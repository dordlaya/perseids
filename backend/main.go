package main

// main.go — bootstrap, sim loop, and graceful shutdown.
//
// Concurrency summary:
//   sim.mu    protects all Sim state; held briefly per tick or per handler call.
//   persistMu serialises roster writes so at most one save is in-flight.
//
// simLoop holds sim.mu only during Tick(), then releases it before publishing
// to the hub and before calling persistNow. HTTP handlers do the same: lock →
// mutate → unlock → persist. No goroutine ever holds both mutexes simultaneously,
// so there is no deadlock risk.
//
// Environment variables (all optional):
//   STORE_BACKEND   "json" (default) | "valkey"
//   VALKEY_URL      redis://… (default: redis://localhost:6379)
//   VALKEY_PREFIX   key prefix in Valkey (default: spacemap)
//   DATA_DIR        directory for roster.json (default: ./data)
//   STATIC_DIR      directory served as static files (default: cwd)
//   BIND            listen address (default: 127.0.0.1; 0.0.0.0 when RENDER is set)
//   PORT            listen port (default: 5173)
//   RENDER          any non-empty value → bind 0.0.0.0 (PaaS convention)
//   HEARTBEAT_TIMEOUT duration before a silent user is marked offline (default: 60m)

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

// persistMu ensures at most one roster write is in-flight at a time.
// It is acquired AFTER sim.mu is released to avoid ABBA deadlocks.
var persistMu sync.Mutex

// persistNow snapshots the dirty roster state (under sim.mu) and writes it to
// the store (without holding sim.mu, so ticking continues uninterrupted).
// Calling this function blocks until the write completes or is skipped (not dirty).
func persistNow(sim *Sim, store Store) {
	persistMu.Lock()
	defer persistMu.Unlock()

	if store.Mode() == "granular" {
		sim.mu.Lock()
		if !sim.dirty {
			sim.mu.Unlock()
			return
		}
		payload := sim.DrainChanges()
		sim.mu.Unlock()

		if err := store.SaveChanges(payload); err != nil {
			log.Printf("warn: valkey save failed: %v; will retry", err)
			sim.mu.Lock()
			sim.RequeueChanges(payload)
			sim.mu.Unlock()
		}
	} else {
		sim.mu.Lock()
		if !sim.dirty {
			sim.mu.Unlock()
			return
		}
		data := sim.RosterBytes()
		sim.dirty = false
		sim.dirtyUsers = make(map[int]bool)
		sim.resetPending = false
		sim.mu.Unlock()

		if err := store.SaveFull(data); err != nil {
			log.Printf("warn: roster save failed: %v; will retry", err)
			sim.mu.Lock()
			sim.dirty = true
			sim.mu.Unlock()
		}
	}
}

// simLoop is the single goroutine that ticks the simulation at tickHz and
// broadcasts each snapshot to the hub. It autosaves every saveEvery seconds
// when the roster is dirty. Context cancellation exits the loop cleanly.
func simLoop(ctx context.Context, sim *Sim, hub *Hub, store Store) {
	step := time.Second / tickHz
	last := time.Now()
	var saveAccum float64
	tickI := 0
	lastSentRev := -1

	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		start := time.Now()
		dt := start.Sub(last).Seconds()
		last = start
		if dt > 0.05 { // clamp runaway dt (e.g. first tick after sleep)
			dt = 0.05
		}

		tickI++
		sim.mu.Lock()
		// Broadcast the full users array every Nth tick, or immediately when
		// the roster changes (join/login/reset bump sim.rev).
		includeUsers := (tickI%userBroadcastEvery == 0) || (sim.rev != lastSentRev)
		snap, rev := sim.Tick(dt, includeUsers)
		if includeUsers {
			lastSentRev = rev
		}
		isDirty := sim.dirty
		sim.mu.Unlock()

		// Marshal outside the lock — snap contains fresh copies, no shared state.
		if data, err := json.Marshal(snap); err == nil {
			hub.Publish(string(data))
		}

		saveAccum += dt
		if saveAccum >= saveEvery {
			if isDirty {
				// Run in a goroutine so the tick cadence isn't blocked by I/O.
				// persistMu ensures only one save runs at a time.
				go persistNow(sim, store)
			}
			saveAccum = 0
		}

		if sleep := step - time.Since(start); sleep > 0 {
			time.Sleep(sleep)
		}
	}
}

// envOr returns the env var value or fallback if the var is empty/unset.
func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	// ---- Config ----
	wd, _ := os.Getwd()

	dataDir := envOr("DATA_DIR", filepath.Join(wd, "data"))
	rosterPath := filepath.Join(dataDir, "roster.json")

	defaultBind := "127.0.0.1"
	if os.Getenv("RENDER") != "" {
		defaultBind = "0.0.0.0"
	}
	host := envOr("BIND", defaultBind)
	port := envOr("PORT", "5173")

	storeBackend := strings.TrimSpace(strings.ToLower(envOr("STORE_BACKEND", "json")))
	valkeyURL := envOr("VALKEY_URL", "redis://localhost:6379")
	valkeyPrefix := envOr("VALKEY_PREFIX", "spacemap")
	staticDir := envOr("STATIC_DIR", wd)

	// ---- Store ----
	store, err := makeStore(storeBackend, valkeyURL, valkeyPrefix, rosterPath)
	if err != nil {
		log.Fatalf("store init: %v", err)
	}
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		log.Fatalf("data dir: %v", err)
	}

	// ---- Sim ----
	sim, err := NewSim(store)
	if err != nil {
		log.Fatalf("sim init: %v", err)
	}
	sim.heartbeatTimeout = durationOr("HEARTBEAT_TIMEOUT", time.Hour)

	// ---- Hub ----
	hub := NewHub()

	// ---- Routes (Go 1.22 method+path patterns) ----
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/health", handleHealth(sim, store))
	mux.HandleFunc("GET /api/state", handleState(sim))
	mux.HandleFunc("GET /api/sectors", handleSectors(sim))
	mux.HandleFunc("POST /api/register", handleRegister(sim, store))
	mux.HandleFunc("POST /api/login", handleLogin(sim, store))
	mux.HandleFunc("POST /api/status", handleStatus(sim, store))
	mux.HandleFunc("POST /api/heartbeat", handleHeartbeat(sim))
	mux.HandleFunc("POST /api/boost", handleBoost(sim))
	mux.HandleFunc("POST /api/jam", handleJam(sim))
	mux.HandleFunc("POST /api/move", handleMove(sim, store))
	mux.HandleFunc("POST /api/reset", handleReset(sim, store))
	mux.HandleFunc("GET /ws", handleWebSocket(sim, hub))
	// Static files are last; /api and /ws take precedence automatically.
	mux.Handle("/", http.FileServer(http.Dir(staticDir)))

	handler := corsMiddleware(noCacheMiddleware(mux))

	// ---- HTTP server ----
	addr := host + ":" + port
	srv := &http.Server{
		Addr:              addr,
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
	}

	// ---- Sim loop ----
	ctx, cancel := context.WithCancel(context.Background())
	go simLoop(ctx, sim, hub, store)

	fmt.Printf("perseids (Go/WS) http://%s  (tick %dHz, store: %s)\n",
		addr, tickHz, store.Describe())

	// ---- Graceful shutdown ----
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigCh
		cancel() // stop sim loop
		shutCtx, shutCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer shutCancel()
		_ = srv.Shutdown(shutCtx)
	}()

	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("listen: %v", err)
	}

	// Best-effort final save on clean shutdown so a graceful stop doesn't
	// lose the last few seconds of roster changes.
	sim.mu.Lock()
	dirty := sim.dirty
	sim.mu.Unlock()
	if dirty {
		persistNow(sim, store)
	}
}

func durationOr(key string, fallback time.Duration) time.Duration {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		duration, err := time.ParseDuration(value)
		if err != nil || duration <= 0 {
			log.Printf("warn: invalid %s=%q; using %s", key, value, fallback)
			return fallback
		}
		return duration
	}
	return fallback
}

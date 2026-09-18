package main

// handlers.go — HTTP handlers, WS endpoint, and middleware.
//
// Every mutating handler acquires s.mu, performs the mutation, releases it,
// and then (if needed) calls persistNow synchronously before writing the JSON
// response — matching the Python server's "await persist_now()" contract that
// ensures data is durable before the client is told "ok".
//
// The WebSocket handler spawns a dedicated sender goroutine and runs the
// receiver loop in the handler goroutine. Disconnect triggers context
// cancellation which unblocks the sender cleanly.

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

// ---------------------------------------------------------------------------
// WebSocket upgrader
// ---------------------------------------------------------------------------

var wsUpgrader = websocket.Upgrader{
	CheckOrigin:     func(_ *http.Request) bool { return true },
	ReadBufferSize:  1024,
	WriteBufferSize: 4096,
}

// ---------------------------------------------------------------------------
// Request types
// ---------------------------------------------------------------------------

type RegisterReq struct {
	Name     string `json:"name"`
	Email    string `json:"email"`
	Password string `json:"password"`
}

type LoginReq struct {
	Identifier string `json:"identifier"` // email OR username
	Password   string `json:"password"`
}

type StatusReq struct {
	ID    int  `json:"id"`
	Value bool `json:"value"`
}

type HeartbeatReq struct {
	ID int `json:"id"`
}

type BoostReq struct {
	ID int `json:"id"`
}

type JamReq struct {
	Attacker int `json:"attacker"`
	Target   int `json:"target"`
}

type MoveReq struct {
	ID     int `json:"id"`
	Sector int `json:"sector"`
}

// ---------------------------------------------------------------------------
// Middleware
// ---------------------------------------------------------------------------

// corsMiddleware adds CORS headers and handles pre-flight OPTIONS requests.
func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS, PUT, DELETE")
		w.Header().Set("Access-Control-Allow-Headers",
			"Accept, Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// noCacheMiddleware sets Cache-Control: no-cache on HTML/JS/CSS so browsers
// always revalidate and pick up a redeployed frontend immediately.
func noCacheMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := r.URL.Path
		if p == "/" || strings.HasSuffix(p, ".html") ||
			strings.HasSuffix(p, ".js") || strings.HasSuffix(p, ".css") {
			w.Header().Set("Cache-Control", "no-cache")
		}
		next.ServeHTTP(w, r)
	})
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func decodeBody(w http.ResponseWriter, r *http.Request, dst any) bool {
	if err := json.NewDecoder(r.Body).Decode(dst); err != nil {
		writeJSON(w, http.StatusBadRequest,
			map[string]any{"ok": false, "error": "bad_request"})
		return false
	}
	return true
}

// ---------------------------------------------------------------------------
// API handlers
// ---------------------------------------------------------------------------

func handleHealth(sim *Sim, store Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sim.mu.Lock()
		users, probes, rev := len(sim.users), len(sim.probes), sim.rev
		sim.mu.Unlock()
		writeJSON(w, http.StatusOK, map[string]any{
			"ok": true, "users": users, "probes": probes,
			"rev": rev, "store": store.Kind(),
		})
	}
}

func handleState(sim *Sim) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sim.mu.Lock()
		snap := sim.snapshot(true)
		sim.mu.Unlock()
		writeJSON(w, http.StatusOK, snap)
	}
}

func handleSectors(sim *Sim) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sim.mu.Lock()
		sectors := sim.sectors()
		sim.mu.Unlock()
		writeJSON(w, http.StatusOK, sectors)
	}
}

func handleRegister(sim *Sim, store Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req RegisterReq
		if !decodeBody(w, r, &req) {
			return
		}
		sim.mu.Lock()
		res := sim.Register(req.Name, req.Email, req.Password)
		sim.mu.Unlock()
		if res.OK {
			persistNow(sim, store)
		}
		status := http.StatusOK
		if !res.OK {
			status = http.StatusBadRequest
		}
		writeJSON(w, status, res)
	}
}

func handleLogin(sim *Sim, store Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req LoginReq
		if !decodeBody(w, r, &req) {
			return
		}
		sim.mu.Lock()
		res := sim.Authenticate(req.Identifier, req.Password)
		sim.mu.Unlock()
		if res.OK {
			persistNow(sim, store)
		}
		status := http.StatusOK
		if !res.OK {
			status = http.StatusUnauthorized
		}
		writeJSON(w, status, res)
	}
}

func handleStatus(sim *Sim, store Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req StatusReq
		if !decodeBody(w, r, &req) {
			return
		}
		sim.mu.Lock()
		res := sim.SetLoggedIn(req.ID, req.Value)
		sim.mu.Unlock()
		if res.OK {
			persistNow(sim, store)
		}
		status := http.StatusOK
		if !res.OK {
			status = http.StatusNotFound
		}
		writeJSON(w, status, res)
	}
}

func handleHeartbeat(sim *Sim) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req HeartbeatReq
		if !decodeBody(w, r, &req) {
			return
		}
		sim.mu.Lock()
		res := sim.Heartbeat(req.ID)
		sim.mu.Unlock()
		status := http.StatusOK
		if !res.OK {
			status = http.StatusConflict
			if res.Error == "not_found" {
				status = http.StatusNotFound
			}
		}
		writeJSON(w, status, res)
	}
}

func handleBoost(sim *Sim) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req BoostReq
		if !decodeBody(w, r, &req) {
			return
		}
		sim.mu.Lock()
		res := sim.ActivateBoost(req.ID)
		sim.mu.Unlock()
		status := http.StatusOK
		if !res.OK {
			status = http.StatusConflict
		}
		writeJSON(w, status, res)
	}
}

func handleJam(sim *Sim) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req JamReq
		if !decodeBody(w, r, &req) {
			return
		}

		sim.mu.Lock()
		res := sim.Jam(req.Attacker, req.Target)
		sim.mu.Unlock()
		status := http.StatusOK
		if !res.OK {
			status = http.StatusConflict
		}
		writeJSON(w, status, res)
	}
}

func handleMove(sim *Sim, store Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req MoveReq
		if !decodeBody(w, r, &req) {
			return
		}
		sim.mu.Lock()
		res := sim.MoveUser(req.ID, req.Sector)
		sim.mu.Unlock()
		if res.OK {
			persistNow(sim, store)
		}
		status := http.StatusOK
		if !res.OK {
			status = http.StatusConflict
			if res.Error == "not_found" || res.Error == "invalid_sector" {
				status = http.StatusBadRequest
			}
		}
		writeJSON(w, status, res)
	}
}

func handleReset(sim *Sim, store Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sim.mu.Lock()
		res := sim.Reset()
		sim.mu.Unlock()
		persistNow(sim, store)
		writeJSON(w, http.StatusOK, res)
	}
}

// ---------------------------------------------------------------------------
// WebSocket handler
// ---------------------------------------------------------------------------

func handleWebSocket(sim *Sim, hub *Hub) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		conn, err := wsUpgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Printf("ws upgrade: %v", err)
			return
		}
		defer conn.Close()

		// Capture the hub seq BEFORE the initial snapshot so we never miss a
		// concurrent publish that arrives between snapshot and starting the loop.
		lastSeq := hub.Seq()

		// Send a full snapshot immediately so the client has users/world even
		// if it connects during a probes-only broadcast tick.
		sim.mu.Lock()
		initSnap := sim.snapshot(true)
		sim.mu.Unlock()
		if data, err2 := json.Marshal(initSnap); err2 == nil {
			_ = conn.WriteMessage(websocket.TextMessage, data)
		}

		ctx, cancel := context.WithCancel(r.Context())
		defer cancel()

		sendDone := make(chan struct{})

		// Sender goroutine: waits for hub snapshots and writes them to the WS.
		go func() {
			defer close(sendDone)
			for {
				seq, data := hub.WaitCtx(ctx, lastSeq, 15*time.Second)
				if ctx.Err() != nil {
					return
				}
				lastSeq = seq
				if data == "" {
					continue // timeout heartbeat — ReadMessage handles WS pings
				}
				conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
				if err := conn.WriteMessage(websocket.TextMessage, []byte(data)); err != nil {
					return
				}
			}
		}()

		// Drain incoming messages; returns on any error (i.e. client disconnect).
		for {
			if _, _, err := conn.ReadMessage(); err != nil {
				break
			}
		}
		cancel()   // signal the sender to exit
		<-sendDone // wait for the sender to finish
	}
}

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
	"crypto/subtle"
	"encoding/json"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
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

// authResponse wraps a register/login result with the session token the
// client must send back as "Authorization: Bearer <token>" on every
// subsequent request.
type authResponse struct {
	OK    bool   `json:"ok"`
	Error string `json:"error,omitempty"`
	ID    int    `json:"id,omitempty"`
	Name  string `json:"name,omitempty"`
	Token string `json:"token,omitempty"`
}

// None of the request types below carry a user ID. The acting user is
// always the one resolved from the bearer token by requireAuth — never a
// value the client supplies — which is what stops one player from
// puppeting another player's probe.
type StatusReq struct {
	Value bool `json:"value"`
}

type JamReq struct {
	Target int `json:"target"`
}

type MoveReq struct {
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
// Auth middleware
// ---------------------------------------------------------------------------

type ctxKey int

const userIDKey ctxKey = 0

// requireAuth resolves the bearer token to a user ID and stores it on the
// request context for the handler to read via userIDFromContext. Requests
// with a missing, unknown, or expired token never reach the handler.
func requireAuth(sessions *SessionStore) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			uid, ok := sessions.Lookup(bearerToken(r))
			if !ok {
				writeJSON(w, http.StatusUnauthorized,
					map[string]any{"ok": false, "error": "unauthorized"})
				return
			}
			ctx := context.WithValue(r.Context(), userIDKey, uid)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// userIDFromContext reads the user ID that requireAuth resolved. Only call
// this from handlers mounted behind requireAuth.
func userIDFromContext(r *http.Request) int {
	uid, _ := r.Context().Value(userIDKey).(int)
	return uid
}

// requireAdmin protects operator-only endpoints (currently just /api/reset)
// behind a shared secret set via the ADMIN_TOKEN env var, sent the same way
// as a session token: "Authorization: Bearer <ADMIN_TOKEN>". If ADMIN_TOKEN
// isn't set, the endpoint is disabled rather than left open — a safer
// default for a small game server that's easy to deploy without configuring.
func requireAdmin(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		want := os.Getenv("ADMIN_TOKEN")
		if want == "" {
			writeJSON(w, http.StatusForbidden, map[string]any{"ok": false, "error": "disabled"})
			return
		}
		got := bearerToken(r)
		if subtle.ConstantTimeCompare([]byte(got), []byte(want)) != 1 {
			writeJSON(w, http.StatusUnauthorized, map[string]any{"ok": false, "error": "unauthorized"})
			return
		}
		next.ServeHTTP(w, r)
	})
}

// ---------------------------------------------------------------------------
// Login/register rate limiting
// ---------------------------------------------------------------------------

// rateLimiter is a minimal fixed-window limiter keyed by client IP: at most
// `max` calls per `window`. Enough to blunt casual credential-stuffing and
// account-enumeration against /api/login and /api/register without pulling
// in a dependency or needing shared state across instances (this server is
// single-instance in-memory already, so that's not a new constraint).
type rateLimiter struct {
	mu       sync.Mutex
	max      int
	window   time.Duration
	attempts map[string][]time.Time
}

func newRateLimiter(max int, window time.Duration) *rateLimiter {
	return &rateLimiter{max: max, window: window, attempts: make(map[string][]time.Time)}
}

func (rl *rateLimiter) allow(key string) bool {
	now := time.Now()
	cutoff := now.Add(-rl.window)
	rl.mu.Lock()
	defer rl.mu.Unlock()
	var kept []time.Time
	for _, t := range rl.attempts[key] {
		if t.After(cutoff) {
			kept = append(kept, t)
		}
	}
	if len(kept) >= rl.max {
		rl.attempts[key] = kept
		return false
	}
	rl.attempts[key] = append(kept, now)
	return true
}

// clientIP prefers the first X-Forwarded-For hop (set by most PaaS proxies,
// including Render) and falls back to the raw remote address.
func clientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		return strings.TrimSpace(strings.SplitN(xff, ",", 2)[0])
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func rateLimitMiddleware(rl *rateLimiter, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !rl.allow(clientIP(r)) {
			writeJSON(w, http.StatusTooManyRequests,
				map[string]any{"ok": false, "error": "rate_limited"})
			return
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

func handleRegister(sim *Sim, store Store, sessions *SessionStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req RegisterReq
		if !decodeBody(w, r, &req) {
			return
		}
		sim.mu.Lock()
		res := sim.Register(req.Name, req.Email, req.Password)
		sim.mu.Unlock()
		if !res.OK {
			writeJSON(w, http.StatusBadRequest, authResponse{Error: res.Error})
			return
		}
		persistNow(sim, store)
		token, err := sessions.Create(res.ID)
		if err != nil {
			log.Printf("session create: %v", err)
			writeJSON(w, http.StatusInternalServerError, authResponse{Error: "internal"})
			return
		}
		writeJSON(w, http.StatusOK,
			authResponse{OK: true, ID: res.ID, Name: res.Name, Token: token})
	}
}

func handleLogin(sim *Sim, store Store, sessions *SessionStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req LoginReq
		if !decodeBody(w, r, &req) {
			return
		}
		sim.mu.Lock()
		res := sim.Authenticate(req.Identifier, req.Password)
		sim.mu.Unlock()
		if !res.OK {
			writeJSON(w, http.StatusUnauthorized, authResponse{Error: res.Error})
			return
		}
		persistNow(sim, store)
		token, err := sessions.Create(res.ID)
		if err != nil {
			log.Printf("session create: %v", err)
			writeJSON(w, http.StatusInternalServerError, authResponse{Error: "internal"})
			return
		}
		writeJSON(w, http.StatusOK,
			authResponse{OK: true, ID: res.ID, Name: res.Name, Token: token})
	}
}

// handleLogout revokes the caller's session token and marks them offline.
// Mounted behind requireAuth, so uid/token are already verified.
func handleLogout(sim *Sim, store Store, sessions *SessionStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid := userIDFromContext(r)
		sessions.Delete(bearerToken(r))
		sim.mu.Lock()
		res := sim.SetLoggedIn(uid, false)
		sim.mu.Unlock()
		if res.OK {
			persistNow(sim, store)
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	}
}

// handleStatus toggles the CALLER's own online/offline flag. Mounted behind
// requireAuth; the target user is always the token's owner.
func handleStatus(sim *Sim, store Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req StatusReq
		if !decodeBody(w, r, &req) {
			return
		}
		uid := userIDFromContext(r)
		sim.mu.Lock()
		res := sim.SetLoggedIn(uid, req.Value)
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
		uid := userIDFromContext(r)
		sim.mu.Lock()
		res := sim.Heartbeat(uid)
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
		uid := userIDFromContext(r)
		sim.mu.Lock()
		res := sim.ActivateBoost(uid)
		sim.mu.Unlock()
		status := http.StatusOK
		if !res.OK {
			status = http.StatusConflict
		}
		writeJSON(w, status, res)
	}
}

// handleJam: the attacker is always the authenticated caller, never a
// client-supplied field — only the target is provided by the client.
func handleJam(sim *Sim) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req JamReq
		if !decodeBody(w, r, &req) {
			return
		}
		attacker := userIDFromContext(r)
		sim.mu.Lock()
		res := sim.Jam(attacker, req.Target)
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
		uid := userIDFromContext(r)
		sim.mu.Lock()
		res := sim.MoveUser(uid, req.Sector)
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

package main

// security_origins.go centralizes browser-origin policy for HTTP CORS and WebSockets.

import (
	"net/http"
	"os"
	"strings"
)

func configuredOrigins() []string {
	raw := strings.TrimSpace(os.Getenv("ALLOWED_ORIGINS"))
	if raw == "" {
		return nil
	}
	parts := strings.Split(raw, ",")
	origins := make([]string, 0, len(parts))
	for _, part := range parts {
		origin := strings.TrimRight(strings.TrimSpace(part), "/")
		if origin != "" {
			origins = append(origins, origin)
		}
	}
	return origins
}

func originAllowed(origin string, allowed []string) bool {
	if origin == "" {
		return true // non-browser clients do not send Origin
	}
	if len(allowed) == 0 {
		return true // backwards-compatible wildcard fallback
	}
	for _, candidate := range allowed {
		if origin == candidate {
			return true
		}
	}
	return false
}

// secureCORSMiddleware preserves the existing wildcard fallback when
// ALLOWED_ORIGINS is unset, and otherwise reflects only an explicitly allowed
// browser origin. Disallowed browser preflights are rejected before routing.
func secureCORSMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		allowed := configuredOrigins()
		origin := r.Header.Get("Origin")
		if origin != "" && !originAllowed(origin, allowed) {
			if r.Method == http.MethodOptions {
				writeJSON(w, http.StatusForbidden, map[string]any{"ok": false, "error": "origin_not_allowed"})
				return
			}
			w.Header().Del("Access-Control-Allow-Origin")
			next.ServeHTTP(w, r)
			return
		}

		if origin != "" && len(allowed) > 0 {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
		} else if len(allowed) == 0 {
			w.Header().Set("Access-Control-Allow-Origin", "*")
		}
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS, PUT, DELETE")
		w.Header().Set("Access-Control-Allow-Headers", "Accept, Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func init() {
	// Apply the same origin policy to WebSocket handshakes.
	wsUpgrader.CheckOrigin = func(r *http.Request) bool {
		return originAllowed(r.Header.Get("Origin"), configuredOrigins())
	}
}

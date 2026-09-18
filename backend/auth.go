package main

// auth.go — email validation and PBKDF2-HMAC-SHA256 password hashing.
//
// The wire format is deliberately identical to the Python server so existing
// roster.json files can be loaded by either implementation:
//   pbkdf2_sha256$<iters>$<salt_hex>$<hash_hex>

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/pbkdf2"
)

const (
	pwMinLen    = 4
	pbkdf2Iters = 120_000

	// sessionTTL is how long a login token stays valid without being renewed.
	// Every authenticated request that resolves a valid token refreshes it
	// (see SessionStore.Lookup), so an active user is never logged out from
	// under them — only idle tokens expire.
	sessionTTL = 24 * time.Hour
)

var emailRE = regexp.MustCompile(`^[^@\s]+@[^@\s]+\.[^@\s]+$`)

func validEmail(email string) bool {
	return emailRE.MatchString(strings.TrimSpace(email))
}

// hashPassword returns a salted PBKDF2-HMAC-SHA256 token.
func hashPassword(password string) string {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		panic("crypto/rand: " + err.Error())
	}
	dk := pbkdf2.Key([]byte(password), salt, pbkdf2Iters, 32, sha256.New)
	return fmt.Sprintf("pbkdf2_sha256$%d$%s$%s",
		pbkdf2Iters, hex.EncodeToString(salt), hex.EncodeToString(dk))
}

// verifyPassword returns true iff password matches the stored token.
func verifyPassword(password, encoded string) bool {
	parts := strings.SplitN(encoded, "$", 4)
	if len(parts) != 4 || parts[0] != "pbkdf2_sha256" {
		return false
	}
	var iters int
	if _, err := fmt.Sscanf(parts[1], "%d", &iters); err != nil || iters <= 0 {
		return false
	}
	salt, err := hex.DecodeString(parts[2])
	if err != nil {
		return false
	}
	want, err := hex.DecodeString(parts[3])
	if err != nil {
		return false
	}
	got := pbkdf2.Key([]byte(password), salt, iters, 32, sha256.New)
	return subtle.ConstantTimeCompare(got, want) == 1
}

// ---------------------------------------------------------------------------
// Session tokens
//
// Opaque bearer tokens, held server-side only (never JWTs — there's nothing
// here a client needs to decode, and an in-memory map lets us revoke a
// token instantly on logout, which a self-contained signed token can't do
// without an extra denylist anyway).
//
// A token is handed to the client once, at register/login time, and must be
// sent back as "Authorization: Bearer <token>" on every request that acts on
// behalf of a specific user. Handlers must NOT trust a user id supplied in
// the request body — only the id resolved from the token via requireAuth.
// ---------------------------------------------------------------------------

type sessionEntry struct {
	userID    int
	expiresAt time.Time
}

// SessionStore maps bearer tokens to user IDs. Safe for concurrent use; it
// has its own mutex, deliberately separate from Sim.mu, so a session lookup
// never has to wait on (or block) the world-state lock.
type SessionStore struct {
	mu     sync.RWMutex
	tokens map[string]sessionEntry
}

func NewSessionStore() *SessionStore {
	return &SessionStore{tokens: make(map[string]sessionEntry)}
}

// generateToken returns a 256-bit random token, base64url-encoded.
func generateToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

// Create mints a fresh token for uid and stores it.
func (s *SessionStore) Create(uid int) (string, error) {
	token, err := generateToken()
	if err != nil {
		return "", err
	}
	s.mu.Lock()
	s.tokens[token] = sessionEntry{userID: uid, expiresAt: time.Now().Add(sessionTTL)}
	s.mu.Unlock()
	return token, nil
}

// Lookup resolves a token to a user ID. A valid lookup slides the
// expiry forward so active sessions don't die mid-use.
func (s *SessionStore) Lookup(token string) (int, bool) {
	if token == "" {
		return 0, false
	}
	s.mu.RLock()
	entry, ok := s.tokens[token]
	s.mu.RUnlock()
	if !ok {
		return 0, false
	}
	if time.Now().After(entry.expiresAt) {
		s.Delete(token)
		return 0, false
	}
	entry.expiresAt = time.Now().Add(sessionTTL)
	s.mu.Lock()
	s.tokens[token] = entry
	s.mu.Unlock()
	return entry.userID, true
}

// Delete revokes a single token (logout).
func (s *SessionStore) Delete(token string) {
	s.mu.Lock()
	delete(s.tokens, token)
	s.mu.Unlock()
}

// bearerToken extracts the token from "Authorization: Bearer <token>".
func bearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	const prefix = "Bearer "
	if !strings.HasPrefix(h, prefix) {
		return ""
	}
	return strings.TrimSpace(strings.TrimPrefix(h, prefix))
}

package main

// store.go — pluggable persistence backends.
//
// The Store interface abstracts two backends:
//   json   — atomic whole-file write to $DATA_DIR/roster.json (default).
//   valkey — per-user HASH in a Valkey/Redis server; only changed users are
//            written on each save (granular dirty tracking).
//
// Both backends are safe to call from a goroutine without holding sim.mu
// because they always receive immutable copies of the data.

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
)

// ---------------------------------------------------------------------------
// Shared data types
// ---------------------------------------------------------------------------

// UserRecord is the persisted subset of a User (no live/transient fields).
type UserRecord struct {
	ID           int     `json:"id"`
	Name         string  `json:"name"`
	Fx           float64 `json:"fx"`
	Fy           float64 `json:"fy"`
	Sector       int     `json:"sector,omitempty"`
	R            float64 `json:"r"`
	Hits         int     `json:"hits"`
	CreatedAt    int64   `json:"createdAt"`
	LoggedIn     bool    `json:"loggedIn"`
	GravityUntil int64   `json:"gravityUntil,omitempty"`
	MoveReadyAt  int64   `json:"moveReadyAt,omitempty"`
	Email        string  `json:"email"`
	Pw           string  `json:"pw"`
}

// RosterSnapshot is what Load() returns — rev counter, optional seq counter
// (Valkey only), and the ordered user list.
type RosterSnapshot struct {
	Rev   int          `json:"rev"`
	Seq   int          `json:"seq,omitempty"` // populated by Valkey, 0 for JSON
	Users []UserRecord `json:"users"`
}

// ChangePayload carries only the users that changed since the last save.
type ChangePayload struct {
	Rev   int
	Seq   int
	Reset bool
	Users []UserRecord
}

// ---------------------------------------------------------------------------
// Store interface
// ---------------------------------------------------------------------------

// Store is the persistence seam.  Implementations must be safe to call from
// a goroutine that does NOT hold sim.mu (they receive immutable data copies).
type Store interface {
	Kind() string     // "json" | "valkey"
	Mode() string     // "full" | "granular"
	Describe() string // human-readable connection info for the startup banner
	Load() (*RosterSnapshot, error)
	SaveFull(data []byte) error        // used by JsonStore
	SaveChanges(p ChangePayload) error // used by ValkeyStore
}

// ---------------------------------------------------------------------------
// JSON store
// ---------------------------------------------------------------------------

// JsonStore writes the entire roster as a pretty-printed JSON file.
// Writes are atomic (write to .tmp, then os.Rename).
type JsonStore struct{ path string }

func NewJsonStore(path string) *JsonStore { return &JsonStore{path: path} }

func (s *JsonStore) Kind() string     { return "json" }
func (s *JsonStore) Mode() string     { return "full" }
func (s *JsonStore) Describe() string { return "json:" + s.path }

func (s *JsonStore) Load() (*RosterSnapshot, error) {
	data, err := os.ReadFile(s.path)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var snap RosterSnapshot
	if err := json.Unmarshal(data, &snap); err != nil {
		return nil, err
	}
	return &snap, nil
}

func (s *JsonStore) SaveFull(data []byte) error {
	if err := os.MkdirAll(filepath.Dir(s.path), 0o755); err != nil {
		return err
	}
	tmp := s.path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	// Retry os.Rename on Windows where AV/indexers can briefly lock the target.
	var lastErr error
	for i := 0; i < 6; i++ {
		if err := os.Rename(tmp, s.path); err == nil {
			return nil
		} else {
			lastErr = err
			time.Sleep(20 * time.Millisecond)
		}
	}
	return fmt.Errorf("roster rename: %w", lastErr)
}

func (s *JsonStore) SaveChanges(_ ChangePayload) error {
	return fmt.Errorf("json store does not support granular saves")
}

// ---------------------------------------------------------------------------
// Valkey store
// ---------------------------------------------------------------------------

// ValkeyStore uses a Valkey (Redis-compatible) server.
//
// Key layout (all under VALKEY_PREFIX):
//
//	{prefix}:user:{id}   HASH   one per user
//	{prefix}:order       LIST   user ids in insertion order
//	{prefix}:rev         STRING roster revision counter
//	{prefix}:seq         STRING last minted user-id
//
// Only changed users are written per save (dirty tracking lives in Sim).
type ValkeyStore struct {
	client *redis.Client
	prefix string
	url    string
	known  map[int]bool // ids already appended to the order LIST
}

func NewValkeyStore(url, prefix string) (*ValkeyStore, error) {
	opts, err := redis.ParseURL(url)
	if err != nil {
		return nil, fmt.Errorf("valkey: invalid URL %q: %w", url, err)
	}
	opts.DialTimeout = 3 * time.Second
	opts.ReadTimeout = 3 * time.Second
	opts.WriteTimeout = 3 * time.Second
	return &ValkeyStore{
		client: redis.NewClient(opts),
		prefix: prefix,
		url:    url,
		known:  make(map[int]bool),
	}, nil
}

func (s *ValkeyStore) Kind() string     { return "valkey" }
func (s *ValkeyStore) Mode() string     { return "granular" }
func (s *ValkeyStore) Describe() string { return fmt.Sprintf("valkey:%s prefix=%s", s.url, s.prefix) }

func (s *ValkeyStore) k(parts ...string) string {
	return s.prefix + ":" + strings.Join(parts, ":")
}

func (s *ValkeyStore) Load() (*RosterSnapshot, error) {
	ctx := context.Background()
	order, err := s.client.LRange(ctx, s.k("order"), 0, -1).Result()
	if err != nil {
		log.Printf("warn: valkey load failed (%v); starting with empty roster", err)
		return nil, nil // non-fatal: start empty
	}
	revStr, _ := s.client.Get(ctx, s.k("rev")).Result()
	seqStr, _ := s.client.Get(ctx, s.k("seq")).Result()

	snap := &RosterSnapshot{}
	snap.Rev, _ = strconv.Atoi(revStr)
	snap.Seq, _ = strconv.Atoi(seqStr)

	if len(order) > 0 {
		pipe := s.client.Pipeline()
		cmds := make([]*redis.MapStringStringCmd, len(order))
		for i, uid := range order {
			cmds[i] = pipe.HGetAll(ctx, s.k("user", uid))
		}
		if _, err := pipe.Exec(ctx); err != nil && err != redis.Nil {
			return nil, fmt.Errorf("valkey pipeline: %w", err)
		}
		for i, uid := range order {
			h, err := cmds[i].Result()
			if err != nil || len(h) == 0 {
				continue
			}
			id, _ := strconv.Atoi(uid)
			r, _ := strconv.ParseFloat(h["r"], 64)
			fx, _ := strconv.ParseFloat(h["fx"], 64)
			fy, _ := strconv.ParseFloat(h["fy"], 64)
			hits, _ := strconv.Atoi(h["hits"])
			ca, _ := strconv.ParseInt(h["createdAt"], 10, 64)
			snap.Users = append(snap.Users, UserRecord{
				ID: id, Name: h["name"], Fx: fx, Fy: fy,
				Sector:       atoiDefault(h["sector"]),
				GravityUntil: int64Default(h["gravityUntil"]),
				MoveReadyAt:  int64Default(h["moveReadyAt"]), R: r,
				Hits: hits, CreatedAt: ca, LoggedIn: h["loggedIn"] == "1",
				Email: h["email"], Pw: h["pw"],
			})
			s.known[id] = true
		}
	}
	return snap, nil
}

func (s *ValkeyStore) SaveFull(_ []byte) error {
	return fmt.Errorf("valkey store does not support full saves")
}

func (s *ValkeyStore) SaveChanges(p ChangePayload) error {
	ctx := context.Background()
	if p.Reset {
		s.clear(ctx)
		s.known = make(map[int]bool)
	}
	pipe := s.client.Pipeline()
	for _, rec := range p.Users {
		uid := rec.ID
		li := "0"
		if rec.LoggedIn {
			li = "1"
		}
		pipe.HSet(ctx, s.k("user", strconv.Itoa(uid)), map[string]any{
			"name": rec.Name, "fx": strconv.FormatFloat(rec.Fx, 'g', -1, 64),
			"fy":     strconv.FormatFloat(rec.Fy, 'g', -1, 64),
			"sector": rec.Sector, "gravityUntil": rec.GravityUntil, "moveReadyAt": rec.MoveReadyAt,
			"r":    strconv.FormatFloat(rec.R, 'g', -1, 64),
			"hits": rec.Hits, "createdAt": rec.CreatedAt,
			"loggedIn": li, "email": rec.Email, "pw": rec.Pw,
		})
		if !s.known[uid] {
			pipe.RPush(ctx, s.k("order"), uid)
			s.known[uid] = true
		}

	}
	pipe.Set(ctx, s.k("rev"), p.Rev, 0)
	pipe.Set(ctx, s.k("seq"), p.Seq, 0)
	if _, err := pipe.Exec(ctx); err != nil {
		return fmt.Errorf("valkey save: %w", err)
	}
	return nil
}

func atoiDefault(value string) int {
	n, _ := strconv.Atoi(value)
	return n
}

func int64Default(value string) int64 {
	n, _ := strconv.ParseInt(value, 10, 64)
	return n
}

func (s *ValkeyStore) clear(ctx context.Context) {
	order, _ := s.client.LRange(ctx, s.k("order"), 0, -1).Result()
	pipe := s.client.Pipeline()
	for _, uid := range order {
		pipe.Del(ctx, s.k("user", uid))
	}
	pipe.Del(ctx, s.k("order"), s.k("rev"), s.k("seq"))
	_, _ = pipe.Exec(ctx)
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

func makeStore(backend, valkeyURL, valkeyPrefix, rosterPath string) (Store, error) {
	switch backend {
	case "valkey":
		return NewValkeyStore(valkeyURL, valkeyPrefix)
	default:
		return NewJsonStore(rosterPath), nil
	}
}

package main

// sim.go — the authoritative world simulation.
//
// Concurrency model: all Sim methods that read or mutate state must be called
// with s.mu held by the caller. The sim_loop goroutine is the sole ticker; HTTP
// handlers acquire s.mu for the duration of their mutation, then release it
// before triggering persistence. This mirrors Python's single-event-loop model
// where awaits between coroutines act as cooperative scheduling points.
//
// The spatial grid is rebuilt only when the roster changes (position_users is
// called), so per-tick physics stay O(probes) regardless of user count.

import (
	"encoding/json"
	"fmt"
	"math"
	"math/rand/v2"
	"strings"
	"sync"
	"time"
)

// ---------------------------------------------------------------------------
// Simulation constants (mirror the Python server exactly)
// ---------------------------------------------------------------------------

const (
	tickHz    = 30
	saveEvery = 5.0

	maxSpeed       = 90.0
	wanderStrength = 2.6
	edgeMargin     = 120.0
	edgeForce      = 140.0
	userRadius     = 10.0
	userAttraction = 26.0
	userGrowth     = 2.5
	maxUserRadius  = 46.0
	starMinGap     = 12.0
	pullFade       = 3.0
	probeRadius    = 6.0
	probeRatio     = 0.10
	minProbes      = 10
	maxProbesCap   = 60

	spawnBase = 100.0
	spawnMin  = 0.5
	spawnMax  = 10.0

	sectorSize     = 560.0
	sectorCols     = 3
	sectorPad      = 70.0
	starsPerSector = 10
	pullMin        = 0.05

	basePull        = 0.5
	boostPull       = 1.0
	boostDurationMs = 60_000
	boostCooldownMs = 600_000
	jamReduction    = 0.25
	jamDurationMs   = 60_000
	jamCooldownMs   = 1_800_000
	moveGravityMs   = 30_000
	moveCooldownMs  = 300_000
	sectorCapacity  = 10

	gridCell = 120.0
	// Dynamic user positions are sent at 15 Hz while the simulation continues
	// at 30 Hz. The client interpolates between these snapshots.
	userBroadcastEvery = 2
)

// ---------------------------------------------------------------------------
// Data structures
// ---------------------------------------------------------------------------

// User is a player's live star in the simulation.
type User struct {
	// Persisted
	ID              int
	Name            string
	Fx, Fy          float64 // fractional position within its sector [0,1]
	R               float64 // current radius
	Hits            int
	CreatedAt       int64
	LoggedIn        bool
	Email           string
	Pw              string // hashed password
	LastHeartbeatAt int64  // live presence timestamp; not persisted

	// Live (not persisted)
	PullForce    float64
	Pulse        float64
	X, Y         float64 // world-space position
	Sector       int
	BoostAt      int64
	GravityUntil int64
	MoveReadyAt  int64
	Jams         map[int]int64 // attacker_id → activated_at_ms
	LastJamAt    int64
	LastJamBy    string
}

// expireHeartbeats marks users dark when their client has stopped reporting.
func (s *Sim) expireHeartbeats(now int64) {
	if s.heartbeatTimeout <= 0 {
		return
	}
	timeoutMs := s.heartbeatTimeout.Milliseconds()
	for _, u := range s.users {
		if u.LoggedIn && (u.LastHeartbeatAt == 0 || now-u.LastHeartbeatAt >= timeoutMs) {
			u.LoggedIn = false
			u.LastHeartbeatAt = 0
			u.PullForce = 0
			s.rev++
			s.markDirty(u.ID)
		}
	}
}

// Probe is an ephemeral physics particle that orbits active stars.
type Probe struct {
	ID     int
	X, Y   float64
	Vx, Vy float64
	Wander float64
	Hue    float64
}

// gridKey is the (col, row) cell index in the spatial hash grid.
type gridKey [2]int

// ---------------------------------------------------------------------------
// Snapshot types (wire format sent to clients over WebSocket)
// ---------------------------------------------------------------------------

type ProbeSnap struct {
	ID  int     `json:"id"`
	X   float64 `json:"x"`
	Y   float64 `json:"y"`
	Hue float64 `json:"hue"`
}

type UserSnap struct {
	ID           int     `json:"id"`
	Name         string  `json:"name"`
	X            float64 `json:"x"`
	Y            float64 `json:"y"`
	R            float64 `json:"r"`
	Hits         int     `json:"hits"`
	LoggedIn     bool    `json:"loggedIn"`
	Pull         float64 `json:"pull"`
	Pulse        float64 `json:"pulse"`
	CreatedAt    int64   `json:"createdAt"`
	Sector       int     `json:"sector"`
	BoostAt      int64   `json:"boostAt"`
	GravityUntil int64   `json:"gravityUntil"`
	MoveReadyAt  int64   `json:"moveReadyAt"`
	LastJamAt    int64   `json:"lastJamAt"`
	LastJamBy    string  `json:"lastJamBy"`
}

type WorldSnap struct {
	W float64 `json:"w"`
	H float64 `json:"h"`
}

// Snapshot is what gets broadcast to every WS client each tick.
// Rev/World/Users are nil on probe-only ticks to keep payload small.
type Snapshot struct {
	T             int64       `json:"t"`
	Collisions    int         `json:"collisions"`
	MaxProbes     int         `json:"maxProbes"`
	SpawnInterval float64     `json:"spawnInterval"`
	Probes        []ProbeSnap `json:"probes"`
	Rev           *int        `json:"rev,omitempty"`
	World         *WorldSnap  `json:"world,omitempty"`
	Users         []UserSnap  `json:"users,omitempty"`
}

// ---------------------------------------------------------------------------
// Result types returned by Sim methods to HTTP handlers
// ---------------------------------------------------------------------------

type RegisterResult struct {
	OK    bool   `json:"ok"`
	Error string `json:"error,omitempty"`
	ID    int    `json:"id,omitempty"`
	Name  string `json:"name,omitempty"`
}

type AuthResult struct {
	OK    bool   `json:"ok"`
	Error string `json:"error,omitempty"`
	ID    int    `json:"id,omitempty"`
	Name  string `json:"name,omitempty"`
}

type StatusResult struct {
	OK    bool   `json:"ok"`
	Error string `json:"error,omitempty"`
}

type HeartbeatResult struct {
	OK    bool   `json:"ok"`
	Error string `json:"error,omitempty"`
}

type BoostResult struct {
	OK         bool   `json:"ok"`
	Error      string `json:"error,omitempty"`
	BoostUntil int64  `json:"boostUntil,omitempty"`
	ReadyAt    int64  `json:"readyAt,omitempty"`
}

type JamResult struct {
	OK            bool   `json:"ok"`
	Error         string `json:"error,omitempty"`
	JamUntil      int64  `json:"jamUntil,omitempty"`
	CooldownUntil int64  `json:"cooldownUntil,omitempty"`
}

type ResetResult struct {
	OK bool `json:"ok"`
}

type SectorSnap struct {
	ID        int    `json:"id"`
	Name      string `json:"name"`
	Occupied  int    `json:"occupied"`
	Capacity  int    `json:"capacity"`
	Available bool   `json:"available"`
}

type MoveResult struct {
	OK           bool   `json:"ok"`
	Error        string `json:"error,omitempty"`
	Sector       int    `json:"sector,omitempty"`
	GravityUntil int64  `json:"gravityUntil,omitempty"`
	ReadyAt      int64  `json:"readyAt,omitempty"`
}

// ---------------------------------------------------------------------------
// Sim
// ---------------------------------------------------------------------------

// Sim is the authoritative world state. Every exported method that reads or
// mutates fields must be called with s.mu held by the caller.
type Sim struct {
	mu sync.Mutex

	users      []*User
	probes     []*Probe
	rev        int
	collisions int
	userSeq    int
	probeSeq   int
	spawnTimer float64
	dirty      bool

	dirtyUsers   map[int]bool
	resetPending bool

	grid      map[gridKey][]*User
	gridDirty bool
	gridMaxR  int
	anyActive bool

	store            Store
	heartbeatTimeout time.Duration
}

func nowMs() int64 { return time.Now().UnixMilli() }

// NewSim creates and loads the simulation. Returns an error only if the store
// itself fails; a missing roster is not an error (start fresh).
func NewSim(store Store) (*Sim, error) {
	s := &Sim{
		store:      store,
		dirtyUsers: make(map[int]bool),
		grid:       make(map[gridKey][]*User),
		gridDirty:  true,
		spawnTimer: spawnMax,
	}
	if err := s.load(); err != nil {
		return nil, err
	}
	s.positionUsers()
	s.spawnProbe() // always start with at least one probe
	return s, nil
}

// ---------------------------------------------------------------------------
// Geometry helpers (identical math to the Python server)
// ---------------------------------------------------------------------------

func sectorOrigin(i int) (float64, float64) {
	col, row := i%sectorCols, i/sectorCols
	return float64(col) * sectorSize, float64(row) * sectorSize
}

func (s *Sim) sectorCount() int {
	n := int(math.Ceil(float64(len(s.users)) / sectorCapacity))
	if n < 1 {
		return 1
	}
	for _, u := range s.users {
		if u.Sector+1 > n {
			n = u.Sector + 1
		}
	}
	return n
}

func (s *Sim) worldSize() (float64, float64) {
	n := s.sectorCount()
	cols := n
	if cols > sectorCols {
		cols = sectorCols
	}
	rows := int(math.Ceil(float64(n) / sectorCols))
	return float64(cols) * sectorSize, float64(rows) * sectorSize
}

func (s *Sim) positionUsers() {
	pad := sectorPad
	span := sectorSize - pad*2
	for _, u := range s.users {
		ox, oy := sectorOrigin(u.Sector)
		u.X = ox + pad + u.Fx*span
		u.Y = oy + pad + u.Fy*span
	}
}

var sectorWords = []string{
	"Andromeda", "Cygnus", "Draco", "Eridanus", "Fornax", "Hydra", "Indus", "Lyra",
	"Orion", "Perseus", "Phoenix", "Serpens", "Tucana", "Vela", "Carina", "Pyxis",
}

func (s *Sim) sectorName(id int) string {
	if id < 0 || len(sectorWords) == 0 {
		return fmt.Sprintf("Galaxy %d", id+1)
	}
	base := sectorWords[id%len(sectorWords)]
	tier := id / len(sectorWords)
	if tier > 0 {
		return fmt.Sprintf("%s-%d", base, tier+1)
	}
	return base
}

func (s *Sim) sectorOccupancy(id int) int {
	n := 0
	for _, u := range s.users {
		if u.Sector == id {
			n++
		}
	}
	return n
}

func (s *Sim) sectors() []SectorSnap {
	count := s.sectorCount()
	out := make([]SectorSnap, count)
	for i := range out {
		occupied := s.sectorOccupancy(i)
		out[i] = SectorSnap{
			ID: i, Name: s.sectorName(i), Occupied: occupied,
			Capacity: sectorCapacity, Available: occupied < sectorCapacity,
		}
	}
	return out
}

func (s *Sim) firstAvailableSector() int {
	for _, sector := range s.sectors() {
		if sector.Available {
			return sector.ID
		}
	}
	return s.sectorCount()
}

// placeStarFraction finds a fractional (fx,fy) in the given sector that
// doesn't crowd existing stars (best-of-40-attempts).
func (s *Sim) placeStarFraction(sectorIdx int) (float64, float64) {
	pad := sectorPad
	span := sectorSize - pad*2
	ox, oy := sectorOrigin(sectorIdx)
	want := 2*userRadius + starMinGap

	var others []*User
	for _, u := range s.users {
		if u.Sector == sectorIdx {
			others = append(others, u)
		}
	}
	bestFx, bestFy := rand.Float64(), rand.Float64()
	bestNearest := -1.0

	for try := 0; try < 40; try++ {
		fx, fy := rand.Float64(), rand.Float64()
		x := ox + pad + fx*span
		y := oy + pad + fy*span
		nearest := math.Inf(1)
		for _, o := range others {
			if d := math.Hypot(o.X-x, o.Y-y); d < nearest {
				nearest = d
			}
		}
		if nearest >= want {
			return fx, fy
		}
		if nearest > bestNearest {
			bestNearest = nearest
			bestFx, bestFy = fx, fy
		}
	}
	return bestFx, bestFy
}

// ---------------------------------------------------------------------------
// Spatial grid
// ---------------------------------------------------------------------------

func (s *Sim) rebuildGrid() {
	g := make(map[gridKey][]*User, len(s.users))
	for _, u := range s.users {
		key := gridKey{int(u.X / gridCell), int(u.Y / gridCell)}
		g[key] = append(g[key], u)
	}
	s.grid = g
	s.gridDirty = false
}

func (s *Sim) neighborCells(x, y float64) [][]*User {
	cx, cy := int(x/gridCell), int(y/gridCell)
	var out [][]*User
	for gx := cx - 1; gx <= cx+1; gx++ {
		for gy := cy - 1; gy <= cy+1; gy++ {
			if cell, ok := s.grid[gridKey{gx, gy}]; ok {
				out = append(out, cell)
			}
		}
	}
	return out
}

func (s *Sim) allowedRadius(u *User) float64 {
	cap_ := maxUserRadius
	for _, cell := range s.neighborCells(u.X, u.Y) {
		for _, o := range cell {
			if o == u {
				continue
			}
			if v := math.Hypot(o.X-u.X, o.Y-u.Y) - o.R - starMinGap; v < cap_ {
				cap_ = v
			}
		}
	}
	return cap_
}

// ---------------------------------------------------------------------------
// User construction
// ---------------------------------------------------------------------------

// userFromRecord converts a UserRecord (loaded from disk or freshly built for
// Register) into a live User. When rec.ID == 0 a new id is minted.
func (s *Sim) userFromRecord(rec UserRecord) *User {
	isNew := rec.ID <= 0
	uid := rec.ID
	if isNew {
		s.userSeq++
		uid = s.userSeq
	}
	r := rec.R
	if r <= 0 {
		r = userRadius
	}
	fx, fy := rec.Fx, rec.Fy
	if isNew {
		fx, fy = rand.Float64(), rand.Float64()
	}
	pull := 0.0
	if rec.LoggedIn {
		pull = basePull
	}
	name := rec.Name
	if name == "" {
		name = fmt.Sprintf("User%d", uid)
	}
	ca := rec.CreatedAt
	if ca == 0 {
		ca = nowMs()
	}
	return &User{
		ID: uid, Name: name, Fx: fx, Fy: fy, R: r, Hits: rec.Hits,
		CreatedAt: ca, LoggedIn: rec.LoggedIn,
		Email: strings.TrimSpace(rec.Email), Pw: rec.Pw,
		PullForce: pull, Sector: rec.Sector,
		GravityUntil: rec.GravityUntil, MoveReadyAt: rec.MoveReadyAt,
		Jams: make(map[int]int64),
	}
}

// ---------------------------------------------------------------------------
// World mutations (all called with s.mu held)
// ---------------------------------------------------------------------------

// Register adds a new account and star, enforcing unique name + email.
func (s *Sim) Register(name, email, password string) RegisterResult {
	name = strings.TrimSpace(name)
	email = strings.TrimSpace(email)

	switch {
	case name == "":
		return RegisterResult{Error: "empty"}
	case !validEmail(email):
		return RegisterResult{Error: "bad_email"}
	case len(password) < pwMinLen:
		return RegisterResult{Error: "weak_password"}
	}
	nameLower := strings.ToLower(name)
	emailLower := strings.ToLower(email)
	for _, u := range s.users {
		if strings.ToLower(u.Name) == nameLower {
			return RegisterResult{Error: "name_taken"}
		}
		if strings.ToLower(u.Email) == emailLower {
			return RegisterResult{Error: "email_taken"}
		}
	}
	if len(name) > 16 {
		name = name[:16]
	}
	sector := s.firstAvailableSector()
	u := s.userFromRecord(UserRecord{
		Name: name, Email: email, Pw: hashPassword(password),
		LoggedIn: true, CreatedAt: nowMs(), R: userRadius,
	})
	u.LastHeartbeatAt = nowMs()
	u.Fx, u.Fy = s.placeStarFraction(sector)
	s.users = append(s.users, u)
	s.positionUsers()
	s.gridDirty = true
	s.rev++
	s.markDirty(u.ID)
	return RegisterResult{OK: true, ID: u.ID, Name: u.Name}
}

// Authenticate checks credentials by email OR username, then marks the star online.
func (s *Sim) Authenticate(identifier, password string) AuthResult {
	ident := strings.ToLower(strings.TrimSpace(identifier))
	if ident == "" {
		return AuthResult{Error: "invalid_credentials"}
	}
	var found *User
	for _, u := range s.users {
		if strings.ToLower(u.Name) == ident || strings.ToLower(u.Email) == ident {
			found = u
			break
		}
	}
	if found == nil || !verifyPassword(password, found.Pw) {
		return AuthResult{Error: "invalid_credentials"}
	}
	if !found.LoggedIn {
		found.LoggedIn = true
		s.rev++
		s.markDirty(found.ID)
	}
	found.LastHeartbeatAt = nowMs()
	return AuthResult{OK: true, ID: found.ID, Name: found.Name}
}

// Heartbeat records that a logged-in client is still connected.
func (s *Sim) Heartbeat(uid int) HeartbeatResult {
	for _, u := range s.users {
		if u.ID != uid {
			continue
		}
		if !u.LoggedIn {
			return HeartbeatResult{Error: "offline"}
		}
		u.LastHeartbeatAt = nowMs()
		return HeartbeatResult{OK: true}
	}
	return HeartbeatResult{Error: "not_found"}
}

// SetLoggedIn toggles a star's online/offline state.
func (s *Sim) SetLoggedIn(uid int, value bool) StatusResult {
	for _, u := range s.users {
		if u.ID == uid {
			u.LoggedIn = value
			if value {
				u.LastHeartbeatAt = nowMs()
			} else {
				u.LastHeartbeatAt = 0
				u.PullForce = 0
			}
			s.rev++
			s.markDirty(uid)
			return StatusResult{OK: true}
		}
	}
	return StatusResult{Error: "not_found"}
}

// ---------------------------------------------------------------------------
// Abilities (transient — not persisted)
// ---------------------------------------------------------------------------

// activeJams counts jams currently biting this star, pruning stale entries.
func (s *Sim) activeJams(u *User, now int64) int {
	if len(u.Jams) == 0 {
		return 0
	}
	count := 0
	for aid, at := range u.Jams {
		if now-at >= jamCooldownMs {
			delete(u.Jams, aid)
		} else if now-at < jamDurationMs {
			count++
		}
	}
	return count
}

// pullTarget returns the pull force this star is easing toward.
func (s *Sim) pullTarget(u *User, now int64) float64 {
	if !u.LoggedIn || now < u.GravityUntil {
		return 0.0
	}
	base := basePull
	if u.BoostAt > 0 && now-u.BoostAt < boostDurationMs {
		base = boostPull
	}
	result := base - jamReduction*float64(s.activeJams(u, now))
	if result < 0 {
		return 0.0
	}
	return result
}

// ActivateBoost activates the Heartbeat ability for the given user.
func (s *Sim) ActivateBoost(uid int) BoostResult {
	now := nowMs()
	for _, u := range s.users {
		if u.ID != uid {
			continue
		}
		if !u.LoggedIn {
			return BoostResult{Error: "offline"}
		}
		if now < u.GravityUntil {
			return BoostResult{Error: "in_transit"}
		}
		var readyAt int64
		if u.BoostAt > 0 {
			readyAt = u.BoostAt + boostCooldownMs
		}
		if now < readyAt {
			return BoostResult{Error: "cooldown", ReadyAt: readyAt}
		}
		u.BoostAt = now
		s.rev++
		return BoostResult{
			OK:         true,
			BoostUntil: now + boostDurationMs,
			ReadyAt:    now + boostCooldownMs,
		}
	}
	return BoostResult{Error: "not_found"}
}

// Jam reduces the target's pull for jamDurationMs.
func (s *Sim) Jam(attackerID, targetID int) JamResult {
	if attackerID == targetID {
		return JamResult{Error: "self"}
	}
	now := nowMs()
	var attacker, target *User
	for _, u := range s.users {
		switch u.ID {
		case attackerID:
			attacker = u
		case targetID:
			target = u
		}
	}
	if target == nil {
		return JamResult{Error: "not_found"}
	}
	if !target.LoggedIn {
		return JamResult{Error: "target_offline"}
	}
	if attacker == nil || !attacker.LoggedIn {
		return JamResult{Error: "offline"}
	}
	if now < attacker.GravityUntil {
		return JamResult{Error: "in_transit"}
	}
	if last, ok := target.Jams[attackerID]; ok && now-last < jamCooldownMs {
		return JamResult{Error: "cooldown", CooldownUntil: last + jamCooldownMs}
	}

	target.Jams[attackerID] = now
	target.LastJamAt = now
	target.LastJamBy = attacker.Name
	s.rev++
	return JamResult{
		OK:            true,
		JamUntil:      now + jamDurationMs,
		CooldownUntil: now + jamCooldownMs,
	}
}

func (s *Sim) MoveUser(uid, destination int) MoveResult {
	now := nowMs()
	var user *User
	for _, u := range s.users {
		if u.ID == uid {
			user = u
			break
		}
	}
	if user == nil {
		return MoveResult{Error: "not_found"}
	}
	if !user.LoggedIn {
		return MoveResult{Error: "offline"}
	}
	if destination < 0 || destination >= s.sectorCount() {
		return MoveResult{Error: "invalid_sector"}
	}
	if destination == user.Sector {
		return MoveResult{Error: "already_here"}
	}
	if now < user.MoveReadyAt {
		return MoveResult{Error: "cooldown", ReadyAt: user.MoveReadyAt}
	}
	if s.sectorOccupancy(destination) >= sectorCapacity {
		return MoveResult{Error: "sector_full"}
	}

	user.Sector = destination
	user.Fx, user.Fy = rand.Float64(), rand.Float64()
	user.GravityUntil = now + moveGravityMs
	user.MoveReadyAt = now + moveCooldownMs
	user.BoostAt = 0
	user.PullForce = 0
	s.positionUsers()
	s.gridDirty = true
	s.rev++
	s.markDirty(user.ID)
	return MoveResult{
		OK: true, Sector: destination,
		GravityUntil: user.GravityUntil, ReadyAt: user.MoveReadyAt,
	}
}

// Reset clears all users and probes.
func (s *Sim) Reset() ResetResult {
	s.users = nil
	s.probes = nil
	s.gridDirty = true
	s.rev++
	s.dirtyUsers = make(map[int]bool)
	s.resetPending = true
	s.dirty = true
	return ResetResult{OK: true}
}

func (s *Sim) markDirty(uid int) {
	s.dirtyUsers[uid] = true
	s.dirty = true
}

// ---------------------------------------------------------------------------
// Counts
// ---------------------------------------------------------------------------

func (s *Sim) activeUsers() int {
	n := 0
	for _, u := range s.users {
		if u.LoggedIn {
			n++
		}
	}
	return n
}

func (s *Sim) maxProbes() int {
	return min(maxProbesCap, max(minProbes, int(float64(s.activeUsers())*probeRatio)))
}

func (s *Sim) spawnInterval() float64 {
	active := max(1, s.activeUsers())
	return math.Max(spawnMin, math.Min(spawnMax, spawnBase/float64(active)))
}

// ---------------------------------------------------------------------------
// Physics
// ---------------------------------------------------------------------------

func (s *Sim) spawnProbe() {
	if len(s.probes) >= s.maxProbes() {
		return
	}
	bw, bh := s.worldSize()
	m := edgeMargin
	angle := rand.Float64() * math.Pi * 2
	s.probeSeq++
	s.probes = append(s.probes, &Probe{
		ID:     s.probeSeq,
		X:      m + rand.Float64()*math.Max(1.0, bw-m*2),
		Y:      m + rand.Float64()*math.Max(1.0, bh-m*2),
		Vx:     math.Cos(angle) * maxSpeed * 0.6,
		Vy:     math.Sin(angle) * maxSpeed * 0.6,
		Wander: angle,
		Hue:    180 + rand.Float64()*80,
	})
}

// nearestActiveUser returns the nearest star with meaningful pull, using an
// outward ring search on the spatial grid (effectively O(1) when stars are dense).
func (s *Sim) nearestActiveUser(x, y float64) *User {
	if len(s.grid) == 0 {
		return nil
	}
	cx, cy := int(x/gridCell), int(y/gridCell)
	var best *User
	bestD := math.Inf(1)

	for r := 0; r <= s.gridMaxR; r++ {
		for gx := cx - r; gx <= cx+r; gx++ {
			for gy := cy - r; gy <= cy+r; gy++ {
				if absInt(gx-cx) != r && absInt(gy-cy) != r {
					continue // only the outer ring at radius r
				}
				cell, ok := s.grid[gridKey{gx, gy}]
				if !ok {
					continue
				}
				for _, u := range cell {
					if u.PullForce <= pullMin {
						continue
					}
					d := (u.X-x)*(u.X-x) + (u.Y-y)*(u.Y-y)
					if d < bestD {
						bestD, best = d, u
					}
				}
			}
		}
		// A candidate found at ring r is guaranteed nearest once the ring's
		// closest possible point is farther than the current best.
		rc := float64(r) * gridCell
		if best != nil && rc*rc > bestD {
			break
		}
	}
	return best
}

func absInt(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

// update advances the simulation by dt seconds.
func (s *Sim) update(dt float64) {
	// Trim probes to the current cap (can shrink when users log out).
	if cap_ := s.maxProbes(); len(s.probes) > cap_ {
		s.probes = s.probes[:cap_]
	}

	s.spawnTimer -= dt
	if s.spawnTimer <= 0 {
		s.spawnProbe()
		s.spawnTimer = s.spawnInterval()
	}

	ease := math.Min(1.0, dt*pullFade)
	now := nowMs()
	anyActive := false
	for _, u := range s.users {
		u.PullForce += (s.pullTarget(u, now) - u.PullForce) * ease
		if u.PullForce > pullMin {
			anyActive = true
		}
		if u.Pulse > 0 {
			u.Pulse = math.Max(0, u.Pulse-dt*2.2)
		}
	}

	bw, bh := s.worldSize()
	if s.gridDirty {
		s.rebuildGrid()
	}
	s.gridMaxR = int(math.Max(bw, bh)/gridCell) + 2
	s.anyActive = anyActive

	for _, p := range s.probes {
		ax, ay := 0.0, 0.0
		p.Wander += (rand.Float64() - 0.5) * wanderStrength * dt * 2
		ax += math.Cos(p.Wander) * maxSpeed
		ay += math.Sin(p.Wander) * maxSpeed

		if p.X < edgeMargin {
			ax += edgeForce * (1 - p.X/edgeMargin)
		}
		if p.X > bw-edgeMargin {
			ax -= edgeForce * (1 - (bw-p.X)/edgeMargin)
		}
		if p.Y < edgeMargin {
			ay += edgeForce * (1 - p.Y/edgeMargin)
		}
		if p.Y > bh-edgeMargin {
			ay -= edgeForce * (1 - (bh-p.Y)/edgeMargin)
		}

		if anyActive {
			if near := s.nearestActiveUser(p.X, p.Y); near != nil {
				dx, dy := near.X-p.X, near.Y-p.Y
				d := math.Hypot(dx, dy)
				if d == 0 {
					d = 1
				}
				force := userAttraction * near.PullForce
				ax += (dx / d) * force
				ay += (dy / d) * force
			}
		}

		p.Vx += ax * dt
		p.Vy += ay * dt
		if speed := math.Hypot(p.Vx, p.Vy); speed > maxSpeed {
			p.Vx = (p.Vx / speed) * maxSpeed
			p.Vy = (p.Vy / speed) * maxSpeed
		}
		p.X += p.Vx * dt
		p.Y += p.Vy * dt
	}

	s.detectCollisions()
}

func (s *Sim) detectCollisions() {
	for i := len(s.probes) - 1; i >= 0; i-- {
		p := s.probes[i]
		var hit *User
	outer:
		for _, cell := range s.neighborCells(p.X, p.Y) {
			for _, u := range cell {
				if u.PullForce <= pullMin {
					continue
				}
				rr := probeRadius + u.R
				dx, dy := p.X-u.X, p.Y-u.Y
				if dx*dx+dy*dy <= rr*rr {
					hit = u
					break outer
				}
			}
		}
		if hit == nil {
			continue
		}
		hit.Hits++
		hit.Pulse = 1.0
		if newR := math.Min(hit.R+userGrowth, s.allowedRadius(hit)); newR > hit.R {
			hit.R = newR
		}
		s.collisions++
		s.markDirty(hit.ID)
		s.probes = append(s.probes[:i], s.probes[i+1:]...)
	}
}

// ---------------------------------------------------------------------------
// Snapshot
// ---------------------------------------------------------------------------

// snapshot returns a Snapshot value that is safe to marshal after releasing
// s.mu, since all slices are freshly allocated copies.
func (s *Sim) snapshot(includeUsers bool) Snapshot {
	probes := make([]ProbeSnap, len(s.probes))
	for i, p := range s.probes {
		probes[i] = ProbeSnap{
			ID:  p.ID,
			X:   math.Round(p.X*10) / 10,
			Y:   math.Round(p.Y*10) / 10,
			Hue: math.Round(p.Hue*10) / 10,
		}
	}
	snap := Snapshot{
		T:             nowMs(),
		Collisions:    s.collisions,
		MaxProbes:     s.maxProbes(),
		SpawnInterval: math.Round(s.spawnInterval()*100) / 100,
		Probes:        probes,
	}
	if includeUsers {
		bw, bh := s.worldSize()
		rev := s.rev
		snap.Rev = &rev
		snap.World = &WorldSnap{
			W: math.Round(bw*10) / 10,
			H: math.Round(bh*10) / 10,
		}
		users := make([]UserSnap, len(s.users))
		for i, u := range s.users {
			users[i] = UserSnap{
				ID: u.ID, Name: u.Name,
				X: math.Round(u.X*10) / 10, Y: math.Round(u.Y*10) / 10,
				R: math.Round(u.R*100) / 100, Hits: u.Hits,
				LoggedIn:  u.LoggedIn,
				Pull:      math.Round(u.PullForce*1000) / 1000,
				Pulse:     math.Round(u.Pulse*1000) / 1000,
				CreatedAt: u.CreatedAt, Sector: u.Sector,
				BoostAt: u.BoostAt, GravityUntil: u.GravityUntil, MoveReadyAt: u.MoveReadyAt,
				LastJamAt: u.LastJamAt, LastJamBy: u.LastJamBy,
			}
		}
		snap.Users = users
	}
	return snap
}

// Tick advances the sim and returns a snapshot + the current rev.
// Must be called with s.mu held. The snapshot is safe to marshal after release.
func (s *Sim) Tick(dt float64, includeUsers bool) (Snapshot, int) {
	s.expireHeartbeats(nowMs())
	s.update(dt)
	return s.snapshot(includeUsers), s.rev
}

// ---------------------------------------------------------------------------
// Persistence helpers (called by persistNow in main.go)
// ---------------------------------------------------------------------------

type rosterPayload struct {
	Rev   int          `json:"rev"`
	Users []UserRecord `json:"users"`
}

func (s *Sim) persistRecord(u *User) UserRecord {
	return UserRecord{
		ID: u.ID, Name: u.Name, Fx: u.Fx, Fy: u.Fy, Sector: u.Sector, R: u.R,
		Hits: u.Hits, CreatedAt: u.CreatedAt, LoggedIn: u.LoggedIn,
		Email: u.Email, Pw: u.Pw, GravityUntil: u.GravityUntil, MoveReadyAt: u.MoveReadyAt,
	}
}

// RosterBytes serialises the whole roster for the JSON backend.
// Must be called with s.mu held.
func (s *Sim) RosterBytes() []byte {
	records := make([]UserRecord, len(s.users))
	for i, u := range s.users {
		records[i] = s.persistRecord(u)
	}
	data, _ := json.MarshalIndent(rosterPayload{Rev: s.rev, Users: records}, "", "  ")
	return data
}

// DrainChanges snapshots pending dirty state and clears it.
// Must be called with s.mu held.
func (s *Sim) DrainChanges() ChangePayload {
	reset := s.resetPending
	var users []UserRecord
	if !reset {
		byID := make(map[int]*User, len(s.users))
		for _, u := range s.users {
			byID[u.ID] = u
		}
		for uid := range s.dirtyUsers {
			if u, ok := byID[uid]; ok {
				users = append(users, s.persistRecord(u))
			}
		}
	}
	p := ChangePayload{Rev: s.rev, Seq: s.userSeq, Reset: reset, Users: users}
	s.dirtyUsers = make(map[int]bool)
	s.resetPending = false
	s.dirty = false
	return p
}

// RequeueChanges re-marks a failed save so the next autosave retries it.
// Must be called with s.mu held.
func (s *Sim) RequeueChanges(p ChangePayload) {
	if p.Reset {
		s.resetPending = true
	}
	for _, rec := range p.Users {
		s.dirtyUsers[rec.ID] = true
	}
	s.dirty = true
}

// load populates the sim from the store. Missing data is not an error.
func (s *Sim) load() error {
	snap, err := s.store.Load()
	if err != nil {
		return fmt.Errorf("store load: %w", err)
	}
	if snap == nil {
		return nil
	}
	s.rev = snap.Rev
	maxID := 0
	for _, rec := range snap.Users {
		u := s.userFromRecord(rec)
		s.users = append(s.users, u)
		if u.ID > maxID {
			maxID = u.ID
		}
		// Rosters written before sector persistence were ordered in groups of ten.
		// Preserve that initial layout when every record still has the zero value.
		if len(snap.Users) > 0 {
			legacy := true
			for _, rec := range snap.Users {
				if rec.Sector != 0 {
					legacy = false
					break
				}
			}
			if legacy {
				for i, u := range s.users {
					u.Sector = i / sectorCapacity
				}
				s.positionUsers()
			}
		}
	}
	// Never re-issue an id that already exists on disk / in Valkey.
	if snap.Seq > s.userSeq {
		s.userSeq = snap.Seq
	}
	if maxID > s.userSeq {
		s.userSeq = maxID
	}
	return nil
}

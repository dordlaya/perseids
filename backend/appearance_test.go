package main

import "testing"

func TestAppearanceIDsAndDefault(t *testing.T) {
	if got := normalizedAppearanceID(""); got != appearanceHaloRing {
		t.Fatalf("empty appearance normalized to %q, want %q", got, appearanceHaloRing)
	}
	if got := normalizedAppearanceID("unknown"); got != appearanceHaloRing {
		t.Fatalf("unknown appearance normalized to %q, want %q", got, appearanceHaloRing)
	}
	for _, id := range []string{
		appearanceHaloRing,
		appearanceParticles,
		appearanceOrb,
		appearanceSwirl,
		appearanceCoreCircle,
		appearanceLens,
	} {
		if !validAppearanceID(id) {
			t.Errorf("validAppearanceID(%q) = false", id)
		}
	}
}

func TestSetAppearanceOnlyAcceptsKnownOptions(t *testing.T) {
	user := &User{ID: 7, AppearanceID: appearanceHaloRing}
	sim := &Sim{
		users:      []*User{user},
		dirtyUsers: make(map[int]bool),
	}

	if result := sim.SetAppearance(user.ID, "unknown"); result.OK || result.Error != "invalid_appearance" {
		t.Fatalf("invalid selection result = %+v", result)
	}
	if user.AppearanceID != appearanceHaloRing {
		t.Fatalf("invalid selection changed appearance to %q", user.AppearanceID)
	}

	if result := sim.SetAppearance(user.ID, appearanceSwirl); !result.OK {
		t.Fatalf("valid selection failed: %+v", result)
	}
	if user.AppearanceID != appearanceSwirl {
		t.Fatalf("appearance = %q, want %q", user.AppearanceID, appearanceSwirl)
	}
	if !sim.dirty || !sim.dirtyUsers[user.ID] {
		t.Fatal("appearance change was not marked for persistence")
	}
}

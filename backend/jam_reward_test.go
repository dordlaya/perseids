package main

import "testing"

func TestJamRewardStacksRefreshesAndCaps(t *testing.T) {
	user := &User{}
	if got := user.recordJamReward(1_000); got != 1 {
		t.Fatalf("first reward count = %d, want 1", got)
	}
	if got := user.recordJamReward(2_000); got != 2 {
		t.Fatalf("stacked reward count = %d, want 2", got)
	}
	if user.JamRewardAt != 2_000 {
		t.Fatalf("reward timestamp = %d, want refreshed timestamp 2000", user.JamRewardAt)
	}
	if got := user.recordJamReward(2_000 + jamRewardMs); got != 1 {
		t.Fatalf("reward count after expiration = %d, want 1", got)
	}

	for i := 0; i < jamRewardMax+5; i++ {
		user.recordJamReward(2_000 + jamRewardMs + int64(i+1))
	}
	if user.JamRewardCount != jamRewardMax {
		t.Fatalf("reward count = %d, want cap %d", user.JamRewardCount, jamRewardMax)
	}
}

func TestJamRewardRaisesPullWithoutCreatingJamImmunity(t *testing.T) {
	user := &User{
		LoggedIn:       true,
		JamRewardAt:    1_000,
		JamRewardCount: 10,
	}
	sim := &Sim{}
	if got := sim.pullTarget(user, 2_000); got != 0.6 {
		t.Fatalf("pull target with jam rewards = %v, want 0.6", got)
	}
	if got := sim.pullTarget(user, 1_000+jamRewardMs); got != basePull {
		t.Fatalf("pull target after reward expiry = %v, want %v", got, basePull)
	}
	if user.BoostAt != 0 {
		t.Fatalf("jam reward activated regular boost at %d", user.BoostAt)
	}
}

func TestSuccessfulJamGrantsRewardAndRewardedUserCanBeJammed(t *testing.T) {
	attacker := &User{ID: 1, Name: "Attacker", LoggedIn: true, Jams: make(map[int]int64)}
	target := &User{ID: 2, Name: "Target", LoggedIn: true, Jams: make(map[int]int64)}
	sim := &Sim{
		users:      []*User{attacker, target},
		dirtyUsers: make(map[int]bool),
	}

	result := sim.Jam(attacker.ID, target.ID)
	if !result.OK || result.RewardPercent != 1 {
		t.Fatalf("successful jam result = %+v, want first reward +1%% for one minute", result)
	}
	if attacker.JamRewardCount != 1 || attacker.JamRewardAt == 0 {
		t.Fatalf("attacker reward state = count %d at %d", attacker.JamRewardCount, attacker.JamRewardAt)
	}

	result = sim.Jam(target.ID, attacker.ID)
	if !result.OK {
		t.Fatalf("jam against a jam-rewarded user failed: %+v", result)
	}
}

func TestJamStillRejectsTargetWithRegularBoost(t *testing.T) {
	attacker := &User{ID: 1, Name: "Attacker", LoggedIn: true}
	target := &User{ID: 2, Name: "Target", LoggedIn: true, BoostAt: nowMs()}
	sim := &Sim{users: []*User{attacker, target}}

	result := sim.Jam(attacker.ID, target.ID)
	if result.OK || result.Error != "target_boosted" {
		t.Fatalf("jam result against regular boosted target = %+v, want target_boosted", result)
	}
}

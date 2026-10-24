package main

import "testing"

func TestJamRewardStacksWithIndependentExpiryAndCap(t *testing.T) {
	user := &User{}
	count, earliest := user.recordJamReward(1_000)
	if count != 1 || earliest != 1_000+jamRewardMs {
		t.Fatalf("first reward = (%d, %d), want (1, %d)", count, earliest, 1_000+jamRewardMs)
	}
	count, earliest = user.recordJamReward(2_000)
	if count != 2 || earliest != 1_000+jamRewardMs {
		t.Fatalf("second reward = (%d, %d), want (2, %d)", count, earliest, 1_000+jamRewardMs)
	}

	count, earliest = user.activeJamRewards(1_000 + jamRewardMs)
	if count != 1 || earliest != 2_000+jamRewardMs {
		t.Fatalf("rewards after first expiry = (%d, %d), want (1, %d)", count, earliest, 2_000+jamRewardMs)
	}

	for i := 0; i < jamRewardMax+5; i++ {
		user.recordJamReward(3_000 + int64(i))
	}
	count, _ = user.activeJamRewards(4_000)
	if count != jamRewardMax {
		t.Fatalf("reward count = %d, want cap %d", count, jamRewardMax)
	}
}

func TestJamRewardRaisesPullWithoutCreatingJamImmunity(t *testing.T) {
	user := &User{
		LoggedIn:       true,
		JamRewardUntil: []int64{60_000, 61_000, 62_000, 63_000, 64_000, 65_000, 66_000, 67_000, 68_000, 69_000},
	}
	sim := &Sim{}
	if got := sim.pullTarget(user, 2_000); got != 0.6 {
		t.Fatalf("pull target with jam rewards = %v, want 0.6", got)
	}
	if got := sim.pullTarget(user, 69_000); got != basePull {
		t.Fatalf("pull target after reward expiry = %v, want %v", got, basePull)
	}
	if user.BoostAt != 0 {
		t.Fatalf("jam reward activated regular boost at %d", user.BoostAt)
	}
}

func TestSuccessfulJamGrantsOnePercentForOneMinute(t *testing.T) {
	attacker := &User{ID: 1, Name: "Attacker", LoggedIn: true, Jams: make(map[int]int64)}
	target := &User{ID: 2, Name: "Target", LoggedIn: true, Jams: make(map[int]int64)}
	sim := &Sim{
		users:      []*User{attacker, target},
		dirtyUsers: make(map[int]bool),
	}

	result := sim.Jam(attacker.ID, target.ID)
	if !result.OK || result.RewardPercent != 1 || result.RewardTotalPercent != 1 {
		t.Fatalf("successful jam result = %+v, want +1%% active reward", result)
	}
	if result.RewardUntil == 0 || result.RewardUntil-result.JamUntil != 0 {
		t.Fatalf("reward expiry = %d, jam expiry = %d, want same one-minute duration", result.RewardUntil, result.JamUntil)
	}

	result = sim.Jam(target.ID, attacker.ID)
	if !result.OK {
		t.Fatalf("jam against a jam-rewarded user failed: %+v", result)
	}
}

func TestJamStillRejectsTargetWithRegularBoost(t *testing.T) {
	attacker := &User{ID: 1, Name: "Attacker", LoggedIn: true}
	target := &User{
		ID:             2,
		Name:           "Target",
		LoggedIn:       true,
		BoostAt:        nowMs(),
		JamRewardUntil: []int64{nowMs() + jamRewardMs},
	}
	sim := &Sim{users: []*User{attacker, target}}

	result := sim.Jam(attacker.ID, target.ID)
	if result.OK || result.Error != "target_boosted" {
		t.Fatalf("jam result against regular boosted target = %+v, want target_boosted", result)
	}
}

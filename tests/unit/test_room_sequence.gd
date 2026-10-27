extends GutTest
## Five-room cycle, boss rooms, spawn ranges and special room draws (D-002 .. D-006, D-009).


func test_five_room_cycle() -> void:
	assert_eq(RoomSequence.get_room_type(1), RoomSequence.RoomType.COMBAT)
	assert_eq(RoomSequence.get_room_type(2), RoomSequence.RoomType.COMBAT)
	assert_eq(RoomSequence.get_room_type(3), RoomSequence.RoomType.COMBAT_UPGRADE)
	assert_eq(RoomSequence.get_room_type(4), RoomSequence.RoomType.SPECIAL)
	assert_eq(RoomSequence.get_room_type(5), RoomSequence.RoomType.MINIBOSS)
	assert_eq(RoomSequence.get_room_type(6), RoomSequence.RoomType.COMBAT)
	assert_eq(RoomSequence.get_room_type(8), RoomSequence.RoomType.COMBAT_UPGRADE)


func test_boss_every_fifteen_rooms_endlessly() -> void:
	assert_eq(RoomSequence.get_room_type(10), RoomSequence.RoomType.MINIBOSS)
	assert_eq(RoomSequence.get_room_type(15), RoomSequence.RoomType.BOSS)
	assert_eq(RoomSequence.get_room_type(30), RoomSequence.RoomType.BOSS)
	assert_eq(RoomSequence.get_room_type(45), RoomSequence.RoomType.BOSS)
	assert_eq(RoomSequence.get_room_type(50), RoomSequence.RoomType.MINIBOSS)
	assert_eq(RoomSequence.get_room_type(105), RoomSequence.RoomType.BOSS, "endless: bosses keep coming")


func test_enemy_count_range() -> void:
	# D-118 (playtest): more but weaker enemies in every depth.
	assert_eq(RoomSequence.get_enemy_count_range(1), Vector2i(2, 4), "busy start, weak enemies")
	assert_eq(RoomSequence.get_enemy_count_range(6), Vector2i(4, 5))
	assert_eq(RoomSequence.get_enemy_count_range(16), Vector2i(7, 9), "second biome needs attention (D-200, D-213)")
	assert_eq(RoomSequence.get_enemy_count_range(31), Vector2i(6, 8), "late run (D-210, D-213)")


func test_biomes_and_boss_tiers() -> void:
	assert_eq(RoomSequence.get_biome(1), RoomSequence.Biome.CRYPT)
	assert_eq(RoomSequence.get_biome(16), RoomSequence.Biome.SLIME_GROTTO)
	assert_eq(RoomSequence.get_biome(45), RoomSequence.Biome.SHADOW_REALM)
	assert_eq(RoomSequence.get_biome(60), RoomSequence.Biome.EMBER_FORGE)
	assert_eq(RoomSequence.get_biome(61), RoomSequence.Biome.CRYPT)
	assert_eq(RoomSequence.get_boss_tier(60), 0)
	assert_eq(RoomSequence.get_boss_tier(75), 1, "second cycle of bosses")


func test_special_type_never_repeats() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var previous := -1
	var seen := {}
	for i in 400:
		var special := RoomSequence.roll_special_type(previous, rng)
		assert_ne(special, previous)
		seen[special] = true
		previous = special
	assert_eq(seen.size(), RoomSequence.SpecialType.size(), "every special type appears")


# --- Soul gate at place 4 (KE3, KONZEPT §2) ---

func test_soul_gate_chance_is_about_half() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var gates := 0
	for i in 5000:
		# Last gate in the cycle before: no guarantee, only the chance.
		if RoomSequence.roll_portal(rng, 9, 4):
			gates += 1
	assert_almost_eq(gates / 5000.0, RoomSequence.PORTAL_CHANCE, 0.03)
	assert_eq(RoomSequence.PORTAL_CHANCE, 0.5, "TESTWERT KE3: 50 % of the cycles")


func test_soul_gate_only_at_place_four() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 200:
		assert_false(RoomSequence.roll_portal(rng, 7, 0), "a branch special room at place 2 gets no gate")
		assert_false(RoomSequence.roll_portal(rng, 15, 0), "the boss room has its gate at the campfire")


func test_soul_gate_is_due_after_a_cycle_without() -> void:
	assert_eq(RoomSequence.get_cycle(0), 0)
	assert_eq(RoomSequence.get_cycle(4), 1)
	assert_eq(RoomSequence.get_cycle(5), 1)
	assert_eq(RoomSequence.get_cycle(6), 2)
	assert_false(RoomSequence.is_gate_due(4, 0), "first cycle: only the chance")
	assert_true(RoomSequence.is_gate_due(9, 0), "no gate in cycle 1: cycle 2 gets one")
	assert_false(RoomSequence.is_gate_due(9, 4))
	assert_false(RoomSequence.is_gate_due(19, 15), "the campfire after room 15 counts for cycle 3")
	assert_true(RoomSequence.is_gate_due(24, 15))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 200:
		assert_true(RoomSequence.roll_portal(rng, 14, 4), "due: always a gate")


func test_soul_gate_never_two_cycles_in_a_row_without() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var last_gate := 0
	var gates := 0
	var cycles := 3000
	for cycle in range(1, cycles + 1):
		var place_four := (cycle - 1) * RoomSequence.CYCLE_LENGTH + 4
		var has_gate := RoomSequence.roll_portal(rng, place_four, last_gate)
		if has_gate:
			last_gate = place_four
			gates += 1
		assert_true(RoomSequence.get_cycle(place_four) - RoomSequence.get_cycle(last_gate) <= 1, "cycle %d: a gate in this or the last cycle" % cycle)
	# 50 % chance plus the guarantee: 1 / (2 - 0.5) = two of three cycles.
	assert_almost_eq(gates / float(cycles), 2.0 / 3.0, 0.03)


func test_soul_gate_roll_draws_exactly_once() -> void:
	var a := RandomNumberGenerator.new()
	a.seed = 5
	var b := RandomNumberGenerator.new()
	b.seed = 5
	RoomSequence.roll_portal(a, 9, 0)
	RoomSequence.roll_portal(a, 7, 0)
	RoomSequence.roll_portal(a)
	for i in 3:
		b.randf()
	assert_eq(a.state, b.state, "forced, refused or legacy: one draw each, the room stream stays")

extends GutTest
## Pure rules of A7 (KONZEPT_RAEUME §4, D-101, D-104, D-109): the variant draw (20 % from room 6,
## never two in a row, gravedigger only in the crypt, wager altar on 12 % of the others, fixed RNG
## use), the variant numbers, the placement helpers, the variant encounter group and the decoy hook.

const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
const SLIME: EnemyData = preload("res://enemies/data/slime.tres")
const ARCHER: EnemyData = preload("res://enemies/data/archer.tres")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_variant_rules_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# --- Draw table ---

func test_default_table_lists_every_variant() -> void:
	var table := VariantTable.load_default()
	assert_not_null(table)
	assert_eq(table.from_room, 6)
	assert_almost_eq(table.variant_chance, 0.2, 0.0001, "D-101")
	assert_almost_eq(table.wager_chance, 0.12, 0.0001, "D-104")
	for id in VariantRules.ALL:
		assert_true(table.variant_ids.has(id), "%s in the table" % id)
	# A7 + A9: crypt 4 + stone guardian + lantern, shadow realm 3 + stone guardian + lantern + torch
	# room, the other biomes 3 + lantern.
	assert_eq(table.get_allowed(RoomSequence.Biome.CRYPT).size(), 6)
	assert_eq(table.get_allowed(RoomSequence.Biome.SHADOW_REALM).size(), 6)
	assert_false(table.get_allowed(RoomSequence.Biome.SLIME_GROTTO).has(VariantRules.GRAVEDIGGER), "gravedigger: crypt only")
	assert_eq(table.get_allowed(RoomSequence.Biome.EMBER_FORGE).size(), 4)
	for id in table.variant_ids:
		assert_eq(table.get_weight(id), 1.0, "%s weighs like the others" % id)


func test_rooms_one_to_five_and_other_room_types_get_nothing() -> void:
	var table := VariantTable.load_default()
	var rng := _rng(4)
	for room in range(1, 6):
		for i in 200:
			var pick := table.roll(room, RoomSequence.RoomType.COMBAT, &"", rng)
			assert_true(pick.is_empty(), "room %d stays plain" % room)
	for room_type in [RoomSequence.RoomType.SPECIAL, RoomSequence.RoomType.MINIBOSS, RoomSequence.RoomType.BOSS, RoomSequence.RoomType.CAMPFIRE]:
		assert_true(table.roll(12, room_type, &"", rng).is_empty())


func test_roll_draws_three_numbers_for_combat_rooms_and_none_otherwise() -> void:
	var table := VariantTable.load_default()
	for room_type in RoomSequence.RoomType.values():
		var rng := _rng(77)
		var reference := _rng(77)
		table.roll(3, room_type, &"", rng)
		var draws := 3 if RoomSequence.is_normal_combat(room_type) else 0
		for i in draws:
			reference.randf()
		assert_eq(rng.randf(), reference.randf(), "room type %d uses %d numbers" % [room_type, draws])
	var a := _rng(5)
	var b := _rng(5)
	table.roll(9, RoomSequence.RoomType.COMBAT, &"", a)
	table.roll(9, RoomSequence.RoomType.COMBAT, VariantRules.BOUNTY, b)
	assert_eq(a.randf(), b.randf(), "the previous variant changes nothing in the RNG use")


func test_twenty_percent_variants_and_twelve_percent_wager_from_room_six() -> void:
	var table := VariantTable.load_default()
	var rng := _rng(2026)
	var variants := 0
	var wagers := 0
	var plain := 0
	var runs := 20000
	for i in runs:
		var pick := table.roll(7 + i % 8, RoomSequence.RoomType.COMBAT, &"", rng)
		if pick.has_variant():
			variants += 1
			assert_false(pick.wager, "a variant room has no wager altar")
		elif pick.wager:
			wagers += 1
		else:
			plain += 1
	assert_almost_eq(float(variants) / runs, 0.2, 0.015, "20 % variants (D-101)")
	assert_almost_eq(float(wagers) / (wagers + plain), 0.12, 0.015, "12 % of the other combat rooms (D-104)")


func test_never_two_variants_in_a_row() -> void:
	var table := VariantTable.load_default()
	var rng := _rng(99)
	var previous: StringName = &""
	var seen := 0
	for i in 3000:
		var pick := table.roll(6 + i % 9, RoomSequence.RoomType.COMBAT_UPGRADE if i % 3 == 2 else RoomSequence.RoomType.COMBAT, previous, rng)
		if previous != &"":
			assert_false(pick.has_variant(), "no variant right after %s" % previous)
		if pick.has_variant():
			seen += 1
		previous = pick.variant_id
	assert_gt(seen, 300)


func test_gravedigger_only_in_the_crypt_and_all_four_appear() -> void:
	var table := VariantTable.load_default()
	var rng := _rng(11)
	var crypt_counts := {}
	for i in 6000:
		var room := 6 + i % 9  # rooms 6-14: crypt
		var pick := table.roll(room, RoomSequence.RoomType.COMBAT, &"", rng)
		if pick.has_variant():
			crypt_counts[pick.variant_id] = crypt_counts.get(pick.variant_id, 0) + 1
		var deeper := table.roll(16 + i % 14, RoomSequence.RoomType.COMBAT, &"", rng)  # slime grotto
		assert_ne(deeper.variant_id, VariantRules.GRAVEDIGGER, "gravedigger only in the crypt")
	for id in table.get_allowed(RoomSequence.Biome.CRYPT):
		assert_gt(crypt_counts.get(id, 0), 100, "%s appears in the crypt" % id)


func test_choose_variant_follows_the_weights() -> void:
	var table := VariantTable.new()
	table.variant_ids = [&"a", &"b"] as Array[StringName]
	table.variant_weights = [3.0, 1.0] as Array[float]
	table.variant_biomes = [-1, -1] as Array[int]
	assert_eq(table.choose_variant(0, 0.0), &"a")
	assert_eq(table.choose_variant(0, 0.74), &"a")
	assert_eq(table.choose_variant(0, 0.76), &"b")
	table.variant_weights = [0.0, 0.0] as Array[float]
	assert_eq(table.choose_variant(0, 0.5), &"", "no weight, no variant")


# --- Variant numbers ---

func test_soul_flame_numbers() -> void:
	assert_eq(VariantRules.FLAME_DURATION, 24.0, "24 s (D-118, KONZEPT §4.1 said 40 s)")
	assert_eq(VariantRules.FLAME_RAID_SHARE, 0.7, "70 % go for the flame")
	assert_true(VariantRules.is_raider(0.69))
	assert_false(VariantRules.is_raider(0.7))
	var solo := VariantRules.flame_health(6, 1)
	assert_gt(VariantRules.flame_health(30, 1), solo, "scales with the enemy damage of the room")
	assert_almost_eq(VariantRules.flame_health(6, 2), solo * 1.5, 0.5, "co-op parameter (D-109)")
	assert_eq(fmod(solo, 0.5), 0.0, "0.5 steps")


func test_raid_waves_by_time_or_when_the_room_runs_empty() -> void:
	assert_true(VariantRules.should_send_wave(12.0, VariantRules.FLAME_WAVE_INTERVAL, 5, true), "every interval")
	assert_false(VariantRules.should_send_wave(12.0, 4.0, 5, true))
	assert_true(VariantRules.should_send_wave(12.0, VariantRules.FLAME_WAVE_MIN_GAP, 1, true), "at most one enemy left")
	assert_false(VariantRules.should_send_wave(12.0, VariantRules.FLAME_WAVE_MIN_GAP - 0.5, 1, true), "minimum gap (D-118)")
	assert_false(VariantRules.should_send_wave(1.0, 1.0, 0, true), "not two waves at once")
	assert_false(VariantRules.should_send_wave(VariantRules.FLAME_DURATION + 1.0, 20.0, 0, true), "raid over after the flame time")
	assert_false(VariantRules.should_send_wave(12.0, 20.0, 0, false), "no raid once the flame is out")
	assert_eq(VariantRules.flame_wave_size(10), 5, "half a normal roll (D-118)")
	assert_eq(VariantRules.flame_wave_size(1), VariantRules.FLAME_WAVE_MIN)
	assert_true(VariantRules.flame_holds_room(VariantRules.FLAME_DURATION - 1.0, true))
	assert_false(VariantRules.flame_holds_room(VariantRules.FLAME_DURATION, true))
	assert_false(VariantRules.flame_holds_room(0.0, false))


func test_rift_numbers() -> void:
	assert_eq(VariantRules.rift_count(0.0, 1), 2)
	assert_eq(VariantRules.rift_count(0.99, 1), 3)
	assert_eq(VariantRules.rift_count(0.0, 2), 2 + VariantRules.RIFTS_PER_EXTRA_PLAYER, "co-op parameter (D-109)")
	assert_true(VariantRules.can_summon(5))
	assert_false(VariantRules.can_summon(6), "fewer than six alive (KONZEPT §4.2)")
	assert_eq(VariantRules.RIFT_SUMMON_INTERVAL, 4.0)


func test_gravedigger_numbers() -> void:
	assert_true(VariantRules.can_rise(&"skeleton"))
	assert_false(VariantRules.can_rise(&"slime"))
	assert_false(VariantRules.is_rising(3.9))
	assert_true(VariantRules.is_rising(4.0), "the last second is visible")
	assert_false(VariantRules.should_rise(4.99))
	assert_true(VariantRules.should_rise(5.0), "5 s (KONZEPT §4.5)")
	assert_eq(VariantRules.risen_health(28.0), 14.0, "50 % health")
	assert_eq(VariantRules.risen_health(0.6), 0.5)
	assert_true(VariantRules.is_stomped(VariantRules.STOMP_RADIUS))
	assert_false(VariantRules.is_stomped(VariantRules.STOMP_RADIUS + 1.0))


func test_bounty_numbers() -> void:
	assert_eq(VariantRules.BOUNTY_CATCH_TIME, 12.0, "12 s (KONZEPT §4.6)")
	assert_true(VariantRules.bounty_sees(100.0, true))
	assert_false(VariantRules.bounty_sees(100.0, false), "no sight through walls")
	assert_false(VariantRules.bounty_sees(VariantRules.BOUNTY_SIGHT_RANGE + 1.0, true))
	assert_eq(VariantRules.hole_progress(6.0), 0.5)
	assert_false(VariantRules.bounty_escapes(11.9))
	assert_true(VariantRules.bounty_escapes(12.0))
	assert_true(VariantRules.bounty_warns(9.5))


func test_one_chest_for_the_group_until_mp5() -> void:
	assert_false(VariantRules.CHESTS_PER_PLAYER)
	assert_eq(VariantRules.chest_count(1), 1)
	assert_eq(VariantRules.chest_count(3), 1)


# --- Placement ---

func _block(size: Vector2i) -> Dictionary[Vector2i, bool]:
	var free: Dictionary[Vector2i, bool] = {}
	for y in size.y:
		for x in size.x:
			free[Vector2i(x, y)] = true
	return free


func test_open_tiles_need_free_neighbours() -> void:
	var free := _block(Vector2i(5, 5))
	assert_true(VariantSpots.is_open(Vector2i(2, 2), free))
	assert_false(VariantSpots.is_open(Vector2i(0, 2), free), "edge tile")
	free.erase(Vector2i(3, 3))
	assert_false(VariantSpots.is_open(Vector2i(2, 2), free))
	assert_eq(VariantSpots.nearest_open(free, Vector2i(2, 2)), Vector2i(2, 1), "next open tile (ties: north first)")
	assert_eq(VariantSpots.nearest_open({} as Dictionary[Vector2i, bool], Vector2i.ZERO), VariantSpots.INVALID)


func test_wall_tiles_and_spread() -> void:
	var free := _block(Vector2i(24, 6))
	var walkable := _block(Vector2i(24, 6))
	var doors: Array[Vector2i] = [Vector2i(6, 5), Vector2i(6, 0)]
	var walls := VariantSpots.wall_tiles(free, walkable, doors, 3.0)
	for tile in walls:
		assert_eq(tile.y, 0, "north row: wall above")
		assert_gte(Vector2(tile - Vector2i(6, 0)).length(), 3.0, "away from the exit door")
	var picked := VariantSpots.pick_spread(walls, 3, 4.0, _rng(3))
	assert_eq(picked.size(), 3)
	for a in picked:
		for b in picked:
			if a != b:
				assert_gte(Vector2(a - b).length(), 4.0)


func test_far_tile_and_altar_tile() -> void:
	var free := _block(Vector2i(15, 9))
	var far := VariantSpots.far_tile(free, Vector2i(1, 1), 5.0, [Vector2i(13, 7)] as Array[Vector2i], 3.0, _rng(8))
	assert_gte(Vector2(far - Vector2i(1, 1)).length(), 5.0)
	assert_gte(Vector2(far - Vector2i(13, 7)).length(), 3.0, "away from the players")
	free.erase(Vector2i(7, 8))
	assert_eq(VariantSpots.altar_tile(free, Vector2i(7, 8)), Vector2i(8, 8), "right beside the entrance")
	free.erase(Vector2i(8, 8))
	assert_eq(VariantSpots.altar_tile(free, Vector2i(7, 8)), Vector2i(6, 8))


# --- Encounter group ---

func test_variant_group_keeps_the_room_group_and_shapes_it() -> void:
	var base := EncounterGroup.new()
	base.allow_elites = false
	base.count_factor = 0.8
	base.attack_kind = EnemyData.AttackKind.MELEE
	var factors: Dictionary[StringName, float] = {&"skeleton": 3.0}
	var group := VariantEncounterGroup.wrap(base, self, 0.5, factors)
	assert_false(group.allow_elites)
	assert_almost_eq(group.count_factor, 0.4, 0.0001)
	var table := group.filter_table([SLIME, SKELETON, ARCHER] as Array[EnemyData], [0.5, 0.35, 0.15] as Array[float])
	var types: Array[EnemyData] = table[0]
	var weights: Array[float] = table[1]
	assert_false(types.has(ARCHER), "the base filter (melee) still applies")
	assert_almost_eq(weights[types.find(SKELETON)], 1.05, 0.0001, "skeletons x3")
	assert_almost_eq(weights[types.find(SLIME)], 0.5, 0.0001)
	var plain := VariantEncounterGroup.wrap(null, self, 0.7)
	assert_almost_eq(plain.count_factor, 0.7, 0.0001)
	assert_true(plain.allow_elites)


# --- Decoy hook ---

func test_decoy_wins_while_it_lives() -> void:
	var enemy := autofree(Node2D.new()) as Node2D
	add_child(enemy)
	var player := autofree(_Target.new()) as _Target
	add_child(player)
	player.position = Vector2(50, 0)
	var flame := autofree(_Target.new()) as _Target
	add_child(flame)
	flame.position = Vector2(400, 0)
	assert_eq(EnemyDecoy.choose_target(enemy, [player], null), player, "without decoy: nearest player")
	EnemyDecoy.assign(enemy, flame)
	assert_true(EnemyDecoy.has_decoy(enemy))
	assert_eq(EnemyDecoy.choose_target(enemy, [player], player), flame, "the flame first")
	flame.alive = false
	assert_null(EnemyDecoy.get_decoy(enemy))
	assert_eq(EnemyDecoy.choose_target(enemy, [player], flame), player, "flame out: back to the players")
	EnemyDecoy.clear(enemy)
	assert_false(enemy.has_meta(EnemyDecoy.META))


class _Target:
	extends Node2D
	var alive := true

	func is_alive() -> bool:
		return alive

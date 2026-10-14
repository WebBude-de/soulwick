extends GutTest
## Pure rules of the room modes (KONZEPT_RAEUME_V2 §2, §4, D-120, R4b): the mode table (35 % of the
## combat rooms from room 6, at most two per cycle, never the same mode twice in a row, no mode twice
## in a cycle, new modes one by one, first rooms per mode, plan modes, wager altar on 12 % of the
## others, fixed RNG use), the numbers of the five minigames and the crypt trait, the placement
## helpers, the variant encounter group and the decoy hook.

const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
const SLIME: EnemyData = preload("res://enemies/data/slime.tres")
const ARCHER: EnemyData = preload("res://enemies/data/archer.tres")
const R4B_MODES: Array[StringName] = [&"flame", &"relic", &"rifts", &"hunt", &"lightfire"]

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


## Rooms of a run on cycle places 1-3 (the combat rooms), from first to last.
func _combat_rooms(first: int, last: int) -> Array[int]:
	var rooms: Array[int] = []
	for room in range(first, last + 1):
		if RoomSequence.is_normal_combat(RoomSequence.get_room_type(room)):
			rooms.append(room)
	return rooms


# --- Mode table ---

func test_registry_lists_the_modes_of_r4b_with_their_plans_and_first_rooms() -> void:
	for id in R4B_MODES:
		assert_true(ModeRegistry.has_mode(id), "%s registered" % id)
		assert_true(RoomObjective.has_mode(id), "%s has a goal (RoomObjective.MODES)" % id)
		assert_true(RoomGenre.has_genre(id), "%s has a genre card" % id)
		assert_true(ResourceLoader.exists(ModeRegistry.get_script_path(id)), "%s script" % id)
	assert_eq(ModeRegistry.get_plan_mode(&"lightfire"), &"beacon", "the plans call it beacon")
	assert_eq(ModeRegistry.get_plan_mode(&"flame"), &"flame")
	assert_eq(ModeRegistry.get_from_room(&"flame"), 6, "cycle 2")
	assert_eq(ModeRegistry.get_from_room(&"relic"), 11, "cycle 3")
	assert_eq(ModeRegistry.get_from_room(&"rifts"), 16, "cycle 4")
	assert_eq(ModeRegistry.get_from_room(&"hunt"), 16, "cycle 4")
	assert_eq(ModeRegistry.get_from_room(&"lightfire"), 16, "second biome")
	assert_eq(ModeRegistry.get_plan_mode(&"nonsense"), &"")
	assert_true(ModeRegistry.allows_secret(&""), "plain rooms may hide a niche")
	assert_true(ModeRegistry.allows_secret(&"flame"))
	assert_false(ModeRegistry.allows_secret(&"collapse"), "Einsturz breaks the floor in front of a niche")
	assert_null(ModeRegistry.create(&"nonsense"))
	for id in R4B_MODES:
		var mode := ModeRegistry.create(id)
		assert_true(mode is RoomMode, "%s builds a RoomMode" % id)
		mode.free()


func test_default_table_comes_from_the_registry() -> void:
	var table := VariantTable.load_default()
	assert_not_null(table)
	assert_eq(table.from_room, 6)
	assert_almost_eq(table.variant_chance, 0.35, 0.0001, "D-120: 30-40 %")
	assert_eq(table.max_per_cycle, 2)
	assert_almost_eq(table.wager_chance, 0.12, 0.0001, "D-104")
	for id in R4B_MODES:
		assert_true(table.variant_ids.has(id), "%s in the table" % id)
	var room_six := table.get_allowed(RoomSequence.Biome.CRYPT, 6)
	assert_true(room_six.has(&"flame"), "room 6: the flame (cycle 2)")
	for id in room_six:
		assert_eq(ModeRegistry.get_from_room(id), 6, "room 6: only the modes of cycle 2 (%s)" % id)
	assert_true(table.get_allowed(RoomSequence.Biome.CRYPT, 11).has(&"relic"))
	assert_false(table.get_allowed(RoomSequence.Biome.CRYPT, 11).has(&"hunt"))
	for id in R4B_MODES:
		assert_true(table.get_allowed(RoomSequence.Biome.EMBER_FORGE, 50).has(id), "%s in every biome later" % id)
	assert_ne(VariantTable.load_default(), table, "a fresh table per run")


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
	for room_type in RoomSequence.RoomType.values():
		var table := VariantTable.load_default()
		var rng := _rng(77)
		var reference := _rng(77)
		table.roll(3, room_type, &"", rng)
		var draws := 3 if RoomSequence.is_normal_combat(room_type) else 0
		for i in draws:
			reference.randf()
		assert_eq(rng.randf(), reference.randf(), "room type %d uses %d numbers" % [room_type, draws])
	var a := _rng(5)
	var b := _rng(5)
	VariantTable.load_default().roll(9, RoomSequence.RoomType.COMBAT, &"", a)
	VariantTable.load_default().roll(9, RoomSequence.RoomType.COMBAT, &"flame", b)
	assert_eq(a.randf(), b.randf(), "the previous mode changes nothing in the RNG use")


func test_a_pick_names_its_plan_mode() -> void:
	var table := VariantTable.load_default()
	var rng := _rng(31)
	var seen := 0
	for run in 40:
		table.reset_history()
		for room in _combat_rooms(16, 45):
			var pick := table.roll(room, RoomSequence.RoomType.COMBAT, &"", rng)
			if pick.has_variant():
				seen += 1
				assert_eq(pick.plan_mode, ModeRegistry.get_plan_mode(pick.variant_id))
				assert_false(pick.wager, "a minigame room has no wager altar")
			else:
				assert_eq(pick.plan_mode, &"")
	assert_gt(seen, 100)
	var forced := VariantTable.pick_for(&"lightfire")
	assert_eq(forced.variant_id, &"lightfire")
	assert_eq(forced.plan_mode, &"beacon")


func test_about_a_third_minigames_at_most_two_per_cycle_and_wager_on_the_rest() -> void:
	var rng := _rng(2026)
	var rooms := _combat_rooms(6, 90)
	var modes := 0
	var wagers := 0
	var plain := 0
	for run in 300:
		var table := VariantTable.load_default()
		var per_cycle := {}
		var previous: StringName = &""
		for room in rooms:
			var pick := table.roll(room, RoomSequence.RoomType.COMBAT, previous, rng)
			if pick.has_variant():
				modes += 1
				var cycle := VariantTable.get_cycle(room)
				var in_cycle: Array = per_cycle.get(cycle, [])
				assert_false(in_cycle.has(pick.variant_id), "no mode twice in a cycle")
				in_cycle.append(pick.variant_id)
				per_cycle[cycle] = in_cycle
				assert_lte(in_cycle.size(), 2, "at most two per cycle")
			elif pick.wager:
				wagers += 1
			else:
				plain += 1
			previous = pick.variant_id
	var share := float(modes) / (300.0 * rooms.size())
	assert_between(share, 0.28, 0.4, "30-40 %% minigames (D-120), measured %.3f" % share)
	assert_almost_eq(float(wagers) / (wagers + plain), 0.12, 0.015, "12 % of the other combat rooms (D-104)")


func test_never_the_same_mode_twice_in_a_row() -> void:
	var rng := _rng(99)
	for run in 200:
		var table := VariantTable.load_default()
		var last: StringName = &""
		for room in _combat_rooms(6, 120):
			var pick := table.roll(room, RoomSequence.RoomType.COMBAT, &"", rng)
			if pick.has_variant():
				assert_ne(pick.variant_id, last, "room %d: not %s again" % [room, last])
				last = pick.variant_id


func test_new_modes_come_one_by_one_and_never_before_their_room() -> void:
	var rng := _rng(7)
	var first_seen := {}
	for run in 400:
		var table := VariantTable.load_default()
		for room in _combat_rooms(6, 60):
			var pick := table.roll(room, RoomSequence.RoomType.COMBAT, &"", rng)
			if not pick.has_variant():
				continue
			assert_gte(room, ModeRegistry.get_from_room(pick.variant_id), "%s not before its room" % pick.variant_id)
			if not first_seen.has(pick.variant_id) or room < int(first_seen[pick.variant_id]):
				first_seen[pick.variant_id] = room
	for id in R4B_MODES:
		assert_true(first_seen.has(id), "%s appears" % id)
	assert_lt(int(first_seen[&"relic"]), 16, "the relic comes in cycle 3")
	# A mode the run has not seen comes first: after its debut the next new one is preferred.
	var table := VariantTable.load_default()
	table.note_drawn(16, &"rifts")
	table.note_drawn(17, &"hunt")
	table.note_drawn(18, &"flame")
	table.note_drawn(19, &"relic")
	var fresh := table.choose_variant(RoomSequence.Biome.SLIME_GROTTO, 0.0, 21)
	assert_false([&"rifts", &"hunt", &"flame", &"relic"].has(fresh), "a mode not seen yet first, got %s" % fresh)


func test_choose_variant_follows_the_weights() -> void:
	var table := VariantTable.new()
	table.variant_ids = [&"a", &"b"] as Array[StringName]
	table.variant_weights = [3.0, 1.0] as Array[float]
	table.variant_biomes = [-1, -1] as Array[int]
	table.variant_biome_masks = [0, 0] as Array[int]
	table.variant_from_rooms = [0, 0] as Array[int]
	assert_eq(table.choose_variant(0, 0.0), &"a")
	assert_eq(table.choose_variant(0, 0.74), &"a")
	assert_eq(table.choose_variant(0, 0.76), &"b")
	assert_eq(table.choose_variant(0, 0.0, 0, [&"a"] as Array[StringName]), &"b", "excluded mode")
	table.variant_weights = [0.0, 0.0] as Array[float]
	assert_eq(table.choose_variant(0, 0.5), &"", "no weight, no mode")


# --- Mode numbers ---

func test_flame_numbers() -> void:
	assert_eq(FlameRules.DURATION, 40.0, "Halte die Flamme 40 s (KONZEPT_RAEUME_V2 §3.4)")
	assert_true(FlameRules.is_raider(0.69))
	assert_false(FlameRules.is_raider(0.7))
	var solo := FlameRules.flame_health(6, 1)
	assert_gt(FlameRules.flame_health(30, 1), solo, "scales with the enemy damage of the room")
	assert_almost_eq(FlameRules.flame_health(6, 2), solo * 1.5, 0.5, "co-op parameter (D-109)")
	assert_eq(fmod(solo, 0.5), 0.0, "0.5 steps")
	assert_true(FlameRules.should_push(12.0, FlameRules.PUSH_INTERVAL, 5, true), "every 8 s")
	assert_false(FlameRules.should_push(12.0, 4.0, 5, true))
	assert_true(FlameRules.should_push(12.0, FlameRules.PUSH_MIN_GAP, 1, true), "almost empty: sooner")
	assert_false(FlameRules.should_push(12.0, FlameRules.PUSH_MIN_GAP - 0.5, 0, true))
	assert_false(FlameRules.should_push(FlameRules.DURATION, 20.0, 0, true), "the sources go dark after 40 s")
	assert_false(FlameRules.should_push(12.0, 20.0, 0, false), "no pushes once the flame is out")
	assert_eq(FlameRules.push_size(10), 4)
	assert_eq(FlameRules.push_size(1), FlameRules.PUSH_MIN)
	assert_true(FlameRules.holds_room(39.0, true))
	assert_false(FlameRules.holds_room(40.0, true))
	assert_gt(FlameRules.light_radius(1.0), FlameRules.light_radius(0.3), "the light follows the health")
	assert_eq(FlameRules.full_flame_crystals(1.0), 1, "volle Flamme = +1 Kristall")
	assert_eq(FlameRules.full_flame_crystals(0.97), 0)


func test_relic_numbers() -> void:
	assert_eq(RelicRules.relic_count(11), 1)
	assert_eq(RelicRules.relic_count(26), 2, "two relics from cycle 6")
	assert_true(RelicRules.holds_room(true, 0, 1))
	assert_false(RelicRules.holds_room(true, 1, 1))
	assert_false(RelicRules.holds_room(false, 0, 1))
	assert_true(RelicRules.bonus_open(39.9))
	assert_false(RelicRules.relics_return(39.9, 0, 1))
	assert_true(RelicRules.relics_return(40.0, 0, 1), "late: the relic flies home")
	assert_false(RelicRules.relics_return(50.0, 1, 1))
	assert_true(RelicRules.can_place(RelicRules.ALTAR_RADIUS))
	assert_false(RelicRules.can_place(RelicRules.ALTAR_RADIUS + 1.0))
	assert_eq(RelicRules.wake_size(1), RelicRules.WAKE_MIN)
	assert_lt(RelicRules.CARRY_SPEED_FACTOR, 1.0, "the carrier is slower")


func test_rift_numbers() -> void:
	assert_eq(RiftRules.rift_count(0.0, 1), 2)
	assert_eq(RiftRules.rift_count(0.99, 1), 3)
	assert_eq(RiftRules.rift_count(0.0, 2), 2 + RiftRules.PER_EXTRA_PLAYER, "co-op parameter (D-109)")
	assert_true(RiftRules.can_summon(5))
	assert_false(RiftRules.can_summon(6), "fewer than six alive")
	assert_eq(RiftRules.PUSH_INTERVAL, 6.0, "im Takt alle 6 s")
	assert_eq(RiftRules.vent_count(0), 0)
	assert_eq(RiftRules.vent_count(1), RiftRules.VENT_PUSH, "vents join after the first rift")
	assert_eq(RiftRules.fast_crystals(39.0), 1, "alle unter 40 s = Kristall")
	assert_eq(RiftRules.fast_crystals(40.0), 0)


func test_hunt_numbers() -> void:
	assert_true(HuntRules.sees(100.0, true))
	assert_false(HuntRules.sees(100.0, false), "no sight through walls")
	assert_false(HuntRules.sees(HuntRules.SIGHT_RANGE + 1.0, true))
	assert_eq(HuntRules.hole_progress(HuntRules.CATCH_TIME * 0.5), 0.5)
	assert_false(HuntRules.hole_open(HuntRules.CATCH_TIME - 0.1))
	assert_true(HuntRules.hole_open(HuntRules.CATCH_TIME))
	assert_true(HuntRules.forced_escape(HuntRules.CATCH_TIME + HuntRules.STUCK_GRACE))
	assert_false(HuntRules.runs_to_hole(1.0), "first he zigzags")
	assert_true(HuntRules.runs_to_hole(HuntRules.CATCH_TIME - HuntRules.RUN_TO_HOLE_TIME))
	assert_gt(HuntRules.evade_score(400.0, 64.0), HuntRules.evade_score(100.0, 64.0), "away from the players")
	assert_eq(HuntRules.loot_gold(10), 10 * HuntRules.LOOT_GOLD_FACTOR, "viel Gold")
	assert_eq(HuntRules.loot_gold(0), HuntRules.LOOT_GOLD_MIN)
	assert_true(HuntRules.loot_has_upgrade(HuntRules.UPGRADE_CHANCE - 0.01))
	assert_false(HuntRules.loot_has_upgrade(HuntRules.UPGRADE_CHANCE))


func test_lightfire_numbers() -> void:
	assert_eq(LightfireRules.fire_count(0.0, 10), 4)
	assert_eq(LightfireRules.fire_count(0.99, 10), 6)
	assert_eq(LightfireRules.fire_count(0.99, 3), 3, "never more than spots")
	assert_almost_eq(LightfireRules.vision_factor(0, 6), LightfireRules.VISION_FACTOR, 0.0001)
	assert_almost_eq(LightfireRules.vision_factor(6, 6), 1.0, 0.0001, "every fire: the normal circle")
	assert_false(LightfireRules.is_complete(6, 6, 1), "guardians left")
	assert_false(LightfireRules.is_complete(5, 6, 0), "a fire is cold")
	assert_true(LightfireRules.is_complete(6, 6, 0))
	assert_true(LightfireRules.guardian_frozen(true, false, 0.0))
	assert_true(LightfireRules.guardian_frozen(false, true, 0.1), "thaw delay")
	assert_false(LightfireRules.guardian_frozen(false, true, LightfireRules.GUARDIAN_THAW_DELAY))
	assert_true(LightfireRules.PLAYER_LIGHT_HOLDS_GUARDIANS, "every light counts (D-116), no room without a way out")
	assert_eq(LightfireRules.guardian_count(0.0, 2), LightfireRules.GUARDIAN_COUNT.x + 1, "co-op parameter (D-109)")


func test_gravedigger_trait_numbers() -> void:
	assert_true(VariantRules.has_gravedigger(VariantRules.GRAVEDIGGER_FROM_ROOM, RoomSequence.Biome.CRYPT))
	assert_false(VariantRules.has_gravedigger(VariantRules.GRAVEDIGGER_FROM_ROOM - 1, RoomSequence.Biome.CRYPT))
	assert_false(VariantRules.has_gravedigger(20, RoomSequence.Biome.SLIME_GROTTO), "crypt only")
	assert_true(VariantRules.skeleton_rises(&"skeleton", VariantRules.GRAVEDIGGER_SKELETON_CHANCE - 0.01))
	assert_false(VariantRules.skeleton_rises(&"skeleton", VariantRules.GRAVEDIGGER_SKELETON_CHANCE))
	assert_false(VariantRules.skeleton_rises(&"slime", 0.0))
	assert_false(VariantRules.is_rising(3.9))
	assert_true(VariantRules.is_rising(4.0), "the last second is visible")
	assert_true(VariantRules.should_rise(5.0))
	assert_eq(VariantRules.risen_health(28.0), 14.0, "50 % health")
	assert_eq(VariantRules.risen_health(0.6), 0.5)
	assert_true(VariantRules.is_stomped(VariantRules.STOMP_RADIUS))
	assert_false(VariantRules.is_stomped(VariantRules.STOMP_RADIUS + 1.0))


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

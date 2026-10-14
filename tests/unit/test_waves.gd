extends GutTest
## Wave rules (A5, KONZEPT_RAEUME 3.1), overflow into an extra wave (D-086), wall gates and the
## spawner hooks for encounter groups. Pure rules and the spawner without a room.

const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
const ARCHER: EnemyData = preload("res://enemies/data/archer.tres")
const SLIME: EnemyData = preload("res://enemies/data/slime.tres")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_waves_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _rng(seed_value := 5) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _other_kind() -> int:
	for kind in RoomSequence.RoomKind.values():
		if kind != RoomSequence.RoomKind.ARENA:
			return kind
	return -1


func _spawner() -> EnemySpawner:
	var spawner: EnemySpawner = autofree(EnemySpawner.new())
	spawner.enemy_types.assign([SLIME, SKELETON, ARCHER])
	spawner.spawn_weights.assign([0.5, 0.35, 0.15])
	return spawner


func _context() -> DungeonContext:
	var context := DungeonContext.new()
	context.rng = _rng(9)
	return context


func _markers(count: int) -> Array[Marker2D]:
	var markers: Array[Marker2D] = []
	for i in count:
		var marker: Marker2D = autofree(Marker2D.new())
		marker.position = Vector2(64.0 * i, 0.0)
		markers.append(marker)
	return markers


# --- Rules ---

func test_arena_only_for_arena_kind_from_room_six() -> void:
	var arena := RoomSequence.RoomKind.ARENA
	assert_false(WaveRules.is_arena(RoomSequence.RoomType.COMBAT, arena, 5), "rooms 1-5 are normal (D-100)")
	assert_true(WaveRules.is_arena(RoomSequence.RoomType.COMBAT, arena, WaveRules.ARENA_FROM_ROOM))
	assert_true(WaveRules.is_arena(RoomSequence.RoomType.COMBAT_UPGRADE, arena, 12))
	assert_false(WaveRules.is_arena(RoomSequence.RoomType.COMBAT, _other_kind(), 12))
	assert_false(WaveRules.is_arena(RoomSequence.RoomType.MINIBOSS, arena, 10))
	assert_false(WaveRules.is_arena(RoomSequence.RoomType.BOSS, arena, 15))


func test_arena_has_two_waves_and_three_from_room_thirty() -> void:
	assert_eq(WaveRules.get_wave_count(6, true), 2)
	assert_eq(WaveRules.get_wave_count(16, true), 2, "two waves up to room 29 (D-118)")
	assert_eq(WaveRules.get_wave_count(29, true), 2)
	assert_eq(WaveRules.get_wave_count(31, true), 3)
	assert_eq(WaveRules.get_wave_count(61, true), 3)
	# Normal rooms keep D-074.
	assert_eq(WaveRules.get_wave_count(16, false), RoomSequence.get_wave_count(16))
	assert_eq(WaveRules.get_wave_count(61, false), RoomSequence.get_wave_count(61))


func test_next_wave_only_after_the_running_wave_is_cleared() -> void:
	assert_false(WaveRules.should_start_next_wave(1, true), "arena too (D-118, playtest)")
	assert_true(WaveRules.should_start_next_wave(0, true))
	assert_false(WaveRules.should_start_next_wave(2, true))
	assert_true(WaveRules.should_start_next_wave(0, false))
	assert_false(WaveRules.should_start_next_wave(1, false))


func test_arena_waves_are_smaller_but_never_single() -> void:
	assert_eq(WaveRules.get_wave_size(3, false), 3, "normal rooms keep their roll")
	assert_eq(WaveRules.get_wave_size(1, true), WaveRules.ARENA_MIN_WAVE_SIZE)
	assert_eq(WaveRules.get_wave_size(4, true), maxi(2, roundi(4 * WaveRules.ARENA_WAVE_SIZE_FACTOR)))
	assert_eq(WaveRules.get_wave_size(3, true, 3), 3, "never below the room's normal minimum")
	assert_eq(WaveRules.get_wave_size(5, true, 1, true), 5, "counts from room data stay as they are")
	# Every arena wave stays inside the normal range of its room (D-074).
	for room in [6, 16, 31, 61]:
		var limits := RoomSequence.get_enemy_count_range(room)
		for rolled in range(limits.x, limits.y + 1):
			assert_between(WaveRules.get_wave_size(rolled, true, limits.x), limits.x, limits.y)


func test_overflow_becomes_an_extra_wave() -> void:
	assert_eq(WaveRules.plan_wave_sizes([3] as Array[int], 5), [3] as Array[int])
	assert_eq(WaveRules.plan_wave_sizes([6, 3] as Array[int], 5), [5, 1, 3] as Array[int])
	assert_eq(WaveRules.plan_wave_sizes([12] as Array[int], 5), [5, 5, 2] as Array[int])
	assert_eq(WaveRules.plan_wave_sizes([4, 4] as Array[int], 0), [] as Array[int], "no spawn places, nothing planned")


func test_ambush_share_matches_the_chance() -> void:
	var rng := _rng(21)
	var hits := 0
	var draws := 4000
	for i in draws:
		if WaveRules.roll_ambush(rng):
			hits += 1
	assert_almost_eq(hits / float(draws), WaveRules.AMBUSH_CHANCE, 0.025)


# --- Wall gates ---

func _room_floor(size: Vector2i) -> Dictionary:
	var floor_tiles := {}
	for y in size.y:
		for x in size.x:
			floor_tiles[Vector2i(x, y)] = true
	return floor_tiles


func test_gates_sit_on_the_outer_walls_away_from_doors_and_props() -> void:
	var size := Vector2i(15, 9)
	var reachable := _room_floor(size)
	# Exit corridor north of column 7 and entrance south of column 7, as RoomTiles reports them.
	for y in [-1, -2, -3]:
		reachable[Vector2i(7, y)] = true
	reachable[Vector2i(7, 9)] = true
	var doors: Array[Vector2i] = [Vector2i(7, 9), Vector2i(7, -1)]
	var props: Array[Vector2] = [Vector2(64, -64)]
	var gates := WallGates.find_gates(reachable, size, doors, props)
	assert_gt(gates.size(), 20)
	assert_eq(WallGates.count_sides(gates), 4)
	for gate in gates:
		assert_false(Rect2i(Vector2i.ZERO, size).has_point(gate.wall_tile), "wall tile outside the floor")
		assert_true(reachable.has(gate.floor_tile))
		if gate.side == WallGates.Side.NORTH or gate.side == WallGates.Side.SOUTH:
			assert_true(absi(gate.wall_tile.x - 7) > 1, "no gate beside a door (%s)" % gate.wall_tile)
		assert_false(gate.wall_tile == Vector2i(0, -1) or gate.wall_tile == Vector2i(1, -1), "torch tiles stay intact")


func test_pick_keeps_the_minimum_distance_and_uses_two_walls() -> void:
	var size := Vector2i(15, 9)
	var gates := WallGates.find_gates(_room_floor(size), size, [] as Array[Vector2i], [] as Array[Vector2])
	# A player right next to the west wall and one in the north east corner (coop).
	var players: Array[Vector2] = [Vector2(40, 288), Vector2(900, 40)]
	for seed_value in 30:
		var picked := WallGates.pick(gates, 4, players, WaveRules.MIN_PLAYER_DISTANCE, WaveRules.MIN_SIDES, _rng(seed_value))
		assert_eq(picked.size(), 4)
		assert_gte(WallGates.count_sides(picked), 2, "at least two walls")
		for gate in picked:
			assert_gte(WaveRules.distance_to_nearest(gate.get_floor_position(), players), WaveRules.MIN_PLAYER_DISTANCE)


func test_pick_spreads_an_ambush_over_three_walls() -> void:
	var size := Vector2i(15, 9)
	var gates := WallGates.find_gates(_room_floor(size), size, [] as Array[Vector2i], [] as Array[Vector2])
	for seed_value in 20:
		var picked := WallGates.pick(gates, 3, [] as Array[Vector2], WaveRules.MIN_PLAYER_DISTANCE, WaveRules.AMBUSH_MIN_SIDES, _rng(seed_value))
		assert_gte(WallGates.count_sides(picked), 3)


func test_pick_falls_back_to_far_walls_when_players_crowd_the_gates() -> void:
	var size := Vector2i(4, 3)
	var gates := WallGates.find_gates(_room_floor(size), size, [] as Array[Vector2i], [] as Array[Vector2])
	# Players everywhere: no gate keeps 96 px, the room still gets its enemies from two walls.
	var players: Array[Vector2] = [Vector2(32, 96), Vector2(224, 96), Vector2(128, 32), Vector2(128, 160)]
	var picked := WallGates.pick(gates, 3, players, WaveRules.MIN_PLAYER_DISTANCE, WaveRules.MIN_SIDES, _rng(3))
	assert_eq(picked.size(), 3)
	assert_gte(WallGates.count_sides(picked), 2)


func test_fixed_gates_are_spread_and_apart() -> void:
	var size := Vector2i(19, 11)
	var gates := WallGates.find_gates(_room_floor(size), size, [] as Array[Vector2i], [] as Array[Vector2])
	var placed := WallGates.place(gates, ArenaWaves.GATE_COUNT, WaveRules.MIN_SIDES, _rng(4))
	assert_eq(placed.size(), ArenaWaves.GATE_COUNT)
	assert_gte(WallGates.count_sides(placed), WaveRules.MIN_SIDES)
	for i in placed.size():
		for j in range(i + 1, placed.size()):
			var gap := (placed[i].wall_tile - placed[j].wall_tile).abs()
			assert_gte(maxi(gap.x, gap.y), WallGates.GATE_SPACING)


# --- Spawner ---

func test_spawner_accepts_more_than_five_markers() -> void:
	var spawner := _spawner()
	var container: Node2D = autofree(Node2D.new())
	var spawned := spawner.spawn_encounter(8, RoomSequence.RoomType.COMBAT, _markers(8), Vector2.ZERO, container, _context())
	var limits := RoomSequence.get_enemy_count_range(8)
	assert_between(spawned.size(), limits.x, limits.y)
	assert_eq(spawner.last_overflow, 0)


func test_spawner_reports_overflow_beyond_the_markers() -> void:
	var spawner := _spawner()
	var group := EncounterGroup.new()
	group.count_range = Vector2i(9, 9)
	spawner.encounter_group = group
	var container: Node2D = autofree(Node2D.new())
	var spawned := spawner.spawn_encounter(8, RoomSequence.RoomType.COMBAT, _markers(6), Vector2.ZERO, container, _context())
	assert_eq(spawned.size(), 6, "one enemy per marker")
	assert_eq(spawner.last_overflow, 3, "the rest is left for an extra wave")


func test_count_follows_the_group_range_and_factor() -> void:
	var spawner := _spawner()
	var rng := _rng(2)
	var limits := RoomSequence.get_enemy_count_range(8)
	for i in 50:
		assert_between(spawner.roll_enemy_count(8, rng), limits.x, limits.y)
		assert_gte(spawner.roll_enemy_count(2, rng, 2), 2, "arena minimum")
	var group := EncounterGroup.new()
	group.count_range = Vector2i(1, 2)
	group.count_factor = 2.8
	spawner.encounter_group = group
	for i in 50:
		assert_has([3, 6], spawner.roll_enemy_count(8, rng), "1-2 enemies x 2.8 (D-084, 4 players)")


func test_group_filters_the_enemy_table() -> void:
	var group := EncounterGroup.new()
	group.attack_kind = EnemyData.AttackKind.RANGED
	var types: Array[EnemyData] = [SLIME, SKELETON, ARCHER]
	var weights: Array[float] = [0.5, 0.35, 0.15]
	var table := group.filter_table(types, weights)
	assert_eq(table[0], [ARCHER] as Array[EnemyData])
	assert_eq(table[1], [0.15] as Array[float])
	# A theme that matches nothing keeps the whole table: a room never stays empty.
	group.tags.assign([&"no_such_tag"])
	assert_eq((group.filter_table(types, weights)[0] as Array).size(), 3)


func test_spawner_uses_the_group_types_and_health() -> void:
	var spawner := _spawner()
	var group := EncounterGroup.new()
	group.attack_kind = EnemyData.AttackKind.RANGED
	group.allow_extra_types = false
	group.allow_elites = false
	spawner.encounter_group = group
	var container: Node2D = add_child_autofree(Node2D.new())
	var reference: Array[Enemy] = spawner.spawn_enemies(8, [Vector2.ZERO] as Array[Vector2], container, _context())
	var plain_health := reference[0].health.get_max_health()
	group.health_factor = 2.0
	var positions: Array[Vector2] = [Vector2.ZERO, Vector2(64, 0), Vector2(128, 0), Vector2(192, 0)]
	var spawned := spawner.spawn_enemies(8, positions, container, _context())
	assert_eq(spawned.size(), 4)
	for enemy in spawned:
		assert_eq(enemy.data, ARCHER, "ranged theme")
		assert_eq(enemy.elite, Enemy.Elite.NONE, "elites switched off")
		assert_almost_eq(enemy.health.get_max_health(), plain_health * 2.0, 0.01, "quiet room: more HP each")

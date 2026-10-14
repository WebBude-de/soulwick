extends GutTest
## Enemy sources (R2): pure rules (which sources a push uses, timing), the source node (rest,
## warning, opening, rest) and the emerge phase of the enemy (hidden, passive, invulnerable).

const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
## Loaded when needed: a preload here would make this script the first to load the enemy scene
## when it runs alone, which trips over the old load cycle enemy_base -> variants -> enemy_base.
const ENEMY_SCENE_PATH := "res://enemies/enemy_base.tscn"
const Kind := SpawnSourceRules.Kind

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_spawn_source_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _rng(seed_value := 5) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _no_groups(count: int) -> Array[int]:
	var groups: Array[int] = []
	for i in count:
		groups.append(-1)
	return groups


func _enemy() -> Enemy:
	var enemy := (load(ENEMY_SCENE_PATH) as PackedScene).instantiate() as Enemy
	enemy.data = SKELETON
	enemy.apply_scaling(3, false)
	add_child_autofree(enemy)
	return enemy


# --- Marker contract ---

func test_marker_ids_and_wall_sides_are_read() -> void:
	assert_eq(SpawnSourceRules.kind_from_id("grave"), Kind.GRAVE)
	assert_eq(SpawnSourceRules.kind_from_id(&"sarcophagus"), Kind.SARCOPHAGUS)
	assert_eq(SpawnSourceRules.kind_from_id(" Rift_Wall "), Kind.RIFT_WALL)
	assert_eq(SpawnSourceRules.kind_from_id("gate"), Kind.GATE)
	assert_eq(SpawnSourceRules.kind_from_id("lava"), -1)
	assert_eq(SpawnSourceRules.kind_id(Kind.VENT), &"vent")
	assert_eq(SpawnSourceRules.side_from_meta("north"), RoomTiles.DoorSide.NORTH)
	assert_eq(SpawnSourceRules.side_from_meta(&"West"), RoomTiles.DoorSide.WEST)
	assert_eq(SpawnSourceRules.side_from_meta(1), RoomTiles.DoorSide.EAST)
	assert_eq(SpawnSourceRules.side_from_meta("2"), RoomTiles.DoorSide.SOUTH)
	assert_eq(SpawnSourceRules.side_from_meta(null), -1)
	assert_eq(SpawnSourceRules.side_from_meta("up"), -1)
	assert_true(SpawnSourceRules.is_wall_kind(Kind.GATE))
	assert_true(SpawnSourceRules.is_wall_kind(Kind.RIFT_WALL))
	assert_false(SpawnSourceRules.is_wall_kind(Kind.GRAVE))


func test_every_biome_has_its_floor_source_and_sound() -> void:
	assert_eq(SpawnSourceRules.biome_kind(&"crypt"), Kind.GRAVE)
	assert_eq(SpawnSourceRules.biome_kind(&"slime_grotto"), Kind.PUDDLE)
	assert_eq(SpawnSourceRules.biome_kind(&"shadow_realm"), Kind.RIFT)
	assert_eq(SpawnSourceRules.biome_kind(&"ember_forge"), Kind.VENT)
	assert_eq(SpawnSourceRules.biome_kind(&"unknown"), Kind.GRAVE)
	for kind in Kind.values():
		assert_true(String(SpawnSourceRules.sound_for(kind)).begins_with("spawn_"), "R9 sound name for %d" % kind)


# --- Choice ---

func test_a_push_never_uses_every_source() -> void:
	assert_eq(SpawnSourceRules.max_active(1), 1, "a single source is all there is")
	assert_eq(SpawnSourceRules.max_active(2), 2, "two sources: both, several beats never all")
	assert_eq(SpawnSourceRules.max_active(3), 2)
	for total in range(3, 15):
		assert_lt(SpawnSourceRules.max_active(total), total, "%d sources" % total)
		assert_gte(SpawnSourceRules.max_active(total), 2)
		assert_eq(SpawnSourceRules.capacity(total), SpawnSourceRules.max_active(total) * SpawnSourceRules.PER_SOURCE)
	assert_eq(SpawnSourceRules.sources_for(1, 6, 6), 1)
	assert_eq(SpawnSourceRules.sources_for(2, 6, 6), 2, "two enemies come out of two sources")
	assert_eq(SpawnSourceRules.sources_for(4, 6, 6), 3, "four enemies from three sides")
	assert_eq(SpawnSourceRules.sources_for(8, 10, 10), 4, "two per source")
	assert_eq(SpawnSourceRules.sources_for(6, 1, 10), 1, "only one usable source")
	assert_eq(SpawnSourceRules.sources_for(0, 5, 5), 0)


func test_behind_beats_beside_beats_in_front() -> void:
	var players: Array[Vector2] = [Vector2.ZERO]
	var fronts: Array[Vector2] = [Vector2.RIGHT]
	assert_eq(SpawnSourceRules.direction_weight(Vector2(-300, 20), players, fronts), SpawnSourceRules.WEIGHT_BEHIND)
	assert_eq(SpawnSourceRules.direction_weight(Vector2(10, 300), players, fronts), SpawnSourceRules.WEIGHT_SIDE)
	assert_eq(SpawnSourceRules.direction_weight(Vector2(300, -20), players, fronts), SpawnSourceRules.WEIGHT_FRONT)
	assert_eq(SpawnSourceRules.direction_weight(Vector2(300, 0), players, [Vector2.ZERO] as Array[Vector2]), SpawnSourceRules.WEIGHT_SIDE, "unknown facing is neutral")
	assert_eq(SpawnSourceRules.direction_weight(Vector2(300, 0), [] as Array[Vector2], [] as Array[Vector2]), SpawnSourceRules.WEIGHT_SIDE)


func test_sources_behind_the_player_are_preferred() -> void:
	# Four sources behind (west) and four in front (east) of a player looking east.
	var spots: Array[Vector2] = []
	for i in 4:
		spots.append(Vector2(-400, -150 + i * 100))
	for i in 4:
		spots.append(Vector2(400, -150 + i * 100))
	var players: Array[Vector2] = [Vector2.ZERO]
	var fronts: Array[Vector2] = [Vector2.RIGHT]
	var behind := 0
	var total := 0
	for seed_value in 60:
		for index in SpawnSourceRules.pick(spots, _no_groups(spots.size()), 2, players, fronts, [] as Array[int], SpawnSourceRules.MIN_PLAYER_DISTANCE, _rng(seed_value)):
			total += 1
			if index < 4:
				behind += 1
	assert_gt(behind / float(total), 0.7, "mostly behind the player (%d of %d)" % [behind, total])


func test_no_source_close_to_any_player() -> void:
	var spots: Array[Vector2] = []
	for y in 4:
		for x in 6:
			spots.append(Vector2(64 + x * 160, 64 + y * 160))
	# Coop: two players in different corners.
	var players: Array[Vector2] = [Vector2(70, 70), Vector2(860, 540)]
	var fronts: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT]
	for seed_value in 40:
		var picked := SpawnSourceRules.pick(spots, _no_groups(spots.size()), 5, players, fronts, [] as Array[int], SpawnSourceRules.MIN_PLAYER_DISTANCE, _rng(seed_value))
		assert_eq(picked.size(), 5)
		for index in picked:
			assert_gte(WaveRules.distance_to_nearest(spots[index], players), SpawnSourceRules.MIN_PLAYER_DISTANCE)


func test_all_sources_too_close_still_uses_the_farthest() -> void:
	var spots: Array[Vector2] = [Vector2(10, 0), Vector2(60, 0), Vector2(-40, 0)]
	var players: Array[Vector2] = [Vector2.ZERO]
	var picked := SpawnSourceRules.pick(spots, _no_groups(3), 3, players, [Vector2.UP] as Array[Vector2], [] as Array[int], SpawnSourceRules.MIN_PLAYER_DISTANCE, _rng())
	assert_eq(picked, [1, 1, 1] as Array[int], "the farthest one, enemies queue")


func test_several_sources_but_never_all_and_enemies_queue() -> void:
	var spots: Array[Vector2] = []
	for i in 5:
		spots.append(Vector2(300 + i * 200, 500))
	for seed_value in 20:
		var picked := SpawnSourceRules.pick(spots, _no_groups(5), 10, [] as Array[Vector2], [] as Array[Vector2], [] as Array[int], 0.0, _rng(seed_value))
		assert_eq(picked.size(), 10)
		var distinct := {}
		for index in picked:
			distinct[index] = true
		assert_eq(distinct.size(), SpawnSourceRules.max_active(5), "three of five sources")
	var two := SpawnSourceRules.pick(spots, _no_groups(5), 2, [] as Array[Vector2], [] as Array[Vector2], [] as Array[int], 0.0, _rng())
	assert_ne(two[0], two[1], "two enemies, two sources")


func test_the_next_push_takes_other_sources() -> void:
	var spots: Array[Vector2] = []
	var groups: Array[int] = []
	for i in 6:
		spots.append(Vector2(100 + i * 150, 0))
		groups.append(WallGates.Side.NORTH if i < 3 else WallGates.Side.EAST)
	for seed_value in 20:
		var first := SpawnSourceRules.pick(spots, groups, 4, [] as Array[Vector2], [] as Array[Vector2], [] as Array[int], 0.0, _rng(seed_value))
		var used: Array[int] = []
		for index in first:
			if not used.has(index):
				used.append(index)
		var second := SpawnSourceRules.pick(spots, groups, 4, [] as Array[Vector2], [] as Array[Vector2], used, 0.0, _rng(seed_value + 100))
		for index in second:
			assert_false(used.has(index), "wave 2 uses other gates (seed %d)" % seed_value)


func test_gates_spread_over_two_walls() -> void:
	var spots: Array[Vector2] = []
	var groups: Array[int] = []
	for i in 4:
		spots.append(Vector2(100 + i * 120, 0))
		groups.append(WallGates.Side.NORTH)
	spots.append(Vector2(800, 300))
	groups.append(WallGates.Side.EAST)
	var players: Array[Vector2] = [Vector2(300, 400)]
	# Facing north: the north gates are "in front", the east gate beside - it still gets a turn.
	for seed_value in 20:
		var picked := SpawnSourceRules.pick(spots, groups, 4, players, [Vector2.UP] as Array[Vector2], [] as Array[int], 0.0, _rng(seed_value))
		var walls := {}
		for index in picked:
			walls[groups[index]] = true
		assert_eq(walls.size(), 2, "from two walls")


func test_the_choice_draws_the_same_numbers_wherever_players_stand() -> void:
	var spots: Array[Vector2] = []
	for i in 7:
		spots.append(Vector2(i * 150, 0))
	var a := _rng(77)
	var b := _rng(77)
	SpawnSourceRules.pick(spots, _no_groups(7), 3, [Vector2(0, 0)] as Array[Vector2], [Vector2.RIGHT] as Array[Vector2], [] as Array[int], 160.0, a)
	SpawnSourceRules.pick(spots, _no_groups(7), 5, [Vector2(900, 0), Vector2(400, 0)] as Array[Vector2], [Vector2.ZERO, Vector2.UP] as Array[Vector2], [2] as Array[int], 160.0, b)
	assert_eq(a.randi(), b.randi(), "stable RNG stream")


func test_timing_warns_one_second_and_staggers_the_sources() -> void:
	assert_eq(SpawnSourceRules.WARN_TIME, 1.0, "design answer: 1 s warning")
	assert_almost_eq(SpawnSourceRules.emerge_start(0, 0), SpawnSourceRules.WARN_TIME, 0.001)
	assert_almost_eq(SpawnSourceRules.emerge_start(1, 0), SpawnSourceRules.SOURCE_STAGGER + SpawnSourceRules.WARN_TIME, 0.001)
	assert_almost_eq(SpawnSourceRules.emerge_start(0, 1), SpawnSourceRules.WARN_TIME + SpawnSourceRules.SAME_SOURCE_DELAY, 0.001)
	assert_almost_eq(SpawnSourceRules.release_time(1, 1), SpawnSourceRules.WARN_TIME + SpawnSourceRules.EMERGE_TIME, 0.001)
	assert_eq(SpawnSourceRules.queue_offset(0), Vector2.ZERO)
	assert_ne(SpawnSourceRules.queue_offset(1), SpawnSourceRules.queue_offset(2))


# --- Source node ---

func test_floor_sources_use_the_delivered_art() -> void:
	for kind in [Kind.GRAVE, Kind.SARCOPHAGUS, Kind.PUDDLE, Kind.RIFT, Kind.VENT]:
		var source: SpawnSource = add_child_autofree(SpawnSource.create_floor(kind, Vector2(96, 96)))
		var art := source.get_node_or_null("Art") as AnimatedSprite2D
		if SpawnSource.has_art(kind):
			assert_not_null(art, "art for %s" % SpawnSourceRules.kind_id(kind))
			assert_eq(art.frame, SpawnSource.ART[kind]["idle"], "rest frame before use")
		else:
			assert_null(art, "drawn fallback without the file")
		assert_eq(source.z_index, -1 if SpawnSource.FLAT_KINDS.has(kind) else 0)
		assert_eq(source.phase, SpawnSource.Phase.IDLE)


func test_wall_sources_sit_between_wall_and_floor() -> void:
	var gate: SpawnSource = add_child_autofree(SpawnSource.create_wall(Kind.GATE, WallGates.Side.NORTH, Vector2i(4, -1), Vector2i(4, 0)))
	assert_not_null(gate.get_node_or_null("Opening"), "the arena gate look (WallBreach)")
	assert_eq(gate.spot, RoomTiles.tile_center(Vector2i(4, 0)))
	assert_eq(gate.hold, RoomTiles.tile_center(Vector2i(4, -1)))
	assert_eq(gate.get_group(), WallGates.Side.NORTH)
	assert_eq(gate.get_emerge_style(), Enemy.Emerge.STEP)
	var rift: SpawnSource = add_child_autofree(SpawnSource.create_wall(Kind.RIFT_WALL, WallGates.Side.WEST, Vector2i(-1, 3), Vector2i(0, 3)))
	assert_eq((rift.get_node("Opening") as WallBreach).mode, WallBreach.Mode.BREACH)


func test_a_source_warns_then_opens_then_rests() -> void:
	var source: SpawnSource = add_child_autofree(SpawnSource.create_floor(Kind.GRAVE, Vector2(200, 200)))
	source.play(0.0, 2)
	await wait_frames(2)
	assert_eq(source.phase, SpawnSource.Phase.WARN)
	assert_true(source.is_active())
	assert_not_null(source.get_node_or_null("Warning"), "warning light")
	await wait_seconds(SpawnSourceRules.WARN_TIME + 0.1)
	assert_eq(source.phase, SpawnSource.Phase.OPEN, "first enemy comes out")
	await wait_seconds(SpawnSourceRules.SAME_SOURCE_DELAY + SpawnSourceRules.EMERGE_TIME + 0.1)
	assert_eq(source.phase, SpawnSource.Phase.REST)
	assert_false(source.is_active())
	assert_eq(source.uses, 1)
	source.go_quiet()
	assert_true(source.quiet)


# --- Enemy emerge phase ---

func test_an_emerging_enemy_is_hidden_passive_and_invulnerable() -> void:
	var enemy := _enemy()
	await wait_frames(1)
	var layer := enemy.collision_layer
	watch_signals(enemy)
	enemy.begin_emerge(0.3, 0.2)
	assert_true(enemy.is_emerging())
	assert_true(enemy.is_hidden_in_source())
	assert_true(enemy.is_in_intro(), "passive")
	assert_true(enemy.hurtbox.is_invulnerable())
	assert_false(enemy.visible)
	assert_eq(enemy.collision_layer, 0, "nobody bumps into it")
	await wait_seconds(0.4)
	assert_true(enemy.visible, "rising")
	assert_true(enemy.is_in_intro(), "still passive while rising")
	assert_false(enemy.is_hidden_in_source())
	await wait_seconds(0.25)
	assert_false(enemy.is_emerging())
	assert_false(enemy.is_in_intro(), "fights")
	assert_false(enemy.hurtbox.is_invulnerable())
	assert_eq(enemy.collision_layer, layer)
	assert_signal_emit_count(enemy, "intro_ended", 1)


func test_an_enemy_killed_in_its_source_dies_visibly() -> void:
	var enemy := _enemy()
	await wait_frames(1)
	enemy.begin_emerge(5.0, 0.5)
	enemy.health.take_damage(INF)
	assert_true(enemy.is_dead())
	assert_false(enemy.is_emerging())
	assert_true(enemy.visible)
	assert_false(enemy.is_in_intro())


func test_a_gate_moves_its_enemy_out_of_the_wall() -> void:
	var room: Node2D = add_child_autofree(Node2D.new())
	var gate := SpawnSource.create_wall(Kind.GATE, WallGates.Side.NORTH, Vector2i(3, -1), Vector2i(3, 0))
	room.add_child(gate)
	var enemy := _enemy()
	await wait_frames(1)
	gate.bring(enemy, room, 0.2, 0)
	assert_almost_eq(enemy.global_position.distance_to(room.to_global(gate.hold)), 0.0, 0.5, "waits in the wall")
	await wait_seconds(0.2 + SpawnSourceRules.EMERGE_TIME + 0.15)
	assert_almost_eq(enemy.global_position.distance_to(room.to_global(gate.spot)), 0.0, 1.0, "stands on the floor")
	assert_false(enemy.is_in_intro())

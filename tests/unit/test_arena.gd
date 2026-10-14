extends GutTest
## Arena rooms in the tree (A5): gates in the walls, waves at <= 1 enemy left, enemies stepping
## out of the walls away from the players, the ambush starting with the closing door, overflow
## waves in normal rooms and completion only after the last wave.

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_arena_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _other_kind() -> int:
	for kind in RoomSequence.RoomKind.values():
		if kind != RoomSequence.RoomKind.ARENA:
			return kind
	return -1


## A combat room with skeletons only (no splitting slimes), fixed RNG seed and an optional group.
func _room(arena := true, ambush := 0, room_index := 8, group: EncounterGroup = null) -> RoomController:
	var room := HALL.instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.ARENA if arena else _other_kind() as RoomSequence.RoomKind
	room.forced_ambush = ambush
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 31
	room.setup(room_index, RoomSequence.RoomType.COMBAT, -1, false, context)
	var spawner := room.get_node("EnemySpawner") as EnemySpawner
	spawner.biomes = [] as Array[BiomeData]
	spawner.extra_types = [] as Array[EnemyData]
	spawner.enemy_types = [SKELETON] as Array[EnemyData]
	spawner.spawn_weights = [1.0] as Array[float]
	if group == null:
		group = EncounterGroup.new()
		group.allow_elites = false
	spawner.encounter_group = group
	add_child_autofree(room)
	return room


func _fixed_count(count: int) -> EncounterGroup:
	var group := EncounterGroup.new()
	group.count_range = Vector2i(count, count)
	group.allow_elites = false
	return group


func _living(room: RoomController) -> Array[Enemy]:
	var living: Array[Enemy] = []
	for child in room.enemy_container.get_children():
		var enemy := child as Enemy
		if enemy != null and not enemy.is_dead():
			living.append(enemy)
	return living


func _kill(enemy: Enemy) -> void:
	enemy.health.take_damage(INF)


func test_plain_arena_shows_gates_on_two_walls_before_the_fight() -> void:
	var room := _room()
	await wait_frames(2)
	assert_true(room.is_arena)
	assert_false(room.is_ambush)
	var arena := room.get_arena_waves()
	assert_not_null(arena)
	var gates := arena.get_fixed_gates()
	assert_eq(gates.size(), ArenaWaves.GATE_COUNT)
	assert_gte(WallGates.count_sides(gates), 2)
	for gate in gates:
		assert_not_null(arena.get_view(gate), "every gate is visible")
	assert_false(room.is_encounter_started())


func test_rooms_one_to_five_and_normal_kinds_are_no_arena() -> void:
	assert_false(_room(true, 0, 4).is_arena, "rooms 1-5 are normal (D-100)")
	assert_false(_room(false, 0, 8).is_arena)
	assert_null(_room(false, 0, 8).get_arena_waves())


func test_arena_plans_two_waves_and_three_deeper() -> void:
	var room := _room()
	room.activate()
	assert_eq(room.get_wave_progress(), Vector2i(1, 2))
	for size in room.get_wave_sizes():
		assert_gte(size, WaveRules.ARENA_MIN_WAVE_SIZE)
	var deep := _room(true, 0, 16)
	deep.activate()
	assert_eq(deep.get_wave_progress().y, 3)


func test_next_wave_starts_when_one_enemy_is_left() -> void:
	var room := _room(true, 0, 8, _fixed_count(3))
	watch_signals(room)
	room.activate()
	assert_signal_emitted_with_parameters(room, "arena_started", [room, false])
	assert_false(room.is_ambush_room())
	var first := _living(room)
	assert_eq(first.size(), 3)
	_kill(first[0])
	await wait_frames(2)
	assert_eq(room.get_wave_progress().x, 1, "two of wave 1 left: no new wave")
	assert_signal_not_emitted(room, "wave_started")
	_kill(first[1])
	await wait_frames(2)
	assert_eq(room.get_wave_progress().x, 2, "one left: wave 2 comes")
	assert_signal_emitted_with_parameters(room, "wave_started", [room, 2, 2])
	assert_eq(_living(room).size(), 1 + 3, "the straggler plus wave 2")


func test_room_counts_as_cleared_only_after_the_last_wave() -> void:
	var room := _room(true, 0, 16, _fixed_count(2))
	watch_signals(room)
	room.activate()
	for wave in range(1, 4):
		assert_eq(room.get_wave_progress().x, wave)
		for enemy in _living(room):
			_kill(enemy)
		await wait_frames(2)
		if wave < 3:
			assert_signal_not_emitted(room, "completed", "wave %d of 3 cleared" % wave)
	assert_signal_emit_count(room, "completed", 1)
	assert_eq(room.state, RoomController.State.CLEARED)


func test_enemies_wait_in_the_wall_and_step_out() -> void:
	var room := _room(true, 0, 8, _fixed_count(2))
	room.activate()
	var enemies := _living(room)
	var gates := room.get_arena_waves().get_last_gates()
	assert_eq(gates.size(), 2)
	for i in enemies.size():
		assert_false(enemies[i].visible, "hidden in the wall")
		assert_true(enemies[i].is_in_intro(), "passive and invulnerable while coming out")
		assert_almost_eq(enemies[i].position.distance_to(gates[i].get_wall_position()), 0.0, 0.5)
	await wait_seconds(ArenaWaves.get_release_time(2) + 0.2)
	for i in enemies.size():
		assert_true(enemies[i].visible)
		assert_false(enemies[i].is_in_intro(), "fights once out")


func test_gates_keep_the_distance_to_every_player() -> void:
	var first: Player = add_child_autofree(PLAYER_SCENE.instantiate())
	var second: Player = add_child_autofree(PLAYER_SCENE.instantiate())
	var room := _room(true, 0, 8, _fixed_count(4))
	await wait_frames(2)
	# One player at the west wall, one at the north wall.
	first.global_position = room.to_global(Vector2(40, 288))
	second.global_position = room.to_global(Vector2(480, 40))
	room.activate()
	var gates := room.get_arena_waves().get_last_gates()
	assert_eq(gates.size(), 4)
	assert_gte(WallGates.count_sides(gates), 2, "from at least two walls")
	for gate in gates:
		var spot := room.to_global(gate.get_floor_position())
		assert_gte(spot.distance_to(first.global_position), WaveRules.MIN_PLAYER_DISTANCE)
		assert_gte(spot.distance_to(second.global_position), WaveRules.MIN_PLAYER_DISTANCE)


func test_ambush_looks_empty_and_starts_when_the_door_closes() -> void:
	var room := _room(true, 1, 8, _fixed_count(3))
	await wait_frames(2)
	assert_true(room.is_ambush_room())
	assert_true(room.is_arena_room())
	assert_eq(room.get_arena_waves().get_fixed_gates().size(), 0, "no gates: the room looks empty")
	assert_eq(room.get_arena_waves().get_child_count(), 0)
	watch_signals(room)
	# The door closing while the room is merely prepared springs nothing.
	room._entrance_door.close()
	assert_false(room.is_encounter_started())
	assert_signal_not_emitted(room, "arena_started")
	room._entrance_door.open()
	room.activate()
	assert_true(room.is_encounter_started(), "the closing entrance door springs the ambush")
	assert_signal_emitted_with_parameters(room, "arena_started", [room, true])
	assert_false(room._entrance_door.is_open)
	var gates := room.get_arena_waves().get_last_gates()
	assert_gte(WallGates.count_sides(gates), WaveRules.AMBUSH_MIN_SIDES, "from (almost) every wall")
	for enemy in _living(room):
		assert_false(enemy.visible)
	await wait_seconds(ArenaWaves.get_release_time(1, ArenaWaves.AMBUSH_DELAY) + 0.2)
	for enemy in _living(room):
		assert_true(enemy.visible)
	for gate in gates:
		assert_true(room.get_arena_waves().get_view(gate).is_broken, "the wall broke open")


func test_ambush_waits_for_the_door_and_not_for_activation() -> void:
	var room := _room(true, 1, 8, _fixed_count(2))
	await wait_frames(1)
	room.state = RoomController.State.ACTIVE
	assert_false(room.is_encounter_started())
	room._entrance_door.close()
	assert_true(room.is_encounter_started())


func test_overflow_becomes_an_extra_wave_in_a_normal_room() -> void:
	var room := _room(false, 0, 8, _fixed_count(8))
	var markers := room.get_spawn_markers().size()
	assert_eq(room._get_markers().size(), markers, "all markers go to the spawner")
	watch_signals(room)
	room.activate()
	assert_eq(room.get_wave_sizes(), RoomSequence.split_into_waves(8, markers))
	assert_eq(_living(room).size(), mini(8, markers))
	for enemy in _living(room):
		_kill(enemy)
	await wait_frames(2)
	assert_eq(room.get_wave_progress().x, 2, "the rest comes as an extra wave")
	assert_eq(_living(room).size(), 8 - markers)
	assert_signal_not_emitted(room, "completed")
	for enemy in _living(room):
		_kill(enemy)
	await wait_frames(2)
	assert_signal_emit_count(room, "completed", 1)


func test_normal_room_waits_for_its_wave_to_be_cleared() -> void:
	var room := _room(false, 0, 31, _fixed_count(3))
	room.activate()
	assert_eq(room.get_wave_progress(), Vector2i(1, 2), "D-074: two waves from room 30")
	var first := _living(room)
	_kill(first[0])
	_kill(first[1])
	await wait_frames(2)
	assert_eq(room.get_wave_progress().x, 1, "normal rooms wait for the last enemy")
	_kill(first[2])
	await wait_frames(2)
	assert_eq(room.get_wave_progress().x, 2)


func test_delivered_art_is_used_and_drawn_art_is_the_fallback() -> void:
	for mode in [WallBreach.Mode.GATE, WallBreach.Mode.BREACH]:
		for inward in [Vector2.DOWN, Vector2.RIGHT]:
			var view: WallBreach = add_child_autofree(WallBreach.new())
			view.setup(mode, inward, 3)
			var art := view.get_node_or_null("Art") as AnimatedSprite2D
			if WallBreach.has_art(mode):
				assert_not_null(art, "SPRITES_V5 art for mode %d" % mode)
			else:
				assert_null(art, "drawn fallback without the file")
	var breach: WallBreach = add_child_autofree(WallBreach.new())
	breach.setup(WallBreach.Mode.BREACH, Vector2.DOWN, 3)
	breach.burst(false)
	assert_true(breach.is_broken, "the hole stays")

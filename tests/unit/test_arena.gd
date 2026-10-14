extends GutTest
## Arena rooms in the tree (A5): wave plan, the next wave once the running one is cleared, overflow
## waves in normal rooms and completion only after the last wave. Where enemies come out (gates,
## other gates every wave, distance to the players) is tested with the sources (R2,
## test_spawn_source_room, test_spawn_source_flow); there is no ambush any more (D-120).

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
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
func _room(arena := true, ambush := 0, room_index := 12, group: EncounterGroup = null) -> RoomController:
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


func test_rooms_one_to_five_and_normal_kinds_are_no_arena() -> void:
	assert_false(_room(true, 0, 4).is_arena, "rooms 1-5 are normal (D-100)")
	assert_false(_room(false, 0, 8).is_arena)


func test_arena_plans_two_waves_and_three_deeper() -> void:
	var room := _room()
	room.activate()
	assert_eq(room.get_wave_progress(), Vector2i(1, 2))
	for size in room.get_wave_sizes():
		assert_gte(size, WaveRules.ARENA_MIN_WAVE_SIZE)
	var deep := _room(true, 0, 31)
	deep.activate()
	assert_eq(deep.get_wave_progress().y, 3)


func test_next_wave_starts_when_the_wave_is_cleared() -> void:
	var room := _room(true, 0, 12, _fixed_count(3))
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
	assert_eq(room.get_wave_progress().x, 1, "one left: still wave 1 (D-118)")
	_kill(first[2])
	await wait_frames(2)
	assert_eq(room.get_wave_progress().x, 2, "wave 1 cleared: wave 2 comes")
	assert_signal_emitted_with_parameters(room, "wave_started", [room, 2, 2])
	assert_eq(_living(room).size(), 3, "wave 2")


func test_room_counts_as_cleared_only_after_the_last_wave() -> void:
	var room := _room(true, 0, 31, _fixed_count(2))
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


func test_overflow_becomes_an_extra_wave_in_a_normal_room() -> void:
	var room := _room(false, 0, 8, _fixed_count(1))
	var markers := room.get_spawn_markers().size()
	assert_eq(room._get_markers().size(), markers, "all markers go to the spawner")
	# Places of one wave: the spawn markers, or with sources (R2) what one push of them brings.
	var sources := SpawnSources.of(room)
	var capacity := sources.get_capacity() if sources != null else markers
	var count := capacity + 2
	room.set_encounter_group(_fixed_count(count))
	watch_signals(room)
	room.activate()
	assert_eq(room.get_wave_sizes(), RoomSequence.split_into_waves(count, capacity))
	assert_eq(_living(room).size(), mini(count, capacity))
	for enemy in _living(room):
		_kill(enemy)
	await wait_frames(2)
	assert_eq(room.get_wave_progress().x, 2, "the rest comes as an extra wave")
	assert_eq(_living(room).size(), count - capacity)
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

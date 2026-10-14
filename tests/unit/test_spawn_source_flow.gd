extends GutTest
## Enemy sources in the room flow (R2): once RoomController calls SpawnSources.setup and spawns its
## waves through the sources, every enemy of a combat room, an arena and a champion room comes out
## of a source. Pending while the RoomController hook is not wired yet (integrator).

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_spawn_source_flow_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _other_kind() -> int:
	for kind in RoomSequence.RoomKind.values():
		if kind != RoomSequence.RoomKind.ARENA:
			return kind
	return -1


func _room(room_index := 8, arena := false, count := 3, room_type := RoomSequence.RoomType.COMBAT) -> RoomController:
	var room := HALL.instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.ARENA if arena else _other_kind() as RoomSequence.RoomKind
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 31
	room.setup(room_index, room_type, -1, false, context)
	var spawner := room.get_node("EnemySpawner") as EnemySpawner
	spawner.extra_types = [] as Array[EnemyData]
	spawner.enemy_types = [SKELETON] as Array[EnemyData]
	spawner.spawn_weights = [1.0] as Array[float]
	spawner.biomes = [] as Array[BiomeData]
	var group := EncounterGroup.new()
	group.count_range = Vector2i(count, count)
	group.allow_elites = false
	spawner.encounter_group = group
	add_child_autofree(room)
	return room


func _living(room: RoomController) -> Array[Enemy]:
	var living: Array[Enemy] = []
	for child in room.enemy_container.get_children():
		var enemy := child as Enemy
		if enemy != null and not enemy.is_dead():
			living.append(enemy)
	return living


## True once the RoomController builds its sources itself; marks the test pending otherwise.
func _wired(room: RoomController) -> bool:
	if SpawnSources.of(room) != null:
		return true
	pending("RoomController does not call SpawnSources.setup yet (R2 hook for the integrator)")
	return false


func test_a_combat_room_spawns_through_its_sources() -> void:
	var room := _room(8, false, 4)
	await wait_frames(1)
	if not _wired(room):
		return
	room.activate()
	var sources := SpawnSources.of(room)
	var used := sources.get_last_sources().size()
	assert_gte(used, mini(2, sources.get_pool().size()))
	for enemy in _living(room):
		assert_true(enemy.is_hidden_in_source(), "no enemy just stands there")
	await wait_seconds(SpawnSourceRules.release_time(used, ceili(4.0 / used)) + 0.2)
	for enemy in _living(room):
		assert_false(enemy.is_in_intro())


func test_the_wave_plan_follows_the_source_capacity() -> void:
	var room := _room(8, false, 12)
	await wait_frames(1)
	if not _wired(room):
		return
	room.activate()
	var capacity := SpawnSources.of(room).get_capacity()
	assert_eq(room.get_wave_sizes(), RoomSequence.split_into_waves(12, capacity))
	assert_eq(_living(room).size(), mini(12, capacity))


func test_an_arena_has_no_ambush_and_opens_other_gates_each_wave() -> void:
	var room := _room(12, true, 3)
	await wait_frames(2)
	if not _wired(room):
		return
	assert_false(room.is_ambush_room(), "no ambush any more (D-120)")
	room.activate()
	assert_true(room.is_encounter_started(), "starts on entry")
	var sources := SpawnSources.of(room)
	var first := sources.get_last_sources()
	for source in first:
		assert_eq(source.kind, SpawnSourceRules.Kind.GATE)
	for enemy in _living(room):
		enemy.health.take_damage(INF)
	await wait_frames(3)
	assert_eq(room.get_wave_progress().x, 2)
	for source in sources.get_last_sources():
		assert_false(first.has(source), "other gates")


func test_the_champion_comes_out_of_a_source() -> void:
	var room := _room(10, false, 3, RoomSequence.RoomType.MINIBOSS)
	await wait_frames(1)
	if not _wired(room):
		return
	room.activate()
	for enemy in _living(room):
		assert_true(enemy.is_emerging())

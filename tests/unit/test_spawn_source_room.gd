extends GutTest
## Enemy sources in real rooms (R2): fallback at the old spawn points in the biome's kind, the
## marker contract with the room plans (R1), arenas with gates only and other gates every wave,
## pushes out of several sources away from every player, elites and champions from sarcophagi.
## Uses SpawnSources directly, so it holds before and after the RoomController is wired.

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
const Kind := SpawnSourceRules.Kind
## Fixed step for the hand-stepped push timeline (s): one frame at 60 fps.
const TIMELINE_STEP := 1.0 / 60.0

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_spawn_source_room_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


## The source timelines are tweens: a hit stop left over from an earlier test file would slow them
## down (seen in the full run: "the first source warns at once" failed).
func before_each() -> void:
	HitStop.reset()


func _other_kind() -> int:
	for kind in RoomSequence.RoomKind.values():
		if kind != RoomSequence.RoomKind.ARENA:
			return kind
	return -1


## A combat hall; skeletons only unless keep_biomes; plan: marker specs [kind, position, side].
func _room(room_index := 8, arena := false, keep_biomes := false, plan: Array = [], room_type := RoomSequence.RoomType.COMBAT) -> RoomController:
	var room := HALL.instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.ARENA if arena else _other_kind() as RoomSequence.RoomKind
	room.forced_ambush = 0
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 31
	room.setup(room_index, room_type, -1, false, context)
	var spawner := room.get_node("EnemySpawner") as EnemySpawner
	if not keep_biomes:
		spawner.biomes = [] as Array[BiomeData]
	spawner.extra_types = [] as Array[EnemyData]
	spawner.enemy_types = [SKELETON] as Array[EnemyData]
	spawner.spawn_weights = [1.0] as Array[float]
	var group := EncounterGroup.new()
	group.allow_elites = false
	spawner.encounter_group = group
	# Plan templates (R1) bring their own sources: replaced, so every test knows its markers.
	var own := room.get_node_or_null("Sources")
	if own != null:
		room.remove_child(own)
		own.free()
	if not plan.is_empty():
		var holder := Node2D.new()
		holder.name = "Sources"
		for spec: Array in plan:
			var marker := Marker2D.new()
			marker.position = spec[1]
			marker.set_meta(&"source_kind", spec[0])
			if spec.size() > 2:
				marker.set_meta(&"wall_side", spec[2])
			if spec.size() > 4:
				marker.set_meta(&"tile", spec[3])
				marker.set_meta(&"floor_tile", spec[4])
			holder.add_child(marker)
		room.add_child(holder)
	add_child_autofree(room)
	return room


func _sources(room: RoomController) -> SpawnSources:
	var sources := SpawnSources.setup(room)
	sources.build()
	return sources


func _player_at(room: RoomController, local: Vector2) -> Player:
	var player: Player = add_child_autofree(PLAYER_SCENE.instantiate())
	player.global_position = room.to_global(local)
	return player


func test_rooms_without_markers_use_the_old_spawn_points_in_the_biome_look() -> void:
	var expected := {7: Kind.GRAVE, 22: Kind.PUDDLE, 37: Kind.RIFT, 52: Kind.VENT}
	for room_index: int in expected:
		var room := _room(room_index, false, true)
		var sources := _sources(room)
		assert_false(sources.from_markers, "fallback")
		var markers := room.get_spawn_markers()
		assert_eq(sources.get_sources().size(), markers.size(), "one source per old spawn point")
		for i in markers.size():
			var source := sources.get_sources()[i]
			assert_eq(source.kind, expected[room_index], "room %d" % room_index)
			assert_eq(source.spot, markers[i].position)
		assert_eq(sources.get_capacity(), maxi(SpawnSourceRules.capacity(markers.size()), markers.size()))


func test_setup_is_idempotent_and_only_for_rooms_with_an_encounter() -> void:
	var room := _room()
	var sources := SpawnSources.setup(room)
	assert_not_null(sources)
	assert_eq(SpawnSources.setup(room), sources, "same node again")
	assert_eq(SpawnSources.of(room), sources)
	assert_null(SpawnSources.setup(_room(8, false, false, [], RoomSequence.RoomType.BOSS)), "the boss has its intro")
	assert_null(SpawnSources.setup(_room(8, false, false, [], RoomSequence.RoomType.SPECIAL)))
	assert_not_null(SpawnSources.setup(_room(10, false, false, [], RoomSequence.RoomType.MINIBOSS)), "champion rooms")


func test_plan_markers_become_sources() -> void:
	var plan := [
		["grave", Vector2(96, 96)],
		["grave", Vector2(864, 480)],
		["sarcophagus", Vector2(480, 96)],
		# Gate in the north wall: marker in the wall tile (5, -1).
		["gate", RoomTiles.tile_center(Vector2i(5, -1)), "north"],
		# Wall rift in the east wall, marker on the floor tile in front of it.
		["rift_wall", RoomTiles.tile_center(Vector2i(14, 4)), 1],
		# As the R1 generator writes it: gate in a short inner wall, both tiles named, floor sources -1.
		["gate", RoomTiles.tile_center(Vector2i(7, 3)), 0, Vector2i(7, 3), Vector2i(7, 4)],
		["puddle", Vector2(480, 480), -1],
		["lava", Vector2(200, 200)],
	]
	var room := _room(8, false, false, plan)
	var sources := _sources(room)
	assert_true(sources.from_markers)
	assert_eq(sources.get_sources().size(), 7, "the unknown kind is skipped")
	var pool := sources.get_pool()
	assert_eq(pool.size(), 6, "sarcophagi wait for elites and champions")
	var gate: SpawnSource = null
	var inner_gate: SpawnSource = null
	var rift: SpawnSource = null
	for source in sources.get_sources():
		if source.kind == Kind.GATE and gate == null:
			gate = source
		elif source.kind == Kind.GATE:
			inner_gate = source
		elif source.kind == Kind.RIFT_WALL:
			rift = source
	assert_eq(inner_gate.wall_tile, Vector2i(7, 3))
	assert_eq(inner_gate.floor_tile, Vector2i(7, 4))
	assert_eq(inner_gate.side, WallGates.Side.NORTH)
	assert_eq(gate.wall_tile, Vector2i(5, -1))
	assert_eq(gate.floor_tile, Vector2i(5, 0))
	assert_eq(rift.wall_tile, Vector2i(15, 4))
	assert_eq(rift.floor_tile, Vector2i(14, 4))
	assert_eq(rift.spot, RoomTiles.tile_center(Vector2i(14, 4)))


func test_arena_uses_gates_only_and_other_gates_every_wave() -> void:
	var room := _room(12, true)
	await wait_frames(2)
	assert_true(room.is_arena_room())
	var sources := _sources(room)
	var pool := sources.get_pool()
	assert_eq(pool.size(), SpawnSourceRules.ARENA_GATE_COUNT)
	var sides := {}
	for source in pool:
		assert_eq(source.kind, Kind.GATE)
		sides[source.side] = true
	assert_gte(sides.size(), 2, "gates in at least two walls")
	var first := sources.choose(4)
	var second := sources.choose(4)
	for source in second:
		assert_false(first.has(source), "wave 2 opens other gates")


func test_arena_plan_with_floor_sources_still_uses_only_its_gates() -> void:
	var plan := [
		["gate", RoomTiles.tile_center(Vector2i(3, -1)), "north"],
		["gate", RoomTiles.tile_center(Vector2i(11, -1)), "north"],
		["gate", RoomTiles.tile_center(Vector2i(-1, 4)), "west"],
		["grave", Vector2(480, 288)],
	]
	var room := _room(12, true, false, plan)
	await wait_frames(1)
	var sources := _sources(room)
	assert_true(sources.from_markers)
	assert_eq(sources.get_pool().size(), 3)
	for source in sources.choose(5):
		assert_eq(source.kind, Kind.GATE)


func test_a_wave_comes_out_of_several_sources_away_from_the_player() -> void:
	var room := _room(8)
	await wait_frames(1)
	var player := _player_at(room, Vector2(480, 288))
	var sources := _sources(room)
	watch_signals(sources)
	var enemies := sources.spawn_wave(room.spawner, 4, room.enemy_container, room.context, room.get_arena())
	assert_eq(enemies.size(), 4)
	var used := sources.get_last_sources()
	assert_gte(used.size(), 2, "several sources")
	assert_lt(used.size(), sources.get_pool().size(), "never all at once")
	for enemy in enemies:
		assert_true(enemy.is_hidden_in_source(), "nobody stands there yet")
		assert_true(enemy.is_in_intro())
		assert_gte(enemy.global_position.distance_to(player.global_position), SpawnSourceRules.MIN_PLAYER_DISTANCE - SpawnSourceRules.QUEUE_SPREAD * 2.0)
	# The timelines (source pushes, enemy emerges) are tweens on the frame time: under load one slow
	# frame jumped past the stagger or the whole warning and the test flickered. Paused and stepped
	# by hand in fixed steps, the same push plays the same way on every machine.
	var tweens: Array[Tween] = []
	for source in used:
		assert_not_null(source.get_timeline(), "every used source plays a push")
		tweens.append(source.get_timeline())
	var out_at := {}
	var clock := [0.0]
	for enemy in enemies:
		# Enemy.begin_emerge keeps its timeline here (no getter in the hotspot enemy_base.gd).
		var emerge: Tween = enemy.get(&"_emerge_tween")
		assert_not_null(emerge, "every enemy waits on its emerge timeline")
		tweens.append(emerge)
		enemy.intro_ended.connect(func(out: Enemy) -> void: out_at[out] = clock[0])
	for tween in tweens:
		tween.pause()
	var warned_at := {}
	var opened_at := {}
	var per_source := ceili(float(enemies.size()) / float(used.size()))
	var end_time := SpawnSourceRules.release_time(used.size(), per_source) + 0.5
	while clock[0] < end_time:
		clock[0] += TIMELINE_STEP
		for tween in tweens:
			if tween.is_valid():
				tween.custom_step(TIMELINE_STEP)
		for source in used:
			if source.phase == SpawnSource.Phase.WARN and not warned_at.has(source):
				warned_at[source] = clock[0]
			elif source.phase == SpawnSource.Phase.OPEN and not opened_at.has(source):
				opened_at[source] = clock[0]
		if clock[0] <= TIMELINE_STEP:
			assert_eq(used[0].phase, SpawnSource.Phase.WARN, "the first source warns at once")
			assert_eq(used[1].phase, SpawnSource.Phase.IDLE, "the next one a moment later")
	assert_eq(warned_at.size(), used.size(), "every source warned")
	assert_eq(opened_at.size(), used.size(), "every source opened")
	for i in range(1, used.size()):
		assert_almost_eq(float(warned_at[used[i]]) - float(warned_at[used[i - 1]]), SpawnSourceRules.SOURCE_STAGGER, TIMELINE_STEP * 1.5, "the sources light up one after the other")
	var last_warning: float = warned_at.values().max()
	var first_opening: float = opened_at.values().min()
	assert_lt(last_warning, first_opening, "every source warns before anyone comes out")
	for source in used:
		assert_almost_eq(float(opened_at[source]) - float(warned_at[source]), SpawnSourceRules.WARN_TIME, TIMELINE_STEP * 1.5, "the whole warning plays")
	assert_eq(out_at.size(), enemies.size(), "everyone came out")
	for enemy in enemies:
		assert_true(enemy.visible)
		assert_false(enemy.is_in_intro(), "fights once out")
		assert_gte(float(out_at.get(enemy, 0.0)), SpawnSourceRules.WARN_TIME + SpawnSourceRules.EMERGE_TIME - TIMELINE_STEP, "nobody out before warning and rise")
		assert_lte(float(out_at.get(enemy, INF)), SpawnSourceRules.release_time(used.size(), per_source) + TIMELINE_STEP * 1.5, "everyone out in time")
	assert_signal_emit_count(sources, "enemy_emerged", 4)


func test_elites_take_a_free_sarcophagus() -> void:
	var plan := [
		["grave", Vector2(96, 96)],
		["grave", Vector2(864, 96)],
		["grave", Vector2(96, 480)],
		["sarcophagus", Vector2(864, 480)],
	]
	var room := _room(8, false, false, plan)
	await wait_frames(1)
	var sources := _sources(room)
	var chosen := sources.choose(2)
	var positions: Array[Vector2] = [chosen[0].spot, chosen[1].spot]
	var enemies := room.spawner.spawn_enemies(8, positions, room.enemy_container, room.context)
	enemies[1].elite = Enemy.Elite.ARMORED
	sources._give_sarcophagi_to_elites(enemies, chosen)
	assert_eq(chosen[1].kind, Kind.SARCOPHAGUS, "the elite comes out of the sarcophagus")
	assert_eq(chosen[0].kind, Kind.GRAVE)


func test_the_champion_rises_from_a_sarcophagus() -> void:
	var room := _room(10, false, true, [], RoomSequence.RoomType.MINIBOSS)
	await wait_frames(1)
	var enemies := room.spawner.spawn_encounter(10, RoomSequence.RoomType.MINIBOSS, room.get_spawn_markers(), room.content_anchor.position, room.enemy_container, room.context, room.get_arena())
	var sources := _sources(room)
	sources.release_encounter(enemies)
	var champion: Enemy = null
	for enemy in enemies:
		assert_true(enemy.is_emerging(), "everyone comes out of a source")
		if enemy.is_miniboss:
			champion = enemy
	assert_not_null(champion)
	var sarcophagus: SpawnSource = null
	for source in sources.get_sources():
		if source.kind == Kind.SARCOPHAGUS:
			sarcophagus = source
	assert_not_null(sarcophagus, "crypt champion: a sarcophagus where it stands")
	assert_almost_eq(room.to_global(sarcophagus.spot).distance_to(champion.global_position), 0.0, 1.0)
	assert_false(sources.get_pool().has(sarcophagus), "not used by later pushes")


func test_sources_go_quiet_when_the_room_is_cleared() -> void:
	var room := _room(8)
	var sources := _sources(room)
	room.completed.emit(room)
	for source in sources.get_sources():
		assert_true(source.quiet)

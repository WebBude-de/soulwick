extends GutTest
## Minigame "Einsturz" (R4a, KONZEPT_RAEUME_V2 §3.10): the floor breaks in fields of 2×2 tiles in a
## fixed order from the outside in (1 s warning, then abyss via RoomTiles.add_pit_tiles); enemies on
## a field fall with it; after 30 s only the way to the exit stands, with the bonus chest at its end.

const PLAN_ROOM: PackedScene = preload("res://dungeon/rooms/combat/einsturz_halle_ember_forge.tscn")
const PLAIN_ROOM: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_collapse_save.cfg"


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()


func after_each() -> void:
	HitStop.reset()
	await wait_process_frames(1)


func _room(scene: PackedScene = PLAN_ROOM, room_index := 17) -> RoomController:
	var room := scene.instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 77
	room.setup(room_index, RoomSequence.RoomType.COMBAT, -1, false, context)
	var spawner := room.get_node("EnemySpawner") as EnemySpawner
	spawner.biomes = [] as Array[BiomeData]
	spawner.extra_types = [] as Array[EnemyData]
	spawner.enemy_types = [SKELETON] as Array[EnemyData]
	spawner.spawn_weights = [1.0] as Array[float]
	var group := EncounterGroup.new()
	group.allow_elites = false
	group.count_range = Vector2i(4, 4)
	spawner.encounter_group = group
	add_child_autofree(room)
	return room


func _attach(room: RoomController, seed_value := 13) -> CollapseMode:
	var mode := CollapseMode.attach(room, seed_value)
	assert_not_null(mode, "the collapse fits the room")
	return mode


func _kill_all(room: RoomController) -> void:
	for child in room.enemy_container.get_children():
		var enemy := child as Enemy
		if enemy != null and not enemy.is_dead():
			enemy.health.take_damage(INF)


## Floor tiles still standing that cannot be walked to from the entrance.
func _islands(room: RoomController) -> Array[Vector2i]:
	var reached := room.tiles.get_reachable_tiles(0)
	var floor_rect := Rect2i(Vector2i.ZERO, room.tiles.room_size)
	var islands: Array[Vector2i] = []
	for tile: Vector2i in room.tiles.get_walkable_tiles():
		if floor_rect.has_point(tile) and not reached.has(tile):
			islands.append(tile)
	return islands


# --- Rules ---

func test_collapse_numbers() -> void:
	assert_eq(CollapseRules.DURATION, 30.0)
	assert_eq(CollapseRules.WARN_TIME, 1.0)
	var times := CollapseRules.break_times(5)
	assert_eq(times.size(), 5)
	assert_almost_eq(times[0], CollapseRules.START_DELAY, 0.001)
	assert_almost_eq(times[4], CollapseRules.DURATION - CollapseRules.END_CALM, 0.001)
	for i in range(1, times.size()):
		assert_gt(times[i], times[i - 1], "one after another")
	assert_true(CollapseRules.should_warn(2.0, 2.9))
	assert_false(CollapseRules.should_warn(1.8, 2.9))
	assert_eq(CollapseRules.MIN_ROOM, 16, "2. Biom")


func test_fields_break_from_the_outside_in_and_never_leave_islands() -> void:
	var floor_tiles: Dictionary[Vector2i, bool] = {}
	for y in 7:
		for x in 9:
			floor_tiles[Vector2i(x, y)] = true
	var way := CollapseRules.shortest_way(floor_tiles, Vector2i(4, 6), Vector2i(4, 0))
	assert_eq(way.size(), 7, "straight up")
	var kept := CollapseRules.widen(way, floor_tiles, 1)
	assert_eq(kept.size(), 21, "three tiles wide")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var fields := CollapseRules.build_fields(floor_tiles, kept, [] as Array[Vector2i], rng)
	var covered: Dictionary[Vector2i, bool] = {}
	var standing := floor_tiles.duplicate()
	for field: Array in fields:
		assert_lte(field.size(), 8, "small fields (2×2 plus cut-off tiles)")
		for tile: Vector2i in field:
			assert_false(kept.has(tile), "the way never breaks")
			assert_false(covered.has(tile), "every tile once")
			covered[tile] = true
			standing.erase(tile)
		# Everything still standing is connected to the way.
		var reached := RoomTiles.flood_fill(standing, {} as Dictionary[Vector2i, bool], Vector2i(4, 6), 0)
		assert_eq(reached.size(), standing.size(), "no island after a field")
	assert_eq(covered.size() + kept.size(), floor_tiles.size(), "the rest of the floor breaks")
	var first: Array = fields[0]
	var last: Array = fields[fields.size() - 1]
	assert_gt(absi(first[0].x - 4), absi(last[0].x - 4), "outside first, next to the way last")


# --- Room ---

func test_plan_room_keeps_the_way_and_marks_the_cracked_fields() -> void:
	var room := _room()
	var mode := _attach(room)
	assert_true(mode.kept.has(room.tiles.get_entrance_inside_tile()))
	assert_true(mode.kept.has(room.tiles.get_exit_inside_tile()))
	assert_gt(mode.fields.size(), 5)
	var marked := room.get_objectives_of(CollapseRules.FIELD_MARKER)
	assert_eq(marked.size(), 6)
	for marker in marked:
		var tile: Vector2i = marker.get_meta(&"tile")
		if not mode.kept.has(tile):
			assert_true(mode.view.has_plate(tile), "cracked plate on %s" % tile)
	assert_eq(mode.get_next_fields().size(), CollapseRules.LOOKAHEAD)
	assert_not_null(CollapseMode.attach(_room(PLAIN_ROOM), 2), "any combat room works")


func test_intro_and_bar() -> void:
	var room := _room()
	var mode := _attach(room)
	room.player_entered.emit(room)
	var goal := RoomObjective.of_room(room)
	assert_eq(goal.mode_id, RoomObjective.COLLAPSE)
	assert_eq(goal.get_goal(), DungeonTexts.t(&"MODE_COLLAPSE_GOAL", [30]))
	assert_eq(goal.time_left, CollapseRules.DURATION)
	assert_true(goal.label_text.begins_with(DungeonTexts.t(&"OBJECTIVE_COLLAPSE_NEXT", [""])), "the next fields")
	assert_eq(RoomIntro.get_intro(room).focus, room.to_global(CollapseRules.field_center(mode.fields[0])), "camera on the first field")


func test_a_field_warns_then_breaks_and_takes_enemies_with_it() -> void:
	var room := _room()
	var mode := _attach(room)
	room.start_encounter()
	_kill_all(room)
	var field: Array = mode.fields[0]
	var tile: Vector2i = field[0]
	var enemies := room.spawner.spawn_enemies(room.room_index, [RoomTiles.tile_center(tile)] as Array[Vector2], room.enemy_container, room.context, room.get_arena())
	room.track_enemy(enemies[0])
	mode.step(mode.break_at[0] - CollapseRules.WARN_TIME + 0.05)
	assert_eq(mode.field_states[0], CollapseMode.FieldState.WARNED)
	assert_true(mode.is_warned_tile(tile))
	assert_false(room.tiles.is_pit(tile), "still floor during the warning")
	mode.step(CollapseRules.WARN_TIME)
	assert_eq(mode.field_states[0], CollapseMode.FieldState.BROKEN)
	for broken: Vector2i in field:
		assert_true(room.tiles.is_pit(broken), "abyss now %s" % broken)
	assert_true(enemies[0].has_fallen_into_pit(), "the enemy fell with the floor")
	assert_eq(_islands(room), [] as Array[Vector2i], "no island")


func test_after_thirty_seconds_only_the_way_stands_with_the_chest() -> void:
	var room := _room()
	var mode := _attach(room)
	room.start_encounter()
	_kill_all(room)
	await wait_process_frames(2)
	assert_ne(room.state, RoomController.State.CLEARED, "held while the floor breaks")
	mode.step(CollapseRules.DURATION + 0.1)
	assert_true(mode.is_survived)
	assert_eq(mode.broken_count, mode.fields.size())
	assert_eq(mode.bonus, CombatVariant.Bonus.ACHIEVED)
	assert_true(RoomObjective.of_room(room).success)
	for tile: Vector2i in mode.kept:
		assert_false(room.tiles.is_pit(tile), "the way stands %s" % tile)
	assert_eq(_islands(room), [] as Array[Vector2i], "every standing tile leads to the exit")
	assert_eq(mode.chests.size(), 1, "bonus chest at the end of the way")
	var chest_tile := RoomTiles.local_to_tile(mode.chests[0].position)
	assert_false(room.tiles.is_pit(chest_tile))
	_kill_all(room)
	await wait_process_frames(2)
	assert_eq(room.state, RoomController.State.CLEARED)


func test_a_player_on_a_breaking_field_falls_like_on_any_abyss() -> void:
	var room := _room()
	var mode := _attach(room)
	room.start_encounter()
	_kill_all(room)
	var tile: Vector2i = (mode.fields[0] as Array)[0]
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	room.context.player = player
	player.health.reset(20.0)
	player.global_position = room.to_global(RoomTiles.tile_center(tile)) - Player.FEET_OFFSET
	player.fall.remember_safe_spot(room.to_global(RoomTiles.tile_center(room.tiles.get_entrance_inside_tile())))
	await wait_physics_frames(2)
	mode.step(mode.break_at[0] - 0.5)
	assert_true(RoomObjective.of_room(room).danger, "red bar: the floor under a player is about to break")
	mode.step(0.55)
	await wait_physics_frames(14)
	assert_true(player.fall.falls > 0, "falls through")
	await wait_seconds(ChasmRules.FALL_TIME + 0.2)
	assert_eq(player.fall.falls, 1, "fell once")
	assert_eq(player.health.get_health(), 20.0 - ChasmRules.fall_damage(), "a whole heart (D-115)")
	var feet_tile := RoomTiles.local_to_tile(room.to_local(player.get_feet_position()))
	assert_false(room.tiles.is_pit(feet_tile), "back on solid floor")
	assert_true(mode.kept.has(feet_tile), "landed on the way that stays")

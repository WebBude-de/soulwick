extends GutTest
## Trial room floor plan and courses (KONZEPT_RAEUME §6.1, ROADMAP_AUSBAU A8): the exit is always
## reachable without touching the parcours, the parcours and its chest are reachable, hazards only
## stand in the parcours, every kind of hazard appears, beats leave gaps, torches light the way.

const TRIAL_ROOM: PackedScene = preload("res://dungeon/rooms/trials/trial_room.tscn")
const CONTENT: PackedScene = preload("res://dungeon/rooms/trials/trial_content.tscn")
const SEEDS := 40

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_trial_room_save.cfg"


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


## Door views free their pieces with queue_free (D1): let a frame pass so they are not orphans.
func after_each() -> void:
	await wait_process_frames(1)


func _context(seed_value := 7) -> DungeonContext:
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = seed_value
	return context


func _room(context: DungeonContext, room_index := 4) -> RoomController:
	var room := _loose_room(context, room_index)
	autofree(room)
	return room


## A room the test frees itself (loops over many seeds).
func _loose_room(context: DungeonContext, room_index := 4) -> RoomController:
	var room := TRIAL_ROOM.instantiate() as RoomController
	room.setup(room_index, RoomSequence.RoomType.SPECIAL, SpecialTable.TRIAL, false, context)
	add_child(room)
	return room


func _content(room: RoomController, kind: int) -> TrialContent:
	var content := CONTENT.instantiate() as TrialContent
	content.forced_kind = kind
	room.add_child(content)
	content.setup(room.context, room)
	return content


# --- Floor plan ---

func test_template_matches_the_layout() -> void:
	var room := _room(_context())
	var tiles := room.tiles
	assert_eq(tiles.room_size, TrialLayout.ROOM_SIZE)
	assert_eq(tiles.entrance_x, TrialLayout.ENTRANCE_X)
	assert_eq(tiles.exit_x, TrialLayout.EXIT_X)
	assert_eq(tiles.wall_rects, TrialLayout.get_wall_rects(false))
	for marker in room.get_spawn_markers():
		var tile := RoomTiles.local_to_tile(marker.position)
		assert_true(TrialLayout.get_safe_tiles(tiles).has(tile), "marker %s on the safe floor" % marker.name)


func test_exit_is_reachable_without_the_parcours() -> void:
	var tiles := _room(_context()).tiles
	var safe := TrialLayout.get_safe_tiles(tiles)
	var reached := RoomTiles.flood_fill(safe, {} as Dictionary[Vector2i, bool], tiles.get_entrance_inside_tile())
	assert_true(reached.has(tiles.get_exit_inside_tile()), "direct way to the exit")
	assert_true(reached.has(Vector2i(TrialLayout.EXIT_X, -1)), "into the exit corridor")
	for tile in reached:
		assert_false(TrialLayout.is_parcours_tile(tile), "the direct way never crosses the parcours: %s" % tile)


func test_parcours_and_chest_are_reachable_only_through_the_start() -> void:
	var tiles := _room(_context()).tiles
	var reached := tiles.get_reachable_tiles()
	for tile in TrialLayout.get_parcours_tiles():
		assert_true(reached.has(tile), "parcours tile %s reachable" % tile)
	assert_true(reached.has(TrialLayout.CHEST_TILE))
	# The only door into the parcours is the start: without it the finish is cut off.
	var without_start := tiles.get_walkable_tiles()
	for y in range(TrialLayout.START.position.y, TrialLayout.START.end.y):
		without_start.erase(Vector2i(TrialLayout.START.position.x, y))
	var cut := RoomTiles.flood_fill(without_start, {} as Dictionary[Vector2i, bool], tiles.get_entrance_inside_tile())
	assert_false(cut.has(TrialLayout.CHEST_TILE), "no shortcut to the chest while the gate is closed")


func test_shortcut_gate_opens_the_way_back() -> void:
	var room := _room(_context())
	var tiles := room.tiles
	for y in range(TrialLayout.GATE.position.y, TrialLayout.GATE.end.y):
		assert_false(tiles.is_walkable(Vector2i(TrialLayout.GATE.position.x, y)))
	tiles.wall_rects = TrialLayout.get_wall_rects(true)
	var safe := TrialLayout.get_safe_tiles(tiles)
	for y in range(TrialLayout.GATE.position.y, TrialLayout.GATE.end.y):
		assert_true(safe.has(Vector2i(TrialLayout.GATE.position.x, y)), "gate tile is safe floor now")
	assert_true(tiles.is_walkable(TrialLayout.CHEST_TILE + Vector2i.RIGHT))
	await wait_physics_frames(2)
	var cell := Vector2i(TrialLayout.GATE.position.x, TrialLayout.GATE.position.y)
	assert_eq(tiles.get_cell_source_id(cell), RoomTiles.SOURCE_ID, "repainted as floor")


func test_path_runs_from_start_to_finish_inside_the_parcours() -> void:
	var length := TrialLayout.get_path_length()
	assert_gt(length, 1000.0)
	var steps := 60
	for i in steps + 1:
		var point := TrialLayout.get_path_point(length * i / steps)
		assert_true(TrialLayout.is_parcours_tile(RoomTiles.local_to_tile(point)), "path point %s" % point)
	assert_true(TrialLayout.START.has_point(RoomTiles.local_to_tile(TrialLayout.get_path_point(0.0))))
	assert_true(TrialLayout.FINISH.has_point(RoomTiles.local_to_tile(TrialLayout.get_path_point(length))))


# --- Gauntlet ---

func test_gauntlet_hazards_stay_in_the_lanes_and_every_kind_appears() -> void:
	for seed_value in SEEDS:
		var room := _loose_room(_context(seed_value + 1))
		var content := _content(room, SpecialTable.TrialKind.GAUNTLET)
		var course := content.course as GauntletCourse
		assert_not_null(course)
		for kind in GauntletCourse.Kind.values():
			assert_true(course.placed_kinds.has(kind), "seed %d: kind %d appears" % [seed_value, kind])
		assert_between(course.hazards.size(), 6, 14)
		for hazard in course.hazards:
			var tile := RoomTiles.local_to_tile(hazard.hit_rect.get_center())
			assert_true(TrialLayout.is_parcours_tile(tile), "hazard in the parcours")
			assert_false(TrialLayout.START.has_point(tile), "start stays free")
			assert_false(TrialLayout.FINISH.has_point(tile), "finish stays free")
			assert_false(TrialLayout.TURN.has_point(tile), "turn stays free")
		room.free()


func test_gauntlet_is_reproducible_with_the_same_seed() -> void:
	var columns := func(seed_value: int) -> Array:
		var room := _loose_room(_context(seed_value))
		var course := _content(room, SpecialTable.TrialKind.GAUNTLET).course as GauntletCourse
		var result: Array = []
		for hazard in course.hazards:
			result.append([hazard.get_script(), hazard.hit_rect])
		room.free()
		return result
	assert_eq(columns.call(99), columns.call(99))
	assert_ne(columns.call(99), columns.call(100), "another room, another parcours")


func test_every_hazard_leaves_gaps() -> void:
	var room := _room(_context(3))
	var course := _content(room, SpecialTable.TrialKind.GAUNTLET).course as GauntletCourse
	var safe_time: Dictionary[TrialHazard, float] = {}
	var active_time: Dictionary[TrialHazard, float] = {}
	for frame in 60 * 20:
		course.advance(1.0 / 60.0)
		for hazard in course.hazards:
			if hazard.is_dangerous():
				active_time[hazard] = active_time.get(hazard, 0.0) + 1.0 / 60.0
			else:
				safe_time[hazard] = safe_time.get(hazard, 0.0) + 1.0 / 60.0
	for hazard in course.hazards:
		assert_gt(active_time.get(hazard, 0.0), 1.0, "%s fires" % hazard.get_script().get_global_name())
		assert_gt(safe_time.get(hazard, 0.0), 6.0, "%s leaves gaps" % hazard.get_script().get_global_name())


func test_twin_flame_jets_never_burn_together() -> void:
	for seed_value in 10:
		var room := _loose_room(_context(seed_value + 11))
		var course := _content(room, SpecialTable.TrialKind.GAUNTLET).course as GauntletCourse
		var columns: Dictionary[float, Array] = {}
		for hazard in course.hazards:
			if hazard is TrialFlameJet:
				var x := hazard.hit_rect.position.x
				if not columns.has(x):
					columns[x] = []
				columns[x].append(hazard)
		for frame in 60 * 15:
			course.advance(1.0 / 60.0)
			for jets in columns.values():
				var burning := 0
				for jet: TrialFlameJet in jets:
					if jet.is_dangerous():
						burning += 1
				assert_true(burning < jets.size(), "one row of a flame column is always quiet")
				if burning >= jets.size():
					room.free()
					return
		room.free()


func test_pendulum_hurts_only_in_the_middle_of_its_swing() -> void:
	var pendulum: TrialPendulum = autofree(TrialPendulum.new())
	pendulum.build(TrialLayout.column_rect(TrialLayout.LANE_A, 9))
	pendulum.period = 2.0
	var seen_active := false
	var seen_idle := false
	for frame in 120:
		pendulum.advance(1.0 / 60.0)
		var middle := absf(pendulum.get_swing()) < TrialPendulum.DANGER_BAND
		assert_eq(pendulum.is_dangerous(), middle)
		seen_active = seen_active or middle
		seen_idle = seen_idle or not middle
	assert_true(seen_active and seen_idle)


# --- Light run ---

func test_lit_torches_light_the_whole_path() -> void:
	var room := _room(_context(5))
	var content := _content(room, SpecialTable.TrialKind.LIGHT_RUN)
	var course := content.course as LightRunCourse
	assert_not_null(course)
	assert_gt(course.torches.size(), 4)
	var length := TrialLayout.get_path_length()
	for i in 41:
		var point := TrialLayout.get_path_point(length * i / 40.0)
		assert_true(course.is_lit(point), "path point %s lit before the start" % point)
	for torch in course.torches:
		assert_true(TrialLayout.is_parcours_tile(RoomTiles.local_to_tile(torch.base_position)), "torch beside the lane, inside the parcours")


func test_torches_go_out_one_after_another_and_relight() -> void:
	var room := _room(_context(6))
	var content := _content(room, SpecialTable.TrialKind.LIGHT_RUN)
	var course := content.course as LightRunCourse
	for i in range(1, course.out_times.size()):
		assert_gt(course.out_times[i], course.out_times[i - 1], "one after the other")
	assert_gt(course.out_times[0], LightRunCourse.START_GRACE)
	var player: Player = add_child_autofree(preload("res://player/player.tscn").instantiate())
	course.on_run_started(player)
	assert_true(course.is_sequence_running())
	course.advance(course.out_times[0] + 0.01)
	assert_false(course.torches[0].is_lit())
	assert_true(course.torches[1].is_lit())
	course.advance(course.out_times[course.out_times.size() - 1] + LightRunCourse.RELIGHT_DELAY)
	assert_false(course.is_sequence_running(), "nobody runs: all torches burn again for a retry")
	for torch in course.torches:
		assert_true(torch.is_lit())


func test_finish_and_safe_way_stay_lit_in_the_light_run() -> void:
	var room := _room(_context(8))
	var content := _content(room, SpecialTable.TrialKind.LIGHT_RUN)
	var course := content.course as LightRunCourse
	for torch in course.torches:
		torch.set_lit(false)
	var finish := TrialLayout.rect_to_local(TrialLayout.FINISH).get_center()
	assert_true(course.is_lit(finish), "the chest lights the finish")
	assert_false(course.is_lit(TrialLayout.rect_to_local(TrialLayout.TURN).get_center()), "the turn is dark")

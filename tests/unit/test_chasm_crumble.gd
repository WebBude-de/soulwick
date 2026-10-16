extends GutTest
## Bröckelboden (KONZEPT_RAEUME §6.1, A4/A8): one open gap per lane from the start, cracked plates
## that break after a step and grow back, solid tiles to choose; a fall is a mistake, lands on the
## last solid tile of the course and never ends the run.

const TRIAL_ROOM: PackedScene = preload("res://dungeon/rooms/trials/trial_room.tscn")
const CONTENT: PackedScene = preload("res://dungeon/rooms/trials/trial_content.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_chasm_crumble_save.cfg"


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()


func after_each() -> void:
	HitStop.reset()
	await wait_process_frames(1)


func _trial(seed_value := 4, player: Player = null) -> TrialContent:
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = seed_value
	context.player = player
	var room := TRIAL_ROOM.instantiate() as RoomController
	room.setup(4, RoomSequence.RoomType.SPECIAL, SpecialTable.TRIAL, false, context)
	add_child_autofree(room)
	var content := CONTENT.instantiate() as TrialContent
	content.forced_kind = SpecialTable.TrialKind.CRUMBLE
	room.add_child(content)
	content.setup(context, room)
	return content


func _course(content: TrialContent) -> CrumbleCourse:
	return content.course as CrumbleCourse


func test_crumbling_floor_is_part_of_the_trial_draw() -> void:
	assert_true(CrumbleCourse.is_available())
	var table := SpecialTable.load_default().duplicate() as SpecialTable
	table.crumble_weight = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var crumble := 0
	for i in 3000:
		if table.roll_trial_kind(rng, CrumbleCourse.is_available()) == SpecialTable.TrialKind.CRUMBLE:
			crumble += 1
	assert_almost_eq(crumble / 3000.0, 1.0 / 3.0, 0.04, "one weight of three")
	assert_eq(TrialContent.get_intro_key(SpecialTable.TrialKind.CRUMBLE), &"ROOM_TRIAL_CRUMBLE_INTRO")


func test_layout_gap_columns_and_plates() -> void:
	for seed_value in 12:
		var content := _trial(seed_value)
		var course := _course(content)
		assert_not_null(course, "crumbling course built")
		var tiles := content.room.tiles
		# One gap column per lane: two tiles (both rows), one tile wide, never at a lane end.
		assert_eq(course.gap_tiles.size(), 4)
		var columns := {}
		for tile in course.gap_tiles:
			assert_true(tiles.is_pit(tile), "gap %s is an abyss from the start" % tile)
			assert_true(TrialLayout.is_parcours_tile(tile), "gap inside the parcours")
			columns[Vector2i(tile.x, 1 if tile.y >= 6 else 0)] = true
			assert_false(course.gap_tiles.has(tile + Vector2i.RIGHT), "one tile wide (a dash crosses it)")
		assert_eq(columns.size(), 2, "one gap per lane")
		# The safe way to the exit never crumbles.
		for tile in TrialLayout.get_safe_tiles(tiles):
			assert_false(tiles.is_pit(tile), "safe way %s" % tile)
			assert_false(course.is_crumbling_tile(tile))
		assert_false(course.plates.is_empty())
		# Always a dash over the gap: the tiles on both sides exist (plates or solid floor).
		for tile in course.gap_tiles:
			assert_false(tiles.is_pit(tile + Vector2i.LEFT) or tiles.is_pit(tile + Vector2i.RIGHT), "%s: something to jump from and to" % tile)
		content.room.queue_free()
		await wait_process_frames(1)


func test_plates_break_after_a_step_and_grow_back() -> void:
	var content := _trial(7)
	var course := _course(content)
	var tiles := content.room.tiles
	var plate: Vector2i = course.plates.keys()[0]
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	course.step_on(player, plate)
	assert_eq(course.get_plate(plate), CrumbleCourse.Plate.CRACKING)
	course.advance(CrumbleCourse.CRUMBLE_DELAY * 0.5)
	assert_false(tiles.is_pit(plate), "still holds")
	course.advance(CrumbleCourse.CRUMBLE_DELAY * 0.6)
	assert_eq(course.get_plate(plate), CrumbleCourse.Plate.BROKEN)
	assert_true(tiles.is_pit(plate), "broken: abyss")
	course.advance(CrumbleCourse.REGROW_TIME + 0.1)
	assert_eq(course.get_plate(plate), CrumbleCourse.Plate.INTACT)
	assert_false(tiles.is_pit(plate), "grown back")


func test_a_fall_is_a_mistake_lands_on_solid_ground_and_never_kills() -> void:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.set_physics_process(false)
	var content := _trial(9, player)
	var course := _course(content)
	var start := Vector2i(TrialLayout.START.position.x, TrialLayout.START.end.y - 1)
	player.global_position = content.room.to_global(RoomTiles.tile_center(start)) - Player.FEET_OFFSET
	content.step(0.016)
	assert_eq(content.get_run_state(player), TrialContent.RunState.RUNNING)
	# Low on health: the fall must leave half a heart.
	player.health.take_damage(player.health.get_health() - 1.5)
	player.fall.start_fall()
	assert_eq(content.get_mistakes(player), 1, "a fall is a mistake")
	for i in 40:
		player.fall.update(1.0 / 60.0)
	assert_false(player.is_falling())
	assert_true(player.is_alive(), "a trial never ends the run")
	assert_eq(player.health.get_health(), 0.5, "capped to leave half a heart")
	var landing := content.room.to_local(player.get_feet_position())
	assert_eq(RoomTiles.local_to_tile(landing), start, "back on the last solid tile of the course")
	assert_false(course.is_crumbling_tile(RoomTiles.local_to_tile(landing)))

extends GutTest
## Playtest 23.10.2026 (room modes), one regression per report:
##   #f5470311 Risse schließen: the rifts stand in the walls before the fight (intro and Flint show them).
##   #9c8ebbe0 Einsturz: standing still does not pay - a sinkhole opens under a resting player, also
##             on the way that stays, and closes again.
##   #9ea58659 Geleit: he stays at the end of his way instead of walking on through the doorway; his
##             way stays on the ground in every escort plan.
##   #536bc219 Flamme hüten: the flame on its plateau can be reached by enemies over the stairs from
##             every source (tile level; the enemies' navigation itself is enemies-dev's).
##   #56d68b40 Flamme hüten (co-op, "nie Schaden"): pushes from two sides of the flame, more raiders.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
const RIFT_ROOM := "res://dungeon/rooms/combat/risse_schlucht_slime_grotto.tscn"
const COLLAPSE_ROOM := "res://dungeon/rooms/combat/einsturz_halle_slime_grotto.tscn"
const ESCORT_ROOM := "res://dungeon/rooms/combat/geleit_pfad_crypt.tscn"
const COMBAT_DIR := "res://dungeon/rooms/combat/"
## Seed of the report #f5470311 (room 17, slot 18).
const REPORT_SEED := 8900120934407522844

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_mode_playtest_save.cfg"


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


func _room(path: String, room_index := 17, in_tree := true) -> RoomController:
	var room := (load(path) as PackedScene).instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = REPORT_SEED
	room.setup(room_index, RoomSequence.RoomType.COMBAT, -1, false, context)
	var spawner := room.get_node("EnemySpawner") as EnemySpawner
	spawner.biomes = [] as Array[BiomeData]
	spawner.extra_types = [] as Array[EnemyData]
	spawner.enemy_types = [SKELETON] as Array[EnemyData]
	spawner.spawn_weights = [1.0] as Array[float]
	var group := EncounterGroup.new()
	group.allow_elites = false
	group.count_range = Vector2i(3, 3)
	spawner.encounter_group = group
	if in_tree:
		add_child_autofree(room)
	return room


func _player(room: RoomController, local_feet: Vector2) -> Player:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	room.context.player = player
	player.health.reset(40.0)
	player.global_position = room.to_global(local_feet) - Player.FEET_OFFSET
	return player


func _kill_all(room: RoomController) -> void:
	for child in room.enemy_container.get_children():
		var enemy := child as Enemy
		if enemy != null and not enemy.is_dead() and not enemy is SummoningRift:
			enemy.health.take_damage(INF)


func _templates(prefix: String) -> Array[String]:
	var paths: Array[String] = []
	for file in DirAccess.get_files_at(COMBAT_DIR):
		if file.begins_with(prefix) and file.ends_with(".tscn"):
			paths.append(COMBAT_DIR + file)
	paths.sort()
	return paths


# --- #f5470311 Risse schließen ---

func test_rifts_stand_in_the_walls_before_the_fight() -> void:
	var room := _room(RIFT_ROOM)
	var rng := RandomNumberGenerator.new()
	rng.seed = REPORT_SEED
	assert_eq(RoomVariants.attach(room, VariantTable.pick_for(&"rifts"), rng), &"rifts")
	var mode := CombatVariant.of(room) as RiftsMode
	var wall_tiles := mode.get_wall_rift_tiles()
	assert_eq(wall_tiles.size(), room.get_sources_of(&"rift_wall").size(), "one rift per wall rift of the plan")
	await wait_process_frames(2)
	var rifts := mode.get_open_rifts()
	assert_eq(rifts.size(), wall_tiles.size(), "the rifts are there before anybody walked in")
	for rift in rifts:
		assert_true(rift.is_inside_tree() and rift.visible, "visible %s" % rift.name)
		assert_true(rift.in_wall, "in the wall")
		assert_true(rift.is_in_intro(), "still before the fight")
		assert_true(rift.hurtbox.is_invulnerable(), "cannot be closed before the fight")
		var source := mode.get_source_of(rift)
		assert_not_null(source, "bound to its wall source")
		if source != null:
			assert_true(source.is_opening_hidden(), "no second hole beside the rift")
	assert_eq(room.get_alive_enemy_count(), 0, "not counted before the fight")
	# Intro and Flint: the camera on a rift, not on the bare floor between them.
	mode.start_intro()
	var intro := RoomIntro.get_intro(room)
	assert_not_null(intro)
	var points := mode.get_rift_points()
	assert_eq(intro.focus, points[0], "camera on the first rift")
	var steps := mode.get_flint_steps()
	assert_gte(steps.size(), 2)
	# The fight wakes them, the room counts them, the pushes start.
	room.start_encounter()
	_kill_all(room)
	for rift in rifts:
		assert_false(rift.is_in_intro(), "awake")
		assert_false(rift.hurtbox.is_invulnerable(), "can be hit now")
	assert_eq(room.get_alive_enemy_count(), rifts.size(), "the rifts count for the room")
	var pushed := mode.push_from(rifts[0])
	assert_eq(pushed.size(), 1, "a rift sends its enemy through the wall")


# --- #9c8ebbe0 Einsturz ---

func test_sinkhole_rules() -> void:
	var open: Dictionary[Vector2i, bool] = {}
	for y in 5:
		for x in 5:
			open[Vector2i(x, y)] = true
	# Feet in the lower right quarter of tile (2, 2): the plate reaches right and down.
	var feet := RoomTiles.tile_to_local(Vector2i(2, 2)) + Vector2(50, 50)
	assert_eq(CollapseRules.sinkhole_tiles(feet, open), [Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3), Vector2i(3, 3)] as Array[Vector2i])
	feet = RoomTiles.tile_to_local(Vector2i(2, 2)) + Vector2(10, 10)
	assert_eq(CollapseRules.sinkhole_tiles(feet, open), [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)] as Array[Vector2i])
	open.erase(Vector2i(1, 1))
	assert_eq(CollapseRules.sinkhole_tiles(feet, open).size(), 3, "only floor that may sink")
	assert_false(CollapseRules.is_still_too_long(CollapseRules.STILL_TIME - 0.1))
	assert_true(CollapseRules.is_still_too_long(CollapseRules.STILL_TIME))
	assert_true(CollapseRules.is_resting(Vector2.ZERO, Vector2(CollapseRules.STILL_RADIUS - 1.0, 0)))
	assert_false(CollapseRules.is_resting(Vector2.ZERO, Vector2(CollapseRules.STILL_RADIUS + 1.0, 0)))
	assert_false(CollapseRules.may_sink(CollapseRules.DURATION - CollapseRules.WARN_TIME * 0.5), "not in the last second")


func test_standing_still_on_the_way_opens_a_sinkhole_that_closes_again() -> void:
	var room := _room(COLLAPSE_ROOM, 21)
	var mode := CollapseMode.attach(room, 13)
	assert_not_null(mode)
	room.start_encounter()
	_kill_all(room)
	# Where the report stood: on the way that stays, right in front of the exit.
	var tile := room.tiles.get_exit_inside_tile() + (-RoomTiles.SIDE_DIRECTIONS[room.tiles.exit_side]) * 2
	assert_true(mode.kept.has(tile), "a tile of the way that stays")
	var feet := RoomTiles.tile_center(tile)
	var player := _player(room, feet)
	player.fall.remember_safe_spot(room.to_global(RoomTiles.tile_center(room.tiles.get_entrance_inside_tile())))
	await wait_physics_frames(2)
	# Past the start of the collapse, then standing still.
	mode.step(CollapseRules.START_DELAY)
	assert_true(mode.sinkholes.is_empty())
	mode.step(CollapseRules.STILL_TIME - mode.get_rest_time(player) + 0.05)
	assert_eq(mode.sinkholes.size(), 1, "a sinkhole under the resting player")
	var hole_tiles: Array[Vector2i] = []
	hole_tiles.assign(mode.sinkholes[0]["tiles"])
	assert_true(hole_tiles.has(tile), "under his feet")
	assert_true(mode.is_warned_tile(tile), "warned first")
	assert_true(RoomObjective.of_room(room).danger, "red bar")
	assert_false(room.tiles.is_pit(tile), "still floor during the warning")
	mode.step(CollapseRules.WARN_TIME)
	assert_true(room.tiles.is_pit(tile), "it gives way, on the way that stays too")
	assert_eq(mode.sinkholes_opened, 1)
	await wait_physics_frames(14)
	assert_gt(player.fall.falls, 0, "who stays, falls")
	mode.step(CollapseRules.SINK_TIME + 0.05)
	for hole_tile in hole_tiles:
		if mode.kept.has(hole_tile):
			assert_false(room.tiles.is_pit(hole_tile), "the way closes again %s" % hole_tile)
	# The end: the whole way stands, sinkholes or not.
	mode.step(CollapseRules.DURATION)
	assert_true(mode.is_survived)
	assert_true(mode.sinkholes.is_empty())
	for kept_tile: Vector2i in mode.kept:
		assert_false(room.tiles.is_pit(kept_tile), "the way stands %s" % kept_tile)


func test_a_moving_player_gets_no_sinkhole() -> void:
	var room := _room(COLLAPSE_ROOM, 21)
	var mode := CollapseMode.attach(room, 13)
	room.start_encounter()
	_kill_all(room)
	var start := room.tiles.get_entrance_inside_tile()
	var player := _player(room, RoomTiles.tile_center(start))
	# Walks along the way from the start: one tile per second, always further than STILL_RADIUS.
	for i in mini(8, mode.way.size()):
		player.global_position = room.to_global(RoomTiles.tile_center(mode.way[i])) - Player.FEET_OFFSET
		mode.step(1.0)
	assert_eq(mode.sinkholes_opened, 0, "moving does not sink")
	assert_true(mode.sinkholes.is_empty())


# --- #9ea58659 Geleit ---

func test_escort_way_stays_on_the_ground_in_every_escort_plan() -> void:
	var checked := 0
	for path in _templates("geleit_"):
		var room := _room(path, 8)
		var mode := EscortMode.attach(room, 5)
		assert_not_null(mode, path)
		if mode == null:
			continue
		var height: Dictionary[Vector2i, bool] = {}
		if room.tiles.has_height():
			height = room.tiles.get_height_layout().get_height_tiles()
		for tile in mode.path_tiles:
			assert_true(room.tiles.is_walkable(tile), "%s: walkable %s" % [path.get_file(), tile])
			assert_false(height.has(tile), "%s: never on a plateau, cliff or stairs %s" % [path.get_file(), tile])
		checked += 1
	assert_gt(checked, 0, "escort plans checked")


func test_rescued_villager_stays_at_the_end_of_his_way() -> void:
	var room := _room(ESCORT_ROOM, 8)
	var mode := EscortMode.attach(room, 5)
	assert_not_null(mode)
	room.start_encounter()
	mode.step(mode.path_total / EscortRules.WALK_SPEED + 1.0)
	assert_eq(mode.walk_state, EscortMode.Walk.ARRIVED)
	_kill_all(room)
	await wait_process_frames(2)
	assert_true(mode.is_finished(), "room done")
	var end := RoomTiles.tile_center(mode.path_tiles[mode.path_tiles.size() - 1])
	await wait_seconds(2.5)
	assert_true(is_instance_valid(mode.villager), "he is still there")
	if is_instance_valid(mode.villager):
		assert_eq(mode.villager.position + Player.FEET_OFFSET, end, "standing at the end of his way, inside the room")
		assert_almost_eq(mode.villager.modulate.a, 1.0, 0.01, "not faded out")


# --- #536bc219 Flamme hüten ---

func test_enemies_reach_the_flame_from_every_source_over_the_stairs() -> void:
	var checked := 0
	for path in _templates("flamme_"):
		var room := _room(path, 8)
		var tiles := room.tiles
		var flame_markers := room.get_objectives_of(&"soul_flame")
		if flame_markers.is_empty():
			continue
		var flame_tile: Vector2i = flame_markers[0].get_meta(&"tile", RoomTiles.local_to_tile(flame_markers[0].position))
		var open: Dictionary[Vector2i, bool] = {}
		var floor_rect := Rect2i(Vector2i.ZERO, tiles.room_size)
		for tile: Vector2i in tiles.get_walkable_tiles():
			if floor_rect.has_point(tile) and not tiles.is_navigation_blocked(tile):
				open[tile] = true
		open[flame_tile] = true
		var layout: HeightLayout = tiles.get_height_layout() if tiles.has_height() else null
		if layout != null:
			# Walkable tiles are the ground; the plateau's surface and its connectors join it.
			for tile: Vector2i in layout.surface:
				open[tile] = true
			for tile: Vector2i in layout.stairs:
				open[tile] = true
			for tile: Vector2i in layout.ladders:
				open[tile] = true
		for marker in room.get_sources():
			var floor_tile: Vector2i = marker.get_meta(&"floor_tile", RoomTiles.local_to_tile(marker.position))
			open[floor_tile] = true
			var reached := HeightLayout.reachable(layout, open, floor_tile, true)
			assert_true(reached.has(flame_tile), "%s: enemies from %s reach the flame %s" % [path.get_file(), floor_tile, flame_tile])
		if layout != null and layout.surface.has(flame_tile):
			assert_false(layout.stairs.is_empty(), "%s: a flame up on a plateau has stairs" % path.get_file())
		checked += 1
	assert_gt(checked, 0, "flame plans checked")



func test_flame_pushes_come_from_two_sides_and_most_go_for_the_flame() -> void:
	assert_true(FlameRules.on_two_sides(Vector2.LEFT, Vector2.RIGHT))
	assert_false(FlameRules.on_two_sides(Vector2.LEFT, Vector2(-1, 0.2)), "one side")
	assert_gte(FlameRules.RAID_SHARE, 0.8, "#56d68b40: most enemies go for the flame")
	var room := _room("res://dungeon/rooms/combat/flamme_schrein_crypt.tscn", 6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	assert_eq(RoomVariants.attach(room, VariantTable.pick_for(&"flame"), rng), &"flame")
	var mode := CombatVariant.of(room) as FlameMode
	await wait_process_frames(2)
	var sides := mode.two_side_sources()
	assert_eq(sides.size(), 2, "two sources")
	if sides.size() == 2:
		var centre := SpawnSources.of(room).to_local(mode.flame.global_position)
		assert_true(FlameRules.on_two_sides(sides[0].spot - centre, sides[1].spot - centre), "on two sides of the flame")
	room.start_encounter()
	_kill_all(room)
	var pushed := mode.send_push()
	assert_gte(pushed.size(), FlameRules.PUSH_MIN)
	assert_gt(mode.get_pushes_sent(), 0)

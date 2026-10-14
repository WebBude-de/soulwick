extends GutTest
## R7 Dorf und Dungeon-Eingang (06_dorf.md): a village square with the fountain instead of a
## symmetric cross, the dungeon ruin up on the ridge reached by stairs and stone slabs, a soul flame
## bowl in front, torches and ravens that fly up when a player comes near; names only near a player
## and never with a notice; the chronicle's board (empty before the first run); lamps as light
## islands of 3 tiles. Runs in a test folder (SaveManager.set_storage_root), never on the real save.

const ROOT := "user://test_village_square"
const VILLAGE_SCENE := "res://world/village/village.tscn"
const TILE := 64.0

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String
var _stand_ins: Array[Node2D] = []


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	_wipe()
	SaveManager.set_storage_root(ROOT)


func before_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.load_game()


func after_each() -> void:
	for node in _stand_ins:
		if is_instance_valid(node):
			node.free()
	_stand_ins.clear()
	GameManager.clear_pause_reasons()


func after_all() -> void:
	_wipe()
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()


func _wipe() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	for dir_path in [root.path_join("saves"), root]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			DirAccess.remove_absolute(dir_path.path_join(file))
	DirAccess.make_dir_recursive_absolute(root)


func _village() -> Village:
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	add_child_autofree(village)
	return village


func _ground(village: Village) -> VillageTiles:
	return village.get_node("Ground") as VillageTiles


func _world_rect(rect: Rect2i) -> Rect2:
	return Rect2(Vector2(rect.position) * TILE, Vector2(rect.size) * TILE)


## A stand-in for a player (the village only reads positions of the "player" group).
func _player_at(village: Village, point: Vector2) -> Node2D:
	var stand_in := Node2D.new()
	stand_in.add_to_group(&"player")
	village.add_child(stand_in)
	stand_in.global_position = point
	_stand_ins.append(stand_in)
	return stand_in


# --- Square instead of a cross ---

func test_square_with_the_fountain_in_the_middle() -> void:
	var village := _village()
	var ground := _ground(village)
	assert_gt(ground.plaza_rects.size(), 0, "cobbled square")
	var fountain := village.get_node("Buildings/Fountain") as Node2D
	var on_square := false
	for rect in ground.plaza_rects:
		if _world_rect(rect).grow(8.0).has_point(fountain.global_position):
			on_square = true
	assert_true(on_square, "the fountain stands on the cobbles")
	assert_eq(ground.get_cell_source_id(ground.plaza_rects[0].position), VillageTiles.V2_SOURCE_ID, "cobble tiles painted")


func test_paths_are_not_a_symmetric_cross() -> void:
	var village := _village()
	var ground := _ground(village)
	var cells := {}
	for rect in ground.path_rects:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				cells[Vector2i(x, y)] = true
	var mirrored := 0
	for cell: Vector2i in cells:
		if cells.has(Vector2i(ground.map_size.x - 1 - cell.x, cell.y)):
			mirrored += 1
	gut.p("path cells %d, mirror-symmetric %d" % [cells.size(), mirrored])
	assert_lt(float(mirrored) / cells.size(), 0.6, "left and right half differ")


func test_entrance_on_the_ridge_with_stairs_and_slabs() -> void:
	var village := _village()
	var ground := _ground(village)
	var entrance := village.get_node("Buildings/DungeonEntrance") as VillageEntrance
	assert_not_null(entrance)
	var ridge_top := INF
	for rect in ground.cliff_rects:
		ridge_top = minf(ridge_top, rect.position.y * TILE)
	assert_lt(entrance.global_position.y, ridge_top, "the ruin stands above the ridge (up the hill)")
	assert_lt(entrance.global_position.y, 6.0 * TILE, "at the upper edge of the village")
	assert_gt(ground.stair_rects.size(), 0, "stairs through the ridge")
	assert_gt(ground.slab_rects.size(), 0, "stone slabs in front of the ruin")
	var slabs := _world_rect(ground.slab_rects[0])
	assert_lt(slabs.get_center().distance_to(entrance.global_position), 2.5 * TILE, "slabs lead to the ruin")
	var bowl := village.get_node("Buildings/FlameBowl") as VillageProp
	assert_not_null(bowl, "soul flame bowl")
	assert_lt(bowl.global_position.distance_to(entrance.global_position), 3.0 * TILE, "in front of the entrance")
	assert_gt(bowl.global_position.y, entrance.global_position.y, "below the ruin, on the way to it")
	var light := bowl.get_node_or_null("PropLight") as LightSource
	assert_not_null(light, "the bowl glows")
	assert_true(light.get_draw_color().is_equal_approx(LightPalette.VIOLET), "violet soul light")


func test_ridge_is_solid_and_the_stairs_are_open() -> void:
	var village := _village()
	await wait_physics_frames(3)
	var ground := _ground(village)
	var space := village.get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = PhysicsLayers.WORLD
	var cliff := ground.cliff_rects[0]
	query.position = (Vector2(cliff.position) + Vector2(3.5, 0.5)) * TILE
	assert_false(space.intersect_point(query).is_empty(), "rock face blocks")
	var stairs := ground.stair_rects[0]
	query.position = (Vector2(stairs.position) + Vector2(1.0, 0.5)) * TILE
	assert_true(space.intersect_point(query).is_empty(), "stairs are walkable")


func test_entrance_has_torches_and_ravens() -> void:
	var village := _village()
	var entrance := village.get_node("Buildings/DungeonEntrance") as VillageEntrance
	var sprite := entrance.get_node("Sprite") as Sprite2D
	assert_not_null(sprite.texture, "ruin art or placeholder")
	assert_eq(Vector2i(sprite.texture.get_size()), Vector2i(VillageEntrance.ART_SIZE), "96×80 ruin")
	var torches := 0
	for child in entrance.get_children():
		if child is LightSource and String(child.name).begins_with("TorchLight"):
			torches += 1
			assert_eq((child as LightSource).get_draw_color(), LightPalette.WARM)
	assert_eq(torches, 2, "two torches")
	assert_not_null(entrance.get_ravens(), "ravens on the lintel")
	assert_not_null(entrance.get_node_or_null("Interactable"), "still the way into the dungeon")


func test_ravens_fly_up_when_a_player_comes_near_and_return() -> void:
	var village := _village()
	var ravens := (village.get_node("Buildings/DungeonEntrance") as VillageEntrance).get_ravens()
	await wait_process_frames(2)
	assert_eq(ravens.state, VillageRavens.State.SITTING)
	var player := _player_at(village, ravens.global_position + Vector2(0, 600))
	await wait_process_frames(2)
	assert_eq(ravens.state, VillageRavens.State.SITTING, "far away: they stay")
	player.global_position = ravens.global_position + Vector2(0, VillageRavens.SCARE_DISTANCE * 0.5)
	await wait_process_frames(2)
	assert_eq(ravens.state, VillageRavens.State.LEAVING, "close: they fly up")
	await wait_seconds(VillageRavens.FLIGHT_TIME + 0.2)
	assert_eq(ravens.state, VillageRavens.State.AWAY)
	player.global_position += Vector2(0, 2000)
	await wait_seconds(VillageRavens.AWAY_TIME + VillageRavens.FLIGHT_TIME + 0.4)
	assert_eq(ravens.state, VillageRavens.State.SITTING, "back once nobody is near")


func test_ravens_placeholder_until_the_art_exists() -> void:
	for art in ["dungeon_entrance_v2", "entrance_flame_bowl_6f", "ravens_4f", "village_tiles_v2", "chronicle_board"]:
		assert_not_null(VillageArt.get_texture(art), "%s: file or placeholder" % art)
	if not VillageArt.has_art("entrance_flame_bowl_6f"):
		assert_eq(VillageArt.get_texture("entrance_flame_bowl_6f").get_width(), 6 * 32, "6 frames of 32 px")
	if not VillageArt.has_art("ravens_4f"):
		assert_eq(Vector2i(VillageArt.get_texture("ravens_4f").get_size()), Vector2i(4 * 32, 16))


# --- Names, notices, board ---

func test_names_show_only_near_a_player() -> void:
	var village := _village()
	await wait_process_frames(2)
	assert_false(village.is_caption_shown(&"Forge"), "nobody near")
	var forge := village.get_node("Buildings/Forge") as Node2D
	var player := _player_at(village, forge.global_position + Vector2(0, 80))
	await wait_seconds(0.4)
	assert_true(village.is_caption_shown(&"Forge"), "a player at the door")
	assert_false(village.is_caption_shown(&"Guild"), "the guild is far away")
	village.ui.show_notice("Test", ["Zeile"] as Array[String])
	await wait_seconds(0.4)
	assert_false(village.is_caption_shown(&"Forge"), "never together with a notice")
	assert_not_null(player)


func test_locked_chronicle_keeps_its_name_free() -> void:
	var village := _village()
	var chronicle := village.get_node("Buildings/Chronicle") as Node2D
	assert_true(village.has_lock_marker(VillageBuildings.CHRONICLE), "locked in a fresh save")
	var caption := chronicle.get_node("Caption") as Label
	for label in chronicle.find_children("*", "Label", true, false):
		assert_eq(label, caption, "only the name, no sign over it")
	var board := chronicle.get_node_or_null("Board") as Sprite2D
	assert_not_null(board, "an empty board instead")
	assert_eq(village.get_board_tally(), 0, "empty before the first run")


func test_board_counts_the_runs() -> void:
	SaveManager.add_stat(StatsTracker.RUNS, 7)
	var village := _village()
	assert_eq(village.get_board_tally(), 7)
	assert_not_null(village.get_node_or_null("Buildings/Chronicle/Board/Tally"))


func test_notice_sits_below_the_hud_row() -> void:
	assert_gte(VillageUI.NOTICE_TOP, 96.0, "banner below the gold/crystal panel")


func test_lamps_are_light_islands_of_three_tiles() -> void:
	var village := _village()
	var lamps := 0
	var positions: Array[Vector2] = []
	for prop in village.get_node("Buildings").get_children():
		var light := prop.get_node_or_null("LampLight") as LightSource
		if light == null:
			continue
		lamps += 1
		positions.append((prop as Node2D).global_position)
		assert_eq(light.radius, 3.0 * TILE, "radius 3 tiles")
		assert_eq(light.get_draw_color(), LightPalette.WARM)
	assert_gte(lamps, 5)
	# Not along one line: the lamps spread over both axes.
	var xs := {}
	var ys := {}
	for point in positions:
		xs[int(point.x / (2.0 * TILE))] = true
		ys[int(point.y / (2.0 * TILE))] = true
	assert_gte(xs.size(), 4)
	assert_gte(ys.size(), 3)


func test_fountain_babbles() -> void:
	var village := _village()
	var sound := village.get_node_or_null("Buildings/Fountain/Sound") as FountainSound
	assert_not_null(sound)
	assert_not_null(sound.stream, "file or synthesised loop")
	var wav := FountainSound.synthesize()
	assert_eq(wav.loop_mode, AudioStreamWAV.LOOP_FORWARD, "loops")
	assert_gt(wav.data.size(), 1000)

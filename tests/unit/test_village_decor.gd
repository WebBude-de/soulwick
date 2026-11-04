extends GutTest
## Village decoration (WK5, KONZEPT §8): the board beside the home opens the decorating mode; the
## grid keeps paths, doors and the spawn free; placed pieces stand with collision and light, the
## scattered flowers under them hide; the editor buys, sets, turns and puts away (saved per world);
## only alone; a guest sees the host's arrangement (view only). Uses a test save file only.

const TEST_PATH := "user://test_village_decor.cfg"
const VILLAGE_SCENE := "res://world/village/village.tscn"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

var _old_locale: String
var _old_path: String


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	Loc.apply(&"de")
	_old_path = SaveManager.save_path


func before_each() -> void:
	SaveManager.save_path = TEST_PATH
	_remove_files()
	SaveManager.load_game()


func after_each() -> void:
	GameManager.clear_pause_reasons()


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)
	_remove_files()
	SaveManager.save_path = _old_path
	SaveManager.load_game()


func _remove_files() -> void:
	for suffix in ["", ".bak", ".prev.bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + suffix))


func _village() -> Village:
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	add_child_autofree(village)
	return village


func _player(at: Vector2) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.input = RemoteInput.new()
	player.is_local = false
	add_child_autofree(player)
	player.global_position = at
	return player


## A free cell of the village grid away from the player at from.
func _free_cell(grid: DecorGrid, from: Vector2, item: DecorItem) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for cell: Vector2i in grid.floor_cells:
		if grid.check(item, cell, 0, DecorState.placements(DecorState.VILLAGE)) != DecorGrid.OK:
			continue
		var distance := (Vector2(cell) * grid.tile).distance_to(from)
		if distance > 200.0 and distance < best_distance:
			best = cell
			best_distance = distance
	return best


func test_the_board_stands_beside_the_home() -> void:
	var village := _village()
	assert_not_null(village.decor_station, "decoration board")
	assert_eq(village.decor_station.get_parent().name, "Buildings", "sorted like the props")
	assert_eq(village.decor_station.door.prompt, "Dorf schmücken")
	assert_true(village.decor_station.door.enabled, "solo: open")
	assert_not_null(village.decor_layer)
	assert_eq(village.decor_layer.space, DecorCatalog.VILLAGE)


func test_the_grid_keeps_paths_doors_and_spawn_free() -> void:
	var village := _village()
	var grid := village.decor_layer.grid
	assert_gt(grid.floor_cells.size(), 60, "plenty of grass to decorate")
	var spawn := village.find_child("PlayerSpawn", true, false) as Node2D
	assert_false(grid.floor_cells.has(grid.cell_at(spawn.global_position)), "spawn stays free")
	var ground := village.get_node("Ground") as VillageTiles
	for rect in ground.get_paved_rects():
		assert_false(grid.floor_cells.has(rect.position), "path %s stays free" % rect.position)
	for building in village.get_node("Buildings").get_children():
		var door := building.get_node_or_null("Door") as Node2D
		if door != null:
			assert_false(grid.floor_cells.has(grid.cell_at(door.global_position)), "%s door stays free" % building.name)


func test_placed_pieces_stand_with_collision_and_light() -> void:
	var village := _village()
	var grid := village.decor_layer.grid
	var lamp := DecorCatalog.get_item("lamp_post")
	var cell := _free_cell(grid, Vector2.ZERO, lamp)
	assert_ne(cell, Vector2i(-1, -1), "a free cell exists")
	SaveManager.set_decor_owned("lamp_post", 1)
	SaveManager.set_decor_placements(DecorState.VILLAGE, PackedStringArray([DecorState.format("lamp_post", cell, 0)]))
	village.decor_layer.rebuild()
	var pieces := village.decor_layer.get_pieces()
	assert_eq(pieces.size(), 1)
	assert_not_null(pieces[0].get_solid(), "blocks: true")
	assert_not_null(pieces[0].light, "light from the JSON")
	assert_eq(pieces[0].light.color, Color("#ffd166"))


func test_scattered_flowers_hide_under_a_piece() -> void:
	var village := _village()
	var decor := village.get_node("Decor") as VillageDecor
	var shown := decor.get_children().filter(func(node: Node) -> bool: return (node as CanvasItem).visible)
	assert_gt(shown.size(), 0)
	var target := shown[0] as Node2D
	var grid := village.decor_layer.grid
	var base := target.position + Vector2(0, Player.FEET_OFFSET.y if target.z_index != VillageDecor.FLAT_Z else 0.0)
	village.decor_layer.rebuild()
	decor.hide_under([Rect2(base - Vector2(4, 4), Vector2(8, 8))] as Array[Rect2])
	assert_false(target.visible, "covered")
	decor.hide_under([] as Array[Rect2])
	assert_true(target.visible, "shown again")
	assert_not_null(grid)


func test_the_editor_buys_sets_turns_and_puts_away() -> void:
	var village := _village()
	var spawn := village.find_child("PlayerSpawn", true, false) as Node2D
	var player := _player(spawn.global_position)
	var editor := village.open_decor_editor(player)
	assert_not_null(editor, "opens alone")
	assert_true(village.is_decorating())
	assert_true(player.is_input_locked(), "the player stands still")
	assert_false(get_tree().paused, "nothing pauses")
	SaveManager.add_permanent_gold(1000)
	assert_true(DecorState.buy("fence_straight"))
	assert_true(DecorState.buy("fence_straight"))
	assert_true(editor.hold_from_storage("fence_straight"))
	var cell := _free_cell(editor.grid, player.global_position, DecorCatalog.get_item("fence_straight"))
	editor.set_cursor(cell)
	assert_true(editor.place_held(), "fits")
	assert_eq(DecorState.placements(DecorState.VILLAGE).size(), 1)
	assert_false(editor.held.is_empty(), "the second fence is still in the hand")
	assert_false(editor.place_held(), "not on the first one")
	assert_eq(editor.reason, DecorGrid.REASON_TAKEN)
	editor.cancel_held()
	village.decor_layer.rebuild()
	editor.set_cursor(cell)
	editor.turn()
	assert_eq(DecorState.placements(DecorState.VILLAGE)[0]["rot"], 2, "front only: turned = mirrored")
	editor.store()
	assert_true(DecorState.placements(DecorState.VILLAGE).is_empty())
	assert_eq(DecorState.stored_count("fence_straight"), 2, "both back in the Lager")
	editor.close()
	assert_false(player.is_input_locked())
	assert_false(village.is_decorating())


func test_paths_and_doors_refuse_a_piece() -> void:
	var village := _village()
	var grid := village.decor_layer.grid
	var ground := village.get_node("Ground") as VillageTiles
	var path_cell: Vector2i = ground.get_paved_rects()[0].position
	assert_eq(grid.check(DecorCatalog.get_item("bush"), path_cell, 0, []), DecorGrid.REASON_PLACE)


func test_only_alone() -> void:
	var village := _village()
	var owner := Node.new()
	var script := GDScript.new()
	script.source_code = "extends Node\nvar game_mode: GameMode = GameMode.quick(2)\n"
	script.reload()
	owner.set_script(script)
	owner.add_to_group(GameMode.OWNER_GROUP)
	add_child_autofree(owner)
	assert_false(DecorStation.can_decorate(village), "group session")
	var player := _player(Vector2(600, 600))
	assert_null(village.open_decor_editor(player), "no decorating in a group")
	owner.remove_from_group(GameMode.OWNER_GROUP)
	assert_true(DecorStation.can_decorate(village))


func test_a_guest_sees_the_hosts_village() -> void:
	var village := _village()
	var grid := village.decor_layer.grid
	var cell := _free_cell(grid, Vector2.ZERO, DecorCatalog.get_item("flint_statue"))
	var host := {"village": [DecorState.format("flint_statue", cell, 0)], "home": []}
	village.apply_host_decor(host)
	assert_true(village.decor_layer.is_showing_snapshot())
	assert_eq(village.decor_layer.get_pieces().size(), 1, "the host's statue")
	assert_true(SaveManager.get_decor_placements(DecorState.VILLAGE).is_empty(), "the guest's save stays untouched")
	SaveManager.set_decor_owned("bush", 1)
	await wait_process_frames(2)
	assert_eq(village.decor_layer.get_pieces()[0].item.id, "flint_statue", "own changes do not replace the host's view")
	village.apply_host_decor({})
	assert_false(village.decor_layer.is_showing_snapshot())

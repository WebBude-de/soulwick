extends SceneTree

## Screenshots for a look check of WK5 and WK7 (not a GUT test, GUT only scans tests/unit): the
## village with placed decoration, the decorating mode with a held piece, the catalog, and the home
## in the cozy start, rustic and soul looks (wallpaper, floor and furniture of each style).
## Needs a renderer: run it in the invisible compositor (AGENTS.md §7), never as a visible window:
##   SOULWICK_QUIET=1 tools/godot_offscreen.sh --audio-driver Dummy --path . -s tests/manual/test_decor_shots.gd -- <folder>
## For daylight pictures start it with a time zone where it is day (e.g. TZ=Etc/GMT-14).
## Own save, settings and account files (never the real save, AGENTS.md rule 4).

const SAVE_PATH := "user://decor_shots_save.cfg"
const SETTINGS_PATH := "user://decor_shots_settings.cfg"
const PROGRESS_PATH := "user://decor_shots_progress.cfg"
## Village decoration for the picture, nearest free tiles around the home first.
const VILLAGE_PIECES := ["flower_bed_red", "flower_bed_yellow", "flower_bed_violet", "flower_bed_white",
	"lamp_post", "flint_statue", "bench_outdoor", "tree_small", "hedge_straight", "hedge_straight",
	"fire_bowl", "well_small", "bird_bath", "scarecrow", "pumpkins", "guild_banner", "string_lights_posts",
	"pond_small", "fence_straight", "fence_straight", "fence_gate", "paving_1", "paving_2", "stepping_stones",
	"chicken_statue", "torch_post", "signpost", "bush"]
## Home looks: style -> pieces placed besides the starter set (cell, rot).
const HOME_LOOKS := {
	"rustic": [["sofa_rustic", Vector2i(6, 5), 0], ["tea_table_rustic", Vector2i(7, 4), 0],
		["rug_large_rustic", Vector2i(6, 3), 0],
		["window_box_rustic", Vector2i(5, 1), 0]],
	"soul": [["bed_double_soul", Vector2i(1, 2), 0], ["reading_nook_soul", Vector2i(8, 4), 0],
		["chair_soul", Vector2i(6, 3), 1], ["flint_candleholder_soul", Vector2i(9, 6), 0],
		["runner_soul", Vector2i(7, 6), 0], ["trophy_soul", Vector2i(3, 6), 0]],
}
## Starter pieces a look leaves out (the soul bed is double, KE8b room 11×7).
const SOUL_SKIPS: Array[String] = ["bed_single", "armchair", "nightstand"]

var _out_dir := "user://decor_shots"
var _taken: Array[String] = []
## Loaded after the first frame (class names in a -s script compile before the autoloads exist).
var _catalog: Script = null
var _state: Script = null
var _grid_script: Script = null


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir) if _out_dir.begins_with("user://") else _out_dir)
	TranslationServer.set_locale("de")
	_catalog = load("res://meta/decor_catalog.gd")
	_state = load("res://meta/decor_state.gd")
	_grid_script = load("res://meta/decor_grid.gd")
	for path in [SAVE_PATH, PROGRESS_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var account: Script = load("res://meta/account_progress.gd")
	account.path_override = PROGRESS_PATH
	account.reset()
	var save_manager := root.get_node("SaveManager")
	save_manager.save_path = SAVE_PATH
	save_manager.load_game()
	save_manager.settings_path = SETTINGS_PATH
	save_manager.load_settings()
	save_manager.set_option(&"language", "de")
	save_manager.add_permanent_gold(20000)
	# Flint's explanations would cover the pictures: seen.
	for id in [&"flint_decor_village", &"flint_decor_home", &"flint_home_altar", &"flint_home_decor_spot"]:
		save_manager.mark_seen(id)
	save_manager.save_game()
	change_scene_to_file("res://scenes/game.tscn")
	await _frames(30)
	var controller := current_scene.get_node("WorldController")
	var village: Node = controller.get_world()
	var player: Node2D = controller.get_local_player()
	var guide: Node = player.get_node_or_null(^"FlintGuide")
	if guide != null:
		guide.cancel_all()
	_place_village_decor(village, village.get_node(^"Buildings/Home").global_position)
	await _frames(20)
	player.global_position = village.get_node(^"Buildings/Home").global_position + Vector2(-40, 150)
	(player.get_node(^"Camera2D") as Camera2D).reset_smoothing()
	await _frames(40)
	_shot("01_village_decor")
	# The decorating mode with a held piece (the ghost) and its bar.
	var editor: Node = village.open_decor_editor(player)
	save_manager.set_decor_owned("lamp_post", save_manager.get_decor_owned("lamp_post") + 1)
	editor.hold_from_storage("lamp_post")
	editor.set_cursor(editor.cursor + Vector2i(2, 1))
	await _frames(30)
	_shot("02_village_editor_ghost")
	editor.set_cursor(editor.grid.cell_at(village.get_node(^"Buildings/Home").global_position))
	await _frames(20)
	_shot("03_village_editor_refused")
	editor.cancel_held()
	editor.open_catalog()
	await _frames(30)
	_shot("04_village_catalog")
	_finish_modals(root)
	await _frames(10)
	editor.close()
	await _frames(20)
	# Into the home: the cozy start.
	village.enter_building(&"home")
	await _seconds(1.0)
	await _frames(30)
	var home: Node = controller.get_world()
	if guide != null and is_instance_valid(guide):
		guide.cancel_all()
	player = controller.get_local_player()
	await _frames(30)
	_shot("05_home_cozy_start")
	var home_editor: Node = home.open_decor_editor(player)
	home_editor.set_cursor(Vector2i(1, 5))
	home_editor.primary()
	home_editor.set_cursor(Vector2i(3, 5))
	await _frames(20)
	_shot("06_home_editor_move_chest")
	home_editor.cancel_held()
	home_editor.open_catalog()
	await _frames(10)
	var dialog_modal := root.find_child("DecorCatalogModal", true, false)
	if dialog_modal != null:
		dialog_modal.find_child("Tab_seating", true, false).pressed.emit()
		await _frames(5)
		dialog_modal = root.find_child("DecorCatalogModal", true, false)
		dialog_modal.find_child("Style_soul", true, false).pressed.emit()
	await _frames(20)
	_shot("07_home_catalog_soul_seating")
	_finish_modals(root)
	await _frames(10)
	home_editor.close()
	for style in ["rustic", "soul"]:
		_home_look(save_manager, style)
		await _frames(40)
		_shot("08_home_%s" % style)
	for path in [SAVE_PATH, PROGRESS_PATH, SETTINGS_PATH, SAVE_PATH + ".prev.bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("shots: ", ", ".join(_taken))
	quit(0)


## Buys and places VILLAGE_PIECES on the free tiles nearest to near (outside the home's door circle).
func _place_village_decor(village: Node, near: Vector2) -> void:
	var grid: Object = village.decor_layer.grid
	var cells: Array = grid.floor_cells.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (Vector2(a) * grid.tile).distance_to(near) < (Vector2(b) * grid.tile).distance_to(near))
	for id: String in VILLAGE_PIECES:
		var item: Object = _catalog.get_item(id)
		if item == null:
			continue
		_state.buy(id)
		for cell: Vector2i in cells:
			if grid.check(item, cell, 0, _state.placements(&"village")) == &"":
				_state.place(&"village", id, cell, 0)
				break


## Wallpaper, floor and the style's furniture (starter set swapped to the style where it exists).
func _home_look(save_manager: Node, style: String) -> void:
	for surface in ["wall", "floor"]:
		_state.buy(_catalog.surface_id(surface, style))
	_state.set_surface_style("home_wall", style)
	_state.set_surface_style("home_floor", style)
	var list := PackedStringArray()
	for entry: String in _state.STARTER_HOME:
		var parsed: Dictionary = _state.parse(entry)
		var id := String(parsed["id"]).replace("_cozy", "_" + style)
		if style == "soul" and SOUL_SKIPS.any(func(prefix: String) -> bool: return id.begins_with(prefix)):
			continue
		save_manager.set_decor_owned(id, maxi(1, save_manager.get_decor_owned(id)))
		list.append(_state.format(id, parsed["cell"], int(parsed["rot"])))
	for piece: Array in HOME_LOOKS[style]:
		save_manager.set_decor_owned(piece[0], save_manager.get_decor_owned(piece[0]) + 1)
		var item: Object = _catalog.get_item(piece[0])
		var placements: Array[Dictionary] = _state.parse_list(list)
		if item != null and _grid_script.for_home().check(item, piece[1], piece[2], placements) == &"":
			list.append(_state.format(piece[0], piece[1], piece[2]))
		else:
			print("left out ", piece[0], " at ", piece[1])
	save_manager.set_decor_placements(&"home", list)


func _finish_modals(node: Node) -> void:
	for child in node.get_children():
		if child.get_script() != null and child.get_script().get_global_name() == &"Modal":
			child.finish("")
		else:
			_finish_modals(child)


func _shot(shot_name: String) -> void:
	_taken.append(shot_name)
	var image := root.get_viewport().get_texture().get_image()
	var folder := ProjectSettings.globalize_path(_out_dir) if _out_dir.begins_with("user://") else _out_dir
	image.save_png(folder.path_join(shot_name + ".png"))


func _seconds(duration: float) -> void:
	await create_timer(duration, true, false, true).timeout


func _frames(count: int) -> void:
	for i in count:
		await physics_frame

extends SceneTree

## Screenshots for a look check of the home (KE8b, not a GUT test, GUT only scans tests/unit): the
## small room by day, at dusk and at night (the windows and the light follow the time of day), the
## first visit with Flint pointing at the catalog stand, the decorating mode with a held piece and
## the catalog. Needs a renderer: run it in the invisible compositor (AGENTS.md §7):
##   SOULWICK_QUIET=1 tools/godot_offscreen.sh --audio-driver Dummy --path . -s tests/manual/home_shots.gd -- <folder>
## Own save, settings and account files (never the real save, AGENTS.md rule 4).

const SAVE_PATH := "user://home_shots_save.cfg"
const SETTINGS_PATH := "user://home_shots_settings.cfg"
const PROGRESS_PATH := "user://home_shots_progress.cfg"

var _out_dir := "user://home_shots"
var _taken: Array[String] = []


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir) if _out_dir.begins_with("user://") else _out_dir)
	TranslationServer.set_locale("de")
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
	save_manager.add_permanent_gold(800)
	# The village tour and the altar tour are seen (an old account like the playtest's); the stand's
	# hint is not.
	var seen: Script = load("res://meta/account_seen.gd")
	for id in [&"flint_village_tour", &"flint_home_altar", &"flint_decor_village"]:
		seen.mark_seen(id)
	save_manager.save_game()
	change_scene_to_file("res://scenes/game.tscn")
	await _frames(30)
	var controller := current_scene.get_node("WorldController")
	var village: Node = controller.get_world()
	var player: Node2D = controller.get_local_player()
	var guide: Node = player.get_node_or_null(^"FlintGuide")
	if guide != null:
		guide.cancel_all()
	await _frames(10)
	village.enter_building(&"home")
	await _seconds(1.0)
	await _frames(20)
	var home: Node = controller.get_world()
	player = controller.get_local_player()
	home.pin_night(0.0)
	await _seconds(2.5)
	_shot("01_home_first_visit_hint_day")
	guide = player.get_node_or_null(^"FlintGuide")
	if guide != null:
		guide.cancel_all()
	await _frames(40)
	_shot("02_home_day")
	home.pin_night(0.55)
	await _frames(30)
	_shot("03_home_dusk")
	home.pin_night(1.0)
	await _frames(30)
	_shot("04_home_night")
	home.pin_night(0.0)
	await _frames(10)
	var editor: Node = home.open_decor_editor(player)
	await _frames(5)
	if guide != null and is_instance_valid(guide):
		guide.cancel_all()
	save_manager.set_decor_owned("sofa_cozy", 1)
	editor.hold_from_storage("sofa_cozy")
	editor.set_cursor(Vector2i(7, 5))
	await _frames(30)
	_shot("05_home_editor_ghost")
	editor.cancel_held()
	editor.open_catalog()
	await _frames(30)
	_shot("06_home_catalog")
	_finish_modals(root)
	await _frames(10)
	editor.close()
	await _frames(30)
	_shot("07_home_after_editor_no_arrow")
	# A piece in the last row stands behind the front wall, not on it.
	var state: Script = load("res://meta/decor_state.gd")
	save_manager.set_decor_owned("chest_cozy", 2)
	state.place(&"home", "chest_cozy", Vector2i(8, 6), 0)
	await _frames(30)
	_shot("08_home_last_row_behind_wall")
	for path in [SAVE_PATH, PROGRESS_PATH, SETTINGS_PATH, SAVE_PATH + ".prev.bak", PROGRESS_PATH + ".prev.bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("shots: ", ", ".join(_taken))
	quit(0)


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

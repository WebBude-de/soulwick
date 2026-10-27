extends SceneTree

## Screenshots for a look check of the village reports of 23.10.2026 and WK12: Flint's tour ring at
## the forge (pixel look, #2e95d42c), feeding a chicken and petting the cat (hearts, call, Flint's
## first comment), and the player pushed into the south-west corner (#7539cc72). Needs a renderer:
## run it in the invisible compositor (AGENTS.md §7), never as a visible window:
##   SOULWICK_QUIET=1 tools/godot_offscreen.sh --audio-driver Dummy --path . -s tests/manual/village_animal_shots.gd -- <folder>
## Own save, settings and account files (never the real save, AGENTS.md rule 4).

const SAVE_PATH := "user://village_animal_shots_save.cfg"
const SETTINGS_PATH := "user://village_animal_shots_settings.cfg"
const PROGRESS_PATH := "user://village_animal_shots_progress.cfg"

var _out_dir := "user://village_animal_shots"
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
	var tour_script: Script = load("res://world/village/village_tour.gd")
	tour_script.force_in_scripts = true
	change_scene_to_file("res://scenes/game.tscn")
	await _frames(30)
	var controller := current_scene.get_node("WorldController")
	var village: Node = controller.get_world()
	var player: Node2D = controller.get_local_player()
	var guide: Node = player.get_node_or_null(^"FlintGuide")
	if guide == null:
		print("no tour started")
		quit(1)
		return
	# Through the tour until Flint talks about the forge, then the ring at the forge.
	var forge: Node = village.get_node(^"Buildings/Forge")
	var marker: Node = village.get_node_or_null(^"VillageTour")
	for i in 3000:
		await physics_frame
		if marker != null and marker.get_focus() == forge:
			break
		if guide.phase == 2 and i % 40 == 0:
			guide.press()
			guide.press()
	await _frames(70)
	_shot("01_tour_ring_forge")
	guide.cancel_all()
	await _frames(40)
	# Feeding the first chicken (Flint's first comment comes with it).
	var chicken: Node2D = village.get_node(^"Villagers/Chicken1")
	await _react(player, chicken, Vector2(-34, 6))
	_shot("02_chicken_fed")
	await _frames(40)
	_shot("03_chicken_later")
	guide.cancel_all()
	var cat: Node2D = village.get_node(^"Villagers/Cat")
	await _react(player, cat, Vector2(-34, 0))
	await _frames(12)
	_shot("04_cat_petted")
	guide.cancel_all()
	# Into the south-west corner of the map, walking and dashing.
	var input: RefCounted = load("res://player/input/remote_input.gd").new()
	player.input = input
	player.global_position = Vector2(110, 1180)
	input.set_move(Vector2(-1, 1).normalized())
	for i in 90:
		if i % 7 == 0:
			input.tap(&"dash")
		await physics_frame
	input.set_move(Vector2.LEFT)
	await _frames(30)
	_shot("05_corner_south_west")
	print("player in the corner at ", player.global_position)
	for path in [SAVE_PATH, PROGRESS_PATH, SETTINGS_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("shots: ", ", ".join(_taken))
	quit(0)


## Puts the player beside the animal (offset from its feet) and lets the animal react.
func _react(player: Node2D, animal: Node2D, offset: Vector2) -> void:
	await _frames(2)
	player.global_position = animal.get_feet_global() - Vector2(0, 16) + offset
	await _frames(20)
	player.global_position = animal.get_feet_global() - Vector2(0, 16) + offset
	print(animal.name, " reacts: ", animal.get_animal().react(player))
	await _frames(14)


func _shot(shot_name: String) -> void:
	_taken.append(shot_name)
	var image := root.get_viewport().get_texture().get_image()
	var folder := ProjectSettings.globalize_path(_out_dir) if _out_dir.begins_with("user://") else _out_dir
	image.save_png(folder.path_join(shot_name + ".png"))


func _frames(count: int) -> void:
	for i in count:
		await physics_frame

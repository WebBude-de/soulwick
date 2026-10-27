extends SceneTree

## Screenshots of the practice run (WK10) for a look check: village -> dungeon with the practice
## run forced, the autopilot (TutorialBot) plays it, a picture at the welcome and at every station
## (side view included) and at the gate. Needs a renderer: run it in the invisible compositor
## (AGENTS.md §7), never as a visible window:
##   SOULWICK_QUIET=1 tools/godot_offscreen.sh --path . -s tests/manual/tutorial_shots.gd -- <folder>
## Own save and settings files (never the real save, AGENTS.md rule 4).

const SAVE_PATH := "user://tutorial_shots_save.cfg"
const TUTORIAL_PATH := "res://dungeon/tutorial/tutorial_run.gd"
## Longest the bot may take (s at 60 fps).
const TIMEOUT := 150.0

var _out_dir := "user://tutorial_shots"
var _taken: Array[String] = []


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir) if _out_dir.begins_with("user://") else _out_dir)
	TranslationServer.set_locale("de")
	var save_manager := root.get_node("SaveManager")
	save_manager.save_path = SAVE_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	save_manager.load_game()
	save_manager.settings_path = "user://tutorial_shots_settings.cfg"
	save_manager.load_settings()
	save_manager.set_option(&"language", "de")
	change_scene_to_file("res://scenes/game.tscn")
	await _frames(20)
	var controller := current_scene.get_node("WorldController")
	load(TUTORIAL_PATH).force_next = true
	node_added.connect(_on_node_added)
	controller.enter_dungeon()
	await _frames(20)
	var dungeon: Node = controller.get_world()
	var run: Node = load(TUTORIAL_PATH).of(dungeon)
	if run == null:
		print("no practice run started")
		quit(1)
		return
	await _frames(70)
	_shot("01_welcome")
	var bot: Node = load("res://dungeon/tutorial/tutorial_bot.gd").drive(run)
	var stage := ""
	var side_frames := 0
	var frames := 0
	while is_instance_valid(run) and not run.is_finished and frames < int(TIMEOUT * 60.0):
		await physics_frame
		frames += 1
		if not is_instance_valid(bot):
			break
		if bot.stage != stage:
			stage = bot.stage
			print("stage: ", stage)
		if stage.begins_with("hitting") and not _taken.has("02_attack"):
			await _frames(20)
			_shot("02_attack")
		elif stage == "dash over the abyss" and not _taken.has("03_dash"):
			_shot("03_dash")
		elif stage == "jump (side view)":
			side_frames += 1
			if side_frames == 150:
				_shot("04_jump_side")
			elif side_frames == 420:
				_shot("05_jump_side_later")
		elif stage.begins_with("shield dummy") and not _taken.has("06_special"):
			await _frames(10)
			_shot("06_special")
		elif stage == "to the gate" and not _taken.has("07_finish"):
			await _frames(30)
			_shot("07_finish")
	await _frames(40)
	_shot("08_room_1")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("shots: ", ", ".join(_taken))
	quit(0)


func _on_node_added(node: Node) -> void:
	if node.get_script() == null or not node.get_script().resource_path.ends_with("dungeon_manager.gd"):
		return
	node_added.disconnect(_on_node_added)
	node.ready.connect(func() -> void: load(TUTORIAL_PATH).begin(node), CONNECT_ONE_SHOT)


func _shot(shot_name: String) -> void:
	_taken.append(shot_name)
	var image := root.get_viewport().get_texture().get_image()
	var folder := ProjectSettings.globalize_path(_out_dir) if _out_dir.begins_with("user://") else _out_dir
	image.save_png(folder.path_join(shot_name + ".png"))


func _frames(count: int) -> void:
	for i in count:
		await physics_frame

extends SceneTree

## Screenshots of the one Flint for the group (WK13, D-225) for a look check: solo in the village and
## in the first dungeon room (Flint as before), then a local group of two (GameMode.quick(2, [0, 1]))
## in the dungeon and in the village: two players, one Flint between them. Also counts the Flint
## nodes of each world (must be 1) and prints where he hovers. Needs a renderer: run it in the
## invisible compositor (AGENTS.md §7), never as a visible window:
##   SOULWICK_QUIET=1 tools/godot_offscreen.sh --audio-driver Dummy --path . -s tests/manual/flint_group_shots.gd -- <folder>
## Own save and settings files (never the real save, AGENTS.md rule 4).

const SAVE_PATH := "user://flint_group_shots_save.cfg"
const SETTINGS_PATH := "user://flint_group_shots_settings.cfg"
## Loaded at run time: scripts started with -s cannot name classes that need the autoloads.
const FLINT_PATH := "res://companions/flint/flint_companion.gd"

var _out_dir := "user://flint_group_shots"
var _taken: Array[String] = []
var _problems: Array[String] = []


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_folder())
	TranslationServer.set_locale("de")
	var save_manager := root.get_node("SaveManager")
	save_manager.save_path = SAVE_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	save_manager.load_game()
	save_manager.settings_path = SETTINGS_PATH
	save_manager.load_settings()
	save_manager.set_option(&"language", "de")
	# No practice run in the pictures (it would hold the solo dungeon).
	load("res://meta/account_seen.gd").mark_seen(&"flint_tutorial")
	change_scene_to_file("res://scenes/game.tscn")
	await _frames(30)
	var controller: Node = current_scene.get_node("WorldController")
	# The first read of the viewport texture can come back black (tool only).
	root.get_viewport().get_texture().get_image()
	await _frames(90)
	_check_world(controller, 1)
	_shot("01_solo_village")
	controller.enter_dungeon()
	await _frames(150)
	_check_world(controller, 1)
	_shot("02_solo_dungeon")

	controller.set_game_mode(load("res://scenes/game_mode.gd").quick(2, [0, 1] as Array[int]))
	controller.load_world(controller.dungeon_scene)
	await _frames(60)
	_walk_group(controller, Vector2(90, 0))
	await _frames(120)
	_check_world(controller, 2)
	_shot("03_coop_dungeon")
	_walk_group(controller, Vector2(0, 180))
	await _frames(120)
	_shot("04_coop_dungeon_apart")
	controller.load_world(controller.village_scene)
	await _frames(60)
	_walk_group(controller, Vector2(110, 40))
	await _frames(150)
	_check_world(controller, 2)
	_shot("05_coop_village")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	print("shots: ", ", ".join(_taken))
	if not _problems.is_empty():
		print("PROBLEMS: ", "; ".join(_problems))
		quit(1)
		return
	quit(0)


## The second player stands offset from the first (a local co-op player without input stays put).
func _walk_group(controller: Node, offset: Vector2) -> void:
	var players: Array = controller.get_players()
	if players.size() >= 2:
		players[1].global_position = players[0].global_position + offset


## Exactly one Flint in the world and every player is his member.
func _check_world(controller: Node, expected_players: int) -> void:
	var world: Node = controller.get_world()
	var flints: Array[Node] = []
	for node in world.find_children("*", "Node2D", true, false):
		if node.get_script() == load(FLINT_PATH):
			flints.append(node)
	var players: Array = controller.get_players()
	if flints.size() != 1:
		_problems.append("%s: %d Flints" % [world.name, flints.size()])
		return
	var flint: Node = flints[0]
	if players.size() != expected_players:
		_problems.append("%s: %d players, expected %d" % [world.name, players.size(), expected_players])
	for player in players:
		if load(FLINT_PATH).of(player) != flint:
			_problems.append("%s: player %d has another Flint" % [world.name, player.player_id])
	var spots := PackedStringArray()
	for player in players:
		spots.append("P%d %s" % [player.player_id + 1, player.global_position.round()])
	print("%s: 1 Flint at %s (group point %s), %s" % [world.name, flint.get_follow_position().round(),
			flint.get_anchor().round(), ", ".join(spots)])


func _shot(shot_name: String) -> void:
	_taken.append(shot_name)
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(_folder().path_join(shot_name + ".png"))


func _folder() -> String:
	return ProjectSettings.globalize_path(_out_dir) if _out_dir.begins_with("user://") else _out_dir


func _frames(count: int) -> void:
	for i in count:
		await physics_frame

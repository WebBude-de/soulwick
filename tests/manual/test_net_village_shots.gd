extends SceneTree

## Screenshots of "Gäste sehen das Dorf des Hosts" (WK5 Koop, NetVillage) for a look check, in one
## process: the host's village with its decoration and a coloured guild banner, the guest's village
## with its own decoration, then the guest's village after NetVillage took the host's snapshot (the
## same path the network takes: build_snapshot on the host, receive with the defensive check on the
## guest) and after the room ended (own decoration back). The transport itself is checked by
## tools/net_run_smoke.gd with SOULWICK_NET_VILLAGE_LOG=1. Not a GUT test (tests/manual). Needs a
## renderer: run it in the invisible compositor (AGENTS.md §7), never as a visible window:
##   SOULWICK_QUIET=1 tools/godot_offscreen.sh --audio-driver Dummy --path . -s tests/manual/test_net_village_shots.gd -- <folder>
## Own save and settings files (never the real save, AGENTS.md rule 4).

const SAVE_PATH := "user://net_village_shots_save.cfg"
const SETTINGS_PATH := "user://net_village_shots_settings.cfg"
## Loaded at run time: scripts started with -s cannot name classes that need the autoloads.
const NET_VILLAGE_PATH := "res://online/net_village.gd"
const DECOR_STATE_PATH := "res://meta/decor_state.gd"
const DECOR_PIECE_PATH := "res://world/village/decor/decor_piece.gd"
const DECOR_CATALOG_PATH := "res://meta/decor_catalog.gd"
## The host's banner colour in the pictures (the API has no guild colour yet).
const HOST_GUILD_COLOR := Color("#c0392b")
const HOST_ITEMS: Array[String] = ["guild_banner", "flint_statue", "lamp_post", "fire_bowl", "flower_bed_red", "bench_outdoor"]
const GUEST_ITEMS: Array[String] = ["scarecrow", "pumpkins", "bush", "bird_bath"]

var _out_dir := "user://net_village_shots"
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
	load("res://meta/account_seen.gd").mark_seen(&"flint_tutorial")
	change_scene_to_file("res://scenes/game.tscn")
	await _frames(30)
	var controller: Node = current_scene.get_node("WorldController")
	root.get_viewport().get_texture().get_image()
	await _frames(60)
	var piece_script: GDScript = load(DECOR_PIECE_PATH)
	var state: GDScript = load(DECOR_STATE_PATH)
	var net_script: GDScript = load(NET_VILLAGE_PATH)

	# Host: its decoration around the spawn, banner in the guild's colour.
	_place_around_spawn(controller, save_manager, HOST_ITEMS)
	piece_script.set(&"guild_color", HOST_GUILD_COLOR)
	controller.get_world().decor_layer.rebuild()
	await _frames(90)
	_shot("01_host_village")
	var snapshot: Dictionary = net_script.build_snapshot(state.snapshot(), HOST_GUILD_COLOR)
	print("snapshot: %d bytes, %d village pieces" % [var_to_bytes(snapshot).size(), (snapshot["village"] as Array).size()])

	# Guest: another world, its own decoration and no guild.
	save_manager.set_decor_placements(&"village", PackedStringArray())
	controller.load_world(controller.village_scene)
	await _frames(30)
	_place_around_spawn(controller, save_manager, GUEST_ITEMS)
	await _frames(90)
	_shot("02_guest_own_village")
	var village: Node = controller.get_world()
	var net: Node = net_script.attach(village)
	net.host_check = func() -> bool: return false
	var live := [true]
	net.connected_check = func() -> bool: return live[0]
	if not net.receive(snapshot):
		_problems.append("the guest rejected the host's snapshot")
	await _frames(60)
	_shot("03_guest_sees_host_village")
	_expect_pieces(village, HOST_ITEMS.size(), "guest with the host's village")
	if piece_script.get(&"guild_color") != HOST_GUILD_COLOR:
		_problems.append("guest banner colour %s" % str(piece_script.get(&"guild_color")))
	live[0] = false
	await _frames(60)
	_shot("04_guest_room_ended")
	_expect_pieces(village, GUEST_ITEMS.size(), "guest after the room")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	print("shots: ", ", ".join(_taken))
	if not _problems.is_empty():
		print("PROBLEMS: ", "; ".join(_problems))
		quit(1)
		return
	quit(0)


## Owns and places items on free cells of the village grid near the local player (the grid's own
## check, nearest first, below the player so the camera shows them).
func _place_around_spawn(controller: Node, save_manager: Node, ids: Array[String]) -> void:
	var village: Node = controller.get_world()
	var layer: Node = village.decor_layer
	var grid: RefCounted = layer.grid
	var player: Node2D = controller.get_player()
	var feet: Vector2 = player.global_position
	var catalog: GDScript = load(DECOR_CATALOG_PATH)
	var state: GDScript = load(DECOR_STATE_PATH)
	var cells: Array = grid.floor_cells.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (Vector2(a) * grid.tile).distance_to(feet) < (Vector2(b) * grid.tile).distance_to(feet))
	for id in ids:
		var item: RefCounted = catalog.get_item(id)
		if item == null:
			_problems.append("no catalog item %s" % id)
			continue
		save_manager.set_decor_owned(id, save_manager.get_decor_owned(id) + 1)
		for cell: Vector2i in cells:
			if grid.check(item, cell, 0, state.placements(&"village"), -1, [feet] as Array[Vector2]) == &"":
				state.place(&"village", id, cell, 0)
				break
	layer.rebuild()


func _expect_pieces(village: Node, count: int, what: String) -> void:
	var shown: int = village.decor_layer.get_pieces().size()
	print("%s: %d pieces" % [what, shown])
	if shown != count:
		_problems.append("%s: %d pieces, expected %d" % [what, shown, count])


func _shot(shot_name: String) -> void:
	_taken.append(shot_name)
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(_folder().path_join(shot_name + ".png"))


func _folder() -> String:
	return ProjectSettings.globalize_path(_out_dir) if _out_dir.begins_with("user://") else _out_dir


func _frames(count: int) -> void:
	for i in count:
		await physics_frame

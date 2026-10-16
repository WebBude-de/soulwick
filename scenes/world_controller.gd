class_name WorldController
extends Node
## Owns the active world (village or dungeon) under game.tscn and spawns fresh players from
## player.tscn on every world change (D-041). Rooms inside the dungeon keep those players.
## Several players (MP1): the session (game_mode) says how many players there are and which of
## them sit at this machine. Every player gets an input object of its own; camera, HUD, vision and
## the run recap follow the local player only. A host without a player of its own (later a headless
## server) has local_player == null and binds no UI. hud, game_ui and vision may be null (tests).

signal player_spawned(player: Player)

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const PLAYER_SPAWN_NODE := "PlayerSpawn"
const MAIN_MENU_PATH := "res://scenes/main.tscn"
## Where the players of a group stand around the spawn marker, by spawn order (TESTWERT).
const SPAWN_OFFSETS: Array[Vector2] = [Vector2.ZERO, Vector2(-32, 0), Vector2(32, 0), Vector2(0, -32)]
## Menu protection of the local player in group games (D-085): input lock and invulnerability.
const MENU_PROTECTION: StringName = &"menu"

@export var world_root: Node2D
@export var hud: Hud
@export var game_ui: GameUI
@export var vision: VisionOverlay
@export var village_scene: PackedScene
@export var dungeon_scene: PackedScene

## The session (D-080, D-085): solo unless a lobby or a tool sets another mode. Takes effect for
## pauses and hit stops at once, for the players at the next world change.
var game_mode: GameMode = GameMode.solo()
## All players of the current world, in spawn order (the primary player first).
var players: Array[Player] = []
## The player at this machine (camera, HUD, vision); null on a host without a player of its own.
var local_player: Player = null

var _world: Node = null


func _ready() -> void:
	add_to_group(GameMode.OWNER_GROUP)
	# Also when game.tscn is started directly (editor F6) instead of through the main menu.
	GameOptions.apply_all()
	GameCursor.use_crosshair()
	GameManager.pause_changed.connect(_on_pause_changed)
	EventBus.run_ended.connect(_on_run_ended)
	if game_ui != null:
		game_ui.abort_run_requested.connect(_on_abort_requested)
		game_ui.main_menu_requested.connect(_on_main_menu_requested)
	# Deferred so sibling UI nodes are ready before the first player gets bound.
	load_world.call_deferred(village_scene)


## The local player (camera, HUD, vision); null on a host without a player of its own.
func get_player() -> Player:
	return local_player


func get_local_player() -> Player:
	return local_player


## Every player of the current world, local and remote, in spawn order.
func get_players() -> Array[Player]:
	return players.duplicate()


func set_game_mode(mode: GameMode) -> void:
	game_mode = mode if mode != null else GameMode.solo()
	# An open menu pauses the tree only in single player: apply the new session's rule now.
	GameManager.release_pause(&"")


func get_world() -> Node:
	return _world


func enter_dungeon() -> void:
	# MP2: a relay room shares the village only; the shared run follows with MP3.
	if game_mode.is_networked() and game_mode.network.has_method(&"on_dungeon_requested"):
		game_mode.network.on_dungeon_requested()
		return
	load_world(dungeon_scene)


func load_world(scene: PackedScene) -> void:
	_unload_world()
	GameManager.clear_pause_reasons()
	HitStop.reset()
	_world = scene.instantiate()
	# MP3: a relay room configures the world before it enters the tree (dungeon seed, NetDungeon).
	if game_mode.is_networked() and game_mode.network.has_method(&"configure_world"):
		game_mode.network.configure_world(_world)
	world_root.add_child(_world)
	var in_dungeon := _world is DungeonManager
	GameManager.set_phase(GameManager.Phase.DUNGEON if in_dungeon else GameManager.Phase.VILLAGE)
	if game_ui != null:
		game_ui.in_dungeon = in_dungeon
	if hud != null:
		hud.set_dungeon_mode(in_dungeon)
	if not in_dungeon:
		# The room catalogs load in the background while the village runs (dungeon start hitched
		# ~2 s, online test 16.10.2026).
		DungeonManager.preload_in_background()
	if vision != null and not in_dungeon:
		# The village follows the local clock (bright day, dark night with lit lamps); the dungeon
		# sets its darkness per room (D-067).
		var hour := VillageDaylight.current_hour()
		vision.set_dark_color(VillageDaylight.dark_color_for_hour(hour), true)
		vision.set_vision(VillageDaylight.darkness_for_hour(hour), VillageDaylight.VISION_RADIUS, true)
	if _world.has_signal(&"dungeon_requested"):
		_world.connect(&"dungeon_requested", enter_dungeon, CONNECT_DEFERRED)
	if hud != null and _world.has_signal(&"room_activated"):
		_world.connect(&"room_activated", func(room: RoomController) -> void:
			var next := room.get_next_biome() if room.is_campfire() else null
			hud.set_campfire(room.is_campfire(), Loc.t(StringName(next.display_name)) if next != null else ""))
	if hud != null and _world.has_signal(&"heal_countdown_changed"):
		_world.connect(&"heal_countdown_changed", hud.set_heal_countdown)
	_spawn_players()


func _unload_world() -> void:
	if _world == null:
		return
	world_root.remove_child(_world)
	_world.queue_free()
	_world = null
	players.clear()
	local_player = null


## One player per session member at the spawn marker (offsets for a group), the primary player
## first: worlds bind their single-player systems (shop, upgrade dialogs) to the first one.
func _spawn_players() -> void:
	# In a relay room the network spawns every player (MP2) and hands them to register_player.
	if game_mode.is_networked():
		game_mode.network.attach_world(self, _world)
		return
	var spawn := _world.find_child(PLAYER_SPAWN_NODE, true, false) as Node2D
	if spawn == null:
		push_warning("World '%s' has no %s marker; spawning at origin." % [_world.name, PLAYER_SPAWN_NODE])
	var origin := spawn.global_position if spawn != null else Vector2.ZERO
	var order := game_mode.get_spawn_order()
	for index in order.size():
		_spawn_player(order[index], origin + get_spawn_offset(index))


func _spawn_player(player_id: int, at: Vector2) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.player_id = player_id
	player.is_local = game_mode.is_local(player_id)
	player.input = game_mode.create_input(player_id)
	if player_id != game_mode.get_primary_player_id():
		player.name = "Player%d" % (player_id + 1)
	_world.add_child(player)
	player.global_position = at
	register_player(player)
	return player


## Takes a player that is already in the world (the network spawner adds them itself, MP2): player
## list, world hook, camera, HUD and vision for the local one.
func register_player(player: Player) -> void:
	if player == null or players.has(player):
		return
	players.append(player)
	if _world != null and _world.has_method(&"on_player_spawned"):
		_world.on_player_spawned(player)
	if player.is_local and local_player == null:
		local_player = player
		_bind_local_player(player)
		# A menu may already be open when a network player arrives (D-085).
		if GameManager.is_game_paused() and not game_mode.pauses_for_menus():
			player.set_protected(MENU_PROTECTION, true)
	player_spawned.emit(player)


## A network player leaves the world (peer gone, MP2).
func unregister_player(player: Player) -> void:
	players.erase(player)
	if local_player == player:
		local_player = null


## Offset of the index-th spawned player from the spawn marker.
static func get_spawn_offset(index: int) -> Vector2:
	return SPAWN_OFFSETS[index] if index >= 0 and index < SPAWN_OFFSETS.size() else Vector2.ZERO


## Camera, HUD, vision and run recap follow the player at this machine.
func _bind_local_player(player: Player) -> void:
	var camera := player.get_node("Camera2D") as Camera2D
	if _world.has_method(&"get_camera_limits"):
		var limits: Rect2i = _world.get_camera_limits()
		camera.limit_left = limits.position.x
		camera.limit_top = limits.position.y
		camera.limit_right = limits.end.x
		camera.limit_bottom = limits.end.y
	camera.make_current()
	camera.reset_smoothing()
	if hud != null:
		hud.bind_player(player)
	if game_ui != null:
		game_ui.bind_player(player)
	if vision != null:
		vision.bind_player(player)


## Run end screen (UX1): back to the village or straight into a new run.
func _on_run_ended(_reason: int, _remaining: int, _payout: int) -> void:
	if game_ui == null:
		return
	var choice := await game_ui.show_run_end(RunManager.get_last_summary())
	# A relay room goes back to the shared village; the host starts the next run there (MP3).
	var new_run := choice == GameUI.RUN_END_NEW_RUN and not game_mode.is_networked()
	load_world(dungeon_scene if new_run else village_scene)


func _on_abort_requested() -> void:
	var dungeon := _world as DungeonManager
	if dungeon != null:
		dungeon.end_run(RunManager.EndReason.ABORT)


## is_paused: a menu is open. Single player: the tree is paused (D-043). Group games: the world
## runs on and the local player is protected while the menu is open (D-085).
func _on_pause_changed(is_paused: bool) -> void:
	if is_paused:
		GameCursor.use_pointer()
	else:
		GameCursor.use_crosshair()
	if local_player != null and is_instance_valid(local_player):
		local_player.set_protected(MENU_PROTECTION, is_paused and not game_mode.pauses_for_menus())


func _on_main_menu_requested() -> void:
	GameManager.change_scene(MAIN_MENU_PATH)

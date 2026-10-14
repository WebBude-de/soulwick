class_name WorldController
extends Node
## Owns the active world (village or dungeon) under game.tscn and spawns a fresh player from
## player.tscn on every world change (D-041). Rooms inside the dungeon keep that player.

signal player_spawned(player: Player)

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const PLAYER_SPAWN_NODE := "PlayerSpawn"
const MAIN_MENU_PATH := "res://scenes/main.tscn"

@export var world_root: Node2D
@export var hud: Hud
@export var game_ui: GameUI
@export var vision: VisionOverlay
@export var village_scene: PackedScene
@export var dungeon_scene: PackedScene

var _world: Node = null
var _player: Player = null


func _ready() -> void:
	# Also when game.tscn is started directly (editor F6) instead of through the main menu.
	GameOptions.apply_all()
	GameCursor.use_crosshair()
	GameManager.pause_changed.connect(_on_pause_changed)
	EventBus.run_ended.connect(_on_run_ended)
	game_ui.abort_run_requested.connect(_on_abort_requested)
	game_ui.main_menu_requested.connect(_on_main_menu_requested)
	# Deferred so sibling UI nodes are ready before the first player gets bound.
	load_world.call_deferred(village_scene)


func get_player() -> Player:
	return _player


func get_world() -> Node:
	return _world


func enter_dungeon() -> void:
	load_world(dungeon_scene)


func load_world(scene: PackedScene) -> void:
	_unload_world()
	GameManager.clear_pause_reasons()
	HitStop.reset()
	_world = scene.instantiate()
	world_root.add_child(_world)
	var in_dungeon := _world is DungeonManager
	GameManager.set_phase(GameManager.Phase.DUNGEON if in_dungeon else GameManager.Phase.VILLAGE)
	game_ui.in_dungeon = in_dungeon
	if hud != null:
		hud.set_dungeon_mode(in_dungeon)
	if vision != null and not in_dungeon:
		# The village follows the local clock (bright day, dark night with lit lamps); the dungeon
		# sets its darkness per room (D-067).
		var hour := VillageDaylight.current_hour()
		vision.set_dark_color(VillageDaylight.dark_color_for_hour(hour), true)
		vision.set_vision(VillageDaylight.darkness_for_hour(hour), VillageDaylight.VISION_RADIUS, true)
	if _world.has_signal(&"dungeon_requested"):
		_world.connect(&"dungeon_requested", enter_dungeon, CONNECT_DEFERRED)
	if hud != null and _world.has_signal(&"heal_countdown_changed"):
		_world.connect(&"heal_countdown_changed", hud.set_heal_countdown)
	_spawn_player()


func _unload_world() -> void:
	if _world == null:
		return
	world_root.remove_child(_world)
	_world.queue_free()
	_world = null
	_player = null


func _spawn_player() -> void:
	var spawn := _world.find_child(PLAYER_SPAWN_NODE, true, false) as Node2D
	if spawn == null:
		push_warning("World '%s' has no %s marker; spawning at origin." % [_world.name, PLAYER_SPAWN_NODE])
	_player = PLAYER_SCENE.instantiate() as Player
	_world.add_child(_player)
	_player.global_position = spawn.global_position if spawn != null else Vector2.ZERO
	if _world.has_method(&"on_player_spawned"):
		_world.on_player_spawned(_player)
	if _world.has_method(&"get_camera_limits"):
		var limits: Rect2i = _world.get_camera_limits()
		var camera := _player.get_node("Camera2D") as Camera2D
		camera.limit_left = limits.position.x
		camera.limit_top = limits.position.y
		camera.limit_right = limits.end.x
		camera.limit_bottom = limits.end.y
		camera.reset_smoothing()
	if hud != null:
		hud.bind_player(_player)
	game_ui.bind_player(_player)
	if vision != null:
		vision.bind_player(_player)
	player_spawned.emit(_player)


## Run end screen (UX1): back to the village or straight into a new run.
func _on_run_ended(_reason: int, _remaining: int, _payout: int) -> void:
	var choice := await game_ui.show_run_end(RunManager.get_last_summary())
	load_world(dungeon_scene if choice == GameUI.RUN_END_NEW_RUN else village_scene)


func _on_abort_requested() -> void:
	var dungeon := _world as DungeonManager
	if dungeon != null:
		dungeon.end_run(RunManager.EndReason.ABORT)


func _on_pause_changed(is_paused: bool) -> void:
	if is_paused:
		GameCursor.use_pointer()
	else:
		GameCursor.use_crosshair()


func _on_main_menu_requested() -> void:
	GameManager.change_scene(MAIN_MENU_PATH)

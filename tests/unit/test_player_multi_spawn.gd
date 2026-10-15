extends GutTest
## Several players in one world (MP1): the WorldController spawns one player per session member
## around the spawn marker, the primary player first; only the local player has the camera; remote
## players get RemoteInput; a host without a player of its own spawns everybody and binds no UI.
## Pause and HitStop follow the session (D-085, D-123): solo pauses the tree and freezes time as
## before, a group game keeps both running and protects the local player while a menu is open.

const TEST_SAVE_PATH := "user://test_player_multi_spawn.cfg"
const SPAWN_AT := Vector2(320, 240)

var _old_save_path: String
var _old_phase: GameManager.Phase
var _world_scene: PackedScene = null


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.load_game()
	_old_phase = GameManager.get_phase()
	_world_scene = _make_world_scene()


func after_each() -> void:
	GameManager.clear_pause_reasons()
	HitStop.reset()


func after_all() -> void:
	GameManager.set_phase(_old_phase)
	await wait_seconds(0.3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


## A minimal world: a Node2D with a PlayerSpawn marker.
static func _make_world_scene() -> PackedScene:
	var root := Node2D.new()
	root.name = "TestWorld"
	var spawn := Marker2D.new()
	spawn.name = WorldController.PLAYER_SPAWN_NODE
	spawn.position = SPAWN_AT
	root.add_child(spawn)
	spawn.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	return scene


## A WorldController without HUD, menus and vision (like a headless host) in the given mode.
func _controller(mode: GameMode) -> WorldController:
	var world_root := Node2D.new()
	add_child_autofree(world_root)
	var controller := WorldController.new()
	controller.world_root = world_root
	controller.village_scene = _world_scene
	controller.dungeon_scene = _world_scene
	controller.game_mode = mode
	add_child_autofree(controller)
	await wait_process_frames(2)
	return controller


func test_solo_spawns_one_local_player_like_before() -> void:
	var controller := await _controller(GameMode.solo())
	assert_eq(controller.players.size(), 1)
	var player := controller.get_player()
	assert_not_null(player)
	assert_eq(player, controller.local_player)
	assert_eq(player.name, "Player")
	assert_true(player.is_local)
	assert_true(player.input is LocalKeyboardMouseInput)
	assert_eq(player.global_position, SPAWN_AT)


func test_quick_game_spawns_every_player_around_the_marker() -> void:
	var controller := await _controller(GameMode.quick(4))
	var players := controller.get_players()
	assert_eq(players.size(), 4)
	var ids: Array[int] = []
	for index in players.size():
		var player := players[index]
		ids.append(player.player_id)
		assert_true(player.is_in_group(&"player"))
		assert_eq(player.global_position, SPAWN_AT + WorldController.get_spawn_offset(index))
	assert_eq(ids, [0, 1, 2, 3] as Array[int])
	assert_eq(controller.get_player(), players[0], "the local player is the primary one")
	assert_eq(EnemyTargeting.living_players(get_tree()).size(), 4, "enemies see every player")


func test_only_the_local_player_owns_camera_and_keyboard() -> void:
	var controller := await _controller(GameMode.quick(3))
	var local := controller.get_local_player()
	assert_true(local.input is LocalKeyboardMouseInput)
	var local_camera := local.get_node("Camera2D") as Camera2D
	assert_true(local_camera.enabled)
	assert_eq(controller.get_viewport().get_camera_2d(), local_camera, "the view follows the local player")
	for player in controller.players:
		if player == local:
			continue
		assert_false(player.is_local)
		assert_true(player.input is RemoteInput)
		assert_false((player.get_node("Camera2D") as Camera2D).enabled)


func test_local_player_may_have_any_id() -> void:
	var controller := await _controller(GameMode.quick(3, [2]))
	assert_eq(controller.players[0].player_id, 2, "the primary player spawns first")
	assert_eq(controller.get_player().player_id, 2)
	assert_eq(controller.players[0].global_position, SPAWN_AT)


func test_host_without_own_player_spawns_everybody_and_binds_nothing() -> void:
	var controller := await _controller(GameMode.quick(2, []))
	assert_eq(controller.players.size(), 2)
	assert_null(controller.get_player(), "server rule: no player of its own")
	for player in controller.players:
		assert_false(player.is_local)
		assert_true(player.input is RemoteInput)
		assert_false((player.get_node("Camera2D") as Camera2D).enabled)


func test_world_change_spawns_fresh_players_for_the_session() -> void:
	var controller := await _controller(GameMode.quick(2))
	var before: Array[int] = []
	for player in controller.players:
		before.append(player.get_instance_id())
	watch_signals(controller)
	controller.enter_dungeon()
	await wait_process_frames(2)
	assert_eq(controller.players.size(), 2)
	assert_signal_emit_count(controller, "player_spawned", 2)
	for player in controller.players:
		assert_false(before.has(player.get_instance_id()), "new instances (D-041)")


# --- Pause and HitStop per mode ---

func test_solo_menu_pauses_the_tree() -> void:
	var controller := await _controller(GameMode.solo())
	GameManager.request_pause(GameManager.PAUSE_SHOP)
	var paused := get_tree().paused
	var protected := controller.get_player().is_protected()
	GameManager.release_pause(GameManager.PAUSE_SHOP)
	assert_true(paused, "D-043 unchanged in single player")
	assert_false(protected, "the pause itself protects")
	assert_false(get_tree().paused)


func test_group_menu_keeps_the_world_running_and_protects_the_local_player() -> void:
	var controller := await _controller(GameMode.quick(2))
	var local := controller.get_player()
	var other := controller.players[1]
	watch_signals(GameManager)
	GameManager.request_pause(GameManager.PAUSE_UPGRADE_CHOICE)
	assert_false(get_tree().paused, "D-085: no global pause in a group game")
	assert_true(GameManager.is_game_paused(), "the menu is still known as open")
	assert_signal_emitted_with_parameters(GameManager, "pause_changed", [true])
	assert_true(local.is_protected())
	assert_true(local.is_input_locked(), "no attacks from inside a menu")
	assert_true(local.hurtbox.is_invulnerable(), "cannot be hit while in a menu")
	assert_false(other.is_protected(), "only the player with the menu")
	GameManager.release_pause(GameManager.PAUSE_UPGRADE_CHOICE)
	assert_false(local.is_protected())
	assert_false(local.is_input_locked())
	assert_false(local.hurtbox.is_invulnerable())
	assert_signal_emitted_with_parameters(GameManager, "pause_changed", [false])


func test_hit_stop_only_in_single_player() -> void:
	var solo := await _controller(GameMode.solo())
	HitStop.trigger(solo.get_player(), 0.2)
	var solo_scale := Engine.time_scale
	HitStop.reset()
	solo.queue_free()
	await wait_process_frames(1)
	var group := await _controller(GameMode.quick(2))
	HitStop.trigger(group.get_player(), 0.2)
	assert_lt(solo_scale, 1.0, "single player keeps the impact freeze")
	assert_eq(Engine.time_scale, 1.0, "D-085: the shared time never stops in a group game")

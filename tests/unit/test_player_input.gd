extends GutTest
## Input objects per player (MP1): RemoteInput turns held buttons and taps into frame state,
## LocalKeyboardMouseInput reads the InputMap, and Player/WeaponController act only on their input
## object (a player driven by RemoteInput walks, aims, dashes, attacks and uses its special).

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const TEST_SAVE_PATH := "user://test_player_input.cfg"

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.load_game()


func after_each() -> void:
	for action in PlayerInput.ACTIONS:
		Input.action_release(action)
	Input.action_release(LocalKeyboardMouseInput.MOVE_RIGHT)
	HitStop.reset()


func after_all() -> void:
	await wait_seconds(0.5)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


# --- RemoteInput ---

func test_remote_press_is_just_pressed_for_one_frame_and_held_until_released() -> void:
	var input := RemoteInput.new()
	input.press(PlayerInput.ATTACK)
	input.poll(null)
	assert_true(input.is_pressed(PlayerInput.ATTACK))
	assert_true(input.is_just_pressed(PlayerInput.ATTACK))
	input.poll(null)
	assert_true(input.is_pressed(PlayerInput.ATTACK), "still held")
	assert_false(input.is_just_pressed(PlayerInput.ATTACK), "only the first frame is 'just'")
	input.release(PlayerInput.ATTACK)
	input.poll(null)
	assert_false(input.is_pressed(PlayerInput.ATTACK))
	assert_false(input.is_just_pressed(PlayerInput.ATTACK))


func test_remote_tap_counts_for_exactly_one_frame() -> void:
	var input := RemoteInput.new()
	input.tap(PlayerInput.DASH)
	input.poll(null)
	assert_true(input.is_just_pressed(PlayerInput.DASH))
	assert_true(input.is_pressed(PlayerInput.DASH))
	input.poll(null)
	assert_false(input.is_pressed(PlayerInput.DASH))
	assert_false(input.is_just_pressed(PlayerInput.DASH))


func test_remote_press_and_release_between_frames_is_not_lost() -> void:
	var input := RemoteInput.new()
	input.press(PlayerInput.INTERACT)
	input.release(PlayerInput.INTERACT)
	input.poll(null)
	assert_true(input.is_just_pressed(PlayerInput.INTERACT), "a short click still counts once")
	input.poll(null)
	assert_false(input.is_pressed(PlayerInput.INTERACT))


func test_remote_held_actions_from_one_packet() -> void:
	var input := RemoteInput.new()
	var held: Array[StringName] = [PlayerInput.ATTACK, PlayerInput.SPECIAL]
	input.set_held_actions(held)
	input.poll(null)
	assert_true(input.is_pressed(PlayerInput.ATTACK))
	assert_true(input.is_pressed(PlayerInput.SPECIAL))
	assert_false(input.is_pressed(PlayerInput.DASH))
	var only_special: Array[StringName] = [PlayerInput.SPECIAL]
	input.set_held_actions(only_special)
	input.poll(null)
	assert_false(input.is_pressed(PlayerInput.ATTACK), "missing from the packet = released")
	assert_true(input.is_pressed(PlayerInput.SPECIAL))
	assert_false(input.is_just_pressed(PlayerInput.SPECIAL))


func test_remote_move_is_clamped_and_aim_follows_direction_or_point() -> void:
	var input := RemoteInput.new()
	input.set_move(Vector2(3, 4))
	assert_almost_eq(input.move.length(), 1.0, 0.001)
	assert_eq(input.get_aim_direction(Vector2.ZERO, Vector2.LEFT), Vector2.RIGHT, "default aim to the right")
	input.set_aim_direction(Vector2(0, -5))
	assert_eq(input.get_aim_direction(Vector2(100, 100), Vector2.LEFT), Vector2.UP)
	input.set_aim_point(Vector2(100, 200))
	assert_eq(input.get_aim_direction(Vector2(100, 100), Vector2.LEFT), Vector2.DOWN)
	assert_eq(input.get_aim_direction(Vector2(100, 199), Vector2.LEFT), Vector2.LEFT, "too close: keep the previous aim")


func test_remote_clear_releases_everything() -> void:
	var input := RemoteInput.new()
	input.press(PlayerInput.ATTACK)
	input.set_move(Vector2.RIGHT)
	input.clear()
	input.poll(null)
	assert_false(input.is_pressed(PlayerInput.ATTACK))
	assert_eq(input.move, Vector2.ZERO)
	assert_false(input.is_local())


# --- LocalKeyboardMouseInput ---

func test_local_input_reads_the_input_map() -> void:
	var input := LocalKeyboardMouseInput.new()
	assert_true(input.is_local())
	Input.action_press(PlayerInput.ATTACK)
	Input.action_press(LocalKeyboardMouseInput.MOVE_RIGHT)
	input.poll(null)
	assert_true(input.is_pressed(PlayerInput.ATTACK))
	assert_false(input.is_pressed(PlayerInput.SPECIAL))
	assert_gt(input.move.x, 0.5, "move_right")
	Input.action_release(PlayerInput.ATTACK)
	Input.action_release(LocalKeyboardMouseInput.MOVE_RIGHT)
	input.poll(null)
	assert_false(input.is_pressed(PlayerInput.ATTACK))
	assert_eq(input.move, Vector2.ZERO)


# --- Player and WeaponController read only their input object ---

func _remote_player(local := false) -> Array:
	var player := PLAYER_SCENE.instantiate() as Player
	var input := RemoteInput.new()
	player.input = input
	player.is_local = local
	add_child_autofree(player)
	return [player, input]


func test_player_defaults_to_keyboard_and_mouse() -> void:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	assert_true(player.input is LocalKeyboardMouseInput)
	assert_true(player.is_local)
	assert_eq(player.weapon_controller.input, player.input, "the weapons read the same input")
	player.input = null
	assert_true(player.input is RemoteInput, "never null")
	assert_eq(player.weapon_controller.input, player.input)


func test_remote_player_walks_and_aims() -> void:
	var pair := _remote_player()
	var player: Player = pair[0]
	var input: RemoteInput = pair[1]
	var start := player.global_position
	input.set_move(Vector2.RIGHT)
	input.set_aim_direction(Vector2.UP)
	await wait_physics_frames(10)
	assert_gt(player.global_position.x, start.x + 10.0, "walked right")
	assert_almost_eq(player.get_aim_direction().y, -1.0, 0.001, "aims up")


func test_remote_player_dashes_on_a_tap() -> void:
	var pair := _remote_player()
	var player: Player = pair[0]
	var input: RemoteInput = pair[1]
	input.set_move(Vector2.DOWN)
	input.tap(PlayerInput.DASH)
	await wait_physics_frames(2)
	assert_true(player.is_dashing() or player.get_dash_cooldown_left() > 0.0, "dash started")


func test_remote_player_attacks_and_uses_the_special() -> void:
	var pair := _remote_player()
	var player: Player = pair[0]
	var input: RemoteInput = pair[1]
	watch_signals(player.weapon_controller)
	input.press(PlayerInput.ATTACK)
	await wait_physics_frames(3)
	assert_signal_emitted(player.weapon_controller, "attack_performed")
	input.release(PlayerInput.ATTACK)
	await wait_seconds(0.6)
	input.press(PlayerInput.SPECIAL)
	await wait_physics_frames(3)
	input.release(PlayerInput.SPECIAL)
	assert_signal_emitted(player.weapon_controller, "special_performed")


func test_remote_player_ignores_the_keyboard() -> void:
	var pair := _remote_player()
	var player: Player = pair[0]
	var start := player.global_position
	watch_signals(player.weapon_controller)
	Input.action_press(PlayerInput.ATTACK)
	Input.action_press(LocalKeyboardMouseInput.MOVE_RIGHT)
	await wait_physics_frames(6)
	assert_signal_not_emitted(player.weapon_controller, "attack_performed")
	assert_almost_eq(player.global_position.x, start.x, 0.01, "no keyboard movement")


func test_non_local_player_has_no_camera() -> void:
	var player: Player = _remote_player(false)[0]
	var camera := player.get_node("Camera2D") as Camera2D
	assert_false(camera.enabled)
	assert_false(camera.visible, "no ambient particles around remote players")
	var local: Player = _remote_player(true)[0]
	assert_true((local.get_node("Camera2D") as Camera2D).enabled)


func test_protection_blocks_input_and_damage_per_reason() -> void:
	var pair := _remote_player()
	var player: Player = pair[0]
	var input: RemoteInput = pair[1]
	player.set_protected(&"menu", true)
	assert_true(player.is_protected())
	assert_true(player.is_input_locked())
	assert_true(player.hurtbox.is_invulnerable())
	var start := player.global_position
	input.set_move(Vector2.RIGHT)
	await wait_physics_frames(5)
	assert_almost_eq(player.global_position.x, start.x, 0.01, "no movement while protected")
	player.set_protected(&"menu", false)
	assert_false(player.is_protected())
	assert_false(player.is_input_locked())
	assert_false(player.hurtbox.is_invulnerable())


# --- Per-player state (D-088): falls and safe spots belong to each player ---

func _is_pit(point: Vector2) -> bool:
	return point.x >= 100.0


func test_two_players_fall_and_land_independently() -> void:
	var step := 1.0 / 60.0
	var players: Array[Player] = []
	for i in 2:
		var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
		player.set_physics_process(false)
		player.fall.pit_probe = Callable(self, &"_is_pit")
		players.append(player)
	var a := players[0]
	var b := players[1]
	a.global_position = Vector2(20, 0) - Player.FEET_OFFSET
	b.global_position = Vector2(60, 40) - Player.FEET_OFFSET
	for i in 3:
		for player in players:
			player._tick_timers(step)
			player.fall.update(step)
	a.global_position = Vector2(150, 0) - Player.FEET_OFFSET
	var time := 0.0
	while time < 0.15:
		for player in players:
			player._tick_timers(step)
			player.fall.update(step)
		time += step
	assert_true(a.is_falling(), "the player over the abyss falls")
	assert_false(b.is_falling(), "the other one stands")
	assert_false(b.is_input_locked(), "and keeps its controls")
	assert_almost_eq(a.get_last_safe_position().x, 20.0, 0.5, "own safe spot")
	assert_almost_eq(b.get_last_safe_position().x, 60.0, 0.5, "own safe spot")

extends GutTest
## Feedback #ce7cde79 (23.10.2026): in the lobby dialog of a group game (nothing pauses) the player
## could dash. While a dialog is open at this machine its local players take no game input
## (Player.INPUT_LOCK_DIALOG, per player, no pause); remote players are not touched.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const TEST_SAVE_PATH := "user://test_player_dialog_lock.cfg"

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path


func _player(local: bool) -> Array:
	var player := PLAYER_SCENE.instantiate() as Player
	var input := RemoteInput.new()
	player.input = input
	player.is_local = local
	add_child_autofree(player)
	player.global_position = Vector2(300, 300)
	return [player, input]


## A dialog that does not pause (like any dialog in a group game).
func _dialog() -> Modal:
	var modal := Modal.create(&"test_dialog_lock")
	modal.pauses = false
	modal.show_on(self)
	return modal


func test_an_open_dialog_holds_the_local_player() -> void:
	var pair := _player(true)
	var player: Player = pair[0]
	var input: RemoteInput = pair[1]
	var modal := _dialog()
	await wait_physics_frames(2)
	assert_true(player.is_input_locked(), "locked while the dialog is open")
	var start := player.global_position
	input.set_move(Vector2.RIGHT)
	input.tap(PlayerInput.DASH)
	await wait_physics_frames(5)
	assert_false(player.is_dashing(), "no dash in the menu")
	assert_almost_eq(player.global_position.x, start.x, 0.01, "no walking in the menu")
	modal.finish(null)
	await wait_physics_frames(Player.DIALOG_RELEASE_FRAMES + 2)
	assert_false(player.is_input_locked(), "free again once the dialog closed")
	await wait_physics_frames(5)
	assert_gt(player.global_position.x, start.x, "walks again")


func test_remote_players_are_not_held_by_a_dialog_here() -> void:
	var pair := _player(false)
	var player: Player = pair[0]
	var modal := _dialog()
	await wait_physics_frames(2)
	assert_false(player.is_input_locked(), "another machine's player moves on")
	modal.finish(null)


func test_the_keyboard_input_is_emptied_while_a_dialog_is_open() -> void:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	assert_true(player.input.is_local())
	Input.action_press(LocalKeyboardMouseInput.MOVE_RIGHT)
	var modal := _dialog()
	await wait_physics_frames(3)
	assert_eq(player.input.move, Vector2.ZERO, "nothing to send to the host either")
	modal.finish(null)
	await wait_physics_frames(Player.DIALOG_RELEASE_FRAMES + 2)
	assert_ne(player.input.move, Vector2.ZERO, "the held key counts again")
	Input.action_release(LocalKeyboardMouseInput.MOVE_RIGHT)


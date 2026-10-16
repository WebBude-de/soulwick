class_name LocalKeyboardMouseInput
extends PlayerInput
## Keyboard, mouse and gamepad at this machine (MP1, P0-2): reads the InputMap actions once per
## physics frame. The gamepad's buttons and left stick are bound to the same actions at runtime
## (GamepadInput.ensure_actions), so walking and the buttons need no extra path. The aim follows the
## device in use (InputDevice): the mouse through the player's own viewport, or the right stick of the
## gamepad (GamepadInput: stick, else walking direction, else last aim; light aim assist for ranged
## weapons). The name stays for the callers (player.gd, GameMode, NetPlayers).

const MOVE_LEFT: StringName = &"move_left"
const MOVE_RIGHT: StringName = &"move_right"
const MOVE_UP: StringName = &"move_up"
const MOVE_DOWN: StringName = &"move_down"

## Aim of the gamepad (right stick, last direction).
var gamepad := GamepadInput.new()


func is_local() -> bool:
	return true


func poll(body: Node2D) -> void:
	var in_tree := body != null and body.is_inside_tree()
	GamepadInput.ensure_actions()
	if in_tree:
		InputDeviceWatcher.ensure(body.get_tree())
	move = Input.get_vector(MOVE_LEFT, MOVE_RIGHT, MOVE_UP, MOVE_DOWN)
	var stick := GamepadInput.read_aim_stick()
	if uses_gamepad_aim(stick):
		aim_direction = gamepad.update_aim(body, stick, move, GamepadInput.is_aim_assist_enabled())
		var origin := body.global_position if in_tree else Vector2.ZERO
		aim_point = origin + aim_direction * GamepadInput.AIM_POINT_DISTANCE
	else:
		aim_direction = Vector2.ZERO
		if in_tree:
			aim_point = body.get_global_mouse_position()
			gamepad.follow(aim_point - body.global_position)
	for action in ACTIONS:
		# An action missing from the InputMap (a test project, a stripped build) is never pressed.
		var known := InputMap.has_action(action)
		_pressed[action] = known and Input.is_action_pressed(action)
		_just_pressed[action] = known and Input.is_action_just_pressed(action)


## The right stick aims (not the mouse): the gamepad is the device in use, or its aim stick is
## deflected anyway (e.g. before the InputDeviceWatcher saw an event).
static func uses_gamepad_aim(stick: Vector2) -> bool:
	return InputDevice.is_gamepad() or stick != Vector2.ZERO

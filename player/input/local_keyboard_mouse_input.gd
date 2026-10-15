class_name LocalKeyboardMouseInput
extends PlayerInput
## Keyboard and mouse at this machine (MP1): today's controls. Reads the InputMap actions and the
## mouse position through the player's own viewport, once per physics frame.

const MOVE_LEFT: StringName = &"move_left"
const MOVE_RIGHT: StringName = &"move_right"
const MOVE_UP: StringName = &"move_up"
const MOVE_DOWN: StringName = &"move_down"


func is_local() -> bool:
	return true


func poll(body: Node2D) -> void:
	move = Input.get_vector(MOVE_LEFT, MOVE_RIGHT, MOVE_UP, MOVE_DOWN)
	if body != null and body.is_inside_tree():
		aim_point = body.get_global_mouse_position()
	for action in ACTIONS:
		# An action missing from the InputMap (a test project, a stripped build) is never pressed.
		var known := InputMap.has_action(action)
		_pressed[action] = known and Input.is_action_pressed(action)
		_just_pressed[action] = known and Input.is_action_just_pressed(action)

class_name RemoteInput
extends PlayerInput
## Input filled from outside (MP1): the network later (host side of a client's player), bots and
## tests now. The sender sets movement, aim and which actions are held; poll() turns that into the
## frame state. A press that comes and goes between two frames (tap) still counts for one frame.

## What the sender holds right now.
var _held: Dictionary[StringName, bool] = {}
## Presses since the last poll, also if already released again.
var _taps: Dictionary[StringName, bool] = {}


func _init() -> void:
	aim_direction = Vector2.RIGHT


func set_move(value: Vector2) -> void:
	move = value.limit_length(1.0)


## Aim in a direction (normalised); Vector2.ZERO keeps aiming at aim_point.
func set_aim_direction(direction: Vector2) -> void:
	aim_direction = direction.normalized()


## Aim at a world position.
func set_aim_point(point: Vector2) -> void:
	aim_point = point
	aim_direction = Vector2.ZERO


func press(action: StringName) -> void:
	if not _held.get(action, false):
		_taps[action] = true
	_held[action] = true


func release(action: StringName) -> void:
	_held.erase(action)


## Pressed for exactly one frame (dash, weapon switch, interact).
func tap(action: StringName) -> void:
	_taps[action] = true


## Whole button state at once, e.g. from one network packet: held actions, all others released.
func set_held_actions(held: Array[StringName]) -> void:
	for action in ACTIONS:
		if held.has(action):
			press(action)
		else:
			release(action)


func poll(_body: Node2D) -> void:
	for action in ACTIONS:
		var held: bool = _held.get(action, false)
		var tapped: bool = _taps.get(action, false)
		_just_pressed[action] = tapped or (held and not _pressed.get(action, false))
		_pressed[action] = held or tapped
	_taps.clear()


func clear() -> void:
	super.clear()
	_held.clear()
	_taps.clear()

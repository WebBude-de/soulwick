class_name PlayerInput
extends RefCounted
## Commands of one player for the current physics frame (MP1, D-088): movement, aim and the action
## buttons. Player and WeaponController read only from their PlayerInput, never from Input, so the
## same player code runs for keyboard, mouse and gamepad at this machine (LocalKeyboardMouseInput) and for players
## fed from outside (RemoteInput: the network later, bots and tests now).
## The owning player calls poll() once at the start of every physics frame; afterwards move, aim and
## the pressed/just-pressed flags describe that frame.

## Action ids are the InputMap action names, so the local input can read them directly.
const ATTACK: StringName = &"attack"
const SPECIAL: StringName = &"special_attack"
const DASH: StringName = &"dash"
const SWITCH_WEAPON: StringName = &"switch_weapon"
const INTERACT: StringName = &"interact"
## Horizontal dash of the side-view segments (M5; there DASH is the jump).
const SIDE_DASH: StringName = &"side_dash"
## Order = bit order of the network state (NetPlayerState.bits_of): append only.
const ACTIONS: Array[StringName] = [ATTACK, SPECIAL, DASH, SWITCH_WEAPON, INTERACT, SIDE_DASH]
## Aim points closer than this to the hand (squared px) keep the previous direction.
const MIN_AIM_DISTANCE_SQUARED := 4.0

## Movement, length 0..1 (8 directions on the keyboard, analogue later).
var move := Vector2.ZERO
## World position aimed at (the mouse for the local player).
var aim_point := Vector2.ZERO
## Explicit aim direction (normalised); Vector2.ZERO = aim at aim_point instead.
var aim_direction := Vector2.ZERO

var _pressed: Dictionary[StringName, bool] = {}
var _just_pressed: Dictionary[StringName, bool] = {}


## Refreshes the state for this physics frame. body: the owning player (viewport, mouse).
func poll(_body: Node2D) -> void:
	pass


## True for keyboard and mouse at this machine.
func is_local() -> bool:
	return false


## The action is held in this frame.
func is_pressed(action: StringName) -> bool:
	return _pressed.get(action, false)


## The action went down in this frame.
func is_just_pressed(action: StringName) -> bool:
	return _just_pressed.get(action, false)


## Normalised aim from origin (the hand): the explicit direction if set, otherwise towards
## aim_point; fallback when the point is too close to tell.
func get_aim_direction(origin: Vector2, fallback: Vector2) -> Vector2:
	if aim_direction != Vector2.ZERO:
		return aim_direction.normalized()
	var to_point := aim_point - origin
	if to_point.length_squared() < MIN_AIM_DISTANCE_SQUARED:
		return fallback
	return to_point.normalized()


## Nothing held, no movement (e.g. a player who left the game).
func clear() -> void:
	move = Vector2.ZERO
	_pressed.clear()
	_just_pressed.clear()

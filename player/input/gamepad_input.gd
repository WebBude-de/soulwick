class_name GamepadInput
extends RefCounted
## Gamepad at this machine (P0-2, Steam Deck), two sticks like the touch controls (D-155):
## left stick (or D-pad) walks, right stick aims, RT attacks, LT uses the special, A dashes (jumps in
## a side view), B is the side dash, X uses/interacts, Y switches the weapon, Start pauses and
## Back/Select opens the overview (Tab), held 0.5 s it breaks the return stone (KE5, GameUI). Without right stick the player aims where it walks,
## otherwise keeps the last direction. With a ranged weapon the deflected aim stick snaps onto a
## visible enemy (TouchAimAssist, option "Zielhilfe (Gamepad)").
##
## The bindings are added to the InputMap at runtime (ensure_actions), so project.godot keeps only
## keyboard and mouse and LocalKeyboardMouseInput reads the buttons and the left stick through the
## same actions as the keyboard. Menus get A = accept and B = back (ui_accept / ui_cancel). Events
## use device -1 (every pad); local co-op with one pad per player would bind per device later.
## LocalKeyboardMouseInput owns one GamepadInput and asks it for the aim while the gamepad is in
## use (InputDevice); it is never read for remote players (MP1: their input comes as RemoteInput).

## Runtime actions of the right stick (not in project.godot).
const AIM_LEFT: StringName = &"aim_left"
const AIM_RIGHT: StringName = &"aim_right"
const AIM_UP: StringName = &"aim_up"
const AIM_DOWN: StringName = &"aim_down"
const AIM_ACTIONS: Array[StringName] = [AIM_LEFT, AIM_RIGHT, AIM_UP, AIM_DOWN]
## Dead zone of the aim stick (TESTWERT); the move actions keep their own (0.2, project.godot).
const AIM_DEADZONE := 0.25
## Distance of aim_point in front of the hand while aiming with the stick (only a direction counts).
const AIM_POINT_DISTANCE := 64.0
## Menu actions that get a gamepad button (Godot's defaults only give them the D-pad and stick).
const UI_ACCEPT: StringName = &"ui_accept"
const UI_CANCEL: StringName = &"ui_cancel"
## Menu actions of the game (project.godot; same names as GameManager.PAUSE_MENU / PAUSE_UPGRADE_OVERVIEW).
const PAUSE_MENU: StringName = &"pause_menu"
const UPGRADE_OVERVIEW: StringName = &"upgrade_overview"

static var _ensured := false

## Last aim direction (normalised): kept while neither stick points anywhere.
var last_aim := Vector2.RIGHT
## Aim stick of the last update after its dead zone (0..1); Vector2.ZERO = not aiming.
var aim_stick := Vector2.ZERO


## [action, event] pairs of the gamepad, in binding order (the first one of an action is the symbol
## the UI shows: the stick before the D-pad).
static func bindings() -> Array[Array]:
	return [
		[LocalKeyboardMouseInput.MOVE_LEFT, axis(JOY_AXIS_LEFT_X, -1.0)],
		[LocalKeyboardMouseInput.MOVE_RIGHT, axis(JOY_AXIS_LEFT_X, 1.0)],
		[LocalKeyboardMouseInput.MOVE_UP, axis(JOY_AXIS_LEFT_Y, -1.0)],
		[LocalKeyboardMouseInput.MOVE_DOWN, axis(JOY_AXIS_LEFT_Y, 1.0)],
		[LocalKeyboardMouseInput.MOVE_LEFT, button(JOY_BUTTON_DPAD_LEFT)],
		[LocalKeyboardMouseInput.MOVE_RIGHT, button(JOY_BUTTON_DPAD_RIGHT)],
		[LocalKeyboardMouseInput.MOVE_UP, button(JOY_BUTTON_DPAD_UP)],
		[LocalKeyboardMouseInput.MOVE_DOWN, button(JOY_BUTTON_DPAD_DOWN)],
		[AIM_LEFT, axis(JOY_AXIS_RIGHT_X, -1.0)],
		[AIM_RIGHT, axis(JOY_AXIS_RIGHT_X, 1.0)],
		[AIM_UP, axis(JOY_AXIS_RIGHT_Y, -1.0)],
		[AIM_DOWN, axis(JOY_AXIS_RIGHT_Y, 1.0)],
		[PlayerInput.ATTACK, axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
		[PlayerInput.SPECIAL, axis(JOY_AXIS_TRIGGER_LEFT, 1.0)],
		[PlayerInput.DASH, button(JOY_BUTTON_A)],
		[PlayerInput.SIDE_DASH, button(JOY_BUTTON_B)],
		[PlayerInput.INTERACT, button(JOY_BUTTON_X)],
		[PlayerInput.SWITCH_WEAPON, button(JOY_BUTTON_Y)],
		[PlayerInput.CAST_SPELL, button(JOY_BUTTON_RIGHT_SHOULDER)],
		[PlayerInput.CAST_SPELL_2, button(JOY_BUTTON_LEFT_SHOULDER)],
		# Held, not pressed (KE5): Select opens the overview on a short press; GameUI breaks the
		# return stone after a hold and LocalKeyboardMouseInput ignores this pad press.
		[PlayerInput.USE_RETURN_STONE, button(JOY_BUTTON_BACK)],
		[PAUSE_MENU, button(JOY_BUTTON_START)],
		[UPGRADE_OVERVIEW, button(JOY_BUTTON_BACK)],
		[UI_ACCEPT, button(JOY_BUTTON_A)],
		[UI_CANCEL, button(JOY_BUTTON_B)],
	]


static func button(index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = index
	return event


## Stick or trigger towards direction (-1 or +1).
static func axis(joy_axis: JoyAxis, direction: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = -1
	event.axis = joy_axis
	event.axis_value = signf(direction)
	return event


## Adds the gamepad bindings to the InputMap (idempotent, cheap after the first call). The aim
## actions are created here; other actions only get their events when they exist (project.godot,
## PlayerSideMotion.ensure_actions). Call once at start; LocalKeyboardMouseInput also calls it.
static func ensure_actions() -> void:
	# The aim actions vanish with a reloaded InputMap (later rebinding); then everything is added again.
	if _ensured and InputMap.has_action(AIM_RIGHT):
		return
	_ensured = true
	for action in AIM_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, AIM_DEADZONE)
	for pair in bindings():
		var action: StringName = pair[0]
		var event: InputEvent = pair[1]
		if InputMap.has_action(action) and not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)


## Right stick after its dead zone (0..1, rescaled); Vector2.ZERO without the aim actions.
static func read_aim_stick() -> Vector2:
	if not InputMap.has_action(AIM_RIGHT):
		return Vector2.ZERO
	return Input.get_vector(AIM_LEFT, AIM_RIGHT, AIM_UP, AIM_DOWN)


## Option "Zielhilfe (Gamepad)" (GameOptions, default on).
static func is_aim_assist_enabled() -> bool:
	return GameOptions.is_gamepad_aim_assist_enabled()


## Aim of this frame: the aim stick, else the walking direction (TouchInput.choose_aim, same rule as
## touch), else the last aim; with assist and a ranged weapon onto an enemy in the stick's cone.
## body may be null or outside the tree (no assist then).
func update_aim(body: Node2D, stick: Vector2, move: Vector2, assist: bool) -> Vector2:
	aim_stick = stick.limit_length(1.0)
	var aim := TouchInput.choose_aim(aim_stick, move, last_aim)
	if assist and body != null and body.is_inside_tree():
		aim = TouchAimAssist.apply(body, aim_stick, aim)
	last_aim = aim
	return aim


## Keeps the last aim in step with the mouse while it is in use, so switching to the pad does not
## turn the player around.
func follow(direction: Vector2) -> void:
	aim_stick = Vector2.ZERO
	if direction.length_squared() >= PlayerInput.MIN_AIM_DISTANCE_SQUARED:
		last_aim = direction.normalized()

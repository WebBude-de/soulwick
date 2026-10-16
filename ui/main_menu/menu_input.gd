class_name MenuInput
extends RefCounted
## Key rules of the menus: arrows or WASD move, Enter/Space confirm, Esc back, Del deletes.
## Held arrows repeat (echo); confirm and back do not.
## Gamepad (P0-2 step 2, Steam Deck): D-pad and left stick move, A confirms (ui_accept), B goes back
## (ui_cancel); GamepadInput adds A and B to those actions. The stick sends a stream of motion events,
## so it is debounced here: one step when it is pushed past STICK_PRESS on its stronger axis, the
## next only after it came back under STICK_RELEASE or after the repeat delay. A held D-pad button
## or stick repeats like a held key (REPEAT_DELAY, then every REPEAT_INTERVAL); those repeats come
## from pump_repeat() (open menus call it every frame) as ui_* action events, so every menu reads
## them like arrow keys. latch() (a menu opens) ignores a stick or D-pad that is already held, e.g.
## the player still walking when a dialog pops up, until it is let go.
## direction() decides once per event (cached), so asking is_up/is_down/... in a row is safe.

## Stick deflection that counts as a step, and the one under which it counts as let go (TESTWERT).
const STICK_PRESS := 0.5
const STICK_RELEASE := 0.3
## Held direction: first repeat after REPEAT_DELAY, then every REPEAT_INTERVAL seconds (TESTWERT,
## close to the keyboard's echo).
const REPEAT_DELAY := 0.4
const REPEAT_INTERVAL := 0.12
## No repeat until the held direction is let go (latch()).
const NO_REPEAT := -1

const DPAD_DIRECTIONS := {
	JOY_BUTTON_DPAD_UP: Vector2i.UP, JOY_BUTTON_DPAD_DOWN: Vector2i.DOWN,
	JOY_BUTTON_DPAD_LEFT: Vector2i.LEFT, JOY_BUTTON_DPAD_RIGHT: Vector2i.RIGHT,
}
## Direction -> menu action of a repeat event.
const DIRECTION_ACTIONS := {
	Vector2i.UP: &"ui_up", Vector2i.DOWN: &"ui_down", Vector2i.LEFT: &"ui_left", Vector2i.RIGHT: &"ui_right",
}

enum Source { NONE, STICK, DPAD }

## Tests move the clock instead of waiting (milliseconds added to Time.get_ticks_msec()).
static var clock_offset_ms := 0

static var _cached_event: InputEvent = null
static var _cached_direction := Vector2i.ZERO
## Left stick per device: last values and the direction it stands for.
static var _stick_values: Dictionary = {}
static var _stick_directions: Dictionary = {}
## The direction held right now (stick or D-pad) and when it repeats next.
static var _held := Vector2i.ZERO
static var _held_source := Source.NONE
static var _held_device := 0
static var _held_button := -1
static var _next_repeat_ms := NO_REPEAT


static func is_up(event: InputEvent) -> bool:
	return direction(event) == Vector2i.UP


static func is_down(event: InputEvent) -> bool:
	return direction(event) == Vector2i.DOWN


static func is_left(event: InputEvent) -> bool:
	return direction(event) == Vector2i.LEFT


static func is_right(event: InputEvent) -> bool:
	return direction(event) == Vector2i.RIGHT


## Step of an event: arrows (with echo), W/A/S/D when with_wasd, the D-pad and the debounced left
## stick; Vector2i.ZERO for everything else (and for stick motion that is no new step).
static func direction(event: InputEvent, with_wasd := true) -> Vector2i:
	if is_pad_direction_event(event):
		return pad_direction(event)
	for step: Vector2i in DIRECTION_ACTIONS:
		if event.is_action_pressed(DIRECTION_ACTIONS[step], true):
			return step
	if with_wasd:
		for step: Vector2i in DIRECTION_ACTIONS:
			var move := StringName(String(DIRECTION_ACTIONS[step]).replace("ui_", "move_"))
			if InputMap.has_action(move) and event.is_action_pressed(move, true):
				return step
	return Vector2i.ZERO


static func is_accept(event: InputEvent) -> bool:
	return event.is_action_pressed(&"ui_accept")


static func is_back(event: InputEvent) -> bool:
	return event.is_action_pressed(&"ui_cancel")


## A on the gamepad (the gamepad button of ui_accept).
static func is_pad_accept(event: InputEvent) -> bool:
	return event is InputEventJoypadButton and event.is_action_pressed(&"ui_accept")


## B on the gamepad (the gamepad button of ui_cancel).
static func is_pad_back(event: InputEvent) -> bool:
	return event is InputEventJoypadButton and event.is_action_pressed(&"ui_cancel")


## Enter or A: confirms where Space must not (text fields, the pause menu).
static func is_confirm(event: InputEvent) -> bool:
	return is_enter(event) or is_pad_accept(event)


## A gamepad face or shoulder button pressed (button = JOY_BUTTON_*), no repeat.
static func is_pad_button(event: InputEvent, button: JoyButton) -> bool:
	var pad := event as InputEventJoypadButton
	return pad != null and pad.pressed and pad.button_index == button


static func is_delete(event: InputEvent) -> bool:
	var key := event as InputEventKey
	return key != null and key.pressed and not key.echo and (key.keycode == KEY_DELETE or key.keycode == KEY_BACKSPACE)


## Enter only (not Space): used while a text field has the keyboard.
static func is_enter(event: InputEvent) -> bool:
	var key := event as InputEventKey
	return key != null and key.pressed and not key.echo and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER)


## A key press for tests: InputEventKey with keycode and the matching physical key.
static func key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	return event


## A gamepad button for tests.
static func pad_button_event(button: JoyButton, pressed := true, device := 0) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = pressed
	return event


## A stick axis value for tests.
static func pad_axis_event(axis: JoyAxis, value: float, device := 0) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	return event


# --- Gamepad directions ---

## D-pad buttons (pressed or let go) and the left stick: they go through pad_direction().
static func is_pad_direction_event(event: InputEvent) -> bool:
	var button := event as InputEventJoypadButton
	if button != null:
		return DPAD_DIRECTIONS.has(button.button_index)
	var motion := event as InputEventJoypadMotion
	return motion != null and (motion.axis == JOY_AXIS_LEFT_X or motion.axis == JOY_AXIS_LEFT_Y)


## Step of a D-pad or left stick event (decided once per event, see class comment).
static func pad_direction(event: InputEvent) -> Vector2i:
	if event == _cached_event:
		return _cached_direction
	var result := _decide(event)
	_cached_event = event
	_cached_direction = result
	return result


## Direction a stick stands for: the stronger axis past STICK_PRESS; a direction already held stays
## until the stick falls under STICK_RELEASE that way or clearly turns to another axis.
static func stick_direction(value: Vector2, current := Vector2i.ZERO) -> Vector2i:
	var strongest := maxf(absf(value.x), absf(value.y))
	var dominant := Vector2i.ZERO
	if strongest >= STICK_PRESS:
		dominant = Vector2i(int(signf(value.x)), 0) if absf(value.x) >= absf(value.y) else Vector2i(0, int(signf(value.y)))
	if current != Vector2i.ZERO:
		var along := Vector2(current).dot(value)
		if along >= STICK_RELEASE and (dominant == Vector2i.ZERO or along >= strongest * 0.8):
			return current
	return dominant


## A menu opens: a stick or D-pad already held counts as held without a step or repeat until it is
## let go (Input state of every connected gamepad).
static func latch() -> void:
	_held = Vector2i.ZERO
	_held_source = Source.NONE
	_next_repeat_ms = NO_REPEAT
	_cached_event = null
	for device in Input.get_connected_joypads():
		var value := Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
		_stick_values[device] = value
		var held := stick_direction(value)
		_stick_directions[device] = held
		if held != Vector2i.ZERO:
			_hold(held, Source.STICK, device, -1)
			_next_repeat_ms = NO_REPEAT
		for button: int in DPAD_DIRECTIONS:
			if Input.is_joy_button_pressed(device, button as JoyButton):
				_hold(DPAD_DIRECTIONS[button], Source.DPAD, device, button)
				_next_repeat_ms = NO_REPEAT


## Forgets every held direction (tests).
static func reset() -> void:
	_stick_values.clear()
	_stick_directions.clear()
	_release()
	_cached_event = null
	clock_offset_ms = 0


## The direction held right now (Vector2i.ZERO = none).
static func get_held() -> Vector2i:
	return _held


## The repeat step that is due now as a ui_* action event, or null. Checks that the button or stick
## is still held (Input state); a stick that moved on waits for its next motion event.
static func poll_repeat() -> InputEventAction:
	if _held == Vector2i.ZERO or _next_repeat_ms == NO_REPEAT or _now() < _next_repeat_ms:
		return null
	match _held_source:
		Source.DPAD:
			if not Input.is_joy_button_pressed(_held_device, _held_button as JoyButton):
				_release()
				return null
		Source.STICK:
			var value := Vector2(Input.get_joy_axis(_held_device, JOY_AXIS_LEFT_X), Input.get_joy_axis(_held_device, JOY_AXIS_LEFT_Y))
			if stick_direction(value, _held) != _held:
				return null
	_next_repeat_ms = _now() + int(REPEAT_INTERVAL * 1000.0)
	return action_event(_held)


## Sends the due repeat step (if any) into the input like a key press; menus call it every frame.
## Returns true when a step was sent.
static func pump_repeat() -> bool:
	var event := poll_repeat()
	if event == null:
		return false
	Input.parse_input_event(event)
	var release := action_event(_held)
	release.pressed = false
	Input.parse_input_event(release)
	return true


## A ui_* action event for a direction (pressed).
static func action_event(step: Vector2i) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = DIRECTION_ACTIONS.get(step, &"ui_down")
	event.pressed = true
	return event


static func _decide(event: InputEvent) -> Vector2i:
	var button := event as InputEventJoypadButton
	if button != null:
		var step: Vector2i = DPAD_DIRECTIONS.get(button.button_index, Vector2i.ZERO)
		if not button.pressed:
			if _held_source == Source.DPAD and _held_button == button.button_index:
				_release()
			return Vector2i.ZERO
		_hold(step, Source.DPAD, button.device, button.button_index)
		return step
	var motion := event as InputEventJoypadMotion
	var value: Vector2 = _stick_values.get(motion.device, Vector2.ZERO)
	if motion.axis == JOY_AXIS_LEFT_X:
		value.x = motion.axis_value
	else:
		value.y = motion.axis_value
	_stick_values[motion.device] = value
	var current: Vector2i = _stick_directions.get(motion.device, Vector2i.ZERO)
	var next := stick_direction(value, current)
	_stick_directions[motion.device] = next
	var holding := _held_source == Source.STICK and _held_device == motion.device
	if next == current:
		# Jitter of a held stick: a repeat when it is due (polling covers a perfectly still stick).
		if next != Vector2i.ZERO and holding and _next_repeat_ms != NO_REPEAT and _now() >= _next_repeat_ms:
			_next_repeat_ms = _now() + int(REPEAT_INTERVAL * 1000.0)
			return next
		return Vector2i.ZERO
	if next == Vector2i.ZERO:
		if holding:
			_release()
		return Vector2i.ZERO
	_hold(next, Source.STICK, motion.device, -1)
	return next


static func _hold(step: Vector2i, source: Source, device: int, button: int) -> void:
	_held = step
	_held_source = source
	_held_device = device
	_held_button = button
	_next_repeat_ms = _now() + int(REPEAT_DELAY * 1000.0)


static func _release() -> void:
	_held = Vector2i.ZERO
	_held_source = Source.NONE
	_held_button = -1
	_next_repeat_ms = NO_REPEAT


static func _now() -> int:
	return Time.get_ticks_msec() + clock_offset_ms

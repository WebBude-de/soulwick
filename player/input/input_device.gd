class_name InputDevice
extends RefCounted
## Which device the player at this machine used last (P0-2): keyboard and mouse, a gamepad or the
## touch screen. The UI picks its key symbols from it (InputGlyphs), LocalKeyboardMouseInput its aim
## (mouse or right stick), and the mouse cursor hides while the gamepad is in use and comes back
## with the next real mouse use. One machine has one such state (shared()); the InputDeviceWatcher
## node feeds it every input event, tests call note() directly.
## Decision and effect are split: kind_of() only classifies an event, note() switches the kind and
## emits changed; the cursor follows in apply_cursor().
## Co-op: this is the device of the local player only. Local co-op with one pad per player would
## keep a device id per PlayerInput instead (open point, P0-2 report).

## The device in use changed (kind = Kind). Rebuild key symbols on it.
signal changed(kind: int)

enum Kind { KEYBOARD_MOUSE, GAMEPAD, TOUCH }

## Stick deflection that counts as using the gamepad; worn sticks drift below it (TESTWERT).
const STICK_THRESHOLD := 0.4
## Trigger travel that counts as using the gamepad (TESTWERT).
const TRIGGER_THRESHOLD := 0.3
## Mouse travel per motion event (px) that counts as using the mouse; a bumped desk does not (TESTWERT).
const MOUSE_MOTION_THRESHOLD := 3.0
## kind_of(): the event says nothing about the device.
const NO_CHANGE := -1
## Parts of a joypad name (lower case, Input.get_joy_name) of pads with the Xbox letters A, B, X, Y
## on their face buttons (D-192). Steam's virtual pad is left out: it may stand for a PlayStation pad.
const XBOX_NAME_PARTS: Array[String] = ["xbox", "x-box", "xinput", "microsoft", "steam deck"]

static var _shared: InputDevice = null
## Tests: 1 = the pad in use has Xbox letters, 0 = it has not, -1 = ask the connected pad.
static var xbox_letters_override := -1

var kind: Kind = Kind.KEYBOARD_MOUSE
## Last joypad that was used (-1 = none yet), e.g. for vibration later.
var joypad := -1


## The device state of this machine.
static func shared() -> InputDevice:
	if _shared == null:
		_shared = InputDevice.new()
	return _shared


## The gamepad is the device in use on this machine.
static func is_gamepad() -> bool:
	return shared().kind == Kind.GAMEPAD


## The pad in use (joypad) has Xbox letters on its face buttons; false while no pad is known
## (the UI then shows the neutral positions, InputGlyphs).
static func has_xbox_letters() -> bool:
	if xbox_letters_override >= 0:
		return xbox_letters_override == 1
	var device := shared().joypad
	if device < 0 or not Input.get_connected_joypads().has(device):
		return false
	return is_xbox_name(Input.get_joy_name(device))


## "Xbox Series Controller", "XInput Gamepad", "Steam Deck" -> true; "PS5 Controller" -> false.
static func is_xbox_name(joy_name: String) -> bool:
	var lower := joy_name.to_lower()
	for part in XBOX_NAME_PARTS:
		if lower.contains(part):
			return true
	return false


## Device an event stands for, or NO_CHANGE (releases, tiny stick drift, mouse jitter, emulated
## mouse events of a touch screen, mouse motion while the touch controls are in use).
static func kind_of(event: InputEvent) -> int:
	if event is InputEventJoypadButton:
		return Kind.GAMEPAD if event.is_pressed() else NO_CHANGE
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		var trigger := motion.axis == JOY_AXIS_TRIGGER_LEFT or motion.axis == JOY_AXIS_TRIGGER_RIGHT
		var threshold := TRIGGER_THRESHOLD if trigger else STICK_THRESHOLD
		return Kind.GAMEPAD if absf(motion.axis_value) >= threshold else NO_CHANGE
	if event is InputEventScreenTouch:
		return Kind.TOUCH if event.is_pressed() else NO_CHANGE
	if event is InputEventKey:
		# Phones send keys for system buttons (back), like TouchOverlay._is_desktop_input.
		return Kind.KEYBOARD_MOUSE if event.is_pressed() and not event.is_echo() and not OS.has_feature("mobile") else NO_CHANGE
	if event is InputEventMouseButton:
		return Kind.KEYBOARD_MOUSE if event.is_pressed() and event.device != InputEvent.DEVICE_ID_EMULATION else NO_CHANGE
	if event is InputEventMouseMotion:
		var mouse := event as InputEventMouseMotion
		if mouse.device == InputEvent.DEVICE_ID_EMULATION or TouchState.shared().is_active():
			# In the browser finger drags also arrive as mouse motion (TouchOverlay).
			return NO_CHANGE
		return Kind.KEYBOARD_MOUSE if mouse.relative.length() >= MOUSE_MOTION_THRESHOLD else NO_CHANGE
	return NO_CHANGE


## Takes note of an input event; true if the device in use changed.
func note(event: InputEvent) -> bool:
	var new_kind := kind_of(event)
	if new_kind == NO_CHANGE:
		return false
	if new_kind == Kind.GAMEPAD:
		var had_letters := has_xbox_letters()
		joypad = event.device
		# A gamepad on a touch device: back from the on-screen controls (TouchState, like a keyboard).
		var touch := TouchState.shared()
		if not touch.forced:
			touch.touched = false
		if kind == Kind.GAMEPAD and has_xbox_letters() != had_letters:
			# Another pad with other face buttons (letters <-> positions, D-192): same kind, but the
			# key symbols have to be rebuilt.
			changed.emit(kind)
			return false
	return set_kind(new_kind as Kind)


## Switches the device in use; true if it changed (then changed is emitted and the cursor follows).
func set_kind(new_kind: Kind) -> bool:
	if new_kind == kind:
		return false
	kind = new_kind
	apply_cursor(kind)
	changed.emit(kind)
	return true


## The mouse cursor is hidden while this device is in use.
static func wants_hidden_cursor(device_kind: int) -> bool:
	return device_kind == Kind.GAMEPAD


## Hides or shows the cursor for device_kind. Only switches between visible and hidden, so a
## captured or confined mouse of some other screen stays as it is; no-op without a real display.
static func apply_cursor(device_kind: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if wants_hidden_cursor(device_kind):
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	elif Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

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

static var _shared: InputDevice = null

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
		joypad = event.device
		# A gamepad on a touch device: back from the on-screen controls (TouchState, like a keyboard).
		var touch := TouchState.shared()
		if not touch.forced:
			touch.touched = false
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

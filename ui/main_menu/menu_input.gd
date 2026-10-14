class_name MenuInput
extends RefCounted
## Key rules of the main menu: arrows or WASD move, Enter/Space confirm, Esc back, Del deletes.
## Held arrows repeat (echo); confirm and back do not.


static func is_up(event: InputEvent) -> bool:
	return event.is_action_pressed(&"ui_up", true) or event.is_action_pressed(&"move_up", true)


static func is_down(event: InputEvent) -> bool:
	return event.is_action_pressed(&"ui_down", true) or event.is_action_pressed(&"move_down", true)


static func is_left(event: InputEvent) -> bool:
	return event.is_action_pressed(&"ui_left", true) or event.is_action_pressed(&"move_left", true)


static func is_right(event: InputEvent) -> bool:
	return event.is_action_pressed(&"ui_right", true) or event.is_action_pressed(&"move_right", true)


static func is_accept(event: InputEvent) -> bool:
	return event.is_action_pressed(&"ui_accept")


static func is_back(event: InputEvent) -> bool:
	return event.is_action_pressed(&"ui_cancel")


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

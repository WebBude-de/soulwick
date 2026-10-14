class_name GameOptions
extends RefCounted
## Player options that are not volumes (UX1): window mode and screen shake. Global like the
## volumes (settings.cfg [options] via SaveManager.get_option/set_option, not per save slot).
## apply_all() runs at start (scenes/main.gd, scenes/world_controller.gd); the options panel calls
## the setters, which store and apply at once. F11 toggles the window mode everywhere.

const FULLSCREEN: StringName = &"fullscreen"
const SCREEN_SHAKE: StringName = &"screen_shake"


static func apply_all() -> void:
	apply_window_mode()
	CameraShake.enabled = is_screen_shake_enabled()


static func is_fullscreen() -> bool:
	return SaveManager.get_option(FULLSCREEN, false)


static func set_fullscreen(on: bool) -> void:
	SaveManager.set_option(FULLSCREEN, on)
	apply_window_mode()


static func toggle_fullscreen() -> void:
	set_fullscreen(not is_fullscreen())


static func is_screen_shake_enabled() -> bool:
	return SaveManager.get_option(SCREEN_SHAKE, true)


static func set_screen_shake(on: bool) -> void:
	SaveManager.set_option(SCREEN_SHAKE, on)
	CameraShake.enabled = on


## Puts the window into the stored mode. Leaves a maximised window alone when "Fenster" is chosen,
## and does nothing without a real window (headless tests and tools).
static func apply_window_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if is_fullscreen() and not is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not is_fullscreen() and is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


## F11 toggles fullscreen. Returns true if the event was used.
static func handle_shortcut(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	if key.keycode == KEY_F11:
		toggle_fullscreen()
		return true
	return false

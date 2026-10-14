class_name GameCursor
extends RefCounted
## Custom mouse cursors: crosshair while playing, pixel arrow in menus and dialogs.

const CROSSHAIR: Texture2D = preload("res://art/ui/cursor_crosshair.png")
const POINTER: Texture2D = preload("res://art/ui/cursor_pointer.png")


static func use_crosshair() -> void:
	Input.set_custom_mouse_cursor(CROSSHAIR, Input.CURSOR_ARROW, CROSSHAIR.get_size() * 0.5)


static func use_pointer() -> void:
	Input.set_custom_mouse_cursor(POINTER, Input.CURSOR_ARROW, Vector2(1, 1))

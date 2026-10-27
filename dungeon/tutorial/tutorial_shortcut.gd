class_name TutorialShortcut
extends Interactable
## "Kenne ich schon" at the start of the practice run (WK10): a sign beside the start; using it (the
## interact key, its gamepad button or the touch button, like every Interactable) skips the practice
## run and goes straight into room 1. The progress strip (TutorialHud) has the same as a quiet link
## for the mouse. Quiet here as well (WK10b): a muted caption, the key on the board.

## Reach of the use area (px).
const RADIUS := 56.0
## The sign's board shows the interact key (TutorialSign.BOARD_CENTER).
const KEY_PIXEL := 2
## Caption above the sign (world px).
const CAPTION_SIZE := 14

var _key_holder: Control = null


func _init() -> void:
	name = "Shortcut"
	prompt = "TUTORIAL_SKIP"


func _ready() -> void:
	super._ready()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)
	add_child(TutorialArt.sprite(&"sign"))
	_key_holder = Control.new()
	_key_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_key_holder)
	_build_key()
	var caption := Label.new()
	caption.name = "CaptionSkip"
	caption.text = Loc.t(&"TUTORIAL_SKIP")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override(&"font_size", CAPTION_SIZE)
	caption.add_theme_color_override(&"font_color", UiKit.COLOR_MUTED)
	caption.add_theme_color_override(&"font_outline_color", Color.BLACK)
	caption.add_theme_constant_override(&"outline_size", 4)
	caption.size = Vector2(220, 24)
	caption.position = Vector2(-110, -96)
	caption.z_index = 30
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	if not InputDevice.shared().changed.is_connected(_on_device_changed):
		InputDevice.shared().changed.connect(_on_device_changed)


func _exit_tree() -> void:
	if InputDevice.shared().changed.is_connected(_on_device_changed):
		InputDevice.shared().changed.disconnect(_on_device_changed)


func _build_key() -> void:
	for child in _key_holder.get_children():
		child.free()
	var key := TutorialKeys.cap(&"interact", false, KEY_PIXEL)
	_key_holder.add_child(key)
	var size := key.get_combined_minimum_size()
	key.size = size
	key.position = TutorialSign.BOARD_CENTER - size * 0.5


func _on_device_changed(_kind: int) -> void:
	if is_inside_tree():
		_build_key()

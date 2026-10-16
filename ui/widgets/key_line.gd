extends VBoxContainer
## Key line of a menu (footer, P0-2 step 2): the keyboard text as a Label and, while a gamepad is
## in use, the gamepad text with button pictures ("{a} los · {b} zurück", PadNav tokens) as a
## RichTextLabel. Both texts are translation keys or composed texts; the line follows language and
## device changes by itself. Without a gamepad text the Label always shows.
## Use: const KeyLine := preload("res://ui/widgets/key_line.gd"); var line := KeyLine.new();
## line.setup(UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED); line.set_texts(&"KEY", &"KEY_PAD").

const PadNav := preload("res://ui/widgets/pad_nav.gd")

## Screen pixels per art pixel of the button pictures (HUD scale fits 6-7 px menu text).
var pixel := KeyCap.HUD_PIXEL
## Keyboard text (always a Label, so hosts can read and style it).
var label: Label = null
## Gamepad text with pictures (visible while a gamepad is in use and a gamepad text is set).
var pad_label: RichTextLabel = null

var _text := ""
var _pad_text := ""
var _alignment := HORIZONTAL_ALIGNMENT_CENTER


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 0)
	label = UiKit.text_label("", UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
	label.name = "Keys"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)
	pad_label = GlyphText.rich_label(UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
	pad_label.name = "PadKeys"
	pad_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	pad_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pad_label.visible = false
	add_child(pad_label)


## Text size (mockup pixels), colour and alignment of both lines.
func setup(size: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	_alignment = alignment
	label.add_theme_font_size_override("font_size", UiKit.font_px(size))
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = alignment
	pad_label.add_theme_font_size_override("normal_font_size", UiKit.font_px(size))
	pad_label.add_theme_color_override("default_color", color)
	match alignment:
		HORIZONTAL_ALIGNMENT_LEFT:
			pad_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		HORIZONTAL_ALIGNMENT_RIGHT:
			pad_label.size_flags_horizontal = Control.SIZE_SHRINK_END
		_:
			pad_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_refresh()


func set_color(color: Color) -> void:
	label.add_theme_color_override("font_color", color)
	pad_label.add_theme_color_override("default_color", color)


## Keyboard text and gamepad text ("" = the keyboard text also on a gamepad).
func set_texts(text: String, pad_text := "") -> void:
	_text = text
	_pad_text = pad_text
	label.text = text
	_refresh()


func get_text() -> String:
	return tr(_text)


func get_pad_text() -> String:
	return tr(_pad_text)


## The gamepad line is the one on screen.
func is_showing_pad() -> bool:
	return pad_label.visible


func _enter_tree() -> void:
	var device := InputDevice.shared()
	if not device.changed.is_connected(_on_device_changed):
		device.changed.connect(_on_device_changed)
	_refresh()


func _exit_tree() -> void:
	var device := InputDevice.shared()
	if device.changed.is_connected(_on_device_changed):
		device.changed.disconnect(_on_device_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and pad_label != null:
		_refresh()


func _on_device_changed(_kind: int) -> void:
	_refresh()


func _refresh() -> void:
	var pad := not _pad_text.is_empty() and PadNav.is_pad()
	label.visible = not pad
	pad_label.visible = pad
	if pad:
		PadNav.fill(pad_label, tr(_pad_text), pixel, _alignment)

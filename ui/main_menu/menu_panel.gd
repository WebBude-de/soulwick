class_name MenuPanel
extends PanelContainer
## Base of the main menu's sub panels (Spielstände, Neuer Spielstand, Optionen): framed panel with
## eyebrow + title, content rows and a key line at the bottom. The main menu forwards keys to
## handle_input(); Esc (or the back button) emits closed.
## Texts are translation keys (D-111): header and footer labels re-translate themselves on a
## language change; panels with composed texts call set_header()/set_footer() again in
## _notification(NOTIFICATION_TRANSLATION_CHANGED).
## Gamepad (P0-2 step 2): the footer has a gamepad line with button pictures (KeyLine, shown while a
## gamepad is in use), action buttons show their gamepad button under the label ("Enter" -> A,
## "Esc" -> B, or the pad_key given).

signal closed

const KeyLine := preload("res://ui/widgets/key_line.gd")
## Key hint of an action button -> gamepad token (PadNav) when the caller names none.
const PAD_KEYS := {"Enter": "{a}", "Esc": "{b}"}

## Panel padding in mockup pixels (vertical, horizontal).
const PADDING := Vector2(8, 10)

var content: VBoxContainer = null
var _eyebrow: Label = null
var _title: Label = null
var _footer: Label = null
var _key_line: KeyLine = null


func _init() -> void:
	add_theme_stylebox_override("panel", UiKit.padded_style(&"normal", PADDING.x, PADDING.y))
	mouse_filter = Control.MOUSE_FILTER_STOP
	content = UiKit.vbox(int(UiKit.px(5)))
	add_child(content)


## Fixed width in mockup pixels.
func set_width(spec_width: float) -> void:
	custom_minimum_size.x = UiKit.px(spec_width)


## eyebrow_text and title_text: translation keys or ready texts (the eyebrow is shown in capitals).
func add_header(eyebrow_text: String, title_text: String) -> void:
	var box := UiKit.vbox(int(UiKit.px(1)))
	if not eyebrow_text.is_empty():
		_eyebrow = UiKit.eyebrow(eyebrow_text, UiKit.COLOR_MUTED)
		_eyebrow.uppercase = true
		box.add_child(_eyebrow)
	_title = UiKit.text_label(title_text, UiKit.SIZE_TITLE, UiKit.COLOR_GOLD, true)
	box.add_child(_title)
	content.add_child(box)


## Replaces the header texts (composed texts after a language change).
func set_header(eyebrow_text: String, title_text: String) -> void:
	if _eyebrow != null:
		_eyebrow.text = eyebrow_text
	if _title != null:
		_title.text = title_text


## Key line under the content (translation key or composed text), e.g. "↑↓ wählen · Esc zurück";
## pad_text: the same for a gamepad with PadNav tokens ("{a} los · {b} zurück"), "" = none.
func set_footer(text: String, pad_text := "") -> void:
	if _key_line == null:
		_key_line = KeyLine.new()
		_key_line.name = "Footer"
		_key_line.setup(UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
		_footer = _key_line.label
		content.add_child(_key_line)
	_key_line.set_texts(text, pad_text)
	content.move_child(_key_line, content.get_child_count() - 1)


## The footer's gamepad line is on screen (gamepad in use).
func is_footer_pad() -> bool:
	return _key_line != null and _key_line.is_showing_pad()


## The footer as shown (keys translated).
func get_footer_text() -> String:
	return tr(_footer.text) if _footer != null else ""


## Override: return true if the event was used.
func handle_input(_event: InputEvent) -> bool:
	return false


func close() -> void:
	UiSound.back(self)
	closed.emit()


## Small framed button with a key hint under the label (UiKit.dialog_button look). pad_key: the
## gamepad button shown instead of the key while a gamepad is in use (PadNav token, e.g. "{y}");
## "" = from PAD_KEYS (Enter -> A, Esc -> B) or none.
static func action_button(text: String, key_hint: String, on_pressed: Callable, is_default := false, pad_key := "") -> Button:
	var button := UiKit.dialog_button(text, key_hint, on_pressed, is_default)
	button.custom_minimum_size.x = UiKit.px(70)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if pad_key.is_empty():
		pad_key = PAD_KEYS.get(key_hint, "")
	if not pad_key.is_empty():
		_add_pad_key(button, key_hint, pad_key)
	return button


## Replaces the key hint label under a dialog button by a KeyLine (key name or gamepad button).
static func _add_pad_key(button: Button, key_hint: String, pad_key: String) -> void:
	var sub: Label = null
	for child in button.get_children():
		if child is Label:
			sub = child
	if sub == null:
		return
	var line := KeyLine.new()
	line.name = "KeyHint"
	line.setup(UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
	line.set_texts(key_hint, pad_key)
	line.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	line.offset_top = sub.offset_top
	line.offset_bottom = sub.offset_bottom
	button.remove_child(sub)
	sub.queue_free()
	button.add_child(line)

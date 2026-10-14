class_name MenuPanel
extends PanelContainer
## Base of the main menu's sub panels (Spielstände, Neuer Spielstand, Optionen): framed panel with
## eyebrow + title, content rows and a key line at the bottom. The main menu forwards keys to
## handle_input(); Esc (or the back button) emits closed.

signal closed

## Panel padding in mockup pixels (vertical, horizontal).
const PADDING := Vector2(8, 10)

var content: VBoxContainer = null
var _footer: Label = null


func _init() -> void:
	add_theme_stylebox_override("panel", UiKit.padded_style(&"normal", PADDING.x, PADDING.y))
	mouse_filter = Control.MOUSE_FILTER_STOP
	content = UiKit.vbox(int(UiKit.px(5)))
	add_child(content)


## Fixed width in mockup pixels.
func set_width(spec_width: float) -> void:
	custom_minimum_size.x = UiKit.px(spec_width)


func add_header(eyebrow_text: String, title_text: String) -> void:
	var box := UiKit.vbox(int(UiKit.px(1)))
	if not eyebrow_text.is_empty():
		box.add_child(UiKit.eyebrow(eyebrow_text, UiKit.COLOR_MUTED))
	var title := UiKit.text_label(title_text, UiKit.SIZE_TITLE, UiKit.COLOR_GOLD, true)
	box.add_child(title)
	content.add_child(box)


## Key line under the content, e.g. "↑↓ wählen · Enter spielen · Esc zurück".
func set_footer(text: String) -> void:
	if _footer == null:
		_footer = UiKit.text_label("", UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
		_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(_footer)
	_footer.text = text
	content.move_child(_footer, content.get_child_count() - 1)


func get_footer_text() -> String:
	return _footer.text if _footer != null else ""


## Override: return true if the event was used.
func handle_input(_event: InputEvent) -> bool:
	return false


func close() -> void:
	UiSound.back(self)
	closed.emit()


## Small framed button with a key hint under the label (UiKit.dialog_button look).
static func action_button(text: String, key_hint: String, on_pressed: Callable, is_default := false) -> Button:
	var button := UiKit.dialog_button(text, key_hint, on_pressed, is_default)
	button.custom_minimum_size.x = UiKit.px(70)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button

class_name MenuPanel
extends PanelContainer
## Base of the main menu's sub panels (Spielstände, Neuer Spielstand, Optionen): framed panel with
## eyebrow + title, content rows and a key line at the bottom. The main menu forwards keys to
## handle_input(); Esc (or the back button) emits closed.
## Texts are translation keys (D-111): header and footer labels re-translate themselves on a
## language change; panels with composed texts call set_header()/set_footer() again in
## _notification(NOTIFICATION_TRANSLATION_CHANGED).

signal closed

## Panel padding in mockup pixels (vertical, horizontal).
const PADDING := Vector2(8, 10)

var content: VBoxContainer = null
var _eyebrow: Label = null
var _title: Label = null
var _footer: Label = null


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


## Key line under the content (translation key or composed text), e.g. "↑↓ wählen · Esc zurück".
func set_footer(text: String) -> void:
	if _footer == null:
		_footer = UiKit.text_label("", UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
		_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(_footer)
	_footer.text = text
	content.move_child(_footer, content.get_child_count() - 1)


## The footer as shown (keys translated).
func get_footer_text() -> String:
	return tr(_footer.text) if _footer != null else ""


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

class_name UiDialog
extends RefCounted
## Shared dialog mask of docs/design (screens 06 portal, 07 run end, 10 room 45): centred panel,
## title, body text, "label … value" rows, buttons with one default (button_hover, Enter) and a
## small footnote. Builds on Modal, so every dialog pauses the simulation (D-043).

## Panel padding in mockup pixels (ui_spec dialog.padding: vertical, horizontal).
const PADDING := Vector2(10, 12)


## Dialog with title and optional body; spec_width in mockup pixels (220 portal, 230 run end, 250 room 45).
static func create(reason: StringName, spec_width: float, title_text: String, body := "", title_color := UiKit.COLOR_GOLD) -> Modal:
	var modal := Modal.create(reason)
	modal.frame.add_theme_stylebox_override("panel", UiKit.padded_style(&"normal", PADDING.x, PADDING.y))
	modal.set_width(spec_width)
	modal.content.add_child(UiKit.title(title_text, UiKit.SIZE_TITLE, title_color))
	if not body.is_empty():
		var text := UiKit.wrapped_text(body, spec_width - PADDING.y * 2.0, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		modal.content.add_child(text)
	return modal


## Muted one-liner under the title, e.g. "Raum 12 · Zyklus 3".
static func add_subtitle(modal: Modal, text: String) -> void:
	var label := UiKit.text_label(text, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal.content.add_child(label)


## rows: [[caption, value, value_color], ...]; value_color is optional.
static func add_rows(modal: Modal, rows: Array) -> void:
	if rows.is_empty():
		return
	var box := UiKit.vbox(int(UiKit.px(4)))
	for row in rows:
		var color: Color = row[2] if row.size() > 2 else UiKit.COLOR_TEXT
		box.add_child(UiKit.value_row(String(row[0]), String(row[1]), color))
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_top", int(UiKit.px(2)))
	margin.add_theme_constant_override("margin_bottom", int(UiKit.px(2)))
	margin.add_child(box)
	modal.content.add_child(margin)


## options: [{"text": String, "sub": String, "result": Variant, "default": bool}, ...].
## The default option is highlighted and triggered by Enter. Returns the buttons in order.
static func add_buttons(modal: Modal, options: Array, vertical := true) -> Array[Button]:
	var buttons: Array[Button] = []
	var box: BoxContainer = UiKit.vbox(int(UiKit.px(6))) if vertical else UiKit.hbox(int(UiKit.px(6)))
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	for option: Dictionary in options:
		var result: Variant = option.get("result")
		var is_default: bool = option.get("default", false)
		var button := UiKit.dialog_button(option.get("text", ""), option.get("sub", ""), modal.finish.bind(result), is_default)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if vertical:
			button.custom_minimum_size.x = UiKit.px(88)
		box.add_child(button)
		buttons.append(button)
		if is_default:
			modal.accept_allowed = true
			modal.accept_result = result
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_top", int(UiKit.px(4)))
	margin.add_child(box)
	modal.content.add_child(margin)
	return buttons


## Small note at the bottom of the panel (6 px, #7a7396).
static func add_footnote(modal: Modal, text: String) -> void:
	var label := UiKit.text_label(text, UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal.content.add_child(label)

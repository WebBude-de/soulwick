class_name UiDialog
extends RefCounted
## Menu kit of all dungeon dialogs (UX2) on top of the dialog mask of docs/design (screens 02-07, 10):
## one centred panel on the dimmed scene, a header (eyebrow in capitals, title, subtitle, optional
## badge on the right such as the run gold), a divider, the body (cards, rows, option buttons) and
## the key bar inside the panel (Modal.set_key_hints: key caps, "Spiel pausiert"). Option buttons
## carry their key as a key cap; the default option (Enter) is drawn with button_hover. Builds on
## Modal, so every dialog pauses the simulation (D-043) and sounds the same (open, hover, click,
## back, error).
##
## Widths in mockup pixels: WIDTH_NARROW (confirmations), WIDTH_MEDIUM (campfire, weapon slot),
## WIDTH_WIDE (cards: upgrade choice, shop, Tab overview).

## Panel padding in mockup pixels (ui_spec dialog.padding: vertical, horizontal).
const PADDING := Vector2(10, 12)
const WIDTH_NARROW := 232.0
const WIDTH_MEDIUM := 300.0
const WIDTH_WIDE := 452.0
## Smallest width of an option button in a row (mockup pixels).
const OPTION_MIN_WIDTH := 90.0
## Gap between the key cap and the label of an option button (mockup pixels).
const OPTION_KEY_GAP := 4.0
const OPTION_KEY_MARGIN := 5.0
## Integer upscale of option icons (16 px art -> 32 px on screen, about 12 mockup pixels).
const OPTION_ICON_SCALE := 2
## Legacy "sub" lines that only name a key become a key cap (add_buttons).
const KEY_NAMES: Array[String] = ["Enter", "Esc", "Tab", "N", "1", "2", "3", "4", "5", "6"]


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


## The dungeon menu frame (UX2): eyebrow (accent colour, capitals), title, wrapped subtitle and a
## divider. Add the body to modal.content, then set_key_hints for the key bar.
static func create_menu(reason: StringName, spec_width: float, title_text: String, subtitle := "", eyebrow := "",
		accent := UiKit.COLOR_GOLD, title_color := UiKit.COLOR_GOLD) -> Modal:
	var modal := Modal.create(reason)
	modal.frame.add_theme_stylebox_override("panel", UiKit.padded_style(&"normal", PADDING.x, PADDING.y))
	modal.set_width(spec_width)
	var header := UiKit.hbox(int(UiKit.px(4)))
	header.name = "Header"
	modal.content.add_child(header)
	var left := Control.new()
	left.name = "BadgeBalance"
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(left)
	var center := UiKit.vbox(int(UiKit.px(1)))
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(center)
	var right := UiKit.hbox(0)
	right.name = "BadgeSlot"
	right.alignment = BoxContainer.ALIGNMENT_END
	header.add_child(right)
	if not eyebrow.is_empty():
		var eyebrow_label := UiKit.eyebrow(eyebrow, accent)
		eyebrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		center.add_child(eyebrow_label)
	center.add_child(UiKit.title(title_text, UiKit.SIZE_TITLE, title_color))
	if not subtitle.is_empty():
		var sub := UiKit.wrapped_text(subtitle, spec_width - PADDING.y * 2.0 - 60.0, UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		center.add_child(sub)
	modal.content.add_child(UiKit.separator())
	return modal


## Small control on the right of the header (e.g. the run gold in the shop). The title stays centred.
static func add_header_badge(modal: Modal, badge: Control) -> void:
	var header := modal.content.get_node_or_null(^"Header")
	if header == null:
		modal.content.add_child(badge)
		return
	header.get_node(^"BadgeSlot").add_child(badge)
	var balance := header.get_node(^"BadgeBalance") as Control
	balance.custom_minimum_size.x = badge.get_combined_minimum_size().x
	badge.minimum_size_changed.connect(func() -> void:
		if is_instance_valid(balance) and is_instance_valid(badge):
			balance.custom_minimum_size.x = badge.get_combined_minimum_size().x)


## Muted one-liner under the title, e.g. "Raum 12 · Zyklus 3".
static func add_subtitle(modal: Modal, text: String) -> void:
	var label := UiKit.text_label(text, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal.content.add_child(label)


## Section line in the body, e.g. "ODER EIN UPGRADE STÄRKEN".
static func add_section(modal: Modal, text: String, color := UiKit.COLOR_GOLD) -> Label:
	var label := UiKit.eyebrow(text, color)
	modal.content.add_child(label)
	return label


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


## options: [{"text": String, "sub": String, "key": String, "result": Variant, "default": bool}, ...].
## The default option is highlighted and triggered by Enter. A "sub" that only names a key
## ("Enter", "Esc", "N") becomes the key cap. Returns the buttons in order.
static func add_buttons(modal: Modal, options: Array, vertical := true) -> Array[Button]:
	var buttons: Array[Button] = []
	var box: BoxContainer = UiKit.vbox(int(UiKit.px(5))) if vertical else UiKit.hbox(int(UiKit.px(6)))
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	for option: Dictionary in options:
		var result: Variant = option.get("result")
		var is_default: bool = option.get("default", false)
		var sub: String = option.get("sub", "")
		var key: String = option.get("key", "")
		if key.is_empty() and KEY_NAMES.has(sub):
			key = sub
			sub = ""
		var button := option_button(option.get("text", ""), sub, key, modal.finish.bind(result), is_default)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if vertical:
			button.custom_minimum_size.x = UiKit.px(OPTION_MIN_WIDTH + 10.0)
		box.add_child(button)
		buttons.append(button)
		if is_default:
			modal.accept_allowed = true
			modal.accept_result = result
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_top", int(UiKit.px(2)))
	margin.add_child(box)
	modal.content.add_child(margin)
	return buttons


## Framed option button: key cap on the left, label, optional sub line (e.g. "+4 HP"). is_default
## draws it with button_hover (the action Enter triggers). Disabled: button_disabled, muted text,
## a click plays UiSound.error (UiKit.button). Toggle with set_option_enabled.
static func option_button(text: String, sub: String, key: String, on_pressed: Callable, is_default := false) -> Button:
	var button := UiKit.button(text, on_pressed)
	button.name = "Option"
	button.custom_minimum_size = Vector2(UiKit.px(OPTION_MIN_WIDTH), 0)
	button.add_theme_font_size_override("font_size", UiKit.font_px(UiKit.SIZE_KEY_HINT))
	button.add_theme_font_override("font", UiKit.bold_font())
	button.add_theme_color_override("font_disabled_color", UiKit.COLOR_DISABLED)
	var sub_height := px_sub(sub)
	var shift := 0.0
	var chip: UiChip = null
	if not key.is_empty():
		chip = UiChip.key(key)
		chip.name = "KeyCap"
		button.add_child(chip)
		shift = key_cap_width(key) + UiKit.px(OPTION_KEY_GAP)
	var styles := {
		"normal": UiKit.panel_style(&"button_hover" if is_default else &"button"),
		"hover": UiKit.panel_style(&"button_hover"),
		"pressed": UiKit.panel_style(&"button_hover"),
		"disabled": UiKit.panel_style(&"button_disabled"),
	}
	for state: String in styles:
		var style := (styles[state] as StyleBoxTexture).duplicate() as StyleBoxTexture
		style.content_margin_bottom += sub_height
		style.content_margin_left += shift
		button.add_theme_stylebox_override(state, style)
	if not sub.is_empty():
		var sub_label := UiKit.text_label(sub, UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
		sub_label.name = "Sub"
		sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		sub_label.offset_left = shift
		sub_label.offset_bottom = -UiKit.px(5)
		sub_label.offset_top = sub_label.offset_bottom - UiKit.font_px(UiKit.SIZE_EYEBROW) - UiKit.px(2)
		button.add_child(sub_label)
	if chip != null:
		var place := func() -> void:
			if is_instance_valid(chip):
				var chip_size: Vector2 = chip.get_combined_minimum_size()
				chip.size = chip_size
				chip.position = Vector2(UiKit.px(OPTION_KEY_MARGIN), floorf((button.size.y - chip_size.y) * 0.5))
		button.resized.connect(place)
		chip.ready.connect(place)
	return button


## Pixel icon in front of an option label (upgrade icons, the heart): 16 px art at twice its size
## so it stays crisp instead of being drawn at its tiny source size.
static func set_option_icon(button: Button, texture: Texture2D) -> void:
	if texture == null:
		return
	button.icon = UiKit.upscale(texture, OPTION_ICON_SCALE)
	button.add_theme_constant_override("icon_max_width", int(texture.get_width() * OPTION_ICON_SCALE))


## Enables or disables an option button; its key cap and sub line follow (muted when disabled).
static func set_option_enabled(button: Button, enabled: bool) -> void:
	button.disabled = not enabled
	var sub := button.get_node_or_null(^"Sub") as Label
	if sub != null:
		sub.add_theme_color_override("font_color", UiKit.COLOR_MUTED if enabled else UiKit.COLOR_DISABLED)
	var chip := button.get_node_or_null(^"KeyCap") as Control
	if chip != null:
		chip.modulate = Color.WHITE if enabled else Color(0.6, 0.6, 0.7)


## On-screen width of a key cap with this text (the cap is not in the tree yet when buttons are built).
static func key_cap_width(key: String) -> float:
	var text_width := UiKit.bold_font().get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.font_px(UiChip.KEY_FONT_SIZE)).x
	return ceilf(text_width) + UiKit.px(UiChip.KEY_PADDING.x) * 2.0 + UiKit.ART_SCALE * 2.0


## Extra bottom margin of a button with a sub line.
static func px_sub(sub: String) -> float:
	return 0.0 if sub.is_empty() else UiKit.px(UiKit.SIZE_EYEBROW + 3)


## Small note at the bottom of the panel (6 px, #7a7396).
static func add_footnote(modal: Modal, text: String) -> void:
	var label := UiKit.text_label(text, UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal.content.add_child(label)

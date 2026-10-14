class_name UiChip
extends PanelContainer
## Small pixel chips of the dungeon menu kit (UX2): key caps for key hints ("1", "Enter", "Esc")
## and status badges on cards ("Verkauft", "Am Limit", "Zu wenig Gold" with a lock). Hard borders
## of one art pixel without anti-aliasing: the nine-patch panels are too big for 6-8 px text.

## Key cap: dark face, soft rim, a thicker bottom edge like a key.
const KEY_FACE := UiKit.COLOR_BG
const KEY_RIM := UiKit.COLOR_EMPTY_SLOT
const KEY_TEXT := UiKit.COLOR_TEXT
## Paddings in mockup pixels (horizontal, vertical).
const KEY_PADDING := Vector2(3, 0)
const BADGE_PADDING := Vector2(3, 1)
## Badge icons (lock) at 8 mockup pixels.
const BADGE_ICON_SIZE := 8.0
## Key names at 7 mockup pixels (6 px capitals were too small for "Enter" next to a caption).
const KEY_FONT_SIZE := UiKit.SIZE_BODY

static var _styles: Dictionary = {}

var _label: Label = null


## Key cap with the key name, e.g. UiChip.key("Enter"). Ranges like "1–3" work as well.
static func key(text: String) -> UiChip:
	var chip := UiChip.new()
	chip.name = "Key"
	chip.add_theme_stylebox_override("panel", _style(KEY_FACE, KEY_RIM, KEY_PADDING, true))
	chip._label = UiKit.text_label(text, KEY_FONT_SIZE, KEY_TEXT, true)
	chip._label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip._label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(chip._label)
	return chip


## Status badge in capitals, tinted by color; icon (e.g. the lock) sits in front of the text.
static func badge(text: String, color: Color, icon: Texture2D = null) -> UiChip:
	var chip := UiChip.new()
	chip.name = "Badge"
	chip.add_theme_stylebox_override("panel", _style(color.darkened(0.78), color.darkened(0.25), BADGE_PADDING, false))
	var row := UiKit.hbox(int(UiKit.px(2)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	chip.add_child(row)
	if icon != null:
		var picture := UiKit.pixel_icon(icon, BADGE_ICON_SIZE)
		picture.modulate = color.lightened(0.2)
		row.add_child(picture)
	chip._label = UiKit.eyebrow(text, color)
	chip._label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(chip._label)
	return chip


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func get_text() -> String:
	return _label.text if _label != null else ""


static func _style(face: Color, rim: Color, padding: Vector2, keycap: bool) -> StyleBoxFlat:
	var key_name := "%s_%s_%s_%s" % [face.to_html(), rim.to_html(), padding, keycap]
	if _styles.has(key_name):
		return _styles[key_name]
	var style := StyleBoxFlat.new()
	style.bg_color = face
	style.border_color = rim
	style.anti_aliasing = false
	style.set_border_width_all(UiKit.ART_SCALE)
	if keycap:
		style.border_width_bottom = UiKit.ART_SCALE * 2
	style.content_margin_left = UiKit.px(padding.x)
	style.content_margin_right = UiKit.px(padding.x)
	style.content_margin_top = UiKit.px(padding.y)
	style.content_margin_bottom = UiKit.px(padding.y)
	_styles[key_name] = style
	return style

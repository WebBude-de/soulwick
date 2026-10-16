class_name KeyCap
extends Control
## Compact key cap for the HUD, the controls card and hints (playtest note #12): the key's picture
## from InputGlyphs (mouse buttons, space, shift, tab …) or its short name ("Q", "Esc") on a cap
## of the same height, drawn at a whole pixel scale so it stays crisp. Built from the current
## binding (action or event), so a rebinding shows the right key; texts follow the language.
## The node is named "Key" like UiChip's key caps.

## Screen pixels per art pixel of the HUD at 1280×720 (dialogs use UiKit.ART_SCALE).
const HUD_PIXEL: int = maxi(1, UiKit.ART_SCALE - 1)

## Shown key: picture (null = text cap) and name ("Q", "Rechtsklick" for the picture's tooltip).
var glyph: Texture2D = null
var glyph_id: StringName = &""
var text := ""
## Screen pixels per art pixel.
var pixel := HUD_PIXEL

var _event: InputEvent = null
var _action: StringName = &""
var _fixed_name := ""


## Cap of the first key bound to action ("?" when unbound).
static func for_action(action: StringName, scale := HUD_PIXEL) -> KeyCap:
	var cap := KeyCap.new()
	cap.pixel = scale
	cap._action = action
	cap._refresh()
	return cap


static func for_event(event: InputEvent, scale := HUD_PIXEL) -> KeyCap:
	var cap := KeyCap.new()
	cap.pixel = scale
	cap._event = event
	cap._refresh()
	return cap


## Cap for a key name or glyph id ("Rechtsklick", "Space", "mouse", "1 – 3").
static func for_name(key_name: String, scale := HUD_PIXEL) -> KeyCap:
	var cap := KeyCap.new()
	cap.pixel = scale
	cap._fixed_name = key_name
	cap._refresh()
	return cap


## Caps of a control (ControlsInfo id) in a row: W A S D for moving, the mouse (gamepad: the right
## stick) for aiming.
static func row_for_control(id: StringName, scale := HUD_PIXEL, separation := -1) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", scale if separation < 0 else separation)
	var actions := ControlsInfo.actions(id)
	if actions.is_empty():
		# Aiming: the mouse, or the right stick while a gamepad is in use (P0-2).
		row.add_child(for_name(String(InputGlyphs.aim_id()) if id == ControlsInfo.AIM else ControlsInfo.key_text(id), scale))
		return row
	var seen: Array[String] = []
	for action in actions:
		var cap := for_action(action, scale)
		if seen.has(cap.text):
			cap.free()
			continue
		seen.append(cap.text)
		row.add_child(cap)
	return row


func _init() -> void:
	name = "Key"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func get_text() -> String:
	return text


func is_glyph() -> bool:
	return glyph != null


func _refresh() -> void:
	glyph_id = &""
	text = ""
	if _event != null or _action != &"":
		var event := _event if _event != null else InputGlyphs.first_event(_action)
		if event == null:
			text = "?"
		else:
			glyph_id = InputGlyphs.id_for_event(event)
			text = ControlsInfo.event_text(event) if glyph_id != &"" else InputGlyphs.cap_text(event)
	else:
		var as_id := StringName(_fixed_name)
		glyph_id = as_id if InputGlyphs.IDS.has(as_id) else InputGlyphs.id_for_name(_fixed_name)
		text = Loc.t(&"KEY_MOUSE") if glyph_id == InputGlyphs.MOUSE and _fixed_name == String(InputGlyphs.MOUSE) else _fixed_name
	glyph = InputGlyphs.texture(glyph_id)
	# The full name stays reachable as a tooltip (mouse filter permitting) and for tools.
	tooltip_text = text
	update_minimum_size()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh()


func _get_minimum_size() -> Vector2:
	if glyph != null:
		return Vector2(glyph.get_width(), glyph.get_height()) * pixel
	var width := _text_width() + float((InputGlyphs.CAP_PADDING + 1) * 2 * pixel)
	# Single letters get a square-ish cap one art pixel narrower than high.
	width = maxf(width, float((InputGlyphs.CAP_HEIGHT - 1) * pixel))
	return Vector2(ceilf(width / pixel) * pixel, InputGlyphs.CAP_HEIGHT * pixel)


func _draw() -> void:
	if glyph != null:
		draw_texture_rect(glyph, Rect2(Vector2.ZERO, Vector2(glyph.get_width(), glyph.get_height()) * pixel), false)
		return
	var cap_size := _get_minimum_size()
	var p := float(pixel)
	var face_height := InputGlyphs.FACE_ROWS * p
	var art := InputGlyphs.key_cap_style(pixel)
	if art != null:
		# art/ui/input/input_key_cap.png as 9-slice (SPRITES_V10 §2b).
		draw_style_box(art, Rect2(Vector2.ZERO, cap_size))
	else:
		# Same proportions as InputGlyphs.cap_image: rim, face, thicker front edge, open corners.
		draw_rect(Rect2(p, 0, cap_size.x - 2.0 * p, cap_size.y), InputGlyphs.COLOR_RIM)
		draw_rect(Rect2(0, p, cap_size.x, cap_size.y - 2.0 * p), InputGlyphs.COLOR_RIM)
		draw_rect(Rect2(p, p, cap_size.x - 2.0 * p, face_height), InputGlyphs.COLOR_FACE)
	var font := UiKit.bold_font()
	var font_size := _font_size()
	var text_width := _text_width()
	# Capital letters centred on the face (Pixelify's cap height is about 0.7 em).
	var cap_height := roundf(font_size * 0.7)
	var baseline := p + roundf((face_height + cap_height) * 0.5)
	var x := roundf((cap_size.x - text_width) * 0.5)
	draw_string(font, Vector2(x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, InputGlyphs.COLOR_SYMBOL)


## Text size: the face height plus one art pixel (letters fill the face like the drawn symbols).
func _font_size() -> int:
	return (InputGlyphs.FACE_ROWS + 1) * pixel


func _text_width() -> float:
	return ceilf(UiKit.bold_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size()).x)

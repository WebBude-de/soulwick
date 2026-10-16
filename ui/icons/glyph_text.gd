class_name GlyphText
extends RefCounted
## Hint texts with input symbols (G3 round 2): key names inside a finished, translated sentence
## ("Mit Leertaste (Dash) über Löcher springen") become the pictures of InputGlyphs, inline in a
## RichTextLabel. Translations stay untouched: the producers keep filling %s with the key name
## (ControlsInfo.key_text / action_key), this class finds those names again as whole words.
## With touch in use the names of bound keys become the matching touch buttons (Leertaste ->
## Dash button; in a side-view segment the jump button), so a phone never shows "Leertaste".
## Single letters stay text on a keyboard (Q, E); key names without a picture stay text as well.
##
## Use wrapped() instead of UiKit.wrapped_text() for hint texts, or apply() on an existing
## RichTextLabel. Texts without key names give a plain Label (no RichTextLabel cost).

## Actions scanned for key names, in priority order (the first action that owns a name wins).
const ACTIONS: Array[StringName] = [
	&"dash", &"attack", &"special_attack", &"switch_weapon", &"interact", &"upgrade_overview", &"pause_menu",
	&"side_dash", &"move_up", &"move_left", &"move_down", &"move_right",
]
## Shortest key name replaced on a keyboard (single letters stay text there).
const MIN_NAME_LENGTH := 2


## Text as a wrapping label (width in mockup pixels): a RichTextLabel with pictures when the text
## names keys, else UiKit.wrapped_text.
static func wrapped(text: String, width: float, size := UiKit.SIZE_BODY, color := UiKit.COLOR_TEXT_SOFT, pixel := KeyCap.HUD_PIXEL) -> Control:
	var parts := split(text)
	if not has_glyphs(parts):
		return UiKit.wrapped_text(text, width, size, color)
	var label := rich_label(size, color)
	label.custom_minimum_size = Vector2(UiKit.px(width), 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fill(label, parts, pixel)
	return label


## Single-line variant (banners, subtitles): grows with its content.
static func line(text: String, size := UiKit.SIZE_BODY, color := UiKit.COLOR_TEXT_SOFT, pixel := KeyCap.HUD_PIXEL) -> Control:
	var parts := split(text)
	if not has_glyphs(parts):
		return UiKit.text_label(text, size, color)
	var label := rich_label(size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	fill(label, parts, pixel)
	return label


## Hook for existing RichTextLabels (e.g. a banner subtitle): replaces their content.
static func apply(label: RichTextLabel, text: String, pixel := KeyCap.HUD_PIXEL) -> void:
	fill(label, split(text), pixel)


## RichTextLabel in the UI look (Pixelify, text shadow, sized like UiKit.text_label).
static func rich_label(size := UiKit.SIZE_BODY, color := UiKit.COLOR_TEXT_SOFT) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = false
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	label.add_theme_font_override("normal_font", UiKit.get_font())
	label.add_theme_font_size_override("normal_font_size", UiKit.font_px(size))
	label.add_theme_color_override("default_color", color)
	label.add_theme_color_override("font_shadow_color", UiKit.COLOR_SHADOW)
	label.add_theme_constant_override("shadow_offset_x", UiKit.SHADOW_OFFSET)
	label.add_theme_constant_override("shadow_offset_y", UiKit.SHADOW_OFFSET)
	return label


static func fill(label: RichTextLabel, parts: Array, pixel: int) -> void:
	label.clear()
	for part: Variant in parts:
		if part is Texture2D:
			var texture := part as Texture2D
			label.add_image(texture, texture.get_width() * pixel, texture.get_height() * pixel, Color.WHITE, INLINE_ALIGNMENT_CENTER)
		else:
			label.add_text(String(part))


static func has_glyphs(parts: Array) -> bool:
	for part: Variant in parts:
		if part is Texture2D:
			return true
	return false


## The text cut into strings and glyph textures (key names replaced, see class comment).
static func split(text: String) -> Array:
	var hits: Array[Array] = []
	for entry: Array in name_glyphs():
		var key_name: String = entry[0]
		var regex := RegEx.create_from_string("(?<![\\p{L}\\p{N}])" + _escape(key_name) + "(?![\\p{L}\\p{N}])")
		for found in regex.search_all(text):
			var start := found.get_start()
			var end := found.get_end()
			var free := true
			for hit in hits:
				if start < int(hit[1]) and end > int(hit[0]):
					free = false
					break
			if free:
				hits.append([start, end, entry[1]])
	hits.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	var parts: Array = []
	var at := 0
	for hit in hits:
		if int(hit[0]) > at:
			parts.append(text.substr(at, int(hit[0]) - at))
		parts.append(InputGlyphs.texture(hit[2]))
		at = int(hit[1])
	if at < text.length():
		parts.append(text.substr(at))
	return parts


## [key name, glyph id] pairs of the current binding, longest names first; touch decides the glyph.
static func name_glyphs() -> Array[Array]:
	var touch := InputGlyphs.is_touch()
	var side_view := touch and TouchState.shared().side_view
	var result: Array[Array] = []
	var names: Dictionary = {}
	for action in ACTIONS:
		if not InputMap.has_action(action):
			continue
		for event in InputMap.action_get_events(action):
			if not (event is InputEventKey or event is InputEventMouseButton):
				continue
			var key_name := ControlsInfo.event_text(event)
			if key_name.is_empty() or names.has(key_name):
				continue
			var glyph := InputGlyphs.touch_id_for_action(action, side_view) if touch else InputGlyphs.id_for_event(event)
			if glyph == &"":
				continue
			if key_name.length() < MIN_NAME_LENGTH and not touch:
				continue
			names[key_name] = true
			result.append([key_name, glyph])
	if not touch:
		var mouse := Loc.t(&"KEY_MOUSE")
		if not names.has(mouse):
			result.append([mouse, InputGlyphs.MOUSE])
	result.sort_custom(func(a: Array, b: Array) -> bool: return String(a[0]).length() > String(b[0]).length())
	return result


static func _escape(text: String) -> String:
	var result := ""
	for character in text:
		if "\\^$.|?*+()[]{}".contains(character):
			result += "\\"
		result += character
	return result

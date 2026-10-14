class_name UiKit
extends RefCounted
## Shared UI look (docs/design/ui_spec.json, art/ui/theme.tres) plus small widget factories.
##
## All mockup measurements are virtual pixels of a 480×270 screen. UI_SCALE converts them to the game
## viewport: positions, sizes and font sizes go through px() / font_px(). Pixel art (nine-patch panels,
## icons, hearts, portraits) is upscaled with nearest filtering by the integer ART_SCALE so the 6 px
## borders stay crisp. Running the game at 480×270 later only means setting UI_SCALE to 1.0.
##
## The original API (label, button, panel, icon, ... with real pixel sizes) stays for existing callers;
## the spec-unit helpers (text, eyebrow, pixel_icon, ...) are the preferred way for new UI.

## Mockup resolution of docs/design.
const VIRTUAL_SIZE := Vector2(480, 270)
## Central UI scale: game viewport width / mockup width (1280 / 480 today).
const UI_SCALE := 1280.0 / 480.0
## Integer upscale for pixel art: UI_SCALE rounded, at least 1.
const ART_SCALE: int = maxi(1, roundi(UI_SCALE))
## Text shadow offset: 1 mockup pixel (#1c1a2b, bottom right), rounded down so small text stays crisp.
const SHADOW_OFFSET: int = maxi(1, floori(UI_SCALE))

const SOURCE_THEME_PATH := "res://art/ui/theme.tres"
const SLIDER_GRABBER_PATH := "res://art/ui/slider_grabber.png"
const FONT: FontFile = preload("res://art/fonts/PixelifySans-Variable.ttf")
const PANEL_TEXTURE: Texture2D = preload("res://art/ui/panel.png")
const PANEL_GOLD_TEXTURE: Texture2D = preload("res://art/ui/panel_gold.png")
const PANEL_DARK_TEXTURE: Texture2D = preload("res://art/ui/panel_dark.png")
const BUTTON_TEXTURE: Texture2D = preload("res://art/ui/button.png")
const BUTTON_HOVER_TEXTURE: Texture2D = preload("res://art/ui/button_hover.png")
## Disabled buttons (HANDOUT UI rules, SPRITES_V3): same nine-patch as button.png, text #7a7396.
const BUTTON_DISABLED_TEXTURE: Texture2D = preload("res://art/ui/button_disabled.png")
const GOLD_ICON: Texture2D = preload("res://art/ui/gold_icon.png")
const CRYSTAL_ICON: Texture2D = preload("res://art/ui/crystal_icon.png")
const SHIELD_ICON: Texture2D = preload("res://art/ui/shield_icon.png")
const LOCK_ICON: Texture2D = preload("res://art/ui/icon_lock.png")
const HEART_ICON: Texture2D = preload("res://art/ui/heart_full.png")
## Nine-patch border of panels and buttons in art pixels (ui_spec.json "nine_patch_margin").
const PANEL_BORDER := 6
const BUTTON_BORDER := 6

# --- Colours (ui_spec.json "colors", HANDOUT palette) ---
const COLOR_BG := Color("#15131f")
const COLOR_TEXT := Color("#e9e4d2")
const COLOR_TEXT_SOFT := Color("#d9d2e8")
const COLOR_MUTED := Color("#b9b3c9")
const COLOR_DISABLED := Color("#7a7396")
const COLOR_GOLD := Color("#f2cf4a")
const COLOR_DANGER := Color("#e0463a")
const COLOR_DANGER_SOFT := Color("#ff8a80")
const COLOR_SHIELD := Color("#6cb2ec")
const COLOR_SUCCESS := Color("#5fcd62")
const COLOR_EFFECT := Color("#ff8a3c")
const COLOR_WEAPON := Color("#a98cf5")
const COLOR_CRYSTAL := Color("#dcbcff")
const COLOR_SHADOW := Color("#1c1a2b")
const COLOR_LINE := Color("#3b3650")
const COLOR_EMPTY_SLOT := Color("#5d577a")
## Dialog overlay: the scene stays visible under it, only dimmed (07_ui.md, R8; UX2 had 0.78).
const COLOR_OVERLAY := Color(21.0 / 255.0, 19.0 / 255.0, 31.0 / 255.0, 0.62)
## Dialogs never take more than this share of the screen height (07_ui.md, R8).
const DIALOG_MAX_HEIGHT_RATIO := 0.6
## Weapon accent of the dialogs (HANDOUT category "Waffe").
const COLOR_MAGIC := Color("#a66ef0")
## Upgrade categories (UpgradeData.Category) -> eyebrow colour and German name.
const CATEGORY_COLORS := {0: COLOR_SHIELD, 1: COLOR_SUCCESS, 2: COLOR_EFFECT}
const CATEGORY_NAMES := {0: "Attribut", 1: "Mechanik", 2: "Effekt"}
## Translation keys of the category names (DungeonTexts, UX2).
const CATEGORY_KEYS := {0: &"CATEGORY_ATTRIBUTE", 1: &"CATEGORY_MECHANIC", 2: &"CATEGORY_EFFECT"}

## Kept for existing callers (main menu, village dialogs).
const TEXT_COLOR := COLOR_TEXT
const ACCENT_COLOR := COLOR_GOLD
const MUTED_COLOR := COLOR_MUTED

# --- Font sizes in mockup pixels (ui_spec.json "font.sizes") ---
const SIZE_TITLE_LARGE := 14
const SIZE_TITLE := 13
const SIZE_HEADING := 11
const SIZE_VALUE := 10
const SIZE_CARD_NAME := 9
const SIZE_KEY_HINT := 8
const SIZE_BODY := 7
const SIZE_EYEBROW := 6
## Eyebrows: capitals with 0.08 em letter spacing.
const EYEBROW_SPACING_EM := 0.08

static var _theme: Theme = null
static var _styles: Dictionary = {}
static var _upscaled: Dictionary = {}
static var _bold_font: FontVariation = null
static var _eyebrow_font: FontVariation = null


# --- Scale helpers ---

## Mockup pixels -> viewport pixels (layout: positions, sizes, gaps, paddings).
static func px(value: float) -> float:
	return roundf(value * UI_SCALE)


static func pxv(x: float, y: float) -> Vector2:
	return Vector2(px(x), px(y))


## Mockup font size -> viewport font size.
static func font_px(size: float) -> int:
	return maxi(1, roundi(size * UI_SCALE))


## On-screen size of pixel art drawn at spec_size mockup pixels, snapped to a whole multiple of the
## texture size so nearest filtering stays even (16 px icon at 16 -> 48, at 32 -> 80 today).
static func art_px(spec_size: float, texture_size := 0.0) -> float:
	var source := texture_size if texture_size > 0.0 else spec_size
	return source * maxi(1, roundi(spec_size * UI_SCALE / source))


# --- Theme ---

## Theme for every UI root: art/ui/theme.tres scaled by UI_SCALE / ART_SCALE, plus the few extras
## the design needs (progress bars, sliders, shadowed labels).
static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var theme := Theme.new()
	var source := load(SOURCE_THEME_PATH) as Theme
	if source != null:
		_copy_scaled(source, theme)
	theme.default_font = get_font()
	theme.default_font_size = font_px(8)
	theme.set_color("font_shadow_color", "Label", COLOR_SHADOW)
	theme.set_constant("shadow_offset_x", "Label", SHADOW_OFFSET)
	theme.set_constant("shadow_offset_y", "Label", SHADOW_OFFSET)
	theme.set_constant("outline_size", "Label", 0)
	theme.set_constant("outline_size", "Button", 0)
	theme.set_constant("h_separation", "Button", int(px(4)))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_hover_color", "Button", COLOR_GOLD)
	# Disabled buttons: button_disabled.png with muted text instead of the normal frame (UX2).
	theme.set_stylebox("disabled", "Button", panel_style(&"button_disabled"))
	theme.set_color("font_disabled_color", "Button", COLOR_DISABLED)
	theme.set_stylebox("background", "ProgressBar", bar_style(COLOR_BG))
	theme.set_stylebox("fill", "ProgressBar", bar_style(COLOR_GOLD))
	# Pixel sliders: square track with a 1-art-pixel frame and a pixel grabber (no smooth circle).
	theme.set_stylebox("slider", "HSlider", _pixel_bar(COLOR_BG, COLOR_LINE))
	theme.set_stylebox("grabber_area", "HSlider", _pixel_bar(COLOR_GOLD, COLOR_SHADOW))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _pixel_bar(COLOR_GOLD.lightened(0.2), COLOR_SHADOW))
	theme.set_icon("grabber", "HSlider", _slider_grabber(false))
	theme.set_icon("grabber_highlight", "HSlider", _slider_grabber(true))
	theme.set_icon("grabber_disabled", "HSlider", _slider_grabber(false))
	_theme = theme
	return theme


## Pixelify Sans (regular). Bold and eyebrow variants: bold_font(), eyebrow_font().
static func get_font() -> Font:
	return FONT


static func bold_font() -> FontVariation:
	if _bold_font == null:
		_bold_font = FontVariation.new()
		_bold_font.base_font = FONT
		_bold_font.variation_opentype = {_weight_tag(): 700}
	return _bold_font


static func eyebrow_font() -> FontVariation:
	if _eyebrow_font == null:
		_eyebrow_font = FontVariation.new()
		_eyebrow_font.base_font = FONT
		_eyebrow_font.variation_opentype = {_weight_tag(): 600}
		_eyebrow_font.spacing_glyph = maxi(1, roundi(EYEBROW_SPACING_EM * SIZE_EYEBROW * UI_SCALE))
	return _eyebrow_font


static func _weight_tag() -> int:
	return TextServerManager.get_primary_interface().name_to_tag("wght")


static func _copy_scaled(source: Theme, target: Theme) -> void:
	for type in source.get_type_list():
		var base := source.get_type_variation_base(type)
		if base != &"":
			target.set_type_variation(type, base)
		for name in source.get_color_list(type):
			target.set_color(name, type, source.get_color(name, type))
		for name in source.get_constant_list(type):
			target.set_constant(name, type, maxi(1, roundi(source.get_constant(name, type) * UI_SCALE)))
		for name in source.get_font_size_list(type):
			target.set_font_size(name, type, font_px(source.get_font_size(name, type)))
		for name in source.get_stylebox_list(type):
			target.set_stylebox(name, type, scale_stylebox(source.get_stylebox(name, type)))


## Copy of a 1× stylebox from theme.tres for the game viewport: texture upscaled by ART_SCALE,
## nine-patch margins in art pixels × ART_SCALE, content margins through px().
static func scale_stylebox(style: StyleBox) -> StyleBox:
	var copy := style.duplicate() as StyleBox
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		copy.set_content_margin(side, px(style.get_content_margin(side)))
	if copy is StyleBoxTexture:
		var textured := copy as StyleBoxTexture
		textured.texture = upscale(textured.texture)
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			textured.set_texture_margin(side, (style as StyleBoxTexture).get_texture_margin(side) * ART_SCALE)
	return copy


## Nine-patch panel style. kind: &"normal", &"gold", &"dark", &"button", &"button_hover",
## &"button_disabled".
static func panel_style(kind := &"normal") -> StyleBoxTexture:
	var key := StringName("panel_" + String(kind))
	if _styles.has(key):
		return _styles[key]
	var texture := PANEL_TEXTURE
	var content := Vector4(8, 8, 8, 8)
	match kind:
		&"gold":
			texture = PANEL_GOLD_TEXTURE
		&"dark":
			texture = PANEL_DARK_TEXTURE
			content = Vector4(6, 4, 6, 4)
		&"button":
			texture = BUTTON_TEXTURE
			content = Vector4(8, 4, 8, 4)
		&"button_hover":
			texture = BUTTON_HOVER_TEXTURE
			content = Vector4(8, 4, 8, 4)
		&"button_disabled":
			texture = BUTTON_DISABLED_TEXTURE
			content = Vector4(8, 4, 8, 4)
	var style := StyleBoxTexture.new()
	style.texture = upscale(texture)
	style.set_texture_margin_all(PANEL_BORDER * ART_SCALE)
	style.content_margin_left = px(content.x)
	style.content_margin_top = px(content.y)
	style.content_margin_right = px(content.z)
	style.content_margin_bottom = px(content.w)
	_styles[key] = style
	return style


## Panel style with custom content padding in mockup pixels (vertical, horizontal).
static func padded_style(kind: StringName, vertical: float, horizontal: float) -> StyleBoxTexture:
	var key := StringName("padded_%s_%s_%s" % [kind, vertical, horizontal])
	if _styles.has(key):
		return _styles[key]
	var style := panel_style(kind).duplicate() as StyleBoxTexture
	style.content_margin_left = px(horizontal)
	style.content_margin_right = px(horizontal)
	style.content_margin_top = px(vertical)
	style.content_margin_bottom = px(vertical)
	_styles[key] = style
	return style


## Slider track: 4 art pixels high, hard 1-art-pixel frame, no anti-aliasing.
static func _pixel_bar(color: Color, frame: Color) -> StyleBoxFlat:
	var style := bar_style(color, ART_SCALE * 4)
	style.anti_aliasing = false
	style.border_color = frame
	style.set_border_width_all(ART_SCALE)
	return style


## Slider grabber: art/ui/slider_grabber.png if it exists (SPRITES_V3 §7), else a 6×8 pixel knob.
static func _slider_grabber(highlight: bool) -> Texture2D:
	if not highlight and ResourceLoader.exists(SLIDER_GRABBER_PATH):
		return upscale(load(SLIDER_GRABBER_PATH) as Texture2D)
	var image := Image.create(6, 8, false, Image.FORMAT_RGBA8)
	var fill := COLOR_GOLD if highlight else COLOR_TEXT
	for y in 8:
		for x in 6:
			var edge := x == 0 or x == 5 or y == 0 or y == 7
			var color := COLOR_SHADOW if edge else fill
			if not edge and y == 1:
				color = Color.WHITE if not highlight else fill.lightened(0.4)
			elif not edge and y == 6:
				color = fill.darkened(0.3)
			image.set_pixel(x, y, color)
	return upscale(ImageTexture.create_from_image(image))


## Flat bar style (HP bars, cooldowns); height only matters for sliders.
static func bar_style(color: Color, height := 0.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	if height > 0.0:
		style.content_margin_top = height * 0.5
		style.content_margin_bottom = height * 0.5
	return style


static func upscale(texture: Texture2D, factor := ART_SCALE) -> Texture2D:
	if texture == null or factor <= 1:
		return texture
	var key := "%s:%d" % [texture.get_rid(), factor]
	if _upscaled.has(key):
		return _upscaled[key]
	var image := texture.get_image()
	image.resize(image.get_width() * factor, image.get_height() * factor, Image.INTERPOLATE_NEAREST)
	var result := ImageTexture.create_from_image(image)
	_upscaled[key] = result
	return result


# --- Original factories (sizes in viewport pixels) ---

static func label(text: String, font_size := 18, color := TEXT_COLOR) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


static func wrapped_label(text: String, width: float, font_size := 16, color := TEXT_COLOR) -> Label:
	var result := label(text, font_size, color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.custom_minimum_size = Vector2(width, 0)
	return result


static func icon(texture: Texture2D, size := 32.0) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.custom_minimum_size = Vector2(size, size)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func button(text: String, on_pressed: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.focus_mode = Control.FOCUS_NONE
	# Soft tick on hover, like moving through a menu with the arrow keys.
	result.mouse_entered.connect(func() -> void:
		if not result.disabled:
			Sfx.play_ui(result, &"ui_click", -12.0))
	result.pressed.connect(func() -> void: Sfx.play_ui(result, &"ui_click"))
	result.pressed.connect(on_pressed)
	# A click on a disabled button gets a short "not possible" sound (UX1).
	result.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if result.disabled and click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			UiSound.error(result))
	return result


## kind: &"normal", &"gold", &"dark" or &"none" (no frame, e.g. for card rows on the overlay).
static func panel(kind := &"normal") -> PanelContainer:
	var result := PanelContainer.new()
	if kind == &"none":
		result.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		result.add_theme_stylebox_override("panel", panel_style(kind))
	return result


static func vbox(separation := 8) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


static func hbox(separation := 8) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


# --- Spec factories (sizes in mockup pixels) ---

## Label with a mockup font size; bold uses Pixelify Sans at weight 700.
static func text_label(content: String, size := SIZE_BODY, color := COLOR_TEXT, bold := false) -> Label:
	var result := label(content, font_px(size), color)
	if bold:
		result.add_theme_font_override("font", bold_font())
	return result


## Wrapping label; width in mockup pixels.
static func wrapped_text(content: String, width: float, size := SIZE_BODY, color := COLOR_TEXT_SOFT) -> Label:
	var result := text_label(content, size, color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.custom_minimum_size = Vector2(px(width), 0)
	return result


static func title(content: String, size := SIZE_TITLE, color := COLOR_GOLD) -> Label:
	var result := text_label(content, size, color, true)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return result


## Category line above a name: 6 px capitals with letter spacing.
static func eyebrow(content: String, color := COLOR_MUTED) -> Label:
	var result := label(content.to_upper(), font_px(SIZE_EYEBROW), color)
	result.add_theme_font_override("font", eyebrow_font())
	return result


## Pixel-art icon at spec_size mockup pixels, snapped to whole texture multiples (see art_px).
static func pixel_icon(texture: Texture2D, spec_size := 16.0) -> TextureRect:
	var source := 0.0
	if texture != null:
		source = float(maxi(texture.get_width(), texture.get_height()))
	var rect := icon(texture, art_px(spec_size, source))
	# Keep the snapped size inside containers instead of stretching to the cell.
	rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rect


## Icon + value, e.g. gold or crystals in a badge.
static func icon_value(texture: Texture2D, value: String, color := COLOR_GOLD, size := SIZE_VALUE, icon_size := 12.0) -> HBoxContainer:
	var row := hbox(int(px(4)))
	row.add_child(pixel_icon(texture, icon_size))
	var value_label := text_label(value, size, color, true)
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value_label)
	return row


## "Label ......... value" row for dialogs (ui_spec dialog.rows).
static func value_row(caption: String, value: String, value_color := COLOR_TEXT, size := SIZE_KEY_HINT) -> HBoxContainer:
	var row := hbox(int(px(8)))
	var left := text_label(caption, size, COLOR_TEXT_SOFT)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var right := text_label(value, size, value_color, true)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(right)
	return row


## 1 px divider line (#3b3650).
static func separator() -> ColorRect:
	var line := ColorRect.new()
	line.color = COLOR_LINE
	line.custom_minimum_size = Vector2(0, maxf(1.0, px(1)))
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## Full-screen menu overlay rgba(21,19,31,0.78).
static func overlay() -> ColorRect:
	var dim := ColorRect.new()
	dim.color = COLOR_OVERLAY
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dim


## Button with a small second line under the label (dialog buttons: "Aussteigen" / "100 % Gold ins Dorf").
## is_default draws it with button_hover (the action Enter triggers).
static func dialog_button(content: String, sub: String, on_pressed: Callable, is_default := false) -> Button:
	var result := button(content, on_pressed)
	result.custom_minimum_size = Vector2(px(90), 0)
	result.add_theme_font_size_override("font_size", font_px(SIZE_KEY_HINT))
	result.add_theme_font_override("font", bold_font())
	var normal_kind := &"button_hover" if is_default else &"button"
	var sub_height := 0.0
	if not sub.is_empty():
		sub_height = px(SIZE_EYEBROW + 3)
	result.add_theme_stylebox_override("normal", _with_bottom(panel_style(normal_kind), sub_height))
	result.add_theme_stylebox_override("disabled", _with_bottom(panel_style(&"button_disabled"), sub_height))
	result.add_theme_color_override("font_disabled_color", COLOR_DISABLED)
	for state in ["hover", "pressed"]:
		result.add_theme_stylebox_override(state, _with_bottom(panel_style(&"button_hover"), sub_height))
	if not sub.is_empty():
		var sub_label := text_label(sub, SIZE_EYEBROW, COLOR_MUTED)
		sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		sub_label.offset_bottom = -px(5)
		sub_label.offset_top = sub_label.offset_bottom - font_px(SIZE_EYEBROW) - px(2)
		result.add_child(sub_label)
	return result


## Menu entry (pause menu): label left, small hint right ("50 % Gold · 73"). danger tints the label.
static func menu_button(content: String, hint: String, on_pressed: Callable, danger := false) -> Button:
	var result := button(content, on_pressed)
	result.alignment = HORIZONTAL_ALIGNMENT_LEFT
	result.add_theme_font_size_override("font_size", font_px(SIZE_CARD_NAME))
	result.add_theme_font_override("font", bold_font())
	result.custom_minimum_size = Vector2(0, px(22))
	result.add_theme_stylebox_override("normal", padded_style(&"button", 4, 8))
	result.add_theme_stylebox_override("hover", padded_style(&"button_hover", 4, 8))
	result.add_theme_stylebox_override("pressed", padded_style(&"button_hover", 4, 8))
	result.add_theme_stylebox_override("disabled", padded_style(&"button_disabled", 4, 8))
	if danger:
		result.add_theme_color_override("font_color", COLOR_DANGER_SOFT)
		result.add_theme_color_override("font_hover_color", COLOR_DANGER_SOFT.lightened(0.2))
	if not hint.is_empty():
		var hint_label := text_label(hint, SIZE_EYEBROW, COLOR_MUTED)
		hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hint_label.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		hint_label.offset_left = -px(70)
		hint_label.offset_right = -px(8)
		hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		result.add_child(hint_label)
	return result


## Interaction prompt look for world labels ("E Dungeon betreten"): panel, 8 px text, gold key.
## Hook for the player's PromptLabel (player.gd), see report.
static func apply_prompt_style(target: Label) -> void:
	target.add_theme_stylebox_override("normal", padded_style(&"normal", 3, 6))
	target.add_theme_font_override("font", get_font())
	target.add_theme_font_size_override("font_size", font_px(SIZE_KEY_HINT))
	target.add_theme_color_override("font_color", COLOR_TEXT)
	target.add_theme_color_override("font_shadow_color", COLOR_SHADOW)
	target.add_theme_constant_override("shadow_offset_x", SHADOW_OFFSET)
	target.add_theme_constant_override("shadow_offset_y", SHADOW_OFFSET)
	target.add_theme_constant_override("outline_size", 0)


## Effective weapon values as rows for comparisons (Waffenraum, Tab overview):
## [["Schaden", "14.4"], ["Rate", "1.73/s"], ["Reichweite", "75 px"], [extra caption, extra value]].
static func weapon_stat_rows(controller: WeaponController, weapon: WeaponData) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	rows.append(PackedStringArray([Loc.t(&"STAT_DAMAGE"), DamageNumber.format_amount(DamageProcessor.round_damage(controller.get_effective_damage(weapon)))]))
	rows.append(PackedStringArray([Loc.t(&"STAT_RATE"), "%.2f/s" % controller.get_effective_attack_rate(weapon)]))
	if weapon.attack_range > 0.0:
		rows.append(PackedStringArray([Loc.t(&"STAT_RANGE"), "%d px" % roundi(weapon.attack_range)]))
	match weapon.weapon_type:
		WeaponData.WeaponType.SWORD, WeaponData.WeaponType.DAGGER:
			rows.append(PackedStringArray([Loc.t(&"STAT_ANGLE"), "%d°" % roundi(controller.get_effective_swing_angle(weapon))]))
		WeaponData.WeaponType.STAFF, WeaponData.WeaponType.HAMMER:
			rows.append(PackedStringArray([Loc.t(&"STAT_AREA"), "%d px" % roundi(controller.get_effective_aoe_radius(weapon))]))
		WeaponData.WeaponType.BOW:
			rows.append(PackedStringArray([Loc.t(&"STAT_ARROW"), "%d px/s" % roundi(controller.get_effective_projectile_speed(weapon))]))
	return rows


# --- Accents and motion (R8: dialogs and HUD feel alive; optics only) ---

## Divider in an accent colour that fades out to both sides (dialog headers, R8).
static func accent_line(color: Color, height := 1.0) -> TextureRect:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	gradient.colors = PackedColorArray([Color(color, 0.0), color, color, Color(color, 0.0)])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 64
	var line := TextureRect.new()
	line.name = "AccentLine"
	line.texture = texture
	line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	line.stretch_mode = TextureRect.STRETCH_SCALE
	line.custom_minimum_size = Vector2(0, maxf(1.0, px(height)))
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## Tween that keeps running while the game is paused (dialogs) and ignores HitStop's time scale.
## The node must process while paused (Modal and the HUD layers do).
static func ui_tween(node: Node) -> Tween:
	return node.create_tween().set_ignore_time_scale(true)


## Fades control in and scales it from `from` to 1 around its centre with a small overshoot, after
## delay seconds. Containers keep the layout; only scale and alpha move.
static func pop_in(control: Control, delay := 0.0, from := 0.9, time := 0.24) -> Tween:
	control.modulate.a = 0.0
	control.scale = Vector2.ONE * from
	control.pivot_offset = control.size * 0.5
	var tween := ui_tween(control)
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_callback(func() -> void:
		if is_instance_valid(control):
			control.pivot_offset = control.size * 0.5)
	tween.set_parallel(true)
	tween.tween_property(control, "modulate:a", 1.0, time * 0.6)
	tween.tween_property(control, "scale", Vector2.ONE, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tween


## Short bump (value changed: gold, a heart): scale up to amount and back around the centre.
static func bump(control: Control, amount := 1.25, time := 0.2) -> void:
	if control == null or not control.is_inside_tree():
		return
	if control.has_meta(&"bump_tween"):
		var old := control.get_meta(&"bump_tween") as Tween
		if old != null and old.is_valid():
			old.kill()
	control.pivot_offset = control.size * 0.5
	var tween := ui_tween(control)
	tween.tween_property(control, "scale", Vector2.ONE * amount, time * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, time * 0.65).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	control.set_meta(&"bump_tween", tween)


## "Taken!" at a card (upgrade picked, offer bought): its icon grows and fades, a ring in color
## widens. Lives on its own layer above the dialogs, so it outlasts the dialog that closes now.
static func pick_burst(source: Control, texture: Texture2D, color: Color) -> void:
	if source == null or not source.is_inside_tree():
		return
	var rect := source.get_global_rect()
	var layer := CanvasLayer.new()
	layer.name = "PickBurst"
	layer.layer = 40
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	source.get_tree().root.add_child(layer)
	var center := rect.get_center()
	var ring := Panel.new()
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = color
	style.set_border_width_all(ART_SCALE)
	style.anti_aliasing = false
	ring.add_theme_stylebox_override("panel", style)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.size = rect.size
	ring.position = rect.position
	ring.pivot_offset = rect.size * 0.5
	layer.add_child(ring)
	var tween := ui_tween(layer)
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector2(1.12, 1.18), 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "modulate:a", 0.0, 0.32)
	if texture != null:
		var picture := icon(upscale(texture), art_px(32.0, maxf(texture.get_width(), texture.get_height())))
		picture.size = picture.custom_minimum_size
		picture.position = center - picture.size * 0.5
		picture.pivot_offset = picture.size * 0.5
		layer.add_child(picture)
		tween.tween_property(picture, "scale", Vector2.ONE * 2.2, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(picture, "modulate:a", 0.0, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(layer.queue_free)


static func category_color(category: int) -> Color:
	return CATEGORY_COLORS.get(category, COLOR_MUTED)


static func category_name(category: int) -> String:
	if CATEGORY_KEYS.has(category):
		return DungeonTexts.t(CATEGORY_KEYS[category])
	return CATEGORY_NAMES.get(category, "")


static func _with_bottom(style: StyleBoxTexture, extra: float) -> StyleBoxTexture:
	if extra <= 0.0:
		return style
	var copy := style.duplicate() as StyleBoxTexture
	copy.content_margin_bottom += extra
	return copy

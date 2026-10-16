class_name PlayerLook
extends RefCounted
## The account's look (D-152): one of four figures plus one palette index per colour slot (hair,
## outfit, skin, accent), all freely selectable. The dictionary is the API format of
## contracts/common.ts PlayerAppearance: {"character": "wick", "colors": {"hair": 0, "outfit": 0,
## "skin": 0, "accent": 0}} (indexes 0..7). It travels unchanged to the API (POST /auth/*, PATCH /me)
## and to the other machines of a room (NetPlayers).
##
## Colouring: the player art uses a fixed source palette per slot (SOURCE_RAMPS, the colours of
## art/characters/player/). Every sheet of a figure is recoloured once per look on the CPU (exact
## colour keys with a small tolerance) and cached, so all animations (also the side view) and every
## material (SpriteFx in game, the tint shader in menus) show the same colours; the old one-colour
## tint mask is not needed for it any more. Palette index 0 of every slot is the source colour itself.
## Figures without their own art yet (ember, moss, frost) are the base figure with a small
## silhouette mark drawn on the head (PLACEHOLDER_MARKS) until art/characters/<id>/<id>_frames.tres
## exists (CharacterData.art_frames_path); new art follows the same source palette (SPRITES_V10 §7).

const DEFAULT_CHARACTER := &"wick"
## Figures of contracts PlayerCharacter, in the order of the figure choice.
const CHARACTERS: Array[StringName] = [&"wick", &"ember", &"moss", &"frost"]
## Character ids of older builds (MM1 saves): "hero" is the figure now called wick.
const LEGACY_IDS := {&"hero": &"wick"}

const HAIR := &"hair"
const OUTFIT := &"outfit"
const SKIN := &"skin"
const ACCENT := &"accent"
const SLOTS: Array[StringName] = [HAIR, OUTFIT, SKIN, ACCENT]
## Choices per slot (contracts PLAYER_APPEARANCE_COLOR_MAX = 7, TESTWERT).
const COLOR_COUNT := 8

## TESTWERT: the palettes. Index 0 = the colour in the art. Outfit 0..5 are the clothing colours of
## MM1 (wardrobe), so old saves keep their colour.
const PALETTES := {
	&"hair": [Color("#c7542e"), Color("#3a2f3f"), Color("#6b4226"), Color("#e6c35c"),
			Color("#d8d8e0"), Color("#e8402a"), Color("#4a6fd0"), Color("#5fa84a")],
	&"outfit": [Color("#3690da"), Color("#e0463a"), Color("#5fcd62"), Color("#f2cf4a"),
			Color("#a66ef0"), Color("#2fb391"), Color("#d8d2c4"), Color("#3a3548")],
	&"skin": [Color("#f3c9a3"), Color("#ffe0c8"), Color("#e0a878"), Color("#b97a4e"),
			Color("#8d5634"), Color("#5e3a24"), Color("#a8c49a"), Color("#a9bde0")],
	&"accent": [Color("#3f3b58"), Color("#6b4a2e"), Color("#3b5a34"), Color("#6e2a2a"),
			Color("#2f4f6e"), Color("#8a8494"), Color("#c9b98f"), Color("#5a3d75")],
}
## Source colours of every slot in the art: [main tone, further tones of the ramp].
const SOURCE_RAMPS := {
	&"hair": [Color("#c7542e"), Color("#86351c")],
	&"outfit": [Color("#3690da"), Color("#2a6cb0"), Color("#6cb2ec")],
	&"skin": [Color("#f3c9a3"), Color("#d99c6c")],
	&"accent": [Color("#3f3b58"), Color("#2f2b45")],
}
const OUTLINE := Color("#1c1a2b")
## A pixel counts as a source colour if every channel is at most this far off (8-bit).
const KEY_TOLERANCE := 3
## Highlights (brighter than the main tone) blend this much towards white per step of brightness.
const HIGHLIGHT_BLEND := 0.8

## TESTWERT: start colours of every figure (switching the figure in the editor takes them).
const CHARACTER_DEFAULTS := {
	&"wick": {"hair": 0, "outfit": 0, "skin": 0, "accent": 0},
	&"ember": {"hair": 5, "outfit": 1, "skin": 2, "accent": 1},
	&"moss": {"hair": 2, "outfit": 2, "skin": 3, "accent": 6},
	&"frost": {"hair": 4, "outfit": 6, "skin": 1, "accent": 4},
}

## Placeholder marks until the figure's own art exists: rows from top to bottom, the last row sits on
## the first hair row of the head, centred on the head. o outline, h/H hair, c/C/l outfit, a/A
## accent, w/g/f/y fixed colours (white, grey, flame, gold), "." keeps the pixel.
const PLACEHOLDER_MARKS := {
	# Ember: three flame spikes of hair.
	&"ember": [
		"...o...o...",
		"..oho.ofo.o",
		".ohhhohfhoh",
		"ohhhhhhhhho",
		"ohhHhhhHhho",
	],
	# Moss: a pointed hat in the outfit colour, the tip bends back.
	&"moss": [
		"o...........",
		"oco.........",
		".occo.......",
		".occco......",
		"..occcoo....",
		"..occcccoo..",
		"oCCCCCCCCCCo",
	],
	# Frost: a beanie in the accent colour with a white pompom.
	&"frost": [
		"....ooo....",
		"...owwwo...",
		"...owgwo...",
		"..ooaaaoo..",
		".oaaaaaaao.",
		"oAAAAAAAAAo",
	],
}
const MARK_COLORS := {
	"o": Color("#1c1a2b"), "h": Color("#c7542e"), "H": Color("#86351c"),
	"c": Color("#3690da"), "C": Color("#2a6cb0"), "l": Color("#6cb2ec"),
	"a": Color("#3f3b58"), "A": Color("#2f2b45"),
	"w": Color("#e9e4d2"), "g": Color("#b9b3c9"), "f": Color("#ff8a3c"), "y": Color("#f2cf4a"),
}
## Frame size of character sheets (art px).
const FRAME := 32
## TESTWERT: baked looks kept in memory (lobby with 4 players, editor preview, menu figure).
const MAX_CACHED_LOOKS := 24

## look key -> SpriteFrames (all animations).
static var _frames_cache: Dictionary = {}
## "<sheet>|<look key>" -> Texture2D.
static var _sheet_cache: Dictionary = {}
## Base SpriteFrames whose side-view animations were added (PlayerSideArt).
static var _prepared_bases: Dictionary = {}
## rgb int -> [slot, ramp index] of the source palette (with tolerance).
static var _source_lookup: Dictionary = {}


# --- The look dictionary ---

## Look of a new profile: wick (or character) in its start colours.
static func default_look(character: StringName = DEFAULT_CHARACTER) -> Dictionary:
	var id := character_id(character)
	return {"character": String(id), "colors": default_colors(id)}


static func default_colors(character: StringName) -> Dictionary:
	var colors: Dictionary = CHARACTER_DEFAULTS.get(character_id(character), CHARACTER_DEFAULTS[DEFAULT_CHARACTER])
	return colors.duplicate()


## A known figure id for any value: legacy ids are mapped, unknown ones become the default.
static func character_id(value: Variant) -> StringName:
	var id := StringName(str(value)) if value != null else &""
	id = LEGACY_IDS.get(id, id)
	return id if CHARACTERS.has(id) else DEFAULT_CHARACTER


## Any value as a valid look (API, network, file): missing or broken parts take the figure's start
## colours, indexes are clamped to 0..7, JSON floats become ints. Never fails.
static func normalize(value: Variant) -> Dictionary:
	var source: Dictionary = value if value is Dictionary else {}
	var character := character_id(source.get("character", DEFAULT_CHARACTER))
	var defaults := default_colors(character)
	var given: Variant = source.get("colors", {})
	var colors_in: Dictionary = given if given is Dictionary else {}
	var colors := {}
	for slot in SLOTS:
		var index: Variant = colors_in.get(String(slot), null)
		if typeof(index) == TYPE_INT or typeof(index) == TYPE_FLOAT:
			colors[String(slot)] = clampi(int(index), 0, COLOR_COUNT - 1)
		else:
			colors[String(slot)] = int(defaults[String(slot)])
	return {"character": String(character), "colors": colors}


## True if value is a dictionary that already is a valid look (no repair needed).
static func is_valid(value: Variant) -> bool:
	return value is Dictionary and value.has("character") and value.has("colors") and normalize(value) == value


static func equals(a: Variant, b: Variant) -> bool:
	return normalize(a) == normalize(b)


## "wick|0|0|0|0", the cache key.
static func key_of(look: Dictionary) -> String:
	var normalized := normalize(look)
	var colors: Dictionary = normalized.colors
	return "%s|%d|%d|%d|%d" % [normalized.character, colors.hair, colors.outfit, colors.skin, colors.accent]


static func get_character(look: Dictionary) -> StringName:
	return StringName(normalize(look).character)


static func get_index(look: Dictionary, slot: StringName) -> int:
	return int(normalize(look).colors.get(String(slot), 0))


## Copy of look with one colour changed.
static func with_color(look: Dictionary, slot: StringName, index: int) -> Dictionary:
	var result := normalize(look)
	if SLOTS.has(slot):
		result.colors[String(slot)] = clampi(index, 0, COLOR_COUNT - 1)
	return result


## Copy of look with another figure in that figure's start colours (the editor's figure choice).
static func with_character(_look: Dictionary, character: StringName) -> Dictionary:
	return default_look(character)


static func color_of(slot: StringName, index: int) -> Color:
	var palette: Array = PALETTES.get(slot, [])
	return palette[clampi(index, 0, palette.size() - 1)] if not palette.is_empty() else Color.WHITE


## Translation key of a palette colour ("LOOK_HAIR_0" -> "Rotbraun").
static func color_name_key(slot: StringName, index: int) -> StringName:
	return StringName("LOOK_%s_%d" % [String(slot).to_upper(), clampi(index, 0, COLOR_COUNT - 1)])


## Translation key of a slot's caption ("LOOK_SLOT_HAIR" -> "Haare").
static func slot_name_key(slot: StringName) -> StringName:
	return StringName("LOOK_SLOT_%s" % String(slot).to_upper())


## Outfit colour of a look (old one-colour code: name tags, the MM1 "color").
static func outfit_color(look: Dictionary) -> Color:
	return color_of(OUTFIT, get_index(look, OUTFIT))


## Nearest palette index of colour in slot.
static func nearest_index(slot: StringName, color: Color) -> int:
	var palette: Array = PALETTES.get(slot, [])
	var best := 0
	var best_distance := INF
	for i in palette.size():
		var c: Color = palette[i]
		var distance := Vector3(c.r - color.r, c.g - color.g, c.b - color.b).length_squared()
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


## The look of an MM1 save profile: character id ("hero") and clothing colour (alpha 0 = default).
static func from_legacy(character: Variant, color: Color) -> Dictionary:
	var look := default_look(character_id(character))
	if color.a > 0.0:
		look.colors["outfit"] = nearest_index(OUTFIT, color)
	return look


## Player.appearance in either form: the look of D-152 or the MM1 pair {character, color}.
static func from_appearance(appearance: Dictionary) -> Dictionary:
	if appearance.has("colors"):
		return normalize(appearance)
	var color: Variant = appearance.get("color", Color(0, 0, 0, 0))
	return from_legacy(appearance.get("character", DEFAULT_CHARACTER), color if color is Color else Color(0, 0, 0, 0))


# --- Recolouring ---

## Gives sprite the look's figure in its colours (all animations, keeps the current animation).
static func apply(sprite: AnimatedSprite2D, look: Dictionary) -> void:
	var normalized := normalize(look)
	var data := CharacterCatalog.get_character(StringName(normalized.character))
	if data != null:
		data.apply_look(sprite, normalized)


## The figure's frames recoloured for look, cached. Falls back to the plain frames when the art
## cannot be read (then the outfit tint of the shader still colours the clothes).
static func frames_for(data: CharacterData, look: Dictionary) -> SpriteFrames:
	if data == null:
		return null
	var base := data.get_frames()
	if base == null:
		return null
	_prepare_base(base, data)
	var normalized := normalize(look)
	var key := "%s|%s|%s" % [data.id, key_of(normalized), base.get_instance_id()]
	var cached: SpriteFrames = _frames_cache.get(key, null)
	if cached != null:
		return cached
	if _frames_cache.size() >= MAX_CACHED_LOOKS:
		clear_cache()
	var frames := SpriteFrames.new()
	if not base.has_animation(&"default"):
		frames.remove_animation(&"default")
	var mark := data.get_placeholder_mark()
	for animation in base.get_animation_names():
		if not frames.has_animation(animation):
			frames.add_animation(animation)
		frames.set_animation_speed(animation, base.get_animation_speed(animation))
		frames.set_animation_loop(animation, base.get_animation_loop(animation))
		for i in base.get_frame_count(animation):
			var texture := _bake_texture(base.get_frame_texture(animation, i), normalized, mark)
			frames.add_frame(animation, texture, base.get_frame_duration(animation, i))
	_frames_cache[key] = frames
	return frames


static func clear_cache() -> void:
	_frames_cache.clear()
	_sheet_cache.clear()


## The side-view animations (PlayerSideArt) live in the base frames, so every baked look has them.
static func _prepare_base(base: SpriteFrames, data: CharacterData) -> void:
	if _prepared_bases.has(base.get_instance_id()):
		return
	_prepared_bases[base.get_instance_id()] = true
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = base
	sprite.set_meta(CharacterData.META_DATA, data)
	PlayerSideArt.ensure(sprite)
	sprite.free()


static func _bake_texture(texture: Texture2D, look: Dictionary, mark: StringName) -> Texture2D:
	var atlas := texture as AtlasTexture
	if atlas != null and atlas.atlas != null:
		var sheet := _bake_sheet(atlas.atlas, look, mark)
		if sheet == atlas.atlas:
			return texture
		var baked := AtlasTexture.new()
		baked.atlas = sheet
		baked.region = atlas.region
		baked.margin = atlas.margin
		baked.filter_clip = atlas.filter_clip
		return baked
	return _bake_sheet(texture, look, mark) if texture != null else texture


static func _bake_sheet(sheet: Texture2D, look: Dictionary, mark: StringName) -> Texture2D:
	var key := "%d|%s|%s" % [sheet.get_instance_id(), key_of(look), mark]
	var cached: Texture2D = _sheet_cache.get(key, null)
	if cached != null:
		return cached
	var colors: Dictionary = look.colors
	var plain := mark == &""
	for slot in SLOTS:
		plain = plain and int(colors[String(slot)]) == 0
	if plain:
		return sheet
	var image := sheet.get_image()
	if image == null or image.is_empty():
		return sheet
	image = image.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	if mark != &"":
		add_placeholder_mark(image, mark)
	recolor(image, look)
	var texture := ImageTexture.create_from_image(image)
	_sheet_cache[key] = texture
	return texture


## Replaces the source colours of image (RGBA8) with the look's palette, keeping light and shade.
static func recolor(image: Image, look: Dictionary) -> void:
	var mapping := _mapping_for(normalize(look))
	if mapping.is_empty():
		return
	var bytes := image.get_data()
	var count := bytes.size()
	var i := 0
	while i < count:
		if bytes[i + 3] != 0:
			var target: Variant = mapping.get((bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2], null)
			if target != null:
				var rgb: PackedByteArray = target
				bytes[i] = rgb[0]
				bytes[i + 1] = rgb[1]
				bytes[i + 2] = rgb[2]
		i += 4
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, bytes)


## rgb int -> target rgb bytes for every slot whose colour is not the source colour.
static func _mapping_for(look: Dictionary) -> Dictionary:
	var lookup := _get_source_lookup()
	var targets := {}
	for slot in SLOTS:
		var index := int(look.colors[String(slot)])
		if index == 0:
			continue
		var ramp: Array = SOURCE_RAMPS[slot]
		var main := color_of(slot, index)
		var main_luma := _luma(ramp[0])
		var shades: Array[PackedByteArray] = []
		for tone: Color in ramp:
			shades.append(_bytes(shade(main, _luma(tone) / maxf(main_luma, 0.001))))
		targets[slot] = shades
	var mapping := {}
	if targets.is_empty():
		return mapping
	for rgb: int in lookup:
		var hit: Array = lookup[rgb]
		var shades: Variant = targets.get(hit[0], null)
		if shades != null:
			mapping[rgb] = (shades as Array)[hit[1]]
	return mapping


## main scaled by a brightness ratio: darker tones multiply, brighter ones blend towards white.
static func shade(main: Color, ratio: float) -> Color:
	if ratio <= 1.0:
		return Color(main.r * ratio, main.g * ratio, main.b * ratio, 1.0)
	return main.lerp(Color.WHITE, clampf((ratio - 1.0) * HIGHLIGHT_BLEND, 0.0, 1.0))


## Source colour of a pixel: [slot, ramp index] or [] (outline, boots, belt …).
static func source_of(color: Color) -> Array:
	var rgb := (color.r8 << 16) | (color.g8 << 8) | color.b8
	return _get_source_lookup().get(rgb, [])


static func _get_source_lookup() -> Dictionary:
	if not _source_lookup.is_empty():
		return _source_lookup
	for slot in SLOTS:
		var ramp: Array = SOURCE_RAMPS[slot]
		for tone_index in ramp.size():
			var tone: Color = ramp[tone_index]
			for dr in range(-KEY_TOLERANCE, KEY_TOLERANCE + 1):
				for dg in range(-KEY_TOLERANCE, KEY_TOLERANCE + 1):
					for db in range(-KEY_TOLERANCE, KEY_TOLERANCE + 1):
						var r := tone.r8 + dr
						var g := tone.g8 + dg
						var b := tone.b8 + db
						if r < 0 or g < 0 or b < 0 or r > 255 or g > 255 or b > 255:
							continue
						var rgb := (r << 16) | (g << 8) | b
						if not _source_lookup.has(rgb):
							_source_lookup[rgb] = [slot, tone_index]
	return _source_lookup


## Draws the figure's placeholder mark on every upright 32×32 frame of image (lying frames of the
## death or fall animation are left alone).
static func add_placeholder_mark(image: Image, mark: StringName) -> void:
	var rows: Array = PLACEHOLDER_MARKS.get(mark, [])
	if rows.is_empty() or image.get_height() < FRAME:
		return
	for tile in floori(float(image.get_width()) / FRAME):
		var anchor := _head_anchor(image, Rect2i(tile * FRAME, 0, FRAME, FRAME))
		if anchor.x < 0:
			continue
		var width: int = (rows[0] as String).length()
		for row_index in rows.size():
			var row: String = rows[row_index]
			var y := anchor.y - (rows.size() - 1 - row_index)
			for column in row.length():
				var code := row[column]
				if code == "." or not MARK_COLORS.has(code):
					continue
				var x := anchor.x - floori(width / 2.0) + column
				if x < tile * FRAME or x >= (tile + 1) * FRAME or y < 0 or y >= FRAME:
					continue
				image.set_pixel(x, y, MARK_COLORS[code])


## Top centre of the head in a frame: (x, first hair row), (-1, -1) without hair or for a lying figure.
static func _head_anchor(image: Image, rect: Rect2i) -> Vector2i:
	var top := -1
	var min_x := rect.end.x
	var max_x := rect.position.x - 1
	var min_y := rect.end.y
	var max_y := -1
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var color := image.get_pixel(x, y)
			if color.a < 0.5:
				continue
			var hit := source_of(color)
			if hit.is_empty() or (hit[0] != HAIR and hit[0] != SKIN):
				continue
			if hit[0] == HAIR and top < 0:
				top = y
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
			min_y = mini(min_y, y)
			max_y = maxi(max_y, y)
	if top < 0:
		return Vector2i(-1, -1)
	# Head and hands: a figure lying on its side is much wider than high.
	if (max_x - min_x) > (max_y - min_y) * 1.3:
		return Vector2i(-1, -1)
	var sum := 0
	var count := 0
	for y in range(top, mini(top + 7, rect.end.y)):
		for x in range(rect.position.x, rect.end.x):
			var hit := source_of(image.get_pixel(x, y))
			if not hit.is_empty() and (hit[0] == HAIR or hit[0] == SKIN):
				sum += x
				count += 1
	return Vector2i(roundi(float(sum) / maxi(1, count)), top)


static func _luma(color: Color) -> float:
	return color.r * 0.299 + color.g * 0.587 + color.b * 0.114


static func _bytes(color: Color) -> PackedByteArray:
	return PackedByteArray([color.r8, color.g8, color.b8])

class_name DoorArt
extends RefCounted
## Door textures (ROADMAP_AUSBAU D1). Delivered files from art/environment/doors/ (names in
## docs/SPRITES_V4.md §4, built by DoorStyle) win automatically; while a file is missing, a
## placeholder is painted here pixel by pixel in the HANDOUT palette. Everything is cached.
## Visual only: randomness here is a fixed hash, so every door of a style looks the same.

## Colour of the dark passage inside delivered frames (art/environment/doors/doors.json).
const PASSAGE_COLOR := Color("#0b0a12")
const OUTLINE := Color("1c1a2b")
const VOID_TOP := Color("0c0a13")
const VOID_MID := Color("15131f")
const VOID_FLOOR := Color("221e30")
const BONE := Color("e9e4d2")
const BONE_DARK := Color("b8b09a")
const WOOD_LIGHT := Color("a8703f")
const WOOD_MID := Color("8a5a34")
const WOOD_DARK := Color("5c3a24")
const METAL_LIGHT := Color("c6ccd6")
const METAL_MID := Color("8c8f9a")
const METAL_DARK := Color("5a5f6a")
const GOLD := Color("e0b84a")
const GOLD_DARK := Color("c99a2e")
const PLAQUE_FILL := Color("2a2638")
const PLAQUE_RIM := Color("8f88ad")
const LEAF_FRAMES := 4
## Placeholder sign behind the UI icon: 20x20 art px.
const PLAQUE_SIZE := Vector2i(20, 20)
const SYMBOL_SIZE := Vector2i(16, 16)
## UI icons shown on the placeholder sign until door_special_symbols.png exists.
const SYMBOL_ICONS := {
	&"shop": "res://art/ui/gold_icon.png",
	&"weapon": "res://art/ui/icon_sword.png",
	&"fountain": "res://art/ui/heart_full.png",
	&"upgrade": "res://art/ui/upgrade_magic_power.png",
	&"trial": "res://art/ui/clock_icon.png",
	&"miniboss": "res://art/ui/skull_icon.png",
}
## The campfire sign shows the flame of the first torch frame.
const CAMPFIRE_ICON := "res://art/environment/props/torch_4f.png"
const CAMPFIRE_REGION := Rect2i(8, 4, 16, 16)
## Delivered frames: pixels at least this saturated and bright glow (runes, embers) when their hue
## is close to the style's glow colour (so moss and gold trim stay dark).
const GLOW_MIN_SATURATION := 0.45
const GLOW_MIN_VALUE := 0.55
const GLOW_HUE_TOLERANCE := 0.08

## Folder the delivered art is looked up in. Tests point it at a temporary folder.
static var art_dir := DoorStyle.ART_DIR
static var _cache: Dictionary = {}


static func clear_cache() -> void:
	_cache.clear()


## True when the delivered file for this style's frame exists.
static func has_frame_file(style: DoorStyle) -> bool:
	return _file_exists(_art_path(style.get_frame_path()))


static func has_leaf_file(style: DoorStyle) -> bool:
	return _file_exists(_art_path(style.get_leaf_path()))


static func has_symbol_file(symbol_id: StringName) -> bool:
	var sheet := _load_file(_art_path(DoorStyle.get_symbols_path()))
	var index := DoorStyle.symbol_index(symbol_id)
	return sheet != null and index >= 0 and sheet.get_width() >= (index + 1) * SYMBOL_SIZE.x


## Frame texture (48x48, boss 64x56): delivered file or placeholder.
static func get_frame(style: DoorStyle) -> Texture2D:
	var key := "frame_%s" % style.get_key()
	if not _cache.has(key):
		var file := _load_file(_art_path(style.get_frame_path()))
		_cache[key] = ImageTexture.create_from_image(open_passage(file.get_image())) if file != null \
				else ImageTexture.create_from_image(paint_frame(style))
	return _cache[key]


## The delivered frames paint their passage in PASSAGE_COLOR; flood-filling it from the bottom
## centre makes it transparent, so the corridor shows through the arch (the leaf closes it).
static func open_passage(image: Image) -> Image:
	if image == null:
		return image
	image.convert(Image.FORMAT_RGBA8)
	var start := Vector2i(image.get_width() / 2, image.get_height() - 1)
	if not _is_passage(image.get_pixelv(start)):
		return image
	var stack: Array[Vector2i] = [start]
	var bounds := Rect2i(Vector2i.ZERO, image.get_size())
	while not stack.is_empty():
		var point: Vector2i = stack.pop_back()
		if not bounds.has_point(point) or not _is_passage(image.get_pixelv(point)):
			continue
		image.set_pixelv(point, Color(0, 0, 0, 0))
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			stack.append(point + step)
	return image


static func _is_passage(color: Color) -> bool:
	return color.a > 0.5 and absf(color.r - PASSAGE_COLOR.r) + absf(color.g - PASSAGE_COLOR.g) \
			+ absf(color.b - PASSAGE_COLOR.b) < 0.03


## Leaf strip, four frames of 32x32 (frame 1 closed, frame 4 open).
static func get_leaf_strip(style: DoorStyle) -> Texture2D:
	var key := "leaf_%s" % style.get_key()
	if not _cache.has(key):
		var file := _load_file(_art_path(style.get_leaf_path()))
		_cache[key] = file if file != null else ImageTexture.create_from_image(paint_leaf_strip(style))
	return _cache[key]


## Additive glow overlay in frame size; null when the style does not glow or nothing glows.
static func get_glow(style: DoorStyle) -> Texture2D:
	if style.glow_mode == DoorStyle.GLOW_NONE:
		return null
	var key := "glow_%s" % style.get_key()
	if not _cache.has(key):
		var image: Image
		if has_frame_file(style):
			image = glow_from_frame(get_frame(style).get_image(), style)
		else:
			image = paint_glow(style)
		_cache[key] = ImageTexture.create_from_image(image) if image != null and not image.is_invisible() else null
	return _cache[key]


## Sign over a door to a special room: a column of door_special_symbols.png, else a placeholder
## sign with the matching UI icon. null for no symbol.
static func get_symbol(symbol_id: StringName) -> Texture2D:
	if DoorStyle.symbol_index(symbol_id) < 0:
		return null
	var key := "symbol_%s" % symbol_id
	if not _cache.has(key):
		if has_symbol_file(symbol_id):
			var atlas := AtlasTexture.new()
			atlas.atlas = _load_file(_art_path(DoorStyle.get_symbols_path()))
			atlas.region = Rect2(DoorStyle.symbol_index(symbol_id) * SYMBOL_SIZE.x, 0, SYMBOL_SIZE.x, SYMBOL_SIZE.y)
			_cache[key] = atlas
		else:
			_cache[key] = ImageTexture.create_from_image(paint_symbol(symbol_id))
	return _cache[key]


# --- Files ---

static func _art_path(default_path: String) -> String:
	return art_dir + default_path.get_file()


static func _file_exists(path: String) -> bool:
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)


## Imported texture, or a raw PNG read from disk (freshly dropped, not yet imported art).
static func _load_file(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty():
			return ImageTexture.create_from_image(image)
	return null


# --- Pixel helpers ---

static func _new_image(size: Vector2i) -> Image:
	return Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)


static func _put(image: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
		image.set_pixel(x, y, color)


static func _blend(image: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
		image.set_pixel(x, y, image.get_pixel(x, y).blend(color))


static func _fill(image: Image, rect: Rect2i, color: Color) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_put(image, x, y, color)


static func _opaque(image: Image, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return false
	return image.get_pixel(x, y).a > 0.5


## 1 px contour #1c1a2b around every opaque area (also on the inside of the opening).
static func _outline(image: Image) -> void:
	var edge: Array[Vector2i] = []
	for y in image.get_height():
		for x in image.get_width():
			if _opaque(image, x, y):
				continue
			if _opaque(image, x - 1, y) or _opaque(image, x + 1, y) or _opaque(image, x, y - 1) or _opaque(image, x, y + 1):
				edge.append(Vector2i(x, y))
	for p in edge:
		image.set_pixel(p.x, p.y, OUTLINE)


## Stable pseudo-random 0..1 per pixel (same look for every door of a style).
static func _hash(x: int, y: int, salt: int) -> float:
	var v := sin(float(x) * 12.9898 + float(y) * 78.233 + float(salt) * 37.719) * 43758.5453
	return v - floorf(v)


static func _shade(base: Color, amount: float) -> Color:
	return base.lightened(amount) if amount >= 0.0 else base.darkened(-amount)


# --- Frame shapes ---

## Masks of one frame: "body" (stone/iron), "inner" (opening incl. leaf area).
static func _frame_masks(style: DoorStyle) -> Dictionary:
	var size := style.frame_size
	var body := {}
	var inner := {}
	var leaf_rect := Rect2i(style.leaf_offset, style.leaf_size)
	var cx := float(size.x - 1) * 0.5
	if style.is_boss():
		for y in size.y:
			for x in size.x:
				var p := Vector2i(x, y)
				var in_open := (y >= 32 and x >= 17 and x <= 46) or Vector2(x, y).distance_to(Vector2(cx, 32)) <= 14.5
				var in_arch := (y >= 30 and x >= 10 and x <= 53) or (Vector2(x, y).distance_to(Vector2(cx, 30)) <= 24.0 and y >= 6)
				var pillar := (x >= 2 and x <= 13 or x >= 50 and x <= 61) and y >= 10
				var capital := (x >= 1 and x <= 14 or x >= 49 and x <= 62) and (y >= 8 and y <= 12 or y >= 51)
				if in_open:
					inner[p] = true
				elif in_arch or pillar or capital:
					body[p] = true
	elif style.biome_id == &"ember_forge":
		# Heavy iron frame: square lintel with chamfered corners.
		for y in size.y:
			for x in size.x:
				var p := Vector2i(x, y)
				var in_open := x >= 9 and x <= 38 and y >= 13
				var chamfer := mini(x - 3, 44 - x) + (y - 6) < 3
				var in_outer := x >= 3 and x <= 44 and y >= 6 and not chamfer
				var base := y >= 43 and x >= 1 and x <= 46
				if in_open:
					inner[p] = true
				elif in_outer or base:
					body[p] = true
	else:
		var rough := style.biome_id == &"slime_grotto"
		for y in size.y:
			for x in size.x:
				var p := Vector2i(x, y)
				var bump := 0.0
				if rough:
					bump = (_hash(x / 3, y / 3, 5) - 0.5) * 3.0
				var in_open := (y >= 28 and x >= 9 and x <= 38) or Vector2(x, y).distance_to(Vector2(cx, 28)) <= 14.5
				var half := 20.5 + (bump if rough else 0.0)
				var in_outer := (y >= 24 and absf(x - cx) <= half) or Vector2(x, y).distance_to(Vector2(cx, 24)) <= 20.5 + bump
				var plinth := y >= 43 and x >= 2 and x <= 45
				if in_open:
					inner[p] = true
				elif in_outer or plinth:
					body[p] = true
	return {"body": body, "inner": inner, "leaf": leaf_rect}


## Opening pixels next to the frame body (the inner contour).
static func _opening_edge(inner: Dictionary, body: Dictionary) -> Array[Vector2i]:
	var edge: Array[Vector2i] = []
	for p: Vector2i in inner:
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
			if body.has(p + d):
				edge.append(p)
				break
	return edge


## Leaf pixels that lie in the free opening of the placeholder frame (true = visible).
static func _leaf_mask(style: DoorStyle) -> Dictionary:
	var masks := _frame_masks(style)
	var inner: Dictionary = masks["inner"]
	var visible := inner.duplicate()
	for p: Vector2i in _opening_edge(inner, masks["body"]):
		visible.erase(p)
	return visible


static func paint_frame(style: DoorStyle) -> Image:
	var image := _new_image(style.frame_size)
	var masks := _frame_masks(style)
	var body: Dictionary = masks["body"]
	var inner: Dictionary = masks["inner"]
	# Transparent passage like the opened delivered frames: the corridor shows through, the leaf
	# closes it.
	for p: Vector2i in inner:
		image.set_pixelv(p, Color(0, 0, 0, 0))
	if style.is_boss():
		_paint_boss_body(image, style, body)
	else:
		match style.biome_id:
			&"slime_grotto":
				_paint_rock_body(image, style, body)
			&"shadow_realm":
				_paint_obsidian_body(image, style, body)
			&"ember_forge":
				_paint_iron_body(image, style, body)
			_:
				_paint_brick_body(image, style, body)
	_outline(image)
	# Contour on the inside of the opening.
	for p: Vector2i in _opening_edge(inner, body):
		image.set_pixelv(p, OUTLINE)
	match style.biome_id if not style.is_boss() else &"boss":
		&"crypt":
			_paint_crypt_details(image, style)
		&"slime_grotto":
			_paint_slime_details(image, style)
		&"shadow_realm":
			_paint_runes(image, style, false)
		&"ember_forge":
			_paint_ember_details(image, style)
		&"boss":
			_paint_boss_details(image, style)
	return image


## Crypt: arch of voussoirs with a keystone, brick posts, light from the top left.
static func _paint_brick_body(image: Image, style: DoorStyle, body: Dictionary) -> void:
	var cx := float(style.frame_size.x - 1) * 0.5
	for p: Vector2i in body:
		var c := style.stone_mid
		if p.y < 24:
			var angle := atan2(float(p.y) - 24.0, float(p.x) - cx)
			var segment := floori((angle + PI) / (PI / 7.0))
			var edge := fposmod(angle + PI, PI / 7.0) < 0.07
			c = style.stone_light if segment % 2 == 0 else style.stone_mid
			if segment == 3:
				c = style.stone_light.lightened(0.1)
			if edge and segment != 3 and segment != 4:
				c = style.stone_dark
		elif p.y >= 43:
			c = style.stone_mid if p.y > 43 else style.stone_light
		else:
			var row := (p.y - 24) / 5
			var local_x := p.x - (3 if p.x < 24 else 39)
			c = style.stone_mid if row % 2 == 0 else _shade(style.stone_mid, 0.06)
			if (p.y - 24) % 5 == 4 or local_x == (2 if row % 2 == 0 else 4):
				c = style.stone_dark
		# Light from the top left: left edges brighter, right edges darker.
		if not body.has(p + Vector2i.LEFT):
			c = c.lightened(0.15)
		elif not body.has(p + Vector2i.RIGHT):
			c = c.darkened(0.2)
		image.set_pixelv(p, c)


## Slime grotto: lumpy greenish rock in blotches.
static func _paint_rock_body(image: Image, style: DoorStyle, body: Dictionary) -> void:
	for p: Vector2i in body:
		var n := _hash(p.x / 3, p.y / 3, 11)
		var c := style.stone_mid
		if n > 0.72:
			c = style.stone_light
		elif n < 0.25:
			c = style.stone_dark
		if _hash(p.x, p.y, 3) > 0.93:
			c = style.stone_dark
		if not body.has(p + Vector2i.UP):
			c = c.lightened(0.12)
		image.set_pixelv(p, c)


## Shadow realm: obsidian facets with thin cold highlights.
static func _paint_obsidian_body(image: Image, style: DoorStyle, body: Dictionary) -> void:
	var cx := float(style.frame_size.x - 1) * 0.5
	for p: Vector2i in body:
		var facet: int
		if p.y < 24:
			facet = floori((atan2(float(p.y) - 24.0, float(p.x) - cx) + PI) / (PI / 5.0))
		else:
			facet = 10 + (p.y - 24) / 7
		var c := style.stone_mid if facet % 2 == 0 else style.stone_dark
		var shine := (p.x + p.y * 2 + facet * 3) % 11 == 0
		if shine:
			c = style.stone_light
		if not body.has(p + Vector2i.LEFT) or not body.has(p + Vector2i.UP):
			c = style.stone_light
		image.set_pixelv(p, c)


## Ember forge: dark iron plates with lighter top edges.
static func _paint_iron_body(image: Image, style: DoorStyle, body: Dictionary) -> void:
	for p: Vector2i in body:
		var c := style.stone_mid
		if p.y <= 12:
			c = style.stone_mid if p.y > 7 else style.stone_light
		elif p.y >= 43:
			c = style.stone_dark if _hash(p.x, p.y, 7) > 0.35 else style.stone_mid
		else:
			c = style.stone_mid if (p.x <= 6 or p.x >= 41) else _shade(style.stone_mid, -0.15)
		if not body.has(p + Vector2i.LEFT):
			c = c.lightened(0.15)
		elif not body.has(p + Vector2i.RIGHT):
			c = c.darkened(0.2)
		image.set_pixelv(p, c)


## Boss gate: biome-neutral grey stone (tinted per biome like delivered art).
static func _paint_boss_body(image: Image, style: DoorStyle, body: Dictionary) -> void:
	var light := Color("b4aecb")
	var mid := Color("8f88ad")
	var dark := Color("5d577a")
	var cx := float(style.frame_size.x - 1) * 0.5
	for p: Vector2i in body:
		var c := mid
		var pillar := p.x <= 14 or p.x >= 49
		if pillar:
			var local := p.x - (2 if p.x <= 14 else 50)
			c = light if local <= 3 else (mid if local <= 8 else dark)
			if (p.y >= 8 and p.y <= 12) or p.y >= 51:
				c = light if p.y == 8 or p.y == 51 else mid
			elif p.y % 9 == 0:
				c = dark
		elif p.y < 30:
			var angle := atan2(float(p.y) - 30.0, float(p.x) - cx)
			var segment := floori((angle + PI) / (PI / 9.0))
			c = light if segment % 2 == 0 else mid
			if fposmod(angle + PI, PI / 9.0) < 0.05:
				c = dark
		else:
			c = mid if (p.y / 4) % 2 == 0 else dark.lightened(0.1)
		if not body.has(p + Vector2i.LEFT):
			c = c.lightened(0.12)
		image.set_pixelv(p, c)


# --- Frame details (drawn after the contour) ---

static func _paint_skull(image: Image, origin: Vector2i, eye: Color, big: bool) -> void:
	var rows: Array[String]
	if big:
		rows = [
			"...XXXXXXXX...",
			"..XXXXXXXXXX..",
			".XXXXXXXXXXXX.",
			"XXXXXXXXXXXXXX",
			"XXXooXXXXooXXX",
			"XXXooXXXXooXXX",
			"XXXXXXX.XXXXXX",
			".XXXXX...XXXX.",
			"..XXXXXXXXXX..",
			"..X.X.X.X.X...",
			"..XXXXXXXXXX..",
		]
	else:
		rows = [
			".XXXX.",
			"XXXXXX",
			"XoXXoX",
			"XXXXXX",
			".X.XX.",
		]
	var height := rows.size()
	for y in height:
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			var p := origin + Vector2i(x, y)
			if ch == "X":
				var shade := BONE if y < height / 2 else BONE_DARK
				_put(image, p.x, p.y, shade)
			elif ch == "o":
				_put(image, p.x, p.y, eye)
			elif ch == ".":
				# Dark gaps inside the skull read as outline.
				if (x > 0 and x < row.length() - 1 and y > 0 and y < height - 1) and row[x - 1] != "." and row[x + 1] != ".":
					_put(image, p.x, p.y, OUTLINE)
	# Contour around the skull.
	var size := Vector2i(rows[0].length(), height)
	for y in range(-1, size.y + 1):
		for x in range(-1, size.x + 1):
			var inside := x >= 0 and y >= 0 and x < size.x and y < size.y and rows[y][x] != "."
			if inside:
				continue
			var near := false
			for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var q := Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < size.x and q.y < size.y and rows[q.y][q.x] != ".":
					near = true
			if near and not (x >= 0 and y >= 0 and x < size.x and y < size.y):
				_put(image, origin.x + x, origin.y + y, OUTLINE)


static func _paint_crypt_details(image: Image, style: DoorStyle) -> void:
	# Skull relief on the keystone.
	_paint_skull(image, Vector2i(21, 5), OUTLINE, false)
	# Cracks in the posts and the arch.
	var cracks: Array[Array] = [
		[Vector2i(5, 27), Vector2i(6, 28), Vector2i(6, 29), Vector2i(5, 30), Vector2i(5, 31)],
		[Vector2i(42, 33), Vector2i(41, 34), Vector2i(41, 35), Vector2i(42, 36)],
		[Vector2i(12, 12), Vector2i(13, 13), Vector2i(13, 14)],
		[Vector2i(36, 9), Vector2i(35, 10), Vector2i(35, 11)],
	]
	for crack in cracks:
		for p: Vector2i in crack:
			if _opaque(image, p.x, p.y):
				_put(image, p.x, p.y, style.stone_dark.darkened(0.3))


static func _paint_slime_details(image: Image, style: DoorStyle) -> void:
	var moss := style.accent
	var moss_dark := Color("2f944c")
	# Moss on the upper rim of the arch.
	for x in image.get_width():
		for y in 26:
			if _opaque(image, x, y) and image.get_pixel(x, y) != OUTLINE:
				if _hash(x, 0, 9) > 0.25:
					_put(image, x, y, moss if _hash(x, y, 13) > 0.4 else moss_dark)
				if _hash(x, 1, 9) > 0.55 and _opaque(image, x, y + 1):
					_put(image, x, y + 1, moss_dark)
				break
	# Slime dripping from the inner edge of the arch into the opening.
	var drips := [[13, 3], [17, 5], [22, 2], [27, 4], [32, 6], [35, 3]]
	for drip: Array in drips:
		var x: int = drip[0]
		var length: int = drip[1]
		var start := -1
		for y in range(4, 30):
			if _opaque(image, x, y) and not _opaque(image, x, y + 1):
				start = y + 1
				break
		if start < 0:
			continue
		for i in length:
			_put(image, x, start + i, Color("5fcd62") if i < length - 1 else Color("b4f09c"))
	# Crystals at the foot of the posts.
	_paint_crystal(image, Vector2i(3, 39))
	_paint_crystal(image, Vector2i(43, 40))


static func _paint_crystal(image: Image, origin: Vector2i) -> void:
	var rows: Array[String] = [".L.", "LLM", "LMD", "LMD", "MMD"]
	for y in rows.size():
		for x in 3:
			var ch: String = rows[y][x]
			if ch == ".":
				continue
			var c := Color("b4fff0") if ch == "L" else (Color("7ff0c8") if ch == "M" else Color("2fb391"))
			_put(image, origin.x + x, origin.y + y, c)


## Rune glyphs (3x5) on posts and arch. glow_only paints them into the glow mask instead.
static func _paint_runes(image: Image, style: DoorStyle, glow_only: bool) -> void:
	var glyphs: Array[Array] = [
		["X.X", ".X.", "XXX", ".X.", "X.X"],
		["XX.", "X..", "XXX", "..X", ".XX"],
		[".X.", "XXX", ".X.", "X.X", ".X."],
		["X..", "XX.", "X.X", ".XX", "..X"],
	]
	var spots: Array[Vector2i] = [Vector2i(4, 28), Vector2i(4, 36), Vector2i(41, 30), Vector2i(41, 38),
		Vector2i(9, 13), Vector2i(36, 13), Vector2i(22, 4)]
	for i in spots.size():
		var glyph: Array = glyphs[i % glyphs.size()]
		for y in 5:
			for x in 3:
				if glyph[y][x] != "X":
					continue
				var p := spots[i] + Vector2i(x, y)
				var c := Color("dcbcff") if (x + y) % 2 == 0 else style.accent
				if glow_only:
					_put(image, p.x, p.y, Color(style.glow_color, 0.9))
					for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
						if not _opaque(image, p.x + d.x, p.y + d.y):
							_put(image, p.x + d.x, p.y + d.y, Color(style.glow_color, 0.35))
				else:
					_put(image, p.x, p.y, c)


static func _paint_ember_details(image: Image, style: DoorStyle) -> void:
	# Glowing seams between the plates.
	for x in range(5, 43):
		if _opaque(image, x, 12):
			_put(image, x, 12, Color("e04e2a") if x % 4 else style.glow_color)
	for y in range(15, 42):
		if y % 6 != 0:
			_put(image, 6, y, Color("e04e2a"))
			_put(image, 41, y, Color("e04e2a"))
	# Rivets.
	for x in range(6, 43, 5):
		_put(image, x, 9, style.accent)
		_put(image, x, 10, METAL_DARK)
	for y in range(17, 42, 6):
		for x: int in [4, 8, 39, 43]:
			_put(image, x, y, style.accent)
			_put(image, x, y + 1, METAL_DARK)
	# Slag lumps with glowing specks at the base.
	for x in range(1, 47):
		if x >= 9 and x <= 38:
			continue
		if _hash(x, 44, 21) > 0.5:
			_put(image, x, 44, Color("2f2a2a"))
		if _hash(x, 46, 22) > 0.8:
			_put(image, x, 46, Color("ff8a3c"))


static func _paint_boss_details(image: Image, style: DoorStyle) -> void:
	# Skull crown over the arch.
	_paint_skull(image, Vector2i(25, 0), OUTLINE, true)
	# Horns / spikes beside the skull.
	for i in 4:
		_put(image, 22 - i, 3 + i, BONE_DARK)
		_put(image, 41 + i, 3 + i, BONE_DARK)
	# Chains hanging down the pillar fronts.
	for pillar_x: int in [7, 55]:
		for y in range(14, 46):
			var link := (y - 14) % 4
			if link == 0 or link == 3:
				_put(image, pillar_x, y, METAL_MID)
				_put(image, pillar_x + 1, y, METAL_DARK)
			else:
				_put(image, pillar_x - 1, y, METAL_MID)
				_put(image, pillar_x + 2, y, METAL_DARK)
				_put(image, pillar_x, y, OUTLINE)
				_put(image, pillar_x + 1, y, OUTLINE)
	# Iron torch holders on the pillars (DoorView places the flames there).
	for holder_x: int in [6, 54]:
		_fill(image, Rect2i(holder_x, 22, 4, 2), METAL_DARK)
		_put(image, holder_x, 22, METAL_LIGHT)


# --- Glow masks ---

## Red light leaking through the gap between the two wings of the boss gate.
static func _paint_boss_seam(image: Image, style: DoorStyle) -> void:
	var seam_x := style.leaf_offset.x + style.leaf_size.x / 2
	for y in range(style.leaf_offset.y + 4, style.frame_size.y - 1):
		_put(image, seam_x - 1, y, Color(style.glow_color, 0.55))
		_put(image, seam_x, y, Color(style.glow_color, 0.55))
		_blend(image, seam_x - 2, y, Color(style.glow_color, 0.18))
		_blend(image, seam_x + 1, y, Color(style.glow_color, 0.18))


static func paint_glow(style: DoorStyle) -> Image:
	var image := _new_image(style.frame_size)
	if style.is_boss():
		# Skull eyes, the seam between the wings and the lock (leaf area, under the frame).
		for p: Vector2i in [Vector2i(28, 4), Vector2i(29, 4), Vector2i(28, 5), Vector2i(29, 5),
				Vector2i(34, 4), Vector2i(35, 4), Vector2i(34, 5), Vector2i(35, 5)]:
			_put(image, p.x, p.y, Color(style.glow_color, 1.0))
			for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				_blend(image, p.x + d.x, p.y + d.y, Color(style.glow_color, 0.3))
		_paint_boss_seam(image, style)
		return image
	match style.biome_id:
		&"shadow_realm":
			_paint_runes(image, style, true)
		&"ember_forge":
			for x in range(5, 43):
				_put(image, x, 12, Color(style.glow_color, 0.8))
				_blend(image, x, 11, Color(style.glow_color, 0.2))
				_blend(image, x, 13, Color(style.glow_color, 0.25))
			for y in range(15, 42):
				if y % 6 != 0:
					_put(image, 6, y, Color(style.glow_color, 0.7))
					_put(image, 41, y, Color(style.glow_color, 0.7))
			for x in range(1, 47):
				if (x < 9 or x > 38) and _hash(x, 46, 22) > 0.8:
					_put(image, x, 46, Color(style.glow_color, 1.0))
		&"slime_grotto":
			for origin: Vector2i in [Vector2i(3, 39), Vector2i(43, 40)]:
				for y in 5:
					for x in 3:
						_put(image, origin.x + x, origin.y + y, Color(style.glow_color, 0.7))
	return image


## Glow mask from delivered frame art: its saturated, bright pixels (runes, embers, eyes).
static func glow_from_frame(frame: Image, style: DoorStyle) -> Image:
	if frame == null:
		return null
	var source := frame.duplicate() as Image
	if source.is_compressed():
		source.decompress()
	source.convert(Image.FORMAT_RGBA8)
	var image := _new_image(source.get_size())
	for y in source.get_height():
		for x in source.get_width():
			var c := source.get_pixel(x, y)
			if c.a > 0.5 and c.s >= GLOW_MIN_SATURATION and c.v >= GLOW_MIN_VALUE and _hue_close(c.h, style.glow_color.h):
				image.set_pixel(x, y, Color(style.glow_color, 0.9))
	if style.is_boss():
		_paint_boss_seam(image, style)
	return image


static func _hue_close(a: float, b: float) -> bool:
	var d := absf(a - b)
	return minf(d, 1.0 - d) <= GLOW_HUE_TOLERANCE


# --- Leaves ---

static func paint_leaf_strip(style: DoorStyle) -> Image:
	var size := style.leaf_size
	var strip := _new_image(Vector2i(size.x * LEAF_FRAMES, size.y))
	var visible := _leaf_mask(style)
	for f in LEAF_FRAMES:
		var frame := _paint_void(size)
		match style.leaf_kind:
			DoorStyle.LEAF_VINES:
				_paint_vines(frame, f)
			DoorStyle.LEAF_VEIL:
				_paint_veil(frame, style, f)
			DoorStyle.LEAF_PORTCULLIS:
				_paint_portcullis(frame, f)
			DoorStyle.LEAF_DOUBLE:
				_paint_double(frame, f)
			_:
				_paint_wood(frame, f)
		# The leaf is drawn over the frame: cut it to the arch of the placeholder frame.
		for y in size.y:
			for x in size.x:
				if not visible.has(Vector2i(x, y) + style.leaf_offset):
					frame.set_pixel(x, y, Color(0, 0, 0, 0))
		strip.blit_rect(frame, Rect2i(Vector2i.ZERO, size), Vector2i(f * size.x, 0))
	return strip


## Open passage: dark, a hint of floor at the bottom.
static func _paint_void(size: Vector2i) -> Image:
	var image := _new_image(size)
	for y in size.y:
		var t := float(y) / float(size.y - 1)
		var c := VOID_TOP.lerp(VOID_MID, minf(1.0, t * 1.6))
		if y >= size.y - 5:
			c = VOID_FLOOR
		for x in size.x:
			image.set_pixel(x, y, c)
	return image


## Crypt: iron-banded planks; the door swings up and inward (gets shorter from the bottom).
static func _paint_wood(image: Image, frame: int) -> void:
	var size := image.get_size()
	var heights := [size.y, 21, 10, 2]
	var h: int = heights[frame]
	var darken := [0.0, 0.18, 0.35, 0.5][frame] as float
	for y in h:
		var src_y := floori(float(y) * float(size.y) / float(maxi(1, h)))
		for x in size.x:
			var plank := x / 8
			var c := WOOD_LIGHT if plank % 2 == 0 else WOOD_MID
			if x % 8 == 7 or x == 0:
				c = WOOD_DARK
			# Sparse knots and grain.
			if (x * 7 + src_y * 3 + plank * 5) % 41 == 0:
				c = WOOD_DARK
			elif x % 8 == 3 and (src_y + plank * 4) % 9 < 3:
				c = c.darkened(0.12)
			if src_y == 6 or src_y == 7 or src_y == 23 or src_y == 24:
				c = METAL_MID if src_y % 2 == 0 else METAL_DARK
				if x % 6 == 3:
					c = METAL_LIGHT
			if src_y >= 14 and src_y <= 16 and x >= 22 and x <= 24:
				c = METAL_LIGHT if src_y == 14 else METAL_DARK
			if frame == 3:
				c = WOOD_DARK
			image.set_pixel(x, y, c.darkened(darken))
	if h < size.y:
		# Shadow line under the swung door.
		for x in size.x:
			image.set_pixel(x, h, OUTLINE)


## Slime grotto: vine and slime curtain, pulled to both sides.
static func _paint_vines(image: Image, frame: int) -> void:
	var size := image.get_size()
	var pull := [0.0, 0.45, 0.8, 1.0][frame] as float
	var strands := 8
	for s in strands:
		var base_x := 1.5 + float(s) * (float(size.x) - 3.0) / float(strands - 1)
		var side := -1.0 if base_x < size.x * 0.5 else 1.0
		var edge := 0.5 if side < 0.0 else float(size.x) - 1.5
		var x0 := lerpf(base_x, edge + side * -float(absf(base_x - size.x * 0.5)) * 0.12, pull)
		for y in size.y:
			# Strands hang from the top; when pulled they sag toward the side.
			var sway := sin(float(y) * 0.45 + float(s) * 1.7) * (1.0 - pull * 0.6)
			var droop := pull * (1.0 - float(y) / float(size.y)) * side * 1.5
			var x := roundi(x0 + sway + droop)
			if frame == 3 and absf(x - edge) > 2.5:
				continue
			var c := Color("2f944c") if s % 2 == 0 else Color("4fae4a")
			if (y + s * 3) % 7 == 0:
				_put(image, x + 1, y, Color("6fbf5a"))
			_put(image, x, y, c)
		# Slime threads between neighbours (only while closed).
		if frame == 0 and s % 3 == 1:
			var y_thread := 8 + (s * 5) % 18
			for i in 3:
				_blend(image, roundi(base_x) + i, y_thread + i / 2, Color("b4f09c", 0.6))


## Shadow realm: a veil with a rune circle; runes go out from the outside inward, veil dissolves.
static func _paint_veil(image: Image, style: DoorStyle, frame: int) -> void:
	var size := image.get_size()
	if frame == 3:
		return
	var keep := [1.0, 0.6, 0.25][frame] as float
	var centre := Vector2(15.5, 15.0)
	for y in size.y:
		for x in size.x:
			if _hash(x, y, 31) > keep:
				continue
			var c := Color("2e2640") if (x + y) % 2 == 0 else Color("3b3150")
			if _hash(x / 2, y / 3, 32) > 0.85:
				c = Color("6a3cb4").darkened(0.3)
			image.set_pixel(x, y, c)
	# Rune ring: 8 marks; frame 1 loses the outer ring, frame 2 keeps only the centre.
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var p := centre + Vector2(cos(angle), sin(angle)) * 10.0
		var lit := frame == 0
		var c := style.accent if lit else Color("6a3cb4").darkened(0.2)
		if frame < 2:
			_put(image, roundi(p.x), roundi(p.y), c)
			_put(image, roundi(p.x), roundi(p.y) + 1, c.darkened(0.2))
	for i in 24:
		var angle := TAU * float(i) / 24.0
		var p := centre + Vector2(cos(angle), sin(angle)) * 7.0
		if frame < 2 and i % 2 == 0:
			_put(image, roundi(p.x), roundi(p.y), Color("6a3cb4") if frame == 0 else Color("4a2a80"))
	# Centre sigil burns longest.
	for d: Vector2i in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i(0, 2), Vector2i(0, -2)]:
		var c := Color("dcbcff") if d == Vector2i.ZERO else style.accent
		if frame == 2:
			c = c.darkened(0.25)
		_put(image, roundi(centre.x) + d.x, roundi(centre.y) + d.y, c)


## Ember forge: iron portcullis over the dark passage, slides upward.
static func _paint_portcullis(image: Image, frame: int) -> void:
	var size := image.get_size()
	var lift := [0, 11, 22, 29][frame] as int
	# Warm glow on the floor behind the bars.
	for x in size.x:
		image.set_pixel(x, size.y - 2, Color("3a1f18"))
		image.set_pixel(x, size.y - 1, Color("4a2418"))
	for y in size.y:
		var src_y := y + lift
		if src_y >= size.y:
			break
		for x in size.x:
			var bar_x := x % 6
			var vertical := bar_x == 2 or bar_x == 3
			var horizontal := src_y % 10 == 5 or src_y % 10 == 6
			var spike := src_y >= size.y - 3
			if spike and vertical:
				var tip := src_y - (size.y - 3)
				if tip == 2 and bar_x == 3:
					continue
				image.set_pixel(x, y, METAL_MID if bar_x == 2 else METAL_DARK)
			elif vertical and not spike:
				image.set_pixel(x, y, METAL_MID if bar_x == 2 else METAL_DARK)
				if horizontal:
					image.set_pixel(x, y, METAL_LIGHT)
			elif horizontal and not spike:
				image.set_pixel(x, y, METAL_DARK if src_y % 10 == 6 else METAL_MID)


## Boss gate: chained double door; chains burst, wings swing inward.
static func _paint_double(image: Image, frame: int) -> void:
	var size := image.get_size()
	var half := size.x / 2
	var widths := [half, half, 7, 2]
	var w: int = widths[frame]
	var darken := [0.0, 0.0, 0.3, 0.5][frame] as float
	for side in 2:
		for i in w:
			var x := i if side == 0 else size.x - 1 - i
			var src := floori(float(i) * float(half) / float(maxi(1, w)))
			for y in size.y:
				var c := Color("6b4128") if (src / 5) % 2 == 0 else Color("5c3a24")
				if src == half - 1 or src == 0:
					c = OUTLINE
				if y == 5 or y == 6 or y == 25 or y == 26:
					c = METAL_DARK if y % 2 == 0 else METAL_MID
				if (y == 5 or y == 25) and src % 4 == 1:
					c = METAL_LIGHT
				image.set_pixel(x, y, c.darkened(darken))
	if frame == 0:
		# Chains crossing in an X, padlock in the middle.
		for i in range(2, size.x - 2):
			var y1 := 4 + roundi(float(i - 2) * 0.8)
			var y2 := size.y - 5 - roundi(float(i - 2) * 0.8)
			for y: int in [y1, y2]:
				if y >= 0 and y < size.y:
					image.set_pixel(i, y, METAL_MID if i % 3 else METAL_LIGHT)
					if y + 1 < size.y:
						image.set_pixel(i, y + 1, OUTLINE)
		_fill(image, Rect2i(half - 3, 14, 6, 6), GOLD)
		_fill(image, Rect2i(half - 3, 18, 6, 2), GOLD_DARK)
		image.set_pixel(half - 1, 16, OUTLINE)
		image.set_pixel(half, 16, OUTLINE)
		for x in range(half - 2, half + 2):
			image.set_pixel(x, 12, METAL_MID)
		image.set_pixel(half - 2, 13, METAL_MID)
		image.set_pixel(half + 1, 13, METAL_MID)
	elif frame == 1:
		# Broken chain links falling.
		for p: Vector2i in [Vector2i(9, 18), Vector2i(10, 19), Vector2i(21, 21), Vector2i(22, 22), Vector2i(15, 27), Vector2i(17, 28)]:
			image.set_pixel(p.x, p.y, METAL_MID)


# --- Symbols ---

## Placeholder sign: dark plaque with a light rim and the UI icon on it.
static func paint_symbol(symbol_id: StringName) -> Image:
	var image := _new_image(PLAQUE_SIZE)
	for y in PLAQUE_SIZE.y:
		for x in PLAQUE_SIZE.x:
			var corner := mini(x, PLAQUE_SIZE.x - 1 - x) + mini(y, PLAQUE_SIZE.y - 1 - y) < 3
			if corner:
				continue
			var rim := x == 0 or y == 0 or x == PLAQUE_SIZE.x - 1 or y == PLAQUE_SIZE.y - 1
			image.set_pixel(x, y, OUTLINE if rim else PLAQUE_FILL)
	for y in range(1, PLAQUE_SIZE.y - 1):
		for x in range(1, PLAQUE_SIZE.x - 1):
			var ring := x == 1 or y == 1 or x == PLAQUE_SIZE.x - 2 or y == PLAQUE_SIZE.y - 2
			if ring and image.get_pixel(x, y).a > 0.5:
				image.set_pixel(x, y, PLAQUE_RIM if (x + y) % 5 else GOLD)
	var icon := _symbol_icon(symbol_id)
	if icon != null:
		var offset := (PLAQUE_SIZE - icon.get_size()) / 2
		image.blend_rect(icon, Rect2i(Vector2i.ZERO, icon.get_size()), offset)
	return image


static func _symbol_icon(symbol_id: StringName) -> Image:
	var image: Image = null
	if symbol_id == &"campfire":
		var torch := _load_file(CAMPFIRE_ICON)
		if torch != null:
			image = torch.get_image().get_region(CAMPFIRE_REGION)
	elif SYMBOL_ICONS.has(symbol_id):
		var texture := _load_file(SYMBOL_ICONS[symbol_id])
		if texture != null:
			image = texture.get_image()
	if image == null:
		return null
	image = image.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image

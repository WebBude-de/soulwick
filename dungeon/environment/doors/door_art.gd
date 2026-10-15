class_name DoorArt
extends RefCounted
## Door textures (ROADMAP_AUSBAU D1). Delivered files from art/environment/doors/ (names in
## docs/design/sprites/SPRITES_V4.md §4, built by DoorStyle) win automatically; while a file is missing, a
## placeholder is painted here pixel by pixel in the HANDOUT palette. Everything is cached.
## Visual only: randomness here is a fixed hash, so every door of a style looks the same.
## Gates (M2, gates.json) are one neutral strip per kind (slab, bars), tinted by DoorView; the
## placeholder cave mouth is the biome's arch on a wider rock lintel.

## Colour of the dark passage inside delivered frames (art/environment/doors/doors.json) and of the
## soft palette (cave_mouth_crypt_soft, the gates' space behind the slab and between the bars). Every
## opening is made transparent (playtest 14.10.2026: no black hole in a door, the corridor and the
## next room show through; a veiled next room darkens itself).
const PASSAGE_COLOR := Color("#0b0a12")
const SOFT_PASSAGE_COLOR := Color("#1a1626")
## Passage pixels this transparent or more count too (the cave mouths fade their opening upwards).
const PASSAGE_MIN_ALPHA := 0.3
## Dark sheet between the arch and the swirl of art/environment/props/exit_portal_6f.png (open_fill).
const PORTAL_FILL := Color("#1d1536")
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
## Width in art px of the placeholder leaf of a west/east door (A10).
const SIDE_LEAF_WIDTH := 12
## Overlay sheet of a biome (32 px cells): pebbles and a tuft at the foot of a mouth (M2).
const OVERLAY_PATH := "res://art/environment/tiles/overlay_%s.png"
const OVERLAY_CELLS: Dictionary[StringName, int] = {&"pebbles": 1, &"tuft": 2}
const OVERLAY_CELL := 32
## Placeholder gate colours (neutral grey like the delivered strips; DoorView tints them).
const GATE_STONE_LIGHT := Color("a29db4")
const GATE_STONE_MID := Color("7d7891")
const GATE_STONE_DARK := Color("575269")
## UI icons shown on the placeholder sign until door_special_symbols.png exists.
const SYMBOL_ICONS := {
	&"shop": "res://art/ui/gold_icon.png",
	&"weapon": "res://art/ui/icon_sword.png",
	&"fountain": "res://art/ui/heart_full.png",
	&"upgrade": "res://art/ui/upgrade_magic_power.png",
	&"trial": "res://art/ui/clock_icon.png",
	&"miniboss": "res://art/ui/skull_icon.png",
	&"elite_nest": "res://art/ui/skull_icon.png",
	&"safe": "res://art/ui/heart_full.png",
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
	if DoorStyle.is_branch_symbol(symbol_id):
		var branch_sheet := _load_file(DoorStyle.get_branch_symbols_path())
		var column := DoorStyle.branch_symbol_index(symbol_id)
		return branch_sheet != null and branch_sheet.get_width() >= (column + 1) * SYMBOL_SIZE.x
	var sheet := _load_file(_art_path(DoorStyle.get_symbols_path()))
	var index := DoorStyle.symbol_index(symbol_id)
	return sheet != null and index >= 0 and sheet.get_width() >= (index + 1) * SYMBOL_SIZE.x


## Frame texture (arch 48x48, cave mouth 64x48, boss 64x56): delivered file or placeholder. A missing
## soft crypt mouth falls back to the plain crypt mouth.
static func get_frame(style: DoorStyle) -> Texture2D:
	var key := "frame_%s" % style.get_key()
	if not _cache.has(key):
		var file := _load_file(_art_path(style.get_frame_path()))
		if file == null and style.soft:
			file = _load_file(_art_path(style.get_frame_path().replace(DoorStyle.SOFT_SUFFIX, "")))
		var image := open_passage(file.get_image()) if file != null else paint_frame(style)
		# Old mouths are a rock block with the arch in it: only the arch stays. The V9 soft mouths are
		# the arch band alone already (transparent corners).
		if style.is_cave() and not style.is_boss() and image.get_pixel(0, 0).a > 0.5:
			image = arch_band(image, CAVE_ARCH_BAND)
		_cache[key] = ImageTexture.create_from_image(image)
	return _cache[key]


## A cave mouth keeps only its arch: the rim around the passage, this many px wide; the flat rock
## around it goes, so the mouth sits seamless in the room's own wall front and crown (38.png: no
## darker rectangle around the arch). TESTWERT
const CAVE_ARCH_BAND := 5


## image with every opaque pixel farther than band px (8 neighbours) from the open passage (the
## transparent area reached from the bottom centre) made transparent.
static func arch_band(image: Image, band: int) -> Image:
	if image == null:
		return image
	image.convert(Image.FORMAT_RGBA8)
	var size := image.get_size()
	var passage: Dictionary[Vector2i, int] = {}
	var start := Vector2i(size.x / 2, size.y - 1)
	if image.get_pixelv(start).a > 0.05:
		return image
	# The passage first (transparent, 4-connected to the bottom centre), then the distance of every
	# opaque pixel to it, breadth first over 8 neighbours from all passage pixels at once.
	var queue: Array[Vector2i] = []
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var point: Vector2i = stack.pop_back()
		if point.x < 0 or point.y < 0 or point.x >= size.x or point.y >= size.y or passage.has(point):
			continue
		if image.get_pixelv(point).a > 0.05:
			continue
		passage[point] = 0
		queue.append(point)
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			stack.append(point + step)
	var head := 0
	while head < queue.size():
		var point: Vector2i = queue[head]
		head += 1
		var distance: int = passage[point]
		if distance >= band:
			continue
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var next := point + Vector2i(dx, dy)
				if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y or passage.has(next):
					continue
				if image.get_pixelv(next).a <= 0.05:
					continue
				passage[next] = distance + 1
				queue.append(next)
	for y in size.y:
		for x in size.x:
			var p := Vector2i(x, y)
			if image.get_pixelv(p).a > 0.05 and (not passage.has(p) or passage[p] > band):
				image.set_pixelv(p, Color(0, 0, 0, 0))
	return image


## Dark of the tunnel seen through the top of an arch or mouth over a closed crown: alpha at the top
## and where it meets the door tile. TESTWERTE
const TUNNEL_COLOR := Color("0d0b14")
const TUNNEL_ALPHA_TOP := 0.8
const TUNNEL_ALPHA_BOTTOM := 0.5
## Below the crown the tunnel dark fades out over this many art px of the door tile (39.png: no hard
## shadow edge where the player walks in). TESTWERT
const TUNNEL_FADE_PX := 18


## Side passage (40.png): a dark slot in the light edge of the closed side wall, one tile tall, drawn
## for an east wall (the room's floor on the left): SIDE_MOUTH_SHADOW px of shadow on the floor
## darkening towards the slot over the edge, then fading into the rock, soft at both ends. Art px; DoorView mirrors it for a west wall. TESTWERTE
const SIDE_MOUTH_SHADOW := 7
const SIDE_MOUTH_SLOT := 5
const SIDE_MOUTH_FADE := 8
const SIDE_MOUTH_ALPHA := 0.8
## Soft ends: the slot fades in over this many rows at the top and the bottom (no box, 40.png).
const SIDE_MOUTH_END := 8


static func side_mouth_image() -> Image:
	var width := SIDE_MOUTH_SHADOW + SIDE_MOUTH_SLOT + SIDE_MOUTH_FADE
	var image := Image.create_empty(width, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		var end := clampf(minf(float(y) + 0.5, 31.5 - float(y)) / float(SIDE_MOUTH_END), 0.0, 1.0)
		end = end * end * (3.0 - 2.0 * end)
		for x in width:
			var a := 0.0
			if x < SIDE_MOUTH_SHADOW:
				var u := float(x + 1) / float(SIDE_MOUTH_SHADOW + 1)
				a = SIDE_MOUTH_ALPHA * u * u
			elif x < SIDE_MOUTH_SHADOW + SIDE_MOUTH_SLOT:
				a = SIDE_MOUTH_ALPHA
			else:
				var t := float(x - SIDE_MOUTH_SHADOW - SIDE_MOUTH_SLOT + 1) / float(SIDE_MOUTH_FADE + 1)
				a = SIDE_MOUTH_ALPHA * (1.0 - t * t * (3.0 - 2.0 * t))
			image.set_pixel(x, y, Color(TUNNEL_COLOR, a * end))
	return image


## The opening of a frame (art px of the frame): every see-through pixel inside the arch, reached
## from the bottom centre without leaving the arch. The arch's side pillars bound it below; above the
## pillars' tops (a cave mouth keeps only a band) the search stays between the leftmost and rightmost
## pillar pixel of the row, so it never runs round the outside. Cached.
static func passage_mask(style: DoorStyle) -> Dictionary[Vector2i, bool]:
	var key := "passage_%s" % style.get_key()
	if _cache.has(key):
		return _cache[key]
	var mask: Dictionary[Vector2i, bool] = {}
	var frame := get_frame(style).get_image()
	if frame.is_compressed():
		frame.decompress()
	frame.convert(Image.FORMAT_RGBA8)
	var size := frame.get_size()
	var start := Vector2i(size.x / 2, size.y - 1)
	if frame.get_pixelv(start).a <= 0.05:
		# Per row: the opaque arch pixels left and right of the centre bound the opening.
		var bounds: Dictionary[int, Vector2i] = {}
		for y in size.y:
			var left := -1
			var right := size.x
			for x in range(size.x / 2, -1, -1):
				if frame.get_pixel(x, y).a > 0.05:
					left = x
					break
			for x in range(size.x / 2, size.x):
				if frame.get_pixel(x, y).a > 0.05:
					right = x
					break
			bounds[y] = Vector2i(left, right)
		# A row with the arch on one side only (a pillar foot left out, a shadow row) takes the missing
		# side from the nearest row that has it; rows without any arch stay outside.
		for y in size.y:
			var row: Vector2i = bounds[y]
			if (row.x < 0) == (row.y >= size.x):
				continue
			for d in range(1, size.y):
				var near := -1
				for candidate in [y + d, y - d]:
					if candidate >= 0 and candidate < size.y and bounds[candidate].x >= 0 and bounds[candidate].y < size.x:
						near = candidate
						break
				if near >= 0:
					var found: Vector2i = bounds[near]
					bounds[y] = Vector2i(found.x if row.x < 0 else row.x, found.y if row.y >= size.x else row.y)
					break
		var stack: Array[Vector2i] = [start]
		while not stack.is_empty():
			var point: Vector2i = stack.pop_back()
			if point.y < 0 or point.y >= size.y or mask.has(point):
				continue
			var row: Vector2i = bounds[point.y]
			# A row without arch on one side (above the arch) is outside the opening.
			if row.x < 0 or row.y >= size.x or point.x <= row.x or point.x >= row.y:
				continue
			if frame.get_pixelv(point).a > 0.05:
				continue
			mask[point] = true
			for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				stack.append(point + step)
	_cache[key] = mask
	return mask


## Frame-sized image of the opening in the tunnel colour from row top down, with alpha per row
## (alpha_of_row: Callable(row) -> float). Everything seen in the opening is cut to its arch (44.png:
## no rectangle corners inside the arch).
static func opening_image(style: DoorStyle, top: int, alpha_of_row: Callable) -> Image:
	var frame := get_frame(style)
	var size := Vector2i(frame.get_width(), frame.get_height())
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	for point: Vector2i in passage_mask(style):
		if point.y >= top:
			var a: float = alpha_of_row.call(point.y)
			if a > 0.0:
				image.set_pixelv(point, Color(TUNNEL_COLOR, a))
	return image


## Inner shadow of the V9 frames (tunnel_shade.json): one per frame shape, biome-neutral, as large
## as the frame, an 18 px soft run from the crown into the opening.
const TUNNEL_SHADE_CAVE := "res://art/environment/doors/tunnel_shade_cave.png"
const TUNNEL_SHADE_ARCH := "res://art/environment/doors/tunnel_shade_arch.png"
## Side passage opening of the soft rooms (V9): side_mouth_<biome>_soft.png, 20x32, east wall.
const SIDE_MOUTH_PATH := "res://art/environment/doors/side_mouth_%s_soft.png"


## The delivered inner shadow for this style (a V9 soft mouth or arch, the shade of its size), else
## null (the shadow is made from the opening, opening_image).
static func get_delivered_shade(style: DoorStyle) -> Image:
	if style.is_boss() or not style.soft or not has_art(style.get_frame_path()):
		return null
	var path := TUNNEL_SHADE_CAVE if style.is_cave() else TUNNEL_SHADE_ARCH
	var key := "delivered_shade_%s" % path
	if not _cache.has(key):
		var file := _load_file(_art_path(path))
		var image: Image = null
		if file != null:
			image = file.get_image()
			if image.is_compressed():
				image.decompress()
			image.convert(Image.FORMAT_RGBA8)
		_cache[key] = image
	var shade: Image = _cache[key]
	if shade == null or shade.get_size() != style.frame_size:
		return null
	return shade


## First row of the frame with an opaque pixel (the top of the arch), 0 for a frame that starts at
## its top edge. Cached.
static func frame_top_row(style: DoorStyle) -> int:
	var key := "top_row_%s" % style.get_key()
	if not _cache.has(key):
		var image := get_frame(style).get_image()
		if image.is_compressed():
			image.decompress()
		var row := 0
		var found := false
		while row < image.get_height() and not found:
			for x in image.get_width():
				if image.get_pixel(x, row).a > 0.05:
					found = true
					break
			if not found:
				row += 1
		_cache[key] = row if found else 0
	return _cache[key]


## Rows of image from top (incl.) to bottom (excl.) kept, the rest transparent (same size).
static func rows_of(image: Image, top: int, bottom: int) -> Image:
	var part := Image.create_empty(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	var from := clampi(top, 0, image.get_height())
	var to := clampi(bottom, from, image.get_height())
	if to > from:
		part.blit_rect(image, Rect2i(0, from, image.get_width(), to - from), Vector2i(0, from))
	return part


## The opening of the side passage: the delivered side_mouth_<biome>_soft (soft rooms), else the
## placeholder (side_mouth_image).
static func get_side_mouth(style: DoorStyle) -> Texture2D:
	if style != null and style.soft:
		var file := _load_file(_art_path(SIDE_MOUTH_PATH % style.biome_id))
		if file != null:
			return file
	var key := "side_mouth_placeholder"
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(side_mouth_image())
	return _cache[key]


## The whole opening in the tunnel colour (over the door tile and up into the crown): DoorView fades
## it in while a player walks through, so the player is hidden in the arch and the opening is one
## even dark, no step where the crown part meets the door tile. With a delivered inner shadow its
## shape (every pixel it touches), else the opening of the frame. null without an opening.
static func tunnel_shade_image(style: DoorStyle) -> Image:
	var delivered := get_delivered_shade(style)
	if delivered != null:
		var image := Image.create_empty(delivered.get_width(), delivered.get_height(), false, Image.FORMAT_RGBA8)
		for y in delivered.get_height():
			for x in delivered.get_width():
				if delivered.get_pixel(x, y).a > 0.02:
					image.set_pixel(x, y, Color(TUNNEL_COLOR, 1.0))
		return image
	if passage_mask(style).is_empty():
		return null
	return opening_image(style, 0, func(_row: int) -> float: return 1.0)


## The dark of the tunnel running on softly into the door tile, cut to the arch (39/44.png).
static func tunnel_fade_image(style: DoorStyle) -> Image:
	var top := style.leaf_offset.y
	return opening_image(style, top, func(row: int) -> float:
		var t := clampf(float(row - top) / float(TUNNEL_FADE_PX - 1), 0.0, 1.0)
		return TUNNEL_ALPHA_BOTTOM * (1.0 - t * t * (3.0 - 2.0 * t)))


## The door tile's floor seen through the opening where the arch is wider than the tile (a cave mouth
## opens 38 px over a 32 px tile): floor_image (one floor tile, art px) repeated under the opening
## from row top down, frame-sized. The fronts beside the door never show inside the arch.
static func opening_floor_image(style: DoorStyle, floor_image: Image) -> Image:
	var frame := get_frame(style)
	var size := Vector2i(frame.get_width(), frame.get_height())
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	if floor_image == null or floor_image.is_empty():
		return image
	var tile := floor_image.get_size()
	for point: Vector2i in passage_mask(style):
		if point.y >= style.leaf_offset.y:
			var u := posmod(point.x - style.leaf_offset.x, tile.x)
			var v := posmod(point.y - style.leaf_offset.y, tile.y)
			image.set_pixelv(point, floor_image.get_pixel(u, v))
	return image


## Width of the opening at the bottom row (art px), 0 without one.
static func opening_width(style: DoorStyle) -> int:
	var frame := get_frame(style)
	var bottom := frame.get_height() - 1
	var count := 0
	for point: Vector2i in passage_mask(style):
		if point.y == bottom:
			count += 1
	return count


## The part of a frame above its door tile (rows 0 .. leaf_offset.y): the frame as it is, its open
## passage filled with the tunnel dark (fading towards the door tile). null for nothing above.
static func frame_top_image(style: DoorStyle) -> Image:
	var rows := style.leaf_offset.y
	if rows <= 0:
		return null
	var frame := get_frame(style).get_image()
	if frame.is_compressed():
		frame.decompress()
	frame.convert(Image.FORMAT_RGBA8)
	var image := frame.get_region(Rect2i(0, 0, frame.get_width(), rows))
	if get_delivered_shade(style) != null:
		# The delivered inner shadow darkens the opening (DoorView).
		return image
	# The opening of the arch itself, not a rectangle (44.png).
	for point: Vector2i in passage_mask(style):
		if point.y < rows:
			var t := float(point.y) / float(maxi(1, rows - 1))
			image.set_pixelv(point, Color(TUNNEL_COLOR, lerpf(TUNNEL_ALPHA_TOP, TUNNEL_ALPHA_BOTTOM, t)))
	return image


## Sides of the light cone: from this share of its half width outwards it fades to nothing (L1,
## 15.10.2026: rock blocks cut a hard cone edge straight off). TESTWERT
const CONE_SIDE_FEATHER := 0.45


## The light cone with its start edge faded in over the first share of its length (pivot top
## centre): no hard edge where the cone leaves the door (31.png). Its base is narrowed to base_share
## of the width (the opening, one tile) and widens to the full art at the far end; the sides fade
## out softly. Cached.
static func soft_cone(texture: Texture2D, share: float, base_share := 1.0) -> Texture2D:
	if texture == null:
		return texture
	var key := "soft_cone_%s_%.2f_%.2f" % [texture.resource_path, share, base_share]
	if not _cache.has(key):
		var image := texture.get_image()
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		var height := image.get_height()
		var width := image.get_width()
		var fade := maxf(1.0, share * height)
		var centre := (width - 1) * 0.5
		for y in height:
			var t := clampf(float(y) / fade, 0.0, 1.0)
			var factor := t * t * (3.0 - 2.0 * t)
			var along := float(y) / float(maxi(1, height - 1))
			var half := maxf(1.0, lerpf(base_share, 1.0, along) * width * 0.5)
			for x in width:
				var u := clampf(absf(x - centre) / half, 0.0, 1.0)
				var side := 1.0 - clampf((u - (1.0 - CONE_SIDE_FEATHER)) / CONE_SIDE_FEATHER, 0.0, 1.0)
				side = side * side * (3.0 - 2.0 * side)
				var c := image.get_pixel(x, y)
				c.a *= factor * side
				image.set_pixel(x, y, c)
		_cache[key] = ImageTexture.create_from_image(image)
	return _cache[key]


## One cell of the biome's overlay sheet (pebbles, tuft), null without the sheet.
static func get_overlay(biome_id: StringName, soft: bool, cell: StringName) -> Texture2D:
	var key := "overlay_%s_%s_%s" % [biome_id, soft, cell]
	if not _cache.has(key):
		var sheet: Texture2D = null
		if soft:
			sheet = _load_file(OVERLAY_PATH % (String(biome_id) + DoorStyle.SOFT_SUFFIX))
		if sheet == null:
			sheet = _load_file(OVERLAY_PATH % biome_id)
		var atlas: AtlasTexture = null
		if sheet != null and OVERLAY_CELLS.has(cell):
			atlas = AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(OVERLAY_CELLS[cell] * OVERLAY_CELL, 0, OVERLAY_CELL, OVERLAY_CELL)
		_cache[key] = atlas
	return _cache[key]


## The delivered frames paint their passage in PASSAGE_COLOR; flood-filling it from the bottom
## centre makes it transparent, so the corridor shows through the arch (the leaf closes it).
static func open_passage(image: Image) -> Image:
	if image == null:
		return image
	image.convert(Image.FORMAT_RGBA8)
	var start := Vector2i(image.get_width() / 2, image.get_height() - 1)
	# The passage colour of this file: the known ones, or the dark colour at the bottom centre
	# (palette swaps such as cave_mouth_<biome>_soft recolour it).
	var seed_color := image.get_pixelv(start)
	var dark_seed := seed_color.a > PASSAGE_MIN_ALPHA and seed_color.get_luminance() < 0.15
	if not _is_passage(seed_color) and not dark_seed:
		return image
	var stack: Array[Vector2i] = [start]
	var bounds := Rect2i(Vector2i.ZERO, image.get_size())
	while not stack.is_empty():
		var point: Vector2i = stack.pop_back()
		if not bounds.has_point(point):
			continue
		var c := image.get_pixelv(point)
		if not (_is_passage(c) or (dark_seed and c.a > PASSAGE_MIN_ALPHA and _close(c, seed_color))):
			continue
		image.set_pixelv(point, Color(0, 0, 0, 0))
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			stack.append(point + step)
	return image


static func _is_passage(color: Color) -> bool:
	return color.a > PASSAGE_MIN_ALPHA and (_close(color, PASSAGE_COLOR) or _close(color, SOFT_PASSAGE_COLOR))


static func _close(color: Color, other: Color) -> bool:
	return absf(color.r - other.r) + absf(color.g - other.g) + absf(color.b - other.b) < 0.03


## texture with the dark sheet under an arch made transparent: every pixel of the colour fill that is
## connected to one in the top third (e.g. the exit portal: PORTAL_FILL between the arch and the swirl;
## dark parts of the swirl itself are not connected and stay). Cached by path.
static func open_fill(texture: Texture2D, fill: Color) -> Texture2D:
	if texture == null:
		return texture
	var key := "open_fill_%s_%s" % [texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id()), fill.to_html()]
	if not _cache.has(key):
		var image := texture.get_image()
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		var stack: Array[Vector2i] = []
		for y in image.get_height() / 3:
			for x in image.get_width():
				stack.append(Vector2i(x, y))
		var bounds := Rect2i(Vector2i.ZERO, image.get_size())
		while not stack.is_empty():
			var point: Vector2i = stack.pop_back()
			if not bounds.has_point(point):
				continue
			var c := image.get_pixelv(point)
			if c.a <= PASSAGE_MIN_ALPHA or not _close(c, fill):
				continue
			image.set_pixelv(point, Color(0, 0, 0, 0))
			for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				stack.append(point + step)
		_cache[key] = ImageTexture.create_from_image(image)
	return _cache[key]


## Delivered gate strips paint the space behind the slab and between the bars as a dark sheet (soft
## passage colour, alpha 0.9): it becomes transparent, so an open or opening gate shows the corridor.
## The block itself (outline at full alpha) stays.
static func open_gate_strip(image: Image) -> Image:
	if image == null:
		return image
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a < 0.97 and _is_passage(c):
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	return image


## Leaf of a west/east wall door (A10): delivered file or a placeholder made from the front leaf,
## turned and narrowed (four frames of 32x32, drawn for the west wall).
static func get_side_leaf_strip(style: DoorStyle) -> Texture2D:
	var key := "side_leaf_%s" % style.get_key()
	if not _cache.has(key):
		var file := _load_file(_art_path(style.get_side_leaf_path()))
		_cache[key] = file if file != null else ImageTexture.create_from_image(paint_side_leaf_strip(style))
	return _cache[key]


## Placeholder side leaf: every frame of the biome's door leaf (wood, vines, veil, portcullis; not
## the gate) turned a quarter and squeezed into a narrow slab in the middle of the tile, so it reads
## as a door seen from above.
static func paint_side_leaf_strip(style: DoorStyle) -> Image:
	var classic := _classic_style(style)
	var front := paint_leaf_strip(classic)
	var size := classic.leaf_size
	var frames := maxi(1, front.get_width() / maxi(1, size.x))
	var strip := _new_image(Vector2i(size.y * frames, size.y))
	for f in frames:
		var frame := front.get_region(Rect2i(f * size.x, 0, size.x, size.y))
		frame.rotate_90(CLOCKWISE)
		frame.resize(SIDE_LEAF_WIDTH, size.y, Image.INTERPOLATE_NEAREST)
		strip.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(f * size.y + (size.y - SIDE_LEAF_WIDTH) / 2, 0))
	return strip


## Leaf strip of a north door, four frames (frame 1 closed, frame 4 open): the gate (32x48) or the
## boss gate's double door (32x32).
static func get_leaf_strip(style: DoorStyle) -> Texture2D:
	var key := "leaf_%s" % style.get_key()
	if not _cache.has(key):
		var file := _load_file(_art_path(style.get_leaf_path()))
		if file != null and style.is_gate():
			_cache[key] = ImageTexture.create_from_image(open_gate_strip(file.get_image()))
		else:
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
	if DoorStyle.is_branch_symbol(symbol_id):
		return _get_branch_symbol(symbol_id)
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


## Branch sign (A10): a column of door_branch_symbols.png (SPRITES_V5 §6), else a placeholder sign.
static func _get_branch_symbol(symbol_id: StringName) -> Texture2D:
	var key := "branch_symbol_%s" % symbol_id
	if not _cache.has(key):
		if has_symbol_file(symbol_id):
			var atlas := AtlasTexture.new()
			atlas.atlas = _load_file(DoorStyle.get_branch_symbols_path())
			atlas.region = Rect2(DoorStyle.branch_symbol_index(symbol_id) * SYMBOL_SIZE.x, 0, SYMBOL_SIZE.x, SYMBOL_SIZE.y)
			_cache[key] = atlas
		else:
			_cache[key] = ImageTexture.create_from_image(paint_symbol(symbol_id))
	return _cache[key]


# --- Files ---

static func _art_path(default_path: String) -> String:
	return art_dir + default_path.get_file()


## Is the delivered file of this default path there? Door files are looked up in art_dir like every
## door file, others (the branch signs) where they are.
static func has_art(default_path: String) -> bool:
	return _file_exists(_art_path(default_path) if default_path.begins_with(DoorStyle.ART_DIR) else default_path)


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
	if style.is_cave() and not style.is_boss():
		return _paint_cave_frame(style)
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


## Placeholder cave mouth: the biome's arch on a rough rock lintel two tiles wide, the passage open.
static func _paint_cave_frame(style: DoorStyle) -> Image:
	var arch_style := _classic_style(style)
	var arch := paint_frame(arch_style)
	var image := _new_image(style.frame_size)
	var shift := (style.leaf_offset - arch_style.leaf_offset)
	for y in style.frame_size.y:
		for x in style.frame_size.x:
			var cx := float(style.frame_size.x - 1) * 0.5
			var outer := Vector2(x, y).distance_to(Vector2(cx, 26.0)) <= 30.0 + (_hash(x / 3, y / 3, 41) - 0.5) * 3.0
			if outer and y >= 2:
				image.set_pixel(x, y, _shade(style.stone_dark, (_hash(x / 2, y / 2, 42) - 0.5) * 0.2))
	image.blend_rect(arch, Rect2i(Vector2i.ZERO, arch.get_size()), shift)
	# The passage stays open (transparent) through the rock too.
	for y in range(style.leaf_offset.y - 4, style.frame_size.y):
		for x in range(style.leaf_offset.x + 1, style.leaf_offset.x + 31):
			var p := Vector2i(x, y) - shift
			if p.x >= 0 and p.y >= 0 and p.x < arch.get_width() and p.y < arch.get_height() and arch.get_pixelv(p).a < 0.1:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	_outline(image)
	return image


## The biome's door with an arch and a plain 32x32 leaf: placeholder base of side leaves and of
## the placeholder cave mouth.
static func _classic_style(style: DoorStyle) -> DoorStyle:
	var classic := DoorStyle.for_door(style.biome_id, style.kind, style.symbol)
	classic.gate = &""
	classic.leaf_size = Vector2i(32, 32)
	return classic


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
	if style.is_gate():
		return paint_gate_strip(style.gate)
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


## Placeholder gate (gates.json): 32x48 frames, frame 1 closed and flush like a piece of wall with a
## crown on top, frame 4 open. The slab sinks into the floor, the bars rise into the wall.
static func paint_gate_strip(gate: StringName) -> Image:
	var size := DoorStyle.GATE_SIZE
	var strip := _new_image(Vector2i(size.x * LEAF_FRAMES, size.y))
	for f in LEAF_FRAMES:
		var frame := _new_image(size)
		if gate == DoorStyle.GATE_BARS:
			_paint_gate_bars(frame, f)
		else:
			_paint_gate_slab(frame, f)
		strip.blit_rect(frame, Rect2i(Vector2i.ZERO, size), Vector2i(f * size.x, 0))
	return strip


## Stone block with a crown cap and brick courses; it sinks: frame f shows the top (48 - 16 f) px
## standing on the floor line, the last frame only a lip.
static func _paint_gate_slab(image: Image, frame: int) -> void:
	var size := image.get_size()
	var visible := [size.y, 30, 14, 3][frame] as int
	var top := size.y - visible
	for y in range(top, size.y):
		var src := y - top
		for x in size.x:
			var c := GATE_STONE_MID
			if src < 14:
				c = GATE_STONE_LIGHT if src < 2 else GATE_STONE_MID.lightened(0.08)
			else:
				var course := (src - 14) / 8
				var joint := (src - 14) % 8 == 7 or (x + (course % 2) * 8) % 16 == 0
				c = GATE_STONE_DARK if joint else GATE_STONE_MID
			if x == 0 or x == size.x - 1:
				c = OUTLINE
			image.set_pixel(x, y, c)
	for x in size.x:
		image.set_pixel(x, top, OUTLINE)


## Portcullis: iron grid over the dark passage, rising into the wall (the bottom row of spikes last).
static func _paint_gate_bars(image: Image, frame: int) -> void:
	var size := image.get_size()
	var lift := [0, 14, 28, 44][frame] as int
	for y in size.y:
		var src := y + lift
		if src >= size.y:
			break
		for x in size.x:
			var vertical := x % 7 == 3 or x % 7 == 4
			var horizontal := src % 12 == 5 or src % 12 == 6
			if vertical:
				image.set_pixel(x, y, METAL_MID if x % 7 == 3 else METAL_DARK)
			elif horizontal:
				image.set_pixel(x, y, METAL_DARK)
			elif src < 12:
				image.set_pixel(x, y, GATE_STONE_MID)


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

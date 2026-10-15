class_name WaterArt
extends RefCounted
## Organic water drawn per pixel (M1, playtest 15.10.2026: "no grid, organic puddles and pools"):
## pools of plan cell 'w' (ShallowWater) and the small puddles under drips (DecoProp) share one water
## palette per biome that matches the soft rock palette. The outline is no tile grid: it keeps a
## wavy inset from the water tiles (smooth value noise), rounds every outer corner wide and every
## inner corner soft. Inside: a light shore line, a darker rim, the body getting deeper towards the
## middle, a light reflection under the north shore, short ripples and glints that move over four
## frames (a slow shimmer). Collision and slowing stay on the tile grid (ShallowWater).
## Shapes come from the tiles and a seed derived from their position (never the dungeon RNG), so a
## template always looks the same. Built once per shape and cached.
## Until shallow_water_edge / puddle art is delivered (SPRITES_V9) this is the look.

## Water colours per biome (TESTWERTE, look): shore line, rim, body, deep middle, ripples, glints,
## reflection; alpha of the body (the floor shimmers through a little).
const PALETTES := {
	&"crypt": {"shore": Color("a9bcd8"), "rim": Color("27304a"), "body": Color("3d5174"), "deep": Color("2f3f5e"), "ripple": Color("6d86ad"), "glint": Color("e4eeff"), "reflect": Color("51688f")},
	&"slime_grotto": {"shore": Color("9fcfa2"), "rim": Color("173229"), "body": Color("2c5845"), "deep": Color("21463a"), "ripple": Color("5c9670"), "glint": Color("e2ffd8"), "reflect": Color("3d6e57")},
	&"shadow_realm": {"shore": Color("b49ae0"), "rim": Color("21173a"), "body": Color("3b2c61"), "deep": Color("2d2150"), "ripple": Color("6e57a6"), "glint": Color("f0e2ff"), "reflect": Color("4c3b7a")},
	&"ember_forge": {"shore": Color("c98a5a"), "rim": Color("171012"), "body": Color("2e2327"), "deep": Color("221a1d"), "ripple": Color("7a4b37"), "glint": Color("ffd08a"), "reflect": Color("4a3330")},
}
const DEFAULT_BIOME := &"crypt"
const BODY_ALPHA := 0.94
const TILE := 32
const FRAMES := 4
const FPS := 3.0
## Outline (art px, TESTWERTE, look): mean inset from the water tiles, noise amplitude and its
## wavelength, radius of outer corners, extra softness of inner corners.
const INSET := 5.0
const WOBBLE := 3.4
const WOBBLE_SCALE := 13.0
## A finer second wobble on top (amplitude, wavelength).
const RIPPLE_EDGE := 1.1
const RIPPLE_EDGE_SCALE := 4.5
const OUTER_RADIUS := 11.0
const INNER_RADIUS := 12.0
## Depth bands (art px from the outline): shore line, rim, then body; deep beyond DEEP_FROM.
const SHORE_WIDTH := 1.0
const RIM_WIDTH := 2.5
const DEEP_FROM := 9.0
## Ripples and glints per 100 water pixels (TESTWERTE, look).
const RIPPLES_PER_100 := 0.55
const GLINTS_PER_100 := 0.35
## Small puddle (DecoProp, one 32x32 frame, pivot (16, 18)): ellipse half axes and centre (art px).
const PUDDLE_CENTER := Vector2(16.0, 19.0)
const PUDDLE_RADII := Vector2(11.0, 7.0)

static var _cache: Dictionary[String, Texture2D] = {}


static func palette(biome_id: StringName) -> Dictionary:
	return PALETTES.get(biome_id, PALETTES[DEFAULT_BIOME])


## A pool over tiles (one connected area, layer cells): a strip of FRAMES frames, each as large as the
## tiles' bounding box (art px), to be drawn at the box's top-left tile.
static func pool_strip(tiles: Array[Vector2i], biome_id: StringName) -> Texture2D:
	var box := bounds(tiles)
	var key := "pool:%s:%s" % [biome_id, ",".join(tiles.map(func(t: Vector2i) -> String: return "%d.%d" % [t.x, t.y]))]
	if _cache.has(key):
		return _cache[key]
	var water: Dictionary[Vector2i, bool] = {}
	for tile in tiles:
		water[tile] = true
	var seed_value := seed_of(tiles)
	var size := box.size * TILE
	var depth := PackedFloat32Array()
	depth.resize(size.x * size.y)
	for y in size.y:
		for x in size.x:
			var point := Vector2(box.position * TILE) + Vector2(x + 0.5, y + 0.5)
			depth[y * size.x + x] = edge_distance(point, water) - wobble(point, seed_value)
	var texture := _paint(depth, size, biome_id, seed_value)
	_cache[key] = texture
	return texture


## A small round puddle in one 32 px frame (DecoProp item puddle, FRAMES frames).
static func puddle_strip(biome_id: StringName, seed_value: int) -> Texture2D:
	var key := "puddle:%s:%d" % [biome_id, seed_value % 8]
	if _cache.has(key):
		return _cache[key]
	var size := Vector2i(TILE, TILE)
	var depth := PackedFloat32Array()
	depth.resize(size.x * size.y)
	var shape_seed := seed_value % 8
	for y in size.y:
		for x in size.x:
			var point := Vector2(x + 0.5, y + 0.5)
			# Distance inside the ellipse (scaled to its small axis), wobbled inwards only.
			var local := (point - PUDDLE_CENTER) / PUDDLE_RADII
			var inside := (1.0 - local.length()) * PUDDLE_RADII.y
			depth[y * size.x + x] = inside - absf(wobble(point * 1.6, shape_seed)) * 0.6
	var texture := _paint(depth, size, biome_id, shape_seed)
	_cache[key] = texture
	return texture


## Smallest tile rectangle around tiles.
static func bounds(tiles: Array[Vector2i]) -> Rect2i:
	var low := tiles[0]
	var high := tiles[0]
	for tile in tiles:
		low = Vector2i(mini(low.x, tile.x), mini(low.y, tile.y))
		high = Vector2i(maxi(high.x, tile.x), maxi(high.y, tile.y))
	return Rect2i(low, high - low + Vector2i.ONE)


## Seed of a shape from its tiles (positions only: the same template always looks the same).
static func seed_of(tiles: Array[Vector2i]) -> int:
	var value := 17
	for tile in tiles:
		value = absi(value * 31 + tile.x * 7919 + tile.y * 104729) % 1000003
	return value


## Distance (art px) of a point inside the water tiles to the outline before the wobble: the inset
## from every open side, wide round outer corners, inner corners swung round in a wide arc.
## Negative = outside.
static func edge_distance(point: Vector2, water: Dictionary[Vector2i, bool]) -> float:
	var tile := Vector2i(floori(point.x / TILE), floori(point.y / TILE))
	if not water.has(tile):
		return -INSET
	# Inner corners: a tile corner with exactly one open tile around it. Near it the arc replaces the
	# inset from that open tile (the arc is tangent to both inset lines).
	var skipped := Vector2i(-99999, -99999)
	var result := 64.0
	for offset: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var corner := tile + offset
		var open: Array[Vector2i] = []
		for around: Vector2i in [corner + Vector2i(-1, -1), corner + Vector2i(0, -1), corner + Vector2i(-1, 0), corner]:
			if not water.has(around):
				open.append(around)
		if open.size() != 1:
			continue
		var side := Vector2(-1.0 if open[0].x < corner.x else 1.0, -1.0 if open[0].y < corner.y else 1.0)
		var center := Vector2(corner * TILE) + side * (INNER_RADIUS - INSET)
		if (point.x - center.x) * side.x < 0.0 and (point.y - center.y) * side.y < 0.0:
			skipped = open[0]
			result = minf(result, point.distance_to(center) - INNER_RADIUS)
	# Inset from every open tile around (sides and diagonals).
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var other := tile + Vector2i(dx, dy)
			if water.has(other) or other == skipped:
				continue
			var gap_x := maxf(maxf(float(other.x * TILE) - point.x, 0.0), point.x - float((other.x + 1) * TILE))
			var gap_y := maxf(maxf(float(other.y * TILE) - point.y, 0.0), point.y - float((other.y + 1) * TILE))
			result = minf(result, Vector2(gap_x, gap_y).length() - INSET)
	# Outer corners (both sides open): a wide arc.
	var local := point - Vector2(tile * TILE)
	for corner: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		if water.has(tile + Vector2i(corner.x, 0)) or water.has(tile + Vector2i(0, corner.y)):
			continue
		var reach := OUTER_RADIUS + INSET
		var center := Vector2(reach if corner.x < 0 else TILE - reach, reach if corner.y < 0 else TILE - reach)
		var beyond_x := local.x < center.x if corner.x < 0 else local.x > center.x
		var beyond_y := local.y < center.y if corner.y < 0 else local.y > center.y
		if beyond_x and beyond_y:
			result = minf(result, OUTER_RADIUS - local.distance_to(center))
	return result


## Wavy offset of the outline (art px): a slow wave plus a finer one, continuous over tiles.
static func wobble(point: Vector2, seed_value: int) -> float:
	return _noise(point / WOBBLE_SCALE, seed_value) * WOBBLE + _noise(point / RIPPLE_EDGE_SCALE, seed_value + 7) * RIPPLE_EDGE


## Smooth value noise in -1..1.
static func _noise(p: Vector2, seed_value: int) -> float:
	var cell := Vector2i(floori(p.x), floori(p.y))
	var f := p - Vector2(cell)
	var u := f * f * (Vector2(3, 3) - 2.0 * f)
	var a := _hash01(cell, seed_value)
	var b := _hash01(cell + Vector2i(1, 0), seed_value)
	var c := _hash01(cell + Vector2i(0, 1), seed_value)
	var d := _hash01(cell + Vector2i(1, 1), seed_value)
	var value := lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)
	return value * 2.0 - 1.0


static func _hash01(cell: Vector2i, seed_value: int) -> float:
	var h := absi(hash(Vector3i(cell.x, cell.y, seed_value)))
	return float(h % 10007) / 10006.0


## Colours from the depth field, then FRAMES frames of ripples and glints side by side.
static func _paint(depth: PackedFloat32Array, size: Vector2i, biome_id: StringName, seed_value: int) -> Texture2D:
	var colors := palette(biome_id)
	var base := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var water_pixels: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			var d := depth[y * size.x + x]
			if d <= 0.0:
				continue
			var color: Color
			if d <= SHORE_WIDTH:
				color = colors["shore"]
				color.a = 0.85
			elif d <= SHORE_WIDTH + RIM_WIDTH:
				color = colors["rim"]
				color.a = BODY_ALPHA
			else:
				var deep := clampf((d - DEEP_FROM) / 10.0, 0.0, 1.0)
				color = (colors["body"] as Color).lerp(colors["deep"], deep)
				color.a = BODY_ALPHA
				# Reflection of the north shore: a lighter band a little below it.
				if y >= 4 and _depth_at(depth, size, x, y - 4) <= SHORE_WIDTH + RIM_WIDTH and d < DEEP_FROM:
					color = color.lerp(colors["reflect"], 0.7)
				water_pixels.append(Vector2i(x, y))
			base.set_pixel(x, y, color)
	var strip := Image.create_empty(size.x * FRAMES, size.y, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	var ripples := maxi(1, int(water_pixels.size() * RIPPLES_PER_100 / 100.0))
	var glints := maxi(1, int(water_pixels.size() * GLINTS_PER_100 / 100.0))
	for frame in FRAMES:
		var image := base.duplicate() as Image
		if not water_pixels.is_empty():
			# Same ripples every frame, drifting one pixel to the east and back (a slow sway).
			rng.seed = seed_value
			var sway: int = [0, 1, 2, 1][frame]
			for i in ripples:
				var start: Vector2i = water_pixels[rng.randi() % water_pixels.size()]
				var length := 2 + rng.randi() % 3
				for k in length:
					var pixel := start + Vector2i(sway + k, 0)
					if _depth_at(depth, size, pixel.x, pixel.y) > SHORE_WIDTH + RIM_WIDTH:
						var ripple: Color = colors["ripple"]
						ripple.a = BODY_ALPHA
						image.set_pixelv(pixel, ripple)
			# Glints blink: each one lights up in one of the frames.
			rng.seed = seed_value * 3 + 1
			for i in glints:
				var pixel: Vector2i = water_pixels[rng.randi() % water_pixels.size()]
				if rng.randi() % FRAMES == frame:
					image.set_pixelv(pixel, colors["glint"])
		strip.blit_rect(image, Rect2i(Vector2i.ZERO, size), Vector2i(frame * size.x, 0))
	return ImageTexture.create_from_image(strip)


static func _depth_at(depth: PackedFloat32Array, size: Vector2i, x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= size.x or y >= size.y:
		return 0.0
	return depth[y * size.x + x]

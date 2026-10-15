class_name CampfireArt
extends RefCounted
## Art of the campfire room (docs/design/sprites/SPRITES_V4.md §5): loads art/environment/campfire/<name>.png and
## draws a simple pixel placeholder with the same size and frame layout until the file exists.
## Placeholders are drawn once per name with a fixed seed (pure optics, no dungeon RNG).

const ART_DIR := "res://art/environment/campfire/"
const FIRE := "campfire_6f"
const FIRE_FRAMES := 6
const FIRE_FRAME_SIZE := Vector2i(32, 32)
const LOG_SEAT := "log_seat"
const BEDROLL := "bedroll"
const PACK := "pack"
## Four 32x32 floor overlays per file that make the old biome's floor look like the next one.
const OVERLAY_PREFIX := "transition_overlay_"
const OVERLAY_TILES := 4

const OUTLINE := Color("#1c1a2b")
const WOOD_LIGHT := Color("#a8703f")
const WOOD := Color("#8a5a34")
const WOOD_DARK := Color("#5c3a24")
const STONE_LIGHT := Color("#9a94b5")
const STONE := Color("#7d7799")
const STONE_DARK := Color("#59547a")
const FLAME_CORE := Color("#fff1a8")
const FLAME_MID := Color("#f2cf4a")
const FLAME_OUTER := Color("#ff8a3c")
const FLAME_EDGE := Color("#e0463a")
## Overlay colours per next biome: [main, accent, small detail].
const OVERLAY_COLORS := {
	&"slime_grotto": [Color(0.29, 0.48, 0.23, 0.85), Color(0.43, 0.88, 0.43, 0.7), Color(0.75, 0.95, 0.55, 0.9)],
	&"shadow_realm": [Color(0.23, 0.16, 0.35, 0.85), Color(0.65, 0.43, 0.94, 0.75), Color(0.85, 0.7, 1.0, 0.9)],
	&"ember_forge": [Color(0.35, 0.33, 0.38, 0.8), Color(1.0, 0.54, 0.24, 0.8), Color(1.0, 0.85, 0.4, 0.9)],
	&"crypt": [Color(0.6, 0.58, 0.7, 0.6), Color(0.91, 0.89, 0.82, 0.85), Color(0.35, 0.33, 0.48, 0.8)],
}

static var _cache: Dictionary[String, Texture2D] = {}


## Delivered file or placeholder.
static func get_texture(art_name: String) -> Texture2D:
	if _cache.has(art_name):
		return _cache[art_name]
	var texture: Texture2D = null
	var path := ART_DIR + art_name + ".png"
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	if texture == null:
		texture = ImageTexture.create_from_image(_placeholder(art_name))
	_cache[art_name] = texture
	return texture


## Is the delivered file there (false = placeholder)?
static func has_file(art_name: String) -> bool:
	return ResourceLoader.exists(ART_DIR + art_name + ".png")


static func get_overlay_name(biome_id: StringName) -> String:
	return OVERLAY_PREFIX + String(biome_id)


static func _placeholder(art_name: String) -> Image:
	match art_name:
		FIRE:
			return _draw_fire()
		LOG_SEAT:
			return _draw_log()
		BEDROLL:
			return _draw_bedroll()
		PACK:
			return _draw_pack()
	if art_name.begins_with(OVERLAY_PREFIX):
		return _draw_overlay(StringName(art_name.trim_prefix(OVERLAY_PREFIX)))
	return Image.create(16, 16, false, Image.FORMAT_RGBA8)


# --- Placeholders (pixel art, outline #1c1a2b, pivot bottom centre) ---

static func _draw_fire() -> Image:
	var image := Image.create(FIRE_FRAME_SIZE.x * FIRE_FRAMES, FIRE_FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	for frame in FIRE_FRAMES:
		rng.seed = 4021 + frame * 17
		var ox := frame * FIRE_FRAME_SIZE.x
		# Ring of stones around the embers.
		for i in 10:
			var angle := TAU * float(i) / 10.0
			var center := Vector2(ox + 16 + cos(angle) * 11.0, 25 + sin(angle) * 4.0)
			_disc(image, center, 2.2, OUTLINE)
			_disc(image, center, 1.4, STONE if i % 3 else STONE_LIGHT)
			image.set_pixelv(Vector2i(center) + Vector2i(0, 1), STONE_DARK)
		# Glowing embers and two crossed logs.
		for x in range(9, 24):
			for y in range(23, 27):
				image.set_pixel(ox + x, y, FLAME_EDGE.darkened(0.3) if (x + y + frame) % 3 else FLAME_OUTER)
		_line(image, Vector2(ox + 9, 26), Vector2(ox + 22, 21), WOOD_DARK, 2)
		_line(image, Vector2(ox + 23, 26), Vector2(ox + 10, 21), WOOD, 2)
		# Flames: three tongues with a flickering height, hot core.
		for tongue in 3:
			var base_x := 12.0 + tongue * 4.0
			var height := 10.0 + rng.randf() * 6.0 + (4.0 if tongue == 1 else 0.0)
			var sway := rng.randf_range(-1.5, 1.5)
			for step in int(height):
				var y := 23 - step
				var k := float(step) / height
				var half := (1.0 - k) * (3.2 if tongue == 1 else 2.4)
				var cx := base_x + sway * k
				for x in range(int(cx - half - 1), int(cx + half + 2)):
					var d := absf(x - cx) / maxf(half, 0.5)
					var color := FLAME_EDGE if d > 0.85 else (FLAME_OUTER if d > 0.5 or k > 0.7 else (FLAME_MID if d > 0.2 or k > 0.4 else FLAME_CORE))
					if d <= 1.15 and y >= 0:
						image.set_pixel(ox + x, y, color)
		# Sparks.
		for spark in 2:
			image.set_pixel(ox + rng.randi_range(10, 22), rng.randi_range(1, 7), FLAME_MID)
	return image


static func _draw_log() -> Image:
	var image := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	_rect(image, Rect2i(2, 5, 27, 9), OUTLINE)
	_rect(image, Rect2i(3, 6, 25, 7), WOOD)
	_rect(image, Rect2i(3, 6, 25, 2), WOOD_LIGHT)
	for x in [8, 15, 21]:
		_rect(image, Rect2i(x, 8, 3, 1), WOOD_DARK)
	# Cut end with rings.
	_disc(image, Vector2(28, 9.5), 4.0, OUTLINE)
	_disc(image, Vector2(28, 9.5), 3.0, Color("#d8a868"))
	_disc(image, Vector2(28, 9.5), 1.6, WOOD_LIGHT)
	image.set_pixel(28, 9, WOOD_DARK)
	return image


static func _draw_bedroll() -> Image:
	var image := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	var cloth := Color("#7a3b3b")
	_rect(image, Rect2i(3, 4, 25, 10), OUTLINE)
	_rect(image, Rect2i(4, 5, 23, 8), cloth)
	_rect(image, Rect2i(4, 5, 23, 2), cloth.lightened(0.2))
	_disc(image, Vector2(4.5, 9), 4.5, OUTLINE)
	_disc(image, Vector2(4.5, 9), 3.5, cloth.lightened(0.1))
	_disc(image, Vector2(4.5, 9), 1.8, cloth.darkened(0.3))
	for x in [11, 21]:
		_rect(image, Rect2i(x, 4, 2, 10), WOOD_DARK)
		image.set_pixel(x, 9, Color("#c9b27a"))
	return image


static func _draw_pack() -> Image:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	_disc(image, Vector2(8, 10), 5.5, OUTLINE)
	_disc(image, Vector2(8, 10), 4.5, WOOD_LIGHT)
	_rect(image, Rect2i(4, 5, 8, 4), OUTLINE)
	_rect(image, Rect2i(5, 6, 6, 3), WOOD)
	_rect(image, Rect2i(7, 8, 2, 6), WOOD_DARK)
	return image


## Four 32x32 floor patches in the next biome's colours: blotches, cracks and a few dots.
static func _draw_overlay(biome_id: StringName) -> Image:
	var image := Image.create(32 * OVERLAY_TILES, 32, false, Image.FORMAT_RGBA8)
	var colors: Array = OVERLAY_COLORS.get(biome_id, OVERLAY_COLORS[&"slime_grotto"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(biome_id)
	for tile in OVERLAY_TILES:
		var ox := tile * 32
		for blob in rng.randi_range(2, 4):
			var center := Vector2(ox + rng.randf_range(8, 24), rng.randf_range(8, 24))
			var radius := rng.randf_range(2.5, 6.0)
			_disc(image, center, radius, colors[0])
			_disc(image, center + Vector2(-1, -1), radius * 0.5, colors[1])
		var start := Vector2(ox + rng.randf_range(4, 28), rng.randf_range(4, 28))
		for segment in 3:
			var end := start + Vector2(rng.randf_range(-7, 7), rng.randf_range(-7, 7))
			end = Vector2(clampf(end.x, ox + 1, ox + 30), clampf(end.y, 1, 30))
			_line(image, start, end, colors[1], 1)
			start = end
		for dot in 4:
			image.set_pixel(ox + rng.randi_range(2, 29), rng.randi_range(2, 29), colors[2])
	return image


static func _rect(image: Image, rect: Rect2i, color: Color) -> void:
	image.fill_rect(rect.intersection(Rect2i(Vector2i.ZERO, image.get_size())), color)


static func _disc(image: Image, center: Vector2, radius: float, color: Color) -> void:
	var size := image.get_size()
	for y in range(floori(center.y - radius), ceili(center.y + radius) + 1):
		for x in range(floori(center.x - radius), ceili(center.x + radius) + 1):
			if x < 0 or y < 0 or x >= size.x or y >= size.y:
				continue
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= radius:
				image.set_pixel(x, y, color)


static func _line(image: Image, from: Vector2, to: Vector2, color: Color, width: int) -> void:
	var steps := maxi(1, ceili(from.distance_to(to)))
	var size := image.get_size()
	for i in steps + 1:
		var point := Vector2i(from.lerp(to, float(i) / steps))
		for w in width:
			var pixel := point + Vector2i(0, w)
			if pixel.x >= 0 and pixel.y >= 0 and pixel.x < size.x and pixel.y < size.y:
				image.set_pixelv(pixel, color)

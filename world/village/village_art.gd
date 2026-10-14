class_name VillageArt
extends RefCounted
## Village decoration art (B3, docs/SPRITES_V4.md): loads art/environment/village/<name>.png and
## the villager/animal strips in art/characters/npcs/ as soon as the files exist. Until then simple
## props get a pixel placeholder in the palette (flowers, grass, stones, bush, stump, garden fence,
## flower bed, hay bale, bench, signpost, pond, chicken); the rest (cart, cat) has none and stays
## away (VillageProp/Villager free themselves). All art is drawn at SCALE like the village.

const DIR := "res://art/environment/village/"
const NPC_DIR := "res://art/characters/npcs/"
const TILESET := "res://art/environment/tiles/village_tileset.png"
const SCALE := 2.0

## Placeholder regions in village_tileset.png (bush, stump, a fence piece without the grass).
const TILE_REGIONS := {
	"bush_small": Rect2i(32, 64, 32, 32),
	"stump": Rect2i(64, 64, 32, 32),
	"garden_fence": Rect2i(224, 39, 32, 22),
}
## Palette colours (docs/HANDOUT.md) for the drawn placeholders.
const OUTLINE := Color("#1c1a2b")
const GRASS_DARK := Color("#4a7a3a")
const GRASS_LIGHT := Color("#6ea455")
const LEAF := Color("#2f944c")
const SOIL := Color("#5c3a24")
const SOIL_LIGHT := Color("#8a5a34")
const WOOD := Color("#a8703f")
const WOOD_MID := Color("#8a5a34")
const WOOD_DARK := Color("#5c3a24")
const STONE := Color("#9a94b5")
const STONE_MID := Color("#7d7799")
const STONE_DARK := Color("#59547a")
const HAY := Color("#e0b84a")
const HAY_DARK := Color("#c99a2e")
const HAY_LIGHT := Color("#f2cf4a")
const WATER := Color("#2a6cb0")
const WATER_MID := Color("#3690da")
const WATER_LIGHT := Color("#6cb2ec")
const FEATHER := Color("#e9e4d2")
const FEATHER_DARK := Color("#b8b09a")
const COMB := Color("#e0463a")
const BEAK := Color("#ff8a3c")
const BLOSSOMS: Array[Color] = [Color("#f0648c"), Color("#f2cf4a"), Color("#e9e4d2"), Color("#a66ef0"), Color("#6cb2ec"), Color("#ff8a3c")]
## Fixed seed for the drawn placeholders: they look the same on every start.
const PLACEHOLDER_SEED := 4021

static var _cache: Dictionary = {}


## Texture for a decoration name: the real file if it exists, else a placeholder (null if there is
## none for this name).
static func get_texture(art_name: String) -> Texture2D:
	if _cache.has(art_name):
		return _cache[art_name]
	var texture: Texture2D = null
	if has_art(art_name):
		texture = load(DIR + art_name + ".png") as Texture2D
	else:
		texture = make_placeholder(art_name)
	_cache[art_name] = texture
	return texture


static func has_art(art_name: String) -> bool:
	return ResourceLoader.exists(DIR + art_name + ".png")


## Frames for a villager or animal from art/characters/npcs/<name>_idle_<n>f.png and
## <name>_walk_<n>f.png (square frames, size from the strip height). Without the idle strip: a
## one-frame placeholder for simple animals (chicken), else null.
## Sprite offset (art px, sprite centred) that puts the lowest opaque row of the first idle frame on
## the node's feet line. Measured instead of assumed: not every figure stands on row 29 of its frame
## (the chronicler ends on row 26 and would float otherwise).
static func feet_offset_y(frames: SpriteFrames) -> float:
	var animation := &"idle" if frames != null and frames.has_animation(&"idle") else &"default"
	var texture := frames.get_frame_texture(animation, 0) if frames != null and frames.has_animation(animation) else null
	if texture == null:
		return -14.0
	var image := texture.get_image()
	var lowest := image.get_height() - 3
	for y in range(image.get_height() - 1, -1, -1):
		var found := false
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				found = true
				break
		if found:
			lowest = y
			break
	return -(lowest + 1 - image.get_height() * 0.5)


static func get_character_frames(art_name: String) -> SpriteFrames:
	var key := "npc:" + art_name
	if _cache.has(key):
		return _cache[key]
	var frames: SpriteFrames = null
	var idle := _find_strip(art_name, "idle")
	if not idle.is_empty():
		var texture := load(idle) as Texture2D
		var size := Vector2i(texture.get_height(), texture.get_height())
		frames = SpriteStrip.make_frames(texture, size, 4.0, true, &"idle")
		var walk := _find_strip(art_name, "walk")
		if not walk.is_empty():
			SpriteStrip.add_strip(frames, &"walk", load(walk) as Texture2D, size, 8.0, true)
	elif art_name == "chicken":
		frames = SpriteFrames.new()
		frames.rename_animation(&"default", &"idle")
		frames.add_frame(&"idle", _chicken())
	_cache[key] = frames
	return frames


## True once the real strips exist (not the placeholder).
static func has_character_art(art_name: String) -> bool:
	return not _find_strip(art_name, "idle").is_empty()


static func _find_strip(art_name: String, animation: String) -> String:
	for count in range(2, 9):
		var path := "%s%s_%s_%df.png" % [NPC_DIR, art_name, animation, count]
		if ResourceLoader.exists(path):
			return path
	return ""


## Pixel placeholder for simple decoration; null for everything that needs real art.
static func make_placeholder(art_name: String) -> Texture2D:
	if TILE_REGIONS.has(art_name):
		return _from_tileset(TILE_REGIONS[art_name])
	var rng := RandomNumberGenerator.new()
	rng.seed = PLACEHOLDER_SEED + art_name.hash()
	match art_name:
		"flowers_1", "flowers_2", "flowers_3":
			return _flowers(rng, int(art_name.right(1)))
		"grass_tuft":
			return _grass_tuft(rng)
		"stones":
			return _stones(rng)
		"flower_bed":
			return _flower_bed(rng)
		"hay_bale":
			return _hay_bale()
		"bench":
			return _bench()
		"signpost":
			return _signpost()
		"pond":
			return _pond(rng)
	return null


## Tile region without its grass: flood fill from the border over everything that is not the dark
## outline makes the background transparent, the outlined prop stays.
static func _from_tileset(region: Rect2i) -> Texture2D:
	var sheet := load(TILESET) as Texture2D
	if sheet == null:
		return null
	var full := sheet.get_image()
	if full == null:
		return null
	if full.is_compressed():
		full.decompress()
	full.convert(Image.FORMAT_RGBA8)
	var image := full.get_region(region)
	var size := image.get_size()
	var open: Array[Vector2i] = []
	var seen := {}
	for x in size.x:
		open.append(Vector2i(x, 0))
		open.append(Vector2i(x, size.y - 1))
	for y in size.y:
		open.append(Vector2i(0, y))
		open.append(Vector2i(size.x - 1, y))
	while not open.is_empty():
		var cell: Vector2i = open.pop_back()
		if seen.has(cell) or cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
			continue
		seen[cell] = true
		if not _is_grass(image.get_pixelv(cell)):
			continue
		image.set_pixelv(cell, Color(0, 0, 0, 0))
		for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			open.append(cell + step)
	return ImageTexture.create_from_image(image)


## Grass pixels of the village tileset: clearly green, not the dark outline.
static func _is_grass(color: Color) -> bool:
	return color.a > 0.5 and color.g > color.r and color.g > color.b and color.get_luminance() > 0.25


## 1 px outline (palette) around everything drawn so far.
static func _outline(image: Image) -> void:
	var size := image.get_size()
	var edge: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			if image.get_pixel(x, y).a > 0.0:
				continue
			for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var other := Vector2i(x, y) + step
				if other.x >= 0 and other.y >= 0 and other.x < size.x and other.y < size.y and image.get_pixelv(other).a > 0.0 and image.get_pixelv(other) != OUTLINE:
					edge.append(Vector2i(x, y))
					break
	for cell in edge:
		image.set_pixelv(cell, OUTLINE)


static func _ellipse(image: Image, centre: Vector2, radius: Vector2, color: Color) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var d := (Vector2(x + 0.5, y + 0.5) - centre) / radius
			if d.length_squared() <= 1.0:
				image.set_pixel(x, y, color)


static func _flowers(rng: RandomNumberGenerator, variant: int) -> Texture2D:
	var image := Image.create(20, 14, false, Image.FORMAT_RGBA8)
	var count := 4 + variant
	var hue := BLOSSOMS[(variant * 2 + rng.randi_range(0, 1)) % BLOSSOMS.size()]
	# Leaves first, blossoms on top.
	for i in 5:
		var x := rng.randi_range(2, 17)
		image.set_pixel(x, 12, LEAF)
		image.set_pixel(x + 1, 11, GRASS_DARK)
	for i in count:
		var x := rng.randi_range(2, 17)
		var y := rng.randi_range(3, 9)
		for stem in range(y + 1, 13):
			image.set_pixel(x, stem, LEAF if stem > y + 2 else GRASS_DARK)
		var blossom := hue if rng.randf() < 0.7 else BLOSSOMS[rng.randi_range(0, BLOSSOMS.size() - 1)]
		image.set_pixel(x, y, Color("#ffd166") if blossom != BLOSSOMS[1] else BLOSSOMS[5])
		image.set_pixel(x - 1, y, blossom)
		image.set_pixel(x + 1, y, blossom)
		image.set_pixel(x, y - 1, blossom.lightened(0.2))
		image.set_pixel(x, y + 1, blossom.darkened(0.25))
	return ImageTexture.create_from_image(image)


static func _grass_tuft(rng: RandomNumberGenerator) -> Texture2D:
	var image := Image.create(14, 9, false, Image.FORMAT_RGBA8)
	for i in 7:
		var x := rng.randi_range(1, 12)
		var height := rng.randi_range(3, 7)
		for y in range(9 - height, 9):
			image.set_pixel(x, y, GRASS_DARK if y > 9 - height else LEAF)
		if rng.randf() < 0.5:
			image.set_pixel(x + 1, 8 - (height >> 1), GRASS_LIGHT)
	return ImageTexture.create_from_image(image)


static func _stones(rng: RandomNumberGenerator) -> Texture2D:
	var image := Image.create(16, 10, false, Image.FORMAT_RGBA8)
	var stones := [Rect2i(2, 4, 6, 5), Rect2i(9, 5, 4, 4)]
	if rng.randf() < 0.5:
		stones.append(Rect2i(7, 2, 3, 3))
	for rect: Rect2i in stones:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var edge := x == rect.position.x or x == rect.end.x - 1 or y == rect.position.y or y == rect.end.y - 1
				var corner := (x == rect.position.x or x == rect.end.x - 1) and (y == rect.position.y or y == rect.end.y - 1)
				if corner:
					continue
				var color := OUTLINE if edge else (STONE if y < rect.position.y + 2 else STONE_MID)
				if not edge and y == rect.end.y - 2:
					color = STONE_DARK
				image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


static func _flower_bed(rng: RandomNumberGenerator) -> Texture2D:
	var image := Image.create(32, 14, false, Image.FORMAT_RGBA8)
	for y in range(4, 14):
		for x in 32:
			var edge := x == 0 or x == 31 or y == 4 or y == 13
			image.set_pixel(x, y, OUTLINE if edge else (SOIL_LIGHT if y == 5 else SOIL))
	for i in 9:
		var x := 2 + i * 3 + rng.randi_range(0, 1)
		var y := rng.randi_range(2, 7)
		var blossom := BLOSSOMS[rng.randi_range(0, BLOSSOMS.size() - 1)]
		image.set_pixel(x, y + 2, LEAF)
		image.set_pixel(x, y + 1, LEAF)
		image.set_pixel(x, y, blossom)
		image.set_pixel(x + 1, y, blossom.darkened(0.2))
	return ImageTexture.create_from_image(image)


static func _hay_bale() -> Texture2D:
	var image := Image.create(24, 18, false, Image.FORMAT_RGBA8)
	for y in range(2, 17):
		for x in range(1, 23):
			if (x == 1 or x == 22) and (y == 2 or y == 16):
				continue
			var color := HAY_LIGHT if y < 5 else (HAY_DARK if y > 13 else HAY)
			if x % 5 == 0 and y > 4:
				color = HAY_DARK
			image.set_pixel(x, y, color)
	for x in range(1, 23):
		image.set_pixel(x, 9, WOOD_MID)
	_outline(image)
	return ImageTexture.create_from_image(image)


static func _bench() -> Texture2D:
	var image := Image.create(28, 16, false, Image.FORMAT_RGBA8)
	for x in range(1, 27):
		for y in range(2, 5):
			image.set_pixel(x, y, WOOD if y < 4 else WOOD_MID)
		for y in range(7, 10):
			image.set_pixel(x, y, WOOD if y < 9 else WOOD_MID)
	for leg in [3, 23]:
		for y in range(5, 15):
			image.set_pixel(leg, y, WOOD_DARK)
			image.set_pixel(leg + 1, y, WOOD_DARK)
	_outline(image)
	return ImageTexture.create_from_image(image)


static func _signpost() -> Texture2D:
	var image := Image.create(24, 30, false, Image.FORMAT_RGBA8)
	for y in range(3, 29):
		image.set_pixel(11, y, WOOD_MID)
		image.set_pixel(12, y, WOOD_DARK)
	# Board to the left (Dorf) and one to the right (Dungeon), arrow tips.
	for y in range(5, 10):
		for x in range(2, 13):
			image.set_pixel(x, y, WOOD if y < 9 else WOOD_MID)
	for y in range(12, 17):
		for x in range(11, 22):
			image.set_pixel(x, y, WOOD if y < 16 else WOOD_MID)
	image.set_pixel(1, 7, WOOD)
	image.set_pixel(22, 14, WOOD)
	for x in range(4, 11, 2):
		image.set_pixel(x, 7, WOOD_DARK)
	for x in range(13, 20, 2):
		image.set_pixel(x, 14, WOOD_DARK)
	_outline(image)
	return ImageTexture.create_from_image(image)


static func _pond(rng: RandomNumberGenerator) -> Texture2D:
	var image := Image.create(56, 30, false, Image.FORMAT_RGBA8)
	var centre := Vector2(28, 15)
	_ellipse(image, centre, Vector2(26.5, 13.5), STONE_MID)
	_ellipse(image, centre, Vector2(24.5, 11.5), WATER)
	_ellipse(image, centre + Vector2(0, 1), Vector2(22, 9.5), WATER_MID)
	for i in 6:
		var x := rng.randi_range(12, 42)
		var y := rng.randi_range(10, 20)
		for dx in 4:
			image.set_pixel(x + dx, y, WATER_LIGHT)
	# Rim stones and two lily pads.
	for i in 10:
		var angle := TAU * i / 10.0 + rng.randf_range(-0.2, 0.2)
		var spot := centre + Vector2(cos(angle) * 25.5, sin(angle) * 12.5)
		image.set_pixel(int(spot.x), int(spot.y), STONE)
		image.set_pixel(int(spot.x) + 1, int(spot.y), STONE_DARK)
	for pad: Vector2i in [Vector2i(18, 12), Vector2i(36, 17)]:
		_ellipse(image, Vector2(pad), Vector2(2.6, 1.6), LEAF)
	image.set_pixel(37, 16, BLOSSOMS[0])
	_outline(image)
	return ImageTexture.create_from_image(image)


static func _chicken() -> Texture2D:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	_ellipse(image, Vector2(7, 10.5), Vector2(4.5, 3.5), FEATHER)
	_ellipse(image, Vector2(11, 6.5), Vector2(2.2, 2.4), FEATHER)
	for x in range(4, 8):
		image.set_pixel(x, 12, FEATHER_DARK)
	image.set_pixel(3, 8, FEATHER)
	image.set_pixel(2, 7, FEATHER_DARK)
	image.set_pixel(11, 3, COMB)
	image.set_pixel(12, 4, COMB)
	image.set_pixel(13, 6, BEAK)
	image.set_pixel(14, 6, BEAK)
	image.set_pixel(12, 9, COMB)
	image.set_pixel(6, 14, BEAK)
	image.set_pixel(8, 14, BEAK)
	_outline(image)
	image.set_pixel(11, 6, OUTLINE)
	return ImageTexture.create_from_image(image)

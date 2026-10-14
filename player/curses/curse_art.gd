class_name CurseArt
extends RefCounted
## Curse symbols for the pact altar and the Tab overview (docs/SPRITES_V5.md §4): one strip of
## 16x16 symbols in PlayerCurses.Curse order (-1 max heart, faster enemies, smaller light circle,
## fountains heal half). Loads art/environment/trials/curse_icons.png, until then a drawn
## placeholder of the same layout (pure optics, fixed shapes, no RNG).

const PATH := "res://art/environment/trials/curse_icons.png"
const ICON_SIZE := 16
const ICON_COUNT := 4

const OUTLINE := Color("#1c1a2b")
const HEART := Color("#e0463a")
const HEART_LIGHT := Color("#ff8a80")
const CURSE := Color("#a66ef0")
const CURSE_LIGHT := Color("#dcbcff")
const METAL := Color("#7d7799")
const GLOW := Color("#f2cf4a")
const WATER := Color("#6cb2ec")
const STONE := Color("#9a94b5")

static var _strip: Texture2D = null
static var _icons: Dictionary[int, Texture2D] = {}


static func get_strip() -> Texture2D:
	if _strip == null:
		if ResourceLoader.exists(PATH):
			_strip = load(PATH) as Texture2D
		if _strip == null:
			_strip = ImageTexture.create_from_image(_draw_placeholder())
	return _strip


## Symbol of one curse (AtlasTexture on the strip).
static func get_icon(curse: int) -> Texture2D:
	if _icons.has(curse):
		return _icons[curse]
	var atlas := AtlasTexture.new()
	atlas.atlas = get_strip()
	atlas.region = Rect2(clampi(curse, 0, ICON_COUNT - 1) * ICON_SIZE, 0, ICON_SIZE, ICON_SIZE)
	_icons[curse] = atlas
	return atlas


static func has_file() -> bool:
	return ResourceLoader.exists(PATH)


static func _draw_placeholder() -> Image:
	var image := Image.create(ICON_SIZE * ICON_COUNT, ICON_SIZE, false, Image.FORMAT_RGBA8)
	_draw_broken_heart(image, 0)
	_draw_fast_enemy(image, ICON_SIZE)
	_draw_dark_lantern(image, ICON_SIZE * 2)
	_draw_dry_fountain(image, ICON_SIZE * 3)
	return image


static func _draw_broken_heart(image: Image, ox: int) -> void:
	for y in range(3, 14):
		for x in range(1, 15):
			var p := Vector2(x - 7.5, y - 6.5)
			var lobe := minf(Vector2(p.x + 3.0, p.y + 1.0).length(), Vector2(p.x - 3.0, p.y + 1.0).length()) < 3.6
			var point := p.y >= -1.0 and absf(p.x) <= 6.6 - (p.y + 1.0) * 0.9
			if lobe or point:
				image.set_pixel(ox + x, y, HEART if p.y > -2.0 else HEART_LIGHT)
	_outline(image, ox)
	# Crack down the middle.
	for step in 9:
		var x := 7 + (1 if step % 3 == 1 else 0) - (1 if step % 3 == 2 else 0)
		image.set_pixel(ox + x, 3 + step, OUTLINE)


static func _draw_fast_enemy(image: Image, ox: int) -> void:
	for y in range(4, 14):
		for x in range(6, 15):
			var p := Vector2(x - 10.0, y - 9.0)
			if p.length() < 4.6:
				image.set_pixel(ox + x, y, CURSE if p.y > -2.0 else CURSE_LIGHT)
	_outline(image, ox)
	image.set_pixel(ox + 11, 8, GLOW)
	image.set_pixel(ox + 13, 8, GLOW)
	# Speed lines behind it.
	for row in [6, 9, 12]:
		for x in range(1, 5):
			if x != 2 or row == 9:
				image.set_pixel(ox + x, row, CURSE_LIGHT)


static func _draw_dark_lantern(image: Image, ox: int) -> void:
	for y in range(5, 14):
		for x in range(4, 12):
			var edge := x == 4 or x == 11 or y == 5 or y == 13
			image.set_pixel(ox + x, y, METAL if edge else Color("#2a2540"))
	for x in range(6, 10):
		image.set_pixel(ox + x, 3, METAL)
	image.set_pixel(ox + 6, 4, METAL)
	image.set_pixel(ox + 9, 4, METAL)
	# A tiny dying flame and a slash.
	image.set_pixel(ox + 8, 10, GLOW.darkened(0.5))
	image.set_pixel(ox + 8, 11, GLOW.darkened(0.3))
	_outline(image, ox)
	for step in 13:
		image.set_pixel(ox + 1 + step, 14 - step, HEART)


static func _draw_dry_fountain(image: Image, ox: int) -> void:
	for y in range(9, 14):
		for x in range(2, 14):
			image.set_pixel(ox + x, y, STONE if y > 9 else STONE.lightened(0.2))
	for y in range(4, 9):
		image.set_pixel(ox + 7, y, STONE)
		image.set_pixel(ox + 8, y, STONE)
	# Half a drop: left side water, right side empty outline.
	for y in range(1, 7):
		for x in range(10, 15):
			var p := Vector2(x - 12.0, y - 4.5)
			if p.length() < 2.2 or (p.y < 0.0 and absf(p.x) < (p.y + 3.5) * 0.6):
				image.set_pixel(ox + x, y, WATER if x <= 12 else Color(0, 0, 0, 0))
	_outline(image, ox)


## 1 px outline around every opaque pixel of one icon.
static func _outline(image: Image, ox: int) -> void:
	var border: Array[Vector2i] = []
	for y in ICON_SIZE:
		for x in ICON_SIZE:
			if image.get_pixel(ox + x, y).a > 0.0:
				continue
			for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n := Vector2i(x, y) + offset
				if n.x >= 0 and n.y >= 0 and n.x < ICON_SIZE and n.y < ICON_SIZE and image.get_pixel(ox + n.x, n.y).a > 0.0 and image.get_pixel(ox + n.x, n.y) != OUTLINE:
					border.append(Vector2i(x, y))
					break
	for pixel in border:
		image.set_pixel(ox + pixel.x, pixel.y, OUTLINE)

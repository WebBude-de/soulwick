class_name IngredientArt
extends RefCounted
## Art of the room ingredients (docs/SPRITES_V5.md §1, art/environment/rooms/). A delivered file
## with the agreed name is used as it is; until then a small pixel placeholder of the same size is
## drawn here, so the ingredients work and the art drops in without code changes
## (after `godot --headless --path . --import`).

const ART_DIR := "res://art/environment/rooms/"
## Frame sizes in art pixels (SPRITES_V5 §1).
const CRYSTAL_FRAME := Vector2i(32, 32)
const TORCH_STAND_FRAME := Vector2i(16, 40)
const BARREL_FRAME := Vector2i(32, 32)
const CHEST_FRAME := Vector2i(32, 32)
const FRAMES := 4

const STONE := Color(0.32, 0.31, 0.36)
const STONE_LIGHT := Color(0.46, 0.45, 0.5)
const STONE_DARK := Color(0.18, 0.17, 0.22)
const IRON := Color(0.22, 0.22, 0.26)
const IRON_LIGHT := Color(0.42, 0.42, 0.48)
const WOOD := Color(0.45, 0.28, 0.14)
const WOOD_DARK := Color(0.28, 0.16, 0.08)
const GOLD := Color(0.95, 0.78, 0.28)
const BARREL_RED := Color(0.66, 0.14, 0.1)
const BARREL_RED_DARK := Color(0.4, 0.07, 0.06)
const WARNING := Color(0.98, 0.82, 0.2)
const FLAME := Color(1.0, 0.62, 0.18)
const FLAME_CORE := Color(1.0, 0.92, 0.55)
const OUTLINE := Color(0.06, 0.05, 0.08)

static var _cache: Dictionary[String, Texture2D] = {}


## Texture for file_name (without .png): the delivered file or a placeholder.
static func get_texture(file_name: String) -> Texture2D:
	if _cache.has(file_name):
		return _cache[file_name]
	var path := ART_DIR + file_name + ".png"
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	if texture == null:
		texture = ImageTexture.create_from_image(make_placeholder(file_name))
	_cache[file_name] = texture
	return texture


static func has_file(file_name: String) -> bool:
	return ResourceLoader.exists(ART_DIR + file_name + ".png")


## Placeholder image in the size of the briefing (an empty 32x32 for unknown names).
static func make_placeholder(file_name: String) -> Image:
	match file_name:
		"light_crystal_4f":
			return _strip(CRYSTAL_FRAME, _draw_crystal)
		"torch_stand_4f":
			return _strip(TORCH_STAND_FRAME, _draw_torch_stand)
		"explosive_barrel":
			var barrel := _blank(BARREL_FRAME)
			_draw_barrel(barrel, 0, 0, false)
			return barrel
		"explosive_barrel_fuse_4f":
			return _strip(BARREL_FRAME, func(image: Image, x0: int, frame: int) -> void: _draw_barrel(image, x0, frame, true))
		"chest_closed":
			var chest := _blank(CHEST_FRAME)
			_draw_chest(chest, 0, 0)
			return chest
		"chest_open_4f":
			return _strip(CHEST_FRAME, _draw_chest)
	return _blank(Vector2i(32, 32))


static func _blank(size: Vector2i) -> Image:
	return Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)


## FRAMES frames side by side; draw(image, frame_x, frame) paints one frame.
static func _strip(frame: Vector2i, draw: Callable) -> Image:
	var image := _blank(Vector2i(frame.x * FRAMES, frame.y))
	for i in FRAMES:
		draw.call(image, i * frame.x, i)
	return image


static func _rect(image: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	image.fill_rect(Rect2i(x, y, w, h).intersection(Rect2i(Vector2i.ZERO, image.get_size())), color)


## Crystal on a stone pedestal, pulsing brightness (tinted per biome in the game).
static func _draw_crystal(image: Image, x0: int, frame: int) -> void:
	_rect(image, x0 + 8, 25, 16, 6, STONE)
	_rect(image, x0 + 8, 25, 16, 1, STONE_LIGHT)
	_rect(image, x0 + 7, 30, 18, 2, STONE_DARK)
	var glow := 0.78 + 0.22 * sin(float(frame) / FRAMES * TAU)
	var body := Color(0.75 * glow, 0.98 * glow, 1.0 * glow)
	var edge := Color(0.4, 0.7, 0.8)
	for y in range(5, 25):
		var half := 6 - absi(y - 15) * 6 / 10
		if half <= 0:
			continue
		_rect(image, x0 + 16 - half, y, half * 2, 1, body)
		image.set_pixel(x0 + 16 - half, y, edge)
		image.set_pixel(x0 + 15 + half, y, edge)
	_rect(image, x0 + 14, 10, 2, 8, Color(1, 1, 1, glow))


## Iron pole with a fire bowl; the flame flickers.
static func _draw_torch_stand(image: Image, x0: int, frame: int) -> void:
	_rect(image, x0 + 4, 37, 8, 3, IRON)
	_rect(image, x0 + 7, 13, 2, 25, IRON)
	_rect(image, x0 + 7, 13, 1, 25, IRON_LIGHT)
	_rect(image, x0 + 3, 11, 10, 3, IRON)
	_rect(image, x0 + 3, 11, 10, 1, IRON_LIGHT)
	var heights: Array[int] = [8, 10, 7, 9]
	var top := 11 - heights[frame]
	_rect(image, x0 + 4, top + 2, 8, heights[frame] - 2, FLAME)
	_rect(image, x0 + 5 + frame % 2, top, 4, 3, FLAME)
	_rect(image, x0 + 6, top + 4, 4, heights[frame] - 5, FLAME_CORE)


## Red barrel with iron hoops and a yellow warning sign; the fuse frames spark and swell.
static func _draw_barrel(image: Image, x0: int, frame: int, fuse: bool) -> void:
	var swell := frame / 2 if fuse else 0
	var left := x0 + 8 - swell
	var width := 16 + swell * 2
	_rect(image, left, 9, width, 21, BARREL_RED if not fuse or frame % 2 == 0 else Color(0.85, 0.25, 0.12))
	_rect(image, left, 9, 2, 21, BARREL_RED_DARK)
	_rect(image, left + width - 2, 9, 2, 21, BARREL_RED_DARK)
	_rect(image, left, 7, width, 3, Color(0.5, 0.1, 0.08))
	for hoop_y in [12, 26]:
		_rect(image, left, hoop_y, width, 2, IRON)
	# Warning triangle.
	for row in 7:
		_rect(image, x0 + 16 - row / 2 - 1, 15 + row, row + 2, 1, WARNING)
	_rect(image, x0 + 15, 17, 2, 3, OUTLINE)
	_rect(image, x0 + 15, 21, 2, 1, OUTLINE)
	# Fuse on the lid.
	_rect(image, x0 + 19, 4, 1, 4, IRON_LIGHT)
	if fuse:
		var spark := Vector2i(x0 + 19 + (frame % 3) - 1, 2 + frame % 2)
		_rect(image, spark.x - 1, spark.y - 1, 3, 3, FLAME)
		image.set_pixel(spark.x, spark.y, FLAME_CORE)


## Wooden chest with an iron band and a gold lock; frames 1-3 lift the lid and let gold shine.
static func _draw_chest(image: Image, x0: int, frame: int) -> void:
	_rect(image, x0 + 5, 16, 22, 13, WOOD)
	_rect(image, x0 + 5, 28, 22, 2, WOOD_DARK)
	_rect(image, x0 + 5, 16, 2, 13, IRON)
	_rect(image, x0 + 25, 16, 2, 13, IRON)
	var lift := frame * 3
	if frame > 0:
		_rect(image, x0 + 7, 15, 18, 3, GOLD)
		_rect(image, x0 + 9, 14 - frame, 14, frame + 1, Color(1.0, 0.9, 0.5, 0.7))
	_rect(image, x0 + 5, 9 - lift, 22, 7, WOOD_DARK if frame > 0 else WOOD)
	_rect(image, x0 + 5, 9 - lift, 22, 1, Color(0.6, 0.4, 0.2))
	_rect(image, x0 + 5, 9 - lift, 2, 7, IRON)
	_rect(image, x0 + 25, 9 - lift, 2, 7, IRON)
	if frame == 0:
		_rect(image, x0 + 14, 14, 4, 5, GOLD)
		image.set_pixel(x0 + 15, 16, OUTLINE)

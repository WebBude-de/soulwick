class_name HomeArt
extends RefCounted
## Pictures of the home interior (SPRITES_V13 §B6, art/environment/home/): the interior tiles
## (home_interior_tiles.json, regions by name) and the furniture strips (home_props.json: frame size,
## frames, fps, pivot). Antwort 20 §1 furniture that is not delivered yet (nightstand, armchair,
## wall_picture, broom, window_sill_flower) gets a small drawn placeholder in the same size; the
## names are in SPRITES_V13 Teil C, a delivered file replaces the placeholder by name.

const DIR := "res://art/environment/home/"
const TILES_FILE := "home_interior_tiles.png"
const TILES_SPEC := "home_interior_tiles.json"
const PROPS_SPEC := "home_props.json"
## Sizes of the furniture that is still missing (Antwort 20 §1), pivot bottom centre.
const PLACEHOLDER_SIZES := {
	"nightstand": Vector2i(16, 24),
	"armchair": Vector2i(32, 32),
	"wall_picture": Vector2i(24, 16),
	"broom": Vector2i(8, 24),
	"window_sill_flower": Vector2i(24, 12),
	"bookshelf_full": Vector2i(32, 48),
}
const WOOD := Color("#8a5a34")
const WOOD_DARK := Color("#5c3a24")
const WOOD_LIGHT := Color("#a8703f")
const OUTLINE := Color("#1c1a2b")
const RED := Color("#a83a3a")
const RED_LIGHT := Color("#c85252")
const LAMP := Color("#ffd166")
const LEAF := Color("#5fae4a")
## V13d (27.10.2026) delivered home_interior_tiles.png as 256×96 with rows 2 and 3 but kept the old
## home_interior_tiles.json ("rows": 2, the door at (0, 32), where the new sheet has plain plaster).
## While the JSON names fewer rows than the sheet has, these tiles (art px) win over it; an updated
## JSON (rows 3) is taken as it is. Only the door is used so far (SPRITES_V13 Teil C, FS6).
const SHEET_V13D_TILES := {"door_out": Vector2(192, 64)}
## The window pictures of the back wall (day, night), replacing the window tiles once delivered.
const WINDOW_DAY := "home_window_day"
const WINDOW_NIGHT := "home_window_night"

static var _specs: Dictionary = {}
static var _textures: Dictionary[String, Texture2D] = {}
static var _regions: Dictionary = {}


## {name: {file, frame_size, frames, fps, loop, pivot}} from home_props.json (empty when missing).
static func prop_specs() -> Dictionary:
	if _specs.is_empty():
		var text := FileAccess.get_file_as_string(DIR + PROPS_SPEC)
		var data: Variant = JSON.parse_string(text) if not text.is_empty() else null
		if data is Dictionary:
			for item: Variant in data.get("items", []):
				if item is Dictionary and item.has("name"):
					_specs[String(item["name"])] = item
	return _specs


## Spec of a prop: delivered values, or the placeholder size with pivot bottom centre.
static func prop_spec(prop_name: String) -> Dictionary:
	var specs := prop_specs()
	if specs.has(prop_name) and ResourceLoader.exists(DIR + String(specs[prop_name]["file"])):
		return specs[prop_name]
	var size: Vector2i = PLACEHOLDER_SIZES.get(prop_name, Vector2i(16, 16))
	return {"name": prop_name, "file": prop_name + ".png", "frame_size": [size.x, size.y], "frames": 1,
		"fps": 0, "loop": false, "pivot": [size.x * 0.5, size.y - 1]}


## Delivered art of a prop exists (as named in the spec or as <name>.png).
static func has_prop(prop_name: String) -> bool:
	var specs := prop_specs()
	if specs.has(prop_name) and ResourceLoader.exists(DIR + String(specs[prop_name]["file"])):
		return true
	return ResourceLoader.exists(DIR + prop_name + ".png")


static func frame_size(spec: Dictionary) -> Vector2i:
	var size: Array = spec.get("frame_size", [16, 16])
	return Vector2i(int(size[0]), int(size[1]))


static func pivot(spec: Dictionary) -> Vector2:
	var point: Array = spec.get("pivot", [8, 15])
	return Vector2(float(point[0]), float(point[1]))


## The strip (or single picture) of a prop; a drawn placeholder when it is missing.
static func prop_texture(prop_name: String) -> Texture2D:
	if _textures.has(prop_name):
		return _textures[prop_name]
	var spec := prop_spec(prop_name)
	var path := DIR + String(spec.get("file", prop_name + ".png"))
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	elif ResourceLoader.exists(DIR + prop_name + ".png"):
		texture = load(DIR + prop_name + ".png") as Texture2D
	if texture == null:
		texture = ImageTexture.create_from_image(placeholder_image(prop_name, frame_size(spec)))
	_textures[prop_name] = texture
	return texture


## SpriteFrames for an animated prop (altar, fireplace), one animation "default".
static func prop_frames(prop_name: String) -> SpriteFrames:
	var spec := prop_spec(prop_name)
	var fps := float(spec.get("fps", 6))
	return SpriteStrip.make_frames(prop_texture(prop_name), frame_size(spec), fps if fps > 0.0 else 1.0, bool(spec.get("loop", true)))


# --- Tiles ---

static func tiles_texture() -> Texture2D:
	if not _textures.has(TILES_FILE):
		var path := DIR + TILES_FILE
		_textures[TILES_FILE] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _textures[TILES_FILE]


## Region of a named tile (floor_a, floor_b, wall_front, wall_corner_l/r, window_a/b, door_out) in the
## tile sheet, Rect2() when the sheet or the name is missing.
static func tile_region(tile_name: String) -> Rect2:
	if _regions.is_empty():
		var text := FileAccess.get_file_as_string(DIR + TILES_SPEC)
		var data: Variant = JSON.parse_string(text) if not text.is_empty() else null
		if data is Dictionary and data.get("tiles") is Dictionary:
			var size: Array = data.get("tile_size", [32, 32])
			for key: String in data["tiles"]:
				var tile: Dictionary = data["tiles"][key]
				_regions[key] = Rect2(float(tile["x"]), float(tile["y"]), float(size[0]), float(size[1]))
			var sheet := tiles_texture()
			if sheet != null and int(data.get("rows", 0)) * float(size[1]) < sheet.get_height():
				for key: String in SHEET_V13D_TILES:
					_regions[key] = Rect2(SHEET_V13D_TILES[key], Vector2(float(size[0]), float(size[1])))
	return _regions.get(tile_name, Rect2())


## The delivered window picture for the time of day (night >= 0.5: the night one); null until both
## are delivered (the room keeps its window tiles then).
static func window_texture(night: float) -> Texture2D:
	if not has_prop(WINDOW_DAY) or not has_prop(WINDOW_NIGHT):
		return null
	return prop_texture(WINDOW_NIGHT if night >= 0.5 else WINDOW_DAY)


static func clear_cache() -> void:
	_specs.clear()
	_textures.clear()
	_regions.clear()


# --- Placeholders (Antwort 20 §1 furniture until it is delivered) ---

static func placeholder_image(prop_name: String, size: Vector2i) -> Image:
	var image := Image.create(maxi(1, size.x), maxi(1, size.y), false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	match prop_name:
		"nightstand":
			_box(image, Rect2i(1, 10, size.x - 2, size.y - 10), WOOD)
			_box(image, Rect2i(5, 4, 6, 6), LAMP)
			_box(image, Rect2i(7, 1, 2, 3), WOOD_LIGHT)
		"armchair":
			_box(image, Rect2i(2, 4, size.x - 4, size.y - 6), RED)
			_box(image, Rect2i(6, 14, size.x - 12, 10), RED_LIGHT)
			_box(image, Rect2i(4, size.y - 3, 3, 3), WOOD_DARK)
			_box(image, Rect2i(size.x - 7, size.y - 3, 3, 3), WOOD_DARK)
		"wall_picture":
			_box(image, Rect2i(0, 0, size.x, size.y), WOOD)
			_box(image, Rect2i(2, 2, size.x - 4, 6), Color("#7ec8e3"))
			_box(image, Rect2i(2, 8, size.x - 4, size.y - 10), LEAF)
		"broom":
			_box(image, Rect2i(3, 0, 2, size.y - 8), WOOD_LIGHT)
			_box(image, Rect2i(1, size.y - 8, 6, 8), Color("#d8b25a"))
		"window_sill_flower":
			_box(image, Rect2i(0, size.y - 3, size.x, 3), WOOD)
			_box(image, Rect2i(9, 4, 6, size.y - 7), Color("#c0603a"))
			_box(image, Rect2i(10, 0, 4, 4), Color("#ff9ad5"))
		_:
			_box(image, Rect2i(0, 0, size.x, size.y), WOOD)
			for y in range(6, size.y - 2, 10):
				_box(image, Rect2i(2, y, size.x - 4, 2), WOOD_DARK)
	return image


## Filled rectangle with a dark outline (clipped to the image).
static func _box(image: Image, rect: Rect2i, color: Color) -> void:
	var bounds := Rect2i(Vector2i.ZERO, image.get_size()).intersection(rect)
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var edge := x == rect.position.x or y == rect.position.y or x == rect.end.x - 1 or y == rect.end.y - 1
			image.set_pixel(x, y, OUTLINE if edge else color)

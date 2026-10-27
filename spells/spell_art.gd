class_name SpellArt
extends RefCounted
## Pictures of the spells (SPRITES_V13 §B5): the HUD symbol art/ui/spells/spell_<id>.png (16×16),
## the slot frame art/ui/spells/spell_slot.png (20×20) and the effect strips in art/effects/spells/.
## A delivered file replaces the placeholder by name (like TouchArt, EnemyArt); until then icons are
## drawn pixel grids in the spell's colour and effects are drawn by SpellLook (rings, sparks).
## Frame size, fps, pivot and loop of an effect come from the delivered JSONs (spell_fx.json next to
## the strips, spells.json next to the icons, items by name); a value missing there keeps the
## default below (pivot: middle of the frame).

const ICON_DIR := "res://art/ui/spells/"
const EFFECT_DIR := "res://art/effects/spells/"
const SLOT_FRAME := "spell_slot"
const ICON_SIZE := 16
## Effect strips: file, frame size, fps, loop, the radius in the picture the code scales to the
## spell's reach (0 = fixed size around the target). SPRITES_V13 §B5. Defaults; the JSONs win.
const EFFECTS := {
	&"light_flash": {"file": "light_flash_6f.png", "frame": Vector2i(96, 96), "fps": 18.0, "loop": false, "art_radius": 46.0},
	&"soul_shield": {"file": "soul_shield_6f.png", "frame": Vector2i(40, 40), "fps": 14.0, "loop": false, "art_radius": 0.0},
	&"soul_shield_loop": {"file": "soul_shield_loop_4f.png", "frame": Vector2i(40, 40), "fps": 6.0, "loop": true, "art_radius": 0.0},
	&"flame_ring": {"file": "flame_ring_8f.png", "frame": Vector2i(96, 96), "fps": 16.0, "loop": false, "art_radius": 46.0},
	&"heal_spark": {"file": "heal_spark_8f.png", "frame": Vector2i(64, 64), "fps": 14.0, "loop": false, "art_radius": 0.0},
	&"wisp": {"file": "wisp_4f.png", "frame": Vector2i(10, 10), "fps": 10.0, "loop": true, "art_radius": 0.0},
	&"wisp_trail": {"file": "wisp_trail_3f.png", "frame": Vector2i(8, 8), "fps": 10.0, "loop": false, "art_radius": 0.0},
}
## Delivered descriptions of the strips and icons ({"items": [{name, file, frame_size, fps, loop, pivot}]}).
const SPEC_FILES: Array[String] = [ICON_DIR + "spells.json", EFFECT_DIR + "spell_fx.json"]

## Icon grids (16 × 16) of the placeholders: "#" spell colour, "w" white, "d" dark; outline added.
const ICON_GRIDS := {
	&"light_flash": [
		"................", ".......#........", ".......#........", "...#...#...#....",
		"....#..#..#.....", ".....#www#......", "......www.......", ".######w#######.",
		"......www.......", ".....#www#......", "....#..#..#.....", "...#...#...#....",
		".......#........", ".......#........", "................", "................",
	],
	&"soul_shield": [
		"................", "...##########...", "..#wwwwwwwwww#..", "..#w########w#..",
		"..#w###ww###w#..", "..#w##wwww##w#..", "..#w###ww###w#..", "..#w########w#..",
		"...#w######w#...", "...#ww####ww#...", "....#ww##ww#....", ".....#wwww#.....",
		"......#ww#......", ".......##.......", "................", "................",
	],
	&"flame_ring": [
		"................", ".....######.....", "...##..ww..##...", "..#....ww....#..",
		".#....w##w....#.", ".#....####....#.", "#.....####.....#", "#....w####w....#",
		"#.....####.....#", ".#.....##.....#.", ".#............#.", "..#..........#..",
		"...##......##...", ".....######.....", "................", "................",
	],
	&"will_o_wisp": [
		"................", "................", "...##...........", "..#ww#......##..",
		"..####.....#ww#.", "...##......####.", "............##..", "......####......",
		".....#wwww#.....", "....#w#ww#w#....", "....#wwwwww#....", "....#ww##ww#....",
		".....#wwww#.....", "......####......", "................", "................",
	],
	&"heal_spark": [
		"................", "......w.........", ".....www........", "......w.........",
		"..###....###....", ".#####..#####...", ".############..w", ".######ww####.ww",
		"..####wwww###..w", "...###ww####....", "....########....", ".....######.....",
		"......####......", ".......##.......", "................", "................",
	],
}
const WHITE := Color("#f4f0e2")
const DARK := Color("#1c1a2b")
const OUTLINE := Color("#1c1a2b")
const SLOT_FILL := Color(0.082, 0.075, 0.122, 0.85)
const SLOT_RIM := Color("#a66ef0")

static var _cache: Dictionary[String, Texture2D] = {}
static var _specs: Dictionary = {}
static var _specs_loaded := false


## HUD symbol of a spell: the file, else the drawn placeholder (never null for a known spell).
static func icon(id: StringName) -> Texture2D:
	var own := _load(ICON_DIR + "spell_" + String(id) + ".png")
	if own != null:
		return own
	return placeholder_icon(id)


## Slot frame of the HUD (20×20): the file, else a drawn frame.
static func slot_frame() -> Texture2D:
	var own := _load(ICON_DIR + SLOT_FRAME + ".png")
	if own != null:
		return own
	var key := "placeholder:" + SLOT_FRAME
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(slot_frame_image())
	return _cache[key]


## {texture, file, frame, fps, loop, pivot, art_radius} of a delivered effect strip, or {} while it
## is missing. Values from the JSON item of the same name, the defaults (EFFECTS) for the rest.
static func effect(id: StringName) -> Dictionary:
	if not EFFECTS.has(id):
		return {}
	var result := apply_spec(EFFECTS[id], effect_spec(id))
	var texture := _load(EFFECT_DIR + String(result["file"]))
	if texture == null and result["file"] != EFFECTS[id]["file"]:
		result = apply_spec(EFFECTS[id], {})
		texture = _load(EFFECT_DIR + String(result["file"]))
	if texture == null:
		return {}
	result["texture"] = texture
	return result


## The delivered JSON item named like the effect ({} without one).
static func effect_spec(id: StringName) -> Dictionary:
	if not _specs_loaded:
		_specs_loaded = true
		_specs = read_specs(SPEC_FILES)
	return _specs.get(String(id), {})


## defaults (an EFFECTS entry) with the values of spec (a JSON item) where they are given and
## readable: file, frame_size, fps (> 0), loop, pivot. Pivot defaults to the middle of the frame.
static func apply_spec(defaults: Dictionary, spec: Dictionary) -> Dictionary:
	var result := defaults.duplicate()
	var file: Variant = spec.get("file")
	if file is String and not (file as String).is_empty():
		result["file"] = file
	var frame: Variant = spec.get("frame_size")
	if frame is Array and (frame as Array).size() >= 2 and float(frame[0]) > 0.0 and float(frame[1]) > 0.0:
		result["frame"] = Vector2i(int(frame[0]), int(frame[1]))
	var fps: Variant = spec.get("fps")
	if (fps is float or fps is int) and float(fps) > 0.0:
		result["fps"] = float(fps)
	var loop: Variant = spec.get("loop")
	if loop is bool:
		result["loop"] = loop
	result["loop"] = bool(result.get("loop", false))
	result["pivot"] = Vector2(result["frame"]) * 0.5
	var pivot: Variant = spec.get("pivot")
	if pivot is Array and (pivot as Array).size() >= 2:
		result["pivot"] = Vector2(float(pivot[0]), float(pivot[1]))
	return result


## name -> item of the JSON files (missing or broken files are skipped; later files win).
static func read_specs(paths: Array[String]) -> Dictionary:
	var specs := {}
	for path in paths:
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary or not (parsed as Dictionary).get("items") is Array:
			continue
		for item: Variant in parsed["items"]:
			if item is Dictionary and (item as Dictionary).get("name") is String:
				specs[item["name"]] = item
	return specs


static func placeholder_icon(id: StringName) -> Texture2D:
	var key := "placeholder:" + String(id)
	if _cache.has(key):
		return _cache[key]
	var data := SpellBook.get_spell(id)
	var image := icon_image(id, data.color if data != null else Color.WHITE)
	var texture: Texture2D = ImageTexture.create_from_image(image) if image != null else null
	_cache[key] = texture
	return texture


## 16 × 16 icon image from its grid in color with a one-pixel outline; null for unknown ids.
static func icon_image(id: StringName, color: Color) -> Image:
	if not ICON_GRIDS.has(id):
		return null
	var rows: Array = ICON_GRIDS[id]
	var image := Image.create_empty(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	var colors := {"#": color, "w": WHITE, "d": DARK}
	for y in ICON_SIZE:
		for x in ICON_SIZE:
			var cell := (rows[y] as String)[x]
			if colors.has(cell):
				image.set_pixel(x, y, colors[cell])
			elif _touches_motif(rows, colors, x, y):
				image.set_pixel(x, y, OUTLINE)
	return image


## 20 × 20 frame: dark fill, violet rim, outline (the Seele path's colour, SPRITES_V13 §B5).
static func slot_frame_image() -> Image:
	var size := ICON_SIZE + 4
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var edge := mini(mini(x, y), mini(size - 1 - x, size - 1 - y))
			var corner := (x == 0 or x == size - 1) and (y == 0 or y == size - 1)
			if corner:
				continue
			image.set_pixel(x, y, OUTLINE if edge == 0 else (SLOT_RIM if edge == 1 else SLOT_FILL))
	return image


## Forgets loaded and drawn pictures (art dropped in while the game runs, tests).
static func clear_cache() -> void:
	_cache.clear()
	_specs.clear()
	_specs_loaded = false


static func _touches_motif(rows: Array, colors: Dictionary, x: int, y: int) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var nx: int = x + dx
			var ny: int = y + dy
			if nx < 0 or ny < 0 or nx >= ICON_SIZE or ny >= ICON_SIZE:
				continue
			if colors.has((rows[ny] as String)[nx]):
				return true
	return false


static func _load(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var result: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_cache[path] = result
	return result

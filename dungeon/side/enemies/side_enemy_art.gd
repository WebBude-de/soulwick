class_name SideEnemyArt
extends RefCounted
## Delivered art of the newer side enemies (SV4, SPRITES_V13 §B10) by EnemyArt's naming convention:
##   art/characters/enemies/<id>/<id>_<anim>_<n>f.png   with walk (the bat: its flight loop) and death;
## idle is optional (walk stands in, the briefing asks only for walk and death), refuse optional (a
## refused stomp or a run into it: hedgehog bristles, shield bearer shoves, SPRITES_V13 part C). An optional
## <id>.json {"pivot": [x, y], "animations": [{"name", "fps", "loop"}]} sets the feet pivot and the
## speeds; default pivot (16, 30) scaled to the frame. Without a walk strip: null, the enemy draws its
## placeholder (SideEnemyPlaceholder).

const ANIMATIONS: Array[StringName] = [&"idle", &"walk", &"death", &"refuse"]
const DEFAULT_FPS := {&"idle": 6.0, &"walk": 10.0, &"death": 10.0, &"refuse": 12.0}
const LOOPING: Array[StringName] = [&"idle", &"walk"]
const DEFAULT_PIVOT := Vector2(16, 30)
const REFERENCE_FRAME := 32.0


## Frames plus the numbers to place them (feet pivot in frame pixels).
class Art:
	extends RefCounted
	var frames: SpriteFrames
	var frame_size := Vector2i(32, 32)
	var pivot := DEFAULT_PIVOT


static var _cache: Dictionary[StringName, Art] = {}
static var _missing: Dictionary[StringName, bool] = {}


static func get_art(id: StringName) -> Art:
	if id == &"":
		return null
	if _cache.has(id):
		return _cache[id]
	if _missing.has(id):
		return null
	var art := _load(id)
	if art == null:
		_missing[id] = true
	else:
		_cache[id] = art
	return art


static func clear_cache() -> void:
	_cache.clear()
	_missing.clear()


static func _load(id: StringName) -> Art:
	var location := EnemyArt.get_location(id, false)
	var folder := location[0]
	var prefix := location[1]
	if not DirAccess.dir_exists_absolute(folder):
		return null
	var strips := {}
	for file_name in ResourceLoader.list_directory(folder):
		var parsed := EnemyArt.parse_strip_name(file_name, prefix)
		if not parsed.is_empty() and ANIMATIONS.has(parsed["animation"]):
			strips[parsed["animation"]] = {"path": folder + file_name, "frames": parsed["frames"]}
	if not strips.has(&"walk"):
		return null
	if not strips.has(&"idle"):
		strips[&"idle"] = strips[&"walk"]
	var settings := _read_settings(folder + prefix + ".json")
	var art := Art.new()
	art.frames = SpriteFrames.new()
	art.frames.remove_animation(&"default")
	var frame_size := Vector2i.ZERO
	for animation in ANIMATIONS:
		if not strips.has(animation):
			continue
		var texture := load(strips[animation]["path"]) as Texture2D
		if texture == null:
			continue
		var count: int = strips[animation]["frames"]
		var size := Vector2i(floori(texture.get_width() / float(count)), texture.get_height())
		if frame_size == Vector2i.ZERO:
			frame_size = size
		var entry: Dictionary = settings.get(animation, {})
		var fps: float = entry.get("fps", DEFAULT_FPS.get(animation, 8.0))
		var loop: bool = entry.get("loop", LOOPING.has(animation))
		SpriteStrip.add_strip(art.frames, animation, texture, size, fps, loop)
	if frame_size == Vector2i.ZERO:
		return null
	art.frame_size = frame_size
	art.pivot = DEFAULT_PIVOT * (frame_size.x / REFERENCE_FRAME)
	var pivot: Variant = settings.get(&"__pivot")
	if pivot is Array and (pivot as Array).size() == 2:
		art.pivot = Vector2(float(pivot[0]), float(pivot[1]))
	return art


static func _read_settings(path: String) -> Dictionary:
	var result := {}
	if not FileAccess.file_exists(path):
		return result
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return result
	result[&"__pivot"] = (parsed as Dictionary).get("pivot")
	for entry: Variant in (parsed as Dictionary).get("animations", []):
		if entry is Dictionary and (entry as Dictionary).has("name"):
			result[StringName(str(entry["name"]))] = entry
	return result

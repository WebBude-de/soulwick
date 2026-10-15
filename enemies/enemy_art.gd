class_name EnemyArt
extends RefCounted
## Picks up real enemy art by naming convention (docs/design/sprites/SPRITES_V2.md §3/§4), so dropping the PNGs
## into art/ replaces the tinted placeholder sprites without touching any .tres:
##   art/characters/enemies/<id>/<id>_<anim>_<n>f.png          (normal enemies)
##   art/characters/bosses/<name>/<name>_<anim>_<n>f.png       (id "boss_<name>")
##   art/characters/bosses/<name>/<name>_portrait.png          (boss bar)
## Frame width = strip width / n; an optional <name>.json with {"pivot": [x, y] (feet),
## "animations": [{"name", "fps", "loop"}]} sets the anchor and overrides the default speeds.
## Without files EnemyData.sprite_frames + tint stay in use.

const ENEMY_DIR := "res://art/characters/enemies/%s/"
const BOSS_DIR := "res://art/characters/bosses/%s/"
const BOSS_PREFIX := "boss_"
## Placeholder sprites are 32 px; real art keeps the same on-screen size (see ArtSet.scale_factor).
const PLACEHOLDER_FRAME := 32.0
## Body centre relative to the frame, as in the 32 px placeholders (16, 22).
const ORIGIN_FACTOR := Vector2(0.5, 22.0 / 32.0)
## The body centre sits this far (in frame heights) above the feet pivot (placeholder 30 -> 22).
const FEET_TO_BODY := 0.25
const ANIMATIONS: Array[StringName] = [&"idle", &"walk", &"attack", &"attack2", &"summon", &"death"]
const DEFAULT_FPS := {&"idle": 4.0, &"walk": 10.0, &"attack": 8.0, &"attack2": 8.0, &"summon": 8.0, &"death": 8.0}
const LOOPING: Array[StringName] = [&"idle", &"walk"]


## Result of a lookup: frames plus the numbers the enemy needs to place them.
class ArtSet:
	extends RefCounted
	var frames: SpriteFrames
	var frame_size := Vector2i(32, 32)
	var origin := Vector2(16, 22)
	## Multiply onto the sprite scale so the figure keeps the placeholder size.
	var scale_factor := 1.0


	## Sprite scale for a gameplay size factor: about the placeholder size, but snapped to whole
	## pixels so the real pixel art stays crisp.
	func sprite_scale_for(visual_scale: float) -> float:
		return maxf(1.0, roundf(SpriteStrip.PIXEL_SCALE * visual_scale * scale_factor))


static var _cache: Dictionary[StringName, ArtSet] = {}
static var _missing: Dictionary[StringName, bool] = {}


## Folder and file prefix for an enemy id: ["res://art/characters/bosses/bone_king/", "bone_king"].
static func get_location(id: StringName, is_boss: bool) -> Array[String]:
	var name := String(id)
	if is_boss or name.begins_with(BOSS_PREFIX):
		name = name.trim_prefix(BOSS_PREFIX)
		return [BOSS_DIR % name, name]
	return [ENEMY_DIR % name, name]


## "golem_walk_6f.png" with prefix "golem" -> {"animation": &"walk", "frames": 6}; {} if no match.
static func parse_strip_name(file_name: String, prefix: String) -> Dictionary:
	if not file_name.begins_with(prefix + "_") or file_name.get_extension().to_lower() != "png":
		return {}
	var stem := file_name.get_basename().substr(prefix.length() + 1)
	var regex := RegEx.create_from_string("^([a-z0-9]+)_(\\d+)f$")
	var found := regex.search(stem)
	if found == null:
		return {}
	var count := found.get_string(2).to_int()
	if count <= 0:
		return {}
	return {"animation": StringName(found.get_string(1)), "frames": count}


## Real art for this enemy type or null (then use data.sprite_frames + tint). Cached per id.
static func get_art(data: EnemyData) -> ArtSet:
	if data == null or data.id == &"":
		return null
	if _cache.has(data.id):
		return _cache[data.id]
	if _missing.has(data.id):
		return null
	var art := _load_art(data)
	if art == null:
		_missing[data.id] = true
	else:
		_cache[data.id] = art
	return art


## Boss portrait (48×48) or null.
static func get_portrait(data: EnemyData) -> Texture2D:
	if data == null:
		return null
	var location := get_location(data.id, data.is_boss)
	var path := location[0] + location[1] + "_portrait.png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## Forget cached lookups (e.g. after new files were imported in the editor).
static func clear_cache() -> void:
	_cache.clear()
	_missing.clear()


static func _load_art(data: EnemyData) -> ArtSet:
	var location := get_location(data.id, data.is_boss)
	var folder := location[0]
	var prefix := location[1]
	if not DirAccess.dir_exists_absolute(folder):
		return null
	# The type already uses the real art of this folder (slime, skeleton, archer).
	if data.sprite_frames != null and data.sprite_frames.resource_path.begins_with(folder):
		return null
	var strips := {}
	for file_name in ResourceLoader.list_directory(folder):
		var parsed := parse_strip_name(file_name, prefix)
		if not parsed.is_empty() and ANIMATIONS.has(parsed["animation"]):
			strips[parsed["animation"]] = {"path": folder + file_name, "frames": parsed["frames"]}
	# Without at least idle and walk the placeholder is the better choice.
	if not strips.has(&"idle") or not strips.has(&"walk"):
		return null
	var settings := _read_settings(folder + prefix + ".json")
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
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
		var fps: float = settings.get(animation, {}).get("fps", DEFAULT_FPS.get(animation, 8.0))
		var loop: bool = settings.get(animation, {}).get("loop", LOOPING.has(animation))
		SpriteStrip.add_strip(frames, animation, texture, size, fps, loop)
	if frame_size == Vector2i.ZERO:
		return null
	var art := ArtSet.new()
	art.frames = frames
	art.frame_size = frame_size
	art.origin = (Vector2(frame_size) * ORIGIN_FACTOR).round()
	var pivot: Variant = settings.get(&"__pivot")
	if pivot is Array and (pivot as Array).size() == 2:
		art.origin = Vector2(float(pivot[0]), float(pivot[1]) - frame_size.y * FEET_TO_BODY).round()
	art.scale_factor = PLACEHOLDER_FRAME / float(frame_size.x)
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

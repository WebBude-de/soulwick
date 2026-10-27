class_name FlintArt
extends RefCounted
## Flint's frames, flame masks and anchors. The art is generated from the website figure by
## tools/generate_flint.py (D-217) and read from the folder's JSON like the other character sheets
## (art/characters/npcs/chicken.json):
##   art/companions/flint/flint.json              (frame_size, pivot, facing, animations[name, file,
##                                               frames, fps, loop, anchors], anchors)
##   art/companions/flint/flint_<anim>_<n>f.png   (32x32 frames, pivot (16, 30), facing left)
## When the JSON lists animations, exactly those are used (names, frame counts, fps, loop); only
## without a JSON the strips are found by name. Entries named "flame_mask_<anim>" are no animations
## but the flame mask of <anim> (white = flame, for the flame colour cosmetic): flame_masks.
## Anchors "flame" (light, spell origin, glow and sparks) and "head" (hats; the JSON may call it
## "hat") are either fixed for every frame ("anchors": {"flame": [x, y]}) or per frame inside an
## animation entry ({"name": "idle", ..., "anchors": {"flame": [[x, y], ...]}}). "facing" says where
## the art looks ("left" or "right", default right); FlintCompanion mirrors it to where he flies.
## Without idle art the same figure comes from code (FlintPlaceholder, idle only); a mood strip
## that is missing falls back to idle (FlintCompanion.play).

const DIR := "res://art/companions/flint/"
const PREFIX := "flint"
const JSON_FILE := "flint.json"
## Defaults when the JSON is missing or incomplete (the generated figure, FlintPlaceholder).
const DEFAULT_FRAME := FlintPlaceholder.FRAME_SIZE
const DEFAULT_PIVOT := FlintPlaceholder.PIVOT
const DEFAULT_FLAME := Vector2(16.5, 14.0)
const DEFAULT_HEAD := Vector2(16, 18)
const ANCHOR_FLAME := &"flame"
const ANCHOR_HEAD := &"head"
## Other names of an anchor in delivered JSONs (V13c calls the hat anchor "hat").
const ANCHOR_ALIASES := {&"hat": &"head"}
## JSON animation names with this prefix are flame masks of the animation named by the rest.
const FLAME_MASK_PREFIX := "flame_mask_"
## Speed of a strip whose JSON entry names none.
const DEFAULT_FPS := 8.0

var frames: SpriteFrames
## Flame masks by the animation they cover (same frames as that animation), empty without masks.
var flame_masks: SpriteFrames
var frame_size := DEFAULT_FRAME
var pivot := DEFAULT_PIVOT
## True if the frames look to the left (the generated art and the placeholder do).
var faces_left := true
var is_placeholder := true
## anchor -> {animation -> PackedVector2Array (one point per frame)}
var _frame_anchors: Dictionary = {}
## anchor -> Vector2 (the same for every frame)
var _fixed_anchors: Dictionary = {}


## Flint's art: the delivered files if there are any, else the placeholder. Built per Flint (at most
## one per player; the textures themselves come from the resource cache), so nothing outlives the
## world.
static func get_art() -> FlintArt:
	return load_from(DIR)


## Art from a folder, or the placeholder when the folder has no usable idle strip.
static func load_from(folder: String) -> FlintArt:
	var art := _load_files(folder)
	return art if art != null else placeholder()


## The same figure from code (idle only, FlintPlaceholder).
static func placeholder() -> FlintArt:
	var built := FlintPlaceholder.build()
	var art := FlintArt.new()
	art.frames = built["frames"]
	art.frame_size = FlintPlaceholder.FRAME_SIZE
	art.pivot = FlintPlaceholder.PIVOT
	art.faces_left = true
	art.is_placeholder = true
	art._frame_anchors = built["anchors"]
	return art


## Anchor point in frame pixels (unflipped) for a frame of an animation; per-frame values win over
## fixed ones, unknown animations use idle, unknown anchors the defaults.
func get_anchor(anchor: StringName, animation: StringName = &"idle", frame := 0) -> Vector2:
	var per_animation: Dictionary = _frame_anchors.get(anchor, {})
	var points: PackedVector2Array = per_animation.get(animation, per_animation.get(&"idle", PackedVector2Array()))
	if not points.is_empty():
		return points[clampi(frame, 0, points.size() - 1)]
	if _fixed_anchors.has(anchor):
		return _fixed_anchors[anchor]
	return DEFAULT_FLAME if anchor == ANCHOR_FLAME else DEFAULT_HEAD


## Offset of an anchor from the pivot in world px (art pixels * PIXEL_SCALE), mirrored when Flint
## looks the other way than the art (needs_flip).
func anchor_offset(anchor: StringName, animation: StringName = &"idle", frame := 0, facing_left := false) -> Vector2:
	var offset := (get_anchor(anchor, animation, frame) - pivot) * SpriteStrip.PIXEL_SCALE
	if needs_flip(facing_left):
		offset.x = -offset.x
	return offset


## True if the frames must be mirrored for Flint to look left (facing_left) or right.
func needs_flip(facing_left: bool) -> bool:
	return facing_left != faces_left


func has_animation(animation: StringName) -> bool:
	return frames != null and frames.has_animation(animation)


## True if the delivery has a flame mask for animation (frame by frame like the animation).
func has_flame_mask(animation: StringName) -> bool:
	return flame_masks != null and flame_masks.has_animation(animation)


static func _load_files(folder: String) -> FlintArt:
	if not DirAccess.dir_exists_absolute(folder):
		return null
	var settings := read_settings(folder + JSON_FILE)
	var entries := _animation_entries(folder, settings)
	if not entries.has(&"idle"):
		return null
	var art := FlintArt.new()
	art.is_placeholder = false
	art.frame_size = _vector2i(settings.get("frame_size"), DEFAULT_FRAME)
	art.pivot = _vector2(settings.get("pivot"), DEFAULT_PIVOT)
	art.faces_left = str(settings.get("facing", "right")) == "left"
	art.frames = SpriteFrames.new()
	art.frames.remove_animation(&"default")
	art.flame_masks = SpriteFrames.new()
	art.flame_masks.remove_animation(&"default")
	for animation: StringName in entries:
		var entry: Dictionary = entries[animation]
		var texture := load(folder + String(entry["file"])) as Texture2D
		if texture == null:
			continue
		var count := maxi(1, int(entry.get("frames", 1)))
		var size := Vector2i(floori(texture.get_width() / float(count)), texture.get_height())
		var fps := float(entry.get("fps", DEFAULT_FPS))
		var loop := bool(entry.get("loop", true))
		var animation_name := String(animation)
		if animation_name.begins_with(FLAME_MASK_PREFIX):
			SpriteStrip.add_strip(art.flame_masks, StringName(animation_name.trim_prefix(FLAME_MASK_PREFIX)), texture, size, fps, loop)
			continue
		SpriteStrip.add_strip(art.frames, animation, texture, size, fps, loop)
		art._read_frame_anchors(animation, entry.get("anchors", {}))
	if not art.frames.has_animation(&"idle"):
		return null
	var fixed: Variant = settings.get("anchors", {})
	if fixed is Dictionary:
		for key: Variant in fixed:
			var point: Variant = fixed[key]
			if point is Array and point.size() >= 2 and not (point[0] is Array):
				art._fixed_anchors[_anchor_name(key)] = _vector2(point, Vector2.ZERO)
	return art


## {"frame_size": ..., "animations": [...], ...} or {} without a readable JSON.
static func read_settings(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## animation -> {file, frames, fps?, loop?, anchors?}: the JSON entries (masks included), or without
## a JSON animation list the strips found by name (flint_<anim>_<n>f.png; mask strips
## flint_flame_mask_... never match the name rule). Strips the JSON does not name are ignored.
static func _animation_entries(folder: String, settings: Dictionary) -> Dictionary:
	var entries := {}
	var listed: Variant = settings.get("animations", [])
	if listed is Array and not listed.is_empty():
		for item: Variant in listed:
			if item is Dictionary and item.has("name") and item.has("file") and ResourceLoader.exists(folder + String(item["file"])):
				entries[StringName(str(item["name"]))] = item
		return entries
	for file_name in ResourceLoader.list_directory(folder):
		var parsed := EnemyArt.parse_strip_name(file_name, PREFIX)
		if parsed.is_empty() or entries.has(parsed["animation"]):
			continue
		entries[parsed["animation"]] = {"file": file_name, "frames": parsed["frames"]}
	return entries


func _read_frame_anchors(animation: StringName, anchors: Variant) -> void:
	if not anchors is Dictionary:
		return
	for key: Variant in anchors:
		var list: Variant = anchors[key]
		if not list is Array:
			continue
		var points := PackedVector2Array()
		for point: Variant in list:
			points.append(_vector2(point, DEFAULT_FLAME))
		var anchor := _anchor_name(key)
		if not _frame_anchors.has(anchor):
			_frame_anchors[anchor] = {}
		_frame_anchors[anchor][animation] = points


static func _anchor_name(key: Variant) -> StringName:
	var anchor := StringName(str(key))
	return ANCHOR_ALIASES.get(anchor, anchor)


static func _vector2(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback


static func _vector2i(value: Variant, fallback: Vector2i) -> Vector2i:
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return fallback

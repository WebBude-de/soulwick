class_name FlintPortraitArt
extends RefCounted
## Flint big for the explanation corner: portrait strips by mood, the round frame, the speech bubble
## (9-slice) with its tail and the "Weiter" arrow. The portraits are the website figure (D-217) drawn
## twice as large by tools/generate_flint.py; the rest is delivered art (SPRITES_V13 §B2):
##   art/ui/flint_guide/flint_portrait_<mood>_<n>f.png  (48x48 frames, facing left to the bubble)
##   art/ui/flint_guide/flint_guide_portraits.json      (fps and frames per strip, wins over
##                                                       ANIMATIONS; anchor "flame" for glow and sparks)
##   art/ui/flint_guide/guide_frame.png                 (56x56, middle transparent)
##   art/ui/flint_guide/speech_bubble.png               (24x24, 9-slice margin 8)
##   art/ui/flint_guide/speech_bubble_tail.png          (8x8)
##   art/ui/flint_guide/guide_next_4f.png               (8x8 frames, 6 fps)
## Without portrait strips the same figure comes from code (FlintPlaceholder twice as large); frame,
## bubble and arrow then come from FlintGuideView's drawing.

const DIR := "res://art/ui/flint_guide/"
const PREFIX := "flint_portrait"
const FRAME_SIZE := Vector2i(48, 48)
const RING_SIZE := Vector2i(56, 56)
const FRAME_FILE := "guide_frame.png"
const BUBBLE_FILE := "speech_bubble.png"
const BUBBLE_TAIL_FILE := "speech_bubble_tail.png"
const NEXT_PREFIX := "guide"
const PORTRAITS_JSON := "flint_guide_portraits.json"
## The bubble's 9-slice border in art pixels (§B2).
const BUBBLE_MARGIN := 8
## Placeholder: the code figure (FlintPlaceholder) this many times as large, feet on the bottom row.
const PLACEHOLDER_SCALE := 2
const PLACEHOLDER_FEET := Vector2i(24, 46)
## Middle of the flame in the portrait frame (art px) when the JSON names none.
const DEFAULT_FLAME := Vector2(25.0, 9.5)
## mood strip -> [frames, fps] (as generated; FlintGuideStep.Mood).
const ANIMATIONS := {
	&"talk": [6, 8.0],
	&"neutral": [12, 6.0],
	&"happy": [4, 6.0],
	&"worried": [4, 8.0],
	&"point": [4, 6.0],
	&"proud": [4, 6.0],
}


## Portrait frames: delivered strips where they exist, the placeholder for the rest.
static func get_frames(folder := DIR) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var found := _strips(folder)
	var listed := _json_entries(folder)
	for animation: StringName in ANIMATIONS:
		var spec: Array = ANIMATIONS[animation]
		frames.add_animation(animation)
		frames.set_animation_speed(animation, spec[1])
		frames.set_animation_loop(animation, true)
		if found.has(animation):
			var entry: Dictionary = found[animation]
			var texture := load(folder + String(entry["file"])) as Texture2D
			if texture != null:
				var count := maxi(1, int(entry["frames"]))
				var json_entry: Dictionary = listed.get(entry["file"], {})
				if json_entry.has("fps"):
					frames.set_animation_speed(animation, maxf(0.1, float(json_entry["fps"])))
				if json_entry.has("loop"):
					frames.set_animation_loop(animation, bool(json_entry["loop"]))
				var size := Vector2i(floori(texture.get_width() / float(count)), texture.get_height())
				for i in count:
					var atlas := AtlasTexture.new()
					atlas.atlas = texture
					atlas.region = Rect2(Vector2(size.x * i, 0), Vector2(size))
					frames.add_frame(animation, atlas)
				continue
		for image in placeholder_images(animation, spec[0]):
			frames.add_frame(animation, ImageTexture.create_from_image(image))
	return frames


## True if any portrait strip was delivered (else everything is the placeholder).
static func has_delivered_portraits(folder := DIR) -> bool:
	return not _strips(folder).is_empty()


## A texture of the folder or null (frame, bubble, tail).
static func texture(file: String, folder := DIR) -> Texture2D:
	var path := folder + file
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## Frames of the "Weiter" arrow (guide_next_<n>f.png) or empty.
static func next_arrow_frames(folder := DIR) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	if not DirAccess.dir_exists_absolute(folder):
		return result
	for file_name in ResourceLoader.list_directory(folder):
		var parsed := EnemyArt.parse_strip_name(file_name, NEXT_PREFIX)
		if parsed.is_empty() or parsed["animation"] != &"next":
			continue
		var strip := load(folder + file_name) as Texture2D
		if strip == null:
			continue
		var count: int = parsed["frames"]
		var width := floori(strip.get_width() / float(count))
		for i in count:
			var atlas := AtlasTexture.new()
			atlas.atlas = strip
			atlas.region = Rect2(width * i, 0, width, strip.get_height())
			result.append(atlas)
	return result


## Placeholder frames of a mood strip: 48x48 images of the code figure, facing left.
static func placeholder_images(animation: StringName, count: int) -> Array[Image]:
	var images: Array[Image] = []
	for i in count:
		var image := Image.create_empty(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
		FlintPlaceholder.paint_into(image, placeholder_pose(animation, i), PLACEHOLDER_FEET, PLACEHOLDER_SCALE)
		images.append(image)
	return images


## The pose of a placeholder portrait frame: the flame flickers, talking opens the mouth.
static func placeholder_pose(animation: StringName, i: int) -> FlintPlaceholder.Pose:
	var flame: StringName = [&"a", &"b", &"c"][i % 3]
	return FlintPlaceholder.Pose.new(flame, false, animation == &"talk" and i % 2 == 1)


## Middle of Flint's flame in the portrait frame (art px): where glow and sparks sit (FlintPortrait).
static func flame_point(folder := DIR) -> Vector2:
	var path := folder + PORTRAITS_JSON
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var anchors: Variant = parsed.get("anchors", {}) if parsed is Dictionary else {}
		var point: Variant = anchors.get("flame") if anchors is Dictionary else null
		if point is Array and point.size() >= 2:
			return Vector2(float(point[0]), float(point[1]))
	return DEFAULT_FLAME


## file name -> item of flint_guide_portraits.json ({name, file, frames, fps, loop}) or {}.
static func _json_entries(folder: String) -> Dictionary:
	var entries := {}
	var path := folder + PORTRAITS_JSON
	if not FileAccess.file_exists(path):
		return entries
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var items: Variant = parsed.get("items", []) if parsed is Dictionary else []
	if items is Array:
		for item: Variant in items:
			if item is Dictionary and item.has("file"):
				entries[String(item["file"])] = item
	return entries


## mood strip -> {file, frames} of the delivered strips in folder.
static func _strips(folder: String) -> Dictionary:
	var found := {}
	if not DirAccess.dir_exists_absolute(folder):
		return found
	for file_name in ResourceLoader.list_directory(folder):
		var parsed := EnemyArt.parse_strip_name(file_name, PREFIX)
		if not parsed.is_empty() and ANIMATIONS.has(parsed["animation"]):
			found[parsed["animation"]] = {"file": file_name, "frames": parsed["frames"]}
	return found

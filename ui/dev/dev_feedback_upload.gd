class_name DevFeedbackUpload
extends RefCounted
## Body of POST /bug-reports (soulwick-platform packages/contracts/src/bug-report.ts,
## CreateBugReportRequest) built from a saved note (DevFeedback.build_record) and its screenshot:
## note, category keys, marks and strokes relative to the screenshot (0..1), a context object of at
## most 16 KiB (shrunk when larger), game version, platform and the screenshot as base64 WebP
## (lossy, at most 1280x720, at most 1.5 MiB decoded; JPEG when WebP fails). The limits mirror the
## contract; the server checks them again. Pure functions, no network (DevFeedbackOutbox sends).

const MAX_NOTE := 2000
const MAX_MARK_NOTE := 300
const MAX_MARKS := 20
const MAX_STROKES := 20
const MAX_STROKE_POINTS := 256
const MAX_CONTEXT_BYTES := 16 * 1024
const MAX_IMAGE_BYTES := 1_572_864
const MAX_IMAGE_SIZE := Vector2i(1280, 720)
## Second try after 413 payload_too_large: smaller and lower quality.
const SMALL_IMAGE_SIZE := Vector2i(960, 540)
const SMALL_IMAGE_QUALITIES: Array[float] = [0.6, 0.45, 0.3]
## WebP qualities tried in turn before the image is made smaller.
const QUALITIES: Array[float] = [0.8, 0.65, 0.5, 0.35]
## Named context fields of the contract with their length limits; never dropped when shrinking.
const CONTEXT_FIELDS := {"location": 200, "scene": 300, "seed": 64, "resolution": 32, "locale": 16}
## Entries per node list under a mark once the context is too large.
const SHRUNK_NODE_LIST := 3


## The request body for record (note.json content) and the unmarked screenshot.
static func build_body(record: Dictionary, screenshot: Image) -> Dictionary:
	var image_size := _image_size(record, screenshot)
	var body := {
		"note": str(record.get("text", "")).strip_edges().left(MAX_NOTE),
		"categories": categories_of(record),
		"marks": relative_marks(record),
		"strokes": relative_strokes(record, image_size),
		"context": build_context(record),
		"gameVersion": OnlineConfig.get_game_version().left(32),
		"platform": platform(),
		"image": "",
	}
	if screenshot != null and not screenshot.is_empty():
		body["image"] = Marshalls.raw_to_base64(encode_image(screenshot))
	return body


## Platform of the contract (BugReportPlatform): OnlineConfig's names plus "web".
static func platform() -> String:
	return "web" if OS.has_feature("web") else OnlineConfig.get_platform()


## Base64 of a new screenshot encoding for a retry: jpeg = true after 400 invalid_image (JPEG
## instead of WebP), small = true after 413 payload_too_large (960x540, lower quality). "" when
## the image is missing.
static func reencode(screenshot: Image, jpeg: bool, small: bool) -> String:
	if screenshot == null or screenshot.is_empty():
		return ""
	var bytes := encode_image(screenshot, MAX_IMAGE_BYTES, SMALL_IMAGE_SIZE if small else MAX_IMAGE_SIZE,
			jpeg, SMALL_IMAGE_QUALITIES if small else QUALITIES)
	return Marshalls.raw_to_base64(bytes) if not bytes.is_empty() else ""


## Known category keys only, each once.
static func categories_of(record: Dictionary) -> Array:
	var result: Array = []
	for category in record.get("categories", []):
		var key := str(category)
		if DevFeedbackTexts.CATEGORY_TEXT.has(key) and not result.has(key):
			result.append(key)
	return result


static func relative_marks(record: Dictionary) -> Array:
	var result: Array = []
	for mark: Dictionary in record.get("marks", []):
		if result.size() >= MAX_MARKS:
			break
		var rel: Dictionary = mark.get("rect_rel", {})
		var x := _unit(rel.get("x", 0.0))
		var y := _unit(rel.get("y", 0.0))
		result.append({
			"x": x, "y": y,
			"w": minf(_unit(rel.get("w", 0.0)), 1.0 - x),
			"h": minf(_unit(rel.get("h", 0.0)), 1.0 - y),
			"note": str(mark.get("note", "")).strip_edges().left(MAX_MARK_NOTE),
		})
	return result


## Strokes as [[x, y], ...] relative to the image; long strokes are thinned to MAX_STROKE_POINTS.
static func relative_strokes(record: Dictionary, image_size: Vector2) -> Array:
	var result: Array = []
	if image_size.x <= 0.0 or image_size.y <= 0.0:
		return result
	for stroke: Dictionary in record.get("strokes", []):
		if result.size() >= MAX_STROKES:
			break
		var points: Array = stroke.get("points_px", [])
		if points.is_empty():
			continue
		var line: Array = []
		var step := ceili(points.size() / float(MAX_STROKE_POINTS))
		for i in range(0, points.size(), step):
			line.append(_rel_point(points[i], image_size))
		if (points.size() - 1) % step != 0:
			line[line.size() - 1] = _rel_point(points[points.size() - 1], image_size)
		result.append(line.slice(0, MAX_STROKE_POINTS))
	return result


## The context object: the contract's named fields first, then the game state of note.json and the
## nodes under each mark; shrunk to MAX_CONTEXT_BYTES.
static func build_context(record: Dictionary, max_bytes := MAX_CONTEXT_BYTES) -> Dictionary:
	var source: Dictionary = record.get("context", {})
	var context := {}
	context["location"] = str(record.get("location", source.get("location", "")))
	context["scene"] = str(source.get("scene", ""))
	var dungeon: Dictionary = source.get("dungeon", {})
	if dungeon.has("seed"):
		context["seed"] = str(dungeon["seed"])
	var window: Dictionary = source.get("window", {})
	var size: Variant = window.get("window_size", record.get("image_size", []))
	if size is Array and (size as Array).size() >= 2:
		context["resolution"] = "%dx%d" % [int(size[0]), int(size[1])]
	context["locale"] = TranslationServer.get_locale()
	for key: String in CONTEXT_FIELDS:
		if context.has(key):
			context[key] = str(context[key]).left(int(CONTEXT_FIELDS[key]))
	for key in source:
		if not context.has(key):
			context[key] = source[key]
	context["version"] = record.get("version", {})
	context["view_size"] = record.get("view_size", [])
	context["image_size"] = record.get("image_size", [])
	var mark_nodes: Array = []
	for mark: Dictionary in record.get("marks", []):
		mark_nodes.append({"nr": mark.get("nr", 0), "ui_nodes": mark.get("ui_nodes", []), "world_nodes": mark.get("world_nodes", [])})
	if not mark_nodes.is_empty():
		context["mark_nodes"] = mark_nodes
	return shrink_context(context, max_bytes)


## Makes context fit into max_bytes (UTF-8 JSON): first the node lists under the marks get shorter,
## then the largest other keys go (listed in "truncated"); the named contract fields stay.
static func shrink_context(context: Dictionary, max_bytes := MAX_CONTEXT_BYTES) -> Dictionary:
	var result := context.duplicate(true)
	if json_bytes(result) <= max_bytes:
		return result
	if result.get("mark_nodes", null) is Array:
		for entry: Variant in result["mark_nodes"]:
			if entry is Dictionary:
				for list_key in ["ui_nodes", "world_nodes"]:
					var list: Variant = entry.get(list_key, [])
					if list is Array:
						entry[list_key] = (list as Array).slice(0, SHRUNK_NODE_LIST)
	var dropped: Array = []
	while json_bytes(result) > max_bytes:
		var largest := ""
		var largest_size := -1
		for key: String in result:
			if CONTEXT_FIELDS.has(key) or key == "truncated":
				continue
			var size := json_bytes(result[key])
			if size > largest_size:
				largest = key
				largest_size = size
		if largest.is_empty():
			break
		result.erase(largest)
		dropped.append(largest)
		result["truncated"] = dropped
	return result


## UTF-8 length of value as JSON.
static func json_bytes(value: Variant) -> int:
	return JSON.stringify(value).to_utf8_buffer().size()


## WebP (lossy) of the image, scaled to fit max_size, at most max_bytes: lower quality first, then
## smaller. JPEG when jpeg is set or this build cannot write WebP.
static func encode_image(screenshot: Image, max_bytes := MAX_IMAGE_BYTES, max_size := MAX_IMAGE_SIZE,
		jpeg := false, qualities: Array[float] = QUALITIES) -> PackedByteArray:
	var image := screenshot.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8 and image.get_format() != Image.FORMAT_RGB8:
		image.convert(Image.FORMAT_RGBA8)
	# The game has no transparency; RGB keeps WebP and JPEG small.
	image.convert(Image.FORMAT_RGB8)
	var size := fit_size(image.get_size(), max_size)
	var buffer := PackedByteArray()
	for attempt in 6:
		if size != image.get_size():
			image.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
		for quality in qualities:
			buffer = PackedByteArray() if jpeg else image.save_webp_to_buffer(true, quality)
			if buffer.is_empty():
				buffer = image.save_jpg_to_buffer(quality)
			if not buffer.is_empty() and buffer.size() <= max_bytes:
				return buffer
		size = Vector2i(maxi(1, roundi(size.x * 0.7)), maxi(1, roundi(size.y * 0.7)))
	return buffer


## size scaled down (never up) to fit into bounds, aspect kept.
static func fit_size(size: Vector2i, bounds: Vector2i) -> Vector2i:
	if size.x <= 0 or size.y <= 0:
		return Vector2i.ONE
	var scale := minf(1.0, minf(float(bounds.x) / size.x, float(bounds.y) / size.y))
	return Vector2i(maxi(1, roundi(size.x * scale)), maxi(1, roundi(size.y * scale)))


static func _image_size(record: Dictionary, screenshot: Image) -> Vector2:
	var size: Variant = record.get("image_size", [])
	if size is Array and (size as Array).size() >= 2:
		return Vector2(float(size[0]), float(size[1]))
	if screenshot != null:
		return Vector2(screenshot.get_size())
	return Vector2.ZERO


static func _rel_point(point: Variant, image_size: Vector2) -> Array:
	var x := 0.0
	var y := 0.0
	if point is Array and (point as Array).size() >= 2:
		x = float(point[0]) / image_size.x
		y = float(point[1]) / image_size.y
	return [_unit(x), _unit(y)]


static func _unit(value: Variant) -> float:
	return snappedf(clampf(float(value), 0.0, 1.0), 0.0001)

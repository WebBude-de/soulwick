class_name DevFeedbackStore
extends RefCounted
## Writes one bug report (DevFeedback, Ctrl + B / # / F9) into its own folder under the feedback root:
## screenshot.png (the frame as it was), marked.png (the frame with the numbered rectangles and
## strokes burnt in) and note.json (text, kind, marks, context), and appends one line to the
## running index.md. Folder names: <YYYY-MM-DD_HH-MM-SS>_<nr>, nr counts up across all notes.
## The marked image is drawn straight into the Image (no font, no SubViewport) so saving works the
## same in headless tests: numbers use a tiny built-in 3x5 pixel digit font.
## with_marked = false (web build, DevFeedback.light_save) skips marked.png: nobody opens user://
## in the browser, and one PNG less keeps the browser's single thread free; index.md then links
## screenshot.png.

const INDEX_FILE := "index.md"
const SCREENSHOT_FILE := "screenshot.png"
const MARKED_FILE := "marked.png"
const NOTE_FILE := "note.json"
const INDEX_TEXT_LENGTH := 80

const MARK_COLOR := Color(1.0, 0.16, 0.12, 1.0)
const MARK_FILL := Color(1.0, 0.16, 0.12, 0.18)
const STROKE_COLOR := Color(1.0, 0.85, 0.2, 1.0)
const LABEL_TEXT_COLOR := Color(1.0, 1.0, 1.0, 1.0)

## 3x5 digits, one string of 15 cells (row by row) per digit.
const DIGITS: Array[String] = [
	"111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001",
	"111100111001111", "111100111101111", "111001001001001", "111101111101111", "111101111001111",
]


## Writes the note; returns the folder (user:// or absolute path) or "" on failure.
## record: the note.json content (DevFeedback builds it); id and folder are filled in here.
## with_marked = false writes no marked.png (see the class notes).
static func save(root_dir: String, screenshot: Image, record: Dictionary, with_marked := true) -> String:
	if screenshot == null or screenshot.is_empty():
		push_warning("DevFeedbackStore: no screenshot to save")
		return ""
	if DirAccess.make_dir_recursive_absolute(root_dir) != OK and not DirAccess.dir_exists_absolute(root_dir):
		push_warning("DevFeedbackStore: cannot create %s" % root_dir)
		return ""
	var number := next_number(root_dir)
	var stamp := folder_stamp(Time.get_datetime_string_from_system(false, true))
	var folder := "%s_%d" % [stamp, number]
	var dir := root_dir.path_join(folder)
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		push_warning("DevFeedbackStore: cannot create %s" % dir)
		return ""
	record["id"] = number
	record["folder"] = folder
	var marks: Array = record.get("marks", [])
	var strokes: Array = record.get("strokes", [])
	if screenshot.save_png(dir.path_join(SCREENSHOT_FILE)) != OK:
		push_warning("DevFeedbackStore: cannot write screenshot")
		return ""
	if with_marked:
		render_marked(screenshot, marks, strokes).save_png(dir.path_join(MARKED_FILE))
	var file := FileAccess.open(dir.path_join(NOTE_FILE), FileAccess.WRITE)
	if file == null:
		push_warning("DevFeedbackStore: cannot write note.json")
		return ""
	file.store_string(JSON.stringify(record, "\t", false))
	file.close()
	append_index(root_dir, record, MARKED_FILE if with_marked else SCREENSHOT_FILE)
	return dir


## "2026-10-15 14:03:22" -> "2026-10-15_14-03-22".
static func folder_stamp(datetime: String) -> String:
	return datetime.replace(" ", "_").replace("T", "_").replace(":", "-")


## Highest note number in the root (folder suffix _<nr>) plus one.
static func next_number(root_dir: String) -> int:
	var highest := 0
	var dir := DirAccess.open(root_dir)
	if dir == null:
		return 1
	for folder in dir.get_directories():
		var suffix := folder.get_slice("_", folder.get_slice_count("_") - 1)
		if suffix.is_valid_int():
			highest = maxi(highest, suffix.to_int())
	return highest + 1


## Appends one table row to index.md (creates it with a header first); the folder links link_file.
static func append_index(root_dir: String, record: Dictionary, link_file := MARKED_FILE) -> void:
	var path := root_dir.path_join(INDEX_FILE)
	var exists := FileAccess.file_exists(path)
	var file := FileAccess.open(path, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if file == null:
		push_warning("DevFeedbackStore: cannot write index.md")
		return
	if exists:
		file.seek_end()
	else:
		file.store_string("# Dev-Feedback\n\nEine Zeile je Meldung (Strg + B, am Pad Select + Start, # oder F9 im Spiel). Auswerten: `python tools/collect_feedback.py`.\n\n")
		file.store_string("| Zeit | Art | Ort | Text | Ordner |\n| --- | --- | --- | --- | --- |\n")
	file.store_string(index_line(record, link_file) + "\n")
	file.close()


static func index_line(record: Dictionary, link_file := MARKED_FILE) -> String:
	var kind := "Idee" if str(record.get("kind", "bug")) == "idea" else "Fehler"
	var text := _one_line(str(record.get("text", "")))
	if text.is_empty():
		for mark: Dictionary in record.get("marks", []):
			var mark_note := _one_line(str(mark.get("note", "")))
			if not mark_note.is_empty():
				text = mark_note
				break
	if text.length() > INDEX_TEXT_LENGTH:
		text = text.substr(0, INDEX_TEXT_LENGTH - 1) + "…"
	var folder := str(record.get("folder", ""))
	return "| %s | %s | %s | %s | [%s](%s/%s) |" % [
		str(record.get("time", "")).replace("T", " "),
		kind,
		_cell(str(record.get("location", ""))),
		_cell(text),
		folder, folder, link_file,
	]


## Copy of the screenshot with the marks burnt in. marks: [{nr, rect_px: {x, y, w, h}}],
## strokes: [{points_px: [[x, y], ...]}] (both in image pixels).
static func render_marked(screenshot: Image, marks: Array, strokes: Array) -> Image:
	var image := screenshot.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var bounds := Rect2i(Vector2i.ZERO, image.get_size())
	var line := maxi(2, roundi(image.get_height() / 360.0))
	for stroke: Dictionary in strokes:
		var points: Array = stroke.get("points_px", [])
		for i in range(1, points.size()):
			_draw_line(image, _point(points[i - 1]), _point(points[i]), line, STROKE_COLOR, bounds)
	for mark: Dictionary in marks:
		var rect := _rect(mark.get("rect_px", {})).intersection(bounds)
		if rect.size.x <= 0 or rect.size.y <= 0:
			continue
		var fill := Image.create_empty(rect.size.x, rect.size.y, false, Image.FORMAT_RGBA8)
		fill.fill(MARK_FILL)
		image.blend_rect(fill, Rect2i(Vector2i.ZERO, rect.size), rect.position)
		_draw_frame(image, rect, line, MARK_COLOR, bounds)
		_draw_label(image, rect.position, int(mark.get("nr", 0)), line, bounds)
	return image


static func _draw_frame(image: Image, rect: Rect2i, width: int, color: Color, bounds: Rect2i) -> void:
	_fill(image, Rect2i(rect.position, Vector2i(rect.size.x, width)), color, bounds)
	_fill(image, Rect2i(rect.position.x, rect.end.y - width, rect.size.x, width), color, bounds)
	_fill(image, Rect2i(rect.position, Vector2i(width, rect.size.y)), color, bounds)
	_fill(image, Rect2i(rect.end.x - width, rect.position.y, width, rect.size.y), color, bounds)


## Red box with the white number at the top left corner of a mark.
static func _draw_label(image: Image, at: Vector2i, number: int, line: int, bounds: Rect2i) -> void:
	var digits := str(maxi(0, number))
	var cell := maxi(2, line + 1)
	var pad := cell
	var size := Vector2i(digits.length() * 4 * cell - cell + 2 * pad, 5 * cell + 2 * pad)
	var box := Rect2i(at, size)
	_fill(image, box, MARK_COLOR, bounds)
	for d in digits.length():
		var glyph := DIGITS[digits.unicode_at(d) - 48]
		var origin := at + Vector2i(pad + d * 4 * cell, pad)
		for cell_index in 15:
			if glyph[cell_index] == "1":
				var cx := cell_index % 3
				var cy := floori(cell_index / 3.0)
				_fill(image, Rect2i(origin + Vector2i(cx, cy) * cell, Vector2i(cell, cell)), LABEL_TEXT_COLOR, bounds)


static func _draw_line(image: Image, from: Vector2i, to: Vector2i, width: int, color: Color, bounds: Rect2i) -> void:
	var steps := maxi(1, maxi(absi(to.x - from.x), absi(to.y - from.y)))
	var half := floori(width / 2.0)
	for i in steps + 1:
		var p := Vector2i(Vector2(from).lerp(Vector2(to), float(i) / steps).round())
		_fill(image, Rect2i(p - Vector2i(half, half), Vector2i(width, width)), color, bounds)


static func _fill(image: Image, rect: Rect2i, color: Color, bounds: Rect2i) -> void:
	var clipped := rect.intersection(bounds)
	if clipped.size.x > 0 and clipped.size.y > 0:
		image.fill_rect(clipped, color)


static func _rect(data: Dictionary) -> Rect2i:
	return Rect2i(int(data.get("x", 0)), int(data.get("y", 0)), int(data.get("w", 0)), int(data.get("h", 0)))


static func _point(data: Variant) -> Vector2i:
	if data is Array and (data as Array).size() >= 2:
		return Vector2i(int(data[0]), int(data[1]))
	return Vector2i.ZERO


static func _one_line(text: String) -> String:
	return text.replace("\r", " ").replace("\n", " ").replace("\t", " ").strip_edges()


static func _cell(text: String) -> String:
	return _one_line(text).replace("|", "/")

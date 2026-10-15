class_name DevFeedback
extends Node
## Dev feedback tool for local graphics/UI reviews: F9 grabs the current frame (before anything of
## the tool is drawn), freezes the game through the regular pause system (pause reason
## &"dev_feedback", D-043) and opens DevFeedbackOverlay. There the developer marks rectangles and
## types notes; saving writes screenshot, marked copy, note.json with context
## (DevFeedbackContext) and a line in index.md under root_dir (DevFeedbackStore). Evaluate the
## notes with tools/collect_feedback.py (docs/feedback/README.md).
## Debug builds only (editor, local runs); in release exports the node is never created
## (is_enabled). No autoload (AGENTS.md §6.5): GameManager._ready() calls install() once.
## Headless runs (tools, GUT, bot) carry the node but F9 is ignored there; tests drive open() and
## the overlay directly and point root_dir at a test folder, so nothing ever touches the real
## feedback folder or the save game.

signal opened
## saved_dir: folder of the written note, "" when discarded or failed.
signal closed(saved_dir: String)

const PAUSE_REASON := &"dev_feedback"
const NODE_NAME := &"DevFeedback"
const TRIGGER_KEY := KEY_F9
const TOAST_LAYER := 121
const TOAST_SECONDS := 2.4

## Where the notes go (user://dev_feedback = %APPDATA%/Godot/app_userdata/Soulwick/dev_feedback).
static var root_dir := "user://dev_feedback"
## -1: follow OS.is_debug_build(); 0: force off (release check in tests); 1: force on.
static var debug_override := -1
## The pause is released this many frames after the overlay closed, so the key or click that
## closed it is no longer "just pressed" when the game runs again. Tests set 0 (synchronous).
static var release_delay_frames := 2

var _overlay: DevFeedbackOverlay = null
var _image: Image = null
var _toast_layer: CanvasLayer = null
var _toast_tween: Tween = null
var _last_saved_dir := ""


static func is_enabled() -> bool:
	if debug_override >= 0:
		return debug_override == 1
	return OS.is_debug_build()


## Hangs one DevFeedback under the tree root (deferred: the root is still setting up its children
## while autoloads run _ready). Returns the node, or null when the tool is off.
static func install(tree_root: Node) -> DevFeedback:
	if tree_root == null or not is_enabled():
		return null
	var existing := tree_root.get_node_or_null(NodePath(NODE_NAME))
	if existing is DevFeedback:
		return existing
	var node := DevFeedback.new()
	node.name = NODE_NAME
	tree_root.add_child.call_deferred(node)
	return node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if _overlay != null or DisplayServer.get_name() == "headless":
		return
	if handle_event(event):
		get_viewport().set_input_as_handled()


## F9 opens the overlay; true when the event was used.
func handle_event(event: InputEvent) -> bool:
	if not is_trigger(event) or not is_enabled() or is_open():
		return false
	return open()


static func is_trigger(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key := event as InputEventKey
	return key.pressed and not key.echo and (key.keycode == TRIGGER_KEY or key.physical_keycode == TRIGGER_KEY)


func is_open() -> bool:
	return _overlay != null


func get_overlay() -> DevFeedbackOverlay:
	return _overlay


func get_last_saved_dir() -> String:
	return _last_saved_dir


## Freezes the game and shows the overlay; image = null grabs the current frame.
func open(image: Image = null) -> bool:
	if is_open() or not is_enabled() or not is_inside_tree():
		return false
	_image = image if image != null else capture_frame()
	GameManager.request_pause(PAUSE_REASON)
	# Last child of the root: its input handlers run before the game's (reverse tree order).
	if get_parent() != null and get_index() != get_parent().get_child_count() - 1:
		get_parent().move_child(self, -1)
	_overlay = DevFeedbackOverlay.new()
	_overlay.name = "Overlay"
	_overlay.setup(_image, get_viewport().get_visible_rect().size)
	_overlay.submitted.connect(_on_submitted)
	_overlay.cancelled.connect(_on_cancelled)
	add_child(_overlay)
	opened.emit()
	return true


## The frame as the player sees it; a grey placeholder where nothing is rendered (headless).
func capture_frame() -> Image:
	var image: Image = null
	var texture := get_viewport().get_texture()
	if texture != null and DisplayServer.get_name() != "headless":
		image = texture.get_image()
	if image == null or image.is_empty():
		var size := Vector2i(get_viewport().get_visible_rect().size)
		image = Image.create_empty(maxi(size.x, 1), maxi(size.y, 1), false, Image.FORMAT_RGBA8)
		image.fill(Color(0.12, 0.11, 0.15))
	elif image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image


## Writes the note now (the overlay calls this through its submitted signal).
func save_note(note: Dictionary) -> String:
	var record := build_record(note)
	var dir := DevFeedbackStore.save(root_dir, _image, record)
	_last_saved_dir = dir
	if dir.is_empty():
		_show_toast("Speichern fehlgeschlagen (siehe Ausgabe)", Color("#ff8a80"))
	else:
		_show_toast("Notiz gespeichert (#%d)" % int(record.get("id", 0)), Color("#5fcd62"))
		print("[DevFeedback] Notiz gespeichert: %s" % ProjectSettings.globalize_path(dir))
	return dir


## note.json content: the overlay note in image pixels and relative units plus the context.
func build_record(note: Dictionary) -> Dictionary:
	var view_size: Vector2 = note.get("view_size", get_viewport().get_visible_rect().size)
	var image_size := Vector2(_image.get_size()) if _image != null else view_size
	var scale := image_size / view_size if view_size.x > 0.0 and view_size.y > 0.0 else Vector2.ONE
	var tree_root := get_tree().root
	var marks: Array = []
	var number := 0
	for mark: Dictionary in note.get("marks", []):
		number += 1
		var rect: Rect2 = mark["rect"]
		var pixels := Rect2i(Vector2i((rect.position * scale).round()), Vector2i((rect.size * scale).round()))
		pixels = pixels.intersection(Rect2i(Vector2i.ZERO, Vector2i(image_size)))
		marks.append({
			"nr": number,
			"note": str(mark.get("note", "")),
			"rect_px": {"x": pixels.position.x, "y": pixels.position.y, "w": pixels.size.x, "h": pixels.size.y},
			"rect_rel": {
				"x": snappedf(rect.position.x / view_size.x, 0.0001), "y": snappedf(rect.position.y / view_size.y, 0.0001),
				"w": snappedf(rect.size.x / view_size.x, 0.0001), "h": snappedf(rect.size.y / view_size.y, 0.0001),
			},
			"rect_view": {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y},
			"ui_nodes": DevFeedbackContext.ui_nodes_in(tree_root, rect, self),
			"world_nodes": DevFeedbackContext.world_nodes_in(tree_root, rect, self),
		})
	var strokes: Array = []
	for line: PackedVector2Array in note.get("strokes", []):
		var points: Array = []
		for p in line:
			var px := (p * scale).round()
			points.append([int(px.x), int(px.y)])
		strokes.append({"points_px": points})
	var context := DevFeedbackContext.collect(get_tree(), self)
	return {
		"time": Time.get_datetime_string_from_system(false, false),
		"unix": int(Time.get_unix_time_from_system()),
		"version": version_info(),
		"text": str(note.get("text", "")),
		"categories": note.get("categories", []),
		"location": context.get("location", ""),
		"image_size": [int(image_size.x), int(image_size.y)],
		"view_size": [view_size.x, view_size.y],
		"marks": marks,
		"strokes": strokes,
		"context": context,
	}


## Game version, engine version and (when run from the repository) git branch and commit.
static func version_info() -> Dictionary:
	var info := {
		"game": str(ProjectSettings.get_setting("application/config/version", "")),
		"engine": str(Engine.get_version_info().get("string", "")),
		"debug_build": OS.is_debug_build(),
	}
	var head := _read_text("res://.git/HEAD")
	if head.begins_with("ref:"):
		var ref := head.substr(4).strip_edges()
		info["branch"] = ref.trim_prefix("refs/heads/")
		var commit := _read_text("res://.git/" + ref)
		if commit.is_empty():
			for line in _read_text("res://.git/packed-refs").split("\n"):
				if line.ends_with(" " + ref):
					commit = line.get_slice(" ", 0)
					break
		if not commit.is_empty():
			info["commit"] = commit.substr(0, 10)
	elif not head.is_empty():
		info["commit"] = head.substr(0, 10)
	return info


static func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text().strip_edges() if file != null else ""


func _on_submitted(note: Dictionary) -> void:
	_close(save_note(note))


func _on_cancelled() -> void:
	_close("")


func _close(saved_dir: String) -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
	closed.emit(saved_dir)
	for i in release_delay_frames:
		await get_tree().process_frame
		# Opened again in the meantime: that overlay keeps the pause.
		if is_open():
			return
	GameManager.release_pause(PAUSE_REASON)


func _show_toast(text: String, color: Color) -> void:
	if _toast_layer == null:
		_toast_layer = CanvasLayer.new()
		_toast_layer.name = "Toast"
		_toast_layer.layer = TOAST_LAYER
		add_child(_toast_layer)
	for child in _toast_layer.get_children():
		child.queue_free()
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.07, 0.06, 0.1, 0.92)
	box.border_color = color
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(10.0)
	panel.add_theme_stylebox_override(&"panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_font_size_override(&"font_size", 18)
	panel.add_child(label)
	_toast_layer.add_child(panel)
	panel.position = Vector2(16, 16)
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.set_ignore_time_scale(true)
	_toast_tween.tween_interval(TOAST_SECONDS)
	_toast_tween.tween_property(panel, ^"modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(panel.queue_free)

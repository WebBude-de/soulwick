extends GutTest
## Dev feedback tool (F9): overlay opens and closes, the pause is requested and released, marks
## are dragged and removed, saving writes screenshot, marked copy, note.json with context and an
## index line, UI and world nodes under a mark are found, and nothing happens in release builds.
## Notes go to a test folder (DevFeedback.root_dir), the save game is never touched.

const TEST_ROOT := "user://test_dev_feedback"

var _old_save_path: String
var _old_root: String
var _old_override: int
var _old_delay: int


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_dev_feedback_save.cfg"
	_old_root = DevFeedback.root_dir
	_old_override = DevFeedback.debug_override
	_old_delay = DevFeedback.release_delay_frames
	DevFeedback.root_dir = TEST_ROOT
	DevFeedback.release_delay_frames = 0


func after_all() -> void:
	_wipe(TEST_ROOT)
	DevFeedback.root_dir = _old_root
	DevFeedback.debug_override = _old_override
	DevFeedback.release_delay_frames = _old_delay
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	_wipe(TEST_ROOT)
	DevFeedback.debug_override = 1


func after_each() -> void:
	GameManager.clear_pause_reasons()


func test_overlay_opens_and_closes_with_the_pause() -> void:
	var feedback := _feedback()
	assert_true(feedback.open(_image()), "F9 tool opens")
	assert_true(feedback.is_open())
	assert_not_null(feedback.get_overlay())
	assert_eq(feedback.get_overlay().layer, DevFeedbackOverlay.LAYER)
	assert_true(GameManager.has_pause_reason(DevFeedback.PAUSE_REASON), "pause requested")
	assert_true(get_tree().paused)
	assert_eq(feedback.get_overlay().process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_false(feedback.open(_image()), "a second open is ignored")

	feedback.get_overlay().cancel()
	assert_false(feedback.is_open(), "overlay closed")
	assert_false(GameManager.has_pause_reason(DevFeedback.PAUSE_REASON), "pause released")
	assert_false(get_tree().paused)
	assert_false(DirAccess.dir_exists_absolute(TEST_ROOT), "cancel writes nothing")


func test_f9_opens_the_overlay() -> void:
	var feedback := _feedback()
	assert_true(feedback.handle_event(_f9()))
	assert_true(feedback.is_open())
	assert_false(feedback.handle_event(_f9()), "F9 while open does nothing")
	feedback.get_overlay().cancel()


func test_nothing_happens_in_release_builds() -> void:
	DevFeedback.debug_override = 0
	assert_false(DevFeedback.is_enabled())
	assert_null(DevFeedback.install(get_tree().root), "no node in release builds")
	var feedback := _feedback()
	assert_false(feedback.handle_event(_f9()))
	assert_false(feedback.open(_image()))
	assert_false(feedback.is_open())
	assert_false(GameManager.has_pause_reason(DevFeedback.PAUSE_REASON))


func test_drag_rectangle_and_remove_it() -> void:
	var overlay := _overlay()
	_drag(overlay, Vector2(100, 100), Vector2(300, 250))
	assert_eq(overlay.mark_count(), 1)
	var rect := overlay.get_mark_rect(0)
	assert_almost_eq(rect.position, Vector2(100, 100), Vector2.ONE)
	assert_almost_eq(rect.size, Vector2(200, 150), Vector2.ONE)

	_drag(overlay, Vector2(400, 400), Vector2(402, 401))
	assert_eq(overlay.mark_count(), 1, "a click is no rectangle")
	_drag(overlay, Vector2(600, 300), Vector2(500, 200))
	assert_eq(overlay.mark_count(), 2, "dragging up-left works too")
	assert_almost_eq(overlay.get_mark_rect(1).position, Vector2(500, 200), Vector2.ONE)

	overlay.handle_canvas_event(_click(Vector2(150, 150), MOUSE_BUTTON_RIGHT, true))
	assert_eq(overlay.mark_count(), 1, "right click removes the mark under the cursor")
	assert_almost_eq(overlay.get_mark_rect(0).position, Vector2(500, 200), Vector2.ONE, "the rest is renumbered")
	overlay.handle_canvas_event(_click(Vector2(10, 600), MOUSE_BUTTON_RIGHT, true))
	assert_eq(overlay.mark_count(), 1, "right click on nothing removes nothing")


func test_shift_drag_draws_a_stroke() -> void:
	var overlay := _overlay()
	var press := _click(Vector2(50, 50), MOUSE_BUTTON_LEFT, true)
	press.shift_pressed = true
	overlay.handle_canvas_event(press)
	for x in range(60, 200, 10):
		overlay.handle_canvas_event(_motion(Vector2(x, 50)))
	overlay.handle_canvas_event(_click(Vector2(200, 50), MOUSE_BUTTON_LEFT, false))
	assert_eq(overlay.strokes.size(), 1)
	assert_eq(overlay.mark_count(), 0)
	assert_gt(overlay.strokes[0].size(), 5)
	assert_true(overlay.remove_mark_at(Vector2(120, 52)), "right click near the stroke removes it")
	assert_eq(overlay.strokes.size(), 0)


func test_save_writes_three_files_and_an_index_line() -> void:
	var feedback := _feedback()
	var image := _image()
	assert_true(feedback.open(image))
	var overlay := feedback.get_overlay()
	var view := get_tree().root.get_visible_rect().size
	overlay.add_mark(Rect2(view * 0.25, view * 0.25), "Rahmen zu dunkel")
	overlay.set_text("Der Knopf ist kaum lesbar\nzweite Zeile")
	overlay.set_category("UI", true)
	overlay.set_category("Licht", true)
	var closed_dirs: Array[String] = []
	feedback.closed.connect(func(dir: String) -> void: closed_dirs.append(dir))
	overlay.submit()

	assert_false(feedback.is_open())
	assert_false(GameManager.has_pause_reason(DevFeedback.PAUSE_REASON))
	assert_eq(closed_dirs.size(), 1)
	var dir := closed_dirs[0]
	assert_true(dir.begins_with(TEST_ROOT), "note lands in the test folder: %s" % dir)
	assert_true(dir.ends_with("_1"), "first note has number 1")
	for file in [DevFeedbackStore.SCREENSHOT_FILE, DevFeedbackStore.MARKED_FILE, DevFeedbackStore.NOTE_FILE]:
		assert_true(FileAccess.file_exists(dir.path_join(file)), "%s written" % file)

	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(DevFeedbackStore.NOTE_FILE)))
	assert_eq(record["text"], "Der Knopf ist kaum lesbar\nzweite Zeile")
	assert_eq(record["categories"], ["UI", "Licht"])
	assert_eq(int(record["id"]), 1)
	assert_eq((record["marks"] as Array).size(), 1)
	var mark: Dictionary = record["marks"][0]
	assert_eq(mark["note"], "Rahmen zu dunkel")
	assert_almost_eq(float(mark["rect_rel"]["x"]), 0.25, 0.001)
	assert_almost_eq(float(mark["rect_rel"]["w"]), 0.25, 0.001)
	assert_almost_eq(int(mark["rect_px"]["x"]), int(image.get_width() * 0.25), 1, "pixels follow the image size")
	assert_true(mark.has("ui_nodes") and mark.has("world_nodes"))
	var context: Dictionary = record["context"]
	for key in ["scene", "phase", "window", "camera", "players", "location"]:
		assert_true(context.has(key), "context has %s" % key)
	assert_true((record["version"] as Dictionary).has("engine"))

	var marked := Image.load_from_file(ProjectSettings.globalize_path(dir.path_join(DevFeedbackStore.MARKED_FILE)))
	var edge := Vector2i(int(mark["rect_px"]["x"]) + int(mark["rect_px"]["w"]) - 1, int(mark["rect_px"]["y"]) + int(mark["rect_px"]["h"]) / 2)
	assert_gt(marked.get_pixelv(edge).r, 0.9, "the mark is burnt into marked.png")
	var shot := Image.load_from_file(ProjectSettings.globalize_path(dir.path_join(DevFeedbackStore.SCREENSHOT_FILE)))
	assert_lt(shot.get_pixelv(edge).r, 0.5, "screenshot.png stays clean")

	var index := FileAccess.get_file_as_string(TEST_ROOT.path_join(DevFeedbackStore.INDEX_FILE))
	assert_string_contains(index, dir.get_file())
	assert_string_contains(index, "UI, Licht")
	assert_string_contains(index, "Der Knopf ist kaum lesbar zweite Zeile")

	assert_true(feedback.open(_image()))
	feedback.get_overlay().submit()
	assert_true(feedback.get_last_saved_dir().ends_with("_2"), "numbers count up")
	assert_eq(FileAccess.get_file_as_string(TEST_ROOT.path_join(DevFeedbackStore.INDEX_FILE)).count("](") , 2)


func test_ui_nodes_under_a_rectangle_are_found() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 7
	add_child_autofree(layer)
	var panel := Panel.new()
	panel.position = Vector2(20, 20)
	panel.size = Vector2(300, 200)
	layer.add_child(panel)
	var label := Label.new()
	label.text = "Testknopf"
	label.position = Vector2(30, 30)
	label.size = Vector2(100, 30)
	panel.add_child(label)
	var hidden := Label.new()
	hidden.text = "Versteckt"
	hidden.position = Vector2(30, 30)
	hidden.size = Vector2(100, 30)
	hidden.visible = false
	panel.add_child(hidden)

	var found := DevFeedbackContext.ui_nodes_in(get_tree().root, Rect2(60, 55, 20, 10))
	var texts := found.map(func(entry: Dictionary) -> String: return str(entry.get("text", "")))
	assert_has(texts, "Testknopf")
	assert_does_not_have(texts, "Versteckt", "hidden controls are skipped")
	var label_entry: Dictionary = found[texts.find("Testknopf")]
	assert_eq(label_entry["class"], "Label")
	assert_eq(label_entry["path"], str(label.get_path()))
	var paths := found.map(func(entry: Dictionary) -> String: return str(entry["path"]))
	assert_lt(paths.find(str(label.get_path())), paths.find(str(panel.get_path())), "smaller first")
	assert_lte(found.size(), DevFeedbackContext.MAX_NODES)

	var elsewhere := DevFeedbackContext.ui_nodes_in(get_tree().root, Rect2(900, 600, 10, 10))
	assert_does_not_have(elsewhere.map(func(entry: Dictionary) -> String: return str(entry["path"])), str(label.get_path()))


func test_world_nodes_under_a_rectangle_are_found() -> void:
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(Image.create_empty(32, 32, false, Image.FORMAT_RGBA8))
	sprite.position = Vector2(400, 300)
	layer.add_child(sprite)
	var found := DevFeedbackContext.world_nodes_in(get_tree().root, Rect2(390, 290, 20, 20))
	var paths := found.map(func(entry: Dictionary) -> String: return str(entry["path"]))
	assert_has(paths, str(sprite.get_path()))
	assert_eq(found[paths.find(str(sprite.get_path()))]["class"], "Sprite2D")
	var outside := DevFeedbackContext.world_nodes_in(get_tree().root, Rect2(10, 10, 5, 5))
	assert_does_not_have(outside.map(func(entry: Dictionary) -> String: return str(entry["path"])), str(sprite.get_path()))


func test_context_without_a_dungeon_does_not_fail() -> void:
	var context := DevFeedbackContext.collect(get_tree())
	assert_true(context.has("phase"))
	assert_false(context.has("dungeon"))
	assert_typeof(context["location"], TYPE_STRING)


func _feedback() -> DevFeedback:
	var feedback := DevFeedback.new()
	add_child_autofree(feedback)
	return feedback


func _overlay() -> DevFeedbackOverlay:
	var overlay := DevFeedbackOverlay.new()
	overlay.setup(_image(), get_tree().root.get_visible_rect().size)
	add_child_autofree(overlay)
	return overlay


func _image() -> Image:
	var size := Vector2i(get_tree().root.get_visible_rect().size)
	var image := Image.create_empty(maxi(size.x, 64), maxi(size.y, 36), false, Image.FORMAT_RGBA8)
	image.fill(Color(0.1, 0.2, 0.3))
	return image


func _drag(overlay: DevFeedbackOverlay, from: Vector2, to: Vector2) -> void:
	overlay.handle_canvas_event(_click(from, MOUSE_BUTTON_LEFT, true))
	overlay.handle_canvas_event(_motion(from.lerp(to, 0.5)))
	overlay.handle_canvas_event(_motion(to))
	overlay.handle_canvas_event(_click(to, MOUSE_BUTTON_LEFT, false))


func _click(at: Vector2, button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = button
	event.pressed = pressed
	return event


func _motion(at: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = at
	return event


func _f9() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_F9
	event.pressed = true
	return event


func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	for folder in dir.get_directories():
		_wipe(path.path_join(folder))
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)

extends GutTest
## Bug report tool (# / F9, touch button): overlay opens and closes, the pause is requested and
## released, # and F9 open it (# not while a text field has the focus), marks are dragged and
## removed (mouse and finger, long press), saving writes screenshot, marked copy, note.json with
## context, an index line and an outbox entry for the upload, UI and world nodes under a mark are
## found, the touch button only shows with touch, and nothing happens with the switch off.
## Reports go to a test folder (DevFeedback.root_dir), the save game is never touched.

const TEST_ROOT := "user://test_dev_feedback"
const TEST_CONSENT := "user://test_dev_feedback_consent.cfg"

var _old_save_path: String
var _old_root: String
var _old_override: int
var _old_delay: int
var _old_consent: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_dev_feedback_save.cfg"
	_old_root = DevFeedback.root_dir
	_old_override = DevFeedback.enabled_override
	_old_delay = DevFeedback.release_delay_frames
	DevFeedback.root_dir = TEST_ROOT
	DevFeedback.release_delay_frames = 0
	_old_consent = DevFeedback.consent_path
	DevFeedback.consent_path = TEST_CONSENT


func after_all() -> void:
	_wipe(TEST_ROOT)
	DirAccess.remove_absolute(TEST_CONSENT)
	DevFeedback.consent_path = _old_consent
	DevFeedback.root_dir = _old_root
	DevFeedback.enabled_override = _old_override
	DevFeedback.release_delay_frames = _old_delay
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	_wipe(TEST_ROOT)
	DevFeedback.enabled_override = 1
	# The privacy notice was confirmed (test_privacy_notice_before_the_first_send checks it).
	DevFeedback.store_consent()


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


func test_hash_key_opens_the_overlay() -> void:
	var feedback := _feedback()
	var by_keycode := _key(KEY_NUMBERSIGN)
	assert_true(DevFeedback.is_trigger(by_keycode), "# by its keycode (German keyboard)")
	var by_unicode := _key(KEY_3)
	by_unicode.unicode = 35
	assert_true(DevFeedback.is_trigger(by_unicode), "# typed as Shift+3 (US keyboard)")
	var by_place := _key(KEY_NONE)
	by_place.physical_keycode = KEY_BACKSLASH
	assert_true(DevFeedback.is_trigger(by_place), "the key at the place of German # on other layouts")
	assert_false(DevFeedback.is_trigger(_key(KEY_A)), "other keys do nothing")
	var echo := _key(KEY_NUMBERSIGN)
	echo.echo = true
	assert_false(DevFeedback.is_trigger(echo), "a held key does not repeat")
	assert_true(feedback.handle_event(by_keycode))
	assert_true(feedback.is_open())
	feedback.get_overlay().cancel()


func test_hash_key_is_typed_into_a_focused_text_field() -> void:
	var feedback := _feedback()
	var edit := LineEdit.new()
	add_child_autofree(edit)
	edit.grab_focus()
	assert_false(feedback.handle_event(_key(KEY_NUMBERSIGN)), "# stays a character in a text field")
	assert_false(feedback.is_open())
	assert_true(feedback.handle_event(_f9()), "F9 works anyway")
	feedback.get_overlay().cancel()
	edit.release_focus()


func test_nothing_happens_with_the_switch_off() -> void:
	DevFeedback.enabled_override = 0
	assert_false(DevFeedback.is_enabled())
	assert_null(DevFeedback.install(get_tree().root), "no node with the switch off")
	var feedback := _feedback()
	feedback.touch_override = 1
	assert_false(feedback.handle_event(_f9()))
	assert_false(feedback.handle_event(_key(KEY_NUMBERSIGN)))
	assert_false(feedback.open(_image()))
	assert_false(feedback.is_open())
	assert_false(feedback.wants_touch_button(), "no touch button either")
	assert_false(GameManager.has_pause_reason(DevFeedback.PAUSE_REASON))


func test_switch_rule() -> void:
	assert_true(DevFeedback.resolve_enabled("", null, OnlineConfig.ENV_LOCAL), "editor and local runs: on")
	assert_true(DevFeedback.resolve_enabled("", null, OnlineConfig.ENV_DEVELOPMENT), "development exports: on")
	assert_false(DevFeedback.resolve_enabled("", null, OnlineConfig.ENV_PRODUCTION), "production exports: off")
	assert_true(DevFeedback.resolve_enabled("", true, OnlineConfig.ENV_PRODUCTION), "project setting beats the environment")
	assert_false(DevFeedback.resolve_enabled("", false, OnlineConfig.ENV_DEVELOPMENT))
	assert_true(DevFeedback.resolve_enabled("1", false, OnlineConfig.ENV_PRODUCTION), "command line beats everything")
	assert_false(DevFeedback.resolve_enabled("0", true, OnlineConfig.ENV_LOCAL))
	assert_false(DevFeedback.resolve_enabled("", "yes", OnlineConfig.ENV_PRODUCTION), "a non-bool setting is ignored")


func test_touch_button_only_with_touch() -> void:
	var feedback := _feedback()
	assert_not_null(feedback.touch_button, "the temporary touch button exists")
	assert_eq(feedback.touch_button.layer, DevFeedbackTouchButton.LAYER)
	feedback.touch_override = 0
	feedback._process(0.0)
	assert_false(feedback.touch_button.visible, "hidden without touch")
	feedback.touch_override = 1
	feedback._process(0.0)
	assert_true(feedback.touch_button.visible, "shown with touch")
	var rect := feedback.touch_button.get_button_rect()
	var view := get_tree().root.get_visible_rect().size
	assert_almost_eq(rect.end.x, view.x - DevFeedbackTouchButton.MARGIN_RIGHT, 1.0, "at the right edge")
	assert_gte(rect.position.y, 60.0, "below the room line of the HUD")
	assert_lte(rect.size.x, 32.0, "small")
	assert_true(feedback.open(_image()))
	feedback._process(0.0)
	assert_false(feedback.touch_button.visible, "hidden while the overlay is open")
	feedback.get_overlay().cancel()
	feedback._process(0.0)
	assert_true(feedback.touch_button.visible)


func test_touch_button_moves_below_hud_text() -> void:
	var feedback := _feedback()
	feedback.touch_override = 1
	feedback._process(0.0)
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var view := get_tree().root.get_visible_rect().size
	var label := Label.new()
	label.text = "nächste Heilung in 8"
	label.position = Vector2(view.x - 200.0, 70.0)
	label.size = Vector2(190, 40)
	layer.add_child(label)
	var button := feedback.touch_button
	var later := Time.get_ticks_msec() + 1_000_000
	button.update_place(layer, feedback, later)
	assert_almost_eq(button.get_button_rect().position.y, 110.0 + DevFeedbackTouchButton.GAP, 0.5, "below the text")
	label.visible = false
	button.update_place(layer, feedback, later + DevFeedbackTouchButton.PLACE_INTERVAL_MSEC)
	assert_almost_eq(button.get_button_rect().position.y, DevFeedbackTouchButton.TOP, 0.5, "back up when the text is gone")


func test_touch_button_opens_the_phone_layout() -> void:
	var feedback := _feedback()
	feedback.touch_override = 1
	feedback.touch_button.button.pressed.emit()
	await wait_process_frames(1)
	assert_true(feedback.is_open(), "a tap on the bug button opens the overlay")
	assert_true(feedback.get_overlay().touch_mode, "phone layout")
	feedback.get_overlay().cancel()


func test_finger_drag_and_long_press() -> void:
	var overlay := _overlay(true)
	overlay.handle_canvas_event(_touch(0, Vector2(100, 100), true))
	overlay.handle_canvas_event(_finger_drag(0, Vector2(200, 180)))
	overlay.handle_canvas_event(_finger_drag(0, Vector2(300, 250)))
	overlay.handle_canvas_event(_touch(0, Vector2(300, 250), false))
	assert_eq(overlay.mark_count(), 1, "a finger drags a rectangle")
	assert_almost_eq(overlay.get_mark_rect(0).size, Vector2(200, 150), Vector2.ONE)

	_drag(overlay, Vector2(500, 300), Vector2(700, 400), InputEvent.DEVICE_ID_EMULATION)
	assert_eq(overlay.mark_count(), 1, "the emulated mouse of a phone draws nothing")

	overlay.handle_canvas_event(_touch(0, Vector2(150, 150), true))
	assert_false(overlay.check_long_press(Time.get_ticks_msec()), "a short touch removes nothing")
	assert_true(overlay.check_long_press(Time.get_ticks_msec() + DevFeedbackOverlay.LONG_PRESS_MSEC + 10), "long press removes the mark")
	assert_eq(overlay.mark_count(), 0)
	overlay.handle_canvas_event(_finger_drag(0, Vector2(400, 400)))
	overlay.handle_canvas_event(_touch(0, Vector2(400, 400), false))
	assert_eq(overlay.mark_count(), 0, "the finger after a long press draws nothing")

	overlay.handle_canvas_event(_touch(1, Vector2(600, 300), true))
	overlay.handle_canvas_event(_finger_drag(1, Vector2(605, 303)))
	assert_false(overlay.check_long_press(Time.get_ticks_msec() + 2000), "long press on nothing removes nothing")
	overlay.handle_canvas_event(_touch(1, Vector2(605, 303), false))


func test_overlay_texts_are_translated() -> void:
	var old_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var overlay := _overlay()
	var send := overlay.find_child("Send", true, false) as Button
	assert_eq(send.text, DevFeedbackTexts.t(&"BUG_REPORT_SEND"))
	assert_eq((overlay.find_child("Tab_bug", true, false) as Button).text, "Report a bug")
	assert_eq((overlay.find_child("Tab_idea", true, false) as Button).text, "Suggest an idea")
	assert_null(overlay.find_child("Category_ui", true, false), "no categories any more")
	assert_string_contains((overlay.find_child("Header", true, false) as Label).text, "#", "the key is named in the hint")
	assert_false((overlay.find_child("Privacy", true, false) as Label).text.is_empty(), "privacy line")
	TranslationServer.set_locale("de")
	assert_eq(DevFeedbackTexts.t(&"BUG_REPORT_SAVED"), "Danke! Meldung gespeichert")
	assert_eq(DevFeedbackTexts.kind_text("idea", 0), "Idee einreichen")
	assert_eq(DevFeedbackTexts.kind_text("bug", 0), "Fehler melden")
	assert_eq(DevFeedbackTexts.kind_text("nonsense", 0), "Fehler melden", "unknown kinds read as bug")
	TranslationServer.set_locale(old_locale)
	for key: StringName in DevFeedbackTexts.TEXTS:
		var pair: Array = DevFeedbackTexts.TEXTS[key]
		assert_eq(pair.size(), 2, "%s has en and de" % key)
		assert_eq(str(pair[0]).count("%"), str(pair[1]).count("%"), "%s: same placeholders" % key)


func test_privacy_notice_before_the_first_send() -> void:
	DirAccess.remove_absolute(TEST_CONSENT)
	assert_false(DevFeedback.has_consent())
	var feedback := _feedback()
	assert_true(feedback.open(_image()))
	var overlay := feedback.get_overlay()
	assert_true(overlay.needs_consent, "first report: notice needed")
	overlay.set_text("Test")
	overlay.submit()
	assert_true(feedback.is_open(), "not sent yet")
	assert_true(overlay.is_consent_open(), "notice shown")
	assert_not_null(overlay.find_child("ConsentOk", true, false))
	overlay.close_consent()
	assert_false(overlay.is_consent_open(), "back to the report")
	assert_false(DevFeedback.has_consent(), "nothing remembered when going back")
	overlay.submit()
	overlay.confirm_consent()
	assert_false(feedback.is_open(), "sent after confirming")
	assert_true(DevFeedback.has_consent(), "remembered")
	assert_true(FileAccess.file_exists(TEST_CONSENT), "in its own file, not the save")
	assert_false(feedback.get_last_saved_dir().is_empty())
	assert_true(feedback.open(_image()))
	assert_false(feedback.get_overlay().needs_consent, "only once")
	feedback.get_overlay().cancel()


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
	assert_eq(record["kind"], "bug", "the default tab is bug")
	assert_false(record.has("categories"), "no categories in note.json")
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
	assert_string_contains(index, "| Fehler |")
	assert_string_contains(index, "Der Knopf ist kaum lesbar zweite Zeile")

	var outbox := feedback.outbox
	assert_not_null(outbox)
	assert_eq(outbox.pending(), PackedStringArray([dir.get_file()]), "the report waits in the outbox")
	assert_true(outbox.outbox_path(dir.get_file()).begins_with(TEST_ROOT), "outbox in the test folder")
	var body: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(outbox.outbox_path(dir.get_file())))
	assert_eq(body["note"], "Der Knopf ist kaum lesbar\nzweite Zeile")
	assert_eq(body["kind"], "bug")
	assert_eq(body["categories"], [])
	assert_eq((body["marks"] as Array).size(), 1)
	assert_almost_eq(float(body["marks"][0]["x"]), 0.25, 0.001, "marks relative")
	assert_eq(body["marks"][0]["note"], "Rahmen zu dunkel")
	assert_eq(body["platform"], DevFeedbackUpload.platform())
	assert_has(["windows", "linux", "android", "ios", "macos", "web"], body["platform"])
	assert_eq(body["gameVersion"], OnlineConfig.get_game_version())
	assert_true((body["context"] as Dictionary).has("location"))
	assert_lte(DevFeedbackUpload.json_bytes(body["context"]), DevFeedbackUpload.MAX_CONTEXT_BYTES)
	var image_bytes := Marshalls.base64_to_raw(str(body["image"]))
	assert_gt(image_bytes.size(), 0, "screenshot attached")
	assert_lte(image_bytes.size(), DevFeedbackUpload.MAX_IMAGE_BYTES)
	assert_eq(image_bytes.slice(8, 12).get_string_from_ascii(), "WEBP", "lossy WebP")

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


func test_tabs_pick_bug_or_idea() -> void:
	var old_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("de")
	var overlay := _overlay()
	var bug_tab := overlay.find_child("Tab_bug", true, false) as Button
	var idea_tab := overlay.find_child("Tab_idea", true, false) as Button
	var note := overlay.find_child("Note", true, false) as TextEdit
	var header := overlay.find_child("Header", true, false) as Label
	assert_eq(overlay.get_kind(), "bug", "Fehler melden is the default")
	assert_true(bug_tab.button_pressed)
	assert_false(idea_tab.button_pressed)
	assert_string_contains(note.placeholder_text, "Was ist kaputt?")
	assert_string_starts_with(header.text, "FEHLER MELDEN")

	idea_tab.pressed.emit()
	assert_eq(overlay.get_kind(), "idea", "click on the tab")
	assert_string_contains(note.placeholder_text, "Was wünschst du dir?")
	assert_string_starts_with(header.text, "IDEE EINREICHEN")
	assert_false(bug_tab.button_pressed)

	overlay.set_text("Text bleibt")
	overlay.add_mark(Rect2(10, 10, 40, 40))
	var ctrl_tab := _key(KEY_TAB)
	ctrl_tab.ctrl_pressed = true
	overlay._input(ctrl_tab)
	assert_eq(overlay.get_kind(), "bug", "Ctrl+Tab switches")
	assert_eq(overlay.build_note()["text"], "Text bleibt", "switching keeps the note")
	assert_eq(overlay.mark_count(), 1, "and the marks")

	assert_true(overlay.handle_pad_button(_pad(JOY_BUTTON_RIGHT_SHOULDER)))
	assert_eq(overlay.get_kind(), "idea", "RB")
	assert_true(overlay.handle_pad_button(_pad(JOY_BUTTON_LEFT_SHOULDER)))
	assert_eq(overlay.get_kind(), "bug", "LB")
	assert_true(overlay.pad_mode, "pad hint shown")
	assert_eq((overlay.find_child("Status", true, false) as Label).text, DevFeedbackTexts.t(&"BUG_REPORT_KEYS_PAD"))
	overlay.set_kind("idea")
	overlay.set_kind("wish")
	assert_eq(overlay.get_kind(), "idea", "unknown kinds are ignored")
	assert_eq(overlay.build_note()["kind"], "idea")
	TranslationServer.set_locale(old_locale)


func test_phone_tabs_are_large() -> void:
	var overlay := _overlay(true)
	var tab := overlay.find_child("Tab_idea", true, false) as Button
	assert_gte(tab.custom_minimum_size.y, DevFeedbackOverlay.TAB_HEIGHT_TOUCH)
	assert_eq((overlay.find_child("Status", true, false) as Label).text, "", "no key hints on a phone")


func test_gamepad_sends_and_cancels() -> void:
	var feedback := _feedback()
	assert_true(feedback.open(_image()))
	var overlay := feedback.get_overlay()
	overlay.handle_pad_button(_pad(JOY_BUTTON_RIGHT_SHOULDER))
	overlay.set_text("Gilden-Chat wäre schön")
	var closed_dirs: Array[String] = []
	feedback.closed.connect(func(dir: String) -> void: closed_dirs.append(dir))
	overlay.handle_pad_button(_pad(JOY_BUTTON_START))
	assert_false(feedback.is_open(), "Start sends")
	assert_eq(closed_dirs.size(), 1)
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(closed_dirs[0].path_join(DevFeedbackStore.NOTE_FILE)))
	assert_eq(record["kind"], "idea")
	assert_eq(record["context"]["kind"], "idea")
	var index := FileAccess.get_file_as_string(TEST_ROOT.path_join(DevFeedbackStore.INDEX_FILE))
	assert_string_contains(index, "| Idee |")
	var body: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(feedback.outbox.outbox_path(closed_dirs[0].get_file())))
	assert_eq(body["kind"], "idea")

	assert_true(feedback.open(_image()))
	overlay = feedback.get_overlay()
	assert_eq(overlay.get_kind(), "bug", "every report starts as bug")
	overlay.set_text("etwas")
	overlay.handle_pad_button(_pad(JOY_BUTTON_B))
	assert_true(feedback.is_open(), "first B with content only warns")
	overlay.handle_pad_button(_pad(JOY_BUTTON_B))
	assert_false(feedback.is_open(), "second B discards")


func test_context_without_a_dungeon_does_not_fail() -> void:
	var context := DevFeedbackContext.collect(get_tree())
	assert_true(context.has("phase"))
	assert_false(context.has("dungeon"))
	assert_typeof(context["location"], TYPE_STRING)


func _feedback() -> DevFeedback:
	var feedback := DevFeedback.new()
	add_child_autofree(feedback)
	return feedback


func _overlay(touch := false) -> DevFeedbackOverlay:
	var overlay := DevFeedbackOverlay.new()
	overlay.touch_mode = touch
	overlay.setup(_image(), get_tree().root.get_visible_rect().size)
	add_child_autofree(overlay)
	return overlay


func _image() -> Image:
	var size := Vector2i(get_tree().root.get_visible_rect().size)
	var image := Image.create_empty(maxi(size.x, 64), maxi(size.y, 36), false, Image.FORMAT_RGBA8)
	image.fill(Color(0.1, 0.2, 0.3))
	return image


func _drag(overlay: DevFeedbackOverlay, from: Vector2, to: Vector2, device := 0) -> void:
	for event: InputEvent in [_click(from, MOUSE_BUTTON_LEFT, true), _motion(from.lerp(to, 0.5)), _motion(to),
			_click(to, MOUSE_BUTTON_LEFT, false)]:
		event.device = device
		overlay.handle_canvas_event(event)


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
	return _key(KEY_F9)


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _pad(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	return event


func _touch(index: int, at: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	return event


func _finger_drag(index: int, at: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at
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

extends GutTest
## Lighter sending in the web build (DevFeedback.light_save, report 17.10.2026 "since the last
## report the music loops again"): the frame is scaled to the upload size before anything is
## encoded, no marked.png is written, the upload is encoded one frame later (still paused), and
## every report carries the music state (context "music"). Desktop saving stays as it was
## (test_dev_feedback.gd). Reports go to a test folder, the save game is never touched.

const TEST_ROOT := "user://test_dev_feedback_web"
const TEST_CONSENT := "user://test_dev_feedback_web_consent.cfg"
## A high-DPI window: twice the upload size.
const BIG := Vector2i(2560, 1440)

var _old_save_path: String
var _old_root: String
var _old_override: int
var _old_delay: int
var _old_consent: String
var _old_light: bool


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_dev_feedback_web_save.cfg"
	_old_root = DevFeedback.root_dir
	_old_override = DevFeedback.enabled_override
	_old_delay = DevFeedback.release_delay_frames
	_old_consent = DevFeedback.consent_path
	_old_light = DevFeedback.light_save
	DevFeedback.root_dir = TEST_ROOT
	DevFeedback.release_delay_frames = 0
	DevFeedback.consent_path = TEST_CONSENT


func after_all() -> void:
	_wipe(TEST_ROOT)
	DirAccess.remove_absolute(TEST_CONSENT)
	DevFeedback.consent_path = _old_consent
	DevFeedback.root_dir = _old_root
	DevFeedback.enabled_override = _old_override
	DevFeedback.release_delay_frames = _old_delay
	DevFeedback.light_save = _old_light
	SaveManager.save_path = _old_save_path
	MusicPlayer.clear_handoff()


func before_each() -> void:
	_wipe(TEST_ROOT)
	DevFeedback.enabled_override = 1
	DevFeedback.light_save = true
	DevFeedback.store_consent()


func after_each() -> void:
	GameManager.clear_pause_reasons()
	DevFeedback.light_save = _old_light


func test_light_save_scales_skips_marked_and_uploads_a_frame_later() -> void:
	var music := MusicPlayer.new()
	add_child_autofree(music)
	music.play_track("dungeon_crypt", 0.0)
	var feedback := DevFeedback.new()
	add_child_autofree(feedback)
	var image := Image.create_empty(BIG.x, BIG.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.1, 0.2, 0.3))
	assert_true(feedback.open(image))
	var overlay := feedback.get_overlay()
	var view := get_tree().root.get_visible_rect().size
	overlay.add_mark(Rect2(view * 0.25, view * 0.25), "Musik loopt")
	overlay.set_text("Seit der letzten Meldung loopt die Musik")
	var closed_dirs: Array[String] = []
	feedback.closed.connect(func(dir: String) -> void: closed_dirs.append(dir))
	overlay.submit()

	assert_eq(closed_dirs.size(), 1)
	var dir := closed_dirs[0]
	assert_true(dir.begins_with(TEST_ROOT), "note lands in the test folder: %s" % dir)
	assert_eq(image.get_size(), BIG, "the caller's image is not changed")
	var shot := Image.load_from_file(ProjectSettings.globalize_path(dir.path_join(DevFeedbackStore.SCREENSHOT_FILE)))
	assert_not_null(shot)
	assert_eq(shot.get_size(), DevFeedbackUpload.fit_size(BIG, DevFeedbackUpload.MAX_IMAGE_SIZE), "saved at upload size")
	assert_false(FileAccess.file_exists(dir.path_join(DevFeedbackStore.MARKED_FILE)), "no marked.png in the browser")
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(DevFeedbackStore.NOTE_FILE)))
	assert_eq(int(record["image_size"][0]), shot.get_width(), "note.json has the saved size")
	assert_eq(int(record["image_size"][1]), shot.get_height())
	var mark: Dictionary = record["marks"][0]
	assert_almost_eq(int(mark["rect_px"]["x"]), int(shot.get_width() * 0.25), 1, "mark pixels follow the saved image")
	assert_almost_eq(float(mark["rect_rel"]["x"]), 0.25, 0.001)
	var context: Dictionary = record["context"]
	assert_true(context.has("music"), "the music state is in every report")
	assert_eq(context["music"]["track"], "dungeon_crypt")
	assert_true((context["music"] as Dictionary).has("stalls"))
	var index := FileAccess.get_file_as_string(TEST_ROOT.path_join(DevFeedbackStore.INDEX_FILE))
	assert_string_contains(index, "%s/%s" % [dir.get_file(), DevFeedbackStore.SCREENSHOT_FILE], "index links the screenshot")

	assert_eq(feedback.outbox.pending(), PackedStringArray(), "the upload is encoded a frame later")
	await wait_process_frames(2)
	assert_eq(feedback.outbox.pending(), PackedStringArray([dir.get_file()]), "then it waits in the outbox")
	var body: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(feedback.outbox.outbox_path(dir.get_file())))
	var bytes := Marshalls.base64_to_raw(str(body["image"]))
	assert_eq(bytes.slice(8, 12).get_string_from_ascii(), "WEBP")
	assert_almost_eq(float(body["marks"][0]["x"]), 0.25, 0.001)
	assert_true((body["context"] as Dictionary).has("music"), "the music state goes to the server too")


func test_desktop_save_keeps_full_size_and_marked_copy() -> void:
	DevFeedback.light_save = false
	var feedback := DevFeedback.new()
	add_child_autofree(feedback)
	var image := Image.create_empty(BIG.x, BIG.y, false, Image.FORMAT_RGBA8)
	assert_true(feedback.open(image))
	var closed_dirs: Array[String] = []
	feedback.closed.connect(func(dir: String) -> void: closed_dirs.append(dir))
	feedback.get_overlay().submit()
	var dir := closed_dirs[0]
	assert_true(FileAccess.file_exists(dir.path_join(DevFeedbackStore.MARKED_FILE)))
	var shot := Image.load_from_file(ProjectSettings.globalize_path(dir.path_join(DevFeedbackStore.SCREENSHOT_FILE)))
	assert_eq(shot.get_size(), BIG)
	assert_eq(feedback.outbox.pending(), PackedStringArray([dir.get_file()]), "queued at once")


func test_shrink_to_upload_size() -> void:
	var small := Image.create_empty(640, 360, false, Image.FORMAT_RGBA8)
	assert_same(DevFeedback.shrink_to_upload_size(small), small, "fits: the same image")
	var big := Image.create_empty(BIG.x, BIG.y, false, Image.FORMAT_RGBA8)
	var shrunk := DevFeedback.shrink_to_upload_size(big)
	assert_eq(shrunk.get_size(), DevFeedbackUpload.MAX_IMAGE_SIZE)
	assert_eq(big.get_size(), BIG, "a copy")
	assert_null(DevFeedback.shrink_to_upload_size(null))


func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	for folder in dir.get_directories():
		_wipe(path.path_join(folder))
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)

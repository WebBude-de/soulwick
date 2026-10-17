class_name DevFeedback
extends Node
## Bug report tool (beta: for every player while bug reports are switched on, see is_enabled):
## Ctrl + B (Cmd + B on macOS; 65 % keyboards have no F keys without Fn, 17.10.2026), the key #
## (German keyboard; the same physical key elsewhere) or F9, on a gamepad Back (Select) + Start
## pressed together (handle_pad_event), or the small
## touch button at the top right (DevFeedbackTouchButton, temporary) grabs the current frame
## (before anything of the tool is drawn), freezes the game through the regular pause system
## (pause reason &"dev_feedback", D-043) and opens DevFeedbackOverlay. There the player picks the
## tab "Fehler melden" (kind "bug", default) or "Idee einreichen" ("idea"), marks rectangles and
## types notes; sending writes screenshot, marked copy, note.json with context
## (DevFeedbackContext) and a line in index.md under root_dir (DevFeedbackStore), and queues the
## report for the platform API (DevFeedbackOutbox, POST /bug-reports, in the background).
## Evaluate with tools/collect_feedback.py (docs/feedback/README.md).
## No autoload (AGENTS.md §6.5): GameManager._ready() calls install() once; with the switch off no
## node is created. Headless runs (tools, GUT, bot) carry the node but ignore the keys and send
## nothing on their own; tests drive open(), the overlay and the outbox directly and point root_dir
## at a test folder, so nothing ever touches the real feedback folder or the save game.

signal opened
## saved_dir: folder of the written note, "" when discarded or failed.
signal closed(saved_dir: String)

const PAUSE_REASON := &"dev_feedback"
const NODE_NAME := &"DevFeedback"
## Second key on every layout.
const TRIGGER_KEY := KEY_F9
## The # key: its label on a German keyboard, and its physical place (US backslash, the ISO key
## next to Enter) so other layouts have a sensible key at the same spot.
const HASH_KEY := KEY_NUMBERSIGN
const HASH_PHYSICAL_KEY := KEY_BACKSLASH
## Main shortcut: Ctrl + this key (Cmd on macOS). B is bound nowhere else (InputMap incl. the
## built-in ui_* actions, GamepadInput, modal hotkeys; checked 17.10.2026) and types nothing.
const SHORTCUT_KEY := KEY_B
## Gamepad: these two buttons pressed together open the tool (Start alone pauses, Back alone opens
## the overview, D-163).
const PAD_COMBO: Array[int] = [JOY_BUTTON_BACK, JOY_BUTTON_START]
## Both within this time count as the combo (TESTWERT). Back or Start alone reach the game at most
## this much later (held back, then replayed).
const PAD_COMBO_MSEC := 250
## Meta of a replayed pad event: it passes the tool untouched.
const REPLAY_META := &"dev_feedback_replay"
const TOAST_LAYER := 121
const TOAST_SECONDS := 2.4
const SENT_TOAST_SECONDS := 1.6
## Switch (project setting, optional): true/false beats the environment rule. Not in project.godot
## yet: without it, the environment decides.
const SETTING_ENABLED := "soulwick/beta/bug_reports"
## Command-line switch after "--": bug_reports=0 or bug_reports=1 (strongest).
const ARG_ENABLED := "bug_reports"
## Preloaded: works before the global class cache knows NetDiagnostics (new file).
const NetDiagnosticsScript := preload("res://online/net_diagnostics.gd")

## Where the notes go (user://dev_feedback = %APPDATA%/Godot/app_userdata/Soulwick/dev_feedback).
static var root_dir := "user://dev_feedback"
## The privacy notice was confirmed on this installation (own file, never the save game; tests
## point it elsewhere).
static var consent_path := "user://bug_report_consent.cfg"
## -1: follow the switch (is_enabled); 0: force off (tests); 1: force on.
static var enabled_override := -1
## The pause is released this many frames after the overlay closed, so the key or click that
## closed it is no longer "just pressed" when the game runs again. Tests set 0 (synchronous).
static var release_delay_frames := 2
## Lighter sending for the browser, which runs game, encoding and file system on one thread
## (feedback 17.10.2026): the frame is scaled to the upload size (DevFeedbackUpload.MAX_IMAGE_SIZE,
## the window may be 2560x1440) before anything is encoded, no marked.png is written (nobody opens
## user:// in a browser; the server copy is evaluated) and the upload (WebP) is encoded one frame
## later, still under the pause. On by default in the web build; tests switch it on.
static var light_save := OS.has_feature("web")

static var _enabled_cache := -1

var outbox: DevFeedbackOutbox = null
## TEMPORÄR (Beta): the bug button for phones.
var touch_button: DevFeedbackTouchButton = null
## Touch in use, for tests (-1 = ask TouchState and the own finger detection).
var touch_override := -1

var _overlay: DevFeedbackOverlay = null
var _image: Image = null
var _toast_layer: CanvasLayer = null
var _toast_tween: Tween = null
var _last_saved_dir := ""
## A finger touched the screen since the last keyboard or real mouse input (the TouchOverlay only
## reports touches during a run; the button is wanted in the menus too).
var _finger_seen := false
var _opening := false
## A gamepad button came after the last key, mouse or touch input (the overlay names pad buttons).
var _pad_seen := false
## Replays a held-back pad event (tests capture them); invalid = Input.parse_input_event.
var replay := Callable()
## Back or Start waiting for its partner (PAD_COMBO_MSEC), null when none.
var _held_pad: InputEventJoypadButton = null
var _held_pad_msec := 0


## Bug reports on? Command line bug_reports=0/1, else the project setting soulwick/beta/bug_reports,
## else on in every environment except production (editor = local, development exports on,
## production exports off as long as nothing else is decided).
static func is_enabled() -> bool:
	if enabled_override >= 0:
		return enabled_override == 1
	if _enabled_cache < 0:
		var args := OnlineConfig.parse_args(OS.get_cmdline_user_args())
		var setting: Variant = ProjectSettings.get_setting(SETTING_ENABLED, null)
		var on := resolve_enabled(str(args.get(ARG_ENABLED, "")), setting, OnlineConfig.build_environment())
		_enabled_cache = 1 if on else 0
	return _enabled_cache == 1


## Pure rule of is_enabled() (tests).
static func resolve_enabled(arg: String, setting: Variant, environment: String) -> bool:
	match arg.strip_edges().to_lower():
		"1", "true", "on", "yes":
			return true
		"0", "false", "off", "no":
			return false
	if typeof(setting) == TYPE_BOOL:
		return setting
	return environment != OnlineConfig.ENV_PRODUCTION


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
	if outbox == null:
		outbox = DevFeedbackOutbox.new()
		outbox.name = "Outbox"
	outbox.root_dir = root_dir
	outbox.auto_send = DisplayServer.get_name() != "headless"
	if not outbox.sent.is_connected(_on_report_sent):
		outbox.sent.connect(_on_report_sent)
	if outbox.get_parent() == null:
		add_child(outbox)
	if touch_button == null:
		touch_button = DevFeedbackTouchButton.new()
		touch_button.name = "TouchButton"
		touch_button.tapped.connect(_on_touch_button)
		add_child(touch_button)


func _process(_delta: float) -> void:
	flush_pad(Time.get_ticks_msec())
	if touch_button != null:
		touch_button.set_wanted(wants_touch_button())
		if touch_button.visible:
			touch_button.update_place(get_tree().root, self)


## TEMPORÄR (Beta): the bug button is shown while touch is in use and the overlay is closed.
func wants_touch_button() -> bool:
	return is_enabled() and not is_open() and not _opening and is_touch_active()


func is_touch_active() -> bool:
	if touch_override >= 0:
		return touch_override == 1
	return _finger_seen or TouchState.shared().is_active()


func _input(event: InputEvent) -> void:
	_track_touch(event)
	if _overlay != null or DisplayServer.get_name() == "headless":
		return
	if handle_event(event):
		get_viewport().set_input_as_handled()


## Ctrl + B, # or F9 opens the overlay, a gamepad Back + Start too (handle_pad_event); true when the
## event was used. # is left alone while a text field has the focus (guild names, player name);
## Ctrl + B and F9 type nothing and always work.
func handle_event(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return handle_pad_event(event as InputEventJoypadButton, Time.get_ticks_msec())
	if not is_trigger(event) or not is_enabled() or is_open():
		return false
	if not (_is_f9(event) or is_shortcut(event)) and _text_field_focused():
		return false
	return open()


static func is_trigger(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	if _is_f9(key) or is_shortcut(key):
		return true
	return key.keycode == HASH_KEY or key.key_label == HASH_KEY or key.unicode == 35 or key.physical_keycode == HASH_PHYSICAL_KEY


## Ctrl + B (Cmd + B on macOS, where Ctrl + B stays the text caret key). The B as labelled on the
## layout; the physical key only when the layout reports none. Not with Alt: AltGr is Ctrl + Alt
## on Windows and types characters.
static func is_shortcut(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.alt_pressed or not key.is_command_or_control_pressed():
		return false
	if key.keycode != KEY_NONE:
		return key.keycode == SHORTCUT_KEY
	return key.physical_keycode == SHORTCUT_KEY


## The shortcut as shown in hints: "Cmd" on macOS, else ctrl_name ("Ctrl" / "Strg").
static func shortcut_text(ctrl_name: String) -> String:
	return "%s + B" % ("Cmd" if OS.has_feature("macos") else ctrl_name)


static func _is_f9(event: InputEvent) -> bool:
	var key := event as InputEventKey
	return key != null and (key.keycode == TRIGGER_KEY or key.physical_keycode == TRIGGER_KEY)


## Gamepad: Back (Select) and Start pressed together within PAD_COMBO_MSEC open the overlay. A press
## of either is held back that long and then replayed (flush_pad), so Start alone still pauses and
## Back alone still opens the overview, only up to PAD_COMBO_MSEC later; the combo itself never
## reaches the game. Releasing the button or pressing another one replays at once (order kept).
## true when the event was held back or used (the caller marks it handled).
func handle_pad_event(event: InputEventJoypadButton, now_msec: int) -> bool:
	if event.has_meta(REPLAY_META) or not is_enabled() or is_open():
		return false
	var combo := PAD_COMBO.has(int(event.button_index))
	if _held_pad == null:
		if not combo or not event.pressed:
			return false
		_held_pad = event
		_held_pad_msec = now_msec
		return true
	var partner := combo and event.pressed and event.device == _held_pad.device \
			and event.button_index != _held_pad.button_index and now_msec - _held_pad_msec <= PAD_COMBO_MSEC
	if partner:
		var held := _held_pad
		_held_pad = null
		if open():
			return true
		_replay(held)
		_replay(event)
		return true
	# Anything else of a pad while one waits: the waiting press first, then this event.
	flush_pad(now_msec, true)
	_replay(event)
	return true


## A held Back or Start goes to the game once the combo window is over (force: now).
func flush_pad(now_msec: int, force := false) -> void:
	if _held_pad == null or (not force and now_msec - _held_pad_msec <= PAD_COMBO_MSEC):
		return
	var held := _held_pad
	_held_pad = null
	_replay(held)


func is_pad_held() -> bool:
	return _held_pad != null


func _replay(event: InputEvent) -> void:
	event.set_meta(REPLAY_META, true)
	if replay.is_valid():
		replay.call(event)
	else:
		Input.parse_input_event(event)


func _text_field_focused() -> bool:
	var focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return focus is LineEdit or focus is TextEdit


func _track_touch(event: InputEvent) -> void:
	DevFeedbackContext.note_input(event)
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event is InputEventJoypadButton or absf((event as InputEventJoypadMotion).axis_value) > 0.5:
			_pad_seen = true
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch:
		_pad_seen = false
	if event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).pressed:
			_finger_seen = true
	elif event is InputEventKey:
		if event.is_pressed() and not OS.has_feature("mobile"):
			_finger_seen = false
	elif event is InputEventMouseButton:
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			_finger_seen = false


## TEMPORÄR (Beta): the bug button; hidden for one drawn frame so the screenshot does not show it.
func _on_touch_button() -> void:
	if is_open() or _opening or not is_enabled():
		return
	_opening = true
	touch_button.set_wanted(false)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	_opening = false
	open(null, true)


func is_open() -> bool:
	return _overlay != null


func get_overlay() -> DevFeedbackOverlay:
	return _overlay


func get_last_saved_dir() -> String:
	return _last_saved_dir


## Freezes the game and shows the overlay; image = null grabs the current frame. touch: true/false
## picks the phone layout (finger marks, no auto focus on the text field); null = is_touch_active().
func open(image: Image = null, touch: Variant = null) -> bool:
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
	_overlay.touch_mode = bool(touch) if touch != null else is_touch_active()
	_overlay.pad_mode = _pad_seen and not _overlay.touch_mode
	_overlay.needs_consent = not has_consent()
	_overlay.consent_given.connect(store_consent)
	_overlay.submitted.connect(_on_submitted)
	_overlay.cancelled.connect(_on_cancelled)
	add_child(_overlay)
	opened.emit()
	return true


## The privacy notice of the first send was confirmed here already.
static func has_consent() -> bool:
	var file := ConfigFile.new()
	return file.load(consent_path) == OK and bool(file.get_value("bug_reports", "consent", false))


static func store_consent() -> void:
	var file := ConfigFile.new()
	file.set_value("bug_reports", "consent", true)
	file.set_value("bug_reports", "time", Time.get_datetime_string_from_system(false, true))
	if file.save(consent_path) != OK:
		push_warning("DevFeedback: cannot write %s" % consent_path)


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


## Writes the note now (the overlay calls this through its submitted signal). With light_save the
## upload is queued one frame later (see there).
func save_note(note: Dictionary) -> String:
	if light_save:
		_image = shrink_to_upload_size(_image)
	var record := build_record(note)
	var dir := DevFeedbackStore.save(root_dir, _image, record, not light_save)
	_last_saved_dir = dir
	if dir.is_empty():
		_show_toast(DevFeedbackTexts.t(&"BUG_REPORT_SAVE_FAILED"), Color("#ff8a80"))
		return dir
	_show_toast(DevFeedbackTexts.kind_text(str(record.get("kind", "bug")), 3), Color("#5fcd62"))
	print("[DevFeedback] Meldung gespeichert: %s" % ProjectSettings.globalize_path(dir))
	if light_save and is_inside_tree():
		_queue_upload_next_frame(dir.get_file(), record, _image)
	else:
		queue_upload(dir.get_file(), record)
	return dir


## Puts the saved report into the outbox (DevFeedbackOutbox sends it in the background). image:
## the screenshot to attach (null = the current one).
func queue_upload(folder: String, record: Dictionary, image: Image = null) -> bool:
	if outbox == null:
		return false
	outbox.root_dir = root_dir
	return outbox.enqueue(folder, DevFeedbackUpload.build_body(record, image if image != null else _image))


## light_save: the WebP of the upload is encoded in the next frame, so saving and encoding do not
## block the browser in the same frame.
func _queue_upload_next_frame(folder: String, record: Dictionary, image: Image) -> void:
	await get_tree().process_frame
	queue_upload(folder, record, image)


## image scaled down (never up) to DevFeedbackUpload.MAX_IMAGE_SIZE, a copy (the caller's image
## stays as it is); the image itself when it already fits.
static func shrink_to_upload_size(image: Image) -> Image:
	if image == null or image.is_empty():
		return image
	var size := DevFeedbackUpload.fit_size(image.get_size(), DevFeedbackUpload.MAX_IMAGE_SIZE)
	if size == image.get_size():
		return image
	var small := image.duplicate() as Image
	if small.is_compressed():
		small.decompress()
	small.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	return small


## note.json content: the overlay note (kind "bug" or "idea") in image pixels and relative units
## plus the context.
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
	# Frame rate, main-thread stalls and, online, traffic, rtt and the last disconnect (online test
	# 16.10.2026).
	context["network"] = DevFeedbackContext.without_room_codes(NetDiagnosticsScript.snapshot())
	DevFeedbackContext.add_ping(context)
	# Music state, browser loop fix and frame gaps over 150 ms ("music loops" report 17.10.2026).
	var music := MusicPlayer.diagnostics_of(get_tree())
	if not music.is_empty():
		context["music"] = music
	var kind := DevFeedbackUpload.kind_of(note)
	context["kind"] = kind
	return {
		"time": Time.get_datetime_string_from_system(false, false),
		"unix": int(Time.get_unix_time_from_system()),
		"version": version_info(),
		"text": str(note.get("text", "")),
		"kind": kind,
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


func _on_report_sent(_folder: String, _report_id: String) -> void:
	_show_toast(DevFeedbackTexts.t(&"BUG_REPORT_SENT"), Color("#b9b3c9"), SENT_TOAST_SECONDS, 14)


func _show_toast(text: String, color: Color, seconds := TOAST_SECONDS, font_size := 18) -> void:
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
	label.add_theme_font_size_override(&"font_size", font_size)
	panel.add_child(label)
	_toast_layer.add_child(panel)
	panel.position = Vector2(16, 16)
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.set_ignore_time_scale(true)
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(panel, ^"modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(panel.queue_free)

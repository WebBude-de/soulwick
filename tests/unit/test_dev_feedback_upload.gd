extends GutTest
## Bug report upload (DevFeedbackOutbox, DevFeedbackUpload) against a fake HTTP layer (no
## network): 201 sends and clears the outbox, 404/unreachable/429/5xx stay for later, 400/413 are
## final (moved to rejected/, noted in upload.json and outbox/index.md), 400 invalid_image is sent
## once more as JPEG and 413 once more smaller, 429 pauses, 401 renews the login once.
## The body follows the contract: context at most 16 KiB (shrunk), screenshot at most 1.5 MiB and
## 1280x720, strokes thinned. Everything lives in a test folder; the save game is never touched.

const TEST_ROOT := "user://test_dev_feedback_upload"
const FOLDER := "2026-10-16_10-00-00_1"
const TOKEN := "player-token.c2ln"


## Answers from a queue keyed by "METHOD path"; records every request (as in test_api_client).
class FakeTransport extends HttpTransport:
	var answers: Dictionary = {}
	var requests: Array[Dictionary] = []

	func send(_owner: Node, method: HTTPClient.Method, url: String, headers: PackedStringArray, body: String, timeout: float) -> Dictionary:
		var path := url.substr(url.find("/", 8))
		var key := "%s %s" % [["GET", "HEAD", "POST", "PUT", "DELETE"][method] if method <= 4 else str(method), path]
		requests.append({"key": key, "url": url, "headers": headers, "body": body, "timeout": timeout})
		var queue: Array = answers.get(key, [])
		if queue.is_empty():
			return {"status": 0, "body": "", "error": ApiResult.UNREACHABLE}
		return queue.pop_front()

	func answer(status: int, body: Variant) -> void:
		var key := "POST /bug-reports"
		if not answers.has(key):
			answers[key] = []
		answers[key].append({"status": status, "body": JSON.stringify(body) if body != null else "", "error": ""})

	func header(index: int, name: String) -> String:
		for line: String in requests[index].headers:
			if line.to_lower().begins_with(name.to_lower() + ":"):
				return line.substr(name.length() + 1).strip_edges()
		return ""


var _old_save_path: String
var _fake: FakeTransport
var _outbox: DevFeedbackOutbox
var _renews: Array[bool] = []


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_dev_feedback_upload_save.cfg"


func after_all() -> void:
	_wipe(TEST_ROOT)
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	_wipe(TEST_ROOT)
	DirAccess.make_dir_recursive_absolute(TEST_ROOT.path_join(FOLDER))
	_renews.clear()
	_fake = FakeTransport.new()
	var api := ApiClient.new()
	api.transport = _fake
	_outbox = DevFeedbackOutbox.new()
	_outbox.root_dir = TEST_ROOT
	_outbox.api = api
	_outbox.auto_send = false
	_outbox.auth_provider = func(renew: bool) -> Dictionary:
		_renews.append(renew)
		return {"ok": true, "token": TOKEN, "base_url": "http://api.test/"}
	add_child_autofree(_outbox)


func test_created_report_leaves_the_outbox() -> void:
	assert_true(_outbox.enqueue(FOLDER, _body()))
	assert_eq(_outbox.pending(), PackedStringArray([FOLDER]))
	_fake.answer(201, {"id": "0b9d4a8e-1f7c-4d2a-9b1e-5c6d7e8f9a0b"})
	var sent_ids: Array[String] = []
	_outbox.sent.connect(func(_folder: String, id: String) -> void: sent_ids.append(id))
	var count: int = await _outbox.flush()
	assert_eq(count, 1)
	assert_eq(_outbox.pending().size(), 0, "outbox empty")
	assert_eq(sent_ids, ["0b9d4a8e-1f7c-4d2a-9b1e-5c6d7e8f9a0b"])
	assert_eq(_fake.requests.size(), 1)
	assert_eq(_fake.requests[0].url, "http://api.test/bug-reports")
	assert_eq(_fake.header(0, "Authorization"), "Bearer " + TOKEN, "player token")
	assert_eq(_fake.header(0, "Content-Type"), "application/json")
	assert_eq(_fake.requests[0].timeout, DevFeedbackOutbox.UPLOAD_TIMEOUT_SECONDS, "own timeout for the large body")
	assert_eq(JSON.parse_string(_fake.requests[0].body)["note"], "Knopf unlesbar")
	var state := _outbox.upload_state(FOLDER)
	assert_eq(state.get("status"), "sent")
	assert_eq(state.get("id"), "0b9d4a8e-1f7c-4d2a-9b1e-5c6d7e8f9a0b")
	assert_string_contains(FileAccess.get_file_as_string(_outbox.outbox_dir().path_join(DevFeedbackOutbox.LOG_FILE)), "| sent |")


func test_missing_route_and_offline_keep_the_report() -> void:
	_outbox.enqueue(FOLDER, _body())
	_fake.answer(404, {"error": "not_found"})
	assert_eq(await _outbox.flush(), 0)
	assert_eq(_outbox.pending(), PackedStringArray([FOLDER]), "404: tried again later")
	assert_true(_outbox.upload_state(FOLDER).is_empty())
	assert_eq(await _outbox.flush(), 0, "no answer at all")
	assert_eq(_outbox.pending(), PackedStringArray([FOLDER]), "offline: tried again later")
	_fake.answer(429, {"error": "rate_limited"})
	await _outbox.flush()
	_fake.answer(503, null)
	await _outbox.flush()
	assert_eq(_outbox.pending(), PackedStringArray([FOLDER]), "429 and 5xx: later")
	_fake.answer(201, {"id": "0b9d4a8e-1f7c-4d2a-9b1e-5c6d7e8f9a0b"})
	assert_eq(await _outbox.flush(), 1, "sent once the server is there")
	assert_eq(_outbox.pending().size(), 0)


func test_bad_request_is_noted_and_not_repeated() -> void:
	_outbox.enqueue(FOLDER, _body())
	_fake.answer(400, {"error": "validation_error", "message": "bad"})
	var rejected: Array[String] = []
	_outbox.rejected.connect(func(_folder: String, error: String) -> void: rejected.append(error))
	assert_eq(await _outbox.flush(), 0)
	assert_eq(_outbox.pending().size(), 0, "not sent again")
	assert_eq(rejected, ["validation_error"])
	assert_true(FileAccess.file_exists(_outbox.outbox_dir().path_join(DevFeedbackOutbox.REJECTED_DIR).path_join(FOLDER + ".json")), "kept in rejected/")
	var state := _outbox.upload_state(FOLDER)
	assert_eq(state.get("status"), "rejected")
	assert_eq(int(state.get("http_status", 0)), 400)
	assert_string_contains(FileAccess.get_file_as_string(_outbox.outbox_dir().path_join(DevFeedbackOutbox.LOG_FILE)), "validation_error 400")
	assert_eq(await _outbox.flush(), 0)
	assert_eq(_fake.requests.size(), 1, "nothing is sent a second time")


func test_too_large_is_sent_once_more_smaller() -> void:
	_screenshot()
	_outbox.enqueue(FOLDER, _body())
	_fake.answer(413, {"error": "payload_too_large"})
	_fake.answer(201, {"id": "0b9d4a8e-1f7c-4d2a-9b1e-5c6d7e8f9a0b"})
	assert_eq(await _outbox.flush(), 1, "sent with the smaller image")
	assert_eq(_fake.requests.size(), 2)
	var second: Dictionary = JSON.parse_string(_fake.requests[1].body)
	assert_false(second.has(DevFeedbackOutbox.KEY_SMALL), "bookkeeping keys are never sent")
	var image := Image.new()
	assert_eq(image.load_webp_from_buffer(Marshalls.base64_to_raw(str(second["image"]))), OK)
	assert_lte(image.get_width(), DevFeedbackUpload.SMALL_IMAGE_SIZE.x, "960x540 at most")


func test_too_large_twice_is_final() -> void:
	_screenshot()
	_outbox.enqueue(FOLDER, _body())
	_fake.answer(413, {"error": "payload_too_large"})
	_fake.answer(413, {"error": "payload_too_large"})
	await _outbox.flush()
	assert_eq(_fake.requests.size(), 2, "one smaller try, then no more")
	assert_eq(_outbox.pending().size(), 0)
	assert_eq(_outbox.upload_state(FOLDER).get("error"), "payload_too_large")


func test_invalid_image_is_sent_once_more_as_jpeg() -> void:
	_screenshot()
	_outbox.enqueue(FOLDER, _body())
	_fake.answer(400, {"error": "invalid_image"})
	_fake.answer(201, {"id": "0b9d4a8e-1f7c-4d2a-9b1e-5c6d7e8f9a0b"})
	assert_eq(await _outbox.flush(), 1)
	var second: Dictionary = JSON.parse_string(_fake.requests[1].body)
	var bytes := Marshalls.base64_to_raw(str(second["image"]))
	assert_eq(bytes[0], 0xFF, "JPEG magic bytes")
	assert_eq(bytes[1], 0xD8)


func test_invalid_image_without_screenshot_is_final() -> void:
	_outbox.enqueue(FOLDER, _body())
	_fake.answer(400, {"error": "invalid_image"})
	await _outbox.flush()
	assert_eq(_fake.requests.size(), 1)
	assert_eq(_outbox.upload_state(FOLDER).get("error"), "invalid_image")


func test_rate_limit_pauses_the_queue() -> void:
	_outbox.enqueue(FOLDER, _body())
	_fake.answer(429, {"error": "rate_limited"})
	await _outbox.flush()
	assert_eq(_outbox.pending(), PackedStringArray([FOLDER]), "kept")
	assert_gt(_outbox._next_try_msec, Time.get_ticks_msec() + int(DevFeedbackOutbox.RATE_LIMIT_SECONDS * 1000.0) - 5000, "pause")


func test_unauthorized_renews_the_login_once() -> void:
	_outbox.enqueue(FOLDER, _body())
	_fake.answer(401, {"error": "unauthorized"})
	_fake.answer(201, {"id": "0b9d4a8e-1f7c-4d2a-9b1e-5c6d7e8f9a0b"})
	assert_eq(await _outbox.flush(), 1)
	assert_eq(_renews, [false, true], "logged in again after the 401")
	assert_eq(_fake.requests.size(), 2)


func test_failed_login_keeps_everything() -> void:
	_outbox.auth_provider = func(_renew: bool) -> Dictionary: return {"ok": false, "error": "unreachable"}
	_outbox.enqueue(FOLDER, _body())
	assert_eq(await _outbox.flush(), 0)
	assert_eq(_fake.requests.size(), 0, "nothing sent without a login")
	assert_eq(_outbox.pending(), PackedStringArray([FOLDER]))


func test_classify() -> void:
	assert_eq(DevFeedbackOutbox.classify(ApiResult.success(201, {})), DevFeedbackOutbox.Outcome.SENT)
	assert_eq(DevFeedbackOutbox.classify(ApiResult.from_http(201, "not json")), DevFeedbackOutbox.Outcome.SENT, "arrived even with an odd answer")
	assert_eq(DevFeedbackOutbox.classify(ApiResult.from_http(401, "")), DevFeedbackOutbox.Outcome.RENEW_LOGIN)
	for status in [400, 403, 413]:
		assert_eq(DevFeedbackOutbox.classify(ApiResult.from_http(status, "<html>")), DevFeedbackOutbox.Outcome.REJECTED, "%d is final" % status)
	for status in [0, 404, 408, 429, 500, 502, 503]:
		assert_eq(DevFeedbackOutbox.classify(ApiResult.failure("x", "", status)), DevFeedbackOutbox.Outcome.RETRY, "%d: later" % status)


func test_context_is_shrunk_to_16_kib() -> void:
	var nodes: Array = []
	for i in 40:
		nodes.append({"path": "/root/Game/Hud/Some/Very/Long/Path/Node%d" % i, "class": "Label", "text": "x".repeat(100)})
	var players: Array = []
	for i in 200:
		players.append({"position": [i, i], "note": "y".repeat(80)})
	var record := {
		"location": "Dungeon · Raum 7 · Krypta",
		"marks": [{"nr": 1, "ui_nodes": nodes, "world_nodes": nodes}, {"nr": 2, "ui_nodes": nodes, "world_nodes": nodes}],
		"context": {"scene": "res://scenes/game.tscn", "phase": "dungeon", "players": players, "dungeon": {"seed": 12345, "room_index": 7}},
		"version": {"game": "0.9.0"},
	}
	var context := DevFeedbackUpload.build_context(record)
	assert_lte(DevFeedbackUpload.json_bytes(context), DevFeedbackUpload.MAX_CONTEXT_BYTES)
	assert_eq(context["location"], "Dungeon · Raum 7 · Krypta", "named fields stay")
	assert_eq(context["scene"], "res://scenes/game.tscn")
	assert_eq(context["seed"], "12345")
	assert_true(context.has("truncated"), "dropped keys are listed")
	assert_has(context["truncated"], "players")
	var small := DevFeedbackUpload.build_context({"location": "Dorf", "context": {"phase": "village"}})
	assert_false(small.has("truncated"), "small contexts stay whole")
	assert_eq(small["phase"], "village")


func test_image_fits_the_limits() -> void:
	var noise := Image.create_from_data(1920, 1080, false, Image.FORMAT_RGB8, Crypto.new().generate_random_bytes(1920 * 1080 * 3))
	var bytes := DevFeedbackUpload.encode_image(noise)
	assert_gt(bytes.size(), 0)
	assert_lte(bytes.size(), DevFeedbackUpload.MAX_IMAGE_BYTES, "at most 1.5 MiB even for noise")
	var decoded := Image.new()
	assert_eq(decoded.load_webp_from_buffer(bytes), OK, "WebP")
	assert_lte(decoded.get_width(), 1280)
	assert_lte(decoded.get_height(), 720)
	var tight := DevFeedbackUpload.encode_image(noise, 60_000)
	assert_lte(tight.size(), 60_000, "made smaller until it fits")
	assert_eq(DevFeedbackUpload.fit_size(Vector2i(640, 360), Vector2i(1280, 720)), Vector2i(640, 360), "never scaled up")
	assert_eq(DevFeedbackUpload.fit_size(Vector2i(2560, 1600), Vector2i(1280, 720)), Vector2i(1152, 720))


func test_strokes_and_marks_are_relative_and_limited() -> void:
	var points: Array = []
	for i in 1000:
		points.append([i, 360])
	var record := {
		"image_size": [1000, 720],
		"strokes": [{"points_px": points}],
		"marks": [{"rect_rel": {"x": 0.9, "y": -0.1, "w": 0.5, "h": 0.2}, "note": "z".repeat(500)}],
	}
	var strokes := DevFeedbackUpload.relative_strokes(record, Vector2(1000, 720))
	assert_eq(strokes.size(), 1)
	assert_lte((strokes[0] as Array).size(), DevFeedbackUpload.MAX_STROKE_POINTS, "thinned")
	assert_almost_eq(float(strokes[0][strokes[0].size() - 1][0]), 0.999, 0.001, "the end point stays")
	assert_almost_eq(float(strokes[0][0][1]), 0.5, 0.001)
	var marks := DevFeedbackUpload.relative_marks(record)
	assert_almost_eq(float(marks[0]["y"]), 0.0, 0.0001, "clamped to 0..1")
	assert_lte(float(marks[0]["x"]) + float(marks[0]["w"]), 1.0001, "inside the image")
	assert_eq(str(marks[0]["note"]).length(), DevFeedbackUpload.MAX_MARK_NOTE)



func test_kind_defaults_to_bug() -> void:
	assert_eq(DevFeedbackUpload.kind_of({}), "bug", "older notes without kind are bugs")
	assert_eq(DevFeedbackUpload.kind_of({"kind": "idea"}), "idea")
	assert_eq(DevFeedbackUpload.kind_of({"kind": " IDEA "}), "idea")
	assert_eq(DevFeedbackUpload.kind_of({"kind": "wish"}), "bug", "unknown kinds are bugs")
	var body := DevFeedbackUpload.build_body({"text": "Mehr Hüte", "kind": "idea", "categories": ["ui"]}, null)
	assert_eq(body["kind"], "idea")
	assert_eq(body["categories"], [], "no categories any more")
	assert_eq(body["context"]["kind"], "idea", "also in the context (older servers drop unknown fields)")
	assert_eq(DevFeedbackUpload.build_body({"text": "x"}, null)["kind"], "bug")


func _screenshot() -> void:
	var image := Image.create_empty(1920, 1080, false, Image.FORMAT_RGB8)
	image.fill(Color(0.2, 0.3, 0.4))
	image.save_png(TEST_ROOT.path_join(FOLDER).path_join(DevFeedbackStore.SCREENSHOT_FILE))


func _body() -> Dictionary:
	return {"note": "Knopf unlesbar", "kind": "bug", "categories": [], "marks": [], "strokes": [], "context": {"location": "Dorf"},
		"gameVersion": "0.9.0", "platform": "windows", "image": "UklGRg=="}


func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	for folder in dir.get_directories():
		_wipe(path.path_join(folder))
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)

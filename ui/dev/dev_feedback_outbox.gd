class_name DevFeedbackOutbox
extends Node
## Upload queue of the bug reports (temporary, beta: as long as DevFeedback.is_enabled). Every saved
## report also lands as <root>/outbox/<folder>.json (the finished POST /bug-reports body,
## DevFeedbackUpload) and is sent from here in the background: right after saving, once shortly
## after the game start and then every RETRY_SECONDS while something is waiting. Nothing blocks and
## nothing pauses the game; without a server (offline, 404 while the route is missing, 429, 5xx) the
## file simply stays for the next try. A 401 renews the login once (guest login of OnlineSession).
## 400 invalid_image is sent once more as JPEG, 413 payload_too_large once more as a smaller image
## (both encoded again from the report's screenshot.png); 429 rate_limited waits RATE_LIMIT_SECONDS.
## Other 400 (validation_error), 403 (banned) and a second 400/413 are final: the file moves to
## outbox/rejected/ and is not sent again. Every outcome is written next to the report
## (<folder>/upload.json) and as a line into outbox/index.md.
## Uses the online code read-only: OnlineSession.of() for the login and a private ApiClient for the
## request (own timeout for the large body, lives under DevFeedback across scene changes).
## Tests replace auth_provider and api.transport (no network) and point root_dir at a test folder.

signal sent(folder: String, report_id: String)
signal rejected(folder: String, error: String)

const ROUTE := "/bug-reports"
const OUTBOX_DIR := "outbox"
const REJECTED_DIR := "rejected"
const LOG_FILE := "index.md"
const UPLOAD_FILE := "upload.json"
## TESTWERT: seconds between two rounds while reports are waiting.
const RETRY_SECONDS := 180.0
## TESTWERT: first round after the game start (the menu has settled by then).
const FIRST_TRY_SECONDS := 8.0
## TESTWERT: seconds one upload of up to ~2 MB may take (ApiClient default is 5 s).
const UPLOAD_TIMEOUT_SECONDS := 45.0
## TESTWERT: pause after 429 rate_limited (the server allows 10 reports per player and hour; the
## Retry-After header is not visible through ApiClient, so a fixed pause is used).
const RATE_LIMIT_SECONDS := 600.0
## Keys of the outbox file that are never sent (retry bookkeeping).
const KEY_JPEG := "_jpeg"
const KEY_SMALL := "_small"
## A round that hangs this long (its session node was freed with a scene) is abandoned.
const STUCK_SECONDS := 120.0
## Final answers: never sent again (validation_error, invalid_image, invalid_json, banned,
## payload_too_large).
const FINAL_STATUSES: Array[int] = [400, 403, 413, 422]

enum Outcome { SENT, RETRY, RENEW_LOGIN, REJECTED }

## Folder of the reports (DevFeedback.root_dir); the queue is <root_dir>/outbox.
var root_dir := DevFeedback.root_dir
## Request client of the uploads (tests swap its transport).
var api: ApiClient = null
## Login: func(renew: bool) -> Dictionary {ok, token, base_url, error}; may be a coroutine.
## Empty = OnlineSession.of(self) (guest login when needed).
var auth_provider: Callable = Callable()
## Rounds start on their own (off in headless runs and tests: they call flush()).
var auto_send := true

var _busy := false
var _busy_since_msec := 0
var _generation := 0
var _next_try_msec := 0
## Last retry reason logged per folder (a waiting report logs each new reason once, not every round).
var _last_retry: Dictionary[String, String] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if api == null:
		api = ApiClient.new()
		api.name = "ApiClient"
	if api.get_parent() == null:
		add_child(api)
	api.timeout = UPLOAD_TIMEOUT_SECONDS
	_next_try_msec = Time.get_ticks_msec() + int(FIRST_TRY_SECONDS * 1000.0)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _busy:
		if now - _busy_since_msec > int(STUCK_SECONDS * 1000.0):
			_busy = false
			_generation += 1
		return
	if not auto_send or now < _next_try_msec:
		return
	_next_try_msec = now + int(RETRY_SECONDS * 1000.0)
	if not pending().is_empty():
		flush()


func outbox_dir() -> String:
	return root_dir.path_join(OUTBOX_DIR)


func outbox_path(folder: String) -> String:
	return outbox_dir().path_join(folder + ".json")


## Queues body for the report folder; the next frame starts a round (auto_send).
func enqueue(folder: String, body: Dictionary) -> bool:
	if folder.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(outbox_dir())
	var file := FileAccess.open(outbox_path(folder), FileAccess.WRITE)
	if file == null:
		push_warning("DevFeedbackOutbox: cannot write %s" % outbox_path(folder))
		return false
	file.store_string(JSON.stringify(body))
	file.close()
	_next_try_msec = 0
	return true


## Report folders waiting to be sent, oldest first.
func pending() -> PackedStringArray:
	var result := PackedStringArray()
	var dir := DirAccess.open(outbox_dir())
	if dir == null:
		return result
	for file in dir.get_files():
		if file.ends_with(".json"):
			result.append(file.get_basename())
	result.sort()
	return result


func is_busy() -> bool:
	return _busy


## One round (coroutine): logs in, sends every waiting report until the server stops answering.
## Returns the number sent; 0 while another round runs.
func flush() -> int:
	if _busy:
		return 0
	var folders := pending()
	if folders.is_empty():
		return 0
	_busy = true
	_busy_since_msec = Time.get_ticks_msec()
	_generation += 1
	var generation := _generation
	var count := 0
	var auth: Dictionary = await _auth(false)
	if generation != _generation:
		return count
	if bool(auth.get("ok", false)):
		for folder in folders:
			var outcome: Outcome = await send_one(folder, auth)
			if generation != _generation:
				return count
			if outcome == Outcome.RENEW_LOGIN:
				auth = await _auth(true)
				if generation != _generation:
					return count
				if not bool(auth.get("ok", false)):
					break
				outcome = await send_one(folder, auth)
				if generation != _generation:
					return count
				if outcome == Outcome.RENEW_LOGIN:
					break
			if outcome == Outcome.SENT:
				count += 1
			elif outcome == Outcome.RETRY:
				break
	_busy = false
	return count


## Sends one queued report with auth {token, base_url} (coroutine).
func send_one(folder: String, auth: Dictionary) -> Outcome:
	var path := outbox_path(folder)
	if not FileAccess.file_exists(path):
		return Outcome.SENT
	var body: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (body is Dictionary):
		_reject(folder, "invalid_outbox_file", 0)
		return Outcome.REJECTED
	api.base_url = str(auth.get("base_url", api.base_url)).trim_suffix("/")
	api.token = str(auth.get("token", ""))
	api.timeout = UPLOAD_TIMEOUT_SECONDS
	var result: ApiResult = await api.request(HTTPClient.METHOD_POST, ROUTE, sendable(body))
	var outcome := classify(result)
	# The image is the problem: encode it again (JPEG, or smaller) and send once more.
	if outcome == Outcome.REJECTED and _repair_image(folder, body, result):
		_log(folder, "retry", "%s %d: Bild neu kodiert" % [result.error, result.status])
		result = await api.request(HTTPClient.METHOD_POST, ROUTE, sendable(body))
		outcome = classify(result)
	if result.status == 429:
		_next_try_msec = Time.get_ticks_msec() + int(RATE_LIMIT_SECONDS * 1000.0)
	match outcome:
		Outcome.SENT:
			_mark_sent(folder, str(result.get_field("id", "")))
		Outcome.REJECTED:
			_reject(folder, result.error, result.status)
		_:
			var reason := "%s %d" % [result.error, result.status]
			if _last_retry.get(folder, "") != reason:
				_last_retry[folder] = reason
				_log(folder, "retry", reason)
	return outcome


## The body without the bookkeeping keys (KEY_JPEG, KEY_SMALL).
static func sendable(body: Dictionary) -> Dictionary:
	var result := body.duplicate()
	result.erase(KEY_JPEG)
	result.erase(KEY_SMALL)
	return result


## After 400 invalid_image (once: JPEG) or 413 (once: smaller): new image from the report's
## screenshot.png into body and the outbox file. False when it was tried already or impossible.
func _repair_image(folder: String, body: Dictionary, result: ApiResult) -> bool:
	var jpeg := result.status == 400 and result.error == "invalid_image" and not body.has(KEY_JPEG)
	var small := result.status == 413 and not body.has(KEY_SMALL)
	if not jpeg and not small:
		return false
	var shot_path := root_dir.path_join(folder).path_join(DevFeedbackStore.SCREENSHOT_FILE)
	var screenshot: Image = null
	if FileAccess.file_exists(shot_path):
		screenshot = Image.load_from_file(ProjectSettings.globalize_path(shot_path))
	var image := DevFeedbackUpload.reencode(screenshot, jpeg or body.has(KEY_JPEG), small or body.has(KEY_SMALL))
	if image.is_empty():
		return false
	body["image"] = image
	body[KEY_JPEG if jpeg else KEY_SMALL] = true
	var file := FileAccess.open(outbox_path(folder), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(body))
		file.close()
	return true


## What to do with an answer: 2xx sent, 401 log in again, 400/403/413/422 give up, else later.
static func classify(result: ApiResult) -> Outcome:
	if result == null:
		return Outcome.RETRY
	if result.ok or (result.status >= 200 and result.status < 300):
		return Outcome.SENT
	if result.status == 401:
		return Outcome.RENEW_LOGIN
	if FINAL_STATUSES.has(result.status):
		return Outcome.REJECTED
	return Outcome.RETRY


## upload.json of a report folder ({} when it was never sent or rejected).
func upload_state(folder: String) -> Dictionary:
	var path := root_dir.path_join(folder).path_join(UPLOAD_FILE)
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


func _auth(renew: bool) -> Dictionary:
	if auth_provider.is_valid():
		var answer: Variant = await auth_provider.call(renew)
		return answer if answer is Dictionary else {"ok": false, "error": "no_auth"}
	return await _session_auth(renew)


## Login through the game's OnlineSession (created on demand, guest login without a dev key).
func _session_auth(renew: bool) -> Dictionary:
	if OnlineVersionCheck.is_locked():
		return {"ok": false, "error": ApiResult.UPDATE_REQUIRED}
	var session := OnlineSession.of(self)
	if session == null:
		return {"ok": false, "error": "no_session"}
	if renew:
		session.logout()
	var login: ApiResult = await session.ensure_login()
	if not is_instance_valid(session) or not login.ok or session.token.is_empty():
		return {"ok": false, "error": login.error if login != null else "no_login"}
	return {"ok": true, "token": session.token, "base_url": session.config.api_url}


func _mark_sent(folder: String, report_id: String) -> void:
	DirAccess.remove_absolute(outbox_path(folder))
	_write_state(folder, {"status": "sent", "id": report_id, "time": _now()})
	_log(folder, "sent", report_id)
	sent.emit(folder, report_id)


func _reject(folder: String, error: String, status: int) -> void:
	var target_dir := outbox_dir().path_join(REJECTED_DIR)
	DirAccess.make_dir_recursive_absolute(target_dir)
	var target := target_dir.path_join(folder + ".json")
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)
	if DirAccess.rename_absolute(outbox_path(folder), target) != OK:
		DirAccess.remove_absolute(outbox_path(folder))
	_write_state(folder, {"status": "rejected", "error": error, "http_status": status, "time": _now()})
	_log(folder, "rejected", "%s %d" % [error, status])
	rejected.emit(folder, error)


func _write_state(folder: String, state: Dictionary) -> void:
	var dir := root_dir.path_join(folder)
	if not DirAccess.dir_exists_absolute(dir):
		return
	var file := FileAccess.open(dir.path_join(UPLOAD_FILE), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(state, "\t"))
		file.close()


## One table row per attempt in outbox/index.md.
func _log(folder: String, status: String, detail: String) -> void:
	DirAccess.make_dir_recursive_absolute(outbox_dir())
	var path := outbox_dir().path_join(LOG_FILE)
	var exists := FileAccess.file_exists(path)
	var file := FileAccess.open(path, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if file == null:
		return
	if exists:
		file.seek_end()
	else:
		file.store_string("# Upload der Meldungen\n\nEine Zeile je Versuch (sent = angekommen, retry = später erneut, rejected = abgelehnt, wird nicht wiederholt).\n\n")
		file.store_string("| Zeit | Ordner | Status | Detail |\n| --- | --- | --- | --- |\n")
	file.store_string("| %s | %s | %s | %s |\n" % [_now(), folder, status, detail.replace("|", "/").strip_edges()])
	file.close()


static func _now() -> String:
	return Time.get_datetime_string_from_system(false, true)

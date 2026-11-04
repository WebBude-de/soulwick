class_name WebLoginFlow
extends RefCounted
## One login in the browser from the game (KF6, D-188; contracts login.ts, API KF5): start() asks
## the API for a request (POST /auth/web-login), opens the website page with the browser secret in
## its fragment (<page>#k=<secret>, the API's url carries it already) and shows only the user code
## ("ABC-DEF") that the website asks the player to type; the request code is only for polling. poll()
## asks every pollIntervalSeconds (POST /auth/web-login/poll) until the request is completed,
## failed or expired. Taking the finished session over is up to the caller
## (AccountService.finish_web_login): this class only follows the request.
## Secrets: the poll secret and the browser secret never show up on screen or in a log; the browser
## secret only goes into the opened (and the copied) link, never into url. Field names live in
## ApiClient.WEB_*.
## RefCounted on purpose: a poll still running when the panel closes ends here without touching it.

signal changed

enum Status { IDLE, STARTING, WAITING, CONFIRM, COMPLETED, FAILED, EXPIRED, CANCELLED }

## Poll states of the API (contracts WebLoginStatus; AWAITING_CONFIRM: the website waits for the
## player to confirm and type the user code).
const POLL_PENDING := "pending"
const POLL_AWAITING_CONFIRM := "awaiting_confirm"
const POLL_COMPLETED := "completed"
const POLL_FAILED := "failed"
const POLL_EXPIRED := "expired"
const NOT_FOUND := "web_login_not_found"
## Contracts WEB_LOGIN_POLL_INTERVAL_SECONDS; the answer's pollIntervalSeconds wins.
const DEFAULT_INTERVAL := 2.0
## Contracts WEB_LOGIN_TTL_SECONDS (TESTWERT on the server); the answer's expiresAt wins.
const DEFAULT_TTL_SECONDS := 600

## Opening the page: on in the real game, off in script runs (tests, tools) unless they set it.
static var open_browser_enabled := not PlayerProfile.is_script_run()

var session: OnlineSession = null
var intent := ApiClient.WEB_SIGN_IN
var status := Status.IDLE
## The request's code (polling only, not shown).
var code := ""
## The code the player types in the browser, as shown ("ABC-DEF").
var user_code := ""
## The page without the browser secret.
var url := ""
## Unix seconds (local clock).
var expires_at := 0
var interval := DEFAULT_INTERVAL
## Unix seconds the request was started (an account created after it is new, see AccountService).
var started_at := 0
## FAILED: the API's error ("banned", "cancelled", ...) or a local one; ban reason and end (unix s, 0 =
## none or permanent) for "banned".
var error := ""
var ban_reason := ""
var ban_expires_at := 0
## The last poll had no answer (the game keeps asking until the request expires).
var offline := false
## The poll body of COMPLETED: {result, provider, merged, removedPlayerId, auth}.
var completion: Dictionary = {}
## (url: String) -> void; default OS.shell_open. Tests replace it.
var url_opener: Callable = Callable()

var _poll_secret := ""
var _browser_secret := ""
## Counts start() calls, so a loop of an older request stops (run()).
var _generation := 0


func _init(online_session: OnlineSession = null) -> void:
	session = online_session


## Starts a request (coroutine). intent: ApiClient.WEB_SIGN_IN or WEB_LINK (needs a session; the
## caller logs in first). Opens the page right away. ok: WAITING; else FAILED with error.
func start(new_intent: String) -> ApiResult:
	_generation += 1
	intent = new_intent
	_reset()
	status = Status.STARTING
	changed.emit()
	if session == null or session.api == null:
		return _fail(ApiResult.failure(ApiResult.UNREACHABLE, "No session"))
	var result := await session.api.start_web_login(intent, String(Loc.current_language()))
	if status != Status.STARTING:
		# Cancelled while waiting.
		return result
	if not result.ok or not (result.data is Dictionary):
		return _fail(result if not result.ok else ApiResult.failure(ApiResult.BAD_RESPONSE, "No web login"))
	var body: Dictionary = result.data
	code = str(body.get(ApiClient.WEB_CODE, ""))
	user_code = format_code(str(body.get(ApiClient.WEB_USER_CODE, "")))
	_poll_secret = str(body.get(ApiClient.WEB_POLL_SECRET, ""))
	_browser_secret = str(body.get(ApiClient.WEB_BROWSER_SECRET, ""))
	var page := str(body.get(ApiClient.WEB_URL, ""))
	var cut := page.find("#")
	url = page.left(cut) if cut >= 0 else page
	if cut >= 0 and _browser_secret.is_empty():
		_browser_secret = _fragment_secret(page.substr(cut + 1))
	if code.is_empty() or user_code.is_empty() or _poll_secret.is_empty() or url.is_empty():
		return _fail(ApiResult.failure(ApiResult.BAD_RESPONSE, "Web login without code, secret or url"))
	var now := _now()
	started_at = now
	var until := OnlineConfig.parse_iso_time(body.get(ApiClient.WEB_EXPIRES_AT, null))
	expires_at = until if until > now else now + DEFAULT_TTL_SECONDS
	var seconds: Variant = body.get(ApiClient.WEB_POLL_INTERVAL, DEFAULT_INTERVAL)
	interval = maxf(1.0, float(seconds)) if typeof(seconds) in [TYPE_INT, TYPE_FLOAT] else DEFAULT_INTERVAL
	status = Status.WAITING
	changed.emit()
	open_browser()
	return result


## One poll (coroutine) while the request waits; returns the status afterwards.
func poll() -> Status:
	if not is_waiting():
		return status
	if _now() >= expires_at:
		return _set_status(Status.EXPIRED)
	var result := await session.api.poll_web_login(code, _poll_secret)
	if not is_waiting():
		return status
	if not result.ok:
		if result.error == NOT_FOUND:
			return _set_status(Status.EXPIRED)
		if result.error == ApiResult.UNREACHABLE or result.error == ApiResult.TIMEOUT or result.status >= 500 or result.status == 429:
			offline = true
			changed.emit()
			return status
		error = result.error
		return _set_status(Status.FAILED)
	offline = false
	var body: Dictionary = result.data if result.data is Dictionary else {}
	match str(body.get("status", "")):
		POLL_PENDING:
			return _set_status(Status.WAITING)
		POLL_AWAITING_CONFIRM:
			return _set_status(Status.CONFIRM)
		POLL_COMPLETED:
			if not (body.get("auth", null) is Dictionary):
				error = ApiResult.BAD_RESPONSE
				return _set_status(Status.FAILED)
			completion = body
			return _set_status(Status.COMPLETED)
		POLL_FAILED:
			error = str(body.get("error", ApiResult.BAD_RESPONSE))
			ban_reason = str(body.get("reason", "")) if body.get("reason", null) != null else ""
			ban_expires_at = OnlineConfig.parse_iso_time(body.get("expiresAt", null))
			return _set_status(Status.FAILED)
		POLL_EXPIRED:
			return _set_status(Status.EXPIRED)
	# Unknown states of a newer API: keep waiting.
	return status


## Polls every interval until the request is no longer waiting (coroutine). tree: for the timer.
func run(tree: SceneTree) -> Status:
	var generation := _generation
	while is_waiting() and generation == _generation:
		await tree.create_timer(interval, true, false, true).timeout
		if generation != _generation or not is_waiting():
			break
		await poll()
	return status


## Stops asking (the request ends on the server by itself).
func cancel() -> void:
	if is_waiting() or status == Status.STARTING:
		_generation += 1
		_set_status(Status.CANCELLED)


func is_waiting() -> bool:
	return status == Status.WAITING or status == Status.CONFIRM


## The code the player types in the browser: "ABC-DEF".
func display_code() -> String:
	return user_code


## Codes in two halves: "ABC-DEF" (user code, 6), "ABCD-EFGH" (deletion code, 8); else unchanged.
static func format_code(raw: String) -> String:
	var clean := raw.replace("-", "").replace(" ", "").to_upper()
	if clean.length() < 6 or clean.length() % 2 != 0:
		return clean
	var half := clean.length() / 2
	return "%s-%s" % [clean.left(half), clean.right(half)]


## The browser secret of a fragment "k=<secret>&…" ("" if none).
static func _fragment_secret(fragment: String) -> String:
	for part in fragment.split("&"):
		if part.begins_with(ApiClient.WEB_BROWSER_FRAGMENT + "="):
			return part.substr(ApiClient.WEB_BROWSER_FRAGMENT.length() + 1).uri_decode()
	return ""


## The page to open: url plus the browser secret in the fragment (never shown).
func browser_url() -> String:
	if _browser_secret.is_empty():
		return url
	return "%s#%s=%s" % [url, ApiClient.WEB_BROWSER_FRAGMENT, _browser_secret.uri_encode()]


## Opens the page in the browser (again). false without a request or with opening switched off.
func open_browser() -> bool:
	if url.is_empty():
		return false
	if url_opener.is_valid():
		url_opener.call(browser_url())
		return true
	if not open_browser_enabled:
		return false
	return OS.shell_open(browser_url()) == OK


## Puts the page (with the browser secret, so it works on this computer's other browser) on the clipboard.
func copy_link() -> bool:
	if url.is_empty():
		return false
	DisplayServer.clipboard_set(browser_url())
	return true


## Seconds until the request expires (0 when over).
func seconds_left() -> int:
	return maxi(0, expires_at - _now())


func _reset() -> void:
	code = ""
	user_code = ""
	url = ""
	_poll_secret = ""
	_browser_secret = ""
	expires_at = 0
	started_at = 0
	error = ""
	ban_reason = ""
	ban_expires_at = 0
	offline = false
	completion = {}


func _fail(result: ApiResult) -> ApiResult:
	error = result.error
	if result.error == ApiResult.BANNED:
		ban_reason = result.ban_reason
		ban_expires_at = result.ban_expires_at
	_set_status(Status.FAILED)
	return result


func _set_status(new_status: Status) -> Status:
	if status != new_status or new_status == Status.WAITING:
		status = new_status
		changed.emit()
	return status


static func _now() -> int:
	return int(Time.get_unix_time_from_system())

extends GutTest
## KF6: the logic of the account panel against a fake API that follows the KF5 web login (code,
## poll secret, browser secret in the fragment of the opened page, pending / awaiting_confirm /
## confirm_merge / completed / failed / expired), the password routes, "this device stays signed in"
## with the merge question (D-122), logins per provider, the deletion code and deleting the account.
## The fake follows the final contract: the API's url already carries #k=<browserSecret>, the
## player sees only userCode. WebLoginFlow and AccountService only; the panel itself: test_account_panel.gd. No network, the
## real online.cfg and save are never touched.

const TEST_PATH := "user://test_account_service_online.cfg"
const SAVE_PATH := "user://test_account_service_save.cfg"
const TOKEN := "session-token.c2lnbmF0dXJl"
const NEW_TOKEN := "fresh-token.c2lnbmF0dXJl"
const OWN_ID := "6f1c3a52-6a0e-4a3b-9a55-1c2d3e4f5a6b"
const OTHER_ID := "7a2d4b63-7b1f-4c4c-8b66-2d3e4f5a6b7c"
const BROWSER_SECRET := "browser-secret-do-not-show-0123456789"
const POLL_SECRET := "poll-secret-0123456789abcdef"

const FakeTransport := preload("res://tests/unit/test_session_account.gd").FakeTransport

var _fake
var _client: ApiClient
var _session: OnlineSession
var _service: AccountService
var _opened: Array[String] = []
var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = SAVE_PATH


func before_each() -> void:
	_remove_files()
	_opened.clear()
	_fake = FakeTransport.new()
	_client = ApiClient.new()
	_client.transport = _fake
	_client.base_url = "http://api.test"
	add_child_autofree(_client)
	var config := OnlineConfig.new()
	config.path = TEST_PATH
	config.settings_path = TEST_PATH
	config.load_from({"api": "http://api.test"})
	_session = OnlineSession.new(config)
	_session.api = _client
	add_child_autofree(_session)
	_service = AccountService.new(_session)
	_service.web.url_opener = func(url: String) -> void: _opened.append(url)


func after_all() -> void:
	_remove_files()
	SaveManager.save_path = _old_save_path


func _remove_files() -> void:
	for path in [TEST_PATH, SAVE_PATH, TEST_PATH.get_basename() + OnlineSession.LOGIN_FILE_SUFFIX]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _log_in(id := OWN_ID) -> void:
	_session.token = TOKEN
	_session.token_expires_at = 4_000_000_000
	_session.player = _player(id)
	_session.state = OnlineSession.State.ONLINE
	_client.token = TOKEN


static func _player(id := OWN_ID, created := "2026-10-01T10:00:00.000Z") -> Dictionary:
	return {"id": id, "name": "Lumen", "createdAt": created, "guild": null, "guilds": [], "level": 4}


static func _auth(id := OWN_ID, token := NEW_TOKEN, created := "2026-10-01T10:00:00.000Z") -> Dictionary:
	return {"token": token, "expiresAt": "2099-01-01T00:00:00.000Z", "player": _player(id, created)}


func _web_start() -> void:
	var expires := CloudSave.iso_time(int(Time.get_unix_time_from_system()) + 600)
	_fake.answer("POST /auth/web-login", 201, {ApiClient.WEB_CODE: "ABCDEFGH", ApiClient.WEB_USER_CODE: "KMN-PQR", ApiClient.WEB_POLL_SECRET: POLL_SECRET,
			ApiClient.WEB_BROWSER_SECRET: BROWSER_SECRET, ApiClient.WEB_URL: "https://playsoulwick.test/login/ABCDEFGH#k=" + BROWSER_SECRET,
			ApiClient.WEB_EXPIRES_AT: expires, ApiClient.WEB_POLL_INTERVAL: 2})


func _identities(providers: Array) -> Dictionary:
	var items := []
	for provider: String in providers:
		items.append({"id": "00000000-0000-4000-8000-%012d" % items.size(), "provider": provider,
				"maskedId": "***" + (_session.config.get_device_id().right(4) if provider == "device" else "0001"),
				"label": "lumen" if provider == "password" else null, "createdAt": "2026-10-01T10:00:00.000Z", "lastUsedAt": "2026-10-01T10:00:00.000Z"})
	return {"items": items}


# --- Web login flow ---

func test_web_login_opens_the_page_with_the_secret_only_in_the_fragment() -> void:
	_web_start()
	var result: ApiResult = await _service.web.start(ApiClient.WEB_SIGN_IN)
	assert_true(result.ok, result.describe())
	var web := _service.web
	assert_eq(web.status, WebLoginFlow.Status.WAITING)
	assert_eq(web.display_code(), "KMN-PQR", "only the user code is shown")
	assert_eq(_opened, ["https://playsoulwick.test/login/ABCDEFGH#k=" + BROWSER_SECRET], "opened once, secret once in the fragment")
	assert_false(web.url.contains(BROWSER_SECRET), "the shown address has no secret")
	assert_false(web.display_code().contains(BROWSER_SECRET))
	assert_eq(web.interval, 2.0)
	assert_between(web.seconds_left(), 590, 600)


func test_web_login_follows_the_poll_states() -> void:
	_web_start()
	await _service.web.start(ApiClient.WEB_SIGN_IN)
	var web := _service.web
	_fake.answer("POST /auth/web-login/poll", 200, {"status": "pending"})
	assert_eq(await web.poll(), WebLoginFlow.Status.WAITING)
	assert_eq(_fake.last("POST /auth/web-login/poll").body, {"code": "ABCDEFGH", "pollSecret": POLL_SECRET})
	_fake.answer("POST /auth/web-login/poll", 200, {"status": "awaiting_confirm"})
	assert_eq(await web.poll(), WebLoginFlow.Status.CONFIRM, "awaiting_confirm: confirm in the browser")
	assert_eq(await web.poll(), WebLoginFlow.Status.CONFIRM, "no answer: keeps waiting")
	assert_true(web.offline, "and says so")
	_fake.answer("POST /auth/web-login/poll", 200, {"status": "completed", "result": "signed_in", "provider": "discord",
			"merged": false, "removedPlayerId": null, "auth": _auth()})
	assert_eq(await web.poll(), WebLoginFlow.Status.COMPLETED)
	assert_false(web.offline)
	assert_eq(web.completion.get("provider"), "discord")


func test_web_login_failures_and_expiry() -> void:
	_web_start()
	await _service.web.start(ApiClient.WEB_SIGN_IN)
	var web := _service.web
	_fake.answer("POST /auth/web-login/poll", 200, {"status": "failed", "error": "banned", "reason": "Cheating", "expiresAt": "2099-01-01T00:00:00.000Z"})
	assert_eq(await web.poll(), WebLoginFlow.Status.FAILED)
	assert_eq(web.error, "banned")
	assert_eq(web.ban_reason, "Cheating")
	assert_gt(web.ban_expires_at, 0)
	_web_start()
	await web.start(ApiClient.WEB_SIGN_IN)
	_fake.answer("POST /auth/web-login/poll", 200, {"status": "expired"})
	assert_eq(await web.poll(), WebLoginFlow.Status.EXPIRED)
	_web_start()
	await web.start(ApiClient.WEB_SIGN_IN)
	_fake.answer("POST /auth/web-login/poll", 200, {"status": "failed", "error": "too_many_attempts"})
	assert_eq(await web.poll(), WebLoginFlow.Status.FAILED)
	assert_eq(web.error, "too_many_attempts")
	_web_start()
	await web.start(ApiClient.WEB_SIGN_IN)
	_fake.answer("POST /auth/web-login/poll", 404, {"error": "web_login_not_found"})
	assert_eq(await web.poll(), WebLoginFlow.Status.EXPIRED, "gone on the server")
	_web_start()
	await web.start(ApiClient.WEB_SIGN_IN)
	web.expires_at = int(Time.get_unix_time_from_system()) - 1
	assert_eq(await web.poll(), WebLoginFlow.Status.EXPIRED, "past its time: no request")


func test_cancel_stops_the_loop() -> void:
	_web_start()
	await _service.web.start(ApiClient.WEB_SIGN_IN)
	_service.web.interval = 0.05
	_service.web.cancel()
	assert_eq(await _service.web.run(get_tree()), WebLoginFlow.Status.CANCELLED)
	assert_eq(_fake.last("POST /auth/web-login/poll"), {}, "no poll after cancel")


func test_format_code() -> void:
	assert_eq(WebLoginFlow.format_code("kmnpqr"), "KMN-PQR")
	assert_eq(WebLoginFlow.format_code("KMN-PQR"), "KMN-PQR")
	assert_eq(WebLoginFlow.format_code("abcdefgh"), "ABCD-EFGH", "deletion codes")
	assert_eq(WebLoginFlow.format_code("ABC"), "ABC")


func test_an_url_without_fragment_gets_the_secret_appended() -> void:
	var expires := CloudSave.iso_time(int(Time.get_unix_time_from_system()) + 600)
	_fake.answer("POST /auth/web-login", 201, {ApiClient.WEB_CODE: "ABCDEFGH", ApiClient.WEB_USER_CODE: "KMN-PQR", ApiClient.WEB_POLL_SECRET: POLL_SECRET,
			ApiClient.WEB_BROWSER_SECRET: BROWSER_SECRET, ApiClient.WEB_URL: "https://playsoulwick.test/login/ABCDEFGH",
			ApiClient.WEB_EXPIRES_AT: expires, ApiClient.WEB_POLL_INTERVAL: 2})
	await _service.web.start(ApiClient.WEB_SIGN_IN)
	assert_eq(_opened, ["https://playsoulwick.test/login/ABCDEFGH#k=" + BROWSER_SECRET])


# --- Signing in ---

func test_web_sign_in_takes_the_account_and_keeps_this_device() -> void:
	_web_start()
	_fake.answer("POST /auth/web-login/poll", 200, {"status": "completed", "result": "signed_in", "provider": "discord",
			"merged": false, "removedPlayerId": null, "auth": _auth(OTHER_ID)})
	_fake.answer("GET /public/config", 200, {"apiVersion": "1.1.0"})
	_fake.answer("POST /me/logins", 200, _auth(OTHER_ID, "device-token").merged({"merged": false, "removedPlayerId": null, "identities": _identities(["discord", "device"]).items}))
	_fake.answer("GET /me/identities", 200, _identities(["discord", "device"]))
	_service.web.interval = 0.05
	var result: ApiResult = await _service.web_login(false, get_tree())
	assert_true(result.ok, result.describe())
	assert_eq(_session.get_player_id(), OTHER_ID)
	assert_eq(_client.token, "device-token", "the session of the device login")
	assert_eq(_session.login_kind, OnlineSession.LOGIN_DEVICE, "the device signs in again by itself")
	assert_eq(_fake.last("POST /me/logins").body.get("deviceId"), _session.config.get_device_id())
	assert_eq(_service.get_state(), AccountService.State.SECURED)
	assert_true(_service.keeps_device())


func test_device_guest_with_progress_asks_before_merging() -> void:
	_fake.answer("POST /auth/password", 200, _auth(OTHER_ID))
	_fake.answer("GET /public/config", 200, {"apiVersion": "1.1.0"})
	var offer := {"error": "account_has_progress", "remaining": {"id": OTHER_ID, "name": "Lumen", "level": 9, "runCount": 40, "worlds": 2, "guilds": []},
			"removed": {"id": OWN_ID, "name": "Gast", "level": 2, "runCount": 3, "worlds": 1, "guilds": []}}
	_fake.answer("POST /me/logins", 409, offer)
	_fake.answer("GET /me/identities", 200, _identities(["password"]))
	var result: ApiResult = await _service.sign_in_with_password("  Lumen ", "soulwick-player-local")
	assert_true(result.ok, result.describe())
	assert_eq(_fake.last("POST /auth/password").body.get("username"), "lumen", "trimmed and lower case")
	assert_eq(int(_service.merge_offer.get("remaining", {}).get("level", 0)), 9, "both accounts for the question")
	assert_eq(_session.login_kind, OnlineSession.LOGIN_ACCOUNT, "until the player decides")
	_fake.answer("POST /me/logins", 200, _auth(OTHER_ID, "merged-token").merged({"merged": true, "removedPlayerId": OWN_ID, "identities": _identities(["password", "device"]).items}))
	_fake.answer("GET /public/config", 200, {"apiVersion": "1.1.0"})
	var merged: ApiResult = await _service.keep_device(true)
	assert_true(merged.ok, merged.describe())
	assert_eq(_fake.last("POST /me/logins").body.get("confirmMerge"), true)
	assert_eq(_client.token, "merged-token")
	assert_eq(_service.merge_offer, {})
	assert_eq(_session.login_kind, OnlineSession.LOGIN_DEVICE)


func test_declining_the_merge_keeps_an_account_session() -> void:
	_log_in(OTHER_ID)
	_service.merge_offer = {"remaining": {}, "removed": {}}
	_service.decline_merge()
	assert_eq(_service.merge_offer, {})
	assert_eq(_session.login_kind, OnlineSession.LOGIN_ACCOUNT)


func test_wrong_password_and_local_checks() -> void:
	var short: ApiResult = await _service.sign_in_with_password("lumen", "")
	assert_eq(short.error, AccountService.ERROR_PASSWORD)
	_fake.answer("POST /auth/password", 401, {"error": "invalid_credentials"})
	var wrong: ApiResult = await _service.sign_in_with_password("lumen", "falsch-falsch")
	assert_eq(wrong.error, "invalid_credentials")
	assert_false(_session.is_logged_in())
	assert_true(AccountService.is_valid_username("lumen.2_x-y"))
	assert_false(AccountService.is_valid_username("lu"))
	assert_false(AccountService.is_valid_username("_lumen"))
	assert_false(AccountService.is_valid_username("lümen"))


func test_securing_a_guest_with_a_password() -> void:
	_log_in()
	_fake.answer("PUT /me/logins/password", 200, _identities(["device", "password"]))
	_fake.answer("GET /me/identities", 200, _identities(["device", "password"]))
	var bad: ApiResult = await _service.save_password_login("lumen", "kurz")
	assert_eq(bad.error, AccountService.ERROR_PASSWORD, "checked here first")
	var result: ApiResult = await _service.save_password_login("Lumen", "soulwick-player-local")
	assert_true(result.ok, result.describe())
	assert_eq(_fake.last("PUT /me/logins/password").body, {"username": "lumen", "password": "soulwick-player-local"})
	assert_eq(_service.get_state(), AccountService.State.SECURED)
	assert_eq(_service.password_username(), "lumen")


func test_link_in_the_browser_logs_in_the_guest_first() -> void:
	_fake.answer("POST /auth/device", 200, {"token": TOKEN, "expiresAt": "2099-01-01T00:00:00.000Z", "player": _player()})
	_fake.answer("GET /public/config", 200, {"apiVersion": "1.1.0", "loginMethods": ["device", "discord"]})
	_web_start()
	var result: ApiResult = await _service.start_web_login(true)
	assert_true(result.ok, result.describe())
	assert_true(_fake.has_bearer(_fake.last("POST /auth/web-login")), "link with the guest's session")
	assert_eq(_fake.last("POST /auth/web-login").body.get("intent"), "link")
	# Completed: the same account with a fresh session; no device step for a link.
	_fake.answer("GET /public/config", 200, {"apiVersion": "1.1.0"})
	_fake.answer("GET /me/identities", 200, _identities(["device", "discord"]))
	_service.web.status = WebLoginFlow.Status.COMPLETED
	_service.web.completion = {"status": "completed", "result": "linked", "provider": "discord", "merged": false, "removedPlayerId": null, "auth": _auth()}
	var done: ApiResult = await _service.finish_web_login()
	assert_true(done.ok, done.describe())
	assert_eq(_client.token, NEW_TOKEN)
	assert_eq(_fake.last("POST /me/logins"), {})
	assert_eq(_service.get_state(), AccountService.State.SECURED)


# --- Logins, state ---

func test_login_groups_and_what_can_be_removed() -> void:
	_log_in()
	_service._take_identities(_identities(["device", "device", "discord", "password"]))
	var groups := _service.login_groups()
	assert_eq(groups.size(), 3)
	assert_eq(groups[0].provider, "device")
	assert_eq(groups[0].count, 2)
	assert_true(groups[0].this_device, "recognised by the end of the device id")
	assert_eq(groups[2].label, "lumen")
	assert_true(_service.can_remove("discord"))
	_service._take_identities(_identities(["device"]))
	assert_false(_service.can_remove("device"), "the last provider stays")
	assert_eq(_service.get_state(), AccountService.State.GUEST)


func test_removing_the_devices_makes_an_account_session() -> void:
	_log_in()
	_fake.answer("DELETE /me/identities/device", 200, _identities(["discord"]))
	var result: ApiResult = await _service.remove_login("device")
	assert_true(result.ok, result.describe())
	assert_eq(_session.login_kind, OnlineSession.LOGIN_ACCOUNT)
	assert_false(_service.keeps_device())


func test_state_without_session_and_after_sign_out() -> void:
	assert_eq(_service.get_state(), AccountService.State.NONE)
	_session.set_login_kind(OnlineSession.LOGIN_ACCOUNT)
	assert_eq(_service.get_state(), AccountService.State.SIGNED_OUT)
	_service.play_as_guest()
	assert_eq(_service.get_state(), AccountService.State.NONE)


func test_refresh_never_creates_an_account() -> void:
	_fake.answer("GET /public/config", 200, {"apiVersion": "1.1.0", "loginMethods": ["device", "password", "google"]})
	await _service.refresh()
	assert_eq(_fake.last("POST /auth/device"), {}, "no guest login on open (D-224)")
	assert_true(_service.has_web_login())
	assert_true(_service.has_password_login())


func test_login_methods_of_an_older_api() -> void:
	_session.public_config = {"apiVersion": "1.0.0"}
	assert_eq(_service.login_methods(), PackedStringArray(["device"]))
	assert_false(_service.has_web_login())
	assert_false(_service.has_password_login())


# --- Deleting ---

func test_deletion_code_and_deleting_the_account() -> void:
	_log_in()
	_fake.answer("POST /me/deletion-code", 201, {"code": "QRSTUVWX", "expiresAt": "2099-01-01T00:00:00.000Z"})
	var code: ApiResult = await _service.create_deletion_code()
	assert_true(code.ok)
	assert_eq(_service.deletion_code.get("code"), "QRSTUVWX")
	assert_string_ends_with(_service.deletion_page(), "/delete-account")
	_fake.answer("DELETE /me", 204, null)
	var deleted: ApiResult = await _service.delete_account()
	assert_true(deleted.ok, deleted.describe())
	assert_false(_session.is_logged_in())
	assert_eq(_session.login_kind, OnlineSession.LOGIN_DEVICE)
	assert_eq(_service.get_state(), AccountService.State.NONE)
	assert_eq(_service.deletion_code, {})


func test_run_reports_with_action_finished() -> void:
	_log_in()
	_fake.answer("GET /me/identities", 200, _identities(["device"]))
	watch_signals(_service)
	_service.run(&"ids", _service.load_identities)
	await wait_for_signal(_service.action_finished, 2.0)
	assert_signal_emitted(_service, "action_finished")
	assert_true(_service.identities_loaded)

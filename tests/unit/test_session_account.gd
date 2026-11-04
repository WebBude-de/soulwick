extends GutTest
## KF6: the session takes a finished account login over (adopt_auth), remembers how it came about
## (login kind next to online.cfg) and never falls back to a silent guest login once an account
## without this device ended (SIGNED_OUT, D-224). The new ApiClient routes of the account panel send
## the contract bodies, a sign-in in the browser without the bearer, a link with it. Fake HTTP layer,
## no network; the real online.cfg and save are never touched.

const TEST_PATH := "user://test_session_account_online.cfg"
const SAVE_PATH := "user://test_session_account_save.cfg"
const TOKEN := "session-token.c2lnbmF0dXJl"
const OWN_ID := "6f1c3a52-6a0e-4a3b-9a55-1c2d3e4f5a6b"
const OTHER_ID := "7a2d4b63-7b1f-4c4c-8b66-2d3e4f5a6b7c"


class FakeTransport extends HttpTransport:
	var answers: Dictionary = {}
	var requests: Array[Dictionary] = []

	func send(_owner: Node, method: HTTPClient.Method, url: String, headers: PackedStringArray, body: String, _timeout: float) -> Dictionary:
		var path := url.substr(url.find("/", 8))
		var key := "%s %s" % [["GET", "HEAD", "POST", "PUT", "DELETE", "OPTIONS", "TRACE", "CONNECT", "PATCH"][method], path]
		requests.append({"key": key, "headers": headers, "body": JSON.parse_string(body) if not body.is_empty() else null})
		var queue: Array = answers.get(key, [])
		if queue.is_empty():
			return {"status": 0, "body": "", "error": ApiResult.UNREACHABLE}
		return queue.pop_front()

	func answer(key: String, status: int, body: Variant) -> void:
		if not answers.has(key):
			answers[key] = []
		answers[key].append({"status": status, "body": JSON.stringify(body) if body != null else "", "error": ""})

	func last(key: String) -> Dictionary:
		for i in range(requests.size() - 1, -1, -1):
			if requests[i].key == key:
				return requests[i]
		return {}

	func has_bearer(request: Dictionary) -> bool:
		for header: String in request.get("headers", PackedStringArray()):
			if header.begins_with("Authorization: Bearer"):
				return true
		return false


var _fake: FakeTransport
var _client: ApiClient
var _session: OnlineSession
var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = SAVE_PATH


func before_each() -> void:
	_remove_files()
	_fake = FakeTransport.new()
	_client = ApiClient.new()
	_client.transport = _fake
	_client.base_url = "http://api.test"
	add_child_autofree(_client)
	_session = _new_session()


func after_all() -> void:
	_remove_files()
	SaveManager.save_path = _old_save_path


func _new_session() -> OnlineSession:
	var config := OnlineConfig.new()
	config.path = TEST_PATH
	config.settings_path = TEST_PATH
	config.load_from({"api": "http://api.test"})
	var session := OnlineSession.new(config)
	session.api = _client
	add_child_autofree(session)
	return session


func _remove_files() -> void:
	for path in [TEST_PATH, SAVE_PATH, TEST_PATH.get_basename() + OnlineSession.LOGIN_FILE_SUFFIX]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _auth(id := OWN_ID, token := TOKEN) -> Dictionary:
	return {"token": token, "expiresAt": "2099-01-01T00:00:00.000Z",
			"player": {"id": id, "name": "Lumen", "createdAt": "2026-10-01T10:00:00.000Z", "guild": null, "guilds": [], "level": 4}}


# --- adopt_auth ---

func test_adopt_auth_takes_the_session_and_stores_it() -> void:
	_fake.answer("GET /public/config", 200, {"apiVersion": "1.1.0", "loginMethods": ["device", "password"]})
	var result: ApiResult = await _session.adopt_auth(_auth(), OnlineSession.LOGIN_ACCOUNT)
	assert_true(result.ok, result.describe())
	assert_true(_session.is_logged_in())
	assert_eq(_session.get_player_id(), OWN_ID)
	assert_eq(_client.token, TOKEN, "the API client sends the new token")
	assert_eq(_session.config.get_stored_session().get("token", ""), TOKEN, "stored in online.cfg")
	assert_eq(_session.login_kind, OnlineSession.LOGIN_ACCOUNT)
	assert_eq(_session.public_config.get("loginMethods", []), ["device", "password"], "public config read")


func test_adopt_auth_refuses_an_answer_without_token_or_player() -> void:
	var result: ApiResult = await _session.adopt_auth({"token": "", "player": {}}, OnlineSession.LOGIN_ACCOUNT)
	assert_false(result.ok)
	assert_eq(result.error, ApiResult.BAD_RESPONSE)
	assert_false(_session.is_logged_in(), "nothing changed")


func test_login_kind_survives_a_restart_of_the_game() -> void:
	_session.set_login_kind(OnlineSession.LOGIN_ACCOUNT)
	var again := _new_session()
	assert_eq(again.login_kind, OnlineSession.LOGIN_ACCOUNT, "read from the login file")
	again.set_login_kind(OnlineSession.LOGIN_DEVICE)
	assert_eq(_new_session().login_kind, OnlineSession.LOGIN_DEVICE)


func test_login_kind_of_another_api_counts_as_device() -> void:
	_session.set_login_kind(OnlineSession.LOGIN_ACCOUNT)
	var config := OnlineConfig.new()
	config.path = TEST_PATH
	config.settings_path = TEST_PATH
	config.load_from({"api": "http://other.test"})
	var session := OnlineSession.new(config)
	session.api = _client
	add_child_autofree(session)
	assert_eq(session.login_kind, OnlineSession.LOGIN_DEVICE)


# --- No silent guest after an account session (D-224) ---

func test_an_ended_account_session_asks_for_a_new_sign_in() -> void:
	_session.set_login_kind(OnlineSession.LOGIN_ACCOUNT)
	var result: ApiResult = await _session.ensure_login()
	assert_false(result.ok)
	assert_eq(result.error, OnlineSession.SIGNED_OUT)
	assert_true(_session.is_signed_out())
	assert_eq(_fake.last("POST /auth/device"), {}, "no guest login")


func test_a_rejected_account_token_does_not_become_a_guest() -> void:
	_session.config.store_session(TOKEN, 4_000_000_000, OWN_ID, "Lumen")
	_session.set_login_kind(OnlineSession.LOGIN_ACCOUNT)
	_fake.answer("GET /me", 401, {"error": "unauthorized"})
	var result: ApiResult = await _session.ensure_login()
	assert_eq(result.error, OnlineSession.SIGNED_OUT)
	assert_eq(_fake.last("POST /auth/device"), {}, "no guest login")


func test_a_device_session_still_logs_in_as_guest() -> void:
	_fake.answer("POST /auth/device", 200, _auth())
	_fake.answer("GET /public/config", 200, {"apiVersion": "1.1.0"})
	var result: ApiResult = await _session.ensure_login()
	assert_true(result.ok, result.describe())
	assert_ne(_fake.last("POST /auth/device"), {})


func test_forget_account_returns_to_the_device_login() -> void:
	await _session.adopt_auth(_auth(), OnlineSession.LOGIN_ACCOUNT)
	_session.forget_account()
	assert_false(_session.is_logged_in())
	assert_false(_session.is_signed_out())
	assert_eq(_session.login_kind, OnlineSession.LOGIN_DEVICE)
	assert_eq(_session.config.get_stored_session(), {}, "token forgotten")


# --- ApiClient routes of the account panel ---

func test_web_login_sign_in_is_sent_without_bearer_and_link_with_it() -> void:
	_client.token = TOKEN
	_fake.answer("POST /auth/web-login", 201, {})
	_fake.answer("POST /auth/web-login", 201, {})
	await _client.start_web_login(ApiClient.WEB_SIGN_IN, "de")
	var sign_in := _fake.last("POST /auth/web-login")
	assert_false(_fake.has_bearer(sign_in), "sign_in never carries the session")
	assert_eq(sign_in.body, {"intent": "sign_in", "locale": "de"})
	await _client.start_web_login(ApiClient.WEB_LINK, "xx")
	var link := _fake.last("POST /auth/web-login")
	assert_true(_fake.has_bearer(link), "link needs the session")
	assert_eq(link.body, {"intent": "link"}, "unknown locales are left out")


func test_link_without_a_session_sends_nothing() -> void:
	_client.token = ""
	var result: ApiResult = await _client.start_web_login(ApiClient.WEB_LINK)
	assert_eq(result.error, ApiResult.UNAUTHORIZED)
	assert_eq(_fake.requests.size(), 0)


func test_account_routes_send_the_contract_bodies() -> void:
	_client.token = TOKEN
	for key in ["POST /auth/web-login/poll", "POST /auth/password", "PUT /me/logins/password", "POST /me/logins",
			"GET /me/identities", "DELETE /me/identities/discord", "POST /me/deletion-code", "DELETE /me"]:
		_fake.answer(key, 200, {})
	await _client.poll_web_login("ABCDEFGH", "poll-secret-0123456789")
	assert_eq(_fake.last("POST /auth/web-login/poll").body, {"code": "ABCDEFGH", "pollSecret": "poll-secret-0123456789"})
	assert_false(_fake.has_bearer(_fake.last("POST /auth/web-login/poll")))
	await _client.login_password("lumen", "soulwick-player-local")
	assert_eq(_fake.last("POST /auth/password").body, {"username": "lumen", "password": "soulwick-player-local"})
	assert_false(_fake.has_bearer(_fake.last("POST /auth/password")))
	await _client.set_password_login("", "new-password-123")
	assert_eq(_fake.last("PUT /me/logins/password").body, {"password": "new-password-123"}, "only what changes")
	await _client.add_device_login("device-1234", true)
	assert_eq(_fake.last("POST /me/logins").body, {"provider": "device", "deviceId": "device-1234", "confirmMerge": true})
	await _client.get_identities()
	await _client.remove_identity("discord")
	await _client.create_deletion_code()
	await _client.delete_account()
	for key in ["GET /me/identities", "DELETE /me/identities/discord", "POST /me/deletion-code", "DELETE /me"]:
		assert_true(_fake.has_bearer(_fake.last(key)), key)

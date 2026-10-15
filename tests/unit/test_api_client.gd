extends GutTest
## MP1b: ApiClient and OnlineSession against a fake HTTP layer (no network): headers and bodies of
## the dev login, error results instead of exceptions (unreachable, timeout, banned, 401, no JSON),
## token reuse from user://, relay URL from GET /public/config. The real save is never touched.
## P-027: the relay JWT of GET /auth/token (Bearer = session token, cached until shortly before its
## end, a 401 drops the session and logs in again, 403 banned).

const TEST_PATH := "user://test_api_client_online.cfg"
## Better Auth session token (<token>.<signature>) and relay JWTs.
const TOKEN := "session-token.c2lnbmF0dXJl"
const NEW_TOKEN := "session-token-2.c2lnbmF0dXJl"
const JWT := "eyJhbGciOiJFZERTQSJ9.eyJzdWIiOiIxIn0.c2ln"
const JWT_2 := "eyJhbGciOiJFZERTQSJ9.eyJzdWIiOiIyIn0.c2ln"
const PLAYER := {"id": "6f1c3a52-6a0e-4a3b-9a55-1c2d3e4f5a6b", "name": "Kerze", "steamId": null, "createdAt": "2026-10-14T10:00:00.000Z", "guild": null}


## Answers from a queue keyed by "METHOD path"; records every request.
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

	func answer(key: String, status: int, body: Variant, error := "") -> void:
		if not answers.has(key):
			answers[key] = []
		answers[key].append({"status": status, "body": JSON.stringify(body) if body != null else "", "error": error})

	func header(index: int, name: String) -> String:
		for line: String in requests[index].headers:
			if line.to_lower().begins_with(name.to_lower() + ":"):
				return line.substr(name.length() + 1).strip_edges()
		return ""


var _fake: FakeTransport
var _client: ApiClient


func before_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	_fake = FakeTransport.new()
	_client = ApiClient.new()
	_client.transport = _fake
	_client.base_url = "http://api.test"
	_client.dev_key = "dev-key-0123456789"
	add_child_autofree(_client)


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _auth_response(expires := "2099-01-01T00:00:00.000Z") -> Dictionary:
	return {"token": TOKEN, "expiresAt": expires, "player": PLAYER}


func test_dev_login_sends_key_name_and_device() -> void:
	_fake.answer("POST /auth/dev", 200, _auth_response())
	var result := await _client.login_dev("Kerze", "device-0123456789abcdef")
	assert_true(result.ok, result.describe())
	assert_eq(result.get_field("token"), TOKEN)
	assert_eq(_fake.requests.size(), 1)
	assert_eq(_fake.requests[0].url, "http://api.test/auth/dev")
	assert_eq(_fake.header(0, "x-dev-auth-key"), "dev-key-0123456789")
	assert_eq(_fake.header(0, "Content-Type"), "application/json")
	assert_eq(_fake.header(0, "Authorization"), "", "no token on the login")
	assert_eq(JSON.parse_string(_fake.requests[0].body), {"name": "Kerze", "deviceId": "device-0123456789abcdef"})
	assert_eq(_fake.requests[0].timeout, ApiClient.TIMEOUT_SECONDS)


func test_without_dev_key_nothing_is_sent() -> void:
	_client.dev_key = ""
	var result := await _client.login_dev("Kerze", "device-0123456789abcdef")
	assert_false(result.ok)
	assert_eq(result.error, ApiResult.NO_DEV_KEY)
	assert_eq(_fake.requests.size(), 0)


func test_me_uses_bearer_token_and_needs_one() -> void:
	var missing := await _client.get_me()
	assert_eq(missing.error, ApiResult.UNAUTHORIZED)
	_client.token = TOKEN
	_fake.answer("GET /me", 200, PLAYER)
	var result := await _client.get_me()
	assert_true(result.ok)
	assert_eq(_fake.header(0, "Authorization"), "Bearer %s" % TOKEN)
	assert_eq(result.get_field("name"), "Kerze")


func test_errors_are_results() -> void:
	_client.token = TOKEN
	_fake.answer("GET /me", 403, {"error": "banned", "reason": "Cheating", "expiresAt": "2026-10-21T14:23:24.017Z"})
	_fake.answer("GET /me", 401, {"error": "invalid_token", "message": "Token expired"})
	_fake.answer("GET /me", 500, null)
	_fake.answer("GET /me", 0, null, ApiResult.TIMEOUT)
	_fake.answer("GET /me", 200, null)
	var banned := await _client.get_me()
	assert_eq(banned.error, ApiResult.BANNED)
	assert_eq(banned.ban_reason, "Cheating")
	assert_eq(banned.ban_expires_at, Time.get_unix_time_from_datetime_string("2026-10-21T14:23:24"))
	var expired := await _client.get_me()
	assert_eq(expired.error, "invalid_token")
	assert_eq(expired.status, 401)
	var server := await _client.get_me()
	assert_eq(server.error, "http_500")
	var timeout := await _client.get_me()
	assert_eq(timeout.error, ApiResult.TIMEOUT)
	var empty := await _client.get_me()
	assert_true(empty.ok, "2xx without a body is fine")
	var unreachable := await _client.get_me()
	assert_eq(unreachable.error, ApiResult.UNREACHABLE)
	assert_false(ApiResult.from_http(200, "<html>").ok)
	assert_eq(ApiResult.from_http(200, "<html>").error, ApiResult.BAD_RESPONSE)


func _session() -> OnlineSession:
	var config := OnlineConfig.new()
	config.path = TEST_PATH
	config.settings_path = TEST_PATH
	config.load_from({"api": "http://api.test", "dev_key": "dev-key-0123456789", "name": "Kerze"})
	var session := OnlineSession.new(config)
	session.api = _client
	add_child_autofree(session)
	return session


func test_session_logs_in_stores_token_and_reads_public_config() -> void:
	_fake.answer("POST /auth/dev", 200, _auth_response())
	_fake.answer("GET /public/config", 200, {"apiVersion": "1.0.0", "minGameVersion": null, "protocolVersion": 1, "relayUrl": "ws://relay.test/v1"})
	var session := _session()
	var result := await session.ensure_login()
	assert_true(result.ok, result.describe())
	assert_true(session.is_logged_in())
	assert_eq(session.get_player_name(), "Kerze")
	assert_eq(session.get_relay_url(), "ws://relay.test/v1")
	var body: Dictionary = JSON.parse_string(_fake.requests[0].body)
	assert_eq(body.get("name"), "Kerze")
	assert_eq(body.get("deviceId"), session.config.get_device_id())
	var stored := ConfigFile.new()
	assert_eq(stored.load(TEST_PATH), OK)
	assert_eq(stored.get_value("session", "token", ""), TOKEN, "token in online.cfg, not in a save slot")
	# A second call needs no request.
	var count := _fake.requests.size()
	assert_true((await session.ensure_login()).ok)
	assert_eq(_fake.requests.size(), count)


func test_session_reuses_a_stored_token() -> void:
	var config := OnlineConfig.new()
	config.path = TEST_PATH
	config.settings_path = TEST_PATH
	config.load_from({"api": "http://api.test"})
	config.store_session(TOKEN, 4_000_000_000, PLAYER.id, PLAYER.name)
	_fake.answer("GET /me", 200, PLAYER)
	_fake.answer("GET /public/config", 404, {"error": "not_found"})
	var session := _session()
	var result := await session.ensure_login()
	assert_true(result.ok, result.describe())
	assert_eq(_fake.requests[0].key, "GET /me")
	assert_false(_fake.requests.any(func(request: Dictionary) -> bool: return request.key == "POST /auth/dev"))
	assert_eq(session.get_relay_url(), OnlineConfig.DEFAULT_RELAY_URL, "older API without /public/config")


func test_rejected_token_logs_in_again() -> void:
	var config := OnlineConfig.new()
	config.path = TEST_PATH
	config.settings_path = TEST_PATH
	config.load_from({"api": "http://api.test"})
	config.store_session("old-token", 4_000_000_000, PLAYER.id, PLAYER.name)
	_fake.answer("GET /me", 401, {"error": "invalid_token"})
	_fake.answer("POST /auth/dev", 200, _auth_response())
	_fake.answer("GET /public/config", 200, {"apiVersion": "1.0.0", "minGameVersion": null, "protocolVersion": 1, "relayUrl": null})
	var session := _session()
	assert_true((await session.ensure_login()).ok)
	assert_eq(session.token, TOKEN)


func test_offline_login_fails_softly() -> void:
	var session := _session()
	var result := await session.ensure_login()
	assert_false(result.ok)
	assert_eq(result.error, ApiResult.UNREACHABLE)
	assert_eq(session.state, OnlineSession.State.FAILED)
	assert_false(session.is_logged_in())


func test_banned_login() -> void:
	_fake.answer("POST /auth/dev", 403, {"error": "banned", "reason": "Test", "expiresAt": null})
	var session := _session()
	var result := await session.ensure_login()
	assert_eq(result.error, ApiResult.BANNED)
	assert_eq(result.ban_expires_at, 0, "null = permanent")


# --- relay token (P-027) ---

func _iso_in(seconds: int) -> String:
	return Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) + seconds) + ".000Z"


## Keys of the requests so far ("GET /auth/token" …), optionally only those starting with prefix.
func _keys(prefix := "") -> Array[String]:
	var keys: Array[String] = []
	for request: Dictionary in _fake.requests:
		if prefix.is_empty() or str(request.key).begins_with(prefix):
			keys.append(str(request.key))
	return keys


## Index of the nth request (0-based) with this key, -1 if there is none.
func _index_of(key: String, nth := 0) -> int:
	for i in _fake.requests.size():
		if _fake.requests[i].key == key:
			if nth == 0:
				return i
			nth -= 1
	return -1


func _logged_in_session() -> OnlineSession:
	_fake.answer("POST /auth/dev", 200, _auth_response())
	_fake.answer("GET /public/config", 200, {"apiVersion": "1.0.0", "minGameVersion": null, "protocolVersion": 1, "relayUrl": null})
	return _session()


func _session_with_stored_token(stored_token: String, with_dev_key: bool) -> OnlineSession:
	var config := OnlineConfig.new()
	config.path = TEST_PATH
	config.settings_path = TEST_PATH
	var settings := {"api": "http://api.test"}
	if with_dev_key:
		settings["dev_key"] = "dev-key-0123456789"
	config.load_from(settings)
	config.store_session(stored_token, 4_000_000_000, PLAYER.id, PLAYER.name)
	var session := OnlineSession.new(config)
	session.api = _client
	add_child_autofree(session)
	return session


func test_relay_token_needs_a_session_token() -> void:
	var result := await _client.get_relay_token()
	assert_eq(result.error, ApiResult.UNAUTHORIZED)
	assert_eq(_fake.requests.size(), 0)


func test_relay_token_is_fetched_with_the_session_token_and_cached() -> void:
	var session := _logged_in_session()
	_fake.answer("GET /auth/token", 200, {"token": JWT, "expiresAt": _iso_in(900)})
	var result := await session.ensure_relay_token()
	assert_true(result.ok, result.describe())
	assert_eq(result.get_field("token"), JWT)
	assert_eq(session.relay_token, JWT)
	assert_ne(session.relay_token, session.token, "the relay never gets the session token")
	var index := _index_of("GET /auth/token")
	assert_gt(index, -1)
	assert_eq(_fake.header(index, "Authorization"), "Bearer %s" % TOKEN)
	assert_almost_eq(session.relay_token_expires_at, int(Time.get_unix_time_from_system()) + 900, 2)
	assert_false(FileAccess.get_file_as_string(TEST_PATH).contains(JWT), "the relay JWT is never stored")
	# Cached: the next connection asks nothing.
	var count := _fake.requests.size()
	var again := await session.ensure_relay_token()
	assert_true(again.ok)
	assert_eq(again.get_field("token"), JWT)
	assert_eq(_fake.requests.size(), count)


func test_relay_token_is_refreshed_shortly_before_it_ends() -> void:
	var session := _logged_in_session()
	_fake.answer("GET /auth/token", 200, {"token": JWT, "expiresAt": _iso_in(OnlineSession.RELAY_TOKEN_MARGIN_SECONDS - 10)})
	_fake.answer("GET /auth/token", 200, {"token": JWT_2, "expiresAt": _iso_in(900)})
	assert_eq((await session.ensure_relay_token()).get_field("token"), JWT, "a fresh answer is used once")
	assert_false(session.has_relay_token(), "less than the margin left")
	var result := await session.ensure_relay_token()
	assert_eq(result.get_field("token"), JWT_2)
	assert_eq(_keys("GET /auth/token").size(), 2)
	assert_eq(_keys("POST /auth/dev").size(), 1, "the session token is reused")


func test_relay_token_cache_is_capped_by_its_lifetime() -> void:
	var session := _logged_in_session()
	_fake.answer("GET /auth/token", 200, {"token": JWT, "expiresAt": "2099-01-01T00:00:00.000Z"})
	assert_true((await session.ensure_relay_token()).ok)
	assert_lte(session.relay_token_expires_at, int(Time.get_unix_time_from_system()) + OnlineSession.RELAY_TOKEN_TTL_SECONDS)


func test_relay_token_401_drops_the_session_and_logs_in_again() -> void:
	_fake.answer("GET /me", 200, PLAYER)
	_fake.answer("GET /public/config", 404, {"error": "not_found"})
	_fake.answer("GET /auth/token", 401, {"error": "unauthorized", "message": "Valid player token required"})
	var fresh := _auth_response()
	fresh.token = NEW_TOKEN
	_fake.answer("POST /auth/dev", 200, fresh)
	_fake.answer("GET /public/config", 404, {"error": "not_found"})
	_fake.answer("GET /auth/token", 200, {"token": JWT, "expiresAt": _iso_in(900)})
	var session := _session_with_stored_token("revoked-token", true)
	var result := await session.ensure_relay_token()
	assert_true(result.ok, result.describe())
	assert_eq(session.relay_token, JWT)
	assert_eq(session.token, NEW_TOKEN)
	assert_true(session.is_logged_in())
	assert_eq(_fake.header(_index_of("GET /auth/token", 0), "Authorization"), "Bearer revoked-token")
	assert_eq(_fake.header(_index_of("GET /auth/token", 1), "Authorization"), "Bearer %s" % NEW_TOKEN)
	assert_eq(str(session.config.get_stored_session().get("token", "")), NEW_TOKEN, "the new session replaces the revoked one")


func test_relay_token_401_without_dev_key_logs_in_as_guest() -> void:
	_fake.answer("GET /me", 200, PLAYER)
	_fake.answer("GET /public/config", 404, {"error": "not_found"})
	_fake.answer("GET /auth/token", 401, {"error": "unauthorized"})
	var fresh := _auth_response()
	fresh.token = NEW_TOKEN
	_fake.answer("POST /auth/device", 200, fresh)
	_fake.answer("GET /public/config", 404, {"error": "not_found"})
	_fake.answer("GET /auth/token", 200, {"token": JWT, "expiresAt": _iso_in(900)})
	var session := _session_with_stored_token("revoked-token", false)
	var result := await session.ensure_relay_token()
	assert_true(result.ok, result.describe())
	assert_eq(session.token, NEW_TOKEN)
	assert_eq(_index_of("POST /auth/dev"), -1, "no dev login without a key")
	var login := _fake.requests[_index_of("POST /auth/device")]
	assert_eq(_fake.header(_index_of("POST /auth/device"), "x-dev-auth-key"), "", "the guest login sends no key")
	assert_eq(JSON.parse_string(login.body).deviceId, session.config.get_device_id())


func test_device_login_sends_name_and_device_without_key() -> void:
	_fake.answer("POST /auth/device", 200, _auth_response())
	var result := await _client.login_device("Kerze", "0f0e4c1a-2b3c-4d5e-8f90-a1b2c3d4e5f6")
	assert_true(result.ok, result.describe())
	assert_eq(_fake.requests[0].url, "http://api.test/auth/device")
	assert_eq(_fake.header(0, "x-dev-auth-key"), "")
	assert_eq(_fake.header(0, "Authorization"), "")
	assert_eq(JSON.parse_string(_fake.requests[0].body), {"name": "Kerze", "deviceId": "0f0e4c1a-2b3c-4d5e-8f90-a1b2c3d4e5f6"})


func test_relay_token_401_with_guest_login_off_ends_logged_out() -> void:
	_fake.answer("GET /me", 200, PLAYER)
	_fake.answer("GET /public/config", 404, {"error": "not_found"})
	_fake.answer("GET /auth/token", 401, {"error": "unauthorized"})
	_fake.answer("POST /auth/device", 403, {"error": "guest_auth_disabled", "message": "Guest login is disabled"})
	var session := _session_with_stored_token("revoked-token", false)
	var result := await session.ensure_relay_token()
	assert_false(result.ok)
	assert_eq(result.error, "guest_auth_disabled")
	assert_eq(LobbyClient.login_error(result), LobbyClient.ERROR_LOGIN)
	assert_false(session.is_logged_in())
	assert_eq(session.relay_token, "")
	assert_true(session.config.get_stored_session().is_empty(), "the revoked token is gone from online.cfg")
	assert_eq(_keys("GET /auth/token").size(), 1)


func test_relay_token_401_twice_is_unauthorized() -> void:
	var session := _logged_in_session()
	_fake.answer("GET /auth/token", 401, {"error": "unauthorized"})
	_fake.answer("POST /auth/dev", 200, _auth_response())
	_fake.answer("GET /public/config", 404, {"error": "not_found"})
	_fake.answer("GET /auth/token", 401, {"error": "unauthorized"})
	var result := await session.ensure_relay_token()
	assert_false(result.ok)
	assert_eq(result.status, 401)
	assert_eq(LobbyClient.login_error(result), LobbyClient.ERROR_UNAUTHORIZED)
	assert_eq(_keys("GET /auth/token").size(), 2, "one retry, no loop")


func test_relay_token_banned() -> void:
	var session := _logged_in_session()
	_fake.answer("GET /auth/token", 403, {"error": "banned", "reason": "Cheating", "expiresAt": null})
	var result := await session.ensure_relay_token()
	assert_eq(result.error, ApiResult.BANNED)
	assert_eq(result.ban_reason, "Cheating")
	assert_eq(LobbyClient.login_error(result), ApiResult.BANNED)
	assert_eq(session.relay_token, "")
	assert_eq(session.state, OnlineSession.State.FAILED)
	assert_eq(_keys("POST /auth/dev").size(), 1, "a ban is no reason to log in again")


func test_forget_and_logout_drop_the_relay_token() -> void:
	var session := _logged_in_session()
	_fake.answer("GET /auth/token", 200, {"token": JWT, "expiresAt": _iso_in(900)})
	assert_true((await session.ensure_relay_token()).ok)
	session.forget_relay_token()
	assert_false(session.has_relay_token())
	_fake.answer("GET /auth/token", 200, {"token": JWT_2, "expiresAt": _iso_in(900)})
	assert_eq((await session.ensure_relay_token()).get_field("token"), JWT_2, "fetched again after the relay refused it")
	session.logout()
	assert_eq(session.relay_token, "")
	assert_false(session.has_relay_token())


func test_401_on_any_route_drops_the_session() -> void:
	var session := _logged_in_session()
	assert_true((await session.ensure_login()).ok)
	_fake.answer("POST /runs", 401, {"error": "unauthorized"})
	var report := await _client.post_run({"mode": "quick"})
	assert_eq(report.status, 401)
	assert_false(session.is_logged_in())
	assert_eq(session.state, OnlineSession.State.OFFLINE)
	assert_eq(_client.token, "")
	assert_true(session.config.get_stored_session().is_empty())


func test_login_errors_for_the_lobby() -> void:
	assert_eq(LobbyClient.login_error(ApiResult.failure(ApiResult.TIMEOUT)), LobbyClient.ERROR_API_UNREACHABLE)
	assert_eq(LobbyClient.login_error(ApiResult.failure(ApiResult.UNREACHABLE)), LobbyClient.ERROR_API_UNREACHABLE)
	assert_eq(LobbyClient.login_error(ApiResult.failure("invalid_dev_auth_key", "", 401)), LobbyClient.ERROR_LOGIN, "a wrong dev key is no expired session")
	assert_eq(LobbyClient.login_error(ApiResult.from_http(401, JSON.stringify({"error": "unauthorized"}))), LobbyClient.ERROR_UNAUTHORIZED)
	assert_eq(LobbyClient.login_error(ApiResult.failure("http_500", "", 500)), LobbyClient.ERROR_LOGIN)
	assert_eq(LobbyClient.login_error(null), LobbyClient.ERROR_LOGIN)

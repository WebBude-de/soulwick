extends GutTest
## MP1b, optional: the real ApiClient (HTTPRequest) against a running soulwick-api (login, /me and
## since P-027 the relay JWT of GET /auth/token). Skipped (pending)
## unless the environment names one, e.g. in PowerShell:
##   $env:SOULWICK_TEST_API="http://localhost:8797"; $env:SOULWICK_TEST_DEV_KEY="<DEV_AUTH_KEY>"
## or when it does not answer. Uses its own online file, never the real one or a save slot.

const TEST_PATH := "user://test_api_integration_online.cfg"

var _api_url := ""
var _dev_key := ""


func before_all() -> void:
	_api_url = OS.get_environment("SOULWICK_TEST_API")
	_dev_key = OS.get_environment("SOULWICK_TEST_DEV_KEY")


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _client() -> ApiClient:
	var client := ApiClient.new()
	client.base_url = _api_url
	client.dev_key = _dev_key
	add_child_autofree(client)
	return client


func test_dev_login_and_me_against_a_local_api() -> void:
	if _api_url.is_empty() or _dev_key.is_empty():
		pending("SOULWICK_TEST_API / SOULWICK_TEST_DEV_KEY not set")
		return
	var client := _client()
	var health := await client.get_health()
	if not health.ok:
		pending("API %s not reachable (%s)" % [_api_url, health.describe()])
		return
	var config := OnlineConfig.new()
	config.path = TEST_PATH
	config.settings_path = TEST_PATH
	config.load_from({"api": _api_url})
	var login := await client.login_dev("GUT Test", config.get_device_id())
	assert_true(login.ok, login.describe())
	client.token = str(login.get_field("token", ""))
	var me := await client.get_me()
	assert_true(me.ok, me.describe())
	assert_eq(me.get_field("name"), "GUT Test")
	var public_config := await client.get_public_config()
	if public_config.ok:
		assert_eq(int(public_config.get_field("protocolVersion", -1)), OnlineConfig.PROTOCOL_VERSION)


## P-027: the session token of the login gets a relay JWT at GET /auth/token (EdDSA, aud
## soulwick-relay, sub = player id, about 15 min); a wrong token gets 401 and the client says so.
func test_relay_token_against_a_local_api() -> void:
	if _api_url.is_empty() or _dev_key.is_empty():
		pending("SOULWICK_TEST_API / SOULWICK_TEST_DEV_KEY not set")
		return
	var client := _client()
	if not (await client.get_health()).ok:
		pending("API %s not reachable" % _api_url)
		return
	var config := OnlineConfig.new()
	config.path = TEST_PATH
	config.settings_path = TEST_PATH
	config.load_from({"api": _api_url, "dev_key": _dev_key, "name": "GUT Relay"})
	var session := OnlineSession.new(config)
	session.api = client
	add_child_autofree(session)
	var result := await session.ensure_relay_token()
	assert_true(result.ok, result.describe())
	var jwt := session.relay_token
	assert_eq(jwt.split(".").size(), 3, "a JWT")
	assert_ne(jwt, session.token, "not the session token")
	var header := _jwt_part(jwt, 0)
	var claims := _jwt_part(jwt, 1)
	assert_eq(header.get("alg"), "EdDSA")
	assert_eq(claims.get("aud"), "soulwick-relay")
	assert_eq(claims.get("sub"), session.get_player_id())
	assert_eq(claims.get("name"), session.get_player_name())
	var lifetime := int(claims.get("exp", 0)) - int(claims.get("iat", 0))
	assert_eq(lifetime, OnlineSession.RELAY_TOKEN_TTL_SECONDS)
	assert_almost_eq(session.relay_token_expires_at, int(claims.get("exp", 0)), 5)
	# Reused while valid.
	var again := await session.ensure_relay_token()
	assert_eq(again.get_field("token"), jwt)
	# A token the API does not know: 401, the client reports it.
	var stranger := _client()
	stranger.token = "not-a-session.c2lnbmF0dXJl"
	watch_signals(stranger)
	var refused := await stranger.get_relay_token()
	assert_eq(refused.status, 401)
	assert_eq(refused.error, ApiResult.UNAUTHORIZED)
	assert_signal_emitted(stranger, "unauthorized")
	session.logout()


## Decoded JSON of part index (0 header, 1 claims) of a JWT; no signature check (that is the relay's).
func _jwt_part(jwt: String, index: int) -> Dictionary:
	var text := jwt.split(".")[index].replace("-", "+").replace("_", "/")
	while text.length() % 4 != 0:
		text += "="
	var parsed: Variant = JSON.parse_string(Marshalls.base64_to_raw(text).get_string_from_utf8())
	return parsed if parsed is Dictionary else {}

extends GutTest
## MP1b: OnlineConfig (addresses, device id, stored token in its own file, never the save slots),
## OnlineSession name rules and the relay wire helpers of RelayProtocol.

const TEST_PATH := "user://test_online_config.cfg"


func before_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _config(args: Dictionary = {}) -> OnlineConfig:
	var config := OnlineConfig.new()
	config.path = TEST_PATH
	config.settings_path = TEST_PATH
	config.load_from(args)
	return config


func test_defaults_without_file_or_arguments() -> void:
	var config := _config()
	assert_eq(config.api_url, OnlineConfig.DEFAULT_API_URL)
	assert_eq(config.relay_url, OnlineConfig.DEFAULT_RELAY_URL)
	assert_false(config.relay_explicit)
	assert_eq(OnlineConfig.PROTOCOL_VERSION, 1, "must equal PROTOCOL_VERSION of the relay contract")


func test_command_line_beats_file() -> void:
	var file := ConfigFile.new()
	file.set_value("settings", "api_url", "http://file:1")
	file.set_value("settings", "dev_key", "from-file")
	file.save(TEST_PATH)
	var args := OnlineConfig.parse_args(PackedStringArray(["api=http://arg:2/", "--relay=ws://arg:3/v1", "instance=2", "solo"]))
	assert_eq(args.get("instance"), "2")
	assert_true(args.has("solo"))
	var config := _config(args)
	assert_eq(config.api_url, "http://arg:2", "trailing slash removed")
	assert_eq(config.relay_url, "ws://arg:3/v1")
	assert_true(config.relay_explicit)
	assert_eq(config.dev_key, "from-file")


func test_server_relay_only_without_explicit_relay() -> void:
	var config := _config()
	assert_true(config.apply_server_relay("wss://play.example/v1"))
	assert_eq(config.relay_url, "wss://play.example/v1")
	assert_false(config.apply_server_relay(null), "null = no relay in this environment, keep ours")
	var pinned := _config({"relay": "ws://localhost:9999/v1"})
	assert_false(pinned.apply_server_relay("wss://play.example/v1"))
	assert_eq(pinned.relay_url, "ws://localhost:9999/v1")


func test_device_id_is_a_uuid_and_stays() -> void:
	var config := _config()
	var id := config.get_device_id()
	assert_true(RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$").search(id) != null, id)
	assert_eq(_config().get_device_id(), id, "stored once per installation")
	assert_ne(OnlineConfig.generate_uuid(), OnlineConfig.generate_uuid())


func test_session_is_stored_per_api_and_cleared() -> void:
	var config := _config()
	assert_eq(config.get_stored_session(), {})
	config.store_session("tok", 1_900_000_000, "p-1", "Kerze")
	var again := _config()
	var stored := again.get_stored_session()
	assert_eq(stored.get("token"), "tok")
	assert_eq(stored.get("expires_at"), 1_900_000_000)
	assert_eq(stored.get("player_name"), "Kerze")
	assert_eq(_config({"api": "http://elsewhere:1"}).get_stored_session(), {}, "a token belongs to its API")
	again.clear_session()
	assert_eq(_config().get_stored_session(), {})
	assert_ne(_config().get_device_id(), "", "the device id survives a logout")


func test_game_version_and_platform() -> void:
	assert_eq(OnlineConfig.get_game_version(), "0.9.1")
	assert_has(["windows", "linux", "macos", "android", "ios", "web"], OnlineConfig.get_platform())


func test_iso_time() -> void:
	assert_eq(OnlineConfig.parse_iso_time("2026-10-21T14:23:24.017Z"), Time.get_unix_time_from_datetime_string("2026-10-21T14:23:24"))
	assert_eq(OnlineConfig.parse_iso_time(null), 0)


func test_login_names_follow_the_contract() -> void:
	assert_eq(OnlineSession.sanitize_name("  Kerzen<>schein!! "), "Kerzenschein")
	assert_eq(OnlineSession.sanitize_name("Ä"), OnlineSession.FALLBACK_NAME)
	assert_eq(OnlineSession.sanitize_name("Ein sehr langer Spielername mit Rest").length(), OnlineSession.NAME_MAX)
	assert_eq(OnlineSession.sanitize_name("a  b_c.d-e"), "a b_c.d-e")


func test_room_codes() -> void:
	assert_eq(RelayProtocol.normalize_code(" ab c-d2 3x"), "ABCD23")
	assert_eq(RelayProtocol.normalize_code("o0il1q"), "Q", "ambiguous characters are not in the alphabet")
	assert_true(RelayProtocol.is_valid_code("ABCD23"))
	assert_false(RelayProtocol.is_valid_code("ABCD2"))
	assert_false(RelayProtocol.is_valid_code("abcd23"))


func test_relay_url_gets_its_path() -> void:
	assert_eq(RelayProtocol.with_ws_path("ws://localhost:8790"), "ws://localhost:8790/v1")
	assert_eq(RelayProtocol.with_ws_path("ws://localhost:8790/v1"), "ws://localhost:8790/v1")
	assert_eq(RelayProtocol.with_ws_path("wss://play.playsoulwick.com/"), "wss://play.playsoulwick.com/v1")
	assert_eq(RelayProtocol.prefer_ipv4_loopback("ws://localhost:8790/v1"), "ws://127.0.0.1:8790/v1")
	assert_eq(RelayProtocol.prefer_ipv4_loopback("wss://play.playsoulwick.com/v1"), "wss://play.playsoulwick.com/v1")
	assert_eq(RelayProtocol.prefer_ipv4_loopback("ws://localhostish:1/v1"), "ws://localhostish:1/v1")


func test_lobby_errors_have_texts() -> void:
	for code in RelayProtocol.ERROR_CODES:
		if code in ["invalid_message", "invalid_target", "frame_too_large"]:
			continue
		assert_ne(String(Loc.t(LobbyClient.error_key(code))), String(LobbyClient.error_key(code)), code)
	for reason in ["host_left", "expired", "kicked", "shutdown", "disconnected"]:
		assert_ne(String(Loc.t(LobbyClient.error_key(reason))), String(LobbyClient.error_key(reason)), reason)
	assert_string_contains(LobbyClient.error_text("invalid_message"), "invalid_message")


func test_version_gate() -> void:
	assert_true(LobbyClient.is_version_older("0.9.0", "1.0.0"))
	assert_false(LobbyClient.is_version_older("0.9.0", "0.9.0"))
	assert_false(LobbyClient.is_version_older("0.10.0", "0.9.5"))
	assert_true(LobbyClient.is_version_older("0.9", "0.9.1"))
	assert_false(LobbyClient.is_version_older("1.0.0-beta.2", "1.0.0"))

extends GutTest
## MP4: build environment (editor = local, export = feature tag or online/environment.cfg, default
## development), its addresses with the old overrides still winning, version comparison, the
## start-up version check of the main menu (OnlineVersionCheck) and the export presets (no dev key,
## test and tool folders excluded). No network: the API answers come from a fake transport.

const TEST_PATH := "user://test_online_build.cfg"
const TEST_ENV_PATH := "user://test_online_build_env.cfg"


class FakeTransport extends HttpTransport:
	var answers: Dictionary = {}
	var requests: Array[String] = []

	func send(_owner: Node, _method: HTTPClient.Method, url: String, _headers: PackedStringArray, _body: String, _timeout: float) -> Dictionary:
		var path := url.substr(url.find("/", 8))
		requests.append(path)
		if not answers.has(path):
			return {"status": 0, "body": "", "error": ApiResult.UNREACHABLE}
		return answers[path]

	func answer(path: String, status: int, body: Variant) -> void:
		answers[path] = {"status": status, "body": JSON.stringify(body) if body != null else "", "error": ""}


func before_each() -> void:
	for file_path in [TEST_PATH, TEST_ENV_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	OnlineVersionCheck.reset()


func after_all() -> void:
	for file_path in [TEST_PATH, TEST_ENV_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	OnlineVersionCheck.reset()


func _config(environment: String, args: Dictionary = {}) -> OnlineConfig:
	var config := OnlineConfig.new()
	config.path = TEST_PATH
	config.settings_path = TEST_PATH
	config.environment = environment
	config.load_from(args)
	return config


# --- Environment ---

func test_editor_is_always_local() -> void:
	assert_eq(OnlineConfig.resolve_environment(true, "production", "production"), OnlineConfig.ENV_LOCAL)
	assert_true(OS.has_feature("editor"), "tests run with the editor binary")
	assert_eq(OnlineConfig.build_environment(), OnlineConfig.ENV_LOCAL)


func test_export_takes_feature_tag_then_file_then_development() -> void:
	assert_eq(OnlineConfig.resolve_environment(false, "production", "development"), OnlineConfig.ENV_PRODUCTION, "feature tag of the preset wins")
	assert_eq(OnlineConfig.resolve_environment(false, "", "production"), OnlineConfig.ENV_PRODUCTION)
	assert_eq(OnlineConfig.resolve_environment(false, "", ""), OnlineConfig.ENV_DEVELOPMENT, "test builds default to development")
	assert_eq(OnlineConfig.resolve_environment(false, "", "staging"), OnlineConfig.ENV_DEVELOPMENT, "unknown names are ignored")


func test_environment_file_is_read_and_has_no_dev_key() -> void:
	assert_eq(OnlineConfig.read_environment_file(OnlineConfig.ENVIRONMENT_FILE), OnlineConfig.ENV_DEVELOPMENT)
	var packed := ConfigFile.new()
	assert_eq(packed.load(OnlineConfig.ENVIRONMENT_FILE), OK)
	assert_eq(packed.get_section_keys(OnlineConfig.ENVIRONMENT_SECTION), PackedStringArray(["env"]), "only env, never a dev key")
	var file := ConfigFile.new()
	file.set_value("build", "env", " Production ")
	file.save(TEST_ENV_PATH)
	assert_eq(OnlineConfig.read_environment_file(TEST_ENV_PATH), "production")
	assert_eq(OnlineConfig.read_environment_file("user://does_not_exist.cfg"), "")


func test_environment_addresses_follow_p018() -> void:
	var dev := _config(OnlineConfig.ENV_DEVELOPMENT)
	assert_eq(dev.api_url, "https://api.dev.playsoulwick.com")
	assert_eq(dev.relay_url, "wss://play.dev.playsoulwick.com/v1")
	assert_false(dev.relay_explicit, "GET /public/config may still name another relay")
	assert_eq(dev.get_web_url(), "https://dev.playsoulwick.com")
	assert_eq(dev.get_environment_tag(), "dev")
	var prod := _config(OnlineConfig.ENV_PRODUCTION)
	assert_eq(prod.api_url, "https://api.playsoulwick.com")
	assert_eq(prod.relay_url, "wss://play.playsoulwick.com/v1")
	assert_eq(prod.get_environment_tag(), "", "production shows only the version")
	var local := _config(OnlineConfig.ENV_LOCAL)
	assert_eq(local.api_url, OnlineConfig.DEFAULT_API_URL)
	assert_eq(local.relay_url, OnlineConfig.DEFAULT_RELAY_URL)
	assert_eq(local.get_web_url(), OnlineConfig.DEFAULT_WEB_URL)


func test_overrides_still_win_over_the_environment() -> void:
	var file := ConfigFile.new()
	file.set_value("settings", "api_url", "http://file:1")
	file.set_value("settings", "dev_key", "from-file")
	file.save(TEST_PATH)
	var config := _config(OnlineConfig.ENV_PRODUCTION)
	assert_eq(config.api_url, "http://file:1", "online.cfg beats the build environment")
	assert_eq(config.relay_url, "wss://play.playsoulwick.com/v1")
	assert_eq(config.dev_key, "from-file", "the dev key only comes from online.cfg or the command line")
	var args := OnlineConfig.parse_args(PackedStringArray(["api=http://arg:2", "relay=ws://arg:3/v1", "dev_key=from-arg"]))
	var pinned := _config(OnlineConfig.ENV_PRODUCTION, args)
	assert_eq(pinned.api_url, "http://arg:2")
	assert_eq(pinned.relay_url, "ws://arg:3/v1")
	assert_true(pinned.relay_explicit)
	assert_eq(pinned.dev_key, "from-arg")


func test_command_line_can_switch_the_environment() -> void:
	var config := _config(OnlineConfig.ENV_LOCAL, OnlineConfig.parse_args(PackedStringArray(["env=development"])))
	assert_eq(config.environment, OnlineConfig.ENV_DEVELOPMENT)
	assert_eq(config.api_url, "https://api.dev.playsoulwick.com")
	var unknown := _config(OnlineConfig.ENV_LOCAL, {"env": "staging"})
	assert_eq(unknown.environment, OnlineConfig.ENV_LOCAL, "unknown names change nothing")
	assert_true(_config(OnlineConfig.ENV_DEVELOPMENT).apply_server_relay("wss://other.example/v1"), "server relay replaces the built-in one")


# --- Versions ---

func test_version_comparison() -> void:
	assert_true(OnlineConfig.is_version_older("0.9.0", "0.10.0"))
	assert_true(OnlineConfig.is_version_older("0.9.0", "v0.9.1"), "a leading v is ignored")
	assert_false(OnlineConfig.is_version_older("1.0.0", "0.99.99"))
	assert_false(OnlineConfig.is_version_older("0.9", "0.9.0"), "missing parts count as 0")
	assert_false(OnlineConfig.is_version_older("1.2.3-rc.1", "1.2.3"))
	assert_true(LobbyClient.is_version_older("0.9.0", "1.0.0"), "LobbyClient uses the same rule")


func test_version_check_evaluates_answers() -> void:
	var own := "0.9.0"
	assert_eq(OnlineVersionCheck.evaluate(ApiResult.failure(ApiResult.UNREACHABLE), own), OnlineVersionCheck.Status.OFFLINE)
	assert_eq(OnlineVersionCheck.evaluate(ApiResult.failure(ApiResult.TIMEOUT), own), OnlineVersionCheck.Status.OFFLINE)
	assert_eq(OnlineVersionCheck.evaluate(ApiResult.success(200, {"minGameVersion": "1.0.0"}), own), OnlineVersionCheck.Status.OUTDATED)
	assert_eq(OnlineVersionCheck.evaluate(ApiResult.success(200, {"minGameVersion": "0.9.0"}), own), OnlineVersionCheck.Status.ONLINE)
	assert_eq(OnlineVersionCheck.evaluate(ApiResult.success(200, {"minGameVersion": null}), own), OnlineVersionCheck.Status.ONLINE)
	assert_eq(OnlineVersionCheck.evaluate(ApiResult.success(200, {}), own), OnlineVersionCheck.Status.ONLINE)


func _check(fake: FakeTransport) -> OnlineVersionCheck:
	var check := OnlineVersionCheck.new()
	check.config = _config(OnlineConfig.ENV_LOCAL)
	check.api = ApiClient.new()
	check.api.transport = fake
	add_child_autofree(check)
	return check


func test_version_check_locks_online_when_outdated() -> void:
	var fake := FakeTransport.new()
	fake.answer("/public/config", 200, {"apiVersion": "1", "minGameVersion": "99.0.0", "protocolVersion": 1, "relayUrl": null})
	var check := _check(fake)
	watch_signals(check)
	var status: OnlineVersionCheck.Status = await check.run()
	assert_eq(status, OnlineVersionCheck.Status.OUTDATED)
	assert_signal_emitted_with_parameters(check, "finished", [OnlineVersionCheck.Status.OUTDATED])
	assert_true(OnlineVersionCheck.is_locked())
	assert_eq(OnlineVersionCheck.min_game_version, "99.0.0")
	var lobby := LobbyClient.new()
	lobby.reload_world = false
	add_child_autofree(lobby)
	watch_signals(lobby)
	await lobby.create_room()
	assert_signal_emitted_with_parameters(lobby, "error", [LobbyClient.ERROR_UPDATE_REQUIRED])
	assert_eq(lobby.state, LobbyClient.State.IDLE, "no login, no relay")
	assert_ne(LobbyClient.error_text(LobbyClient.ERROR_UPDATE_REQUIRED), String(LobbyClient.error_key(LobbyClient.ERROR_UPDATE_REQUIRED)))


func test_version_check_offline_and_old_api() -> void:
	var offline := _check(FakeTransport.new())
	assert_eq(await offline.run(), OnlineVersionCheck.Status.OFFLINE)
	assert_false(OnlineVersionCheck.is_locked(), "offline only shows a hint")
	var fake := FakeTransport.new()
	fake.answer("/public/config", 404, {"error": "not_found"})
	fake.answer("/health", 200, {"status": "ok", "apiVersion": "1", "minGameVersion": "0.1.0"})
	var old_api := _check(fake)
	assert_eq(await old_api.run(), OnlineVersionCheck.Status.ONLINE)
	assert_eq(fake.requests, ["/public/config", "/health"] as Array[String], "falls back to GET /health")
	assert_eq(OnlineVersionCheck.apply_config({"minGameVersion": "50.0.0"}), OnlineVersionCheck.Status.OUTDATED, "login path updates the lock too")
	assert_true(OnlineVersionCheck.is_locked())


# --- Main menu footer ---

func test_main_menu_footer_shows_version_environment_and_update_hint() -> void:
	var old_check := MainMenu.online_check
	MainMenu.online_check = false
	var old_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("de")
	var menu := MainMenu.new()
	add_child_autofree(menu)
	assert_eq(MainMenu.build_text("dev"), MainMenu.version_text() + " dev")
	assert_eq(MainMenu.build_text(""), MainMenu.version_text())
	assert_false(menu.get_online_label().visible, "no check, no line")
	OnlineVersionCheck.min_game_version = "9.9.9"
	menu._on_online_checked(OnlineVersionCheck.Status.OUTDATED)
	assert_true(menu.get_online_label().visible)
	assert_string_contains(menu.get_online_label().text, "Bitte aktualisiere das Spiel")
	assert_string_contains(menu.get_online_label().text, "9.9.9")
	assert_eq(menu.get_list().get_entry_hint(MainMenu.ENTRY_ONLINE), "Update nötig")
	menu._on_online_checked(OnlineVersionCheck.Status.OFFLINE)
	assert_string_contains(menu.get_online_label().text, "Einzelspieler")
	TranslationServer.set_locale(old_locale)
	MainMenu.online_check = old_check


# --- Export presets ---

func test_export_presets_exclude_dev_folders_and_never_carry_a_dev_key() -> void:
	var presets := ConfigFile.new()
	assert_eq(presets.load("res://export_presets.cfg"), OK)
	var by_name := {}
	for section in presets.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			by_name[presets.get_value(section, "name")] = section
	for preset_name in ["Windows Desktop", "Linux", "Linux Dedicated Server"]:
		assert_true(by_name.has(preset_name), preset_name)
		var section: String = by_name.get(preset_name, "")
		var excluded := str(presets.get_value(section, "exclude_filter", ""))
		for folder in ["tests/*", "tools/*", "addons/gut/*", "docs/*", ".userdata/*", "builds/*"]:
			assert_string_contains(excluded, folder, "%s excludes %s" % [preset_name, folder])
		assert_string_contains(str(presets.get_value(section, "include_filter", "")), "online/environment.cfg")
		assert_eq(str(presets.get_value(section + ".options", "binary_format/architecture", "")), "x86_64")
	assert_true(bool(presets.get_value(by_name["Linux Dedicated Server"], "dedicated_server", false)))
	assert_true(bool(presets.get_value(by_name["Windows Desktop"] + ".options", "binary_format/embed_pck", false)))
	assert_eq(str(presets.get_value(by_name["Windows Desktop"] + ".options", "application/product_name", "")), "Soulwick")
	var text := FileAccess.get_file_as_string("res://export_presets.cfg")
	assert_false(text.contains("dev_key"), "the dev key is never part of a build")

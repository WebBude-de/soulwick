class_name OnlineConfig
extends RefCounted
## Where the online services of this environment are and what this installation remembers about
## them (MP1b, D-121, D-124). Nothing here is needed for single player.
##
## Addresses, strongest first: command line after "--" (api=…, relay=…, dev_key=…, name=…,
## instance=N, env=…), the [settings] section of user://online.cfg, the project settings
## soulwick/online/api_url and soulwick/online/relay_url (feature tags like .release work), then the
## addresses of the build environment (MP4, platform P-018): the editor and every run of the editor
## binary use "local" (localhost), an exported game takes the feature tag env_<name> of its export
## preset, else env of res://online/environment.cfg (written by tools/export_build.*), else
## "development". The relay URL the API reports in GET /public/config is used unless the relay was
## set explicitly. The dev key is never part of a build: only online.cfg or the command line.
##
## The same file stores the device id (random UUID, created once per installation and instance)
## and the login token with its expiry, never the save slots. Several game instances on one machine
## (editor "Customize Run Instances") pass instance=2..4: they share the [settings] of
## user://online.cfg but keep device id and token in user://online_<n>.cfg, so every instance is a
## device of its own.

## Preloaded: works before the global class cache knows SafeSave (new file).
const SafeSaveScript := preload("res://meta/safe_save.gd")
const DEFAULT_API_URL := "http://localhost:3101"
const DEFAULT_RELAY_URL := "ws://localhost:3103/v1"
## Must equal PROTOCOL_VERSION in soulwick-platform/packages/contracts/src/lobby.ts and the relay.
const PROTOCOL_VERSION := 1
const FILE_PATH := "user://online.cfg"
const INSTANCE_FILE_PATH := "user://online_%d.cfg"
const SETTING_API_URL := "soulwick/online/api_url"
const SETTING_RELAY_URL := "soulwick/online/relay_url"
const SECTION_SETTINGS := "settings"
const SECTION_DEVICE := "device"
const SECTION_SESSION := "session"
const VERSION_SETTING := "application/config/version"

const ENV_LOCAL := "local"
const ENV_DEVELOPMENT := "development"
const ENV_PRODUCTION := "production"
## Packed into exports by the include filter of export_presets.cfg; only "env" is read from it.
const ENVIRONMENT_FILE := "res://online/environment.cfg"
const ENVIRONMENT_SECTION := "build"
## Feature tag prefix of an export preset, e.g. env_production.
const ENVIRONMENT_FEATURE_PREFIX := "env_"
## Addresses per environment (platform P-018). local = the services of `bun dev` in soulwick-platform.
const ENVIRONMENTS := {
	ENV_LOCAL: {"api": DEFAULT_API_URL, "relay": DEFAULT_RELAY_URL, "web": ""},
	ENV_DEVELOPMENT: {"api": "https://api-dev.playsoulwick.com", "relay": "wss://play-dev.playsoulwick.com/v1", "web": "https://dev.playsoulwick.com"},
	ENV_PRODUCTION: {"api": "https://api.playsoulwick.com", "relay": "wss://play.playsoulwick.com/v1", "web": "https://playsoulwick.com"},
}
## Website for "please update" when the environment has none of its own (local).
const DEFAULT_WEB_URL := "https://playsoulwick.com"

var api_url := DEFAULT_API_URL
var relay_url := DEFAULT_RELAY_URL
## local, development or production (see above); decides the default addresses.
var environment := ENV_LOCAL
## Key for POST /auth/dev (x-dev-auth-key); only the test phase needs it.
var dev_key := ""
## Player name for the dev login instead of the save's profile name (tests, several instances).
var name_override := ""
## 1 for a normal start, 2..4 for further instances on the same machine.
var instance := 1
## Storage file of this instance: device id and token (tests point it elsewhere, AGENTS.md rule 4
## by analogy).
var path := FILE_PATH
## File with the [settings] section, shared by all instances.
var settings_path := FILE_PATH

## True when the relay came from the command line, online.cfg or the project settings: then the
## relay URL of GET /public/config does not replace it.
var relay_explicit := false
var _file := ConfigFile.new()


## Configuration of this game start: defaults, project settings, online.cfg, command line.
static func load_default() -> OnlineConfig:
	var args := parse_args(OS.get_cmdline_user_args())
	var config := OnlineConfig.new()
	config.instance = clampi(int(args.get("instance", args.get("player", "1"))), 1, 99)
	config.path = FILE_PATH if config.instance == 1 else INSTANCE_FILE_PATH % config.instance
	config.environment = build_environment()
	config.load_from(args)
	return config


## Environment of this build: local in the editor binary, else feature tag env_<name> of the export
## preset, else res://online/environment.cfg, else development.
static func build_environment() -> String:
	var feature_env := ""
	for env_name: String in ENVIRONMENTS:
		if OS.has_feature(ENVIRONMENT_FEATURE_PREFIX + env_name):
			feature_env = env_name
	return resolve_environment(OS.has_feature("editor"), feature_env, read_environment_file(ENVIRONMENT_FILE))


## Pure rule of build_environment() (tests): the editor is always local; a known feature tag beats
## the file; unknown or missing values fall back to development (test builds for friends, MP4).
static func resolve_environment(is_editor: bool, feature_env: String, file_env: String) -> String:
	if is_editor:
		return ENV_LOCAL
	for candidate in [feature_env, file_env]:
		if is_known_environment(candidate):
			return candidate
	return ENV_DEVELOPMENT


static func is_known_environment(env_name: String) -> bool:
	return ENVIRONMENTS.has(env_name)


## env of the [build] section ("" if the file is missing or has none), lower case.
static func read_environment_file(file_path: String) -> String:
	var file := ConfigFile.new()
	if file.load(file_path) != OK:
		return ""
	return str(file.get_value(ENVIRONMENT_SECTION, "env", "")).strip_edges().to_lower()


## key=value pairs from user arguments ("api=…" or "--api=…"); bare words become "word": "".
static func parse_args(args: PackedStringArray) -> Dictionary:
	var result := {}
	for arg in args:
		var text := arg.trim_prefix("--")
		var cut := text.find("=")
		if cut < 0:
			result[text] = ""
		else:
			result[text.substr(0, cut)] = text.substr(cut + 1)
	return result


## Reads the storage file and applies settings in the order described above.
func load_from(args: Dictionary = {}) -> void:
	_file = ConfigFile.new()
	SafeSaveScript.load_config(_file, path)
	var settings := _file
	if settings_path != path:
		settings = ConfigFile.new()
		settings.load(settings_path)
	var wanted_env := str(args.get("env", "")).strip_edges().to_lower()
	if is_known_environment(wanted_env):
		environment = wanted_env
	if not is_known_environment(environment):
		environment = ENV_DEVELOPMENT
	api_url = str(ENVIRONMENTS[environment]["api"])
	relay_url = str(ENVIRONMENTS[environment]["relay"])
	relay_explicit = false
	var project_api := str(ProjectSettings.get_setting(SETTING_API_URL, ""))
	var project_relay := str(ProjectSettings.get_setting(SETTING_RELAY_URL, ""))
	if not project_api.is_empty():
		api_url = project_api
	if not project_relay.is_empty():
		relay_url = project_relay
		relay_explicit = true
	api_url = str(settings.get_value(SECTION_SETTINGS, "api_url", api_url))
	if settings.has_section_key(SECTION_SETTINGS, "relay_url"):
		relay_url = str(settings.get_value(SECTION_SETTINGS, "relay_url"))
		relay_explicit = true
	dev_key = str(settings.get_value(SECTION_SETTINGS, "dev_key", dev_key))
	# A name in the instance's own file wins (several instances, several names).
	name_override = str(settings.get_value(SECTION_SETTINGS, "name", name_override))
	name_override = str(_file.get_value(SECTION_SETTINGS, "name", name_override))
	if args.has("api"):
		api_url = str(args["api"])
	if args.has("relay"):
		relay_url = str(args["relay"])
		relay_explicit = true
	if args.has("dev_key"):
		dev_key = str(args["dev_key"])
	if args.has("name"):
		name_override = str(args["name"])
	api_url = api_url.strip_edges().trim_suffix("/")
	relay_url = relay_url.strip_edges()


## Takes the relay of GET /public/config unless one was set explicitly. Returns whether it changed.
func apply_server_relay(url: Variant) -> bool:
	if relay_explicit or typeof(url) != TYPE_STRING or String(url).is_empty() or url == relay_url:
		return false
	relay_url = String(url)
	return true


## Website of this environment (download of a newer version), never empty.
func get_web_url() -> String:
	var web := str(ENVIRONMENTS.get(environment, {}).get("web", ""))
	return web if not web.is_empty() else DEFAULT_WEB_URL


## Short tag for the main menu footer: "" in production, "dev" for development, else the name.
func get_environment_tag() -> String:
	return environment_tag(environment)


static func environment_tag(env_name: String) -> String:
	match env_name:
		ENV_PRODUCTION:
			return ""
		ENV_DEVELOPMENT:
			return "dev"
	return env_name


## Random id of this installation (and instance) for POST /auth/dev, created on first use.
func get_device_id() -> String:
	var id := str(_file.get_value(SECTION_DEVICE, "id", ""))
	if id.length() < 16:
		id = generate_uuid()
		_file.set_value(SECTION_DEVICE, "id", id)
		save()
	return id


## Stored login of this API: {token, expires_at (unix s), player_id, player_name} or {}.
func get_stored_session() -> Dictionary:
	if not _file.has_section(SECTION_SESSION):
		return {}
	if str(_file.get_value(SECTION_SESSION, "api_url", "")) != api_url:
		return {}
	var token := str(_file.get_value(SECTION_SESSION, "token", ""))
	if token.is_empty():
		return {}
	return {
		"token": token,
		"expires_at": int(_file.get_value(SECTION_SESSION, "expires_at", 0)),
		"player_id": str(_file.get_value(SECTION_SESSION, "player_id", "")),
		"player_name": str(_file.get_value(SECTION_SESSION, "player_name", "")),
	}


func store_session(token: String, expires_at: int, player_id: String, player_name: String) -> void:
	_file.set_value(SECTION_SESSION, "api_url", api_url)
	_file.set_value(SECTION_SESSION, "token", token)
	_file.set_value(SECTION_SESSION, "expires_at", expires_at)
	_file.set_value(SECTION_SESSION, "player_id", player_id)
	_file.set_value(SECTION_SESSION, "player_name", player_name)
	save()


func clear_session() -> void:
	if _file.has_section(SECTION_SESSION):
		_file.erase_section(SECTION_SESSION)
		save()


func save() -> void:
	var error := SafeSaveScript.write_config(_file, path)
	if error != OK:
		push_warning("OnlineConfig: could not write %s (%s)." % [path, error_string(error)])


## "0.9.0" older than "1.0.0"? Numeric parts compared one by one, pre-release suffixes ignored,
## missing parts count as 0 (KONZEPT_ONLINE §3.8 minGameVersion).
static func is_version_older(version: String, minimum: String) -> bool:
	var a := version.strip_edges().trim_prefix("v").split("-")[0].split(".")
	var b := minimum.strip_edges().trim_prefix("v").split("-")[0].split(".")
	for i in maxi(a.size(), b.size()):
		var x := int(a[i]) if i < a.size() else 0
		var y := int(b[i]) if i < b.size() else 0
		if x != y:
			return x < y
	return false


## Version of this build (project.godot application/config/version), sent to the relay.
static func get_game_version() -> String:
	var version := str(ProjectSettings.get_setting(VERSION_SETTING, ""))
	return version if not version.is_empty() else "0.0.0"


## Platform name of the relay contract (ClientPlatform): windows, linux, macos, android, ios, web.
static func get_platform() -> String:
	match OS.get_name():
		"Windows":
			return "windows"
		"Web":
			return "web"
		"macOS":
			return "macos"
		"Android":
			return "android"
		"iOS":
			return "ios"
	return "linux"


## Random UUID version 4, e.g. "3f0c1d5e-8a2b-4c6d-9e1f-0a1b2c3d4e5f".
static func generate_uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


## ISO 8601 date from the API ("2026-10-21T14:23:24.017Z") as unix seconds; 0 if unreadable.
static func parse_iso_time(text: Variant) -> int:
	if typeof(text) != TYPE_STRING or String(text).is_empty():
		return 0
	var value := String(text)
	var cut := value.find(".")
	if cut >= 0:
		value = value.substr(0, cut)
	value = value.trim_suffix("Z")
	return Time.get_unix_time_from_datetime_string(value)

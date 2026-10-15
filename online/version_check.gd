class_name OnlineVersionCheck
extends Node
## Start-up check of the main menu (MP4, KONZEPT_ONLINE §3.8, platform P16): reads GET /public/config
## of this build's environment once, without blocking anything. Is this build older than
## minGameVersion, the online features are locked ("please update", LobbyClient refuses rooms);
## is the API unreachable, the menu shows an offline hint and single player works as always.
## The result stays in static vars for the rest of this game start (no autoload, D-044).

signal finished(status: Status)

enum Status { UNKNOWN, CHECKING, ONLINE, OUTDATED, OFFLINE }

## Result of the last check of this game start (UNKNOWN until one finished).
static var last_status := Status.UNKNOWN
## minGameVersion of the last answer ("" if the API names none).
static var min_game_version := ""

## Replaceable for tests; created from OnlineConfig.load_default() when null.
var config: OnlineConfig = null
var api: ApiClient = null
var status := Status.UNKNOWN


## Online features locked because this build is too old.
static func is_locked() -> bool:
	return last_status == Status.OUTDATED


## Forget the result (tests).
static func reset() -> void:
	last_status = Status.UNKNOWN
	min_game_version = ""


## Status for an answer of GET /public/config or GET /health: no usable answer = OFFLINE, own
## version older than minGameVersion = OUTDATED, else ONLINE (also when the API names no minimum).
static func evaluate(result: ApiResult, own_version: String) -> Status:
	if result == null or not result.ok or not (result.data is Dictionary):
		return Status.OFFLINE
	return evaluate_config(result.data, own_version)


static func evaluate_config(data: Dictionary, own_version: String) -> Status:
	var minimum: Variant = data.get("minGameVersion", null)
	if typeof(minimum) == TYPE_STRING and not String(minimum).is_empty() and OnlineConfig.is_version_older(own_version, minimum):
		return Status.OUTDATED
	return Status.ONLINE


## Takes a public config read elsewhere (OnlineSession after a login) into the static result.
static func apply_config(data: Dictionary) -> Status:
	var result := evaluate_config(data, OnlineConfig.get_game_version())
	_remember(result, data)
	return result


static func _remember(result: Status, data: Variant) -> void:
	last_status = result
	if data is Dictionary and typeof(data.get("minGameVersion", null)) == TYPE_STRING:
		min_game_version = String(data["minGameVersion"])
	else:
		min_game_version = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if config == null:
		config = OnlineConfig.load_default()
	if api == null:
		api = ApiClient.new()
		api.name = "ApiClient"
	if api.get_parent() == null:
		add_child(api)
	api.base_url = config.api_url


## Runs the check (coroutine): GET /public/config, for older APIs (404) GET /health.
func run() -> Status:
	status = Status.CHECKING
	var result := await api.get_public_config()
	if not result.ok and result.status == 404:
		result = await api.get_health()
	status = evaluate(result, OnlineConfig.get_game_version())
	_remember(status, result.data if result.ok else null)
	finished.emit(status)
	return status

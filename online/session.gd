class_name OnlineSession
extends Node
## Login state of this game instance (MP1b, D-121, D-124): account, token and its expiry, the
## environment's public config. Lives under the game scene, not as an autoload (D-044): of(node)
## finds it or creates it below the current scene (hook for the integrator: put a node with this
## script into scenes/game.tscn, then nothing is created on the fly). Token and device id are kept
## in user://online.cfg (OnlineConfig), never in the save slots.
## Two tokens (P-027): token is the Better Auth session token of the login (30 days, Bearer on every
## API route, stored); relay_token is a short-lived player JWT from GET /auth/token for hello.token
## at the relay (15 min, only in memory, see ensure_relay_token). A 401 on any authenticated call
## drops the session token, the next ensure_login() logs in again.
## Single player never needs any of this; every failure only changes the status.

signal state_changed(state: State)

enum State { OFFLINE, LOGGING_IN, ONLINE, FAILED }

const GROUP: StringName = &"online_session"
## A stored token is reused while it is valid for at least this many seconds more.
const TOKEN_MARGIN_SECONDS := 300
## TESTWERT: the relay JWT is reused while it is valid for at least this many seconds more.
const RELAY_TOKEN_MARGIN_SECONDS := 60
## Lifetime of the relay JWT (contracts PLAYER_JWT_TTL_SECONDS); caps the cache when the local clock
## is behind the server's.
const RELAY_TOKEN_TTL_SECONDS := 900
const FALLBACK_NAME := "Spieler"
## Allowed in PlayerName (contracts common.ts): letters, digits, space, _ . -; 2–24 characters.
const NAME_MIN := 2
const NAME_MAX := 24

var config: OnlineConfig = null
var api: ApiClient = null
var state := State.OFFLINE
## PlayerSelf of the account ({} while offline).
var player: Dictionary = {}
var token := ""
## Unix seconds.
var token_expires_at := 0
## ApiResult error of the last failed login ("" if none).
var last_error := ""
var last_result: ApiResult = null
## GET /public/config of this environment ({} until fetched or when the API has none).
var public_config: Dictionary = {}
## Player JWT for hello.token at the relay (GET /auth/token, P-027), "" if none; never stored.
var relay_token := ""
## Unix seconds (local clock), 0 without a relay token.
var relay_token_expires_at := 0

var _login_running := false
var _relay_token_running := false


## The session of the running game: found in the tree or created below the current scene.
static func of(node: Node) -> OnlineSession:
	if node == null or not node.is_inside_tree():
		return null
	var tree := node.get_tree()
	var existing := tree.get_first_node_in_group(GROUP) as OnlineSession
	if existing != null:
		return existing
	var parent := tree.current_scene if tree.current_scene != null else tree.root
	var session := OnlineSession.new()
	session.name = "OnlineSession"
	parent.add_child(session)
	return session


func _init(online_config: OnlineConfig = null) -> void:
	config = online_config


func _enter_tree() -> void:
	add_to_group(GROUP)


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
	api.dev_key = config.dev_key
	if not api.unauthorized.is_connected(_on_unauthorized):
		api.unauthorized.connect(_on_unauthorized)


func is_logged_in() -> bool:
	return state == State.ONLINE and not token.is_empty() and not is_token_expired()


func is_token_expired(margin := 0) -> bool:
	return token_expires_at > 0 and token_expires_at - margin <= int(Time.get_unix_time_from_system())


func get_player_id() -> String:
	return str(player.get("id", ""))


func get_player_name() -> String:
	return str(player.get("name", ""))


## The relay of this environment: the one from GET /public/config, else the configured one.
func get_relay_url() -> String:
	return config.relay_url


## Logs in if needed (coroutine): reuses a stored token that is valid for a while, otherwise the
## dev login (with a dev key) or the guest login with the save's player name and this
## installation's device id. Also reads the public
## config once (relay URL, protocol version). Returns the result of the step that decided.
func ensure_login() -> ApiResult:
	if is_logged_in() and not is_token_expired(TOKEN_MARGIN_SECONDS):
		return ApiResult.success(200, player)
	while _login_running:
		await get_tree().process_frame
	if is_logged_in() and not is_token_expired(TOKEN_MARGIN_SECONDS):
		return ApiResult.success(200, player)
	_login_running = true
	_set_state(State.LOGGING_IN)
	var result := await _login()
	_login_running = false
	last_result = result
	last_error = "" if result.ok else result.error
	_set_state(State.ONLINE if result.ok else State.FAILED)
	return result


## Forgets the token (also in online.cfg); the device id stays.
func logout() -> void:
	_drop_session()
	player = {}
	_set_state(State.OFFLINE)


## A cached relay JWT valid for at least RELAY_TOKEN_MARGIN_SECONDS more (and a live login)?
func has_relay_token() -> bool:
	if relay_token.is_empty() or not is_logged_in():
		return false
	return relay_token_expires_at - RELAY_TOKEN_MARGIN_SECONDS > int(Time.get_unix_time_from_system())


## Drops the cached relay JWT, e.g. after the relay refused it (unauthorized); the next connection
## fetches a new one. The session token stays.
func forget_relay_token() -> void:
	relay_token = ""
	relay_token_expires_at = 0


## The player JWT for hello.token (coroutine, P-027), fetched before every connection to the relay
## (create, join): the cached one while it is valid for RELAY_TOKEN_MARGIN_SECONDS more, else a new
## one from GET /auth/token. Logs in first if needed. A 401 (session expired or revoked) has dropped
## the session token: logs in once more (dev login with a dev key, else the guest login) and asks
## again. 403 banned and network errors come back as they are.
## ok: data = {token, expiresAt (unix s)}.
func ensure_relay_token() -> ApiResult:
	while _relay_token_running:
		await get_tree().process_frame
	if has_relay_token():
		return ApiResult.success(200, {"token": relay_token, "expiresAt": relay_token_expires_at})
	_relay_token_running = true
	var result := await _fetch_relay_token(true)
	_relay_token_running = false
	if not result.ok:
		last_result = result
		last_error = result.error
		if result.error == ApiResult.BANNED:
			_set_state(State.FAILED)
	return result


## Fetches GET /public/config (coroutine) and takes its relay URL unless one was set explicitly.
func refresh_public_config() -> ApiResult:
	var result := await api.get_public_config()
	if result.ok and result.data is Dictionary:
		public_config = result.data
		config.apply_server_relay(public_config.get("relayUrl", null))
	return result


func _login() -> ApiResult:
	var stored := config.get_stored_session()
	if not stored.is_empty() and int(stored.expires_at) - TOKEN_MARGIN_SECONDS > int(Time.get_unix_time_from_system()):
		api.token = str(stored.token)
		var me := await api.get_me()
		if me.ok and me.data is Dictionary:
			_accept(str(stored.token), int(stored.expires_at), me.data)
			await refresh_public_config()
			return me
		if me.error == ApiResult.BANNED:
			return me
		# Unreachable: keep the stored token for the next try. Rejected: log in again below.
		if me.error == ApiResult.UNREACHABLE or me.error == ApiResult.TIMEOUT:
			api.token = ""
			return me
		api.token = ""
	# With a dev key the test login, otherwise the guest account of this installation.
	var login: ApiResult
	if api.dev_key.is_empty():
		login = await api.login_device(get_login_name(), config.get_device_id())
	else:
		login = await api.login_dev(get_login_name(), config.get_device_id())
		# A dev key from local testing does not fit another server: fall back to the guest account.
		# A ban stays a ban (403 banned), never a way around it.
		if not login.ok and login.status in [401, 403, 404] and login.error != ApiResult.BANNED:
			login = await api.login_device(get_login_name(), config.get_device_id())
	if not login.ok:
		return login
	var body: Dictionary = login.data if login.data is Dictionary else {}
	var new_token := str(body.get("token", ""))
	var self_data: Variant = body.get("player", null)
	if new_token.is_empty() or not (self_data is Dictionary):
		return ApiResult.failure(ApiResult.BAD_RESPONSE, "AuthResponse without token or player", login.status, login.data)
	var expires := OnlineConfig.parse_iso_time(body.get("expiresAt", null))
	_accept(new_token, expires, self_data)
	config.store_session(new_token, expires, get_player_id(), get_player_name())
	await refresh_public_config()
	return login


func _fetch_relay_token(retry: bool) -> ApiResult:
	var login := await ensure_login()
	if not login.ok:
		return login
	var answer := await api.get_relay_token()
	if not answer.ok:
		# 401: _on_unauthorized dropped the session token, ensure_login() logs in again.
		if retry and answer.status == 401:
			return await _fetch_relay_token(false)
		return answer
	var body: Dictionary = answer.data if answer.data is Dictionary else {}
	var jwt := str(body.get("token", ""))
	if jwt.is_empty():
		return ApiResult.failure(ApiResult.BAD_RESPONSE, "AuthTokenResponse without token", answer.status, answer.data)
	var now := int(Time.get_unix_time_from_system())
	var expires := OnlineConfig.parse_iso_time(body.get("expiresAt", null))
	relay_token = jwt
	relay_token_expires_at = mini(expires, now + RELAY_TOKEN_TTL_SECONDS) if expires > 0 else now + RELAY_TOKEN_TTL_SECONDS
	return ApiResult.success(answer.status, {"token": relay_token, "expiresAt": relay_token_expires_at})


## 401 on an authenticated call: the session token is gone for good (expired, revoked, account
## deleted). Forget it here and in online.cfg; a running login handles the rest itself.
func _on_unauthorized(_path: String) -> void:
	_drop_session()
	if not _login_running:
		player = {}
		_set_state(State.OFFLINE)


func _drop_session() -> void:
	token = ""
	token_expires_at = 0
	api.token = ""
	forget_relay_token()
	config.clear_session()


func _accept(new_token: String, expires_at: int, self_data: Dictionary) -> void:
	if new_token != token:
		forget_relay_token()
	token = new_token
	token_expires_at = expires_at
	player = self_data
	api.token = new_token


## Name for a new account: name= override, else the save's profile name, made valid for the API.
func get_login_name() -> String:
	var raw := config.name_override if not config.name_override.is_empty() else SaveManager.get_display_name()
	var name_text := sanitize_name(raw)
	if config.instance > 1 and config.name_override.is_empty():
		name_text = sanitize_name("%s %d" % [name_text.left(NAME_MAX - 2), config.instance])
	return name_text


## Keeps letters, digits, space, _ . - and trims to 2..24 characters ("Spieler" if too short).
static func sanitize_name(raw: String) -> String:
	var regex := RegEx.create_from_string("[^\\p{L}\\p{N} _.-]")
	var cleaned := regex.sub(raw, "", true).strip_edges()
	while cleaned.contains("  "):
		cleaned = cleaned.replace("  ", " ")
	cleaned = cleaned.left(NAME_MAX).strip_edges()
	return cleaned if cleaned.length() >= NAME_MIN else FALLBACK_NAME


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)

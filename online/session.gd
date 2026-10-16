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
## Account profile (D-152): the login sends the player's name and look (PlayerProfile; the API only
## uses them when the account is created). Afterwards sync_profile() decides who wins: what was
## changed here and not sent yet (dirty) goes up with PATCH /me, otherwise the server's profile is
## taken (a profile that never met this account is sent up once). push_profile() sends a change made
## in the game (editor in the menu, lobby, village); a refused name change (429
## name_change_limited) keeps the server's name and sends the look alone (profile_hint() says when
## the name can change again).

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
## Errors of PATCH /me (contracts player.ts).
const NAME_CHANGE_LIMITED := "name_change_limited"
const VALIDATION_ERROR := "validation_error"

## Take part in the profile sync of D-152 (login body with the look, sync after the login). Off in
## runs started with a script (tests, tools) unless they switch it on: their fake servers and test
## accounts must not change a profile on disk.
static var profile_sync_enabled := not PlayerProfile.is_script_run()

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


## One authenticated API call for menus (coroutine, D-147 guilds): logs in first if needed, then
## calls fn with the ApiClient. A 401 (session expired or revoked) has dropped the session token:
## logs in once more and repeats the call. A build too old for the API (OnlineVersionCheck) sends
## nothing. fn: Callable(api: ApiClient) -> ApiResult, e.g. func(api): return await api.get_my_guilds().
func call_api(fn: Callable) -> ApiResult:
	if OnlineVersionCheck.is_locked():
		return ApiResult.failure(ApiResult.UPDATE_REQUIRED, "Game too old for the API")
	var login := await ensure_login()
	if not login.ok:
		return login
	if not public_config.is_empty() and OnlineVersionCheck.apply_config(public_config) == OnlineVersionCheck.Status.OUTDATED:
		return ApiResult.failure(ApiResult.UPDATE_REQUIRED, "Game too old for the API")
	var result: ApiResult = await fn.call(api)
	if result.status == 401:
		login = await ensure_login()
		if not login.ok:
			return login
		result = await fn.call(api)
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
			await sync_profile()
			return me
		if me.error == ApiResult.BANNED:
			return me
		# Unreachable: keep the stored token for the next try. Rejected: log in again below.
		if me.error == ApiResult.UNREACHABLE or me.error == ApiResult.TIMEOUT:
			api.token = ""
			return me
		api.token = ""
	# With a dev key the test login, otherwise the guest account of this installation. Name and look
	# of the profile only count when the account is created (D-152).
	var login: ApiResult
	var look := get_login_appearance()
	if api.dev_key.is_empty():
		login = await api.login_device(get_login_name(), config.get_device_id(), look)
	else:
		login = await api.login_dev(get_login_name(), config.get_device_id(), look)
		# A dev key from local testing does not fit another server: fall back to the guest account.
		# A ban stays a ban (403 banned), never a way around it.
		if not login.ok and login.status in [401, 403, 404] and login.error != ApiResult.BANNED:
			login = await api.login_device(get_login_name(), config.get_device_id(), look)
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
	await sync_profile()
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


## Name for a new account: name= override, else the player's profile name (D-152; before the first
## start the name of an older save slot), made valid for the API. Instance N > 1 without a profile
## of its own gets " N" (several windows on one PC).
func get_login_name() -> String:
	if not config.name_override.is_empty():
		return sanitize_name(config.name_override)
	var profile := PlayerProfile.current()
	var raw := profile.player_name
	if raw.is_empty():
		raw = str(PlayerProfile.legacy_suggestion().get("name", ""))
	var name_text := sanitize_name(raw if not raw.is_empty() else profile.get_display_name())
	if config.instance > 1 and profile.player_name.is_empty():
		name_text = sanitize_name("%s %d" % [name_text.left(NAME_MAX - 2), config.instance])
	return name_text


## Look for a new account: the profile's, once the player chose one ({} = the server's default).
func get_login_appearance() -> Dictionary:
	var profile := PlayerProfile.current()
	return profile.look.duplicate(true) if profile_sync_enabled and profile.is_set_up else {}


# --- Account profile (D-152) ---

## After a login (coroutine): who wins between this machine's profile and the account's.
## - No profile here yet (no first start): the server's name and look are taken.
## - Changed here and not sent (dirty), or the profile never met this account: sent up (PATCH /me).
## - Otherwise the server wins (changed on another device); an account without a look gets ours.
func sync_profile() -> void:
	if not profile_sync_enabled or player.is_empty():
		return
	var profile := PlayerProfile.current()
	var server_look: Variant = player.get("appearance", null)
	if profile.needs_setup():
		profile.take_server_profile(player)
		return
	if profile.synced_player_id != get_player_id():
		profile.name_dirty = profile.name_dirty or profile.player_name != get_player_name()
		profile.look_dirty = profile.look_dirty or not (server_look is Dictionary and PlayerLook.equals(server_look, profile.look))
	elif not profile.name_dirty and not profile.look_dirty:
		if server_look is Dictionary or profile.player_name != get_player_name():
			profile.take_server_profile(player)
			if server_look is Dictionary:
				return
		profile.look_dirty = true
	var result := await push_profile(true)
	if not result.ok and result.error != NAME_CHANGE_LIMITED and result.error != VALIDATION_ERROR:
		push_warning("OnlineSession: profile not synced (%s), next login tries again." % result.error)


## Sends what the server does not know yet (coroutine, PATCH /me): the name if it changed, the look
## if it changed. ok without a request when nothing is dirty. 429 name_change_limited: the name goes
## back to the server's (profile.name_locked_until is set) and the look is sent alone. 400
## validation_error on the name: back to the server's name too. Network errors keep everything
## dirty for the next login. direct: send with the current token without call_api (used inside the
## login itself, where call_api would wait for the running login).
func push_profile(direct := false) -> ApiResult:
	var profile := PlayerProfile.current()
	if not profile_sync_enabled:
		return ApiResult.success(200, player)
	var body := {}
	var name_locked := profile.name_dirty and profile.get_name_wait_seconds() > 0
	if profile.name_dirty and not name_locked:
		body["name"] = profile.player_name
	if profile.look_dirty:
		body["appearance"] = profile.look.duplicate(true)
	var refused: ApiResult = null
	if name_locked:
		# Known from an earlier answer: do not ask again, keep the server's name.
		refused = ApiResult.failure(NAME_CHANGE_LIMITED, "Name change limit", 429)
		refused.retry_after_seconds = profile.get_name_wait_seconds()
		_keep_server_name(profile)
	if body.is_empty():
		return refused if refused != null else ApiResult.success(200, player)
	var result := await _patch_me(body, direct)
	if result.ok:
		_take_player(result.data)
		profile.mark_synced(get_player_id(), body.has("name"), body.has("appearance"))
		return refused if refused != null else result
	if body.has("name") and (result.error == NAME_CHANGE_LIMITED or result.error == VALIDATION_ERROR):
		if result.error == NAME_CHANGE_LIMITED:
			profile.name_locked_until = int(Time.get_unix_time_from_system()) + retry_seconds(result)
		_keep_server_name(profile)
		# The look of a refused request was not applied either: send it alone.
		if body.has("appearance"):
			var look_only := await _patch_me({"appearance": body["appearance"]}, direct)
			if look_only.ok:
				_take_player(look_only.data)
				profile.mark_synced(get_player_id(), false, true)
	return result


func _patch_me(body: Dictionary, direct: bool) -> ApiResult:
	if direct:
		return await api.update_profile(body)
	return await call_api(func(client: ApiClient) -> ApiResult: return await client.update_profile(body))


## Seconds of a 429 answer: Retry-After header, else retryAfter in the body (0 if neither).
static func retry_seconds(result: ApiResult) -> int:
	if result.retry_after_seconds > 0:
		return result.retry_after_seconds
	if result.data is Dictionary:
		var value: Variant = result.data.get("retryAfter", 0)
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
			return maxi(0, int(value))
	return 0


## A line for the player about a push_profile() result ("" = nothing to say): when the name can be
## changed again, an invalid name, or that the server is not reachable (saved here, sent later).
static func profile_hint(result: ApiResult) -> String:
	if result == null or result.ok:
		return ""
	match result.error:
		NAME_CHANGE_LIMITED:
			var seconds := retry_seconds(result)
			if seconds <= 0:
				return Loc.t(&"PROFILE_NAME_LIMITED_SOON")
			if seconds < 3600:
				return Loc.t(&"PROFILE_NAME_LIMITED_MINUTES", [maxi(1, ceili(seconds / 60.0))])
			return Loc.t(&"PROFILE_NAME_LIMITED_HOURS", [ceili(seconds / 3600.0)])
		VALIDATION_ERROR:
			return Loc.t(&"PROFILE_NAME_INVALID")
	return Loc.t(&"PROFILE_SAVED_OFFLINE")


func _keep_server_name(profile: PlayerProfile) -> void:
	var server_name := get_player_name()
	if server_name.length() >= NAME_MIN and profile.player_name != server_name:
		profile.player_name = server_name.left(NAME_MAX)
		SaveManager.profile_changed.emit()
	profile.name_dirty = false
	profile.save()


## A PlayerSelf from PATCH /me replaces the cached one (name, appearance, guilds).
func _take_player(data: Variant) -> void:
	if data is Dictionary and not (data as Dictionary).is_empty():
		player = data
		config.store_session(token, token_expires_at, get_player_id(), get_player_name())


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

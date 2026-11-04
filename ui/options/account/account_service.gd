class_name AccountService
extends RefCounted
## What the account panel does (KF6, D-188, D-224; API KF5/KF8): the account's state on this device
## (no account, guest, secured, signed out), its logins (GET /me/identities, separate per provider),
## signing in and securing the account in the browser (WebLoginFlow) or with username and password,
## keeping this device on the account, merging, the deletion code and deleting the account, and the
## cloud worlds with their backups and archive (CloudSave). Every call goes through the
## OnlineSession and only changes the state here; the panel listens to changed. Nothing logs in by
## itself: refresh() only reuses a session this device already has (D-224), creating a guest account
## happens only when the player secures the account.
## After every sign-in this device is put on the account (POST /me/logins with the device id), so
## it signs in again by itself when the 30-day session ends. Is the device's own guest account full
## of progress too, merge_offer holds both accounts until the player decides (D-122); without the
## device the session is LOGIN_ACCOUNT and asks for a new sign-in when it ends.
## After a sign-in the cloud worlds are synced at once (never in a run, D-222).
## Failures never throw: the error code comes back and stays in last_error.

signal changed
## A call started with run() ended (the panel moves on from here). result may be null.
signal action_finished(action: StringName, result: ApiResult)

enum State { NONE, GUEST, SECURED, SIGNED_OUT }

## Providers a login in the browser can prove (contracts LoginMethod).
const WEB_METHODS: Array[String] = ["email", "google", "apple", "discord", "steam"]
const METHOD_PASSWORD := "password"
const PROVIDER_DEVICE := "device"
## Contracts PlayerUsername / PLAYER_PASSWORD_MIN_LENGTH (TESTWERT on the server).
const USERNAME_MIN := 3
const USERNAME_MAX := 24
const PASSWORD_MIN := 10
const PASSWORD_MAX := 128
## Local errors (texts ACCOUNT_ERR_*).
const ERROR_USERNAME := "username_invalid"
const ERROR_PASSWORD := "password_too_short"
const ERROR_IN_RUN := "in_run"
## The player stopped the web login here (no text: the panel just goes back).
const WEB_CANCELLED := "web_login_cancelled_here"
## API errors the panel names (contracts login.ts, identity.ts, world.ts).
const ACCOUNT_HAS_PROGRESS := "account_has_progress"
const LAST_IDENTITY := "last_identity"
## A sign-in whose account was created at most this long before the request is a new account: its
## profile comes from this device (TESTWERT, seconds; covers clock differences).
const NEW_ACCOUNT_MARGIN := 120

var session: OnlineSession = null
var web: WebLoginFlow = null
## IdentitySummary of the account, oldest first (empty while unknown).
var identities: Array[Dictionary] = []
var identities_loaded := false
## WorldList of GET /me/worlds ({} until loaded).
var worlds: Dictionary = {}
## World id -> WorldBackupMeta[] of GET …/backups.
var backups: Dictionary = {}
## AccountHasProgressResponse {remaining, removed} while the device merge waits for the player.
var merge_offer: Dictionary = {}
## World limit (409 world_limit_reached): {world_id, backup_id ("" = unarchive), items}.
var limit_offer: Dictionary = {}
## DeletionCodeResponse {code, expiresAt} of the last POST /me/deletion-code ({} = none).
var deletion_code: Dictionary = {}
## Calls running right now.
var running := 0
var last_error := ""
## Report of the last sync started here ({} = none).
var sync_report: Dictionary = {}


func _init(online_session: OnlineSession = null) -> void:
	session = online_session
	web = WebLoginFlow.new(session)


## Runs a call of this service in the background and reports it with action_finished (the panel
## never awaits: a call still running when it closes ends here). call: a bound method of this service.
func run(action: StringName, call: Callable) -> void:
	var result: Variant = await call.call()
	action_finished.emit(action, result as ApiResult if result is ApiResult else null)


# --- State ---

func get_state() -> State:
	if session == null:
		return State.NONE
	if session.is_signed_out():
		return State.SIGNED_OUT
	if not session.is_logged_in():
		return State.NONE
	return State.SECURED if is_secured() else State.GUEST


## A login other than a device is on the account (identities loaded).
func is_secured() -> bool:
	for identity in identities:
		if str(identity.get("provider", "")) != PROVIDER_DEVICE:
			return true
	return false


func is_busy() -> bool:
	return running > 0


## Login methods of this environment (GET /public/config loginMethods); an older API without the
## list only knows the guest login.
func login_methods() -> PackedStringArray:
	var methods: Variant = session.public_config.get("loginMethods", null) if session != null else null
	var result := PackedStringArray()
	if methods is Array:
		for method: Variant in methods:
			result.append(str(method))
	else:
		result.append(PROVIDER_DEVICE)
	return result


func has_web_login() -> bool:
	for method in login_methods():
		if WEB_METHODS.has(method):
			return true
	return false


func has_password_login() -> bool:
	return login_methods().has(METHOD_PASSWORD)


## The account's logins grouped per provider (DELETE removes a whole provider):
## [{provider, count, label (username or masked address, "" if none), this_device}].
func login_groups() -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var by_provider := {}
	var device_tail := device_id_tail()
	for identity in identities:
		var provider := str(identity.get("provider", ""))
		if not by_provider.has(provider):
			by_provider[provider] = {"provider": provider, "count": 0, "label": "", "this_device": false}
			groups.append(by_provider[provider])
		var group: Dictionary = by_provider[provider]
		group["count"] = int(group["count"]) + 1
		var label: Variant = identity.get("label", null)
		if label != null and str(label) != "" and str(group["label"]).is_empty():
			group["label"] = str(label)
		if provider == PROVIDER_DEVICE and not device_tail.is_empty() and str(identity.get("maskedId", "")).ends_with(device_tail):
			group["this_device"] = true
	return groups


## A provider can be removed while another one stays (the API answers 409 last_identity otherwise).
func can_remove(provider: String) -> bool:
	for group in login_groups():
		if group["provider"] != provider:
			return true
	return false


## The password login of the account (its username), "" if none.
func password_username() -> String:
	for identity in identities:
		if str(identity.get("provider", "")) == METHOD_PASSWORD:
			var label: Variant = identity.get("label", null)
			return str(label) if label != null else ""
	return ""


func has_password() -> bool:
	for identity in identities:
		if str(identity.get("provider", "")) == METHOD_PASSWORD:
			return true
	return false


## Last 4 characters of this installation's device id (identity maskedId "***abcd").
func device_id_tail() -> String:
	if session == null or session.config == null:
		return ""
	return session.config.get_device_id().right(4)


## This device signs in by itself (its id is on the account).
func keeps_device() -> bool:
	return session != null and session.login_kind == OnlineSession.LOGIN_DEVICE


# --- Loading ---

## Reads the environment's login methods and, if this device already has a session, the account's
## logins and cloud worlds (coroutine). Never creates an account.
func refresh() -> void:
	if session == null:
		return
	_begin()
	if session.public_config.is_empty():
		await session.refresh_public_config()
	if not session.is_logged_in() and not session.config.get_stored_session().is_empty() and not session.is_signed_out():
		await session.ensure_login()
	_end()
	if session.is_logged_in():
		await load_identities()
		await load_worlds()


func load_identities() -> ApiResult:
	_begin()
	var result := await session.call_api(func(client: ApiClient) -> ApiResult: return await client.get_identities())
	if result.ok:
		_take_identities(result.data)
	_end(result)
	return result


func load_worlds() -> ApiResult:
	var cloud := CloudSave.for_session(session)
	if cloud == null:
		return ApiResult.failure(ApiResult.UNAUTHORIZED, "Not logged in")
	_begin()
	var result := await cloud.list_worlds()
	if result.ok and result.data is Dictionary:
		worlds = result.data
	_end(result)
	return result


func load_backups(world_id: String) -> ApiResult:
	var cloud := CloudSave.for_session(session)
	if cloud == null:
		return ApiResult.failure(ApiResult.UNAUTHORIZED, "Not logged in")
	_begin()
	var result := await cloud.list_backups(world_id)
	if result.ok and result.data is Dictionary:
		var items: Variant = result.data.get("items", [])
		backups[world_id] = items if items is Array else []
	_end(result)
	return result


# --- Signing in and securing ---

## Starts a login in the browser (coroutine). link = "Konto sichern" / "Anmeldung hinzufügen": logs in
## first (the guest account of this device, created now if there is none), then adds the proven
## login to it. The panel follows web (run, cancel) and calls finish_web_login() when it completed.
func start_web_login(link: bool) -> ApiResult:
	_begin()
	if link:
		var login := await session.ensure_login()
		if not login.ok:
			_end(login)
			return login
	var result := await web.start(ApiClient.WEB_LINK if link else ApiClient.WEB_SIGN_IN)
	_end(result)
	return result


## The whole web login (coroutine): start, poll until it ends (tree for the timer), take the session.
func web_login(link: bool, tree: SceneTree) -> ApiResult:
	var started := await start_web_login(link)
	if not started.ok:
		return started
	await web.run(tree)
	if web.status == WebLoginFlow.Status.COMPLETED:
		return await finish_web_login()
	if web.status == WebLoginFlow.Status.CANCELLED:
		return ApiResult.failure(WEB_CANCELLED)
	return ApiResult.failure(web.error if web.status == WebLoginFlow.Status.FAILED else WebLoginFlow.POLL_EXPIRED)


## Takes the session of a completed web login over (coroutine): sign_in = the account behind the
## login (new on this device, then this device is put on it); link = the own account (or the one it
## was merged into) with a fresh session.
func finish_web_login() -> ApiResult:
	if web.status != WebLoginFlow.Status.COMPLETED:
		return ApiResult.failure(ApiResult.BAD_RESPONSE, "Web login not completed")
	var body := web.completion
	var auth: Variant = body.get("auth", {})
	_begin()
	var result: ApiResult
	if web.intent == ApiClient.WEB_LINK:
		var changed_account := _other_account(auth)
		result = await session.adopt_auth(auth, session.login_kind, OnlineSession.PROFILE_SERVER if changed_account else OnlineSession.PROFILE_SYNC)
	else:
		result = await _sign_in(auth, web.started_at)
	_end(result)
	if result.ok:
		await after_sign_in()
	return result


## Username and password (coroutine): checks them here first, then POST /auth/password.
func sign_in_with_password(username: String, password: String) -> ApiResult:
	var name_text := normalize_username(username)
	if password.is_empty() or name_text.is_empty():
		return _local_error(ERROR_USERNAME if name_text.is_empty() else ERROR_PASSWORD)
	_begin()
	var started := int(Time.get_unix_time_from_system())
	var answer := await session.api.login_password(name_text, password)
	var result := answer
	if answer.ok:
		result = await _sign_in(answer.data, started)
	_end(result)
	if result.ok:
		await after_sign_in()
	return result


## Adds username and password to the own account or changes them (coroutine). Without a session the
## device's guest account is used (created now if needed): "Konto sichern" with a password.
## password "" keeps the old one (only when the account has a password already).
func save_password_login(username: String, password: String) -> ApiResult:
	var name_text := normalize_username(username)
	if not is_valid_username(name_text):
		return _local_error(ERROR_USERNAME)
	if password.is_empty() and not has_password():
		return _local_error(ERROR_PASSWORD)
	if not password.is_empty() and (password.length() < PASSWORD_MIN or password.length() > PASSWORD_MAX):
		return _local_error(ERROR_PASSWORD)
	_begin()
	var send_name := "" if name_text == password_username() and not password.is_empty() else name_text
	var result := await session.call_api(func(client: ApiClient) -> ApiResult: return await client.set_password_login(send_name, password))
	if result.ok:
		_take_identities(result.data)
	_end(result)
	if result.ok:
		await after_sign_in()
	return result


## Puts this device on the account (coroutine, POST /me/logins). confirm: the player agreed to merge
## the device's guest account (merge_offer).
func keep_device(confirm := false) -> ApiResult:
	_begin()
	var device_id := session.config.get_device_id()
	var result := await session.call_api(func(client: ApiClient) -> ApiResult: return await client.add_device_login(device_id, confirm))
	if result.ok:
		merge_offer = {}
		var other := _other_account(result.data)
		var adopted := await session.adopt_auth(result.data, OnlineSession.LOGIN_DEVICE, OnlineSession.PROFILE_SERVER if other else OnlineSession.PROFILE_SYNC)
		if adopted.ok and result.data is Dictionary and result.data.get("identities", null) is Array:
			_take_identities({"items": result.data["identities"]})
		_end(adopted)
		return adopted
	if result.error == ACCOUNT_HAS_PROGRESS and result.data is Dictionary:
		merge_offer = result.data
	_end(result)
	return result


## "Nicht jetzt": the device's guest account stays apart, this session asks for a new sign-in when it ends.
func decline_merge() -> void:
	merge_offer = {}
	session.set_login_kind(OnlineSession.LOGIN_ACCOUNT)
	changed.emit()


## After a sign-in or securing (coroutine): the logins, a sync of the worlds (not in a run) and the
## cloud list.
func after_sign_in() -> void:
	await load_identities()
	await sync_worlds()
	await load_worlds()


## Syncs the worlds now (coroutine); nothing in a run or while another sync runs.
func sync_worlds() -> Dictionary:
	var cloud := CloudSave.for_session(session)
	if cloud == null or RunManager.is_run_active() or not CloudSave.auto_sync_enabled or CloudSave.is_running():
		return {}
	_begin()
	sync_report = await cloud.sync_all()
	_end()
	return sync_report


## Removes all logins of a provider (coroutine). Removing the devices makes this a LOGIN_ACCOUNT
## session (it asks for a new sign-in when it ends).
func remove_login(provider: String) -> ApiResult:
	_begin()
	var result := await session.call_api(func(client: ApiClient) -> ApiResult: return await client.remove_identity(provider))
	if result.ok:
		_take_identities(result.data)
		if provider == PROVIDER_DEVICE:
			session.set_login_kind(OnlineSession.LOGIN_ACCOUNT)
	_end(result)
	return result


## "Als Gast spielen" after a signed-out account: the next online use logs in with this device.
func play_as_guest() -> void:
	session.forget_account()
	identities = []
	identities_loaded = false
	worlds = {}
	changed.emit()


# --- Deleting the account ---

func create_deletion_code() -> ApiResult:
	_begin()
	var result := await session.call_api(func(client: ApiClient) -> ApiResult: return await client.create_deletion_code())
	if result.ok and result.data is Dictionary:
		deletion_code = result.data
	_end(result)
	return result


## Deletes the account now (coroutine, DELETE /me). The worlds on this device stay; the session is
## gone and the next online use starts a new guest account.
func delete_account() -> ApiResult:
	_begin()
	var result := await session.call_api(func(client: ApiClient) -> ApiResult: return await client.delete_account())
	if result.ok:
		session.forget_account()
		identities = []
		identities_loaded = false
		worlds = {}
		backups = {}
		deletion_code = {}
	_end(result)
	return result


## The deletion page of the website (P-026).
func deletion_page() -> String:
	return session.config.get_web_url().trim_suffix("/") + "/delete-account"


# --- Backups and archive ---

## Restores a backup (coroutine): first syncs (changes made here go up and stay as a backup), then the
## backup becomes the world's state and comes to this device. archive_world_id answers limit_offer.
func restore_backup(world_id: String, backup_id: String, archive_world_id := "") -> ApiResult:
	return await _restore(world_id, backup_id, archive_world_id)


## Brings an archived world back (coroutine), same rules as restore_backup().
func unarchive_world(world_id: String, archive_world_id := "") -> ApiResult:
	return await _restore(world_id, "", archive_world_id)


func _restore(world_id: String, backup_id: String, archive_world_id: String) -> ApiResult:
	if RunManager.is_run_active():
		return _local_error(ERROR_IN_RUN)
	var cloud := CloudSave.for_session(session)
	if cloud == null:
		return _local_error(ApiResult.UNAUTHORIZED)
	await sync_worlds()
	_begin()
	limit_offer = {}
	var result: ApiResult
	if backup_id.is_empty():
		result = await cloud.unarchive_world(world_id, archive_world_id)
	else:
		result = await cloud.restore_backup(world_id, backup_id, archive_world_id)
	if not result.ok and result.error == CloudSave.LIMIT_REACHED and result.data is Dictionary:
		limit_offer = {"world_id": world_id, "backup_id": backup_id, "items": result.data.get("items", [])}
	_end(result)
	if result.ok:
		backups.erase(world_id)
		await load_worlds()
	return result


# --- Checks ---

## Lower case and trimmed, like the API (contracts PlayerUsername).
static func normalize_username(text: String) -> String:
	return text.strip_edges().to_lower()


static func is_valid_username(text: String) -> bool:
	if text.length() < USERNAME_MIN or text.length() > USERNAME_MAX:
		return false
	var regex := RegEx.create_from_string("^[a-z0-9][a-z0-9._-]*$")
	return regex.search(text) != null


# --- Helpers ---

## A sign-in (coroutine): the account behind body (AuthResponse) becomes this device's; an account
## that is new (created after started) gets this device's profile, an existing one keeps its own.
## Then this device is put on it (keep_device).
func _sign_in(body: Variant, started: int) -> ApiResult:
	var self_data: Variant = body.get("player", {}) if body is Dictionary else {}
	var created := OnlineConfig.parse_iso_time(self_data.get("createdAt", null)) if self_data is Dictionary else 0
	var is_new := created > 0 and created >= started - NEW_ACCOUNT_MARGIN
	var same := self_data is Dictionary and str(self_data.get("id", "")) == session.get_player_id()
	var rule := OnlineSession.PROFILE_SYNC if is_new or same else OnlineSession.PROFILE_SERVER
	var result := await session.adopt_auth(body, OnlineSession.LOGIN_ACCOUNT, rule)
	if not result.ok:
		return result
	var kept := await keep_device()
	if not kept.ok and kept.error != ACCOUNT_HAS_PROGRESS:
		push_warning("AccountService: this device was not put on the account (%s); it asks again when the session ends." % kept.error)
	return result


## The account of an AuthResponse is another one than the session's.
func _other_account(body: Variant) -> bool:
	if not (body is Dictionary) or not (body.get("player", null) is Dictionary):
		return false
	return str(body["player"].get("id", "")) != session.get_player_id()


func _take_identities(data: Variant) -> void:
	identities = []
	var items: Variant = data.get("items", []) if data is Dictionary else []
	if items is Array:
		for item: Variant in items:
			if item is Dictionary:
				identities.append(item)
	identities_loaded = true


func _local_error(code: String) -> ApiResult:
	last_error = code
	changed.emit()
	return ApiResult.failure(code)


func _begin() -> void:
	running += 1
	changed.emit()


func _end(result: ApiResult = null) -> void:
	running = maxi(0, running - 1)
	if result != null:
		last_error = "" if result.ok else result.error
	changed.emit()

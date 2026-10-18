class_name ApiClient
extends Node
## Small HTTP client for soulwick-api (MP1b, D-124): JSON in and out, bearer token, 5 s timeout.
## token is the Better Auth session token of the login (P-027, 30 days, Bearer on every player
## route); the relay only takes the short-lived JWT of get_relay_token().
## Every call is a coroutine returning an ApiResult (await it); nothing blocks, nothing throws, so
## the game stays playable without a server. Routes and bodies follow
## soulwick-platform/packages/contracts (player.ts, common.ts, guild.ts, run.ts). No e-mail, no
## password (D-121).

## Emitted after every finished call (status lines, logs).
signal request_finished(path: String, result: ApiResult)
## An authenticated call came back 401: the session token expired or was revoked (P-027). Only
## when the token that was sent is still the current one.
signal unauthorized(path: String)

## TESTWERT: seconds until a call gives up.
const TIMEOUT_SECONDS := 5.0
const DEV_KEY_HEADER := "x-dev-auth-key"

## Base URL without a trailing slash, e.g. http://localhost:3101.
var base_url := OnlineConfig.DEFAULT_API_URL
## Player token for authenticated routes ("" = none).
var token := ""
var dev_key := ""
var timeout := TIMEOUT_SECONDS
## Replaceable for tests (no network).
var transport: HttpTransport = HttpTransport.new()


func _ready() -> void:
	# Logins also work while a solo dialog pauses the village.
	process_mode = Node.PROCESS_MODE_ALWAYS


## POST /auth/dev: test phase login with player name and device id (DevAuthRequest). name and
## appearance (PlayerLook, {} = none) are only used when the account is created (D-152, P-034).
## data: AuthResponse {token, expiresAt, player}.
func login_dev(player_name: String, device_id: String, appearance: Dictionary = {}) -> ApiResult:
	if dev_key.is_empty():
		return _finish("/auth/dev", ApiResult.failure(ApiResult.NO_DEV_KEY, "No dev key configured"))
	var headers := PackedStringArray(["%s: %s" % [DEV_KEY_HEADER, dev_key]])
	return await request(HTTPClient.METHOD_POST, "/auth/dev", login_body(player_name, device_id, appearance), headers, false)


## POST /auth/device: guest login of this installation without a key (DeviceAuthRequest, platform
## P-028). The device id is the only secret of a guest account; it is linked to Steam or Google Play
## later with a link code. name and appearance only count when the account is created (P-034).
## data: AuthResponse {token, expiresAt, player}.
func login_device(player_name: String, device_id: String, appearance: Dictionary = {}) -> ApiResult:
	return await request(HTTPClient.METHOD_POST, "/auth/device", login_body(player_name, device_id, appearance), PackedStringArray(), false)


## Body of a login: {name?, deviceId, appearance?} (empty name or look are left out).
static func login_body(player_name: String, device_id: String, appearance: Dictionary = {}) -> Dictionary:
	var body := {"deviceId": device_id}
	if not player_name.is_empty():
		body["name"] = player_name
	if not appearance.is_empty():
		body["appearance"] = appearance
	return body


## PATCH /me {name?, appearance?} (UpdateProfileRequest, D-152): changes the account profile.
## data: PlayerSelf. Errors: 400 validation_error, 429 name_change_limited (retryAfter in the body
## and the Retry-After header; the appearance of such a request is not applied either).
func update_profile(body: Dictionary) -> ApiResult:
	return await _with_token(HTTPClient.METHOD_PATCH, "/me", body)


## GET /me with the token: PlayerSelf {id, name, steamId, createdAt, guild, guilds, appearance}.
func get_me() -> ApiResult:
	if token.is_empty():
		return _finish("/me", ApiResult.failure(ApiResult.UNAUTHORIZED, "Not logged in"))
	return await request(HTTPClient.METHOD_GET, "/me")


## GET /auth/token with the session token (P-027): short-lived player JWT for hello.token at the
## relay. data: AuthTokenResponse {token, expiresAt}. 401 unauthorized (session expired, revoked or
## an admin session), 403 banned (with reason and end).
func get_relay_token() -> ApiResult:
	if token.is_empty():
		return _finish("/auth/token", ApiResult.failure(ApiResult.UNAUTHORIZED, "Not logged in"))
	return await request(HTTPClient.METHOD_GET, "/auth/token")


## GET /public/config: {apiVersion, minGameVersion, protocolVersion, relayUrl} (P16). Older APIs
## answer 404; the caller then keeps its configured relay.
func get_public_config() -> ApiResult:
	return await request(HTTPClient.METHOD_GET, "/public/config", null, PackedStringArray(), false)


## GET /health: {status, apiVersion, db, time, minGameVersion?, protocolVersion?}.
func get_health() -> ApiResult:
	return await request(HTTPClient.METHOD_GET, "/health", null, PackedStringArray(), false)


## POST /runs with the token (CreateRunRequest of contracts/run.ts): the host reports a finished
## run (MP3, D-082). data: CreateRunResponse {id, flagged, flagReason, createdAt}.
func post_run(body: Dictionary) -> ApiResult:
	if token.is_empty():
		return _finish("/runs", ApiResult.failure(ApiResult.UNAUTHORIZED, "Not logged in"))
	return await request(HTTPClient.METHOD_POST, "/runs", body)


# --- Guilds (D-080, D-147: up to 5 guilds per player, contracts guild.ts) ---

## GET /me/guilds: MyGuildList {items: GuildSummary[] (id, name, tag, myRole, memberCount,
## maxMembers, joinedAt, treasury), maxGuilds}, oldest membership first.
func get_my_guilds() -> ApiResult:
	return await _with_token(HTTPClient.METHOD_GET, "/me/guilds")


## POST /guilds {name, tag}: founds a guild, the caller becomes founder. 201 GuildDetail.
## Errors: guild_limit_reached, guild_name_taken, guild_tag_taken, validation_error.
func create_guild(guild_name: String, tag: String) -> ApiResult:
	return await _with_token(HTTPClient.METHOD_POST, "/guilds", {"name": guild_name, "tag": tag})


## POST /guilds/join {inviteCode}: joins by invite code, 200 GuildDetail. Errors:
## invalid_invite_code, guild_full, guild_limit_reached, already_member.
func join_guild(invite_code: String) -> ApiResult:
	return await _with_token(HTTPClient.METHOD_POST, "/guilds/join", {"inviteCode": invite_code})


## GET /guilds/:id: GuildDetail (myRole, members with roles, inviteCode for founder/officer else
## null, progress with the treasury). Error not_member (also for a guild that is gone).
func get_guild(guild_id: String) -> ApiResult:
	return await _with_token(HTTPClient.METHOD_GET, guild_path(guild_id))


## POST /guilds/:id/leave: LeaveGuildResponse {guildId, disbanded, newFounderId}; not_member if not
## in it. The last member disbands the guild, a leaving founder passes the role on (P-102).
func leave_guild(guild_id: String) -> ApiResult:
	return await _with_token(HTTPClient.METHOD_POST, guild_path(guild_id, "/leave"))


## DELETE /guilds/:id/members/:playerId (founder; officers only plain members): 200 GuildDetail.
## Errors forbidden_role, member_not_found, cannot_target_self, not_member.
func remove_guild_member(guild_id: String, player_id: String) -> ApiResult:
	return await _with_token(HTTPClient.METHOD_DELETE, guild_path(guild_id, "/members/" + player_id.uri_encode()))


## PATCH /guilds/:id/members/:playerId {role: "officer" | "member"} (founder only): makes a member
## officer or back. 200 GuildDetail. Errors forbidden_role, member_not_found, cannot_target_self.
func set_guild_member_role(guild_id: String, player_id: String, role: String) -> ApiResult:
	return await _with_token(HTTPClient.METHOD_PATCH, guild_path(guild_id, "/members/" + player_id.uri_encode()), {"role": role})


## POST /guilds/:id/invite-code (founder/officer): a new invite code, the old one stops working.
## data: {inviteCode}.
func rotate_guild_invite_code(guild_id: String) -> ApiResult:
	return await _with_token(HTTPClient.METHOD_POST, guild_path(guild_id, "/invite-code"))


## GET /guilds/:id/progress: GuildProgress {treasury, forgeLevels, version}.
func get_guild_progress(guild_id: String) -> ApiResult:
	return await _with_token(HTTPClient.METHOD_GET, guild_path(guild_id, "/progress"))


## GET /guilds/:id/rooms (members only): the guild's open rooms on the relay, so members can join
## without a room code. Expected answer: {rooms: [{code, hostName, players, maxPlayers, started,
## createdAt}]}. Older APIs answer 404 (the menu then hides the list; joining by code still works).
func get_guild_rooms(guild_id: String) -> ApiResult:
	return await _with_token(HTTPClient.METHOD_GET, guild_path(guild_id, "/rooms"))


## "/guilds/<id><suffix>" with the id URL-encoded.
static func guild_path(guild_id: String, suffix := "") -> String:
	return "/guilds/%s%s" % [guild_id.uri_encode(), suffix]


## An authenticated call; without a token it fails at once (no request).
func _with_token(method: HTTPClient.Method, path: String, body: Variant = null) -> ApiResult:
	if token.is_empty():
		return _finish(path, ApiResult.failure(ApiResult.UNAUTHORIZED, "Not logged in"))
	return await request(method, path, body)


## Any call: body (Dictionary/Array or null) goes out as JSON, the token as bearer when with_token.
func request(method: HTTPClient.Method, path: String, body: Variant = null, extra_headers := PackedStringArray(), with_token := true) -> ApiResult:
	var headers := PackedStringArray(["Accept: application/json"])
	headers.append_array(extra_headers)
	var text := ""
	if body != null:
		headers.append("Content-Type: application/json")
		text = JSON.stringify(body)
	var sent_token := token if with_token else ""
	if not sent_token.is_empty():
		headers.append("Authorization: Bearer %s" % sent_token)
	var answer: Dictionary = await transport.send(self, method, base_url + path, headers, text, timeout)
	var error := str(answer.get("error", ""))
	var result: ApiResult
	if not error.is_empty():
		result = ApiResult.failure(error, "No answer from %s" % base_url)
	else:
		var response_headers: Variant = answer.get("headers", PackedStringArray())
		result = ApiResult.from_http(int(answer.get("status", 0)), str(answer.get("body", "")), PackedStringArray(response_headers) if response_headers is PackedStringArray or response_headers is Array else PackedStringArray())
	if result.status == 401 and not sent_token.is_empty() and sent_token == token:
		unauthorized.emit(path)
	return _finish(path, result)


func _finish(path: String, result: ApiResult) -> ApiResult:
	request_finished.emit(path, result)
	return result

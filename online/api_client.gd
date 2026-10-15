class_name ApiClient
extends Node
## Small HTTP client for soulwick-api (MP1b, D-124): JSON in and out, bearer token, 5 s timeout.
## token is the Better Auth session token of the login (P-027, 30 days, Bearer on every player
## route); the relay only takes the short-lived JWT of get_relay_token().
## Every call is a coroutine returning an ApiResult (await it); nothing blocks, nothing throws, so
## the game stays playable without a server. Routes and bodies follow
## soulwick-platform/packages/contracts (player.ts, common.ts). No e-mail, no password (D-121).

## Emitted after every finished call (status lines, logs).
signal request_finished(path: String, result: ApiResult)
## An authenticated call came back 401: the session token expired or was revoked (P-027). Only
## when the token that was sent is still the current one.
signal unauthorized(path: String)

## TESTWERT: seconds until a call gives up.
const TIMEOUT_SECONDS := 5.0
const DEV_KEY_HEADER := "x-dev-auth-key"

## Base URL without a trailing slash, e.g. http://localhost:8787.
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


## POST /auth/dev: test phase login with player name and device id (DevAuthRequest).
## data: AuthResponse {token, expiresAt, player}.
func login_dev(player_name: String, device_id: String) -> ApiResult:
	if dev_key.is_empty():
		return _finish("/auth/dev", ApiResult.failure(ApiResult.NO_DEV_KEY, "No dev key configured"))
	var headers := PackedStringArray(["%s: %s" % [DEV_KEY_HEADER, dev_key]])
	return await request(HTTPClient.METHOD_POST, "/auth/dev", {"name": player_name, "deviceId": device_id}, headers, false)


## POST /auth/device: guest login of this installation without a key (DeviceAuthRequest, platform
## P-028). The device id is the only secret of a guest account; it is linked to Steam or Google Play
## later with a link code. data: AuthResponse {token, expiresAt, player}.
func login_device(player_name: String, device_id: String) -> ApiResult:
	return await request(HTTPClient.METHOD_POST, "/auth/device", {"name": player_name, "deviceId": device_id}, PackedStringArray(), false)


## GET /me with the token: PlayerSelf {id, name, steamId, createdAt, guild}.
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
		result = ApiResult.from_http(int(answer.get("status", 0)), str(answer.get("body", "")))
	if result.status == 401 and not sent_token.is_empty() and sent_token == token:
		unauthorized.emit(path)
	return _finish(path, result)


func _finish(path: String, result: ApiResult) -> ApiResult:
	request_finished.emit(path, result)
	return result

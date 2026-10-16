class_name ApiResult
extends RefCounted
## Outcome of one API call (MP1b). Never thrown, always returned: the game stays playable when the
## server is down. error is a stable code: the API's own ("banned", "invalid_dev_auth_key",
## "validation_failed" …) or one of the local ones below.

## No connection (DNS, refused, TLS) or no answer at all.
const UNREACHABLE := "unreachable"
const TIMEOUT := "timeout"
## The answer was not the expected JSON.
const BAD_RESPONSE := "bad_response"
## The stored token is missing or expired (also HTTP 401 on authenticated routes).
const UNAUTHORIZED := "unauthorized"
const BANNED := "banned"
## The dev login needs a key (online.cfg dev_key or -- dev_key=…).
const NO_DEV_KEY := "no_dev_key"
## This build is older than minGameVersion of the API (OnlineVersionCheck): nothing was sent.
const UPDATE_REQUIRED := "update_required"
## Guild errors of the API (contracts guild.ts, D-147).
const GUILD_LIMIT_REACHED := "guild_limit_reached"
const GUILD_FULL := "guild_full"
const INVALID_INVITE_CODE := "invalid_invite_code"
const ALREADY_MEMBER := "already_member"
const NOT_MEMBER := "not_member"
const FORBIDDEN_ROLE := "forbidden_role"
const MEMBER_NOT_FOUND := "member_not_found"
const CANNOT_TARGET_SELF := "cannot_target_self"

var ok := false
## HTTP status, 0 without an answer.
var status := 0
## Parsed JSON body (Dictionary or Array), null if there was none.
var data: Variant = null
var error := ""
var message := ""
## Only for error == BANNED: reason and end (unix s, 0 = permanent).
var ban_reason := ""
var ban_expires_at := 0
## Only for HTTP 429 (too many requests): seconds to wait from the Retry-After header (0 = none).
var retry_after_seconds := 0


static func success(http_status: int, body: Variant) -> ApiResult:
	var result := ApiResult.new()
	result.ok = true
	result.status = http_status
	result.data = body
	return result


static func failure(code: String, text := "", http_status := 0, body: Variant = null) -> ApiResult:
	var result := ApiResult.new()
	result.ok = false
	result.error = code
	result.message = text
	result.status = http_status
	result.data = body
	return result


## Result of a finished HTTP exchange: 2xx with JSON is ok, everything else an error with the
## API's code ({"error": "...", "message": "..."}; 403 banned carries reason and end; 429 the
## seconds of its Retry-After header).
static func from_http(http_status: int, body_text: String, headers := PackedStringArray()) -> ApiResult:
	var body: Variant = null
	if not body_text.strip_edges().is_empty():
		var json := JSON.new()
		if json.parse(body_text) != OK:
			var broken := failure(BAD_RESPONSE, "Response is not JSON", http_status)
			if http_status == 429:
				broken.retry_after_seconds = parse_retry_after(headers)
			return broken
		body = json.data
	if http_status >= 200 and http_status < 300:
		return success(http_status, body)
	var code := "http_%d" % http_status
	var text := ""
	if body is Dictionary:
		code = str(body.get("error", code))
		text = str(body.get("message", ""))
	if http_status == 401 and not (body is Dictionary and body.has("error")):
		code = UNAUTHORIZED
	var result := failure(code, text, http_status, body)
	if code == BANNED and body is Dictionary:
		result.ban_reason = str(body.get("reason", ""))
		result.ban_expires_at = OnlineConfig.parse_iso_time(body.get("expiresAt", null))
	if http_status == 429:
		result.retry_after_seconds = parse_retry_after(headers)
	return result


## Seconds of a Retry-After response header (RFC 9110): delay-seconds ("120") or an HTTP date
## ("Wed, 21 Oct 2026 07:28:00 GMT", counted from now_unix, default the system clock). 0 if the
## header is missing, broken or in the past. The header name is case-insensitive.
static func parse_retry_after(headers: PackedStringArray, now_unix := -1) -> int:
	for header in headers:
		var cut := header.find(":")
		if cut < 0 or header.substr(0, cut).strip_edges().to_lower() != "retry-after":
			continue
		var value := header.substr(cut + 1).strip_edges()
		if value.is_valid_int():
			return maxi(0, value.to_int())
		var at := _parse_http_date(value)
		if at <= 0:
			return 0
		var now := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
		return maxi(0, at - now)
	return 0


## Unix seconds of an IMF-fixdate ("Wed, 21 Oct 2026 07:28:00 GMT"), 0 if it is not one.
static func _parse_http_date(text: String) -> int:
	const MONTHS := ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
	var parts := text.replace(",", " ").split(" ", false)
	if parts.size() < 5:
		return 0
	# Optional weekday first.
	if not parts[0].is_valid_int():
		parts = parts.slice(1)
	if parts.size() < 4 or not parts[0].is_valid_int() or not parts[2].is_valid_int():
		return 0
	var month := MONTHS.find(parts[1].to_lower().left(3))
	var clock := parts[3].split(":")
	if month < 0 or clock.size() != 3:
		return 0
	for piece in clock:
		if not piece.is_valid_int():
			return 0
	return int(Time.get_unix_time_from_datetime_dict({
		"year": parts[2].to_int(), "month": month + 1, "day": parts[0].to_int(),
		"hour": clock[0].to_int(), "minute": clock[1].to_int(), "second": clock[2].to_int(),
	}))


## Dictionary field of data, or fallback.
func get_field(key: String, fallback: Variant = null) -> Variant:
	return data.get(key, fallback) if data is Dictionary else fallback


func describe() -> String:
	if ok:
		return "ok (%d)" % status
	return "%s (%d) %s" % [error, status, message]

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
## API's code ({"error": "...", "message": "..."}; 403 banned carries reason and end).
static func from_http(http_status: int, body_text: String) -> ApiResult:
	var body: Variant = null
	if not body_text.strip_edges().is_empty():
		var json := JSON.new()
		if json.parse(body_text) != OK:
			return failure(BAD_RESPONSE, "Response is not JSON", http_status)
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
	return result


## Dictionary field of data, or fallback.
func get_field(key: String, fallback: Variant = null) -> Variant:
	return data.get(key, fallback) if data is Dictionary else fallback


func describe() -> String:
	if ok:
		return "ok (%d)" % status
	return "%s (%d) %s" % [error, status, message]

extends GutTest
## HTTP 429 (too many requests): ApiResult.retry_after_seconds from the Retry-After header, as
## delay-seconds or as an HTTP date; HttpTransport hands the response headers through. No network.


## Answers every request with one prepared answer (status, body, headers).
class HeaderTransport extends HttpTransport:
	var answer: Dictionary = {}

	func send(_owner: Node, _method: HTTPClient.Method, _url: String, _headers: PackedStringArray, _body: String, _timeout: float) -> Dictionary:
		return answer


var _client: ApiClient
var _transport: HeaderTransport


func before_each() -> void:
	_transport = HeaderTransport.new()
	_client = ApiClient.new()
	_client.transport = _transport
	_client.base_url = "http://api.test"
	_client.token = "session-token.c2lnbmF0dXJl"
	add_child_autofree(_client)


func test_429_carries_the_seconds_of_retry_after() -> void:
	_transport.answer = {"status": 429, "body": JSON.stringify({"error": "rate_limited", "message": "Too many requests"}), "error": "",
		"headers": PackedStringArray(["Content-Type: application/json", "Retry-After: 17"])}
	var result := await _client.get_my_guilds()
	assert_false(result.ok)
	assert_eq(result.status, 429)
	assert_eq(result.error, "rate_limited")
	assert_eq(result.retry_after_seconds, 17)


func test_without_header_or_other_status_it_is_zero() -> void:
	_transport.answer = {"status": 429, "body": "", "error": "", "headers": PackedStringArray()}
	assert_eq((await _client.get_my_guilds()).retry_after_seconds, 0, "429 without Retry-After")
	_transport.answer = {"status": 503, "body": "", "error": "", "headers": PackedStringArray(["Retry-After: 30"])}
	assert_eq((await _client.get_my_guilds()).retry_after_seconds, 0, "only 429 counts")
	# Older transports (and the test fakes) answer without headers at all.
	_transport.answer = {"status": 429, "body": "", "error": ""}
	assert_eq((await _client.get_my_guilds()).retry_after_seconds, 0)


func test_header_forms() -> void:
	assert_eq(ApiResult.parse_retry_after(PackedStringArray(["retry-after:  5 "])), 5, "name in any case, spaces")
	assert_eq(ApiResult.parse_retry_after(PackedStringArray(["Retry-After: -3"])), 0, "never negative")
	assert_eq(ApiResult.parse_retry_after(PackedStringArray(["Retry-After: soon"])), 0, "broken value")
	var now := int(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 10, "day": 21, "hour": 7, "minute": 27, "second": 0}))
	assert_eq(ApiResult.parse_retry_after(PackedStringArray(["Retry-After: Wed, 21 Oct 2026 07:28:00 GMT"]), now), 60, "HTTP date")
	assert_eq(ApiResult.parse_retry_after(PackedStringArray(["Retry-After: Wed, 21 Oct 2026 07:20:00 GMT"]), now), 0, "a date in the past")

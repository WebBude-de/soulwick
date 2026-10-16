class_name HttpTransport
extends RefCounted
## The HTTP layer of ApiClient (MP1b): one HTTPRequest node per call under the client node, with a
## timeout. Tests replace it with a fake that answers without a network (test_api_client.gd).


## Sends one request and waits for the answer (coroutine). Returns {status, body, error, headers}:
## error is "" or ApiResult.UNREACHABLE / ApiResult.TIMEOUT; status is 0 without an answer;
## headers are the response headers ("Name: value", e.g. Retry-After of a 429).
func send(owner: Node, method: HTTPClient.Method, url: String, headers: PackedStringArray, body: String, timeout: float) -> Dictionary:
	if owner == null or not owner.is_inside_tree():
		return {"status": 0, "body": "", "error": ApiResult.UNREACHABLE}
	var tree := owner.get_tree()
	var request := HTTPRequest.new()
	request.timeout = timeout
	request.use_threads = false
	owner.add_child(request)
	var error := request.request(url, headers, method, body)
	if error != OK:
		request.queue_free()
		return {"status": 0, "body": "", "error": ApiResult.UNREACHABLE}
	var answer: Array = await request.request_completed
	request.queue_free()
	# Resume outside the signal emission, so callers may free the client right away.
	await tree.process_frame
	var result: int = answer[0]
	var status: int = answer[1]
	var response_headers: PackedStringArray = answer[2]
	var raw: PackedByteArray = answer[3]
	if result == HTTPRequest.RESULT_TIMEOUT:
		return {"status": 0, "body": "", "error": ApiResult.TIMEOUT, "headers": PackedStringArray()}
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"status": status, "body": "", "error": ApiResult.UNREACHABLE, "headers": response_headers}
	return {"status": status, "body": raw.get_string_from_utf8(), "error": "", "headers": response_headers}

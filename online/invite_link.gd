class_name InviteLink
extends RefCounted
## Invite by link (MP2b, D-176, D-190): "https://game.playsoulwick.com/?room=ABC123" opens the browser
## version straight in the host's lobby. The link carries the room code and nothing else (no name,
## no account). Codes follow the relay's rules (RelayProtocol: 6 characters of the unambiguous
## alphabet, D-121/CP3); anything else is dropped, never guessed.
##
## Building: the game domain of the build environment (OnlineConfig): development →
## game-dev.playsoulwick.com, production → game.playsoulwick.com; local (editor, local platform) →
## the page itself in the browser, else the local web container (WEB_BUILD.md §7, port 3110).
## Reading: the browser shell (deploy/web/shell.html) takes ?room= from the address, checks it and
## starts the engine with "-- room=ABC123"; native builds take the same argument (tests, tools; a
## clicked link does not reach them yet, OFFEN in D-190). In the browser the address itself is the
## fallback when another shell started the game. The main menu takes the code once
## (take_arrival) and joins the room through LobbyClient like a typed code.
## Sharing: copy() puts the link on the clipboard everywhere (the browser asks
## navigator.clipboard); on phones in the browser share() opens the system's share sheet (Web
## Share API) when the browser has one (can_share).

## Name of the query parameter and of the command line argument.
const PARAM := "room"
## Game page per server environment (D-148, D-157; the website's own domain is OnlineConfig "web").
const GAME_URLS := {
	OnlineConfig.ENV_DEVELOPMENT: "https://game-dev.playsoulwick.com",
	OnlineConfig.ENV_PRODUCTION: "https://game.playsoulwick.com",
}
## The web container of the local platform test (docs/WEB_BUILD.md, docker run -p 3110:80).
const LOCAL_GAME_URL := "http://localhost:3110"

## Tests: 1 = can share, 0 = cannot, -1 = ask the browser.
static var share_override := -1
## Tests: the code of this start instead of the command line ("" = read it); see set_arrival.
static var _arrival := ""
static var _arrival_read := false


## The link to a room for this build's environment ("" for an invalid code).
static func for_room(code: String, environment := "") -> String:
	var env := environment if not environment.is_empty() else OnlineConfig.build_environment()
	return build(code, base_url(env, _page_origin()))


## Game page of an environment. page_origin: "https://host[:port]" of the running browser page ("" on
## native builds), used only for local and unknown environments (the page then links to itself).
static func base_url(environment: String, page_origin := "") -> String:
	if GAME_URLS.has(environment):
		return str(GAME_URLS[environment])
	if page_origin.begins_with("http://") or page_origin.begins_with("https://"):
		return page_origin.trim_suffix("/")
	return LOCAL_GAME_URL


## "<base>/?room=ABC123"; the code is normalised first ("" if it is no valid room code).
static func build(code: String, base: String) -> String:
	var normalized := RelayProtocol.normalize_code(code)
	if not RelayProtocol.is_valid_code(normalized) or normalized.length() != code.strip_edges().length():
		return ""
	return "%s/?%s=%s" % [base.strip_edges().trim_suffix("/"), PARAM, normalized]


## The room code in a link, a query ("?room=abc123&x=1") or a bare code; "" if there is none or it
## is not a valid room code (wrong length, characters outside the alphabet). Lower case is fine.
static func parse(text: String) -> String:
	var value := text.strip_edges()
	if value.is_empty():
		return ""
	var query_at := value.find("?")
	if query_at >= 0 or value.contains("="):
		var query := value.substr(query_at + 1) if query_at >= 0 else value
		var hash_at := query.find("#")
		if hash_at >= 0:
			query = query.left(hash_at)
		for pair in query.split("&", false):
			var cut := pair.find("=")
			var key := pair.left(cut) if cut >= 0 else pair
			if key.uri_decode() == PARAM:
				return _strict_code(pair.substr(cut + 1).uri_decode() if cut >= 0 else "")
		return ""
	if value.contains("/"):
		return ""
	return _strict_code(value)


## The code of "room=ABC123" among the user arguments ("" if none or invalid).
static func code_from_args(args: PackedStringArray) -> String:
	var parsed := OnlineConfig.parse_args(args)
	return parse(str(parsed.get(PARAM, ""))) if parsed.has(PARAM) else ""


## The room this game start was invited to ("" if none): the shell's argument, in the browser the
## address as a fallback. Read once; take_arrival() hands it out once.
static func peek_arrival() -> String:
	if not _arrival_read:
		_arrival_read = true
		_arrival = code_from_args(OS.get_cmdline_user_args())
		if _arrival.is_empty():
			_arrival = parse(_page_search())
	return _arrival


## Takes the invitation of this start (main menu, once): later visits of the menu do not join again.
static func take_arrival() -> String:
	var code := peek_arrival()
	_arrival = ""
	return code


## Tests: pretend this start came with code ("" = none).
static func set_arrival(code: String) -> void:
	_arrival_read = true
	_arrival = parse(code)


## Puts the link on the clipboard (every platform). false without a link.
static func copy(url: String) -> bool:
	if url.is_empty():
		return false
	DisplayServer.clipboard_set(url)
	return true


## Phones in the browser with the Web Share API: share() opens the share sheet.
static func can_share() -> bool:
	if share_override >= 0:
		return share_override == 1
	if not OS.has_feature("web") or not Engine.has_singleton(&"JavaScriptBridge"):
		return false
	if not (OS.has_feature("web_android") or OS.has_feature("web_ios")):
		return false
	return bool(JavaScriptBridge.eval("typeof navigator.share === 'function'", true))


## Opens the browser's share sheet with text and link (the press that called this is the user
## gesture the browser asks for). Cancelling it is fine. false if no sheet could be opened: then
## the link is copied instead.
static func share(url: String, text: String, title := "Soulwick") -> bool:
	if url.is_empty():
		return false
	if share_override >= 0 or not can_share():
		copy(url)
		return false
	var data := JSON.stringify({"title": title, "text": text, "url": url})
	var opened: Variant = JavaScriptBridge.eval(
			"(function(d){try{navigator.share(d).catch(function(){});return true;}catch(e){return false;}})(%s)" % data, true)
	if not bool(opened):
		copy(url)
		return false
	return true


## Translation key of the one-sentence explanation of a failed link join (INVITE_ERR_*), falling back
## to the lobby's sentence (LobbyClient.error_text) for codes without an own one.
static func error_text(code: String) -> String:
	var key := StringName("INVITE_ERR_%s" % code.to_upper())
	var text := Loc.t(key)
	return text if text != String(key) else LobbyClient.error_text(code)


## Is another try worth it (the server or the connection, not the room itself)?
static func can_retry(code: String) -> bool:
	return code in [LobbyClient.ERROR_API_UNREACHABLE, LobbyClient.ERROR_RELAY_UNREACHABLE, LobbyClient.ERROR_TIMEOUT,
			LobbyClient.ERROR_LOGIN, LobbyClient.ERROR_UNAUTHORIZED, LobbyClient.ERROR_BUSY, "room_full",
			"api_unavailable", "internal", "rate_limited", "hello_required", "already_in_room"]


## Exactly a room code (no trimming of extra characters: "ABC1234" or "AB-C12" are not codes).
static func _strict_code(raw: String) -> String:
	var value := raw.strip_edges().to_upper()
	return value if RelayProtocol.is_valid_code(value) else ""


## "https://host[:port]" of the browser page, "" on native builds.
static func _page_origin() -> String:
	if not OS.has_feature("web") or not Engine.has_singleton(&"JavaScriptBridge"):
		return ""
	return str(JavaScriptBridge.eval("String(window.location.origin || '')", true))


## "?room=…" of the browser page, "" on native builds.
static func _page_search() -> String:
	if not OS.has_feature("web") or not Engine.has_singleton(&"JavaScriptBridge"):
		return ""
	return str(JavaScriptBridge.eval("String(window.location.search || '')", true))

extends GutTest
## MP2b (D-190): the invite link itself (InviteLink) and the shell that hands its code to the game.
## Building per environment, reading links, queries, bare codes and command line arguments, the
## rules of the room codes (6 characters, no 0/O, 1/I/L) and the error sentences of a link join.
## No network, no save, no online.cfg.


func after_each() -> void:
	InviteLink.share_override = -1
	InviteLink.set_arrival("")


func test_link_per_environment() -> void:
	assert_eq(InviteLink.base_url(OnlineConfig.ENV_DEVELOPMENT), "https://game-dev.playsoulwick.com")
	assert_eq(InviteLink.base_url(OnlineConfig.ENV_PRODUCTION), "https://game.playsoulwick.com")
	assert_eq(InviteLink.base_url(OnlineConfig.ENV_PRODUCTION, "http://localhost:3110"), "https://game.playsoulwick.com",
			"a known environment always links to its game domain")
	assert_eq(InviteLink.base_url(OnlineConfig.ENV_LOCAL), InviteLink.LOCAL_GAME_URL, "local native: the local web container")
	assert_eq(InviteLink.base_url(OnlineConfig.ENV_LOCAL, "http://localhost:8060/"), "http://localhost:8060", "local in the browser: the page itself")
	assert_eq(InviteLink.base_url(OnlineConfig.ENV_LOCAL, "file://"), InviteLink.LOCAL_GAME_URL, "only http(s) pages")
	assert_eq(InviteLink.for_room("ABC234", OnlineConfig.ENV_DEVELOPMENT), "https://game-dev.playsoulwick.com/?room=ABC234")
	assert_eq(InviteLink.for_room("ABC234", OnlineConfig.ENV_PRODUCTION), "https://game.playsoulwick.com/?room=ABC234")


func test_build_takes_only_room_codes() -> void:
	var base := "https://game.playsoulwick.com"
	assert_eq(InviteLink.build("abc234", base), base + "/?room=ABC234", "lower case is normalised")
	assert_eq(InviteLink.build(" ABC234 ", base + "/"), base + "/?room=ABC234", "spaces around and a slash at the end")
	for bad in ["", "ABC23", "ABC2345", "ABC0O1", "ABCI23", "AB C23", "ABC-23"]:
		assert_eq(InviteLink.build(bad, base), "", "no link for %s" % bad)


func test_parse_links_queries_and_codes() -> void:
	assert_eq(InviteLink.parse("https://game.playsoulwick.com/?room=ABC234"), "ABC234")
	assert_eq(InviteLink.parse("https://game-dev.playsoulwick.com/?install&room=abc234#top"), "ABC234", "other parameters and a hash")
	assert_eq(InviteLink.parse("?room=XYZ789"), "XYZ789", "the address query of the browser")
	assert_eq(InviteLink.parse("room=XYZ789"), "XYZ789")
	assert_eq(InviteLink.parse("  xyz789 "), "XYZ789", "a bare code")
	assert_eq(InviteLink.parse("https://game.playsoulwick.com/?room=AB%2DC23"), "", "decoded, still not a code")
	assert_eq(InviteLink.parse("https://game.playsoulwick.com/?room=ABC2"), "", "too short")
	assert_eq(InviteLink.parse("https://game.playsoulwick.com/?room=ABC2345"), "", "too long, never cut")
	assert_eq(InviteLink.parse("https://game.playsoulwick.com/?room=ABC10O"), "", "0, O, 1 are not in the alphabet")
	assert_eq(InviteLink.parse("https://game.playsoulwick.com/?rooms=ABC234"), "", "another parameter")
	assert_eq(InviteLink.parse("https://game.playsoulwick.com/ABC234"), "", "the code must be the parameter")
	assert_eq(InviteLink.parse("?install"), "")
	assert_eq(InviteLink.parse(""), "")


func test_built_links_read_back() -> void:
	for code in ["ABC234", "ZZZZZZ", "222222", "HJKMNP"]:
		for env: String in OnlineConfig.ENVIRONMENTS:
			assert_eq(InviteLink.parse(InviteLink.for_room(code, env)), code, "%s in %s" % [code, env])


func test_code_from_command_line() -> void:
	assert_eq(InviteLink.code_from_args(PackedStringArray(["room=abc234"])), "ABC234", "the shell's argument")
	assert_eq(InviteLink.code_from_args(PackedStringArray(["--room=ABC234", "offline"])), "ABC234")
	assert_eq(InviteLink.code_from_args(PackedStringArray(["room=https://game.playsoulwick.com/?room=ABC234"])), "ABC234", "a whole link")
	assert_eq(InviteLink.code_from_args(PackedStringArray(["room=ABC0"])), "", "invalid: dropped")
	assert_eq(InviteLink.code_from_args(PackedStringArray(["instance=2"])), "")


func test_arrival_is_taken_once() -> void:
	InviteLink.set_arrival("abc234")
	assert_eq(InviteLink.peek_arrival(), "ABC234")
	assert_eq(InviteLink.take_arrival(), "ABC234")
	assert_eq(InviteLink.take_arrival(), "", "a later visit of the main menu does not join again")
	InviteLink.set_arrival("ABC0O1")
	assert_eq(InviteLink.take_arrival(), "", "an invalid code never arrives")


func test_sharing_falls_back_to_copying() -> void:
	assert_false(InviteLink.can_share(), "headless: no share sheet")
	InviteLink.share_override = 0
	assert_false(InviteLink.share("https://game.playsoulwick.com/?room=ABC234", "Raum ABC234"), "no sheet: copied")
	if DisplayServer.get_name() != "headless":
		assert_eq(DisplayServer.clipboard_get(), "https://game.playsoulwick.com/?room=ABC234")
	assert_false(InviteLink.copy(""), "nothing to copy")
	assert_false(InviteLink.share("", "x"))
	InviteLink.share_override = 1
	assert_true(InviteLink.can_share(), "phones in the browser")


func test_error_sentences_and_ways_out() -> void:
	var old_locale := TranslationServer.get_locale()
	Loc.apply(&"de")
	assert_eq(InviteLink.error_text("room_not_found"), "Diese Einladung ist abgelaufen: Der Raum ist schon geschlossen.")
	assert_string_contains(InviteLink.error_text("room_full"), "voll")
	assert_string_contains(InviteLink.error_text("version_mismatch"), "Spielversionen")
	assert_string_contains(InviteLink.error_text(LobbyClient.ERROR_API_UNREACHABLE), "nicht erreichbar")
	assert_string_contains(InviteLink.error_text(LobbyClient.ERROR_RELAY_UNREACHABLE), "nicht erreichbar")
	assert_eq(InviteLink.error_text("banned"), LobbyClient.error_text("banned"), "without an own sentence the lobby's")
	for code in ["room_not_found", "room_full", "version_mismatch", "update_required", "api_unreachable",
			"relay_unreachable", "relay_timeout", "kicked", "not_guild_member", "invalid_code"]:
		for locale in [&"de", &"en"]:
			assert_true(Loc.has_key(StringName("INVITE_ERR_%s" % code.to_upper()), locale), "%s in %s" % [code, locale])
	assert_true(InviteLink.can_retry(LobbyClient.ERROR_API_UNREACHABLE), "server gone: try again")
	assert_true(InviteLink.can_retry("room_full"), "somebody may leave")
	assert_false(InviteLink.can_retry("room_not_found"), "an expired room does not come back")
	assert_false(InviteLink.can_retry("kicked"))
	assert_false(InviteLink.can_retry("version_mismatch"), "another try does not change the version")
	TranslationServer.set_locale(old_locale)


func test_shell_hands_only_valid_codes_to_the_game() -> void:
	var shell := FileAccess.get_file_as_string("res://deploy/web/shell.html")
	assert_false(shell.is_empty(), "deploy/web/shell.html readable")
	assert_string_contains(shell, "/^[ABCDEFGHJKMNPQRSTUVWXYZ2-9]{6}$/", "the alphabet and length of the room codes")
	assert_true(shell.contains(".get('room')"), "reads ?room=")
	assert_true(shell.contains("args.push(`room=${inviteRoom}`)"), "hands it over as -- room=CODE")
	assert_true(shell.contains("engine.start({ args: gameArgs() })"), "the engine starts with it")
	var alphabet := RelayProtocol.ROOM_CODE_ALPHABET
	var pattern := "ABCDEFGHJKMNPQRSTUVWXYZ2-9"
	assert_eq(pattern.left(23), alphabet.left(23), "letters as in the relay protocol")
	assert_eq(alphabet.right(8), "23456789", "digits 2-9")

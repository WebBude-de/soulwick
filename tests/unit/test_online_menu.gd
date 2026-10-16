extends GutTest
## D-147: online menu with quick game and guilds. ApiClient guild routes against a fake HTTP layer
## (contracts guild.ts, API 1.1.0), GuildDirectory (list, detail, found, join, leave, remove, 401
## once more), the OnlineMenu views (no guild: two big buttons; list; guild with roles; confirm;
## offline), the main menu's room wish, the guild run mode and its run report. No network, the real
## save and online.cfg are never touched.

const TEST_PATH := "user://test_online_menu_online.cfg"
const SAVE_PATH := "user://test_online_menu_save.cfg"
const TOKEN := "session-token.c2lnbmF0dXJl"
const OWN_ID := "6f1c3a52-6a0e-4a3b-9a55-1c2d3e4f5a6b"
const OTHER_ID := "7a2d4b63-7b1f-4c4c-8b66-2d3e4f5a6b7c"
const OFFICER_ID := "8b3e5c74-8c2a-4d5d-9c77-3e4f5a6b7c8d"
const GUILD_ID := "11111111-2222-4333-8444-555555555555"
const GUILD_2_ID := "99999999-2222-4333-8444-555555555555"
const PLAYER := {"id": OWN_ID, "name": "Kerze", "steamId": null, "createdAt": "2026-10-14T10:00:00.000Z", "guild": null, "guilds": []}


## Answers from a queue keyed by "METHOD path"; records every request (as in test_api_client.gd).
class FakeTransport extends HttpTransport:
	var answers: Dictionary = {}
	var requests: Array[Dictionary] = []

	func send(_owner: Node, method: HTTPClient.Method, url: String, headers: PackedStringArray, body: String, timeout: float) -> Dictionary:
		var path := url.substr(url.find("/", 8))
		var key := "%s %s" % [["GET", "HEAD", "POST", "PUT", "DELETE", "OPTIONS", "TRACE", "CONNECT", "PATCH"][method], path]
		requests.append({"key": key, "url": url, "headers": headers, "body": body, "timeout": timeout})
		var queue: Array = answers.get(key, [])
		if queue.is_empty():
			return {"status": 0, "body": "", "error": ApiResult.UNREACHABLE}
		return queue.pop_front()

	func answer(key: String, status: int, body: Variant, error := "") -> void:
		if not answers.has(key):
			answers[key] = []
		answers[key].append({"status": status, "body": JSON.stringify(body) if body != null else "", "error": error})

	func keys() -> Array[String]:
		var result: Array[String] = []
		for request in requests:
			result.append(request.key)
		return result


var _fake: FakeTransport
var _client: ApiClient
var _session: OnlineSession
var _old_locale: String
var _old_save_path: String


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	Loc.apply(&"de")
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = SAVE_PATH
	SaveManager.load_game()


func before_each() -> void:
	OnlineVersionCheck.reset()
	OnlineMenu.remembered_view = OnlineMenu.View.QUICK
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	_fake = FakeTransport.new()
	_client = ApiClient.new()
	_client.transport = _fake
	_client.base_url = "http://api.test"
	add_child_autofree(_client)
	var config := OnlineConfig.new()
	config.path = TEST_PATH
	config.settings_path = TEST_PATH
	config.load_from({"api": "http://api.test"})
	_session = OnlineSession.new(config)
	_session.api = _client
	add_child_autofree(_session)
	# Logged in already: no login requests in the tests below.
	_session.token = TOKEN
	_session.token_expires_at = 4_000_000_000
	_session.player = PLAYER
	_session.state = OnlineSession.State.ONLINE
	_client.token = TOKEN


func after_each() -> void:
	LobbyClient.take_launch()
	OnlineMenu.remembered_view = OnlineMenu.View.QUICK
	GameManager.clear_pause_reasons()


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()
	OnlineVersionCheck.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


# --- Fixtures (contracts guild.ts) ---

func _guild_summary(id: String, guild_name: String, tag: String, role: String, count := 3) -> Dictionary:
	return {"id": id, "name": guild_name, "tag": tag, "myRole": role, "memberCount": count, "maxMembers": 30, "joinedAt": "2026-10-15T10:00:00.000Z", "treasury": 120}


func _guild_detail(role: String, invite: Variant = "ABCD2345") -> Dictionary:
	return {
		"id": GUILD_ID, "name": "Lichtwacht", "tag": "LW", "inviteCode": invite, "founderId": OWN_ID if role == "founder" else OTHER_ID,
		"createdAt": "2026-10-15T10:00:00.000Z", "maxMembers": 30, "myRole": role,
		"members": [
			{"playerId": OWN_ID if role == "founder" else OTHER_ID, "name": "Kerze" if role == "founder" else "Docht", "role": "founder", "joinedAt": "2026-10-15T10:00:00.000Z"},
			{"playerId": OFFICER_ID, "name": "Flamme", "role": "officer", "joinedAt": "2026-10-15T10:01:00.000Z"},
			{"playerId": OTHER_ID if role == "founder" else OWN_ID, "name": "Docht" if role == "founder" else "Kerze", "role": "member", "joinedAt": "2026-10-15T10:02:00.000Z"},
		],
		"progress": {"treasury": 240, "forgeLevels": {}, "version": 3},
	}


func _open_menu(lobby: LobbyClient = null) -> OnlineMenu:
	var menu := OnlineMenu.create(lobby, _session)
	add_child_autofree(menu)
	return menu


func _node(node: Node, node_name: String) -> Node:
	return node.find_child(node_name, true, false)


func _all_texts(node: Node) -> String:
	var parts: PackedStringArray = []
	for label: Label in node.find_children("*", "Label", true, false):
		parts.append(label.text)
	for button: Button in node.find_children("*", "Button", true, false):
		parts.append(button.text)
	return " | ".join(parts)


# --- ApiClient ---

func test_guild_routes_follow_the_contract() -> void:
	_fake.answer("GET /me/guilds", 200, {"items": [], "maxGuilds": 5})
	_fake.answer("POST /guilds", 201, _guild_detail("founder"))
	_fake.answer("POST /guilds/join", 200, _guild_detail("member", null))
	_fake.answer("GET /guilds/%s" % GUILD_ID, 200, _guild_detail("founder"))
	_fake.answer("POST /guilds/%s/leave" % GUILD_ID, 200, {"guildId": GUILD_ID, "disbanded": false, "newFounderId": null})
	_fake.answer("DELETE /guilds/%s/members/%s" % [GUILD_ID, OTHER_ID], 200, _guild_detail("founder"))
	_fake.answer("POST /guilds/%s/invite-code" % GUILD_ID, 200, {"inviteCode": "NEWC0DE2"})
	_fake.answer("GET /guilds/%s/progress" % GUILD_ID, 200, {"treasury": 5, "forgeLevels": {}, "version": 1})
	assert_true((await _client.get_my_guilds()).ok)
	assert_true((await _client.create_guild("Lichtwacht", "LW")).ok)
	assert_true((await _client.join_guild("ABCD2345")).ok)
	assert_true((await _client.get_guild(GUILD_ID)).ok)
	assert_true((await _client.leave_guild(GUILD_ID)).ok)
	assert_true((await _client.remove_guild_member(GUILD_ID, OTHER_ID)).ok)
	assert_eq((await _client.rotate_guild_invite_code(GUILD_ID)).get_field("inviteCode"), "NEWC0DE2")
	assert_true((await _client.get_guild_progress(GUILD_ID)).ok)
	assert_eq(_fake.keys(), [
		"GET /me/guilds", "POST /guilds", "POST /guilds/join", "GET /guilds/%s" % GUILD_ID,
		"POST /guilds/%s/leave" % GUILD_ID, "DELETE /guilds/%s/members/%s" % [GUILD_ID, OTHER_ID],
		"POST /guilds/%s/invite-code" % GUILD_ID, "GET /guilds/%s/progress" % GUILD_ID,
	] as Array[String])
	assert_eq(JSON.parse_string(_fake.requests[1].body), {"name": "Lichtwacht", "tag": "LW"})
	assert_eq(JSON.parse_string(_fake.requests[2].body), {"inviteCode": "ABCD2345"})
	for request in _fake.requests:
		assert_true(("Authorization: Bearer %s" % TOKEN) in request.headers, "%s with the session token" % request.key)


func test_guild_routes_need_a_token() -> void:
	_client.token = ""
	var result := await _client.get_my_guilds()
	assert_eq(result.error, ApiResult.UNAUTHORIZED)
	assert_true(_fake.requests.is_empty(), "nothing sent without a login")


# --- GuildDirectory ---

func test_parse_my_guild_list_and_detail() -> void:
	var list := GuildDirectory.parse_guild_list({"items": [_guild_summary(GUILD_ID, "Lichtwacht", "LW", "officer"), {"name": "no id"}], "maxGuilds": 5})
	assert_eq(list.size(), 1, "entries without id are skipped")
	assert_eq(list[0].role, "officer", "myRole of the contract")
	assert_eq(list[0].treasury, 120)
	var detail := GuildDirectory.normalize_guild(_guild_detail("member", null))
	assert_eq(detail.role, "member")
	assert_eq(detail.inviteCode, "", "plain members get no invite code (P-031)")
	assert_eq(detail.treasury, 240)
	assert_eq((detail.members as Array).size(), 3)


func test_rights_and_input_rules() -> void:
	assert_true(GuildDirectory.can_manage("founder"))
	assert_true(GuildDirectory.can_manage("officer"))
	assert_false(GuildDirectory.can_manage("member"))
	assert_true(GuildDirectory.can_remove("founder", "officer"))
	assert_false(GuildDirectory.can_remove("founder", "founder"))
	assert_true(GuildDirectory.can_remove("officer", "member"))
	assert_false(GuildDirectory.can_remove("officer", "officer"))
	assert_false(GuildDirectory.can_remove("member", "member"))
	assert_true(GuildDirectory.is_valid_name("Die Lichtwacht"))
	assert_false(GuildDirectory.is_valid_name("ab"), "3 characters at least")
	assert_false(GuildDirectory.is_valid_name("Böse<Gilde>"))
	assert_eq(GuildDirectory.normalize_tag(" lw-2x9 "), "LW2X9")
	assert_true(GuildDirectory.is_valid_tag("LW"))
	assert_false(GuildDirectory.is_valid_tag("L"))
	assert_eq(GuildDirectory.normalize_invite_code("abcd-2345 "), "ABCD2345", "dashes and spaces from Discord are dropped")
	assert_false(GuildDirectory.is_valid_invite_code("ABC12"))
	assert_eq(GuildDirectory.error_text(ApiResult.GUILD_LIMIT_REACHED), "Du bist schon in 5 Gilden, mehr geht nicht.")
	assert_eq(GuildDirectory.error_text(ApiResult.UNREACHABLE), "Der Server ist nicht erreichbar. Der Einzelspieler funktioniert weiter.")
	assert_eq(GuildDirectory.error_text("teapot"), "Etwas ist schiefgelaufen (teapot).")


func test_directory_logs_in_again_after_a_401() -> void:
	var directory := GuildDirectory.new(_session)
	_session.config.load_from({"api": "http://api.test", "dev_key": "dev-key-0123456789", "name": "Kerze"})
	_client.dev_key = "dev-key-0123456789"
	_fake.answer("GET /me/guilds", 401, {"error": "unauthorized"})
	_fake.answer("POST /auth/dev", 200, {"token": "session-token-2.c2ln", "expiresAt": "2099-01-01T00:00:00.000Z", "player": PLAYER})
	_fake.answer("GET /public/config", 200, {"apiVersion": "1.1.0", "minGameVersion": null, "protocolVersion": 1, "relayUrl": null})
	_fake.answer("GET /me/guilds", 200, {"items": [_guild_summary(GUILD_ID, "Lichtwacht", "LW", "member")], "maxGuilds": 5})
	var result := await directory.refresh()
	assert_true(result.ok, result.describe())
	assert_eq(directory.guilds.size(), 1)
	assert_eq(_fake.keys().count("GET /me/guilds"), 2, "the call is repeated once after the new login")


func test_directory_offline_keeps_single_player_quiet() -> void:
	var directory := GuildDirectory.new(_session)
	var result := await directory.refresh()
	assert_false(result.ok)
	assert_false(directory.loaded)
	assert_eq(directory.list_error, ApiResult.UNREACHABLE)


# --- OnlineMenu ---

func test_menu_starts_with_the_quick_game_and_logs_in() -> void:
	_fake.answer("GET /me/guilds", 200, {"items": [], "maxGuilds": 5})
	var menu := _open_menu()
	await wait_physics_frames(2)
	assert_eq(menu.view, OnlineMenu.View.QUICK)
	assert_not_null(_node(menu, "CreateRoom"))
	assert_not_null(_node(menu, "RoomCode"))
	assert_true((_node(menu, "JoinRoom") as Button).disabled, "join waits for a full room code")
	assert_eq(_fake.keys(), ["GET /me/guilds"] as Array[String], "opening logs in and loads the guilds once")
	assert_null(_node(menu, "OfflineHint"), "online: no hint")
	menu.show_view(OnlineMenu.View.GUILDS)
	await wait_physics_frames(1)
	assert_eq(_fake.keys().size(), 1, "the guild tab uses the loaded list")


func test_menu_offline_on_open_stays_usable() -> void:
	var menu := _open_menu()
	await wait_physics_frames(2)
	var hint := _node(menu, "OfflineHint") as Label
	assert_not_null(hint, "the server is not there: a friendly line on the quick tab")
	assert_string_contains(hint.text, "Einzelspieler")
	assert_not_null(_node(menu, "Retry"))
	assert_false((_node(menu, "CreateRoom") as Button).disabled, "the menu stays usable")
	var escape := InputEventAction.new()
	escape.action = &"ui_cancel"
	escape.pressed = true
	assert_false(menu.handle_input(escape), "Esc closes the dialog around it")


func test_no_login_on_open_when_switched_off() -> void:
	OnlineMenu.login_on_open = false
	var menu := _open_menu()
	await wait_physics_frames(1)
	OnlineMenu.login_on_open = true
	assert_true(_fake.requests.is_empty(), "tests and -- offline: nothing is sent")
	assert_null(_node(menu, "OfflineHint"))


func test_without_a_guild_only_two_big_buttons() -> void:
	_fake.answer("GET /me/guilds", 200, {"items": [], "maxGuilds": 5})
	var menu := _open_menu()
	menu.show_view(OnlineMenu.View.GUILDS)
	await wait_physics_frames(2)
	assert_not_null(_node(menu, "CreateGuildBig"))
	assert_not_null(_node(menu, "JoinGuildBig"))
	assert_null(_node(menu, "CreateGuild"), "no small header buttons")
	assert_string_contains(_all_texts(menu), "Du bist noch in keiner Gilde.")


func test_guild_list_with_create_and_join_on_top() -> void:
	_fake.answer("GET /me/guilds", 200, {"items": [_guild_summary(GUILD_ID, "Lichtwacht", "LW", "founder", 12), _guild_summary(GUILD_2_ID, "Dochte", "DO", "member")], "maxGuilds": 5})
	var menu := _open_menu()
	menu.show_view(OnlineMenu.View.GUILDS)
	await wait_physics_frames(2)
	assert_not_null(_node(menu, "CreateGuild"))
	assert_not_null(_node(menu, "JoinGuild"))
	assert_null(_node(menu, "CreateGuildBig"))
	var text := _all_texts(menu)
	assert_string_contains(text, "Deine Gilden (2/5)")
	var card := _node(menu, "Guild_%s" % GUILD_ID.replace("-", "_")) as Button
	assert_not_null(card, "one card per guild")
	assert_eq(card.focus_mode, Control.FOCUS_ALL)
	assert_eq((_node(card, "Tag") as Label).text, "[LW]")
	assert_eq((_node(card, "Name") as Label).text, "Lichtwacht")
	assert_eq((_node(card, "Info") as Label).text, "Gründer · 12/30")
	assert_eq(((_node(card, "Treasury") as Control).get_child(1) as Label).text, "120", "the treasury on the card")
	assert_eq(OnlineMenu.remembered_view, OnlineMenu.View.GUILDS, "the tab is remembered")


func test_guild_limit_disables_create_and_join() -> void:
	var items: Array = []
	for i in 5:
		items.append(_guild_summary("0000000%d-2222-4333-8444-555555555555" % i, "Gilde %d" % i, "G%d" % i, "member"))
	_fake.answer("GET /me/guilds", 200, {"items": items, "maxGuilds": 5})
	var menu := _open_menu()
	menu.show_view(OnlineMenu.View.GUILDS)
	await wait_physics_frames(2)
	assert_true((_node(menu, "CreateGuild") as Button).disabled)
	assert_true((_node(menu, "JoinGuild") as Button).disabled)


func test_founder_sees_invite_code_treasury_and_can_remove() -> void:
	_fake.answer("GET /me/guilds", 200, {"items": [_guild_summary(GUILD_ID, "Lichtwacht", "LW", "founder")], "maxGuilds": 5})
	_fake.answer("GET /guilds/%s" % GUILD_ID, 200, _guild_detail("founder"))
	var menu := _open_menu()
	menu.show_view(OnlineMenu.View.GUILDS)
	await wait_physics_frames(2)
	menu.show_view(OnlineMenu.View.DETAIL, GUILD_ID)
	await wait_physics_frames(2)
	assert_eq((_node(menu, "InviteCodeLabel") as Label).text, "ABCD2345")
	assert_not_null(_node(menu, "CopyInvite"))
	assert_not_null(_node(menu, "RenewInvite"))
	assert_eq(((_node(menu, "Treasury") as Control).get_child(1) as Label).text, "240")
	assert_string_contains(_all_texts(menu), "Mitglieder (3/30)")
	assert_string_contains(_all_texts(menu), "Kerze (du)")
	assert_eq((_node(_node(menu, "Member_%s" % OWN_ID.replace("-", "_")), "Joined") as Label).text, "15.10.2026", "joined on")
	assert_not_null(_node(menu, "Remove_%s" % OTHER_ID.replace("-", "_")), "founder removes members")
	assert_not_null(_node(menu, "Remove_%s" % OFFICER_ID.replace("-", "_")), "and officers")
	assert_null(_node(menu, "Remove_%s" % OWN_ID.replace("-", "_")), "never himself")
	assert_not_null(_node(menu, "CreateGuildRoom"))


func test_founder_names_and_demotes_officers() -> void:
	_fake.answer("GET /me/guilds", 200, {"items": [_guild_summary(GUILD_ID, "Lichtwacht", "LW", "founder")], "maxGuilds": 5})
	_fake.answer("GET /guilds/%s" % GUILD_ID, 200, _guild_detail("founder"))
	var promoted := _guild_detail("founder")
	promoted.members[2].role = "officer"
	_fake.answer("PATCH /guilds/%s/members/%s" % [GUILD_ID, OTHER_ID], 200, promoted)
	var menu := _open_menu()
	menu.show_view(OnlineMenu.View.GUILDS)
	await wait_physics_frames(2)
	menu.show_view(OnlineMenu.View.DETAIL, GUILD_ID)
	await wait_physics_frames(2)
	var promote := _node(menu, "Role_%s" % OTHER_ID.replace("-", "_")) as Button
	assert_not_null(promote, "the founder can name a member officer")
	assert_eq(tr(promote.text), "Ernennen")
	assert_eq(tr((_node(menu, "Role_%s" % OFFICER_ID.replace("-", "_")) as Button).text), "Absetzen", "and take the rank back")
	assert_null(_node(menu, "Role_%s" % OWN_ID.replace("-", "_")))
	promote.pressed.emit()
	await wait_physics_frames(2)
	var request: Dictionary = _fake.requests[_fake.requests.size() - 1]
	assert_eq(request.key, "PATCH /guilds/%s/members/%s" % [GUILD_ID, OTHER_ID])
	assert_eq(JSON.parse_string(request.body), {"role": "officer"})
	assert_eq(tr((_node(menu, "Role_%s" % OTHER_ID.replace("-", "_")) as Button).text), "Absetzen", "the list follows the answer")
	assert_string_contains(_all_texts(menu), "Docht ist jetzt Offizier.")


func test_officers_change_no_roles() -> void:
	assert_false(GuildDirectory.can_change_role("officer", "member"))
	assert_false(GuildDirectory.can_change_role("founder", "founder"))
	assert_true(GuildDirectory.can_change_role("founder", "officer"))


func test_member_sees_no_invite_code_and_removes_nobody() -> void:
	_fake.answer("GET /me/guilds", 200, {"items": [_guild_summary(GUILD_ID, "Lichtwacht", "LW", "member")], "maxGuilds": 5})
	_fake.answer("GET /guilds/%s" % GUILD_ID, 200, _guild_detail("member", null))
	var menu := _open_menu()
	menu.show_view(OnlineMenu.View.GUILDS)
	await wait_physics_frames(2)
	menu.show_view(OnlineMenu.View.DETAIL, GUILD_ID)
	await wait_physics_frames(2)
	assert_null(_node(menu, "InviteCodeLabel"))
	assert_not_null(_node(menu, "InviteHidden"))
	assert_eq(menu.find_children("Remove_*", "", true, false).size(), 0)
	assert_eq(tr((_node(menu, "OwnRole") as Label).text), "Mitglied")


func test_leaving_asks_first_and_goes_back_to_the_list() -> void:
	_fake.answer("GET /me/guilds", 200, {"items": [_guild_summary(GUILD_ID, "Lichtwacht", "LW", "member")], "maxGuilds": 5})
	_fake.answer("GET /guilds/%s" % GUILD_ID, 200, _guild_detail("member", null))
	_fake.answer("POST /guilds/%s/leave" % GUILD_ID, 200, {"guildId": GUILD_ID, "disbanded": false, "newFounderId": null})
	var menu := _open_menu()
	menu.show_view(OnlineMenu.View.GUILDS)
	await wait_physics_frames(2)
	menu.show_view(OnlineMenu.View.DETAIL, GUILD_ID)
	await wait_physics_frames(2)
	(_node(menu, "LeaveGuild") as Button).pressed.emit()
	await wait_physics_frames(1)
	assert_eq(menu.view, OnlineMenu.View.CONFIRM, "asks first")
	assert_string_contains(_all_texts(menu), "Lichtwacht wirklich verlassen?")
	assert_false(_fake.keys().has("POST /guilds/%s/leave" % GUILD_ID), "nothing sent before the confirmation")
	(_node(menu, "ConfirmYes") as Button).pressed.emit()
	await wait_physics_frames(2)
	assert_true(_fake.keys().has("POST /guilds/%s/leave" % GUILD_ID))
	assert_eq(menu.view, OnlineMenu.View.GUILDS)
	assert_not_null(_node(menu, "CreateGuildBig"), "no guild left: the two big buttons")
	assert_string_contains(_all_texts(menu), "Du hast Lichtwacht verlassen.")


func test_escape_goes_back_one_step() -> void:
	_fake.answer("GET /me/guilds", 200, {"items": [], "maxGuilds": 5})
	var menu := _open_menu()
	menu.show_view(OnlineMenu.View.GUILDS)
	await wait_physics_frames(2)
	menu.show_view(OnlineMenu.View.JOIN)
	await wait_physics_frames(1)
	var escape := InputEventAction.new()
	escape.action = &"ui_cancel"
	escape.pressed = true
	assert_true(menu.handle_input(escape), "form -> list")
	assert_eq(menu.view, OnlineMenu.View.GUILDS)
	assert_false(menu.handle_input(escape), "at the top the dialog closes")


func test_creating_a_guild_opens_it() -> void:
	_fake.answer("GET /me/guilds", 200, {"items": [], "maxGuilds": 5})
	_fake.answer("POST /guilds", 201, _guild_detail("founder"))
	_fake.answer("GET /me/guilds", 200, {"items": [_guild_summary(GUILD_ID, "Lichtwacht", "LW", "founder", 1)], "maxGuilds": 5})
	_fake.answer("GET /guilds/%s" % GUILD_ID, 200, _guild_detail("founder"))
	var menu := _open_menu()
	menu.show_view(OnlineMenu.View.GUILDS)
	await wait_physics_frames(2)
	(_node(menu, "CreateGuildBig") as Button).pressed.emit()
	await wait_physics_frames(1)
	var confirm := _node(menu, "ConfirmCreate") as Button
	assert_true(confirm.disabled, "needs name and tag")
	(_node(menu, "GuildName") as LineEdit).text_changed.emit("Lichtwacht")
	var tag := _node(menu, "GuildTag") as LineEdit
	tag.text = "lw"
	tag.text_changed.emit("lw")
	assert_eq(tag.text, "LW", "tag in capitals")
	assert_false(confirm.disabled)
	confirm.pressed.emit()
	await wait_physics_frames(2)
	assert_eq(JSON.parse_string(_fake.requests[1].body), {"name": "Lichtwacht", "tag": "LW"})
	assert_eq(menu.view, OnlineMenu.View.DETAIL)
	assert_eq(menu.detail_id, GUILD_ID)
	assert_string_contains(_all_texts(menu), "Gilde Lichtwacht gegründet.")


func test_join_errors_are_friendly() -> void:
	_fake.answer("GET /me/guilds", 200, {"items": [], "maxGuilds": 5})
	_fake.answer("POST /guilds/join", 404, {"error": "invalid_invite_code", "message": "Invite code not found"})
	var menu := _open_menu()
	menu.show_view(OnlineMenu.View.GUILDS)
	await wait_physics_frames(2)
	menu.show_view(OnlineMenu.View.JOIN)
	await wait_physics_frames(1)
	var code := _node(menu, "InviteCode") as LineEdit
	code.text_changed.emit("abcd 2345")
	assert_eq(code.text, "ABCD2345")
	(_node(menu, "ConfirmJoin") as Button).pressed.emit()
	await wait_physics_frames(2)
	assert_eq(menu.view, OnlineMenu.View.JOIN, "stays in the form")
	assert_eq((_node(menu, "FieldError") as Label).text, "Einladungscode unbekannt.", "at the field")
	assert_false((_node(menu, "Status") as Label).visible, "not twice")


func test_create_errors_stand_at_their_field() -> void:
	_fake.answer("GET /me/guilds", 200, {"items": [], "maxGuilds": 5})
	_fake.answer("POST /guilds", 409, {"error": "guild_tag_taken", "message": "Tag taken"})
	_fake.answer("POST /guilds", 409, {"error": "guild_limit_reached", "message": "Limit"})
	var menu := _open_menu()
	await wait_physics_frames(2)
	menu.show_view(OnlineMenu.View.CREATE)
	await wait_physics_frames(1)
	(_node(menu, "GuildName") as LineEdit).text_changed.emit("Lichtwacht")
	(_node(menu, "GuildTag") as LineEdit).text_changed.emit("LW")
	(_node(menu, "ConfirmCreate") as Button).pressed.emit()
	await wait_physics_frames(2)
	assert_eq(menu.form_error_field, "tag")
	var error := _node(menu, "FieldError") as Label
	assert_eq(error.text, "Dieses Kürzel ist schon vergeben.")
	var grid := error.get_parent()
	assert_eq(error.get_index(), _node(menu, "GuildTag").get_index() + 2, "right under the tag field")
	assert_eq(grid, _node(menu, "GuildTag").get_parent())
	(_node(menu, "ConfirmCreate") as Button).pressed.emit()
	await wait_physics_frames(2)
	assert_eq((_node(menu, "FormError") as Label).text, "Du bist schon in 5 Gilden, mehr geht nicht.", "no field: under the form")
	assert_null(_node(menu, "FieldError"))


func test_offline_shows_a_hint_and_retry() -> void:
	var menu := _open_menu()
	menu.show_view(OnlineMenu.View.GUILDS)
	await wait_physics_frames(2)
	assert_not_null(_node(menu, "GuildsError"))
	assert_string_contains((_node(menu, "GuildsError") as Label).text, "Einzelspieler")
	assert_not_null(_node(menu, "Retry"))


func test_main_menu_rooms_become_launch_wishes() -> void:
	var menu := _open_menu()
	watch_signals(menu)
	await wait_physics_frames(1)
	(_node(menu, "CreateRoom") as Button).pressed.emit()
	assert_signal_emitted_with_parameters(menu, "launch_requested", [{"action": LobbyClient.LAUNCH_CREATE, "mode": LobbyClient.MODE_QUICK}])
	_fake.answer("GET /me/guilds", 200, {"items": [_guild_summary(GUILD_ID, "Lichtwacht", "LW", "member")], "maxGuilds": 5})
	_fake.answer("GET /guilds/%s" % GUILD_ID, 200, _guild_detail("member", null))
	menu.show_view(OnlineMenu.View.GUILDS)
	await wait_physics_frames(2)
	menu.show_view(OnlineMenu.View.DETAIL, GUILD_ID)
	await wait_physics_frames(2)
	(_node(menu, "CreateGuildRoom") as Button).pressed.emit()
	assert_signal_emitted_with_parameters(menu, "launch_requested", [{"action": LobbyClient.LAUNCH_CREATE, "mode": LobbyClient.MODE_GUILD, "guild_id": GUILD_ID, "guild_name": "Lichtwacht", "guild_tag": "LW"}])
	var room_code := _node(menu, "GuildRoomCode") as LineEdit
	assert_true((_node(menu, "JoinGuildRoom") as Button).disabled, "join waits for a room code")
	room_code.text_changed.emit("abcd23")
	assert_eq(room_code.text, "ABCD23")
	(_node(menu, "JoinGuildRoom") as Button).pressed.emit()
	assert_signal_emitted_with_parameters(menu, "launch_requested", [{"action": LobbyClient.LAUNCH_JOIN, "code": "ABCD23", "guild_id": GUILD_ID, "guild_name": "Lichtwacht", "guild_tag": "LW"}])


func test_leave_question_warns_founder_and_last_member() -> void:
	var menu := _open_menu()
	await wait_physics_frames(1)
	assert_eq(menu.leave_question("Lichtwacht", "member", 3), "Lichtwacht wirklich verlassen? Zurück kommst du nur mit einem Einladungscode.")
	assert_string_contains(menu.leave_question("Lichtwacht", "founder", 3), "Die Leitung geht an den Offizier, der am längsten dabei ist")
	assert_string_contains(menu.leave_question("Lichtwacht", "founder", 1), "Die Gilde wird aufgelöst.")


func test_leaving_as_last_member_says_disbanded() -> void:
	_fake.answer("GET /me/guilds", 200, {"items": [_guild_summary(GUILD_ID, "Lichtwacht", "LW", "founder", 1)], "maxGuilds": 5})
	_fake.answer("POST /guilds/%s/leave" % GUILD_ID, 200, {"guildId": GUILD_ID, "disbanded": true, "newFounderId": null})
	var menu := _open_menu()
	await wait_physics_frames(2)
	menu.show_view(OnlineMenu.View.GUILDS)
	await wait_physics_frames(1)
	await menu.directory.leave_guild(GUILD_ID)
	await wait_physics_frames(2)
	assert_string_contains(_all_texts(menu), "Du hast Lichtwacht verlassen. Die Gilde ist aufgelöst.")


func test_dates_follow_the_language() -> void:
	assert_eq(GuildDirectory.format_date("2026-10-15T10:00:00.000Z", "de"), "15.10.2026")
	assert_eq(GuildDirectory.format_date("2026-10-15T10:00:00.000Z", "en"), "2026-10-15")
	assert_eq(GuildDirectory.format_date("", "de"), "")


func test_keyboard_reaches_the_buttons() -> void:
	var menu := _open_menu()
	await wait_physics_frames(2)
	var down := InputEventAction.new()
	down.action = &"ui_down"
	down.pressed = true
	menu.handle_input(down)
	var focused := get_viewport().gui_get_focus_owner()
	assert_not_null(focused, "a key gives the menu the focus")
	assert_true(menu.is_ancestor_of(focused))
	assert_eq(focused.focus_mode, Control.FOCUS_ALL)


# --- Guild runs ---

func test_launch_wish_is_taken_once() -> void:
	LobbyClient.request_launch(LobbyClient.LAUNCH_JOIN, LobbyClient.MODE_QUICK, "", "", "ABCD23")
	assert_true(LobbyClient.has_pending_launch())
	assert_eq(LobbyClient.take_launch().get("code"), "ABCD23")
	assert_true(LobbyClient.take_launch().is_empty())


func test_guild_room_is_a_guild_session() -> void:
	var lobby := LobbyClient.new()
	lobby.reload_world = false
	add_child_autofree(lobby)
	lobby.state = LobbyClient.State.IN_ROOM
	lobby.room = {"code": "ABCD23", "mode": "guild", "guildId": GUILD_ID, "peers": []}
	assert_true(lobby.is_guild_room())
	assert_eq(lobby.get_room_guild_id(), GUILD_ID)
	var mode := lobby.create_session_mode()
	assert_eq(mode.kind, GameMode.Kind.GUILD)
	assert_eq(mode.guild_id, GUILD_ID)
	assert_eq(mode.get_run_mode_name(), "guild")
	assert_false(mode.pauses_for_menus(), "no global pause in a guild room")
	lobby.room = {"code": "ABCD23", "mode": "quick", "guildId": null, "peers": []}
	assert_eq(lobby.create_session_mode().kind, GameMode.Kind.QUICK)
	lobby.state = LobbyClient.State.IDLE


func test_guild_room_needs_a_guild() -> void:
	var lobby := LobbyClient.new()
	add_child_autofree(lobby)
	watch_signals(lobby)
	await lobby.create_room(LobbyClient.MODE_GUILD, "")
	assert_signal_emitted_with_parameters(lobby, "error", [LobbyClient.ERROR_NO_GUILD])
	assert_eq(lobby.state, LobbyClient.State.IDLE)


func test_run_report_of_a_guild_run() -> void:
	var lobby := LobbyClient.new()
	lobby.reload_world = false
	add_child_autofree(lobby)
	lobby.state = LobbyClient.State.IN_ROOM
	lobby.room = {"code": "ABCD23", "mode": "guild", "guildId": GUILD_ID, "peers": []}
	var run := lobby.net_run
	run.participants.assign([OWN_ID, OTHER_ID])
	run.seed_value = 4242
	var body := run.report_body({"room": 12, "reason": RunManager.EndReason.EXIT, "remaining_gold": 87})
	assert_eq(body.mode, "guild")
	assert_eq(body.guildId, GUILD_ID)
	assert_eq(body.endReason, "portal")
	assert_eq(body.remainingGold, 87)
	assert_eq(body.roomReached, 12)
	assert_eq(str(body.reportId).length(), 36, "a UUID per run (reportId)")
	assert_eq(run.report_body({"room": 12}).reportId, body.reportId, "the same on a second try")
	var answer := ApiResult.success(201, {"id": GUILD_2_ID, "flagged": false, "flagReason": null, "createdAt": "2026-10-15T10:00:00.000Z",
		"guildPayout": 87, "guildProgress": {"treasury": 327, "forgeLevels": {}, "version": 4}})
	run._accept_guild_payout(answer)
	assert_eq(run.last_guild_payout, 87)
	assert_eq(run.last_guild_treasury, 327)
	lobby.room = {"code": "ABCD23", "mode": "quick", "guildId": null, "peers": []}
	var quick := run.report_body({"room": 3, "reason": RunManager.EndReason.DEATH, "remaining_gold": 10})
	assert_eq(quick.mode, "quick")
	assert_false(quick.has("guildId"), "the API refuses guildId outside guild runs")
	assert_false(quick.has("remainingGold"))
	lobby.state = LobbyClient.State.IDLE


func test_guild_payout_is_shown_once_in_the_village() -> void:
	var lobby := LobbyClient.new()
	lobby.reload_world = false
	add_child_autofree(lobby)
	lobby.room_guild_tag = "DOCHT"
	var run := lobby.net_run
	watch_signals(run)
	run._notice_payout(0, 100, "DOCHT", "Docht")
	assert_signal_not_emitted(run, "guild_payout_noticed", "nothing paid, nothing to say")
	run._notice_payout(21, 321, "DOCHT", "Docht")
	assert_signal_emitted(run, "guild_payout_noticed")
	assert_eq(NetRun.payout_text({"payout": 21, "tag": "DOCHT"}), "+21 Gold für [DOCHT]")
	assert_eq(NetRun.payout_text({"payout": 21, "tag": ""}), "+21 Gold für die Gildenkasse")
	# The village loaded after the report: it takes the notice once.
	var ui := VillageUI.new()
	add_child_autofree(ui)
	await wait_physics_frames(2)
	var notice := ui.get_notice()
	assert_not_null(notice, "a short notice in the village")
	assert_string_contains(_all_texts(notice), "+21 Gold für [DOCHT]")
	assert_string_contains(_all_texts(notice), "Kasse jetzt: 321 Gold")
	assert_true(run.take_payout_notice().is_empty(), "shown once")


func test_room_view_copies_the_code_and_shows_the_ping() -> void:
	var lobby := LobbyClient.new()
	lobby.reload_world = false
	add_child_autofree(lobby)
	lobby.state = LobbyClient.State.IN_ROOM
	lobby.room = {"code": "ABCD23", "mode": "quick", "guildId": null, "maxPlayers": 4,
		"peers": [{"peerId": 1, "playerId": OWN_ID, "name": "Kerze", "platform": "pc"}]}
	lobby.peer = RelayPeer.new()
	var menu := _open_menu(lobby)
	await wait_physics_frames(2)
	var hint := _node(menu, "RoomHint") as Label
	assert_false(hint.text.contains("Ping"), "no ping before the first round trip")
	lobby.peer.last_rtt_msec = 42
	await wait_seconds(1.2)
	assert_string_contains(hint.text, "Ping 42 ms", "the hint follows the relay's round trip")
	var copy := _node(menu, "CopyRoomCode") as Button
	copy.pressed.emit()
	if DisplayServer.get_name() != "headless":
		assert_eq(DisplayServer.clipboard_get(), "ABCD23")
	assert_eq(copy.text, "Kopiert!", "the button says it worked")
	lobby.peer = null
	lobby.state = LobbyClient.State.IDLE


func test_solo_and_quick_run_mode_names() -> void:
	assert_eq(GameMode.solo().get_run_mode_name(), "solo")
	assert_eq(GameMode.quick(2).get_run_mode_name(), "quick")
	assert_eq(GameMode.guild(2).get_run_mode_name(), "quick", "a guild session without id reports as quick")


# --- Village ---

func test_guild_building_shows_the_online_menu() -> void:
	var ui := VillageUI.new()
	add_child_autofree(ui)
	ui.open_guild(true)
	await wait_physics_frames(2)
	var menu := ui.get_online_menu()
	assert_not_null(menu, "the guild building is the online menu (D-147)")
	var modal := ui.get_building_modal()
	assert_true(modal.input_handler.is_valid(), "Esc goes back inside the menu first")
	assert_not_null(_node(menu, "TabGuilds"))
	assert_false(_all_texts(modal).contains("Vorbereitung"), "no 'in Vorbereitung' any more")
	modal.finish()
	await wait_physics_frames(1)
	assert_null(ui.get_online_menu())

extends GutTest
## Guild rooms on the guild's page (playtest 16.10.2026): GET /guilds/:id/rooms (contracts guild.ts
## GuildRoomList) through ApiClient and GuildDirectory (quiet, 404 hides the list), the open rooms
## with "Beitreten" (greyed out while a run is on or for another game version), the own guild room
## on the guild's page instead of the quick tab, and "Was bringt eine Gilde?" (only what exists).
## No network (fake HTTP layer), the real save and online.cfg are never touched.

const TEST_PATH := "user://test_guild_rooms_online.cfg"
const SAVE_PATH := "user://test_guild_rooms_save.cfg"
const TOKEN := "session-token.c2lnbmF0dXJl"
const OWN_ID := "6f1c3a52-6a0e-4a3b-9a55-1c2d3e4f5a6b"
const OTHER_ID := "7a2d4b63-7b1f-4c4c-8b66-2d3e4f5a6b7c"
const GUILD_ID := "11111111-2222-4333-8444-555555555555"
const PLAYER := {"id": OWN_ID, "name": "Kerze", "steamId": null, "createdAt": "2026-10-14T10:00:00.000Z", "guild": null, "guilds": []}


## Answers from a queue keyed by "METHOD path"; records every request (as in test_online_menu.gd).
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

	func count(key: String) -> int:
		return keys().count(key)


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

func _guild_summary(role := "member") -> Dictionary:
	return {"id": GUILD_ID, "name": "Lichtwacht", "tag": "LW", "myRole": role, "memberCount": 2, "maxMembers": 30, "joinedAt": "2026-10-15T10:00:00.000Z", "treasury": 120}


func _guild_detail(role := "member") -> Dictionary:
	return {
		"id": GUILD_ID, "name": "Lichtwacht", "tag": "LW", "inviteCode": null, "founderId": OTHER_ID,
		"createdAt": "2026-10-15T10:00:00.000Z", "maxMembers": 30, "myRole": role,
		"members": [
			{"playerId": OTHER_ID, "name": "Docht", "role": "founder", "joinedAt": "2026-10-15T10:00:00.000Z"},
			{"playerId": OWN_ID, "name": "Kerze", "role": role, "joinedAt": "2026-10-15T10:02:00.000Z"},
		],
		"progress": {"treasury": 240, "forgeLevels": {}, "version": 3},
	}


## One GuildRoom of the contract.
func _room(code: String, host: String, count: int, started := false, version := "") -> Dictionary:
	var players: Array = [{"playerId": OTHER_ID, "name": host, "host": true}]
	for i in count - 1:
		players.append({"playerId": OWN_ID, "name": "Gast %d" % i, "host": false})
	return {"code": code, "hostName": host, "hostPlayerId": OTHER_ID, "playerCount": count, "maxPlayers": 4, "started": started,
		"gameVersion": version if not version.is_empty() else OnlineConfig.get_game_version(), "players": players,
		"createdAt": "2026-10-16T10:00:00.000Z", "expiresAt": null if started else "2026-10-16T11:00:00.000Z"}


func _room_list(rooms: Array, relay := true) -> Dictionary:
	return {"time": "2026-10-16T10:05:00.000Z", "relayAvailable": relay, "rooms": rooms}


func _answer_guild(rooms_status := 200, rooms_body: Variant = null) -> void:
	_fake.answer("GET /me/guilds", 200, {"items": [_guild_summary()], "maxGuilds": 5})
	_fake.answer("GET /guilds/%s" % GUILD_ID, 200, _guild_detail())
	_fake.answer("GET /guilds/%s/rooms" % GUILD_ID, rooms_status, rooms_body if rooms_body != null else _room_list([]))


func _open_menu(lobby: LobbyClient = null) -> OnlineMenu:
	var menu := OnlineMenu.create(lobby, _session)
	add_child_autofree(menu)
	return menu


## The menu on the guild's page, with the list and the guild loaded.
func _open_guild_page(lobby: LobbyClient = null) -> OnlineMenu:
	var menu := _open_menu(lobby)
	await wait_physics_frames(2)
	menu.show_view(OnlineMenu.View.DETAIL, GUILD_ID)
	await wait_physics_frames(3)
	return menu


func _node(node: Node, node_name: String) -> Node:
	return node.find_child(node_name, true, false)


## A lobby in a room without network (state and snapshot set by hand).
func _lobby_in_room(mode: String, guild_id: Variant = null) -> LobbyClient:
	var lobby := LobbyClient.new()
	lobby.reload_world = false
	add_child_autofree(lobby)
	lobby.state = LobbyClient.State.IN_ROOM
	lobby.room = {"code": "ROOM23", "mode": mode, "guildId": guild_id, "maxPlayers": 4,
		"peers": [{"peerId": 1, "playerId": OTHER_ID, "name": "Docht", "platform": "pc"}, {"peerId": 2, "playerId": OWN_ID, "name": "Kerze", "platform": "pc"}]}
	return lobby


# --- ApiClient / GuildDirectory ---

func test_rooms_route_follows_the_contract() -> void:
	_fake.answer("GET /guilds/%s/rooms" % GUILD_ID, 200, _room_list([_room("ABCD23", "Docht", 2)]))
	var result := await _client.get_guild_rooms(GUILD_ID)
	assert_true(result.ok)
	assert_eq(_fake.keys(), ["GET /guilds/%s/rooms" % GUILD_ID] as Array[String])
	assert_true(("Authorization: Bearer %s" % TOKEN) in _fake.requests[0].headers, "with the session token like every guild route")
	_client.token = ""
	assert_eq((await _client.get_guild_rooms(GUILD_ID)).error, ApiResult.UNAUTHORIZED, "nothing sent without a login")
	assert_eq(_fake.requests.size(), 1)


func test_room_list_is_parsed_leniently() -> void:
	var rooms := GuildDirectory.parse_room_list(_room_list([_room("abcd23", "Docht", 2, true, "0.1.0"), {"code": "nope"}, {"code": "WXYZ45", "players": 3, "maxPlayers": 4}]))
	assert_eq(rooms.size(), 2, "entries without a valid room code are skipped")
	assert_eq(rooms[0].code, "ABCD23", "the code is normalised")
	assert_eq(rooms[0].hostName, "Docht")
	assert_eq(rooms[0].players, 2, "playerCount of the contract")
	assert_eq(rooms[0].maxPlayers, 4)
	assert_true(rooms[0].started)
	assert_eq(rooms[0].gameVersion, "0.1.0")
	assert_eq(rooms[1].players, 3, "players as a number is read too")
	assert_eq(rooms[1].hostName, "", "no host name known")
	var no_name := _room("ABCD23", "Docht", 1)
	no_name.erase("hostName")
	assert_eq(GuildDirectory.normalize_room(no_name).hostName, "Docht", "else the host of the players list")
	assert_true(GuildDirectory.parse_room_list(_room_list([_room("ABCD23", "Docht", 2)], false)).is_empty(), "relay away: no list")


func test_rooms_load_quietly_and_404_hides_them_for_good() -> void:
	var directory := GuildDirectory.new(_session)
	watch_signals(directory)
	_fake.answer("GET /guilds/%s/rooms" % GUILD_ID, 200, _room_list([_room("ABCD23", "Docht", 2)]))
	_fake.answer("GET /guilds/%s/rooms" % GUILD_ID, 200, _room_list([_room("ABCD23", "Docht", 2)]))
	_fake.answer("GET /guilds/%s/rooms" % GUILD_ID, 404, {"error": "not_found", "message": "Route not found"})
	await directory.load_rooms(GUILD_ID)
	assert_eq(directory.running, 0, "never busy: the menu keeps its buttons")
	assert_true(directory.has_rooms(GUILD_ID))
	assert_eq(directory.get_rooms(GUILD_ID).size(), 1)
	assert_signal_emit_count(directory, "changed", 1, "the new list")
	await directory.load_rooms(GUILD_ID)
	assert_signal_emit_count(directory, "changed", 1, "the same list again: no rebuild")
	await directory.load_rooms(GUILD_ID)
	assert_false(directory.rooms_supported, "an API without the route")
	assert_false(directory.has_rooms(GUILD_ID))
	await directory.load_rooms(GUILD_ID)
	assert_eq(_fake.count("GET /guilds/%s/rooms" % GUILD_ID), 3, "not asked again after a 404")


func test_rooms_of_a_left_guild_are_dropped() -> void:
	var directory := GuildDirectory.new(_session)
	_fake.answer("GET /guilds/%s/rooms" % GUILD_ID, 200, _room_list([_room("ABCD23", "Docht", 2)]))
	_fake.answer("POST /guilds/%s/leave" % GUILD_ID, 200, {"guildId": GUILD_ID, "disbanded": false, "newFounderId": null})
	await directory.load_rooms(GUILD_ID)
	await directory.leave_guild(GUILD_ID)
	assert_false(directory.has_rooms(GUILD_ID))


# --- The guild's page ---

func test_guild_page_lists_open_rooms_with_join() -> void:
	_answer_guild(200, _room_list([_room("ABCD23", "Docht", 2), _room("RUNS45", "Flamme", 3, true), _room("VERS67", "Lunte", 1, false, "0.0.1")]))
	var menu := await _open_guild_page()
	assert_true(_fake.keys().has("GET /guilds/%s/rooms" % GUILD_ID), "the page loads the open rooms")
	assert_not_null(_node(menu, "OpenRoom_ABCD23"))
	var join := _node(menu, "JoinListed_ABCD23") as Button
	assert_not_null(join)
	assert_false(join.disabled)
	assert_eq((_node(_node(menu, "OpenRoom_ABCD23"), "Players") as Label).text, "2/4")
	assert_true((_node(menu, "JoinListed_RUNS45") as Button).disabled, "a run is on: the relay would refuse (room_started)")
	assert_not_null(_node(_node(menu, "OpenRoom_RUNS45"), "State"))
	assert_true((_node(menu, "JoinListed_VERS67") as Button).disabled, "another game version: version_mismatch")
	assert_not_null(_node(menu, "CreateGuildRoom"), "creating stays on the page")
	assert_null(_node(menu, "GuildRoomCode"), "no room code: the guild joins from the list (b47bee4a)")
	assert_null(_node(menu, "JoinGuildRoom"))
	assert_eq(menu.get_tab(), OnlineMenu.View.GUILDS)


func test_main_menu_join_from_the_list_is_a_launch_wish() -> void:
	_answer_guild(200, _room_list([_room("ABCD23", "Docht", 2)]))
	var menu := await _open_guild_page()
	watch_signals(menu)
	(_node(menu, "JoinListed_ABCD23") as Button).pressed.emit()
	assert_signal_emitted_with_parameters(menu, "launch_requested", [{"action": LobbyClient.LAUNCH_JOIN, "code": "ABCD23", "guild_id": GUILD_ID, "guild_name": "Lichtwacht", "guild_tag": "LW"}])


func test_no_open_room_says_so() -> void:
	_answer_guild(200, _room_list([]))
	var menu := await _open_guild_page()
	assert_not_null(_node(menu, "NoOpenRooms"))
	assert_null(_node(menu, "OpenRooms"))


func test_api_without_the_route_hides_the_list() -> void:
	_answer_guild(404, {"error": "not_found", "message": "Route not found"})
	var menu := await _open_guild_page()
	assert_false(menu.directory.rooms_supported)
	assert_null(_node(menu, "NoOpenRooms"), "no empty promise either")
	assert_null(_node(menu, "OpenRooms"))
	assert_not_null(_node(menu, "CreateGuildRoom"), "creating and joining by code still work")
	assert_not_null(_node(menu, "GuildRoomCode"), "the room code is the fallback here")
	assert_not_null(_node(menu, "JoinGuildRoom"))
	assert_true(menu.notice.is_empty(), "no error line for a missing list")
	assert_false(menu.wants_rooms(), "no more polling")


func test_rooms_are_polled_only_on_the_guild_page() -> void:
	_answer_guild(200, _room_list([]))
	var menu := await _open_guild_page()
	assert_true(menu.wants_rooms(), "the page is open: poll")
	assert_gte(OnlineMenu.ROOMS_REFRESH_SECONDS, 5.0, "the API asks for at most one call every ~5 s")
	menu.show_view(OnlineMenu.View.GUILDS)
	assert_false(menu.wants_rooms(), "not on the list")
	menu.show_view(OnlineMenu.View.QUICK)
	assert_false(menu.wants_rooms(), "not on the quick tab")
	await wait_physics_frames(1)


func test_a_new_room_appears_without_reopening() -> void:
	_answer_guild(200, _room_list([]))
	var menu := await _open_guild_page()
	assert_not_null(_node(menu, "NoOpenRooms"))
	_fake.answer("GET /guilds/%s/rooms" % GUILD_ID, 200, _room_list([_room("ABCD23", "Docht", 1)]))
	await menu.directory.load_rooms(GUILD_ID)
	await wait_physics_frames(2)
	assert_not_null(_node(menu, "JoinListed_ABCD23"), "the list follows the poll")


# --- The own guild room lives on the guild's page ---

func test_guild_room_opens_on_the_guild_page() -> void:
	_answer_guild()
	var lobby := _lobby_in_room(LobbyClient.MODE_GUILD, GUILD_ID)
	lobby.room_guild_name = "Lichtwacht"
	lobby.room_guild_tag = "LW"
	var menu := _open_menu(lobby)
	await wait_physics_frames(3)
	assert_eq(menu.view, OnlineMenu.View.DETAIL, "not the quick tab")
	assert_eq(menu.detail_id, GUILD_ID)
	assert_eq(menu.get_tab(), OnlineMenu.View.GUILDS)
	var room := _node(menu, "GuildRoom")
	assert_not_null(room, "the room on the guild's page")
	assert_null(_node(room, "RoomCodeLabel"), "a guild room shows no code (b47bee4a)")
	assert_null(_node(room, "CopyRoomCode"))
	assert_null(_node(room, "ShareCode"), "no 'Code teilen' at the free places")
	assert_not_null(_node(room, "LobbyPlayers"))
	assert_eq(menu.get_slots().size(), 4, "the free places are there")
	assert_not_null(_node(room, "LeaveRoom"))
	assert_null(_node(menu, "CreateGuildRoom"), "no second room from here")
	assert_false(_fake.keys().has("GET /guilds/%s/rooms" % GUILD_ID), "no list while in the guild's room")
	assert_false(menu.wants_rooms())
	lobby.state = LobbyClient.State.IDLE


func test_guild_room_code_only_without_the_room_list() -> void:
	# An API without GET /guilds/:id/rooms: members could not find the room, so the code stays.
	_answer_guild()
	var lobby := _lobby_in_room(LobbyClient.MODE_GUILD, GUILD_ID)
	lobby.peer = RelayPeer.new()
	lobby.peer._unique_id = 1
	lobby.peer._is_host = true
	var menu := _open_menu(lobby)
	await wait_physics_frames(3)
	menu.directory.rooms_supported = false
	menu._rebuild()
	var room := _node(menu, "GuildRoom")
	assert_eq((_node(room, "RoomCodeLabel") as Label).text, "ROOM23")
	assert_not_null(_node(room, "CopyRoomCode"))
	assert_not_null(_node(room, "ShareCode"), "the first free place offers the code again")
	assert_string_contains((_node(room, "RoomHint") as Label).text, "Gib diesen Code", "the host is told to pass it on")
	menu.directory.rooms_supported = true
	menu._rebuild()
	assert_string_contains((_node(menu, "RoomHint") as Label).text, "Deine Gilde sieht den Raum hier", "with the list: the guild finds it")
	lobby.peer = null
	lobby.state = LobbyClient.State.IDLE


func test_guild_room_shows_before_the_guild_loaded() -> void:
	# The server is away (no answers): the room on the relay still shows on the page.
	var lobby := _lobby_in_room(LobbyClient.MODE_GUILD, GUILD_ID)
	lobby.room_guild_name = "Lichtwacht"
	lobby.room_guild_tag = "LW"
	var menu := _open_menu(lobby)
	await wait_physics_frames(3)
	assert_eq(menu.view, OnlineMenu.View.DETAIL, "the page stays")
	assert_not_null(_node(menu, "GuildRoom"))
	assert_eq((_node(menu, "GuildTitle") as Label).text, "[LW]  Lichtwacht", "named from the room")
	lobby.state = LobbyClient.State.IDLE


func test_quick_tab_points_to_the_guild_room() -> void:
	_answer_guild()
	var lobby := _lobby_in_room(LobbyClient.MODE_GUILD, GUILD_ID)
	var menu := _open_menu(lobby)
	await wait_physics_frames(3)
	menu.show_view(OnlineMenu.View.QUICK)
	await wait_physics_frames(1)
	assert_null(_node(menu, "RoomCodeLabel"), "the guild room is not in the quick tab")
	assert_null(_node(menu, "CreateRoom"), "no quick room while in a guild room")
	var go := _node(menu, "ShowGuildRoom") as Button
	assert_not_null(go)
	assert_not_null(_node(menu, "GuildRoomActive"))
	go.pressed.emit()
	await wait_physics_frames(1)
	assert_eq(menu.view, OnlineMenu.View.DETAIL)
	assert_not_null(_node(menu, "GuildRoom"))
	lobby.state = LobbyClient.State.IDLE


func test_quick_room_stays_in_the_quick_tab() -> void:
	_fake.answer("GET /me/guilds", 200, {"items": [_guild_summary()], "maxGuilds": 5})
	var lobby := _lobby_in_room(LobbyClient.MODE_QUICK)
	var menu := _open_menu(lobby)
	await wait_physics_frames(2)
	assert_eq(menu.view, OnlineMenu.View.QUICK)
	assert_not_null(_node(menu, "RoomCodeLabel"))
	assert_null(_node(menu, "GuildRoomTitle"))
	lobby.state = LobbyClient.State.IDLE


func test_creating_a_guild_room_stays_on_the_guild_page() -> void:
	_answer_guild()
	var lobby := LobbyClient.new()
	lobby.reload_world = false
	add_child_autofree(lobby)
	var menu := await _open_guild_page(lobby)
	# What create_room does before the relay answers (no network here).
	lobby.target_guild_id = GUILD_ID
	lobby.state = LobbyClient.State.CONNECTING
	lobby.state_changed.emit(lobby.state)
	await wait_physics_frames(2)
	assert_eq(menu.view, OnlineMenu.View.DETAIL, "playtest: no jump to the quick tab")
	assert_eq(menu.detail_id, GUILD_ID)
	assert_true((_node(menu, "CreateGuildRoom") as Button).disabled, "one room at a time")
	assert_eq((menu.get_node("Status") as Label).text, "Verbinde …", "connecting shows on the page")
	menu.show_view(OnlineMenu.View.GUILDS)
	lobby.state_changed.emit(lobby.state)
	await wait_physics_frames(1)
	assert_eq(menu.view, OnlineMenu.View.DETAIL, "the guild tab leads to the room being made")
	lobby.state = LobbyClient.State.IDLE


func test_lobby_names_the_guild_whose_room_it_is() -> void:
	var lobby := LobbyClient.new()
	lobby.reload_world = false
	add_child_autofree(lobby)
	lobby.target_guild_id = GUILD_ID
	assert_eq(lobby.get_guild_room_target(), "", "idle: nothing")
	lobby.state = LobbyClient.State.CONNECTING
	assert_eq(lobby.get_guild_room_target(), GUILD_ID, "while connecting: the guild of its page")
	lobby.state = LobbyClient.State.IN_ROOM
	lobby.room = {"code": "ROOM23", "mode": "quick", "guildId": null, "peers": []}
	assert_eq(lobby.get_guild_room_target(), "", "a quick room belongs to no guild")
	lobby.room = {"code": "ROOM23", "mode": "guild", "guildId": GUILD_ID, "peers": []}
	assert_eq(lobby.get_guild_room_target(), GUILD_ID, "inside: the room's guild")
	lobby.state = LobbyClient.State.IDLE


# --- Was bringt eine Gilde? ---

func test_no_guild_explains_what_a_guild_brings() -> void:
	_fake.answer("GET /me/guilds", 200, {"items": [], "maxGuilds": 5})
	var menu := _open_menu()
	menu.show_view(OnlineMenu.View.GUILDS)
	await wait_physics_frames(2)
	var perks := _node(menu, "GuildPerks")
	assert_not_null(perks, "a short list next to the two big buttons")
	assert_eq(OnlineMenu.PERK_KEYS.size(), 3, "rooms, treasury, leaderboard: only what exists")
	for key in OnlineMenu.PERK_KEYS:
		assert_not_null(_node(perks, "Perk_%s" % String(key).trim_prefix("GUILD_PERK_")))
		assert_false(String(key).contains("FORGE"), "no guild forge promised (MP8)")
	assert_not_null(_node(menu, "CreateGuildBig"))
	assert_not_null(_node(menu, "JoinGuildBig"))


func test_guild_page_has_a_short_info() -> void:
	_answer_guild()
	var menu := await _open_guild_page()
	assert_not_null(_node(menu, "GuildPerksShort"))
	assert_null(_node(menu, "GuildPerks"), "the long version only without a guild")

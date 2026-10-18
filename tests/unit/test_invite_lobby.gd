extends GutTest
## MP2b (D-190): the lobby side of an invite link. LobbyClient remembers the invite until the room
## is entered or the player gives up, waits for a run in progress (room_started) and tries again;
## the online menu shows the invite instead of create/join, every failure as one sentence with a way
## out (Erneut versuchen, Selbst spielen), and in a room "Link kopieren" (phones: "Teilen") next to
## the code; the first free place invites with the link. No network: failing joins are cut short by
## a locked version check (update_required), rooms are a LobbyClient in IN_ROOM with an unconnected
## RelayPeer. Test profile, never the real one.

const PROFILE_PATH := "user://test_invite_lobby_profile.cfg"
const OWN_ID := "6f1c3a52-6a0e-4a3b-9a55-1c2d3e4f5a6b"

var _old_locale := ""
var _old_login := true


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	Loc.apply(&"de")
	_old_login = OnlineMenu.login_on_open
	OnlineMenu.login_on_open = false
	PlayerProfile.path_override = PROFILE_PATH
	PlayerProfile.reset()
	PlayerProfile.current().complete_setup("Kerze", PlayerLook.default_look())


func after_each() -> void:
	OnlineVersionCheck.reset()
	InviteLink.share_override = -1
	LobbyClient.take_launch()
	OnlineMenu.remembered_view = OnlineMenu.View.QUICK


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)
	OnlineMenu.login_on_open = _old_login
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
	PlayerProfile.path_override = ""
	PlayerProfile.reset()
	GameManager.clear_pause_reasons()


func _lobby() -> LobbyClient:
	var lobby := LobbyClient.new()
	lobby.reload_world = false
	add_child_autofree(lobby)
	return lobby


## A lobby on its way to an invite whose last try failed with code.
func _failed_invite(code: String) -> LobbyClient:
	var lobby := _lobby()
	lobby.invite_code = "ABC234"
	lobby.last_error = code
	return lobby


func _room_lobby() -> LobbyClient:
	var lobby := _lobby()
	lobby.state = LobbyClient.State.IN_ROOM
	lobby.room = {"code": "ABCD23", "mode": "quick", "guildId": null, "maxPlayers": 4,
		"peers": [{"peerId": 1, "playerId": OWN_ID, "name": "Kerze", "platform": "pc"}]}
	lobby.peer = RelayPeer.new()
	lobby.peer._unique_id = 1
	return lobby


func _menu(lobby: LobbyClient, width := OnlineMenu.DEFAULT_WIDTH, height := 0.0) -> OnlineMenu:
	var menu := OnlineMenu.create(lobby, null, width, height)
	add_child_autofree(menu)
	return menu


func _node(node: Node, node_name: String) -> Node:
	return node.find_child(node_name, true, false)


func _close_room(lobby: LobbyClient) -> void:
	lobby.peer = null
	lobby.state = LobbyClient.State.IDLE


# --- LobbyClient ---

func test_link_launch_remembers_the_invite() -> void:
	var lobby := _lobby()
	# Locked version: the join stops before any login (no network in unit tests).
	OnlineVersionCheck.last_status = OnlineVersionCheck.Status.OUTDATED
	await lobby.run_launch({"action": LobbyClient.LAUNCH_JOIN, "code": "abc234", "via_link": true})
	assert_true(lobby.has_invite())
	assert_eq(lobby.invite_code, "ABC234")
	assert_eq(lobby.last_error, LobbyClient.ERROR_UPDATE_REQUIRED)
	assert_false(lobby.invite_waiting, "only a run in progress is waited for")
	var typed := _lobby()
	await typed.run_launch({"action": LobbyClient.LAUNCH_JOIN, "code": "ABC234"})
	assert_false(typed.has_invite(), "a typed code is no invite")


func test_run_in_progress_is_waited_for_and_tried_again() -> void:
	var lobby := _lobby()
	lobby.invite_code = "ABC234"
	lobby._fail("room_started")
	assert_true(lobby.invite_waiting, "the group is in the dungeon: wait")
	assert_almost_eq(lobby._invite_retry_left, LobbyClient.INVITE_RETRY_SECONDS, 0.01)
	OnlineVersionCheck.last_status = OnlineVersionCheck.Status.OUTDATED
	lobby._invite_retry_left = 0.05
	await wait_seconds(0.2)
	assert_eq(lobby.last_error, LobbyClient.ERROR_UPDATE_REQUIRED, "tried again by itself")
	assert_false(lobby.invite_waiting, "another failure ends the waiting")
	assert_true(lobby.has_invite(), "the invite stays for Erneut versuchen")


func test_no_retry_without_an_invite_or_after_giving_up() -> void:
	var lobby := _lobby()
	lobby._fail("room_started")
	assert_false(lobby.invite_waiting, "a typed code is not waited for")
	lobby.invite_code = "ABC234"
	lobby._fail("room_started")
	assert_true(lobby.invite_waiting)
	lobby.give_up_invite()
	assert_false(lobby.has_invite(), "Selbst spielen drops it")
	assert_false(lobby.invite_waiting)
	assert_eq(lobby.last_error, "")
	lobby._invite_retry_left = 0.01
	await wait_physics_frames(3)
	assert_eq(lobby.state, LobbyClient.State.IDLE, "nothing is tried any more")


func test_retry_invite_joins_the_invite_again() -> void:
	var lobby := _failed_invite(LobbyClient.ERROR_API_UNREACHABLE)
	OnlineVersionCheck.last_status = OnlineVersionCheck.Status.OUTDATED
	await lobby.retry_invite()
	assert_eq(lobby.last_error, LobbyClient.ERROR_UPDATE_REQUIRED, "a new join of the same room")


# --- Online menu: arrival ---

func test_invite_card_instead_of_create_and_join() -> void:
	var lobby := _failed_invite("")
	lobby.state = LobbyClient.State.LOGGING_IN
	var menu := _menu(lobby)
	await wait_physics_frames(2)
	assert_string_contains((_node(menu, "InviteTitle") as Label).text, "ABC234")
	assert_null(_node(menu, "CreateRoom"), "no create/join for an invite")
	assert_null(_node(menu, "InviteText"), "nothing failed yet")
	assert_not_null(_node(menu, "InviteSolo"), "Selbst spielen also while it connects")
	assert_eq((menu.get_node("Status") as Label).text, "Anmelden …", "the guest login runs in the background")
	lobby.state = LobbyClient.State.IDLE


func test_failures_are_one_sentence_with_a_way_out() -> void:
	var cases := {
		"room_full": ["voll", true],
		"room_not_found": ["abgelaufen", false],
		"version_mismatch": ["Spielversionen", false],
		LobbyClient.ERROR_UPDATE_REQUIRED: ["zu alt", false],
		LobbyClient.ERROR_API_UNREACHABLE: ["nicht erreichbar", true],
		LobbyClient.ERROR_RELAY_UNREACHABLE: ["nicht erreichbar", true],
		LobbyClient.ERROR_TIMEOUT: ["dauert zu lange", true],
		"kicked": ["entfernt", false],
	}
	for code: String in cases:
		var lobby := _failed_invite(code)
		var menu := _menu(lobby)
		await wait_physics_frames(2)
		var text := _node(menu, "InviteText") as Label
		assert_not_null(text, code)
		if text == null:
			continue
		assert_string_contains(text.text, cases[code][0], code)
		assert_eq(text.text.count(". ") + text.text.count("! "), 0, "one sentence: %s" % text.text)
		assert_eq(_node(menu, "InviteRetry") != null, cases[code][1], "Erneut versuchen for %s" % code)
		assert_not_null(_node(menu, "InviteSolo"), "Selbst spielen for %s" % code)
		assert_eq((menu.get_node("Status") as Label).text, "", "not twice (status line) for %s" % code)
		menu.queue_free()
		lobby.queue_free()


func test_run_in_progress_says_the_player_comes_in_after_it() -> void:
	var lobby := _failed_invite("room_started")
	lobby.invite_waiting = true
	lobby._invite_retry_left = 60.0
	var menu := _menu(lobby)
	await wait_physics_frames(2)
	assert_string_contains((_node(menu, "InviteText") as Label).text, "sobald ihr Run endet")
	assert_null(_node(menu, "InviteRetry"), "it tries by itself")
	assert_not_null(_node(menu, "InviteSolo"))


func test_play_solo_drops_the_invite() -> void:
	var lobby := _failed_invite("room_not_found")
	var menu := _menu(lobby)
	await wait_physics_frames(2)
	(_node(menu, "InviteSolo") as Button).pressed.emit()
	await wait_physics_frames(2)
	assert_false(lobby.has_invite())
	assert_not_null(_node(menu, "CreateRoom"), "the ordinary quick game is back")
	assert_null(_node(menu, "InviteTitle"))


func test_closing_the_dialog_stops_waiting() -> void:
	var lobby := _failed_invite("room_started")
	lobby.invite_waiting = true
	# No retry during the test (it would log in for real).
	lobby._invite_retry_left = 60.0
	var menu := _menu(lobby)
	await wait_physics_frames(2)
	remove_child(menu)
	menu.free()
	assert_false(lobby.invite_waiting, "no join behind the player's back")
	assert_false(lobby.has_invite())
	var connecting := _failed_invite("")
	connecting.state = LobbyClient.State.CONNECTING
	var other := _menu(connecting)
	await wait_physics_frames(2)
	remove_child(other)
	other.free()
	assert_true(connecting.has_invite(), "a join on its way goes on")
	connecting.state = LobbyClient.State.IDLE


# --- Online menu: in a room ---

func test_room_offers_the_link_next_to_the_code() -> void:
	var lobby := _room_lobby()
	var menu := _menu(lobby, OnlineMenu.DEFAULT_WIDTH, OnlineMenu.VILLAGE_CONTENT_HEIGHT)
	await wait_physics_frames(2)
	var row := _node(menu, "RoomCodeRow") as Control
	assert_not_null(row)
	assert_eq((_node(row, "RoomCodeLabel") as Label).text, "ABCD23", "the code stays visible")
	assert_not_null(_node(row, "CopyRoomCode"), "the code can still be copied")
	var link := _node(row, "CopyLink") as Button
	assert_not_null(link, "Link kopieren")
	assert_null(_node(row, "ShareLink"), "no share sheet on a PC")
	assert_eq(tr(link.text), "Link kopieren")
	assert_lte(row.get_combined_minimum_size().x, UiKit.px(OnlineMenu.DEFAULT_WIDTH) + 0.5, "fits the village dialog")
	assert_eq(menu.get_invite_url(), InviteLink.for_room("ABCD23"))
	assert_eq(InviteLink.parse(menu.get_invite_url()), "ABCD23", "the link reads back")
	link.pressed.emit()
	await wait_physics_frames(1)
	if DisplayServer.get_name() != "headless":
		assert_eq(DisplayServer.clipboard_get(), menu.get_invite_url())
	assert_eq(link.text, "Kopiert!", "the button says it worked")
	assert_string_contains((menu.get_node("Status") as Label).text, "Link kopiert")
	var share := _node(menu, "ShareCode") as Button
	assert_not_null(share, "the first free place invites")
	assert_eq(tr(share.text), "Einladen")
	_close_room(lobby)


func test_phones_share_the_link() -> void:
	InviteLink.share_override = 1
	var lobby := _room_lobby()
	var menu := _menu(lobby, OnlineMenu.DEFAULT_WIDTH, OnlineMenu.VILLAGE_CONTENT_HEIGHT)
	await wait_physics_frames(2)
	var share := _node(menu, "ShareLink") as Button
	assert_not_null(share, "Teilen on phones")
	assert_eq(tr(share.text), "Teilen")
	assert_null(_node(menu, "CopyLink"))
	assert_not_null(_node(menu, "RoomCodeLabel"), "the code stays next to it")
	_close_room(lobby)


func test_guild_room_without_code_has_no_link() -> void:
	var lobby := _room_lobby()
	lobby.room["mode"] = LobbyClient.MODE_GUILD
	lobby.room["guildId"] = "11111111-2222-4333-8444-555555555555"
	var menu := _menu(lobby)
	await wait_physics_frames(2)
	assert_null(_node(menu, "CopyLink"), "guild rooms are joined from the guild's page (b47bee4a)")
	_close_room(lobby)

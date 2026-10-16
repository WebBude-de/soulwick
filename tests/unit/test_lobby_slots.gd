extends GutTest
## D-152: the room dialog shows one designed place per player (LobbySlot): own place gold with
## "Aussehen ändern", host crown, status, ping bars, free places "Wartet auf Spieler …" with
## "Code teilen"; "Aussehen ändern" opens the profile editor in the menu and Esc leads back. No
## network: a LobbyClient in the IN_ROOM state with a RelayPeer that is not connected. Test profile.

const PROFILE_PATH := "user://test_lobby_slots_profile.cfg"
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
	PlayerProfile.current().complete_setup("Kerze", PlayerLook.default_look(&"frost"))


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)
	OnlineMenu.login_on_open = _old_login
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
	PlayerProfile.path_override = ""
	PlayerProfile.reset()
	GameManager.clear_pause_reasons()


func _room_lobby(peers: Array) -> LobbyClient:
	var lobby := LobbyClient.new()
	lobby.reload_world = false
	add_child_autofree(lobby)
	lobby.state = LobbyClient.State.IN_ROOM
	lobby.room = {"code": "ABCD23", "mode": "quick", "guildId": null, "maxPlayers": 4, "peers": peers}
	lobby.peer = RelayPeer.new()
	lobby.peer._unique_id = 1
	return lobby


func _menu(lobby: LobbyClient) -> OnlineMenu:
	var menu := OnlineMenu.create(lobby, null)
	add_child_autofree(menu)
	return menu


func test_places_for_players_and_free_places() -> void:
	var lobby := _room_lobby([
		{"peerId": 1, "playerId": OWN_ID, "name": "Kerze", "platform": "pc"},
		{"peerId": 2, "playerId": "p-2", "name": "Docht", "platform": "android"},
	])
	var menu := _menu(lobby)
	await wait_physics_frames(2)
	var slots := menu.get_slots()
	assert_eq(slots.size(), 4, "one place per room seat")
	var own := slots[0]
	assert_true(own.is_own and own.is_host)
	assert_not_null(own.find_child("HostCrown", true, false), "the host wears the crown")
	assert_not_null(own.find_child("EditLook", true, false), "own place: Aussehen ändern")
	assert_eq((own.find_child("PlayerName", true, false) as Label).text, "Kerze")
	assert_eq((own.find_child("StatusText", true, false) as Label).text, "LOBBY_SLOT_CONNECTING", "no player in this world yet")
	var other := slots[1]
	assert_false(other.is_own or other.is_host)
	assert_null(other.find_child("EditLook", true, false), "only the own look can be changed")
	assert_eq(other.tooltip_text, "Android")
	assert_true(slots[2].is_empty)
	assert_not_null(slots[2].find_child("ShareCode", true, false), "the first free place offers the code")
	assert_null(slots[3].find_child("ShareCode", true, false), "only once")
	for slot in slots:
		assert_almost_eq(slot.get_combined_minimum_size().x, slots[0].get_combined_minimum_size().x, 1.0, "all places equally wide")
	lobby.peer = null
	lobby.state = LobbyClient.State.IDLE


func test_ping_bars() -> void:
	assert_eq(LobbySlot.ping_quality(-1), &"bad")
	assert_eq(LobbySlot.ping_quality(30), &"good")
	assert_eq(LobbySlot.ping_quality(LobbySlot.PING_GOOD_MS), &"mid")
	assert_eq(LobbySlot.ping_quality(400), &"bad")
	var slot := LobbySlot.create_player(0, "Kerze", PlayerLook.default_look(), true, true, LobbySlot.Status.READY, 42, 62.0)
	add_child_autofree(slot)
	assert_eq((slot.find_child("PingText", true, false) as Label).text, "42")
	assert_not_null(slot.find_child("ReadyTick", true, false))
	slot.set_ping(-1)
	assert_eq((slot.find_child("PingText", true, false) as Label).text, "–")


func test_change_look_opens_the_editor_and_esc_goes_back() -> void:
	var lobby := _room_lobby([{"peerId": 1, "playerId": OWN_ID, "name": "Kerze", "platform": "pc"}])
	var menu := _menu(lobby)
	await wait_physics_frames(2)
	(menu.find_child("EditLook", true, false) as Button).pressed.emit()
	await wait_physics_frames(2)
	assert_eq(menu.view, OnlineMenu.View.PROFILE)
	var editor := menu.get_profile_editor()
	assert_not_null(editor, "the same editor as everywhere")
	assert_eq(editor.get_player_name(), "Kerze")
	assert_eq(menu.get_tab(), OnlineMenu.View.QUICK, "still the quick game tab")
	# A player joining meanwhile must not throw the editor away.
	lobby.room["peers"] = lobby.get_room_peers() + [{"peerId": 2, "playerId": "p-2", "name": "Docht", "platform": "pc"}]
	lobby.room_changed.emit(lobby.room)
	await wait_physics_frames(2)
	assert_eq(menu.get_profile_editor(), editor, "editor kept")
	editor._set_row(ProfileEditor.Row.FIGURE)
	assert_true(menu.handle_input(MenuInput.key_event(KEY_RIGHT)), "keys go to the editor")
	assert_eq(PlayerLook.get_character(editor.get_look()), &"wick", "frost -> wick")
	assert_true(menu.handle_input(MenuInput.key_event(KEY_ESCAPE)))
	await wait_physics_frames(2)
	assert_eq(menu.view, OnlineMenu.View.QUICK, "Esc: back to the room")
	assert_eq(PlayerLook.get_character(PlayerProfile.current().look), &"frost", "nothing saved")
	assert_eq(menu.get_slots().size(), 4)
	lobby.peer = null
	lobby.state = LobbyClient.State.IDLE

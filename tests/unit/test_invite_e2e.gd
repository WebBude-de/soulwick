extends GutTest
## MP2b (D-190), optional end to end: "Link lesen → Beitritt" against a running soulwick-api and
## soulwick-relay. A host (bare RelayPeer, dev login) opens a quick room; its link is read back like
## the browser shell hands it over ("-- room=<link>") and a LobbyClient joins it as an invite. Then
## the host starts a run: the invite waits (room_started) and gets in by itself once the host ends
## it; a link to a closed room says "abgelaufen". Skipped (pending) unless the environment names the
## services, e.g. in Bash:
##   SOULWICK_TEST_API=http://localhost:3102 SOULWICK_TEST_RELAY=ws://localhost:3103/v1 \
##   SOULWICK_TEST_DEV_KEY=<DEV_AUTH_KEY> godot --headless --audio-driver Dummy --path . \
##   -s addons/gut/gut_cmdln.gd -gselect=test_invite_e2e -gexit
## Own online files (two test accounts), never the real online.cfg or a save slot.

const HOST_PATH := "user://test_invite_e2e_host.cfg"
const GUEST_PATH := "user://test_invite_e2e_guest.cfg"
## Seconds per step (TESTWERT; a busy machine needs a while for login and relay).
const STEP_TIMEOUT := 15.0

var _api := ""
var _relay := ""
var _dev_key := ""
var _host_peer: RelayPeer = null
var _host_room: Dictionary = {}
var _old_locale := ""


func before_all() -> void:
	_api = OS.get_environment("SOULWICK_TEST_API")
	_relay = OS.get_environment("SOULWICK_TEST_RELAY")
	_dev_key = OS.get_environment("SOULWICK_TEST_DEV_KEY")
	_old_locale = TranslationServer.get_locale()
	Loc.apply(&"de")


func after_each() -> void:
	if _host_peer != null:
		_host_peer.close()
		_host_peer = null
	OnlineVersionCheck.reset()
	LobbyClient.take_launch()


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)
	for path in [HOST_PATH, GUEST_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _process(_delta: float) -> void:
	# The host's peer is nobody's multiplayer peer: polled here.
	if _host_peer != null:
		_host_peer.poll()


func _session(path: String, player_name: String) -> OnlineSession:
	var config := OnlineConfig.new()
	config.path = path
	config.settings_path = path
	config.load_from({"api": _api, "relay": _relay, "dev_key": _dev_key, "name": player_name})
	var session := OnlineSession.new(config)
	add_child_autofree(session)
	return session


func _wait_for(check: Callable, seconds := STEP_TIMEOUT) -> bool:
	var left := seconds
	while left > 0.0:
		if check.call():
			return true
		await wait_physics_frames(1)
		left -= get_physics_process_delta_time()
	return bool(check.call())


## Opens a quick room as host; the code or "" (the reason is asserted).
func _host_room_code() -> String:
	var host := _session(HOST_PATH, "GUT Host")
	var login := await host.ensure_login()
	if not login.ok:
		fail_test("host login: " + login.describe())
		return ""
	var token := await host.ensure_relay_token()
	if not token.ok:
		fail_test("host relay token: " + token.describe())
		return ""
	_host_peer = RelayPeer.new()
	_host_room = {}
	_host_peer.room_entered.connect(func(room: Dictionary, _peer_id: int) -> void: _host_room = room)
	_host_peer.room_updated.connect(func(room: Dictionary) -> void: _host_room = room)
	var hello := RelayProtocol.hello(host.relay_token, OnlineConfig.PROTOCOL_VERSION, OnlineConfig.get_game_version(), OnlineConfig.get_platform())
	var url := RelayProtocol.prefer_ipv4_loopback(RelayProtocol.with_ws_path(host.get_relay_url()))
	assert_eq(_host_peer.open(url, hello, RelayProtocol.create(LobbyClient.MODE_QUICK)), OK)
	var entered := await _wait_for(func() -> bool: return not _host_room.is_empty())
	assert_true(entered, "the host is in a room")
	return str(_host_room.get("code", ""))


func _guest_lobby() -> LobbyClient:
	var lobby := LobbyClient.new()
	lobby.reload_world = false
	lobby._session = _session(GUEST_PATH, "GUT Gast")
	add_child_autofree(lobby)
	return lobby


## The shell hands the code over as "-- room=<code>"; here the whole link goes through the same path.
func _arrive(lobby: LobbyClient, link: String) -> void:
	var code := InviteLink.code_from_args(PackedStringArray(["room=" + link]))
	LobbyClient.request_launch(LobbyClient.LAUNCH_JOIN, LobbyClient.MODE_QUICK, "", "", code, "", true)
	lobby.run_launch(LobbyClient.take_launch())


func _skip() -> bool:
	if _api.is_empty() or _relay.is_empty() or _dev_key.is_empty():
		pending("SOULWICK_TEST_API / SOULWICK_TEST_RELAY / SOULWICK_TEST_DEV_KEY not set")
		return true
	return false


func test_link_read_and_join_then_wait_for_a_run() -> void:
	if _skip():
		return
	var code := await _host_room_code()
	if code.is_empty():
		return
	var link := InviteLink.for_room(code, OnlineConfig.ENV_DEVELOPMENT)
	assert_eq(InviteLink.parse(link), code, "the link carries the room code")
	var lobby := _guest_lobby()
	_arrive(lobby, link)
	assert_eq(lobby.invite_code, code)
	var joined := await _wait_for(lobby.is_in_room)
	assert_true(joined, "in the host's lobby by the link alone (%s)" % lobby.last_error)
	if not joined:
		return
	assert_eq(lobby.get_room_code(), code)
	assert_false(lobby.has_invite(), "the invite is done once inside")
	assert_eq(lobby.get_room_peers().size(), 2, "host and guest")
	lobby.leave()
	assert_true(await _wait_for(func() -> bool: return lobby.state == LobbyClient.State.IDLE), "left")
	assert_true(await _wait_for(func() -> bool: return _host_room.get("peers", []).size() == 1), "the host is alone again")

	# The group goes into the dungeon: the link waits and gets in once the run ends.
	assert_eq(_host_peer.start(), OK)
	assert_true(await _wait_for(func() -> bool: return bool(_host_room.get("started", false))), "the run started")
	_arrive(lobby, link)
	assert_true(await _wait_for(func() -> bool: return lobby.invite_waiting), "room_started: waiting (%s)" % lobby.last_error)
	assert_eq(lobby.last_error, "room_started")
	assert_false(lobby.is_in_room())
	lobby._invite_retry_left = 1.0
	assert_eq(_host_peer.end_run(RelayProtocol.RUN_END_PORTAL), OK)
	var back := await _wait_for(lobby.is_in_room, LobbyClient.INVITE_RETRY_SECONDS + STEP_TIMEOUT)
	assert_true(back, "in the village once the run ended (%s)" % lobby.last_error)
	assert_false(lobby.invite_waiting)
	lobby.leave()
	await _wait_for(func() -> bool: return lobby.state == LobbyClient.State.IDLE)

	# The host closes the room: the old link has expired.
	_host_peer.leave()
	await wait_seconds(0.5)
	_arrive(lobby, link)
	assert_true(await _wait_for(func() -> bool: return not lobby.last_error.is_empty() and lobby.state == LobbyClient.State.IDLE),
			"the join fails")
	assert_eq(lobby.last_error, "room_not_found")
	assert_string_contains(InviteLink.error_text(lobby.last_error), "abgelaufen")
	assert_false(InviteLink.can_retry(lobby.last_error), "only Selbst spielen")
	assert_true(lobby.has_invite(), "the card stays until Selbst spielen")

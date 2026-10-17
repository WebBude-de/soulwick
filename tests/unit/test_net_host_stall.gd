extends GutTest
## Host stall (bug of 17.10.2026, D-183): the host's browser tab went into the background, its game
## stood still, and every client was pulled back again and again and could not move. Checked here:
## HostStall (thresholds, hysteresis), RelayPeer's silence of the host (game frames only, pongs and
## an own hang do not count, the host's own long gap), NetPlayerState (no rubber band while the host
## stands still, no input pile-up, other players stand, smooth resume, the host stops a silent
## client's player), the notice, the texts and the browser keep-alive outside a browser.
## Follow-up of 17.10.2026: the host's beats (a host that sends no world data on purpose at a world
## change is no stalled host, a slow world change on either side neither, a stopped host still is),
## and the host's clock for the clients' input (its own hitch does not stop its teammates).

const FakeSocket = preload("res://tests/unit/test_relay_peer.gd").FakeSocket
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const TEST_SAVE_PATH := "user://test_net_host_stall.cfg"
const CLIENT_PEER := 2
const POLL_MSEC := 16
## Real milliseconds may pass between two polls of a test (the peer's clock is real time + offset).
const CLOCK_SLACK := 40
const ROOM := {"code": "ABCD23", "mode": "quick", "guildId": null, "hostPeerId": 1, "started": true, "maxPlayers": 4, "gameVersion": "0.9.0", "peers": [{"peerId": 1, "playerId": "p1", "name": "Host", "platform": "windows"}, {"peerId": 2, "playerId": "p2", "name": "Gast", "platform": "windows"}], "expiresAt": null}
const ROOM_ALONE := {"code": "ABCD23", "mode": "quick", "guildId": null, "hostPeerId": 1, "started": false, "maxPlayers": 4, "gameVersion": "0.9.0", "peers": [{"peerId": 1, "playerId": "p1", "name": "Host", "platform": "windows"}], "expiresAt": null}
const TEXT_KEYS: Array[StringName] = [&"NET_HOST_STALL_TITLE", &"NET_HOST_STALL_SUB", &"NET_HOST_STALL_SECONDS",
	&"NET_HOST_AWAY_TITLE", &"NET_HOST_AWAY", &"NET_HOST_AWAY_WEB", &"LOBBY_WEB_HOST_HINT_TITLE",
	&"LOBBY_WEB_HOST_HINT", &"LOBBY_LEAVE"]

var _old_save_path: String
var _socket: FakeSocket
var _peer: RelayPeer
var _frame_number := 0
## A host for _peer as its client (_pair), and the longest host stall _peer showed meanwhile.
var _host_socket: FakeSocket = null
var _host: RelayPeer = null
var _max_stall := 0


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.load_game()


func before_each() -> void:
	_socket = FakeSocket.new()
	_peer = RelayPeer.new()
	_peer.socket = _socket
	_frame_number = 0
	_host_socket = null
	_host = null
	_max_stall = 0


func after_all() -> void:
	await wait_seconds(0.3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


# --- HostStall (pure logic) ---

## Polls every POLL_MSEC for duration_msec; the host sends a frame every host_every ms (0 = never).
## Returns the new time; box.last_frame is the time of the host's last frame.
func _run(stall: HostStall, now: int, duration_msec: int, host_every: int, box: Dictionary) -> int:
	var end := now + duration_msec
	while now < end:
		now += POLL_MSEC
		if host_every > 0 and now - int(box.last_frame) >= host_every:
			box.last_frame = now
		stall.update(now - int(box.last_frame), now)
	return now


func test_a_running_host_never_stalls() -> void:
	var stall := HostStall.new()
	var box := {"last_frame": 0}
	_run(stall, 0, 5000, POLL_MSEC, box)
	assert_false(stall.stalled)
	assert_eq(stall.stall_count, 0)
	# A late packet now and then (jitter below STALL_MSEC) changes nothing either.
	_run(stall, 5000, 2000, 250, box)
	assert_false(stall.stalled, "250 ms gaps are jitter, no stall")


func test_stall_and_resume_with_hysteresis() -> void:
	var stall := HostStall.new()
	var box := {"last_frame": 0}
	var now := _run(stall, 0, 1000, POLL_MSEC, box)
	now = _run(stall, now, HostStall.STALL_MSEC - POLL_MSEC * 2, 0, box)
	assert_false(stall.stalled, "not before STALL_MSEC")
	now = _run(stall, now, POLL_MSEC * 3, 0, box)
	assert_true(stall.stalled, "stalled from STALL_MSEC on")
	assert_eq(stall.since_msec, int(box.last_frame), "measured from the host's last frame")
	assert_eq(stall.stall_count, 1)
	# A host in a throttled tab: one frame a second keeps the clients waiting, no flicker.
	now = _run(stall, now, 5000, 1000, box)
	assert_true(stall.stalled, "a host ticking once a second stays stalled")
	assert_eq(stall.stall_count, 1, "no stall/resume flicker")
	assert_false(stall.shows_notice(stall.since_msec + HostStall.NOTICE_MSEC - 1))
	assert_true(stall.shows_notice(stall.since_msec + HostStall.NOTICE_MSEC))
	assert_false(stall.offers_leave(stall.since_msec + HostStall.LEAVE_MSEC - 1))
	assert_true(stall.offers_leave(stall.since_msec + HostStall.LEAVE_MSEC))
	# Back at full rate: free again after RESUME_MSEC of steady frames.
	var resumed_at := -1
	var start := now
	while now < start + 2000 and resumed_at < 0:
		now = _run(stall, now, POLL_MSEC, POLL_MSEC, box)
		if not stall.stalled:
			resumed_at = now
	assert_true(resumed_at > 0, "the stall ends")
	assert_between(resumed_at - start, HostStall.RESUME_MSEC, HostStall.RESUME_MSEC + POLL_MSEC * 3, "after RESUME_MSEC of frames")
	assert_true(stall.longest_msec >= 5000, "longest stall %d ms" % stall.longest_msec)
	assert_eq(stall.stall_msec(now), 0)


# --- RelayPeer: the host's silence ---

func _welcome(action: Dictionary) -> void:
	_peer.open("ws://relay.test/v1", RelayProtocol.hello("tok", 1, "0.9.0", "windows"), action)
	_socket.ready_state = WebSocketPeer.STATE_OPEN
	_peer.poll()
	_socket.push_text({"type": "welcome", "playerId": "p2", "name": "Gast", "protocolVersion": 1, "maxFrameBytes": 65536, "maxPlayers": 4, "clientRouting": "host_only"})
	_peer.poll()


func _join_as_client() -> void:
	_welcome(RelayProtocol.join("ABCD23"))
	_socket.push_text({"type": "joined", "code": "ABCD23", "peerId": CLIENT_PEER, "room": ROOM})
	_peer.set_delivering(true)
	_peer.poll()
	assert_true(_peer.is_in_room())


func _create_as_host(room: Dictionary) -> void:
	_welcome(RelayProtocol.create("quick"))
	_socket.push_text({"type": "created", "code": "ABCD23", "peerId": 1, "room": room})
	_peer.set_delivering(true)
	_peer.poll()
	assert_true(_peer.is_in_room() and _peer.is_host())


func _advance(msec: int) -> void:
	_peer.time_offset_msec += msec


## One client poll after msec; with_host_frame: a game frame of the host arrived meanwhile.
func _poll_after(msec: int, with_host_frame: bool) -> void:
	_advance(msec)
	if with_host_frame:
		_frame_number += 1
		_socket.push_binary(RelayProtocol.encode_frame(1, CLIENT_PEER, 0, 2, PackedByteArray([_frame_number % 256])))
	_peer.poll()


func test_client_measures_the_hosts_game_frames_only() -> void:
	_join_as_client()
	for i in 30:
		_poll_after(POLL_MSEC, true)
	assert_eq(_peer.get_host_silence_msec(), 0)
	assert_false(_peer.is_host_stalled())
	# The host's tab goes into the background: no game frames, the relay keeps answering pings.
	var before := HostStall.STALL_MSEC - 100
	_poll_after(before, false)
	assert_almost_eq(_peer.get_host_silence_msec(), before, CLOCK_SLACK)
	assert_false(_peer.is_host_stalled(), "not yet")
	_socket.push_text({"type": "pong", "t": _peer.time_offset_msec})
	_poll_after(200, false)
	assert_almost_eq(_peer.get_host_silence_msec(), before + 200, CLOCK_SLACK, "a pong of the relay is no sign of the host")
	assert_true(_peer.is_host_stalled())
	_poll_after(HostStall.NOTICE_MSEC, false)
	assert_true(_peer.get_host_stall_msec() >= HostStall.NOTICE_MSEC)
	assert_eq(_peer.diagnostics.totals.host_stalls, 1)
	# The host is back.
	for i in 30:
		_poll_after(POLL_MSEC, true)
	assert_false(_peer.is_host_stalled(), "free again with the host's frames")
	assert_eq(_peer.get_host_stall_msec(), 0)
	assert_true(_peer.diagnostics.longest_host_stall_msec >= HostStall.NOTICE_MSEC)


func test_an_own_hang_is_no_host_stall() -> void:
	_join_as_client()
	for i in 10:
		_poll_after(POLL_MSEC, true)
	# This machine hung for 2 s (loading, a slow frame); the host's frames waited in the socket.
	_poll_after(2000, true)
	assert_eq(_peer.get_host_silence_msec(), 0, "the waiting frames are read first")
	assert_false(_peer.is_host_stalled())
	assert_eq(_peer.diagnostics.totals.host_stalls, 0)


func test_the_host_measures_no_silence_but_its_own_gap() -> void:
	_create_as_host(ROOM)
	var gaps: Array = []
	_peer.host_hitched.connect(func(gap: int) -> void: gaps.append(gap))
	_peer.poll()
	_advance(5000)
	_peer.poll()
	assert_eq(_peer.get_host_silence_msec(), 0, "the host never waits for itself")
	assert_false(_peer.is_host_stalled())
	assert_eq(gaps.size(), 1, "its own 5 s gap with a teammate in the room is reported")
	assert_almost_eq(int(gaps[0]) if not gaps.is_empty() else 0, 5000, CLOCK_SLACK)
	assert_eq(_peer.host_away_count, 1)
	_advance(HostStall.HOST_AWAY_NOTICE_MSEC - 200)
	_peer.poll()
	assert_eq(gaps.size(), 1, "shorter gaps are no news")
	_peer.forgive_hitch()
	_advance(4000)
	_peer.poll()
	assert_eq(gaps.size(), 1, "a world loaded on purpose (forgive_hitch) is no hang")
	assert_eq(_peer.diagnostics.totals.host_away, 1)


func test_a_lonely_host_is_not_told() -> void:
	_create_as_host(ROOM_ALONE)
	var gaps: Array = []
	_peer.host_hitched.connect(func(gap: int) -> void: gaps.append(gap))
	_peer.poll()
	_advance(5000)
	_peer.poll()
	assert_eq(gaps, [], "nobody waited")
	assert_eq(_peer.beats_sent, 0, "no beats without teammates")


# --- Beats: a running host is never silent (follow-up of 17.10.2026) ---

## Beats among the frames the test host (_peer) sent: [{from, to, channel, mode, data}].
func _sent_beats() -> Array:
	var result: Array = []
	for bytes in _socket.sent_binary:
		var frame := RelayProtocol.decode_frame(bytes)
		if int(frame.channel) == RelayProtocol.CAPS_CHANNEL and RelayProtocol.is_beat(frame.data):
			result.append(frame)
	return result


func test_the_host_beats_to_every_peer_it_sends_nothing_else() -> void:
	_create_as_host(ROOM)
	_peer.poll()
	assert_eq(_sent_beats().size(), 0, "a peer that just came up got its capability frame")
	_advance(HostStall.BEAT_MSEC)
	_peer.poll()
	var beats := _sent_beats()
	assert_eq(beats.size(), 1, "a beat after BEAT_MSEC without anything else")
	assert_eq(int(beats[0].to), CLIENT_PEER)
	assert_eq(int(beats[0].mode), RelayProtocol.MODE_UNRELIABLE, "the next beat replaces a lost one")
	assert_eq(RelayProtocol.beat_flags(beats[0].data), 0)
	# World data counts as a sign of life: no beats while it flows.
	_peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	for i in 20:
		_advance(POLL_MSEC)
		_peer.set_target_peer(0)
		_peer.put_packet(PackedByteArray([i]))
		_peer.poll()
	assert_eq(_sent_beats().size(), 1, "no beat while world data flows")
	_advance(HostStall.BEAT_MSEC)
	_peer.poll()
	assert_eq(_sent_beats().size(), 2)
	# Before a world load of its own: one reliable beat with BEAT_LOADING to everybody at once.
	_peer.announce_loading()
	beats = _sent_beats()
	assert_eq(beats.size(), 3)
	assert_eq(int(beats[2].mode), RelayProtocol.MODE_RELIABLE)
	assert_eq(RelayProtocol.beat_flags(beats[2].data) & RelayProtocol.BEAT_LOADING, RelayProtocol.BEAT_LOADING)
	# Older builds: no capability frame, SceneMultiplayer's RAW command first (unused peer_packet).
	assert_false(RelayProtocol.is_caps(beats[2].data))
	assert_false(RelayProtocol.is_beat(RelayProtocol.caps_payload()))
	assert_eq(int(beats[2].data[0]), 3)
	# The host polls on as usual: nothing for itself, it never waits for itself.
	assert_false(_peer.is_host_loading())
	assert_eq(_peer.get_host_silence_msec(), 0)


## A host RelayPeer and this test's client (_peer) in one room; _step plays both machines and the
## relay between them (host -> client).
func _pair() -> void:
	_host_socket = FakeSocket.new()
	_host = RelayPeer.new()
	_host.socket = _host_socket
	_host.open("ws://relay.test/v1", RelayProtocol.hello("tok", 1, "0.9.0", "windows"), RelayProtocol.create("quick"))
	_host_socket.ready_state = WebSocketPeer.STATE_OPEN
	_host.poll()
	_host_socket.push_text({"type": "welcome", "playerId": "p1", "name": "Host", "protocolVersion": 1, "maxFrameBytes": 65536, "maxPlayers": 4, "clientRouting": "host_only"})
	_host.poll()
	_host_socket.push_text({"type": "created", "code": "ABCD23", "peerId": 1, "room": ROOM})
	_host.set_delivering(true)
	_host.poll()
	_join_as_client()
	_host.time_offset_msec = _peer.time_offset_msec
	_pass_on()
	_peer.poll()


## The relay: the host's frames for the client land in the client's socket.
func _pass_on() -> void:
	for bytes in _host_socket.sent_binary:
		var to := int(RelayProtocol.decode_frame(bytes).to)
		if to == CLIENT_PEER or (to <= 0 and to != -CLIENT_PEER):
			_socket.push_binary(bytes)
	_host_socket.sent_binary.clear()


## msec pass on both machines. host_runs: the host's game polls (and sends world_data to the client
## first); client_runs: the client polls (else it hangs, its frames wait in the socket).
func _step(msec: int, host_runs: bool, world_data: bool, client_runs := true) -> void:
	_advance(msec)
	_host.time_offset_msec += msec
	if host_runs:
		if world_data:
			_host.set_target_peer(CLIENT_PEER)
			_host.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
			_host.put_packet(PackedByteArray([7]))
		_host.poll()
	_pass_on()
	if client_runs:
		_peer.poll()
		_max_stall = maxi(_max_stall, _peer.get_host_stall_msec())


func _drain() -> void:
	while _peer.get_available_packet_count() > 0:
		_peer.get_packet()


func test_hide_from_peers_and_a_slow_world_change_produce_no_stall() -> void:
	_pair()
	for i in 30:
		_step(POLL_MSEC, true, true)
	_drain()
	assert_false(_peer.is_host_stalled())
	# Run start or end (NetPlayers.hide_from_peers, NetDungeon run_over): the host sends this client
	# nothing of its world until the client has loaded the new one, here for 3 s. Only beats come.
	var beats_before := _host.beats_sent
	for i in 3000 / POLL_MSEC:
		_step(POLL_MSEC, true, false)
	assert_between(_host.beats_sent - beats_before, 3000 / (HostStall.BEAT_MSEC + POLL_MSEC), 3000 / HostStall.BEAT_MSEC + 2, "a beat about every BEAT_MSEC")
	assert_eq(_peer.get_available_packet_count(), 0, "beats never reach SceneMultiplayer")
	assert_true(_peer.get_host_silence_msec() < HostStall.STALL_MSEC)
	assert_false(_peer.is_host_stalled(), "a host that sends no world data on purpose is no stalled host")
	# The client loads its new world slowly: 2.5 s without a poll, the host's beats wait in its socket.
	for i in 2500 / POLL_MSEC:
		_step(POLL_MSEC, true, false, false)
	_peer.poll()
	assert_false(_peer.is_host_stalled(), "after an own slow load the waiting beats count")
	# The host loads its world (LobbyClient.configure_world): it announces it, then its frame takes 3 s.
	_host.announce_loading()
	_pass_on()
	_peer.poll()
	for i in 3000 / POLL_MSEC:
		_step(POLL_MSEC, false, false)
	assert_true(_peer.is_host_loading())
	assert_true(_peer.get_host_silence_msec() >= 2900, "the host really was silent")
	assert_false(_peer.is_host_stalled(), "a world load the host announced is no stall")
	# The host's first frame afterwards ends the grace (LobbyClient.attach_world forgives its own gap).
	_host.forgive_hitch()
	_step(POLL_MSEC, true, false)
	assert_false(_peer.is_host_loading())
	for i in 30:
		_step(POLL_MSEC, true, true)
	assert_false(_peer.is_host_stalled())
	assert_eq(_peer.diagnostics.totals.host_stalls, 0, "no stall in the whole world change")
	assert_eq(_max_stall, 0, "no \"Warte auf den Host …\" at any time")
	assert_eq(_host.host_away_count, 0, "the host is not told the others waited")


func test_a_stopped_host_is_still_noticed_and_its_beats_end_the_stall() -> void:
	_pair()
	# The village between runs: no world data for this client, beats only.
	for i in 30:
		_step(POLL_MSEC, true, false)
	assert_false(_peer.is_host_stalled())
	# The host's tab goes into the background without the keep-alive: no poll, no beat.
	for i in HostStall.STALL_MSEC / POLL_MSEC + 2:
		_step(POLL_MSEC, false, false)
	assert_true(_peer.is_host_stalled(), "no beats: the host stands still")
	# Back: its beats alone end the stall (gaps below RESUME_GAP_MSEC).
	for i in (HostStall.RESUME_MSEC + 200) / POLL_MSEC:
		_step(POLL_MSEC, true, false)
	assert_false(_peer.is_host_stalled(), "beats alone end the stall")
	assert_eq(_peer.diagnostics.totals.host_stalls, 1)
	# A load announcement does not hide a host that never comes back: the grace has an end.
	_host.announce_loading()
	_pass_on()
	_peer.poll()
	_step(HostStall.LOAD_GRACE_MSEC - 200, false, false)
	assert_false(_peer.is_host_stalled(), "within the grace")
	_step(400, false, false)
	assert_true(_peer.is_host_stalled(), "after LOAD_GRACE_MSEC")
	assert_true(_peer.get_host_stall_msec() >= HostStall.LOAD_GRACE_MSEC, "counted from the announcement, the notice shows at once")


# --- NetPlayerState ---

## A player driven by RemoteInput (the keyboard of its machine or the network), with a NetState.
func _player(local: bool, peer := CLIENT_PEER) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.input = RemoteInput.new()
	player.is_local = local
	player.add_child(NetPlayerState.create(peer, Vector2.ZERO))
	add_child_autofree(player)
	return player


func _state(player: Player) -> NetPlayerState:
	return player.get_node(NodePath(NetPlayerState.NODE_NAME)) as NetPlayerState


func _keys(player: Player) -> RemoteInput:
	return player.input as RemoteInput


## The own player on a client holds "right" for seconds while the host's position of it stays at
## the start (its game stands still). The host's stall is noticed at stall_frame (-1 = never, as
## before the fix). Movement is applied here (the player's own physics is not stepped).
func _walk_against_frozen_host(player: Player, seconds: float, stall_frame: int) -> void:
	var state := _state(player)
	state.pos = Vector2.ZERO
	_keys(player).set_move(Vector2.RIGHT)
	for frame in int(seconds * 60.0):
		if frame == stall_frame:
			state.set_host_stalled(true)
		if not player.is_input_locked():
			player.position.x += player.move_speed / 60.0
		state.call(&"_correct_self", 1.0 / 60.0, int(frame * 1000.0 / 60.0))


func test_without_stall_detection_the_own_player_is_pulled_back() -> void:
	# The bug as it was: the own player walks on, the frozen host position drops out of its history
	# after a second and pulls it back, again and again.
	var player := _player(true)
	_walk_against_frozen_host(player, 5.0, -1)
	var state := _state(player)
	assert_true(state.snap_count >= 2, "pulled back %d times" % state.snap_count)
	assert_true(player.position.x < player.move_speed * 5.0 * 0.5, "got only %.0f px of %.0f" % [player.position.x, player.move_speed * 5.0])


func test_no_rubber_band_while_the_host_stands_still() -> void:
	var player := _player(true)
	var state := _state(player)
	var stall_frame := int(HostStall.STALL_MSEC * 60.0 / 1000.0)
	_walk_against_frozen_host(player, 5.0, stall_frame)
	assert_eq(state.snap_count, 0, "no correction in 5 s")
	assert_true(player.is_input_locked(), "the own player waits (own lock, no pause)")
	assert_eq(state.stall_count, 1)
	assert_almost_eq(player.position.x, 0.0, 1.0, "it glided once to the host's position and stays there")
	assert_false(get_tree().paused, "no global pause")


func test_smooth_resume_after_the_stall() -> void:
	var player := _player(true)
	var state := _state(player)
	_walk_against_frozen_host(player, 3.0, 18)
	state.set_host_stalled(false)
	assert_false(player.is_input_locked(), "free as soon as the host's game runs")
	assert_eq(state.next_input()[0], Vector2.RIGHT, "the current input leaves at once")
	# The host follows 100 ms behind (one round trip): no correction while walking on.
	var trail: Array[Vector2] = []
	var start_msec := 3000
	for frame in 120:
		player.position.x += player.move_speed / 60.0
		trail.append(player.position)
		state.pos = trail[maxi(0, trail.size() - 7)]
		state.call(&"_correct_self", 1.0 / 60.0, start_msec + int(frame * 1000.0 / 60.0))
	assert_eq(state.snap_count, 0, "no rubber band after the stall")
	assert_almost_eq(player.position.x, player.move_speed * 2.0, 1.0, "walked freely for 2 s")


func test_input_does_not_pile_up_while_the_host_stands_still() -> void:
	var player := _player(true)
	var state := _state(player)
	var keys := _keys(player)
	keys.set_move(Vector2.RIGHT)
	keys.press(PlayerInput.ATTACK)
	keys.poll(player)
	var normal: Array = state.next_input()
	assert_eq(normal[0], Vector2.RIGHT)
	assert_true(int(normal[2]) & (1 << PlayerInput.ACTIONS.find(PlayerInput.ATTACK)) != 0)
	state.set_host_stalled(true)
	var sent: Array = []
	var ticks := Engine.physics_ticks_per_second
	for frame in 5 * ticks:
		# The mouse keeps moving: still no packet per frame.
		keys.set_aim_direction(Vector2.from_angle(frame * 0.1))
		var packet: Array = state.next_input()
		if not packet.is_empty():
			sent.append(packet)
	assert_eq(sent.size(), 5, "one empty input at once, then one per second")
	assert_eq(sent[0][0], Vector2.ZERO, "no movement")
	assert_eq(int(sent[0][2]) & ~NetPlayerState.ACTIVE_SLOT_MASK, 0, "no actions, only the weapon slot")
	state.set_host_stalled(false)
	var back: Array = state.next_input()
	assert_eq(back[0], Vector2.RIGHT, "resume: the held input at once")


func test_other_players_stand_while_the_host_stands_still() -> void:
	var copy := _player(false, 1)
	var state := _state(copy)
	var attack := 1 << PlayerInput.ACTIONS.find(PlayerInput.ATTACK)
	state.pos = Vector2(40, 0)
	state.move = Vector2.RIGHT
	state.held = attack
	state.call(&"_follow", 1.0 / 60.0)
	assert_eq(_keys(copy).move, Vector2.RIGHT, "normally the host's input is replayed")
	state.set_host_stalled(true)
	for i in 60:
		state.call(&"_follow", 1.0 / 60.0)
	_keys(copy).poll(copy)
	_keys(copy).poll(copy)
	assert_eq(_keys(copy).move, Vector2.ZERO, "no walking on the spot")
	assert_false(_keys(copy).is_pressed(PlayerInput.ATTACK), "no swinging either")
	assert_almost_eq(copy.position.x, 40.0, 1.0, "stands at the host's position")
	assert_false(copy.is_input_locked(), "copies are not locked")
	state.set_host_stalled(false)
	state.call(&"_follow", 1.0 / 60.0)
	assert_eq(_keys(copy).move, Vector2.RIGHT, "replayed again once the host runs")


func test_host_stops_the_player_of_a_silent_client() -> void:
	var copy := _player(false, CLIENT_PEER)
	var state := _state(copy)
	var keys := _keys(copy)
	var attack := 1 << PlayerInput.ACTIONS.find(PlayerInput.ATTACK)
	assert_false(state.expire_stale_input(Time.get_ticks_msec() + 60000), "nothing to clear before any input")
	state.apply_input(CLIENT_PEER, Vector2.RIGHT, Vector2.RIGHT, attack)
	keys.poll(copy)
	var now := Time.get_ticks_msec()
	assert_false(state.expire_stale_input(now + 100), "a client sends at least every SEND_EVERY_FRAMES")
	assert_eq(keys.move, Vector2.RIGHT)
	assert_true(state.expire_stale_input(now + NetPlayerState.CLIENT_INPUT_STALE_MSEC + 50), "silent too long")
	keys.poll(copy)
	assert_eq(keys.move, Vector2.ZERO, "its player no longer walks on (ghost walking)")
	assert_false(keys.is_pressed(PlayerInput.ATTACK))
	state.apply_input(CLIENT_PEER, Vector2.LEFT, Vector2.RIGHT, 0)
	assert_eq(keys.move, Vector2.LEFT, "the next packet counts again")
	assert_false(state.expire_stale_input(Time.get_ticks_msec()))


func test_a_hitch_of_the_host_does_not_stop_its_teammates() -> void:
	# Finding of 17.10.2026: after a hitch of the host the physics steps that catch up run before the
	# poll, measured against the wall clock they cleared every client's input although it waited in
	# the socket. The clock is the host's last poll (NetPlayerState.input_clock_msec).
	_create_as_host(ROOM)
	_peer.poll()
	var copy := _player(false, CLIENT_PEER)
	var state := _state(copy)
	var keys := _keys(copy)
	state.apply_input(CLIENT_PEER, Vector2.RIGHT, Vector2.RIGHT, 0)
	keys.poll(copy)
	# The host hangs for 2 s; up to 8 physics steps catch up before the next poll.
	_advance(2000)
	for step in 8:
		assert_false(state.expire_stale_input(NetPlayerState.input_clock_msec(_peer)), "catch-up step %d keeps the input" % step)
	keys.poll(copy)
	assert_eq(keys.move, Vector2.RIGHT, "the teammate walks on through the catch-up steps")
	# The poll brings nothing from this client (it really was silent): now its player stops.
	_peer.poll()
	assert_true(state.expire_stale_input(NetPlayerState.input_clock_msec(_peer)), "silent up to the poll")
	keys.poll(copy)
	assert_eq(keys.move, Vector2.ZERO)
	# Without a relay (tests, local sim) the clock is the wall clock.
	assert_almost_eq(NetPlayerState.input_clock_msec(null), Time.get_ticks_msec(), 5)


func test_the_lock_goes_with_the_session() -> void:
	var player := _player(true)
	var state := _state(player)
	state.set_host_stalled(true)
	assert_true(player.is_input_locked())
	await wait_physics_frames(2)
	assert_false(player.is_input_locked(), "no session any more: no lock stays behind")
	assert_false(state.is_host_stalled())


# --- Notice, texts, browser ---

func test_wait_notice_with_name_seconds_and_leave_button() -> void:
	var notice := HostStallNotice.new()
	autofree(notice)
	notice.update_wait(0, "Ada")
	notice.update_wait(HostStall.NOTICE_MSEC - 1, "Ada")
	assert_false(notice.is_waiting(), "a short stall shows nothing")
	notice.update_wait(HostStall.NOTICE_MSEC + 1200, "Ada")
	assert_true(notice.is_waiting())
	assert_eq(notice.get_title(), Loc.t(&"NET_HOST_STALL_TITLE"))
	assert_string_contains(notice.get_text(), "Ada")
	assert_string_contains(notice.get_text(), Loc.t(&"NET_HOST_STALL_SECONDS", [2]))
	assert_false(notice.is_leave_offered())
	notice.update_wait(HostStall.LEAVE_MSEC, "Ada")
	assert_true(notice.is_leave_offered(), "after a long stall the room can be left")
	assert_eq(notice.get_leave_button().text, Loc.t(&"LOBBY_LEAVE"))
	notice.show_host_away(5000)
	assert_true(notice.is_waiting(), "a host note never covers the wait")
	notice.update_wait(0)
	assert_false(notice.is_waiting(), "gone when the host runs again")
	assert_false(notice.is_leave_offered())
	assert_eq(notice.wait_count, 1)


func test_host_note_after_its_game_stood_still() -> void:
	var notice := HostStallNotice.new()
	autofree(notice)
	notice.show_host_away(12400)
	assert_true(notice.is_note_visible())
	assert_eq(notice.get_title(), Loc.t(&"NET_HOST_AWAY_TITLE"))
	assert_string_contains(notice.get_text(), Loc.t(&"NET_HOST_AWAY", [12]))
	assert_eq(HostStallNotice.host_away_lines(12400, false).size(), 2)
	var web := HostStallNotice.host_away_lines(12400, true)
	assert_eq(web.size(), 3, "in the browser with the tip to keep the tab visible")
	assert_eq(web[2], Loc.t(&"NET_HOST_AWAY_WEB"))


func test_texts_have_english_and_german() -> void:
	for key in TEXT_KEYS:
		assert_true(Loc.has_key(key, &"en"), "%s en" % key)
		assert_true(Loc.has_key(key, &"de"), "%s de" % key)
		assert_ne(Loc.t(key), String(key))


func test_lobby_switches_the_keep_alive_with_the_room() -> void:
	var lobby := LobbyClient.new()
	lobby.reload_world = false
	add_child_autofree(lobby)
	assert_not_null(lobby.get_node_or_null(NodePath(String(HostStallNotice.NODE_NAME))), "the notice lives under the lobby")
	lobby.call(&"_set_state", LobbyClient.State.IN_ROOM)
	assert_true(WebKeepAlive.is_enabled(), "on in a room")
	lobby.call(&"_set_state", LobbyClient.State.IDLE)
	assert_false(WebKeepAlive.is_enabled(), "off outside (single player keeps its behaviour)")


func test_keep_alive_does_nothing_outside_the_browser() -> void:
	assert_false(WebKeepAlive.is_supported())
	WebKeepAlive.set_enabled(true)
	WebKeepAlive.update(1.0)
	assert_false(WebKeepAlive.is_page_hidden())
	assert_eq(WebKeepAlive.stats(), {})
	assert_true(RenderingServer.render_loop_enabled, "drawing untouched")
	WebKeepAlive.set_enabled(false)
	assert_false(WebKeepAlive.is_enabled())


func test_shell_wraps_the_frame_loop_before_the_engine_loads() -> void:
	var shell := FileAccess.get_file_as_string("res://deploy/web/shell.html")
	assert_false(shell.is_empty(), "deploy/web/shell.html readable")
	var wrapper := shell.find("window.requestAnimationFrame = function")
	var engine := shell.find("<script src=\"$GODOT_URL\"></script>")
	assert_true(wrapper > 0 and engine > wrapper, "the wrapper is installed before Godot's script")
	for part in ["window.soulwickShell", "setKeepAlive", "isHidden", "stats()", "visibilitychange", "new Worker"]:
		assert_string_contains(shell, part)

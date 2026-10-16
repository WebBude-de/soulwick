extends GutTest
## Connection stability of RelayPeer (first online test 15.10.2026): heartbeat ping/pong, the
## silence timeout, the session end reason per relay close code and a room_closed that arrives
## together with the close frame. Uses the fake WebSocket of test_relay_peer.gd.

const FakeSocket = preload("res://tests/unit/test_relay_peer.gd").FakeSocket
const ROOM := {"code": "ABCD23", "mode": "quick", "guildId": null, "hostPeerId": 1, "started": true, "maxPlayers": 4, "gameVersion": "0.9.0", "peers": [{"peerId": 1, "playerId": "p1", "name": "Host", "platform": "windows"}, {"peerId": 2, "playerId": "p2", "name": "Gast", "platform": "windows"}], "expiresAt": null}

var _socket: FakeSocket
var _peer: RelayPeer
var _left: Array = []


func before_each() -> void:
	_socket = FakeSocket.new()
	_peer = RelayPeer.new()
	_peer.socket = _socket
	_left = []
	_peer.room_left.connect(func(reason: String) -> void: _left.append(reason))


func _advance(seconds: float) -> void:
	_peer.time_offset_msec += int(seconds * 1000.0)


func _welcome(action: Dictionary) -> void:
	_peer.open("ws://relay.test/v1", RelayProtocol.hello("tok", 1, "0.9.0", "windows"), action)
	_socket.ready_state = WebSocketPeer.STATE_OPEN
	_peer.poll()
	_socket.push_text({"type": "welcome", "playerId": "p2", "name": "Gast", "protocolVersion": 1, "maxFrameBytes": 65536, "maxPlayers": 4, "clientRouting": "host_only"})
	_peer.poll()


func _join_as_client() -> void:
	_welcome(RelayProtocol.join("ABCD23"))
	_socket.push_text({"type": "joined", "code": "ABCD23", "peerId": 2, "room": ROOM})
	_peer.set_delivering(true)
	_peer.poll()
	assert_true(_peer.is_in_room())


func _pings() -> Array:
	return _socket.sent_text.filter(func(message: Dictionary) -> bool: return message.type == "ping")


func test_no_ping_before_welcome() -> void:
	_peer.open("ws://relay.test/v1", RelayProtocol.hello("tok", 1, "0.9.0", "windows"), {})
	_socket.ready_state = WebSocketPeer.STATE_OPEN
	_peer.poll()
	_advance(RelayProtocol.HEARTBEAT_SECONDS + 1.0)
	_peer.poll()
	assert_eq(_socket.sent_text.size(), 1, "only hello: the relay closes on anything before hello")
	assert_eq(_socket.sent_text[0].type, "hello")


func test_heartbeat_ping_and_round_trip() -> void:
	_join_as_client()
	assert_eq(_pings().size(), 0)
	_advance(RelayProtocol.HEARTBEAT_SECONDS)
	_peer.poll()
	assert_eq(_pings().size(), 1, "one ping per heartbeat interval")
	var sent_t := int(_pings()[0].t)
	_advance(0.08)
	_socket.push_text({"type": "pong", "t": sent_t})
	_peer.poll()
	assert_almost_eq(_peer.last_rtt_msec, 80, 40)
	_advance(1.0)
	_peer.poll()
	assert_eq(_pings().size(), 1, "not again before the next interval")
	_advance(RelayProtocol.HEARTBEAT_SECONDS)
	_peer.poll()
	assert_eq(_pings().size(), 2)


func test_traffic_keeps_the_connection_alive() -> void:
	_join_as_client()
	for i in 10:
		_advance(RelayProtocol.SILENCE_TIMEOUT_SECONDS * 0.5)
		_socket.push_binary(RelayProtocol.encode_frame(1, 2, 0, 2, PackedByteArray([i])))
		_peer.poll()
	assert_true(_peer.is_in_room(), "%.0f s of play with packets" % (RelayProtocol.SILENCE_TIMEOUT_SECONDS * 5.0))
	assert_eq(_left, [])


func test_silence_ends_the_session_with_timeout() -> void:
	_join_as_client()
	var closed: Array = []
	_peer.connection_closed.connect(func(code: int, _reason: String) -> void: closed.append(code))
	_advance(RelayProtocol.SILENCE_TIMEOUT_SECONDS - 1.0)
	_peer.poll()
	assert_true(_peer.is_in_room(), "not yet")
	_advance(1.0)
	_peer.poll()
	assert_false(_peer.is_in_room())
	assert_eq(_left, [RelayProtocol.END_TIMEOUT])
	assert_eq(_peer.end_reason, "timeout")
	assert_eq(closed, [RelayProtocol.CLOSE_ABNORMAL])
	assert_eq(_peer.get_connection_status(), MultiplayerPeer.CONNECTION_DISCONNECTED)
	assert_eq(_socket.ready_state, WebSocketPeer.STATE_CLOSED, "the dead socket is closed")
	_peer.poll()
	assert_eq(_left.size(), 1, "the session ends only once")


func test_end_reason_per_close_code() -> void:
	var expected := {
		RelayProtocol.CLOSE_SHUTDOWN: "shutdown",
		RelayProtocol.CLOSE_TIMEOUT: "timeout",
		RelayProtocol.CLOSE_SLOW_CONSUMER: "slow_consumer",
		RelayProtocol.CLOSE_RATE_LIMITED: "rate_limited",
		RelayProtocol.CLOSE_BANNED: "banned",
		RelayProtocol.CLOSE_ABNORMAL: "disconnected",
		1006: "disconnected",
		1000: "disconnected",
	}
	for code: int in expected:
		assert_eq(RelayProtocol.end_reason_for_close(code), expected[code], "close %d" % code)
		before_each()
		_join_as_client()
		_socket.close_code = code
		_socket.ready_state = WebSocketPeer.STATE_CLOSED
		_peer.poll()
		assert_eq(_left, [expected[code]], "room_left for close %d" % code)


func test_room_closed_with_the_close_frame_wins() -> void:
	_join_as_client()
	_socket.push_text({"type": "room_closed", "code": "ABCD23", "reason": "shutdown"})
	_socket.close_code = RelayProtocol.CLOSE_ABNORMAL
	_socket.ready_state = WebSocketPeer.STATE_CLOSED
	_peer.poll()
	assert_eq(_left, ["shutdown"], "the relay's reason, not 'disconnected'")
	assert_eq(_peer.end_reason, "shutdown")


func test_host_left_keeps_its_reason() -> void:
	_join_as_client()
	_socket.push_text({"type": "room_closed", "code": "ABCD23", "reason": "host_left"})
	_peer.poll()
	assert_eq(_left, ["host_left"])
	# The socket stays open in the lobby and keeps its heartbeat.
	_advance(RelayProtocol.HEARTBEAT_SECONDS)
	_peer.poll()
	assert_eq(_pings().size(), 1)


func test_every_session_end_reason_has_a_message_key() -> void:
	# LobbyClient shows LOBBY_ERR_<REASON>; these keys must exist in localization/translations.csv
	# (timeout and slow_consumer are new, see the report of the network stability package).
	for reason: String in ["shutdown", "host_left", "kicked", "closed_by_admin", "disconnected", "timeout", "slow_consumer", "rate_limited", "banned"]:
		assert_eq(String(LobbyClient.error_key(reason)), "LOBBY_ERR_%s" % reason.to_upper())

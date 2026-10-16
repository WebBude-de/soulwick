extends GutTest
## MP2: RelayPeer against the relay contract (soulwick-platform/packages/contracts/src/lobby.ts)
## with a fake WebSocket: the binary frame against RELAY_FRAME_TEST_VECTORS, hello -> welcome ->
## create/join, peer events only after set_delivering, host vs client routing, room end.

## Copied from RELAY_FRAME_TEST_VECTORS (lobby.ts); keep in step with the contract.
const FRAME_VECTORS := [
	{"name": "host broadcasts reliable", "from": 1, "to": 0, "channel": 0, "mode": 2, "dataHex": "dead", "hex": "01000000000000000002dead"},
	{"name": "client to host, channel 3, unreliable", "from": 2, "to": 1, "channel": 3, "mode": 0, "dataHex": "6869", "hex": "020000000100000003006869"},
	{"name": "host to all except peer 2, unreliable ordered", "from": 1, "to": -2, "channel": 1, "mode": 1, "dataHex": "00ff", "hex": "01000000feffffff010100ff"},
	{"name": "host to peer 4, empty payload", "from": 1, "to": 4, "channel": 0, "mode": 2, "dataHex": "", "hex": "01000000040000000002"},
	{"name": "large peer id and channel 255", "from": 1, "to": 305419896, "channel": 255, "mode": 2, "dataHex": "01020304", "hex": "0100000078563412ff0201020304"},
]
const ROOM_HOST := {"code": "ABCD23", "mode": "quick", "guildId": null, "hostPeerId": 1, "started": false, "maxPlayers": 4, "gameVersion": "0.9.0", "peers": [{"peerId": 1, "playerId": "p1", "name": "Host", "platform": "windows"}], "expiresAt": null}


## The WebSocketPeer methods RelayPeer uses; the test pushes incoming messages.
class FakeSocket extends RefCounted:
	var url := ""
	var ready_state := WebSocketPeer.STATE_CONNECTING
	var sent_text: Array[Dictionary] = []
	var sent_binary: Array[PackedByteArray] = []
	var _inbox: Array = []
	var _last_was_string := false
	var close_code := -1

	func connect_to_url(target: String) -> Error:
		url = target
		return OK

	func poll() -> void:
		pass

	func get_ready_state() -> int:
		return ready_state

	func get_available_packet_count() -> int:
		return _inbox.size()

	func get_packet() -> PackedByteArray:
		var item: Array = _inbox.pop_front()
		_last_was_string = item[0]
		return item[1]

	func was_string_packet() -> bool:
		return _last_was_string

	func send_text(text: String) -> Error:
		sent_text.append(JSON.parse_string(text))
		return OK

	func put_packet(bytes: PackedByteArray) -> Error:
		sent_binary.append(bytes)
		return OK

	func close(code := 1000, _reason := "") -> void:
		close_code = code
		ready_state = WebSocketPeer.STATE_CLOSED

	func get_close_code() -> int:
		return close_code

	func get_close_reason() -> String:
		return ""

	func push_text(message: Dictionary) -> void:
		_inbox.append([true, JSON.stringify(message).to_utf8_buffer()])

	func push_binary(bytes: PackedByteArray) -> void:
		_inbox.append([false, bytes])


var _socket: FakeSocket
var _peer: RelayPeer
var _events: Array = []


func before_each() -> void:
	_socket = FakeSocket.new()
	_peer = RelayPeer.new()
	_peer.socket = _socket
	_events = []
	_peer.peer_connected.connect(func(id: int) -> void: _events.append(["up", id]))
	_peer.peer_disconnected.connect(func(id: int) -> void: _events.append(["down", id]))
	_peer.room_left.connect(func(reason: String) -> void: _events.append(["left", reason]))


func test_frames_match_the_contract_vectors() -> void:
	for vector: Dictionary in FRAME_VECTORS:
		var data := String(vector.dataHex).hex_decode()
		var encoded := RelayProtocol.encode_frame(vector.from, vector.to, vector.channel, vector.mode, data)
		assert_eq(encoded.hex_encode(), vector.hex, vector.name)
		var decoded := RelayProtocol.decode_frame(String(vector.hex).hex_decode())
		assert_eq(decoded.from, vector.from, vector.name)
		assert_eq(decoded.to, vector.to, vector.name)
		assert_eq(decoded.channel, vector.channel, vector.name)
		assert_eq(decoded.mode, vector.mode, vector.name)
		assert_eq((decoded.data as PackedByteArray).hex_encode(), vector.dataHex, vector.name)
	assert_eq(RelayProtocol.decode_frame(PackedByteArray([1, 2, 3])), {}, "shorter than the header")
	assert_eq(MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, RelayProtocol.MODE_UNRELIABLE_ORDERED)
	assert_eq(MultiplayerPeer.TRANSFER_MODE_RELIABLE, RelayProtocol.MODE_RELIABLE)


func _open(action: Dictionary) -> void:
	var hello := RelayProtocol.hello("tok", 1, "0.9.0", "windows")
	assert_eq(_peer.open("ws://relay.test/v1", hello, action), OK)
	assert_eq(_peer.get_connection_status(), MultiplayerPeer.CONNECTION_CONNECTING)
	_socket.ready_state = WebSocketPeer.STATE_OPEN
	_peer.poll()
	_socket.push_text({"type": "welcome", "playerId": "p", "name": "N", "protocolVersion": 1, "maxFrameBytes": 1034, "maxPlayers": 4, "clientRouting": "host_only"})
	_peer.poll()


func test_hello_first_then_the_action() -> void:
	_open(RelayProtocol.create("quick"))
	assert_eq(_socket.url, "ws://relay.test/v1")
	assert_eq(_socket.sent_text.size(), 2)
	var hello: Dictionary = _socket.sent_text[0]
	assert_eq(hello.type, "hello")
	assert_eq(hello.token, "tok")
	assert_eq(int(hello.protocolVersion), 1)
	assert_eq(hello.gameVersion, "0.9.0")
	assert_eq(hello.platform, "windows")
	assert_eq(_socket.sent_text[1], {"type": "create", "mode": "quick"})
	assert_eq(_peer._get_max_packet_size(), 1024, "maxFrameBytes minus the header")
	assert_eq(RelayProtocol.create("guild", "g-1"), {"type": "create", "mode": "guild", "guildId": "g-1"})


func test_host_room_peers_and_packets() -> void:
	_open(RelayProtocol.create("quick"))
	var entered: Array = []
	_peer.room_entered.connect(func(room: Dictionary, id: int) -> void: entered.append([room.code, id]))
	_socket.push_text({"type": "created", "code": "ABCD23", "peerId": 1, "room": ROOM_HOST})
	_socket.push_text({"type": "peer_joined", "peer": {"peerId": 2, "playerId": "p2", "name": "Gast", "platform": "android"}})
	_peer.poll()
	assert_eq(entered, [["ABCD23", 1]])
	assert_eq(_peer.get_connection_status(), MultiplayerPeer.CONNECTION_CONNECTED)
	assert_eq(_peer.get_unique_id(), 1)
	assert_true(_peer.is_host())
	assert_eq(_events, [], "held back until delivering")
	_peer.set_delivering(true)
	_peer.poll()
	assert_eq(_events, [["up", 2]])
	# Client packet to the host arrives with its sender.
	_socket.push_binary(RelayProtocol.encode_frame(2, 1, 3, 0, PackedByteArray([7, 8])))
	_socket.push_binary(RelayProtocol.encode_frame(9, 1, 0, 2, PackedByteArray([1])))
	_peer.poll()
	assert_eq(_peer.get_available_packet_count(), 1, "frames of unknown peers are dropped")
	assert_eq(_peer.get_packet_peer(), 2)
	assert_eq(_peer.get_packet_channel(), 3)
	assert_eq(_peer.get_packet_mode(), MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	assert_eq(_peer.get_packet(), PackedByteArray([7, 8]))
	# The host addresses anyone: broadcast except peer 2.
	_peer.transfer_channel = 1
	_peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	_peer.set_target_peer(-2)
	assert_eq(_peer.put_packet(PackedByteArray([0, 255])), OK)
	assert_eq(_socket.sent_binary.back().hex_encode(), "01000000feffffff010100ff")
	# Client leaves.
	_socket.push_text({"type": "peer_left", "peerId": 2, "reason": "left"})
	_peer.poll()
	assert_eq(_events.back(), ["down", 2])


func test_client_sees_only_the_host_and_sends_to_it() -> void:
	_open(RelayProtocol.join("ABCD23"))
	assert_eq(_socket.sent_text[1], {"type": "join", "code": "ABCD23"})
	var room := ROOM_HOST.duplicate(true)
	room.peers.append({"peerId": 3, "playerId": "p3", "name": "Ich", "platform": "linux"})
	_socket.push_text({"type": "joined", "code": "ABCD23", "peerId": 3, "room": room})
	_peer.poll()
	assert_eq(_peer.get_unique_id(), 3)
	assert_false(_peer.is_host())
	_peer.set_delivering(true)
	_peer.poll()
	assert_eq(_events, [["up", 1]])
	_peer.set_target_peer(0)
	_peer.put_packet(PackedByteArray([42]))
	assert_eq(RelayProtocol.decode_frame(_socket.sent_binary.back()).to, 1, "host_only routing")
	assert_eq(RelayProtocol.decode_frame(_socket.sent_binary.back()).from, 3)
	# Peer events of other clients are host business.
	_socket.push_text({"type": "peer_joined", "peer": {"peerId": 4, "playerId": "p4", "name": "X", "platform": "ios"}})
	_peer.poll()
	assert_eq(_events.size(), 1)
	# The host leaves: session over (D-123).
	_socket.push_text({"type": "room_closed", "code": "ABCD23", "reason": "host_left"})
	_peer.poll()
	assert_eq(_events, [["up", 1], ["down", 1], ["left", "host_left"]])
	assert_eq(_peer.get_connection_status(), MultiplayerPeer.CONNECTION_DISCONNECTED)
	assert_eq(_peer.put_packet(PackedByteArray([1])), ERR_UNCONFIGURED)


func test_relay_shutdown_closes_the_session() -> void:
	_open(RelayProtocol.join("ABCD23"))
	_socket.push_text({"type": "joined", "code": "ABCD23", "peerId": 2, "room": ROOM_HOST})
	_peer.set_delivering(true)
	_peer.poll()
	var closed: Array = []
	_peer.connection_closed.connect(func(code: int, _reason: String) -> void: closed.append(code))
	_socket.close_code = RelayProtocol.CLOSE_SHUTDOWN
	_socket.ready_state = WebSocketPeer.STATE_CLOSED
	_peer.poll()
	assert_eq(closed, [1001])
	assert_eq(_events, [["up", 1], ["down", 1], ["left", "shutdown"]])


func test_errors_are_reported() -> void:
	var errors: Array = []
	_peer.relay_error.connect(func(code: String, _message: String, request: String) -> void: errors.append([code, request]))
	_open(RelayProtocol.join("ZZZZZZ"))
	_socket.push_text({"type": "error", "code": "room_not_found", "message": "No such room", "request": "join"})
	_peer.poll()
	assert_eq(errors, [["room_not_found", "join"]])
	assert_eq(_peer.get_connection_status(), MultiplayerPeer.CONNECTION_CONNECTING)


func test_several_runs_per_room() -> void:
	_open(RelayProtocol.create("quick"))
	_socket.push_text({"type": "created", "code": "ABCD23", "peerId": 1, "room": ROOM_HOST})
	_peer.set_delivering(true)
	_peer.poll()
	var ended: Array = []
	_peer.run_ended.connect(func(reason: String) -> void: ended.append(reason))
	assert_eq(_peer.start(), OK)
	assert_eq(_socket.sent_text.back(), {"type": "start"})
	assert_eq(_peer.end_run(RelayProtocol.RUN_END_PORTAL), OK)
	assert_eq(_socket.sent_text.back(), {"type": "end_run", "reason": "portal"})
	assert_eq(RelayProtocol.end_run(), {"type": "end_run"}, "the reason is optional")
	assert_eq(RelayProtocol.end_run("nonsense"), {"type": "end_run"}, "unknown reasons are left out")
	var room := ROOM_HOST.duplicate(true)
	room.peers.append({"peerId": 3, "playerId": "p3", "name": "Neu", "platform": "linux"})
	_socket.push_text({"type": "run_ended", "reason": "wiped"})
	_socket.push_text({"type": "run_ended", "reason": null})
	_socket.push_text({"type": "room_state", "room": room})
	_peer.poll()
	assert_eq(ended, ["wiped", ""], "run_ended with and without a reason")
	assert_false(bool(_peer.room.started))
	assert_eq(_events, [["up", 3]], "a player joining between runs is a new peer")
	assert_true(RelayProtocol.ERROR_CODES.has("room_not_started"))


func test_run_end_reasons_for_the_relay() -> void:
	assert_eq(NetRun.relay_end_reason(RunManager.EndReason.EXIT), "portal")
	assert_eq(NetRun.relay_end_reason(RunManager.EndReason.DEATH), "wiped")
	assert_eq(NetRun.relay_end_reason(RunManager.EndReason.ABORT), "abandoned")


func test_input_bits_round_trip() -> void:
	var input := RemoteInput.new()
	input.press(PlayerInput.ATTACK)
	input.press(PlayerInput.INTERACT)
	input.poll(null)
	var bits := NetPlayerState.bits_of(input)
	var both: Array[StringName] = [PlayerInput.ATTACK, PlayerInput.INTERACT]
	var attack_only: Array[StringName] = [PlayerInput.ATTACK]
	assert_eq(NetPlayerState.actions_of(bits), both)
	assert_eq(NetPlayerState.actions_of(bits & ~NetPlayerState.INTERACT_BIT), attack_only, "interact never travels")

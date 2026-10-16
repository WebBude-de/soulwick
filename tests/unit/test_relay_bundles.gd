extends GutTest
## Traffic of RelayPeer after the online test of 16.10.2026: capability frame, bundles per receiver
## (order of reliable packets, broadcasts split, plain frames for peers without bundles), unreliable
## packets skipped above the own backlog, a reliable packet that does not fit ends the session as
## slow_consumer, the received backlog is thinned out (unreliable only). Fake WebSocket of
## test_relay_peer.gd with a fillable outbound buffer.

const BaseSocket = preload("res://tests/unit/test_relay_peer.gd").FakeSocket
const Diagnostics = preload("res://online/net_diagnostics.gd")
const ROOM := {"code": "ABCD23", "mode": "quick", "guildId": null, "hostPeerId": 1, "started": true, "maxPlayers": 4, "gameVersion": "0.9.1", "peers": [{"peerId": 1, "playerId": "p1", "name": "Host", "platform": "windows"}], "expiresAt": null}


class Socket extends BaseSocket:
	var outbound := 0
	var refuse := false

	func get_current_outbound_buffered_amount() -> int:
		return outbound

	func put_packet(bytes: PackedByteArray) -> Error:
		if refuse:
			return ERR_OUT_OF_MEMORY
		return super.put_packet(bytes)


var _socket: Socket
var _peer: RelayPeer
var _left: Array = []


func before_each() -> void:
	RelayPeer.bundling_allowed = true
	_socket = Socket.new()
	_peer = RelayPeer.new()
	_peer.socket = _socket
	_left = []
	_peer.room_left.connect(func(reason: String) -> void: _left.append(reason))


func after_all() -> void:
	RelayPeer.bundling_allowed = OS.get_environment("SOULWICK_NET_BUNDLE") != "0" and not RelayPeer.legacy_sync


func _enter(as_host: bool, peer_ids: Array) -> void:
	_peer.open("ws://relay.test/v1", RelayProtocol.hello("tok", 1, "0.9.1", "windows"), RelayProtocol.create("quick") if as_host else RelayProtocol.join("ABCD23"))
	_socket.ready_state = WebSocketPeer.STATE_OPEN
	_peer.poll()
	_socket.push_text({"type": "welcome", "playerId": "p", "name": "N", "protocolVersion": 1, "maxFrameBytes": 65536, "maxPlayers": 4, "clientRouting": "host_only"})
	_peer.poll()
	var room := ROOM.duplicate(true)
	for id: int in peer_ids:
		room.peers.append({"peerId": id, "playerId": "p%d" % id, "name": "P%d" % id, "platform": "windows"})
	if as_host:
		_socket.push_text({"type": "created", "code": "ABCD23", "peerId": 1, "room": room})
	else:
		_socket.push_text({"type": "joined", "code": "ABCD23", "peerId": peer_ids[0], "room": room})
	_peer.set_delivering(true)
	_peer.poll()
	assert_true(_peer.is_in_room())


func _caps_from(from: int, to: int) -> void:
	_socket.push_binary(RelayProtocol.encode_frame(from, to, RelayProtocol.CAPS_CHANNEL, RelayProtocol.MODE_RELIABLE, RelayProtocol.caps_payload()))
	_peer.poll()


func _put(to: int, mode: int, data: Array, channel := 0) -> Error:
	_peer.set_target_peer(to)
	_peer.transfer_mode = mode as MultiplayerPeer.TransferMode
	_peer.transfer_channel = channel
	return _peer.put_packet(PackedByteArray(data))


func _frames() -> Array:
	var result: Array = []
	for bytes in _socket.sent_binary:
		result.append(RelayProtocol.decode_frame(bytes))
	return result


func _game_frames() -> Array:
	return _frames().filter(func(frame: Dictionary) -> bool: return frame.channel != RelayProtocol.CAPS_CHANNEL)


func test_bundle_round_trip_and_malformed_payloads() -> void:
	var entries := [[0, 2, PackedByteArray([1, 2, 3])], [2, 1, PackedByteArray()], [1, 0, PackedByteArray([9])]]
	var bytes := RelayProtocol.encode_bundle(entries)
	assert_eq(bytes.size(), 3 * RelayProtocol.BUNDLE_ENTRY_HEADER + 4)
	assert_eq(RelayProtocol.decode_bundle(bytes), entries)
	assert_eq(RelayProtocol.decode_bundle(bytes.slice(0, bytes.size() - 1)), [], "a cut bundle is rejected whole")
	assert_eq(RelayProtocol.decode_bundle(PackedByteArray([0, 2, 9])), [], "shorter than an entry header")
	assert_true(RelayProtocol.is_caps(RelayProtocol.caps_payload()))
	assert_eq(RelayProtocol.caps_payload()[0], 3, "SceneMultiplayer RAW command for older builds")


func test_every_peer_that_comes_up_gets_the_capability_frame() -> void:
	_enter(true, [2])
	var caps := _frames().filter(func(frame: Dictionary) -> bool: return frame.channel == RelayProtocol.CAPS_CHANNEL)
	assert_eq(caps.size(), 1)
	assert_eq(caps[0].to, 2)
	assert_eq(caps[0].mode, RelayProtocol.MODE_RELIABLE)
	_socket.push_text({"type": "peer_joined", "peer": {"peerId": 3, "playerId": "p3", "name": "C", "platform": "linux"}})
	_peer.poll()
	assert_eq(_frames().filter(func(frame: Dictionary) -> bool: return frame.channel == RelayProtocol.CAPS_CHANNEL).size(), 2)
	assert_eq(_peer.get_available_packet_count(), 0, "capability frames never reach SceneMultiplayer")


func test_without_capability_every_packet_is_a_plain_frame_at_once() -> void:
	_enter(true, [2])
	_put(2, RelayProtocol.MODE_RELIABLE, [1])
	_put(2, RelayProtocol.MODE_RELIABLE, [2])
	assert_eq(_game_frames().size(), 2, "sent at once, one frame each (older build on the other side)")
	assert_eq(_game_frames()[1].data, PackedByteArray([2]))


func test_packets_of_one_frame_leave_as_one_bundle_per_mode() -> void:
	_enter(true, [2])
	_caps_from(2, 1)
	assert_true(_peer.diagnostics.bundling)
	_put(2, RelayProtocol.MODE_RELIABLE, [1], 0)
	_put(2, RelayProtocol.MODE_UNRELIABLE_ORDERED, [7], 2)
	_put(2, RelayProtocol.MODE_RELIABLE, [2, 2], 0)
	assert_eq(_game_frames().size(), 0, "queued until the flush")
	_peer.flush()
	var frames := _game_frames()
	assert_eq(frames.size(), 2, "one reliable bundle, the single unreliable packet as a plain frame")
	assert_eq(frames[0].channel, RelayProtocol.BUNDLE_CHANNEL)
	assert_eq(frames[0].mode, RelayProtocol.MODE_RELIABLE)
	assert_eq(RelayProtocol.decode_bundle(frames[0].data), [[0, 2, PackedByteArray([1])], [0, 2, PackedByteArray([2, 2])]], "order kept")
	assert_eq(frames[1].channel, 2)
	assert_eq(frames[1].mode, RelayProtocol.MODE_UNRELIABLE_ORDERED)
	assert_eq(_peer.diagnostics.totals.packets_out, 3)
	assert_eq(_peer.diagnostics.totals.bundles_out, 1)


func test_broadcast_is_split_per_receiver_or_plain_when_one_cannot_read_bundles() -> void:
	_enter(true, [2, 3])
	_caps_from(2, 1)
	_caps_from(3, 1)
	_put(0, RelayProtocol.MODE_RELIABLE, [5])
	_put(3, RelayProtocol.MODE_RELIABLE, [6])
	_put(-3, RelayProtocol.MODE_RELIABLE, [7])
	_peer.flush()
	var to_two := _game_frames().filter(func(frame: Dictionary) -> bool: return frame.to == 2)
	var to_three := _game_frames().filter(func(frame: Dictionary) -> bool: return frame.to == 3)
	assert_eq(RelayProtocol.decode_bundle(to_two[0].data), [[0, 2, PackedByteArray([5])], [0, 2, PackedByteArray([7])]])
	assert_eq(RelayProtocol.decode_bundle(to_three[0].data), [[0, 2, PackedByteArray([5])], [0, 2, PackedByteArray([6])]])
	# A newcomer without bundles: broadcasts go plain again, after everything queued before.
	_socket.sent_binary.clear()
	_socket.push_text({"type": "peer_joined", "peer": {"peerId": 4, "playerId": "p4", "name": "D", "platform": "linux"}})
	_peer.poll()
	_put(2, RelayProtocol.MODE_RELIABLE, [8])
	_put(0, RelayProtocol.MODE_RELIABLE, [9])
	var frames := _game_frames()
	assert_eq(frames.size(), 2)
	assert_eq(frames[0].to, 2, "the queued packet first")
	assert_eq(frames[1].to, 0)
	assert_eq(frames[1].data, PackedByteArray([9]))


func test_client_reads_bundles_of_the_host() -> void:
	_enter(false, [2])
	var bundle := RelayProtocol.encode_bundle([[0, 2, PackedByteArray([1])], [2, 1, PackedByteArray([2])], [0, 2, PackedByteArray([3])]])
	_socket.push_binary(RelayProtocol.encode_frame(1, 2, RelayProtocol.BUNDLE_CHANNEL, RelayProtocol.MODE_RELIABLE, bundle))
	_peer.poll()
	assert_eq(_peer.get_available_packet_count(), 3)
	var got: Array = []
	while _peer.get_available_packet_count() > 0:
		got.append([_peer.get_packet_channel(), _peer.get_packet_mode(), _peer.get_packet_peer(), _peer.get_packet()])
	assert_eq(got, [[0, 2, 1, PackedByteArray([1])], [2, 1, 1, PackedByteArray([2])], [0, 2, 1, PackedByteArray([3])]])
	assert_eq(_peer.diagnostics.totals.packets_in, 3)
	assert_eq(_peer.diagnostics.totals.frames_in, 1)


func test_unreliable_packets_are_skipped_while_the_own_socket_is_backed_up() -> void:
	_enter(false, [2])
	_socket.outbound = RelayPeer.SOFT_OUTBOUND_BYTES + 1
	assert_eq(_put(1, RelayProtocol.MODE_UNRELIABLE_ORDERED, [1], 1), OK)
	assert_eq(_put(1, RelayProtocol.MODE_RELIABLE, [2]), OK)
	var frames := _game_frames()
	assert_eq(frames.size(), 1, "only the reliable packet")
	assert_eq(frames[0].mode, RelayProtocol.MODE_RELIABLE)
	assert_eq(_peer.diagnostics.totals.dropped_out, 1)


func test_a_reliable_packet_that_does_not_fit_ends_the_session() -> void:
	Diagnostics.reset_static()
	_enter(false, [2])
	_socket.refuse = true
	_put(1, RelayProtocol.MODE_UNRELIABLE, [1])
	assert_true(_peer.is_in_room(), "an unreliable packet is only skipped")
	_put(1, RelayProtocol.MODE_RELIABLE, [2])
	assert_true(_peer.is_in_room(), "not inside SceneMultiplayer's send")
	assert_eq(_put(1, RelayProtocol.MODE_RELIABLE, [3]), ERR_UNAVAILABLE)
	_peer.poll()
	assert_false(_peer.is_in_room())
	assert_eq(_left, [RelayProtocol.END_SLOW_CONSUMER])
	assert_eq(Diagnostics.last_disconnect.end_reason, "slow_consumer")
	assert_string_contains(Diagnostics.describe_last_disconnect(), "send buffer full")
	assert_eq(_peer.diagnostics.totals.send_errors, 1)


func test_old_unreliable_packets_of_a_backlog_are_thinned_out() -> void:
	_enter(false, [2])
	for i in 100:
		_socket.push_binary(RelayProtocol.encode_frame(1, 2, 2, RelayProtocol.MODE_UNRELIABLE_ORDERED, PackedByteArray([i])))
		if i % 25 == 0:
			_socket.push_binary(RelayProtocol.encode_frame(1, 2, 0, RelayProtocol.MODE_RELIABLE, PackedByteArray([200 + i / 25])))
	_peer.poll()
	assert_eq(_peer.get_available_packet_count(), RelayPeer.UNRELIABLE_KEEP + 4)
	var reliable: Array = []
	var unreliable: Array = []
	while _peer.get_available_packet_count() > 0:
		var mode := _peer.get_packet_mode()
		var data := _peer.get_packet()
		(reliable if mode == MultiplayerPeer.TRANSFER_MODE_RELIABLE else unreliable).append(data[0])
	assert_eq(reliable, [200, 201, 202, 203], "reliable packets all stay, in order")
	assert_eq(unreliable, range(100 - RelayPeer.UNRELIABLE_KEEP, 100), "the newest unreliable ones stay")
	assert_eq(_peer.diagnostics.totals.dropped_in, 100 - RelayPeer.UNRELIABLE_KEEP)


func test_a_few_waiting_packets_are_never_thinned() -> void:
	_enter(false, [2])
	for i in RelayPeer.BACKLOG_COLLAPSE_AT:
		_socket.push_binary(RelayProtocol.encode_frame(1, 2, 2, RelayProtocol.MODE_UNRELIABLE_ORDERED, PackedByteArray([i])))
	_peer.poll()
	assert_eq(_peer.get_available_packet_count(), RelayPeer.BACKLOG_COLLAPSE_AT)

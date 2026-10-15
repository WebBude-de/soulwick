class_name RelayPeer
extends MultiplayerPeerExtension
## Godot MultiplayerPeer over soulwick-relay (D-119, MP2): one WebSocket per game instance to
## ws(s)://<relay>/v1, protocol in RelayProtocol and soulwick-platform/packages/contracts/src/lobby.ts.
##
## Lifecycle: open(url, hello, action) connects, sends hello, waits for welcome and then sends the
## action (create or join). Until the room is entered the owner polls this peer itself (poll());
## with created/joined the peer becomes CONNECTED with its peer id (host 1, clients 2, 3, …) and
## the owner hands it to SceneMultiplayer (server_relay on) and calls set_delivering(true). Peer
## events are held back until then, so SceneMultiplayer sees every peer_connected.
## Host: peer_joined/peer_left become peer_connected/peer_disconnected. Client: only the host
## exists (peer_connected(1)); CLIENT_ROUTING=host_only, so every packet goes to peer 1 and
## SceneMultiplayer forwards client-to-client traffic through the host.
## Several runs per room: start closes the room for joins, end_run (host) opens it again; every
## member then gets run_ended and a room_state with started false.
## room_closed (left, host_left, kicked, expired, shutdown) or a closed socket end the session:
## peer_disconnected for everybody, status DISCONNECTED (D-123: host gone = session over).

signal welcomed(info: Dictionary)
## Created (peer_id 1) or joined (peer_id >= 2).
signal room_entered(room: Dictionary, peer_id: int)
## Every new room snapshot (created, joined, room_state).
signal room_updated(room: Dictionary)
signal room_started
## The host ended the run (end_run): the room is back in the lobby. reason: RunEndReason or "".
signal run_ended(reason: String)
## The receiver is no longer in the room (RoomClosedReason).
signal room_left(reason: String)
signal relay_error(code: String, message: String, request: String)
## The WebSocket closed (close code, -1 if it never opened).
signal connection_closed(code: int, reason: String)

enum Phase { IDLE, CONNECTING, HELLO, LOBBY, ENTERING, IN_ROOM, CLOSED }

## TESTWERT: WebSocket buffers (bytes) for bursts like the first spawn of every player.
const BUFFER_BYTES := 1 << 20

var phase := Phase.IDLE
## Last snapshot of the room (RoomInfo) and the welcome message.
var room: Dictionary = {}
var welcome: Dictionary = {}
## Code of the room this peer is or was in.
var room_code := ""
var close_code := 0
var close_reason := ""
## Replaceable for tests (anything with the WebSocketPeer methods used below).
var socket: Variant = null

var _hello: Dictionary = {}
var _action: Dictionary = {}
var _unique_id := 0
var _is_host := false
var _status := MultiplayerPeer.CONNECTION_DISCONNECTED
var _target_peer := 0
var _transfer_channel := 0
var _transfer_mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _refuse_new := false
var _max_packet_size := 65536 - RelayProtocol.FRAME_HEADER_BYTES
## Received game packets: {from, channel, mode, data}.
var _incoming: Array[Dictionary] = []
## Remote peers SceneMultiplayer knows (or will know once the events are delivered).
var _peers: Dictionary[int, bool] = {}
## [connected: bool, peer id] waiting for set_delivering(true).
var _pending_events: Array = []
var _delivering := false
## A leave was sent: game packets are dropped until the room_closed confirmation.
var _leaving := false


## Connects and sends hello; action (RelayProtocol.create/join) follows the welcome.
func open(url: String, hello: Dictionary, action: Dictionary) -> Error:
	if socket == null:
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = BUFFER_BYTES
		ws.outbound_buffer_size = BUFFER_BYTES
		socket = ws
	_hello = hello
	_action = action
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	phase = Phase.CONNECTING
	var error: Error = socket.connect_to_url(url)
	if error != OK:
		phase = Phase.CLOSED
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		close_code = -1
		close_reason = "connect_to_url failed: %s" % error_string(error)
	return error


func is_host() -> bool:
	return _is_host


func is_in_room() -> bool:
	return phase == Phase.IN_ROOM


## Lets peer events through to SceneMultiplayer (after multiplayer_peer was set to this peer).
func set_delivering(enabled: bool) -> void:
	_delivering = enabled


## Remote peer ids currently in the room as SceneMultiplayer sees them.
func get_remote_peers() -> Array[int]:
	var result: Array[int] = []
	result.assign(_peers.keys())
	return result


func send_control(message: Dictionary) -> Error:
	if socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNCONFIGURED
	return socket.send_text(JSON.stringify(message))


func leave() -> Error:
	_leaving = true
	return send_control({"type": "leave"})


## Host only: no joins until end_run (MP3 starts the run with it).
func start() -> Error:
	return send_control({"type": "start"})


## Host only: the run is over, joins and start work again (reason: RelayProtocol.RUN_END_*).
func end_run(reason := "") -> Error:
	return send_control(RelayProtocol.end_run(reason))


func kick(peer_id: int) -> Error:
	return send_control({"type": "kick", "peerId": peer_id})


# --- MultiplayerPeerExtension ---

func _poll() -> void:
	if socket == null or phase == Phase.IDLE:
		_flush_events()
		return
	socket.poll()
	var ready_state: int = socket.get_ready_state()
	if ready_state == WebSocketPeer.STATE_OPEN and phase == Phase.CONNECTING:
		phase = Phase.HELLO
		send_control(_hello)
	if ready_state == WebSocketPeer.STATE_OPEN or ready_state == WebSocketPeer.STATE_CLOSING:
		while socket.get_available_packet_count() > 0:
			var packet: PackedByteArray = socket.get_packet()
			if socket.was_string_packet():
				_handle_text(packet.get_string_from_utf8())
			else:
				_handle_binary(packet)
	elif ready_state == WebSocketPeer.STATE_CLOSED and phase != Phase.CLOSED:
		_on_socket_closed(socket.get_close_code(), socket.get_close_reason())
	_flush_events()


func _close() -> void:
	if socket != null and phase != Phase.CLOSED:
		if phase == Phase.IN_ROOM:
			leave()
		socket.close(1000, "bye")
	_end_session()
	phase = Phase.CLOSED
	_flush_events()


func _disconnect_peer(peer: int, _force: bool) -> void:
	if _is_host:
		kick(peer)
	elif peer == RelayProtocol.HOST_PEER_ID:
		leave()


func _get_available_packet_count() -> int:
	return _incoming.size() if _delivering else 0


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	var packet: Dictionary = _incoming.pop_front()
	return packet.data


func _get_packet_peer() -> int:
	return int(_incoming[0].from) if not _incoming.is_empty() else 0


func _get_packet_channel() -> int:
	return int(_incoming[0].channel) if not _incoming.is_empty() else 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	if _incoming.is_empty():
		return MultiplayerPeer.TRANSFER_MODE_RELIABLE
	return clampi(int(_incoming[0].mode), 0, 2) as MultiplayerPeer.TransferMode


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if phase != Phase.IN_ROOM or socket == null:
		return ERR_UNCONFIGURED
	if _leaving:
		return OK
	# Clients only ever talk to the host (CLIENT_ROUTING host_only); the host may address anyone.
	var to := _target_peer if _is_host else RelayProtocol.HOST_PEER_ID
	if buffer.size() > _max_packet_size:
		push_warning("RelayPeer: packet of %d bytes exceeds %d, dropped." % [buffer.size(), _max_packet_size])
		return ERR_INVALID_PARAMETER
	var frame := RelayProtocol.encode_frame(_unique_id, to, _transfer_channel, _transfer_mode, buffer)
	return socket.put_packet(frame)


func _get_max_packet_size() -> int:
	return _max_packet_size


func _set_target_peer(peer: int) -> void:
	_target_peer = peer


func _get_unique_id() -> int:
	return _unique_id


func _is_server() -> bool:
	return _is_host


func _is_server_relay_supported() -> bool:
	return true


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status


func _set_transfer_channel(channel: int) -> void:
	_transfer_channel = channel


func _get_transfer_channel() -> int:
	return _transfer_channel


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_transfer_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _transfer_mode


func _set_refuse_new_connections(enable: bool) -> void:
	_refuse_new = enable


func _is_refusing_new_connections() -> bool:
	return _refuse_new


# --- Incoming ---

func _handle_text(text: String) -> void:
	var message: Variant = JSON.parse_string(text)
	if not (message is Dictionary):
		push_warning("RelayPeer: unreadable control message: %s" % text.left(200))
		return
	match str(message.get("type", "")):
		"welcome":
			welcome = message
			var max_frame := int(message.get("maxFrameBytes", 0))
			if max_frame > RelayProtocol.FRAME_HEADER_BYTES:
				_max_packet_size = max_frame - RelayProtocol.FRAME_HEADER_BYTES
			phase = Phase.LOBBY
			welcomed.emit(message)
			if not _action.is_empty():
				phase = Phase.ENTERING
				send_control(_action)
		"created", "joined":
			_enter_room(message)
		"room_state":
			_set_room(message.get("room", {}))
			if _is_host and phase == Phase.IN_ROOM:
				_reconcile_peers()
			room_updated.emit(room)
		"peer_joined":
			var peer: Variant = message.get("peer", {})
			if _is_host and phase == Phase.IN_ROOM and peer is Dictionary:
				_peer_up(int(peer.get("peerId", 0)))
		"peer_left":
			if _is_host and phase == Phase.IN_ROOM:
				_peer_down(int(message.get("peerId", 0)))
		"started":
			room_started.emit()
		"run_ended":
			var reason: Variant = message.get("reason")
			run_ended.emit(str(reason) if reason != null else "")
		"room_closed":
			var reason := str(message.get("reason", RelayProtocol.CLOSED_LEFT))
			if phase == Phase.IN_ROOM:
				_end_session()
				phase = Phase.LOBBY
				_flush_events()
				room_left.emit(reason)
		"error":
			relay_error.emit(str(message.get("code", "internal")), str(message.get("message", "")), str(message.get("request", "")))
		"pong":
			pass
		_:
			push_warning("RelayPeer: unknown control message type '%s'." % message.get("type", ""))


func _handle_binary(packet: PackedByteArray) -> void:
	if phase != Phase.IN_ROOM:
		return
	var frame := RelayProtocol.decode_frame(packet)
	if frame.is_empty():
		return
	var from := int(frame.from)
	# Only packets of peers SceneMultiplayer knows (a client only hears the host).
	if not _peers.has(from):
		return
	_incoming.append({"from": from, "channel": frame.channel, "mode": frame.mode, "data": frame.data})


func _enter_room(message: Dictionary) -> void:
	var peer_id := int(message.get("peerId", 0))
	if peer_id <= 0:
		push_warning("RelayPeer: %s without peerId." % message.get("type", ""))
		return
	_unique_id = peer_id
	_is_host = peer_id == RelayProtocol.HOST_PEER_ID
	_leaving = false
	room_code = str(message.get("code", ""))
	_set_room(message.get("room", {}))
	phase = Phase.IN_ROOM
	_status = MultiplayerPeer.CONNECTION_CONNECTED
	if _is_host:
		_reconcile_peers()
	else:
		_peer_up(RelayProtocol.HOST_PEER_ID)
	room_entered.emit(room, peer_id)
	room_updated.emit(room)


func _set_room(value: Variant) -> void:
	if value is Dictionary:
		room = value
		room_code = str(room.get("code", room_code))


## Host: the room snapshot is the truth for who is connected (in case an event was missed).
func _reconcile_peers() -> void:
	var present: Dictionary[int, bool] = {}
	for peer: Variant in room.get("peers", []):
		if peer is Dictionary:
			var id := int(peer.get("peerId", 0))
			if id > 0 and id != _unique_id:
				present[id] = true
	for id in present:
		_peer_up(id)
	for id in _peers.keys():
		if not present.has(id):
			_peer_down(id)


func _peer_up(id: int) -> void:
	if id <= 0 or id == _unique_id or _peers.has(id):
		return
	_peers[id] = true
	_pending_events.append([true, id])


func _peer_down(id: int) -> void:
	if not _peers.has(id):
		return
	_peers.erase(id)
	_incoming.assign(_incoming.filter(func(packet: Dictionary) -> bool: return int(packet.from) != id))
	_pending_events.append([false, id])


func _on_socket_closed(code: int, reason: String) -> void:
	close_code = code
	close_reason = reason
	var was_in_room := phase == Phase.IN_ROOM
	_end_session()
	phase = Phase.CLOSED
	_flush_events()
	if was_in_room:
		room_left.emit(RelayProtocol.CLOSED_SHUTDOWN if code == RelayProtocol.CLOSE_SHUTDOWN else "disconnected")
	connection_closed.emit(code, reason)


## Everybody leaves, status DISCONNECTED (SceneMultiplayer: server_disconnected on clients).
func _end_session() -> void:
	for id in _peers.keys():
		_peer_down(id)
	_incoming.clear()
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED


func _flush_events() -> void:
	if not _delivering or _pending_events.is_empty():
		return
	var events := _pending_events
	_pending_events = []
	for event: Array in events:
		if event[0]:
			peer_connected.emit(event[1])
		else:
			peer_disconnected.emit(event[1])

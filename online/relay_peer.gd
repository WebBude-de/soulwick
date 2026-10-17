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
## Keepalive: once welcomed the peer sends its own ping every RelayProtocol.HEARTBEAT_SECONDS
## (round trip in last_rtt_msec) and declares the connection dead after SILENCE_TIMEOUT_SECONDS
## without any data (end reason "timeout"). A socket closed in a room ends the session with
## RelayProtocol.end_reason_for_close(code) (shutdown, timeout, slow_consumer, … or disconnected),
## a room_closed that arrived together with the close wins.
## Traffic (online test 16.10.2026, NetDiagnostics in `diagnostics`):
## - Bundles: Godot writes every put_packet straight into the socket, so each RPC was one WebSocket
##   message (TLS record, relay message token). Once a remote peer announced bundles
##   (RelayProtocol.CAPS_CHANNEL, sent to every peer that comes up), the packets for it are queued
##   per receiver and leave once per frame (deferred flush, at the latest at the next poll) as one
##   reliable and one unreliable bundle. Broadcasts are split per receiver, so every receiver keeps
##   the order of its reliable packets. Peers that never announced (older build) get plain frames.
## - Own backlog: above SOFT_OUTBOUND_BYTES queued in the socket, unreliable packets are not sent
##   (the next snapshot replaces them); a reliable packet that no longer fits ends the session as
##   slow_consumer instead of losing it silently (the worlds would drift apart).
## - Backlog after a hitch: when many packets wait at once, only the newest UNRELIABLE_KEEP
##   unreliable packets per sender and channel are kept (old snapshots would only be replayed).
## Host stall (D-183, a host's browser tab in the background stopped its game): a client measures
## the silence of peer 1 (game frames only, the relay's pongs do not count, a hang of the client
## itself neither) and keeps HostStall up to date at every poll; NetPlayerState stops predicting
## while is_host_stalled(). The host notices its own long frame gaps (host_hitched) so it can be
## told that its teammates waited. Follow-up of 17.10.2026: the host's world data stops on purpose
## at a world change (hide_from_peers, a client loading at its own pace), so a running host also sends
## a beat (RelayProtocol.BEAT_PAYLOAD, unreliable) at every poll to each room peer it sent nothing
## else to for HostStall.BEAT_MSEC, and before a world load of its own one with BEAT_LOADING
## (announce_loading, reliable, pushed out at once); a client does not count the silence after that
## for up to HostStall.LOAD_GRACE_MSEC. Beats never reach SceneMultiplayer. get_last_poll_msec() is
## the host's clock for the clients' input (NetPlayerState: catch-up physics steps after an own hitch
## run before the poll, their input waits in the socket and is not stale).

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
## Host with teammates in the room: its own frame stood still for gap_msec
## (HostStall.HOST_AWAY_NOTICE_MSEC or more; a hidden browser tab, a hang), the others waited.
signal host_hitched(gap_msec: int)

enum Phase { IDLE, CONNECTING, HELLO, LOBBY, ENTERING, IN_ROOM, CLOSED }

## Preloaded: works before the global class cache knows NetDiagnostics (new file).
const Diagnostics := preload("res://online/net_diagnostics.gd")
const HostStallScript := preload("res://online/host_stall.gd")

## TESTWERT: WebSocket buffers (bytes) for bursts like the first spawn of every player.
const BUFFER_BYTES := 1 << 20
## TESTWERT: WebSocket messages the socket may hold per direction (Godot's default is 4096).
const MAX_QUEUED_PACKETS := 8192
## TESTWERT: bytes waiting in the own socket above which unreliable packets are skipped.
const SOFT_OUTBOUND_BYTES := 256 * 1024
## TESTWERT: received packets waiting at once from which old unreliable ones are thinned out, and
## how many unreliable packets per sender, channel and mode survive.
const BACKLOG_COLLAPSE_AT := 64
const UNRELIABLE_KEEP := 8

## SOULWICK_NET_LEGACY=1: the sync as before the online test of 16.10.2026 (no bundles, the own
## player snaps at SNAP_DISTANCE, enemy snapshots without delta and extrapolation), for comparisons.
static var legacy_sync := OS.get_environment("SOULWICK_NET_LEGACY") == "1"
## Bundling may be used (SOULWICK_NET_BUNDLE=0 switches only it off; tests set it).
static var bundling_allowed := OS.get_environment("SOULWICK_NET_BUNDLE") != "0" and not legacy_sync
## Measurements only (environment, never set in a normal start): received game frames are held
## SOULWICK_NET_SIM_DELAY_MS +- SOULWICK_NET_SIM_JITTER_MS before the game sees them, in arrival
## order like TCP (a late frame holds back the ones behind it).
static var sim_delay_msec := int(OS.get_environment("SOULWICK_NET_SIM_DELAY_MS"))
static var sim_jitter_msec := int(OS.get_environment("SOULWICK_NET_SIM_JITTER_MS"))

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
## Round trip of the last heartbeat (ms), -1 before the first pong.
var last_rtt_msec := -1
## Why the last session ended on this peer (room_closed reason or end_reason_for_close), "" if none.
var end_reason := ""
## Tests move the clock forward with this (ms added to Time.get_ticks_msec()).
var time_offset_msec := 0
var _last_received_msec := 0
var _next_heartbeat_msec := 0
## Traffic, round trip, buffers, hitches and the disconnect reason of this connection.
var diagnostics: Diagnostics = Diagnostics.new()
## Remote peers that announced bundles (RelayProtocol.CAPS_CHANNEL).
var _bundle_peers: Dictionary[int, bool] = {}
## Per receiver: {"r": [[channel, mode, data], …], "rb": bytes, "u": […], "ub": bytes}.
var _queues: Dictionary[int, Dictionary] = {}
var _flush_scheduled := false
## The socket can report its queued bytes (a real WebSocketPeer; test fakes may not).
var _can_measure_outbound := false
## Limit of the socket's outbound buffer (0 = unknown, never pre-checked).
var _outbound_limit := 0
## A reliable packet could not be queued: the session ends at the next poll.
var _send_failed := ""
## Simulated latency: [release msec, frame] in arrival order.
var _delayed: Array[Array] = []
var _last_release_msec := 0
var _sim_rng := RandomNumberGenerator.new()
## Client: is the host's game standing still (D-183)? Updated at every poll in a room.
var host_stall: HostStallScript = HostStallScript.new()
## Host: how often its own frame stood still long enough to tell it (host_hitched), the last gap.
var host_away_count := 0
var last_host_away_msec := 0
## Time of this machine's last poll in a room and of the last game frame from the host (client).
var _last_poll_msec := 0
var _last_host_frame_msec := 0
## The next poll's frame gap is not a hang (a world was loaded on purpose, forgive_hitch()).
var _forgive_gap := false
## Host: when the last frame went to each room peer (local msec), for the beats.
var _last_sent_to: Dictionary[int, int] = {}
## Host: beats sent (tests and tools).
var beats_sent := 0
## Client: until when the host's silence does not count (it announced a world load; 0 = no grace).
var _host_loading_until := 0


## Connects and sends hello; action (RelayProtocol.create/join) follows the welcome.
func open(url: String, hello: Dictionary, action: Dictionary) -> Error:
	if socket == null:
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = BUFFER_BYTES
		ws.outbound_buffer_size = BUFFER_BYTES
		ws.max_queued_packets = MAX_QUEUED_PACKETS
		socket = ws
	_can_measure_outbound = socket.has_method(&"get_current_outbound_buffered_amount")
	_outbound_limit = int(socket.get(&"outbound_buffer_size")) if socket is WebSocketPeer else 0
	_hello = hello
	_action = action
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	phase = Phase.CONNECTING
	end_reason = ""
	_send_failed = ""
	diagnostics = Diagnostics.new(_now_msec())
	diagnostics.make_current()
	_last_received_msec = _now_msec()
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


## Client in a room: ms between the last poll and the host's last game frame (pongs of the relay do
## not count; a hang of this machine does not count either, its poll reads the waiting frames
## first). 0 for the host and outside a room.
func get_host_silence_msec() -> int:
	if _is_host or phase != Phase.IN_ROOM or _last_host_frame_msec <= 0:
		return 0
	return maxi(0, _last_poll_msec - _last_host_frame_msec)


## Client in a room: the host's game stands still (HostStall, with hysteresis).
func is_host_stalled() -> bool:
	return not _is_host and phase == Phase.IN_ROOM and host_stall.stalled


## How long the host's game stands still (ms, 0 when it runs).
func get_host_stall_msec() -> int:
	return host_stall.stall_msec(_now_msec()) if is_host_stalled() else 0


## Client: the host announced a world load and its silence does not count yet (HostStall.LOAD_GRACE_MSEC).
func is_host_loading() -> bool:
	return not _is_host and phase == Phase.IN_ROOM and _host_loading_until > 0 and _last_poll_msec < _host_loading_until


## Time of this machine's last poll in a room (the clock of RelayPeer, 0 before the first one): the
## moment received packets were last read.
func get_last_poll_msec() -> int:
	return _last_poll_msec if phase == Phase.IN_ROOM else 0


## The next poll's frame gap is no hang (a world was just loaded on purpose).
func forgive_hitch() -> void:
	_forgive_gap = true


## Host: it is about to load a world on purpose (a long frame). Everything queued and a beat with
## RelayProtocol.BEAT_LOADING go out to every room peer at once (the socket is polled to push them
## before the frame blocks), so the clients wait calmly instead of reporting a stall.
func announce_loading() -> void:
	if not _is_host or phase != Phase.IN_ROOM or socket == null or _peers.is_empty():
		return
	flush()
	_send_beats(_now_msec(), RelayProtocol.BEAT_LOADING)
	socket.poll()


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
	flush()
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
	if phase == Phase.IN_ROOM:
		diagnostics.note_poll(_now_msec())
		_note_own_gap(_now_msec())
		flush()
		if _is_host:
			_send_beats(_last_poll_msec)
	socket.poll()
	if phase == Phase.CLOSED:
		# Only finishes a close handshake; the session is already over.
		_flush_events()
		return
	if not _send_failed.is_empty() and phase == Phase.IN_ROOM:
		var why := _send_failed
		_send_failed = ""
		socket.close(1000, "send buffer full")
		_on_socket_closed(RelayProtocol.CLOSE_ABNORMAL, why, RelayProtocol.END_SLOW_CONSUMER)
		return
	var ready_state: int = socket.get_ready_state()
	if ready_state == WebSocketPeer.STATE_OPEN and phase == Phase.CONNECTING:
		phase = Phase.HELLO
		_last_received_msec = _now_msec()
		send_control(_hello)
	if ready_state != WebSocketPeer.STATE_CONNECTING:
		# Also when already CLOSED: a room_closed that came with the close frame still counts.
		_read_packets()
	if phase == Phase.IN_ROOM and not _is_host and host_stall.update(0 if is_host_loading() else get_host_silence_msec(), _last_poll_msec):
		diagnostics.note_host_stall(host_stall.stalled, host_stall.longest_msec)
	if ready_state == WebSocketPeer.STATE_CLOSED:
		_on_socket_closed(socket.get_close_code(), socket.get_close_reason())
	elif ready_state == WebSocketPeer.STATE_OPEN:
		_keep_alive()
	_flush_events()


func _read_packets() -> void:
	var count: int = socket.get_available_packet_count()
	if count > 0:
		_last_received_msec = _now_msec()
	for _i in count:
		if phase == Phase.CLOSED:
			return
		var packet: PackedByteArray = socket.get_packet()
		if socket.was_string_packet():
			_handle_text(packet.get_string_from_utf8())
		elif sim_delay_msec > 0 and phase == Phase.IN_ROOM:
			var release := maxi(_last_release_msec, _now_msec() + sim_delay_msec + _sim_rng.randi_range(-sim_jitter_msec, sim_jitter_msec))
			_last_release_msec = release
			_delayed.append([release, packet])
		else:
			_handle_binary(packet)
	while not _delayed.is_empty() and int(_delayed[0][0]) <= _now_msec() and phase == Phase.IN_ROOM:
		_handle_binary(_delayed.pop_front()[1])
	_collapse_backlog()
	diagnostics.note_buffers(_outbound_buffered(), _incoming.size())


## After a hitch (or while the world loads and nothing is delivered) many packets wait at once:
## old unreliable ones would only be replayed in one frame, the newest UNRELIABLE_KEEP per sender,
## channel and mode stay. Reliable packets are never touched.
func _collapse_backlog() -> void:
	if _incoming.size() <= BACKLOG_COLLAPSE_AT:
		return
	var seen: Dictionary[int, int] = {}
	var kept: Array[Dictionary] = []
	var dropped := 0
	for i in range(_incoming.size() - 1, -1, -1):
		var packet := _incoming[i]
		var mode := int(packet.mode)
		if mode != RelayProtocol.MODE_RELIABLE:
			var key := (int(packet.from) << 12) | (int(packet.channel) << 2) | mode
			var count: int = seen.get(key, 0)
			if count >= UNRELIABLE_KEEP:
				dropped += 1
				continue
			seen[key] = count + 1
		kept.append(packet)
	if dropped > 0:
		kept.reverse()
		_incoming = kept
		diagnostics.note_dropped(false, dropped)


## Heartbeat ping and the silence check (only after welcome: before it the relay wants hello).
func _keep_alive() -> void:
	if phase != Phase.LOBBY and phase != Phase.ENTERING and phase != Phase.IN_ROOM:
		return
	var now := _now_msec()
	if now - _last_received_msec >= int(RelayProtocol.SILENCE_TIMEOUT_SECONDS * 1000.0):
		var silent := float(now - _last_received_msec) / 1000.0
		socket.close(1000, "no data from the relay")
		_on_socket_closed(RelayProtocol.CLOSE_ABNORMAL, "no data from the relay for %.0f s" % silent, RelayProtocol.END_TIMEOUT)
		return
	if now >= _next_heartbeat_msec:
		_next_heartbeat_msec = now + int(RelayProtocol.HEARTBEAT_SECONDS * 1000.0)
		send_control(RelayProtocol.ping(now))


func _now_msec() -> int:
	return Time.get_ticks_msec() + time_offset_msec


## Every poll in a room: remembers its time (the host's silence counts up to it) and, on the host
## with teammates, reports a long gap since the previous poll (host_hitched).
func _note_own_gap(now: int) -> void:
	var previous := _last_poll_msec
	_last_poll_msec = now
	if _forgive_gap or previous <= 0:
		_forgive_gap = false
		return
	var gap := now - previous
	if _is_host and gap >= HostStallScript.HOST_AWAY_NOTICE_MSEC and not _peers.is_empty():
		host_away_count += 1
		last_host_away_msec = gap
		diagnostics.note_host_away(gap)
		host_hitched.emit(gap)


## Host: a beat to every room peer it sent nothing to for HostStall.BEAT_MSEC (flags 0, unreliable:
## the next one replaces a lost one), or to all of them at once with flags (BEAT_LOADING, reliable).
func _send_beats(now: int, flags := 0) -> void:
	if _leaving or not _send_failed.is_empty() or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var mode := RelayProtocol.MODE_RELIABLE if flags != 0 else RelayProtocol.MODE_UNRELIABLE
	for peer in _peers.keys():
		if flags == 0 and now - int(_last_sent_to.get(peer, 0)) < HostStallScript.BEAT_MSEC:
			continue
		if _send_frame(peer, RelayProtocol.CAPS_CHANNEL, mode, RelayProtocol.beat_payload(flags), 0, false) == OK:
			beats_sent += 1


## Host: frames that reached the socket count as a sign of life for their receivers (no beat needed).
func _note_sent_to(to: int) -> void:
	if not _is_host:
		return
	var now := _now_msec()
	if to > 0:
		_last_sent_to[to] = now
		return
	for peer in _peers:
		if peer != -to:
			_last_sent_to[peer] = now


## Seconds since the relay last sent anything (diagnostics).
func get_silence_seconds() -> float:
	return float(_now_msec() - _last_received_msec) / 1000.0


func _close() -> void:
	if socket != null and phase != Phase.CLOSED:
		if phase == Phase.IN_ROOM:
			flush()
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
	if not _send_failed.is_empty():
		return ERR_UNAVAILABLE
	# Clients only ever talk to the host (CLIENT_ROUTING host_only); the host may address anyone.
	var to := _target_peer if _is_host else RelayProtocol.HOST_PEER_ID
	if buffer.size() > _max_packet_size:
		push_warning("RelayPeer: packet of %d bytes exceeds %d, dropped." % [buffer.size(), _max_packet_size])
		return ERR_INVALID_PARAMETER
	var reliable := _transfer_mode == MultiplayerPeer.TRANSFER_MODE_RELIABLE
	if not reliable and _outbound_buffered() > SOFT_OUTBOUND_BYTES:
		# The line does not keep up: the next snapshot replaces this one.
		diagnostics.note_dropped(true)
		return OK
	var receivers := _bundle_receivers(to, buffer.size())
	if receivers.is_empty():
		# Plain frame; everything queued before it leaves first (order of reliable packets).
		flush()
		return _send_frame(to, _transfer_channel, _transfer_mode, buffer, 1, false)
	for receiver in receivers:
		_enqueue(receiver, _transfer_channel, _transfer_mode, buffer)
	return OK


## Sends every queued bundle (also called deferred after the first packet of a frame and at every
## poll; public for tests and tools).
func flush() -> void:
	_flush_scheduled = false
	if _queues.is_empty():
		return
	var queues := _queues
	_queues = {}
	for receiver in queues:
		var queue := queues[receiver]
		_send_queue(receiver, queue.r, true)
		_send_queue(receiver, queue.u, false)


## Receivers a packet to `to` can be bundled for: every addressed peer must have announced bundles
## (else [] and the packet goes as a plain frame). Broadcasts are split per receiver.
func _bundle_receivers(to: int, size: int) -> Array[int]:
	var result: Array[int] = []
	if not bundling_allowed or _bundle_peers.is_empty() or size + RelayProtocol.BUNDLE_ENTRY_HEADER > mini(_max_packet_size, RelayProtocol.BUNDLE_ENTRY_MAX):
		return result
	if to > 0:
		if _bundle_peers.has(to):
			result.append(to)
		return result
	for peer in _peers:
		if to < 0 and peer == -to:
			continue
		if not _bundle_peers.has(peer):
			result.clear()
			return result
		result.append(peer)
	return result


func _enqueue(receiver: int, channel: int, mode: int, data: PackedByteArray) -> void:
	if not _queues.has(receiver):
		_queues[receiver] = {"r": [], "rb": 0, "u": [], "ub": 0}
	var queue := _queues[receiver]
	var reliable := mode == MultiplayerPeer.TRANSFER_MODE_RELIABLE
	var list_key := "r" if reliable else "u"
	var bytes_key := "rb" if reliable else "ub"
	var size := data.size() + RelayProtocol.BUNDLE_ENTRY_HEADER
	if int(queue[bytes_key]) + size > _max_packet_size:
		_send_queue(receiver, queue[list_key], reliable)
		queue[list_key] = []
		queue[bytes_key] = 0
	(queue[list_key] as Array).append([channel, mode, data])
	queue[bytes_key] = int(queue[bytes_key]) + size
	if not _flush_scheduled:
		_flush_scheduled = true
		flush.call_deferred()


## One queue of one receiver: a single packet as a plain frame, several as one bundle.
func _send_queue(receiver: int, entries: Array, reliable: bool) -> void:
	if entries.is_empty():
		return
	if not reliable and _outbound_buffered() > SOFT_OUTBOUND_BYTES:
		diagnostics.note_dropped(true, entries.size())
		return
	if entries.size() == 1:
		var entry: Array = entries[0]
		_send_frame(receiver, int(entry[0]), int(entry[1]), entry[2], 1, false)
		return
	var mode := RelayProtocol.MODE_RELIABLE if reliable else RelayProtocol.MODE_UNRELIABLE_ORDERED
	_send_frame(receiver, RelayProtocol.BUNDLE_CHANNEL, mode, RelayProtocol.encode_bundle(entries), entries.size(), true)


func _send_frame(to: int, channel: int, mode: int, payload: PackedByteArray, packets: int, bundled: bool) -> Error:
	if phase != Phase.IN_ROOM or socket == null or not _send_failed.is_empty():
		return ERR_UNCONFIGURED
	var frame := RelayProtocol.encode_frame(_unique_id, to, channel, mode, payload)
	var reliable := mode == RelayProtocol.MODE_RELIABLE
	# Checked here: Godot would refuse the packet with an engine error line per packet.
	if _outbound_limit > 0 and _outbound_buffered() + frame.size() > _outbound_limit:
		if not reliable:
			diagnostics.note_dropped(true, packets)
			return OK
		_fail_send(frame.size())
		return ERR_OUT_OF_MEMORY
	var error: Error = socket.put_packet(frame)
	if error != OK:
		if reliable:
			_fail_send(frame.size())
		else:
			diagnostics.note_dropped(true, packets)
		return error
	diagnostics.note_sent(frame.size(), packets, bundled)
	_note_sent_to(to)
	return OK


## A reliable packet did not fit into the socket: without it the machines drift apart, so the
## session ends (at the next poll, outside SceneMultiplayer's send) as slow_consumer.
func _fail_send(frame_bytes: int) -> void:
	diagnostics.note_send_error()
	if _send_failed.is_empty():
		_send_failed = "send buffer full: %d bytes queued, frame of %d bytes" % [_outbound_buffered(), frame_bytes]
		push_warning("RelayPeer: %s. %s" % [_send_failed, diagnostics.summary_line()])


func _outbound_buffered() -> int:
	return int(socket.get_current_outbound_buffered_amount()) if _can_measure_outbound and socket != null else 0


## Tells a remote peer that this machine reads bundles (once per peer that comes up).
func _announce_bundles(peer: int) -> void:
	if not bundling_allowed or phase != Phase.IN_ROOM or socket == null:
		return
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_send_frame(peer, RelayProtocol.CAPS_CHANNEL, RelayProtocol.MODE_RELIABLE, RelayProtocol.caps_payload(), 0, false)


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
			_next_heartbeat_msec = _now_msec() + int(RelayProtocol.HEARTBEAT_SECONDS * 1000.0)
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
				end_reason = reason
				diagnostics.note_disconnect(0, "room_closed", reason, get_silence_seconds(), _now_msec())
				_end_session()
				phase = Phase.LOBBY
				_flush_events()
				room_left.emit(reason)
		"error":
			var code := str(message.get("code", "internal"))
			diagnostics.note_relay_error(code)
			if code in ["rate_limited", "frame_too_large", "invalid_message"]:
				# Dropped game packets at the relay (at most one notice per second): the log says
				# what this machine sent at the time.
				push_warning("RelayPeer: relay error %s '%s'. %s" % [code, message.get("message", ""), diagnostics.summary_line()])
			relay_error.emit(code, str(message.get("message", "")), str(message.get("request", "")))
		"pong":
			var sent: Variant = message.get("t")
			if sent is float or sent is int:
				last_rtt_msec = maxi(0, _now_msec() - int(sent))
				diagnostics.note_rtt(last_rtt_msec)
		_:
			push_warning("RelayPeer: unknown control message type '%s'." % message.get("type", ""))


func _handle_binary(packet: PackedByteArray) -> void:
	if phase != Phase.IN_ROOM:
		return
	var frame := RelayProtocol.decode_frame(packet)
	if frame.is_empty():
		return
	var from := int(frame.from)
	var from_host := from == RelayProtocol.HOST_PEER_ID and not _is_host
	if from_host:
		_last_host_frame_msec = _now_msec()
		# Any frame after a load announcement: the host runs again.
		_host_loading_until = 0
	var channel := int(frame.channel)
	var data: PackedByteArray = frame.data
	if channel == RelayProtocol.CAPS_CHANNEL and RelayProtocol.is_beat(data):
		# The host's sign of life; nothing for SceneMultiplayer.
		diagnostics.note_received(packet.size(), 0)
		if from_host and RelayProtocol.beat_flags(data) & RelayProtocol.BEAT_LOADING:
			_host_loading_until = _last_host_frame_msec + HostStallScript.LOAD_GRACE_MSEC
		return
	if channel == RelayProtocol.CAPS_CHANNEL and RelayProtocol.is_caps(data):
		diagnostics.note_received(packet.size(), 0)
		if from > 0 and from != _unique_id:
			_bundle_peers[from] = true
			diagnostics.bundling = bundling_allowed
		return
	# Only packets of peers SceneMultiplayer knows (a client only hears the host).
	if not _peers.has(from):
		return
	if channel == RelayProtocol.BUNDLE_CHANNEL:
		var entries := RelayProtocol.decode_bundle(data)
		if not entries.is_empty():
			diagnostics.note_received(packet.size(), entries.size(), true)
			for entry: Array in entries:
				_incoming.append({"from": from, "channel": entry[0], "mode": entry[1], "data": entry[2]})
			return
	diagnostics.note_received(packet.size())
	_incoming.append({"from": from, "channel": channel, "mode": frame.mode, "data": data})


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
	diagnostics.role = "host" if _is_host else "client"
	diagnostics.room_code = room_code
	diagnostics.reset_poll_clock()
	# The host counts as heard at the start (the client loads its village first).
	_last_poll_msec = _now_msec()
	_last_host_frame_msec = _last_poll_msec
	_forgive_gap = true
	_host_loading_until = 0
	_last_sent_to.clear()
	host_stall.reset()
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
	# The first beat is due HostStall.BEAT_MSEC after a peer came up (its capability frame counts).
	_last_sent_to[id] = _now_msec()
	_pending_events.append([true, id])
	_announce_bundles(id)


func _peer_down(id: int) -> void:
	if not _peers.has(id):
		return
	_peers.erase(id)
	_bundle_peers.erase(id)
	_queues.erase(id)
	_last_sent_to.erase(id)
	diagnostics.bundling = bundling_allowed and not _bundle_peers.is_empty()
	_incoming.assign(_incoming.filter(func(packet: Dictionary) -> bool: return int(packet.from) != id))
	_pending_events.append([false, id])


## forced_reason: the game itself gave up on the connection (silence), else the close code decides.
func _on_socket_closed(code: int, reason: String, forced_reason := "") -> void:
	close_code = code
	close_reason = reason
	var was_in_room := phase == Phase.IN_ROOM
	if was_in_room:
		end_reason = forced_reason if not forced_reason.is_empty() else RelayProtocol.end_reason_for_close(code)
		diagnostics.note_disconnect(code, reason, end_reason, get_silence_seconds(), _now_msec())
		# In godot.log of every player: the evening's report can match it to the relay log.
		push_warning("RelayPeer: connection to room %s lost at %s: close %d '%s' -> %s; last data %.1f s ago, rtt %d ms. %s" % [
			room_code, Time.get_datetime_string_from_system(), code, reason, end_reason, get_silence_seconds(), last_rtt_msec, diagnostics.summary_line()])
	_end_session()
	phase = Phase.CLOSED
	_flush_events()
	if was_in_room:
		room_left.emit(end_reason)
	connection_closed.emit(code, reason)


## Everybody leaves, status DISCONNECTED (SceneMultiplayer: server_disconnected on clients).
func _end_session() -> void:
	for id in _peers.keys():
		_peer_down(id)
	_incoming.clear()
	_delayed.clear()
	_queues.clear()
	_bundle_peers.clear()
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

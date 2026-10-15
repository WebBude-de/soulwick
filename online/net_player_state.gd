class_name NetPlayerState
extends Node
## Network state of one player in a room (MP2, host authority, MULTIPLAYER.md §2). Child "NetState"
## of every player spawned by NetPlayers; its MultiplayerSynchronizer sends pos, move, aim and held
## from the host to everybody.
## - Host: copies its simulation into the synced properties every physics frame (its own player
##   from the keyboard, the clients' players from the input they send with submit_input).
## - Client, own player: simulates locally from the keyboard (light prediction), sends its input to
##   the host and glides back to the host's position once both stand still; far off = snap.
## - Client, other players: RemoteInput from the synced input (walk/dash animations come from the
##   normal player code) plus a soft pull towards the synced position.
## Interact is never sent or applied for other players: doors open only for the player at a machine.
## Side-view segments (M5): velocity and the side state (ladder, ground, jump, pit, facing) travel
## too; other players replay them with gravity (PlayerSideMotion.apply_remote_state), the own
## player is corrected only while it stands on the ground.

const NODE_NAME := &"NetState"
const SYNCED_PROPERTIES: Array[StringName] = [&"pos", &"move", &"aim", &"held", &"vel", &"side"]
## TESTWERT: synchronizer interval in seconds.
const SYNC_INTERVAL := 1.0 / 30.0
## TESTWERT: further off than this (px) the player jumps to the host position.
const SNAP_DISTANCE := 96.0
## TESTWERT: share of the remaining error corrected per second for other players and for the own
## player while standing still.
const CORRECTION_RATE := 10.0
const SELF_CORRECTION_RATE := 8.0
## TESTWERT: input is sent on change and at least every N physics frames.
const SEND_EVERY_FRAMES := 10
const INTERACT_BIT := 1 << 4
## Bits of side (M5).
const SIDE_ACTIVE := 1
const SIDE_CLIMBING := 1 << 1
const SIDE_ON_FLOOR := 1 << 2
const SIDE_JUMPING := 1 << 3
const SIDE_IN_PIT := 1 << 4
const SIDE_FACING_LEFT := 1 << 5
## TESTWERT: seconds the host's copy may be in another view (segment / room) than this machine's
## copy before it is corrected anyway (the own transit starts and ends a little later than the host's).
const VIEW_MISMATCH_GRACE := 2.0

## Synced from the host.
var pos := Vector2.ZERO
var move := Vector2.ZERO
var aim := Vector2.RIGHT
var held := 0
var vel := Vector2.ZERO
## Side-view state as SIDE_* bits, 0 in the top-down view.
var side := 0
## Peer that owns this player (1 = host).
var peer_id := 0

var _player: Player = null
var _last_sent: Array = []
var _frames_since_send := 0
var _mismatch_time := 0.0


static func create(owner_peer: int, start: Vector2) -> NetPlayerState:
	var state := NetPlayerState.new()
	state.name = NODE_NAME
	state.peer_id = owner_peer
	state.pos = start
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	# Rooted at the player (the node the spawner creates): its visibility decides where the player is
	# spawned and despawned (MP3, NetPlayers._show_to / hide_from_peers).
	sync.root_path = NodePath("../..")
	sync.replication_interval = SYNC_INTERVAL
	var config := SceneReplicationConfig.new()
	for property in SYNCED_PROPERTIES:
		var path := NodePath("%s:%s" % [NODE_NAME, property])
		config.add_property(path)
		config.property_set_spawn(path, true)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	state.add_child(sync)
	return state


## Actions held as bits in PlayerInput.ACTIONS order (interact = bit 4).
static func bits_of(input: PlayerInput) -> int:
	var bits := 0
	for i in PlayerInput.ACTIONS.size():
		if input.is_pressed(PlayerInput.ACTIONS[i]):
			bits |= 1 << i
	return bits


static func actions_of(bits: int) -> Array[StringName]:
	var actions: Array[StringName] = []
	for i in PlayerInput.ACTIONS.size():
		if bits & (1 << i):
			actions.append(PlayerInput.ACTIONS[i])
	return actions


## Side-view state of player as SIDE_* bits (0 outside a segment).
static func side_bits_of(player: Player) -> int:
	if player == null or not player.is_side_view():
		return 0
	var motion := player.side_motion
	var bits := SIDE_ACTIVE
	if motion.is_climbing():
		bits |= SIDE_CLIMBING
	if motion.is_on_floor():
		bits |= SIDE_ON_FLOOR
	if motion.is_jumping():
		bits |= SIDE_JUMPING
	if motion.is_in_pit():
		bits |= SIDE_IN_PIT
	if motion.facing < 0.0:
		bits |= SIDE_FACING_LEFT
	return bits


func _ready() -> void:
	_player = get_parent() as Player


func get_player() -> Player:
	return _player


func get_synchronizer() -> MultiplayerSynchronizer:
	return get_node_or_null(^"Sync") as MultiplayerSynchronizer


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or not _has_session():
		return
	if multiplayer.is_server():
		pos = _player.position
		move = _player.input.move
		aim = _player.get_aim_direction()
		held = bits_of(_player.input) & ~INTERACT_BIT
		vel = _player.velocity
		side = side_bits_of(_player)
	elif _player.is_local:
		_send_input()
		_correct_self(delta)
	else:
		_follow(delta)


## Host: the owning client's input for its player (NetRun.submit_input: unreliable ordered,
## channel 1, through a node every machine has, so a world change never loses a packet path).
func apply_input(sender: int, new_move: Vector2, new_aim: Vector2, new_held: int) -> void:
	if not multiplayer.is_server() or sender != peer_id:
		return
	var remote := _player.input as RemoteInput if _player != null else null
	if remote == null:
		return
	remote.set_move(new_move)
	if new_aim != Vector2.ZERO:
		remote.set_aim_direction(new_aim)
	remote.set_held_actions(actions_of(new_held & ~INTERACT_BIT))


func _has_session() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer) and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _send_input() -> void:
	var input := _player.input
	var state := [input.move, _player.get_aim_direction(), bits_of(input) & ~INTERACT_BIT]
	_frames_since_send += 1
	if state == _last_sent and _frames_since_send < SEND_EVERY_FRAMES:
		return
	_last_sent = state
	_frames_since_send = 0
	var lobby := LobbyClient.find(self)
	if lobby != null and lobby.net_run != null:
		lobby.net_run.submit_input.rpc_id(RelayProtocol.HOST_PEER_ID, state[0], state[1], state[2])


## Own player on a client: keep the local simulation, glide to the host once both stand still.
func _correct_self(delta: float) -> void:
	if not _views_agree(delta):
		return
	var error := pos - _player.position
	if error.length() > SNAP_DISTANCE:
		_player.position = pos
	elif _player.input.move == Vector2.ZERO and move == Vector2.ZERO and error.length_squared() > 0.25 and _stands_with_host():
		_player.position += error * minf(1.0, SELF_CORRECTION_RATE * delta)


## Both copies are in the same view (side segment or rooms), or have been apart for too long. While
## one machine's transit runs ahead, positions of the other view are not applied (no jump into the
## segment before this machine built it, no fall through a room after it).
func _views_agree(delta: float) -> bool:
	var agree := ((side & SIDE_ACTIVE) != 0) == _player.is_side_view()
	_mismatch_time = 0.0 if agree else _mismatch_time + delta
	return agree or _mismatch_time >= VIEW_MISMATCH_GRACE


## Side view: the own player glides back only while both copies stand on the ground (never in a
## jump, on a ladder or in a pit, where the host's position lags behind the own one).
func _stands_with_host() -> bool:
	if not _player.is_side_view():
		return true
	var own := side_bits_of(_player)
	var standing := SIDE_ACTIVE | SIDE_ON_FLOOR
	return own & (standing | SIDE_CLIMBING | SIDE_IN_PIT) == standing and side & (standing | SIDE_CLIMBING | SIDE_IN_PIT) == standing


## Other players on a client: replay their input, pull towards the synced position.
func _follow(delta: float) -> void:
	var remote := _player.input as RemoteInput
	if remote != null:
		remote.set_move(move)
		if aim != Vector2.ZERO:
			remote.set_aim_direction(aim)
		remote.set_held_actions(actions_of(held & ~INTERACT_BIT))
	if not _views_agree(delta):
		return
	if _player.is_side_view() and side & SIDE_ACTIVE:
		# Gravity and jumps run here as at the host: start from its velocity, climb where it climbs.
		_player.velocity = vel
		_player.side_motion.apply_remote_state(side & SIDE_CLIMBING != 0, side & SIDE_IN_PIT != 0,
				-1.0 if side & SIDE_FACING_LEFT else 1.0)
	var error := pos - _player.position
	if error.length() > SNAP_DISTANCE:
		_player.position = pos
	else:
		_player.position += error * minf(1.0, CORRECTION_RATE * delta)

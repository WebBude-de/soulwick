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
## Side-view segments (M5): velocity and the side state (ladder, ground, jump, pit, facing, wall
## slide, double jump used) travel too; other players replay them with gravity
## (PlayerSideMotion.apply_remote_state / apply_remote_air_state; their jumps and landings are the
## host's, NetSide.side_move_net), the own player is corrected only while it stands on the ground.
## Weapons (online test 15.10.2026): the active weapon slot is state, not a replayed toggle. It
## travels in the same bits as the held actions (ACTIVE_SLOT_*), so an attack in a packet always
## runs with the weapon its owner held: the owner's machine decides it (own player: this machine;
## the host takes a client's slot from its input), every other copy follows. The weapon-switch
## button is never replayed - two copies that toggled from different states (a press during a room
## intro that locks only one copy, a loadout plus the replayed press) showed the other weapon for
## the rest of the run. The weapons in the slots come from NetDungeon (loadout, submit_weapon).
## Rubber band (online test 16.10.2026): the host's position of the own player is always one round
## trip old; while dashing (450 px/s) or after a late packet that alone was more than SNAP_DISTANCE
## and pulled the player back. Now the own player keeps HISTORY_SECONDS of its own positions and
## only corrects when the host's position is far from all of them (a real disagreement: blocked,
## knocked back, teleported) - with a quick glide, a jump only beyond HARD_SNAP_DISTANCE; a lagging
## host position is ignored while moving. snap_count counts the corrections (tools/net_smoke.gd
## load=). Other players in the side view take the host's velocity once per received state and are
## not pulled while in the air (their arc comes from that velocity and the same gravity).

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
## Weapon switch (PlayerInput.SWITCH_WEAPON): sent, never replayed (the active slot travels instead).
const SWITCH_BIT := 1 << 3
## Held actions a copy replays: everything but interact and the weapon switch.
const REPLAY_MASK := ~(INTERACT_BIT | SWITCH_BIT)
## Active weapon slot + 1 in bits 8..10 of held (0 = unknown, keep the copy's slot).
const ACTIVE_SLOT_SHIFT := 8
const ACTIVE_SLOT_MASK := 0b111 << ACTIVE_SLOT_SHIFT
## Bits of side (M5).
const SIDE_ACTIVE := 1
const SIDE_CLIMBING := 1 << 1
const SIDE_ON_FLOOR := 1 << 2
const SIDE_JUMPING := 1 << 3
const SIDE_IN_PIT := 1 << 4
const SIDE_FACING_LEFT := 1 << 5
## Air state of the side view (double jump, wall slide): the host decides, copies show it.
const SIDE_WALL_SLIDING := 1 << 6
const SIDE_WALL_RIGHT := 1 << 7
const SIDE_DOUBLE_JUMPED := 1 << 8
## TESTWERT: seconds the host's copy may be in another view (segment / room) than this machine's
## copy before it is corrected anyway (the own transit starts and ends a little later than the host's).
const VIEW_MISMATCH_GRACE := 2.0
## TESTWERT: seconds of own positions a client keeps to recognise the host's (older) position, and
## how close (px) the host's position must be to one of them to count as "where I was".
const HISTORY_SECONDS := 1.0
const HISTORY_TOLERANCE := 24.0
## TESTWERTE: a real disagreement of the own player is closed by this share per second (a quick
## glide instead of a jump); only further off than HARD_SNAP_DISTANCE it jumps.
const RECONCILE_RATE := 15.0
const HARD_SNAP_DISTANCE := 256.0

## Jumps to the host's position (own player and other players) on this machine.
static var snaps_total := 0

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
## Host: the active weapon slot the owning client holds (-1 = not known yet).
var _wanted_slot := -1
## Jumps of this player's copy to the host's position.
var snap_count := 0
## Client, own player: recent positions [msec, Vector2], oldest first.
var _history: Array[Array] = []
## Client: a new state arrived from the host since the last physics frame (the synced velocity is
## applied once per state, not every frame: an old jump velocity re-applied every frame lifted the
## copy too high and the position pull dragged it back, side view, online test 16.10.2026).
var _fresh_sync := false
## Client, own player: gliding to the host's position after a real disagreement.
var _reconciling := false


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


## Bits of player's active weapon slot for held (ACTIVE_SLOT_*).
static func slot_bits_of(player: Player) -> int:
	if player == null or player.weapon_controller == null:
		return 0
	return ((player.weapon_controller.get_active_slot() + 1) << ACTIVE_SLOT_SHIFT) & ACTIVE_SLOT_MASK


## Active weapon slot in held bits, -1 if they carry none.
static func slot_of(bits: int) -> int:
	return ((bits & ACTIVE_SLOT_MASK) >> ACTIVE_SLOT_SHIFT) - 1


## Every bit that is to travel for player: held actions (not interact) and the active weapon slot.
static func held_bits_of(player: Player) -> int:
	return (bits_of(player.input) & ~INTERACT_BIT) | slot_bits_of(player)


## The owner's weapon slot on a copy (no effect while that slot is still empty: the weapon comes
## with the next loadout, and the slot is applied again every frame).
static func apply_slot(player: Player, bits: int) -> void:
	var slot := slot_of(bits)
	if slot >= 0 and player != null and player.weapon_controller != null:
		player.weapon_controller.set_active_slot(slot)


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
	if motion.is_wall_sliding:
		bits |= SIDE_WALL_SLIDING
	if motion.wall_side > 0:
		bits |= SIDE_WALL_RIGHT
	if motion.has_double_jumped:
		bits |= SIDE_DOUBLE_JUMPED
	return bits


func _ready() -> void:
	_player = get_parent() as Player
	var sync := get_synchronizer()
	if sync != null:
		sync.synchronized.connect(func() -> void: _fresh_sync = true)


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
		if not _player.is_local and _wanted_slot >= 0:
			# A client's weapon may arrive after the slot that holds it (submit_weapon, reliable).
			_player.weapon_controller.set_active_slot(_wanted_slot)
		held = held_bits_of(_player)
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
	remote.set_held_actions(actions_of(new_held & REPLAY_MASK))
	# Before the player's next physics step reads the attack of this packet.
	_wanted_slot = slot_of(new_held)
	apply_slot(_player, new_held)


func _has_session() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer) and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _send_input() -> void:
	var input := _player.input
	var state := [input.move, _player.get_aim_direction(), held_bits_of(_player)]
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
	_remember_position(Time.get_ticks_msec(), _player.position)
	if not _views_agree(delta):
		return
	var error := pos - _player.position
	var distance := error.length()
	if distance > SNAP_DISTANCE and not was_recently_at(pos):
		if distance > HARD_SNAP_DISTANCE or RelayPeer.legacy_sync:
			_snap_to(pos)
			_history.clear()
			_reconciling = false
			return
		if not _reconciling:
			_reconciling = true
			snap_count += 1
			snaps_total += 1
	elif _reconciling and (distance <= HISTORY_TOLERANCE or was_recently_at(pos)):
		_reconciling = false
	if _reconciling:
		_player.position += error * minf(1.0, RECONCILE_RATE * delta)
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
		remote.set_held_actions(actions_of(held & REPLAY_MASK))
	apply_slot(_player, held)
	if not _views_agree(delta):
		return
	if _player.is_side_view() and side & SIDE_ACTIVE:
		# Gravity runs here as at the host: start from its velocity, climb where it climbs. Jumps,
		# wall slides and landings are the host's (NetSide.side_move_net, the air bits).
		var motion := _player.side_motion
		motion.moves_from_remote = true
		if _fresh_sync or RelayPeer.legacy_sync:
			_player.velocity = vel
		motion.apply_remote_state(side & SIDE_CLIMBING != 0, side & SIDE_IN_PIT != 0,
				-1.0 if side & SIDE_FACING_LEFT else 1.0)
		motion.apply_remote_air_state(side & SIDE_WALL_SLIDING != 0, 1 if side & SIDE_WALL_RIGHT else -1,
				side & SIDE_DOUBLE_JUMPED != 0)
	_fresh_sync = false
	var error := pos - _player.position
	if error.length() > SNAP_DISTANCE:
		_snap_to(pos)
	elif not _airborne_copy() or RelayPeer.legacy_sync:
		_player.position += error * minf(1.0, CORRECTION_RATE * delta)


## Side view: the copy or the host's player is in the air. Its arc comes from the host's velocity
## and the same gravity here; pulling it towards the host's older position would drag it back
## (online test 16.10.2026), so it is corrected once both stand again.
func _airborne_copy() -> bool:
	if not _player.is_side_view() or not (side & SIDE_ACTIVE):
		return false
	var own := side_bits_of(_player)
	return own & (SIDE_ON_FLOOR | SIDE_CLIMBING) == 0 or side & (SIDE_ON_FLOOR | SIDE_CLIMBING) == 0


func _snap_to(target: Vector2) -> void:
	_player.position = target
	snap_count += 1
	snaps_total += 1


## Client, own player: this frame's position into the history (older than HISTORY_SECONDS drops).
func _remember_position(now_msec: int, at: Vector2) -> void:
	_history.append([now_msec, at])
	var limit := now_msec - int(HISTORY_SECONDS * 1000.0)
	var old := 0
	while old < _history.size() and int(_history[old][0]) < limit:
		old += 1
	if old > 0:
		_history = _history.slice(old)


## The host's position of the own player is one where it stood within HISTORY_SECONDS (the host is
## only behind, not elsewhere).
func was_recently_at(target: Vector2) -> bool:
	if RelayPeer.legacy_sync:
		return false
	var tolerance := HISTORY_TOLERANCE * HISTORY_TOLERANCE
	for i in range(_history.size() - 1, -1, -1):
		if (_history[i][1] as Vector2).distance_squared_to(target) <= tolerance:
			return true
	return false

class_name NetSide
extends Node
## Side-view gang segments in a shared run (M5, D-144; MULTIPLAYER.md §3e "Makeover"), child
## "NetSide" of the NetDungeon on every machine (same node path). Host-authoritative like the rooms:
## - Planning: the host plans the way from a room to the next one with its own "Seitenwege
##   auslassen" option (DungeonManager._plan_side_way) and announces it (side_way_net with a
##   signature). A client plans only announced ways (DungeonManager.plan_side_way): run seed and
##   slot give the same SideRules.make_rng, so the same plan, mirror, reason and segment seed; the
##   signature proves it.
## - Start: the host's gate takes every player of the session into the segment and tells the
##   clients (side_transit_net); a client's own gate waits for that.
## - Waiting (online test 16.10.2026, nobody is pulled away from a chest any more): the first living
##   player at the gate (SideGate.covers) or at the segment's door (SideSegment.is_at_door; the
##   host's segment has door_waits on) starts CoopRules.WAIT_COUNTDOWN (the same as for rooms).
##   Whoever stands there waits, held and protected (WAIT_PROTECT); the way starts once every living
##   player is there or the time is up, and only then are the stragglers taken along (downed ones as
##   before). The host decides and sends who waits, who is missing and the time left
##   (side_wait_net); every machine shows the countdown of the CoopWaitLine: the number with "Warte
##   auf <Name> …" at the gate, big with "Beeil dich!" and an arrow to the gate or door for a
##   straggler. A client holds its own player at once when it
##   reaches the gate or door (until the host says otherwise, WAIT_PREDICT_GRACE). While somebody
##   waits at the door, the segment camera follows the others and nobody is pulled (catch-up off).
## - In the segment: the host collects coins and the golden coin, opens the door, ends the segment
##   (see waiting), pulls stragglers back after 3 s (SideSegment catch-up) and runs the
##   enemies. A client's segment is a picture of it: its own decisions are off (physics of the
##   segment and of its enemies); coins, door, enemies (snapshots 10/s, deaths) and the end come from
##   the host. Players move through NetPlayerState as everywhere (velocity and side state too);
##   spikes run on every machine by the same clock, damage only at the host. Gold, crystals and HP
##   come back through the pot and the vitals.
## - Moves (round 2): the host's copy of every player decides jumps, double jumps, wall jumps and
##   landings; each one goes to the clients as an event (side_move_net) and a copy there plays it
##   with the same signals (PlayerSideMotion.apply_remote_move: stretch, salto, dust, landing). The
##   own player of a client keeps its prediction (its own looks, the host's event is skipped). Wall
##   slide and the used double jump travel as state (NetPlayerState side bits).
## - Crumbling ledges: only the host's ledges decide (someone stands on it, it falls, it comes back
##   once nobody is in the way); every change goes out (side_crumble_net), the clients' ledges are
##   remote_controlled and shake, drop and return when the host's do.
## - Turrets and spike traps (round 3): only the host's decide. A turret's charge (with its aim), its
##   shot and its death go out (side_turret_net); a client's turret is remote_controlled and shows
##   the telegraph and the recoil (the orb itself comes through NetEnemies as a harmless picture,
##   hits on the turret only count at the host). Every phase change of a spike trap goes out
##   (side_spikes_net), so a spike wave runs at the same moment on every machine.

const NODE_NAME := &"NetSide"
## The wait line at the top edge (online/coop_wait_line.gd, class CoopWaitLine; preloaded, so it
## also resolves before the editor's class list knows it).
const WaitLine := preload("res://online/coop_wait_line.gd")
## TESTWERTE: enemy snapshots per second (15 instead of 10 since the online test of 16.10.2026:
## with NetInterpolator's 100 ms delay two snapshots are always in the buffer); share of the error
## corrected per second and jump distance (legacy pull, RelayPeer.legacy_sync, and enemies without
## samples yet).
const ENEMY_SNAPSHOT_RATE := 15.0
const ENEMY_CORRECTION_RATE := 12.0
const ENEMY_SNAP_DISTANCE := 96.0
## Side-view enemies are drawn like the dungeon's puppets: between two host snapshots, a little in
## the host's past (online/net_interpolator.gd; "Mobs springen" in the side view, 16.10.2026).
const Interpolator := preload("res://online/net_interpolator.gd")
## TESTWERT: px/s of drawn movement from which a side enemy plays its walk animation.
const ENEMY_WALK_SPEED := 10.0
## A client's coin matches the host's within this distance (px, the same cell centre).
const COIN_MATCH_DISTANCE := 4.0
## What happened to a turret (side_turret_net).
enum TurretEvent { CHARGE, FIRE, DIED }
## What the group waits at (side_wait_net): nothing, the gate into a segment, the segment's door.
enum WaitKind { NONE, ENTRY, EXIT }
## Protection of a player waiting at the gate or door: no input, no damage, no enemy target.
const WAIT_PROTECT := &"coop_wait"
## A player counts as at the gate this far around its covered way (px; its body touches the trigger
## before its origin is inside).
const GATE_MARGIN := 12.0
## TESTWERT: a client's own player, held when it reached the gate or door, is let go again if the
## host has not confirmed it as waiting this long after (seconds).
const WAIT_PREDICT_GRACE := 1.0

var net: NetDungeon = null
var dm: DungeonManager = null
var is_host := false

## Test and tool counters. Host: ways announced; client: announced ways planned and compared.
var ways_announced := 0
var signatures_checked := 0
var signature_mismatches := 0
## Signatures of every way this machine planned, in order (tests compare host and client).
var signatures: Array[String] = []
var transits := 0
var segments_entered := 0
var segments_finished := 0
var coin_events := 0
var enemy_deaths := 0
var doors_opened := 0
## Moves (PlayerSideMotion.Move) sent by the host about its own player / about clients' players;
## client: moves received about other players, played on their copies, double jumps among them.
var moves_sent_own := 0
var moves_sent_clients := 0
var double_jumps_sent_own := 0
var moves_received := 0
var moves_applied := 0
var double_jumps_applied := 0
## Ledge changes sent (host) or applied (client), collapses among them.
var crumble_events := 0
var crumble_collapses := 0
## Turret events sent (host) or applied (client): charges, shots, deaths; spike phase changes.
var turret_events := 0
var turret_shots := 0
var turret_deaths := 0
var spike_events := 0
## Largest number of players in one segment and in its camera's targets (co-op camera).
var max_players_in_segment := 0
var max_camera_targets := 0
## Side-way waits started (host) or followed (client); host: ways started with everybody there /
## by the timer, the longest wait (s). Every machine: wait hints shown, frames the arrow was shown,
## times a player was held (client: its own player; host: any player).
var side_waits := 0
var waits_full := 0
var waits_timed_out := 0
var max_side_wait := 0.0
var wait_hints := 0
var wait_arrow_frames := 0
var holds := 0

var _detached := false
## The running segment of this machine and the slot of the room it leads into.
var _segment: SideSegment = null
var _segment_slot := -1
var _started_slots: Dictionary[int, bool] = {}
## Client: a host end that came before the own segment was built.
var _pending_finish: Dictionary[int, bool] = {}
## Client: ledge changes of a segment not built here yet {slot: [[index, state], ...]}, in order.
var _pending_crumbles: Dictionary[int, Array] = {}
## Client: turret and spike events of a segment not built here yet {slot: [[kind, args], ...]}.
var _pending_traps: Dictionary[int, Array] = {}
## Host: coins of the running segment by local position; door already announced.
var _coins: Dictionary[Vector2, SideCoin] = {}
var _door_sent := false
## Enemies of the running segment in build order (the same on every machine).
var _enemies: Array[SideEnemy] = []
## Client: the host's last enemy positions (segment-local) and facings.
var _enemy_targets: Dictionary[int, Vector2] = {}
## Client: the host's enemy positions over its time (index = build order).
var _enemy_interpolator: Interpolator = Interpolator.new()
var _snapshot_left := 0.0
## Host: side motions whose moves go to the clients (instance id -> true).
var _watched_motions: Dictionary[int, bool] = {}
## The running wait (every machine; the host decides, a client follows side_wait_net): its kind,
## the slot of the room the way leads into, the gate (ENTRY), time left, peers of living players
## waiting there and missing, the hint of this machine.
var _wait_kind := WaitKind.NONE
var _wait_slot := -1
var _wait_gate: SideGate = null
var _wait_left := 0.0
var _wait_time := 0.0
var _wait_at: Array[int] = []
var _wait_missing: Array[int] = []
var _wait_hint := CoopRules.WaitHint.NONE
## Host: the last wait state sent (key, whole seconds).
var _wait_sent := ""
var _wait_sent_seconds := -1
## Client: its own player held before the host said so (seconds of WAIT_PREDICT_GRACE left, < 0 =
## no), and the wait point it was for ("kind|slot"; once per point).
var _predicted_left := -1.0
var _predicted_point := ""
## Players held on this machine (instance id -> player).
var _held: Dictionary[int, Player] = {}


static func create(owner_net: NetDungeon, dungeon: DungeonManager) -> NetSide:
	var node := NetSide.new()
	node.name = NODE_NAME
	node.net = owner_net
	node.dm = dungeon
	return node


## What host and client compare for a planned way: plan, mirror, biome, reason, segment seed and
## the rooms it connects, and whether its turrets are set up.
static func signature_of(gate: SideGate) -> String:
	if gate == null or gate.layout == null:
		return ""
	var from_slot := gate.from_room.slot_index if is_instance_valid(gate.from_room) else -1
	var next_slot := gate.next_room.slot_index if is_instance_valid(gate.next_room) else -1
	return "%s|%s|%s|%d|%d|%d|%d|%d|%d" % [gate.layout.plan_id, gate.layout.is_mirrored, gate.layout.biome_id,
			int(gate.reason), gate.rng_seed, from_slot, next_slot, gate.layout.coins.size(), int(gate.layout.turrets_enabled)]


func _ready() -> void:
	is_host = multiplayer.is_server()


## The run ends (or the session): nobody stays held for a wait (players may live on in the village).
func _exit_tree() -> void:
	for id: int in _held:
		if is_instance_valid(_held[id]):
			_held[id].set_protected(WAIT_PROTECT, false)
	_held.clear()


## The relay session is gone: a client's segment decides for itself again.
func detach() -> void:
	if _detached:
		return
	_detached = true
	_end_wait()
	if is_instance_valid(_segment):
		# Alone again: the first one at the door ends the segment as in a solo run.
		_segment.door_waits = false
	if is_host:
		return
	if is_instance_valid(_segment):
		_segment.set_physics_process(true)
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.set_physics_process(true)
	if is_instance_valid(_segment):
		for turret in _segment.get_turrets():
			if is_instance_valid(turret):
				turret.remote_controlled = false
		for spikes in _segment.get_spikes():
			if is_instance_valid(spikes):
				spikes.remote_controlled = false


func get_segment() -> SideSegment:
	return _segment if is_instance_valid(_segment) else null


# --- Hooks (DungeonManager through NetDungeon) ---

## Host: the dungeon planned the way from room to next (gate null: a plain corridor).
func after_plan_side_way(room: RoomController, _next: RoomController, gate: SideGate) -> void:
	if not is_host or gate == null or _detached:
		return
	var signature := signature_of(gate)
	signatures.append(signature)
	ways_announced += 1
	net.send_to_clients(self, &"side_way_net", [room.slot_index, signature])


## A player walked into a side gate. Host: the wait starts (the whole group goes once everybody is
## there or the time is up, _tick_wait); right away when every living player is there already.
## Client: waits for the host.
func allow_side_transit(gate: SideGate) -> bool:
	if not is_host or _detached:
		return false
	var slot := gate.next_room.slot_index
	if _started_slots.has(slot) or (_wait_kind != WaitKind.NONE and _wait_slot == slot):
		return false
	_begin_wait(WaitKind.ENTRY, slot, gate)
	if _gather_wait():
		# Everybody is at the gate: the DungeonManager starts the way now (as before).
		waits_full += 1
		_end_wait()
		_mark_transit(slot)
		return true
	_send_wait_state()
	return false


## Host: the way into slot starts (the clients follow).
func _mark_transit(slot: int) -> void:
	_started_slots[slot] = true
	_segment_slot = slot
	transits += 1
	net.send_to_clients(self, &"side_transit_net", [slot])


## A node of the dungeon entered the tree (NetDungeon._on_node_added).
func on_node_added(node: Node) -> void:
	if _detached:
		return
	if node is SideSegment:
		_on_segment_added(node as SideSegment)
	elif node is SideEnemy and is_instance_valid(_segment) and _segment.is_ancestor_of(node):
		_on_enemy_added(node as SideEnemy)


func _on_segment_added(segment: SideSegment) -> void:
	_segment = segment
	_coins.clear()
	_enemies.clear()
	_enemy_targets.clear()
	_enemy_interpolator = Interpolator.new()
	_enemy_interpolator.teleport_distance = ENEMY_SNAP_DISTANCE
	_door_sent = false
	segments_entered += 1
	var slot := _segment_slot
	if is_host:
		# The door waits for the group (online test 16.10.2026): NetSide ends the segment.
		segment.door_waits = true
		segment.ready.connect(_watch_coins.bind(segment), CONNECT_ONE_SHOT)
		segment.ready.connect(_watch_crumbles.bind(segment), CONNECT_ONE_SHOT)
		segment.ready.connect(_watch_traps.bind(segment), CONNECT_ONE_SHOT)
		segment.coin_collected.connect(_on_coin_taken_host.unbind(2))
		segment.golden_coin_collected.connect(_on_coin_taken_host.unbind(2))
		segment.finished.connect(_on_finished_host.bind(slot).unbind(1))
		return
	# Client: the host decides coins, door, catch-up, ledges and the end (a picture of its segment).
	segment.ready.connect(segment.set_physics_process.bind(false), CONNECT_ONE_SHOT)
	segment.ready.connect(_follow_crumbles.bind(segment), CONNECT_ONE_SHOT)
	segment.ready.connect(_follow_traps.bind(segment), CONNECT_ONE_SHOT)
	if _pending_finish.has(slot):
		_pending_finish.erase(slot)
		segments_finished += 1
		segment.finish.call_deferred()


func _on_enemy_added(enemy: SideEnemy) -> void:
	var index := _enemies.size()
	_enemies.append(enemy)
	if is_host:
		enemy.died.connect(_on_enemy_died_host.bind(index).unbind(1))
		return
	# Client: the enemy is a puppet of the host's (no AI, no contact damage; its hurtbox is off,
	# NetEnemies switches every enemy hurtbox of a client off).
	enemy.ready.connect(enemy.set_physics_process.bind(false), CONNECT_ONE_SHOT)


# --- Host ---

## Every change of a ledge goes to the clients (index = build order, the same everywhere).
func _watch_crumbles(segment: SideSegment) -> void:
	var crumbles := segment.get_crumbles()
	for index in crumbles.size():
		crumbles[index].state_changed.connect(_on_crumble_changed_host.bind(index))


func _on_crumble_changed_host(_crumble: SideCrumble, state: SideCrumble.State, index: int) -> void:
	crumble_events += 1
	if state == SideCrumble.State.FALLEN:
		crumble_collapses += 1
	net.send_to_clients(self, &"side_crumble_net", [_segment_slot, index, int(state)])


## Every turret and spike trap of the running segment reports to the clients (index = build order,
## the same everywhere).
func _watch_traps(segment: SideSegment) -> void:
	var turrets := segment.get_turrets()
	for index in turrets.size():
		var turret := turrets[index]
		turret.charge_started.connect(_on_turret_host.bind(TurretEvent.CHARGE, index))
		turret.fired.connect(_on_turret_host.bind(TurretEvent.FIRE, index))
		turret.died.connect(_on_turret_died_host.bind(index))
	var spikes := segment.get_spikes()
	for index in spikes.size():
		spikes[index].phase_changed.connect(_on_spikes_host.bind(index))


func _on_turret_host(_turret: SideTurret, aim: Vector2, event: TurretEvent, index: int) -> void:
	if _detached:
		return
	turret_events += 1
	if event == TurretEvent.FIRE:
		turret_shots += 1
	net.send_to_clients(self, &"side_turret_net", [_segment_slot, index, int(event), aim])


func _on_turret_died_host(_turret: SideTurret, index: int) -> void:
	if _detached:
		return
	turret_events += 1
	turret_deaths += 1
	net.send_to_clients(self, &"side_turret_net", [_segment_slot, index, int(TurretEvent.DIED), Vector2.ZERO])


func _on_spikes_host(_spikes: SideSpikes, phase: SideSpikes.Phase, index: int) -> void:
	if _detached:
		return
	spike_events += 1
	net.send_to_clients(self, &"side_spikes_net", [_segment_slot, index, int(phase)])


## The moves of every player in the running segment go to the clients (once per side motion; it
## stays with the player from segment to segment).
func _watch_moves(segment: SideSegment) -> void:
	for player in segment.get_players():
		var motion := player.side_motion
		if motion == null or _watched_motions.has(motion.get_instance_id()):
			continue
		_watched_motions[motion.get_instance_id()] = true
		motion.jumped.connect(_on_move_host.bind(PlayerSideMotion.Move.JUMP, 0.0))
		motion.double_jumped.connect(_on_move_host.bind(PlayerSideMotion.Move.DOUBLE_JUMP, 0.0))
		motion.wall_jumped.connect(_on_move_host.bind(PlayerSideMotion.Move.WALL_JUMP, 0.0))
		motion.landed.connect(_on_landed_host)


func _on_landed_host(player: Player, fall_speed: float) -> void:
	_on_move_host(player, PlayerSideMotion.Move.LAND, fall_speed)


func _on_move_host(player: Player, move: PlayerSideMotion.Move, fall_speed: float) -> void:
	if _detached or not is_instance_valid(player) or player.side_motion == null:
		return
	var peer := NetDungeon.peer_of(player)
	if peer == multiplayer.get_unique_id():
		moves_sent_own += 1
		if move == PlayerSideMotion.Move.DOUBLE_JUMP:
			double_jumps_sent_own += 1
	else:
		moves_sent_clients += 1
	net.send_to_clients(self, &"side_move_net", [peer, int(move), player.velocity, player.side_motion.facing, fall_speed])


func _watch_coins(segment: SideSegment) -> void:
	for child in segment.get_children():
		var coin := child as SideCoin
		if coin != null:
			_coins[coin.position] = coin


## A coin went (coin_collected / golden_coin_collected): every coin freed since goes to the clients.
func _on_coin_taken_host() -> void:
	var slot := _segment_slot
	for local: Vector2 in _coins.keys():
		var coin := _coins[local]
		if not is_instance_valid(coin) or coin.is_queued_for_deletion():
			_coins.erase(local)
			coin_events += 1
			net.send_to_clients(self, &"side_coin_net", [slot, local])


func _on_enemy_died_host(index: int) -> void:
	enemy_deaths += 1
	net.send_to_clients(self, &"side_enemy_died_net", [_segment_slot, index])


func _on_finished_host(slot: int) -> void:
	segments_finished += 1
	net.send_to_clients(self, &"side_finished_net", [slot])


func _physics_process(delta: float) -> void:
	if _detached:
		return
	_tick_wait(delta)
	_update_holds()
	_update_wait_view()
	var segment := get_segment()
	if segment == null:
		return
	max_players_in_segment = maxi(max_players_in_segment, segment.get_players().size())
	max_camera_targets = maxi(max_camera_targets, segment.camera_targets().size())
	if is_host:
		_watch_moves(segment)
		var door := segment.get_node_or_null(^"Exit") as SideExit
		if door != null and door.is_open and not _door_sent:
			_door_sent = true
			doors_opened += 1
			net.send_to_clients(self, &"side_door_net", [_segment_slot])
		_snapshot_left -= delta
		if _snapshot_left <= 0.0 and not _enemies.is_empty():
			_snapshot_left = 1.0 / ENEMY_SNAPSHOT_RATE
			_send_enemies()
		return
	_follow_enemies(delta)
	# The segment's own physics is off here: the ledges only animate (the host decides).
	for crumble in segment.get_crumbles():
		if is_instance_valid(crumble):
			crumble.step(delta, true)


# --- Waiting at the gate and the door (online test 16.10.2026) ---

func _begin_wait(kind: WaitKind, slot: int, gate: SideGate) -> void:
	_wait_kind = kind
	_wait_slot = slot
	_wait_gate = gate
	_wait_left = CoopRules.WAIT_COUNTDOWN
	_wait_time = 0.0
	_wait_at.clear()
	_wait_missing.clear()
	side_waits += 1


## Every machine: no wait any more - holds let go, the line cleared; the host tells the clients.
func _end_wait() -> void:
	var was_waiting := _wait_kind != WaitKind.NONE
	_wait_kind = WaitKind.NONE
	_wait_gate = null
	_wait_at.clear()
	_wait_missing.clear()
	_predicted_left = -1.0
	_update_holds()
	_update_wait_view()
	var segment := get_segment()
	if segment != null:
		segment.set_door_waiting([])
	if is_host and was_waiting:
		_send_wait_state()


## Host: who of the living players is at the wait point now (once there, a player stays counted: he
## is held there). Returns true when the way may start (everybody there, or the time is up).
func _gather_wait() -> bool:
	var segment := get_segment()
	var living := dm.get_living_players()
	var at: Array[int] = []
	var missing: Array[int] = []
	for player in living:
		var peer := NetDungeon.peer_of(player)
		if _wait_at.has(peer) or _is_at_wait_point(player, segment):
			at.append(peer)
		else:
			missing.append(peer)
	at.sort()
	missing.sort()
	_wait_at = at
	_wait_missing = missing
	return CoopRules.should_start_side_way(living.size(), at.size(), _wait_left)


func _is_at_wait_point(player: Player, segment: SideSegment) -> bool:
	if player == null or not player.is_alive():
		return false
	match _wait_kind:
		WaitKind.ENTRY:
			return is_instance_valid(_wait_gate) and not player.is_side_view() and _wait_gate.covers(player.global_position, GATE_MARGIN)
		WaitKind.EXIT:
			return segment != null and player.is_side_view() and segment.is_at_door(player)
	return false


func _wait_still_valid(segment: SideSegment) -> bool:
	match _wait_kind:
		WaitKind.ENTRY:
			return is_instance_valid(_wait_gate) and is_instance_valid(_wait_gate.next_room) and not _started_slots.has(_wait_slot)
		WaitKind.EXIT:
			return segment != null and not segment.is_finished and _wait_slot == _segment_slot
	return false


func _tick_wait(delta: float) -> void:
	if is_host:
		_tick_wait_host(delta)
		return
	if _wait_kind != WaitKind.NONE:
		_wait_left = maxf(0.0, _wait_left - delta)
	_predict_hold(delta)


## Host: the door of the running segment starts a wait when the first living player reaches it; the
## running wait counts down and ends in the way (transit or the segment's end).
func _tick_wait_host(delta: float) -> void:
	var segment := get_segment()
	if _wait_kind == WaitKind.NONE:
		if segment == null or segment.is_finished or not segment.door_waits:
			return
		var anybody := false
		for player in segment.get_players():
			if player.is_alive() and player.is_side_view() and segment.is_at_door(player):
				anybody = true
				break
		if not anybody:
			return
		_begin_wait(WaitKind.EXIT, _segment_slot, null)
	if not _wait_still_valid(segment):
		_end_wait()
		return
	_wait_left -= delta
	_wait_time += delta
	max_side_wait = maxf(max_side_wait, _wait_time)
	if _gather_wait():
		_complete_wait_host(segment)
		return
	_send_wait_state()


func _complete_wait_host(segment: SideSegment) -> void:
	if _wait_missing.is_empty():
		waits_full += 1
	else:
		waits_timed_out += 1
	var kind := _wait_kind
	var gate := _wait_gate
	var slot := _wait_slot
	_end_wait()
	match kind:
		WaitKind.ENTRY:
			if is_instance_valid(gate) and dm != null:
				_mark_transit(slot)
				dm.start_side_transit(gate)
		WaitKind.EXIT:
			if segment != null:
				segment.finish()


## Host -> clients: the wait state whenever who waits changes, and every whole second.
func _send_wait_state() -> void:
	var key := "%d|%d|%s|%s" % [_wait_kind, _wait_slot, _wait_at, _wait_missing]
	var seconds := CoopRules.countdown_seconds(_wait_left) if _wait_kind != WaitKind.NONE else -1
	if key == _wait_sent and seconds == _wait_sent_seconds:
		return
	_wait_sent = key
	_wait_sent_seconds = seconds
	net.send_to_clients(self, &"side_wait_net", [int(_wait_kind), _wait_slot, PackedInt32Array(_wait_at),
			PackedInt32Array(_wait_missing), maxf(0.0, _wait_left)])


## Client: its own player stops at once at the gate or door (the host's word follows; if the host
## still counts it as missing after WAIT_PREDICT_GRACE, it is let go).
func _predict_hold(delta: float) -> void:
	var local := net.get_local_player() if net != null else null
	if local == null or not local.is_alive():
		_predicted_left = -1.0
		return
	if _predicted_left >= 0.0:
		# The host's word did not come (no wait) or counts the own player as missing: let go.
		var confirmed := _wait_kind != WaitKind.NONE and not _wait_missing.has(multiplayer.get_unique_id())
		_predicted_left -= delta
		if not confirmed and _predicted_left < 0.0:
			_predicted_left = -1.0
		return
	var point := ""
	var segment := get_segment()
	if local.is_side_view():
		if segment != null and not segment.is_finished and segment.is_at_door(local):
			point = "%d|%d" % [WaitKind.EXIT, _segment_slot]
	else:
		var gate := _open_gate()
		if gate != null and gate.covers(local.global_position):
			point = "%d|%d" % [WaitKind.ENTRY, gate.next_room.slot_index]
	if point.is_empty() or point == _predicted_point:
		return
	_predicted_point = point
	_predicted_left = WAIT_PREDICT_GRACE


## Client: the side gate of the active room whose way has not started yet (null if none).
func _open_gate() -> SideGate:
	var room := dm.get_room_at_slot(dm.get_active_slot()) if dm != null else null
	var gate := room.get_node_or_null(^"SideGate") as SideGate if room != null else null
	if gate == null or not is_instance_valid(gate.next_room) or _started_slots.has(gate.next_room.slot_index):
		return null
	return gate


## Every machine: the players waiting at the gate or door are held and protected (the host: every
## waiting player's copy, hits count there; a client: its own player, also predicted).
func _update_holds() -> void:
	var wanted: Dictionary[int, Player] = {}
	if _wait_kind != WaitKind.NONE:
		for peer in _wait_at:
			if not is_host and peer != multiplayer.get_unique_id():
				continue
			var player := net.player_of(peer) if net != null else null
			if player != null and is_instance_valid(player):
				wanted[player.get_instance_id()] = player
	if not is_host and _predicted_left >= 0.0:
		var local := net.get_local_player() if net != null else null
		if local != null:
			wanted[local.get_instance_id()] = local
	for id: int in _held.keys():
		if not wanted.has(id):
			var player := _held[id]
			if is_instance_valid(player):
				player.set_protected(WAIT_PROTECT, false)
			_held.erase(id)
	for id: int in wanted:
		if not _held.has(id):
			wanted[id].set_protected(WAIT_PROTECT, true)
			_held[id] = wanted[id]
			holds += 1


## Every machine: the line at the top edge and the straggler's arrow; the segment's camera follows
## the ones still running.
func _update_wait_view() -> void:
	var line := net.get_wait_line() if net != null else null
	if _wait_kind == WaitKind.NONE:
		_wait_hint = CoopRules.WaitHint.NONE
		if line != null:
			line.set_text(WaitLine.CHANNEL_SIDE, "")
			line.clear_countdown(WaitLine.CHANNEL_SIDE)
			line.clear_arrow(WaitLine.CHANNEL_SIDE)
		return
	var hint := CoopRules.wait_hint(multiplayer.get_unique_id(), _wait_at, _wait_missing)
	if hint != _wait_hint and hint != CoopRules.WaitHint.NONE:
		wait_hints += 1
	_wait_hint = hint
	var segment := get_segment()
	if segment != null and _wait_kind == WaitKind.EXIT:
		var waiting: Array[Player] = []
		for peer in _wait_at:
			var player := net.player_of(peer)
			if player != null:
				waiting.append(player)
		segment.set_door_waiting(waiting)
	if line == null:
		return
	line.set_text(WaitLine.CHANNEL_SIDE, wait_text(hint, net.names_of(_wait_missing)))
	if hint == CoopRules.WaitHint.NONE:
		line.clear_countdown(WaitLine.CHANNEL_SIDE)
	else:
		line.set_countdown(WaitLine.CHANNEL_SIDE, _wait_left, hint == CoopRules.WaitHint.MATES_WAIT_FOR_YOU)
	var local := net.get_local_player()
	var target := _wait_target()
	if hint == CoopRules.WaitHint.MATES_WAIT_FOR_YOU and local != null and local.is_alive() and target != Vector2.INF:
		line.set_arrow(WaitLine.CHANNEL_SIDE, local, target)
	else:
		line.clear_arrow(WaitLine.CHANNEL_SIDE)
	if line.get_arrow_channel() == WaitLine.CHANNEL_SIDE:
		wait_arrow_frames += 1


## The line under the countdown: at the gate or door "Warte auf <Namen> …" (as for rooms), a
## straggler "Beeil dich!", nothing for a downed player.
static func wait_text(hint: CoopRules.WaitHint, names: String) -> String:
	match hint:
		CoopRules.WaitHint.WAIT_FOR_MATES:
			return NetDungeon.wait_text(&"NET_WAIT_FOR_MATES", names)
		CoopRules.WaitHint.MATES_WAIT_FOR_YOU:
			return WaitLine.hurry_text()
	return ""


## Where the straggler's arrow points: the gate's start at the room's exit, or the segment's door.
func _wait_target() -> Vector2:
	match _wait_kind:
		WaitKind.ENTRY:
			if is_instance_valid(_wait_gate) and is_instance_valid(_wait_gate.from_room):
				var room := _wait_gate.from_room
				return room.to_global(RoomTiles.tile_center(room.get_exit_tile()))
		WaitKind.EXIT:
			var segment := get_segment()
			if segment != null:
				return segment.get_door_feet()
	return Vector2.INF


## The running wait of this machine (tools, tests): kind, hint, time left, waiting and missing peers.
func get_wait_kind() -> WaitKind:
	return _wait_kind


func get_wait_hint() -> CoopRules.WaitHint:
	return _wait_hint


func get_wait_left() -> float:
	return _wait_left if _wait_kind != WaitKind.NONE else 0.0


func get_wait_peers() -> Array[int]:
	return _wait_at.duplicate()


func get_missing_peers() -> Array[int]:
	return _wait_missing.duplicate()


func _send_enemies() -> void:
	var positions := PackedVector2Array()
	var facings := PackedFloat32Array()
	for enemy in _enemies:
		var alive := is_instance_valid(enemy) and not enemy.is_dead()
		positions.append(enemy.position if alive else Vector2.INF)
		facings.append(enemy.get_facing() if alive else 0.0)
	net.send_to_clients(self, &"side_enemies_net", [_segment_slot, Time.get_ticks_msec(), positions, facings])


# --- Client ---

func _follow_crumbles(segment: SideSegment) -> void:
	for crumble in segment.get_crumbles():
		crumble.remote_controlled = true
	var pending: Array = _pending_crumbles.get(_segment_slot, [])
	_pending_crumbles.erase(_segment_slot)
	for change: Array in pending:
		_apply_crumble(segment, int(change[0]), int(change[1]))


## A client's turrets and spike traps wait for the host's (and get what came before the build).
func _follow_traps(segment: SideSegment) -> void:
	for turret in segment.get_turrets():
		turret.remote_controlled = true
	for spikes in segment.get_spikes():
		spikes.remote_controlled = true
	var pending: Array = _pending_traps.get(_segment_slot, [])
	_pending_traps.erase(_segment_slot)
	for entry: Array in pending:
		if entry[0] == &"turret":
			_apply_turret(segment, int(entry[1]), int(entry[2]), entry[3])
		else:
			_apply_spikes(segment, int(entry[1]), int(entry[2]))


func _apply_turret(segment: SideSegment, index: int, event: int, aim: Vector2) -> void:
	var turrets := segment.get_turrets()
	if index < 0 or index >= turrets.size() or not is_instance_valid(turrets[index]):
		return
	var turret := turrets[index]
	turret.remote_controlled = true
	turret_events += 1
	match event:
		TurretEvent.CHARGE:
			turret.apply_remote_charge(aim)
		TurretEvent.FIRE:
			turret_shots += 1
			turret.apply_remote_fire(aim)
		TurretEvent.DIED:
			turret_deaths += 1
			turret.apply_remote_death()


func _apply_spikes(segment: SideSegment, index: int, phase: int) -> void:
	var spikes := segment.get_spikes()
	if index < 0 or index >= spikes.size() or not is_instance_valid(spikes[index]):
		return
	spikes[index].remote_controlled = true
	spike_events += 1
	spikes[index].apply_remote_phase(phase as SideSpikes.Phase)


## A trap event for slot: applied now, or kept until this machine's segment is built.
func _trap_event(slot: int, entry: Array) -> void:
	var segment := get_segment()
	if segment != null and slot == _segment_slot and segment.is_node_ready():
		if entry[0] == &"turret":
			_apply_turret(segment, int(entry[1]), int(entry[2]), entry[3])
		else:
			_apply_spikes(segment, int(entry[1]), int(entry[2]))
	elif slot >= _segment_slot:
		if not _pending_traps.has(slot):
			_pending_traps[slot] = []
		_pending_traps[slot].append(entry)


func _apply_crumble(segment: SideSegment, index: int, state: int) -> void:
	var crumbles := segment.get_crumbles()
	if index < 0 or index >= crumbles.size():
		return
	var crumble := crumbles[index]
	crumble.remote_controlled = true
	crumble_events += 1
	if state == SideCrumble.State.FALLEN and crumble.state != SideCrumble.State.FALLEN:
		crumble_collapses += 1
	crumble.apply_remote_state(state as SideCrumble.State)


func _follow_enemies(delta: float) -> void:
	var now := float(Time.get_ticks_msec())
	for index: int in _enemy_targets:
		if index >= _enemies.size():
			continue
		var enemy := _enemies[index]
		if not is_instance_valid(enemy) or enemy.is_dead():
			continue
		var target := _enemy_targets[index]
		var error := target - enemy.position
		var moving := error.length_squared() > 4.0
		var drawn := Vector2.INF if RelayPeer.legacy_sync else _enemy_interpolator.position_at(index, now)
		if drawn != Vector2.INF:
			moving = drawn.distance_to(enemy.position) > ENEMY_WALK_SPEED * delta
			enemy.position = drawn
		elif error.length() > ENEMY_SNAP_DISTANCE:
			enemy.position = target
		else:
			enemy.position += error * minf(1.0, ENEMY_CORRECTION_RATE * delta)
		var sprite := enemy.get_node_or_null(^"Sprite") as AnimatedSprite2D
		if sprite != null:
			sprite.flip_h = enemy.get_facing() < 0.0
			var animation := &"walk" if moving else &"idle"
			if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(animation) and sprite.animation != animation:
				sprite.play(animation)


## The host announced a side way from the room of room_slot to the next one: plan it the same way.
@rpc("authority", "call_remote", "reliable")
func side_way_net(room_slot: int, signature: String) -> void:
	if is_host or _detached:
		return
	var room := dm.get_room_at_slot(room_slot)
	var next := dm.get_room_at_slot(room_slot + 1)
	if room == null or next == null:
		push_warning("NetSide: side way of slot %d without its rooms." % room_slot)
		signature_mismatches += 1
		return
	var gate := dm.plan_side_way(room, next)
	var own := signature_of(gate)
	signatures.append(own)
	ways_announced += 1
	signatures_checked += 1
	if own != signature:
		signature_mismatches += 1
		push_warning("NetSide: side way of slot %d differs from the host.\n  host:   %s\n  client: %s" % [room_slot, signature, own])


## The host's wait at a side way (kind NONE: over): who waits there, who is missing, time left.
@rpc("authority", "call_remote", "reliable")
func side_wait_net(kind: int, slot: int, at: PackedInt32Array, missing: PackedInt32Array, time_left: float) -> void:
	if is_host or _detached:
		return
	if kind == WaitKind.NONE:
		if _wait_kind != WaitKind.NONE or _predicted_left >= 0.0:
			_end_wait()
		return
	if _wait_kind == WaitKind.NONE or _wait_slot != slot or int(_wait_kind) != kind:
		side_waits += 1
	_wait_kind = kind as WaitKind
	_wait_slot = slot
	_wait_left = time_left
	_wait_at.assign(at)
	_wait_missing.assign(missing)
	if kind == WaitKind.ENTRY:
		var room := dm.get_room_at_slot(slot - 1)
		_wait_gate = room.get_node_or_null(^"SideGate") as SideGate if room != null else null
	else:
		_wait_gate = null
	if _wait_at.has(multiplayer.get_unique_id()):
		# The host counts the own player as waiting: the hold is its word now.
		_predicted_left = -1.0


@rpc("authority", "call_remote", "reliable")
func side_transit_net(next_slot: int) -> void:
	if is_host or _detached or _started_slots.has(next_slot):
		return
	var room := dm.get_room_at_slot(next_slot - 1)
	var gate := room.get_node_or_null(^"SideGate") as SideGate if room != null else null
	if gate == null or not is_instance_valid(gate.next_room) or gate.next_room.slot_index != next_slot:
		push_warning("NetSide: no side gate into slot %d to follow the host." % next_slot)
		return
	_started_slots[next_slot] = true
	_segment_slot = next_slot
	transits += 1
	dm.start_side_transit(gate)


@rpc("authority", "call_remote", "reliable")
func side_coin_net(slot: int, local: Vector2) -> void:
	var segment := get_segment()
	if is_host or segment == null or slot != _segment_slot:
		return
	for child in segment.get_children():
		var coin := child as SideCoin
		if coin == null or coin.is_queued_for_deletion() or coin.position.distance_to(local) > COIN_MATCH_DISTANCE:
			continue
		coin_events += 1
		var golden := coin.golden
		coin.take()
		if golden and segment.context != null and segment.context.ui != null:
			# Same banner as on the host: the golden coin pays gold (D-144 round 2), no crystal.
			var gold := SideRules.golden_coin_gold(segment.room_index, MetaProgression.get_gold_multiplier())
			segment.context.ui.show_banner(DungeonTexts.t(&"SIDE_GOLDEN_COIN_TITLE"),
					Loc.t(&"SIDE_GOLDEN_COIN_GOLD", [gold]), UiKit.COLOR_GOLD)
		return


@rpc("authority", "call_remote", "reliable")
func side_door_net(slot: int) -> void:
	var segment := get_segment()
	if is_host or segment == null or slot != _segment_slot:
		return
	var door := segment.get_node_or_null(^"Exit") as SideExit
	if door != null:
		doors_opened += 1
		door.open()


@rpc("authority", "call_remote", "reliable")
func side_enemy_died_net(slot: int, index: int) -> void:
	if is_host or slot != _segment_slot or index < 0 or index >= _enemies.size():
		return
	var enemy := _enemies[index]
	if is_instance_valid(enemy) and not enemy.is_dead():
		enemy_deaths += 1
		enemy.health.take_damage(enemy.health.get_health() + 1.0)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func side_enemies_net(slot: int, host_msec: int, positions: PackedVector2Array, facings: PackedFloat32Array) -> void:
	if is_host or slot != _segment_slot:
		return
	_enemy_interpolator.begin_snapshot(float(host_msec), float(Time.get_ticks_msec()))
	for index in mini(positions.size(), _enemies.size()):
		if positions[index] == Vector2.INF:
			_enemy_interpolator.erase(index)
			continue
		_enemy_targets[index] = positions[index]
		_enemy_interpolator.push(index, float(host_msec), positions[index])
		var enemy := _enemies[index]
		if is_instance_valid(enemy) and index < facings.size() and facings[index] != 0.0:
			enemy.set(&"_facing", facings[index])


## A move the host decided for the player of peer: its copy here plays it (looks on every machine).
## The own player predicted it already and keeps its own.
@rpc("authority", "call_remote", "reliable")
func side_move_net(peer: int, move: int, velocity: Vector2, facing: float, fall_speed: float) -> void:
	if is_host or _detached or peer == multiplayer.get_unique_id():
		return
	moves_received += 1
	var player := net.player_of(peer) if net != null else null
	if player == null or not player.is_side_view() or player.side_motion == null:
		return
	var motion := player.side_motion
	motion.moves_from_remote = true
	motion.apply_remote_move(move as PlayerSideMotion.Move, velocity, facing, fall_speed)
	# The next synced velocity may be older than this event: start from the event's.
	var state := player.get_node_or_null(NodePath(NetPlayerState.NODE_NAME)) as NetPlayerState
	if state != null and move != PlayerSideMotion.Move.LAND:
		state.vel = velocity
	moves_applied += 1
	if move == PlayerSideMotion.Move.DOUBLE_JUMP:
		double_jumps_applied += 1


@rpc("authority", "call_remote", "reliable")
func side_crumble_net(slot: int, index: int, state: int) -> void:
	if is_host or _detached:
		return
	var segment := get_segment()
	if segment != null and slot == _segment_slot and segment.is_node_ready():
		_apply_crumble(segment, index, state)
	elif slot >= _segment_slot:
		# Faster than this machine's transit: applied once the segment is built (_follow_crumbles).
		if not _pending_crumbles.has(slot):
			_pending_crumbles[slot] = []
		_pending_crumbles[slot].append([index, state])


## The host's turret index of slot lit up, fired or was destroyed (aim: unit direction).
@rpc("authority", "call_remote", "reliable")
func side_turret_net(slot: int, index: int, event: int, aim: Vector2) -> void:
	if is_host or _detached:
		return
	_trap_event(slot, [&"turret", index, event, aim])


## The host's spike trap index of slot changed phase.
@rpc("authority", "call_remote", "reliable")
func side_spikes_net(slot: int, index: int, phase: int) -> void:
	if is_host or _detached:
		return
	_trap_event(slot, [&"spikes", index, phase, Vector2.ZERO])


@rpc("authority", "call_remote", "reliable")
func side_finished_net(slot: int) -> void:
	if is_host:
		return
	var segment := get_segment()
	if segment == null or slot != _segment_slot:
		# The host was faster than this machine's fade: end it as soon as it is built.
		_pending_finish[slot] = true
		return
	segments_finished += 1
	segment.finish()

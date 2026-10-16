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
## - In the segment: the host collects coins and the golden coin, opens the door, ends the segment
##   (first player at the door), pulls stragglers back after 3 s (SideSegment catch-up) and runs the
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
## TESTWERTE: enemy snapshots per second; share of the error corrected per second; jump distance.
const ENEMY_SNAPSHOT_RATE := 10.0
const ENEMY_CORRECTION_RATE := 12.0
const ENEMY_SNAP_DISTANCE := 96.0
## A client's coin matches the host's within this distance (px, the same cell centre).
const COIN_MATCH_DISTANCE := 4.0
## What happened to a turret (side_turret_net).
enum TurretEvent { CHARGE, FIRE, DIED }

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
var _snapshot_left := 0.0
## Host: side motions whose moves go to the clients (instance id -> true).
var _watched_motions: Dictionary[int, bool] = {}


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


## The relay session is gone: a client's segment decides for itself again.
func detach() -> void:
	if _detached:
		return
	_detached = true
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


## A player walked into a side gate. Host: the whole group goes, the clients follow; client: waits.
func allow_side_transit(gate: SideGate) -> bool:
	if not is_host:
		return false
	var slot := gate.next_room.slot_index
	if _started_slots.has(slot):
		return false
	_started_slots[slot] = true
	_segment_slot = slot
	transits += 1
	net.send_to_clients(self, &"side_transit_net", [slot])
	return true


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
	_door_sent = false
	segments_entered += 1
	var slot := _segment_slot
	if is_host:
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
	var segment := get_segment()
	if segment == null or _detached:
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


func _send_enemies() -> void:
	var positions := PackedVector2Array()
	var facings := PackedFloat32Array()
	for enemy in _enemies:
		var alive := is_instance_valid(enemy) and not enemy.is_dead()
		positions.append(enemy.position if alive else Vector2.INF)
		facings.append(enemy.get_facing() if alive else 0.0)
	net.send_to_clients(self, &"side_enemies_net", [_segment_slot, positions, facings])


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
	for index: int in _enemy_targets:
		if index >= _enemies.size():
			continue
		var enemy := _enemies[index]
		if not is_instance_valid(enemy) or enemy.is_dead():
			continue
		var target := _enemy_targets[index]
		var error := target - enemy.position
		if error.length() > ENEMY_SNAP_DISTANCE:
			enemy.position = target
		else:
			enemy.position += error * minf(1.0, ENEMY_CORRECTION_RATE * delta)
		var sprite := enemy.get_node_or_null(^"Sprite") as AnimatedSprite2D
		if sprite != null:
			sprite.flip_h = enemy.get_facing() < 0.0
			var moving := error.length_squared() > 4.0
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
func side_enemies_net(slot: int, positions: PackedVector2Array, facings: PackedFloat32Array) -> void:
	if is_host or slot != _segment_slot:
		return
	for index in mini(positions.size(), _enemies.size()):
		if positions[index] == Vector2.INF:
			continue
		_enemy_targets[index] = positions[index]
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

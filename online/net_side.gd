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

const NODE_NAME := &"NetSide"
## TESTWERTE: enemy snapshots per second; share of the error corrected per second; jump distance.
const ENEMY_SNAPSHOT_RATE := 10.0
const ENEMY_CORRECTION_RATE := 12.0
const ENEMY_SNAP_DISTANCE := 96.0
## A client's coin matches the host's within this distance (px, the same cell centre).
const COIN_MATCH_DISTANCE := 4.0

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
## Host: coins of the running segment by local position; door already announced.
var _coins: Dictionary[Vector2, SideCoin] = {}
var _door_sent := false
## Enemies of the running segment in build order (the same on every machine).
var _enemies: Array[SideEnemy] = []
## Client: the host's last enemy positions (segment-local) and facings.
var _enemy_targets: Dictionary[int, Vector2] = {}
var _snapshot_left := 0.0


static func create(owner_net: NetDungeon, dungeon: DungeonManager) -> NetSide:
	var node := NetSide.new()
	node.name = NODE_NAME
	node.net = owner_net
	node.dm = dungeon
	return node


## What host and client compare for a planned way: plan, mirror, biome, reason, segment seed and
## the rooms it connects.
static func signature_of(gate: SideGate) -> String:
	if gate == null or gate.layout == null:
		return ""
	var from_slot := gate.from_room.slot_index if is_instance_valid(gate.from_room) else -1
	var next_slot := gate.next_room.slot_index if is_instance_valid(gate.next_room) else -1
	return "%s|%s|%s|%d|%d|%d|%d|%d" % [gate.layout.plan_id, gate.layout.is_mirrored, gate.layout.biome_id,
			int(gate.reason), gate.rng_seed, from_slot, next_slot, gate.layout.coins.size()]


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
		segment.coin_collected.connect(_on_coin_taken_host.unbind(2))
		segment.golden_coin_collected.connect(_on_coin_taken_host.unbind(2))
		segment.finished.connect(_on_finished_host.bind(slot).unbind(1))
		return
	# Client: the host decides coins, door, catch-up and the end (a picture of its segment).
	segment.ready.connect(segment.set_physics_process.bind(false), CONNECT_ONE_SHOT)
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


func _send_enemies() -> void:
	var positions := PackedVector2Array()
	var facings := PackedFloat32Array()
	for enemy in _enemies:
		var alive := is_instance_valid(enemy) and not enemy.is_dead()
		positions.append(enemy.position if alive else Vector2.INF)
		facings.append(enemy.get_facing() if alive else 0.0)
	net.send_to_clients(self, &"side_enemies_net", [_segment_slot, positions, facings])


# --- Client ---

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

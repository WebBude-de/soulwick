class_name NetModes
extends Node
## Room modes (minigames R4, D-120, D-135-D-137) in a shared run (MP3, D-126), child "NetModes" of the
## NetDungeon (MULTIPLAYER.md §3e). Host-authoritative like the rest of the dungeon: a mode's clock,
## pushes, decisions and bonus run only on the host. A client's room never starts its encounter
## (RoomController.remote_encounter), so CombatVariant.start() and every mode step stay off there.
## Every machine builds the same mode from the slot's RNG state (what _on_attach builds: flame, altar
## and relics, torches, villager and his way, plates, hole); layout_of() goes into the room signature.
##
## Host -> clients: the mode's banners (CombatVariant.banner_shown; muted on the client), the bonus
## decision (always before the room's completion, so a client's finish() places the same bonus chest),
## the start, events for what happens once (soul appears / taken / lost, round over, field warned /
## broken, survived, torch lit, villager rescued) and a state poll for what moves or counts (flame
## health, the villager on his way, the relics and their carriers, the escape hole; 10/s, only when it
## changed). The task bar comes as RoomObjective (NetDungeon.objective_state), enemies as puppets.
## Client -> host: E on a relic or a torch (request_action; the host decides with its copy of the
## client's player). On a client the mode's own decisions are cut off: relic signals and physics, the
## E handlers of relics and torches, the crypt's gravedigger trait.

const NODE_NAME := &"NetModes"
## State poll of the active room's mode (TESTWERT).
const STATE_RATE := 10.0
## Host: a client's E counts within this distance of the object (px, generous for latency).
const ACTION_RANGE := 140.0
## Client: the villager follows the host's way share at this many px per second at most.
const VILLAGER_FOLLOW_SPEED := 260.0

enum Event { STARTED, SOUL_SPAWNED, SOUL_TAKEN, SOUL_LOST, SOULS_OVER, FIELD_WARNED, FIELD_BROKEN, SURVIVED, TORCH_LIT, RESCUED, VILLAGER_LOST, SINKHOLE }

var net: NetDungeon = null
var dm: DungeonManager = null
var is_host := false

## Test and tool counters: events and states sent (host) or applied (client), banners, bonus.
var events := 0
var states := 0
var banners := 0
var actions := 0
## Mode id per slot of every prepared room with a mode, and its bonus at the end (1 / 0 / -1 open).
var mode_by_slot: Dictionary[int, StringName] = {}
var bonus_by_slot: Dictionary[int, int] = {}
## Bonus of every mode room that ended here (CombatVariant.finished; 1 / 0), per machine.
var finished_by_slot: Dictionary[int, int] = {}

var _detached := false
var _state_left := 0.0
## Host: last state sent per slot; souls spawned already announced per slot.
var _sent_states: Dictionary[int, Array] = {}
var _souls_sent: Dictionary[int, int] = {}
## Client: the villager's way share the host last reported, per escort mode.
var _villager_targets: Dictionary[EscortMode, float] = {}
## Client: the host's place of every bonus chest per slot (chest name -> mode-local position).
var _chest_spots: Dictionary[int, Dictionary] = {}
## Test and tool record: where each bonus chest stands on this machine ("slot/name" -> mode-local
## spot as placed, before SortLift), host and clients alike.
var chest_places: Dictionary[String, Vector2] = {}


static func create(owner_net: NetDungeon, dungeon: DungeonManager) -> NetModes:
	var node := NetModes.new()
	node.name = NODE_NAME
	node.net = owner_net
	node.dm = dungeon
	return node


## What the mode built on attach, as a short text for the room signature (empty without a mode).
static func layout_of(room: RoomController) -> String:
	var mode := CombatVariant.of(room)
	if mode == null:
		return ""
	var parts: Array[String] = [String(mode.variant_id)]
	for child in mode.get_children():
		# Named objects only: bursts and flashes of the attach (auto names) differ per machine.
		if child is Node2D and not String(child.name).begins_with("@"):
			parts.append("%s@%s" % [child.name, (child as Node2D).position.round()])
	if mode is SoulsMode:
		parts.append(str((mode as SoulsMode).spots))
	elif mode is CollapseMode:
		parts.append("%d/%d" % [(mode as CollapseMode).fields.size(), (mode as CollapseMode).kept.size()])
	elif mode is EscortMode:
		parts.append(str((mode as EscortMode).path_tiles) + str((mode as EscortMode).is_chicken))
	elif mode is RiftsMode:
		parts.append(str((mode as RiftsMode).get_wall_rift_tiles()) + str((mode as RiftsMode)._free_tiles))
	elif mode is LightfireMode:
		parts.append(str((mode as LightfireMode).get_guardian_tiles()))
	elif mode is HuntMode:
		parts.append("%s %s" % [(mode as HuntMode)._hole_tile, (mode as HuntMode).has_loot_upgrade()])
	return "%x" % hash("|".join(parts))


func _ready() -> void:
	is_host = multiplayer.is_server()
	get_tree().node_added.connect(_on_node_added)


func detach() -> void:
	_detached = true
	set_physics_process(false)
	set_process(false)


## NetDungeon.after_prepare_slot: a prepared room (or branch way). Host: listens to its mode; client:
## cuts the mode's own decisions off.
func on_room_prepared(room: RoomController) -> void:
	var mode := CombatVariant.of(room)
	var slot := room.slot_index
	if mode != null:
		mode_by_slot[slot] = mode.variant_id
		bonus_by_slot[slot] = -1
		mode.finished.connect(func(_mode: CombatVariant, achieved: bool) -> void: finished_by_slot[slot] = 1 if achieved else 0)
	if is_host:
		if mode != null:
			_watch_host(room, mode)
		return
	_quiet_client(room, mode)


# --- Host ---

func _watch_host(room: RoomController, mode: CombatVariant) -> void:
	var slot := room.slot_index
	mode.banner_shown.connect(_on_banner.bind(room))
	mode.child_entered_tree.connect(_on_host_chest.bind(room))
	mode.bonus_changed.connect(_on_bonus.bind(room))
	mode.started.connect(func(_mode: CombatVariant) -> void: _event(room, Event.STARTED))
	if mode is SoulsMode:
		var souls := mode as SoulsMode
		souls.soul_taken.connect(func(_m: SoulsMode, wisp: SoulWisp, _p: Player) -> void:
			_flush_souls(room, souls)
			_event(room, Event.SOUL_TAKEN, [_wisp_index(wisp)]))
		souls.soul_lost.connect(func(_m: SoulsMode, wisp: SoulWisp) -> void:
			_flush_souls(room, souls)
			_event(room, Event.SOUL_LOST, [_wisp_index(wisp)]))
		souls.round_over.connect(func(_m: SoulsMode, collected: int, crystals: int) -> void:
			_flush_souls(room, souls)
			_event(room, Event.SOULS_OVER, [collected, crystals]))
	elif mode is CollapseMode:
		var collapse := mode as CollapseMode
		collapse.field_warned.connect(func(_m: CollapseMode, index: int) -> void: _event(room, Event.FIELD_WARNED, [index]))
		collapse.field_broken.connect(func(_m: CollapseMode, index: int, _tiles: Array[Vector2i]) -> void: _event(room, Event.FIELD_BROKEN, [index]))
		collapse.survived.connect(func(_m: CollapseMode) -> void: _event(room, Event.SURVIVED))
		collapse.sinkhole_changed.connect(func(_m: CollapseMode, tiles: Array[Vector2i], phase: CollapseMode.SinkPhase) -> void:
			_event(room, Event.SINKHOLE, _sinkhole_args(tiles, phase)))
	elif mode is EscortMode:
		var escort := mode as EscortMode
		escort.rescued.connect(func(_m: EscortMode, _chicken: bool) -> void:
			_send_state(room, true)
			_event(room, Event.RESCUED))
		escort.villager_lost.connect(func(_m: EscortMode) -> void:
			_send_state(room, true)
			_event(room, Event.VILLAGER_LOST))
	elif mode is LightfireMode:
		for torch in (mode as LightfireMode).torches:
			torch.ignited.connect(func(lit: RoomTorch, _by: Node) -> void: _event(room, Event.TORCH_LIT, [String(lit.name)]))
	elif mode is RelicMode:
		for relic in (mode as RelicMode).relics:
			# Carrier changes go out at once (the poll catches the position).
			relic.picked_up.connect(func(_r: Relic, _p: Player) -> void: _send_state.call_deferred(room, true))
			relic.dropped.connect(func(_r: Relic, _p: Player, _hit: bool) -> void: _send_state.call_deferred(room, true))
			relic.placed.connect(func(_r: Relic, _p: Player) -> void: _send_state.call_deferred(room, true))
	_sent_states.erase(slot)
	_souls_sent.erase(slot)


func _physics_process(delta: float) -> void:
	if _detached or not is_host or dm == null:
		return
	var room := dm.get_room_at_slot(dm.get_active_slot())
	if room == null or CombatVariant.of(room) == null:
		return
	var souls := CombatVariant.of(room) as SoulsMode
	if souls != null:
		_flush_souls(room, souls)
	_state_left -= delta
	if _state_left <= 0.0:
		_state_left = 1.0 / STATE_RATE
		_send_state(room)


## The poll of a mode: sent when it differs from the last one (force: always).
func _send_state(room: RoomController, force := false) -> void:
	if _detached or not is_instance_valid(room):
		return
	var mode := CombatVariant.of(room)
	var state := capture_state(mode)
	if state.is_empty():
		return
	var slot := room.slot_index
	if not force and _sent_states.get(slot, []) == state:
		return
	_sent_states[slot] = state
	states += 1
	net.send_to_clients(self, &"mode_state", [slot, state])


## The host's state of what moves or counts in a mode (empty for modes that only send events).
static func capture_state(mode: CombatVariant) -> Array:
	if mode is FlameMode:
		var flame := (mode as FlameMode).flame
		if flame == null or flame.health == null:
			return []
		return [snappedf(flame.health.get_health(), 0.01), flame.health.get_max_health()]
	if mode is EscortMode:
		var escort := mode as EscortMode
		var villager := escort.villager
		if villager == null or not is_instance_valid(villager):
			return []
		return [int(escort.walk_state), snappedf(escort.travelled, 0.5), villager.hearts, villager.max_hearts, escort._facing_left()]
	if mode is RelicMode:
		var data: Array = []
		for relic in (mode as RelicMode).relics:
			var at := relic.global_position.round() if relic.is_inside_tree() else relic.position.round()
			data.append_array([int(relic.state), NetDungeon.peer_of(relic.carrier) if relic.is_carried() else 0, at.x, at.y])
		return data
	if mode is HuntMode:
		var hunt := mode as HuntMode
		var hole := hunt.get_hole()
		var built := hole != null and is_instance_valid(hole)
		var phase := 0
		if hunt.is_caught():
			phase = 2
		elif hunt.is_escaped():
			phase = 3
		elif hunt.flight != null and is_instance_valid(hunt.flight) and hunt.flight.is_fleeing():
			phase = 1
		var hole_at := hole.position if built else Vector2.ZERO
		return [built, hole_at.x, hole_at.y, hole.frame if built else 0, phase, hunt._caught_at.x, hunt._caught_at.y]
	if mode is SoulsMode:
		var souls := mode as SoulsMode
		return [souls.collected, souls.get_crystal_pickup() != null]
	return []


## Souls that appeared since the last call go out (before taken / lost / over, so the order holds).
func _flush_souls(room: RoomController, souls: SoulsMode) -> void:
	var slot := room.slot_index
	var sent := int(_souls_sent.get(slot, 0))
	while sent < souls.spawned:
		_event(room, Event.SOUL_SPAWNED, [sent])
		sent += 1
	_souls_sent[slot] = sent


static func _wisp_index(wisp: SoulWisp) -> int:
	return String(wisp.name).trim_prefix("Soul").to_int() if wisp != null else -1


func _event(room: RoomController, kind: Event, args: Array = []) -> void:
	if _detached or not is_instance_valid(room):
		return
	events += 1
	net.send_to_clients(self, &"mode_event", [room.slot_index, int(kind), args])


func _on_banner(_mode: CombatVariant, title: String, subtitle: String, color: Color, room: RoomController) -> void:
	banners += 1
	net.send_to_clients(self, &"mode_banner", [room.slot_index, title, subtitle, color])


func _on_bonus(_mode: CombatVariant, state: CombatVariant.Bonus, room: RoomController) -> void:
	var achieved := state == CombatVariant.Bonus.ACHIEVED
	bonus_by_slot[room.slot_index] = 1 if achieved else 0
	net.send_to_clients(self, &"mode_bonus", [room.slot_index, achieved])


@rpc("any_peer", "call_remote", "reliable")
func request_action(slot: int, node_name: String) -> void:
	if not is_host or _detached:
		return
	var player := net._sender_player()
	var room := dm.get_room_at_slot(slot)
	var mode := CombatVariant.of(room)
	if player == null or mode == null or not player.is_alive():
		return
	var target := mode.get_node_or_null(NodePath(node_name)) as Node2D
	if target == null or player.global_position.distance_to(target.global_position) > ACTION_RANGE:
		return
	actions += 1
	if target is Relic:
		(target as Relic)._on_interacted(player)
	elif target is RoomTorch:
		(target as RoomTorch).ignite(player)


# --- Client ---

## A client's mode: banners muted, own decisions off, E on relics and torches asks the host.
func _quiet_client(room: RoomController, mode: CombatVariant) -> void:
	var gravedigger := GravediggerTrait.of(room)
	if gravedigger != null:
		# Bone heaps rise on the host; the client's puppets follow its snapshots.
		gravedigger.set_physics_process(false)
		for connection in room.enemy_container.child_entered_tree.get_connections():
			if connection.callable.get_object() == gravedigger:
				room.enemy_container.child_entered_tree.disconnect(connection.callable)
	if mode == null:
		return
	mode.banners_muted = true
	var slot := room.slot_index
	mode.child_entered_tree.connect(_on_client_chest.bind(slot))
	if mode is RelicMode:
		var relic_mode := mode as RelicMode
		for relic in relic_mode.relics:
			for signal_name: StringName in [&"picked_up", &"dropped", &"placed"]:
				for connection in relic.get_signal_connection_list(signal_name):
					if connection.callable.get_object() == relic_mode:
						relic.disconnect(signal_name, connection.callable)
			relic.set_physics_process(false)
			_redirect_interaction(relic.get_interactable(), slot, relic.name)
	elif mode is LightfireMode:
		for torch in (mode as LightfireMode).torches:
			_redirect_interaction(torch.get_interactable(), slot, torch.name)


func _redirect_interaction(interactable: Interactable, slot: int, node_name: StringName) -> void:
	if interactable == null:
		return
	for connection in interactable.interacted.get_connections():
		interactable.interacted.disconnect(connection.callable)
	interactable.interacted.connect(func(_player: Player) -> void:
		actions += 1
		if net != null:
			net.send_to_host(self, &"request_action", [slot, String(node_name)]))


func _on_node_added(node: Node) -> void:
	if _detached or is_host or dm == null or not (node is SummoningRift) or not dm.is_ancestor_of(node):
		return
	# A rift puppet: the biome colour and the wall look of the host's rift (set before its _ready).
	var rift := node as SummoningRift
	var room := NetEnemies._room_of(rift)
	var mode := CombatVariant.of(room) as RiftsMode
	if room == null or mode == null:
		return
	var biome := room.spawner.get_biome(room.room_index)
	rift.rift_color = RiftsMode.BIOME_COLORS.get(biome.id if biome != null else &"", Color.WHITE)
	for tile in mode.get_wall_rift_tiles():
		if (RoomTiles.tile_center(tile) - Vector2(0, RiftsMode.WALL_RIFT_LIFT)).distance_to(rift.position) < 4.0:
			rift.in_wall = true
			# Like the host (RiftsMode._open_rift): the rift is the opening, no second hole beside it.
			# Deferred: the sources may be built in this very call.
			hide_rift_opening.call_deferred(mode, tile)


## Rifts mode: the wall source a wall rift sits in shows no opening of its own (SpawnSource
## .hide_opening); its phases still come from the host (NetEnemies.source_phase). Public for tests.
static func hide_rift_opening(mode: RiftsMode, tile: Vector2i) -> bool:
	if mode == null or not is_instance_valid(mode) or not mode.is_inside_tree():
		return false
	var sources := mode.get_sources()
	if sources == null:
		return false
	for source in sources.get_sources():
		if is_instance_valid(source) and source.kind == SpawnSourceRules.Kind.RIFT_WALL and source.floor_tile == tile:
			source.hide_opening()
			return true
	return false


func _process(delta: float) -> void:
	if _detached or is_host:
		return
	for escort: EscortMode in _villager_targets.keys():
		if not is_instance_valid(escort):
			_villager_targets.erase(escort)
		else:
			_follow_villager(escort, delta)
	if dm == null:
		return
	var room := dm.get_room_at_slot(dm.get_active_slot())
	var mode := CombatVariant.of(room)
	if mode is SoulsMode:
		# The souls' rings run down here too (the host decides when they go).
		for wisp in (mode as SoulsMode).get_visible_wisps():
			wisp.age = minf(wisp.lifetime, wisp.age + delta)
	elif mode is RelicMode:
		for relic in (mode as RelicMode).relics:
			if relic.is_carried() and is_instance_valid(relic.carrier):
				relic._follow_carrier()


func _follow_villager(escort: EscortMode, delta: float) -> void:
	var target: float = _villager_targets.get(escort, escort.travelled)
	if escort.villager == null or not is_instance_valid(escort.villager) or is_equal_approx(target, escort.travelled):
		return
	escort.travelled = move_toward(escort.travelled, target, VILLAGER_FOLLOW_SPEED * delta)
	escort._place_villager()
	if escort.path_view != null and is_instance_valid(escort.path_view):
		escort.path_view.set_progress(escort.get_progress())


@rpc("authority", "call_remote", "reliable")
func mode_banner(slot: int, title: String, subtitle: String, color: Color) -> void:
	if is_host or _detached or dm.get_room_at_slot(slot) == null:
		return
	banners += 1
	dm.ui.show_banner(title, subtitle, color)


## Host: a bonus chest of a mode. It keeps off the tiles of the players (CombatVariant
## ._tiles_around_players: all living players of the session here), whose places differ a little per
## machine; the clients put theirs where the host's stands.
func _on_host_chest(node: Node, room: RoomController) -> void:
	var chest := node as TreasureChest
	if chest == null or not is_instance_valid(room):
		return
	chest_places["%d/%s" % [room.slot_index, chest.name]] = chest.position
	if net != null:
		net.send_to_clients(self, &"mode_chest", [room.slot_index, String(chest.name), chest.position])


@rpc("authority", "call_remote", "reliable")
func mode_chest(slot: int, chest_name: String, spot: Vector2) -> void:
	if is_host or _detached or dm == null:
		return
	apply_chest(dm.get_room_at_slot(slot), chest_name, spot)


## Client: a bonus chest stands where the host's stands (mode-local spot as placed, before the chest
## lifts its sort origin in _ready, SortLift). Moves a chest that is already here, else keeps the spot
## until this machine places it (_on_client_chest). Public for tests.
func apply_chest(room: RoomController, chest_name: String, spot: Vector2) -> bool:
	var mode := CombatVariant.of(room)
	if mode == null:
		return false
	var chest := mode.get_node_or_null(NodePath(chest_name)) as TreasureChest
	if chest != null:
		chest.position = spot - Vector2(0, Player.FEET_OFFSET.y) if chest.is_node_ready() else spot
	var spots: Dictionary = _chest_spots.get(room.slot_index, {})
	spots[chest_name] = spot
	_chest_spots[room.slot_index] = spots
	chest_places["%d/%s" % [room.slot_index, chest_name]] = spot
	return true


func _on_client_chest(node: Node, slot: int) -> void:
	var chest := node as TreasureChest
	if chest == null:
		return
	var spots: Dictionary = _chest_spots.get(slot, {})
	if spots.has(String(chest.name)):
		chest.position = spots[String(chest.name)]
	chest_places["%d/%s" % [slot, chest.name]] = chest.position


@rpc("authority", "call_remote", "reliable")
func mode_bonus(slot: int, achieved: bool) -> void:
	if is_host or _detached or dm == null:
		return
	apply_bonus(dm.get_room_at_slot(slot), achieved)


## Client: the host decided the mode's bonus (before the room's completion). Public for tests.
func apply_bonus(room: RoomController, achieved: bool) -> bool:
	var mode := CombatVariant.of(room)
	if mode == null:
		return false
	mode.set_bonus(achieved)
	bonus_by_slot[room.slot_index] = 1 if achieved else 0
	return true


@rpc("authority", "call_remote", "reliable")
func mode_state(slot: int, state: Array) -> void:
	var room := dm.get_room_at_slot(slot)
	if is_host or _detached or room == null:
		return
	if apply_state(room, state):
		states += 1


@rpc("authority", "call_remote", "reliable")
func mode_event(slot: int, kind: int, args: Array) -> void:
	var room := dm.get_room_at_slot(slot)
	if is_host or _detached or room == null:
		return
	if apply_event(room, kind, args):
		events += 1


## Client: the host's poll of a mode (capture_state) applied to this machine's mode. Public for tests.
func apply_state(room: RoomController, state: Array) -> bool:
	var mode := CombatVariant.of(room)
	if mode is FlameMode and state.size() >= 2:
		_apply_flame(mode as FlameMode, float(state[0]), float(state[1]))
		return true
	if mode is EscortMode and state.size() >= 5:
		_apply_escort(room, mode as EscortMode, state)
		return true
	if mode is RelicMode:
		var relics := (mode as RelicMode).relics
		for i in mini(relics.size(), state.size() / 4):
			_apply_relic(relics[i], int(state[i * 4]), int(state[i * 4 + 1]), Vector2(float(state[i * 4 + 2]), float(state[i * 4 + 3])))
		return true
	if mode is HuntMode and state.size() >= 7:
		_apply_hunt(mode as HuntMode, state)
		return true
	if mode is SoulsMode and state.size() >= 2:
		var crystal := (mode as SoulsMode).get_crystal_pickup()
		if not bool(state[1]) and crystal != null and (mode as SoulsMode).is_round_over:
			# Somebody took the crystals at the host.
			crystal.queue_free()
		return true
	return false


## Client: one event of the host's mode. Public for tests.
func apply_event(room: RoomController, kind: int, args: Array = []) -> bool:
	var mode := CombatVariant.of(room)
	if mode == null:
		return false
	match kind:
		Event.STARTED:
			_client_started(mode)
		Event.SOUL_SPAWNED, Event.SOUL_TAKEN, Event.SOUL_LOST, Event.SOULS_OVER:
			if not mode is SoulsMode:
				return false
			_apply_souls(mode as SoulsMode, kind, args)
		Event.FIELD_WARNED, Event.FIELD_BROKEN, Event.SURVIVED:
			if not mode is CollapseMode:
				return false
			_apply_collapse(room, mode as CollapseMode, kind, args)
		Event.SINKHOLE:
			if not mode is CollapseMode or args.is_empty():
				return false
			(mode as CollapseMode).apply_sinkhole(_sinkhole_tiles(args), int(args[0]) as CollapseMode.SinkPhase)
		Event.TORCH_LIT:
			var torch := mode.get_node_or_null(NodePath(str(args[0]) if not args.is_empty() else "")) as RoomTorch
			if torch == null:
				return false
			torch.ignite(null)
		Event.RESCUED:
			if not mode is EscortMode:
				return false
			_client_rescued(mode as EscortMode)
		Event.VILLAGER_LOST:
			if not mode is EscortMode:
				return false
			var villager := (mode as EscortMode).villager
			if villager != null and is_instance_valid(villager) and villager.is_alive():
				_set_hearts(villager, 0)
		_:
			return false
	return true


## The fight began at the host: what the mode's start shows (its logic stays at the host).
func _client_started(mode: CombatVariant) -> void:
	if mode is SoulsMode:
		var souls := mode as SoulsMode
		for preview in souls._previews:
			if is_instance_valid(preview):
				preview.fade()
		souls._previews.clear()
	elif mode is EscortMode:
		var escort := mode as EscortMode
		if escort.walk_state == EscortMode.Walk.WAITING:
			escort.walk_state = EscortMode.Walk.WALKING
		if escort.path_view != null and not escort.path_view.is_revealed():
			escort.path_view.reveal()
	elif mode is LightfireMode:
		(mode as LightfireMode)._darken_room()


func _apply_flame(mode: FlameMode, health: float, maximum: float) -> void:
	var flame := mode.flame
	if flame == null or not is_instance_valid(flame) or not flame.is_alive():
		return
	if maximum > 0.0 and not is_equal_approx(flame.health.get_max_health(), maximum):
		flame.health.reset(maximum)
	if health <= 0.0:
		flame.health.take_damage(flame.health.get_health() + 1.0)
	elif not is_equal_approx(flame.health.get_health(), health):
		flame.health.set_current(health)


func _apply_escort(room: RoomController, escort: EscortMode, state: Array) -> void:
	var villager := escort.villager
	if villager == null or not is_instance_valid(villager):
		return
	var walk := int(state[0]) as EscortMode.Walk
	var facing_left := bool(state[4])
	_villager_targets[escort] = float(state[1])
	var max_hearts := int(state[3])
	if villager.max_hearts != max_hearts and villager.is_alive():
		villager.set_max_hearts(max_hearts)
	_set_hearts(villager, int(state[2]))
	if escort.walk_state == EscortMode.Walk.ARRIVED or escort.walk_state == EscortMode.Walk.DOWN:
		return
	if walk == EscortMode.Walk.STOPPED:
		if escort.walk_state != EscortMode.Walk.STOPPED:
			villager.say(escort._help_text())
		villager.set_look(LostVillager.Look.SCARED, facing_left)
	elif walk == EscortMode.Walk.WALKING:
		villager.set_look(LostVillager.Look.WALK, facing_left)
	if walk != EscortMode.Walk.ARRIVED and walk != EscortMode.Walk.DOWN:
		escort.walk_state = walk


## Hearts down to the host's count, with the hit look (the last one lets him fall: villager_lost).
static func _set_hearts(villager: LostVillager, hearts: int) -> void:
	var guard := 0
	while villager.is_alive() and villager.hearts > hearts and guard < 16:
		guard += 1
		villager._invulnerable_left = 0.0
		if villager.hurtbox != null:
			villager.hurtbox.set_invulnerable(LostVillager.INVULNERABLE_HIT, false)
		villager.take_hit(DamageData.new())


func _client_rescued(escort: EscortMode) -> void:
	if escort.walk_state == EscortMode.Walk.ARRIVED or escort.villager == null or not is_instance_valid(escort.villager):
		return
	escort.walk_state = EscortMode.Walk.ARRIVED
	escort.travelled = escort.path_total
	_villager_targets.erase(escort)
	escort._place_villager()
	escort.villager.set_rescued()
	escort.villager.say(DungeonTexts.t(&"MODE_ESCORT_CHICKEN_THANKS" if escort.is_chicken else &"MODE_ESCORT_THANKS"), 2.4)
	if escort.path_view != null and is_instance_valid(escort.path_view):
		escort.path_view.fade_all()
	if escort.is_inside_tree():
		LightSource.flash(escort, escort.villager.global_position, 420.0, 0.6)
	# Every machine shows the bonus chest; each player opens their own (D-109, per player like D-126).
	escort.spawn_bonus_chests(escort._chest_spot())


func _apply_relic(relic: Relic, state: int, carrier_peer: int, at: Vector2) -> void:
	match state:
		Relic.State.PLACED:
			if not relic.is_placed():
				relic.place(null, true)
		Relic.State.CARRIED:
			var carrier := net._player_of(carrier_peer) if net != null else null
			if relic.is_carried() and relic.carrier == carrier:
				return
			_release_relic(relic)
			relic.state = Relic.State.CARRIED
			relic.carrier = carrier
			if carrier != null:
				# The carrier walks slower and cannot attack on this machine too (prediction).
				LanternCarry.attach(carrier, relic)
				relic._follow_carrier()
			relic.get_light().radius = RelicRules.CARRIED_LIGHT_RADIUS
			relic.z_index = 2
			relic._update_prompt()
		_:
			if relic.is_placed():
				return
			if relic.is_carried():
				_release_relic(relic)
				relic.state = Relic.State.LYING
				relic.get_light().radius = RelicRules.LIGHT_RADIUS
				relic.z_index = 0
				relic._update_prompt()
			if relic.is_inside_tree() and relic.global_position.distance_to(at) > 1.0:
				relic.global_position = at


static func _release_relic(relic: Relic) -> void:
	if relic.carrier != null and is_instance_valid(relic.carrier):
		LanternCarry.detach(relic.carrier)
	relic.carrier = null


func _apply_hunt(hunt: HuntMode, state: Array) -> void:
	var built := bool(state[0])
	var phase := int(state[4])
	var hole := hunt.get_hole()
	if built and phase < 2 and (hole == null or not is_instance_valid(hole)):
		hunt._build_hole(Vector2(float(state[1]), float(state[2])) - Vector2(0, 8))
		hole = hunt.get_hole()
	if hole != null and is_instance_valid(hole):
		hole.frame = int(state[3])
	if phase >= 2 and hunt._caught_at == Vector2.ZERO:
		hunt._caught_at = Vector2(float(state[5]), float(state[6]))
		hunt._close_hole()


func _apply_souls(souls: SoulsMode, kind: int, args: Array) -> void:
	var index := int(args[0]) if not args.is_empty() else -1
	match kind:
		Event.SOUL_SPAWNED:
			if index < 0 or souls.spots.is_empty() or souls.get_node_or_null(NodePath("Soul%d" % index)) != null:
				return
			var wisp := SoulWisp.new()
			wisp.name = "Soul%d" % index
			wisp.build(souls.spots[index % souls.spots.size()])
			souls.add_child(wisp)
			souls._wisps.append(wisp)
			souls.spawned = maxi(souls.spawned, index + 1)
		Event.SOUL_TAKEN, Event.SOUL_LOST:
			var wisp := souls.get_node_or_null(NodePath("Soul%d" % index)) as SoulWisp
			if wisp == null:
				return
			souls._wisps.erase(wisp)
			if kind == Event.SOUL_TAKEN:
				souls.collected += 1
				wisp.take()
			else:
				souls.lost += 1
				wisp.fade()
		Event.SOULS_OVER:
			if souls.is_round_over:
				return
			souls.is_round_over = true
			souls.collected = int(args[0]) if args.size() > 0 else souls.collected
			souls.crystals = int(args[1]) if args.size() > 1 else 0
			for wisp in souls.get_visible_wisps():
				wisp.fade()
			souls._wisps.clear()
			if souls.crystals > 0:
				souls._place_crystals()
				# The group's crystals are booked at the host (shared pot); this one only shows them.
				var crystal := souls.get_crystal_pickup()
				if crystal != null:
					crystal.amount = 0


## Sinkhole as event arguments: [phase, x0, y0, x1, y1, …] (plain ints for the wire).
static func _sinkhole_args(tiles: Array[Vector2i], phase: CollapseMode.SinkPhase) -> Array:
	var args: Array = [int(phase)]
	for tile in tiles:
		args.append(tile.x)
		args.append(tile.y)
	return args


static func _sinkhole_tiles(args: Array) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for i in range(1, args.size() - 1, 2):
		tiles.append(Vector2i(int(args[i]), int(args[i + 1])))
	return tiles


func _apply_collapse(room: RoomController, collapse: CollapseMode, kind: int, args: Array) -> void:
	var index := int(args[0]) if not args.is_empty() else -1
	match kind:
		Event.FIELD_WARNED:
			if index >= 0 and index < collapse.fields.size() and collapse.field_states[index] == CollapseMode.FieldState.STANDING:
				collapse._warn(index)
		Event.FIELD_BROKEN:
			if index >= 0 and index < collapse.fields.size() and collapse.field_states[index] != CollapseMode.FieldState.BROKEN:
				_break_field(room, collapse, index)
		Event.SURVIVED:
			if collapse.is_survived:
				return
			collapse.is_survived = true
			collapse.spawn_bonus_chests(RoomTiles.tile_center(collapse._chest_tile()))


## A field breaks as at the host (CollapseMode._break), without the enemies: they are the host's.
static func _break_field(room: RoomController, collapse: CollapseMode, index: int) -> void:
	collapse.field_states[index] = CollapseMode.FieldState.BROKEN
	collapse.broken_count += 1
	var tiles: Array[Vector2i] = []
	tiles.assign(collapse.fields[index])
	room.tiles.add_pit_tiles(tiles)
	var broken: Dictionary[Vector2i, bool] = {}
	for tile in tiles:
		collapse._free.erase(tile)
		broken[tile] = true
	collapse.view.crumble(index)
	collapse.view.set_queued(collapse.get_next_fields())
	var props := room.get_node_or_null("Props")
	if props != null:
		for prop in props.get_children():
			var node := prop as Node2D
			if node != null and not node is TreasureChest and broken.has(RoomTiles.local_to_tile(node.position)):
				collapse._sink(node, true)
	var sources := SpawnSources.of(room)
	if sources != null:
		for source in sources.get_sources():
			if not source.is_wall_source() and source.visible and broken.has(RoomTiles.local_to_tile(source.spot)):
				collapse._sink(source, false)
	if collapse.is_inside_tree():
		Sfx.play_at(collapse, &"collapse_fall", room.to_global(CollapseRules.field_center(collapse.fields[index])), -3.0)
		CameraShake.shake(collapse, 2.0)

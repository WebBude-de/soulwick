class_name NetDetails
extends Node
## The smaller pieces of a shared run that the host decides and every machine shows (MP5, D-191),
## child "NetDetails" of the NetDungeon on every machine (same node path).
## - Trap clock: spike traps and lava cracks (SpikeTrap, LavaCrack) start with a random delay and
##   lava cracks sleep while nobody is near, so every machine had its own rhythm while only the
##   host's hurts. The host sends every phase change of a trap in the rooms the group stands in
##   (trap_phase_net: slot, index in build order, phase); the client steps its copy into that phase
##   (its own sound, sparks and light play then) and lets its own clock run TRAP_SLACK longer, so
##   the host's next step comes first. Without the host the copy goes on by itself.
## - Curses of the pact altar (PlayerCurses, D-112): a curse lies on the player who sealed the pact,
##   on every machine. A client reports its own curse (submit_curse), the host lays it on its copy
##   of that player (HASTE and FRAILTY act there: enemies, vitals) and sends every curse of every
##   player to all clients (player_cursed_net), so the copies and the Tab overview match.
## The wandering merchant of the secret niche shares the host's offers through the NetDungeon's
## shop messages (NetDungeon._share_merchant).

const NODE_NAME := &"NetDetails"
## Client: its own trap clock runs this much longer than the phase (s, TESTWERT), so the host's
## step arrives first; after a longer silence of the host the copy steps by itself.
const TRAP_SLACK := 0.5
## Phases of SpikeTrap and LavaCrack (both enum Phase { IDLE, WARN, ACTIVE }) and their timers.
const PHASE_COUNT := 3
const PHASE_TIMES: Array[StringName] = [&"IDLE_TIME", &"WARN_TIME", &"ACTIVE_TIME"]

var net: NetDungeon = null
var dm: DungeonManager = null

## Tools and tests: trap phases the host sent / a client applied, curses sent and laid on a copy.
var trap_events_sent := 0
var trap_events_applied := 0
var curses_sent := 0
var curses_applied := 0

var _detached := false
## Traps per slot in build order and the room they belong to (a slot may be rebuilt).
var _traps: Dictionary[int, Array] = {}
var _trap_rooms: Dictionary[int, int] = {}
## Host: the phase sent last per slot and trap index.
var _sent_phases: Dictionary[int, PackedInt32Array] = {}
## A curse laid on a copy from a message: not reported back.
var _applying_curse := false


static func create(owner_net: NetDungeon, dungeon: DungeonManager) -> NetDetails:
	var details := NetDetails.new()
	details.name = NODE_NAME
	details.net = owner_net
	details.dm = dungeon
	return details


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func detach() -> void:
	_detached = true
	set_physics_process(false)


# --- Trap clock ---

static func is_trap(node: Node) -> bool:
	return node is SpikeTrap or node is LavaCrack


## The traps of room in build order (the same on every machine: templates and BiomeHazards from the
## slot's RNG state).
static func traps_of(room: Node) -> Array[Node2D]:
	var traps: Array[Node2D] = []
	if room == null or not is_instance_valid(room):
		return traps
	for node in room.find_children("*", "Node2D", true, false):
		if is_trap(node):
			traps.append(node as Node2D)
	return traps


static func phase_of(trap: Node) -> int:
	return int(trap.get(&"_phase"))


## Length of a phase of trap (its own constants), 0 if unknown.
static func phase_time(trap: Node, phase: int) -> float:
	var script := trap.get_script() as Script
	if script == null or phase < 0 or phase >= PHASE_COUNT:
		return 0.0
	return float(script.get_script_constant_map().get(PHASE_TIMES[phase], 0.0))


## Client: trap goes into phase as the host's did. It steps there itself from the phase before (sound,
## sparks, light and its hitbox, which hurts nobody on a client), and a sleeping lava crack is set
## directly; then its own clock gets the phase's time plus slack.
static func apply_phase(trap: Node2D, phase: int, slack := TRAP_SLACK) -> void:
	if trap == null or not is_instance_valid(trap) or phase < 0 or phase >= PHASE_COUNT:
		return
	if phase_of(trap) != phase:
		trap.set(&"_phase", posmod(phase - 1, PHASE_COUNT))
		trap.set(&"_time_left", 0.0)
		trap.call(&"_physics_process", 0.0)
		if phase_of(trap) != phase:
			trap.set(&"_phase", phase)
	trap.set(&"_time_left", phase_time(trap, phase) + slack)
	trap.queue_redraw()


func _physics_process(_delta: float) -> void:
	if _detached or net == null or not net.is_host or dm == null:
		return
	var slot := dm.get_active_slot()
	for at in [slot - 1, slot]:
		_send_trap_phases(at)


## Host: every trap of the room at slot whose phase changed since the last message.
func _send_trap_phases(slot: int) -> void:
	var traps := _traps_at(slot)
	if traps.is_empty():
		return
	var sent: PackedInt32Array = _sent_phases.get(slot, PackedInt32Array())
	if sent.size() != traps.size():
		sent.resize(traps.size())
		sent.fill(-1)
	for index in traps.size():
		var trap: Node2D = traps[index]
		if not is_instance_valid(trap):
			continue
		var phase := phase_of(trap)
		if sent[index] == phase:
			continue
		sent[index] = phase
		trap_events_sent += 1
		net.send_to_clients(self, &"trap_phase_net", [slot, index, phase])
	_sent_phases[slot] = sent


func _traps_at(slot: int) -> Array:
	var room := dm.peek_room_at_slot(slot) if slot > 0 else null
	if room == null or not is_instance_valid(room):
		_traps.erase(slot)
		_trap_rooms.erase(slot)
		_sent_phases.erase(slot)
		return []
	if _trap_rooms.get(slot, 0) != room.get_instance_id():
		_traps[slot] = traps_of(room)
		_trap_rooms[slot] = room.get_instance_id()
		_sent_phases.erase(slot)
	return _traps[slot]


@rpc("authority", "call_remote", "reliable")
func trap_phase_net(slot: int, index: int, phase: int) -> void:
	if _detached or net == null or net.is_host:
		return
	var traps := _traps_at(slot)
	if index < 0 or index >= traps.size():
		return
	apply_phase(traps[index], phase)
	trap_events_applied += 1


# --- Curses of the pact altar ---

func _on_node_added(node: Node) -> void:
	if _detached or not (node is PlayerCurses):
		return
	var player := node.get_parent() as Player
	if player == null:
		return
	(node as PlayerCurses).curse_added.connect(_on_curse_added.bind(player))


func _on_curse_added(curse: PlayerCurses.Curse, player: Player) -> void:
	if _detached or net == null or not is_instance_valid(player):
		return
	if net.is_host:
		# Every curse of every player (the host's own, a client's reported one) to every client.
		curses_sent += 1
		net.send_to_clients(self, &"player_cursed_net", [NetDungeon.peer_of(player), int(curse)])
	elif player.is_local and not _applying_curse:
		curses_sent += 1
		net.send_to_host(self, &"submit_curse", [int(curse)])


## Client -> host: the client sealed a pact; its curse goes onto the host's copy of its player.
@rpc("any_peer", "call_remote", "reliable")
func submit_curse(curse: int) -> void:
	if _detached or net == null or not net.is_host:
		return
	if lay_curse(net.player_of(multiplayer.get_remote_sender_id()), curse):
		curses_applied += 1


## Host -> clients: player of peer carries curse (the own player already has it).
@rpc("authority", "call_remote", "reliable")
func player_cursed_net(peer: int, curse: int) -> void:
	if _detached or net == null or net.is_host:
		return
	_applying_curse = true
	var laid := lay_curse(net.player_of(peer), curse)
	_applying_curse = false
	if laid:
		curses_applied += 1


## curse onto player unless it is there already (or not allowed); true if it was laid now.
static func lay_curse(player: Player, curse: int) -> bool:
	if player == null or not is_instance_valid(player) or curse < 0 or curse >= PlayerCurses.Curse.size():
		return false
	if PlayerCurses.has_curse(player, curse as PlayerCurses.Curse):
		return false
	return PlayerCurses.ensure(player).add_curse(curse as PlayerCurses.Curse)

class_name NetGuide
extends Node
## Flint's "first time" hints in a shared run (feedback #2b1a5a87 23.10.2026: "Wenn dann sollen alle
## Spieler die Erklärung bekommen, wenn einer der Mitspieler die Erklärung braucht / neu ist"), child
## "NetGuide" of NetDungeon on every machine (same node path for the RPCs). The host decides:
## - A machine's coach (FlintControls, explain_first) hands every hint to request_hint (group
##   GROUP_ROUTER). If the local player has seen it, nothing happens; else the machine asks the host.
## - The host starts one hint at a time for everybody (group_hint): every machine shows it in Flint's
##   corner, every player is held (Player.set_protected PROTECTION: no input, no damage, enemies
##   ignore him; on the host for every player's copy, D-085, nothing pauses).
## - The learners (who asked) page with "Weiter" (a TOUR); the others watch it go on by itself and
##   wait. When the last learner is through (hint_done) or the time limit ran out (time_limit), the
##   host ends it everywhere (group_hint_end) and starts the next one waiting.
## Every machine marks the hint seen when it ends (they all got it). Other explanations (village,
## spells, rank) stay per player. Room-type intros (WK11) follow the same rule in
## dungeon/modes/room_intro.gd (rooms-dev); register_builder lets them use this queue.

const NODE_NAME := &"NetGuide"
## FlintControls.GROUP_ROUTER (kept equal, the coach finds this node through it).
const GROUP_ROUTER: StringName = &"flint_group_hints"
## Player.set_protected reason while a group hint runs.
const PROTECTION: StringName = &"flint_group_hint"
## TESTWERTE: the host ends a group hint after the estimated reading time times LIMIT_FACTOR plus
## LIMIT_EXTRA, at least LIMIT_MIN and at most LIMIT_MAX seconds (a learner who walked away).
const LIMIT_FACTOR := 2.0
const LIMIT_EXTRA := 4.0
const LIMIT_MIN := 10.0
const LIMIT_MAX := 30.0

var net: NetDungeon = null
var is_host := false
## Explanation builders beyond FlintControls: id prefix -> (id: StringName) -> FlintExplanation.
var builders: Dictionary[String, Callable] = {}
## This machine's player and every player of the world (tests swap them; NetDungeon's by default).
var local_player: Callable = _net_local_player
var all_players: Callable = _net_players

## Tests and tools: group hints started and ended here.
var started_count := 0
var ended_count := 0

## Host: hints waiting, [id: StringName, learners: Array[int]] each.
var _waiting: Array[Array] = []
## Host: the running hint, the learners still reading it, seconds left, hints shown this run.
var _active: StringName = &""
var _learners: Dictionary[int, bool] = {}
var _time_left := 0.0
var _shown: Dictionary[StringName, bool] = {}
## Every machine: the hint shown here now and whether this machine's player is a learner of it.
var _showing: StringName = &""
var _learner := false
var _held: Array = []


static func create(owner_net: NetDungeon) -> NetGuide:
	var guide := NetGuide.new()
	guide.name = NODE_NAME
	guide.net = owner_net
	guide.is_host = owner_net.is_host if owner_net != null else false
	return guide


## The NetGuide of the shared run in tree, or null (single player, local co-op).
static func of(tree: SceneTree) -> NetGuide:
	return tree.get_first_node_in_group(GROUP_ROUTER) as NetGuide if tree != null else null


## The time a group hint may take at most (s), from its sentences.
static func time_limit(explanation: FlintExplanation) -> float:
	var texts := PackedStringArray()
	if explanation != null:
		for step in explanation.steps:
			if step != null:
				texts.append(step.get_text())
	var estimate := FlintGuideRules.estimated_duration(texts)
	return clampf(estimate * LIMIT_FACTOR + LIMIT_EXTRA, LIMIT_MIN, LIMIT_MAX)


## The group form of explanation: a TOUR (holds and protects, "Weiter"), going on by itself for those
## who only watch; once per account like the hint.
static func group_copy(explanation: FlintExplanation, learner: bool) -> FlintExplanation:
	var result := explanation.copy()
	result.style = FlintExplanation.Style.TOUR
	result.auto_advance = not learner
	result.once = true
	return result


func _ready() -> void:
	add_to_group(GROUP_ROUTER)


## The explanation of a hint id: a registered builder by prefix, else FlintControls'.
func build(id: StringName) -> FlintExplanation:
	for prefix: String in builders:
		if String(id).begins_with(prefix):
			return builders[prefix].call(id) as FlintExplanation
	return FlintControls.explanation_for(id)


## Room intros and other "first time" moments may use this queue: ids starting with prefix are built
## with builder(id) -> FlintExplanation (must give the same sentences on every machine).
func register_builder(prefix: String, builder: Callable) -> void:
	builders[prefix] = builder


## FlintControls' router hook: the hint id for player (local). True = taken over (asked the host, or
## nothing to do because this player has seen it).
func request_hint(player: Player, id: StringName) -> bool:
	if player == null or not is_instance_valid(player) or not player.is_local:
		return false
	var explanation := build(id)
	if explanation == null:
		return false
	var guide := FlintGuide.for_player(player)
	if guide == null:
		return false
	if not FlintGuideRules.should_explain(explanation, bool(guide.has_seen.call(id))):
		return true
	if is_host:
		host_need(id, _own_peer())
	elif net != null:
		net.send_to_host(self, &"need_hint", [String(id)])
	return true


func is_showing() -> bool:
	return _showing != &""


func get_showing() -> StringName:
	return _showing


func is_learner() -> bool:
	return _learner


## Host: the running hint (&"" none) and the hints still waiting.
func get_active() -> StringName:
	return _active


func get_waiting_count() -> int:
	return _waiting.size()


# --- Host ---

## Host: peer needs the hint id. Starts it for everybody or queues it; a hint shown this run is not
## shown again (the late learner watched it already).
func host_need(id: StringName, peer: int) -> void:
	if not is_host or _shown.has(id):
		return
	for entry in _waiting:
		if entry[0] == id:
			if not (entry[1] as Array).has(peer):
				(entry[1] as Array).append(peer)
			return
	_waiting.append([id, [peer]])
	_host_next()


## Host: a learner is through the hint id (its own or a client's "Weiter" to the end).
func host_done(id: StringName, peer: int) -> void:
	if not is_host or id != _active:
		return
	_learners.erase(peer)
	if _learners.is_empty():
		_host_end()


func _host_next() -> void:
	if _active != &"" or _waiting.is_empty():
		return
	var entry: Array = _waiting.pop_front()
	var id: StringName = entry[0]
	var learners := PackedInt32Array()
	_learners.clear()
	for peer: int in entry[1]:
		learners.append(peer)
		_learners[peer] = true
	_active = id
	_shown[id] = true
	_time_left = time_limit(build(id))
	if net != null:
		net.send_to_clients(self, &"group_hint", [String(id), learners])
	_hold_host(true)
	_show(id, learners)


func _host_end() -> void:
	var id := _active
	if id == &"":
		return
	_active = &""
	_learners.clear()
	if net != null:
		net.send_to_clients(self, &"group_hint_end", [String(id)])
	_close(id)
	_hold_host(false)
	_host_next()


## Host: holds every player's copy (the clients' too) while a group hint runs.
func _hold_host(on: bool) -> void:
	for node: Variant in all_players.call():
		if is_instance_valid(node) and node is Player:
			(node as Player).set_protected(PROTECTION, on)


func _process(delta: float) -> void:
	if is_host and _active != &"":
		_time_left -= delta
		if _time_left <= 0.0:
			_host_end()


# --- Messages ---

## Client -> host: this client's player needs the hint id.
@rpc("any_peer", "call_remote", "reliable")
func need_hint(id: String) -> void:
	if is_host:
		host_need(StringName(id), multiplayer.get_remote_sender_id())


## Client -> host: this client's learner is through the hint id.
@rpc("any_peer", "call_remote", "reliable")
func hint_done(id: String) -> void:
	if is_host:
		host_done(StringName(id), multiplayer.get_remote_sender_id())


## Host -> clients: show the hint id to everybody now; learners page it.
@rpc("authority", "call_remote", "reliable")
func group_hint(id: String, learners: PackedInt32Array) -> void:
	if not is_host:
		_show(StringName(id), learners)


## Host -> clients: the hint id is over everywhere.
@rpc("authority", "call_remote", "reliable")
func group_hint_end(id: String) -> void:
	if not is_host:
		_close(StringName(id))


# --- Every machine ---

func _show(id: StringName, learners: PackedInt32Array) -> void:
	var explanation := build(id)
	if explanation == null:
		return
	_showing = id
	_learner = learners.has(_own_peer())
	started_count += 1
	var player := local_player.call() as Player
	if player == null:
		return
	if not _held.has(player):
		player.set_protected(PROTECTION, true)
		_held.append(player)
	var guide := FlintGuide.for_player(player)
	if guide == null:
		return
	if _learner and not guide.finished.is_connected(_on_local_finished):
		guide.finished.connect(_on_local_finished)
	guide.queue(group_copy(explanation, _learner), true)


func _close(id: StringName) -> void:
	if _showing != id:
		return
	_showing = &""
	_learner = false
	ended_count += 1
	var player := local_player.call() as Player
	if player != null:
		var guide := FlintGuide.of(player)
		if guide != null:
			guide.withdraw(id)
	_release_local()


func _release_local() -> void:
	for node: Variant in _held:
		if is_instance_valid(node):
			(node as Player).set_protected(PROTECTION, false)
	_held.clear()


## The local learner's guide finished an explanation: through the group hint -> tell the host.
func _on_local_finished(explanation: FlintExplanation, _skipped: bool) -> void:
	if explanation == null or explanation.id != _showing or not _learner:
		return
	_learner = false
	if is_host:
		host_done(explanation.id, _own_peer())
	elif net != null:
		net.send_to_host(self, &"hint_done", [String(explanation.id)])


func _net_local_player() -> Player:
	return net.get_local_player() if net != null else null


func _net_players() -> Array[Player]:
	var result: Array[Player] = []
	if net != null:
		result = net.get_all_players()
	return result


func _own_peer() -> int:
	return multiplayer.get_unique_id() if multiplayer != null and multiplayer.has_multiplayer_peer() else 1


func _exit_tree() -> void:
	_release_local()
	if is_host:
		_hold_host(false)

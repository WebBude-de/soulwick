class_name NetGuide
extends Node
## Flint's "first time" hints in a shared run (feedback #2b1a5a87 23.10.2026: "Wenn dann sollen alle
## Spieler die Erklärung bekommen, wenn einer der Mitspieler die Erklärung braucht / neu ist"), child
## "NetGuide" of NetDungeon on every machine (same node path for the RPCs). The host decides:
## - A machine's coach (FlintControls, explain_first) hands every hint to request_hint (group
##   GROUP_ROUTER). If the local player has seen it, nothing happens; else the machine asks the host.
## - The host starts one hint at a time for everybody (group_hint): every machine shows it in Flint's
##   corner. Only the learners (who asked) are held (Player.set_protected PROTECTION: no input, no
##   damage, enemies ignore him; on the host for their copies too, D-085, nothing pauses) and page
##   with "Weiter" (a TOUR); who knows it already sees it as a short hint that goes on by itself and
##   plays on (FS5: a group with a newcomer is not stopped for every hint). When the last learner is
##   through (hint_done) or the time limit ran out (time_limit), the host ends it everywhere
##   (group_hint_end) and starts the next one waiting.
## - Order and dropping are the host's (FS5): waiting hints by FlintExplanation.priority (danger,
##   then the place, then general), a higher one cuts a running hint of lower priority (it ends
##   unseen everywhere, group_hint_drop, and waits again); a machine whose player no longer needs a
##   hint it asked for (still_due of request_hint, e.g. he used the key himself) takes it back
##   (drop_need), and the host drops it when nobody needs it any more.
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
## (player: Player) -> int: the peer a player belongs to (tests swap it).
var peer_of: Callable = _peer_of_player

## Tests and tools: group hints started and ended here.
var started_count := 0
var ended_count := 0

## Host: hints waiting, [id: StringName, learners: Array[int], priority: int] each (highest first).
var _waiting: Array[Array] = []
## Host: the running hint's learners per peer, the players held for it, its priority.
var _host_held: Array[Player] = []
var _active_priority := 0
## Every machine: hints asked for the local player and not shown yet -> still_due (may be empty).
var _needs: Dictionary[StringName, Callable] = {}
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


## The group form of explanation: for a learner a TOUR (holds and protects, "Weiter"); for who knows
## it a HINT (corner only, goes on by itself, no hold, FS5); once per account like the hint.
static func group_copy(explanation: FlintExplanation, learner: bool) -> FlintExplanation:
	var result := explanation.copy()
	result.style = FlintExplanation.Style.TOUR if learner else FlintExplanation.Style.HINT
	result.auto_advance = not learner
	result.once = true
	result.still_due = Callable()
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
## nothing to do because this player has seen it). still_due: () -> bool, false once the local player
## no longer needs it (then this machine takes the request back).
func request_hint(player: Player, id: StringName, still_due := Callable()) -> bool:
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
	_needs[id] = still_due
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

## Host: peer needs the hint id. Starts it for everybody or queues it by priority (a higher one cuts
## a running hint of lower priority); a hint shown this run is not shown again (the late learner
## watched it already).
func host_need(id: StringName, peer: int) -> void:
	if not is_host or _shown.has(id):
		return
	for entry in _waiting:
		if entry[0] == id:
			if not (entry[1] as Array).has(peer):
				(entry[1] as Array).append(peer)
			return
	var explanation := build(id)
	var priority: int = explanation.priority if explanation != null else 0
	_queue_entry([id, [peer], priority])
	if _active != &"" and priority > _active_priority:
		_host_cut()
	_host_next()


## Host: peer no longer needs the hint id (its player did it himself): out of the waiting hint, which
## is dropped when nobody needs it any more; a running one counts as through for peer.
func host_drop_need(id: StringName, peer: int) -> void:
	if not is_host:
		return
	if id == _active:
		host_done(id, peer)
		return
	for entry in _waiting:
		if entry[0] == id:
			(entry[1] as Array).erase(peer)
			if (entry[1] as Array).is_empty():
				_waiting.erase(entry)
			return


func _queue_entry(entry: Array, before_equals := false) -> void:
	var priorities: Array[int] = []
	for waiting in _waiting:
		priorities.append(int(waiting[2]))
	_waiting.insert(FlintGuideRules.queue_index(priorities, int(entry[2]), before_equals), entry)


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
	_active_priority = int(entry[2])
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


## Host: the running hint gives way to a higher one: it ends unseen everywhere and waits again (in
## front of its equals) with the learners still reading it.
func _host_cut() -> void:
	var id := _active
	var learners: Array = []
	for peer: int in _learners:
		learners.append(peer)
	var entry: Array = [id, learners, _active_priority]
	_active = &""
	_learners.clear()
	_shown.erase(id)
	if net != null:
		net.send_to_clients(self, &"group_hint_drop", [String(id)])
	_drop_local(id)
	_hold_host(false)
	if not learners.is_empty():
		_queue_entry(entry, true)


## Host: holds the learners' players (the clients' copies too) while a group hint runs; who knows it
## plays on (FS5).
func _hold_host(on: bool) -> void:
	if not on:
		for held in _host_held:
			if is_instance_valid(held):
				held.set_protected(PROTECTION, false)
		_host_held.clear()
		return
	for node: Variant in all_players.call():
		if is_instance_valid(node) and node is Player and _learners.has(int(peer_of.call(node))):
			(node as Player).set_protected(PROTECTION, true)
			_host_held.append(node)


func _process(delta: float) -> void:
	_check_needs()
	if is_host and _active != &"":
		_time_left -= delta
		if _time_left <= 0.0:
			_host_end()


## Every machine: a hint asked for the local player and not shown yet that he no longer needs is
## taken back from the host.
func _check_needs() -> void:
	for id: StringName in _needs.keys():
		var still_due: Callable = _needs[id]
		if not still_due.is_valid() or bool(still_due.call()):
			continue
		_needs.erase(id)
		if is_host:
			host_drop_need(id, _own_peer())
		elif net != null:
			net.send_to_host(self, &"drop_need", [String(id)])


# --- Messages ---

## Client -> host: this client's player needs the hint id.
@rpc("any_peer", "call_remote", "reliable")
func need_hint(id: String) -> void:
	if is_host:
		host_need(StringName(id), multiplayer.get_remote_sender_id())


## Client -> host: this client's player no longer needs the hint id it asked for.
@rpc("any_peer", "call_remote", "reliable")
func drop_need(id: String) -> void:
	if is_host:
		host_drop_need(StringName(id), multiplayer.get_remote_sender_id())


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


## Host -> clients: the hint id gave way to a more urgent one; it ends unseen and comes again.
@rpc("authority", "call_remote", "reliable")
func group_hint_drop(id: String) -> void:
	if not is_host:
		_drop_local(StringName(id))


# --- Every machine ---

func _show(id: StringName, learners: PackedInt32Array) -> void:
	var explanation := build(id)
	if explanation == null:
		return
	_showing = id
	_needs.erase(id)
	_learner = learners.has(_own_peer())
	started_count += 1
	var player := local_player.call() as Player
	if player == null:
		return
	if _learner and not _held.has(player):
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


## The hint id ends here unseen (it gave way and comes again).
func _drop_local(id: StringName) -> void:
	if _showing != id:
		return
	_showing = &""
	_learner = false
	var player := local_player.call() as Player
	if player != null:
		var guide := FlintGuide.of(player)
		if guide != null:
			guide.drop(id)
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


func _peer_of_player(player: Node) -> int:
	if player != null and is_instance_valid(player) and player.get(&"is_local") == true:
		return _own_peer()
	return NetDungeon.peer_of(player)


func _own_peer() -> int:
	return multiplayer.get_unique_id() if multiplayer != null and multiplayer.has_multiplayer_peer() else 1


func _exit_tree() -> void:
	_release_local()
	if is_host:
		_hold_host(false)

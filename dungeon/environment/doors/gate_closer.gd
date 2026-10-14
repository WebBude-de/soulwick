class_name GateCloser
extends Node
## No way back (M2, Wunsch Projektmitglied 14.10.2026): once a room has been entered - every living
## player through the transition and inside its floor - the gate of the room left behind shuts (its
## opening animation backwards, with its sound) and stays shut, for players and enemies alike. It never
## shuts on a player: while anyone is outside the new room's floor (in the corridor, in the gate) it
## waits. Co-op: all living players of the group (EnemyTargeting.living_players), never only one.
## Only the decision lives here; the door animates and sounds through DoorView (state_changed).
## Child of the new room, so it goes with it.

signal closed(door: Door)

const NODE_NAME := &"GateCloser"
## A player counts as inside when his position lies this far within the new room's floor. TESTWERT
const INSIDE_MARGIN := 8.0

var door: Door = null
var room: Node2D = null


## Watches the exit gate of previous (the chosen one of a branch room) until everyone is inside room;
## null when there is no open gate to shut.
static func close_behind(previous: Node, entered: Node2D) -> GateCloser:
	var gate := gate_between(previous)
	if gate == null or not gate.is_open or entered == null or not is_instance_valid(entered):
		return null
	var existing := entered.get_node_or_null(NodePath(NODE_NAME)) as GateCloser
	if existing != null:
		return existing
	var closer := GateCloser.new()
	closer.name = NODE_NAME
	closer.door = gate
	closer.room = entered
	entered.add_child(closer)
	return closer


## The exit gate the way left previous through: its only exit or the chosen way of a branch.
static func gate_between(previous: Node) -> Door:
	if previous == null or not is_instance_valid(previous) or not previous.has_method(&"get_exit_doors"):
		return null
	var doors: Array = previous.call(&"get_exit_doors")
	if doors.is_empty():
		return null
	var index := maxi(0, int(previous.call(&"get_chosen_branch")))
	return doors[mini(index, doors.size() - 1)] as Door


## Are all living players inside the floor of room (hook for the co-op group)? False without players.
static func all_players_inside(target: Node2D, tree: SceneTree) -> bool:
	if target == null or not is_instance_valid(target) or not target.has_method(&"get_arena"):
		return false
	var players := EnemyTargeting.living_players(tree)
	if players.is_empty():
		return false
	var floor_rect: Rect2 = (target.call(&"get_arena") as Rect2).grow(-INSIDE_MARGIN)
	for player in players:
		if not floor_rect.has_point(player.global_position):
			return false
	return true


func _physics_process(_delta: float) -> void:
	if door == null or not is_instance_valid(door) or not door.is_open:
		queue_free()
		return
	if not all_players_inside(room, get_tree()):
		return
	door.close()
	closed.emit(door)
	queue_free()

class_name EnemyTargeting
extends RefCounted
## Target choice for enemies (A2, D-088 coop guard rails): the nearest living player of the group
## "player". Works for one or many players; no get_first_node_in_group.

## A new player must be this much closer than the current target before the enemy switches
## (no flip-flopping between two players at almost the same distance). TESTWERT
const SWITCH_MARGIN := 48.0


## All living players of the tree (group "player"), freed or dead ones skipped.
static func living_players(tree: SceneTree) -> Array[Node2D]:
	var players: Array[Node2D] = []
	if tree == null:
		return players
	for node in tree.get_nodes_in_group(&"player"):
		if is_alive(node):
			players.append(node as Node2D)
	return players


## Nearest living candidate to from, or null. Candidates may contain freed or dead nodes.
static func nearest_living(candidates: Array, from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_distance := INF
	for candidate: Variant in candidates:
		if not is_alive(candidate):
			continue
		var node := candidate as Node2D
		var distance := from.distance_squared_to(node.global_position)
		if distance < best_distance:
			best_distance = distance
			best = node
	return best


## Keeps current while it lives, unless another living candidate is SWITCH_MARGIN closer.
## Protected players (menu open in a group game, D-085/D-123) are no targets.
static func choose(candidates: Array, from: Vector2, current: Node2D) -> Node2D:
	var targets: Array = []
	for candidate: Variant in candidates:
		if is_targetable(candidate):
			targets.append(candidate)
	var nearest := nearest_living(targets, from)
	if not is_targetable(current) or nearest == null or nearest == current:
		return nearest
	var current_distance := from.distance_to(current.global_position)
	if from.distance_to(nearest.global_position) + SWITCH_MARGIN < current_distance:
		return nearest
	return current


## Alive and not protected (is_protected() if it has one): a menu in a group game hides a player.
static func is_targetable(candidate: Variant) -> bool:
	if not is_alive(candidate):
		return false
	var node := candidate as Node2D
	return not node.has_method(&"is_protected") or not bool(node.call(&"is_protected"))


## A valid, not freed Node2D that is alive (is_alive() if it has one).
static func is_alive(candidate: Variant) -> bool:
	if candidate == null or not is_instance_valid(candidate) or not (candidate is Node2D):
		return false
	var node := candidate as Node2D
	if not node.is_inside_tree():
		return false
	return not node.has_method(&"is_alive") or bool(node.call(&"is_alive"))

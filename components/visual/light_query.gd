class_name LightQuery
extends RefCounted
## The one decision "does this point lie in the light?" (A9, D-116) for any number of
## light circles: the own circle of every living player (D-084: each player has one) and every
## LightSource with counts_as_light (torches, crystals, lanterns). Flashes, projectiles and enemy
## glows do not count. Effects (a guardian freezes, a torch dims enemies) only ask; they never
## decide here.
## A circle is a Vector3 (x, y = centre in global px, z = lit radius), so the pure part
## (is_in_circles) works without nodes for tests and other rules (light run).
## Co-op: every player is looked up through the group "player" (no first-node lookup, D-088); the
## light radius is state at the player (meta PLAYER_RADIUS_META, written by whoever draws that
## player's vision - today the VisionOverlay - and read by everyone).

## The player's circle is drawn soft over 150 px (vision.gdshader "softness"); the visible edge,
## where half of the light is left, lies this far inside the radius.
const PLAYER_SOFT_EDGE := 75.0
## Player light radius before anyone wrote one (DungeonManager.VISION_RADIUS).
const DEFAULT_PLAYER_RADIUS := 300.0
const PLAYER_RADIUS_META := &"light_radius"


# --- Pure decision ---

static func circle(center: Vector2, lit_radius: float) -> Vector3:
	return Vector3(center.x, center.y, maxf(0.0, lit_radius))


## True if point lies inside (or on the edge of) at least one circle.
static func is_in_circles(point: Vector2, circles: Array[Vector3]) -> bool:
	for c in circles:
		var dx := point.x - c.x
		var dy := point.y - c.y
		if c.z > 0.0 and dx * dx + dy * dy <= c.z * c.z:
			return true
	return false


## Circles of the same radius around a list of points (trial torches, tests).
static func circles_from_points(points: PackedVector2Array, lit_radius: float) -> Array[Vector3]:
	var circles: Array[Vector3] = []
	for point in points:
		circles.append(circle(point, lit_radius))
	return circles


## The lit radius of a player circle with the given drawn radius.
static func player_lit_radius(drawn_radius: float) -> float:
	return maxf(0.0, drawn_radius - PLAYER_SOFT_EDGE)


# --- Players ---

## Stores the drawn light radius of a player (state at the player, D-088).
static func set_player_radius(player: Node, drawn_radius: float) -> void:
	if player != null and is_instance_valid(player):
		player.set_meta(PLAYER_RADIUS_META, drawn_radius)


## Drawn light radius of a player: the stored one, else the default narrowed by dark zones.
static func get_player_radius(player: Node2D) -> float:
	if player == null or not is_instance_valid(player):
		return 0.0
	if player.has_meta(PLAYER_RADIUS_META):
		return float(player.get_meta(PLAYER_RADIUS_META))
	var factor := DarkZone.get_vision_factor_at(player.get_tree(), player.global_position) if player.is_inside_tree() else 1.0
	return DEFAULT_PLAYER_RADIUS * factor


## One circle per living player.
static func player_circles(tree: SceneTree) -> Array[Vector3]:
	var circles: Array[Vector3] = []
	for player in EnemyTargeting.living_players(tree):
		circles.append(circle(player.global_position, player_lit_radius(get_player_radius(player))))
	return circles


# --- Light sources ---

## One circle per burning LightSource that counts as light.
static func source_circles(tree: SceneTree) -> Array[Vector3]:
	var circles: Array[Vector3] = []
	if tree == null:
		return circles
	for node in tree.get_nodes_in_group(LightSource.GAMEPLAY_GROUP):
		var light := node as LightSource
		if light != null and is_instance_valid(light) and light.counts_as_light and light.is_lit():
			circles.append(circle(light.get_lit_center(), light.get_lit_radius()))
	return circles


## Every light circle of the tree: the players' own (unless include_players is false) and the
## counting light sources.
static func get_circles(tree: SceneTree, include_players := true) -> Array[Vector3]:
	var circles: Array[Vector3] = source_circles(tree)
	if include_players:
		circles.append_array(player_circles(tree))
	return circles


## The shared decision: does global_point lie in the light?
static func is_lit(tree: SceneTree, global_point: Vector2, include_players := true) -> bool:
	return is_in_circles(global_point, get_circles(tree, include_players))

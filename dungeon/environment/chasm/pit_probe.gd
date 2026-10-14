class_name PitProbe
extends RefCounted
## "Is there an abyss at this point?" for any node in the world (A4). Abyss tiles are solid on the
## pit physics layer (PhysicsLayers.PIT, tools/build_tilesets.gd), bridges are not, so one point
## query answers for every room, every player and runtime pits (crumbling floor, holes) alike,
## without looking up rooms or players (D-088).

## Search for a safe point around a pit: ring step and the farthest ring (px).
const SEARCH_STEP := 16.0
const SEARCH_RADIUS := 256.0
const SEARCH_DIRECTIONS := 12


## True if a pit tile lies under point (global coordinates) in world.
static func is_pit_at(world: World2D, point: Vector2) -> bool:
	if world == null:
		return false
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = PhysicsLayers.PIT
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return not world.direct_space_state.intersect_point(query, 1).is_empty()


## Callable(point) -> bool that asks the world of node (for ChasmRules).
static func probe_for(node: Node2D) -> Callable:
	return func(point: Vector2) -> bool:
		return is_instance_valid(node) and node.is_inside_tree() and is_pit_at(node.get_world_2d(), point)


## Nearest point to point (in rings of SEARCH_STEP) that is no pit and keeps margin to pits; point
## itself if it is safe, the best found otherwise. is_pit(point) -> bool.
static func nearest_safe_point(point: Vector2, is_pit: Callable, margin := 12.0) -> Vector2:
	if _is_clear(point, is_pit, margin):
		return point
	var radius := SEARCH_STEP
	while radius <= SEARCH_RADIUS:
		for i in SEARCH_DIRECTIONS:
			var candidate := point + Vector2.from_angle(TAU * i / SEARCH_DIRECTIONS) * radius
			if _is_clear(candidate, is_pit, margin):
				return candidate
		radius += SEARCH_STEP
	return point


static func _is_clear(point: Vector2, is_pit: Callable, margin: float) -> bool:
	for sample in ChasmRules.sample_points(point, margin):
		if is_pit.call(sample):
			return false
	return true

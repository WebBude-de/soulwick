class_name EnemyNavigation
extends RefCounted
## Pathfinding for one enemy (A2). With a free walking line to the goal the enemy keeps walking
## straight (its old steering). Only when tiles block the line (walls, pillars, inner walls, later
## abysses) it asks its NavigationAgent2D for a path over the navigation of the room tiles
## (navigation layer of the dungeon tilesets, tools/build_tilesets.gd) and walks the waypoints.
## Obstacles outside the navigation (doors, other bodies on navigable floor) stay with the old
## steering, unless tiles block the line behind them (a torch stand in front of a wall:
## _is_navigation_obstacle). Solid props on tiles without navigation (D-115) count as tiles.
## Two floor tiles touching only at a corner are joined by the tile navigation through that point;
## such paths are asked again around the corner (_close_corner_leaks).
## Tile navigation has no agent radius, so paths touch wall corners. The follower therefore moves
## every turning point away from its corner by the body radius and only skips to the next waypoint
## once the body (circle cast) can reach it without touching a wall.
## Sight checks and path requests are throttled and staggered per enemy, so many enemies stay cheap.
## Without navigation (no tiles, test arenas) the enemy falls back to its old behaviour.

## Seconds between two "free line to the goal?" checks. TESTWERT
const SIGHT_INTERVAL := 0.15
## Seconds between two path requests while the enemy has no free line. TESTWERT
const REPATH_INTERVAL := 0.35
## Ask for a new path earlier when the goal moved this far since the last request (px). TESTWERT
const REPATH_DISTANCE := 48.0
## Seconds between two "can I already walk to the waypoint after the next one?" checks. TESTWERT
const LOOKAHEAD_INTERVAL := 0.1
## A turning waypoint is moved this far (plus body radius) away from the corner it turns around,
## so the body does not scrape along the wall edge. TESTWERT
const CORNER_CLEARANCE := 6.0
## A waypoint counts as reached this close (px). Small on purpose: a larger radius would cut the
## corner the waypoint was moved away from; earlier skips come from the cast-checked lookahead.
## TESTWERT
const ARRIVE_DISTANCE := 5.0
## A path whose waypoints all lie this close to the straight line is "straight": the navigation
## knows no obstacle on the way (px). TESTWERT
const STRAIGHT_TOLERANCE := 12.0
## No walking progress for this long while following a path = stuck (jammed by other enemies, a
## crate on the path): the enemy steps aside for a moment (Enemy._follow_path). TESTWERT
const STUCK_TIME := 0.35
const STUCK_DISTANCE := 6.0
## Bodies outside the navigation (props) the sight check looks past to find tiles behind them.
## TESTWERT
const LOOK_PAST_BODIES := 2
## A solid prop takes the navigation off its tiles (D-115): the sight check probes this far into a
## body it touched; without navigation there, the body is a hole of the navigation like a wall
## (px). TESTWERT
const HOLE_PROBE_DEPTH := 3.0
## Walk casts use the body radius minus this much: a cast ignores bodies its shape already overlaps
## at the start, and a body pressed into a corner overlaps the walls there by a fraction of a pixel,
## so a full-size cast walked "free" straight through them (px). TESTWERT
const CAST_INSET := 1.0
## Two floor tiles that touch only at a corner (a pillar and a blocked prop tile diagonally between
## them) are connected by the tile navigation through that point, a passage no body fits through.
## A path point this close to such a corner is a leak (px). TESTWERT
const CORNER_LEAK_TOLERANCE := 2.0
## At most this many leaks of one path are closed by asking again without one of the two tiles.
const MAX_LEAK_REPAIRS := 3

## Statistics for tools and tests.
var path_requests := 0
var sight_checks := 0
var leak_repairs := 0

var _body: CharacterBody2D
var _agent: NavigationAgent2D
var _radius := 8.0
var _sight_left := 0.0
var _repath_left := 0.0
var _lookahead_left := 0.0
var _walk_clear := true
var _shot_clear := true
var _tiles_in_the_way := false
var _sight_goal := Vector2.INF
var _path_goal := Vector2.INF
var _navigation_ready := false
var _waypoints := PackedVector2Array()
var _waypoint_index := 0
var _following := false
var _cast_shape := CircleShape2D.new()
var _stuck_left := STUCK_TIME
var _stuck_origin := Vector2.ZERO
var _tiles: TileMapLayer = null
var _tiles_searched := false


func _init(body: CharacterBody2D, agent: NavigationAgent2D) -> void:
	_body = body
	_agent = agent
	# Stagger the timers by instance id (deterministic, no random numbers).
	var phase := fmod(float(body.get_instance_id() % 997) * 0.618034, 1.0)
	_sight_left = phase * SIGHT_INTERVAL
	_repath_left = phase * REPATH_INTERVAL
	_lookahead_left = phase * LOOKAHEAD_INTERVAL


## Body radius (collision circle) for casts and corner clearance.
func set_radius(radius: float) -> void:
	_radius = maxf(1.0, radius)
	if _agent != null:
		_agent.radius = _radius


func tick(delta: float) -> void:
	_sight_left -= delta
	_repath_left -= delta
	_lookahead_left -= delta


## Is the straight walk from the body (centre of its collision circle) to goal free of walls?
## Cached for SIGHT_INTERVAL while the goal stays close to the last checked one.
func has_free_walk(from: Vector2, goal: Vector2) -> bool:
	_refresh_sight(from, goal)
	return _walk_clear


## Would a projectile from the enemy reach goal without hitting a wall (same ray as Projectile)?
func has_free_shot(from: Vector2, goal: Vector2) -> bool:
	_refresh_sight(from, goal)
	return _shot_clear


## Unit direction to walk towards goal: Vector2.ZERO while the straight line is free or only
## blocked by something outside the navigation (crate, door: the caller keeps its old steering),
## the path direction when walls, pillars or abysses of the tiles are in the way. from is the
## body centre.
func direction_to(from: Vector2, goal: Vector2) -> Vector2:
	if has_free_walk(from, goal) or not _tiles_in_the_way:
		_following = false
		return Vector2.ZERO
	return path_direction(from, goal)


## Unit direction along the navigation path to goal (ignores the free line), or Vector2.ZERO
## when there is no navigation, no path or the rest of the path is a straight line to the goal.
func path_direction(from: Vector2, goal: Vector2) -> Vector2:
	if _agent == null:
		return Vector2.ZERO
	if _repath_left <= 0.0 or goal.distance_to(_path_goal) > REPATH_DISTANCE:
		_repath_left = REPATH_INTERVAL
		_path_goal = goal
		_navigation_ready = _has_navigation()
		if _navigation_ready:
			_request_path(from, goal)
	if not _navigation_ready or _waypoint_index >= _waypoints.size():
		_following = false
		return Vector2.ZERO
	if from.distance_to(_waypoints[_waypoint_index]) < ARRIVE_DISTANCE:
		_waypoint_index += 1
	if _lookahead_left <= 0.0:
		_lookahead_left = LOOKAHEAD_INTERVAL
		_skip_reachable_waypoints(from)
	if _is_rest_straight(from, goal):
		# The navigation sees a straight way, so whatever blocks the line is not part of it (crate,
		# closed door, a wall body without tiles). The caller's old steering walks around such
		# obstacles better than a straight push along the path.
		_following = false
		return Vector2.ZERO
	var to_next := _waypoints[_waypoint_index] - from
	if to_next.length_squared() < 1.0:
		return Vector2.ZERO
	_following = true
	return to_next.normalized()


## True when every remaining waypoint lies within STRAIGHT_TOLERANCE of the line from -> goal.
func _is_rest_straight(from: Vector2, goal: Vector2) -> bool:
	for i in range(_waypoint_index, _waypoints.size()):
		var point := _waypoints[i]
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, from, goal)) > STRAIGHT_TOLERANCE:
			return false
	return true


## Following a path and not moving: true once, then the caller steers around for a moment.
func is_stuck(delta: float) -> bool:
	if not _following:
		_stuck_left = STUCK_TIME
		_stuck_origin = _body.global_position
		return false
	_stuck_left -= delta
	if _body.global_position.distance_to(_stuck_origin) > STUCK_DISTANCE:
		_stuck_left = STUCK_TIME
		_stuck_origin = _body.global_position
		return false
	if _stuck_left > 0.0:
		return false
	_stuck_left = STUCK_TIME
	_stuck_origin = _body.global_position
	return true


func is_following_path() -> bool:
	return _following


## Remaining waypoints of the current path (for tools and debugging).
func get_waypoints() -> PackedVector2Array:
	return _waypoints.slice(_waypoint_index)


## Nearest point on the navigation of the room to point (teleport targets), or point itself.
func snap_to_navigation(point: Vector2) -> Vector2:
	if not _has_navigation():
		return point
	return NavigationServer2D.map_get_closest_point(_get_map(), point)


## Would the body circle (centre body_centre) stand free of walls, pillars and props there?
## (Teleport targets: a point snapped to the navigation edge can still overlap a pillar.)
func fits_at(body_centre: Vector2) -> bool:
	_cast_shape.radius = _radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _cast_shape
	query.transform = Transform2D(0.0, body_centre)
	query.collision_mask = _walk_mask()
	query.exclude = [_body.get_rid()]
	return _body.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


## Would a projectile from from reach to without hitting a wall (same ray as Projectile)? Uncached,
## for points the enemy does not stand on (teleport targets).
func is_shot_free(from: Vector2, to: Vector2) -> bool:
	var ray := PhysicsRayQueryParameters2D.create(from, to, PhysicsLayers.WORLD)
	ray.collide_with_areas = false
	ray.exclude = [_body.get_rid()]
	return _body.get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


## Hook for RoomController (integrator): gives a room's tile layer its own navigation map.
## Stacked rooms share one corridor tile, so in the shared world map their floor polygons overlap
## and Godot warns about edge errors on every map change. With one map per room the warning is
## gone and enemies of different rooms never path through each other's floor. Call once after
## the room entered the tree; extra layers of the room (bridges, A4) must use the same map.
static func isolate_room_navigation(tiles: TileMapLayer) -> RID:
	if tiles == null or not tiles.is_inside_tree():
		return RID()
	var map := NavigationServer2D.map_create()
	NavigationServer2D.map_set_cell_size(map, float(ProjectSettings.get_setting("navigation/2d/default_cell_size", 1.0)))
	NavigationServer2D.map_set_edge_connection_margin(map, float(ProjectSettings.get_setting("navigation/2d/default_edge_connection_margin", 1.0)))
	NavigationServer2D.map_set_active(map, true)
	tiles.set_navigation_map(map)
	tiles.tree_exited.connect(func() -> void: NavigationServer2D.free_rid(map), CONNECT_ONE_SHOT)
	return map


## Turning points of a path moved away from the corner they turn around (inside of the turn),
## without the start point. Pure geometry, static for tests.
static func clear_corners(raw_path: PackedVector2Array, clearance: float) -> PackedVector2Array:
	# Tile navigation repeats points where polygons meet; duplicates have no direction.
	var path := PackedVector2Array()
	for point in raw_path:
		if path.is_empty() or path[path.size() - 1].distance_squared_to(point) > 1.0:
			path.append(point)
	var points := PackedVector2Array()
	for i in range(1, path.size()):
		var point := path[i]
		if i < path.size() - 1:
			var incoming := (path[i] - path[i - 1]).normalized()
			var outgoing := (path[i + 1] - path[i]).normalized()
			var away := incoming - outgoing
			if away.length_squared() > 0.01:
				point += away.normalized() * clearance
		points.append(point)
	return points


func _request_path(from: Vector2, goal: Vector2) -> void:
	var map := _get_map()
	if _agent.get_navigation_map() != map:
		_agent.set_navigation_map(map)
	_agent.target_position = goal
	# Computes the path right away (the agent queries lazily).
	_agent.get_next_path_position()
	path_requests += 1
	var raw_path := _close_corner_leaks(map, _agent.get_current_navigation_path(), goal)
	_waypoints = clear_corners(raw_path, _radius + CORNER_CLEARANCE)
	for i in _waypoints.size():
		_waypoints[i] = _push_out_of_walls(_waypoints[i])
	_waypoint_index = 0
	_skip_reachable_waypoints(from)
	_lookahead_left = LOOKAHEAD_INTERVAL


## The tile navigation has one region per tile and joins regions whose edges touch, even in a
## single point: two floor tiles diagonal to each other between two closed tiles (saeulenkreis: a
## pillar and the tile of a decoration group) form a passage of zero width. A path through such a
## corner leads the body into the gap, where it hangs (the shadow lord behind the pillar). The path
## is asked again without the region of one of the two tiles (never the one of start or goal), so it
## goes around; without a better path the old one stays.
func _close_corner_leaks(map: RID, path: PackedVector2Array, goal: Vector2) -> PackedVector2Array:
	var tiles := _tiles if _tiles != null and is_instance_valid(_tiles) and _tiles.is_inside_tree() else null
	if tiles == null or tiles.tile_set == null or path.size() < 3:
		return path
	var kept: Array[RID] = [
		NavigationServer2D.map_get_closest_point_owner(map, path[0]),
		NavigationServer2D.map_get_closest_point_owner(map, path[path.size() - 1]),
	]
	var excluded: Array[RID] = []
	for _repair in MAX_LEAK_REPAIRS:
		var leak := find_corner_leak(map, tiles, path)
		if leak.is_empty():
			return path
		var region := RID()
		for cell in leak:
			var owner := NavigationServer2D.map_get_closest_point_owner(map, tiles.to_global(tiles.map_to_local(cell)))
			if owner.is_valid() and not kept.has(owner) and not excluded.has(owner):
				region = owner
				break
		if not region.is_valid():
			return path
		excluded.append(region)
		var query := NavigationPathQueryParameters2D.new()
		query.map = map
		query.start_position = path[0]
		query.target_position = goal
		query.navigation_layers = _agent.navigation_layers
		query.pathfinding_algorithm = _agent.pathfinding_algorithm
		query.path_postprocessing = _agent.path_postprocessing
		query.simplify_path = _agent.simplify_path
		query.simplify_epsilon = _agent.simplify_epsilon
		query.excluded_regions = excluded
		var result := NavigationPathQueryResult2D.new()
		NavigationServer2D.query_path(query, result)
		if result.path.size() < 2:
			return path
		path = result.path
		leak_repairs += 1
	return path


## The two floor cells of the first corner leak on path (see _close_corner_leaks), or an empty
## array. A cell is floor when the navigation map covers its centre. Static for tests.
static func find_corner_leak(map: RID, tiles: TileMapLayer, path: PackedVector2Array) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	if tiles == null or tiles.tile_set == null:
		return none
	var size := Vector2(tiles.tile_set.tile_size)
	for i in range(1, path.size() - 1):
		var local := tiles.to_local(path[i])
		var corner := Vector2i((local / size).round())
		if path[i].distance_to(tiles.to_global(Vector2(corner) * size)) > CORNER_LEAK_TOLERANCE:
			continue
		var north_west := corner + Vector2i(-1, -1)
		var north_east := corner + Vector2i(0, -1)
		var south_west := corner + Vector2i(-1, 0)
		var south_east := corner
		var nw := _is_floor_cell(map, tiles, north_west)
		var ne := _is_floor_cell(map, tiles, north_east)
		var sw := _is_floor_cell(map, tiles, south_west)
		var se := _is_floor_cell(map, tiles, south_east)
		if nw and se and not ne and not sw:
			return [north_west, south_east] as Array[Vector2i]
		if ne and sw and not nw and not se:
			return [north_east, south_west] as Array[Vector2i]
	return none


static func _is_floor_cell(map: RID, tiles: TileMapLayer, cell: Vector2i) -> bool:
	var centre := tiles.to_global(tiles.map_to_local(cell))
	return NavigationServer2D.map_get_closest_point(map, centre).distance_to(centre) < 1.0


## Shortcut: while the body can walk straight to the waypoint after the current one, take it.
func _skip_reachable_waypoints(from: Vector2) -> void:
	var skips := 0
	while _waypoint_index < _waypoints.size() - 1 and skips < 3 and _can_walk(from, _waypoints[_waypoint_index + 1]):
		_waypoint_index += 1
		skips += 1


## Paths run along wall edges; a body standing on such a waypoint would overlap the wall. Moves the
## point out until the body circle (plus a little air) is free.
func _push_out_of_walls(point: Vector2) -> Vector2:
	var reach := _radius + 2.0
	_cast_shape.radius = reach
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _cast_shape
	query.collision_mask = _walk_mask()
	query.exclude = [_body.get_rid()]
	var space := _body.get_world_2d().direct_space_state
	for _attempt in 2:
		query.transform = Transform2D(0.0, point)
		var contact := space.get_rest_info(query)
		if contact.is_empty():
			break
		var normal: Vector2 = contact["normal"]
		if normal == Vector2.ZERO:
			break
		var surface: Vector2 = contact["point"]
		point += normal * (reach - (point - surface).dot(normal) + 0.5)
	return point


func _can_walk(from: Vector2, to: Vector2) -> bool:
	return _walk_cast(from, to) < 0.0


## Circle cast of the body from from to to against everything the body collides with except
## players and enemies (walls, props, later abysses: A4 adds the pit layer to the enemy mask).
## Returns the fraction where the body first touches something, or -1.0 when the way is free.
func _walk_cast(from: Vector2, to: Vector2, exclude: Array[RID] = []) -> float:
	_cast_shape.radius = maxf(1.0, _radius - CAST_INSET)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _cast_shape
	query.transform = Transform2D(0.0, from)
	query.motion = to - from
	query.collision_mask = _walk_mask()
	var excluded: Array[RID] = [_body.get_rid()]
	excluded.append_array(exclude)
	query.exclude = excluded
	var result := _body.get_world_2d().direct_space_state.cast_motion(query)
	if result.size() < 2 or result[0] >= 1.0:
		return -1.0
	return result[1]


func _walk_mask() -> int:
	var mask := _body.collision_mask & ~(PhysicsLayers.PLAYER | PhysicsLayers.ENEMIES)
	return mask if mask != 0 else PhysicsLayers.WORLD


## Does a part of the tile navigation (a TileMapLayer: walls, pillars, inner walls, abysses; a
## HeightBody: cliffs, edges and ladders of a plateau, M3) block
## the way from -> goal, first touched at fraction? A body on tiles without navigation counts too:
## solid props take the navigation off their tiles (D-115, a decoration group, a crate), so the path
## knows the way around them. Doors, test walls and other bodies on navigable floor are not part of
## it; the old steering walks around those. But such a body may stand in front of a wall or an abyss
## (a torch stand inside a wall cup, a crystal at a chasm): then the steering alone walks into the
## tiles behind it, so the cast looks past up to LOOK_PAST_BODIES of them.
func _is_navigation_obstacle(from: Vector2, goal: Vector2, fraction: float) -> bool:
	_cast_shape.radius = _radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _cast_shape
	query.collision_mask = _walk_mask()
	var space := _body.get_world_2d().direct_space_state
	var passed: Array[RID] = []
	for _attempt in LOOK_PAST_BODIES + 1:
		var excluded: Array[RID] = [_body.get_rid()]
		excluded.append_array(passed)
		query.exclude = excluded
		query.transform = Transform2D(0.0, from.lerp(goal, fraction))
		var contact := space.get_rest_info(query)
		if contact.is_empty():
			return false
		var collider := instance_from_id(int(contact["collider_id"]))
		if collider is TileMapLayer or collider is HeightBody or _is_navigation_hole(contact):
			return true
		passed.append(contact["rid"])
		fraction = _walk_cast(from, goal, passed)
		if fraction < 0.0:
			return false
	return false


## Is the body of a rest contact a hole in the navigation (a solid prop on blocked tiles)? Probes a
## little inside it: the contact normal points out of the touched body.
func _is_navigation_hole(contact: Dictionary) -> bool:
	if not _has_navigation():
		return false
	var normal: Vector2 = contact["normal"]
	if normal == Vector2.ZERO:
		return false
	var inside: Vector2 = contact["point"] - normal * HOLE_PROBE_DEPTH
	return NavigationServer2D.map_get_closest_point(_get_map(), inside).distance_to(inside) > 1.0


func _refresh_sight(from: Vector2, goal: Vector2) -> void:
	if _sight_left > 0.0 and goal.distance_to(_sight_goal) < REPATH_DISTANCE * 0.5:
		return
	_sight_left = SIGHT_INTERVAL
	_sight_goal = goal
	sight_checks += 1
	var blocked_at := _walk_cast(from, goal)
	_walk_clear = blocked_at < 0.0
	_tiles_in_the_way = not _walk_clear and _is_navigation_obstacle(from, goal, blocked_at)
	var ray := PhysicsRayQueryParameters2D.create(_body.global_position, goal, PhysicsLayers.WORLD)
	ray.collide_with_areas = false
	ray.exclude = [_body.get_rid()]
	_shot_clear = _body.get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


## The map of the room tiles above the enemy (own map after isolate_room_navigation), else the
## world map.
func _get_map() -> RID:
	if not _tiles_searched or (_tiles != null and not is_instance_valid(_tiles)):
		_tiles_searched = true
		_tiles = _find_tiles()
	if _tiles != null and is_instance_valid(_tiles) and _tiles.is_inside_tree():
		return _tiles.get_navigation_map()
	return _body.get_world_2d().navigation_map


func _find_tiles() -> TileMapLayer:
	var node := _body.get_parent()
	while node != null:
		var tiles := node.get_node_or_null(^"Tiles") as TileMapLayer
		if tiles != null:
			return tiles
		node = node.get_parent()
	return null


## A synchronised map with at least one region (no query before the first sync: Godot errors).
func _has_navigation() -> bool:
	var map := _get_map()
	if not map.is_valid() or NavigationServer2D.map_get_iteration_id(map) == 0:
		return false
	return not NavigationServer2D.map_get_regions(map).is_empty()

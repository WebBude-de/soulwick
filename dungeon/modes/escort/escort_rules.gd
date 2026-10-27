class_name EscortRules
extends RefCounted
## Rules of the escort mode "Geleit" (RAEUME §3.3, design answer 01_raumarten.md, R4a):
## the numbers (TESTWERTE) and the pure decisions - the path the lost villager walks, when he stops,
## how fast he goes, how many hearts he has. No nodes, no effects: EscortMode applies them.

const ID: StringName = &"escort"
## Plan mode of the templates made for it (RoomTemplate.mode, plan header "mode: escort").
const PLAN_MODE: StringName = &"escort"
## First room the mode may appear in (Zyklus 2, RAEUME §2). TESTWERT
const MIN_ROOM := 6
## Share among the minigames of a draw (R4b mode table). TESTWERT
const WEIGHT := 1.0
## Objective marker of the plan (cell '1'): where the villager waits.
const START_MARKER: StringName = &"escort_start"

## Walking speed of the villager (px/s; a player walks 180). TESTWERT
const WALK_SPEED := 58.0
## ... times this while a player walks beside him (Konzept: 1,2×). TESTWERT
const ESCORT_SPEED_FACTOR := 1.2
## "Beside him": a living player at most this far from the villager (px, about 1.75 tiles). TESTWERT
const BESIDE_DISTANCE := 112.0
## He stops and calls for help while an enemy is closer than 3 tiles (px). TESTWERT
const STOP_DISTANCE := 192.0
## Seconds between two help calls while he stands. TESTWERT
const HELP_CALL_INTERVAL := 3.5
## Hearts: every enemy hit costs one, whatever its damage, then a short invulnerability. TESTWERTE
const HEARTS := 4
const HEARTS_PER_EXTRA_PLAYER := 1
const HIT_INVULNERABILITY := 1.0
## Chance that the lost one is a chicken with a lantern (Konzept: ca. 5 %). TESTWERT
const CHICKEN_CHANCE := 0.05
## Share of the enemies that go for the villager first (EnemyDecoy), one roll each. TESTWERT
const TARGET_SHARE := 0.6
## The room's own encounter times this: the pushes along the way bring the rest. TESTWERT
const ENCOUNTER_FACTOR := 0.6
## Pushes while he walks: every PUSH_INTERVAL s PUSH_SIZE enemies out of sources near his way,
## never while PUSH_MAX_ALIVE enemies are up. TESTWERTE
const PUSH_INTERVAL := 8.0
const PUSH_FIRST_DELAY := 5.0
const PUSH_SIZE := 2
const PUSH_MAX_ALIVE := 6
## Sources of a push: at least this far from every player (px, like SpawnSourceRules) and within
## this distance band of the villager (px), so the enemies come to him, not out of his feet.
const PUSH_MIN_PLAYER_DISTANCE := 160.0
const PUSH_VILLAGER_RANGE := Vector2(128.0, 480.0)
## Path costs: water slows him (walk around it), tiles along a wall are avoided a little.
const STEP_COST := 1.0
const DIAGONAL_COST := 1.4142
const WATER_COST := 4.0
const WALL_SIDE_COST := 0.35
## On the goal: the villager counts as arrived this close to the end of the path (px).
const ARRIVE_DISTANCE := 4.0

const NEIGHBOURS_8: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1),
]


## Hearts of the villager for a group of players (co-op: more enemies, one more heart each).
static func max_hearts(players: int) -> int:
	return HEARTS + HEARTS_PER_EXTRA_PLAYER * (maxi(1, players) - 1)


static func walk_speed(player_beside: bool) -> float:
	return WALK_SPEED * (ESCORT_SPEED_FACTOR if player_beside else 1.0)


## He stands still while an enemy is this close (distance to the nearest enemy that is out).
static func should_stop(nearest_enemy_distance: float) -> bool:
	return nearest_enemy_distance < STOP_DISTANCE


static func is_player_beside(nearest_player_distance: float) -> bool:
	return nearest_player_distance <= BESIDE_DISTANCE


static func is_chicken(roll: float) -> bool:
	return roll < CHICKEN_CHANCE


static func targets_villager(roll: float) -> bool:
	return roll < TARGET_SHARE


static func should_push(since_last_push: float, elapsed: float, alive: int) -> bool:
	return elapsed >= PUSH_FIRST_DELAY and since_last_push >= PUSH_INTERVAL and alive < PUSH_MAX_ALIVE


## Cheapest way over walkable tiles from start to goal (A*, 8 directions, a diagonal step only when
## both straight neighbours are walkable, so he never cuts a wall corner). water: tiles that cost
## WATER_COST; tiles beside a non-walkable tile cost WALL_SIDE_COST more. Ties are broken by tile
## order, so the same room always gives the same path. Empty when goal cannot be reached.
static func find_path(walkable: Dictionary[Vector2i, bool], water: Dictionary[Vector2i, bool], start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not walkable.has(start) or not walkable.has(goal):
		return path
	var cost_so_far: Dictionary[Vector2i, float] = {start: 0.0}
	var came_from: Dictionary[Vector2i, Vector2i] = {}
	var open: Array[Vector2i] = [start]
	var closed: Dictionary[Vector2i, bool] = {}
	while not open.is_empty():
		var best_index := 0
		var best_score := INF
		for i in open.size():
			var tile := open[i]
			var score := cost_so_far[tile] + _heuristic(tile, goal)
			if score < best_score - 0.0001 or (absf(score - best_score) <= 0.0001 and _tile_before(tile, open[best_index])):
				best_score = score
				best_index = i
		var current: Vector2i = open.pop_at(best_index)
		if current == goal:
			break
		closed[current] = true
		for offset in NEIGHBOURS_8:
			var next := current + offset
			if not walkable.has(next) or closed.has(next):
				continue
			var diagonal := offset.x != 0 and offset.y != 0
			if diagonal and (not walkable.has(current + Vector2i(offset.x, 0)) or not walkable.has(current + Vector2i(0, offset.y))):
				continue
			var step := DIAGONAL_COST if diagonal else STEP_COST
			if water.has(next):
				step *= WATER_COST
			if _beside_wall(next, walkable):
				step += WALL_SIDE_COST
			var new_cost := cost_so_far[current] + step
			if not cost_so_far.has(next) or new_cost < cost_so_far[next] - 0.0001:
				cost_so_far[next] = new_cost
				came_from[next] = current
				if not open.has(next):
					open.append(next)
	if not cost_so_far.has(goal):
		return path
	var tile := goal
	path.append(tile)
	while tile != start:
		tile = came_from[tile]
		path.append(tile)
	path.reverse()
	return path


## Total length of a polyline (px).
static func path_length(points: PackedVector2Array) -> float:
	var length := 0.0
	for i in range(1, points.size()):
		length += points[i - 1].distance_to(points[i])
	return length


## Point at distance along a polyline (clamped to its ends).
static func point_at(points: PackedVector2Array, distance: float) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var left := maxf(0.0, distance)
	for i in range(1, points.size()):
		var segment := points[i - 1].distance_to(points[i])
		if left <= segment:
			return points[i - 1].lerp(points[i], left / segment) if segment > 0.0 else points[i]
		left -= segment
	return points[points.size() - 1]


## Share of the way done (0..1).
static func progress(travelled: float, total: float) -> float:
	return clampf(travelled / total, 0.0, 1.0) if total > 0.0 else 1.0


static func _heuristic(tile: Vector2i, goal: Vector2i) -> float:
	var dx := absi(goal.x - tile.x)
	var dy := absi(goal.y - tile.y)
	return STEP_COST * maxi(dx, dy) + (DIAGONAL_COST - STEP_COST) * mini(dx, dy)


static func _beside_wall(tile: Vector2i, walkable: Dictionary[Vector2i, bool]) -> bool:
	for offset in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		if not walkable.has(tile + offset):
			return true
	return false


static func _tile_before(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)

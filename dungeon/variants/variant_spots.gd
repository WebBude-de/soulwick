class_name VariantSpots
extends RefCounted
## Where variant objects may stand (soul flame, rifts, escape hole, chest, wager altar). Pure tile
## math on a set of free floor tiles; free_tiles() reads that set from a room once: tiles reachable
## on foot from the entrance inside the floor rectangle, minus tiles under props, ingredients, blocked
## navigation and the rows right at the doors. Every choice that needs chance takes an RNG.

const INVALID := Vector2i(-1, -1)
const NEIGHBOURS_8: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
	Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]


## Free floor tiles of a room (see class comment). Doors: the inside tiles of both doors and their
## direct neighbours stay free for the way through.
static func free_tiles(room: RoomController) -> Dictionary[Vector2i, bool]:
	var free: Dictionary[Vector2i, bool] = {}
	if room == null or room.tiles == null:
		return free
	var tiles := room.tiles
	var floor_rect := Rect2i(Vector2i.ZERO, tiles.room_size)
	# On foot (no dash over abysses, A4): enemies and summons must reach every variant object.
	for tile: Vector2i in tiles.get_reachable_tiles(0).keys():
		if floor_rect.has_point(tile) and not tiles.is_navigation_blocked(tile):
			free[tile] = true
	for node in occupied_nodes(room):
		free.erase(RoomTiles.local_to_tile(room.to_local(node.global_position) if node.is_inside_tree() else node.position))
	for door in [tiles.get_entrance_inside_tile(), tiles.get_exit_inside_tile()]:
		free.erase(door)
	# Nothing on the foot of a stair or ladder, or a chest could lock a player on a plateau (M3b, D-189).
	return HeightRules.keep_feet_free(tiles, free)


## Props of the template and everything an ingredient scatter built (traps, cover, barrels).
static func occupied_nodes(room: RoomController) -> Array[Node2D]:
	var nodes: Array[Node2D] = []
	var props := room.get_node_or_null("Props")
	var candidates: Array[Node] = props.get_children() if props != null else []
	for child in room.get_children():
		if child.has_method(&"get_built_nodes"):
			candidates.append_array(child.call(&"get_built_nodes"))
	for candidate in candidates:
		var node := candidate as Node2D
		if node != null and is_instance_valid(node):
			nodes.append(node)
	return nodes


## True if the tile and all eight neighbours are free (nothing stands in the way around it).
static func is_open(tile: Vector2i, free: Dictionary[Vector2i, bool]) -> bool:
	if not free.has(tile):
		return false
	for offset in NEIGHBOURS_8:
		if not free.has(tile + offset):
			return false
	return true


## Open tile nearest to target (ties: smaller y, then smaller x, so the result is stable), or INVALID.
static func nearest_open(free: Dictionary[Vector2i, bool], target: Vector2i) -> Vector2i:
	var best := INVALID
	var best_distance := INF
	for tile: Vector2i in sorted_tiles(free):
		if not is_open(tile, free):
			continue
		var distance := Vector2(tile - target).length_squared()
		if distance < best_distance:
			best_distance = distance
			best = tile
	return best


## Free tile nearest to target (no open area needed), or INVALID.
static func nearest_free(free: Dictionary[Vector2i, bool], target: Vector2i, exclude: Array[Vector2i] = []) -> Vector2i:
	var best := INVALID
	var best_distance := INF
	for tile: Vector2i in sorted_tiles(free):
		if exclude.has(tile):
			continue
		var distance := Vector2(tile - target).length_squared()
		if distance < best_distance:
			best_distance = distance
			best = tile
	return best


## Free tiles with a wall (or rock) directly north of them - walkable = RoomTiles.get_walkable_tiles():
## there a rift seems to tear out of the wall. Only tiles at least door_clearance tiles from every
## door tile.
static func wall_tiles(free: Dictionary[Vector2i, bool], walkable: Dictionary[Vector2i, bool], doors: Array[Vector2i], door_clearance: float) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for tile: Vector2i in sorted_tiles(free):
		if walkable.has(tile + Vector2i.UP) or not is_clear_of(tile, doors, door_clearance):
			continue
		result.append(tile)
	return result


## Up to count tiles out of candidates, at least min_distance tiles apart, drawn with rng.
static func pick_spread(candidates: Array[Vector2i], count: int, min_distance: float, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var pool := candidates.duplicate()
	var picked: Array[Vector2i] = []
	while picked.size() < count and not pool.is_empty():
		var tile: Vector2i = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		if is_clear_of(tile, picked, min_distance):
			picked.append(tile)
	return picked


## A free tile far from origin: at least min_tiles from it and away_tiles from every tile in away;
## drawn with rng from the farther half of those. Without such a tile the farthest free tile.
static func far_tile(free: Dictionary[Vector2i, bool], origin: Vector2i, min_tiles: float, away: Array[Vector2i], away_tiles: float, rng: RandomNumberGenerator) -> Vector2i:
	var candidates: Array[Vector2i] = []
	var farthest := INVALID
	var farthest_distance := -1.0
	for tile: Vector2i in sorted_tiles(free):
		var distance := Vector2(tile - origin).length()
		if distance > farthest_distance:
			farthest_distance = distance
			farthest = tile
		if distance >= min_tiles and is_clear_of(tile, away, away_tiles):
			candidates.append(tile)
	if candidates.is_empty():
		return farthest
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a - origin).length_squared() > Vector2(b - origin).length_squared())
	var half := maxi(1, ceili(candidates.size() * 0.5))
	return candidates[rng.randi_range(0, half - 1)]


## Free floor tiles of the bottom row next to the entrance (wager altar): x = entrance +-1, +-2.
## along: direction along the entrance wall (RIGHT for north/south doors, DOWN for west/east, A10).
static func altar_tile(free: Dictionary[Vector2i, bool], entrance_inside: Vector2i, along := Vector2i.RIGHT) -> Vector2i:
	for step in [1, -1, 2, -2]:
		var tile: Vector2i = entrance_inside + along * step
		if free.has(tile):
			return tile
	return INVALID


static func is_clear_of(tile: Vector2i, others: Array[Vector2i], min_distance: float) -> bool:
	for other in others:
		if Vector2(tile - other).length() < min_distance:
			return false
	return true


## Tiles in a fixed order (y, then x), so draws do not depend on dictionary order.
static func sorted_tiles(free: Dictionary[Vector2i, bool]) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	tiles.assign(free.keys())
	tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	return tiles

class_name WallGates
extends RefCounted
## Where enemies step out of the walls of an arena (A5): pure tile maths, no nodes.
## A gate is a reachable floor tile right inside the outer wall plus the wall tile behind it.
## Door corridors, the tiles beside the doors and tiles with props (torches, crates, traps) are
## never gates. pick() spreads the enemies of a wave over several walls and keeps a minimum
## distance to every player (D-113).

enum Side { NORTH, EAST, SOUTH, WEST }

const SIDE_DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
## Tiles whose centre lies this close to a prop are no gate (torches hang between two tiles).
const PROP_CLEARANCE := 48.0
## Gates of a plain arena are placed at least this many tiles apart on one wall.
const GATE_SPACING := 2


## One opening in the wall. Positions are room-local px.
class Gate:
	var side: int = Side.NORTH
	var wall_tile := Vector2i.ZERO
	var floor_tile := Vector2i.ZERO

	func _init(gate_side: int, wall: Vector2i, floor_cell: Vector2i) -> void:
		side = gate_side
		wall_tile = wall
		floor_tile = floor_cell

	## Where the enemy stands once it is out of the wall.
	func get_floor_position() -> Vector2:
		return RoomTiles.tile_center(floor_tile)

	## Where the enemy waits inside the wall.
	func get_wall_position() -> Vector2:
		return RoomTiles.tile_center(wall_tile)

	## Middle of the edge between wall and floor: the breach effect sits here.
	func get_edge_position() -> Vector2:
		return (get_floor_position() + get_wall_position()) * 0.5

	## Unit direction from the wall into the room.
	func get_inward() -> Vector2:
		return Vector2(floor_tile - wall_tile)


## All gates of a room. reachable: floor reachable from the entrance (RoomTiles.get_reachable_tiles),
## room_size: the floor rectangle, door_tiles: entrance/exit corridor tiles in the walls,
## prop_positions: room-local positions of props.
static func find_gates(reachable: Dictionary, room_size: Vector2i, door_tiles: Array[Vector2i], prop_positions: Array[Vector2]) -> Array[Gate]:
	var gates: Array[Gate] = []
	var floor_rect := Rect2i(Vector2i.ZERO, room_size)
	for tile: Vector2i in reachable:
		if not floor_rect.has_point(tile) or _near_prop(tile, prop_positions):
			continue
		for side in SIDE_DIRECTIONS.size():
			var wall := tile + SIDE_DIRECTIONS[side]
			# Only the outer wall ring: inner walls and pillars keep their look.
			if floor_rect.has_point(wall) or reachable.has(wall):
				continue
			if _near_door(wall, door_tiles) or _near_prop(wall, prop_positions):
				continue
			gates.append(Gate.new(side, wall, tile))
	# Dictionary order is insertion order; sort anyway so the RNG picks are reproducible.
	gates.sort_custom(func(a: Gate, b: Gate) -> bool: return _gate_key(a) < _gate_key(b))
	return gates


## count gates for one wave (gates repeat when there are fewer gates than enemies). Gates closer
## than min_distance to any player are skipped; if that leaves fewer than min_sides walls, the
## farthest gate of each missing wall is added until min_sides walls are reached. Walls take turns
## in a random order, so a wave comes from at least min(min_sides, count, walls) walls.
static func pick(gates: Array[Gate], count: int, player_positions: Array[Vector2], min_distance: float, min_sides: int, rng: RandomNumberGenerator) -> Array[Gate]:
	var picked: Array[Gate] = []
	if gates.is_empty() or count <= 0:
		return picked
	var by_side := _group_by_side(filter_by_distance(gates, player_positions, min_distance))
	if by_side.size() < mini(min_sides, _group_by_side(gates).size()):
		by_side = _fill_missing_sides(by_side, gates, player_positions, min_sides)
	if by_side.is_empty():
		# Every gate is too close (players in all corners): the farthest gate still beats none.
		by_side = _group_by_side([_farthest(gates, player_positions)])
	var sides: Array = by_side.keys()
	sides.sort()
	_shuffle(sides, rng)
	var pools := {}
	for side: int in sides:
		pools[side] = (by_side[side] as Array).duplicate()
	var turn := 0
	while picked.size() < count:
		var side: int = sides[turn % sides.size()]
		turn += 1
		var pool: Array = pools[side]
		if pool.is_empty():
			# Wall used up: start over with its gates (enemies queue behind each other).
			pool.append_array(by_side[side])
		picked.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return picked


## Fixed gates of a plain arena: count gates spread over at least min_sides walls and at least
## GATE_SPACING tiles apart on one wall. Drawn once with the dungeon RNG when the room is built.
static func place(gates: Array[Gate], count: int, min_sides: int, rng: RandomNumberGenerator) -> Array[Gate]:
	var placed: Array[Gate] = []
	var by_side := _group_by_side(gates)
	var sides: Array = by_side.keys()
	sides.sort()
	_shuffle(sides, rng)
	var wanted := mini(count, gates.size())
	var turn := 0
	var misses := 0
	while placed.size() < wanted and misses < sides.size():
		var side: int = sides[turn % sides.size()]
		turn += 1
		var options: Array = (by_side[side] as Array).filter(func(gate: Gate) -> bool: return not _crowds(gate, placed))
		if options.is_empty():
			misses += 1
			continue
		misses = 0
		placed.append(options[rng.randi_range(0, options.size() - 1)])
	return placed


## Number of different walls the gates use.
static func count_sides(gates: Array[Gate]) -> int:
	return _group_by_side(gates).size()


static func filter_by_distance(gates: Array[Gate], player_positions: Array[Vector2], min_distance: float) -> Array[Gate]:
	var result: Array[Gate] = []
	for gate in gates:
		if WaveRules.distance_to_nearest(gate.get_floor_position(), player_positions) >= min_distance:
			result.append(gate)
	return result


static func _fill_missing_sides(by_side: Dictionary, gates: Array[Gate], player_positions: Array[Vector2], min_sides: int) -> Dictionary:
	var all_sides := _group_by_side(gates)
	var missing: Array[Gate] = []
	for side: int in all_sides:
		if not by_side.has(side):
			missing.append(_farthest(all_sides[side], player_positions))
	missing.sort_custom(func(a: Gate, b: Gate) -> bool:
		return WaveRules.distance_to_nearest(a.get_floor_position(), player_positions) > WaveRules.distance_to_nearest(b.get_floor_position(), player_positions))
	var result := by_side.duplicate()
	for gate in missing:
		if result.size() >= min_sides:
			break
		result[gate.side] = [gate]
	return result


static func _farthest(gates: Array, player_positions: Array[Vector2]) -> Gate:
	var best: Gate = null
	var best_distance := -1.0
	for gate: Gate in gates:
		var distance := WaveRules.distance_to_nearest(gate.get_floor_position(), player_positions)
		if distance > best_distance:
			best_distance = distance
			best = gate
	return best


static func _group_by_side(gates: Array) -> Dictionary:
	var by_side := {}
	for gate: Gate in gates:
		if not by_side.has(gate.side):
			by_side[gate.side] = []
		(by_side[gate.side] as Array).append(gate)
	return by_side


static func _crowds(gate: Gate, placed: Array[Gate]) -> bool:
	for other in placed:
		var gap := (gate.wall_tile - other.wall_tile).abs()
		if maxi(gap.x, gap.y) < GATE_SPACING:
			return true
	return false


static func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = values[i]
		values[i] = values[j]
		values[j] = swap


static func _near_door(wall: Vector2i, door_tiles: Array[Vector2i]) -> bool:
	for door in door_tiles:
		var gap := (wall - door).abs()
		if maxi(gap.x, gap.y) <= 1:
			return true
	return false


static func _near_prop(tile: Vector2i, prop_positions: Array[Vector2]) -> bool:
	var centre := RoomTiles.tile_center(tile)
	for prop in prop_positions:
		if centre.distance_to(prop) < PROP_CLEARANCE:
			return true
	return false


static func _gate_key(gate: Gate) -> Vector3i:
	return Vector3i(gate.side, gate.wall_tile.y, gate.wall_tile.x)

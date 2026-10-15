class_name PassageCover
extends RefCounted
## The rock over a passage (M2 tunnel, Projektmitglied 15.10.2026, 35/36/40/41/42.png): the passage
## between two joined rooms runs under the rock like a tunnel. Over it the walls of both rooms are
## drawn again as if the passage were not there - the same terrain pieces the rooms paint (RockTerrain,
## light edges and fronts included), worked out from the floors of both rooms without the passage
## cells. So the crown runs closed over a north gate, the fronts beside it keep their light top line up
## to the arch, the side wall of a west/east passage runs straight through, and no corridor floor,
## rounded corridor corner or rectangle of the other look stays visible. DoorView draws the pieces
## above the characters, so a player in the passage is hidden.
## The passage: the door tile and every tile outward up to the floor of the room behind (its longer
## entrance corridor of D-117 included). The cover: every passage tile with its neighbours across
## (three wide); for a north gate not the door tile itself (the arch and the gate show there), only
## the fronts beside it.
## Tiles only, no RNG, no gameplay state.

## A passage is never longer than this many tiles (door tile, corridor, D-117 extra).
const MAX_DEPTH := 8
## A cover cell takes the look of the room whose floor is nearest, searched this far (tiles).
const OWNER_REACH := 3


## World tiles of the passage of a door: door_cell (world tile of the door) and every tile outward
## until the interior floor of next (its floor without its door corridors).
static func passage_cells(door_cell: Vector2i, outward: Vector2i, next: Node2D) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [door_cell]
	var tiles := _tiles_of(next)
	if tiles == null:
		return cells
	var origin := PassageSeam.origin_of(next)
	var corridors: Dictionary[Vector2i, bool] = {}
	for tile in tiles.get_door_corridor_tiles():
		corridors[tile + origin] = true
	var floor_mask := tiles.get_floor_mask()
	for k in range(1, MAX_DEPTH + 1):
		var cell := door_cell + outward * k
		var local := cell - origin
		if floor_mask.has(local) and not corridors.has(cell):
			break
		cells.append(cell)
	return cells


## Floors of the rooms in world tiles, without the passage cells.
static func closed_floor(rooms: Array, passage: Array[Vector2i]) -> Dictionary[Vector2i, bool]:
	var result: Dictionary[Vector2i, bool] = {}
	for room: Node2D in rooms:
		var tiles := _tiles_of(room)
		if tiles == null:
			continue
		var origin := PassageSeam.origin_of(room)
		for tile in tiles.get_floor_mask():
			result[tile + origin] = true
	for cell in passage:
		result.erase(cell)
	return result


## World tiles the cover draws (see the class comment), never a floor tile of closed.
static func cover_cells(passage: Array[Vector2i], outward: Vector2i, keep_door: bool, closed: Dictionary[Vector2i, bool]) -> Array[Vector2i]:
	var across := Vector2i(absi(outward.y), absi(outward.x))
	var cells: Array[Vector2i] = []
	for i in passage.size():
		for a in [-1, 0, 1]:
			if keep_door and i == 0 and a == 0:
				continue
			var cell: Vector2i = passage[i] + across * a
			if not closed.has(cell) and not cells.has(cell):
				cells.append(cell)
	return cells


## The room whose floor is nearest to cell (Chebyshev, up to OWNER_REACH); ties go to the earlier
## room in rooms (the door's own room first). null without any floor in reach.
static func owner_of(cell: Vector2i, rooms: Array, floors: Array) -> Node2D:
	for reach in range(1, OWNER_REACH + 1):
		for i in rooms.size():
			var floor_mask: Dictionary = floors[i]
			for dy in range(-reach, reach + 1):
				for dx in range(-reach, reach + 1):
					if floor_mask.has(cell + Vector2i(dx, dy)):
						return rooms[i]
	return rooms[0] if not rooms.is_empty() else null


## Atlas cell drawn on a covered cell for a room's tiles: Vector3i(atlas x, atlas y, source id), the
## piece the room would paint there with closed as its floor. z = -1 without a piece.
static func piece_of(cell: Vector2i, tiles: RoomTiles, closed: Dictionary[Vector2i, bool]) -> Vector3i:
	if tiles == null or closed.has(cell):
		return Vector3i(0, 0, -1)
	if tiles.is_terrain_drawn():
		if RockTerrain.is_enclosed(cell, closed):
			return tiles.get_rock_fill_cell()
		var piece := RockTerrain.piece_for(cell, closed)
		return Vector3i(piece.x, piece.y, RockTerrain.rock_source(tiles.get_look()))
	var legacy := WallAutotile.cell_for_floor(cell, closed)
	if legacy == WallAutotile.ROCK:
		return tiles.get_rock_fill_cell()
	return Vector3i(legacy.x, legacy.y, RoomTiles.SOURCE_WALL)


## Every piece of the cover: [{"cell": world tile, "room": owner room, "atlas": Vector3i}].
static func plan(rooms: Array, door_cell: Vector2i, outward: Vector2i, keep_door: bool) -> Array[Dictionary]:
	var pieces: Array[Dictionary] = []
	if rooms.size() < 2:
		return pieces
	var passage := passage_cells(door_cell, outward, rooms[1])
	var closed := closed_floor(rooms, passage)
	var floors: Array = []
	for room: Node2D in rooms:
		var own: Dictionary[Vector2i, bool] = {}
		var tiles := _tiles_of(room)
		if tiles != null:
			var origin := PassageSeam.origin_of(room)
			for tile in tiles.get_floor_mask():
				if closed.has(tile + origin):
					own[tile + origin] = true
		floors.append(own)
	for cell in cover_cells(passage, outward, keep_door, closed):
		var owner := owner_of(cell, rooms, floors)
		var atlas := piece_of(cell, _tiles_of(owner), closed)
		if atlas.z >= 0:
			pieces.append({"cell": cell, "room": owner, "atlas": atlas})
	return pieces


static func _tiles_of(room: Node) -> RoomTiles:
	if room == null or not is_instance_valid(room):
		return null
	return room.get_node_or_null("Tiles") as RoomTiles

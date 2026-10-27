class_name TrialLayout
extends RefCounted
## Floor plan of the trial rooms (D-112): entrance -> direct, always safe way to the
## exit -> a parcours that branches off, with the chest at its end, visible from the start.
## Inner walls (RoomTiles.wall_rects, painted with the biome's inner wall pieces) separate it:
##
##     x  0 1 2 3 4 5 6 7 8 9 ...          16
##   y 0  . . . . . . . . . E . . . . . . .    E exit, top band = safe
##     1  . . . . . . . . . . . . . . . . .
##     2  . . . . . W W W W W W W W W W W W    W inner wall
##     3  . . . . . W W W W W W W W W W W W
##     4  . . . . . G C F < < < < < < < < <    lane B (west), C chest, F finish, G shortcut gate
##     5  . . . . . G F F < < < < < < < < <
##     6  . . . . . W W W W W W W W W W ^ ^    turn
##     7  . . . . . W W W W W W W W W W ^ ^
##     8  . . . . . S > > > > > > > > > > >    lane A (east), S start
##     9  . . I . . S > > > > > > > > > > >    I entrance
##
## The safe column (x 0-4) and the top band (y 0-1) never hold a hazard. The shortcut gate opens
## once the chest is open, so nobody has to walk the parcours back. trial_room.tscn carries the
## same size, door columns and wall_rects (test_trial_room checks they match).

const ROOM_SIZE := Vector2i(17, 10)
const ENTRANCE_X := 2
const EXIT_X := 9
const LANE_A := Rect2i(5, 8, 12, 2)
const TURN := Rect2i(15, 6, 2, 2)
const LANE_B := Rect2i(6, 4, 11, 2)
const START := Rect2i(5, 8, 2, 2)
const FINISH := Rect2i(6, 4, 2, 2)
const CHEST_TILE := Vector2i(6, 4)
const WALL_TOP := Rect2i(5, 2, 12, 2)
const WALL_MIDDLE := Rect2i(5, 6, 10, 2)
const GATE := Rect2i(5, 4, 1, 2)
## Columns (inclusive) where hazards may stand: never on the start, the turn or the finish.
const LANE_A_HAZARD_COLUMNS := Vector2i(7, 14)
const LANE_B_HAZARD_COLUMNS := Vector2i(8, 14)
const TILE := RoomTiles.TILE_WORLD


## Inner walls of the layout; without the gate once the shortcut is open.
static func get_wall_rects(shortcut_open := false) -> Array[Rect2i]:
	var rects: Array[Rect2i] = [WALL_TOP, WALL_MIDDLE]
	if not shortcut_open:
		rects.append(GATE)
	return rects


## Tiles of the shortcut gate (opened with RoomTiles.open_wall_tiles once the chest is open).
static func get_gate_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for y in range(GATE.position.y, GATE.end.y):
		for x in range(GATE.position.x, GATE.end.x):
			tiles.append(Vector2i(x, y))
	return tiles


## Floor tiles of the parcours (lane A, turn, lane B).
static func get_parcours_tiles() -> Dictionary[Vector2i, bool]:
	var tiles: Dictionary[Vector2i, bool] = {}
	for rect: Rect2i in [LANE_A, TURN, LANE_B]:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				tiles[Vector2i(x, y)] = true
	return tiles


static func is_parcours_tile(tile: Vector2i) -> bool:
	return LANE_A.has_point(tile) or TURN.has_point(tile) or LANE_B.has_point(tile)


## Walkable tiles of room outside the parcours: the direct way from the entrance to the exit.
static func get_safe_tiles(tiles: RoomTiles) -> Dictionary[Vector2i, bool]:
	var safe := tiles.get_walkable_tiles()
	for tile in get_parcours_tiles():
		safe.erase(tile)
	return safe


## Centre line of the parcours from the start to the finish (room-local pixels).
static func get_path_points() -> PackedVector2Array:
	var lane_a_y := (LANE_A.position.y + LANE_A.size.y * 0.5) * TILE
	var lane_b_y := (LANE_B.position.y + LANE_B.size.y * 0.5) * TILE
	var turn_x := (TURN.position.x + TURN.size.x * 0.5) * TILE
	return PackedVector2Array([
		Vector2((START.position.x + 0.5) * TILE, lane_a_y),
		Vector2(turn_x, lane_a_y),
		Vector2(turn_x, lane_b_y),
		Vector2((FINISH.position.x + FINISH.size.x * 0.5) * TILE, lane_b_y),
	])


## Length of the centre line in pixels.
static func get_path_length() -> float:
	var points := get_path_points()
	var length := 0.0
	for i in range(1, points.size()):
		length += points[i - 1].distance_to(points[i])
	return length


## Point at distance along the centre line (clamped to its ends).
static func get_path_point(distance: float) -> Vector2:
	var points := get_path_points()
	var rest := maxf(distance, 0.0)
	for i in range(1, points.size()):
		var segment := points[i - 1].distance_to(points[i])
		if rest <= segment:
			return points[i - 1].lerp(points[i], rest / segment if segment > 0.0 else 0.0)
		rest -= segment
	return points[points.size() - 1]


## Room-local rectangle of a tile rect.
static func rect_to_local(rect: Rect2i) -> Rect2:
	return Rect2(Vector2(rect.position) * TILE, Vector2(rect.size) * TILE)


## Room-local rectangle of one column of a lane (all its rows).
static func column_rect(lane: Rect2i, column: int, width := 1) -> Rect2:
	return Rect2(Vector2(column, lane.position.y) * TILE, Vector2(width, lane.size.y) * TILE)

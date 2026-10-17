class_name ExitRules
extends RefCounted
## Way-finding of the room chain (A10, D-105, D-117): which wall a room is left through
## and where the next room goes. Pure tile maths, no nodes, unit-tested.
##
## - The exit lies north, west or east, never on the entrance wall. A room before anything but a
##   normal combat room (special room, trial, miniboss, boss, campfire) is left to the north: those
##   templates have their entrance in the south wall only.
## - The next room is entered through the opposite wall. One gate per transition, at most one tile of
##   corridor (M2, 11_makeover3_komplett.md §11/§12): the two rooms overlap along the corridor, so the
##   gate sits in the wall of the room being left and the next room's wall is the one-tile corridor.
##   North: the next room's south wall lies on this room's wall crown (JOIN_OVERLAP 2); west/east: the
##   next room's wall column is the corridor tile right behind this room's door (JOIN_OVERLAP 1).
##   Where the two rooms paint over each other, each keeps its own floor and walls (PassageSeam).
## - Overlap: at most three rooms live at once, so the next room only has to keep clear of the
##   rooms still alive besides its predecessor (Footprint: rock may lie on rock, never on a floor,
##   wall or corridor). If it would clash with one of them, its entrance corridor gets longer (the
##   room moves away along the exit direction) until it fits; that always works, because every
##   live room lies behind the exit wall. The exit side is chosen
##   when the room is prepared, from an estimate over every template the next slot can get, so
##   turns that would need a long corridor are avoided ("passt nichts, nach oben").
## - Randomness: one number of the dungeon RNG per normal combat room (roll_exit), none otherwise.
##
## Coordinates: room tiles are room-local (RoomTiles), world tiles are room origin + room tile. A room
## origin is its position / RoomTiles.TILE_WORLD.

const NORTH := RoomTiles.DoorSide.NORTH
const EAST := RoomTiles.DoorSide.EAST
const SOUTH := RoomTiles.DoorSide.SOUTH
const WEST := RoomTiles.DoorSide.WEST

## Weights of the exit walls of a normal combat room (TESTWERTE): mostly on to the north, a turn to
## the west or east now and then; the dungeon winds its way up.
const SIDE_WEIGHTS: Dictionary[int, float] = {NORTH: 0.5, EAST: 0.25, WEST: 0.25}
## A turn is only taken when the estimate says the next room needs at most this many extra
## corridor tiles (TESTWERT). Straight on is always possible.
const MAX_TURN_EXTRA := 0
## Corridor tiles two joined rooms share, by exit wall (M2): the next room's entrance corridor ends this
## many tiles back inside the exit corridor. North 2: its south wall is this room's crown row, the gate
## stands in the front row; west/east 1: its wall column follows this room's door column. 0 would be
## the old join with a dark corridor of three tiles between two doors.
const JOIN_OVERLAP: Dictionary[int, int] = {NORTH: 2, EAST: 1, SOUTH: 1, WEST: 1}


## Walls a room may be left through: never the entrance wall, only where the template has a door
## place, only north before a room that is no normal combat room. Sorted (north first).
static func allowed_exit_sides(entrance_side: int, next_slot_type: int, template_sides: Array[int]) -> Array[int]:
	var sides: Array[int] = []
	var north_only := not RoomSequence.is_normal_combat(next_slot_type as RoomSequence.RoomType)
	for side: int in [NORTH, EAST, WEST]:
		if side == entrance_side or not template_sides.has(side):
			continue
		if north_only and side != NORTH:
			continue
		sides.append(side)
	if sides.is_empty():
		# Templates always have a north exit; keep the room passable whatever the data says.
		sides.append(NORTH)
	return sides


## Exit wall from one random number roll in [0, 1): weighted by SIDE_WEIGHTS among the allowed walls
## whose estimated extra corridor (estimates, same order as sides; missing = 0) is at most
## MAX_TURN_EXTRA. North is never filtered out (a north exit of a room entered from the side may
## need a longer corridor; it is placed exactly later).
static func roll_exit(sides: Array[int], estimates: Array[int], roll: float) -> int:
	var options: Array[int] = []
	var weights: Array[float] = []
	for i in sides.size():
		var estimate := estimates[i] if i < estimates.size() else 0
		if sides[i] != NORTH and estimate > MAX_TURN_EXTRA:
			continue
		options.append(sides[i])
		weights.append(SIDE_WEIGHTS.get(sides[i], 0.25))
	if options.is_empty():
		return sides[0] if not sides.is_empty() else NORTH
	return options[SpecialTable.pick_weighted(weights, roll, 0)]


## Place of a door on a wall from the template's places: the one nearest to the middle of the wall
## (west/east have one, the south entrance is the template's own). -1 if the wall has none.
static func pick_place(places: Array[int], wall_length: int) -> int:
	if places.is_empty():
		return -1
	var best := places[0]
	for place in places:
		if absf(place - (wall_length - 1) * 0.5) < absf(best - (wall_length - 1) * 0.5):
			best = place
	return best


## Length of a wall in tiles (places run along x on north/south, along y on west/east).
static func wall_length(side: int, size: Vector2i) -> int:
	return size.x if side == NORTH or side == SOUTH else size.y


# --- Placement ---

## Painted rectangle of a room relative to its entrance corridor end (0, 0), with extra corridor.
static func entrance_reach(size: Vector2i, entrance_side: int, place: int, extra := 0) -> Rect2i:
	var painted := RoomTiles.get_painted_rect_of(size, entrance_side, extra)
	var end := RoomTiles.corridor_end_of(entrance_side, place, size, extra)
	return Rect2i(painted.position - end, painted.size)


## World tile of the room origin so that its entrance corridor end lands on corridor_end.
static func origin_for(corridor_end: Vector2i, size: Vector2i, entrance_side: int, place: int, extra := 0) -> Vector2i:
	return corridor_end - RoomTiles.corridor_end_of(entrance_side, place, size, extra)


## World rectangle a room paints (origin = world tile of its room tile (0, 0)).
static func world_rect(origin: Vector2i, size: Vector2i, entrance_side: int, extra := 0) -> Rect2i:
	var painted := RoomTiles.get_painted_rect_of(size, entrance_side, extra)
	return Rect2i(origin + painted.position, painted.size)


## World tile the next room's entrance corridor ends on (the join, M2): the exit's last corridor tile
## moved JOIN_OVERLAP tiles back towards the door.
static func exit_corridor_end(origin: Vector2i, size: Vector2i, exit_side: int, place: int) -> Vector2i:
	return origin + RoomTiles.corridor_end_of(exit_side, place, size) - RoomTiles.SIDE_DIRECTIONS[exit_side] * join_overlap(exit_side)


static func join_overlap(exit_side: int) -> int:
	return JOIN_OVERLAP.get(exit_side, 1)


## Rows (north) or columns (west/east) two joined rooms paint in common: the shared corridor tiles
## and the end tile.
static func shared_lines(exit_side: int) -> int:
	return join_overlap(exit_side) + 1


## A reach (entrance_reach) grown by extra tiles away from the corridor end: the room moved further
## out along the exit direction, the gap filled by its longer corridor.
static func grow_reach(reach: Rect2i, exit_side: int, extra: int) -> Rect2i:
	if extra <= 0:
		return reach
	match exit_side:
		NORTH:
			return reach.grow_individual(0, extra, 0, 0)
		EAST:
			return reach.grow_individual(0, 0, extra, 0)
		WEST:
			return reach.grow_individual(extra, 0, 0, 0)
	return reach.grow_individual(0, 0, 0, extra)


# --- Overlap ---

## What a room covers in world tiles. painted: everything it paints (floor, walls, the rock ring,
## corridors); body: floor and the wall ring right around it, the part that must never be covered;
## corridors: the corridor tiles through its rock ring. Rock over rock is fine (rooms share their
## outer ring all the time), rock over a floor, a wall or a corridor is not.
class Footprint:
	extends RefCounted
	## Painted parts: the ring rectangle and, with a longer corridor, its strip.
	var painted: Array[Rect2i] = []
	var body := Rect2i()
	var corridors: Array[Vector2i] = []

	func clashes(other: Footprint) -> bool:
		for rect in painted:
			if rect.intersects(other.body):
				return true
			for tile in other.corridors:
				if rect.has_point(tile):
					return true
		for rect in other.painted:
			if rect.intersects(body):
				return true
			for tile in corridors:
				if rect.has_point(tile):
					return true
		return false

	func get_bounds() -> Rect2i:
		var bounds := painted[0] if not painted.is_empty() else Rect2i()
		for rect in painted:
			bounds = bounds.merge(rect)
		return bounds


## Floor and wall ring of a room of this size (room tiles): north wall two rows, the others one.
static func body_rect_of(size: Vector2i) -> Rect2i:
	return Rect2i(-1, -2, size.x + 2, size.y + 3)


## Footprint of a room placed with its origin (world tile), entrance and exits (Vector2i(side, place)),
## with a secret niche behind its north wall (niche: its floor tiles, RoomTiles.niche_rect).
static func footprint_of(origin: Vector2i, size: Vector2i, entrance: Vector2i, extra: int, exits: Array[Vector2i] = [], niche := Rect2i()) -> Footprint:
	var footprint := Footprint.new()
	for rect in RoomTiles.get_painted_rects_of(size, entrance.x, extra, entrance.y):
		footprint.painted.append(Rect2i(origin + rect.position, rect.size))
	var body := body_rect_of(size)
	footprint.body = Rect2i(origin + body.position, body.size)
	for tile in RoomTiles.corridor_tiles_of(entrance.x, entrance.y, size, extra):
		footprint.corridors.append(origin + tile)
	for exit in exits:
		for tile in RoomTiles.corridor_tiles_of(exit.x, exit.y, size):
			footprint.corridors.append(origin + tile)
	if niche.size != Vector2i.ZERO:
		footprint.painted.append(Rect2i(origin + niche.position - Vector2i.ONE, niche.size + Vector2i(2, 2)))
		for y in range(niche.position.y, niche.end.y):
			for x in range(niche.position.x, niche.end.x):
				footprint.corridors.append(origin + Vector2i(x, y))
	return footprint


## Would a secret niche (room tiles, RoomTiles.niche_rect) of a room at origin clash with others?
static func niche_clashes(origin: Vector2i, niche: Rect2i, others: Array[Footprint]) -> bool:
	var footprint := Footprint.new()
	footprint.painted.append(Rect2i(origin + niche.position - Vector2i.ONE, niche.size + Vector2i(2, 2)))
	for y in range(niche.position.y, niche.end.y):
		for x in range(niche.position.x, niche.end.x):
			footprint.corridors.append(origin + Vector2i(x, y))
	return clashes_any(footprint, others)


## Footprint of a room entered through entrance whose entrance corridor ends on corridor_end, with
## extra corridor tiles (exits not known yet).
static func joined_footprint(corridor_end: Vector2i, size: Vector2i, entrance: Vector2i, extra := 0) -> Footprint:
	return footprint_of(origin_for(corridor_end, size, entrance.x, entrance.y, extra), size, entrance, extra)


## Worst case over several templates entered through the same wall, relative to the corridor end
## (0, 0) and without extra corridor: painted and body rectangles merged, the entrance corridor.
static func reach_footprint(sizes: Array[Vector2i], entrance_side: int, places: Array[int]) -> Footprint:
	var union := Footprint.new()
	for i in sizes.size():
		var single := joined_footprint(Vector2i.ZERO, sizes[i], Vector2i(entrance_side, places[i]))
		if i == 0:
			union.painted = single.painted
			union.body = single.body
			union.corridors = single.corridors
		else:
			union.painted[0] = union.painted[0].merge(single.painted[0])
			union.body = union.body.merge(single.body)
	return union


## A reach footprint (relative to the corridor end) behind corridor_end with extra corridor tiles:
## ring and body move away, a strip three tiles wide covers the new corridor tiles next to the end.
static func extend_reach(reach: Footprint, corridor_end: Vector2i, exit_side: int, extra: int) -> Footprint:
	var direction: Vector2i = RoomTiles.SIDE_DIRECTIONS[exit_side]
	var placed := Footprint.new()
	var ring := reach.painted[0]
	placed.painted.append(Rect2i(ring.position + corridor_end + direction * extra, ring.size))
	placed.body = Rect2i(reach.body.position + corridor_end + direction * extra, reach.body.size)
	for i in reach.corridors.size() + extra:
		placed.corridors.append(corridor_end + direction * i)
	if extra > 0:
		var strip := RoomTiles.tile_bounds([corridor_end, corridor_end + direction * (extra - 1)] as Array[Vector2i])
		var across := Vector2i(absi(direction.y), absi(direction.x))
		placed.painted.append(strip.grow_individual(across.x, across.y, across.x, across.y))
	return placed


## Fewest extra corridor tiles (0..max_extra) so that the next room clashes with none of the others:
## exact for one template (size, entrance), see extra_needed_reach for the worst case. -1 = none fits.
static func extra_needed(corridor_end: Vector2i, size: Vector2i, entrance: Vector2i, others: Array[Footprint], max_extra := RoomTiles.MAX_CORRIDOR_EXTRA) -> int:
	for extra in max_extra + 1:
		if not clashes_any(joined_footprint(corridor_end, size, entrance, extra), others):
			return extra
	return -1


static func extra_needed_reach(corridor_end: Vector2i, reach: Footprint, exit_side: int, others: Array[Footprint], max_extra := RoomTiles.MAX_CORRIDOR_EXTRA) -> int:
	for extra in max_extra + 1:
		if not clashes_any(extend_reach(reach, corridor_end, exit_side, extra), others):
			return extra
	return -1


static func clashes_any(footprint: Footprint, others: Array[Footprint]) -> bool:
	for other in others:
		if footprint.clashes(other):
			return true
	return false


## Union of rectangles (worst case over the templates a slot can get); empty input -> zero rect.
static func union_of(rects: Array[Rect2i]) -> Rect2i:
	if rects.is_empty():
		return Rect2i()
	var result := rects[0]
	for rect in rects:
		result = result.merge(rect)
	return result

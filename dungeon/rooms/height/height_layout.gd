class_name HeightLayout
extends RefCounted
## The two floor levels of a room (M3, Claude Design Makeover 3 §2.3/§8), pure tile data: works on
## templates outside the tree (unit tests, plan checks) as well as on live rooms. The plan marks a
## plateau with '^', a ladder 'L' and stairs '&' (RoomTiles.plateau_tiles / ladder_tiles /
## stair_tiles, tools/generate_room_templates.py checks the same rules on the plan):
##   - cliff    a plateau tile with ground floor right below it: the plateau's half-high front in
##              its upper half (HeightField.PLATFORM_HEIGHT, D-205), solid for everyone who walks
##              (PhysicsLayers.CLIFF), shots fly over it; its lower half is ground in front of it;
##   - surface  every other plateau tile: walkable floor one level up;
##   - stairs   a cliff tile cut into steps: joins the ground below and the surface above, for
##              players and enemies (navigation runs over it);
##   - ladder   a cliff tile with a ladder: joins both levels for players only (slow, HeightRules);
##   - edges    where a surface tile touches ground floor beside or above it: a thin wall for
##              everyone who walks, no navigation across it; the same on a connector's side
##              towards the ground beside it (connector_sides: up and down only, never sideways).
## Stairs and ladders are connectors: they belong to both levels. Every other tile of the room is
## ground. At most two levels per room (no plateau on a plateau, §8). A plateau stands free in the
## room: ground all round it, never at a wall (D-205, problems()).

## Level of a tile or a body (HeightRules): ground, plateau, or both (a connector).
enum Level { GROUND = 0, PLATEAU = 1, BOTH = -1 }

const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

var plateau: Dictionary[Vector2i, bool] = {}
var surface: Dictionary[Vector2i, bool] = {}
var cliffs: Dictionary[Vector2i, bool] = {}
var ladders: Dictionary[Vector2i, bool] = {}
var stairs: Dictionary[Vector2i, bool] = {}
## Ground floor of the room (floor mask without any height tile; abyss and water included).
var ground: Dictionary[Vector2i, bool] = {}
## Surface tile -> 4-bit mask of its sides that border ground (N=1 E=2 S=4 W=8): the edges.
var edge_sides: Dictionary[Vector2i, int] = {}
## Stairs or ladder -> its sides that border ground beside it (E=2 W=8, as edge_sides). The steps
## are cut into the cliff, so their sides are cliff too: nobody steps onto them from the side (bug
## report 22.10.2026 #21660828, "man kann hier an der Kante hoch": stairs at the end of a cliff row
## were open to the ground beside them).
var connector_sides: Dictionary[Vector2i, int] = {}
## Surface tile -> its sides (E=2 W=8, as edge_sides) beside a cliff, stairs or ladder tile: the lower
## part of such a tile is ground in front of its half-high front (D-205), so that side of the surface
## is an edge too (bug report 23.10.2026 #302ea822, "Man kann hier an der Seite einfach hochlaufen":
## from the foot of a cliff one walked sideways onto the surface where the plateau reaches one row
## further south).
var foot_sides: Dictionary[Vector2i, int] = {}


## plateau_tiles are the '^' tiles; ground is the floor mask of the room (height tiles left out).
static func build(plateau_tiles: Array[Vector2i], ladder_tiles: Array[Vector2i], stair_tiles: Array[Vector2i], ground_tiles: Dictionary[Vector2i, bool]) -> HeightLayout:
	var layout := HeightLayout.new()
	for tile in ladder_tiles:
		layout.ladders[tile] = true
	for tile in stair_tiles:
		layout.stairs[tile] = true
	for tile in plateau_tiles:
		layout.plateau[tile] = true
	for tile: Vector2i in ground_tiles:
		if not layout.plateau.has(tile) and not layout.is_connector(tile):
			layout.ground[tile] = true
	for tile: Vector2i in layout.plateau:
		if layout.ground.has(tile + Vector2i.DOWN):
			layout.cliffs[tile] = true
		else:
			layout.surface[tile] = true
	for tile: Vector2i in layout.surface:
		var sides := 0
		for i in DIRECTIONS.size():
			if layout.ground.has(tile + DIRECTIONS[i]):
				sides |= 1 << i
		if sides != 0:
			layout.edge_sides[tile] = sides
		var feet := 0
		for i: int in [1, 3]:
			var beside := tile + DIRECTIONS[i]
			if layout.cliffs.has(beside) or layout.is_connector(beside):
				feet |= 1 << i
		if feet != 0:
			layout.foot_sides[tile] = feet
	for tile: Vector2i in layout.ladders.keys() + layout.stairs.keys():
		var sides := 0
		for i: int in [1, 3]:
			if layout.ground.has(tile + DIRECTIONS[i]):
				sides |= 1 << i
		if sides != 0:
			layout.connector_sides[tile] = sides
	return layout


func is_empty() -> bool:
	return plateau.is_empty() and ladders.is_empty() and stairs.is_empty()


func is_connector(tile: Vector2i) -> bool:
	return ladders.has(tile) or stairs.has(tile)


## Ground tiles right below stairs and ladders (sorted): the way up stays free there (M3b, D-189;
## nothing a room mode places may stand on them, or a plateau is cut off).
func get_connector_feet() -> Array[Vector2i]:
	var feet: Array[Vector2i] = []
	for tile: Vector2i in ladders.keys() + stairs.keys():
		if ground.has(tile + Vector2i.DOWN):
			feet.append(tile + Vector2i.DOWN)
	feet.sort()
	return feet


## Ground tiles right north of a plateau's north edge (sorted): what stands there has its foot on the
## plateau's rim line and looks as if it floated over the edge (bug report 22.10.2026 #2d4a4686,
## "Truhe fliegt irgendwie": the flame's bonus chest landed behind its plateau). Room modes leave
## them free (HeightRules.keep_feet_free).
func get_behind_tiles() -> Array[Vector2i]:
	var behind: Array[Vector2i] = []
	for tile: Vector2i in edge_sides:
		if edge_sides[tile] & 1:
			behind.append(tile + Vector2i.UP)
	behind.sort()
	return behind


## Is tile a surface tile that touches no ground among its eight neighbours? Things players take or
## light stand there, out of reach from the ground beside the plateau (M3b, D-189).
func is_inner_surface(tile: Vector2i) -> bool:
	if not surface.has(tile):
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if ground.has(tile + Vector2i(dx, dy)):
				return false
	return true


## The first rock tile (neither ground nor height) among the eight neighbours of tile, tile itself
## when there is none.
func rock_beside(tile: Vector2i) -> Vector2i:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var other := tile + Vector2i(dx, dy)
			if not ground.has(other) and not plateau.has(other) and not is_connector(other):
				return other
	return tile


## Every tile that belongs to the height of the room (plateau, ladders, stairs).
func get_height_tiles() -> Dictionary[Vector2i, bool]:
	var tiles: Dictionary[Vector2i, bool] = plateau.duplicate()
	for tile: Vector2i in ladders:
		tiles[tile] = true
	for tile: Vector2i in stairs:
		tiles[tile] = true
	return tiles


## Level of a tile: surface = PLATEAU, connector = BOTH, everything else (cliffs too: only a body on
## the ground can stand that close below a cliff) = GROUND.
func level_of(tile: Vector2i) -> Level:
	if surface.has(tile):
		return Level.PLATEAU
	if is_connector(tile):
		return Level.BOTH
	return Level.GROUND


## Can a body walk from tile a to its 4-neighbour b? No step between a surface and the ground
## beside it (edge), no step onto a cliff, stairs and ladders only from below or above
## (connector_sides); ladders only for players.
func can_step(a: Vector2i, b: Vector2i, for_enemy := false) -> bool:
	if cliffs.has(b) or cliffs.has(a):
		return false
	if a.y == b.y and ((is_connector(a) and ground.has(b)) or (is_connector(b) and ground.has(a))):
		return false
	if for_enemy and (ladders.has(a) or ladders.has(b)):
		return false
	if surface.has(a) and ground.has(b):
		return false
	if ground.has(a) and surface.has(b):
		return false
	return true


## Tiles a body reaches from start over open (ground tiles it may stand on, e.g. without solid props)
## plus the walkable height tiles in plateau_open (surface and connectors it may stand on).
static func reachable(layout: HeightLayout, open: Dictionary[Vector2i, bool], start: Vector2i, for_enemy := false) -> Dictionary[Vector2i, bool]:
	var reached: Dictionary[Vector2i, bool] = {}
	if not open.has(start):
		return reached
	reached[start] = true
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var tile: Vector2i = queue.pop_back()
		for direction in DIRECTIONS:
			var next := tile + direction
			if not open.has(next) or reached.has(next):
				continue
			if layout != null and not layout.can_step(tile, next, for_enemy):
				continue
			reached[next] = true
			queue.append(next)
	return reached


## Plateaus as 4-connected groups of plateau tiles and connectors (sorted, stable).
func components() -> Array[Array]:
	var left := get_height_tiles()
	var result: Array[Array] = []
	var keys: Array[Vector2i] = []
	keys.assign(left.keys())
	keys.sort()
	for start in keys:
		if not left.has(start):
			continue
		var group: Array[Vector2i] = []
		var queue: Array[Vector2i] = [start]
		left.erase(start)
		while not queue.is_empty():
			var tile: Vector2i = queue.pop_back()
			group.append(tile)
			for direction in DIRECTIONS:
				if left.has(tile + direction):
					left.erase(tile + direction)
					queue.append(tile + direction)
		group.sort()
		result.append(group)
	return result


## Readable rule breaks of the height (empty = fine): every connector sits in the cliff row (ground
## below, surface above), every cliff has surface above it, no cliff over an abyss or water, no rock
## among the eight neighbours of a height tile (D-205: "nie an der Außenwand, mindestens 1 Kachel
## Abstand"), every plateau has a connector and all of its surface is reached from it, nothing joins
## a third level. pits / water: abyss and water tiles of the room.
func problems(pits: Dictionary[Vector2i, bool] = {}, water: Dictionary[Vector2i, bool] = {}) -> Array[String]:
	var result: Array[String] = []
	var sorted_height: Array[Vector2i] = []
	sorted_height.assign(get_height_tiles().keys())
	sorted_height.sort()
	for tile in sorted_height:
		var below := tile + Vector2i.DOWN
		if (pits.has(below) or water.has(below)) and ground.has(below):
			result.append("height tile %s right above an abyss or water" % tile)
		var rock := rock_beside(tile)
		if rock != tile:
			result.append("height tile %s touches rock at %s (keep one tile of floor to every wall, D-205)" % [tile, rock])
	var connectors: Array[Vector2i] = []
	connectors.assign(ladders.keys() + stairs.keys())
	connectors.sort()
	for tile in connectors:
		if not ground.has(tile + Vector2i.DOWN) or pits.has(tile + Vector2i.DOWN) or water.has(tile + Vector2i.DOWN):
			result.append("%s at %s has no plain ground below it" % ["ladder" if ladders.has(tile) else "stairs", tile])
		if not surface.has(tile + Vector2i.UP):
			result.append("%s at %s has no plateau surface above it" % ["ladder" if ladders.has(tile) else "stairs", tile])
	var cliff_keys: Array[Vector2i] = []
	cliff_keys.assign(cliffs.keys())
	cliff_keys.sort()
	for tile in cliff_keys:
		if not surface.has(tile + Vector2i.UP) and not cliffs.has(tile + Vector2i.UP):
			result.append("cliff at %s without a plateau surface above it (a plateau needs two rows)" % tile)
	for group in components():
		var has_surface := false
		var starts: Array[Vector2i] = []
		for tile: Vector2i in group:
			has_surface = has_surface or surface.has(tile)
			if is_connector(tile):
				starts.append(tile)
		if not has_surface:
			result.append("plateau at %s has no surface" % group[0])
			continue
		if starts.is_empty():
			result.append("plateau at %s has neither stairs nor a ladder" % group[0])
			continue
		var open: Dictionary[Vector2i, bool] = {}
		for tile: Vector2i in group:
			if not cliffs.has(tile):
				open[tile] = true
		var reached := reachable(self, open, starts[0])
		for start in starts:
			reached.merge(reachable(self, open, start))
		for tile: Vector2i in group:
			if surface.has(tile) and not reached.has(tile):
				result.append("plateau surface %s not reached from its stairs or ladder" % tile)
				break
	return result

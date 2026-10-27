class_name TutorialPlans
extends RefCounted
## Floor plans of the practice run (Übungsgang, WK10, KONZEPT §7.2): the hall in top-down view with
## its four stations and the short side-view stretch of station 3, drawn as ASCII like the room plans
## (dungeon/rooms/plans/) and the side plans (SidePlans). TutorialArea builds the hall from HALL,
## TutorialJump parses JUMP with SideLayout. Kept in code, not in a .txt: the room generator reads
## every plans/**/*.txt as a room, and exports carry scripts but no text files.
##
## Hall legend (one character per 64 px tile; row 0 lies under the north wall, column 0 at the west
## wall, the entrance from the village is the west wall at the start row):
##   .  floor                        #  wall (part of an inner wall, at least two tiles tall)
##   _  abyss (station 2, dash)      S  player start
##   K  "Kenne ich schon" shortcut   1-4 station sign (its flag stands beside it)
##   d  straw dummy (station 1)      D  dummy with a wooden shield (station 4)
##   |  door in a wall: shut until the station before it is done
##   J  door to the side-view stretch (station 3)   j  where the player comes back out of it
##   G  gate "Dungeon" in the north wall above this tile (the end)
## Rules (check(), tests/unit/test_tutorial_plans.gd): one S, K, G, J, j, D and every sign once,
## straw dummies, all rows equally long, inner walls in whole columns with at least two tiles above
## and below each door, the abyss one tile wide (a dash crosses it, RoomTiles.MAX_DASH_GAP) and across
## the whole hall, the stations from west to east in their order, and everything reachable from the
## start with the doors open and a dash over the abyss.
##
## Side legend: see SidePlans. The stretch has no pit at all (nobody loses a heart while practising):
## a block to jump on, a wall that needs the double jump, and a ditch with a floor that a jump with
## momentum (Schwung, D-195) clears - who falls short walks through the ditch and jumps out.

const HALL: Array[String] = [
	".....#.......#...._.......#.......#...G..",
	".K...#.1...d.#.2.._...3...#.4.....#......",
	".....#.......#...._.......#.......#......",
	".....|.......|...._.......Jj...D..|......",
	"..S..#...d...#...._.......#.......#......",
	".....#.....d.#...._.......#.......#......",
	".....#.......#...._.......#.......#......",
]

## Side-view stretch of station 3 (11 rows like every side plan).
const JUMP: Array[String] = [
	"##############################################",
	"#............................................#",
	"#....t..........t...o......t............t....#",
	"#............................................#",
	"#..........oo......###.......................#",
	"#..................###...........oo..........#",
	"#.........####.....###.......................#",
	"#.S.......####.....###.....................D.#",
	"################################....##########",
	"################################....##########",
	"##############################################",
]
const JUMP_ID: StringName = &"tutorial_jump"
const JUMP_BIOME: StringName = &"crypt"
## Flint speaks when the first player passes these columns of JUMP: before the block, before the
## high wall (double jump), at the start of the run-up to the ditch (momentum).
const JUMP_HINTS: Array[Array] = [
	[6, &"FLINT_TUTORIAL_JUMP_2"],
	[15, &"FLINT_TUTORIAL_JUMP_3"],
	[23, &"FLINT_TUTORIAL_JUMP_4"],
]
## The ditch of the run-up (first and last column); who clears it without touching its floor had
## momentum.
const JUMP_DITCH := Vector2i(32, 35)

const FLOOR := "."
const WALL := "#"
const PIT := "_"
const START := "S"
const SHORTCUT := "K"
const DUMMY := "d"
const SHIELD_DUMMY := "D"
const DOOR := "|"
const JUMP_DOOR := "J"
const JUMP_EXIT := "j"
const GATE := "G"
const SIGNS := ["1", "2", "3", "4"]


## Size of the hall in tiles.
static func hall_size() -> Vector2i:
	return Vector2i(HALL[0].length(), HALL.size())


## Character at a hall tile ("#" outside).
static func char_at(cell: Vector2i, rows: Array[String] = HALL) -> String:
	if cell.y < 0 or cell.y >= rows.size() or cell.x < 0 or cell.x >= rows[cell.y].length():
		return WALL
	return rows[cell.y][cell.x]


## Every tile with this character, row by row.
static func find(character: String, rows: Array[String] = HALL) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] == character:
				cells.append(Vector2i(x, y))
	return cells


## The one tile with this character, (-1, -1) if there is none.
static func find_one(character: String, rows: Array[String] = HALL) -> Vector2i:
	var cells := find(character, rows)
	return cells[0] if not cells.is_empty() else Vector2i(-1, -1)


## Tile of station sign n (0..3).
static func sign_cell(station: int, rows: Array[String] = HALL) -> Vector2i:
	return find_one(SIGNS[station], rows)


## Inner walls as rectangles of whole columns (one per run of wall tiles in a column).
static func wall_rects(rows: Array[String] = HALL) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	var width := rows[0].length()
	for x in width:
		var y := 0
		while y < rows.size():
			if rows[y][x] != WALL:
				y += 1
				continue
			var top := y
			while y < rows.size() and rows[y][x] == WALL:
				y += 1
			rects.append(Rect2i(x, top, 1, y - top))
	return rects


## The abyss as rectangles (one per column).
static func pit_rects(rows: Array[String] = HALL) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	for cell in find(PIT, rows):
		var merged := false
		for i in rects.size():
			if rects[i].position.x == cell.x and rects[i].end.y == cell.y:
				rects[i].size.y += 1
				merged = true
		if not merged:
			rects.append(Rect2i(cell, Vector2i.ONE))
	return rects


## Doors in walls (stations 1 -> 2 and 4 -> end, and the first one after the welcome), west to east.
static func door_cells(rows: Array[String] = HALL) -> Array[Vector2i]:
	var cells := find(DOOR, rows)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	return cells


## Walkable tiles: everything but walls and the abyss (doors, the jump door and every marker count).
static func walkable(rows: Array[String] = HALL) -> Dictionary[Vector2i, bool]:
	var cells: Dictionary[Vector2i, bool] = {}
	for y in rows.size():
		for x in rows[y].length():
			var character := rows[y][x]
			if character != WALL and character != PIT:
				cells[Vector2i(x, y)] = true
	return cells


## Tiles reachable from the start on foot with a dash over one-tile gaps (RoomTiles.flood_fill).
static func reachable(rows: Array[String] = HALL) -> Dictionary[Vector2i, bool]:
	var pits: Dictionary[Vector2i, bool] = {}
	for cell in find(PIT, rows):
		pits[cell] = true
	return RoomTiles.flood_fill(walkable(rows), pits, find_one(START, rows), RoomTiles.MAX_DASH_GAP)


## Plan rule problems (empty = fine).
static func check(rows: Array[String] = HALL) -> PackedStringArray:
	var problems := PackedStringArray()
	var width := rows[0].length()
	for y in rows.size():
		if rows[y].length() != width:
			problems.append("hall row %d is %d long, not %d" % [y, rows[y].length(), width])
	if not problems.is_empty():
		return problems
	for character in [START, SHORTCUT, GATE, JUMP_DOOR, JUMP_EXIT, SHIELD_DUMMY] + SIGNS:
		var count := find(character, rows).size()
		if count != 1:
			problems.append("'%s' appears %d times, once expected" % [character, count])
	if find(DUMMY, rows).is_empty():
		problems.append("station 1 has no straw dummy 'd'")
	if not problems.is_empty():
		return problems
	problems.append_array(_check_doors(rows))
	problems.append_array(_check_pit(rows))
	problems.append_array(_check_order(rows))
	var reach := reachable(rows)
	for character in [SHORTCUT, GATE, JUMP_DOOR, JUMP_EXIT, DUMMY, SHIELD_DUMMY] + SIGNS:
		for cell in find(character, rows):
			if not reach.has(cell):
				problems.append("'%s' at %s cannot be reached from the start" % [character, cell])
	if char_at(find_one(GATE, rows) + Vector2i.DOWN, rows) == WALL:
		problems.append("the tile in front of the gate must be floor")
	if find_one(GATE, rows).y != 0:
		problems.append("the gate must stand in row 0 (under the north wall)")
	return problems


## Every door and the jump door sit in a wall column with wall tiles above and below (at least two
## each, WallAutotile: walls are two tiles tall).
static func _check_doors(rows: Array[String]) -> PackedStringArray:
	var problems := PackedStringArray()
	var doors := find(DOOR, rows)
	doors.append(find_one(JUMP_DOOR, rows))
	for cell in doors:
		var above := 0
		while char_at(cell + Vector2i(0, -above - 1), rows) == WALL and cell.y - above - 1 >= 0:
			above += 1
		var below := 0
		while cell.y + below + 1 < rows.size() and char_at(cell + Vector2i(0, below + 1), rows) == WALL:
			below += 1
		if above < 2 or below < 2 or cell.y - above != 0 or cell.y + below != rows.size() - 1:
			problems.append("door at %s must close a whole wall column (2+ wall tiles above and below)" % cell)
	return problems


## One abyss column across the whole hall: no way round, and one dash crosses it.
static func _check_pit(rows: Array[String]) -> PackedStringArray:
	var rects := pit_rects(rows)
	if rects.size() != 1:
		return PackedStringArray(["the abyss must be one column (found %d pieces)" % rects.size()])
	var rect := rects[0]
	if rect.size.x > RoomTiles.MAX_DASH_GAP or rect.size.y != rows.size():
		return PackedStringArray(["the abyss must be %d tile wide and cross the whole hall" % RoomTiles.MAX_DASH_GAP])
	return PackedStringArray()


## West to east: start, sign 1 and the straw dummies, sign 2, the abyss, sign 3, the jump door and
## its exit, sign 4 and the shield dummy, the gate.
static func _check_order(rows: Array[String]) -> PackedStringArray:
	var problems := PackedStringArray()
	var pit_x := pit_rects(rows)[0].position.x
	var jump_x := find_one(JUMP_DOOR, rows).x
	var order := [
		find_one(START, rows).x, sign_cell(0, rows).x, sign_cell(1, rows).x, pit_x, sign_cell(2, rows).x,
		jump_x, find_one(JUMP_EXIT, rows).x, sign_cell(3, rows).x, find_one(SHIELD_DUMMY, rows).x,
		find_one(GATE, rows).x,
	]
	for i in range(1, order.size()):
		if int(order[i]) <= int(order[i - 1]):
			problems.append("the stations must run from west to east (column %d after %d)" % [order[i], order[i - 1]])
	if find_one(JUMP_EXIT, rows).x != jump_x + 1:
		problems.append("the jump exit 'j' must lie right behind the jump door 'J'")
	for dummy in find(DUMMY, rows):
		if dummy.x <= sign_cell(0, rows).x or dummy.x >= sign_cell(1, rows).x:
			problems.append("straw dummy %s must stand in station 1" % dummy)
	return problems


## The side-view stretch of station 3 as a layout (crypt look).
static func jump_layout() -> SideLayout:
	var layout := SideLayout.parse(PackedStringArray(JUMP), JUMP_ID)
	layout.biome_id = JUMP_BIOME
	layout.chest_enabled = false
	layout.turrets_enabled = false
	return layout


## Side plan problems: start and door, the way needs the double jump (that is what is practised),
## and no pit anywhere (every column has rock in the bottom row).
static func check_jump() -> PackedStringArray:
	var problems := PackedStringArray()
	var layout := jump_layout()
	if layout.start.x < 0 or layout.door.x < 0:
		return PackedStringArray(["the jump plan needs a start 'S' and a door 'D'"])
	for row in JUMP:
		if row.length() != layout.size.x:
			problems.append("jump rows must be equally long")
			return problems
	if layout.find_path(layout.start, layout.door, true).is_empty():
		problems.append("the door cannot be reached from the start")
	if not layout.find_path(layout.start, layout.door, false).is_empty():
		problems.append("the way must need the double jump (station 3 practises it)")
	if layout.count_pits() > 0:
		problems.append("no pit in the practice stretch (a fall would cost a heart)")
	if not layout.slimes.is_empty() or not layout.skeletons.is_empty() or not layout.spikes.is_empty() or not layout.turrets.is_empty():
		problems.append("no enemies, spikes or turrets in the practice stretch")
	return problems

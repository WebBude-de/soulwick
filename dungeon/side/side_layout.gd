class_name SideLayout
extends RefCounted
## One parsed side-segment plan (M5): the cells of an ASCII plan (SidePlans) plus the questions the
## segment, the player motion and the tools ask about it - where is rock, a ledge, a ladder, where
## can a player stand, which stand spots a 2.5-tile jump (or a double jump) connects. check() holds
## the plan rules.
## Cell (column, row); row 0 is the ceiling. A stand cell is an air cell with something to stand on
## below it; the feet of a player standing there are at feet_of(cell).

const ROCK := "#"
const LEDGE := "="
## A ledge that crumbles shortly after a player stands on it and comes back later (round 2).
const CRUMBLE := "~"
const LADDER := "H"
const START := "S"
const DOOR := "D"
const COIN := "o"
const GOLDEN_COIN := "$"
const SLIME := "s"
const SKELETON := "k"
const SPIKES := "^"
const CHEST := "C"
const TORCH := "t"
const AIR := "."

## Planning reach of a jump in whole tiles (SideRules: 2.5 tiles high, about 2.7 tiles far on the
## same level): [rows up] -> furthest column distance between two stand cells.
const REACH_UP_MAX := 2
const REACH_BY_RISE := {2: 2, 1: 3, 0: 3}
## Dropping down: 3 columns too (the fall adds little distance at this gravity).
const REACH_DROP := 3
const REACH_DROP_EXTRA_MAX := 0
## The same with the double jump (2 more tiles high, about 4 tiles far): 4 rows up at most.
const DOUBLE_REACH_UP_MAX := 4
const DOUBLE_REACH_BY_RISE := {4: 2, 3: 3, 2: 4, 1: 4, 0: 4}
const DOUBLE_REACH_DROP := 4
## Items count as reachable within this many columns and rows above a reachable stand cell
## (with the double jump: up to 4 rows).
const ITEM_REACH_COLUMNS := 2
const ITEM_REACH_ROWS := 2
const ITEM_REACH_ROWS_DOUBLE := 4

const WIDTH_RANGE := Vector2i(40, 60)
const PLATFORM_RANGE := Vector2i(8, 14)
const PIT_RANGE := Vector2i(1, 2)
## Coins per plan (TESTWERT round 2: 6-7 coins + the golden coin pay about a combat room).
const COIN_RANGE := Vector2i(6, 8)
const ENEMY_RANGE := Vector2i(1, 3)

var plan_id: StringName = &""
var biome_id: StringName = &""
var is_mirrored := false
var size := Vector2i.ZERO
var rows := PackedStringArray()
var start := Vector2i(-1, -1)
var door := Vector2i(-1, -1)
var chest := Vector2i(-1, -1)
var golden_coin := Vector2i(-1, -1)
var coins: Array[Vector2i] = []
var slimes: Array[Vector2i] = []
var skeletons: Array[Vector2i] = []
var spikes: Array[Vector2i] = []
var torches: Array[Vector2i] = []
## Ladder column -> Vector2i(top row, bottom row).
var ladders: Dictionary[int, Vector2i] = {}
## Crumbling ledges: Vector3i(first column, last column, row) per run.
var crumbles: Array[Vector3i] = []
## The niche chest is set up (SideWays: only on the ladder way of a branch; tests and tools: yes).
var chest_enabled := true

## Jump graphs without (false) and with (true) the double jump.
var _edges: Dictionary[bool, Dictionary] = {}


static func parse(plan_rows: PackedStringArray, id: StringName = &"") -> SideLayout:
	var layout := SideLayout.new()
	layout.plan_id = id
	layout.rows = plan_rows
	layout.size = Vector2i(plan_rows[0].length() if not plan_rows.is_empty() else 0, plan_rows.size())
	for row in plan_rows.size():
		var line := plan_rows[row]
		for column in line.length():
			var cell := Vector2i(column, row)
			match line[column]:
				START:
					layout.start = cell
				DOOR:
					layout.door = cell
				CHEST:
					layout.chest = cell
				GOLDEN_COIN:
					layout.golden_coin = cell
				COIN:
					layout.coins.append(cell)
				SLIME:
					layout.slimes.append(cell)
				SKELETON:
					layout.skeletons.append(cell)
				SPIKES:
					layout.spikes.append(cell)
				TORCH:
					layout.torches.append(cell)
				LADDER:
					var span: Vector2i = layout.ladders.get(column, Vector2i(row, row))
					layout.ladders[column] = Vector2i(mini(span.x, row), maxi(span.y, row))
				CRUMBLE:
					if column == 0 or line[column - 1] != CRUMBLE:
						var last := column
						while last + 1 < line.length() and line[last + 1] == CRUMBLE:
							last += 1
						layout.crumbles.append(Vector3i(column, last, row))
	return layout


## The same plan, left and right swapped (start on the right, door on the left).
func mirrored() -> SideLayout:
	var flipped := PackedStringArray()
	for line in rows:
		var reversed := ""
		for i in range(line.length() - 1, -1, -1):
			reversed += line[i]
		flipped.append(reversed)
	var layout := SideLayout.parse(flipped, plan_id)
	layout.biome_id = biome_id
	layout.is_mirrored = not is_mirrored
	return layout


# --- Cells ---

## Character of a cell; outside: rock at the sides and the top, air below (pits fall out).
func char_at(cell: Vector2i) -> String:
	if cell.y >= size.y:
		return AIR
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x:
		return ROCK
	return rows[cell.y][cell.x]


func is_rock(cell: Vector2i) -> bool:
	return char_at(cell) == ROCK


func is_ledge(cell: Vector2i) -> bool:
	return char_at(cell) == LEDGE


func is_crumble(cell: Vector2i) -> bool:
	return char_at(cell) == CRUMBLE


## Rock or ledge (also a crumbling one): something a player stands on.
func is_blocking(cell: Vector2i) -> bool:
	var c := char_at(cell)
	return c == ROCK or c == LEDGE or c == CRUMBLE


func is_ladder(cell: Vector2i) -> bool:
	return char_at(cell) == LADDER


## The top cell of a ladder: its upper edge is a one-way step.
func is_ladder_top(cell: Vector2i) -> bool:
	return is_ladder(cell) and not is_ladder(cell + Vector2i.UP)


func is_standable(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= size.x or cell.y < 0 or cell.y >= size.y or is_blocking(cell):
		return false
	var below := cell + Vector2i.DOWN
	return is_blocking(below) or is_ladder_top(below)


func stand_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for row in size.y:
		for column in size.x:
			if is_standable(Vector2i(column, row)):
				cells.append(Vector2i(column, row))
	return cells


## Columns whose bottom row is open: falling there leaves the segment.
func pit_columns() -> Array[int]:
	var columns: Array[int] = []
	for column in range(1, size.x - 1):
		if not is_blocking(Vector2i(column, size.y - 1)):
			columns.append(column)
	return columns


## Contiguous pit runs.
func count_pits() -> int:
	var count := 0
	var previous := -10
	for column in pit_columns():
		if column != previous + 1:
			count += 1
		previous = column
	return count


## Horizontal runs of standable surface (ground and ledges).
func count_platforms() -> int:
	var count := 0
	for row in range(1, size.y):
		var running := false
		for column in range(1, size.x - 1):
			var cell := Vector2i(column, row)
			var surface := is_blocking(cell) and not is_blocking(cell + Vector2i.UP)
			if surface and not running:
				count += 1
			running = surface
	return count


# --- World coordinates (local to the segment node) ---

static func cell_origin(cell: Vector2i) -> Vector2:
	return Vector2(cell) * SideRules.TILE


static func cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * SideRules.TILE


## Feet of a player standing in a stand cell: middle of the cell's bottom edge.
static func feet_of(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * SideRules.TILE, (cell.y + 1) * SideRules.TILE)


static func cell_at(local: Vector2) -> Vector2i:
	return Vector2i(floori(local.x / SideRules.TILE), floori(local.y / SideRules.TILE))


func world_size() -> Vector2:
	return Vector2(size) * SideRules.TILE


## Feet below this line have fallen out of the segment.
func kill_y() -> float:
	return (size.y + 0.75) * SideRules.TILE


## Climbable area of a ladder column: from the top cell's upper edge to the bottom cell's lower edge.
func ladder_rect(column: int) -> Rect2:
	var span: Vector2i = ladders.get(column, Vector2i(-1, -1))
	if span.x < 0:
		return Rect2()
	return Rect2(column * SideRules.TILE, span.x * SideRules.TILE, SideRules.TILE, (span.y - span.x + 1) * SideRules.TILE)


## Ladder area holding a local point (feet), empty Rect2 if none.
func ladder_rect_at(local: Vector2) -> Rect2:
	var column := floori(local.x / SideRules.TILE)
	if not ladders.has(column):
		return Rect2()
	var rect := ladder_rect(column)
	# The feet of a player standing on the ground below or on the top step still count.
	return rect if local.y >= rect.position.y - 2.0 and local.y <= rect.end.y + 2.0 else Rect2()


## Direction of travel: +1 to the right (door right of the start), -1 to the left.
func run_direction() -> float:
	return 1.0 if door.x >= start.x else -1.0


# --- Jump graph ---

## Stand cells a jump, a step, a drop or a ladder reaches from cell (planning rules, REACH_*);
## double = with the double jump.
func neighbours(cell: Vector2i, double := true) -> Array[Vector2i]:
	if not _edges.has(double):
		_edges[double] = _build_edges(double)
	var result: Array[Vector2i] = []
	result.assign((_edges[double] as Dictionary).get(cell, []))
	return result


## true if going from a to b needs the double jump (no plain jump, step or ladder gets there).
func needs_double_jump(a: Vector2i, b: Vector2i) -> bool:
	return not neighbours(a, false).has(b) and neighbours(a, true).has(b)


## Shortest chain of stand cells from one stand cell to another (both included), empty if none.
func find_path(from: Vector2i, to: Vector2i, double := true) -> Array[Vector2i]:
	var previous: Dictionary[Vector2i, Vector2i] = {from: from}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		if cell == to:
			break
		for next in neighbours(cell, double):
			if not previous.has(next):
				previous[next] = cell
				queue.append(next)
	if not previous.has(to):
		return []
	var path: Array[Vector2i] = [to]
	while path[0] != from:
		path.push_front(previous[path[0]])
	return path


func reachable_from(cell: Vector2i, double := true) -> Dictionary[Vector2i, bool]:
	var seen: Dictionary[Vector2i, bool] = {cell: true}
	var queue: Array[Vector2i] = [cell]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for next in neighbours(current, double):
			if not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen


## The stand cell to jump from for an item high above (closest below it, free column), or (-1, -1).
## The autopilot takes the golden coin from there.
func launch_cell_for(item: Vector2i, reach: Dictionary[Vector2i, bool]) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_score := 1000000
	for cell in reach:
		var above := cell.y - item.y
		if above < 0 or above > ITEM_REACH_ROWS_DOUBLE or absi(cell.x - item.x) > ITEM_REACH_COLUMNS:
			continue
		var clear := true
		for step in range(1, above + 1):
			if is_blocking(Vector2i(cell.x, cell.y - step)):
				clear = false
		if not clear:
			continue
		var score := absi(cell.x - item.x) * 10 + above
		if score < best_score:
			best_score = score
			best = cell
	return best


func _build_edges(double: bool) -> Dictionary:
	var edges := {}
	var cells := stand_cells()
	for a in cells:
		var targets: Array[Vector2i] = []
		for b in cells:
			if a != b and _jump_connects(a, b, double):
				targets.append(b)
		edges[a] = targets
	for column in ladders:
		var span: Vector2i = ladders[column]
		var bottom := Vector2i(column, span.y)
		var top := Vector2i(column, span.x - 1)
		if edges.has(bottom) and edges.has(top):
			if not (edges[bottom] as Array).has(top):
				(edges[bottom] as Array).append(top)
			if not (edges[top] as Array).has(bottom):
				(edges[top] as Array).append(bottom)
	return edges


func _jump_connects(a: Vector2i, b: Vector2i, double := false) -> bool:
	var columns := absi(b.x - a.x)
	var rise := a.y - b.y
	if rise > (DOUBLE_REACH_UP_MAX if double else REACH_UP_MAX):
		return false
	var reach: int
	if double:
		reach = DOUBLE_REACH_BY_RISE[rise] if rise >= 0 else DOUBLE_REACH_DROP
	else:
		reach = REACH_BY_RISE[rise] if rise >= 0 else REACH_DROP + mini(REACH_DROP_EXTRA_MAX, -rise)
	if columns > reach:
		return false
	# Straight up under solid rock is impossible (ledges can be jumped through from below).
	if rise > 0 and columns == 0:
		for step in range(1, rise + 1):
			if is_rock(a + Vector2i(0, -step)):
				return false
	return true


# --- Plan rules ---

## Errors of this plan against the M5 rules (empty = fine).
func check() -> PackedStringArray:
	var errors := PackedStringArray()
	if size.y != SideRules.ROWS:
		errors.append("%s: %d rows instead of %d" % [plan_id, size.y, SideRules.ROWS])
	if size.x < WIDTH_RANGE.x or size.x > WIDTH_RANGE.y:
		errors.append("%s: width %d" % [plan_id, size.x])
	for line in rows:
		if line.length() != size.x:
			errors.append("%s: ragged row" % plan_id)
			break
	if start.x < 0 or door.x < 0:
		errors.append("%s: start or door missing" % plan_id)
		return errors
	if not is_standable(start) or not is_standable(door):
		errors.append("%s: start or door floats" % plan_id)
	var platforms := count_platforms()
	if platforms < PLATFORM_RANGE.x or platforms > PLATFORM_RANGE.y:
		errors.append("%s: %d platforms" % [plan_id, platforms])
	var pits := count_pits()
	if pits < PIT_RANGE.x or pits > PIT_RANGE.y:
		errors.append("%s: %d pits" % [plan_id, pits])
	var reach := reachable_from(start, true)
	var levels := {}
	for cell in reach:
		levels[cell.y] = true
	if ladders.is_empty() and levels.size() < 2:
		errors.append("%s: neither a ladder nor a change of level" % plan_id)
	if coins.size() < COIN_RANGE.x or coins.size() > COIN_RANGE.y:
		errors.append("%s: %d coins" % [plan_id, coins.size()])
	if golden_coin.x < 0:
		errors.append("%s: no golden coin" % plan_id)
	var enemies := slimes.size() + skeletons.size()
	if enemies < ENEMY_RANGE.x or enemies > ENEMY_RANGE.y:
		errors.append("%s: %d enemies" % [plan_id, enemies])
	if spikes.size() != 1:
		errors.append("%s: %d spike traps" % [plan_id, spikes.size()])
	if not reach.has(door):
		errors.append("%s: door not reachable" % plan_id)
	for column in ladders:
		var span: Vector2i = ladders[column]
		if not is_standable(Vector2i(column, span.y)) or not is_standable(Vector2i(column, span.x - 1)):
			errors.append("%s: ladder %d has a loose end" % [plan_id, column])
	# No dead end: from every reachable spot the door stays reachable.
	for cell in reach:
		if not find_path(cell, door).size() > 0:
			errors.append("%s: dead end at %s" % [plan_id, cell])
			break
	var items: Array[Vector2i] = []
	items.append_array(coins)
	items.append_array(slimes)
	items.append_array(skeletons)
	items.append_array(spikes)
	if chest.x >= 0:
		items.append(chest)
	for item in items:
		if not _item_in_reach(item, reach, ITEM_REACH_ROWS):
			errors.append("%s: %s at %s out of reach" % [plan_id, char_at(item), item])
	# The golden coin needs the double jump: out of a plain jump's reach, in a double jump's.
	if golden_coin.x >= 0:
		if not _item_in_reach(golden_coin, reach, ITEM_REACH_ROWS_DOUBLE):
			errors.append("%s: golden coin out of reach" % plan_id)
		elif _item_in_reach(golden_coin, reach, ITEM_REACH_ROWS):
			errors.append("%s: golden coin needs no double jump" % plan_id)
	for run in crumbles:
		for column in range(run.x, run.y + 1):
			var above := char_at(Vector2i(column, run.z - 1))
			if above in [SLIME, SKELETON, SPIKES, CHEST, DOOR, START]:
				errors.append("%s: something stands on the crumbling ledge at %d" % [plan_id, column])
	return errors


## true if the door can only be reached with the double jump (the plan asks for it on the way).
func way_needs_double_jump() -> bool:
	return not reachable_from(start, false).has(door)


func _item_in_reach(item: Vector2i, reach: Dictionary[Vector2i, bool], rows_above: int) -> bool:
	for cell in reach:
		var above := cell.y - item.y
		if absi(cell.x - item.x) <= ITEM_REACH_COLUMNS and above >= 0 and above <= rows_above:
			return true
	return false

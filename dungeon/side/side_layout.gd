class_name SideLayout
extends RefCounted
## One parsed side-segment plan (M5): the cells of an ASCII plan (SidePlans) plus the questions the
## segment, the player motion and the tools ask about it - where is rock, a ledge, a ladder, where
## can a player stand, which stand spots a 2.5-tile jump (or a double jump) connects. check() holds
## the plan rules. Round 3: turret mounts ("T", on a floor, a ceiling or a wall), water / slime
## pools ("w", slow running, shorter jumps out of them), spike runs ("^^", fired as a wave).
## Cell (column, row); row 0 is the ceiling. A stand cell is an air cell with something to stand on
## below it; the feet of a player standing there are at feet_of(cell).
## Jump trial (Sprungprobe, SV2, D-195): plans 11-22 rows high with a tier (1-3) and the elements
## of dungeon/side/elements/ - moving platforms ("M" + track "-", "V" + track "|"), springs ("j"),
## tilting platforms ("//"), collapsing bridges ("_"), saws on rails ("X" + "+"), wall-jump shafts
## ("*") and lanterns ("L"); the side enemies of SV4 ("b", "i", "u", SideEnemyKinds.PLAN_CHARS).
## The jump graph knows them: a platform's stand cells along its whole track (ridden from one to
## the other), spring launches, the climb out of a shaft.
## Slopes and ramps (SV3, kept by D-216 in the two-way pieces, SideTwoWayPlans): "(" 45° up to the
## right, ")" 45° down, "[[" and "]]" 22.5° over two cells; solid below the line, a stand cell on
## rock like any floor cell, walked without a jump (SideSlopes).
## Obstacle run (Hindernislauf, D-216): a layout composed of pieces (ObstacleRunPlans, pieces not
## empty); its plan rules are ObstacleRunPlans.check.

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
## A turret mount (round 3): the turret stands on the floor below, hangs from the rock above or sits
## on a rock wall beside the cell; set up only when turrets_enabled (SideRules.TURRET_CHANCE).
const TURRET := "T"
## Water or slime of a pool (round 3): air to walk and jump in, running slowed; rock below.
const POOL := "w"
const AIR := "."
## Jump trial elements (SV2): a moving platform (horizontal on a track "-", vertical on a track "|"),
## a spring, a tilting platform, a collapsing bridge piece, a saw on its rail, the air of a
## wall-jump shaft, a lantern (safe return spot). No dash gap: there is no side dash (D-216).
const MOVER_H := "M"
const TRACK_H := "-"
const MOVER_V := "V"
const TRACK_V := "|"
const SPRING := "j"
const TILT := "/"
const BRIDGE := "_"
const SAW := "X"
const RAIL := "+"
const SHAFT := "*"
const LANTERN := "L"
## Slopes 45° up and down to the right, 22.5° slopes over two cells (the first cell of a "[[" is the
## low half, the first of a "]]" the high half).
const SLOPE_UP := "("
const SLOPE_DOWN := ")"
const LONG_UP := "["
const LONG_DOWN := "]"
## Characters swapped when a plan is mirrored (a slope up to the right becomes one down).
const MIRROR_SWAP := {"(": ")", ")": "(", "[": "]", "]": "["}

## Shape of a slope cell: which half of a 22.5° slope, or a 45° one.
enum Slope { NONE, UP, DOWN, LONG_UP_LOW, LONG_UP_HIGH, LONG_DOWN_HIGH, LONG_DOWN_LOW }
## Height of a slope's surface over the cell's bottom at its left and right edge (share of a tile).
const SLOPE_HEIGHTS := {
	Slope.UP: Vector2(0.0, 1.0),
	Slope.DOWN: Vector2(1.0, 0.0),
	Slope.LONG_UP_LOW: Vector2(0.0, 0.5),
	Slope.LONG_UP_HIGH: Vector2(0.5, 1.0),
	Slope.LONG_DOWN_HIGH: Vector2(1.0, 0.5),
	Slope.LONG_DOWN_LOW: Vector2(0.5, 0.0),
}
## The jump graph connects stand cells at most this many columns apart (the widest reach of a
## jump, a drop or a spring; rides, shafts and ladders are added on their own).
const GRAPH_MAX_COLUMNS := 4

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
## Spike traps per plan (round 3: runs of 2-3 fire as a wave) and turret mounts per plan.
const SPIKE_RANGE := Vector2i(1, 3)
const TURRET_RANGE := Vector2i(1, 2)
## Line of sight: sample step along a line (px).
const SIGHT_STEP := 16.0


## A moving platform of the plan: cells first..last of row in the plan, moving along axis
## (Vector2i.RIGHT or Vector2i.DOWN) between low and high tiles from there (low <= 0 <= high).
class Mover:
	extends RefCounted
	var first := 0
	var last := 0
	var row := 0
	var axis := Vector2i.RIGHT
	var low := 0
	var high := 0

	func width() -> int:
		return last - first + 1

	func is_vertical() -> bool:
		return axis == Vector2i.DOWN

	## The plan cells of the platform at offset tiles along its track.
	func cells_at(offset: int) -> Array[Vector2i]:
		var cells: Array[Vector2i] = []
		for column in range(first, last + 1):
			cells.append(Vector2i(column, row) + axis * offset)
		return cells

	## Stand cells on the platform at every offset of its track (the jump graph's virtual cells).
	func all_stand_cells() -> Array[Vector2i]:
		var cells: Array[Vector2i] = []
		for offset in range(low, high + 1):
			for cell in cells_at(offset):
				if not cells.has(cell + Vector2i.UP):
					cells.append(cell + Vector2i.UP)
		return cells


## A saw of the plan: starts on cell and runs along axis between low and high tiles from it.
class Saw:
	extends RefCounted
	var cell := Vector2i.ZERO
	var axis := Vector2i.RIGHT
	var low := 0
	var high := 0

	## Every cell the saw's middle passes.
	func path_cells() -> Array[Vector2i]:
		var cells: Array[Vector2i] = []
		for offset in range(low, high + 1):
			cells.append(cell + axis * offset)
		return cells

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
var turrets: Array[Vector2i] = []
## Pools: Vector3i(first column, last column, row) per run of "w".
var pools: Array[Vector3i] = []
## Ladder column -> Vector2i(top row, bottom row).
var ladders: Dictionary[int, Vector2i] = {}
## Crumbling ledges: Vector3i(first column, last column, row) per run.
var crumbles: Array[Vector3i] = []
## The niche chest is set up (SideWays: only on the ladder way of a branch; tests and tools: yes).
var chest_enabled := true
## The turret mounts are set up (SidePlans.pick: SideRules.TURRET_CHANCE; tests and tools: yes).
var turrets_enabled := true
## Jump trial tier (SidePlans.PLAN_TIERS, 1-3; D-195).
var tier := 1
## Side enemies of SV4 other than slimes and skeletons: Vector3i(column, row, SideEnemy.Kind) in plan
## order (built after the slimes and skeletons, so old seeds keep their enemies).
var other_enemies: Array[Vector3i] = []
var movers: Array[Mover] = []
var springs: Array[Vector2i] = []
## Tilting platforms and collapsing bridges: Vector3i(first column, last column, row) per run.
var tilts: Array[Vector3i] = []
var bridges: Array[Vector3i] = []
var saws: Array[Saw] = []
## Wall-jump shafts: the rectangle of their "*" cells.
var shafts: Array[Rect2i] = []
var lanterns: Array[Vector2i] = []
## Slope cells -> Slope (two-way pieces).
var slopes: Dictionary[Vector2i, int] = {}
## Obstacle run (D-216): the piece ids it was composed of, in way order (empty for a piece).
var pieces: Array[StringName] = []

## Jump graphs without (false) and with (true) the double jump.
var _edges: Dictionary[bool, Dictionary] = {}
## Caches of mover_stand_cells and saw_danger_cells (the plan never changes after parse).
var _riding: Dictionary[Vector2i, int] = {}
var _riding_built := false
var _saw_danger: Dictionary[Vector2i, bool] = {}
var _saw_danger_built := false


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
				TURRET:
					layout.turrets.append(cell)
				POOL:
					if column == 0 or line[column - 1] != POOL:
						var pool_end := column
						while pool_end + 1 < line.length() and line[pool_end + 1] == POOL:
							pool_end += 1
						layout.pools.append(Vector3i(column, pool_end, row))
				LADDER:
					var span: Vector2i = layout.ladders.get(column, Vector2i(row, row))
					layout.ladders[column] = Vector2i(mini(span.x, row), maxi(span.y, row))
				CRUMBLE:
					if column == 0 or line[column - 1] != CRUMBLE:
						layout.crumbles.append(Vector3i(column, _run_end(line, column), row))
				TILT:
					if column == 0 or line[column - 1] != TILT:
						layout.tilts.append(Vector3i(column, _run_end(line, column), row))
				BRIDGE:
					if column == 0 or line[column - 1] != BRIDGE:
						layout.bridges.append(Vector3i(column, _run_end(line, column), row))
				SPRING:
					layout.springs.append(cell)
				SLOPE_UP:
					layout.slopes[cell] = Slope.UP
				SLOPE_DOWN:
					layout.slopes[cell] = Slope.DOWN
				LONG_UP, LONG_DOWN:
					var first := column
					while first > 0 and line[first - 1] == line[column]:
						first -= 1
					var low_first := line[column] == LONG_UP
					var first_half := (column - first) % 2 == 0
					if low_first:
						layout.slopes[cell] = Slope.LONG_UP_LOW if first_half else Slope.LONG_UP_HIGH
					else:
						layout.slopes[cell] = Slope.LONG_DOWN_HIGH if first_half else Slope.LONG_DOWN_LOW
				LANTERN:
					layout.lanterns.append(cell)
				_:
					var kind := SideEnemyKinds.kind_for_char(line[column])
					if kind >= 0 and line[column] != SLIME and line[column] != SKELETON:
						layout.other_enemies.append(Vector3i(column, row, kind))
	layout._parse_movers()
	layout._parse_saws()
	layout._parse_shafts()
	return layout


## Last column of the run of line[column] starting at column.
static func _run_end(line: String, column: int) -> int:
	var last := column
	while last + 1 < line.length() and line[last + 1] == line[column]:
		last += 1
	return last


func _parse_movers() -> void:
	for row in size.y:
		var line := rows[row]
		for column in line.length():
			var c := line[column]
			if (c != MOVER_H and c != MOVER_V) or (column > 0 and line[column - 1] == c):
				continue
			var mover := Mover.new()
			mover.first = column
			mover.last = _run_end(line, column)
			mover.row = row
			if c == MOVER_H:
				mover.axis = Vector2i.RIGHT
				while char_at(Vector2i(mover.first + mover.low - 1, row)) == TRACK_H:
					mover.low -= 1
				while char_at(Vector2i(mover.last + mover.high + 1, row)) == TRACK_H:
					mover.high += 1
			else:
				mover.axis = Vector2i.DOWN
				while char_at(Vector2i(column, row + mover.low - 1)) == TRACK_V:
					mover.low -= 1
				while row + mover.high + 1 < size.y and char_at(Vector2i(column, row + mover.high + 1)) == TRACK_V:
					mover.high += 1
			movers.append(mover)


func _parse_saws() -> void:
	for row in size.y:
		for column in size.x:
			var cell := Vector2i(column, row)
			if char_at(cell) != SAW:
				continue
			var saw := Saw.new()
			saw.cell = cell
			var vertical := char_at(cell + Vector2i.UP) == RAIL or (cell.y + 1 < size.y and char_at(cell + Vector2i.DOWN) == RAIL)
			saw.axis = Vector2i.DOWN if vertical else Vector2i.RIGHT
			while char_at(cell + saw.axis * (saw.low - 1)) == RAIL and (cell + saw.axis * (saw.low - 1)).y < size.y:
				saw.low -= 1
			while (cell + saw.axis * (saw.high + 1)).y < size.y and char_at(cell + saw.axis * (saw.high + 1)) == RAIL:
				saw.high += 1
			saws.append(saw)


## Every connected area of "*" as its bounding rectangle.
func _parse_shafts() -> void:
	var seen: Dictionary[Vector2i, bool] = {}
	for row in size.y:
		for column in size.x:
			var cell := Vector2i(column, row)
			if seen.has(cell) or char_at(cell) != SHAFT:
				continue
			var rect := Rect2i(cell, Vector2i.ONE)
			var queue: Array[Vector2i] = [cell]
			seen[cell] = true
			while not queue.is_empty():
				var current: Vector2i = queue.pop_front()
				rect = rect.expand(current).merge(Rect2i(current, Vector2i.ONE))
				for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var next := current + step
					if not seen.has(next) and next.y < size.y and char_at(next) == SHAFT:
						seen[next] = true
						queue.append(next)
			shafts.append(rect)


## The same plan, left and right swapped (start on the right, door on the left).
func mirrored() -> SideLayout:
	var flipped := PackedStringArray()
	for line in rows:
		var reversed := ""
		for i in range(line.length() - 1, -1, -1):
			reversed += MIRROR_SWAP.get(line[i], line[i])
		flipped.append(reversed)
	var layout := SideLayout.parse(flipped, plan_id)
	layout.biome_id = biome_id
	layout.is_mirrored = not is_mirrored
	layout.chest_enabled = chest_enabled
	layout.turrets_enabled = turrets_enabled
	layout.tier = tier
	layout.pieces = pieces.duplicate()
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


## Rock or ledge (also a crumbling one, a tilting platform or a bridge piece): something a player
## stands on.
func is_blocking(cell: Vector2i) -> bool:
	var c := char_at(cell)
	return c == ROCK or c == LEDGE or c == CRUMBLE or c == TILT or c == BRIDGE


## Ground that can fall away (crumbling ledge, tilting platform, bridge piece): no safe return spot,
## no tile, its own node.
func is_element_ground(cell: Vector2i) -> bool:
	var c := char_at(cell)
	return c == CRUMBLE or c == TILT or c == BRIDGE


func is_spring(cell: Vector2i) -> bool:
	return char_at(cell) == SPRING


## A layout composed of pieces (ObstacleRunPlans), not a piece of its own.
func is_obstacle_run() -> bool:
	return not pieces.is_empty()


func is_slope(cell: Vector2i) -> bool:
	return slopes.has(cell)


## Slope shape of a cell (Slope.NONE for every other cell).
func slope_at(cell: Vector2i) -> Slope:
	return slopes.get(cell, Slope.NONE) as Slope


## Height (px, local y) of the ground under a stand cell at its left (x) and right (y) edge: the
## cell's bottom, or the slope's line in it.
func ground_line(cell: Vector2i) -> Vector2:
	var bottom := (cell.y + 1) * SideRules.TILE
	if not slopes.has(cell):
		return Vector2(bottom, bottom)
	var heights: Vector2 = SLOPE_HEIGHTS[slopes[cell]]
	return Vector2(bottom - heights.x * SideRules.TILE, bottom - heights.y * SideRules.TILE)


## Whether a walk leads from stand cell a to b in the next column without a jump: the ground runs on
## at the same height across their shared edge (flat ground, onto, along and off slopes).
func walk_connects(a: Vector2i, b: Vector2i) -> bool:
	if absi(b.x - a.x) != 1 or absi(b.y - a.y) > 1 or not is_standable(a) or not is_standable(b):
		return false
	if not slopes.has(a) and not slopes.has(b):
		return a.y == b.y
	var right := b.x > a.x
	var from_line := ground_line(a)
	var to_line := ground_line(b)
	var at_edge := from_line.y if right else from_line.x
	var after_edge := to_line.x if right else to_line.y
	return absf(at_edge - after_edge) < 1.0


## The new element kinds of this plan (SideElementRules.KIND_*): the "Besonderheiten" of its tier.
func element_kinds() -> Array[StringName]:
	var kinds: Array[StringName] = []
	if not movers.is_empty():
		kinds.append(SideElementRules.KIND_MOVER)
	if not springs.is_empty():
		kinds.append(SideElementRules.KIND_SPRING)
	if not tilts.is_empty():
		kinds.append(SideElementRules.KIND_TILT)
	if not saws.is_empty():
		kinds.append(SideElementRules.KIND_SAW)
	if not bridges.is_empty():
		kinds.append(SideElementRules.KIND_BRIDGE)
	if not shafts.is_empty():
		kinds.append(SideElementRules.KIND_SHAFT)
	return kinds


## Every enemy of the plan as Vector3i(column, row, SideEnemy.Kind), in build order: slimes,
## skeletons (the order of rounds 1-3, one segment draw each), then the SV4 kinds.
func enemy_cells() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for cell in slimes:
		cells.append(Vector3i(cell.x, cell.y, SideEnemy.Kind.SLIME))
	for cell in skeletons:
		cells.append(Vector3i(cell.x, cell.y, SideEnemy.Kind.SKELETON))
	cells.append_array(other_enemies)
	return cells


## Stand cells on moving platforms (anywhere along their tracks) -> index in movers.
func mover_stand_cells() -> Dictionary[Vector2i, int]:
	if not _riding_built:
		_riding_built = true
		for index in movers.size():
			for cell in movers[index].all_stand_cells():
				if not _riding.has(cell):
					_riding[cell] = index
	return _riding


## Index of the moving platform a (virtual) stand cell rides on, -1 for firm ground.
func mover_of(cell: Vector2i) -> int:
	if is_standable(cell):
		return -1
	return mover_stand_cells().get(cell, -1)


## The shaft whose bottom a stands on and out of which b is an exit, else an empty Rect2i.
func shaft_climb(a: Vector2i, b: Vector2i) -> Rect2i:
	for shaft in shafts:
		if _shaft_bottom(shaft).has(a) and _shaft_exits(shaft).has(b):
			return shaft
	return Rect2i()


## The cells of a saw's rail (with the saw's own) and their neighbours: no safe return spot there.
func saw_danger_cells() -> Dictionary[Vector2i, bool]:
	if not _saw_danger_built:
		_saw_danger_built = true
		for saw in saws:
			for cell in saw.path_cells():
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						_saw_danger[cell + Vector2i(dx, dy)] = true
	return _saw_danger


## A stand cell a player returns to after a pit (D-144: the last safe platform): firm static ground,
## no spikes, no spring, not next to a saw's rail, not inside a shaft (SV2: lanterns are always
## safe).
func is_safe_spot(cell: Vector2i) -> bool:
	if lanterns.has(cell):
		return true
	if not is_standable(cell) or spikes.has(cell) or is_spring(cell) or is_element_ground(cell + Vector2i.DOWN):
		return false
	# On a slope the cell's bottom lies in the rock (SV3).
	if slopes.has(cell):
		return false
	if char_at(cell) == SHAFT or saw_danger_cells().has(cell):
		return false
	return true


func is_ladder(cell: Vector2i) -> bool:
	return char_at(cell) == LADDER


func is_pool(cell: Vector2i) -> bool:
	return char_at(cell) == POOL


## Global-free question for the segment: a local point (feet) is in the water of a pool.
func is_in_pool(local: Vector2) -> bool:
	return is_pool(cell_at(local + Vector2(0, -2)))


## Which way a turret on cell looks out of its mount: UP standing on the floor, DOWN hanging from
## the rock above, RIGHT / LEFT on a rock wall to the left / right; ZERO without a mount.
func turret_normal(cell: Vector2i) -> Vector2i:
	if is_blocking(cell + Vector2i.DOWN):
		return Vector2i.UP
	if is_rock(cell + Vector2i.UP):
		return Vector2i.DOWN
	if is_rock(cell + Vector2i.LEFT):
		return Vector2i.RIGHT
	if is_rock(cell + Vector2i.RIGHT):
		return Vector2i.LEFT
	return Vector2i.ZERO


## No rock between two local points (ledges and everything else let sight and shots through).
func line_clear(from: Vector2, to: Vector2) -> bool:
	var distance := from.distance_to(to)
	var steps := maxi(1, ceili(distance / SIGHT_STEP))
	for i in range(1, steps):
		if is_rock(cell_at(from.lerp(to, float(i) / steps))):
			return false
	return true


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
		var bottom := Vector2i(column, size.y - 1)
		if not is_blocking(bottom) and not slopes.has(bottom):
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
		if not is_standable(cell) or is_spring(cell) or char_at(cell + Vector2i.DOWN) in [TILT, BRIDGE]:
			# Not from a moving platform, a spring, a tilting platform or a bridge piece (a crumbling
			# ledge holds long enough).
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
	var riding := mover_stand_cells()
	for cell in riding:
		if not cells.has(cell):
			cells.append(cell)
	# Cells by column: a jump never reaches further than GRAPH_MAX_COLUMNS (long obstacle runs).
	# The targets keep the order of cells (the ways the bot finds stay the same).
	var by_column: Dictionary[int, Array] = {}
	var order: Dictionary[Vector2i, int] = {}
	for index in cells.size():
		var cell := cells[index]
		order[cell] = index
		if not by_column.has(cell.x):
			by_column[cell.x] = []
		by_column[cell.x].append(cell)
	for a in cells:
		var targets: Array[Vector2i] = []
		for column in range(a.x - GRAPH_MAX_COLUMNS, a.x + GRAPH_MAX_COLUMNS + 1):
			for b: Vector2i in by_column.get(column, []):
				if a == b:
					continue
				var connects := _spring_connects(a, b, double) if is_spring(a) else _jump_connects(a, b, double)
				if connects or walk_connects(a, b):
					targets.append(b)
		targets.sort_custom(func(x: Vector2i, y: Vector2i) -> bool: return order[x] < order[y])
		edges[a] = targets
	# Riding a moving platform: from any of its stand cells to any other.
	for mover in movers:
		var ride := mover.all_stand_cells()
		for a in ride:
			for b in ride:
				if a != b and not (edges[a] as Array).has(b):
					(edges[a] as Array).append(b)
	# Wall jumps up a shaft: from its bottom to every exit.
	for shaft in shafts:
		for bottom in _shaft_bottom(shaft):
			for exit in _shaft_exits(shaft):
				if edges.has(bottom) and not (edges[bottom] as Array).has(exit):
					(edges[bottom] as Array).append(exit)
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
	if is_pool(a):
		# Running in water is slow: a jump out of a pool carries less far (SideRules.POOL_REACH*).
		reach = mini(reach, SideRules.POOL_REACH_DOUBLE if double else SideRules.POOL_REACH)
	if columns > reach:
		return false
	# Straight up under solid rock is impossible (ledges can be jumped through from below).
	if rise > 0 and columns == 0:
		for step in range(1, rise + 1):
			if is_rock(a + Vector2i(0, -step)):
				return false
	return true


## A spring launches straight up (SideElementRules.SPRING_HEIGHT_TILES): rows up -> columns, the
## first rows above the spring must be free of rock.
func _spring_connects(a: Vector2i, b: Vector2i, double := false) -> bool:
	var columns := absi(b.x - a.x)
	var rise := a.y - b.y
	if rise > (SideElementRules.SPRING_DOUBLE_REACH_UP_MAX if double else SideElementRules.SPRING_REACH_UP_MAX):
		return false
	var table: Dictionary = SideElementRules.SPRING_DOUBLE_REACH_BY_RISE if double else SideElementRules.SPRING_REACH_BY_RISE
	var reach: int = table[rise] if rise >= 0 else SideElementRules.SPRING_REACH_DROP
	if columns > reach:
		return false
	for step in range(1, maxi(rise, 1) + 1):
		if is_rock(a + Vector2i(0, -step)):
			return false
	return true


## The stand cells on a shaft's floor.
func _shaft_bottom(shaft: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for column in range(shaft.position.x, shaft.end.x):
		var cell := Vector2i(column, shaft.end.y - 1)
		if is_standable(cell):
			cells.append(cell)
	return cells


## Stand cells beside a shaft's top (SideElementRules.SHAFT_EXIT_*): where a wall jump climbs out.
func _shaft_exits(shaft: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for row in range(shaft.position.y - SideElementRules.SHAFT_EXIT_ROWS, shaft.position.y + 2):
		for column in range(shaft.position.x - SideElementRules.SHAFT_EXIT_COLUMNS, shaft.end.x + SideElementRules.SHAFT_EXIT_COLUMNS):
			var cell := Vector2i(column, row)
			if not shaft.has_point(cell) and is_standable(cell):
				cells.append(cell)
	return cells


# --- Plan rules ---

## Errors of this plan against the M5 rules (empty = fine).
func check() -> PackedStringArray:
	if is_obstacle_run():
		return ObstacleRunPlans.check(self)
	var errors := PackedStringArray()
	if size.y < SideRules.ROWS or size.y > SideRules.MAX_ROWS:
		errors.append("%s: %d rows instead of %d-%d" % [plan_id, size.y, SideRules.ROWS, SideRules.MAX_ROWS])
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
	# Tall plans (SV2) carry one more platform per extra row.
	if platforms < PLATFORM_RANGE.x or platforms > PLATFORM_RANGE.y + size.y - SideRules.ROWS:
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
	var enemies := enemy_cells().size()
	if enemies < ENEMY_RANGE.x or enemies > ENEMY_RANGE.y:
		errors.append("%s: %d enemies" % [plan_id, enemies])
	for enemy in enemy_cells():
		var chain: Array[SideEnemyChain.Placement] = [SideEnemyChain.Placement.new(enemy.z as SideEnemy.Kind)]
		for problem in SideEnemyChain.fits(self, chain, Vector2i(enemy.x, enemy.y)):
			errors.append("%s: %s" % [plan_id, problem])
	# A saw takes the place of the spike traps (SV2).
	if spikes.size() < (0 if not saws.is_empty() else SPIKE_RANGE.x) or spikes.size() > SPIKE_RANGE.y:
		errors.append("%s: %d spike traps" % [plan_id, spikes.size()])
	if turrets.size() < TURRET_RANGE.x or turrets.size() > TURRET_RANGE.y:
		errors.append("%s: %d turret mounts" % [plan_id, turrets.size()])
	for turret in turrets:
		if turret_normal(turret) == Vector2i.ZERO:
			errors.append("%s: turret at %s has no mount" % [plan_id, turret])
		if absi(turret.x - start.x) < SideRules.TURRET_MIN_DISTANCE or absi(turret.x - door.x) < SideRules.TURRET_MIN_DISTANCE:
			errors.append("%s: turret at %s too close to the start or the door" % [plan_id, turret])
	for pool in pools:
		for column in range(pool.x, pool.y + 1):
			if not is_blocking(Vector2i(column, pool.z + 1)):
				errors.append("%s: pool at %d, %d without a floor" % [plan_id, column, pool.z])
				break
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
	for enemy in enemy_cells():
		if not SideEnemyKinds.is_flying(enemy.z as SideEnemy.Kind):
			items.append(Vector2i(enemy.x, enemy.y))
	items.append_array(spikes)
	items.append_array(lanterns)
	if chest.x >= 0:
		items.append(chest)
	for item in items:
		if not _item_in_reach(item, reach, ITEM_REACH_ROWS):
			errors.append("%s: %s at %s out of reach" % [plan_id, char_at(item), item])
	# A turret can be hit: it stands in reach, at worst with the double jump (ceiling mounts).
	for turret in turrets:
		if not _item_in_reach(turret, reach, ITEM_REACH_ROWS_DOUBLE):
			errors.append("%s: turret at %s out of reach" % [plan_id, turret])
	# The golden coin needs the double jump: out of a plain jump's reach, in a double jump's.
	if golden_coin.x >= 0:
		if not _item_in_reach(golden_coin, reach, ITEM_REACH_ROWS_DOUBLE):
			errors.append("%s: golden coin out of reach" % plan_id)
		elif _item_in_reach(golden_coin, reach, ITEM_REACH_ROWS):
			errors.append("%s: golden coin needs no double jump" % plan_id)
	for run in crumbles:
		for column in range(run.x, run.y + 1):
			var above := char_at(Vector2i(column, run.z - 1))
			if above in [SLIME, SKELETON, SPIKES, CHEST, DOOR, START, TURRET]:
				errors.append("%s: something stands on the crumbling ledge at %d" % [plan_id, column])
	errors.append_array(_check_chest())
	errors.append_array(_check_elements())
	errors.append_array(_check_way_view())
	return errors


## The rules of a piece that also hold for a whole obstacle run (ObstacleRunPlans.check): the chest
## niche, the elements without the tier's count, no blind jump.
func run_part_errors() -> PackedStringArray:
	var errors := _check_chest()
	errors.append_array(_check_elements(false))
	errors.append_array(_check_way_view())
	return errors


## The jump trial's elements (SV2, D-195): tracks and rails run through air, springs stand on firm
## ground, tilting platforms are TILT_CELLS wide, shafts between rock walls and higher than a
## double jump, lanterns on the ground, the number of element kinds fits the tier, and a long plan
## has a lantern.
func _check_elements(with_tier := true) -> PackedStringArray:
	var errors := PackedStringArray()
	for mover in movers:
		if mover.low == mover.high:
			errors.append("%s: moving platform at %d, %d without a track" % [plan_id, mover.first, mover.row])
		for offset in range(mover.low, mover.high + 1):
			for cell in mover.cells_at(offset):
				if is_blocking(cell) or cell.y >= size.y:
					errors.append("%s: moving platform at %d, %d runs into %s" % [plan_id, mover.first, mover.row, cell])
					break
	for spring in springs:
		if not is_blocking(spring + Vector2i.DOWN) or is_element_ground(spring + Vector2i.DOWN):
			errors.append("%s: spring at %s without firm ground" % [plan_id, spring])
	for run in tilts:
		if run.y - run.x + 1 != SideElementRules.TILT_CELLS:
			errors.append("%s: tilting platform at %d, %d is not %d wide" % [plan_id, run.x, run.z, SideElementRules.TILT_CELLS])
	var keep_free: Array[Vector2i] = [start, door, chest]
	keep_free.append_array(lanterns)
	for saw in saws:
		if saw.low == saw.high:
			errors.append("%s: saw at %s without a rail" % [plan_id, saw.cell])
		for cell in saw.path_cells():
			if is_blocking(cell):
				errors.append("%s: the rail of the saw at %s runs into rock" % [plan_id, saw.cell])
				break
		var danger := saw_danger_cells()
		for cell in keep_free:
			if cell.x >= 0 and saw.path_cells().has(cell):
				errors.append("%s: the saw at %s runs over %s" % [plan_id, saw.cell, cell])
		if danger.has(start) or danger.has(door):
			errors.append("%s: a saw too close to the start or the door" % plan_id)
	for shaft in shafts:
		if shaft.size.x != SideElementRules.SHAFT_WIDTH or shaft.size.y < SideElementRules.SHAFT_MIN_ROWS:
			errors.append("%s: shaft at %s is %s" % [plan_id, shaft.position, shaft.size])
		for row in range(shaft.position.y + 1, shaft.end.y - 1):
			if not is_rock(Vector2i(shaft.position.x - 1, row)) or not is_rock(Vector2i(shaft.end.x, row)):
				errors.append("%s: shaft at %s without rock walls in row %d" % [plan_id, shaft.position, row])
				break
		if _shaft_bottom(shaft).is_empty() or _shaft_exits(shaft).is_empty():
			errors.append("%s: shaft at %s without a floor or an exit" % [plan_id, shaft.position])
	for lantern in lanterns:
		if not is_standable(lantern):
			errors.append("%s: lantern at %s floats" % [plan_id, lantern])
	if (size.y > SideRules.ROWS or tier >= SideElementRules.LANTERN_FROM_TIER) and lanterns.is_empty():
		errors.append("%s: a long plan without a lantern" % plan_id)
	var kinds := element_kinds().size()
	if with_tier and not SideElementRules.tier_allows(tier, kinds):
		errors.append("%s: %d element kinds do not fit tier %d" % [plan_id, kinds, tier])
	return errors


## No blind jump (D-195): every jump of the way from the start to the door rises at most
## SideElementRules.WAY_MAX_RISE_ROWS and drops at most WAY_MAX_DROP_ROWS rows (ladders, rides and
## shaft climbs follow the player).
func _check_way_view() -> PackedStringArray:
	var errors := PackedStringArray()
	var path := find_path(start, door)
	var riding := mover_stand_cells()
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		if a.y - b.y <= SideElementRules.WAY_MAX_RISE_ROWS and b.y - a.y <= SideElementRules.WAY_MAX_DROP_ROWS:
			continue
		var ladder := a.x == b.x and ladders.has(a.x)
		var ride := riding.has(a) and riding.has(b) and riding[a] == riding[b]
		if not ladder and not ride and shaft_climb(a, b) == Rect2i():
			errors.append("%s: blind jump from %s to %s" % [plan_id, a, b])
	return errors


## The chest niche (D-144): every plan has one, on firm ground (never over a pit) with an open stand
## cell beside it, a detour without the double jump from a spot on the way, and off the way itself
## (no cell of the shortest way from the start to the door, nor one walked over between two of
## them), so it never blocks the way.
func _check_chest() -> PackedStringArray:
	var errors := PackedStringArray()
	if chest.x < 0:
		errors.append("%s: no chest niche" % plan_id)
		return errors
	if not is_standable(chest):
		errors.append("%s: chest at %s floats" % [plan_id, chest])
	if not is_standable(chest + Vector2i.LEFT) and not is_standable(chest + Vector2i.RIGHT):
		errors.append("%s: chest at %s has no open side" % [plan_id, chest])
	if pit_columns().has(chest.x):
		errors.append("%s: chest at %s over a pit" % [plan_id, chest])
	var way := way_cells()
	if chest in way:
		errors.append("%s: chest at %s stands on the way" % [plan_id, chest])
	var plain_detour := false
	for cell in way:
		if is_standable(cell) and reachable_from(cell, false).has(chest):
			plain_detour = true
			break
	if not plain_detour:
		errors.append("%s: the way to the chest at %s needs the double jump" % [plan_id, chest])
	return errors


## The cells of the shortest way from the start to the door, with the cells walked over between two
## of them on the same row.
func way_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var path := find_path(start, door)
	for i in path.size():
		cells.append(path[i])
		if i == 0 or path[i].y != path[i - 1].y:
			continue
		var step := signi(path[i].x - path[i - 1].x)
		for column in range(path[i - 1].x + step, path[i].x, step):
			cells.append(Vector2i(column, path[i].y))
	return cells


## true if the door can only be reached with the double jump (the plan asks for it on the way).
func way_needs_double_jump() -> bool:
	return not reachable_from(start, false).has(door)


## Whether item lies within ITEM_REACH_COLUMNS and rows_above rows above a cell of reach (ObstacleRunPlans).
func item_in_reach(item: Vector2i, reach: Dictionary[Vector2i, bool], rows_above: int) -> bool:
	return _item_in_reach(item, reach, rows_above)


## The blind-jump errors of the way from the start to the door (ObstacleRunPlans).
func way_view_errors() -> PackedStringArray:
	return _check_way_view()


func _item_in_reach(item: Vector2i, reach: Dictionary[Vector2i, bool], rows_above: int) -> bool:
	for cell in reach:
		var above := cell.y - item.y
		if absi(cell.x - item.x) <= ITEM_REACH_COLUMNS and above >= 0 and above <= rows_above:
			return true
	return false

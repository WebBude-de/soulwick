class_name SideEnemyChain
extends RefCounted
## Enemy group building blocks for side plans (SV4, D-195): small groups of side enemies the plans
## use as obstacles (D-216: jumped over or stomped, never run over), e.g. "two slimes with room to
## land between them" or "bats over a gap to stomp across". A chain is a list of placements relative to its origin, a
## stand cell (air with ground below) where the first ground enemy stands; offset x = columns to the
## right, y = rows down (negative = up, bats). Builders: row, mixed, hurdle, bat_bridge. Tools:
## stamp (writes the chain into ASCII plan rows with SideEnemyKinds.PLAN_CHARS), fits (the chain
## stands on ground, bat paths are air), check (count and spacing), can_stomp_through. TESTWERTE
## below.

## Columns between two ground enemies at least (the hit stop and the pop stay readable).
const MIN_SPACING := 2
## Enemies per chain.
const COUNT_RANGE := Vector2i(2, 8)
## Bats of a bridge fly this many rows above the origin row and this many columns apart.
const BAT_ROWS_UP := 1
const BAT_SPACING := 3


## One enemy of a chain.
class Placement:
	extends RefCounted
	var kind := SideEnemy.Kind.SLIME
	var offset := Vector2i.ZERO

	func _init(placement_kind: SideEnemy.Kind = SideEnemy.Kind.SLIME, placement_offset := Vector2i.ZERO) -> void:
		kind = placement_kind
		offset = placement_offset


## count enemies of one kind on the floor, spacing columns apart ("Reihe aus N Schleimen").
static func row(kind: SideEnemy.Kind, count: int, spacing := MIN_SPACING) -> Array[Placement]:
	var chain: Array[Placement] = []
	for i in count:
		chain.append(Placement.new(kind, Vector2i(i * spacing, 0)))
	return chain


## The given kinds in order on the floor, spacing columns apart.
static func mixed(kinds: Array[SideEnemy.Kind], spacing := MIN_SPACING) -> Array[Placement]:
	var chain: Array[Placement] = []
	for i in kinds.size():
		chain.append(Placement.new(kinds[i], Vector2i(i * spacing, 0)))
	return chain


## A row with a spike hedgehog in the middle to jump over (it takes no stomp).
static func hurdle(before: int, after: int, kind := SideEnemy.Kind.SLIME, spacing := MIN_SPACING + 1) -> Array[Placement]:
	var kinds: Array[SideEnemy.Kind] = []
	for i in before:
		kinds.append(kind)
	kinds.append(SideEnemy.Kind.SPIKE_HEDGEHOG)
	for i in after:
		kinds.append(kind)
	return mixed(kinds, spacing)


## count bats over a gap, stomped one after the other (each stomp bounces to the next).
static func bat_bridge(count: int, spacing := BAT_SPACING) -> Array[Placement]:
	var chain: Array[Placement] = []
	for i in count:
		chain.append(Placement.new(SideEnemy.Kind.BAT, Vector2i(i * spacing, -BAT_ROWS_UP)))
	return chain


## Plan cells of the chain at origin (cell -> kind).
static func cells(chain: Array[Placement], origin: Vector2i) -> Dictionary[Vector2i, int]:
	var result: Dictionary[Vector2i, int] = {}
	for placement in chain:
		result[origin + placement.offset] = placement.kind
	return result


## The plan rows with the chain written in at origin (only onto air cells "."); errors go to
## errors. The rows themselves stay untouched.
static func stamp(rows: PackedStringArray, chain: Array[Placement], origin: Vector2i, errors: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var result := rows.duplicate()
	for placement in chain:
		var cell := origin + placement.offset
		if cell.y < 0 or cell.y >= result.size() or cell.x < 0 or cell.x >= result[cell.y].length():
			errors.append("chain enemy at %s outside the plan" % cell)
			continue
		var line := result[cell.y]
		if line[cell.x] != SideLayout.AIR:
			errors.append("chain enemy at %s on '%s', not on air" % [cell, line[cell.x]])
			continue
		result[cell.y] = line.substr(0, cell.x) + SideEnemyKinds.char_for(placement.kind) + line.substr(cell.x + 1)
	return result


## Problems of the chain at origin in layout: ground enemies need a stand cell, a bat's whole
## path must be air inside the plan. Empty = fits.
static func fits(layout: SideLayout, chain: Array[Placement], origin: Vector2i) -> PackedStringArray:
	var errors := PackedStringArray()
	for placement in chain:
		var cell := origin + placement.offset
		if SideEnemyKinds.is_flying(placement.kind):
			for path_cell in SideBat.path_cells(cell):
				if not _inside(layout, path_cell) or layout.is_blocking(path_cell):
					errors.append("bat at %s: its path crosses %s" % [cell, path_cell])
					break
		elif not layout.is_standable(cell):
			errors.append("%s at %s has no ground" % [SideEnemy.Kind.keys()[placement.kind], cell])
	return errors


## Problems of the chain itself: count in COUNT_RANGE, ground enemies of one row at least
## MIN_SPACING apart, no two on one cell. Empty = fine.
static func check(chain: Array[Placement]) -> PackedStringArray:
	var errors := PackedStringArray()
	if chain.size() < COUNT_RANGE.x or chain.size() > COUNT_RANGE.y:
		errors.append("chain of %d enemies (allowed %d-%d)" % [chain.size(), COUNT_RANGE.x, COUNT_RANGE.y])
	var seen: Dictionary[Vector2i, bool] = {}
	for placement in chain:
		if seen.has(placement.offset):
			errors.append("two enemies at %s" % placement.offset)
		seen[placement.offset] = true
		for other in chain:
			if other == placement or other.offset.y != placement.offset.y:
				continue
			var gap := absi(other.offset.x - placement.offset.x)
			if gap > 0 and gap < MIN_SPACING:
				errors.append("enemies at %s and %s closer than %d columns" % [placement.offset, other.offset, MIN_SPACING])
	return errors


## Every enemy of the chain falls to a stomp.
static func can_stomp_through(chain: Array[Placement]) -> bool:
	for placement in chain:
		if not SideEnemy.kind_accepts_stomp(placement.kind):
			return false
	return true


static func _inside(layout: SideLayout, cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < layout.size.x and cell.y < layout.size.y

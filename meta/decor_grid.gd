class_name DecorGrid
extends RefCounted
## Where decoration may stand (WK5, WK7): the tile grid of one space (the village of a world or the
## home) with the cells a piece may cover and the rules a new placement has to keep. One tile is
## TILE art px (32, SPRITES_V13 Teil E) at the space's scale (2 = 64 world px), the same grid as the
## village ground and the home's floor.
## Three layers never mix: flat pieces (rugs, paving) may lie under furniture, standing pieces never
## overlap each other, wall pieces hang on the home's back wall (window slots only for WINDOW_KINDS).
## Rules: inside the allowed cells (village: off paths, doors, the spawn, buildings and cliffs, from
## VillageDecor.collect_rules; home: the floor minus altar, mirror, broom and door), no overlap in
## the layer, no blocking piece on a player, and in the home every free floor cell stays reachable
## from the door, the altar and the mirror keep a free side (nobody walls himself in). The village
## needs no way check: its paths connect every door and decoration never covers a path.
## check() returns &"" or the translation key of the reason (shown in the editor).

const TILE := 32
const OK: StringName = &""
const REASON_PLACE: StringName = &"DECOR_BLOCKED_PLACE"
const REASON_TAKEN: StringName = &"DECOR_BLOCKED_TAKEN"
const REASON_WAY: StringName = &"DECOR_BLOCKED_WAY"
const REASON_PLAYER: StringName = &"DECOR_BLOCKED_PLAYER"
const REASON_WALL: StringName = &"DECOR_BLOCKED_WALL"
## Wall pieces that belong under the window (the window slots are free for them only).
const WINDOW_KINDS: Array[String] = ["window_box"]
## TESTWERT: a player's feet this close to a blocking piece's footprint (world px) keep it from being set.
const PLAYER_MARGIN := 10.0
## TESTWERT: the collision of a blocking piece is its footprint minus this on every side (world px),
## so players squeeze past corners.
const SOLID_INSET := 4.0

var space: StringName = &""
## World px per tile (TILE × scale).
var tile := 64.0
var size := Vector2i.ZERO
## Cells a floor piece may cover.
var floor_cells: Dictionary[Vector2i, bool] = {}
## Back wall cells (home) and the window slots among them.
var wall_cells: Dictionary[Vector2i, bool] = {}
var window_cells: Dictionary[Vector2i, bool] = {}
## Cells only flat pieces may cover (spawn, under the altar, beside the mirror).
var flat_only: Dictionary[Vector2i, bool] = {}
## Cells that block walking without a piece (altar, broom), for the way check.
var fixed_blocked: Dictionary[Vector2i, bool] = {}
## Cells that must keep a reachable free neighbour (altar, mirror).
var access_targets: Array[Vector2i] = []
## Start of the way check (the home's door); (-1, -1) = no way check (village).
var entry := Vector2i(-1, -1)


## The village's grid from its scene (Ground, Buildings, PlayerSpawn; see VillageDecor.collect_rules).
static func for_village(village: Node2D) -> DecorGrid:
	var grid := DecorGrid.new()
	grid.space = DecorCatalog.VILLAGE
	var ground := village.get_node("Ground") as VillageTiles
	grid.tile = TILE * ground.scale.x
	grid.size = ground.map_size
	var rules := VillageDecor.collect_rules(village)
	for y in grid.size.y:
		for x in grid.size.x:
			if village_cell_allowed(Rect2(Vector2(x, y) * grid.tile, Vector2.ONE * grid.tile), rules):
				grid.floor_cells[Vector2i(x, y)] = true
	return grid


## A village tile is free for decoration: inside the fence, not on a path (the tile next to one is
## fine, paths lie on the same grid), not on a building, prop, cliff or bush, and outside the circles
## around doors and the spawn (VillageDecor.collect_rules).
static func village_cell_allowed(cell_rect: Rect2, rules: Dictionary) -> bool:
	var rect := cell_rect.grow(-2.0)
	if not (rules["map"] as Rect2).encloses(rect):
		return false
	for path: Rect2 in rules["paths"]:
		if path.intersects(rect):
			return false
	for blocker: Rect2 in rules["blockers"]:
		if blocker.intersects(rect):
			return false
	for circle: Vector3 in rules["clear"]:
		if VillageDecor.rect_circle_distance(rect, Vector2(circle.x, circle.y)) < circle.z:
			return false
	return true


## The home's grid (HomeLayout: 15×9 tiles, floor rows WALL_ROWS..ROWS-1, back wall row above).
static func for_home() -> DecorGrid:
	var grid := DecorGrid.new()
	grid.space = DecorCatalog.HOME
	grid.tile = HomeLayout.TILE * HomeLayout.SCALE
	grid.size = Vector2i(HomeLayout.COLS, HomeLayout.ROWS)
	for y in range(HomeLayout.WALL_ROWS, HomeLayout.ROWS):
		for x in HomeLayout.COLS:
			grid.floor_cells[Vector2i(x, y)] = true
	var wall_row := HomeLayout.WALL_ROWS - 1
	for x in range(1, HomeLayout.COLS - 1):
		var cell := Vector2i(x, wall_row)
		if x == HomeLayout.WINDOW_COL or x == HomeLayout.WINDOW_COL + 1:
			grid.window_cells[cell] = true
		grid.wall_cells[cell] = true
	grid.floor_cells.erase(HomeLayout.DOOR_CELL)
	for cell in HomeLayout.FIXED_CELLS:
		grid.flat_only[cell] = true
		grid.fixed_blocked[cell] = true
	for cell in HomeLayout.FLAT_ONLY_CELLS:
		grid.flat_only[cell] = true
	grid.access_targets = HomeLayout.ACCESS_CELLS.duplicate()
	grid.entry = HomeLayout.DOOR_CELL
	return grid


func cell_at(world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / tile), floori(world.y / tile))


## Cells a piece covers at cell (top left of its footprint; wall pieces: the wall row).
static func cells_of(item: DecorItem, cell: Vector2i, rot: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var footprint := item.footprint(rot)
	for y in maxi(1, footprint.y):
		for x in footprint.x:
			cells.append(cell + Vector2i(x, y))
	return cells


## The piece's foot point (bottom centre of its footprint, world px): where its pivot goes.
func foot_of(item: DecorItem, cell: Vector2i, rot: int) -> Vector2:
	var footprint := item.footprint(rot)
	return Vector2((cell.x + footprint.x * 0.5) * tile, (cell.y + maxi(1, footprint.y)) * tile)


## Footprint in world px.
func rect_of(item: DecorItem, cell: Vector2i, rot: int) -> Rect2:
	var footprint := item.footprint(rot)
	return Rect2(Vector2(cell) * tile, Vector2(footprint.x, maxi(1, footprint.y)) * tile)


## Clamps a cursor cell into the grid.
func clamp_cell(cell: Vector2i) -> Vector2i:
	return Vector2i(clampi(cell.x, 0, maxi(0, size.x - 1)), clampi(cell.y, 0, maxi(0, size.y - 1)))


## &"" if item may stand at cell with rot among placements (DecorState.placements; the entry with
## ignore_index is the piece being moved), else the reason's key. players: feet points (world px).
func check(item: DecorItem, cell: Vector2i, rot: int, placements: Array[Dictionary], ignore_index := -1,
		players: Array[Vector2] = []) -> StringName:
	if item == null or item.is_surface() or item.space != space:
		return REASON_PLACE
	var cells := cells_of(item, cell, rot)
	for c in cells:
		if item.is_wall():
			if not wall_cells.has(c):
				return REASON_WALL
			if window_cells.has(c) and not WINDOW_KINDS.has(item.kind):
				return REASON_WALL
		elif not floor_cells.has(c) or (not item.is_flat() and flat_only.has(c)):
			return REASON_PLACE
	var taken := occupied(placements, _layer_of(item), ignore_index)
	for c in cells:
		if taken.has(c):
			return REASON_TAKEN
	if item.blocks():
		var rect := rect_of(item, cell, rot).grow(PLAYER_MARGIN)
		for feet in players:
			if rect.has_point(feet):
				return REASON_PLAYER
		if entry.x >= 0 and not keeps_way(placements, ignore_index, cells):
			return REASON_WAY
	return OK


## Cells taken in a layer (&"flat", &"stand", &"wall") by the placements (cell -> placement index).
func occupied(placements: Array[Dictionary], layer: StringName, ignore_index := -1) -> Dictionary[Vector2i, int]:
	var taken: Dictionary[Vector2i, int] = {}
	for entry_data in placements:
		var index := int(entry_data.get("index", -1))
		if index == ignore_index and ignore_index >= 0:
			continue
		var item := DecorCatalog.get_item(String(entry_data["id"]))
		if item == null or _layer_of(item) != layer:
			continue
		for c in cells_of(item, entry_data["cell"], int(entry_data["rot"])):
			taken[c] = index
	return taken


## Index of the placement covering cell (standing and wall pieces before flat ones), -1 if none.
func placement_at(placements: Array[Dictionary], cell: Vector2i) -> int:
	for layer in [&"wall", &"stand", &"flat"]:
		var taken := occupied(placements, layer)
		if taken.has(cell):
			return taken[cell]
	return -1


## True when with the blocking pieces of placements (and extra cells) every free floor cell is still
## reachable from the entry and every access target keeps a reachable free side.
func keeps_way(placements: Array[Dictionary], ignore_index := -1, extra: Array[Vector2i] = []) -> bool:
	var blocked := fixed_blocked.duplicate()
	for entry_data in placements:
		if int(entry_data.get("index", -1)) == ignore_index and ignore_index >= 0:
			continue
		var item := DecorCatalog.get_item(String(entry_data["id"]))
		if item != null and item.blocks():
			for c in cells_of(item, entry_data["cell"], int(entry_data["rot"])):
				blocked[c] = true
	for c in extra:
		blocked[c] = true
	var reached: Dictionary[Vector2i, bool] = {entry: true}
	var queue: Array[Vector2i] = [entry]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_back()
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = current + step
			if reached.has(next) or blocked.has(next) or not floor_cells.has(next):
				continue
			reached[next] = true
			queue.append(next)
	for c in floor_cells:
		if not blocked.has(c) and not reached.has(c):
			return false
	for target in access_targets:
		var open := false
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if reached.has(target + step):
				open = true
				break
		if not open:
			return false
	return true


static func _layer_of(item: DecorItem) -> StringName:
	if item.is_wall():
		return &"wall"
	return &"flat" if item.is_flat() else &"stand"

@tool
class_name VillageTiles
extends TileMapLayer
## Paints the village ground: grass, a fence around the border and paths with matching grass edges.
## Paths are given as tile rectangles; edge tiles are chosen from the grass neighbours.
## R7: a second atlas (art/environment/village/village_tiles_v2.png, drawn by VillagePlaceholders
## until it exists) adds the cobbled village square, the ridge with its rock face (solid), the
## stairs up to the dungeon and the stone slabs in front of the entrance.

const SOURCE_ID := 0
const GRASS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
const GRASS_FLOWERS := Vector2i(3, 0)
const PATH := Vector2i(4, 0)
const PATH_N := Vector2i(5, 0)
const PATH_E := Vector2i(6, 0)
const PATH_S := Vector2i(7, 0)
const PATH_W := Vector2i(0, 1)
const PATH_NS := Vector2i(1, 1)
const PATH_EW := Vector2i(2, 1)
const PATH_NE := Vector2i(3, 1)
const PATH_NW := Vector2i(4, 1)
const PATH_SE := Vector2i(5, 1)
const PATH_SW := Vector2i(6, 1)
const FENCE_H := Vector2i(7, 1)
const FENCE_V := Vector2i(0, 2)
const BUSH := Vector2i(1, 2)
const STUMP := Vector2i(2, 2)
## Second atlas (R7): source id, art name and tiles (8 × 32 px in one row).
const V2_SOURCE_ID := 1
const V2_ART := "village_tiles_v2"
const V2_COBBLE: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
const V2_CLIFF: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0)]
const V2_STAIRS_LEFT := Vector2i(4, 0)
const V2_STAIRS_RIGHT := Vector2i(5, 0)
const V2_SLABS: Array[Vector2i] = [Vector2i(6, 0), Vector2i(7, 0)]
## Solid part of a cliff tile (tile pixels around its centre): the rock face below the grass lip.
const CLIFF_SOLID: Array[Vector2] = [Vector2(-16, -10), Vector2(16, -10), Vector2(16, 13), Vector2(-16, 13)]

@export var map_size := Vector2i(30, 18):
	set(value):
		map_size = value
		_queue_paint()
@export var path_rects: Array[Rect2i] = []:
	set(value):
		path_rects = value
		_queue_paint()
@export var bush_tiles: Array[Vector2i] = []:
	set(value):
		bush_tiles = value
		_queue_paint()
@export var stump_tiles: Array[Vector2i] = []:
	set(value):
		stump_tiles = value
		_queue_paint()
## Cobbled village square (tiles); give the surrounding path rect one tile larger for a dirt rim.
@export var plaza_rects: Array[Rect2i] = []:
	set(value):
		plaza_rects = value
		_queue_paint()
## Ridge with a rock face (solid), the dungeon terrace lies above it.
@export var cliff_rects: Array[Rect2i] = []:
	set(value):
		cliff_rects = value
		_queue_paint()
## Stairs through the ridge (walkable; left and right half of the flight).
@export var stair_rects: Array[Rect2i] = []:
	set(value):
		stair_rects = value
		_queue_paint()
## Stone slabs on grass (the way to the entrance).
@export var slab_rects: Array[Rect2i] = []:
	set(value):
		slab_rects = value
		_queue_paint()
@export var ground_seed := 7:
	set(value):
		ground_seed = value
		_queue_paint()

var _paint_queued := false


func _ready() -> void:
	paint()


func paint() -> void:
	_paint_queued = false
	clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = ground_seed
	for y in map_size.y:
		for x in map_size.x:
			var grass := GRASS_FLOWERS if rng.randf() < 0.08 else GRASS[rng.randi_range(0, GRASS.size() - 1)]
			set_cell(Vector2i(x, y), SOURCE_ID, grass)
	var path_cells := {}
	for rect in path_rects:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				path_cells[Vector2i(x, y)] = true
	for cell in path_cells:
		set_cell(cell, SOURCE_ID, _path_tile(cell, path_cells))
	if _ensure_v2_source():
		for rect in plaza_rects:
			_fill_rect(rect, func(_cell: Vector2i) -> Vector2i: return V2_COBBLE[rng.randi_range(0, 1)])
		for rect in slab_rects:
			_fill_rect(rect, func(cell: Vector2i) -> Vector2i: return V2_SLABS[(cell.x + cell.y) % 2])
		for rect in cliff_rects:
			_fill_rect(rect, func(cell: Vector2i) -> Vector2i: return V2_CLIFF[(cell.x * 7 + cell.y) % 2])
		for rect in stair_rects:
			_fill_rect(rect, func(cell: Vector2i) -> Vector2i: return V2_STAIRS_LEFT if cell.x < rect.get_center().x else V2_STAIRS_RIGHT)
	for x in map_size.x:
		set_cell(Vector2i(x, 0), SOURCE_ID, FENCE_H)
		set_cell(Vector2i(x, map_size.y - 1), SOURCE_ID, FENCE_H)
	for y in range(1, map_size.y - 1):
		set_cell(Vector2i(0, y), SOURCE_ID, FENCE_V)
		set_cell(Vector2i(map_size.x - 1, y), SOURCE_ID, FENCE_V)
	for tile in bush_tiles:
		set_cell(tile, SOURCE_ID, BUSH)
	for tile in stump_tiles:
		set_cell(tile, SOURCE_ID, STUMP)


## Cells of the ground that are paved (paths, square, slabs, stairs): no decoration, villagers walk there.
func get_paved_rects() -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	result.append_array(path_rects)
	result.append_array(plaza_rects)
	result.append_array(slab_rects)
	result.append_array(stair_rects)
	return result


func _fill_rect(rect: Rect2i, pick: Callable) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			set_cell(cell, V2_SOURCE_ID, pick.call(cell))


## Adds the R7 atlas to the tile set once (art file or placeholder); the cliff tiles get collision.
func _ensure_v2_source() -> bool:
	# Not in the editor: the shared village_tileset.tres must not be saved with a runtime texture.
	if tile_set == null or Engine.is_editor_hint():
		return false
	if tile_set.has_source(V2_SOURCE_ID):
		return true
	var texture := VillageArt.get_texture(V2_ART)
	if texture == null:
		return false
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(32, 32)
	tile_set.add_source(source, V2_SOURCE_ID)
	var columns := int(texture.get_width() / 32.0)
	for x in columns:
		source.create_tile(Vector2i(x, 0))
	for coords in V2_CLIFF:
		if source.has_tile(coords):
			var data := source.get_tile_data(coords, 0)
			data.add_collision_polygon(0)
			data.set_collision_polygon_points(0, 0, PackedVector2Array(CLIFF_SOLID))
	return true


func _path_tile(cell: Vector2i, path_cells: Dictionary) -> Vector2i:
	var n := not path_cells.has(cell + Vector2i.UP)
	var e := not path_cells.has(cell + Vector2i.RIGHT)
	var s := not path_cells.has(cell + Vector2i.DOWN)
	var w := not path_cells.has(cell + Vector2i.LEFT)
	if n and s:
		return PATH_NS
	if e and w:
		return PATH_EW
	if n and e:
		return PATH_NE
	if n and w:
		return PATH_NW
	if s and e:
		return PATH_SE
	if s and w:
		return PATH_SW
	if n:
		return PATH_N
	if e:
		return PATH_E
	if s:
		return PATH_S
	if w:
		return PATH_W
	return PATH


func _queue_paint() -> void:
	if not is_inside_tree() or _paint_queued:
		return
	_paint_queued = true
	paint.call_deferred()

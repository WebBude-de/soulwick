@tool
class_name VillageTiles
extends TileMapLayer
## Paints the village ground: grass, a fence around the border and paths with matching grass edges.
## Paths are given as tile rectangles; edge tiles are chosen from the grass neighbours.

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

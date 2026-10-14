@tool
class_name RoomTiles
extends TileMapLayer
## Paints a rectangular dungeon room from a few parameters, in the editor and at runtime.
## Tile (0, 0) is the top-left floor tile. The north wall occupies rows -2 (top) and -1 (front),
## the south wall row room_size.y. Exits lead north through rows -1..-3, entrances come from the
## south through rows h..h+1, so stacked rooms line up seamlessly (see DungeonManager).
## Extra tiles can still be painted by hand after the generated layout.
## Around the room a thick ring of solid rock is painted on a child layer ("Backdrop") drawn below
## all room tiles, so the screen never shows black void, even where neighbouring rooms overlap.

const SOURCE_ID := 0
## World size of one tile: 32 px art drawn at SpriteStrip.PIXEL_SCALE.
const TILE_WORLD := 64.0

const FLOOR_TILES: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
const WALL_TOP := Vector2i(4, 0)
const WALL_FRONT := Vector2i(5, 0)
const WALL_FRONT_ALT := Vector2i(6, 0)
const WALL_N := Vector2i(0, 1)
const WALL_E := Vector2i(1, 1)
const WALL_S := Vector2i(2, 1)
const WALL_W := Vector2i(3, 1)
const OUTER_NE := Vector2i(4, 1)
const OUTER_NW := Vector2i(5, 1)
const INNER_NE := Vector2i(0, 2)
const INNER_NW := Vector2i(1, 2)
const INNER_SE := Vector2i(2, 2)
const INNER_SW := Vector2i(3, 2)
const PILLAR := Vector2i(6, 2)
## Rock ring around the painted room (tiles). Covers the 1280x720 view plus camera tilt/shake.
const BACKDROP_MARGIN := Vector2i(14, 10)
const BACKDROP_NAME := "Backdrop"
const ROCK_SHADER: Shader = preload("res://components/visual/rock_fill.gdshader")
## Widest abyss gap (tiles) a dash crosses: dash reach 90 px vs. 64 px tiles (D-086).
const MAX_DASH_GAP := 1

@export var room_size := Vector2i(15, 9):
	set(value):
		room_size = value
		_queue_paint()
@export var entrance_x := 7:
	set(value):
		entrance_x = value
		_queue_paint()
@export var exit_x := 7:
	set(value):
		exit_x = value
		_queue_paint()
## Single blocking tiles inside the room.
@export var pillar_tiles: Array[Vector2i] = []:
	set(value):
		pillar_tiles = value
		_queue_paint()
@export var floor_seed := 1:
	set(value):
		floor_seed = value
		_queue_paint()

var _paint_queued := false
var _backdrop: TileMapLayer = null


func _ready() -> void:
	# Runtime only, so saving a room template in the editor never embeds the material.
	if material == null and not Engine.is_editor_hint():
		var rock := ShaderMaterial.new()
		rock.shader = ROCK_SHADER
		material = rock
	paint()


static func tile_to_local(tile: Vector2i) -> Vector2:
	return Vector2(tile) * TILE_WORLD


static func tile_center(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * TILE_WORLD


func get_floor_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(room_size) * TILE_WORLD)


static func local_to_tile(local: Vector2) -> Vector2i:
	return Vector2i((local / TILE_WORLD).floor())


## Floor tile just inside the entrance / exit door.
func get_entrance_inside_tile() -> Vector2i:
	return Vector2i(entrance_x, room_size.y - 1)


func get_exit_inside_tile() -> Vector2i:
	return Vector2i(exit_x, 0)


# --- Walkability (D-086). Pure layout data from the exported parameters, no painted cells needed,
# so it also works on templates that are not in the tree (unit tests, generator checks). ---

## Tiles inside the room that block walking. Today: pillars. A3 adds inner walls (wall_rects).
func get_blocked_tiles() -> Array[Vector2i]:
	var blocked: Array[Vector2i] = []
	blocked.assign(pillar_tiles)
	return blocked


## Abyss tiles: not walkable, crossable by a dash when at most MAX_DASH_GAP wide (D-086).
## Empty until A4 adds pit_rects / bridge_rects.
func get_pit_tiles() -> Array[Vector2i]:
	var pits: Array[Vector2i] = []
	return pits


## Floor of the room plus both door corridors, without blocked and pit tiles.
func get_walkable_tiles() -> Dictionary[Vector2i, bool]:
	var walkable: Dictionary[Vector2i, bool] = {}
	for y in room_size.y:
		for x in room_size.x:
			walkable[Vector2i(x, y)] = true
	for y in [-1, -2, -3]:
		walkable[Vector2i(exit_x, y)] = true
	for y in [room_size.y, room_size.y + 1]:
		walkable[Vector2i(entrance_x, y)] = true
	for tile in get_blocked_tiles():
		walkable.erase(tile)
	for tile in get_pit_tiles():
		walkable.erase(tile)
	return walkable


func is_walkable(tile: Vector2i) -> bool:
	return get_walkable_tiles().has(tile)


## Tiles reachable from the entrance by walking, plus dashing over up to max_gap pit tiles.
func get_reachable_tiles(max_gap: int = MAX_DASH_GAP) ->Dictionary[Vector2i, bool]:
	var pits: Dictionary[Vector2i, bool] = {}
	for tile in get_pit_tiles():
		pits[tile] = true
	return flood_fill(get_walkable_tiles(), pits, get_entrance_inside_tile(), max_gap)


## 4-neighbour flood fill over walkable tiles. A straight jump over 1..max_gap pit tiles onto a
## walkable tile counts as a step (dash over an abyss, D-086); walls can never be jumped.
static func flood_fill(walkable: Dictionary[Vector2i, bool], pits: Dictionary[Vector2i, bool], start: Vector2i, max_gap := 0) -> Dictionary[Vector2i, bool]:
	var reached: Dictionary[Vector2i, bool] = {}
	if not walkable.has(start):
		return reached
	reached[start] = true
	var open: Array[Vector2i] = [start]
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	while not open.is_empty():
		var tile: Vector2i = open.pop_back()
		for direction in directions:
			var next := tile + direction
			var gap := 0
			while pits.has(next) and gap < max_gap:
				next += direction
				gap += 1
			if walkable.has(next) and not reached.has(next):
				reached[next] = true
				open.append(next)
	return reached


## Tile rectangle covered by the rock backdrop (includes the room itself).
func get_backdrop_rect() -> Rect2i:
	var inner := _get_painted_rect()
	return inner.grow_individual(BACKDROP_MARGIN.x, BACKDROP_MARGIN.y, BACKDROP_MARGIN.x, BACKDROP_MARGIN.y)


## Swaps the tileset (biome art). All tilesets share the same atlas layout.
func use_tileset(new_tileset: TileSet) -> void:
	tile_set = new_tileset
	if _backdrop != null:
		_backdrop.tile_set = new_tileset


func get_backdrop() -> TileMapLayer:
	return _backdrop


func paint() -> void:
	_paint_queued = false
	clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_seed
	var w := room_size.x
	var h := room_size.y

	for y in range(-3, h + 2):
		for x in range(-2, w + 2):
			_put_tile(Vector2i(x, y), WALL_TOP)
	for y in h:
		for x in w:
			_put_tile(Vector2i(x, y), _random_floor(rng))
	for x in w:
		_put_tile(Vector2i(x, -2), WALL_S)
		_put_tile(Vector2i(x, -1), WALL_FRONT_ALT if rng.randf() < 0.25 else WALL_FRONT)
		_put_tile(Vector2i(x, h), WALL_N)
	for y in range(-1, h):
		_put_tile(Vector2i(-1, y), WALL_E)
		_put_tile(Vector2i(w, y), WALL_W)
	_put_tile(Vector2i(-1, -2), INNER_SE)
	_put_tile(Vector2i(w, -2), INNER_SW)
	_put_tile(Vector2i(-1, h), INNER_NE)
	_put_tile(Vector2i(w, h), INNER_NW)

	# Exit passage to the north.
	for y in [-1, -2, -3]:
		_put_tile(Vector2i(exit_x, y), _random_floor(rng))
	for y in [-2, -3]:
		_put_tile(Vector2i(exit_x - 1, y), WALL_E)
		_put_tile(Vector2i(exit_x + 1, y), WALL_W)
	# Entrance passage from the south.
	for y in [h, h + 1]:
		_put_tile(Vector2i(entrance_x, y), _random_floor(rng))
	_put_tile(Vector2i(entrance_x - 1, h), OUTER_NE)
	_put_tile(Vector2i(entrance_x + 1, h), OUTER_NW)
	_put_tile(Vector2i(entrance_x - 1, h + 1), WALL_E)
	_put_tile(Vector2i(entrance_x + 1, h + 1), WALL_W)

	for tile in pillar_tiles:
		_put_tile(tile, PILLAR)
	_paint_backdrop()


## Tiles painted by paint() on this layer: floor plus the wall ring.
func _get_painted_rect() -> Rect2i:
	return Rect2i(-2, -3, room_size.x + 4, room_size.y + 5)


## Solid rock around the room on a child layer below every room's tiles (also below neighbours,
## so their floors and corridors stay intact). No collision: the room walls already block.
func _paint_backdrop() -> void:
	if _backdrop == null:
		_backdrop = TileMapLayer.new()
		_backdrop.name = BACKDROP_NAME
		_backdrop.z_index = -1
		_backdrop.collision_enabled = false
		_backdrop.navigation_enabled = false
		_backdrop.occlusion_enabled = false
		_backdrop.use_parent_material = true
		add_child(_backdrop, false, Node.INTERNAL_MODE_FRONT)
	_backdrop.tile_set = tile_set
	_backdrop.clear()
	var inner := _get_painted_rect()
	var outer := get_backdrop_rect()
	for y in range(outer.position.y, outer.end.y):
		for x in range(outer.position.x, outer.end.x):
			var tile := Vector2i(x, y)
			if not inner.has_point(tile):
				_backdrop.set_cell(tile, SOURCE_ID, WALL_TOP)


func _put_tile(tile: Vector2i, atlas: Vector2i) -> void:
	set_cell(tile, SOURCE_ID, atlas)


func _random_floor(rng: RandomNumberGenerator) -> Vector2i:
	# Mostly plain floor, some cracked/mossy variants.
	var roll := rng.randf()
	if roll < 0.45:
		return FLOOR_TILES[0]
	if roll < 0.85:
		return FLOOR_TILES[1]
	if roll < 0.95:
		return FLOOR_TILES[2]
	return FLOOR_TILES[3]


func _queue_paint() -> void:
	if not is_inside_tree() or _paint_queued:
		return
	_paint_queued = true
	paint.call_deferred()

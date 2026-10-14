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
## A room between two biomes (campfire, A6) gets a second look on top ("BiomeBlend" layers): the
## same cells in the next biome's tileset, shown through a soft dithered mask from the entrance
## (old biome) to the exit (new biome), see set_biome_blend().
## All walls, outer and inner, come from one floor mask (get_floor_mask(), SPRITES_V6, D-110): every
## tile that is not floor is solid; a solid tile with floor right below it is a brick front (one row,
## always under a crown), every other solid tile is a crown with a light edge where it borders floor
## or a front, plain rock where it is enclosed (WallAutotile). Inner walls (wall_rects) and pillars
## just take tiles out of the floor: cut-out corners of a shape look like the rock around the room,
## a pillar is a crown on its tile plus the front on the tile below. wall_rects therefore hold crown
## and front; every wall above floor is at least two tiles tall (WallAutotile.is_valid_mass).
## Abysses (A4, D-086): pit_rects cut holes into the floor, bridge_rects lay walkable bridges over
## them; add_pit_tiles() adds holes at runtime (ingredient holes, crumbling floor). A pit stays floor
## in the floor mask (walls get their edge towards it), is drawn with the biome's abyss pieces
## (AbyssAutotile), carries no navigation and is solid on the pit physics layer only: enemies are
## blocked, the player falls (PlayerFall), projectiles fly over it. A bridge cell shows the bridge
## art on this layer and the abyss below it on a child layer ("AbyssUnder").

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
## Old single-tile pillar; only drawn if a tileset cannot get the wall pieces (no ground atlas).
const PILLAR := Vector2i(6, 2)
## Atlas source of the wall pieces, added to the tileset at runtime (WallAutotile).
const SOURCE_WALL := WallAutotile.SOURCE_ID
## Share of plain brick fronts drawn with the second brick pattern (like the old north wall).
const FRONT_ALT_CHANCE := 0.25
## Rock ring around the painted room (tiles). Covers the 1280x720 view plus camera tilt/shake.
const BACKDROP_MARGIN := Vector2i(14, 10)
const BACKDROP_NAME := "Backdrop"
const ROCK_SHADER: Shader = preload("res://components/visual/rock_fill.gdshader")
const BLEND_SHADER: Shader = preload("res://dungeon/rooms/campfire/biome_blend.gdshader")
const BLEND_NAME := "BiomeBlend"
const BLEND_BACKDROP_NAME := "BiomeBlendBackdrop"
## Widest abyss gap (tiles) a dash crosses: dash reach 90 px vs. 64 px tiles (D-086).
const MAX_DASH_GAP := 1
## Atlas sources of the abyss (tools/build_tilesets.gd): delivered pieces, bridges, combined pieces.
const SOURCE_ABYSS := 2
const SOURCE_BRIDGE := 3
const SOURCE_ABYSS_PIECES := AbyssAutotile.SOURCE_ID
## Bridge art (bridge_tiles.png): plank runs and the west / north end; east and south are flipped.
const BRIDGE_H := Vector2i(0, 0)
const BRIDGE_V := Vector2i(1, 0)
const BRIDGE_END_W := Vector2i(2, 0)
const BRIDGE_END_N := Vector2i(3, 0)
const ABYSS_UNDER_NAME := "AbyssUnder"
## Rising mist over the deep parts of an abyss (abyss_mist_4f, SPRITES_V3): one per this many
## enclosed pit tiles, at most MIST_MAX per room. Optics only. TESTWERTE
const MIST_TEXTURE: Texture2D = preload("res://art/environment/props/abyss_mist_4f.png")
const MIST_EVERY := 5
const MIST_MAX := 8
const MIST_FPS := 3.0
const MIST_ALPHA := 0.55

## Emitted after pits were added or removed at runtime (crumbling floor, holes): the changed tiles.
signal pits_changed(tiles: Array[Vector2i])

@export var room_size := Vector2i(15, 9):
	set(value):
		room_size = value
		_pits_dirty = true
		_queue_paint()
@export var entrance_x := 7:
	set(value):
		entrance_x = value
		_queue_paint()
@export var exit_x := 7:
	set(value):
		exit_x = value
		_queue_paint()
## Pillars: the crown tile; the front on the tile below belongs to it (two tiles solid).
@export var pillar_tiles: Array[Vector2i] = []:
	set(value):
		pillar_tiles = value
		_pits_dirty = true
		_queue_paint()
## Inner walls in floor tiles (position = top-left tile, size in tiles), crown and front included.
## Overlaps are fine.
@export var wall_rects: Array[Rect2i] = []:
	set(value):
		wall_rects = value
		_pits_dirty = true
		_queue_paint()
@export var floor_seed := 1:
	set(value):
		floor_seed = value
		_queue_paint()
## Abyss areas in floor tiles (position = top-left tile, size in tiles); overlaps are fine. Walls win.
@export var pit_rects: Array[Rect2i] = []:
	set(value):
		pit_rects = value
		_pits_dirty = true
		_queue_paint()
## Bridges over the abyss in floor tiles; only their tiles inside a pit count (walkable).
@export var bridge_rects: Array[Rect2i] = []:
	set(value):
		bridge_rects = value
		_pits_dirty = true
		_queue_paint()

var _paint_queued := false
var _backdrop: TileMapLayer = null
## Rows of rock above the room (BACKDROP_MARGIN.y by default). Rooms are y-sorted, so a room's rock
## covers the rock of the room north of it; the room before a campfire trims it to 0, so the
## campfire's own blended rock stays visible (DungeonManager).
var _backdrop_north_rows := BACKDROP_MARGIN.y
var _blend_layer: TileMapLayer = null
var _blend_backdrop: TileMapLayer = null
var _blend_material: ShaderMaterial = null
## Tile rows (y, may be fractional) where the blend mask is 0 (old biome) and 1 (new biome).
var _blend_rows := Vector2.ZERO
## Floor tiles under solid props (crates, barrels, rubble): no navigation polygon, so enemies path
## around them instead of pushing against them. Collision stays with the prop.
var _navigation_blocked: Dictionary[Vector2i, bool] = {}
## Pits added at runtime (true) on top of pit_rects.
var _runtime_pits: Dictionary[Vector2i, bool] = {}
## Cached pit and bridge tiles (rebuilt when the rects or the runtime pits change).
var _pit_set: Dictionary[Vector2i, bool] = {}
var _bridge_set: Dictionary[Vector2i, bool] = {}
var _pits_dirty := true
## Floor piece painted on each floor tile (also under pits), so a pit that closes again shows the
## same floor and runtime pits never shift the floor pattern.
var _floor_cells: Dictionary[Vector2i, Vector2i] = {}
var _abyss_under: TileMapLayer = null
var _mist: Node2D = null


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

## Tiles inside the room that block walking: every wall tile (inner walls, pillars, their fronts).
func get_blocked_tiles() -> Array[Vector2i]:
	return get_wall_tiles()


## Floor tiles covered by walls (clipped to the floor), without duplicates.
func get_wall_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	tiles.assign(get_wall_mass().keys())
	return tiles


## All wall tiles as a set: wall_rects plus every pillar with the front below it.
func get_wall_mass() -> Dictionary[Vector2i, bool]:
	var mass: Dictionary[Vector2i, bool] = {}
	var floor_rect := Rect2i(Vector2i.ZERO, room_size)
	for rect in wall_rects:
		var clipped := rect.intersection(floor_rect)
		for y in range(clipped.position.y, clipped.end.y):
			for x in range(clipped.position.x, clipped.end.x):
				mass[Vector2i(x, y)] = true
	for pillar in pillar_tiles:
		for tile: Vector2i in [pillar, pillar + Vector2i.DOWN]:
			if floor_rect.has_point(tile):
				mass[tile] = true
	return mass


## Adds inner walls at runtime (ingredient scatter) and repaints right away, so collision and the
## navigation of the layer follow before any enemy moves.
func add_wall_rects(rects: Array[Rect2i]) -> void:
	if rects.is_empty():
		return
	var combined: Array[Rect2i] = wall_rects.duplicate()
	combined.append_array(rects)
	wall_rects = combined
	paint()


## Takes the navigation off a floor tile while a solid prop stands on it (or gives it back).
func set_navigation_blocked(tile: Vector2i, blocked: bool) -> void:
	if blocked == is_navigation_blocked(tile):
		return
	# A freed tile stays in the runtime update (false): Godot keeps the changed tile data of a cell
	# that drops out of it, so the tile gets its own polygon back explicitly.
	_navigation_blocked[tile] = blocked
	notify_runtime_tile_data_update()


func is_navigation_blocked(tile: Vector2i) -> bool:
	return _navigation_blocked.get(tile, false)


func _use_tile_data_runtime_update(coords: Vector2i) -> bool:
	return _navigation_blocked.has(coords)


func _tile_data_runtime_update(coords: Vector2i, tile_data: TileData) -> void:
	if tile_set == null or tile_set.get_navigation_layers_count() == 0:
		return
	var polygon: NavigationPolygon = null
	if not _navigation_blocked[coords]:
		var source := tile_set.get_source(get_cell_source_id(coords)) as TileSetAtlasSource
		if source != null:
			var original := source.get_tile_data(get_cell_atlas_coords(coords), get_cell_alternative_tile(coords))
			polygon = original.get_navigation_polygon(0) if original != null else null
	tile_data.set_navigation_polygon(0, polygon)


## Abyss tiles: not walkable, crossable by a dash when at most MAX_DASH_GAP wide (D-086).
## pit_rects and runtime pits inside the floor, without bridges and walls; sorted (y, then x).
func get_pit_tiles() -> Array[Vector2i]:
	_update_pit_sets()
	var pits: Array[Vector2i] = []
	pits.assign(_pit_set.keys())
	pits.sort_custom(_tile_order)
	return pits


## Bridge tiles: inside a pit rect, walkable (navigation), no pit collision.
func get_bridge_tiles() -> Array[Vector2i]:
	_update_pit_sets()
	var bridges: Array[Vector2i] = []
	bridges.assign(_bridge_set.keys())
	bridges.sort_custom(_tile_order)
	return bridges


func is_pit(tile: Vector2i) -> bool:
	_update_pit_sets()
	return _pit_set.has(tile)


func is_bridge(tile: Vector2i) -> bool:
	_update_pit_sets()
	return _bridge_set.has(tile)


func has_pits() -> bool:
	_update_pit_sets()
	return not _pit_set.is_empty()


## Is the room-local point (pixels of the room, like RoomTiles.tile_center) over a pit tile?
## Logical answer from the layout; the physics answer for any world point is PitProbe.
func is_pit_at_local(local: Vector2) -> bool:
	return is_pit(local_to_tile(local))


## Turns floor tiles into pits at runtime (holes, crumbling floor) and repaints them and their
## neighbours right away, so collision and navigation follow. Walls, bridges and tiles outside the
## floor are skipped.
func add_pit_tiles(tiles: Array[Vector2i]) -> void:
	var changed: Array[Vector2i] = []
	var floor_rect := Rect2i(Vector2i.ZERO, room_size)
	var mass := get_wall_mass()
	for tile in tiles:
		if floor_rect.has_point(tile) and not mass.has(tile) and not is_pit(tile) and not is_bridge(tile):
			_runtime_pits[tile] = true
			_pits_dirty = true
			changed.append(tile)
	_apply_pit_change(changed)


## Closes runtime pits again (crumbling floor that grows back). pit_rects stay.
func remove_pit_tiles(tiles: Array[Vector2i]) -> void:
	var changed: Array[Vector2i] = []
	for tile in tiles:
		if _runtime_pits.has(tile):
			_runtime_pits.erase(tile)
			_pits_dirty = true
			changed.append(tile)
	_apply_pit_change(changed)


func get_runtime_pit_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	tiles.assign(_runtime_pits.keys())
	tiles.sort_custom(_tile_order)
	return tiles


func _apply_pit_change(changed: Array[Vector2i]) -> void:
	if changed.is_empty():
		return
	if not get_used_cells().is_empty():
		var area: Dictionary[Vector2i, bool] = {}
		for tile in changed:
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					area[tile + Vector2i(dx, dy)] = true
		var floor_mask := get_floor_mask()
		for tile: Vector2i in area:
			if floor_mask.has(tile):
				_paint_floor_cell(tile)
		_paint_mist()
	pits_changed.emit(changed)


func _update_pit_sets() -> void:
	if not _pits_dirty:
		return
	_pits_dirty = false
	_pit_set.clear()
	_bridge_set.clear()
	var floor_rect := Rect2i(Vector2i.ZERO, room_size)
	var mass := get_wall_mass()
	for rect in pit_rects:
		var clipped := rect.intersection(floor_rect)
		for y in range(clipped.position.y, clipped.end.y):
			for x in range(clipped.position.x, clipped.end.x):
				var tile := Vector2i(x, y)
				if not mass.has(tile):
					_pit_set[tile] = true
	for rect in bridge_rects:
		var clipped := rect.intersection(floor_rect)
		for y in range(clipped.position.y, clipped.end.y):
			for x in range(clipped.position.x, clipped.end.x):
				var tile := Vector2i(x, y)
				if _pit_set.has(tile):
					_pit_set.erase(tile)
					_bridge_set[tile] = true
	for tile in _runtime_pits:
		if not mass.has(tile) and not _bridge_set.has(tile):
			_pit_set[tile] = true


static func _tile_order(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


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
	return inner.grow_individual(BACKDROP_MARGIN.x, _backdrop_north_rows, BACKDROP_MARGIN.x, BACKDROP_MARGIN.y)


## Rows of rock above the room; repaints the backdrop if it changed.
func set_backdrop_north_rows(rows: int) -> void:
	rows = clampi(rows, 0, BACKDROP_MARGIN.y)
	if rows == _backdrop_north_rows:
		return
	_backdrop_north_rows = rows
	if _backdrop != null:
		_paint_backdrop()


func get_backdrop_north_rows() -> int:
	return _backdrop_north_rows


# --- Biome blend (room between two biomes, A6) ---

## Shows a second biome look over this one: next_tileset tinted with next_tint appears through a
## dithered mask that is 0 at tile row from_row and 1 at to_row (rows may be fractional; north =
## smaller y). Collision and navigation stay on this layer, the blend layers only draw. A modulate
## on this layer also tints the blend layers (children). Call after the room is in the tree;
## follows later moves of the room.
func set_biome_blend(next_tileset: TileSet, next_tint: Color, from_row: float, to_row: float) -> void:
	_blend_rows = Vector2(from_row, to_row)
	if _blend_material == null:
		_blend_material = ShaderMaterial.new()
		_blend_material.shader = BLEND_SHADER
	WallAutotile.ensure_source(next_tileset)
	_blend_layer = _make_blend_layer(_blend_layer, BLEND_NAME, 0)
	_blend_backdrop = _make_blend_layer(_blend_backdrop, BLEND_BACKDROP_NAME, -1)
	for layer: TileMapLayer in [_blend_layer, _blend_backdrop]:
		layer.tile_set = next_tileset if next_tileset != null else tile_set
		layer.modulate = next_tint
	_copy_cells_to_blend()
	set_notify_transform(true)
	_update_blend_range()


func has_biome_blend() -> bool:
	return _blend_layer != null


func get_blend_layer() -> TileMapLayer:
	return _blend_layer


## Blend rows (x = 0 / old biome, y = 1 / new biome), Vector2.ZERO without a blend.
func get_blend_rows() -> Vector2:
	return _blend_rows


## Share of the new biome at a local y of the room (0..1), without the noise of the shader.
## Same straight ramp as the mask in biome_blend.gdshader; used for light and particle colours.
func get_blend_progress(local_y: float) -> float:
	if not has_biome_blend():
		return 0.0
	var from_y := _blend_rows.x * TILE_WORLD
	var to_y := _blend_rows.y * TILE_WORLD
	if is_equal_approx(from_y, to_y):
		return 1.0
	return clampf((local_y - position.y - from_y) / (to_y - from_y), 0.0, 1.0)


func _make_blend_layer(layer: TileMapLayer, layer_name: String, layer_z: int) -> TileMapLayer:
	if layer != null:
		return layer
	layer = TileMapLayer.new()
	layer.name = layer_name
	layer.z_index = layer_z
	# Drawing only: this layer already collides, carries the navigation and occludes.
	layer.collision_enabled = false
	layer.navigation_enabled = false
	layer.occlusion_enabled = false
	layer.material = _blend_material
	# Added after the Backdrop, so at the same z it draws above the old biome's rock ring.
	add_child(layer, false, Node.INTERNAL_MODE_FRONT)
	return layer


func _copy_cells_to_blend() -> void:
	if _blend_layer == null:
		return
	_blend_layer.clear()
	for cell in get_used_cells():
		_blend_layer.set_cell(cell, get_cell_source_id(cell), get_cell_atlas_coords(cell))
	_blend_backdrop.clear()
	if _backdrop != null:
		for cell in _backdrop.get_used_cells():
			_blend_backdrop.set_cell(cell, SOURCE_ID, _backdrop.get_cell_atlas_coords(cell))


## The shader works in world space (TileMapLayer quadrants have their own transforms).
func _update_blend_range() -> void:
	if _blend_material == null:
		return
	var from_world := to_global(Vector2(0.0, _blend_rows.x * TILE_WORLD / scale.y))
	var to_world := to_global(Vector2(0.0, _blend_rows.y * TILE_WORLD / scale.y))
	_blend_material.set_shader_parameter(&"blend_from_y", from_world.y)
	_blend_material.set_shader_parameter(&"blend_to_y", to_world.y)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_update_blend_range()


## Swaps the tileset (biome art). All tilesets share the same atlas layout.
func use_tileset(new_tileset: TileSet) -> void:
	# The wall pieces of the new biome must exist before the cells point at them.
	WallAutotile.ensure_source(new_tileset)
	AbyssAutotile.ensure_source(new_tileset)
	tile_set = new_tileset
	if _backdrop != null:
		_backdrop.tile_set = new_tileset
	if _abyss_under != null:
		_abyss_under.tile_set = new_tileset


func get_backdrop() -> TileMapLayer:
	return _backdrop


func paint() -> void:
	_paint_queued = false
	clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_seed
	_floor_cells.clear()
	if _abyss_under != null:
		_abyss_under.clear()
	if WallAutotile.ensure_source(tile_set):
		AbyssAutotile.ensure_source(tile_set)
		_paint_from_mask(rng)
	else:
		_paint_legacy(rng)
	_paint_backdrop()
	_paint_mist()


## Floor of the room plus both door corridors, without walls and pillars. Abyss tiles (A4) stay in
## the mask: they are holes in the floor, not walls.
func get_floor_mask() -> Dictionary[Vector2i, bool]:
	var floor_mask: Dictionary[Vector2i, bool] = {}
	for y in room_size.y:
		for x in room_size.x:
			floor_mask[Vector2i(x, y)] = true
	for y in [-1, -2, -3]:
		floor_mask[Vector2i(exit_x, y)] = true
	for y in [room_size.y, room_size.y + 1]:
		floor_mask[Vector2i(entrance_x, y)] = true
	for tile: Vector2i in get_wall_mass():
		floor_mask.erase(tile)
	return floor_mask


## One rule for every wall (WallAutotile.cell_for_floor): fronts only right above floor, crowns
## with edges, enclosed rock as the plain wall-top tile (the rock shader turns it into stones).
func _paint_from_mask(rng: RandomNumberGenerator) -> void:
	var floor_mask := get_floor_mask()
	var rect := _get_painted_rect()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var tile := Vector2i(x, y)
			if floor_mask.has(tile):
				# Drawn for every floor tile, pit or not, so the floor pattern never depends on pits.
				_floor_cells[tile] = _random_floor(rng)
				_paint_floor_cell(tile)
				continue
			var piece := WallAutotile.cell_for_floor(tile, floor_mask)
			if piece == WallAutotile.ROCK:
				_put_tile(tile, WALL_TOP)
			elif piece == WallAutotile.front_coords(WallAutotile.Front.MIDDLE) and rng.randf() < FRONT_ALT_CHANCE:
				set_cell(tile, SOURCE_WALL, WallAutotile.front_coords(WallAutotile.Front.MIDDLE_ALT))
			else:
				set_cell(tile, SOURCE_WALL, piece)


## Editor view (no generated pieces there): the hand-drawn outer wall, walls as pillar tiles.
func _paint_legacy(rng: RandomNumberGenerator) -> void:
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
	for tile: Vector2i in get_wall_mass():
		_put_tile(tile, PILLAR)
	for tile in get_pit_tiles():
		set_cell(tile, SOURCE_ABYSS, AbyssAutotile.ART_VOID[0])
	for tile in get_bridge_tiles():
		set_cell(tile, SOURCE_BRIDGE, BRIDGE_H)


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
	if _blend_backdrop != null:
		_copy_cells_to_blend()


## Floor tile of the mask: abyss piece, bridge (with the abyss below it) or the remembered floor.
func _paint_floor_cell(tile: Vector2i) -> void:
	if is_pit(tile):
		_set_abyss_cell(self, tile)
		_set_under_cell(tile, false)
	elif is_bridge(tile):
		var piece := _bridge_piece(tile)
		set_cell(tile, SOURCE_BRIDGE, piece[0], piece[1])
		_set_under_cell(tile, true)
	else:
		_put_tile(tile, _floor_cells.get(tile, FLOOR_TILES[0]))
		_set_under_cell(tile, false)


## Abyss piece of a pit tile on layer (bridges count as abyss for the rim).
func _set_abyss_cell(layer: TileMapLayer, tile: Vector2i) -> void:
	var piece := AbyssAutotile.cell_for(tile, _is_abyss)
	if piece == AbyssAutotile.VOID or layer.tile_set == null or not layer.tile_set.has_source(SOURCE_ABYSS_PIECES):
		var variants := AbyssAutotile.ART_VOID
		layer.set_cell(tile, SOURCE_ABYSS, variants[absi(hash(tile)) % variants.size()])
	else:
		layer.set_cell(tile, SOURCE_ABYSS_PIECES, piece)


func _is_abyss(tile: Vector2i) -> bool:
	return is_pit(tile) or is_bridge(tile)


## The abyss under a bridge, on a draw-only child layer behind this one.
func _set_under_cell(tile: Vector2i, bridge: bool) -> void:
	if not bridge:
		if _abyss_under != null:
			_abyss_under.erase_cell(tile)
		return
	if _abyss_under == null:
		_abyss_under = TileMapLayer.new()
		_abyss_under.name = ABYSS_UNDER_NAME
		_abyss_under.show_behind_parent = true
		_abyss_under.collision_enabled = false
		_abyss_under.navigation_enabled = false
		_abyss_under.occlusion_enabled = false
		_abyss_under.use_parent_material = true
		add_child(_abyss_under, false, Node.INTERNAL_MODE_FRONT)
	_abyss_under.tile_set = tile_set
	_set_abyss_cell(_abyss_under, tile)


func get_abyss_under() -> TileMapLayer:
	return _abyss_under


## Bridge art of a bridge tile: [atlas coords, alternative with flip flags]. Runs along the rect
## the tile belongs to (wider than tall = west-east); the ends next to solid ground get the end
## pieces (east and south ends flipped).
func _bridge_piece(tile: Vector2i) -> Array:
	if _is_horizontal_bridge(tile):
		var west_end := not _is_abyss(tile + Vector2i.LEFT)
		var east_end := not _is_abyss(tile + Vector2i.RIGHT)
		if west_end and not east_end:
			return [BRIDGE_END_W, 0]
		if east_end and not west_end:
			return [BRIDGE_END_W, TileSetAtlasSource.TRANSFORM_FLIP_H]
		return [BRIDGE_H, 0]
	var north_end := not _is_abyss(tile + Vector2i.UP)
	var south_end := not _is_abyss(tile + Vector2i.DOWN)
	if north_end and not south_end:
		return [BRIDGE_END_N, 0]
	if south_end and not north_end:
		return [BRIDGE_END_N, TileSetAtlasSource.TRANSFORM_FLIP_V]
	return [BRIDGE_V, 0]


func _is_horizontal_bridge(tile: Vector2i) -> bool:
	for rect in bridge_rects:
		if rect.has_point(tile) and rect.size != Vector2i.ONE:
			return rect.size.x > rect.size.y
	# A single bridge tile runs between the two sides with solid ground.
	return not _is_abyss(tile + Vector2i.LEFT) and not _is_abyss(tile + Vector2i.RIGHT)


## Slow mist over enclosed pit tiles (optics only; positions from floor_seed, no dungeon RNG).
func _paint_mist() -> void:
	if _mist != null:
		for child in _mist.get_children():
			child.queue_free()
	if Engine.is_editor_hint() or not has_pits():
		return
	var deep: Array[Vector2i] = []
	for tile in get_pit_tiles():
		if _is_abyss(tile + Vector2i.UP) and _is_abyss(tile + Vector2i.DOWN) and _is_abyss(tile + Vector2i.LEFT) and _is_abyss(tile + Vector2i.RIGHT):
			deep.append(tile)
	var count := mini(MIST_MAX, deep.size() / MIST_EVERY)
	if count <= 0:
		return
	if _mist == null:
		_mist = Node2D.new()
		_mist.name = "AbyssMist"
		add_child(_mist, false, Node.INTERNAL_MODE_BACK)
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_seed * 31 + 7
	# Layer space: this layer is drawn at SpriteStrip.PIXEL_SCALE, one tile = one art tile.
	var art_tile := float(tile_set.tile_size.x) if tile_set != null else TILE_WORLD / SpriteStrip.PIXEL_SCALE
	for i in count:
		var tile: Vector2i = deep[rng.randi_range(0, deep.size() - 1)]
		var mist := AnimatedProp.new()
		mist.frame_size = Vector2i(32, 32)
		mist.fps = MIST_FPS
		mist.pivot = Vector2(16, 16)
		mist.strip = MIST_TEXTURE
		mist.material = additive
		mist.modulate.a = MIST_ALPHA
		mist.position = (Vector2(tile) + Vector2(0.5, 0.5)) * art_tile
		_mist.add_child(mist)
		mist.frame = rng.randi_range(0, 3)


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

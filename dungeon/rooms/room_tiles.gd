@tool
class_name RoomTiles
extends TileMapLayer
## Paints a rectangular dungeon room from a few parameters, in the editor and at runtime.
## Tile (0, 0) is the top-left floor tile. The north wall occupies rows -2 (top) and -1 (front),
## the south wall row room_size.y. Doors (A10, KONZEPT_RAEUME §7.1) sit in any wall: entrance_side /
## exit_side name the wall, entrance_x / exit_x the place along it (x on the north and south wall,
## y on the west and east wall). A door corridor runs from the door tile out to the edge of the
## painted ring: north rows -1..-3, south rows h..h+1, west columns -1..-2, east columns w..w+1; the
## entrance corridor can be longer (entrance_corridor_extra), so a room placed further away still
## joins. The last corridor tile of an exit and of the next room's entrance are the same world tile
## (see DungeonManager / ExitRules). A branch room (D-105) has a second exit (branch_exit).
## door_slots lists the places a template allows doors at (generator); without it only the
## template's own entrance (south) and exit (north) are allowed.
## A secret niche (A10, niche_rect) lies behind a wall front: in the rock ring behind the north
## wall (row -3, with a bump of rock painted above it) or cut into a thick inner wall;
## open_wall_tiles() turns the crown and the front in front of it into floor when the wall breaks.
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
## art on this layer and the abyss below it on a child layer ("AbyssUnder"). The north edge of every
## abyss (floor or wall right above the pit) gets a rock face: in terrain rooms the face sinks into the
## void below the abyss's own rim (AbyssFace, playtest 15.10.2026), else abyss_cliff_<biome> (R1).
## Room plans (R1, D-120, tools/generate_room_templates.py) add: shallow water (water_rects, floor
## with a slowing overlay, ShallowWater), moss tiles around drips, the places of the cracked secret
## wall (secret_cracks, plan cell 'q') and the wall fronts holding a fixture (front_fixtures: torch,
## niche, gate, rift - nothing else goes there). A secret niche is drawn as plain rock until its
## wall breaks, so it never shows as a box in the rock.
## Walls as one 47-piece terrain (M1, RockTerrain): the same floor mask, but every border between
## floor and solid gets the same edge, corners included. This layer keeps collision and navigation
## (floor cells, an invisible solid tile on every solid cell); a draw-only child layer ("Rock")
## draws the pieces (composited over the floor), the backdrop below every room the enclosed rock, so
## no room's plain rock covers a neighbour's edge. rock_style picks the look: BLOB = cave rock (soft
## set, seamless floor), WALL = masonry (the biome's set with brick fronts on its tile floor). Floor
## zones (zone_cells: slab, cobble, dirt, rubble with frayed edges) and scatter overlays
## (overlay_cells) lie on two draw-only child layers between floor and rock; the generator fixes both
## per template (no dungeon RNG). Puddle overlays are drawn as water like the pools (WaterArt). Solid
## cells collide with their outer corners rounded like the rock (RockTerrain.solid_corners). A lip
## (rock with floor north of it, RockTerrain.is_lip) collides only from RockTerrain.LIP_WALK down and
## is drawn a second time as a y-sorted sprite in the room ("RockLips"), sorted at the foot of its
## block: a character that walks a bit behind it is hidden by it, one in front of the block is not
## (playtest 15.10.2026, note 17). plateau_tiles, ladder_tiles and stair_tiles only carry the plan's
## height markers for M3; until then they are rock. Without the terrain art (editor, old tilesets)
## the walls fall back to the WallAutotile pieces above.

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
## The combined pieces with round rim corners (AbyssRims, playtest 15.10.2026); AbyssAutotile's own
## source stays the fallback.
const SOURCE_ABYSS_PIECES := AbyssRims.SOURCE_ID
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
## Rock face under the north edge of an abyss (SPRITES_V7, 4 x 1: left, middle, right, single).
const CLIFF_ART_PATH := "res://art/environment/tiles/abyss_cliff_%s.png"
const CLIFF_NAME := "AbyssCliffs"
## Mossy floor piece (FLOOR_TILES[3]) for moss_tiles.
const MOSS_FLOOR := Vector2i(3, 0)

## Wall a door sits in; same order as RoomTemplate.DoorSide.
enum DoorSide { NORTH, EAST, SOUTH, WEST }
## What the walls are made of (M1): masonry or cave rock.
enum RockStyle { WALL, BLOB }
## Child layers of a cave room (draw only), in drawing order.
const ZONES_NAME := "Zones"
const OVERLAYS_NAME := "Overlays"
const ROCK_NAME := "Rock"
## Small overlay puddles drawn as water (WaterArt), a child node in the layer's space.
const PUDDLES_NAME := "Puddles"
## The lip sprites, a y-sorted child of the room (the layer's parent).
const LIPS_NAME := "RockLips"
## Characters sort by their body centre, this far above their feet (Player.FEET_OFFSET): a lip sorts
## that far above the foot line of its block.
const LIP_SORT_FEET := 16.0
## Outward direction of each side (from the floor through the door).
const SIDE_DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
## No second exit (branch_exit.x).
const NO_DOOR := -1
## Longest extra entrance corridor (tiles) a room may get to keep clear of other rooms. TESTWERT
const MAX_CORRIDOR_EXTRA := 24

## Emitted after pits were added or removed at runtime (crumbling floor, holes): the changed tiles.
signal pits_changed(tiles: Array[Vector2i])
## Emitted after wall tiles were opened at runtime (secret wall, A10): the opened tiles.
signal walls_opened(tiles: Array[Vector2i])

@export var room_size := Vector2i(15, 9):
	set(value):
		room_size = value
		_pits_dirty = true
		_queue_paint()
## Place of the entrance along its wall (x on north/south, y on west/east).
@export var entrance_x := 7:
	set(value):
		entrance_x = value
		_queue_paint()
## Place of the (main) exit along its wall (x on north/south, y on west/east).
@export var exit_x := 7:
	set(value):
		exit_x = value
		_queue_paint()
## Wall of the entrance (DoorSide); the previous room's exit lies on the opposite side.
@export var entrance_side: DoorSide = DoorSide.SOUTH:
	set(value):
		entrance_side = value
		_queue_paint()
@export var exit_side: DoorSide = DoorSide.NORTH:
	set(value):
		exit_side = value
		_queue_paint()
## Second exit of a branch room: x = DoorSide (NO_DOOR = none), y = place along that wall.
@export var branch_exit := Vector2i(NO_DOOR, 0):
	set(value):
		branch_exit = value
		_queue_paint()
## Places a template allows doors at: x = DoorSide, y = place along the wall (generator, A10). Empty =
## only the template's entrance_x (south) and exit_x (north).
@export var door_slots: Array[Vector2i] = []
## Floor tiles of a secret niche (A10): behind the north wall (row -3, in the rock ring) or cut into
## a thick inner wall; size zero = none.
@export var niche_rect := Rect2i():
	set(value):
		niche_rect = value
		_queue_paint()
## Shallow water / mud in floor tiles (plan cell 'w', R1): walkable, slows players (ShallowWater).
@export var water_rects: Array[Rect2i] = []:
	set(value):
		water_rects = value
		_queue_paint()
## Floor tiles always painted with the mossy floor piece (around drips, R1 deco groups).
@export var moss_tiles: Array[Vector2i] = []:
	set(value):
		moss_tiles = value
		_queue_paint()
## Wall fronts (room tiles) a cracked secret wall may sit in (plan cell 'q'); empty = any fitting
## front (SecretRules.find_sites).
@export var secret_cracks: Array[Vector2i] = []
## Wall fronts (room tiles) that hold a fixture of the plan (torch, niche, gate, rift, chains): no
## cracked wall goes there.
@export var front_fixtures: Array[Vector2i] = []
## Extra entrance corridor tiles beyond the painted ring (room placed further out, A10).
@export var entrance_corridor_extra := 0:
	set(value):
		entrance_corridor_extra = clampi(value, 0, MAX_CORRIDOR_EXTRA)
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
## Masonry (rest, boss, crypt halls, campfire) or a cave of rock (RockTerrain look, M1).
@export var rock_style: RockStyle = RockStyle.WALL:
	set(value):
		rock_style = value
		_queue_paint()
## Plan header "cave": the room's entrance is a cave mouth instead of an arch (door art: M2).
@export var cave_mouth := false
## Floor zones of the plan (M1): x, y = floor tile, z = RockTerrain.Zone.
@export var zone_cells: Array[Vector3i] = []:
	set(value):
		zone_cells = value
		_queue_paint()
## Scatter overlays (M1): x, y = floor tile, z = RockTerrain.Overlay | RockTerrain.FLIP_BIT * flip.
@export var overlay_cells: Array[Vector3i] = []:
	set(value):
		overlay_cells = value
		_queue_paint()
## Height markers of the plan for M3 (plateau '^', ladder 'L', stairs '&'); built as rock until then.
@export var plateau_tiles: Array[Vector2i] = []
@export var ladder_tiles: Array[Vector2i] = []
@export var stair_tiles: Array[Vector2i] = []

var _paint_queued := false
## Staged build (feedback 16.10.2026, the hitch on entering a room): while held, paint() only notes
## that it is due; the DungeonManager paints the hidden room a frame after it entered the tree
## (hold_paint / release_paint), so the frame that builds the room stays short.
var _paint_held := false
var _paint_due := false
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
## Wall tiles opened at runtime (secret wall, A10): no longer part of the wall mass.
var _opened_walls: Dictionary[Vector2i, bool] = {}
## Ring tiles outside the floor turned into floor at runtime (the opening of a secret niche).
var _extra_floor: Dictionary[Vector2i, bool] = {}
## The secret niche is drawn as rock until its wall breaks (R1).
var _niche_open := false
var _water: ShallowWater = null
var _cliffs: Node2D = null
## The 47-piece terrain is drawn (its art is there); decided at each paint(). _look follows rock_style.
var _terrain_active := false
var _look := RockTerrain.Look.MASONRY
var _zone_layer: TileMapLayer = null
var _overlay_layer: TileMapLayer = null
var _rock_layer: TileMapLayer = null
var _puddles: Node2D = null
## Tiles of the puddles last painted (use_tileset paints them again in the new biome's water).
var _puddle_tiles: Array[Vector2i] = []
var _lips: Node2D = null
## Floor cells whose rock south of it is no lip (door corridors and the cells around door tiles,
## abysses), built at each paint.
var _not_lips: Dictionary[Vector2i, bool] = {}


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


## Floor tile just inside the entrance / (main) exit door.
func get_entrance_inside_tile() -> Vector2i:
	return inside_tile_of(entrance_side, entrance_x, room_size)


func get_exit_inside_tile() -> Vector2i:
	return inside_tile_of(exit_side, exit_x, room_size)


# --- Doors on every side (A10) ---

## Wall tile a door node stands on: (x, -1) north, (w, y) east, (x, h) south, (-1, y) west.
static func door_tile_of(side: int, place: int, size: Vector2i) -> Vector2i:
	match side:
		DoorSide.EAST:
			return Vector2i(size.x, place)
		DoorSide.SOUTH:
			return Vector2i(place, size.y)
		DoorSide.WEST:
			return Vector2i(-1, place)
	return Vector2i(place, -1)


## Floor tile right inside a door.
static func inside_tile_of(side: int, place: int, size: Vector2i) -> Vector2i:
	return door_tile_of(side, place, size) - SIDE_DIRECTIONS[side]


static func opposite_side(side: int) -> int:
	return (side + 2) % 4


## Corridor tiles of a door through the painted ring (north 3, other sides 2) plus extra tiles.
static func corridor_length(side: int) -> int:
	return 3 if side == DoorSide.NORTH else 2


static func corridor_tiles_of(side: int, place: int, size: Vector2i, extra := 0) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var tile := door_tile_of(side, place, size)
	for i in corridor_length(side) + maxi(0, extra):
		tiles.append(tile + SIDE_DIRECTIONS[side] * i)
	return tiles


## Last corridor tile of a door: where two rooms join (same world tile in both rooms).
static func corridor_end_of(side: int, place: int, size: Vector2i, extra := 0) -> Vector2i:
	return door_tile_of(side, place, size) + SIDE_DIRECTIONS[side] * (corridor_length(side) - 1 + maxi(0, extra))


## Lane of a door: depth rows of three tiles inside the room, straight in from the door.
static func door_lane_of(side: int, place: int, size: Vector2i, depth: int) -> Array[Vector2i]:
	var lane: Array[Vector2i] = []
	var inward := -SIDE_DIRECTIONS[side]
	var across := Vector2i(absi(inward.y), absi(inward.x))
	var inside := inside_tile_of(side, place, size)
	for d in depth:
		for a in [-1, 0, 1]:
			lane.append(inside + inward * d + across * a)
	return lane


## Entrance as Vector2i(side, place).
func get_entrance_door() -> Vector2i:
	return Vector2i(entrance_side, entrance_x)


## Every exit as Vector2i(side, place): the main exit first, then the branch exit (if any).
func get_exit_doors() -> Array[Vector2i]:
	var doors: Array[Vector2i] = [Vector2i(exit_side, exit_x)]
	if has_branch_exit():
		doors.append(branch_exit)
	return doors


func has_branch_exit() -> bool:
	return branch_exit.x != NO_DOOR


func get_exit_inside_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for door in get_exit_doors():
		tiles.append(inside_tile_of(door.x, door.y, room_size))
	return tiles


## Corridor tiles of the entrance (with entrance_corridor_extra) and of every exit.
func get_door_corridor_tiles() -> Array[Vector2i]:
	var tiles := corridor_tiles_of(entrance_side, entrance_x, room_size, entrance_corridor_extra)
	for door in get_exit_doors():
		tiles.append_array(corridor_tiles_of(door.x, door.y, room_size))
	return tiles


## Door places the template allows on a side (sorted); without door_slots the template's own
## entrance (south) and exit (north) place.
func get_door_slots(side: int) -> Array[int]:
	var places: Array[int] = []
	for slot in door_slots:
		if slot.x == side and not places.has(slot.y):
			places.append(slot.y)
	if door_slots.is_empty():
		if side == DoorSide.NORTH:
			places.append(exit_x)
		elif side == DoorSide.SOUTH:
			places.append(entrance_x)
	places.sort()
	return places


func allows_door(side: int) -> bool:
	return not get_door_slots(side).is_empty()


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
	for tile in _opened_walls:
		mass.erase(tile)
	for y in range(niche_rect.position.y, niche_rect.end.y):
		for x in range(niche_rect.position.x, niche_rect.end.x):
			mass.erase(Vector2i(x, y))
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


## Opens wall tiles at runtime (a secret wall breaks, A10): they become floor. Only the cells around
## them are repainted, so the floor pattern of the rest of the room stays as it is; collision and
## navigation follow with the cells.
func open_wall_tiles(tiles: Array[Vector2i]) -> void:
	var mass := get_wall_mass()
	var floor_rect := Rect2i(Vector2i.ZERO, room_size)
	var opened: Array[Vector2i] = []
	for tile in tiles:
		if mass.has(tile):
			_opened_walls[tile] = true
			opened.append(tile)
		elif not floor_rect.has_point(tile) and not _extra_floor.has(tile) and is_painted(tile):
			# The ring around the floor (the north wall in front of a secret niche).
			_extra_floor[tile] = true
			opened.append(tile)
	if opened.is_empty():
		return
	# The opening reaches the niche: from now on it is floor, not rock (R1).
	if has_niche() and not _niche_open:
		var around := niche_rect.grow(1)
		for tile in opened:
			if around.has_point(tile):
				_niche_open = true
		if _niche_open:
			for tile in get_niche_tiles():
				opened.append(tile)
	_pits_dirty = true
	if get_used_cells().is_empty() or tile_set == null or not tile_set.has_source(SOURCE_WALL):
		if is_inside_tree():
			paint()
	else:
		# Pieces look two tiles around them (front below a crown, crown masks of the neighbours).
		var area: Dictionary[Vector2i, bool] = {}
		for tile in opened:
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					area[tile + Vector2i(dx, dy)] = true
		_repaint_cells(area)
	walls_opened.emit(opened)


func get_opened_wall_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	tiles.assign(_opened_walls.keys())
	tiles.append_array(_extra_floor.keys())
	return tiles


func has_niche() -> bool:
	return niche_rect.size != Vector2i.ZERO


## Is the secret niche open (its wall broken)? Until then it is drawn as rock.
func is_niche_open() -> bool:
	return _niche_open


func get_niche_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for y in range(niche_rect.position.y, niche_rect.end.y):
		for x in range(niche_rect.position.x, niche_rect.end.x):
			tiles.append(Vector2i(x, y))
	return tiles


## Floor tiles of the plan's shallow water (inside the floor, no walls, no pits).
func get_water_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var floor_rect := Rect2i(Vector2i.ZERO, room_size)
	var mass := get_wall_mass()
	for rect in water_rects:
		var clipped := rect.intersection(floor_rect)
		for y in range(clipped.position.y, clipped.end.y):
			for x in range(clipped.position.x, clipped.end.x):
				var tile := Vector2i(x, y)
				if not mass.has(tile) and not tiles.has(tile) and not is_pit(tile):
					tiles.append(tile)
	return tiles


func is_water(tile: Vector2i) -> bool:
	for rect in water_rects:
		if rect.has_point(tile):
			return not get_wall_mass().has(tile) and not is_pit(tile)
	return false


func get_water() -> ShallowWater:
	return _water


## Floor tiles outside the floor rectangle that are no corridor: the secret niche and what opened
## in front of it.
func get_extra_floor_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for y in range(niche_rect.position.y, niche_rect.end.y):
		for x in range(niche_rect.position.x, niche_rect.end.x):
			tiles.append(Vector2i(x, y))
	for tile in _extra_floor:
		if not tiles.has(tile):
			tiles.append(tile)
	return tiles


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
		_paint_cliffs()
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


## Floor of the room plus every door corridor, without blocked and pit tiles.
func get_walkable_tiles() -> Dictionary[Vector2i, bool]:
	var walkable: Dictionary[Vector2i, bool] = {}
	for y in room_size.y:
		for x in room_size.x:
			walkable[Vector2i(x, y)] = true
	for tile in get_door_corridor_tiles():
		walkable[tile] = true
	for tile in get_extra_floor_tiles():
		walkable[tile] = true
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
	# The lip sprites get the next biome's rock in the same blend (_paint_lips, after the layers).
	call_deferred(&"_paint_lips")
	if _blend_material == null:
		_blend_material = ShaderMaterial.new()
		_blend_material.shader = BLEND_SHADER
	WallAutotile.ensure_source(next_tileset)
	RockTerrain.ensure_sources(next_tileset)
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
		# A solid cell of the terrain is invisible here: its piece lies on the rock layer.
		if _rock_layer != null and _rock_layer.get_cell_source_id(cell) >= 0:
			_blend_layer.set_cell(cell, _rock_layer.get_cell_source_id(cell), _rock_layer.get_cell_atlas_coords(cell))
		else:
			_blend_layer.set_cell(cell, get_cell_source_id(cell), get_cell_atlas_coords(cell))
	_blend_backdrop.clear()
	if _backdrop != null:
		for cell in _backdrop.get_used_cells():
			_blend_backdrop.set_cell(cell, _backdrop.get_cell_source_id(cell), _backdrop.get_cell_atlas_coords(cell))


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
	elif what == NOTIFICATION_PREDELETE:
		# Lips that never reached the room (freed before the deferred attach) go with the layer.
		if _lips != null and is_instance_valid(_lips) and not _lips.is_inside_tree():
			_lips.free()


## Swaps the tileset (biome art). All tilesets share the same atlas layout.
func use_tileset(new_tileset: TileSet) -> void:
	# The wall pieces of the new biome must exist before the cells point at them.
	WallAutotile.ensure_source(new_tileset)
	AbyssAutotile.ensure_source(new_tileset)
	AbyssRims.ensure_source(new_tileset)
	# The cave pieces too (same source ids and layout in every biome); without them the room
	# falls back to masonry on the next paint.
	var had_terrain := _terrain_active
	var terrain := RockTerrain.ensure_sources(new_tileset) and RockTerrain.has_look(new_tileset, _look_of_style())
	tile_set = new_tileset
	for layer in [_backdrop, _abyss_under, _zone_layer, _overlay_layer, _rock_layer]:
		if layer != null:
			(layer as TileMapLayer).tile_set = new_tileset
	if had_terrain != terrain and is_inside_tree():
		paint()
	# The rock faces, the water, the lips and the puddles take the biome's colours (a held paint
	# draws them later). Lips and puddles are sprites holding the old biome's pictures: a room
	# painted in the template's crypt tileset before its biome came kept crypt rock on its block
	# tops (bug report 16.10.2026, slime grotto).
	if is_inside_tree() and not _paint_held:
		_paint_cliffs()
		_paint_water()
		_paint_lips()
		_paint_puddles(_puddle_tiles.duplicate())


func get_backdrop() -> TileMapLayer:
	return _backdrop


## Holds every paint back (call before the layer enters the tree): the cells, collision and
## navigation come with release_paint(). Until then the layer has no cells.
func hold_paint() -> void:
	_paint_held = true


## Paints what was held back (once, with everything set since); a no-op without a hold.
func release_paint() -> void:
	if not _paint_held:
		return
	_paint_held = false
	if not _paint_due:
		return
	_paint_due = false
	paint()
	# A campfire's blend copied no cells while they were missing (set_biome_blend).
	if _blend_layer != null:
		_copy_cells_to_blend()


func is_paint_held() -> bool:
	return _paint_held


func paint() -> void:
	_paint_queued = false
	if _paint_held:
		_paint_due = true
		return
	clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_seed
	_floor_cells.clear()
	if _abyss_under != null:
		_abyss_under.clear()
	for layer in [_zone_layer, _overlay_layer, _rock_layer]:
		if layer != null:
			(layer as TileMapLayer).clear()
	_paint_puddles([])
	_look = _look_of_style()
	_terrain_active = false
	if WallAutotile.ensure_source(tile_set):
		AbyssAutotile.ensure_source(tile_set)
		AbyssRims.ensure_source(tile_set)
		_terrain_active = RockTerrain.ensure_sources(tile_set) and RockTerrain.has_look(tile_set, _look)
		_paint_from_mask(rng)
		if _terrain_active:
			_paint_ground_details()
	else:
		_paint_legacy(rng)
	_paint_backdrop()
	_paint_mist()
	_paint_cliffs()
	_paint_water()
	_paint_lips()


## Floor of the room plus both door corridors, without walls and pillars. Abyss tiles (A4) stay in
## the mask: they are holes in the floor, not walls.
func get_floor_mask() -> Dictionary[Vector2i, bool]:
	var floor_mask: Dictionary[Vector2i, bool] = {}
	for y in room_size.y:
		for x in room_size.x:
			floor_mask[Vector2i(x, y)] = true
	for tile in get_door_corridor_tiles():
		floor_mask[tile] = true
	for tile in get_extra_floor_tiles():
		floor_mask[tile] = true
	for tile: Vector2i in get_wall_mass():
		floor_mask.erase(tile)
	if has_niche() and not _niche_open:
		# A closed niche is rock like the wall around it (no box in the rock, R1).
		for tile in get_niche_tiles():
			floor_mask.erase(tile)
	return floor_mask


## One rule for every wall (WallAutotile.cell_for_floor): fronts only right above floor, crowns
## with edges, enclosed rock as the plain wall-top tile (the rock shader turns it into stones).
func _paint_from_mask(rng: RandomNumberGenerator) -> void:
	var floor_mask := get_floor_mask()
	_not_lips = _lip_blockers()
	var rect := _get_painted_rect()
	var parts := get_painted_parts()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var tile := Vector2i(x, y)
			if parts.size() > 1 and not _in_any(parts, tile):
				continue
			if floor_mask.has(tile):
				# Drawn for every floor tile, pit or not, so the floor pattern never depends on pits.
				_floor_cells[tile] = _random_floor(rng)
				if moss_tiles.has(tile):
					_floor_cells[tile] = MOSS_FLOOR
				_paint_floor_cell(tile)
				continue
			if _terrain_active:
				_paint_rock_cell(tile, floor_mask)
				continue
			var piece := WallAutotile.cell_for_floor(tile, floor_mask)
			if piece == WallAutotile.ROCK:
				_put_tile(tile, WALL_TOP)
			elif piece == WallAutotile.front_coords(WallAutotile.Front.MIDDLE) and rng.randf() < FRONT_ALT_CHANCE:
				set_cell(tile, SOURCE_WALL, WallAutotile.front_coords(WallAutotile.Front.MIDDLE_ALT))
			else:
				set_cell(tile, SOURCE_WALL, piece)
	if _terrain_active:
		for tile: Vector2i in floor_mask:
			if parts.size() <= 1 or _in_any(parts, tile):
				_paint_fillet(tile, floor_mask)


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

	# Door passages (north exit and south entrance get their old side walls).
	for tile in get_door_corridor_tiles():
		_put_tile(tile, _random_floor(rng))
	if exit_side == DoorSide.NORTH:
		for y in [-2, -3]:
			_put_tile(Vector2i(exit_x - 1, y), WALL_E)
			_put_tile(Vector2i(exit_x + 1, y), WALL_W)
	if entrance_side == DoorSide.SOUTH:
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


## Bounding rectangle of the tiles paint() draws on this layer: floor plus the wall ring and, with a
## longer entrance corridor, its strip, with a secret niche its bump (see get_painted_parts).
func _get_painted_rect() -> Rect2i:
	var bounds := get_painted_rect_of(room_size, entrance_side, entrance_corridor_extra)
	return bounds.merge(get_niche_bump()) if has_niche() else bounds


func get_painted_rect() -> Rect2i:
	return _get_painted_rect()


## Painted parts of this room: ring, corridor strip (get_painted_rects_of) and the niche bump.
func get_painted_parts() -> Array[Rect2i]:
	var parts := get_painted_rects_of(room_size, entrance_side, entrance_corridor_extra, entrance_x)
	if has_niche():
		parts.append(get_niche_bump())
	return parts


## Rock around a secret niche that reaches out of the ring (one tile on every side of it).
func get_niche_bump() -> Rect2i:
	return niche_rect.grow(1) if has_niche() else Rect2i()


## Is this tile drawn by the room (ring, corridor strip, niche bump)? Elsewhere the backdrop shows.
func is_painted(tile: Vector2i) -> bool:
	return _in_any(get_painted_parts(), tile)


static func _in_any(rects: Array[Rect2i], tile: Vector2i) -> bool:
	for rect in rects:
		if rect.has_point(tile):
			return true
	return false


## Bounding rectangle of get_painted_rects_of (tiles, room-local).
static func get_painted_rect_of(size: Vector2i, entrance: int = DoorSide.SOUTH, extra := 0) -> Rect2i:
	var rect := Rect2i(-2, -3, size.x + 4, size.y + 5)
	if extra <= 0:
		return rect
	match entrance:
		DoorSide.NORTH:
			return rect.grow_individual(0, extra, 0, 0)
		DoorSide.EAST:
			return rect.grow_individual(0, 0, extra, 0)
		DoorSide.WEST:
			return rect.grow_individual(extra, 0, 0, 0)
	return rect.grow_individual(0, 0, 0, extra)


## What a room paints (tiles, room-local): the ring rectangle and, for extra entrance corridor tiles,
## a strip three tiles wide along them (the corridor and its walls); the rest of that gap is left to
## the backdrop, so a long corridor never covers a neighbouring room (A10).
static func get_painted_rects_of(size: Vector2i, entrance: int = DoorSide.SOUTH, extra := 0, place := 0) -> Array[Rect2i]:
	var rects: Array[Rect2i] = [Rect2i(-2, -3, size.x + 4, size.y + 5)]
	if extra > 0:
		var tiles := corridor_tiles_of(entrance, place, size, extra)
		var strip := tile_bounds(tiles.slice(tiles.size() - extra))
		var across := Vector2i(1, 0) if entrance == DoorSide.NORTH or entrance == DoorSide.SOUTH else Vector2i(0, 1)
		rects.append(strip.grow_individual(across.x, across.y, across.x, across.y))
	return rects


## Smallest rectangle around the tiles (tiles included).
static func tile_bounds(tiles: Array[Vector2i]) -> Rect2i:
	if tiles.is_empty():
		return Rect2i()
	var low := tiles[0]
	var high := tiles[0]
	for tile in tiles:
		low = Vector2i(mini(low.x, tile.x), mini(low.y, tile.y))
		high = Vector2i(maxi(high.x, tile.x), maxi(high.y, tile.y))
	return Rect2i(low, high - low + Vector2i.ONE)


## Repaints single cells from the current floor mask (runtime changes such as opened walls).
## The second brick pattern is picked from the tile position instead of the paint RNG.
func _repaint_cells(area: Dictionary[Vector2i, bool]) -> void:
	var floor_mask := get_floor_mask()
	_not_lips = _lip_blockers()
	for tile: Vector2i in area:
		if not is_painted(tile):
			continue
		if floor_mask.has(tile):
			if not _floor_cells.has(tile):
				var rng := RandomNumberGenerator.new()
				rng.seed = absi(hash(tile)) + floor_seed
				_floor_cells[tile] = _random_floor(rng)
			_paint_floor_cell(tile)
			if _rock_layer != null:
				_rock_layer.erase_cell(tile)
			continue
		if _terrain_active:
			_paint_rock_cell(tile, floor_mask)
			continue
		var piece := WallAutotile.cell_for_floor(tile, floor_mask)
		if piece == WallAutotile.ROCK:
			_put_tile(tile, WALL_TOP)
		elif piece == WallAutotile.front_coords(WallAutotile.Front.MIDDLE) and absi(hash(tile)) % 100 < int(FRONT_ALT_CHANCE * 100.0):
			set_cell(tile, SOURCE_WALL, WallAutotile.front_coords(WallAutotile.Front.MIDDLE_ALT))
		else:
			set_cell(tile, SOURCE_WALL, piece)
	if _terrain_active:
		_paint_lips()
		# Fillets of the changed cells and of the floor around them.
		for tile: Vector2i in area:
			for offset: Vector2i in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i(-1, -1), Vector2i(1, -1)]:
				if floor_mask.has(tile + offset) and is_painted(tile + offset):
					_paint_fillet(tile + offset, floor_mask)


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
	var outer := get_backdrop_rect()
	var painted := get_painted_parts()
	var cell := get_rock_fill_cell()
	for y in range(outer.position.y, outer.end.y):
		for x in range(outer.position.x, outer.end.x):
			var tile := Vector2i(x, y)
			# With the terrain the enclosed rock of the room itself lies here too (below every room).
			if _terrain_active or not _in_any(painted, tile):
				_backdrop.set_cell(tile, cell.z, Vector2i(cell.x, cell.y))
	if _blend_backdrop != null:
		_copy_cells_to_blend()


## Cell of plain rock around the room (backdrop, and the hook for rock fills of the DungeonManager):
## x, y = atlas coords, z = source id. Masonry rooms: the wall-top tile; cave rooms: full rock.
func get_rock_fill_cell() -> Vector3i:
	if _terrain_active:
		return RockTerrain.fill_cell(_look, tile_set)
	return Vector3i(WALL_TOP.x, WALL_TOP.y, SOURCE_ID)


## Is the room's rock the cave's soft rock (M1)? True for cave rooms and, with the soft set, for
## masonry rooms too: both share the rock, its fill around the room and the soft doors, so neither
## has to give way to the other where they meet (PassageSeam, DoorStyle). get_look() tells them apart.
func is_cave_look() -> bool:
	if not _terrain_active:
		return false
	return _look == RockTerrain.Look.CAVE or RockTerrain.floor_source(_look, tile_set) == RockTerrain.SOURCE_MASONRY_GROUND


## Atlas source of plain floor cells (SOURCE_ID without the terrain, else the look's floor source).
func get_floor_source() -> int:
	if _terrain_active and RockTerrain.floor_source(_look, tile_set) >= 0:
		return RockTerrain.floor_source(_look, tile_set)
	return SOURCE_ID


## The look the walls are drawn in (RockTerrain.Look, from rock_style).
func get_look() -> RockTerrain.Look:
	return _look


## Is the 47-piece terrain drawn (either look)?
func is_terrain_drawn() -> bool:
	return _terrain_active


func _look_of_style() -> RockTerrain.Look:
	return RockTerrain.Look.CAVE if rock_style == RockStyle.BLOB else RockTerrain.Look.MASONRY


func get_rock_layer() -> TileMapLayer:
	return _rock_layer


func get_zone_layer() -> TileMapLayer:
	return _zone_layer


func get_overlay_layer() -> TileMapLayer:
	return _overlay_layer


## Solid tile with the terrain: this layer gets the invisible solid tile (collision, no navigation),
## the rock layer the piece of the mass; enclosed rock is left to the backdrop.
func _paint_rock_cell(tile: Vector2i, floor_mask: Dictionary[Vector2i, bool]) -> void:
	# The collision rounds the outer corners like the art (RockTerrain.solid_corners); a lip lets
	# characters walk a bit behind it.
	var lip := RockTerrain.is_lip(tile, floor_mask, _not_lips)
	set_cell(tile, RockTerrain.SOURCE_GROUND, RockTerrain.solid_coords(RockTerrain.solid_corners(tile, floor_mask), lip))
	_ensure_cave_layers()
	if RockTerrain.is_enclosed(tile, floor_mask):
		_rock_layer.erase_cell(tile)
	else:
		_rock_layer.set_cell(tile, RockTerrain.rock_source(_look), RockTerrain.piece_for(tile, floor_mask))


## Rounded rock in the lower corners of a floor cell between two edges (RockTerrain fillets), on
## the rock layer over the floor; never over an abyss.
func _paint_fillet(tile: Vector2i, floor_mask: Dictionary[Vector2i, bool]) -> void:
	_update_pit_sets()
	var bits := 0 if _pit_set.has(tile) else RockTerrain.fillet_bits(tile, floor_mask)
	if bits == 0:
		if _rock_layer != null and _rock_layer.get_cell_source_id(tile) == RockTerrain.rock_source(_look):
			_rock_layer.erase_cell(tile)
		return
	_ensure_cave_layers()
	_rock_layer.set_cell(tile, RockTerrain.rock_source(_look), RockTerrain.fillet_coords(bits))


## The draw-only child layers of a cave room, in drawing order: zones, overlays, rock.
func _ensure_cave_layers() -> void:
	if _rock_layer != null:
		return
	_zone_layer = _make_draw_layer(ZONES_NAME)
	_overlay_layer = _make_draw_layer(OVERLAYS_NAME)
	_rock_layer = _make_draw_layer(ROCK_NAME)


func _make_draw_layer(layer_name: String) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.collision_enabled = false
	layer.navigation_enabled = false
	layer.occlusion_enabled = false
	layer.use_parent_material = true
	layer.tile_set = tile_set
	add_child(layer, false, Node.INTERNAL_MODE_FRONT)
	return layer


## Zones and overlays of the plan, never on pits, bridges, water or walls.
func _paint_ground_details() -> void:
	if zone_cells.is_empty() and overlay_cells.is_empty():
		return
	_ensure_cave_layers()
	var floor_mask := get_floor_mask()
	var zones: Dictionary[Vector2i, int] = {}
	var zone_source := RockTerrain.zone_source(_look, tile_set)
	if tile_set.has_source(zone_source):
		for cell in zone_cells:
			var tile := Vector2i(cell.x, cell.y)
			if _plain_ground(tile, floor_mask):
				zones[tile] = cell.z
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for tile: Vector2i in zones:
		var same := 0
		for i in directions.size():
			if zones.get(tile + directions[i], -1) == zones[tile]:
				same |= 1 << i
		_zone_layer.set_cell(tile, zone_source, RockTerrain.zone_coords(zones[tile], same))
	if tile_set.has_source(RockTerrain.SOURCE_OVERLAY):
		var puddles: Array[Vector2i] = []
		for cell in overlay_cells:
			var tile := Vector2i(cell.x, cell.y)
			if not _plain_ground(tile, floor_mask):
				continue
			if cell.z % RockTerrain.FLIP_BIT == RockTerrain.Overlay.PUDDLE:
				puddles.append(tile)
				continue
			var flip := TileSetAtlasSource.TRANSFORM_FLIP_H if cell.z & RockTerrain.FLIP_BIT else 0
			_overlay_layer.set_cell(tile, RockTerrain.SOURCE_OVERLAY, Vector2i(cell.z % RockTerrain.FLIP_BIT, 0), flip)
		_paint_puddles(puddles)


## Floor cells north of rock that is no lip: door corridors and every cell next to a door tile (the
## door's art lies there), abysses (nobody stands there).
func _lip_blockers() -> Dictionary[Vector2i, bool]:
	var blockers: Dictionary[Vector2i, bool] = {}
	for tile in get_door_corridor_tiles():
		blockers[tile] = true
	var doors: Array[Vector2i] = [get_entrance_door()]
	doors.append_array(get_exit_doors())
	for slot in door_slots:
		doors.append(slot)
	for door in doors:
		var door_tile := door_tile_of(door.x, door.y, room_size)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				blockers[door_tile + Vector2i(dx, dy)] = true
	for tile in get_pit_tiles():
		blockers[tile] = true
	return blockers


## The lips once more as sprites in the room's y-sort (the room is this layer's parent), sorted at the
## foot line of their block: the front below a lip, else the lip itself. Same piece, same material.
## Only with the terrain and inside a room (not in the editor).
func _paint_lips() -> void:
	if _lips != null and is_instance_valid(_lips):
		for child in _lips.get_children():
			child.free()
	var room := get_parent() as Node2D
	if Engine.is_editor_hint() or not _terrain_active or _rock_layer == null or room == null or not is_inside_tree():
		return
	var source := tile_set.get_source(RockTerrain.rock_source(_look)) as TileSetAtlasSource
	if source == null:
		return
	# A room between two biomes: the next biome's piece on top, in the blend's mask (set_biome_blend).
	var blend_source: TileSetAtlasSource = null
	if _blend_layer != null and _blend_layer.tile_set != null and _blend_layer.tile_set.has_source(RockTerrain.rock_source(_look)):
		blend_source = _blend_layer.tile_set.get_source(RockTerrain.rock_source(_look)) as TileSetAtlasSource
	var floor_mask := get_floor_mask()
	if _lips == null or not is_instance_valid(_lips):
		_lips = Node2D.new()
		_lips.name = LIPS_NAME
		_lips.y_sort_enabled = true
		# Deferred: paint() runs while the room is still adding its children.
		_attach_lips.call_deferred()
	var art_tile := float(tile_set.tile_size.x)
	for tile: Vector2i in floor_mask:
		var lip := tile + Vector2i.DOWN
		if _rock_layer.get_cell_source_id(lip) < 0 or not RockTerrain.is_lip(lip, floor_mask, _not_lips):
			continue
		var foot := float(lip.y + (2 if WallAutotile.is_front(lip + Vector2i.DOWN, floor_mask) else 1)) * art_tile
		var sort_y := foot * scale.y - LIP_SORT_FEET
		var region := Rect2(Vector2(_rock_layer.get_cell_atlas_coords(lip)) * art_tile, Vector2.ONE * art_tile)
		var at := position + Vector2(float(lip.x) * art_tile * scale.x, sort_y)
		var offset := Vector2(0.0, (float(lip.y) * art_tile * scale.y - sort_y) / scale.y)
		_lips.add_child(_lip_sprite(source.texture, region, at, offset, material, modulate))
		if blend_source != null:
			# Same sort position: drawn right after (above) the old biome's piece.
			_lips.add_child(_lip_sprite(blend_source.texture, region, at, offset, _blend_material, _blend_layer.modulate))


func _lip_sprite(texture: Texture2D, region: Rect2, at: Vector2, offset: Vector2, look: Material, tint: Color) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.centered = false
	sprite.material = look
	sprite.modulate = tint
	sprite.scale = scale
	sprite.position = at
	sprite.offset = offset
	return sprite


## Puts the lip sprites into the room (deferred from _paint_lips; skipped if the layer is gone).
func _attach_lips() -> void:
	var room := get_parent() as Node2D
	if _lips != null and is_instance_valid(_lips) and not _lips.is_inside_tree() and room != null:
		room.add_child(_lips)


func get_lips() -> Node2D:
	return _lips


## Small puddles of the overlays in the same water as the pools (WaterArt, playtest 15.10.2026 note
## 13: "the water looks so different"), not the old overlay sprite. Shape from the tile, no RNG.
func _paint_puddles(puddles: Array[Vector2i]) -> void:
	if _puddles != null:
		_puddles.queue_free()
		_puddles = null
	_puddle_tiles = puddles.duplicate()
	if puddles.is_empty() or Engine.is_editor_hint():
		return
	_puddles = Node2D.new()
	_puddles.name = PUDDLES_NAME
	add_child(_puddles, false, Node.INTERNAL_MODE_BACK)
	var art_tile := float(tile_set.tile_size.x)
	var biome := WallAutotile.biome_of(tile_set)
	for tile in puddles:
		var puddle := AnimatedProp.new()
		puddle.frame_size = Vector2i(WaterArt.TILE, WaterArt.TILE)
		puddle.fps = WaterArt.FPS
		puddle.pivot = Vector2.ZERO
		puddle.strip = WaterArt.small_puddle_strip(biome, absi(hash(tile)))
		puddle.position = Vector2(tile) * art_tile
		puddle.scale = Vector2.ONE * art_tile / float(WaterArt.TILE)
		_puddles.add_child(puddle)
		puddle.frame = absi(hash(tile)) % WaterArt.FRAMES


func _plain_ground(tile: Vector2i, floor_mask: Dictionary[Vector2i, bool]) -> bool:
	return floor_mask.has(tile) and not is_pit(tile) and not is_bridge(tile) and not is_water(tile)


## Floor tile of the mask: abyss piece, bridge (with the abyss below it) or the remembered floor.
func _paint_floor_cell(tile: Vector2i) -> void:
	if is_pit(tile):
		_set_abyss_cell(self, tile)
		_set_under_cell(tile, false)
		_erase_ground_details(tile)
	elif is_bridge(tile):
		var piece := _bridge_piece(tile)
		set_cell(tile, SOURCE_BRIDGE, piece[0], piece[1])
		_set_under_cell(tile, true)
	elif _terrain_active and RockTerrain.floor_source(_look, tile_set) >= 0:
		set_cell(tile, RockTerrain.floor_source(_look, tile_set), RockTerrain.ground_coords(_floor_cells.get(tile, FLOOR_TILES[0]).x))
		_set_under_cell(tile, false)
	else:
		_put_tile(tile, _floor_cells.get(tile, FLOOR_TILES[0]))
		_set_under_cell(tile, false)


## A floor tile that became abyss loses its zone and overlay.
func _erase_ground_details(tile: Vector2i) -> void:
	if _zone_layer != null:
		_zone_layer.erase_cell(tile)
	if _overlay_layer != null:
		_overlay_layer.erase_cell(tile)


## Abyss piece of a pit tile on layer (bridges count as abyss for the rim).
func _set_abyss_cell(layer: TileMapLayer, tile: Vector2i) -> void:
	var piece := AbyssAutotile.cell_for(tile, _is_abyss)
	if piece == AbyssAutotile.VOID or layer.tile_set == null or not layer.tile_set.has_source(AbyssAutotile.SOURCE_ID):
		var variants := AbyssAutotile.ART_VOID
		layer.set_cell(tile, SOURCE_ABYSS, variants[absi(hash(tile)) % variants.size()])
	elif layer.tile_set.has_source(SOURCE_ABYSS_PIECES):
		layer.set_cell(tile, SOURCE_ABYSS_PIECES, piece)
	else:
		layer.set_cell(tile, AbyssAutotile.SOURCE_ID, piece)


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


## Rock face of the biome under the north edge of every abyss (abyss_cliff_<biome>, 4 x 1 pieces):
## on each pit tile whose north neighbour is no abyss. Optics only, on a child node in the layer's
## space; bridges keep their planks on top. Repainted when pits change (collapse, holes).
func _paint_cliffs() -> void:
	if _cliffs != null:
		for child in _cliffs.get_children():
			child.queue_free()
	if Engine.is_editor_hint() or tile_set == null or not has_pits():
		return
	if _cliffs == null:
		_cliffs = Node2D.new()
		_cliffs.name = CLIFF_NAME
		add_child(_cliffs, false, Node.INTERNAL_MODE_BACK)
	var art_tile := float(tile_set.tile_size.x)
	# Terrain rooms (both looks): the face sinks into the void below the abyss's own rim (AbyssFace,
	# playtest 15.10.2026), one picture per abyss piece.
	if _terrain_active and _paint_abyss_faces(art_tile):
		return
	var path := CLIFF_ART_PATH % WallAutotile.biome_of(tile_set)
	if not ResourceLoader.exists(path):
		path = CLIFF_ART_PATH % "crypt"
	if not ResourceLoader.exists(path):
		return
	var texture := load(path) as Texture2D
	for tile in get_pit_tiles():
		if not _has_cliff(tile):
			continue
		var left := _has_cliff(tile + Vector2i.LEFT)
		var right := _has_cliff(tile + Vector2i.RIGHT)
		var piece := 3
		if left and right:
			piece = 1
		elif right:
			piece = 0
		elif left:
			piece = 2
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.region_enabled = true
		sprite.region_rect = Rect2(piece * art_tile, 0, art_tile, art_tile)
		sprite.centered = false
		sprite.position = Vector2(tile) * art_tile
		_cliffs.add_child(sprite)


## The faces of a terrain room over every cliff tile (AbyssFace); false without the art.
func _paint_abyss_faces(art_tile: float) -> bool:
	var biome := WallAutotile.biome_of(tile_set)
	for tile in get_cliff_tiles():
		var piece := AbyssAutotile.cell_for(tile, _is_abyss)
		# A face ends softly beside abyss without a face (an inner corner of the abyss).
		var fade_left := is_pit(tile + Vector2i.LEFT) and not _has_cliff(tile + Vector2i.LEFT)
		var fade_right := is_pit(tile + Vector2i.RIGHT) and not _has_cliff(tile + Vector2i.RIGHT)
		var texture := AbyssFace.texture_for(tile_set, biome, piece.x, piece.y, fade_left, fade_right)
		if texture == null:
			return false
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.position = Vector2(tile) * art_tile
		_cliffs.add_child(sprite)
	return true


## A pit tile with solid ground or a wall right north of it (no other pit, no bridge).
func _has_cliff(tile: Vector2i) -> bool:
	return is_pit(tile) and not _is_abyss(tile + Vector2i.UP)


## Pit tiles that show a rock face (the north edge of every abyss), sorted.
func get_cliff_tiles() -> Array[Vector2i]:
	var cliffs: Array[Vector2i] = []
	for tile in get_pit_tiles():
		if _has_cliff(tile):
			cliffs.append(tile)
	return cliffs


## Shallow water overlay and its slow area (ShallowWater), runtime only.
func _paint_water() -> void:
	if _water != null:
		_water.queue_free()
		_water = null
	if Engine.is_editor_hint() or water_rects.is_empty() or tile_set == null:
		return
	var tiles := get_water_tiles()
	if tiles.is_empty():
		return
	_water = ShallowWater.new()
	add_child(_water, false, Node.INTERNAL_MODE_BACK)
	_water.build(tiles, float(tile_set.tile_size.x), WallAutotile.biome_of(tile_set))


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

class_name AbyssAutotile
extends RefCounted
## Abyss pieces for any shape of pit (A4, D-086): the delivered biome art (abyss_tiles_<biome>.png,
## TileSet source 2, tools/build_tilesets.gd) has the four edges, four outer corners, four inner
## corners and four void tiles; one-tile gaps (floor on two opposite sides), tongues and single
## holes need combinations of them. Like WallAutotile, the combinations live in an extra atlas
## source (SOURCE_ID) that is added to a dungeon TileSet at runtime:
##   column = 4-bit mask of pit neighbours (N=1, E=2, S=4, W=8; a bridge counts as pit, everything
##   else - floor, wall, outside - shows the rim), row = 4-bit mask of inner corners (top-left=1,
##   top-right=2, bottom-left=4, bottom-right=8: both sides pit, the diagonal not).
## Each piece starts as void and gets the rim strip of every open side from the matching edge tile,
## the corner square of every two adjacent open sides from the outer corner tile and the inner
## corner squares from the inner corner tiles; exact matches use the delivered tile unchanged.
## Every piece is solid on the TileSet's pit physics layer and has no navigation. A pit surrounded
## by pits (mask 15, no corners) is drawn with the delivered void tiles (variety).

const SOURCE_ID := 11
## TileSet source with the delivered abyss art (tools/build_tilesets.gd SOURCE_ABYSS).
const ART_SOURCE_ID := 2
## TileSet physics layer of the pits (tools/build_tilesets.gd PHYSICS_PIT).
const PHYSICS_LAYER := 1
const TILE := 32
## Depth of the rim strip copied from the delivered edges, in art pixels (the rims are 6-8 px).
const RIM_DEPTH := 8

const N := 1
const E := 2
const S := 4
const W := 8
const CORNER_TOP_LEFT := 1
const CORNER_TOP_RIGHT := 2
const CORNER_BOTTOM_LEFT := 4
const CORNER_BOTTOM_RIGHT := 8
const FULL := 15

## Delivered art layout (abyss_tiles_<biome>.png, 4 x 4).
const ART_EDGE := {N: Vector2i(0, 0), E: Vector2i(1, 0), S: Vector2i(2, 0), W: Vector2i(3, 0)}
## Outer corners by their two open sides.
const ART_OUTER := {N | E: Vector2i(0, 1), N | W: Vector2i(1, 1), S | E: Vector2i(2, 1), S | W: Vector2i(3, 1)}
const ART_INNER := {
	CORNER_TOP_RIGHT: Vector2i(0, 2), CORNER_TOP_LEFT: Vector2i(1, 2),
	CORNER_BOTTOM_RIGHT: Vector2i(2, 2), CORNER_BOTTOM_LEFT: Vector2i(3, 2),
}
const ART_VOID: Array[Vector2i] = [Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3)]
## Means "draw a delivered void tile" (cell_for returns it for an enclosed pit).
const VOID := Vector2i(-1, -1)


## Piece of a pit tile: atlas coords in SOURCE_ID, or VOID for an enclosed pit. is_pit(tile) -> bool
## answers for the neighbours (bridges count as pit).
static func cell_for(tile: Vector2i, is_pit: Callable) -> Vector2i:
	var mask := 0
	if is_pit.call(tile + Vector2i.UP):
		mask |= N
	if is_pit.call(tile + Vector2i.RIGHT):
		mask |= E
	if is_pit.call(tile + Vector2i.DOWN):
		mask |= S
	if is_pit.call(tile + Vector2i.LEFT):
		mask |= W
	var corners := 0
	if mask & N and mask & W and not is_pit.call(tile + Vector2i(-1, -1)):
		corners |= CORNER_TOP_LEFT
	if mask & N and mask & E and not is_pit.call(tile + Vector2i(1, -1)):
		corners |= CORNER_TOP_RIGHT
	if mask & S and mask & W and not is_pit.call(tile + Vector2i(-1, 1)):
		corners |= CORNER_BOTTOM_LEFT
	if mask & S and mask & E and not is_pit.call(tile + Vector2i(1, 1)):
		corners |= CORNER_BOTTOM_RIGHT
	if mask == FULL and corners == 0:
		return VOID
	return Vector2i(mask, corners)


## Adds the combined pieces to tileset once (shared by every room using it). False without the
## delivered abyss source, and in the editor (the shared .tres must never be saved with it).
static func ensure_source(tileset: TileSet) -> bool:
	if tileset == null or Engine.is_editor_hint():
		return false
	if tileset.has_source(SOURCE_ID):
		return true
	var art := tileset.get_source(ART_SOURCE_ID) as TileSetAtlasSource if tileset.has_source(ART_SOURCE_ID) else null
	if art == null or art.texture == null:
		return false
	var image := art.texture.get_image()
	if image == null:
		return false
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(build_atlas(image))
	source.texture_region_size = Vector2i(TILE, TILE)
	tileset.add_source(source, SOURCE_ID)
	var half := TILE / 2.0
	var box := PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
	var has_pit_layer := tileset.get_physics_layers_count() > PHYSICS_LAYER
	for corners in 16:
		for mask in 16:
			var coords := Vector2i(mask, corners)
			source.create_tile(coords)
			if has_pit_layer:
				var data := source.get_tile_data(coords, 0)
				data.add_collision_polygon(PHYSICS_LAYER)
				data.set_collision_polygon_points(PHYSICS_LAYER, 0, box)
	return true


## The whole atlas (16 x 16 tiles) from the delivered 4 x 4 abyss art.
static func build_atlas(art: Image) -> Image:
	if art.is_compressed():
		art.decompress()
	art.convert(Image.FORMAT_RGBA8)
	var atlas := Image.create_empty(16 * TILE, 16 * TILE, false, Image.FORMAT_RGBA8)
	for corners in 16:
		for mask in 16:
			atlas.blit_rect(make_piece(art, mask, corners), Rect2i(0, 0, TILE, TILE), Vector2i(mask, corners) * TILE)
	return atlas


## One piece: mask = pit neighbours, corners = inner corners (see cell_for).
static func make_piece(art: Image, mask: int, corners: int) -> Image:
	var open := FULL & ~mask
	if corners == 0:
		if ART_EDGE.has(open):
			return _region(art, ART_EDGE[open])
		if ART_OUTER.has(open):
			return _region(art, ART_OUTER[open])
	var tile := _region(art, ART_VOID[0])
	for side: int in [N, E, S, W]:
		if open & side:
			var strip := _side_rect(side)
			tile.blit_rect(_region(art, ART_EDGE[side]), strip, strip.position)
	for pair: int in ART_OUTER:
		if (open & pair) == pair:
			var square := _corner_rect(pair)
			tile.blit_rect(_region(art, ART_OUTER[pair]), square, square.position)
	for corner: int in ART_INNER:
		if corners & corner:
			var square := _corner_rect(_sides_of_corner(corner))
			tile.blit_rect(_region(art, ART_INNER[corner]), square, square.position)
	return tile


static func _side_rect(side: int) -> Rect2i:
	match side:
		N:
			return Rect2i(0, 0, TILE, RIM_DEPTH)
		S:
			return Rect2i(0, TILE - RIM_DEPTH, TILE, RIM_DEPTH)
		W:
			return Rect2i(0, 0, RIM_DEPTH, TILE)
	return Rect2i(TILE - RIM_DEPTH, 0, RIM_DEPTH, TILE)


## Corner square (RIM_DEPTH) where the two sides of pair meet.
static func _corner_rect(pair: int) -> Rect2i:
	var x := 0 if pair & W else TILE - RIM_DEPTH
	var y := 0 if pair & N else TILE - RIM_DEPTH
	return Rect2i(x, y, RIM_DEPTH, RIM_DEPTH)


static func _sides_of_corner(corner: int) -> int:
	match corner:
		CORNER_TOP_LEFT:
			return N | W
		CORNER_TOP_RIGHT:
			return N | E
		CORNER_BOTTOM_LEFT:
			return S | W
	return S | E


static func _region(image: Image, tile: Vector2i) -> Image:
	return image.get_region(Rect2i(tile * TILE, Vector2i(TILE, TILE)))

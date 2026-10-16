class_name AbyssRims
extends RefCounted
## The abyss pieces of the terrain rooms with round, joined rim corners (playtest 15.10.2026, notes
## 15 and 16: "connect cleanly"). AbyssAutotile composes every piece from the delivered edges and
## lays the delivered corner squares into its corners, whose wavy light line does not meet the
## lines of the edges beside them. Here the same pieces get corners of their own: the rim of the two
## edges runs round the corner point - an outer corner as a quarter ring inside the square, an inner
## corner as a quarter ring around the floor's corner - every pixel taking the edge profile of the
## nearer edge at its distance, so the light and dark lines run on without a break. Straight edges
## stay the delivered ones.
## Same layout and rules as AbyssAutotile (column = pit neighbour mask, row = inner corners; solid
## on the pit physics layer, no navigation), in its own atlas source added at runtime.

const SOURCE_ID := 27
const TILE := AbyssAutotile.TILE
## Depth of the rim (art px, the delivered edges) and the radius of a rounded outer corner.
const RIM := AbyssAutotile.RIM_DEPTH
const RADIUS := 8.0
const N := AbyssAutotile.N
const E := AbyssAutotile.E
const S := AbyssAutotile.S
const W := AbyssAutotile.W
## The four corners: [corner bit of the inner corner, vertical side, horizontal side, corner point].
const CORNERS: Array = [
	[AbyssAutotile.CORNER_TOP_LEFT, N, W, Vector2(0, 0)],
	[AbyssAutotile.CORNER_TOP_RIGHT, N, E, Vector2(TILE, 0)],
	[AbyssAutotile.CORNER_BOTTOM_LEFT, S, W, Vector2(0, TILE)],
	[AbyssAutotile.CORNER_BOTTOM_RIGHT, S, E, Vector2(TILE, TILE)],
]


## Adds the pieces to tileset once (shared by every room using it). False without the delivered
## abyss art and in the editor.
static func ensure_source(tileset: TileSet) -> bool:
	if tileset == null or Engine.is_editor_hint():
		return false
	if tileset.has_source(SOURCE_ID):
		return true
	var art_source := tileset.get_source(AbyssAutotile.ART_SOURCE_ID) as TileSetAtlasSource if tileset.has_source(AbyssAutotile.ART_SOURCE_ID) else null
	if art_source == null or art_source.texture == null:
		return false
	var art := art_source.texture.get_image()
	if art == null:
		return false
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(build_atlas(art))
	source.texture_region_size = Vector2i(TILE, TILE)
	tileset.add_source(source, SOURCE_ID)
	var half := TILE / 2.0
	var box := PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
	var has_pit_layer := tileset.get_physics_layers_count() > AbyssAutotile.PHYSICS_LAYER
	for corners in 16:
		for mask in 16:
			var coords := Vector2i(mask, corners)
			source.create_tile(coords)
			if has_pit_layer:
				var data := source.get_tile_data(coords, 0)
				data.add_collision_polygon(AbyssAutotile.PHYSICS_LAYER)
				data.set_collision_polygon_points(AbyssAutotile.PHYSICS_LAYER, 0, box)
	return true


## The whole atlas (16 x 16 pieces): AbyssAutotile's pieces with the round corners laid in.
static func build_atlas(art: Image) -> Image:
	if art.is_compressed():
		art.decompress()
	art.convert(Image.FORMAT_RGBA8)
	var atlas := Image.create_empty(16 * TILE, 16 * TILE, false, Image.FORMAT_RGBA8)
	for corners in 16:
		for mask in 16:
			atlas.blit_rect(make_piece(art, mask, corners), Rect2i(0, 0, TILE, TILE), Vector2i(mask, corners) * TILE)
	return atlas


static var _patches: Dictionary[int, Array] = {}


## One piece (mask = pit neighbours, corners = inner corners, see AbyssAutotile.cell_for) with the
## round corners.
static func make_piece(art: Image, mask: int, corners: int) -> Image:
	var key := art.get_instance_id()
	if not _patches.has(key):
		var built: Array = []
		for corner: Array in CORNERS:
			built.append([corner_patch(art, corner, true), corner_patch(art, corner, false)])
		_patches[key] = built
	var patches: Array = _patches[key]
	var piece := AbyssAutotile.make_piece(art, mask, corners)
	var open := AbyssAutotile.FULL & ~mask
	for i in CORNERS.size():
		var corner: Array = CORNERS[i]
		var square := _square(corner)
		if open & int(corner[1]) and open & int(corner[2]):
			piece.blit_rect(patches[i][0], Rect2i(Vector2i.ZERO, square.size), square.position)
		elif corners & int(corner[0]):
			piece.blit_rect(patches[i][1], Rect2i(Vector2i.ZERO, square.size), square.position)
	return piece


## The corner square (RIM x RIM) of one corner, outer (both sides open: the rim turns round inside
## the square) or inner (both sides abyss, the diagonal open: the rim runs round the corner point).
static func corner_patch(art: Image, corner: Array, outer: bool) -> Image:
	var square := _square(corner)
	var point: Vector2 = corner[3]
	var void_tile := art.get_region(Rect2i(AbyssAutotile.ART_VOID[0] * TILE, Vector2i(TILE, TILE)))
	var patch := Image.create_empty(square.size.x, square.size.y, false, Image.FORMAT_RGBA8)
	for y in square.size.y:
		for x in square.size.x:
			var tile_x := square.position.x + x
			var tile_y := square.position.y + y
			var dx := absf(tile_x + 0.5 - point.x)
			var dy := absf(tile_y + 0.5 - point.y)
			var depth := 0.0
			if outer:
				depth = maxf(0.0, RADIUS - Vector2(RADIUS - dx, RADIUS - dy).length()) if dx < RADIUS and dy < RADIUS else minf(dx, dy)
			else:
				depth = Vector2(dx, dy).length()
			# The nearer edge lends its profile: the vertical side (N/S) along x, the other along y.
			var side: int = corner[1] if dy <= dx else corner[2]
			var index := tile_x if side == N or side == S else tile_y
			patch.set_pixel(x, y, profile(art, void_tile, side, index, int(depth), tile_x, tile_y))
	return patch


## Colour of the delivered rim of side at index along the edge and depth from the open side; the
## void beyond the rim.
static func profile(art: Image, void_tile: Image, side: int, index: int, depth: int, x: int, y: int) -> Color:
	if depth >= RIM:
		return void_tile.get_pixel(x, y)
	var edge: Vector2i = AbyssAutotile.ART_EDGE[side] * TILE
	index = clampi(index, 0, TILE - 1)
	match side:
		N:
			return art.get_pixel(edge.x + index, edge.y + depth)
		S:
			return art.get_pixel(edge.x + index, edge.y + TILE - 1 - depth)
		W:
			return art.get_pixel(edge.x + depth, edge.y + index)
	return art.get_pixel(edge.x + TILE - 1 - depth, edge.y + index)


static func _square(corner: Array) -> Rect2i:
	var point: Vector2 = corner[3]
	return Rect2i(0 if point.x == 0 else TILE - RIM, 0 if point.y == 0 else TILE - RIM, RIM, RIM)

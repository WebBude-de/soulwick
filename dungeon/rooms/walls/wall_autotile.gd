class_name WallAutotile
extends RefCounted
## One rule for every wall of a room, outer and inner (docs/design/sprites/SPRITES_V6.md, D-110, decisions of the
## orchestrator 14.10.2026), derived from a floor mask (RoomTiles.get_floor_mask()):
## - every tile that is not floor is solid; cut-out corners of a shape are rock like the area
##   around the room, bounded like the room's own edges;
## - a solid tile with floor directly below it (and solid above it) is a brick front: one row, only
##   above floor, never two fronts on top of each other, never a front without a crown above;
## - every other solid tile is a crown with a light edge on each side that borders floor or a front
##   (where the wall top drops), no edge between crowns; an enclosed crown is plain rock.
##
## The pieces live in an extra atlas source (SOURCE_ID) that is added to a dungeon TileSet at
## runtime, so tools/build_tilesets.gd stays untouched: rows 0-15 hold the crowns, column = 4-bit
## mask of crown neighbours (N=1, E=2, S=4, W=8), row = 4-bit mask of inner corners (top-left=1,
## top-right=2, bottom-left=4, bottom-right=8: both sides crown, the diagonal not); row 16 holds the
## fronts (left, middle, right, single, second middle pattern). Every piece is solid (physics layer
## 0) and has no navigation. Delivered art (art/environment/tiles/wall_autotile_<biome>.png, 4x5
## tiles, and wall_inner_corner_<biome>.png, 4x1) is used as soon as it exists; until then the
## pieces are drawn from the biome tileset's own outer wall: its plain crown, its brick fronts and
## its edge profile.

const SOURCE_ID := 10
const TILE := 32
const ART_PATH := "res://art/environment/tiles/wall_autotile_%s.png"
const CORNER_ART_PATH := "res://art/environment/tiles/wall_inner_corner_%s.png"
## Ground atlas tiles of the biome tilesets (RoomTiles): plain crown, brick front, south wall top
## (its first rows are the outer wall's edge profile).
const GROUND_CROWN := Vector2i(4, 0)
const GROUND_FRONT := Vector2i(5, 0)
const GROUND_FRONT_ALT := Vector2i(6, 0)
const GROUND_EDGE := Vector2i(0, 1)
## Edge depth in art pixels (outer wall: two light rows, one mid row).
const EDGE_DEPTH := 3

const N := 1
const E := 2
const S := 4
const W := 8
const CORNER_TOP_LEFT := 1
const CORNER_TOP_RIGHT := 2
const CORNER_BOTTOM_LEFT := 4
const CORNER_BOTTOM_RIGHT := 8
const FRONT_ROW := 16
enum Front { LEFT, MIDDLE, RIGHT, SINGLE, MIDDLE_ALT }
## Enclosed crown: drawn as the ground atlas's plain wall top (same as the rock around the room).
const ROCK := Vector2i(-1, -1)


static func crown_coords(mask: int, corners: int) -> Vector2i:
	return Vector2i(mask, corners)


static func front_coords(front: Front) -> Vector2i:
	return Vector2i(front, FRONT_ROW)


## Piece of a solid tile from the floor mask (keys = floor tiles; everything else is solid):
## front coords, crown coords or ROCK.
static func cell_for_floor(tile: Vector2i, floor_mask: Dictionary[Vector2i, bool]) -> Vector2i:
	if is_front(tile, floor_mask):
		var left := floor_mask.has(tile + Vector2i.LEFT)
		var right := floor_mask.has(tile + Vector2i.RIGHT)
		if left and right:
			return front_coords(Front.SINGLE)
		if left:
			return front_coords(Front.LEFT)
		return front_coords(Front.RIGHT) if right else front_coords(Front.MIDDLE)
	var mask := 0
	if _is_crown(tile + Vector2i.UP, floor_mask):
		mask |= N
	if _is_crown(tile + Vector2i.RIGHT, floor_mask):
		mask |= E
	if _is_crown(tile + Vector2i.DOWN, floor_mask):
		mask |= S
	if _is_crown(tile + Vector2i.LEFT, floor_mask):
		mask |= W
	var corners := 0
	if mask & N and mask & W and not _is_crown(tile + Vector2i(-1, -1), floor_mask):
		corners |= CORNER_TOP_LEFT
	if mask & N and mask & E and not _is_crown(tile + Vector2i(1, -1), floor_mask):
		corners |= CORNER_TOP_RIGHT
	if mask & S and mask & W and not _is_crown(tile + Vector2i(-1, 1), floor_mask):
		corners |= CORNER_BOTTOM_LEFT
	if mask & S and mask & E and not _is_crown(tile + Vector2i(1, 1), floor_mask):
		corners |= CORNER_BOTTOM_RIGHT
	if mask == 15 and corners == 0:
		return ROCK
	return crown_coords(mask, corners)


## Solid tile with floor right below and a solid tile above (the crown it hangs from).
static func is_front(tile: Vector2i, floor_mask: Dictionary[Vector2i, bool]) -> bool:
	return not floor_mask.has(tile) and floor_mask.has(tile + Vector2i.DOWN) and not floor_mask.has(tile + Vector2i.UP)


static func _is_crown(tile: Vector2i, floor_mask: Dictionary[Vector2i, bool]) -> bool:
	return not floor_mask.has(tile) and not is_front(tile, floor_mask)


## Piece of a wall tile inside mass for a plain room of room_size (tests, tools): the floor is the
## rectangle without the mass.
static func cell_for(tile: Vector2i, mass: Dictionary[Vector2i, bool], room_size: Vector2i) -> Vector2i:
	var floor_mask: Dictionary[Vector2i, bool] = {}
	for y in room_size.y:
		for x in room_size.x:
			if not mass.has(Vector2i(x, y)):
				floor_mask[Vector2i(x, y)] = true
	return cell_for_floor(tile, floor_mask)


## No wall between two floors: a wall tile with floor below needs a solid tile above (its crown),
## so every wall above floor is at least two tiles tall. Tiles outside the room count as solid.
static func is_valid_mass(mass: Dictionary[Vector2i, bool], room_size: Vector2i) -> bool:
	var floor_rect := Rect2i(Vector2i.ZERO, room_size)
	for tile: Vector2i in mass:
		var below := tile + Vector2i.DOWN
		var above := tile + Vector2i.UP
		if floor_rect.has_point(below) and not mass.has(below) and floor_rect.has_point(above) and not mass.has(above):
			return false
	return true


## Adds the wall source to tileset once (shared by every room using it). Returns false without a
## ground atlas to derive the pieces from, and in the editor: the shared .tres must never be saved
## with the generated source (rooms show plain pillar tiles there).
static func ensure_source(tileset: TileSet) -> bool:
	if tileset == null or Engine.is_editor_hint():
		return false
	if tileset.has_source(SOURCE_ID):
		return true
	var ground := tileset.get_source(0) as TileSetAtlasSource if tileset.has_source(0) else null
	if ground == null or ground.texture == null:
		return false
	var image := build_atlas(ground.texture.get_image(), biome_of(tileset))
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(TILE, TILE)
	tileset.add_source(source, SOURCE_ID)
	var half := TILE / 2.0
	var box := PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
	var has_physics := tileset.get_physics_layers_count() > 0
	for y in FRONT_ROW + 1:
		for x in 16:
			if y == FRONT_ROW and x >= Front.size():
				break
			var coords := Vector2i(x, y)
			source.create_tile(coords)
			if has_physics:
				var data := source.get_tile_data(coords, 0)
				data.add_collision_polygon(0)
				data.set_collision_polygon_points(0, 0, box)
	return true


## Biome id of a dungeon tileset, from its ground texture (dungeon_tileset.png = crypt).
static func biome_of(tileset: TileSet) -> StringName:
	var ground := tileset.get_source(0) as TileSetAtlasSource if tileset.has_source(0) else null
	if ground == null or ground.texture == null:
		return &"crypt"
	var file := ground.texture.resource_path.get_file().get_basename()
	if file.is_empty() or file == "dungeon_tileset":
		return &"crypt"
	return StringName(file.trim_suffix("_tileset"))


## The whole atlas (16 x 17 tiles) for one biome.
static func build_atlas(ground: Image, biome_id: StringName) -> Image:
	if ground.is_compressed():
		ground.decompress()
	ground.convert(Image.FORMAT_RGBA8)
	var delivered := _load_art(ART_PATH % biome_id)
	var delivered_corners := _load_art(CORNER_ART_PATH % biome_id)
	var profile := edge_profile(ground)
	var atlas := Image.create_empty(16 * TILE, (FRONT_ROW + 1) * TILE, false, Image.FORMAT_RGBA8)
	for mask in 16:
		var crown: Image = _region(delivered, Vector2i(mask % 4, mask / 4)) if delivered != null else make_crown(_region(ground, GROUND_CROWN), mask, profile)
		for corners in 16:
			var tile := crown.duplicate() as Image
			_add_corners(tile, corners, profile, delivered_corners)
			atlas.blit_rect(tile, Rect2i(0, 0, TILE, TILE), Vector2i(mask, corners) * TILE)
	for front in Front.size():
		var piece: Image
		if delivered != null:
			# The delivered sheet has one middle front; the second pattern repeats it.
			piece = _region(delivered, Vector2i(Front.MIDDLE if front == Front.MIDDLE_ALT else front, 4))
		else:
			var base := GROUND_FRONT_ALT if front == Front.MIDDLE_ALT else GROUND_FRONT
			piece = make_front(_region(ground, base), front as Front, profile)
		atlas.blit_rect(piece, Rect2i(0, 0, TILE, TILE), Vector2i(front, FRONT_ROW) * TILE)
	return atlas


## Edge colours of the outer wall, from the outside in (top rows of the south wall's top tile).
static func edge_profile(ground: Image) -> Array[Color]:
	var profile: Array[Color] = []
	var origin := GROUND_EDGE * TILE
	for depth in EDGE_DEPTH:
		profile.append(ground.get_pixel(origin.x + TILE / 2, origin.y + depth))
	return profile


## Plain crown with an edge on every side whose mask bit is 0 (floor there).
static func make_crown(base: Image, mask: int, profile: Array[Color]) -> Image:
	var tile := base.duplicate() as Image
	var sides: Array[int] = []
	for side in [N, E, S, W]:
		if not mask & side:
			sides.append(side)
	# Inner rows first, so the light outer rows win where two edges meet.
	for depth in range(profile.size() - 1, -1, -1):
		for side in sides:
			_edge_line(tile, side, depth, profile[depth])
	return tile


## Brick front with the edge profile down its open sides.
static func make_front(base: Image, front: Front, profile: Array[Color]) -> Image:
	var tile := base.duplicate() as Image
	var sides: Array[int] = []
	if front == Front.LEFT or front == Front.SINGLE:
		sides.append(W)
	if front == Front.RIGHT or front == Front.SINGLE:
		sides.append(E)
	for depth in range(profile.size() - 1, -1, -1):
		for side in sides:
			_edge_line(tile, side, depth, profile[depth])
	return tile


static func _edge_line(tile: Image, side: int, depth: int, color: Color) -> void:
	match side:
		N:
			tile.fill_rect(Rect2i(0, depth, TILE, 1), color)
		S:
			tile.fill_rect(Rect2i(0, TILE - 1 - depth, TILE, 1), color)
		W:
			tile.fill_rect(Rect2i(depth, 0, 1, TILE), color)
		E:
			tile.fill_rect(Rect2i(TILE - 1 - depth, 0, 1, TILE), color)


## Inner corners: the edge only as a small corner piece (delivered file or drawn).
static func _add_corners(tile: Image, corners: int, profile: Array[Color], delivered: Image) -> void:
	var order: Array[int] = [CORNER_TOP_LEFT, CORNER_TOP_RIGHT, CORNER_BOTTOM_LEFT, CORNER_BOTTOM_RIGHT]
	for i in order.size():
		if not corners & order[i]:
			continue
		if delivered != null:
			tile.blend_rect(_region(delivered, Vector2i(i, 0)), Rect2i(0, 0, TILE, TILE), Vector2i.ZERO)
			continue
		var right := order[i] == CORNER_TOP_RIGHT or order[i] == CORNER_BOTTOM_RIGHT
		var bottom := order[i] == CORNER_BOTTOM_LEFT or order[i] == CORNER_BOTTOM_RIGHT
		for dy in profile.size():
			for dx in profile.size():
				var x := TILE - 1 - dx if right else dx
				var y := TILE - 1 - dy if bottom else dy
				tile.set_pixel(x, y, profile[maxi(dx, dy)])


static func _region(image: Image, tile: Vector2i) -> Image:
	return image.get_region(Rect2i(tile * TILE, Vector2i(TILE, TILE)))


static func _load_art(path: String) -> Image:
	if not ResourceLoader.exists(path):
		return null
	var texture := load(path) as Texture2D
	if texture == null:
		return null
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image

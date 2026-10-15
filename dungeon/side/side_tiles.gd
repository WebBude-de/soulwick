class_name SideTiles
extends RefCounted
## Tiles of a side segment (M5): rock masses from the 47-piece blob set of the biome
## (art/environment/tiles/rock_blob_<biome>[_soft].png, piece name r<mask>, 8-bit neighbour mask
## N=1 NE=2 E=4 SE=8 S=16 SW=32 W=64 NW=128, a corner bit only when both of its sides are rock) and
## ledges from the same set's fronts (front_left/mid/right/single) as one-way platforms. The TileSet
## is built at runtime from the sheet and its JSON (cached per biome, never saved). Collision on the
## world layer: rock = full tile, ledge = a one-way strip at the top.

const TILES_DIR := "res://art/environment/tiles/"
const FALLBACK_BIOME := &"crypt"
const TILE_PX := 32
const SOURCE_ID := 0
## Height of a ledge's one-way collision strip in art px.
const LEDGE_DEPTH := 10.0
## Rock rows drawn below the plan, so the camera can show the lowest floor above the HUD.
const DEPTH_ROWS := 3
## Pieces of the sheet that are no rock (other uses of the set, padding).
const SKIPPED := ["cave_mouth_a", "pad"]
## The soft palette sets of the other biomes are palette swaps of crypt_soft (M1, tools/
## build_tilesets.gd) and share its layout file.
const SOFT_LAYOUT := "rock_blob_crypt_soft"

static var _sets: Dictionary[StringName, TileSet] = {}
static var _coords: Dictionary[StringName, Dictionary] = {}


## Sheet of a biome (path without extension): the soft palette set when it exists (M1, the same look
## as the rooms), else the delivered set, else the crypt's.
static func sheet_path(biome_id: StringName) -> String:
	for candidate in ["rock_blob_%s_soft" % biome_id, "rock_blob_%s" % biome_id, "rock_blob_%s" % FALLBACK_BIOME]:
		if ResourceLoader.exists(TILES_DIR + candidate + ".png") and not layout_path(candidate).is_empty():
			return TILES_DIR + candidate
	return ""


## JSON with the piece names of a sheet: its own, or crypt_soft's for a soft palette swap.
static func layout_path(sheet: String) -> String:
	var own := TILES_DIR + sheet + ".json"
	if FileAccess.file_exists(own):
		return own
	if sheet.ends_with("_soft") and FileAccess.file_exists(TILES_DIR + SOFT_LAYOUT + ".json"):
		return TILES_DIR + SOFT_LAYOUT + ".json"
	return ""


static func tileset_for(biome_id: StringName) -> TileSet:
	if _sets.has(biome_id):
		return _sets[biome_id]
	var path := sheet_path(biome_id)
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE_PX, TILE_PX)
	tileset.add_physics_layer()
	tileset.set_physics_layer_collision_layer(0, PhysicsLayers.WORLD)
	tileset.set_physics_layer_collision_mask(0, 0)
	var names := {}
	if not path.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(layout_path(path.get_file())))
		var pieces: Dictionary = (parsed as Dictionary).get("tiles", {}) if parsed is Dictionary else {}
		var source := TileSetAtlasSource.new()
		source.texture = load(path + ".png") as Texture2D
		source.texture_region_size = Vector2i(TILE_PX, TILE_PX)
		tileset.add_source(source, SOURCE_ID)
		for piece_name: String in pieces:
			if SKIPPED.has(piece_name):
				continue
			var piece: Dictionary = pieces[piece_name]
			var coords := Vector2i(int(piece.get("col", 0)), int(piece.get("row", 0)))
			if source.has_tile(coords):
				continue
			source.create_tile(coords)
			names[piece_name] = coords
			var data := source.get_tile_data(coords, 0)
			var half := TILE_PX * 0.5
			data.add_collision_polygon(0)
			if piece_name.begins_with("front_"):
				data.set_collision_polygon_points(0, 0, PackedVector2Array([
					Vector2(-half, -half), Vector2(half, -half), Vector2(half, -half + LEDGE_DEPTH), Vector2(-half, -half + LEDGE_DEPTH)]))
				data.set_collision_polygon_one_way(0, 0, true)
			else:
				data.set_collision_polygon_points(0, 0, PackedVector2Array([
					Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]))
	_sets[biome_id] = tileset
	_coords[biome_id] = names
	return tileset


## 8-bit neighbour mask of a rock cell with the corner rule applied.
static func rock_mask(layout: SideLayout, cell: Vector2i) -> int:
	var n := _rock_for_mask(layout, cell + Vector2i.UP)
	var e := _rock_for_mask(layout, cell + Vector2i.RIGHT)
	var s := _rock_for_mask(layout, cell + Vector2i.DOWN)
	var w := _rock_for_mask(layout, cell + Vector2i.LEFT)
	var mask := (1 if n else 0) | (4 if e else 0) | (16 if s else 0) | (64 if w else 0)
	if n and e and _rock_for_mask(layout, cell + Vector2i(1, -1)):
		mask |= 2
	if s and e and _rock_for_mask(layout, cell + Vector2i(1, 1)):
		mask |= 8
	if s and w and _rock_for_mask(layout, cell + Vector2i(-1, 1)):
		mask |= 32
	if n and w and _rock_for_mask(layout, cell + Vector2i(-1, -1)):
		mask |= 128
	return mask


## Front piece of a ledge cell from its ledge neighbours.
static func ledge_piece(layout: SideLayout, cell: Vector2i) -> String:
	var left := layout.is_ledge(cell + Vector2i.LEFT)
	var right := layout.is_ledge(cell + Vector2i.RIGHT)
	if left and right:
		return "front_mid"
	if right:
		return "front_left"
	if left:
		return "front_right"
	return "front_single"


## Paints rock and ledges of layout into layer (scaled ×2 by the caller).
static func paint(layer: TileMapLayer, layout: SideLayout, biome_id: StringName) -> void:
	layer.tile_set = tileset_for(biome_id)
	var names: Dictionary = _coords.get(biome_id, {})
	if names.is_empty():
		return
	for row in layout.size.y:
		for column in layout.size.x:
			var cell := Vector2i(column, row)
			var piece := ""
			if layout.is_rock(cell):
				piece = "r%d" % rock_mask(layout, cell)
				if not names.has(piece):
					piece = "r255"
			elif layout.is_ledge(cell):
				piece = ledge_piece(layout, cell)
			if piece.is_empty() or not names.has(piece):
				continue
			layer.set_cell(cell, SOURCE_ID, names[piece])
	# Below the plan the rock goes on (pits stay open, they fall into the dark).
	for row in range(layout.size.y, layout.size.y + DEPTH_ROWS):
		for column in layout.size.x:
			var cell := Vector2i(column, row)
			if not layout.is_rock(Vector2i(column, layout.size.y - 1)):
				continue
			var piece := "r%d" % rock_mask(layout, cell)
			layer.set_cell(cell, SOURCE_ID, names[piece] if names.has(piece) else names.get("r255", Vector2i.ZERO))


## One piece of the biome's sheet as a texture (crumbling ledges draw themselves with it), or null.
static func piece_texture(biome_id: StringName, piece: String) -> AtlasTexture:
	var tileset := tileset_for(biome_id)
	var names: Dictionary = _coords.get(biome_id, {})
	if not names.has(piece) or not tileset.has_source(SOURCE_ID):
		return null
	var source := tileset.get_source(SOURCE_ID) as TileSetAtlasSource
	var coords: Vector2i = names[piece]
	var atlas := AtlasTexture.new()
	atlas.atlas = source.texture
	atlas.region = Rect2(Vector2(coords * TILE_PX), Vector2(TILE_PX, TILE_PX))
	return atlas


## Rock for the drawing: the bottom row continues downwards (no rounded edge at the screen bottom).
static func _rock_for_mask(layout: SideLayout, cell: Vector2i) -> bool:
	if cell.y >= layout.size.y and cell.x >= 0 and cell.x < layout.size.x:
		return layout.is_rock(Vector2i(cell.x, layout.size.y - 1))
	return layout.is_rock(cell)

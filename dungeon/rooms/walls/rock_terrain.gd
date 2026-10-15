class_name RockTerrain
extends RefCounted
## Walls of every plan room as one 47-piece terrain (M1, Claude Design Makeover 3 §2.1/§10): the
## solid mass is drawn from a blob set (art/environment/tiles/rock_blob_<set>.png, piece name
## r<mask>, 8-bit neighbour mask N=1 NE=2 E=4 SE=8 S=16 SW=32 W=64 NW=128, bit = neighbour is solid,
## a corner bit only where both of its sides are solid) plus four fronts (left, middle, right,
## single) on every solid tile with floor right below it. Every border between floor and solid gets
## the same edge, outer and inner corners included (no missing corner bits).
## Two looks share the rule:
##   CAVE     cave rooms (plan rock: blob): the soft set (crypt_soft or its palette swap, SOFT_BIOMES)
##            with its seamless floor, zone floors and the flat rock around the room;
##   MASONRY  rest, boss, crypt halls, campfire (plan rock: wall): in the same soft palette as the
##            caves of the biome (playtest 14.10.2026: halls and caves of a biome match), the soft rock
##            with brick fronts on flagstones (masonry_<biome>_soft, tools/build_tilesets.gd); without
##            the soft set the delivered biome set with brick fronts on the biome's tile floor.
## Collision and navigation stay on the room layer (one tile = 32 art px): floor cells carry the
## navigation, solid cells an invisible collision tile. The pieces lie on a draw-only child layer,
## composited over the look's floor (the floor shows in their rounded corners). Fully enclosed rock
## is never drawn on that layer: the backdrop below every room shows it, so a room's plain rock can
## never cover the edge of a neighbouring room.
##
## Like WallAutotile (10) and AbyssAutotile (11) the pieces live in extra atlas sources that are
## added to a biome TileSet at runtime (never saved, never in the editor):
##   20 / 24  rock pieces of the cave / masonry look (8 x 7, order of the delivered sheet)
##   21       cave floor: row 0 = four floor variants with navigation; row 1 = an invisible solid
##            tile (collision on physics layer 0, no navigation) for every solid cell of both looks
##   22 / 26  zone floors (slab, cobble, dirt, rubble; row = zone) in 16 frayed variants (column =
##            4-bit mask N=1 E=2 S=4 W=8 of neighbours in the same zone), draw only
##   23       scatter overlays (crack, pebbles, tuft, bones, puddle, dust), draw only
##   25       masonry floor of the soft palette (flagstones, navigation)

enum Look { CAVE, MASONRY }

const SOURCE_ROCK := 20
const SOURCE_GROUND := 21
const SOURCE_ZONES := 22
const SOURCE_OVERLAY := 23
const SOURCE_MASONRY_ROCK := 24
const SOURCE_MASONRY_GROUND := 25
const SOURCE_MASONRY_ZONES := 26
const TILE := 32
const TILES_DIR := "res://art/environment/tiles/"
## Ground atlas of the biome tilesets (RoomTiles, source 0): plain floor and wall top.
const GROUND_FLOOR := Vector2i(0, 0)
const GROUND_WALL_TOP := Vector2i(4, 0)
## Invisible solid tile on SOURCE_GROUND.
const SOLID := Vector2i(0, 1)

## Per biome: true = the soft set for caves (crypt_soft or its palette swap by
## tools/build_tilesets.gd), false = the delivered biome set (rock_blob_<biome>, the biome's floor,
## floor_extra_<biome>). Soft wins in every biome after the comparison of 14.10.2026 (M1 report):
## seamless floor, light rock edge, rock and floor clearly apart; the delivered biome sets read as
## the old dark wall with brick fronts and stay the masonry look. TESTWERT
const SOFT_BIOMES: Dictionary[StringName, bool] = {
	&"crypt": true,
	&"slime_grotto": true,
	&"shadow_realm": true,
	&"ember_forge": true,
}

## The 47 valid masks in the order of the delivered sheet (ascending), then the fronts.
const MASKS: Array[int] = [
	0, 1, 4, 5, 7, 16, 17, 20, 21, 23, 28, 29, 31, 64, 65, 68, 69, 71, 80, 81, 84, 85, 87, 92,
	93, 95, 112, 113, 116, 117, 119, 124, 125, 127, 193, 197, 199, 209, 213, 215, 221, 223, 241,
	245, 247, 253, 255,
]
const SHEET_COLUMNS := 8
enum Front { LEFT, MIDDLE, RIGHT, SINGLE }
const N := 1
const NE := 2
const E := 4
const SE := 8
const S := 16
const SW := 32
const W := 64
const NW := 128
## Fully enclosed rock.
const FULL := 255

## Zone floors (plan cells ';' slab, ',' cobble, ':' dirt, '%' rubble), the row in the zone source.
enum Zone { SLAB, COBBLE, DIRT, RUBBLE }
## Overlays (plan generator), the column in SOURCE_OVERLAY.
enum Overlay { CRACK, PEBBLES, TUFT, BONES, PUDDLE, DUST }
const OVERLAY_COUNT := 6
## Bit of an overlay code that mirrors the overlay (generator: code = overlay | FLIP_BIT * flip).
const FLIP_BIT := 8
## Frayed zone edges: art pixels over which a zone fades into the floor next to it (TESTWERT, look).
const ZONE_FRAY := 7
## Soft inner corners (M1, playtest 15.10.2026: no sharp 90 degree steps). The delivered pieces draw
## a light band along every straight edge but nothing where two edges meet at an inner corner: the
## sheet gets the band's corner joint drawn into those pieces, and a floor cell whose lower corner
## lies between two edges gets a small rounded fillet of rock (bits FILLET_LEFT / FILLET_RIGHT, the
## three sheet slots after the fronts). Band width in art px (the delivered sets: 4) and fillet
## radius (TESTWERT, look).
const BAND := 4
const FILLET_RADIUS := 5
const FILLET_LEFT := 1
const FILLET_RIGHT := 2
## Delivered inner corner set (SPRITES_V9 §1, %s = biome) and its fillet piece names (bits 1..3).
## Off (look, 15.10.2026): the delivered arcs sit 4-8 px around the corner point instead of joining
## the straight bands (a light blob in the corner), and the fill pieces are a convex bump of rock
## instead of a concave rounding; the drawn joints and fillets stay until a corrected set comes
## (SPRITES_V9 Nachlieferung). The loader stays ready: true uses the files where they exist.
const USE_DELIVERED_INNER := false
const INNER_SHEET := "rock_blob_%s_soft_inner.png"
const FILL_NAMES: Array[String] = ["fill_left", "fill_right", "fill_both"]
## Top edge piece (floor north of it) the band colours are read from.
const BAND_SAMPLE_MASK := E | SE | S | SW | W

static var _mask_index: Dictionary[int, int] = {}


## Atlas coords of a rock piece for an 8-bit neighbour mask (corner bits without both sides are
## dropped first).
static func rock_coords(mask: int) -> Vector2i:
	var index: int = _index_of(normalize(mask))
	return Vector2i(index % SHEET_COLUMNS, index / SHEET_COLUMNS)


static func front_coords(front: Front) -> Vector2i:
	var index := MASKS.size() + int(front)
	return Vector2i(index % SHEET_COLUMNS, index / SHEET_COLUMNS)


## Atlas coords of a fillet piece (bits FILLET_LEFT | FILLET_RIGHT, 1..3).
static func fillet_coords(bits: int) -> Vector2i:
	var index := MASKS.size() + Front.size() + clampi(bits, 1, 3) - 1
	return Vector2i(index % SHEET_COLUMNS, index / SHEET_COLUMNS)


## Fillets of a floor tile: a lower corner between rock on the side and rock below (both drawn as
## edges with the band; a front on the side ends with its own rounded corner instead).
static func fillet_bits(tile: Vector2i, floor_mask: Dictionary[Vector2i, bool]) -> int:
	if not floor_mask.has(tile) or floor_mask.has(tile + Vector2i.DOWN):
		return 0
	var bits := 0
	for side: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT]:
		var beside := tile + side
		if not floor_mask.has(beside) and not WallAutotile.is_front(beside, floor_mask):
			bits |= FILLET_LEFT if side == Vector2i.LEFT else FILLET_RIGHT
	return bits


## Corner bits count only where both sides are solid (47 distinct pieces).
static func normalize(mask: int) -> int:
	var result := mask & (N | E | S | W)
	if mask & NE and mask & N and mask & E:
		result |= NE
	if mask & SE and mask & S and mask & E:
		result |= SE
	if mask & SW and mask & S and mask & W:
		result |= SW
	if mask & NW and mask & N and mask & W:
		result |= NW
	return result


static func _index_of(mask: int) -> int:
	if _mask_index.is_empty():
		for i in MASKS.size():
			_mask_index[MASKS[i]] = i
	return _mask_index.get(mask, MASKS.size() - 1)


## Neighbour mask of a solid tile from the floor mask (keys = floor; everything else is solid,
## fronts included, so the crown above a front runs into it without an edge).
static func mask_for(tile: Vector2i, floor_mask: Dictionary[Vector2i, bool]) -> int:
	var mask := 0
	var bits: Array[int] = [N, NE, E, SE, S, SW, W, NW]
	var offsets: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]
	for i in bits.size():
		if not floor_mask.has(tile + offsets[i]):
			mask |= bits[i]
	return normalize(mask)


## Atlas coords of a solid tile. Fronts: solid with floor right below it and solid above it
## (WallAutotile.is_front), ending with a rounded corner where the front really ends: floor beside it
## or rock that is no front (a step back to a deeper front, the side wall; playtest 15.10.2026).
## faces: abyss tiles drawn with the same rock face in the same row (RoomTiles.get_cliff_faces); a
## front runs on into them without an end.
static func piece_for(tile: Vector2i, floor_mask: Dictionary[Vector2i, bool], faces: Dictionary[Vector2i, bool] = {}) -> Vector2i:
	if WallAutotile.is_front(tile, floor_mask):
		var left := not WallAutotile.is_front(tile + Vector2i.LEFT, floor_mask) and not faces.has(tile + Vector2i.LEFT)
		var right := not WallAutotile.is_front(tile + Vector2i.RIGHT, floor_mask) and not faces.has(tile + Vector2i.RIGHT)
		if left and right:
			return front_coords(Front.SINGLE)
		if left:
			return front_coords(Front.LEFT)
		return front_coords(Front.RIGHT) if right else front_coords(Front.MIDDLE)
	return rock_coords(mask_for(tile, floor_mask))


## Is the solid tile fully enclosed (no floor in its 8 neighbours)? Those stay to the backdrop.
static func is_enclosed(tile: Vector2i, floor_mask: Dictionary[Vector2i, bool]) -> bool:
	return not WallAutotile.is_front(tile, floor_mask) and mask_for(tile, floor_mask) == FULL


## Cave floor variant (0-3) on SOURCE_GROUND.
static func ground_coords(variant: int) -> Vector2i:
	return Vector2i(clampi(variant, 0, 3), 0)


## Zone piece: row = zone, column = 4-bit mask of neighbours in the same zone (N=1 E=2 S=4 W=8).
static func zone_coords(zone: int, same_mask: int) -> Vector2i:
	return Vector2i(same_mask & 15, clampi(zone, 0, Zone.size() - 1))


static func rock_source(look: Look) -> int:
	return SOURCE_ROCK if look == Look.CAVE else SOURCE_MASONRY_ROCK


static func zone_source(look: Look, tileset: TileSet = null) -> int:
	# Soft masonry shares the cave's zone floors (same palette).
	if look == Look.CAVE or (tileset != null and tileset.has_source(SOURCE_MASONRY_GROUND)):
		return SOURCE_ZONES
	return SOURCE_MASONRY_ZONES


## Cell of plain rock around a room of this look in a tileset: x, y = atlas coords, z = source id.
## Soft masonry shares the cave's rock; the delivered sets keep the stone wall top.
static func fill_cell(look: Look, tileset: TileSet = null) -> Vector3i:
	var full := rock_coords(FULL)
	if look == Look.CAVE:
		return Vector3i(full.x, full.y, SOURCE_ROCK)
	if tileset != null and tileset.has_source(SOURCE_MASONRY_GROUND):
		return Vector3i(full.x, full.y, SOURCE_MASONRY_ROCK)
	return Vector3i(GROUND_WALL_TOP.x, GROUND_WALL_TOP.y, 0)


## Source of the floor cells of a look (-1: the biome's own floor tiles on source 0).
static func floor_source(look: Look, tileset: TileSet) -> int:
	if look == Look.CAVE:
		return SOURCE_GROUND
	return SOURCE_MASONRY_GROUND if tileset != null and tileset.has_source(SOURCE_MASONRY_GROUND) else -1


static func is_soft(biome_id: StringName) -> bool:
	return SOFT_BIOMES.get(biome_id, true)


## Art of a biome for a look: rock pieces, floor (4 tiles), zone floors (4 tiles), overlays (6 tiles).
static func art_paths(biome_id: StringName, look: Look) -> Dictionary:
	if look == Look.MASONRY and is_soft(biome_id) and ResourceLoader.exists(TILES_DIR + ("masonry_%s_soft.png" % biome_id)):
		var cave := art_paths(biome_id, Look.CAVE)
		return {
			"rock": TILES_DIR + ("masonry_%s_soft.png" % biome_id),
			"floor": TILES_DIR + ("masonry_floor_%s_soft.png" % biome_id),
			"zones": cave["zones"],
			"overlay": cave["overlay"],
			"soft": true,
		}
	if look == Look.CAVE and is_soft(biome_id):
		var soft := "crypt_soft" if biome_id == &"crypt" else "%s_soft" % biome_id
		return {
			"rock": TILES_DIR + ("rock_blob_%s.png" % soft),
			"floor": TILES_DIR + ("%s_tileset.png" % soft),
			"zones": TILES_DIR + ("floor_zones_%s_soft.png" % biome_id),
			"overlay": TILES_DIR + ("overlay_crypt_soft.png" if biome_id == &"crypt" else "overlay_%s.png" % biome_id),
		}
	var ground := "dungeon_tileset" if biome_id == &"crypt" else "%s_tileset" % biome_id
	return {
		"rock": TILES_DIR + ("rock_blob_%s.png" % biome_id),
		"floor": TILES_DIR + ("%s.png" % ground),
		"zones": TILES_DIR + ("floor_extra_%s.png" % biome_id),
		"overlay": TILES_DIR + ("overlay_%s.png" % biome_id),
	}


## Adds the sources of both looks to tileset once (shared by every room using it). False in the
## editor and without the cave art (the room then keeps the old WallAutotile look).
static func ensure_sources(tileset: TileSet) -> bool:
	if tileset == null or Engine.is_editor_hint():
		return false
	if tileset.has_source(SOURCE_ROCK):
		return true
	var biome := WallAutotile.biome_of(tileset)
	var cave := art_paths(biome, Look.CAVE)
	var masonry := art_paths(biome, Look.MASONRY)
	var cave_rock := _load_image(cave["rock"])
	var cave_floor := _load_image(cave["floor"])
	var ground := tileset.get_source(0) as TileSetAtlasSource if tileset.has_source(0) else null
	if cave_rock == null or cave_floor == null or ground == null or ground.texture == null:
		return false
	var ground_image := ground.texture.get_image()
	if ground_image.is_compressed():
		ground_image.decompress()
	ground_image.convert(Image.FORMAT_RGBA8)
	var masonry_rock := _load_image(masonry["rock"])
	var inner := inner_pieces(biome)
	_add_rock_source(tileset, SOURCE_ROCK, compose_rock(cave_rock, cave_floor.get_region(Rect2i(0, 0, TILE, TILE)), inner))
	var soft_floor := _load_image(masonry["floor"]) if masonry.get("soft", false) else null
	if masonry_rock != null and soft_floor != null:
		# Soft masonry: its own flagstones (with navigation) under the soft rock with brick fronts.
		_add_rock_source(tileset, SOURCE_MASONRY_ROCK, compose_rock(masonry_rock, soft_floor.get_region(Rect2i(0, 0, TILE, TILE)), inner))
		_add_floor_source(tileset, SOURCE_MASONRY_GROUND, soft_floor)
	elif masonry_rock != null:
		var masonry_floor := ground_image.get_region(Rect2i(GROUND_FLOOR * TILE, Vector2i(TILE, TILE)))
		var wall_top := ground_image.get_pixel(GROUND_WALL_TOP.x * TILE + TILE / 2, TILE / 2)
		_add_rock_source(tileset, SOURCE_MASONRY_ROCK, compose_rock(recolor_fill(masonry_rock, wall_top), masonry_floor))
	_add_ground_source(tileset, cave_floor)
	for pair: Array in [[cave["zones"], SOURCE_ZONES], [masonry["zones"], SOURCE_MASONRY_ZONES]]:
		var zones := _load_image(pair[0])
		if zones == null:
			continue
		var zone_source := _add_source(tileset, pair[1], build_zones(zones))
		for zone in Zone.size():
			for mask in 16:
				zone_source.create_tile(Vector2i(mask, zone))
	var overlay := _load_image(cave["overlay"])
	if overlay != null:
		var overlay_source := _add_source(tileset, SOURCE_OVERLAY, overlay)
		for i in mini(OVERLAY_COUNT, overlay.get_width() / TILE):
			overlay_source.create_tile(Vector2i(i, 0))
	return true


static var _cliffs: Dictionary[StringName, Texture2D] = {}


## Rock face under the north edge of an abyss in a cave (the fronts of the cave set, 4 x 1 in the
## order left, middle, right, single, like abyss_cliff_<biome>); null without the art.
static func cliff_texture(biome_id: StringName) -> Texture2D:
	if _cliffs.has(biome_id):
		return _cliffs[biome_id]
	var sheet := _load_image(art_paths(biome_id, Look.CAVE)["rock"])
	if sheet == null:
		return null
	var image := Image.create_empty(TILE * Front.size(), TILE, false, Image.FORMAT_RGBA8)
	for front in Front.size():
		image.blit_rect(sheet, Rect2i(front_coords(front) * TILE, Vector2i(TILE, TILE)), Vector2i(front * TILE, 0))
	_cliffs[biome_id] = ImageTexture.create_from_image(image)
	return _cliffs[biome_id]


static func has_look(tileset: TileSet, look: Look) -> bool:
	return tileset != null and tileset.has_source(rock_source(look)) and tileset.has_source(SOURCE_GROUND)


static func _add_rock_source(tileset: TileSet, id: int, image: Image) -> void:
	var source := _add_source(tileset, id, image)
	for i in MASKS.size() + Front.size() + 3:
		source.create_tile(Vector2i(i % SHEET_COLUMNS, i / SHEET_COLUMNS))


## Cave floor (row 0, navigation) and the invisible solid tile (row 1, collision).
static func _add_ground_source(tileset: TileSet, floor_image: Image) -> void:
	var image := Image.create_empty(TILE * 4, TILE * 2, false, Image.FORMAT_RGBA8)
	image.blit_rect(floor_image, Rect2i(0, 0, TILE * 4, TILE), Vector2i.ZERO)
	var source := _add_source(tileset, SOURCE_GROUND, image)
	var half := TILE / 2.0
	var box := PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
	for x in 4:
		source.create_tile(Vector2i(x, 0))
		if tileset.get_navigation_layers_count() > 0:
			var navigation := NavigationPolygon.new()
			navigation.vertices = box
			navigation.add_polygon(PackedInt32Array([0, 1, 2, 3]))
			source.get_tile_data(Vector2i(x, 0), 0).set_navigation_polygon(0, navigation)
	source.create_tile(SOLID)
	if tileset.get_physics_layers_count() > 0:
		var data := source.get_tile_data(SOLID, 0)
		data.add_collision_polygon(0)
		data.set_collision_polygon_points(0, 0, box)


## Four floor tiles with navigation on their own source (soft masonry).
static func _add_floor_source(tileset: TileSet, id: int, floor_image: Image) -> void:
	var source := _add_source(tileset, id, floor_image.get_region(Rect2i(0, 0, TILE * 4, TILE)))
	var half := TILE / 2.0
	var box := PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
	for x in 4:
		source.create_tile(Vector2i(x, 0))
		if tileset.get_navigation_layers_count() > 0:
			var navigation := NavigationPolygon.new()
			navigation.vertices = box
			navigation.add_polygon(PackedInt32Array([0, 1, 2, 3]))
			source.get_tile_data(Vector2i(x, 0), 0).set_navigation_polygon(0, navigation)


## Every piece of sheet laid over floor (the floor shows where the piece is transparent).
static func compose_rock(sheet: Image, floor_tile: Image, inner: Dictionary = {}) -> Image:
	var result := Image.create_empty(sheet.get_width(), sheet.get_height(), false, Image.FORMAT_RGBA8)
	for y in sheet.get_height() / TILE:
		for x in sheet.get_width() / TILE:
			result.blit_rect(floor_tile, Rect2i(0, 0, TILE, TILE), Vector2i(x, y) * TILE)
	result.blend_rect(sheet, Rect2i(Vector2i.ZERO, sheet.get_size()), Vector2i.ZERO)
	var band := band_colors(sheet)
	var delivered: Dictionary = inner.get("pieces", {})
	_draw_inner_corners(result, band, delivered)
	_draw_fillets(result, band, delivered)
	return result


## The delivered inner corner set of a biome (rock_blob_<biome>_soft_inner, SPRITES_V9 §1), fitted to
## the room rock (SoftPalette): {"pieces": name -> 32x32 Image}. Empty without the files.
static func inner_pieces(biome_id: StringName) -> Dictionary:
	if not USE_DELIVERED_INNER:
		return {}
	var path := TILES_DIR + INNER_SHEET % biome_id
	var json_path := path.get_basename() + ".json"
	if not ResourceLoader.exists(path) or not FileAccess.file_exists(json_path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if not data is Dictionary or not (data as Dictionary).has("tiles"):
		return {}
	var image := SoftPalette.load_image(path)
	if image == null:
		return {}
	image = SoftPalette.fit(image, biome_id, biome_id)
	var pieces := {}
	var tiles: Dictionary = data["tiles"]
	for piece_name: String in tiles:
		var cell: Dictionary = tiles[piece_name]
		pieces[piece_name] = image.get_region(Rect2i(int(cell["x"]), int(cell["y"]), TILE, TILE))
	return {"pieces": pieces}


## The arcs of a delivered inner corner piece on a piece of the sheet: only its band and outline
## pixels (lighter than the rock or as dark as the outline); straight edges stay the sheet's own.
static func _lay_arcs(image: Image, origin: Vector2i, piece: Image, band: Array[Color]) -> void:
	var rock := image.get_pixel(origin.x + TILE / 2, origin.y + TILE / 2)
	var light_from := rock.get_luminance() + 0.12
	var dark_below := rock.get_luminance() - 0.12
	for y in TILE:
		for x in TILE:
			var pixel := piece.get_pixel(x, y)
			if pixel.a < 0.5:
				continue
			var luminance := pixel.get_luminance()
			if luminance > light_from or luminance < dark_below:
				image.set_pixel(origin.x + x, origin.y + y, pixel)


## Colours of the edge band from the outside in (BAND rows of the top edge piece).
static func band_colors(sheet: Image) -> Array[Color]:
	var origin := rock_coords(BAND_SAMPLE_MASK) * TILE
	var colors: Array[Color] = []
	for row in BAND:
		colors.append(sheet.get_pixel(origin.x + TILE / 2, origin.y + row))
	return colors


## The band's joint in every piece with an upper inner corner (both sides solid, the diagonal floor):
## a quarter ring around the corner point, so the side band and the top band run into each other.
## Lower inner corners touch a front, which ends with its own rounded corner.
static func _draw_inner_corners(image: Image, band: Array[Color], delivered: Dictionary = {}) -> void:
	for i in MASKS.size():
		var mask := MASKS[i]
		var origin := Vector2i(i % SHEET_COLUMNS, i / SHEET_COLUMNS) * TILE
		if delivered.has("r%d" % mask):
			_lay_arcs(image, origin, delivered["r%d" % mask], band)
			continue
		for corner: Array in [[NE, E, TILE], [NW, W, 0]]:
			if not mask & N or not mask & int(corner[1]) or mask & int(corner[0]):
				continue
			var corner_x: int = corner[2]
			for y in BAND:
				for x in range(0, BAND) if corner_x == 0 else range(TILE - BAND, TILE):
					var ring := int(Vector2(x + 0.5 - corner_x, y + 0.5).length())
					if ring < BAND:
						image.set_pixel(origin.x + x, origin.y + y, band[ring])


## Fillet pieces (transparent but for the rock in a rounded lower corner): slot 1 left, 2 right,
## 3 both. The rock inside the fillet takes the band colour of its distance to the curve.
static func _draw_fillets(image: Image, band: Array[Color], delivered: Dictionary = {}) -> void:
	for bits in range(1, 4):
		var origin := fillet_coords(bits) * TILE
		image.fill_rect(Rect2i(origin, Vector2i(TILE, TILE)), Color(0, 0, 0, 0))
		var file_name: String = FILL_NAMES[bits - 1]
		if delivered.has(file_name):
			image.blit_rect(delivered[file_name], Rect2i(0, 0, TILE, TILE), origin)
			continue
		for side: int in [FILLET_LEFT, FILLET_RIGHT]:
			if not bits & side:
				continue
			var center := Vector2(FILLET_RADIUS if side == FILLET_LEFT else TILE - FILLET_RADIUS, TILE - FILLET_RADIUS)
			for y in range(TILE - FILLET_RADIUS, TILE):
				for x in range(0, FILLET_RADIUS) if side == FILLET_LEFT else range(TILE - FILLET_RADIUS, TILE):
					var depth := Vector2(x + 0.5, y + 0.5).distance_to(center) - FILLET_RADIUS
					if depth > 0.0:
						image.set_pixel(origin.x + x, origin.y + y, band[clampi(int(depth), 0, BAND - 1)])


## The delivered set with its rock fill (the colour of the enclosed piece) in fill_color.
static func recolor_fill(sheet: Image, fill_color: Color) -> Image:
	var full := rock_coords(FULL) * TILE + Vector2i(TILE / 2, TILE / 2)
	var old := sheet.get_pixel(full.x, full.y)
	var result := sheet.duplicate() as Image
	for y in result.get_height():
		for x in result.get_width():
			var pixel := result.get_pixel(x, y)
			if pixel.a > 0.0 and pixel.is_equal_approx(Color(old.r, old.g, old.b, pixel.a)):
				result.set_pixel(x, y, Color(fill_color.r, fill_color.g, fill_color.b, pixel.a))
	return result


## Zone floors with frayed edges: every zone in 16 variants, the sides towards another floor fade
## out over ZONE_FRAY art pixels with a fixed dither (deterministic, no RNG).
static func build_zones(sheet: Image) -> Image:
	var atlas := Image.create_empty(TILE * 16, TILE * Zone.size(), false, Image.FORMAT_RGBA8)
	for zone in mini(Zone.size(), sheet.get_width() / TILE):
		var base := sheet.get_region(Rect2i(zone * TILE, 0, TILE, TILE))
		for mask in 16:
			var tile := base.duplicate() as Image
			for y in TILE:
				for x in TILE:
					var depth := ZONE_FRAY
					if not mask & 1:
						depth = mini(depth, y)
					if not mask & 2:
						depth = mini(depth, TILE - 1 - x)
					if not mask & 4:
						depth = mini(depth, TILE - 1 - y)
					if not mask & 8:
						depth = mini(depth, x)
					if depth >= ZONE_FRAY:
						continue
					# Ordered noise per art pixel: the closer to the open side, the fewer pixels stay.
					var noise := float(absi(hash(Vector3i(x, y, zone))) % 1000) / 1000.0
					if noise > (float(depth) + 0.5) / float(ZONE_FRAY):
						tile.set_pixel(x, y, Color(0, 0, 0, 0))
			atlas.blit_rect(tile, Rect2i(0, 0, TILE, TILE), Vector2i(mask, zone) * TILE)
	return atlas


static func _add_source(tileset: TileSet, id: int, image: Image) -> TileSetAtlasSource:
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(TILE, TILE)
	tileset.add_source(source, id)
	return source


static func _load_image(path: String) -> Image:
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

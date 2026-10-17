class_name RockTerrain
extends RefCounted
## Walls of every plan room as one 47-piece terrain (M1, Claude Design Makeover 3 §2.1/§10): the
## solid mass is drawn from a blob set (art/environment/tiles/rock_blob_<set>.png, piece name
## r<mask>, 8-bit neighbour mask N=1 NE=2 E=4 SE=8 S=16 SW=32 W=64 NW=128, bit = neighbour is solid,
## a corner bit only where both of its sides are solid) plus four fronts (left, middle, right,
## single) on every solid tile with floor right below it. Every border between floor and solid gets
## the same edge, outer and inner corners included (no missing corner bits). A front belongs to the
## edge too (playtest 15.10.2026, notes 4/7/10: "rounding at the front too", "the light edge belongs on
## top"): every front starts with the same light band as an edge (its top line, drawn in the front
## piece, so it never depends on which room owns the crown row above it), the side wall beside a
## front gets its edge up to that line with a joint, and where a block ends the crown's edge turns
## round into the line (crown variant with a rounded foot, the front face shows in the corner). A
## front only ends round where floor lies beside it; against rock it runs square into that edge.
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
##   20 / 24  rock pieces of the cave / masonry look (8 columns: the delivered sheet's 47 pieces and
##            4 fronts, 3 fillets, then the variants of every piece, variant_coords)
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
## Invisible solid tile on SOURCE_GROUND (square collision); the other columns of its row round some
## corners (solid_coords).
const SOLID := Vector2i(0, 1)
## Rounded collision corners (bits, column of the solid tile) and the arc: radius in art px like the
## rock's outer corners, segments per arc (TESTWERT, feel).
const CORNER_TL := 1
const CORNER_TR := 2
const CORNER_BR := 4
const CORNER_BL := 8
const SOLID_VARIANTS := 16
const COLLISION_RADIUS := 8.0
const COLLISION_STEPS := 4
## Row of the solid tiles of a lip (rock with floor north of it, see is_lip): their collision starts
## LIP_WALK art px below the tile's top, so characters walk a bit behind the rock's top edge and the
## lip, drawn above them (RoomTiles lip sprites), hides their feet and shadow (playtest 15.10.2026,
## note 17: "the shadow lies on top of the wall"). TESTWERT
const SOLID_LIP_ROW := 2
const LIP_WALK := 12
## Bug report 17.10.2026 (#b16194d4, "da bin ich transparent"): the walkable band of a lip is closed
## at an end of the block (floor beside it), so nobody walks into the rock's top from the side and is
## cut by the lip drawn over him; only from the north. Bits of the caps, the rows of their solid
## tiles (lip row + bits) and the cap width in art px (the rounded corner's radius). TESTWERT
const CAP_LEFT := 1
const CAP_RIGHT := 2
const LIP_CAP_WIDTH := 8.0

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
## Rows of the light top line of the delivered cave fronts (taken off for the plain face of an abyss)
## and the radius of the rounded foot where a block's crown turns into its front's top line (art px,
## like the delivered outer corners).
const FRONT_CAP := 2
const FOOT_CORNER := 8
## Variant bits of a crown piece (variant_coords): a rounded foot where its edge turns into the top
## line of the front below it (left / right end of that front), a joint where its side edge meets the
## top line of a front beside it (left / right).
const FOOT_LEFT := 1
const FOOT_RIGHT := 2
const JOINT_LEFT := 4
const JOINT_RIGHT := 8
const VARIANTS := 16

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


## Atlas coords of a piece with variant bits (FOOT_* | JOINT_*, 0 = the plain piece).
static func variant_coords(mask: int, bits: int) -> Vector2i:
	if bits <= 0:
		return rock_coords(mask)
	var index := MASKS.size() + Front.size() + 3 + (clampi(bits, 1, VARIANTS - 1) - 1) * MASKS.size() + _index_of(normalize(mask))
	return Vector2i(index % SHEET_COLUMNS, index / SHEET_COLUMNS)


## Number of atlas slots of a rock source (pieces, fronts, fillets, variants).
static func sheet_slots() -> int:
	return MASKS.size() + Front.size() + 3 + (VARIANTS - 1) * MASKS.size()


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


## Neighbour mask of a solid tile from the floor mask (keys = floor; everything else is solid). The
## crown above a front runs into it (the front draws its own top line); a front right beside the tile
## (west or east) counts as open: the side wall gets its edge up to the top line of that front.
static func mask_for(tile: Vector2i, floor_mask: Dictionary[Vector2i, bool]) -> int:
	var mask := 0
	var bits: Array[int] = [N, NE, E, SE, S, SW, W, NW]
	var offsets: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]
	for i in bits.size():
		var open := floor_mask.has(tile + offsets[i])
		if bits[i] == E or bits[i] == W:
			open = is_open(tile + offsets[i], floor_mask)
		if not open:
			mask |= bits[i]
	return normalize(mask)


## Floor or a front: what a side wall draws its edge towards.
static func is_open(tile: Vector2i, floor_mask: Dictionary[Vector2i, bool]) -> bool:
	return floor_mask.has(tile) or WallAutotile.is_front(tile, floor_mask)


## Variant bits of a solid tile that is no front (FOOT_* | JOINT_*): a crown over a front whose end
## lies under the crown's open side turns its edge round into the front's top line; a side wall next
## to a front joins its edge to that line (only below rock, not at an outer corner).
static func variant_bits(tile: Vector2i, floor_mask: Dictionary[Vector2i, bool]) -> int:
	var bits := 0
	var below := tile + Vector2i.DOWN
	var mask := mask_for(tile, floor_mask)
	for side: Array in [[Vector2i.LEFT, FOOT_LEFT, JOINT_LEFT], [Vector2i.RIGHT, FOOT_RIGHT, JOINT_RIGHT]]:
		var step: Vector2i = side[0]
		if WallAutotile.is_front(below, floor_mask) and is_open(tile + step, floor_mask) and floor_mask.has(below + step):
			bits |= int(side[1])
		if mask & N and WallAutotile.is_front(tile + step, floor_mask):
			bits |= int(side[2])
	return bits


## Atlas coords of a solid tile. Fronts: solid with floor right below it and solid above it
## (WallAutotile.is_front), ending with a rounded corner only where floor lies beside it; against rock
## (the side wall, a step back to a deeper front) it runs square into that rock's edge, which goes up
## to the top of the front (playtest 15.10.2026, notes 4 and 10).
static func piece_for(tile: Vector2i, floor_mask: Dictionary[Vector2i, bool]) -> Vector2i:
	if WallAutotile.is_front(tile, floor_mask):
		var left := floor_mask.has(tile + Vector2i.LEFT)
		var right := floor_mask.has(tile + Vector2i.RIGHT)
		if left and right:
			return front_coords(Front.SINGLE)
		if left:
			return front_coords(Front.LEFT)
		return front_coords(Front.RIGHT) if right else front_coords(Front.MIDDLE)
	return variant_coords(mask_for(tile, floor_mask), variant_bits(tile, floor_mask))


## Is the solid tile fully enclosed (no floor in its 8 neighbours, no front beside it)? Those stay to
## the backdrop.
static func is_enclosed(tile: Vector2i, floor_mask: Dictionary[Vector2i, bool]) -> bool:
	return not WallAutotile.is_front(tile, floor_mask) and mask_for(tile, floor_mask) == FULL and variant_bits(tile, floor_mask) == 0


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


static var _faces: Dictionary[StringName, Image] = {}


## The plain rock face of a biome's cave fronts (middle piece, top line taken off, 32 x 32): the
## rock under the north edge of an abyss (AbyssFace). Null without the art.
static func face_image(biome_id: StringName) -> Image:
	if _faces.has(biome_id):
		return _faces[biome_id]
	var sheet := _load_image(art_paths(biome_id, Look.CAVE)["rock"])
	if sheet == null:
		return null
	_strip_front_tops(sheet, band_colors(sheet))
	var image := sheet.get_region(Rect2i(front_coords(Front.MIDDLE) * TILE, Vector2i(TILE, TILE)))
	_faces[biome_id] = image
	return image


static func has_look(tileset: TileSet, look: Look) -> bool:
	return tileset != null and tileset.has_source(rock_source(look)) and tileset.has_source(SOURCE_GROUND)


static func _add_rock_source(tileset: TileSet, id: int, image: Image) -> void:
	var source := _add_source(tileset, id, image)
	for i in sheet_slots():
		source.create_tile(Vector2i(i % SHEET_COLUMNS, i / SHEET_COLUMNS))


## Cave floor (row 0, navigation) and the invisible solid tiles (row 1, collision): column = corner
## bits of the rounded collision (solid_corners).
static func _add_ground_source(tileset: TileSet, floor_image: Image) -> void:
	var image := Image.create_empty(TILE * SOLID_VARIANTS, TILE * (SOLID_LIP_ROW + 4), false, Image.FORMAT_RGBA8)
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
	for caps in 4:
		for lip in ([false, true] if caps == 0 else [true]):
			for bits in SOLID_VARIANTS:
				var coords := solid_coords(bits, lip, caps)
				source.create_tile(coords)
				if tileset.get_physics_layers_count() > 0:
					var data := source.get_tile_data(coords, 0)
					data.add_collision_polygon(0)
					data.set_collision_polygon_points(0, 0, solid_polygon(bits, lip))
					for cap: int in [CAP_LEFT, CAP_RIGHT]:
						if caps & cap:
							var index := data.get_collision_polygons_count(0)
							data.add_collision_polygon(0)
							data.set_collision_polygon_points(0, index, lip_cap_polygon(bits, cap))


## Collision of a solid tile (tile space, centred): the square with the corners of bits rounded; a
## lip starts LIP_WALK below the top (its upper corners are cut off with it).
static func solid_polygon(bits: int, lip := false) -> PackedVector2Array:
	var half := TILE / 2.0
	var points := PackedVector2Array()
	# Clockwise from the top-left corner: [bit, corner, start angle of its arc (degrees)].
	for corner: Array in [[CORNER_TL, Vector2(-half, -half), 180.0], [CORNER_TR, Vector2(half, -half), 270.0], [CORNER_BR, Vector2(half, half), 0.0], [CORNER_BL, Vector2(-half, half), 90.0]]:
		var point: Vector2 = corner[1]
		if lip and point.y < 0.0:
			points.append(Vector2(point.x, -half + LIP_WALK))
			continue
		if not bits & int(corner[0]):
			points.append(point)
			continue
		var center := point - point.sign() * COLLISION_RADIUS
		for step in COLLISION_STEPS + 1:
			var angle := deg_to_rad(float(corner[2]) + 90.0 * step / COLLISION_STEPS)
			points.append(center + Vector2(cos(angle), sin(angle)) * COLLISION_RADIUS)
	return points


## The cap that closes the walkable band of a lip at one end (CAP_LEFT / CAP_RIGHT, tile space,
## centred): LIP_CAP_WIDTH wide from the top down to LIP_WALK, its outer top corner rounded like the
## rock when bits round it. Convex.
static func lip_cap_polygon(bits: int, cap: int) -> PackedVector2Array:
	var half := TILE / 2.0
	var points := PackedVector2Array()
	var rounded := bits & (CORNER_TL if cap == CAP_LEFT else CORNER_TR)
	if rounded:
		var center := Vector2(-half + COLLISION_RADIUS, -half + COLLISION_RADIUS)
		for step in COLLISION_STEPS + 1:
			var angle := deg_to_rad(180.0 + 90.0 * step / COLLISION_STEPS)
			points.append(center + Vector2(cos(angle), sin(angle)) * COLLISION_RADIUS)
	else:
		points.append(Vector2(-half, -half))
	if not points[points.size() - 1].is_equal_approx(Vector2(-half + LIP_CAP_WIDTH, -half)):
		points.append(Vector2(-half + LIP_CAP_WIDTH, -half))
	points.append(Vector2(-half + LIP_CAP_WIDTH, -half + LIP_WALK))
	points.append(Vector2(-half, -half + LIP_WALK))
	if cap == CAP_RIGHT:
		# Mirrored, still clockwise.
		var mirrored := PackedVector2Array()
		for i in range(points.size() - 1, -1, -1):
			mirrored.append(Vector2(-points[i].x, points[i].y))
		return mirrored
	return points


## Caps of a lip (CAP_LEFT | CAP_RIGHT): an end of the block with open floor beside it; open_ends are
## floor cells the band may run into (door corridors: the passage goes on there).
static func lip_caps(tile: Vector2i, floor_mask: Dictionary[Vector2i, bool], open_ends: Dictionary[Vector2i, bool] = {}) -> int:
	var caps := 0
	for pair: Array in [[CAP_LEFT, Vector2i.LEFT], [CAP_RIGHT, Vector2i.RIGHT]]:
		var side: Vector2i = tile + (pair[1] as Vector2i)
		if floor_mask.has(side) and not open_ends.has(side):
			caps |= int(pair[0])
	return caps


## Atlas coords of the solid tile with these rounded corners (bits CORNER_TL | CORNER_TR | ...),
## lip: the shortened collision of a lip, caps: its band closed at the ends (lip_caps).
static func solid_coords(bits: int, lip := false, caps := 0) -> Vector2i:
	var row := SOLID.y
	if lip:
		row = SOLID_LIP_ROW + clampi(caps, 0, 3)
	return Vector2i(clampi(bits, 0, SOLID_VARIANTS - 1), row)


## Is the cell one of the invisible solid tiles (any corner variant, lip or not)?
static func is_solid_cell(source_id: int, coords: Vector2i) -> bool:
	return source_id == SOURCE_GROUND and coords.y >= SOLID.y and coords.y <= SOLID_LIP_ROW + 3


## Is the solid tile at these atlas coords a lip (any caps)?
static func is_lip_coords(coords: Vector2i) -> bool:
	return coords.y >= SOLID_LIP_ROW and coords.y <= SOLID_LIP_ROW + 3


## A lip: rock that is no front with floor right north of it (the top edge of a block, of the south
## wall, of a ledge). Characters may walk LIP_WALK into it from the north and are drawn behind it.
## not_lips: floor cells that do not count (door corridors: the door art lies there).
static func is_lip(tile: Vector2i, floor_mask: Dictionary[Vector2i, bool], not_lips: Dictionary[Vector2i, bool] = {}) -> bool:
	var north := tile + Vector2i.UP
	return not floor_mask.has(tile) and floor_mask.has(north) and not not_lips.has(north) and not WallAutotile.is_front(tile, floor_mask)


## Corners of a solid tile whose collision is rounded like its art: an outer corner, the two tiles
## beside it and the one across it open (floor, abyss, corridor). Characters slide round a block
## instead of catching on its square corner (playtest 15.10.2026: "collision a bit weird").
static func solid_corners(tile: Vector2i, floor_mask: Dictionary[Vector2i, bool]) -> int:
	var bits := 0
	for corner: Array in [[CORNER_TL, Vector2i(-1, -1)], [CORNER_TR, Vector2i(1, -1)], [CORNER_BR, Vector2i(1, 1)], [CORNER_BL, Vector2i(-1, 1)]]:
		var d: Vector2i = corner[1]
		if floor_mask.has(tile + Vector2i(d.x, 0)) and floor_mask.has(tile + Vector2i(0, d.y)) and floor_mask.has(tile + d):
			bits |= int(corner[0])
	return bits


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
	var rows := ceili(float(sheet_slots()) / SHEET_COLUMNS)
	var result := Image.create_empty(SHEET_COLUMNS * TILE, rows * TILE, false, Image.FORMAT_RGBA8)
	for y in rows:
		for x in SHEET_COLUMNS:
			result.blit_rect(floor_tile, Rect2i(0, 0, TILE, TILE), Vector2i(x, y) * TILE)
	result.blend_rect(sheet, Rect2i(Vector2i.ZERO, sheet.get_size()), Vector2i.ZERO)
	var band := band_colors(sheet)
	var delivered: Dictionary = inner.get("pieces", {})
	# The fronts as delivered, side by side (left, middle, right, single): the face shown outside the
	# rounded foot.
	var faces := Image.create_empty(TILE * Front.size(), TILE, false, Image.FORMAT_RGBA8)
	for front in Front.size():
		faces.blit_rect(result, Rect2i(front_coords(front) * TILE, Vector2i(TILE, TILE)), Vector2i(front * TILE, 0))
	_draw_inner_corners(result, band, delivered)
	_draw_fillets(result, band, delivered)
	_draw_variants(result, band, faces)
	_band_front_tops(result, band, faces)
	return result


## Every front starts with the light band of an edge (rows from the top: middle, middle, light,
## light - the same order as the edge of a crown towards the floor below it). A front's end against
## floor bends the band round (the lower half of the rounded foot, the crown above holds the upper
## half), the face shows outside the curve.
static func _band_front_tops(image: Image, band: Array[Color], faces: Image) -> void:
	for front in Front.size():
		var origin := front_coords(front) * TILE
		var left := front == Front.LEFT or front == Front.SINGLE
		var right := front == Front.RIGHT or front == Front.SINGLE
		for y in BAND:
			for x in TILE:
				var color: Color = band[BAND - 1 - y]
				for end: Array in [[left, FOOT_CORNER], [right, TILE - FOOT_CORNER]]:
					var center_x: int = end[1]
					if not end[0] or (x >= center_x if center_x == FOOT_CORNER else x < center_x):
						continue
					var d := Vector2(x + 0.5 - center_x, y + 0.5 + BAND).length()
					var ring := FOOT_CORNER - d
					color = band[clampi(int(ring), 0, BAND - 1)] if ring > 0.0 else faces.get_pixel(front * TILE + x, y + BAND)
				image.set_pixel(origin.x + x, origin.y + y, color)


## The variants of every piece (variant_coords): the plain piece with a rounded foot (the upper half
## of the turn into a front's top line; the front face outside the curve) and/or a joint (the side
## edge turning into the top line of the front beside it).
static func _draw_variants(image: Image, band: Array[Color], faces: Image) -> void:
	var single := Front.SINGLE * TILE
	for i in MASKS.size():
		var mask := MASKS[i]
		var base := rock_coords(mask) * TILE
		var fill := image.get_pixel(base.x + TILE / 2, base.y + TILE / 2)
		var piece := image.get_region(Rect2i(base, Vector2i(TILE, TILE)))
		for bits in range(1, VARIANTS):
			var origin := variant_coords(mask, bits) * TILE
			image.blit_rect(piece, Rect2i(0, 0, TILE, TILE), origin)
			for foot: Array in [[FOOT_LEFT, FOOT_CORNER, 0], [FOOT_RIGHT, TILE - FOOT_CORNER, TILE - FOOT_CORNER]]:
				if not bits & int(foot[0]):
					continue
				var center := Vector2(int(foot[1]), TILE - BAND)
				for y in range(TILE - BAND, TILE):
					for x in range(int(foot[2]), int(foot[2]) + FOOT_CORNER):
						var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
						var color := fill
						if d >= FOOT_CORNER:
							color = faces.get_pixel(single + x, y - (TILE - BAND) + BAND)
						elif d >= FOOT_CORNER - BAND:
							color = band[clampi(int(FOOT_CORNER - d), 0, BAND - 1)]
						image.set_pixel(origin.x + x, origin.y + y, color)
			for joint: Array in [[JOINT_LEFT, 0], [JOINT_RIGHT, TILE]]:
				if not bits & int(joint[0]):
					continue
				var corner := Vector2(int(joint[1]), BAND)
				for y in BAND:
					for x in range(0, BAND) if int(joint[1]) == 0 else range(TILE - BAND, TILE):
						var ring := int(Vector2(x + 0.5, y + 0.5).distance_to(corner))
						image.set_pixel(origin.x + x, origin.y + y, band[ring] if ring < BAND else fill)


## The plain rock face of the delivered cave fronts: their light top line (the band's middle colour)
## gives way to the face below it. Fronts with another top (the brick cap of masonry) stay.
static func _strip_front_tops(image: Image, band: Array[Color]) -> void:
	var line := band[BAND / 2]
	for front in Front.size():
		var origin := front_coords(front) * TILE
		var top := image.get_pixel(origin.x + TILE / 2, origin.y)
		if not Color(top.r, top.g, top.b).is_equal_approx(Color(line.r, line.g, line.b)):
			continue
		for y in FRONT_CAP:
			for x in TILE:
				image.set_pixel(origin.x + x, origin.y + y, image.get_pixel(origin.x + x, origin.y + FRONT_CAP + y))



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

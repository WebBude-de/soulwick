class_name PlateauArt
extends RefCounted
## Pictures of the height of a room (M3, Makeover 3 §8, mockup 30): the walkable floor on top of a
## plateau, the steps cut into its cliff and the ladders. The plateau itself is rock of the room
## (RockTerrain draws crown and front, the front is the cliff); its surface gets the slab floor of
## the biome (floor_extra slab, "Plateau-Boden", with faint slab seams) framed by a rock rim in the
## colours of the room rock (dark outline, light edge band, like every rock edge of the room) where
## the plateau ends - towards the ground and towards the rock around it - rounded at outer corners;
## towards its own cliff the slab runs to the top of the front. The stairs (stairs_cut, delivered in
## the soft crypt palette) take the rock colours of the biome.
## Pure image work, cached per layout and biome; no randomness.

const STAIRS_ART := "res://art/environment/deco/stairs_cut.png"
## Own art per biome when delivered (SPRITES_V9 §7), else the crypt stairs recoloured / the slab.
const STAIRS_BIOME_ART := "res://art/environment/deco/stairs_cut_%s_soft.png"
const FLOOR_BIOME_ART := "res://art/environment/deco/plateau_floor_%s.png"
const LADDER_ART := "res://art/environment/deco/ladder.png"
const LADDER_TOP_ART := "res://art/environment/deco/ladder_top.png"
## Rock rim left around the surface where it drops to the ground (art px). TESTWERT
const RIM := 5
## Radius of the rounded outer corners of the surface (art px). TESTWERT
const CORNER_RADIUS := 6.0
## Darker line along the rim of the surface (share of brightness lost). TESTWERT
const RIM_SHADE := 0.18
## Light on the surface: plateaus catch a little more light than the ground (brightness). TESTWERT
const SURFACE_LIGHT := 1.06
## Slab seams every SLAB px, darkened by SEAM_SHADE (offset per row of slabs). TESTWERT
const SLAB := 16
const SEAM_SHADE := 0.07
## Rim colours without the rock sheet (outline, light band, band middle): crypt soft.
const RIM_FALLBACK: Array[Color] = [Color("2a2740"), Color("b9b5d2"), Color("8f8bac")]
const TILE := 32

static var _surfaces: Dictionary[String, ImageTexture] = {}
static var _stairs: Dictionary[StringName, Texture2D] = {}


## Picture of all surface tiles of layout (one image over their bounding box, origin in art px of
## the layer = returned rect position), the slab cut from fill (a 32 x 32 floor picture).
## rim: outline, band light, band middle (rim_colors()).
static func surface_texture(layout: HeightLayout, fill: Image, key: String, rim: Array[Color] = RIM_FALLBACK) -> Dictionary:
	var tiles: Array[Vector2i] = []
	tiles.assign(layout.surface.keys())
	if tiles.is_empty() or fill == null:
		return {}
	tiles.sort()
	var bounds := Rect2i(tiles[0], Vector2i.ONE)
	for tile in tiles:
		bounds = bounds.merge(Rect2i(tile, Vector2i.ONE))
	var origin := bounds.position * TILE
	var cache_key := "%s|%s" % [key, str(tiles)]
	if _surfaces.has(cache_key):
		return {"texture": _surfaces[cache_key], "origin": origin}
	var image := Image.create_empty(bounds.size.x * TILE, bounds.size.y * TILE, false, Image.FORMAT_RGBA8)
	for tile in tiles:
		_paint_tile(image, layout, tile, bounds.position, fill, rim)
	_surfaces[cache_key] = ImageTexture.create_from_image(image)
	return {"texture": _surfaces[cache_key], "origin": origin}


## Does the plateau end at this neighbour of a surface tile (ground or rock around it)? Its own
## cliffs and connectors continue it.
static func is_open(layout: HeightLayout, tile: Vector2i) -> bool:
	return not (layout.surface.has(tile) or layout.cliffs.has(tile) or layout.is_connector(tile))


## Outline, band light and band middle of the room rock of a biome (SoftPalette anchors).
static func rim_colors(biome_id: StringName) -> Array[Color]:
	var anchors := SoftPalette.room_anchors(biome_id)
	var colors: Array[Color] = []
	if anchors.size() >= SoftPalette.Anchor.size():
		colors.assign([anchors[SoftPalette.Anchor.OUTLINE], anchors[SoftPalette.Anchor.BAND_LIGHT], anchors[SoftPalette.Anchor.BAND_MIDDLE]])
		return colors
	return RIM_FALLBACK


static func _paint_tile(image: Image, layout: HeightLayout, tile: Vector2i, base: Vector2i, fill: Image, rim: Array[Color]) -> void:
	# Open neighbour rects (8 around) in tile-local px, and the rounded outer corners.
	var open_rects: Array[Rect2] = []
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if (dx != 0 or dy != 0) and is_open(layout, tile + Vector2i(dx, dy)):
				open_rects.append(Rect2(Vector2(dx, dy) * TILE, Vector2.ONE * TILE))
	var corners: Array[Vector2] = []
	for corner: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
		if is_open(layout, tile + Vector2i(corner.x, 0)) and is_open(layout, tile + Vector2i(0, corner.y)):
			corners.append(Vector2(corner))
	var offset := (tile - base) * TILE
	for y in TILE:
		for x in TILE:
			var p := Vector2(x + 0.5, y + 0.5)
			var distance := INF
			for rect in open_rects:
				distance = minf(distance, _distance_to_rect(p, rect))
			for corner in corners:
				# Quarter circle around a point RIM + radius inside the tile corner.
				var tip := Vector2(TILE * 0.5, TILE * 0.5) + corner * TILE * 0.5
				var center := tip - corner * (RIM + CORNER_RADIUS)
				var away := (p - center) * corner
				if away.x > 0.0 and away.y > 0.0:
					distance = minf(distance, RIM + CORNER_RADIUS - (p - center).length())
			if distance <= 0.0:
				continue
			var color: Color
			if distance < 1.0:
				color = rim[0]
			elif distance < RIM:
				color = rim[1] if distance < RIM - 1.5 else rim[2]
			else:
				color = fill.get_pixel(x, y) * SURFACE_LIGHT
				var gx := offset.x + x
				var gy := offset.y + y
				var shift := SLAB / 2 if (gy / SLAB) % 2 == 1 else 0
				if gy % SLAB == 0 or (gx + shift) % SLAB == 0:
					color = color.darkened(SEAM_SHADE)
				if distance < RIM + 1.0:
					color = color.darkened(RIM_SHADE)
			color.a = 1.0
			image.set_pixel(offset.x + x, offset.y + y, color)


static func _distance_to_rect(p: Vector2, rect: Rect2) -> float:
	var dx := maxf(maxf(rect.position.x - p.x, 0.0), p.x - rect.end.x)
	var dy := maxf(maxf(rect.position.y - p.y, 0.0), p.y - rect.end.y)
	return Vector2(dx, dy).length()


## The plateau floor of the biome (delivered plateau_floor_<biome>, 32 x 32), else the slab of the
## biome's zone floors (RockTerrain source, full piece), else the floor.
static func fill_image(tileset: TileSet, look: RockTerrain.Look) -> Image:
	if tileset == null:
		return null
	var delivered := SoftPalette.load_image(FLOOR_BIOME_ART % WallAutotile.biome_of(tileset))
	if delivered != null and delivered.get_width() >= TILE and delivered.get_height() >= TILE:
		return delivered.get_region(Rect2i(0, 0, TILE, TILE))
	var zone := RockTerrain.zone_source(look, tileset)
	var region := Rect2i(RockTerrain.zone_coords(RockTerrain.Zone.SLAB, 15) * TILE, Vector2i(TILE, TILE))
	if not tileset.has_source(zone):
		zone = RockTerrain.floor_source(look, tileset)
		region = Rect2i(Vector2i.ZERO, Vector2i(TILE, TILE))
	if zone < 0 or not tileset.has_source(zone):
		return null
	var source := tileset.get_source(zone) as TileSetAtlasSource
	if source == null or source.texture == null:
		return null
	var image := source.texture.get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image.get_region(region)


## stairs_cut in the rock colours of the biome (delivered for the soft crypt rock).
static func stairs_texture(biome_id: StringName) -> Texture2D:
	if _stairs.has(biome_id):
		return _stairs[biome_id]
	var own := STAIRS_BIOME_ART % biome_id
	if ResourceLoader.exists(own):
		_stairs[biome_id] = load(own) as Texture2D
		return _stairs[biome_id]
	var image := SoftPalette.load_image(STAIRS_ART)
	if image == null:
		return null
	if biome_id != &"crypt":
		image = recolor(image, SoftPalette.room_anchors(&"crypt"), SoftPalette.room_anchors(biome_id))
	_stairs[biome_id] = ImageTexture.create_from_image(image)
	return _stairs[biome_id]


static func ladder_texture() -> Texture2D:
	return load(LADDER_ART) as Texture2D if ResourceLoader.exists(LADDER_ART) else null


static func ladder_top_texture() -> Texture2D:
	return load(LADDER_TOP_ART) as Texture2D if ResourceLoader.exists(LADDER_TOP_ART) else null


## Colours near an anchor of source move by the offset to the same anchor of target (SoftPalette
## rule, rock sheet to rock sheet); every other colour stays.
static func recolor(image: Image, source: Array, target: Array) -> Image:
	var result := image.duplicate() as Image
	if source.size() != target.size() or source.is_empty():
		return result
	for y in result.get_height():
		for x in result.get_width():
			var pixel := result.get_pixel(x, y)
			if pixel.a == 0.0:
				continue
			var best := -1
			var best_distance := SoftPalette.MAX_ANCHOR_DISTANCE
			for i in source.size():
				var anchor: Color = source[i]
				var distance := Vector3(pixel.r - anchor.r, pixel.g - anchor.g, pixel.b - anchor.b).length()
				if distance < best_distance:
					best_distance = distance
					best = i
			if best < 0:
				continue
			var from: Color = source[best]
			var to: Color = target[best]
			result.set_pixel(x, y, Color(clampf(to.r + pixel.r - from.r, 0.0, 1.0), clampf(to.g + pixel.g - from.g, 0.0, 1.0), clampf(to.b + pixel.b - from.b, 0.0, 1.0), pixel.a))
	return result

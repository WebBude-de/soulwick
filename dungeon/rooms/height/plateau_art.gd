class_name PlateauArt
extends RefCounted
## Pictures of the height of a room (M3, Makeover 3 §8, mockup 30; half height D-205, CR6): the
## walkable floor on top of a plateau, its half-high front, the two steps of its stairs and the
## ladders. The plateau is no rock of the room any more (RoomTiles draws it as floor for the rock):
## its surface gets the slab floor of the biome (platform_top, else plateau_floor, else the zone slab,
## with faint slab seams) framed by a rock rim in the colours of the room rock (dark outline, light
## edge band, like every rock edge of the room) where the plateau ends, rounded at outer corners;
## towards its own front the slab runs to the top of the front with a light edge. The front
## (platform_front, PLATFORM_HEIGHT high, pieces for the ends of its row) and the steps (stairs_half)
## fill the upper half of the cliff row. Until that art is delivered (SPRITES_V13 part C) the front
## and the steps are drawn here in the rock colours of the biome (SoftPalette room anchors).
## Pure image work, cached per layout and biome; no randomness.

## Delivered art of the half-high plateau per biome (SPRITES_V13 part C, CR6): front 32 x 16 or
## 128 x 16 (left, middle, right, single), surface 32 x 32, stairs 32 x 16.
const FRONT_ART := "res://art/environment/height/platform_front_%s.png"
const TOP_ART := "res://art/environment/height/platform_top_%s.png"
const STAIRS_HALF_ART := "res://art/environment/height/stairs_half_%s.png"
## Older plateau floor per biome (SPRITES_V9 §7), used while platform_top is missing.
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
## Shade at the foot of the rock rising above a surface in the north (is_walled): art px deep and
## the darkening at the wall. TESTWERT
const WALL_FOOT := 4
const WALL_FOOT_SHADE := 0.3
## Slab seams every SLAB px, darkened by SEAM_SHADE (offset per row of slabs). TESTWERT
const SLAB := 16
const SEAM_SHADE := 0.07
## Light edge of the surface towards its own front (art px; platform_top brings its own). TESTWERT
const LIGHT_EDGE := 2
const LIGHT_EDGE_SHARE := 0.45
## Shade on the ground at the foot of a front: art px deep, darkness at the front. TESTWERT
const FOOT_SHADE := 3
const FOOT_SHADE_ALPHA := 0.32
## Rim colours without the rock sheet (outline, light band, band middle): crypt soft.
const RIM_FALLBACK: Array[Color] = [Color("2a2740"), Color("b9b5d2"), Color("8f8bac")]
## Rock colours without the rock sheet (SoftPalette.Anchor order: top, band light, band middle,
## outline, front, front dark): crypt soft.
const ROCK_FALLBACK: Array[Color] = [Color("5d5878"), Color("b9b5d2"), Color("8f8bac"), Color("2a2740"), Color("4a4563"), Color("3a3651")]
const TILE := 32

## Pieces of a front row (front_pieces, front_piece_of), the order of platform_front.
enum FrontPiece { LEFT, MIDDLE, RIGHT, SINGLE }

static var _surfaces: Dictionary[String, ImageTexture] = {}
static var _stairs: Dictionary[StringName, Texture2D] = {}
static var _fronts: Dictionary[StringName, Array] = {}
static var _shade: ImageTexture = null


## Picture of all surface tiles of layout (one image over their bounding box, origin in art px of
## the layer = returned rect position), the slab cut from fill (a 32 x 32 floor picture).
## rim: outline, band light, band middle (rim_colors()).
## south_light: a light edge where the slab meets its own front (off for a delivered platform_top).
static func surface_texture(layout: HeightLayout, fill: Image, key: String, rim: Array[Color] = RIM_FALLBACK, south_light := true) -> Dictionary:
	var tiles: Array[Vector2i] = []
	tiles.assign(layout.surface.keys())
	if tiles.is_empty() or fill == null:
		return {}
	tiles.sort()
	var bounds := Rect2i(tiles[0], Vector2i.ONE)
	for tile in tiles:
		bounds = bounds.merge(Rect2i(tile, Vector2i.ONE))
	var origin := bounds.position * TILE
	# The picture depends on the rims too (ground, cliffs, stairs, rock around the surface): two rooms
	# with the same surface tiles but other surroundings must not share it.
	var cache_key := "%s|%s|%s|%s" % [key, str(tiles), _rim_signature(layout, tiles), south_light]
	if _surfaces.has(cache_key):
		return {"texture": _surfaces[cache_key], "origin": origin}
	var image := Image.create_empty(bounds.size.x * TILE, bounds.size.y * TILE, false, Image.FORMAT_RGBA8)
	for tile in tiles:
		_paint_tile(image, layout, tile, bounds.position, fill, rim, south_light and is_front_below(layout, tile))
	_surfaces[cache_key] = ImageTexture.create_from_image(image)
	return {"texture": _surfaces[cache_key], "origin": origin}


## Everything _paint_tile reads from the layout besides the tile itself, per tile in order: the
## eight has_rim bits and is_walled.
static func _rim_signature(layout: HeightLayout, tiles: Array[Vector2i]) -> String:
	var parts := PackedStringArray()
	for tile in tiles:
		var bits := 0
		var bit := 0
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				if has_rim(layout, tile, Vector2i(dx, dy)):
					bits |= 1 << bit
				bit += 1
		if is_walled(layout, tile):
			bits |= 1 << bit
		if is_front_below(layout, tile):
			bits |= 1 << (bit + 1)
		parts.append("%x" % bits)
	return ",".join(parts)


## Does the plateau end at this neighbour of a surface tile (ground or rock around it)? Its own
## cliffs and connectors continue it.
static func is_open(layout: HeightLayout, tile: Vector2i) -> bool:
	return not (layout.surface.has(tile) or layout.cliffs.has(tile) or layout.is_connector(tile))


## Does the surface of tile get its rim towards the neighbour at offset? Where the plateau ends
## (is_open), and beside it where the cliff of another part of the plateau begins: at an inner corner
## the edge runs up to the top of that cliff (bug report 22.10.2026 #952d645f, "dort muss die Textur
## hoch gehen"). Its own cliff below continues the slab.
static func has_rim(layout: HeightLayout, tile: Vector2i, offset: Vector2i) -> bool:
	var other := tile + offset
	if offset.y < 0 and is_walled(layout, tile) and is_open(layout, other) and not layout.ground.has(other):
		return false
	if is_open(layout, other):
		return true
	return offset.y == 0 and offset.x != 0 and (layout.cliffs.has(other) or layout.is_connector(other))


## Does the surface of tile run against the rock of the room in the north (no ground, no height
## there)? Plans never build that any more (D-205: plateaus stand free, HeightLayout.problems); where a
## layout still does, the rock rises with its full front above the half-high plateau (RoomTiles draws
## the plateau as floor for the rock) and the surface ends in the shade of its foot instead of a light
## edge.
static func is_walled(layout: HeightLayout, tile: Vector2i) -> bool:
	var north := tile + Vector2i.UP
	return layout.surface.has(tile) and is_open(layout, north) and not layout.ground.has(north)


## Surface tiles against the rock in the north (is_walled), sorted.
static func walled_tiles(layout: HeightLayout) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for tile: Vector2i in layout.surface:
		if is_walled(layout, tile):
			tiles.append(tile)
	tiles.sort()
	return tiles


## Does the front of the plateau (a cliff, stairs or a ladder) lie right below the surface tile?
static func is_front_below(layout: HeightLayout, tile: Vector2i) -> bool:
	var below := tile + Vector2i.DOWN
	return layout.surface.has(tile) and (layout.cliffs.has(below) or layout.is_connector(below))


## Outline, band light and band middle of the room rock of a biome (SoftPalette anchors).
static func rim_colors(biome_id: StringName) -> Array[Color]:
	var anchors := SoftPalette.room_anchors(biome_id)
	var colors: Array[Color] = []
	if anchors.size() >= SoftPalette.Anchor.size():
		colors.assign([anchors[SoftPalette.Anchor.OUTLINE], anchors[SoftPalette.Anchor.BAND_LIGHT], anchors[SoftPalette.Anchor.BAND_MIDDLE]])
		return colors
	return RIM_FALLBACK


static func _paint_tile(image: Image, layout: HeightLayout, tile: Vector2i, base: Vector2i, fill: Image, rim: Array[Color], light_south: bool) -> void:
	# Open neighbour rects (8 around) in tile-local px, and the rounded outer corners.
	var open_rects: Array[Rect2] = []
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if (dx != 0 or dy != 0) and has_rim(layout, tile, Vector2i(dx, dy)):
				open_rects.append(Rect2(Vector2(dx, dy) * TILE, Vector2.ONE * TILE))
	var corners: Array[Vector2] = []
	for corner: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
		if has_rim(layout, tile, Vector2i(corner.x, 0)) and has_rim(layout, tile, Vector2i(0, corner.y)):
			corners.append(Vector2(corner))
	var offset := (tile - base) * TILE
	var walled := is_walled(layout, tile)
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
				if walled and y < WALL_FOOT:
					color = color.darkened(WALL_FOOT_SHADE * (1.0 - float(y) / WALL_FOOT))
				var gx := offset.x + x
				var gy := offset.y + y
				var shift := SLAB / 2 if (gy / SLAB) % 2 == 1 else 0
				if gy % SLAB == 0 or (gx + shift) % SLAB == 0:
					color = color.darkened(SEAM_SHADE)
				if distance < RIM + 1.0:
					color = color.darkened(RIM_SHADE)
				if light_south and y >= TILE - LIGHT_EDGE:
					color = color.lerp(rim[1], LIGHT_EDGE_SHARE)
			color.a = 1.0
			image.set_pixel(offset.x + x, offset.y + y, color)


static func _distance_to_rect(p: Vector2, rect: Rect2) -> float:
	var dx := maxf(maxf(rect.position.x - p.x, 0.0), p.x - rect.end.x)
	var dy := maxf(maxf(rect.position.y - p.y, 0.0), p.y - rect.end.y)
	return Vector2(dx, dy).length()


## The plateau floor of the biome (delivered platform_top_<biome> or plateau_floor_<biome>, 32 x 32),
## else the slab of the biome's zone floors (RockTerrain source, full piece), else the floor.
static func fill_image(tileset: TileSet, look: RockTerrain.Look) -> Image:
	if tileset == null:
		return null
	var biome := WallAutotile.biome_of(tileset)
	for path: String in [TOP_ART % biome, FLOOR_BIOME_ART % biome]:
		var delivered := SoftPalette.load_image(path)
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


## Is platform_top of the biome delivered (it brings its own light edge towards the front)?
static func has_top_art(biome_id: StringName) -> bool:
	return ResourceLoader.exists(TOP_ART % biome_id)


## The two steps of the stairs (32 x 16, PLATFORM_HEIGHT): delivered stairs_half_<biome>, else drawn
## in the rock colours of the biome.
static func stairs_texture(biome_id: StringName) -> Texture2D:
	if not _stairs.has(biome_id):
		var delivered := SoftPalette.load_image(STAIRS_HALF_ART % biome_id)
		var image := delivered if delivered != null else _stairs_placeholder(rock_colors(biome_id))
		_stairs[biome_id] = ImageTexture.create_from_image(image)
	return _stairs[biome_id]


## The front pieces of a biome in FrontPiece order: delivered platform_front_<biome> (four pieces
## side by side, or one piece for all), else drawn in the rock colours of the biome.
static func front_pieces(biome_id: StringName) -> Array[Texture2D]:
	if not _fronts.has(biome_id):
		var image := SoftPalette.load_image(FRONT_ART % biome_id)
		if image == null:
			image = _front_placeholder(rock_colors(biome_id))
		var count := FrontPiece.size() if image.get_width() >= TILE * FrontPiece.size() else 1
		var pieces: Array[Texture2D] = []
		for piece in FrontPiece.size():
			var region := Rect2i((piece % count) * TILE, 0, TILE, mini(image.get_height(), int(HeightField.PLATFORM_HEIGHT)))
			pieces.append(ImageTexture.create_from_image(image.get_region(region)))
		_fronts[biome_id] = pieces
	var result: Array[Texture2D] = []
	result.assign(_fronts[biome_id])
	return result


## Which piece of its row the front of a cliff or ladder tile is: it goes on where a cliff, stairs or
## a ladder lies beside it.
static func front_piece_of(layout: HeightLayout, tile: Vector2i) -> FrontPiece:
	var left := _continues_front(layout, tile + Vector2i.LEFT)
	var right := _continues_front(layout, tile + Vector2i.RIGHT)
	if left and right:
		return FrontPiece.MIDDLE
	if right:
		return FrontPiece.LEFT
	if left:
		return FrontPiece.RIGHT
	return FrontPiece.SINGLE


static func _continues_front(layout: HeightLayout, tile: Vector2i) -> bool:
	return layout.cliffs.has(tile) or layout.is_connector(tile)


## The shade a front casts on the ground at its foot (TILE x FOOT_SHADE, fading downwards).
static func foot_shade_texture() -> Texture2D:
	if _shade == null:
		var image := Image.create_empty(TILE, FOOT_SHADE, false, Image.FORMAT_RGBA8)
		for y in FOOT_SHADE:
			image.fill_rect(Rect2i(0, y, TILE, 1), Color(0.0, 0.0, 0.0, FOOT_SHADE_ALPHA * (1.0 - float(y) / FOOT_SHADE)))
		_shade = ImageTexture.create_from_image(image)
	return _shade


## The rock colours of the biome's room rock (SoftPalette.Anchor order), ROCK_FALLBACK without them.
static func rock_colors(biome_id: StringName) -> Array[Color]:
	var anchors := SoftPalette.room_anchors(biome_id)
	var colors: Array[Color] = []
	if anchors.size() >= SoftPalette.Anchor.size():
		colors.assign(anchors)
		return colors
	return ROCK_FALLBACK


## Placeholder of platform_front: four pieces (FrontPiece order), each TILE x PLATFORM_HEIGHT - light
## edge on top, rock face in two courses of stones, dark foot; the ends of a row get an outline.
static func _front_placeholder(colors: Array[Color]) -> Image:
	var height := int(HeightField.PLATFORM_HEIGHT)
	var image := Image.create_empty(TILE * FrontPiece.size(), height, false, Image.FORMAT_RGBA8)
	for piece in FrontPiece.size():
		var open_left := piece == FrontPiece.LEFT or piece == FrontPiece.SINGLE
		var open_right := piece == FrontPiece.RIGHT or piece == FrontPiece.SINGLE
		for y in height:
			for x in TILE:
				var color := colors[SoftPalette.Anchor.FRONT]
				var course := 0 if y < height / 2 else 1
				if y == height / 2 or (x + course * SLAB / 2) % SLAB == 0:
					color = colors[SoftPalette.Anchor.FRONT_DARK]
				if y == 0:
					color = colors[SoftPalette.Anchor.BAND_LIGHT]
				elif y == 1:
					color = colors[SoftPalette.Anchor.BAND_MIDDLE]
				elif y == height - 2:
					color = colors[SoftPalette.Anchor.FRONT_DARK]
				elif y == height - 1:
					color = colors[SoftPalette.Anchor.OUTLINE]
				var end := (open_left and x == 0) or (open_right and x == TILE - 1)
				if end:
					color = colors[SoftPalette.Anchor.OUTLINE]
					if y == 0:
						color = Color.TRANSPARENT
				color.a = 0.0 if color == Color.TRANSPARENT else 1.0
				image.set_pixel(piece * TILE + x, y, color)
	return image


## Placeholder of stairs_half: two steps of PLATFORM_HEIGHT / 2, each a light tread over a riser,
## between the cut sides of the front.
static func _stairs_placeholder(colors: Array[Color]) -> Image:
	var height := int(HeightField.PLATFORM_HEIGHT)
	var step := height / 2
	var image := Image.create_empty(TILE, height, false, Image.FORMAT_RGBA8)
	for y in height:
		var in_step := y % step
		var color := colors[SoftPalette.Anchor.FRONT]
		if in_step == 0:
			color = colors[SoftPalette.Anchor.BAND_LIGHT]
		elif in_step < step / 2:
			color = colors[SoftPalette.Anchor.BAND_MIDDLE]
		elif in_step == step - 1:
			color = colors[SoftPalette.Anchor.OUTLINE] if y == height - 1 else colors[SoftPalette.Anchor.FRONT_DARK]
		for x in TILE:
			var pixel := color
			if x == 0 or x == TILE - 1:
				pixel = colors[SoftPalette.Anchor.OUTLINE]
			elif x == 1 or x == TILE - 2:
				pixel = colors[SoftPalette.Anchor.FRONT_DARK]
			pixel.a = 1.0
			image.set_pixel(x, y, pixel)
	return image


static func ladder_texture() -> Texture2D:
	return load(LADDER_ART) as Texture2D if ResourceLoader.exists(LADDER_ART) else null


static func ladder_top_texture() -> Texture2D:
	return load(LADDER_TOP_ART) as Texture2D if ResourceLoader.exists(LADDER_TOP_ART) else null

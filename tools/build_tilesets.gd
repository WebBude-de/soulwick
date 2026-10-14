extends SceneTree
## Builds the TileSet resources from the tileset PNGs and their tile lists (art/index.json).
## Usage: godot --headless --path . -s tools/build_tilesets.gd [-- only=dungeon|village]
## Re-run after the tileset images change. Output: dungeon/environment/dungeon_tileset.tres,
## the three biome tilesets next to it, world/village/village_tileset.tres.
##
## Dungeon tilesets (A2, enemy pathfinding): navigation layer 0 marks walkable tiles. Only the four
## floor tiles and bridges carry a navigation polygon; walls, pillars, inner walls and abyss tiles
## have none, so TileMapLayers bake navigation for walkable ground only (no change in RoomTiles
## needed). A blocking tile must replace the floor cell on the same layer; a floor cell under a
## wall on another layer would stay walkable for the navigation.
##
## Atlas sources of every dungeon tileset (same ids in all biomes):
##   0 SOURCE_GROUND      the room tiles (floor, walls, pillar), 8 x 3
##   1 SOURCE_INNER_WALL  inner wall pieces (inner_wall_tiles[_<biome>].png), solid, 4 x 2
##   2 SOURCE_ABYSS       the biome's abyss pieces (abyss_tiles_<biome>.png, crypt for the dungeon
##                        tileset; layout: edges n/e/s/w, outer corners, inner corners, void 1-4),
##                        not walkable, no world collision, but solid on physics layer 1 "pit"
##                        (PhysicsLayers.PIT, A4): enemies collide with it, the player falls
##                        (PlayerFall). RoomTiles combines the pieces at runtime (AbyssAutotile).
##   3 SOURCE_BRIDGE      bridges laid over the abyss (bridge_tiles.png), walkable, no collision on
##                        either layer, 4 x 1; the other ends are flipped per cell
##
## Physics layers of every dungeon tileset: 0 = world (walls, layer 1), 1 = pit (layer 7, A4).
##
## Soft cave art (M1, Makeover 3 §10, `only=soft`, also part of the default run): the delivered
## crypt_soft set is the reference (rock_blob_crypt_soft, crypt_soft_tileset, floor_extra_crypt_soft);
## the other three biomes get the same pieces by a palette swap (own floor and rock colour, ember
## forge with a glowing rock edge), written next to the delivered files and never over them:
##   rock_blob_<biome>_soft.png        47 rock pieces + 4 fronts (crypt: delivered)
##   <biome>_soft_tileset.png           4 floor variants without joints (crypt: delivered)
##   floor_zones_<biome>_soft.png       4 zone floors: slab, cobble, dirt, rubble (all four biomes:
##                                      the delivered soft zones differ too little, so cobble and
##                                      rubble take the delivered crypt patterns in the soft colours)
##   masonry_<biome>_soft.png           masonry rooms in the same palette (playtest 14.10.2026: halls
##                                      and caves of a biome match): the soft rock pieces with the
##                                      delivered brick fronts in the soft rock colour
##   masonry_floor_<biome>_soft.png     the biome's flagstones (4 tiles) in the soft floor colour
##   ../doors/cave_mouth_<biome>_soft.png  the delivered crypt_soft cave mouth swapped (hook H2, M2)
## Run `godot --headless --path . --import` afterwards.

const TILE := 32
const HALF := TILE / 2.0
const FULL_BOX := [Vector2(-HALF, -HALF), Vector2(HALF, -HALF), Vector2(HALF, HALF), Vector2(-HALF, HALF)]
const TILES_DIR := "res://art/environment/tiles/"
const SOURCE_GROUND := 0
const SOURCE_INNER_WALL := 1
const SOURCE_ABYSS := 2
const SOURCE_BRIDGE := 3
## TileSet physics layer of the abyss (A4); its bodies sit on PhysicsLayers.PIT.
const PHYSICS_PIT := 1
const PIT_COLLISION_LAYER := 64
## Abyss art per biome; the crypt version stands in for a biome without its own file.
const ABYSS_PNG := "abyss_tiles_%s.png"
const ABYSS_FALLBACK_BIOME := "crypt"
## Navigation layer bit used by every walkable dungeon tile (NavigationAgent2D default layers = 1).
const NAVIGATION_LAYERS := 1
const BIOMES: Array[String] = ["slime_grotto", "shadow_realm", "ember_forge"]

## --- Soft cave art (M1) ---
const SOFT_ROCK := "rock_blob_%s_soft.png"
const SOFT_FLOOR := "%s_soft_tileset.png"
const SOFT_ZONES := "floor_zones_%s_soft.png"
const SOFT_MASONRY := "masonry_%s_soft.png"
const SOFT_MASONRY_FLOOR := "masonry_floor_%s_soft.png"
const DOORS_DIR := "res://art/environment/doors/"
## Ground sheets of the biome tilesets (their first four tiles are the flagstones).
const GROUND_SHEETS := {"crypt": "dungeon_tileset.png", "slime_grotto": "slime_grotto_tileset.png", "shadow_realm": "shadow_realm_tileset.png", "ember_forge": "ember_forge_tileset.png"}
## Rock sheet layout (RockTerrain): the four fronts follow the 47 pieces, 8 columns.
const SHEET_COLUMNS := 8
const FRONT_FIRST := 47
## Masonry in the soft palette (TESTWERTE, look): flagstones a little lighter than the cave floor,
## brick fronts on the rock colour.
const MASONRY_FLOOR_VALUE := 0.95
const MASONRY_FRONT_VALUE := 1.0
## Colours of the delivered crypt_soft set (Makeover 3 §10): floor base, rock base, rock edge light
## and mid, outline.
const SOFT_FLOOR_BASE := Color("8f5f52")
const SOFT_ROCK_BASE := Color("5a5677")
const SOFT_EDGE_LIGHT := Color("b9b5d2")
const SOFT_EDGE_MID := Color("8f8bac")
const SOFT_OUTLINE := Color("2a2740")
## Target colours per biome (TESTWERTE, look): floor base, rock base, rock edge light and mid,
## outline. Every other colour of the reference keeps its hue offset to its family base and scales
## saturation and value like it (palette swap).
const SOFT_TARGETS := {
	"slime_grotto": {"floor": "5f7448", "rock": "33524a", "edge_light": "a3cfa9", "edge_mid": "6e9e82", "outline": "11251e"},
	"shadow_realm": {"floor": "6c4364", "rock": "4b4768", "edge_light": "b9b0e2", "edge_mid": "8780b0", "outline": "1c1630"},
	"ember_forge": {"floor": "6e635c", "rock": "3a3331", "edge_light": "f29a56", "edge_mid": "b45a3a", "outline": "170e0c"},
}
## Zone floors relative to the soft floor base (value factor of the pattern's main colour, TESTWERTE):
## cobble a little darker (old paths), dirt darker (edges, bays), rubble on the base.
const ZONE_COBBLE_VALUE := 0.9
const ZONE_DIRT_VALUE := 0.86
const ZONE_RUBBLE_VALUE := 1.0
## How strongly the delivered patterns keep their light/dark contrast in the soft colours.
const ZONE_CONTRAST := 0.8


func _init() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("only="):
			only = arg.trim_prefix("only=")
	if only.is_empty() or only == "dungeon":
		_build_dungeon("res://dungeon/environment/dungeon_tileset.tres", "dungeon_tileset.png", "inner_wall_tiles.png", ABYSS_FALLBACK_BIOME)
		# Biome tilesets share the dungeon layout (docs/SPRITES_V2.md §1).
		for biome in BIOMES:
			_build_dungeon(
				"res://dungeon/environment/%s_tileset.tres" % biome,
				"%s_tileset.png" % biome,
				"inner_wall_tiles_%s.png" % biome,
				biome)
	if only.is_empty() or only == "village":
		var village := _new_tileset(false)
		_add_source(village, 0, TILES_DIR + "village_tileset.png", 8, 3, _village_collision, _no_navigation)
		_save(village, "res://world/village/village_tileset.tres")
	if only.is_empty() or only == "soft":
		_build_soft_art()
	quit()


# --- Soft cave art (M1) ---

func _build_soft_art() -> void:
	var rock := _load_image(TILES_DIR + "rock_blob_crypt_soft.png")
	var floor_image := _load_image(TILES_DIR + "crypt_soft_tileset.png")
	var extra_soft := _load_image(TILES_DIR + "floor_extra_crypt_soft.png")
	var extra_crypt := _load_image(TILES_DIR + "floor_extra_crypt.png")
	if rock == null or floor_image == null or extra_soft == null or extra_crypt == null:
		push_error("soft art: a delivered crypt_soft file is missing")
		return
	var zones := soft_zones(floor_image, extra_soft, extra_crypt)
	_save_png(zones, TILES_DIR + SOFT_ZONES % "crypt")
	var bricks := _load_image(TILES_DIR + "rock_blob_crypt.png")
	var masonry := soft_masonry(rock, bricks) if bricks != null else null
	if masonry != null:
		_save_png(masonry, TILES_DIR + SOFT_MASONRY % "crypt")
	for biome: String in GROUND_SHEETS:
		var ground := _load_image(TILES_DIR + GROUND_SHEETS[biome])
		if ground == null:
			continue
		var flagstones := soft_flagstones(ground)
		_save_png(recolor(flagstones, soft_palette(biome)) if SOFT_TARGETS.has(biome) else flagstones, TILES_DIR + SOFT_MASONRY_FLOOR % biome)
	var mouth := _load_image(DOORS_DIR + "cave_mouth_crypt_soft.png")
	for biome: String in SOFT_TARGETS:
		var palette := soft_palette(biome)
		_save_png(recolor(rock, palette), TILES_DIR + SOFT_ROCK % biome)
		_save_png(recolor(floor_image, palette), TILES_DIR + SOFT_FLOOR % biome)
		_save_png(recolor(zones, palette), TILES_DIR + SOFT_ZONES % biome)
		if masonry != null:
			_save_png(recolor(masonry, palette), TILES_DIR + SOFT_MASONRY % biome)
		if mouth != null:
			_save_png(recolor(mouth, palette), DOORS_DIR + "cave_mouth_%s_soft.png" % biome)


## The soft rock pieces with the delivered brick fronts in the soft rock colour (masonry look).
static func soft_masonry(rock: Image, bricks: Image) -> Image:
	var sheet := rock.duplicate() as Image
	for front in 4:
		var index := FRONT_FIRST + front
		var cell := Vector2i(index % SHEET_COLUMNS, index / SHEET_COLUMNS) * TILE
		var tile := _region_on(bricks, Rect2i(cell, Vector2i(TILE, TILE)), SOFT_ROCK_BASE, MASONRY_FRONT_VALUE)
		sheet.fill_rect(Rect2i(cell, Vector2i(TILE, TILE)), Color(0, 0, 0, 0))
		sheet.blit_rect(tile, Rect2i(0, 0, TILE, TILE), cell)
	return sheet


## The first four tiles of a biome ground sheet (flagstones) in the soft floor colour.
static func soft_flagstones(ground: Image) -> Image:
	var result := Image.create_empty(TILE * 4, TILE, false, Image.FORMAT_RGBA8)
	for i in 4:
		result.blit_rect(_region_on(ground, Rect2i(i * TILE, 0, TILE, TILE), SOFT_FLOOR_BASE, MASONRY_FLOOR_VALUE), Rect2i(0, 0, TILE, TILE), Vector2i(i * TILE, 0))
	return result


## Zone floors in the crypt_soft colours: slab (delivered soft slab), cobble and rubble (the delivered
## crypt patterns, recoloured onto the soft floor), dirt (soft floor, darker).
static func soft_zones(floor_image: Image, extra_soft: Image, extra_crypt: Image) -> Image:
	var zones := Image.create_empty(TILE * 4, TILE, false, Image.FORMAT_RGBA8)
	zones.blit_rect(extra_soft, Rect2i(0, 0, TILE, TILE), Vector2i.ZERO)
	zones.blit_rect(_pattern_on(extra_crypt, 1, SOFT_FLOOR_BASE, ZONE_COBBLE_VALUE), Rect2i(0, 0, TILE, TILE), Vector2i(TILE, 0))
	zones.blit_rect(_pattern_on(floor_image, 1, SOFT_FLOOR_BASE, ZONE_DIRT_VALUE), Rect2i(0, 0, TILE, TILE), Vector2i(TILE * 2, 0))
	zones.blit_rect(_pattern_on(extra_crypt, 3, SOFT_FLOOR_BASE, ZONE_RUBBLE_VALUE), Rect2i(0, 0, TILE, TILE), Vector2i(TILE * 3, 0))
	return zones


## Tile column of sheet in the hue of base: every pixel keeps its brightness relative to the tile's
## most frequent colour (contrast scaled by ZONE_CONTRAST), the main colour lands on base * value.
static func _pattern_on(sheet: Image, column: int, base: Color, value: float) -> Image:
	return _region_on(sheet, Rect2i(column * TILE, 0, TILE, TILE), base, value)


static func _region_on(sheet: Image, region: Rect2i, base: Color, value: float) -> Image:
	var tile := sheet.get_region(region)
	var counts := {}
	for y in TILE:
		for x in TILE:
			var pixel := tile.get_pixel(x, y)
			if pixel.a > 0.0:
				counts[pixel.to_html(false)] = int(counts.get(pixel.to_html(false), 0)) + 1
	var main := Color.BLACK
	var best := -1
	for key: String in counts:
		if counts[key] > best:
			best = counts[key]
			main = Color(key)
	var main_value := maxf(main.v, 0.01)
	for y in TILE:
		for x in TILE:
			var pixel := tile.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			var ratio := 1.0 + (pixel.v / main_value - 1.0) * ZONE_CONTRAST
			tile.set_pixel(x, y, Color.from_hsv(base.h, base.s, clampf(base.v * value * ratio, 0.0, 1.0), pixel.a))
	return tile


## Reference colour -> biome colour for every colour family of the soft set.
static func soft_palette(biome: String) -> Dictionary:
	var target: Dictionary = SOFT_TARGETS[biome]
	return {
		"floor": [SOFT_FLOOR_BASE, Color(target["floor"])],
		"rock": [SOFT_ROCK_BASE, Color(target["rock"])],
		"fixed": {
			SOFT_EDGE_LIGHT.to_html(false): Color(target["edge_light"]),
			SOFT_EDGE_MID.to_html(false): Color(target["edge_mid"]),
			SOFT_OUTLINE.to_html(false): Color(target["outline"]),
		},
	}


## A copy of image in the biome's colours (alpha stays). Warm colours (hue near red) belong to the
## floor family, all others to the rock family.
static func recolor(image: Image, palette: Dictionary) -> Image:
	var copy := image.duplicate() as Image
	var fixed: Dictionary = palette["fixed"]
	var cache := {}
	for y in copy.get_height():
		for x in copy.get_width():
			var pixel := copy.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			var key := pixel.to_html(false)
			if not cache.has(key):
				cache[key] = fixed[key] if fixed.has(key) else _swap(pixel, palette)
			var mapped: Color = cache[key]
			copy.set_pixel(x, y, Color(mapped.r, mapped.g, mapped.b, pixel.a))
	return copy


static func _swap(pixel: Color, palette: Dictionary) -> Color:
	var warm := pixel.s > 0.12 and (pixel.h < 0.14 or pixel.h > 0.9)
	var pair: Array = palette["floor"] if warm else palette["rock"]
	var from: Color = pair[0]
	var to: Color = pair[1]
	var saturation := to.s * (pixel.s / maxf(from.s, 0.01))
	var hue := fposmod(to.h + _hue_offset(pixel.h, from.h), 1.0)
	return Color.from_hsv(hue, clampf(saturation, 0.0, 1.0), clampf(to.v * pixel.v / maxf(from.v, 0.01), 0.0, 1.0))


static func _hue_offset(hue: float, base: float) -> float:
	var offset := hue - base
	if offset > 0.5:
		offset -= 1.0
	elif offset < -0.5:
		offset += 1.0
	return offset


static func _load_image(path: String) -> Image:
	if not ResourceLoader.exists(path):
		return null
	var image := (load(path) as Texture2D).get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image


static func _save_png(image: Image, path: String) -> void:
	var err := image.save_png(ProjectSettings.globalize_path(path))
	print("saved ", path, " -> ", error_string(err))


func _build_dungeon(out_path: String, ground_png: String, inner_wall_png: String, biome: String) -> void:
	var tileset := _new_tileset(true)
	tileset.add_physics_layer()
	tileset.set_physics_layer_collision_layer(PHYSICS_PIT, PIT_COLLISION_LAYER)
	tileset.set_physics_layer_collision_mask(PHYSICS_PIT, 0)
	_add_source(tileset, SOURCE_GROUND, TILES_DIR + ground_png, 8, 3, _ground_collision, _ground_walkable)
	if not ResourceLoader.exists(TILES_DIR + inner_wall_png):
		inner_wall_png = "inner_wall_tiles.png"
	_add_source(tileset, SOURCE_INNER_WALL, TILES_DIR + inner_wall_png, 4, 2, _solid, _no_navigation)
	var abyss_png := ABYSS_PNG % biome
	if not ResourceLoader.exists(TILES_DIR + abyss_png):
		abyss_png = ABYSS_PNG % ABYSS_FALLBACK_BIOME
	_add_source(tileset, SOURCE_ABYSS, TILES_DIR + abyss_png, 4, 4, _solid, _no_navigation, PHYSICS_PIT)
	_add_source(tileset, SOURCE_BRIDGE, TILES_DIR + "bridge_tiles.png", 4, 1, _no_collision, _walkable)
	_save(tileset, out_path)


## Floor tiles are the first four of row 0; everything else on the ground atlas blocks.
static func is_ground_walkable(coords: Vector2i) -> bool:
	return coords.y == 0 and coords.x < 4


func _ground_collision(coords: Vector2i) -> Array:
	return [] if is_ground_walkable(coords) else FULL_BOX


func _ground_walkable(coords: Vector2i) -> bool:
	return is_ground_walkable(coords)


func _solid(_coords: Vector2i) -> Array:
	return FULL_BOX


func _no_collision(_coords: Vector2i) -> Array:
	return []


func _walkable(_coords: Vector2i) -> bool:
	return true


func _no_navigation(_coords: Vector2i) -> bool:
	return false


func _village_collision(coords: Vector2i) -> Array:
	match coords:
		Vector2i(7, 1):  # fence_h
			return [Vector2(-HALF, -4), Vector2(HALF, -4), Vector2(HALF, 6), Vector2(-HALF, 6)]
		Vector2i(0, 2):  # fence_v
			return [Vector2(-5, -HALF), Vector2(5, -HALF), Vector2(5, HALF), Vector2(-5, HALF)]
		Vector2i(1, 2), Vector2i(2, 2):  # bush, stump
			return [Vector2(-12, -6), Vector2(12, -6), Vector2(12, 12), Vector2(-12, 12)]
	return []


func _new_tileset(with_navigation: bool) -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE, TILE)
	tileset.add_physics_layer()
	tileset.set_physics_layer_collision_layer(0, 1)
	tileset.set_physics_layer_collision_mask(0, 0)
	if with_navigation:
		tileset.add_navigation_layer()
		tileset.set_navigation_layer_layers(0, NAVIGATION_LAYERS)
	return tileset


## collision(coords) -> Array of polygon points (empty = no collision) on the TileSet physics layer
## physics_layer; walkable(coords) -> bool (navigation polygon over the whole tile).
func _add_source(tileset: TileSet, source_id: int, texture_path: String, cols: int, rows: int, collision: Callable, walkable: Callable, physics_layer := 0) -> void:
	var source := TileSetAtlasSource.new()
	source.texture = load(texture_path)
	source.texture_region_size = Vector2i(TILE, TILE)
	tileset.add_source(source, source_id)
	var has_navigation := tileset.get_navigation_layers_count() > 0
	var width := source.texture.get_width() / TILE
	var height := source.texture.get_height() / TILE
	for y in mini(rows, height):
		for x in mini(cols, width):
			var coords := Vector2i(x, y)
			source.create_tile(coords)
			var tile_data := source.get_tile_data(coords, 0)
			var points: Array = collision.call(coords)
			if not points.is_empty():
				tile_data.add_collision_polygon(physics_layer)
				tile_data.set_collision_polygon_points(physics_layer, 0, PackedVector2Array(points))
			if has_navigation and walkable.call(coords):
				tile_data.set_navigation_polygon(0, _full_tile_navigation())
	print("  source %d: %s (%d x %d)" % [source_id, texture_path.get_file(), mini(cols, width), mini(rows, height)])


static func _full_tile_navigation() -> NavigationPolygon:
	var navigation := NavigationPolygon.new()
	navigation.vertices = PackedVector2Array(FULL_BOX)
	navigation.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	return navigation


func _save(tileset: TileSet, out_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
	var err := ResourceSaver.save(tileset, out_path)
	print("saved ", out_path, " -> ", error_string(err))

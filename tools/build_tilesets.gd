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
	quit()


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

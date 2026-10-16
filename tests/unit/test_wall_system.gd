extends GutTest
## One wall system for every wall (SPRITES_V6, D-110, R1 / 04_wandsystem.md): crown and one row of
## brick front wherever floor lies south of a wall, the north wall two crowns plus a front, pillars
## and inner walls from the same pieces in every biome; plan fixtures (torch, niche, gate, rift,
## cracked wall) sit flush in a brick front; a secret niche stays rock until its wall breaks.
## Since M1 the pieces are drawn as one 47-piece terrain (RockTerrain, caves and masonry): the room
## layer keeps an invisible solid tile per wall cell (collision), the rock layer the pieces.

const BIOMES: Array[StringName] = [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]
const BIOME_TILESET_PATH := "res://dungeon/environment/%s_tileset.tres"
const BASE_TILESET_PATH := "res://dungeon/environment/dungeon_tileset.tres"
const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")

var _old_save_path: String
var _entries: Array[RoomTemplate] = []


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_wall_system_save.cfg"
	_entries = RoomCatalog.create().get_entries()
	_entries.append_array(RoomCatalog.load_plans().get_entries())


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _tiles_of(scene: PackedScene) -> RoomTiles:
	var room := scene.instantiate()
	autofree(room)
	return room.get_node("Tiles") as RoomTiles


func _find(id: StringName) -> RoomTemplate:
	for entry in _entries:
		if entry.id == id:
			return entry
	return null


func test_wall_pieces_by_neighbours() -> void:
	var size := Vector2i(10, 10)
	# A pillar: crown with an edge on every side (floor around, its own front below), the front
	# with both side edges.
	var mass: Dictionary[Vector2i, bool] = {Vector2i(5, 5): true, Vector2i(5, 6): true}
	assert_eq(WallAutotile.cell_for(Vector2i(5, 5), mass, size), WallAutotile.crown_coords(0, 0))
	assert_eq(WallAutotile.cell_for(Vector2i(5, 6), mass, size), WallAutotile.front_coords(WallAutotile.Front.SINGLE))
	# A 3x3 block: crowns on the two upper rows (edge where the front drops), one row of front.
	mass.clear()
	for y in range(2, 5):
		for x in range(2, 5):
			mass[Vector2i(x, y)] = true
	assert_eq(WallAutotile.cell_for(Vector2i(2, 2), mass, size), WallAutotile.crown_coords(WallAutotile.E | WallAutotile.S, 0), "top-left: edges north and west")
	assert_eq(WallAutotile.cell_for(Vector2i(3, 3), mass, size), WallAutotile.crown_coords(WallAutotile.N | WallAutotile.E | WallAutotile.W, 0), "edge only towards the front")
	assert_eq(WallAutotile.cell_for(Vector2i(2, 4), mass, size), WallAutotile.front_coords(WallAutotile.Front.LEFT))
	assert_eq(WallAutotile.cell_for(Vector2i(3, 4), mass, size), WallAutotile.front_coords(WallAutotile.Front.MIDDLE))
	assert_eq(WallAutotile.cell_for(Vector2i(4, 4), mass, size), WallAutotile.front_coords(WallAutotile.Front.RIGHT))
	# Against the outer wall no edge: a pillar in the top-left corner of the room.
	mass.clear()
	mass[Vector2i(0, 0)] = true
	mass[Vector2i(0, 1)] = true
	assert_eq(WallAutotile.cell_for(Vector2i(0, 0), mass, size), WallAutotile.crown_coords(WallAutotile.N | WallAutotile.W, 0))


func test_outer_wall_follows_the_same_rule() -> void:
	var tiles := _tiles_of(HALL)
	var floor_mask := tiles.get_floor_mask()
	var x := tiles.exit_x - 2
	# North wall: front right above the floor (it draws its own light top line, playtest 15.10.2026),
	# the crown above it runs into the front, rock above that.
	assert_eq(RockTerrain.piece_for(Vector2i(x, -1), floor_mask), RockTerrain.front_coords(RockTerrain.Front.MIDDLE))
	assert_eq(RockTerrain.mask_for(Vector2i(x, -2), floor_mask), RockTerrain.FULL, "crown over the front")
	assert_true(RockTerrain.is_enclosed(Vector2i(x, -3), floor_mask), "rock above (the backdrop shows it)")
	# South wall: rock with its edge towards the floor, no front (seen from the south).
	var south := Vector2i(tiles.entrance_x - 1, tiles.room_size.y)
	assert_eq(RockTerrain.mask_for(south, floor_mask) & RockTerrain.N, 0, "edge towards the floor")
	assert_false(WallAutotile.is_front(south, floor_mask))
	# Exit corridor: the fronts beside it get their rounded side.
	assert_eq(RockTerrain.piece_for(Vector2i(tiles.exit_x - 1, -1), floor_mask), RockTerrain.front_coords(RockTerrain.Front.RIGHT))
	assert_eq(RockTerrain.piece_for(Vector2i(tiles.exit_x + 1, -1), floor_mask), RockTerrain.front_coords(RockTerrain.Front.LEFT))


func test_north_wall_is_two_crowns_and_a_front_wherever_floor_follows() -> void:
	for entry in _entries:
		var tiles := _tiles_of(entry.scene)
		var floor_mask := tiles.get_floor_mask()
		for x in tiles.room_size.x:
			if not floor_mask.has(Vector2i(x, 0)) or floor_mask.has(Vector2i(x, -1)):
				continue
			assert_true(WallAutotile.is_front(Vector2i(x, -1), floor_mask), "%s: front over column %d" % [entry.id, x])
			assert_false(floor_mask.has(Vector2i(x, -2)), "%s: crown over the front" % entry.id)
			assert_false(floor_mask.has(Vector2i(x, -3)), "%s: second crown (arches are not cut off)" % entry.id)


func test_cut_out_corners_are_rock_like_outside() -> void:
	# Cross shape: over the rock corners the north wall has no front (no floor below it).
	var tiles := _tiles_of(_find(&"kreuzgang_crypt").scene)
	var floor_mask := tiles.get_floor_mask()
	var corners := 0
	for tile: Vector2i in tiles.get_wall_mass():
		if tile.y == 0:
			corners += 1
			assert_ne(WallAutotile.cell_for_floor(tile + Vector2i.UP, floor_mask).y, WallAutotile.FRONT_ROW, "no north front over the corner at x %d" % tile.x)
	assert_gt(corners, 0)


func test_fronts_only_right_above_floor_in_every_template() -> void:
	for entry in _entries:
		var tiles := _tiles_of(entry.scene)
		var floor_mask := tiles.get_floor_mask()
		var rect := Rect2i(-2, -3, tiles.room_size.x + 4, tiles.room_size.y + 5)
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var tile := Vector2i(x, y)
				if floor_mask.has(tile) or not WallAutotile.is_front(tile, floor_mask):
					continue
				assert_true(floor_mask.has(tile + Vector2i.DOWN), "%s: front %s above floor" % [entry.id, tile])
				assert_false(WallAutotile.is_front(tile + Vector2i.UP, floor_mask), "%s: no front above front %s" % [entry.id, tile])
				assert_false(floor_mask.has(tile + Vector2i.UP), "%s: front %s hangs from a crown" % [entry.id, tile])


func test_wall_mass_rule() -> void:
	var size := Vector2i(10, 10)
	var one_row: Dictionary[Vector2i, bool] = {Vector2i(3, 3): true, Vector2i(4, 3): true}
	assert_false(WallAutotile.is_valid_mass(one_row, size), "a wall needs a crown above its front")
	one_row[Vector2i(3, 2)] = true
	one_row[Vector2i(4, 2)] = true
	assert_true(WallAutotile.is_valid_mass(one_row, size))
	var at_north_wall: Dictionary[Vector2i, bool] = {Vector2i(3, 0): true}
	assert_true(WallAutotile.is_valid_mass(at_north_wall, size), "hangs from the outer wall")
	var at_south_wall: Dictionary[Vector2i, bool] = {Vector2i(3, 9): true}
	assert_true(WallAutotile.is_valid_mass(at_south_wall, size), "standing on the outer wall")
	for entry in _entries:
		assert_true(WallAutotile.is_valid_mass(_tiles_of(entry.scene).get_wall_mass(), entry.room_size), "%s: every wall has crown and front" % entry.id)


func test_fixtures_sit_flush_in_brick_fronts() -> void:
	var fixtures := 0
	for entry in _entries:
		var tiles := _tiles_of(entry.scene)
		var floor_mask := tiles.get_floor_mask()
		for tile in tiles.front_fixtures + tiles.secret_cracks:
			fixtures += 1
			assert_true(WallAutotile.is_front(tile, floor_mask), "%s: fixture %s is a brick front" % [entry.id, tile])
		for prop in tiles.get_parent().get_node("Props").get_children():
			var node := prop as Node2D
			if String(node.name).begins_with("Torch") and not String(node.name).begins_with("TorchStand"):
				# A torch covers its front tile exactly (pivot top-left, 32 px at scale 2).
				var tile := RoomTiles.local_to_tile(node.position)
				assert_true(tiles.front_fixtures.has(tile), "%s: %s hangs in a front" % [entry.id, node.name])
	assert_gt(fixtures, 100)


func test_walls_use_the_generated_pieces_in_every_biome() -> void:
	var entry := _find(&"gewoelbe_crypt")
	for biome in BIOMES:
		var room := entry.scene.instantiate() as Node2D
		var tiles := room.get_node("Tiles") as RoomTiles
		add_child_autofree(room)
		var path := BIOME_TILESET_PATH % biome
		var tileset := load(path if ResourceLoader.exists(path) else BASE_TILESET_PATH) as TileSet
		tiles.use_tileset(tileset)
		tiles.paint()
		assert_true(tileset.has_source(RockTerrain.SOURCE_MASONRY_ROCK), "%s: masonry pieces added" % biome)
		assert_true(tiles.is_terrain_drawn() and tiles.get_look() == RockTerrain.Look.MASONRY, "%s: a crypt hall is masonry" % biome)
		assert_true(tiles.is_cave_look(), "%s: in the soft rock of the caves (same palette)" % biome)
		var rock := tiles.get_rock_layer()
		var floor_mask := tiles.get_floor_mask()
		var fronts := 0
		for wall: Vector2i in tiles.get_wall_mass():
			assert_eq(tiles.get_cell_source_id(wall), RockTerrain.SOURCE_GROUND, "%s: %s solid cell" % [biome, wall])
			assert_true(RockTerrain.is_solid_cell(tiles.get_cell_source_id(wall), tiles.get_cell_atlas_coords(wall)))
			assert_eq(tiles.get_cell_atlas_coords(wall).x, RockTerrain.solid_corners(wall, floor_mask), "%s: %s collision rounded like the art" % [biome, wall])
			var data := tiles.get_cell_tile_data(wall)
			assert_gt(data.get_collision_polygons_count(0), 0, "%s: walls collide (WORLD)" % biome)
			assert_null(data.get_navigation_polygon(0), "%s: no navigation on walls" % biome)
			if RockTerrain.is_enclosed(wall, floor_mask):
				assert_eq(rock.get_cell_source_id(wall), -1, "%s: enclosed %s left to the backdrop" % [biome, wall])
				continue
			assert_eq(rock.get_cell_source_id(wall), RockTerrain.SOURCE_MASONRY_ROCK, "%s: %s drawn" % [biome, wall])
			assert_eq(rock.get_cell_atlas_coords(wall), RockTerrain.piece_for(wall, floor_mask))
			if WallAutotile.is_front(wall, floor_mask):
				fronts += 1
		assert_gt(fronts, 0, "%s: the block shows its front" % biome)
		var inside := tiles.get_entrance_inside_tile()
		assert_eq(tiles.get_cell_source_id(inside), RockTerrain.floor_source(RockTerrain.Look.MASONRY, tileset), "%s: floor stays floor" % biome)
		assert_not_null(tiles.get_cell_tile_data(inside).get_navigation_polygon(0), "%s: floor carries the navigation" % biome)


func test_runtime_walls_repaint_and_block() -> void:
	var room := HALL.instantiate() as Node2D
	add_child_autofree(room)
	var tiles := room.get_node("Tiles") as RoomTiles
	var rects: Array[Rect2i] = [Rect2i(1, 2, 2, 2)]
	tiles.add_wall_rects(rects)
	assert_false(tiles.is_walkable(Vector2i(1, 2)))
	assert_false(tiles.is_walkable(Vector2i(2, 3)))
	assert_true(RockTerrain.is_solid_cell(tiles.get_cell_source_id(Vector2i(2, 2)), tiles.get_cell_atlas_coords(Vector2i(2, 2))), "the new wall collides")
	var floor_mask := tiles.get_floor_mask()
	var rock := tiles.get_rock_layer()
	assert_eq(rock.get_cell_atlas_coords(Vector2i(2, 3)), RockTerrain.piece_for(Vector2i(2, 3), floor_mask), "its front is drawn")
	assert_true(WallAutotile.is_front(Vector2i(2, 3), floor_mask))
	assert_eq(rock.get_cell_atlas_coords(Vector2i(4, -1)), RockTerrain.piece_for(Vector2i(4, -1), floor_mask), "the north wall is drawn by the same rule")
	assert_true(WallAutotile.is_front(Vector2i(4, -1), floor_mask), "and keeps its front")


func test_closed_niche_is_rock_until_the_wall_breaks() -> void:
	var room := HALL.instantiate() as RoomController
	var tiles := room.get_node("Tiles") as RoomTiles
	var sites := SecretRules.find_sites(tiles, {})
	assert_false(sites.is_empty(), "the hall has a place for a niche")
	var site: SecretRules.Site = sites[0]
	SecretNiche.carve(room, site)
	add_child_autofree(room)
	assert_false(tiles.is_niche_open())
	for tile in site.niche:
		assert_false(tiles.get_floor_mask().has(tile), "niche %s is not floor while sealed" % tile)
		var source := tiles.get_cell_source_id(tile)
		assert_true(source == -1 or RockTerrain.is_solid_cell(source, tiles.get_cell_atlas_coords(tile)), "niche %s drawn as rock (no box in the rock)" % tile)
		assert_true(RockTerrain.is_enclosed(tile, tiles.get_floor_mask()), "niche %s is plain rock" % tile)
	# The crack itself is a plain front before it breaks (the cracked art lies on top).
	assert_true(WallAutotile.is_front(site.crack, tiles.get_floor_mask()))
	tiles.open_wall_tiles(site.opening)
	assert_true(tiles.is_niche_open())
	for tile in site.niche:
		assert_true(tiles.get_floor_mask().has(tile), "niche %s floor after the break" % tile)
		assert_eq(tiles.get_cell_source_id(tile), RockTerrain.SOURCE_GROUND, "niche %s painted as cave floor" % tile)
		# No rock left on it; a rounded fillet in a lower inner corner of the pocket at most.
		var fillet := RockTerrain.fillet_bits(tile, tiles.get_floor_mask())
		var rock := tiles.get_rock_layer()
		assert_true(rock.get_cell_source_id(tile) == -1 or (fillet != 0 and rock.get_cell_atlas_coords(tile) == RockTerrain.fillet_coords(fillet)), "no rock left on the niche %s" % tile)
	assert_true(tiles.get_reachable_tiles().has(site.get_content_tile()), "open after the break")


func test_plan_cracks_choose_the_niche_place() -> void:
	var tiles := _tiles_of(_find(&"wandsystem_crypt").scene)
	assert_eq(tiles.secret_cracks.size(), 1, "the demo plan names its cracked wall ('q')")
	var sites := SecretRules.find_sites(tiles, {})
	assert_eq(sites.size(), 1)
	assert_eq(sites[0].crack, tiles.secret_cracks[0])


func test_break_art_takes_the_biome_colours() -> void:
	var crypt := SecretNiche.get_break_art(&"crypt")
	var ember := SecretNiche.get_break_art(&"ember_forge")
	assert_eq(crypt, SecretNiche.BREAK_ART, "the crypt keeps the delivered art")
	if not WallArt.has_biome_colors(&"ember_forge"):
		pass_test("no wall sheets delivered")
		return
	assert_ne(ember, crypt, "recoloured for the ember forge")
	var palette := WallArt.palette_for(&"ember_forge")
	assert_false(palette.is_empty())
	var image := ember.get_image()
	var source := crypt.get_image()
	var changed := 0
	for y in range(0, source.get_height(), 3):
		for x in range(0, source.get_width(), 3):
			if source.get_pixel(x, y).a > 0.0 and source.get_pixel(x, y) != image.get_pixel(x, y):
				changed += 1
	assert_gt(changed, 0, "the crypt purple is gone")


func test_generated_atlas_matches_the_outer_wall() -> void:
	var tileset := load(BASE_TILESET_PATH) as TileSet
	var ground := (tileset.get_source(0) as TileSetAtlasSource).texture.get_image()
	ground.convert(Image.FORMAT_RGBA8)
	var atlas := WallAutotile.build_atlas(ground, &"crypt")
	assert_eq(atlas.get_size(), Vector2i(16 * 32, 17 * 32))

extends GutTest
## Shapes of the combat templates (KONZEPT_RAEUME §3.2, A3): every shape in its sizes, arena shapes,
## catacomb rules (at most two dead ends, at most two branchings to the exit, the chest in the
## deepest dead end), inner walls painted with the inner wall pieces of every biome tileset.

const BIOMES: Array[StringName] = [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]
const BIOME_TILESET_PATH := "res://dungeon/environment/%s_tileset.tres"
const BASE_TILESET_PATH := "res://dungeon/environment/dungeon_tileset.tres"

var _old_save_path: String
var _catalog: RoomCatalog


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_room_shapes_save.cfg"
	_catalog = RoomCatalog.create()


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _entries(kind: int, shape: int) -> Array[RoomTemplate]:
	var result: Array[RoomTemplate] = []
	for entry in _catalog.get_entries():
		if int(entry.room_kind) == kind and int(entry.shape) == shape:
			result.append(entry)
	return result


func _sizes(entries: Array[RoomTemplate]) -> Array[int]:
	var sizes: Array[int] = []
	for entry in entries:
		sizes.append(int(entry.size_class))
	sizes.sort()
	return sizes


func _tiles_of(entry: RoomTemplate) -> RoomTiles:
	var room := entry.scene.instantiate()
	autofree(room)
	return room.get_node("Tiles") as RoomTiles


func _neighbours(tile: Vector2i, walkable: Dictionary[Vector2i, bool]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if walkable.has(tile + direction):
			result.append(tile + direction)
	return result


## Breadth-first distances and parents from start (fixed neighbour order).
func _bfs(walkable: Dictionary[Vector2i, bool], start: Vector2i) -> Array:
	var dist: Dictionary[Vector2i, int] = {start: 0}
	var parent: Dictionary[Vector2i, Vector2i] = {}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var tile: Vector2i = queue.pop_front()
		for next in _neighbours(tile, walkable):
			if not dist.has(next):
				dist[next] = dist[tile] + 1
				parent[next] = tile
				queue.append(next)
	return [dist, parent]


func test_every_normal_shape_exists_in_s_m_l() -> void:
	var all_sizes: Array[int] = [RoomSequence.RoomSize.S, RoomSequence.RoomSize.M, RoomSequence.RoomSize.L]
	for shape in [RoomTemplate.Shape.RECTANGLE, RoomTemplate.Shape.L_SHAPE, RoomTemplate.Shape.CROSS,
			RoomTemplate.Shape.RING, RoomTemplate.Shape.TWO_CHAMBERS, RoomTemplate.Shape.PILLAR_HALL]:
		assert_eq(_sizes(_entries(RoomSequence.RoomKind.NORMAL, shape)), all_sizes, RoomTemplate.get_shape_name(shape))
	var m_l: Array[int] = [RoomSequence.RoomSize.M, RoomSequence.RoomSize.L]
	assert_eq(_sizes(_entries(RoomSequence.RoomKind.NORMAL, RoomTemplate.Shape.CATACOMB)), m_l, "catacomb only M/L")


func test_arena_shapes_are_rectangle_cross_and_pillar_hall() -> void:
	var shapes := {}
	for entry in _catalog.get_entries():
		if entry.room_kind == RoomSequence.RoomKind.ARENA:
			shapes[int(entry.shape)] = true
			assert_ne(entry.size_class, RoomSequence.RoomSize.S, "%s: arenas are big (M/L)" % entry.id)
	assert_eq(shapes.keys().size(), 3)
	for shape in [RoomTemplate.Shape.RECTANGLE, RoomTemplate.Shape.CROSS, RoomTemplate.Shape.PILLAR_HALL]:
		assert_true(shapes.has(shape), "arena %s" % RoomTemplate.get_shape_name(shape))


func test_sizes_follow_d086() -> void:
	var expected := {RoomSequence.RoomSize.S: Vector2i(15, 9), RoomSequence.RoomSize.M: Vector2i(19, 11), RoomSequence.RoomSize.L: Vector2i(25, 15)}
	for entry in _catalog.get_entries():
		if entry.id in [&"combat_hall", &"combat_pillars", &"combat_wide"] or entry.shape != RoomTemplate.Shape.RECTANGLE:
			continue
		assert_eq(entry.room_size, expected[int(entry.size_class)], "%s size" % entry.id)


func test_shapes_differ_from_the_rectangle() -> void:
	for entry in _catalog.get_entries():
		var tiles := _tiles_of(entry)
		match entry.shape:
			RoomTemplate.Shape.RECTANGLE:
				assert_true(tiles.get_blocked_tiles().is_empty(), "%s: open" % entry.id)
			RoomTemplate.Shape.PILLAR_HALL:
				assert_gte(tiles.pillar_tiles.size(), 4, "%s: pillars" % entry.id)
			_:
				assert_false(tiles.wall_rects.is_empty(), "%s: inner walls" % entry.id)


func test_catacomb_rules() -> void:
	var catacombs := _entries(RoomSequence.RoomKind.NORMAL, RoomTemplate.Shape.CATACOMB)
	assert_eq(catacombs.size(), 2)
	for entry in catacombs:
		var tiles := _tiles_of(entry)
		var walkable := tiles.get_walkable_tiles()
		var floor_rect := Rect2i(Vector2i.ZERO, tiles.room_size)
		var dead_ends: Array[Vector2i] = []
		for tile: Vector2i in walkable:
			if floor_rect.has_point(tile) and _neighbours(tile, walkable).size() == 1:
				dead_ends.append(tile)
		assert_between(dead_ends.size(), 1, 2, "%s: at most two dead ends" % entry.id)
		var search := _bfs(walkable, tiles.get_entrance_inside_tile())
		var dist: Dictionary[Vector2i, int] = search[0]
		var parent: Dictionary[Vector2i, Vector2i] = search[1]
		# Branchings on the shortest way from the entrance to the exit.
		var junctions := 0
		var tile := tiles.get_exit_inside_tile()
		while parent.has(tile):
			if _neighbours(tile, walkable).size() >= 3:
				junctions += 1
			tile = parent[tile]
		assert_lte(junctions, 2, "%s: exit at most two branchings away" % entry.id)
		var deepest := dead_ends[0]
		for end in dead_ends:
			if dist[end] > dist[deepest]:
				deepest = end
		assert_true(entry.has_chest(), "%s: has a chest" % entry.id)
		assert_eq(entry.chest_tile, deepest, "%s: chest in the deepest dead end" % entry.id)
		assert_gte(entry.ambush_tiles.size(), 2, "%s: enemies wait in the dead ends" % entry.id)
		var room := entry.scene.instantiate()
		autofree(room)
		var chest_found := false
		for prop in room.get_node("Props").get_children():
			if prop is TreasureChest:
				chest_found = RoomTiles.local_to_tile((prop as Node2D).position - Vector2(0, 1)) == entry.chest_tile
		assert_true(chest_found, "%s: chest prop on the chest tile" % entry.id)
		var scatter := room.get_node("Ingredients") as IngredientScatter
		assert_true(scatter.reserved_tiles.has(entry.chest_tile), "%s: nothing scattered onto the chest" % entry.id)


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
	var tiles := _tiles_of(_catalog.find_by_path("res://dungeon/rooms/combat/combat_hall.tscn"))
	var floor_mask := tiles.get_floor_mask()
	# North wall: front right above the floor, crown with its edge above it, rock above that.
	assert_eq(WallAutotile.cell_for_floor(Vector2i(2, -1), floor_mask), WallAutotile.front_coords(WallAutotile.Front.MIDDLE))
	assert_eq(WallAutotile.cell_for_floor(Vector2i(2, -2), floor_mask), WallAutotile.crown_coords(WallAutotile.N | WallAutotile.E | WallAutotile.W, 0))
	assert_eq(WallAutotile.cell_for_floor(Vector2i(2, -3), floor_mask), WallAutotile.ROCK)
	# South wall: crown with its edge towards the floor, no front (seen from the south).
	assert_eq(WallAutotile.cell_for_floor(Vector2i(2, tiles.room_size.y), floor_mask), WallAutotile.crown_coords(WallAutotile.E | WallAutotile.S | WallAutotile.W, 0))
	# Top-left corner above the side wall: plain crown with the corner piece only.
	assert_eq(WallAutotile.cell_for_floor(Vector2i(-1, -2), floor_mask), WallAutotile.crown_coords(15, WallAutotile.CORNER_BOTTOM_RIGHT))
	# Exit corridor: the fronts beside it get their side edge.
	assert_eq(WallAutotile.cell_for_floor(Vector2i(tiles.exit_x - 1, -1), floor_mask), WallAutotile.front_coords(WallAutotile.Front.RIGHT))


func test_cut_out_corners_are_rock_like_outside() -> void:
	# L shape: over the cut-out corner the north wall has no front (no floor below it); the
	# cut-out shows one row of front towards the floor, and it is crown and rock above.
	for entry in _entries(RoomSequence.RoomKind.NORMAL, RoomTemplate.Shape.L_SHAPE):
		var tiles := _tiles_of(entry)
		var floor_mask := tiles.get_floor_mask()
		var mass := tiles.get_wall_mass()
		for tile: Vector2i in mass:
			if tile.y == 0:
				assert_ne(WallAutotile.cell_for_floor(tile + Vector2i.UP, floor_mask).y, WallAutotile.FRONT_ROW, "%s: no north front over the cut-out at x %d" % [entry.id, tile.x])


func test_fronts_only_right_above_floor_in_every_template() -> void:
	for entry in _catalog.get_entries():
		var tiles := _tiles_of(entry)
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
	for entry in _catalog.get_entries():
		assert_true(WallAutotile.is_valid_mass(_tiles_of(entry).get_wall_mass(), entry.room_size), "%s: every wall has crown and front" % entry.id)


func test_walls_use_the_generated_pieces_in_every_biome() -> void:
	var entry: RoomTemplate = _entries(RoomSequence.RoomKind.NORMAL, RoomTemplate.Shape.RING)[0]
	for biome in BIOMES:
		var room := entry.scene.instantiate() as Node2D
		var tiles := room.get_node("Tiles") as RoomTiles
		add_child_autofree(room)
		var path := BIOME_TILESET_PATH % biome
		var tileset := load(path if ResourceLoader.exists(path) else BASE_TILESET_PATH) as TileSet
		tiles.use_tileset(tileset)
		assert_true(tileset.has_source(WallAutotile.SOURCE_ID), "%s: wall pieces added" % biome)
		var mass := tiles.get_wall_mass()
		var fronts := 0
		for wall: Vector2i in mass:
			var source := tiles.get_cell_source_id(wall)
			assert_true(source == RoomTiles.SOURCE_WALL or (source == RoomTiles.SOURCE_ID and tiles.get_cell_atlas_coords(wall) == RoomTiles.WALL_TOP), "%s: %s is a wall piece or rock" % [biome, wall])
			var data := tiles.get_cell_tile_data(wall)
			if data != null:
				assert_gt(data.get_collision_polygons_count(0), 0, "%s: walls collide (WORLD)" % biome)
				assert_null(data.get_navigation_polygon(0), "%s: no navigation on walls" % biome)
			if source == RoomTiles.SOURCE_WALL and tiles.get_cell_atlas_coords(wall).y == WallAutotile.FRONT_ROW:
				fronts += 1
		assert_gt(fronts, 0, "%s: the block shows its front" % biome)
		var floor_tile := tiles.get_entrance_inside_tile()
		assert_eq(tiles.get_cell_source_id(floor_tile), RoomTiles.SOURCE_ID, "%s: floor stays floor" % biome)


func test_runtime_walls_repaint_and_block() -> void:
	var entry: RoomTemplate = _entries(RoomSequence.RoomKind.NORMAL, RoomTemplate.Shape.RECTANGLE)[0]
	var room := entry.scene.instantiate() as Node2D
	add_child_autofree(room)
	var tiles := room.get_node("Tiles") as RoomTiles
	var rects: Array[Rect2i] = [Rect2i(3, 3, 2, 2)]
	tiles.add_wall_rects(rects)
	assert_false(tiles.is_walkable(Vector2i(3, 3)))
	assert_false(tiles.is_walkable(Vector2i(4, 4)))
	assert_eq(tiles.get_cell_source_id(Vector2i(4, 3)), RoomTiles.SOURCE_WALL)
	assert_eq(tiles.get_cell_atlas_coords(Vector2i(4, 4)), WallAutotile.front_coords(WallAutotile.Front.RIGHT))
	assert_eq(tiles.get_cell_source_id(Vector2i(4, -1)), RoomTiles.SOURCE_WALL, "the north wall is drawn by the same rule")
	assert_eq(tiles.get_cell_atlas_coords(Vector2i(4, -1)).y, WallAutotile.FRONT_ROW, "and keeps its front")


func test_generated_atlas_matches_the_outer_wall() -> void:
	var tileset := load(BASE_TILESET_PATH) as TileSet
	var ground := (tileset.get_source(0) as TileSetAtlasSource).texture.get_image()
	ground.convert(Image.FORMAT_RGBA8)
	var atlas := WallAutotile.build_atlas(ground, &"crypt")
	assert_eq(atlas.get_size(), Vector2i(16 * 32, 17 * 32))
	var profile := WallAutotile.edge_profile(ground)
	# Free-standing crown (mask 0): edge on all four sides, same colours as the outer wall's edge.
	assert_eq(atlas.get_pixel(16, 0), profile[0], "north edge")
	assert_eq(atlas.get_pixel(0, 16), profile[0], "west edge")
	assert_eq(atlas.get_pixel(16, 31), profile[0], "south edge")
	# Enclosed crown (mask 15): plain crown colour of the outer wall top.
	var plain := ground.get_pixel(WallAutotile.GROUND_CROWN.x * 32 + 16, 16)
	assert_eq(atlas.get_pixel(15 * 32 + 16, 0), plain, "no edge wall-to-wall")
	assert_eq(atlas.get_pixel(15 * 32, 16), plain)
	# Middle front = the outer wall's brick front.
	assert_eq(atlas.get_pixel(1 * 32 + 16, 16 * 32 + 16), ground.get_pixel(WallAutotile.GROUND_FRONT.x * 32 + 16, 16))

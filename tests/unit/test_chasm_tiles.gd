extends GutTest
## Abyss tiles (A4, D-086): pit_rects and bridge_rects of RoomTiles, runtime pits, painting with the
## biome's abyss pieces, the pit physics layer (PitProbe) and the navigation without abysses.

const RING_HOLE_S: PackedScene = preload("res://dungeon/rooms/combat/chasm_ring_hole_s.tscn")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_chasm_tiles_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func after_each() -> void:
	# Door views free their pieces with queue_free (D1).
	await wait_process_frames(1)


func _tiles(size := Vector2i(9, 7)) -> RoomTiles:
	var tiles := RoomTiles.new()
	tiles.tile_set = load("res://dungeon/environment/dungeon_tileset.tres") as TileSet
	tiles.room_size = size
	tiles.entrance_x = 4
	tiles.exit_x = 4
	return tiles


func _room(index := 8) -> RoomController:
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 5
	var room := RING_HOLE_S.instantiate() as RoomController
	room.setup(index, RoomSequence.RoomType.COMBAT, -1, false, context)
	add_child_autofree(room)
	return room


func test_pits_and_bridges_from_rects() -> void:
	var tiles := _tiles()
	autofree(tiles)
	tiles.pit_rects = [Rect2i(1, 3, 7, 1)] as Array[Rect2i]
	tiles.bridge_rects = [Rect2i(4, 3, 1, 1), Rect2i(4, 0, 1, 1)] as Array[Rect2i]
	tiles.wall_rects = [Rect2i(7, 2, 1, 2)] as Array[Rect2i]
	assert_eq(tiles.get_pit_tiles().size(), 5, "7 tiles minus a bridge and a wall")
	assert_true(tiles.is_pit(Vector2i(1, 3)))
	assert_false(tiles.is_pit(Vector2i(7, 3)), "walls win over pits")
	assert_true(tiles.is_bridge(Vector2i(4, 3)))
	assert_false(tiles.is_bridge(Vector2i(4, 0)), "a bridge only counts over an abyss")
	var walkable := tiles.get_walkable_tiles()
	assert_false(walkable.has(Vector2i(2, 3)), "pits are not walkable")
	assert_true(walkable.has(Vector2i(4, 3)), "bridges are")
	# Columns 0 and 8 at row 3 stay floor; walking goes around or over the bridge.
	assert_true(tiles.get_reachable_tiles(0).has(Vector2i(1, 0)), "over the bridge on foot")


func test_dash_crosses_one_tile_gaps_only() -> void:
	var tiles := _tiles(Vector2i(9, 7))
	autofree(tiles)
	# A full-width band of one row: no way on foot, a dash crosses it.
	tiles.pit_rects = [Rect2i(0, 3, 9, 1)] as Array[Rect2i]
	assert_false(tiles.get_reachable_tiles(0).has(tiles.get_exit_inside_tile()), "cut off on foot")
	assert_true(tiles.get_reachable_tiles().has(tiles.get_exit_inside_tile()), "one dash")
	tiles.pit_rects = [Rect2i(0, 3, 9, 2)] as Array[Rect2i]
	assert_false(tiles.get_reachable_tiles().has(tiles.get_exit_inside_tile()), "two tiles are too wide (D-086)")


func test_runtime_pits_open_and_close() -> void:
	var tiles := _tiles()
	add_child_autofree(tiles)
	var changes: Array = []
	tiles.pits_changed.connect(func(changed: Array[Vector2i]) -> void: changes.append(changed))
	var floor_piece := tiles.get_cell_atlas_coords(Vector2i(2, 2))
	tiles.add_pit_tiles([Vector2i(2, 2), Vector2i(-1, 2)] as Array[Vector2i])
	assert_eq(tiles.get_runtime_pit_tiles(), [Vector2i(2, 2)] as Array[Vector2i], "only floor tiles turn into pits")
	assert_true(tiles.is_pit(Vector2i(2, 2)))
	assert_ne(tiles.get_cell_source_id(Vector2i(2, 2)), RoomTiles.SOURCE_ID, "painted as abyss")
	tiles.remove_pit_tiles([Vector2i(2, 2)] as Array[Vector2i])
	assert_false(tiles.is_pit(Vector2i(2, 2)))
	assert_eq(tiles.get_cell_source_id(Vector2i(2, 2)), RoomTiles.SOURCE_ID)
	assert_eq(tiles.get_cell_atlas_coords(Vector2i(2, 2)), floor_piece, "the same floor comes back")
	assert_eq(changes.size(), 2)


func test_painting_uses_abyss_pieces_and_bridges() -> void:
	var room := _room()
	var tiles := room.tiles
	assert_true(tiles.has_pits())
	assert_true(tiles.tile_set.has_source(AbyssAutotile.SOURCE_ID), "combined abyss pieces added at runtime")
	for tile in tiles.get_pit_tiles():
		var source := tiles.get_cell_source_id(tile)
		assert_true(source == RoomTiles.SOURCE_ABYSS or source == RoomTiles.SOURCE_ABYSS_PIECES, "%s: abyss art" % tile)
		var data := tiles.get_cell_tile_data(tile)
		assert_null(data.get_navigation_polygon(0), "%s: no navigation over the abyss" % tile)
	for tile in tiles.get_bridge_tiles():
		assert_eq(tiles.get_cell_source_id(tile), RoomTiles.SOURCE_BRIDGE)
		assert_not_null(tiles.get_cell_tile_data(tile).get_navigation_polygon(0), "%s: bridges are walkable" % tile)
		assert_ne(tiles.get_abyss_under().get_cell_source_id(tile), -1, "%s: abyss under the bridge" % tile)


func test_the_pit_layer_answers_for_any_point() -> void:
	var room := _room()
	await wait_physics_frames(2)
	var world := room.get_world_2d()
	var pit: Vector2i = room.tiles.get_pit_tiles()[0]
	var bridge: Vector2i = room.tiles.get_bridge_tiles()[0]
	assert_true(PitProbe.is_pit_at(world, room.to_global(RoomTiles.tile_center(pit))), "pit %s" % pit)
	assert_false(PitProbe.is_pit_at(world, room.to_global(RoomTiles.tile_center(bridge))), "bridge %s" % bridge)
	assert_false(PitProbe.is_pit_at(world, room.to_global(RoomTiles.tile_center(Vector2i(1, 1)))), "floor")
	# The nearest safe point of a pit centre lies on solid floor.
	var probe := PitProbe.probe_for(room)
	var safe := PitProbe.nearest_safe_point(room.to_global(RoomTiles.tile_center(pit)), probe)
	assert_false(probe.call(safe))
	# Runtime pits are solid on the pit layer as soon as the physics catches up.
	room.tiles.add_pit_tiles([Vector2i(1, 1)] as Array[Vector2i])
	await wait_physics_frames(2)
	assert_true(PitProbe.is_pit_at(world, room.to_global(RoomTiles.tile_center(Vector2i(1, 1)))))


func test_biome_tilesets_have_the_pit_layer() -> void:
	for path: String in ["res://dungeon/environment/dungeon_tileset.tres", "res://dungeon/environment/slime_grotto_tileset.tres",
			"res://dungeon/environment/shadow_realm_tileset.tres", "res://dungeon/environment/ember_forge_tileset.tres"]:
		var tileset := load(path) as TileSet
		assert_eq(tileset.get_physics_layers_count(), 2, path)
		assert_eq(tileset.get_physics_layer_collision_layer(AbyssAutotile.PHYSICS_LAYER), PhysicsLayers.PIT, path)
		var abyss := tileset.get_source(RoomTiles.SOURCE_ABYSS) as TileSetAtlasSource
		assert_true(abyss.texture.resource_path.contains("abyss_tiles_"), "%s: biome abyss art" % path)
		assert_eq(abyss.get_tile_data(Vector2i.ZERO, 0).get_collision_polygons_count(AbyssAutotile.PHYSICS_LAYER), 1)
		assert_eq(abyss.get_tile_data(Vector2i.ZERO, 0).get_collision_polygons_count(0), 0, "%s: no wall collision" % path)
	assert_eq(ProjectSettings.get_setting("layer_names/2d_physics/layer_7"), "pit")
	assert_eq(PhysicsLayers.PIT, 64)


func test_players_and_projectiles_ignore_the_pit_layer() -> void:
	var player := (load("res://player/player.tscn") as PackedScene).instantiate() as Player
	autofree(player)
	assert_eq(player.collision_mask & PhysicsLayers.PIT, 0, "the player walks onto the abyss and falls")
	var enemy := (load("res://enemies/enemy_base.tscn") as PackedScene).instantiate() as Enemy
	autofree(enemy)
	assert_eq(enemy.collision_mask & PhysicsLayers.PIT, PhysicsLayers.PIT, "enemies are blocked")
	var projectile := (load("res://weapons/projectiles/projectile.tscn") as PackedScene).instantiate() as Node2D
	autofree(projectile)
	assert_eq(int(projectile.get(&"collision_mask")) & PhysicsLayers.PIT, 0, "projectiles fly over")

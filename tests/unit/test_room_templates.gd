extends GutTest
## Combat templates on disk (D-086, A3): spawn marker count per size class, every floor tile, the
## exit and every marker reachable from the entrance, RoomTemplate metadata matching the scene.
## Guards hand edits in the editor as well as the generator.

const MINIBOSS: PackedScene = preload("res://dungeon/rooms/boss/miniboss_room.tscn")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_room_templates_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _instantiate(scene: PackedScene) -> RoomController:
	var room := scene.instantiate() as RoomController
	autofree(room)
	return room


func _markers(room: RoomController) -> Array[Marker2D]:
	var markers: Array[Marker2D] = []
	for child in room.get_node("SpawnPoints").get_children():
		if child is Marker2D:
			markers.append(child)
	return markers


func test_every_combat_template_has_enough_spawn_markers() -> void:
	var catalog := RoomCatalog.create()
	assert_gt(catalog.get_template_count(), 0)
	for scene in catalog.get_templates():
		var room := _instantiate(scene)
		var count := _markers(room).size()
		var minimum := RoomSequence.get_min_spawn_points(room.room_size_class)
		assert_between(count, minimum, RoomSequence.MAX_SPAWN_POINTS, "%s: %d markers" % [scene.resource_path, count])
		assert_eq(int(room.room_kind), catalog.get_kind_of(scene), "%s: catalog kind" % scene.resource_path)


func test_exit_markers_and_all_floor_are_reachable_from_the_entrance() -> void:
	for scene in RoomCatalog.create().get_templates():
		var room := _instantiate(scene)
		var tiles := room.get_node("Tiles") as RoomTiles
		var reachable := tiles.get_reachable_tiles()
		assert_true(reachable.has(tiles.get_exit_inside_tile()), "%s: exit reachable" % scene.resource_path)
		for marker in _markers(room):
			var tile := RoomTiles.local_to_tile(marker.position - tiles.position)
			assert_true(reachable.has(tile), "%s: %s on reachable floor (tile %s)" % [scene.resource_path, marker.name, tile])
		var walkable := tiles.get_walkable_tiles()
		for tile: Vector2i in walkable:
			if Rect2i(Vector2i.ZERO, tiles.room_size).has_point(tile):
				assert_true(reachable.has(tile), "%s: floor tile %s not cut off" % [scene.resource_path, tile])
		# Room 1 starts the player two tiles inside the entrance.
		assert_true(walkable.has(Vector2i(tiles.entrance_x, tiles.room_size.y - 2)), "%s: player start free" % scene.resource_path)


func test_room_templates_match_their_scenes() -> void:
	for entry in RoomCatalog.create().get_entries():
		var room := _instantiate(entry.scene)
		var tiles := room.get_node("Tiles") as RoomTiles
		assert_eq(tiles.room_size, entry.room_size, "%s: size" % entry.id)
		assert_eq(int(room.room_size_class), int(entry.size_class), "%s: size class" % entry.id)
		var marker_tiles: Array[Vector2i] = []
		for marker in _markers(room):
			marker_tiles.append(RoomTiles.local_to_tile(marker.position - tiles.position))
		assert_eq(marker_tiles, entry.spawn_tiles, "%s: spawn tiles" % entry.id)
		assert_eq(entry.entrance_side, RoomTemplate.DoorSide.SOUTH, "%s: entrance south" % entry.id)
		assert_true(entry.exit_sides.has(RoomTemplate.DoorSide.NORTH), "%s: exit north" % entry.id)
		for tile in entry.ambush_tiles:
			assert_true(entry.spawn_tiles.has(tile), "%s: ambush tile %s is a marker" % [entry.id, tile])
		assert_not_null(room.get_node_or_null("Ingredients") as IngredientScatter, "%s: has the ingredient scatter" % entry.id)


func test_pillars_and_inner_walls_are_not_walkable() -> void:
	var room := _instantiate(preload("res://dungeon/rooms/combat/combat_pillars.tscn"))
	var tiles := room.get_node("Tiles") as RoomTiles
	var pillar: Vector2i = tiles.pillar_tiles[0]
	assert_false(tiles.is_walkable(pillar))
	assert_false(tiles.is_walkable(pillar + Vector2i.DOWN), "the pillar's front blocks too (SPRITES_V6)")
	assert_true(tiles.is_walkable(pillar + Vector2i.RIGHT))
	assert_true(tiles.is_walkable(Vector2i(tiles.exit_x, -3)), "exit corridor")
	assert_false(tiles.is_walkable(Vector2i(-1, 0)), "outer wall")
	var ring := _instantiate(preload("res://dungeon/rooms/combat/normal_ring_m.tscn"))
	var ring_tiles := ring.get_node("Tiles") as RoomTiles
	assert_false(ring_tiles.wall_rects.is_empty())
	var block: Rect2i = ring_tiles.wall_rects[0]
	assert_false(ring_tiles.is_walkable(block.position), "inner wall")
	assert_true(ring_tiles.get_blocked_tiles().has(block.get_center()), "the block is solid")


func test_flood_fill_dashes_over_one_tile_gaps_only() -> void:
	var walkable: Dictionary[Vector2i, bool] = {}
	var pits: Dictionary[Vector2i, bool] = {}
	for x in 6:
		walkable[Vector2i(x, 0)] = true
	# Gap of one pit tile at x = 2, gap of two at x = 4..5 before x = 6.
	walkable.erase(Vector2i(2, 0))
	pits[Vector2i(2, 0)] = true
	walkable.erase(Vector2i(4, 0))
	walkable.erase(Vector2i(5, 0))
	pits[Vector2i(4, 0)] = true
	pits[Vector2i(5, 0)] = true
	walkable[Vector2i(6, 0)] = true
	var walk_only := RoomTiles.flood_fill(walkable, pits, Vector2i.ZERO, 0)
	assert_false(walk_only.has(Vector2i(3, 0)), "walking does not cross a pit")
	var with_dash := RoomTiles.flood_fill(walkable, pits, Vector2i.ZERO, 1)
	assert_true(with_dash.has(Vector2i(3, 0)), "dash crosses one tile")
	assert_false(with_dash.has(Vector2i(6, 0)), "dash does not cross two tiles")


func test_non_combat_templates_keep_five_markers() -> void:
	# The champion escort still draws from exactly five markers (EnemySpawner, D-009).
	assert_eq(_markers(_instantiate(MINIBOSS)).size(), 5)


func test_every_marker_reaches_the_spawner_over_several_waves() -> void:
	var room := _instantiate(preload("res://dungeon/rooms/combat/combat_wide.tscn"))
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 12
	room.setup(2, RoomSequence.RoomType.COMBAT, -1, false, context)
	# Not in the tree: resolve the onready node by hand.
	room.spawn_points = room.get_node("SpawnPoints")
	var count := room.get_spawn_markers().size()
	assert_gte(count, RoomSequence.get_min_spawn_points(RoomSequence.RoomSize.M))
	var seen := {}
	for i in 30:
		var subset: Array[Marker2D] = room._get_markers()
		assert_between(subset.size(), 5, count)
		for marker in subset:
			seen[marker] = true
	assert_eq(seen.size(), count, "every marker gets used over several waves")


func test_template_torches_keep_clear_of_the_exit_door() -> void:
	# The exit door brings its own torches (D1); template torches beside it would make four.
	for scene in RoomCatalog.create().get_templates():
		var room := _instantiate(scene)
		var tiles := room.get_node("Tiles") as RoomTiles
		for prop in room.get_node("Props").get_children():
			if String(prop.name).begins_with("Torch"):
				var torch_x := floori((prop as Node2D).position.x / RoomTiles.TILE_WORLD)
				assert_gte(absi(torch_x - tiles.exit_x), 4, "%s: %s next to the exit door" % [scene.resource_path, prop.name])

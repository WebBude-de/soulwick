extends GutTest
## Shadow lord hanging behind a pillar in saeulenkreis (16.10.2026). Two causes in the pathfinding:
##   - the tile navigation joins two floor tiles that touch only at a corner (between a pillar and
##     the blocked tile of a decoration group) through that point; the path led the body into a gap
##     it does not fit through (EnemyNavigation._close_corner_leaks asks again around it);
##   - a solid prop on tiles without navigation (D-115) counted as "outside the navigation", so the
##     enemy steered against it instead of following the path the navigation knows around it.

const ENEMY_SCENE_PATH := "res://enemies/enemy_base.tscn"
const TILESET_PATH := "res://dungeon/environment/dungeon_tileset.tres"
const TEST_SAVE_PATH := "user://test_enemy_nav_leaks.cfg"
const FLOOR := Vector2i(0, 0)
const PILLAR := Vector2i(6, 2)
const WALL_TOP := Vector2i(4, 0)
const TILE := 64.0

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.load_game()


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func before_each() -> void:
	HitStop.reset()


func after_each() -> void:
	HitStop.reset()


## 12 x 7 floor tiles with their own navigation map. Pillars at x = 6 rows 0-2 and x = 5 rows 3-5:
## a wall from top to bottom with a gap in row 6 and a diagonal corner between (6, 2) and (5, 3).
func _leak_room() -> TileMapLayer:
	var room := Node2D.new()
	add_child_autofree(room)
	var tiles := TileMapLayer.new()
	tiles.name = "Tiles"
	tiles.tile_set = load(TILESET_PATH)
	tiles.scale = Vector2(2, 2)
	room.add_child(tiles)
	for y in range(-1, 8):
		for x in range(-1, 13):
			var inside := x >= 0 and x < 12 and y >= 0 and y < 7
			tiles.set_cell(Vector2i(x, y), 0, FLOOR if inside else WALL_TOP)
	for y in range(0, 3):
		tiles.set_cell(Vector2i(6, y), 0, PILLAR)
	for y in range(3, 6):
		tiles.set_cell(Vector2i(5, y), 0, PILLAR)
	EnemyNavigation.isolate_room_navigation(tiles)
	return tiles


## An idle enemy (no player in the tree) whose navigation the test asks directly.
func _navigation(tiles: Node2D, tile: Vector2) -> EnemyNavigation:
	var container := Node2D.new()
	tiles.get_parent().add_child(container)
	var enemy: Enemy = (load(ENEMY_SCENE_PATH) as PackedScene).instantiate()
	enemy.data = load("res://enemies/data/slime.tres")
	enemy.apply_scaling(1, false)
	enemy.position = tile * TILE
	container.add_child(enemy)
	return enemy.get_navigation()


func _wait_for_navigation(tiles: TileMapLayer, from: Vector2, to: Vector2) -> void:
	for i in 180:
		var map := tiles.get_navigation_map()
		if map.is_valid() and NavigationServer2D.map_get_iteration_id(map) > 0 \
				and not NavigationServer2D.map_get_path(map, from, to, true).is_empty():
			break
		await wait_physics_frames(1)
	await wait_physics_frames(2)


func test_the_tile_navigation_leaks_through_a_diagonal_corner() -> void:
	var tiles := _leak_room()
	var from := Vector2(2.5, 1.5) * TILE
	var goal := Vector2(9.5, 1.5) * TILE
	await _wait_for_navigation(tiles, from, goal)
	var raw := NavigationServer2D.map_get_path(tiles.get_navigation_map(), from, goal, true)
	var leak := EnemyNavigation.find_corner_leak(tiles.get_navigation_map(), tiles, raw)
	assert_eq(leak, [Vector2i(5, 2), Vector2i(6, 3)] as Array[Vector2i], "the raw path squeezes through the corner (6, 3)")


func test_the_path_goes_around_a_corner_leak() -> void:
	var tiles := _leak_room()
	var from := Vector2(2.5, 1.5) * TILE
	var goal := Vector2(9.5, 1.5) * TILE
	var navigation := _navigation(tiles, Vector2(2.5, 1.5))
	await _wait_for_navigation(tiles, from, goal)
	var direction := navigation.path_direction(from, goal)
	assert_ne(direction, Vector2.ZERO, "follows a path")
	assert_gt(navigation.leak_repairs, 0, "the leak was closed")
	var waypoints := navigation.get_waypoints()
	var lowest := 0.0
	for point in waypoints:
		lowest = maxf(lowest, point.y)
	assert_gt(lowest, 6.0 * TILE, "the way leads through the gap in row 6: %s" % [waypoints])
	assert_true(EnemyNavigation.find_corner_leak(tiles.get_navigation_map(), tiles, waypoints).is_empty())


func test_a_corner_without_leak_keeps_the_short_path() -> void:
	var tiles := _leak_room()
	# Close the corner: (5, 2) becomes a pillar too, the wall is straight there.
	tiles.set_cell(Vector2i(5, 2), 0, PILLAR)
	var from := Vector2(2.5, 1.5) * TILE
	var goal := Vector2(9.5, 1.5) * TILE
	var navigation := _navigation(tiles, Vector2(2.5, 1.5))
	await _wait_for_navigation(tiles, from, goal)
	navigation.path_direction(from, goal)
	assert_eq(navigation.leak_repairs, 0, "nothing to repair")


## A solid prop across a room on tiles without navigation (D-115), with a gap in row 0: the enemy
## follows the path up to the gap instead of steering against the prop.
func test_a_prop_on_blocked_tiles_counts_like_a_wall() -> void:
	var room := Node2D.new()
	add_child_autofree(room)
	var tiles := RoomTiles.new()
	tiles.name = "Tiles"
	tiles.tile_set = load(TILESET_PATH)
	tiles.room_size = Vector2i(9, 5)
	tiles.scale = Vector2(2, 2)
	room.add_child(tiles)
	tiles.paint()
	EnemyNavigation.isolate_room_navigation(tiles)
	for y in range(1, 5):
		tiles.set_navigation_blocked(Vector2i(4, y), true)
	var body := StaticBody2D.new()
	body.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(48, 4 * TILE - 8)
	shape.shape = box
	body.add_child(shape)
	room.add_child(body)
	body.global_position = Vector2(4.5, 3.0) * TILE
	var navigation := _navigation(tiles, Vector2(1.5, 3.5))
	var from := Vector2(1.5, 3.5) * TILE
	var goal := Vector2(7.5, 3.5) * TILE
	await _wait_for_navigation(tiles, from, goal)
	assert_false(navigation.has_free_walk(from, goal), "the prop blocks the line")
	var direction := navigation.direction_to(from, goal)
	assert_ne(direction, Vector2.ZERO, "the prop is a hole of the navigation: follow the path")
	assert_lt(direction.y, 0.0, "the path leads up to the gap in row 0")

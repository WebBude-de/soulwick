extends GutTest
## Enemy pathfinding past props (boss_sim U-wall, 16.10.2026): a solid prop outside the navigation
## (torch stand, crystal, crate) in front of a wall must not hide the wall behind it. With only the
## first contact counted, the enemy took the prop for the whole obstacle, steered around it into the
## wall, then saw the wall again and swung between path and steering without getting out.

const ENEMY_SCENE_PATH := "res://enemies/enemy_base.tscn"
const TILESET_PATH := "res://dungeon/environment/dungeon_tileset.tres"
const TEST_SAVE_PATH := "user://test_enemy_nav_props.cfg"
const FLOOR := Vector2i(0, 0)
const PILLAR := Vector2i(6, 2)
const WALL_TOP := Vector2i(4, 0)

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


## 12 x 7 floor tiles with its own navigation map; wall: a pillar column at x = 6 with a gap in
## row 0. Returns the tile layer (child "Tiles" of the room, like RoomController).
func _room(with_wall: bool) -> TileMapLayer:
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
	if with_wall:
		for y in range(1, 7):
			tiles.set_cell(Vector2i(6, y), 0, PILLAR)
	EnemyNavigation.isolate_room_navigation(tiles)
	return tiles


## A solid prop body without navigation (like DecoProp -> LightIsland -> Blocker).
func _prop(parent: Node, tile_center: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(40, 40)
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = tile_center * 64.0
	return body


## An idle enemy (no player in the tree) whose navigation the test asks directly.
func _navigation(tiles: TileMapLayer) -> EnemyNavigation:
	var container := Node2D.new()
	tiles.get_parent().add_child(container)
	var enemy: Enemy = (load(ENEMY_SCENE_PATH) as PackedScene).instantiate()
	enemy.data = load("res://enemies/data/slime.tres")
	enemy.apply_scaling(1, false)
	enemy.position = Vector2(1.5, 0.5) * 64.0
	container.add_child(enemy)
	return enemy.get_navigation()


## Waits until the room's navigation map carries the floor of the tiles (the NavigationServer syncs
## asynchronously and the tile layer hands over its polygons a little later): a path query between
## two floor tiles returns a path. At most 3 s instead of a fixed number of frames.
func _wait_for_navigation(tiles: TileMapLayer) -> void:
	var from := tiles.to_global(tiles.map_to_local(Vector2i(0, 0)))
	var to := tiles.to_global(tiles.map_to_local(Vector2i(11, 0)))
	for i in 180:
		var map := tiles.get_navigation_map()
		if map.is_valid() and NavigationServer2D.map_get_iteration_id(map) > 0 \
				and not NavigationServer2D.map_get_path(map, from, to, true).is_empty():
			break
		await wait_physics_frames(1)
	await wait_physics_frames(2)


func test_a_prop_in_front_of_a_wall_does_not_hide_the_wall() -> void:
	var tiles := _room(true)
	# Directly in front of the wall on the enemy's side: the walk cast touches the prop first.
	_prop(tiles.get_parent(), Vector2(5.5, 5.5))
	var navigation := _navigation(tiles)
	await _wait_for_navigation(tiles)
	var from := Vector2(2.5, 5.5) * 64.0
	var goal := Vector2(9.5, 5.5) * 64.0
	assert_false(navigation.has_free_walk(from, goal), "prop and wall block the line")
	var direction := navigation.direction_to(from, goal)
	assert_ne(direction, Vector2.ZERO, "the wall behind the prop counts: follow the navigation path")
	assert_lt(direction.y, 0.0, "the path leads up to the gap in the wall")
	assert_true(navigation.is_following_path())


func test_a_prop_alone_stays_with_the_steering() -> void:
	var tiles := _room(false)
	_prop(tiles.get_parent(), Vector2(5.5, 5.5))
	var navigation := _navigation(tiles)
	await _wait_for_navigation(tiles)
	var from := Vector2(2.5, 5.5) * 64.0
	var goal := Vector2(9.5, 5.5) * 64.0
	assert_false(navigation.has_free_walk(from, goal), "the prop blocks the line")
	assert_eq(navigation.direction_to(from, goal), Vector2.ZERO, "no tiles behind it: the old steering walks around")
	assert_false(navigation.is_following_path())


func test_two_props_in_a_row_before_a_wall_still_find_the_wall() -> void:
	var tiles := _room(true)
	_prop(tiles.get_parent(), Vector2(4.0, 5.5))
	_prop(tiles.get_parent(), Vector2(5.5, 5.5))
	var navigation := _navigation(tiles)
	await _wait_for_navigation(tiles)
	var direction := navigation.direction_to(Vector2(2.5, 5.5) * 64.0, Vector2(9.5, 5.5) * 64.0)
	assert_ne(direction, Vector2.ZERO, "looks past both props (LOOK_PAST_BODIES)")

extends GutTest
## Enemy pathfinding (A2): target choice (nearest living player, coop-ready), path geometry,
## walking around a wall over the tile navigation and the fallback without navigation.

const ENEMY_SCENE_PATH := "res://enemies/enemy_base.tscn"
const PLAYER_SCENE_PATH := "res://player/player.tscn"
const TILESET_PATH := "res://dungeon/environment/dungeon_tileset.tres"
const TEST_SAVE_PATH := "user://test_enemy_nav.cfg"
const FLOOR := Vector2i(0, 0)
const PILLAR := Vector2i(6, 2)
const WALL_TOP := Vector2i(4, 0)

var _old_save_path: String


class FakePlayer:
	extends Node2D
	var alive := true

	func is_alive() -> bool:
		return alive


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.load_game()


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func after_each() -> void:
	HitStop.reset()
	for node in get_children():
		if node is Enemy or node is Projectile or node is Blast:
			node.queue_free()


func _fake(position: Vector2, alive := true) -> FakePlayer:
	var fake := FakePlayer.new()
	fake.alive = alive
	add_child_autofree(fake)
	fake.global_position = position
	return fake


func _player(position: Vector2) -> Player:
	var player: Player = add_child_autofree((load(PLAYER_SCENE_PATH) as PackedScene).instantiate())
	player.global_position = position
	player.health.reset(9999.0)
	return player


func _enemy(path: String, position: Vector2, parent: Node = self) -> Enemy:
	var enemy: Enemy = (load(ENEMY_SCENE_PATH) as PackedScene).instantiate()
	enemy.data = load(path)
	enemy.apply_scaling(1, false)
	enemy.position = position
	parent.add_child(enemy)
	if parent == self:
		autofree(enemy)
	return enemy


# --- Target choice ---

func test_nearest_living_skips_dead_freed_and_removed_candidates() -> void:
	var near_dead := _fake(Vector2(10, 0), false)
	var freed := FakePlayer.new()
	freed.free()
	var outside := FakePlayer.new()
	autofree(outside)
	var far := _fake(Vector2(300, 0))
	var middle := _fake(Vector2(120, 0))
	var candidates: Array = [near_dead, freed, outside, far, middle, null]
	assert_eq(EnemyTargeting.nearest_living(candidates, Vector2.ZERO), middle)
	middle.alive = false
	assert_eq(EnemyTargeting.nearest_living(candidates, Vector2.ZERO), far)
	far.alive = false
	assert_null(EnemyTargeting.nearest_living(candidates, Vector2.ZERO), "nobody alive")


func test_choose_keeps_the_target_until_another_is_clearly_closer() -> void:
	var current := _fake(Vector2(200, 0))
	var other := _fake(Vector2(-180, 0))
	var candidates: Array = [current, other]
	assert_eq(EnemyTargeting.choose(candidates, Vector2.ZERO, current), current, "only a little closer: keep")
	other.global_position = Vector2(-100, 0)
	assert_eq(EnemyTargeting.choose(candidates, Vector2.ZERO, current), other, "clearly closer: switch")
	assert_eq(EnemyTargeting.choose(candidates, Vector2.ZERO, null), other, "no target yet: nearest")
	other.alive = false
	assert_eq(EnemyTargeting.choose(candidates, Vector2.ZERO, other), current, "dead target is dropped")


func test_living_players_reads_the_player_group() -> void:
	var a := _fake(Vector2(0, 0))
	var b := _fake(Vector2(50, 0), false)
	a.add_to_group(&"player")
	b.add_to_group(&"player")
	var players := EnemyTargeting.living_players(get_tree())
	assert_has(players, a)
	assert_does_not_have(players, b, "dead players are no targets")


func test_enemy_targets_the_nearest_living_player() -> void:
	var far := _player(Vector2(600, 0))
	var near := _player(Vector2(150, 0))
	var enemy := _enemy("res://enemies/data/slime.tres", Vector2.ZERO)
	await wait_physics_frames(3)
	assert_eq(enemy.get_target(), near)
	near.health.take_damage(INF)
	await wait_physics_frames(3)
	assert_eq(enemy.get_target(), far, "switches at once when the target dies")
	HitStop.reset()


func test_enemy_switches_to_a_clearly_closer_player_after_rethinking() -> void:
	var first := _player(Vector2(300, 0))
	var second := _player(Vector2(-900, 0))
	var enemy := _enemy("res://enemies/data/slime.tres", Vector2.ZERO)
	await wait_physics_frames(3)
	assert_eq(enemy.get_target(), first)
	second.global_position = enemy.global_position + Vector2(-60, 0)
	await wait_seconds(Enemy.TARGET_INTERVAL + 0.2)
	assert_eq(enemy.get_target(), second)


# --- Path geometry ---

func test_clear_corners_moves_turns_outward_and_drops_duplicates() -> void:
	var path := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 0), Vector2(100, 100)])
	var points := EnemyNavigation.clear_corners(path, 10.0)
	assert_eq(points.size(), 2, "start dropped, duplicate merged")
	var expected := Vector2(100, 0) + Vector2(1, -1).normalized() * 10.0
	assert_almost_eq(points[0].x, expected.x, 0.01)
	assert_almost_eq(points[0].y, expected.y, 0.01, "away from the inner corner of the turn")
	assert_eq(points[1], Vector2(100, 100), "end point unchanged")
	var straight := EnemyNavigation.clear_corners(PackedVector2Array([Vector2.ZERO, Vector2(50, 0), Vector2(90, 0)]), 10.0)
	assert_eq(straight[0], Vector2(50, 0), "points on a straight line stay")


# --- Navigation ---

func test_enemy_without_navigation_keeps_the_old_steering() -> void:
	var enemy := _enemy("res://enemies/data/slime.tres", Vector2.ZERO)
	await wait_physics_frames(2)
	var navigation := enemy.get_navigation()
	assert_not_null(navigation)
	assert_eq(navigation.path_direction(Vector2.ZERO, Vector2(400, 0)), Vector2.ZERO, "no navigation, no path")
	assert_eq(navigation.path_requests, 0)


func test_tilesets_mark_only_floor_and_bridges_walkable() -> void:
	for path in ["res://dungeon/environment/dungeon_tileset.tres", "res://dungeon/environment/slime_grotto_tileset.tres",
			"res://dungeon/environment/shadow_realm_tileset.tres", "res://dungeon/environment/ember_forge_tileset.tres"]:
		var tileset: TileSet = load(path)
		assert_eq(tileset.get_navigation_layers_count(), 1, path)
		var ground := tileset.get_source(0) as TileSetAtlasSource
		for x in 4:
			assert_not_null(ground.get_tile_data(Vector2i(x, 0), 0).get_navigation_polygon(0), "floor %d walkable" % x)
		for coords in [WALL_TOP, Vector2i(5, 0), Vector2i(0, 1), PILLAR]:
			assert_null(ground.get_tile_data(coords, 0).get_navigation_polygon(0), "%s blocks" % coords)
		var inner_walls := tileset.get_source(1) as TileSetAtlasSource
		assert_null(inner_walls.get_tile_data(Vector2i(0, 0), 0).get_navigation_polygon(0), "inner walls block")
		var abyss := tileset.get_source(2) as TileSetAtlasSource
		assert_null(abyss.get_tile_data(Vector2i(0, 0), 0).get_navigation_polygon(0), "abyss is not walkable")
		var bridges := tileset.get_source(3) as TileSetAtlasSource
		assert_not_null(bridges.get_tile_data(Vector2i(0, 0), 0).get_navigation_polygon(0), "bridges are walkable")


func test_enemy_walks_around_a_wall_over_the_tile_navigation() -> void:
	# A small room: 12 x 7 floor, a wall column in the middle with a gap at the top.
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
	for y in range(1, 7):
		tiles.set_cell(Vector2i(6, y), 0, PILLAR)
	var map := EnemyNavigation.isolate_room_navigation(tiles)
	assert_true(map.is_valid(), "own navigation map for the room")
	var enemy_container := Node2D.new()
	room.add_child(enemy_container)
	var player := _player(Vector2(9.5, 5.5) * 64.0)
	var enemy := _enemy("res://enemies/data/skeleton.tres", Vector2(2.5, 5.5) * 64.0, enemy_container)
	await wait_physics_frames(5)
	var reached := false
	for i in 60 * 8:
		await wait_physics_frames(1)
		player.health.reset(9999.0)
		if enemy.global_position.distance_to(player.global_position) < 80.0:
			reached = true
			break
	assert_true(reached, "the enemy found the gap above the wall")
	assert_gt(enemy.get_navigation().path_requests, 0, "used the navigation")
	assert_eq(tiles.get_navigation_map(), map)


func test_solid_props_take_the_navigation_off_their_tile() -> void:
	var tiles := RoomTiles.new()
	tiles.tile_set = load(TILESET_PATH)
	tiles.room_size = Vector2i(5, 5)
	add_child_autofree(tiles)
	tiles.paint()
	EnemyNavigation.isolate_room_navigation(tiles)
	var tile := Vector2i(2, 2)
	tiles.set_navigation_blocked(tile, true)
	assert_true(tiles.is_navigation_blocked(tile))
	await wait_physics_frames(10)
	var center := tiles.to_global(tiles.map_to_local(tile))
	var closest := NavigationServer2D.map_get_closest_point(tiles.get_navigation_map(), center)
	assert_gt(closest.distance_to(center), 12.0, "no navigation polygon under the prop (nearest point on the tile edge)")
	tiles.set_navigation_blocked(tile, false)
	await wait_physics_frames(10)
	closest = NavigationServer2D.map_get_closest_point(tiles.get_navigation_map(), center)
	assert_lt(closest.distance_to(center), 2.0, "the tile is walkable again once the prop is gone")

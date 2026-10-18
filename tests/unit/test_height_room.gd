extends GutTest
## Height in a live room (M3, Makeover 3 §8): RoomTiles paints the plateau, HeightField holds its
## walls, ladder block, switch areas and pictures; walking (players, enemies), navigation over the
## stairs only, ladder slow, levels of bodies, melee blocked between levels while shots and
## explosions cross, enemies keep their level when they jump or teleport.

const TILESET_PATH := "res://dungeon/environment/dungeon_tileset.tres"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://enemies/enemy_base.tscn")
const TEST_SAVE_PATH := "user://test_height_room.cfg"
const UNIT := 64.0

var _old_save_path: String


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


## 9 x 8 cave room, plateau in the north-east (columns 5-8, rows 0-2): stairs at (6, 2), ladder at
## (8, 2); without_stairs: only the ladder.
func _room(without_stairs := false) -> RoomTiles:
	var room := Node2D.new()
	add_child_autofree(room)
	var tiles := RoomTiles.new()
	tiles.name = "Tiles"
	tiles.tile_set = load(TILESET_PATH)
	tiles.scale = Vector2(2, 2)
	tiles.rock_style = RoomTiles.RockStyle.BLOB
	tiles.room_size = Vector2i(9, 8)
	tiles.entrance_x = 2
	tiles.exit_x = 2
	var plateau: Array[Vector2i] = []
	for y in 3:
		for x in range(5, 9):
			plateau.append(Vector2i(x, y))
	plateau.erase(Vector2i(8, 2))
	var ladders: Array[Vector2i] = [Vector2i(8, 2)]
	var stairs: Array[Vector2i] = []
	if not without_stairs:
		plateau.erase(Vector2i(6, 2))
		stairs.append(Vector2i(6, 2))
	tiles.plateau_tiles = plateau
	tiles.ladder_tiles = ladders
	tiles.stair_tiles = stairs
	room.add_child(tiles)
	EnemyNavigation.isolate_room_navigation(tiles)
	return tiles


func _at(tiles: RoomTiles, tile: Vector2i) -> Vector2:
	return tiles.to_global(tiles.map_to_local(tile))


func _hits(tiles: RoomTiles, tile: Vector2i, mask: int) -> int:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = _at(tiles, tile)
	query.collision_mask = mask
	return tiles.get_world_2d().direct_space_state.intersect_point(query, 4).size()


func _player(at: Vector2) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.global_position = at - Vector2(0, 8)
	player.health.reset(9999.0)
	return player


func _enemy(at: Vector2, parent: Node) -> Enemy:
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	enemy.data = load("res://enemies/data/skeleton.tres")
	enemy.apply_scaling(1, false)
	parent.add_child(enemy)
	enemy.global_position = at
	return enemy


func test_the_room_builds_its_height_field() -> void:
	var tiles := _room()
	await wait_physics_frames(2)
	var field := tiles.get_height_field()
	assert_not_null(field, "a plateau room has a HeightField")
	assert_true(field.is_in_group(HeightRules.FIELDS_GROUP))
	assert_not_null(field.get_node_or_null(^"Surface"), "the plateau floor is drawn")
	assert_eq(field.get_connectors().size(), 2, "one switch area on the stairs, one on the ladder")
	assert_true(field.get_node(^"Cliffs") is HeightBody)
	assert_eq(tiles.get_cell_source_id(Vector2i(6, 0)), tiles.get_floor_source(), "surface is floor on the room layer")
	assert_eq(tiles.get_cell_source_id(Vector2i(5, 2)), -1, "a cliff has no cell: its wall is the HeightField's")
	assert_true(tiles.get_wall_mass().has(Vector2i(6, 0)), "for the floor rules a plateau stays rock")
	assert_true(tiles.get_room_shape_mask().has(Vector2i(8, 0)), "the room's shape (veil) includes the plateau")
	# Z order: the height belongs to the tile layer, below every figure (figures sort by y).
	var base: Node = autofree(load("res://dungeon/rooms/room_base.tscn").instantiate())
	assert_lt((base.get_node("Tiles") as Node2D).z_index + field.z_index, 0, "plateau, cliff and stairs are drawn below the figures")
	assert_true(field.z_as_relative)
	assert_eq(HeightChecks.problems(tiles.get_parent()), [] as Array[String], "live checks for the smoke test")


func test_cliffs_stop_walkers_but_not_shots() -> void:
	var tiles := _room()
	await wait_physics_frames(2)
	assert_gt(_hits(tiles, Vector2i(5, 2), PhysicsLayers.CLIFF), 0, "the cliff is a wall for walkers")
	assert_eq(_hits(tiles, Vector2i(5, 2), PhysicsLayers.WORLD), 0, "shots and sight fly over it")
	assert_eq(_hits(tiles, Vector2i(6, 0), PhysicsLayers.WORLD | PhysicsLayers.CLIFF), 0, "the surface is free")
	assert_eq(_hits(tiles, Vector2i(6, 2), PhysicsLayers.CLIFF), 0, "the stairs are free")
	assert_gt(_hits(tiles, Vector2i(8, 2), PhysicsLayers.LADDER), 0, "the ladder blocks enemies")
	assert_eq(_hits(tiles, Vector2i(8, 2), PhysicsLayers.CLIFF | PhysicsLayers.WORLD), 0, "players walk the ladder")


func test_players_cannot_walk_over_the_edge_but_up_the_stairs_and_the_ladder() -> void:
	var tiles := _room()
	await wait_physics_frames(2)
	var player := _player(_at(tiles, Vector2i(4, 1)))
	await wait_physics_frames(1)
	assert_true(player.test_move(player.global_transform, Vector2(UNIT, 0)), "edge to the plateau blocks")
	player.global_position = _at(tiles, Vector2i(6, 3)) - Vector2(0, 8)
	assert_false(player.test_move(player.global_transform, Vector2(0, -UNIT * 2)), "up the stairs")
	player.global_position = _at(tiles, Vector2i(8, 3)) - Vector2(0, 8)
	assert_false(player.test_move(player.global_transform, Vector2(0, -UNIT * 2)), "up the ladder")
	player.global_position = _at(tiles, Vector2i(7, 3)) - Vector2(0, 8)
	assert_true(player.test_move(player.global_transform, Vector2(0, -UNIT)), "not through the cliff")


func test_enemies_use_stairs_but_never_ladders() -> void:
	var tiles := _room()
	var enemy := _enemy(_at(tiles, Vector2i(8, 4)), tiles.get_parent())
	await wait_physics_frames(2)
	assert_true(enemy.test_move(enemy.global_transform, Vector2(0, -UNIT * 1.6)), "no enemy on the ladder")
	enemy.global_position = _at(tiles, Vector2i(6, 4))
	assert_false(enemy.test_move(enemy.global_transform, Vector2(0, -UNIT * 2.5)), "up the stairs")


func test_navigation_joins_the_levels_only_at_the_stairs() -> void:
	var tiles := _room()
	await wait_physics_frames(12)
	var map := tiles.get_navigation_map()
	var from := _at(tiles, Vector2i(4, 0))
	var to := _at(tiles, Vector2i(6, 0))
	var path := NavigationServer2D.map_get_path(map, from, to, true)
	assert_false(path.is_empty(), "the plateau is reachable for enemies")
	assert_lt(path[path.size() - 1].distance_to(to), 2.0, "the path ends on the plateau")
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	assert_gt(length, UNIT * 4.0, "around over the stairs, not two tiles straight over the edge: %s" % path)
	var island := _room(true)
	await wait_physics_frames(12)
	var island_to := _at(island, Vector2i(6, 0))
	var island_path := NavigationServer2D.map_get_path(island.get_navigation_map(), _at(island, Vector2i(4, 0)), island_to, true)
	assert_true(island_path.is_empty() or island_path[island_path.size() - 1].distance_to(island_to) > 2.0, "a ladder plateau has no way up for enemies: %s" % island_path)


func test_levels_of_bodies_and_points() -> void:
	var tiles := _room()
	await wait_physics_frames(2)
	assert_eq(HeightRules.level_at(_at(tiles, Vector2i(7, 0))), HeightRules.PLATEAU)
	assert_eq(HeightRules.level_at(_at(tiles, Vector2i(2, 5))), HeightRules.GROUND)
	assert_eq(HeightRules.level_at(_at(tiles, Vector2i(6, 2))), HeightRules.BOTH)
	var up := _player(_at(tiles, Vector2i(7, 1)))
	var down := _player(_at(tiles, Vector2i(7, 3)))
	await wait_physics_frames(1)
	assert_eq(HeightRules.level_of(up), HeightRules.PLATEAU, "level from the feet circle of the player")
	assert_eq(HeightRules.level_of(down), HeightRules.GROUND)
	assert_false(HeightRules.same_level(up, down))


func test_melee_is_blocked_between_levels_shots_and_blasts_are_not() -> void:
	var tiles := _room()
	await wait_physics_frames(2)
	var up := _player(_at(tiles, Vector2i(7, 1)))
	var enemy := _enemy(_at(tiles, Vector2i(7, 3)), tiles.get_parent())
	await wait_physics_frames(1)
	var swing := DamageData.new()
	swing.amount = 1.0
	swing.source = enemy
	swing.tags.assign([&"melee"])
	assert_true(HeightRules.blocks_hit(swing, up), "no bite up the cliff")
	var result := DamageProcessor.process_hit(swing, up.health, up.shield, false)
	assert_true(result.blocked, "the hit does not land")
	var shot := swing.duplicate_for_target()
	shot.tags.append(&"projectile")
	assert_false(HeightRules.blocks_hit(shot, up), "a shot from below hits above")
	var blast := DamageData.new()
	blast.source = enemy
	blast.tags.assign([&"explosion"])
	assert_false(HeightRules.blocks_hit(blast, up), "explosions cross levels")
	enemy.global_position = _at(tiles, Vector2i(6, 2))
	assert_false(HeightRules.blocks_hit(swing, up), "from the stairs both levels are in reach")


func test_enemy_projectiles_carry_the_projectile_tag() -> void:
	var tiles := _room()
	await wait_physics_frames(2)
	var enemy := _enemy(_at(tiles, Vector2i(2, 5)), tiles.get_parent())
	await wait_physics_frames(1)
	var damage := DamageData.new()
	damage.tags.assign([&"melee"])
	enemy.call(&"_fire_projectile", damage, Vector2.RIGHT)
	assert_true(damage.tags.has(&"projectile"), "shots of melee bosses cross levels too")


func test_enemies_keep_their_level_when_they_teleport_or_leap() -> void:
	var tiles := _room()
	await wait_physics_frames(2)
	var below := _at(tiles, Vector2i(3, 4))
	assert_eq(HeightRules.keep_level(below, _at(tiles, Vector2i(7, 0))), below, "not up onto the plateau")
	assert_eq(HeightRules.keep_level(below, _at(tiles, Vector2i(5, 2))), below, "not into the cliff")
	assert_eq(HeightRules.keep_level(below, _at(tiles, Vector2i(2, 6))), _at(tiles, Vector2i(2, 6)), "on the ground: unchanged")
	assert_eq(HeightRules.keep_level(_at(tiles, Vector2i(6, 2)), _at(tiles, Vector2i(7, 0))), _at(tiles, Vector2i(7, 0)), "from the stairs both ways")


func test_the_ladder_slows_the_player_and_the_switch_reports_the_level() -> void:
	var tiles := _room()
	await wait_physics_frames(2)
	var player := _player(_at(tiles, Vector2i(8, 4)))
	var speed := player.move_speed
	var changes: Array = []
	tiles.get_height_field().level_changed.connect(func(body: Node2D, level: int) -> void: changes.append([body, level]))
	await wait_physics_frames(2)
	player.global_position = _at(tiles, Vector2i(8, 2)) - Vector2(0, 8)
	await wait_physics_frames(3)
	assert_not_null(tiles.get_height_field().climbing(player), "on the ladder")
	assert_almost_eq(player.move_speed, speed * HeightRules.LADDER_SLOW, 0.01, "climbing is slow")
	player.global_position = _at(tiles, Vector2i(8, 0)) - Vector2(0, 8)
	await wait_physics_frames(3)
	assert_almost_eq(player.move_speed, speed, 0.01, "full speed on the plateau")
	assert_eq(changes.size(), 1, "one level change reported")
	if changes.size() == 1:
		assert_eq(changes[0][1], HeightRules.PLATEAU)


func test_height_reachable_tiles_for_players_and_enemies() -> void:
	var tiles := _room(true)
	var players := tiles.get_height_reachable_tiles()
	var enemies := tiles.get_height_reachable_tiles(true)
	assert_true(players.has(Vector2i(7, 0)), "players reach the plateau over the ladder")
	assert_false(enemies.has(Vector2i(7, 0)), "enemies do not")
	assert_false(tiles.get_reachable_tiles().has(Vector2i(7, 0)), "the ground rules keep the plateau as rock")
	assert_eq(RoomPlanChecks.height_problems(tiles), [] as Array[String])


func test_an_enemy_walks_up_the_stairs_to_a_player_on_the_plateau() -> void:
	var tiles := _room()
	var container := Node2D.new()
	container.name = "EnemyContainer"
	tiles.get_parent().add_child(container)
	await wait_physics_frames(12)
	var player := _player(_at(tiles, Vector2i(7, 0)))
	var enemy := _enemy(_at(tiles, Vector2i(2, 6)), container)
	var reached := false
	for i in 60 * 10:
		await wait_physics_frames(1)
		player.health.reset(9999.0)
		if HeightRules.level_of(enemy) == HeightRules.PLATEAU:
			reached = true
			break
	assert_true(reached, "the skeleton found the stairs (now at %s)" % tiles.local_to_map(tiles.to_local(enemy.global_position)))


func test_a_ladder_plateau_is_a_safe_island() -> void:
	var tiles := _room(true)
	var container := Node2D.new()
	container.name = "EnemyContainer"
	tiles.get_parent().add_child(container)
	await wait_physics_frames(12)
	var player := _player(_at(tiles, Vector2i(7, 0)))
	var enemy := _enemy(_at(tiles, Vector2i(2, 6)), container)
	var hits := 0
	player.hurtbox.hit_received.connect(func(_result: DamageResult, _damage: DamageData) -> void: hits += 1)
	var climbed := false
	for i in 60 * 5:
		await wait_physics_frames(1)
		player.health.reset(9999.0)
		climbed = climbed or HeightRules.level_of(enemy) == HeightRules.PLATEAU
	assert_false(climbed, "no enemy up the ladder")
	assert_eq(hits, 0, "no melee hit from below the cliff")

extends GutTest
## Melee enemies reach a player or the soul flame on a plateau over its stairs (M3, D-186/D-189;
## feedback #690502d9: three slimes pressed against the right edge of the flame plateau in
## flamme_schrein_crypt and never walked round to the stairs - their pack hopped them back to the
## cliff). Real template with its plateau, real slimes and skeletons with their pack tactics.

const FLAME_ROOM := "res://dungeon/rooms/combat/flamme_schrein_crypt.tscn"
const ENEMY_SCENE: PackedScene = preload("res://enemies/enemy_base.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const SLIME: EnemyData = preload("res://enemies/data/slime.tres")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
## Seed of the feedback run (#690502d9).
const FEEDBACK_SEED := -4728548023312275300
## Seconds every melee enemy gets to stand next to its target on the plateau. TESTWERT
const REACH_LIMIT := 10.0
## "Next to its target": this close and on its level (px).
const REACH_DISTANCE := 96.0
## A fighting player steps to the next tile of its route this often (s).
const ROUTE_STEP := 0.6

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_enemy_nav_height_save.cfg"


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()


func after_each() -> void:
	HitStop.reset()
	await wait_process_frames(1)


func _room(room_index: int) -> RoomController:
	var room := (load(FLAME_ROOM) as PackedScene).instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = FEEDBACK_SEED
	room.setup(room_index, RoomSequence.RoomType.COMBAT, -1, false, context)
	add_child_autofree(room)
	return room


func _at(room: RoomController, tile: Vector2i) -> Vector2:
	return room.tiles.to_global(room.tiles.map_to_local(tile))


func _tile(room: RoomController, node: Node2D) -> Vector2i:
	return room.tiles.local_to_map(room.tiles.to_local(node.global_position))


func _player(room: RoomController, tile: Vector2i) -> Player:
	assert_true(room.tiles.get_height_layout().surface.has(tile), "%s is plateau surface" % tile)
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.global_position = _at(room, tile) - Vector2(0, 8)
	player.health.reset(9999.0)
	return player


func _enemies(room: RoomController, data: EnemyData, tiles: Array[Vector2i]) -> Array[Enemy]:
	var enemies: Array[Enemy] = []
	for tile in tiles:
		assert_false(room.tiles.get_height_layout().get_height_tiles().has(tile), "%s is ground" % tile)
		var enemy: Enemy = ENEMY_SCENE.instantiate()
		enemy.data = data
		enemy.arena = room.get_arena()
		enemy.apply_scaling(room.room_index, false)
		room.enemy_container.add_child(enemy)
		enemy.global_position = _at(room, tile)
		enemies.append(enemy)
	return enemies


## Runs until every enemy stood next to target on its level once; returns the ones that never did.
## route: plateau tiles the player steps to in turn, one every ROUTE_STEP seconds (a fighting player).
func _never_reached(room: RoomController, player: Player, target: Node2D, enemies: Array[Enemy], route: Array[Vector2i] = []) -> Array[String]:
	var reached := {}
	var step := int(ROUTE_STEP * 60.0)
	for frame in int(REACH_LIMIT * 60.0):
		if not route.is_empty() and frame % step == 0:
			player.global_position = _at(room, route[(frame / step) % route.size()]) - Vector2(0, 8)
		await wait_physics_frames(1)
		player.health.reset(9999.0)
		for enemy in enemies:
			if is_instance_valid(enemy) and enemy.global_position.distance_to(target.global_position) < REACH_DISTANCE and HeightRules.same_level(enemy, target):
				reached[enemy.get_instance_id()] = true
		if reached.size() == enemies.size():
			break
	var missing: Array[String] = []
	for enemy in enemies:
		if is_instance_valid(enemy) and not reached.has(enemy.get_instance_id()):
			missing.append("%s at %s, level %d" % [enemy.data.id, _tile(room, enemy), HeightRules.level_of(enemy)])
	return missing


func _case(room_index: int, data: EnemyData, player_tile: Vector2i, enemy_tiles: Array[Vector2i], route: Array[Vector2i] = []) -> void:
	var room := _room(room_index)
	await wait_physics_frames(12)
	var player := _player(room, player_tile)
	var enemies := _enemies(room, data, enemy_tiles)
	var missing := await _never_reached(room, player, player, enemies, route)
	assert_eq(missing, [] as Array[String], "%s (room %d) reach the player at %s over the stairs within %.0f s" % [data.id, room_index, player_tile, REACH_LIMIT])
	# Several cases per test: the next one gets the room and the player alone.
	player.queue_free()
	room.queue_free()
	await wait_physics_frames(2)


## The feedback case: player on the right part of the plateau, three slimes below its right edge;
## once standing, once fighting along the edge (before the fix the ones that came up waited at the
## head of the stairs for ring places off the plateau).
func test_slimes_below_the_right_edge_walk_round_to_the_stairs() -> void:
	var slimes: Array[Vector2i] = [Vector2i(12, 2), Vector2i(12, 3), Vector2i(12, 4)]
	var route: Array[Vector2i] = [Vector2i(11, 3), Vector2i(11, 2), Vector2i(10, 3), Vector2i(11, 2)]
	for room_index in [6, 26]:
		await _case(room_index, SLIME, Vector2i(11, 3), slimes)
		await _case(room_index, SLIME, Vector2i(11, 3), slimes, route)


## Before the fix their pack hopped them back against the cliff again and again.
func test_slimes_below_the_left_edge_walk_round_to_the_stairs() -> void:
	for room_index in [6, 26]:
		await _case(room_index, SLIME, Vector2i(7, 2), [Vector2i(6, 2), Vector2i(6, 3), Vector2i(5, 1)] as Array[Vector2i])


## Ring places around a player on the plateau must stay on the plateau: before the fix a skeleton
## that was already up walked down the stairs again towards a ring place on the ground behind it.
func test_skeletons_above_the_plateau_walk_round_to_the_stairs() -> void:
	for room_index in [6, 26]:
		await _case(room_index, SKELETON, Vector2i(10, 3), [Vector2i(9, 1), Vector2i(10, 1), Vector2i(12, 1)] as Array[Vector2i])


## A player pressed against the back edge of the plateau stands with his origin over the strip
## without navigation: the path goal must stay on the plateau, not on the ground behind the edge.
func test_a_player_at_the_back_edge_is_reached_over_the_stairs() -> void:
	var room := _room(26)
	await wait_physics_frames(12)
	var player := _player(room, Vector2i(10, 2))
	player.move_and_collide(Vector2(0, -RoomTiles.TILE_WORLD))
	await wait_physics_frames(1)
	assert_eq(HeightRules.level_of(player), HeightRules.PLATEAU, "pressed against the edge, still up there")
	var goal := HeightRules.navigation_goal(player.global_position)
	var closest := NavigationServer2D.map_get_closest_point(room.tiles.get_navigation_map(), goal)
	assert_eq(HeightRules.level_at(closest), HeightRules.PLATEAU, "the path goal %s lies in the plateau's navigation (%s)" % [goal, closest])
	assert_eq(HeightRules.navigation_goal(_at(room, Vector2i(10, 6))), _at(room, Vector2i(10, 6)), "ground goals stay")
	var enemies := _enemies(room, SKELETON, [Vector2i(12, 5), Vector2i(6, 5)] as Array[Vector2i])
	var missing := await _never_reached(room, player, player, enemies)
	assert_eq(missing, [] as Array[String], "skeletons reach the player at the back edge over the stairs")


## Flame mode (D-189): raiders go for the soul flame on the plateau while the player stands up there.
func test_slimes_reach_the_soul_flame_on_the_plateau() -> void:
	var room := _room(6)
	var rng := RandomNumberGenerator.new()
	rng.seed = FEEDBACK_SEED
	assert_eq(RoomVariants.attach(room, VariantTable.pick_for(&"flame"), rng), &"flame", "flame mode attached")
	var mode := CombatVariant.of(room) as FlameMode
	await wait_physics_frames(12)
	var flame_tile := _tile(room, mode.flame)
	assert_true(room.tiles.get_height_layout().surface.has(flame_tile), "the flame burns on the plateau")
	var player := _player(room, Vector2i(11, 3))
	var enemies := _enemies(room, SLIME, [Vector2i(12, 2), Vector2i(12, 3), Vector2i(12, 4)] as Array[Vector2i])
	for enemy in enemies:
		EnemyDecoy.assign(enemy, mode.flame)
		enemy.set_meta(&"flame_rolled", true)
	mode.flame.health.reset(99999.0)
	var missing := await _never_reached(room, player, mode.flame, enemies)
	assert_eq(missing, [] as Array[String], "slimes reach the flame at %s over the stairs" % flame_tile)

extends GutTest
## Melee enemies below a plateau reach a player on it over its stairs, ranged ones shoot from below
## (M3, D-189 Nachtrag, D-205 half height), in rooms built like the dungeon builds the next room:
## tiles held back, the room hidden while they are painted, shown later (DungeonManager staging).
## Bug reports 23.10.2026 #03d88a6b (kreuzgang_mirror_crypt, room 8: "Die stehen hier und kommen
## nicht hoch") and #536bc219 (flamme_schrein_crypt, room 7: "Ich kann hier oben stehen und die
## Monster kommen nicht hoch"): Godot builds no runtime tile data for a hidden layer and not later
## either, so the plateau's cut-off edges were missing from the navigation; ground and plateau
## joined at every edge and the enemies pressed against the cliff on the shortest line (RoomTiles
## rebuilds it once a layer painted while hidden shows). The same the other way round (#4be5188b,
## koop, room 7 geleit_pfad_crypt: "Die kommen hier nicht runter"): enemies on the plateau, also one coming out
## of the plateau's source, must come down the stairs to players below. Several templates with
## plateaus, mirrored ones and all biomes; the player at the edge farthest from the stairs.

const ENEMY_SCENE: PackedScene = preload("res://enemies/enemy_base.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const SLIME: EnemyData = preload("res://enemies/data/slime.tres")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
const ARCHER: EnemyData = preload("res://enemies/data/archer.tres")
const COMBAT_DIR := "res://dungeon/rooms/combat/"
## The two reported rooms with the player where he stood (room layer px, 32 per tile), then more
## templates with a plateau and stairs: mirrored plans, L plans, every biome.
const REPORTED := {
	"kreuzgang_mirror_crypt": Vector2(6 * 32 + 20, 2 * 32 + 30),
	"flamme_schrein_crypt": Vector2(10 * 32 + 27, 2 * 32 + 10),
}
const MORE_TEMPLATES: Array[String] = [
	"kreuzgang_slime_grotto", "halbmond_mirror_ember_forge", "rundhoehle_mirror_shadow_realm",
	"weiche_hoehle_mirror_crypt", "gewoelbe_l_mirror_slime_grotto", "flamme_schrein_shadow_realm",
]
## #4be5188b, koop: the client's player beside the plateau, the host's far below (room layer px),
## the plateau's source (Source4) and enemies up there (room tiles).
const DOWN_TEMPLATE := "geleit_pfad_crypt"
const DOWN_PLAYERS: Array[Vector2] = [Vector2(330.4, 103.9), Vector2(83.5, 224.2)]
const DOWN_ENEMIES: Array[Vector2i] = [Vector2i(8, 2), Vector2i(8, 1), Vector2i(5, 1)]
const DOWN_SOURCE := Vector2i(7, 2)
## Room number of the reports (cycle 1, no elites forced).
const ROOM_INDEX := 8
## Seconds every melee enemy gets to stand next to the player on his level. TESTWERT
const REACH_LIMIT := 12.0
## "Next to the player": this close and on his level (px).
const REACH_DISTANCE := 96.0
## Seconds a ranged enemy below gets for its first shot at the player up there. TESTWERT
const SHOT_LIMIT := 6.0
## Physics frames the room stays hidden after its paint (the staging takes a few frames).
const HIDDEN_FRAMES := 3
## Physics frames the navigation map may take for its next iteration after the room shows (async
## iterations, slow on a busy machine). TESTWERT
const SYNC_FRAMES := 180

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_enemy_nav_plateaus_save.cfg"


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


## The room as DungeonManager stages the next one: tiles held, room hidden while they are painted,
## shown a few frames later.
func _staged_room(template: String) -> RoomController:
	var room := (load(COMBAT_DIR + template + ".tscn") as PackedScene).instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 6935191255933611860
	room.setup(ROOM_INDEX, RoomSequence.RoomType.COMBAT, -1, false, context)
	(room.get_node(^"Tiles") as RoomTiles).hold_paint()
	add_child_autofree(room)
	room.visible = false
	await wait_process_frames(1)
	room.tiles.release_paint()
	await wait_physics_frames(HIDDEN_FRAMES)
	room.visible = true
	# The navigation map takes a few physics frames for its next iteration.
	await wait_physics_frames(20)
	return room


func _at(room: RoomController, tile: Vector2i) -> Vector2:
	return room.tiles.to_global(room.tiles.map_to_local(tile))


func _tile(room: RoomController, point: Vector2) -> Vector2i:
	return room.tiles.local_to_map(room.tiles.to_local(point))


## Floor tiles nothing stands on (props, sources, blocked navigation).
func _free(room: RoomController, tile: Vector2i) -> bool:
	return not RoomPlanChecks.solid_tiles(room).has(tile) and not RoomPlanChecks.floor_source_tiles(room).has(tile) \
			and not room.tiles.is_navigation_blocked(tile)


## Surface tile at an edge to the ground, reached by enemies, farthest from the stairs.
func _player_tile(room: RoomController) -> Vector2i:
	var layout := room.tiles.get_height_layout()
	var reached := room.tiles.get_height_reachable_tiles(true)
	var best := Vector2i(-1, -1)
	var best_distance := -1
	for tile: Vector2i in layout.edge_sides:
		if not reached.has(tile) or not _free(room, tile) or not (int(layout.edge_sides[tile]) & (2 | 8)):
			continue
		var distance := 1 << 30
		for stairs: Vector2i in layout.stairs:
			distance = mini(distance, absi(stairs.x - tile.x) + absi(stairs.y - tile.y))
		if distance > best_distance or (distance == best_distance and tile < best):
			best_distance = distance
			best = tile
	return best


## Up to count ground tiles beside the plateau closest to the player tile (the hard case: the
## straight line runs over the edge, the way over the stairs).
func _ground_beside(room: RoomController, player_tile: Vector2i, count: int) -> Array[Vector2i]:
	var layout := room.tiles.get_height_layout()
	var reached := room.tiles.get_height_reachable_tiles(true)
	var candidates: Array[Vector2i] = []
	for tile: Vector2i in layout.ground:
		if reached.has(tile) and _free(room, tile) and not room.tiles.is_pit(tile) and not layout.get_connector_feet().has(tile):
			candidates.append(tile)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := Vector2(a - player_tile).length()
		var db := Vector2(b - player_tile).length()
		return da < db or (da == db and a < b))
	return candidates.slice(0, count)


func _player(room: RoomController, origin: Vector2) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.global_position = origin
	player.health.reset(9999.0)
	return player


func _enemy(room: RoomController, data: EnemyData, tile: Vector2i) -> Enemy:
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	enemy.data = data
	enemy.arena = room.get_arena()
	enemy.apply_scaling(room.room_index, false)
	room.enemy_container.add_child(enemy)
	enemy.global_position = _at(room, tile)
	return enemy


## Melee group below the plateau: every one must stand next to the player on his level once.
func _melee_case(template: String, origin_layer := Vector2.INF) -> Array[String]:
	var room := await _staged_room(template)
	var player_tile := _player_tile(room) if origin_layer == Vector2.INF else room.tiles.local_to_map(origin_layer)
	var origin := _at(room, player_tile) - Vector2(0, 8) if origin_layer == Vector2.INF else room.tiles.to_global(origin_layer)
	var problems: Array[String] = []
	if not room.tiles.get_height_layout().surface.has(player_tile):
		problems.append("%s: no surface tile for the player (%s)" % [template, player_tile])
		return problems
	var player := _player(room, origin)
	await wait_physics_frames(2)
	if HeightRules.level_of(player) != HeightRules.PLATEAU:
		problems.append("%s: player at %s is not on the plateau" % [template, _tile(room, player.global_position)])
	var enemies: Array[Enemy] = []
	var tiles := _ground_beside(room, player_tile, 3)
	for i in tiles.size():
		enemies.append(_enemy(room, SKELETON if i == 0 else SLIME, tiles[i]))
	var reached := {}
	for frame in int(REACH_LIMIT * 60.0):
		await wait_physics_frames(1)
		player.health.reset(9999.0)
		for enemy in enemies:
			if is_instance_valid(enemy) and enemy.global_position.distance_to(player.global_position) < REACH_DISTANCE and HeightRules.same_level(enemy, player):
				reached[enemy.get_instance_id()] = true
		if reached.size() == enemies.size():
			break
	for enemy in enemies:
		if is_instance_valid(enemy) and not reached.has(enemy.get_instance_id()):
			problems.append("%s: %s from below never reached the player at %s (now %s, level %d)" % [template, enemy.data.id, player_tile, _tile(room, enemy.global_position), HeightRules.level_of(enemy)])
	player.queue_free()
	room.queue_free()
	await wait_physics_frames(2)
	return problems


## Plateau tiles whose side edge to the ground lies in the navigation (1 layer px inside the edge).
func _edge_leaks(room: RoomController) -> Array[Vector2i]:
	var map := room.tiles.get_navigation_map()
	var layout := room.tiles.get_height_layout()
	var leaks: Array[Vector2i] = []
	for tile: Vector2i in layout.edge_sides:
		var sides := int(layout.edge_sides[tile])
		for side: Array in [[2, Vector2(15, 0)], [8, Vector2(-15, 0)]]:
			if sides & int(side[0]):
				var point := room.tiles.to_global(room.tiles.map_to_local(tile) + (side[1] as Vector2))
				if NavigationServer2D.map_get_closest_point(map, point).distance_to(point) < 0.5:
					leaks.append(tile)
	return leaks


## The navigation of a staged room keeps the plateau's edges cut off once it shows.
func test_a_room_painted_while_hidden_keeps_its_plateau_edges_off_the_navigation() -> void:
	var room := await _staged_room("kreuzgang_mirror_crypt")
	var map := room.tiles.get_navigation_map()
	var layout := room.tiles.get_height_layout()
	assert_false(layout.edge_sides.is_empty(), "the room has plateau edges")
	# The navigation map iterates in the background; under load it takes a few frames more.
	var leaks := _edge_leaks(room)
	for frame in SYNC_FRAMES:
		if leaks.is_empty():
			break
		await wait_physics_frames(1)
		leaks = _edge_leaks(room)
	assert_eq(leaks, [] as Array[Vector2i], "no navigation on the edge strip of the plateau")
	var from := _at(room, Vector2i(5, 3))
	var path := NavigationServer2D.map_get_path(map, from, HeightRules.navigation_goal(room.tiles.to_global(REPORTED["kreuzgang_mirror_crypt"])), true)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	assert_gt(length, RoomTiles.TILE_WORLD * 4.0, "from beside the edge the way leads round over the stairs: %s" % path)


## The reported cases, with the player where he stood.
func test_melee_enemies_reach_the_player_in_the_reported_rooms() -> void:
	for template: String in REPORTED:
		var problems := await _melee_case(template, REPORTED[template])
		assert_eq(problems, [] as Array[String], "%s: melee enemies walk over the stairs within %.0f s" % [template, REACH_LIMIT])


## More plateau templates (mirrored, L plans, every biome): player on the edge farthest from the
## stairs, enemies on the ground beside him.
func test_melee_enemies_reach_the_player_on_other_plateaus() -> void:
	for template in MORE_TEMPLATES:
		if not ResourceLoader.exists(COMBAT_DIR + template + ".tscn"):
			continue
		var problems := await _melee_case(template)
		assert_eq(problems, [] as Array[String], "%s: melee enemies walk over the stairs within %.0f s" % [template, REACH_LIMIT])


## Ranged enemies may shoot from below (D-189): an archer below the plateau takes aim at the player
## up there without climbing first.
func test_an_archer_below_shoots_up_at_the_plateau() -> void:
	var room := await _staged_room("kreuzgang_mirror_crypt")
	var origin_layer: Vector2 = REPORTED["kreuzgang_mirror_crypt"]
	var player := _player(room, room.tiles.to_global(origin_layer))
	var archer := _enemy(room, ARCHER, Vector2i(9, 6))
	var aimed := false
	for frame in int(SHOT_LIMIT * 60.0):
		await wait_physics_frames(1)
		player.health.reset(9999.0)
		if archer._state == Enemy.State.TELEGRAPH and HeightRules.level_of(archer) == HeightRules.GROUND:
			aimed = true
			break
	assert_true(aimed, "the archer takes aim from below (now %s, level %d)" % [_tile(room, archer.global_position), HeightRules.level_of(archer)])


## Ground tile beside a plateau edge (east, west or north of it), reached by enemies, farthest from
## the stairs.
func _ground_player_tile(room: RoomController) -> Vector2i:
	var layout := room.tiles.get_height_layout()
	var reached := room.tiles.get_height_reachable_tiles(true)
	var best := Vector2i(-1, -1)
	var best_distance := -1
	for edge: Vector2i in layout.edge_sides:
		var sides := int(layout.edge_sides[edge])
		for pair: Array in [[1, Vector2i.UP], [2, Vector2i.RIGHT], [8, Vector2i.LEFT]]:
			var tile: Vector2i = edge + (pair[1] as Vector2i)
			if not (sides & int(pair[0])) or not reached.has(tile) or not _free(room, tile) or room.tiles.is_pit(tile):
				continue
			var distance := 1 << 30
			for stairs: Vector2i in layout.stairs:
				distance = mini(distance, absi(stairs.x - tile.x) + absi(stairs.y - tile.y))
			if distance > best_distance or (distance == best_distance and tile < best):
				best_distance = distance
				best = tile
	return best


## Up to count free surface tiles reached by enemies, closest to tile.
func _surface_near(room: RoomController, tile: Vector2i, count: int) -> Array[Vector2i]:
	var layout := room.tiles.get_height_layout()
	var reached := room.tiles.get_height_reachable_tiles(true)
	var candidates: Array[Vector2i] = []
	for surface: Vector2i in layout.surface:
		if reached.has(surface) and _free(room, surface):
			candidates.append(surface)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := Vector2(a - tile).length()
		var db := Vector2(b - tile).length()
		return da < db or (da == db and a < b))
	return candidates.slice(0, count)


## Runs until every enemy stood next to one of the players on his level once; the ones that never did.
func _never_reached(room: RoomController, players: Array[Player], enemies: Array[Enemy], label: String) -> Array[String]:
	var reached := {}
	for frame in int(REACH_LIMIT * 60.0):
		await wait_physics_frames(1)
		for player in players:
			player.health.reset(9999.0)
		for enemy in enemies:
			if not is_instance_valid(enemy):
				continue
			for player in players:
				if enemy.global_position.distance_to(player.global_position) < REACH_DISTANCE and HeightRules.same_level(enemy, player):
					reached[enemy.get_instance_id()] = true
		if reached.size() == enemies.size():
			break
	var problems: Array[String] = []
	for enemy in enemies:
		if is_instance_valid(enemy) and not reached.has(enemy.get_instance_id()):
			problems.append("%s: %s never came down to a player (now %s, level %d)" % [label, enemy.data.id, _tile(room, enemy.global_position), HeightRules.level_of(enemy)])
	return problems


## Melee group on the plateau, players below at origins (room layer px) or beside the edge farthest
## from the stairs; source: one more enemy comes out of this plateau tile like from a spawn source.
func _down_case(template: String, origins: Array[Vector2] = [], enemy_tiles: Array[Vector2i] = [], source := Vector2i(-1, -1)) -> Array[String]:
	var room := await _staged_room(template)
	var problems: Array[String] = []
	var players: Array[Player] = []
	if origins.is_empty():
		var ground := _ground_player_tile(room)
		if ground.x < 0:
			problems.append("%s: no ground tile beside the plateau" % template)
			return problems
		players.append(_player(room, _at(room, ground) - Vector2(0, 8)))
		enemy_tiles = _surface_near(room, ground, 3)
	else:
		for origin in origins:
			players.append(_player(room, room.tiles.to_global(origin)))
	await wait_physics_frames(2)
	for player in players:
		if HeightRules.level_of(player) != HeightRules.GROUND:
			problems.append("%s: player at %s is not on the ground" % [template, _tile(room, player.global_position)])
	var enemies: Array[Enemy] = []
	for i in enemy_tiles.size():
		assert_true(room.tiles.get_height_layout().surface.has(enemy_tiles[i]), "%s: %s is plateau surface" % [template, enemy_tiles[i]])
		enemies.append(_enemy(room, SKELETON if i == 0 else SLIME, enemy_tiles[i]))
	if source.x >= 0:
		var risen := _enemy(room, SKELETON, source)
		risen.begin_emerge(0.0, 1.0)
		enemies.append(risen)
	problems.append_array(await _never_reached(room, players, enemies, template))
	for player in players:
		player.queue_free()
	room.queue_free()
	await wait_physics_frames(2)
	return problems


## #4be5188b: in the reported room with both players where they stood, the enemies up there and one
## coming out of the plateau's source walk down the stairs.
func test_enemies_on_the_plateau_come_down_to_the_players_in_the_reported_room() -> void:
	var problems := await _down_case(DOWN_TEMPLATE, DOWN_PLAYERS, DOWN_ENEMIES, DOWN_SOURCE)
	assert_eq(problems, [] as Array[String], "%s: down the stairs within %.0f s" % [DOWN_TEMPLATE, REACH_LIMIT])


## The way down in more plateau templates: player on the ground beside the edge farthest from the
## stairs, enemies on the plateau next to him.
func test_enemies_on_the_plateau_come_down_in_other_rooms() -> void:
	for template in MORE_TEMPLATES:
		if not ResourceLoader.exists(COMBAT_DIR + template + ".tscn"):
			continue
		var problems := await _down_case(template)
		assert_eq(problems, [] as Array[String], "%s: down the stairs within %.0f s" % [template, REACH_LIMIT])

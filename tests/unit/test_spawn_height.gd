extends GutTest
## Enemy sources on plateaus (M3b, D-189, Projektmitglied 18.10.2026): a floor source may lie on a
## plateau with stairs; ranged enemies of a push take those sources first ("Druck von oben"),
## close-combat enemies come out on the ground (SpawnSourceRules.sort_by_height, SpawnSources).

## Sumpfgrotte: a grave (crypt) on the plateau before the north wall (free-standing, D-205), three on
## the ground.
const PLAN_ROOM: PackedScene = preload("res://dungeon/rooms/combat/geleit_pfad_crypt.tscn")
const ENEMY_SCENE: PackedScene = preload("res://enemies/enemy_base.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
const ARCHER: EnemyData = preload("res://enemies/data/archer.tres")
const PLATEAU_GRAVE := Vector2i(7, 2)

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_spawn_height_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	HitStop.reset()


# --- The rule ---

func test_a_ranged_enemy_swaps_with_a_close_combat_enemy_on_the_plateau() -> void:
	var high: Array[bool] = [false, false, true]
	var open: Array[int] = [0, 1, 2]
	var sorted := SpawnSourceRules.sort_by_height([2, 0, 1] as Array[int], [false, true, false] as Array[bool], high, open, 3)
	assert_eq(sorted, [0, 2, 1] as Array[int], "the archer takes the plateau, the skeleton its ground source")


func test_ranged_enemies_move_up_while_the_plateau_has_room() -> void:
	var high: Array[bool] = [false, false, true]
	var open: Array[int] = [0, 1, 2]
	var all_ranged: Array[bool] = [true, true, true]
	var sorted := SpawnSourceRules.sort_by_height([0, 0, 1] as Array[int], all_ranged, high, open, 3)
	assert_eq(sorted, [2, 2, 1] as Array[int], "two up (PER_SOURCE), the third stays below")
	assert_eq(SpawnSourceRules.PER_SOURCE, 2)


func test_a_push_never_grows_beyond_its_sources() -> void:
	var high: Array[bool] = [false, false, true]
	var open: Array[int] = [0, 1, 2]
	var sorted := SpawnSourceRules.sort_by_height([0, 0, 1] as Array[int], [true, false, false] as Array[bool], high, open, 2)
	assert_eq(sorted, [0, 0, 1] as Array[int], "no third source for a push of two")
	var near: Array[int] = [0, 1]
	sorted = SpawnSourceRules.sort_by_height([0, 1] as Array[int], [true, false] as Array[bool], high, near, 3)
	assert_eq(sorted, [0, 1] as Array[int], "a plateau source close to a player stays shut")


func test_close_combat_enemies_come_out_below_and_rooms_without_height_stay_as_they_were() -> void:
	var high: Array[bool] = [false, false, true]
	var open: Array[int] = [0, 1, 2]
	var melee: Array[bool] = [false, false]
	assert_eq(SpawnSourceRules.sort_by_height([2, 0] as Array[int], melee, high, open, 3), [0, 0] as Array[int], "down to a ground source with room")
	assert_eq(SpawnSourceRules.sort_by_height([2, 2] as Array[int], melee, high, open, 3), [2, 2] as Array[int], "no ground source in the push: they walk down the stairs")
	var flat: Array[bool] = [false, false, false]
	assert_eq(SpawnSourceRules.sort_by_height([0, 1, 2] as Array[int], [true, false, true] as Array[bool], flat, open, 3), [0, 1, 2] as Array[int])


# --- In a room ---

func _room() -> RoomController:
	var room := PLAN_ROOM.instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 23
	room.setup(8, RoomSequence.RoomType.COMBAT, -1, false, context)
	var spawner := room.get_node("EnemySpawner") as EnemySpawner
	spawner.biomes = [] as Array[BiomeData]
	spawner.extra_types = [] as Array[EnemyData]
	spawner.enemy_types = [ARCHER] as Array[EnemyData]
	spawner.spawn_weights = [1.0] as Array[float]
	var group := EncounterGroup.new()
	group.allow_elites = false
	spawner.encounter_group = group
	add_child_autofree(room)
	return room


func _enemy(data: EnemyData) -> Enemy:
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	enemy.data = data
	autofree(enemy)
	return enemy


func test_the_plateau_grave_of_the_plan_is_a_high_source() -> void:
	var room := _room()
	var sources := SpawnSources.setup(room)
	sources.build()
	var high: Array[Vector2i] = []
	for source in sources.get_pool():
		if sources.is_high(source):
			high.append(RoomTiles.local_to_tile(source.spot))
	assert_eq(high, [PLATEAU_GRAVE] as Array[Vector2i], "one grave on the plateau")
	assert_eq(sources.get_pool().size(), 4)
	assert_eq(RoomPlanChecks.height_enemy_problems(room, room.tiles), [] as Array[String], "the plateau has stairs")


func test_archers_of_a_push_come_out_on_the_plateau() -> void:
	var room := _room()
	var sources := SpawnSources.setup(room)
	sources.build()
	var plateau: SpawnSource = null
	var ground: Array[SpawnSource] = []
	for source in sources.get_pool():
		if sources.is_high(source):
			plateau = source
		else:
			ground.append(source)
	assert_not_null(plateau)
	var chosen: Array[SpawnSource] = [plateau, ground[0], ground[1]]
	var enemies: Array[Enemy] = [_enemy(SKELETON), _enemy(ARCHER), _enemy(SKELETON)]
	sources.sort_by_height(enemies, chosen)
	assert_eq(chosen[1], plateau, "the archer up there")
	assert_false(sources.is_high(chosen[0]), "the skeleton below")
	assert_false(sources.is_high(chosen[2]))
	assert_true(sources.get_last_sources().has(plateau))


func test_a_wave_of_archers_uses_the_plateau_grave() -> void:
	var room := _room()
	var player: Player = add_child_autofree(PLAYER_SCENE.instantiate())
	# At the entrance (south-west), far from the plateau grave.
	player.global_position = room.to_global(RoomTiles.tile_center(room.tiles.get_entrance_inside_tile()))
	var sources := SpawnSources.setup(room)
	sources.build()
	await wait_physics_frames(2)
	var on_plateau := 0
	for push in 4:
		var enemies := sources.spawn_wave(room.spawner, 3, room.enemy_container, room.context)
		for enemy in enemies:
			if room.tiles.get_height_layout().surface.has(RoomTiles.local_to_tile(room.to_local(enemy.global_position))):
				on_plateau += 1
		for enemy in enemies:
			enemy.queue_free()
		await wait_physics_frames(1)
	assert_gt(on_plateau, 0, "archers come out on the plateau")

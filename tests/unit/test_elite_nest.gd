extends GutTest
## Elite nest (A10, KONZEPT_RAEUME §4.8, D-105): a combat variant only reachable through a branch.
## Few strong enemies (every one an elite, or one champion with an escort), cleared = bonus chest and
## double soul crystals. Attached without the variant table (A9's), through its own attach().

## CombatVariant and its subclasses load each other: the base goes first (see DungeonManager).
const COMBAT_VARIANT := preload("res://dungeon/variants/combat_variant.gd")
const NEST_PATH := "res://dungeon/variants/elite_nest_variant.gd"
const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_elite_nest_save.cfg"


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


func _room() -> RoomController:
	var room := HALL.instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 13
	room.setup(8, RoomSequence.RoomType.COMBAT, -1, false, context)
	var spawner := room.get_node("EnemySpawner") as EnemySpawner
	spawner.biomes = [] as Array[BiomeData]
	spawner.extra_types = [] as Array[EnemyData]
	spawner.enemy_types = [SKELETON] as Array[EnemyData]
	spawner.spawn_weights = [1.0] as Array[float]
	add_child_autofree(room)
	return room


## A nest with the given mode: seeds are tried until the variant RNG rolls it.
func _nest(room: RoomController, champion: bool) -> CombatVariant:
	var script := load(NEST_PATH) as GDScript
	for seed_value in 200:
		var probe := RandomNumberGenerator.new()
		probe.seed = seed_value
		if (probe.randf() < script.get_script_constant_map()["CHAMPION_CHANCE"]) == champion:
			return script.call(&"attach", room, seed_value) as CombatVariant
	return null


func _enemies(room: RoomController) -> Array[Enemy]:
	var enemies: Array[Enemy] = []
	for child in room.enemy_container.get_children():
		if child is Enemy:
			enemies.append(child)
	return enemies


func test_attach_marks_the_room_as_elite_nest() -> void:
	var room := _room()
	var nest := _nest(room, false)
	assert_not_null(nest)
	assert_eq(room.get_variant_id(), &"elite_nest")
	assert_eq(RoomGenre.of_room(room), &"elite_nest", "named on entry (D-110)")
	assert_eq(BranchOption.ELITE_NEST_ID, &"elite_nest")
	var script := load(NEST_PATH) as GDScript
	assert_null(script.call(&"attach", room, 1), "one variant per room")


func test_every_enemy_is_an_elite() -> void:
	var room := _room()
	_nest(room, false)
	room.activate()
	await wait_physics_frames(2)
	var enemies := _enemies(room)
	assert_between(enemies.size(), 2, 3, "two or three elites")
	for enemy in enemies:
		assert_ne(enemy.elite, Enemy.Elite.NONE, "%s is an elite" % enemy.name)
		assert_false(enemy.is_miniboss)


func test_champion_nest_has_one_champion_and_an_escort() -> void:
	var room := _room()
	var nest := _nest(room, true)
	assert_not_null(nest)
	room.activate()
	await wait_physics_frames(2)
	var enemies := _enemies(room)
	var champions := 0
	for enemy in enemies:
		if enemy.is_miniboss:
			champions += 1
	assert_eq(champions, 1)
	assert_between(enemies.size(), 2, 3, "champion plus one or two")


func test_cleared_nest_pays_crystals_and_a_bonus_chest() -> void:
	var room := _room()
	var nest := _nest(room, false)
	room.activate()
	await wait_physics_frames(2)
	var before := RunManager.get_run_crystals()
	for enemy in _enemies(room):
		enemy.health.take_damage(INF)
	await wait_physics_frames(4)
	assert_true(nest.is_finished())
	assert_true(nest.is_bonus_achieved())
	var crystals: int = (load(NEST_PATH) as GDScript).get_script_constant_map()["NEST_CRYSTALS"]
	assert_eq(RunManager.get_run_crystals(), before + crystals, "double crystals")
	assert_eq(nest.chests.size(), 1, "one bonus chest for the group")

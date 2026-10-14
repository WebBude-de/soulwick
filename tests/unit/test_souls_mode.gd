extends GutTest
## Minigame "Seelen sammeln" (R4a, KONZEPT_RAEUME_V2 §3.6): 12 souls one after another at fixed
## places, each for 6 s, 45 s for the round; every soul taken lets the sources spit enemies; soul
## crystals by count, then the rest of the enemies is beaten. Never costs the run.

const PLAN_ROOM: PackedScene = preload("res://dungeon/rooms/combat/seelen_katakombe_shadow_realm.tscn")
const PLAIN_ROOM: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_souls_save.cfg"


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


func _room(scene: PackedScene = PLAN_ROOM, room_index := 12) -> RoomController:
	var room := scene.instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 23
	room.setup(room_index, RoomSequence.RoomType.COMBAT, -1, false, context)
	var spawner := room.get_node("EnemySpawner") as EnemySpawner
	spawner.biomes = [] as Array[BiomeData]
	spawner.extra_types = [] as Array[EnemyData]
	spawner.enemy_types = [SKELETON] as Array[EnemyData]
	spawner.spawn_weights = [1.0] as Array[float]
	var group := EncounterGroup.new()
	group.allow_elites = false
	group.count_range = Vector2i(4, 4)
	spawner.encounter_group = group
	add_child_autofree(room)
	return room


func _attach(room: RoomController, seed_value := 9) -> SoulsMode:
	var mode := SoulsMode.attach(room, seed_value)
	assert_not_null(mode, "the souls fit the room")
	return mode


func _kill_all(room: RoomController) -> void:
	for child in room.enemy_container.get_children():
		var enemy := child as Enemy
		if enemy != null and not enemy.is_dead():
			enemy.health.take_damage(INF)


# --- Rules ---

func test_souls_numbers() -> void:
	assert_eq(SoulsRules.SOUL_COUNT, 12)
	assert_eq(SoulsRules.TIME_LIMIT, 45.0)
	assert_eq(SoulsRules.SOUL_LIFETIME, 6.0)
	assert_eq(SoulsRules.crystals_for(12), 3)
	assert_eq(SoulsRules.crystals_for(10), 2)
	assert_eq(SoulsRules.crystals_for(6), 1)
	assert_eq(SoulsRules.crystals_for(5), 0, "too few: no bonus")
	assert_lt(SoulsRules.SPAWN_INTERVAL * (SoulsRules.SOUL_COUNT - 1) + SoulsRules.FIRST_DELAY + SoulsRules.SOUL_LIFETIME, SoulsRules.TIME_LIMIT + 0.5, "the last soul still fits into the time")
	assert_true(SoulsRules.should_spawn(1.0, 0.5, 0))
	assert_false(SoulsRules.should_spawn(1.0, 0.5, 12), "twelve at most")
	assert_false(SoulsRules.should_spawn(45.0, 0.5, 3), "not after the time")
	assert_eq(SoulsRules.next_when_empty(10.0, 13.0), 10.0 + SoulsRules.EMPTY_GAP, "sooner when none is left")
	assert_true(SoulsRules.is_round_over(45.0, 3, 1))
	assert_true(SoulsRules.is_round_over(30.0, 12, 0))
	assert_false(SoulsRules.is_round_over(30.0, 12, 1))
	assert_eq(SoulsRules.MIN_ROOM, 11, "Zyklus 3")


func test_fill_spots_keeps_the_plan_and_spreads_the_rest() -> void:
	var plan: Array[Vector2i] = [Vector2i(1, 1), Vector2i(8, 1)]
	var candidates: Array[Vector2i] = []
	for y in 6:
		for x in 10:
			candidates.append(Vector2i(x, y))
	var spots := SoulsRules.fill_spots(plan, candidates, 6, [Vector2i(0, 5)] as Array[Vector2i])
	assert_eq(spots.size(), 6)
	assert_eq(spots[0], Vector2i(1, 1), "the plan's places first")
	assert_eq(spots[1], Vector2i(8, 1))
	for spot in spots:
		assert_eq(spots.count(spot), 1, "every place once")
		assert_gt(Vector2(spot - Vector2i(0, 5)).length(), SoulsRules.DOOR_CLEARANCE - 0.01, "away from the door")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var order := SoulsRules.shuffled_order(12, rng)
	assert_eq(order.size(), 12)
	for i in 12:
		assert_true(order.has(i), "a shuffle of every place")


# --- Room ---

func test_twelve_places_on_free_floor_with_the_plan_markers() -> void:
	var room := _room()
	var mode := _attach(room)
	assert_eq(mode.spots.size(), SoulsRules.SOUL_COUNT)
	var reachable := room.tiles.get_reachable_tiles(0)
	for spot in mode.spots:
		assert_true(reachable.has(spot), "reachable on foot %s" % spot)
		assert_eq(mode.spots.count(spot), 1)
	for marker in room.get_objectives_of(SoulsRules.SPOT_MARKER):
		assert_true(mode.spots.has(marker.get_meta(&"tile")), "plan place used")
	assert_not_null(SoulsMode.attach(_room(PLAIN_ROOM), 1), "any combat room works")


func test_intro_shows_the_first_souls() -> void:
	var room := _room()
	var mode := _attach(room)
	room.player_entered.emit(room)
	var goal := RoomObjective.of_room(room)
	assert_eq(goal.mode_id, RoomObjective.SOULS)
	assert_eq(goal.get_goal(), DungeonTexts.t(&"MODE_SOULS_GOAL", [12]))
	assert_eq(goal.time_left, SoulsRules.TIME_LIMIT)
	assert_false(goal.count_down, "the time waits for the intro")
	var intro := RoomIntro.get_intro(room)
	assert_eq(intro.focus, room.to_global(RoomTiles.tile_center(mode.spots[0])), "camera on the first soul")
	assert_true(mode.get_visible_wisps().is_empty(), "previews only, nothing to take yet")


func test_souls_come_one_after_another_and_fade() -> void:
	var room := _room()
	var mode := _attach(room)
	room.start_encounter()
	mode.step(0.5)
	assert_eq(mode.spawned, 1)
	assert_eq(mode.get_visible_wisps().size(), 1)
	mode.step(SoulsRules.SPAWN_INTERVAL)
	assert_eq(mode.spawned, 2, "the next after the interval")
	mode.step(SoulsRules.SOUL_LIFETIME - SoulsRules.SPAWN_INTERVAL + 0.2)
	assert_eq(mode.lost, 1, "the first faded untaken")
	assert_eq(RoomObjective.of_room(room).label_text, DungeonTexts.t(&"OBJECTIVE_SOULS", [0, 12]))


func test_taking_a_soul_lets_the_sources_spit_enemies() -> void:
	var room := _room()
	var mode := _attach(room)
	room.start_encounter()
	_kill_all(room)
	mode.step(0.5)
	var wisp := mode.get_visible_wisps()[0]
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	room.context.player = player
	player.global_position = wisp.global_position - Player.FEET_OFFSET
	var taken := [0]
	mode.soul_taken.connect(func(_m: SoulsMode, _w: SoulWisp, by: Player) -> void:
		assert_eq(by, player)
		taken[0] += 1)
	assert_eq(mode.get_living_enemies().size(), 0)
	mode.step(0.1)
	assert_eq(mode.collected, 1, "taken with the feet")
	assert_eq(taken[0], 1)
	assert_eq(mode.owed_enemies, 0, "the beat sends what the soul owes")
	assert_eq(mode.get_living_enemies().size(), SoulsRules.ENEMIES_PER_SOUL, "an enemy out of a source")
	assert_eq(RoomObjective.of_room(room).value, 1.0)


func test_round_end_gives_crystals_by_count_and_opens_the_room() -> void:
	var room := _room()
	var mode := _attach(room)
	room.start_encounter()
	_kill_all(room)
	await wait_process_frames(2)
	assert_ne(room.state, RoomController.State.CLEARED, "held while the round runs")
	# Take every soul as it comes.
	while not mode.is_round_over:
		for wisp in mode.get_visible_wisps():
			mode.take(wisp, null)
		mode.owed_enemies = 0
		mode.step(0.5)
	assert_eq(mode.collected, 12)
	assert_eq(mode.crystals, 3)
	assert_eq(mode.bonus, CombatVariant.Bonus.ACHIEVED)
	assert_not_null(mode.get_crystal_pickup(), "crystals by the exit")
	assert_eq(mode.get_crystal_pickup().amount, 3)
	assert_false(mode.holds_completion())
	_kill_all(room)
	await wait_process_frames(2)
	assert_eq(room.state, RoomController.State.CLEARED)


func test_too_few_souls_no_bonus_but_the_room_still_opens() -> void:
	var room := _room()
	var mode := _attach(room)
	room.start_encounter()
	mode.step(SoulsRules.TIME_LIMIT + 1.0)
	assert_true(mode.is_round_over)
	assert_eq(mode.crystals, 0)
	assert_eq(mode.bonus, CombatVariant.Bonus.LOST)
	assert_null(mode.get_crystal_pickup())
	_kill_all(room)
	await wait_process_frames(2)
	assert_eq(room.state, RoomController.State.CLEARED, "never costs the run")

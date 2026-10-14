extends GutTest
## Minigame "Geleit" (R4a, KONZEPT_RAEUME_V2 §3.3): a lost villager walks a visible path from his
## start to the exit; enemies go for him first, he stops while an enemy is closer than 3 tiles, walks
## 1.2 times faster with a player beside him, every enemy hit costs a heart. Arrived = bonus chest and
## a rescue in the save; fallen = no bonus, never the run.

const PLAN_ROOM: PackedScene = preload("res://dungeon/rooms/combat/geleit_pfad_slime_grotto.tscn")
const PLAIN_ROOM: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_escort_save.cfg"


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


func _room(scene: PackedScene = PLAN_ROOM, room_index := 8) -> RoomController:
	var room := scene.instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 41
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


func _attach(room: RoomController, seed_value := 5) -> EscortMode:
	var mode := EscortMode.attach(room, seed_value)
	assert_not_null(mode, "the escort fits the room")
	return mode


func _player(room: RoomController, local_feet: Vector2) -> Player:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	room.context.player = player
	player.global_position = room.to_global(local_feet) - Player.FEET_OFFSET
	return player


func _kill_all(room: RoomController) -> void:
	for child in room.enemy_container.get_children():
		var enemy := child as Enemy
		if enemy != null and not enemy.is_dead():
			enemy.health.take_damage(INF)


func _enemy_hit(room: RoomController) -> DamageData:
	var enemies := room.spawner.spawn_enemies(room.room_index, [Vector2(-500, -500)] as Array[Vector2], room.enemy_container, room.context, room.get_arena())
	var damage := DamageData.new()
	damage.amount = 5.0
	damage.source = enemies[0]
	damage.hit_id = DamageData.next_hit_id()
	return damage


# --- Rules ---

func test_escort_numbers() -> void:
	assert_eq(EscortRules.max_hearts(1), EscortRules.HEARTS)
	assert_eq(EscortRules.max_hearts(3), EscortRules.HEARTS + 2 * EscortRules.HEARTS_PER_EXTRA_PLAYER, "co-op: one more heart each")
	assert_almost_eq(EscortRules.walk_speed(true), EscortRules.walk_speed(false) * 1.2, 0.001, "1.2 times faster beside a player")
	assert_true(EscortRules.should_stop(191.0), "stops under 3 tiles")
	assert_false(EscortRules.should_stop(193.0))
	assert_true(EscortRules.is_chicken(0.049))
	assert_false(EscortRules.is_chicken(0.05), "5 % chickens")
	assert_eq(EscortRules.MIN_ROOM, 6, "Zyklus 2")


func test_path_goes_around_walls_and_water() -> void:
	var walkable: Dictionary[Vector2i, bool] = {}
	for y in 5:
		for x in 7:
			walkable[Vector2i(x, y)] = true
	# A wall in column 3 with a gap at the bottom, water in the middle of the right half.
	for y in 4:
		walkable.erase(Vector2i(3, y))
	var water: Dictionary[Vector2i, bool] = {Vector2i(5, 2): true, Vector2i(5, 3): true}
	var path := EscortRules.find_path(walkable, water, Vector2i(0, 0), Vector2i(6, 0))
	assert_eq(path[0], Vector2i(0, 0))
	assert_eq(path[path.size() - 1], Vector2i(6, 0))
	assert_true(path.has(Vector2i(3, 4)), "through the gap")
	for tile in path:
		assert_true(walkable.has(tile), "only walkable tiles")
		assert_false(water.has(tile), "around the water when there is room")
	for i in range(1, path.size()):
		var step := path[i] - path[i - 1]
		assert_true(absi(step.x) <= 1 and absi(step.y) <= 1, "one tile per step")
	assert_true(EscortRules.find_path(walkable, water, Vector2i(0, 0), Vector2i(9, 9)).is_empty(), "unreachable goal")
	var points := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	assert_eq(EscortRules.path_length(points), 20.0)
	assert_eq(EscortRules.point_at(points, 15.0), Vector2(10, 5))
	assert_eq(EscortRules.point_at(points, 99.0), Vector2(10, 10))


# --- Room ---

func test_villager_waits_at_the_plan_start_and_the_path_leads_to_the_exit() -> void:
	var room := _room()
	var mode := _attach(room)
	var start_markers := room.get_objectives_of(EscortRules.START_MARKER)
	assert_eq(start_markers.size(), 1)
	assert_eq(mode.path_tiles[0], start_markers[0].get_meta(&"tile"), "starts at the plan marker")
	assert_eq(mode.path_tiles[mode.path_tiles.size() - 1], room.tiles.get_exit_inside_tile(), "ends inside the exit")
	var water := room.tiles.get_water_tiles()
	for tile in mode.path_tiles:
		assert_true(room.tiles.is_walkable(tile), "walkable %s" % tile)
		assert_false(room.tiles.is_navigation_blocked(tile))
		assert_false(water.has(tile), "around the water %s" % tile)
	assert_eq(mode.villager.position + Player.FEET_OFFSET, RoomTiles.tile_center(mode.path_tiles[0]))
	assert_eq(mode.path_view.get_mark_count(), mode.path_tiles.size(), "one glowing mark per tile")
	assert_eq(RoomVariants.get_variant_id(room), EscortRules.ID)


func test_works_in_a_room_without_plan_marker() -> void:
	var room := _room(PLAIN_ROOM)
	var mode := _attach(room)
	assert_gt(mode.path_tiles.size(), 2)
	assert_eq(mode.path_tiles[mode.path_tiles.size() - 1], room.tiles.get_exit_inside_tile())


func test_entering_starts_goal_and_intro_on_him() -> void:
	var room := _room()
	var mode := _attach(room)
	room.player_entered.emit(room)
	var goal := RoomObjective.of_room(room)
	assert_not_null(goal)
	assert_eq(goal.mode_id, RoomObjective.ESCORT)
	assert_eq(goal.get_progress_text(), "0 %")
	var intro := RoomIntro.get_intro(room)
	assert_not_null(intro, "the intro holds the fight")
	assert_eq(intro.focus, mode.villager.global_position, "camera on the villager")
	assert_true(mode.path_view.is_revealed(), "the path lights up")
	assert_eq(mode.villager.get_bubble_text(), DungeonTexts.t(&"MODE_ESCORT_HELP"))


func test_walks_faster_beside_a_player_and_holds_the_room() -> void:
	var room := _room()
	var mode := _attach(room)
	room.start_encounter()
	_kill_all(room)
	await wait_process_frames(2)
	assert_ne(room.state, RoomController.State.CLEARED, "no enemy left, but he still walks")
	var before := mode.travelled
	mode.step(1.0)
	assert_almost_eq(mode.travelled - before, EscortRules.WALK_SPEED, 0.01)
	_player(room, mode.villager.position + Player.FEET_OFFSET + Vector2(40, 0))
	before = mode.travelled
	mode.step(1.0)
	assert_true(mode.is_player_beside())
	assert_almost_eq(mode.travelled - before, EscortRules.WALK_SPEED * 1.2, 0.01, "1.2 times faster")
	assert_eq(RoomObjective.of_room(room).status_text, DungeonTexts.t(&"OBJECTIVE_ESCORT_FAST"))
	assert_true(mode.holds_completion())


func test_stops_and_calls_for_help_while_an_enemy_is_near() -> void:
	var room := _room()
	var mode := _attach(room)
	room.start_encounter()
	_kill_all(room)
	var near := mode.villager.position + Vector2(120, 0)
	room.spawner.spawn_enemies(room.room_index, [near] as Array[Vector2], room.enemy_container, room.context, room.get_arena())
	mode.step(1.0)
	assert_eq(mode.walk_state, EscortMode.Walk.STOPPED)
	assert_eq(mode.travelled, 0.0, "he stands")
	assert_eq(mode.villager.get_bubble_text(), DungeonTexts.t(&"MODE_ESCORT_HELP"))
	assert_eq(RoomObjective.of_room(room).status_text, DungeonTexts.t(&"OBJECTIVE_ESCORT_STOPPED"))
	_kill_all(room)
	mode.step(1.0)
	assert_eq(mode.walk_state, EscortMode.Walk.WALKING, "on again once it is gone")
	assert_gt(mode.travelled, 0.0)


func test_enemies_go_for_him_first() -> void:
	var room := _room()
	var mode := _attach(room)
	room.start_encounter()
	var targeting := 0
	var enemies := mode.get_living_enemies()
	for enemy in enemies:
		assert_true(enemy.has_meta(&"escort_rolled"), "every enemy rolled once")
		if EnemyDecoy.get_decoy(enemy) == mode.villager:
			targeting += 1
	assert_gt(enemies.size(), 0)
	gut.p("%d of %d enemies go for the villager" % [targeting, enemies.size()])


func test_every_enemy_hit_costs_one_heart() -> void:
	var room := _room()
	var mode := _attach(room)
	room.start_encounter()
	var villager := mode.villager
	var hearts := villager.hearts
	var damage := _enemy_hit(room)
	var result := villager.hurtbox.receive_hit(damage)
	assert_false(result.blocked)
	assert_eq(villager.hearts, hearts - 1, "one heart, whatever the damage")
	assert_true(villager.hurtbox.receive_hit(_enemy_hit(room)).blocked, "briefly invulnerable")
	assert_eq(villager.hearts, hearts - 1)
	var trap := DamageData.new()
	trap.amount = 3.0
	assert_true(EscortHurtbox.accepts(damage))
	assert_false(EscortHurtbox.accepts(trap), "traps and players never hurt him")
	assert_eq(RoomObjective.of_room(room).label_text, DungeonTexts.t(&"OBJECTIVE_ESCORT_HEARTS", [hearts - 1, villager.max_hearts]))


func test_fallen_villager_costs_only_the_bonus() -> void:
	var room := _room()
	var mode := _attach(room)
	room.start_encounter()
	var lost_signals := [0]
	mode.villager_lost.connect(func(_m: EscortMode) -> void: lost_signals[0] += 1)
	while mode.villager.hearts > 0:
		mode.villager.take_hit(_enemy_hit(room))
		mode.villager._invulnerable_left = 0.0
	assert_eq(mode.walk_state, EscortMode.Walk.DOWN)
	assert_eq(lost_signals[0], 1)
	assert_eq(mode.bonus, CombatVariant.Bonus.LOST)
	assert_true(RoomObjective.of_room(room) == null or not RoomObjective.of_room(room).success)
	assert_false(mode.holds_completion(), "the room is cleared as usual")
	assert_false(mode.villager.is_alive(), "no target any more")
	_kill_all(room)
	assert_eq(room.state, RoomController.State.CLEARED)
	assert_true(mode.chests.is_empty(), "no bonus chest")


func test_arrival_rescues_him_and_gives_the_bonus() -> void:
	var room := _room()
	var mode := _attach(room)
	room.start_encounter()
	var before := RescueRecord.get_rescued(mode.is_chicken)
	var goal := RoomObjective.of_room(room)
	# Enemies still in their sources do not stop him; the walk is fast-forwarded.
	mode.step(mode.path_total / EscortRules.WALK_SPEED + 1.0)
	assert_eq(mode.walk_state, EscortMode.Walk.ARRIVED)
	assert_eq(mode.bonus, CombatVariant.Bonus.ACHIEVED)
	assert_true(goal.is_finished() and goal.success)
	assert_eq(RescueRecord.get_rescued(mode.is_chicken), before + 1, "noted in the save")
	assert_eq(mode.chests.size(), 1, "bonus chest at the exit")
	assert_false(mode.villager.is_alive(), "safe: no target any more")
	await wait_process_frames(2)
	assert_eq(room.state, RoomController.State.CLEARED, "the rest fled from his light")


func test_chicken_placeholder_has_a_lantern() -> void:
	var chicken := LostVillager.new()
	chicken.build(true, 3)
	add_child_autofree(chicken)
	assert_true(chicken.chicken)
	assert_eq(chicken.hearts, 3)
	assert_not_null(chicken.get_light(), "lantern light")
	assert_not_null(chicken.get_node_or_null(^"Sprite/LanternGlyph"), "drawn lantern until the art exists")
	assert_eq(chicken.get_light().color, LightPalette.WARM)

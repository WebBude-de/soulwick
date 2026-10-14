extends GutTest
## Wager altar (KONZEPT_RAEUME §5, D-104, D-109): one condition per altar (trial or curse), accepted
## with E only while the door is open, broken by a hit / the time / the first weapon, curses make
## the room harder (light circle, faster enemies, no healing) and end with the room; success pays
## soul crystals, failure costs nothing more.

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_wager_altar_save.cfg"


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


func _room(count := 2) -> RoomController:
	var room := HALL.instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 17
	room.setup(9, RoomSequence.RoomType.COMBAT, -1, false, context)
	var spawner := room.get_node("EnemySpawner") as EnemySpawner
	spawner.biomes = [] as Array[BiomeData]
	spawner.extra_types = [] as Array[EnemyData]
	spawner.enemy_types = [SKELETON] as Array[EnemyData]
	spawner.spawn_weights = [1.0] as Array[float]
	var group := EncounterGroup.new()
	group.allow_elites = false
	group.count_range = Vector2i(count, count)
	spawner.encounter_group = group
	add_child_autofree(room)
	return room


func _player(room: RoomController) -> Player:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	room.context.player = player
	player.global_position = room.to_global(RoomTiles.tile_center(room.tiles.get_entrance_inside_tile())) - Player.FEET_OFFSET
	return player


## An altar with a fixed condition (the roll picks it from the available ones).
func _altar(room: RoomController, condition: WagerRules.Condition) -> WagerAltar:
	var available := WagerRules.get_available(WagerAltar.has_second_weapon(room.context))
	var index := available.find(condition)
	assert_gte(index, 0, "condition available")
	var roll := (float(index) + 0.5) / available.size()
	var altar := WagerAltar.attach_to(room, roll)
	assert_not_null(altar)
	assert_eq(altar.condition, condition)
	return altar


func _kill_all(room: RoomController) -> void:
	for child in room.enemy_container.get_children():
		var enemy := child as Enemy
		if enemy != null and not enemy.is_dead():
			enemy.health.take_damage(INF)


func _hit(amount := 1.0) -> DamageData:
	var hit := DamageData.new()
	hit.amount = amount
	hit.hit_id = DamageData.next_hit_id()
	return hit


# --- Rules ---

func test_conditions_rewards_and_breaks() -> void:
	assert_false(WagerRules.get_available(false).has(WagerRules.Condition.SECONDARY_ONLY), "needs a second weapon")
	assert_eq(WagerRules.get_available(true).size(), 6, "three trials, three curses (KONZEPT §5)")
	assert_eq(WagerRules.pick(0.0, false), WagerRules.Condition.NO_HIT)
	assert_eq(WagerRules.pick(0.999, false), WagerRules.Condition.CURSE_NO_HEAL)
	for condition in WagerRules.Condition.values():
		assert_between(WagerRules.get_reward(condition), 1, 2, "D-109: 1-2 crystals")
		assert_false(WagerRules.get_condition_name(condition).is_empty())
		assert_false(WagerRules.get_condition_rule(condition).is_empty())
	assert_true(WagerRules.is_curse(WagerRules.Condition.CURSE_HASTE))
	assert_false(WagerRules.is_curse(WagerRules.Condition.NO_HIT))
	assert_true(WagerRules.breaks_on_hit(WagerRules.Condition.NO_HIT))
	assert_false(WagerRules.breaks_on_hit(WagerRules.Condition.UNDER_TIME))
	assert_true(WagerRules.breaks_on_attack(WagerRules.Condition.SECONDARY_ONLY, 0))
	assert_false(WagerRules.breaks_on_attack(WagerRules.Condition.SECONDARY_ONLY, 1))
	assert_false(WagerRules.breaks_on_time(WagerRules.Condition.UNDER_TIME, 30.0))
	assert_true(WagerRules.breaks_on_time(WagerRules.Condition.UNDER_TIME, 30.1), "30 s")
	assert_eq(WagerRules.get_condition_rule(WagerRules.Condition.CURSE_GLOOM), "Lichtkreis −40 % in diesem Raum")
	assert_eq(WagerRules.get_condition_rule(WagerRules.Condition.CURSE_HASTE), "Gegner +15 % Tempo in diesem Raum")


# --- Altar in the room ---

func test_altar_stands_beside_the_entrance_and_reads_back() -> void:
	var room := _room()
	assert_false(RoomVariants.has_wager_altar(room))
	var pick := VariantTable.Pick.new()
	pick.wager = true
	var rng := RandomNumberGenerator.new()
	assert_eq(RoomVariants.attach(room, pick, rng), &"", "a wager altar is no variant")
	assert_true(RoomVariants.has_wager_altar(room), "UX2 reads it")
	var altar := WagerAltar.of(room)
	var tile := RoomTiles.local_to_tile(altar.position + Player.FEET_OFFSET)
	var entrance := room.tiles.get_entrance_inside_tile()
	assert_eq(tile.y, entrance.y, "in the entrance row, outside the enter trigger")
	assert_lte(absi(tile.x - entrance.x), 2, "right beside the entrance")
	assert_true(room.tiles.is_navigation_blocked(tile))
	assert_ne(tile, entrance, "the way in stays free")


func test_accept_only_while_the_door_is_open() -> void:
	var room := _room()
	var player := _player(room)
	var altar := _altar(room, WagerRules.Condition.NO_HIT)
	assert_true(altar.can_accept())
	assert_true(altar.accept(player))
	assert_false(altar.accept(player), "once")
	var late_room := _room()
	var late := _altar(late_room, WagerRules.Condition.NO_HIT)
	late_room.player_entered.emit(late_room)
	late_room.activate()
	assert_false(late.accept(player), "door shut: too late")
	assert_eq(late.state, WagerAltar.State.DECLINED)


func test_no_hit_breaks_on_a_hit_and_costs_nothing_more() -> void:
	var room := _room()
	var player := _player(room)
	var altar := _altar(room, WagerRules.Condition.NO_HIT)
	altar.accept(player)
	room.activate()
	var health := player.health.get_health()
	player.hurtbox.receive_hit(_hit())
	assert_eq(altar.state, WagerAltar.State.LOST)
	assert_eq(player.health.get_health(), health - 1.0, "only the hit itself")
	var crystals := RunManager.get_run_crystals()
	_kill_all(room)
	await wait_physics_frames(2)
	assert_eq(RunManager.get_run_crystals(), crystals, "no reward")


func test_won_wager_pays_crystals() -> void:
	var room := _room()
	var player := _player(room)
	var altar := _altar(room, WagerRules.Condition.NO_HIT)
	altar.accept(player)
	room.activate()
	var crystals := RunManager.get_run_crystals()
	_kill_all(room)
	await wait_physics_frames(2)
	assert_eq(altar.state, WagerAltar.State.WON)
	assert_eq(RunManager.get_run_crystals(), crystals + WagerRules.get_payout(WagerRules.Condition.NO_HIT, 1), "D-109 crystals")


func test_under_time_counts_from_the_closing_door() -> void:
	var room := _room()
	var player := _player(room)
	var altar := _altar(room, WagerRules.Condition.UNDER_TIME)
	altar.accept(player)
	altar.step(100.0)
	assert_eq(altar.state, WagerAltar.State.ACCEPTED, "the clock starts with the fight")
	room.activate()
	altar.step(WagerRules.TIME_LIMIT - 1.0)
	assert_eq(altar.state, WagerAltar.State.ACCEPTED)
	altar.step(2.0)
	assert_eq(altar.state, WagerAltar.State.LOST, "too slow")


func test_secondary_only_breaks_with_the_first_weapon() -> void:
	var room := _room()
	var player := _player(room)
	player.weapon_controller.equip_weapon(load("res://weapons/data/dagger.tres") as WeaponData, 1)
	assert_true(WagerAltar.has_second_weapon(room.context))
	var altar := _altar(room, WagerRules.Condition.SECONDARY_ONLY)
	altar.accept(player)
	room.activate()
	altar.register_attack(1)
	assert_eq(altar.state, WagerAltar.State.ACCEPTED, "second weapon is fine")
	altar.register_attack(0)
	assert_eq(altar.state, WagerAltar.State.LOST)


func test_curse_haste_makes_the_room_enemies_faster() -> void:
	var room := _room(3)
	var player := _player(room)
	var altar := _altar(room, WagerRules.Condition.CURSE_HASTE)
	altar.accept(player)
	room.activate()
	for child in room.enemy_container.get_children():
		var enemy := child as Enemy
		assert_almost_eq(enemy.data.move_speed, SKELETON.move_speed * WagerRules.HASTE_SPEED_FACTOR, 0.01, "+15 %")
	assert_eq(SKELETON.move_speed, 120.0, "the shared data stays untouched")


func test_curse_no_heal_blocks_healing_in_this_room_only() -> void:
	var room := _room()
	var player := _player(room)
	var altar := _altar(room, WagerRules.Condition.CURSE_NO_HEAL)
	altar.accept(player)
	room.activate()
	player.health.take_damage(2.0)
	var hurt := player.health.get_health()
	player.health.heal(1.0)
	assert_eq(player.health.get_health(), hurt, "no healing in this room")
	_kill_all(room)
	await wait_physics_frames(2)
	assert_eq(altar.state, WagerAltar.State.WON, "a curse is met by clearing the room")
	player.health.heal(1.0)
	assert_eq(player.health.get_health(), hurt + 1.0, "healing works again")


func test_declined_altar_changes_nothing() -> void:
	var room := _room(3)
	_player(room)
	var altar := _altar(room, WagerRules.Condition.CURSE_HASTE)
	room.player_entered.emit(room)
	room.activate()
	assert_eq(altar.state, WagerAltar.State.DECLINED)
	for child in room.enemy_container.get_children():
		assert_eq((child as Enemy).data, SKELETON, "no curse without accepting")

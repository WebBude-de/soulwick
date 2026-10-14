extends GutTest
## Room modes in the rooms made for them (R4b, R1 plans in dungeon/rooms/plans/modes/, design answer
## 01_raumarten.md): every mode uses its plan's markers (flame on its podium, relic and altar, wall
## rifts, the crowned one and his hole, cold torch stands and guardians), guards wait still until the
## fight, the first-wave hook gives the guards (and the crowned one) instead of a wave out of the
## sources; then the relic (carry, drop on a hit, altar, graves wake, home after 40 s) and Lichtfeuer
## (dark room, fires light it up and hold the guardians, bonus for fires and guardians).

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
const PLANS := {
	&"flame": "res://dungeon/rooms/combat/flamme_schrein_crypt.tscn",
	&"relic": "res://dungeon/rooms/combat/reliquie_kammer_crypt.tscn",
	&"rifts": "res://dungeon/rooms/combat/risse_schlucht_ember_forge.tscn",
	&"hunt": "res://dungeon/rooms/combat/jagd_saeulenhalle_crypt.tscn",
	&"lightfire": "res://dungeon/rooms/combat/lichtfeuer_halle_shadow_realm.tscn",
}

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_mode_plans_save.cfg"


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


## The plan room of a mode with skeletons only (no elites), room 20 (grotto: no crypt trait).
func _room(mode: StringName, room_index := 20, count := 4) -> RoomController:
	var room := (load(PLANS[mode]) as PackedScene).instantiate() as RoomController
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
	group.count_range = Vector2i(count, count)
	spawner.encounter_group = group
	add_child_autofree(room)
	return room


func _attach(room: RoomController, id: StringName) -> RoomMode:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	assert_eq(RoomVariants.attach(room, VariantTable.pick_for(id), rng), id, "%s attached" % id)
	return CombatVariant.of(room) as RoomMode


func _player(room: RoomController, tile: Vector2i) -> Player:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	room.context.player = player
	player.global_position = room.to_global(RoomTiles.tile_center(tile)) - Player.FEET_OFFSET
	return player


func _living(room: RoomController) -> Array[Enemy]:
	var living: Array[Enemy] = []
	for child in room.enemy_container.get_children():
		var enemy := child as Enemy
		if enemy != null and not enemy.is_dead() and not enemy.is_queued_for_deletion():
			living.append(enemy)
	return living


func _kill_all(room: RoomController) -> void:
	for enemy in _living(room):
		enemy.health.take_damage(INF)


func _hit(source: Node, amount := 1.0) -> DamageData:
	var hit := DamageData.new()
	hit.amount = amount
	hit.source = source
	hit.hit_id = DamageData.next_hit_id()
	return hit


func _marker_tile(room: RoomController, kind: StringName) -> Vector2i:
	var markers := room.get_objectives_of(kind)
	return markers[0].get_meta(&"tile") if not markers.is_empty() else Vector2i(-1, -1)


# --- Plan markers ---

func test_every_mode_uses_the_markers_of_its_plan() -> void:
	var flame_room := _room(&"flame")
	var flame := _attach(flame_room, &"flame") as FlameMode
	assert_eq(RoomTiles.local_to_tile(flame.flame.position), _marker_tile(flame_room, &"soul_flame"), "flame on its podium")
	var relic_room := _room(&"relic")
	var relic := _attach(relic_room, &"relic") as RelicMode
	assert_eq(relic.relics.size(), 1)
	assert_eq(RoomTiles.local_to_tile(relic.relics[0].position), _marker_tile(relic_room, &"relic"), "relic at the far end")
	assert_eq(RoomTiles.local_to_tile(relic.altar.position), _marker_tile(relic_room, &"relic_altar"), "altar beside the entrance")
	var rift_room := _room(&"rifts")
	var rifts := _attach(rift_room, &"rifts") as RiftsMode
	assert_eq(rifts.get_wall_rift_tiles().size(), rift_room.get_sources_of(&"rift_wall").size(), "one rift per wall rift")
	assert_gte(rifts.get_wall_rift_tiles().size(), 2)
	var hunt_room := _room(&"hunt")
	var hunt := _attach(hunt_room, &"hunt") as HuntMode
	assert_eq(RoomTiles.local_to_tile(hunt.crowned.position), _marker_tile(hunt_room, &"crowned"))
	assert_not_null(hunt.get_hole(), "the hole is there from the start")
	assert_eq(RoomTiles.local_to_tile(hunt.get_hole().position - Vector2(0, 8)), _marker_tile(hunt_room, &"escape_hole"))
	var light_room := _room(&"lightfire")
	var light := _attach(light_room, &"lightfire") as LightfireMode
	assert_eq(light.torches.size(), light_room.get_objectives_of(&"torch_stand_unlit").size(), "cold stands of the plan")
	assert_eq(light.get_lit_count(), light_room.get_objectives_of(&"torch_stand").size(), "the burning stand of the plan")
	assert_eq(light.stone_guardians.size(), light_room.get_objectives_of(&"stone_guardian").size())


func test_guards_wait_still_and_the_first_wave_hook_gives_them() -> void:
	var room := _room(&"hunt")
	var hunt := _attach(room, &"hunt") as HuntMode
	assert_true(hunt.uses_own_first_wave())
	assert_eq(hunt.guards.size(), maxi(HuntRules.MIN_GUARDS, room.get_objectives_of(&"guard").size()))
	for guard in hunt.guards:
		assert_true(guard.is_in_intro(), "still and invulnerable before the fight")
		assert_true(guard.hurtbox.is_invulnerable())
	var wave := RoomVariants.spawn_first_wave(room)
	assert_eq(wave.size(), hunt.guards.size() + 1, "guards and the crowned one, no wave out of the sources")
	assert_true(wave.has(hunt.crowned))
	for enemy in wave:
		assert_false(enemy.is_in_intro(), "they fight")
	assert_true(RoomVariants.spawn_first_wave(room).is_empty(), "once")
	var flame_room := _room(&"flame")
	_attach(flame_room, &"flame")
	assert_true(RoomVariants.spawn_first_wave(flame_room).is_empty(), "the flame room spawns as usual")


func test_without_the_hook_guards_join_the_rooms_wave() -> void:
	var room := _room(&"relic")
	var relic := _attach(room, &"relic") as RelicMode
	room.activate()
	for guard in relic.guards:
		assert_false(guard.is_in_intro())
	assert_eq(room.get_alive_enemy_count(), _living(room).size(), "guards are counted by the room")


func test_intro_shows_the_goal_of_each_mode() -> void:
	for id: StringName in PLANS:
		var room := _room(id)
		var mode := _attach(room, id)
		room.player_entered.emit(room)
		var goal := RoomObjective.of_room(room)
		assert_not_null(goal, "%s: task bar" % id)
		assert_eq(goal.mode_id, id)
		var intro := RoomIntro.get_intro(room)
		assert_not_null(intro, "%s: intro" % id)
		assert_true(intro.focus.is_finite(), "%s: the camera has a goal to show" % id)
		assert_lt(room.to_local(intro.focus).distance_to(Vector2(room.tiles.room_size) * RoomTiles.TILE_WORLD * 0.5), 1200.0)
		intro.skip()
		assert_not_null(mode)
		room.queue_free()
		await wait_process_frames(1)


# --- Rifts in their plan ---

func test_plan_rifts_send_their_enemies_through_the_wall() -> void:
	var room := _room(&"rifts", 20, 1)
	var rifts := _attach(room, &"rifts") as RiftsMode
	room.activate()
	var open := rifts.get_open_rifts()
	assert_eq(open.size(), rifts.get_wall_rift_tiles().size())
	var rift := open[0]
	var source := rifts.get_source_of(rift)
	assert_not_null(source, "the rift sits in a wall source")
	assert_eq(source.kind, SpawnSourceRules.Kind.RIFT_WALL)
	var uses := source.uses
	var before := room.get_alive_enemy_count()
	var pushed := rifts.push_from(rift)
	assert_eq(pushed.size(), 1)
	assert_eq(room.get_alive_enemy_count(), before + 1, "tracked by the room")
	assert_true(pushed[0].is_emerging(), "comes out of the wall (warning first)")
	assert_true(source.uses > uses or source.is_active(), "through its source")
	rift.health.take_damage(INF)
	assert_true(source.quiet, "a closed rift goes quiet")


# --- Relic ---

func test_carrier_is_slow_cannot_attack_and_the_graves_wake() -> void:
	var room := _room(&"relic")
	var relic_mode := _attach(room, &"relic") as RelicMode
	var player := _player(room, _marker_tile(room, &"relic") + Vector2i(0, 1))
	room.activate()
	var relic := relic_mode.relics[0]
	var before := room.get_alive_enemy_count()
	assert_true(relic.pick_up(player))
	assert_true(LanternCarry.is_carrying(player))
	assert_false(LanternCarry.can_attack(player), "no attacks while carrying")
	assert_true(relic_mode.is_woken(), "lifting it wakes the graves")
	assert_gt(room.get_alive_enemy_count(), before, "the wake counts for the room")
	assert_ne(relic_mode.get_objective().status_text, "", "the bar names the carrier")
	var chasers := relic_mode.get_chasers()
	assert_gte(chasers.size(), room.get_alive_enemy_count() - before, "everyone out of the graves hunts the carrier")
	for chaser in chasers:
		assert_eq(EnemyDecoy.get_decoy(chaser), player, "chasers go for the carrier")
	relic.drop(player.get_feet_position())
	assert_false(LanternCarry.is_carrying(player))


func test_a_hit_drops_the_relic() -> void:
	var room := _room(&"relic")
	var relic_mode := _attach(room, &"relic") as RelicMode
	var player := _player(room, _marker_tile(room, &"relic") + Vector2i(0, 1))
	room.activate()
	var relic := relic_mode.relics[0]
	relic.pick_up(player)
	var enemy := _living(room)[0]
	player.hurtbox.receive_hit(_hit(enemy, 0.5))
	await wait_process_frames(2)
	assert_false(relic.is_carried(), "Bei Treffer fällt sie hin")
	assert_false(LanternCarry.is_carrying(player), "hands free again")
	assert_true(relic.pick_up(player), "and can be lifted again")


func test_relic_on_the_altar_in_time_is_the_bonus_and_opens_the_room() -> void:
	var room := _room(&"relic")
	var relic_mode := _attach(room, &"relic") as RelicMode
	var player := _player(room, _marker_tile(room, &"relic") + Vector2i(0, 1))
	room.activate()
	_kill_all(room)
	await wait_physics_frames(2)
	assert_eq(room.state, RoomController.State.ACTIVE, "held until the relic lies on the altar")
	var relic := relic_mode.relics[0]
	relic.pick_up(player)
	_kill_all(room)
	relic.drop(relic_mode.altar.global_position + Vector2(10, 0))
	assert_true(relic.is_placed(), "put down at the altar = laid on")
	assert_eq(relic_mode.get_placed_count(), 1)
	assert_true(relic_mode.get_objective().success)
	await wait_physics_frames(2)
	_kill_all(room)
	await wait_physics_frames(2)
	assert_eq(room.state, RoomController.State.CLEARED)
	assert_eq(relic_mode.chests.size(), 1, "bonus chest at the altar")


func test_late_relic_flies_home_without_bonus() -> void:
	var room := _room(&"relic")
	var relic_mode := _attach(room, &"relic") as RelicMode
	room.activate()
	relic_mode.step(RelicRules.BONUS_TIME + 0.1)
	assert_true(relic_mode.relics[0].is_placed(), "home by itself")
	assert_eq(relic_mode.bonus, CombatVariant.Bonus.LOST)
	_kill_all(room)
	await wait_physics_frames(2)
	_kill_all(room)
	await wait_physics_frames(2)
	assert_eq(room.state, RoomController.State.CLEARED, "the room can always be finished")
	assert_eq(relic_mode.chests.size(), 0)


func test_two_relics_from_cycle_six() -> void:
	var room := _room(&"relic", RelicRules.DOUBLE_FROM_ROOM)
	var relic_mode := _attach(room, &"relic") as RelicMode
	assert_eq(relic_mode.relics.size(), 2)
	assert_ne(relic_mode.relics[0].position, relic_mode.relics[1].position)


# --- Lichtfeuer ---

func test_lightfire_lights_hold_the_guardians_and_give_the_bonus() -> void:
	var room := _room(&"lightfire")
	var light := _attach(room, &"lightfire") as LightfireMode
	var player := _player(room, room.tiles.get_entrance_inside_tile() + Vector2i(0, -1))
	room.activate()
	for guardian in light.get_living_guardians():
		assert_true(guardian.active, "awake with the fight")
		assert_eq(guardian.player_light_counts, LightfireRules.PLAYER_LIGHT_HOLDS_GUARDIANS)
	for torch in light.torches:
		torch.ignite(player)
	assert_eq(light.get_lit_count(), light.get_fire_count())
	assert_false(light.is_bonus_achieved(), "the guardians still stand")
	for guardian in light.get_living_guardians():
		guardian.health.take_damage(INF)
	assert_true(light.is_bonus_achieved(), "every fire and every guardian")
	assert_true(light.get_objective().success)
	_kill_all(room)
	await wait_physics_frames(2)
	assert_eq(room.state, RoomController.State.CLEARED)
	assert_eq(light.chests.size(), 1)


func test_lightfire_without_every_fire_has_no_bonus() -> void:
	var room := _room(&"lightfire")
	var light := _attach(room, &"lightfire") as LightfireMode
	room.activate()
	_kill_all(room)
	await wait_physics_frames(2)
	assert_eq(room.state, RoomController.State.CLEARED, "the room is done as usual")
	assert_eq(light.bonus, CombatVariant.Bonus.LOST)
	assert_eq(light.chests.size(), 0)

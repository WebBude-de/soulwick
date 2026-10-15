extends GutTest
## Room modes in a plain combat room without plan markers (R4b, KONZEPT_RAEUME_V2 §3; the hall is the
## fallback when no plan of a mode fits): attaching through RoomVariants (one RNG number, never two),
## the shared RoomMode interface (goal and intro on entry, start with the fight, end with the room),
## every mode finds its own spots, the flame (pushes, raid time, flame out, light), the rifts (count
## for the room, own summons), the hunt (crown, zigzag, escape or loot) and the crypt's gravedigger
## trait (heaps, rising once, gold on the final death).

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
const R4B_MODES: Array[StringName] = [&"flame", &"relic", &"rifts", &"hunt", &"lightfire"]

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_mode_rooms_save.cfg"


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


## A normal combat room with skeletons only (no elites), fixed seed, not yet entered. Room 20 lies in
## the grotto: no gravedigger trait unless a test asks for the crypt.
func _room(room_index := 20, count := 4) -> RoomController:
	var room := HALL.instantiate() as RoomController
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


func _attach(room: RoomController, id: StringName, seed_value := 5) -> RoomMode:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	assert_eq(RoomVariants.attach(room, VariantTable.pick_for(id), rng), id, "%s attached" % id)
	return CombatVariant.of(room) as RoomMode


func _player(room: RoomController, tile := Vector2i(7, 7)) -> Player:
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


func _kill_all(room: RoomController, except: Array = []) -> void:
	for enemy in _living(room):
		var spared := false
		for kept: Variant in except:
			spared = spared or is_same(kept, enemy)
		if not spared:
			enemy.health.take_damage(INF)


func _enemy_hit(source: Node, amount := 1.0) -> DamageData:
	var hit := DamageData.new()
	hit.amount = amount
	hit.source = source
	hit.hit_id = DamageData.next_hit_id()
	return hit


# --- Interface ---

func test_every_mode_fits_the_plain_hall() -> void:
	for id in R4B_MODES:
		var room := _room()
		var mode := _attach(room, id)
		assert_not_null(mode, "%s finds its own spots without a plan" % id)
		assert_eq(RoomVariants.get_variant_id(room), id)
		assert_eq(room.get_variant_id(), id, "RoomGenre and LightingProfile read the id")
		room.queue_free()
		await wait_process_frames(1)


func test_attach_reads_back_and_never_twice() -> void:
	var room := _room()
	assert_eq(RoomVariants.get_variant_id(room), &"")
	_attach(room, &"hunt")
	assert_false(RoomVariants.has_wager_altar(room))
	assert_eq(RoomVariants.attach(room, VariantTable.pick_for(&"rifts"), RandomNumberGenerator.new()), &"", "one mode per room")
	assert_eq(RoomVariants.get_variant_id(room), &"hunt")


func test_attach_uses_one_number_and_nothing_for_an_empty_pick() -> void:
	var room := _room()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var reference := RandomNumberGenerator.new()
	reference.seed = 9
	assert_eq(RoomVariants.attach(room, VariantTable.Pick.new(), rng), &"")
	assert_eq(rng.state, reference.state, "nothing drawn for an empty pick")
	RoomVariants.attach(room, VariantTable.pick_for(&"flame"), rng)
	reference.randi()
	assert_eq(rng.state, reference.state, "exactly one number for a mode")


func test_goal_and_intro_start_on_entry_and_the_mode_runs_with_the_fight() -> void:
	var room := _room()
	var mode := _attach(room, &"flame")
	watch_signals(mode)
	assert_null(RoomObjective.of_room(room), "no task bar for a room ahead")
	room.player_entered.emit(room)
	var goal := RoomObjective.of_room(room)
	assert_not_null(goal, "the goal comes with the entry")
	assert_eq(goal.mode_id, &"flame")
	assert_eq(goal.get_goal(), DungeonTexts.t(&"MODE_FLAME_GOAL", [40]), "Halte die Flamme 40 s")
	assert_not_null(RoomIntro.get_intro(room), "intro: door, camera on the flame, banner, 3-2-1")
	assert_true(RoomIntro.holds_encounter(room))
	RoomIntro.get_intro(room).skip()
	room.activate()
	assert_true(mode.is_started(), "start on encounter_started")
	assert_signal_emitted(mode, "started")
	mode.step(FlameRules.DURATION + 0.1)
	assert_true(goal.is_finished() and goal.success, "flame held: the task bar says so")
	_kill_all(room)
	await wait_physics_frames(2)
	assert_true(mode.is_finished(), "finish on completed")


func test_plan_mode_for_falls_back_when_no_plan_fits() -> void:
	var catalog := RoomCatalog.create()
	assert_eq(RoomVariants.plan_mode_for(&"flame", catalog, RoomSequence.RoomKind.NORMAL, 8, -1), &"flame", "flame plans exist")
	assert_eq(RoomVariants.plan_mode_for(&"beacon", catalog, RoomSequence.RoomKind.NORMAL, 20, RoomTiles.DoorSide.WEST), &"beacon", "entered from the west")
	assert_eq(RoomVariants.plan_mode_for(&"nonsense", catalog, RoomSequence.RoomKind.NORMAL, 8, -1), &"", "no plan: any combat plan")
	assert_eq(RoomVariants.plan_mode_for(&"", catalog, RoomSequence.RoomKind.NORMAL, 8, -1), &"")
	var rng := RandomNumberGenerator.new()
	for id in R4B_MODES:
		var plan := ModeRegistry.get_plan_mode(id)
		var entry := catalog.pick_template(RoomSequence.RoomKind.NORMAL, RoomSequence.SOLO_ROOM_SIZES, rng, &"", 20, -1, plan)
		assert_eq(entry.mode, plan, "%s draws its own plan" % id)


# --- Flame ---

func test_flame_burns_in_the_middle_and_takes_only_enemy_damage() -> void:
	var room := _room()
	var mode := _attach(room, &"flame") as FlameMode
	var flame := mode.flame
	assert_true(flame.is_alive())
	assert_lt(flame.position.distance_to(room.content_anchor.position), RoomTiles.TILE_WORLD * 2.5, "near the centre")
	assert_eq(flame.hurtbox.collision_layer, PhysicsLayers.PLAYER_HURTBOX, "enemy attacks see it")
	var full := flame.health.get_health()
	assert_true(flame.hurtbox.receive_hit(_enemy_hit(null)).blocked, "traps and hazards pass through")
	room.activate()
	var enemy := _living(room)[0]
	var light_before := (flame.get_node("Light") as LightSource).radius
	flame.hurtbox.receive_hit(_enemy_hit(enemy, 4.0))
	assert_eq(flame.health.get_health(), full - 4.0, "an enemy hit counts")
	assert_lt((flame.get_node("Light") as LightSource).radius, light_before, "the light shrinks with the health")


func test_raid_holds_the_room_and_pushes_out_of_the_sources() -> void:
	var room := _room()
	var mode := _attach(room, &"flame") as FlameMode
	assert_false(RoomVariants.holds_completion(room), "not before the fight")
	room.activate()
	assert_true(RoomVariants.holds_completion(room), "held during the raid (RoomController hook)")
	var before := room.get_alive_enemy_count()
	mode.step(FlameRules.PUSH_INTERVAL)
	assert_eq(mode.get_pushes_sent(), 1, "a push after the interval")
	assert_gt(room.get_alive_enemy_count(), before, "push enemies count for the room")
	var sources := SpawnSources.of(room)
	assert_not_null(sources)
	assert_false(sources.get_last_sources().is_empty(), "they come out of sources (R2)")
	mode.step(FlameRules.DURATION)
	assert_true(mode.is_raid_over())
	assert_false(RoomVariants.holds_completion(room), "after 40 s the rest decides")
	assert_true(mode.is_bonus_achieved(), "the flame held")


func test_about_seventy_percent_go_for_the_flame() -> void:
	var room := _room(20, 3)
	var mode := _attach(room, &"flame") as FlameMode
	room.activate()
	for i in 6:
		mode.send_push()
	var raiders := 0
	var total := 0
	for enemy in _living(room):
		total += 1
		if EnemyDecoy.get_decoy(enemy) == mode.flame:
			raiders += 1
	assert_gt(total, 10)
	var share := float(raiders) / total
	assert_between(share, 0.4, 0.95, "about 70 %% go for the flame (%d of %d)" % [raiders, total])


func test_untouched_flame_gives_chest_and_a_crystal() -> void:
	var room := _room()
	var mode := _attach(room, &"flame") as FlameMode
	room.activate()
	var crystals := RunManager.get_run_crystals()
	mode.step(FlameRules.DURATION + 0.1)
	assert_eq(RunManager.get_run_crystals(), crystals + FlameRules.FULL_FLAME_CRYSTALS, "volle Flamme = +1 Kristall")
	_kill_all(room)
	await wait_physics_frames(2)
	assert_eq(room.state, RoomController.State.CLEARED)
	assert_eq(mode.chests.size(), 1, "one bonus chest (D-109)")
	assert_false(mode.chests[0].is_locked(), "open to loot, the room is cleared")


func test_flame_out_means_no_bonus_but_the_fight_goes_on() -> void:
	var room := _room()
	var mode := _attach(room, &"flame") as FlameMode
	room.activate()
	var enemy := _living(room)[0]
	for i in 200:
		if not mode.flame.is_alive():
			break
		mode.flame.hurtbox.receive_hit(_enemy_hit(enemy, 4.0))
	assert_false(mode.flame.is_alive())
	assert_eq(mode.bonus, CombatVariant.Bonus.LOST)
	assert_true(mode.get_objective().is_finished() and not mode.get_objective().success, "Verpasst")
	assert_eq(room.state, RoomController.State.ACTIVE, "the room goes on")
	mode.step(FlameRules.PUSH_INTERVAL)
	assert_eq(mode.get_pushes_sent(), 0, "no pushes without a flame")
	mode.step(FlameRules.DURATION)
	_kill_all(room)
	await wait_physics_frames(2)
	assert_true(mode.is_finished())
	assert_eq(mode.chests.size(), 0, "no bonus chest")


# --- Rifts (hall: rifts at the walls, their own summons) ---

func test_rifts_open_with_the_fight_and_count_for_the_room() -> void:
	var room := _room(20, 3)
	var mode := _attach(room, &"rifts") as RiftsMode
	assert_between(mode.get_rift_tile_count(), 2, 3)
	room.activate()
	var rifts := mode.get_open_rifts()
	assert_between(rifts.size(), 2, 3, "2-3 rifts")
	assert_eq(room.get_alive_enemy_count(), mode.get_alive_minions() + rifts.size(), "rifts count like enemies")
	var rift := rifts[0]
	var before := room.get_alive_enemy_count()
	rift.step(rift.get_cooldown() + 0.01)
	assert_true(rift.is_winding_up(), "telegraph first")
	rift.step(RiftRules.WIND_UP + 0.01)
	assert_eq(room.get_alive_enemy_count(), before + 1, "one enemy, tracked by the room")


func test_room_is_done_only_without_rifts_and_enemies() -> void:
	var room := _room(20, 2)
	var mode := _attach(room, &"rifts") as RiftsMode
	room.activate()
	var crystals := RunManager.get_run_crystals()
	var rifts := mode.get_open_rifts()
	_kill_all(room, rifts)
	await wait_physics_frames(2)
	assert_eq(room.state, RoomController.State.ACTIVE, "rifts still open")
	for rift in rifts:
		rift.health.take_damage(INF)
	assert_true(mode.get_objective().success, "all rifts closed")
	assert_eq(RunManager.get_run_crystals(), crystals + RiftRules.FAST_CRYSTALS, "fast: +1 crystal")
	await wait_physics_frames(2)
	assert_eq(room.state, RoomController.State.CLEARED)
	assert_eq(mode.chests.size(), 1)


# --- Hunt (hall: own spots) ---

func test_crowned_one_waits_still_and_flees_once_the_fight_runs() -> void:
	var room := _room(20, 3)
	var mode := _attach(room, &"hunt") as HuntMode
	assert_not_null(mode.crowned)
	assert_not_null(mode.crowned.get_node_or_null("Crown"))
	assert_true(mode.crowned.is_in_intro(), "he waits, invulnerable")
	assert_gte(mode.guards.size(), HuntRules.MIN_GUARDS, "guards between him and the entrance")
	var flight := mode.flight
	_player(room, Vector2i(7, 4))
	flight.step(0.1)
	assert_eq(flight.state, BountyFlight.State.WATCHING, "no spotting before the fight")
	room.activate()
	assert_false(mode.crowned.is_in_intro())
	assert_true(flight.watching)
	assert_false(flight.evade_points.is_empty(), "zigzag spots")
	for guard in mode.guards:
		assert_false(guard.is_in_intro(), "guards fight too")


func test_escaped_crowned_one_is_gone_without_loot() -> void:
	var room := _room(20, 3)
	var mode := _attach(room, &"hunt") as HuntMode
	room.activate()
	var flight := mode.flight
	flight.spot()
	assert_not_null(mode.get_hole(), "the escape hole is there")
	var before := room.get_alive_enemy_count()
	flight.step(HuntRules.CATCH_TIME + HuntRules.STUCK_GRACE)
	flight.step(HuntRules.JUMP_TIME + 0.01)
	assert_true(flight.is_escaped())
	assert_eq(mode.bonus, CombatVariant.Bonus.LOST)
	assert_eq(room.get_alive_enemy_count(), before - 1, "gone from the room")
	_kill_all(room)
	await wait_physics_frames(2)
	assert_eq(room.state, RoomController.State.CLEARED)
	assert_eq(mode.chests.size(), 0)


func test_caught_crowned_one_drops_his_loot() -> void:
	var room := _room(20, 3)
	var mode := _attach(room, &"hunt") as HuntMode
	room.activate()
	assert_gte(mode.crowned.gold_drop, HuntRules.LOOT_GOLD_MIN, "viel Gold")
	mode.flight.spot()
	mode.flight.step(3.0)
	mode.crowned.health.take_damage(INF)
	assert_true(mode.flight.is_caught())
	assert_eq(mode.bonus, CombatVariant.Bonus.ACHIEVED)
	_kill_all(room)
	await wait_physics_frames(2)
	assert_eq(room.state, RoomController.State.CLEARED)
	assert_eq(mode.chests.size(), 1 if mode.has_loot_upgrade() else 0, "sometimes an upgrade")


func test_zigzag_keeps_away_from_the_player_then_runs_for_the_hole() -> void:
	var room := _room(20, 3)
	var mode := _attach(room, &"hunt") as HuntMode
	_player(room, Vector2i(2, 7))
	room.activate()
	var flight := mode.flight
	flight.spot()
	flight.step(0.016)
	var target := flight.get_run_target()
	assert_ne(target, flight.hole_position, "first he runs to a spot")
	flight.time_fleeing = HuntRules.CATCH_TIME - HuntRules.RUN_TO_HOLE_TIME
	assert_eq(flight.get_run_target(), flight.hole_position, "then for the hole")


# --- Gravedigger trait (crypt) ---

func test_trait_comes_with_crypt_combat_rooms_only() -> void:
	var crypt := _room(8)
	RoomVariants.attach(crypt, VariantTable.Pick.new(), RandomNumberGenerator.new())
	assert_not_null(GravediggerTrait.of(crypt), "crypt room 8")
	var early := _room(VariantRules.GRAVEDIGGER_FROM_ROOM - 1)
	RoomVariants.attach(early, VariantTable.Pick.new(), RandomNumberGenerator.new())
	assert_null(GravediggerTrait.of(early))
	var grotto := _room(20)
	RoomVariants.attach(grotto, VariantTable.Pick.new(), RandomNumberGenerator.new())
	assert_null(GravediggerTrait.of(grotto), "not in the grotto")
	var with_mode := _room(8)
	_attach(with_mode, &"flame")
	assert_not_null(GravediggerTrait.of(with_mode), "minigames in the crypt too")


func test_about_a_third_of_the_skeletons_rise() -> void:
	var marked := 0
	var total := 0
	for i in 12:
		var room := _room(8 + i, 6)
		var gravedigger := GravediggerTrait.attach(room)
		room.activate()
		for enemy in _living(room):
			total += 1
			if gravedigger.is_marked(enemy):
				marked += 1
		room.queue_free()
		await wait_process_frames(1)
	assert_between(float(marked) / total, 0.15, 0.6, "about 35 %% (%d of %d)" % [marked, total])


func test_marked_skeleton_leaves_a_heap_that_rises_once_with_half_health() -> void:
	var room := _room(8, 1)
	var gravedigger := GravediggerTrait.attach(room)
	room.activate()
	var skeleton := _living(room)[0]
	gravedigger.mark(skeleton)
	var max_health := skeleton.health.get_max_health()
	assert_eq(skeleton.gold_drop, 0, "gold waits for the final death")
	skeleton.health.take_damage(INF)
	await wait_physics_frames(2)
	assert_eq(gravedigger.get_heap_count(), 1)
	assert_eq(room.state, RoomController.State.ACTIVE, "the heap keeps the room shut")
	var heap := gravedigger.get_heaps()[0]
	assert_eq(heap.collision_layer, 0, "walk over it")
	gravedigger.step(VariantRules.RISE_TIME - VariantRules.RISE_ANIMATION_TIME + 0.01)
	assert_false(heap.is_physics_processing(), "rising: visible and still")
	gravedigger.step(VariantRules.RISE_ANIMATION_TIME)
	assert_eq(gravedigger.get_risen_count(), 1)
	assert_eq(heap.data.id, &"skeleton", "the skeleton stands again")
	assert_almost_eq(heap.health.get_health(), VariantRules.risen_health(max_health), 0.01, "50 % health")
	assert_null(heap.data.death_spawn, "rises at most once")
	heap.health.take_damage(INF)
	await wait_physics_frames(2)
	assert_eq(gravedigger.get_heap_count(), 0, "no second heap")
	assert_eq(room.state, RoomController.State.CLEARED)


func test_a_hit_or_a_step_destroys_the_heap_and_drops_the_gold() -> void:
	var room := _room(8, 2)
	var gravedigger := GravediggerTrait.attach(room)
	room.activate()
	var skeletons := _living(room)
	var gold := 7
	for skeleton in skeletons:
		gravedigger.mark(skeleton)
		skeleton.set_meta(GravediggerTrait.GOLD_META, gold)
	for skeleton in skeletons:
		skeleton.health.take_damage(INF)
	await wait_physics_frames(2)
	var heaps := gravedigger.get_heaps()
	assert_eq(heaps.size(), 2)
	assert_eq(heaps[0].gold_drop, gold, "the heap carries the gold")
	heaps[0].hurtbox.receive_hit(_enemy_hit(null, 0.5))
	assert_true(heaps[0].is_dead(), "any hit destroys it")
	var player := _player(room)
	player.global_position = heaps[1].global_position
	gravedigger.step(0.01)
	assert_true(heaps[1].is_dead(), "walking over it destroys it")
	await wait_physics_frames(2)
	assert_eq(room.state, RoomController.State.CLEARED)
	assert_eq(gravedigger.get_risen_count(), 0)


func test_bonus_chest_never_lands_on_a_player() -> void:
	var room := _room()
	var mode := _attach(room, &"flame")
	var player := _player(room, Vector2i(7, 7))
	room.activate()
	await wait_process_frames(1)
	var player_tile := RoomTiles.local_to_tile(room.to_local(player.get_feet_position()))
	var chests := mode.spawn_bonus_chests(RoomTiles.tile_center(player_tile))
	assert_false(chests.is_empty())
	for chest in chests:
		var tile := RoomTiles.local_to_tile(chest.position - Vector2(0, 22))
		var off := (tile - player_tile).abs()
		assert_true(maxi(off.x, off.y) >= 2, "the chest keeps clear of the player (playtest 15.10.2026)")

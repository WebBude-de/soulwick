extends GutTest
## Combat variants in a real combat room (A7, KONZEPT_RAEUME §4): attaching through RoomVariants,
## the shared interface (start on encounter, finish on completion, bonus chest), the soul flame
## (raid waves, enemy-only damage, flame out = no bonus, room held during the raid), the rifts
## (count for the room, summon with wind-up, at most six), the gravedigger (bone heaps, rising with
## half health, gold on the final death) and the bounty (flight, escape hole, caught or escaped).

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_variant_rooms_save.cfg"


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


## A normal combat room with skeletons only (no elites), fixed seed, not yet entered.
func _room(room_index := 8, count := 4) -> RoomController:
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


func _attach(room: RoomController, id: StringName, seed_value := 5) -> CombatVariant:
	var pick := VariantTable.Pick.new()
	pick.variant_id = id
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	assert_eq(RoomVariants.attach(room, pick, rng), id, "%s attached" % id)
	return CombatVariant.of(room)


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

func test_attach_reads_back_and_never_twice() -> void:
	var room := _room()
	assert_eq(RoomVariants.get_variant_id(room), &"")
	var variant := _attach(room, VariantRules.BOUNTY)
	assert_not_null(variant)
	assert_eq(RoomVariants.get_variant_id(room), VariantRules.BOUNTY, "UX2 reads the id")
	assert_false(RoomVariants.has_wager_altar(room))
	var again := VariantTable.Pick.new()
	again.variant_id = VariantRules.RIFTS
	assert_eq(RoomVariants.attach(room, again, RandomNumberGenerator.new()), &"", "one variant per room")
	assert_eq(RoomVariants.get_variant_id(room), VariantRules.BOUNTY)


func test_attach_uses_one_number_and_nothing_for_an_empty_pick() -> void:
	var room := _room()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var reference := RandomNumberGenerator.new()
	reference.seed = 9
	assert_eq(RoomVariants.attach(room, VariantTable.Pick.new(), rng), &"")
	assert_eq(rng.state, reference.state, "nothing drawn for an empty pick")
	var pick := VariantTable.Pick.new()
	pick.variant_id = VariantRules.SOUL_FLAME
	RoomVariants.attach(room, pick, rng)
	reference.randi()
	assert_eq(rng.state, reference.state, "exactly one number for a variant")


func test_variant_starts_with_the_fight_and_finishes_with_the_room() -> void:
	var room := _room()
	var variant := _attach(room, VariantRules.BOUNTY)
	watch_signals(variant)
	assert_false(variant.is_started())
	room.activate()
	assert_true(variant.is_started(), "start on encounter_started")
	assert_signal_emitted(variant, "started")
	_kill_all(room)
	await wait_physics_frames(2)
	assert_true(variant.is_finished(), "finish on completed")
	assert_signal_emitted(variant, "finished")


# --- Soul flame ---

func test_flame_burns_in_the_middle_and_takes_only_enemy_damage() -> void:
	var room := _room()
	var variant := _attach(room, VariantRules.SOUL_FLAME) as SoulFlameVariant
	var flame := variant.flame
	assert_not_null(flame)
	assert_true(flame.is_alive())
	assert_lt(flame.position.distance_to(room.content_anchor.position), RoomTiles.TILE_WORLD * 2.5, "near the centre")
	assert_eq(flame.hurtbox.collision_layer, PhysicsLayers.PLAYER_HURTBOX, "enemy attacks see it")
	var full := flame.health.get_health()
	var trap := flame.hurtbox.receive_hit(_enemy_hit(null))
	assert_true(trap.blocked, "traps and hazards pass through")
	room.activate()
	var enemy := _living(room)[0]
	flame.hurtbox.receive_hit(_enemy_hit(enemy))
	assert_eq(flame.health.get_health(), full - 1.0, "an enemy hit counts")


func test_raid_holds_the_room_and_sends_waves() -> void:
	var room := _room()
	var variant := _attach(room, VariantRules.SOUL_FLAME) as SoulFlameVariant
	assert_false(RoomVariants.holds_completion(room), "not before the fight")
	room.activate()
	assert_true(RoomVariants.holds_completion(room), "held during the raid (RoomController hook)")
	var before := room.get_alive_enemy_count()
	variant.step(VariantRules.FLAME_WAVE_INTERVAL)
	assert_eq(variant.get_waves_sent(), 1, "a raid wave after the interval")
	assert_gt(room.get_alive_enemy_count(), before, "raid enemies count for the room")
	variant.step(VariantRules.FLAME_DURATION)
	assert_true(variant.is_raid_over())
	assert_false(RoomVariants.holds_completion(room), "after 40 s the rest decides")


func test_about_seventy_percent_go_for_the_flame() -> void:
	var room := _room(8, 3)
	var variant := _attach(room, VariantRules.SOUL_FLAME) as SoulFlameVariant
	room.activate()
	for i in 6:
		variant.send_wave()
	var raiders := 0
	var total := 0
	for enemy in _living(room):
		total += 1
		if EnemyDecoy.get_decoy(enemy) == variant.flame:
			raiders += 1
	assert_gt(total, 10)
	var share := float(raiders) / total
	assert_between(share, 0.4, 0.95, "about 70 %% go for the flame (%d of %d)" % [raiders, total])


func test_flame_alive_at_the_end_gives_a_bonus_chest() -> void:
	var room := _room()
	var variant := _attach(room, VariantRules.SOUL_FLAME) as SoulFlameVariant
	room.activate()
	variant.step(VariantRules.FLAME_DURATION + 0.1)
	_kill_all(room)
	await wait_physics_frames(2)
	assert_true(room.state == RoomController.State.CLEARED)
	assert_true(variant.is_bonus_achieved())
	assert_eq(variant.chests.size(), 1, "one bonus chest (D-109)")
	assert_false(variant.chests[0].is_locked(), "open to loot, the room is cleared")


func test_flame_out_means_no_bonus_but_the_fight_goes_on() -> void:
	var room := _room()
	var variant := _attach(room, VariantRules.SOUL_FLAME) as SoulFlameVariant
	room.activate()
	var enemy := _living(room)[0]
	flame_kill(variant.flame, enemy)
	assert_false(variant.flame.is_alive())
	assert_eq(variant.bonus, CombatVariant.Bonus.LOST)
	assert_eq(room.state, RoomController.State.ACTIVE, "the room goes on")
	variant.step(VariantRules.FLAME_WAVE_INTERVAL)
	assert_eq(variant.get_waves_sent(), 0, "no raid without a flame")
	assert_null(EnemyDecoy.get_decoy(enemy), "the raiders turn to the players")
	variant.step(VariantRules.FLAME_DURATION)
	_kill_all(room)
	await wait_physics_frames(2)
	assert_true(variant.is_finished())
	assert_eq(variant.chests.size(), 0, "no bonus chest")


func flame_kill(flame: SoulFlame, enemy: Enemy) -> void:
	for i in 200:
		if not flame.is_alive():
			return
		flame.hurtbox.receive_hit(_enemy_hit(enemy, 4.0))


# --- Rifts ---

func test_rifts_open_with_the_fight_and_count_for_the_room() -> void:
	var room := _room(8, 3)
	var variant := _attach(room, VariantRules.RIFTS) as RiftsVariant
	assert_between(variant.get_rift_tiles().size(), 2, 3)
	room.activate()
	var rifts := variant.get_open_rifts()
	assert_between(rifts.size(), 2, 3, "2-3 rifts (KONZEPT §4.2)")
	var minions := variant.get_alive_minions()
	assert_eq(room.get_alive_enemy_count(), minions + rifts.size(), "rifts count like enemies")
	for rift in rifts:
		assert_gt(rift.health.get_max_health(), 0.0)
		var tile := RoomTiles.local_to_tile(room.to_local(rift.global_position))
		assert_false(room.tiles.get_walkable_tiles().has(tile + Vector2i.UP), "at a wall")


func test_rift_summons_after_a_readable_wind_up() -> void:
	var room := _room(8, 1)
	var variant := _attach(room, VariantRules.RIFTS) as RiftsVariant
	room.activate()
	var rift := variant.get_open_rifts()[0]
	var before := room.get_alive_enemy_count()
	rift.step(rift.get_cooldown() + 0.01)
	assert_true(rift.is_winding_up(), "telegraph first")
	assert_eq(room.get_alive_enemy_count(), before, "nobody yet")
	rift.step(VariantRules.RIFT_WIND_UP + 0.01)
	assert_false(rift.is_winding_up())
	assert_eq(room.get_alive_enemy_count(), before + 1, "one enemy, tracked by the room")


func test_rifts_stop_at_six_living_enemies() -> void:
	var room := _room(8, 6)
	var variant := _attach(room, VariantRules.RIFTS) as RiftsVariant
	room.activate()
	for i in 4:
		variant.spawn_enemies([room.content_anchor.position] as Array[Vector2])
	assert_gte(variant.get_alive_minions(), VariantRules.RIFT_MAX_ALIVE)
	var rift := variant.get_open_rifts()[0]
	var before := room.get_alive_enemy_count()
	rift.step(rift.get_cooldown() + 0.01)
	rift.step(VariantRules.RIFT_WIND_UP + 0.01)
	assert_eq(room.get_alive_enemy_count(), before, "room full: no summon")


func test_room_is_done_only_without_rifts_and_enemies() -> void:
	var room := _room(8, 2)
	var variant := _attach(room, VariantRules.RIFTS) as RiftsVariant
	room.activate()
	var rifts := variant.get_open_rifts()
	_kill_all(room, rifts)
	await wait_physics_frames(2)
	assert_eq(room.state, RoomController.State.ACTIVE, "rifts still open")
	for rift in rifts:
		rift.health.take_damage(INF)
	await wait_physics_frames(2)
	assert_eq(room.state, RoomController.State.CLEARED)
	assert_true(variant.is_bonus_achieved())
	assert_eq(variant.chests.size(), 1)


# --- Gravedigger ---

func test_skeletons_leave_a_bone_heap_that_keeps_the_room_shut() -> void:
	var room := _room(8, 1)
	var variant := _attach(room, VariantRules.GRAVEDIGGER) as GravediggerVariant
	room.activate()
	var skeleton := _living(room)[0]
	assert_eq(skeleton.gold_drop, 0, "gold waits for the final death")
	assert_not_null(skeleton.data.death_spawn, "leaves a heap")
	skeleton.health.take_damage(INF)
	await wait_physics_frames(2)
	assert_eq(variant.get_heap_count(), 1)
	assert_eq(room.state, RoomController.State.ACTIVE, "the heap keeps the room shut")
	var heap := variant.get_heaps()[0]
	assert_eq(heap.collision_layer, 0, "walk over it")


func test_heap_rises_once_with_half_health() -> void:
	var room := _room(8, 1)
	var variant := _attach(room, VariantRules.GRAVEDIGGER) as GravediggerVariant
	room.activate()
	var skeleton := _living(room)[0]
	var max_health := skeleton.health.get_max_health()
	skeleton.health.take_damage(INF)
	await wait_physics_frames(2)
	var heap := variant.get_heaps()[0]
	variant.step(VariantRules.RISE_TIME - VariantRules.RISE_ANIMATION_TIME + 0.01)
	assert_false(heap.is_physics_processing(), "rising: visible and still")
	variant.step(VariantRules.RISE_ANIMATION_TIME)
	assert_eq(variant.get_risen_count(), 1)
	assert_eq(heap.data.id, &"skeleton", "the skeleton stands again")
	assert_almost_eq(heap.health.get_health(), VariantRules.risen_health(max_health), 0.01, "50 % health")
	assert_ne(heap.collision_layer, 0, "solid again")
	assert_null(heap.data.death_spawn, "rises at most once")
	heap.health.take_damage(INF)
	await wait_physics_frames(2)
	assert_eq(variant.get_heap_count(), 0, "no second heap")
	assert_eq(room.state, RoomController.State.CLEARED)


func test_a_hit_or_a_step_destroys_the_heap_and_drops_the_gold() -> void:
	var room := _room(8, 2)
	var variant := _attach(room, VariantRules.GRAVEDIGGER) as GravediggerVariant
	room.activate()
	var skeletons := _living(room)
	# No economy in the test: give the skeletons a gold value the variant holds back.
	var gold := 7
	for skeleton in skeletons:
		skeleton.set_meta(GravediggerVariant.GOLD_META, gold)
	for skeleton in skeletons:
		skeleton.health.take_damage(INF)
	await wait_physics_frames(2)
	var heaps := variant.get_heaps()
	assert_eq(heaps.size(), 2)
	assert_eq(heaps[0].gold_drop, gold, "the heap carries the gold")
	assert_eq(heaps[1].gold_drop, gold)
	heaps[0].hurtbox.receive_hit(_enemy_hit(null, 0.5))
	assert_true(heaps[0].is_dead(), "any hit destroys it")
	var player := _player(room)
	player.global_position = heaps[1].global_position
	variant.step(0.01)
	assert_true(heaps[1].is_dead(), "walking over it destroys it")
	await wait_physics_frames(2)
	assert_eq(room.state, RoomController.State.CLEARED)
	assert_eq(variant.get_risen_count(), 0)


func test_skeleton_pushed_into_an_abyss_drops_its_gold_at_once() -> void:
	var room := _room(8, 1)
	var variant := _attach(room, VariantRules.GRAVEDIGGER) as GravediggerVariant
	room.activate()
	var skeleton := _living(room)[0]
	if not skeleton.has_method(&"fall_into_pit"):
		pass_test("abyss (A4) not in this build")
		return
	skeleton.set_meta(GravediggerVariant.GOLD_META, 5)
	skeleton.call(&"fall_into_pit")
	assert_eq(skeleton.gold_drop, 5, "no heap in an abyss: the gold drops at the rim")
	await wait_physics_frames(2)
	assert_eq(variant.get_heap_count(), 0, "no heap")


# --- Bounty ---

func test_bounty_wears_a_crown_and_flees_when_it_sees_a_player() -> void:
	var room := _room(8, 3)
	var variant := _attach(room, VariantRules.BOUNTY) as BountyVariant
	room.activate()
	assert_not_null(variant.bounty)
	var flight := BountyFlight.of(variant.bounty)
	assert_not_null(flight)
	assert_not_null(variant.bounty.get_node_or_null("Crown"))
	assert_true(flight.spot())
	assert_true(flight.is_fleeing())
	assert_false(variant.bounty.is_physics_processing(), "no more fighting")
	var hole := variant.get_hole()
	assert_not_null(hole, "the escape hole opens")
	var hole_tile := RoomTiles.local_to_tile(room.to_local(flight.hole_position))
	var bounty_tile := RoomTiles.local_to_tile(room.to_local(variant.bounty.global_position))
	assert_gte(Vector2(hole_tile - bounty_tile).length(), VariantRules.BOUNTY_HOLE_MIN_TILES - 0.01, "far away")


func test_escaped_bounty_is_gone_and_the_room_still_completes() -> void:
	var room := _room(8, 3)
	var variant := _attach(room, VariantRules.BOUNTY) as BountyVariant
	room.activate()
	var flight := BountyFlight.of(variant.bounty)
	flight.spot()
	var before := room.get_alive_enemy_count()
	flight.step(VariantRules.BOUNTY_CATCH_TIME)
	flight.step(VariantRules.BOUNTY_JUMP_TIME + 0.01)
	assert_true(flight.is_escaped())
	assert_eq(variant.bonus, CombatVariant.Bonus.LOST)
	assert_eq(room.get_alive_enemy_count(), before - 1, "gone from the room")
	_kill_all(room)
	await wait_physics_frames(2)
	assert_eq(room.state, RoomController.State.CLEARED)
	assert_eq(variant.chests.size(), 0)


func test_caught_bounty_gives_the_bonus_chest() -> void:
	var room := _room(8, 3)
	var variant := _attach(room, VariantRules.BOUNTY) as BountyVariant
	room.activate()
	var flight := BountyFlight.of(variant.bounty)
	flight.spot()
	flight.step(3.0)
	variant.bounty.health.take_damage(INF)
	assert_true(flight.is_caught())
	assert_eq(variant.bonus, CombatVariant.Bonus.ACHIEVED)
	_kill_all(room)
	await wait_physics_frames(2)
	assert_eq(room.state, RoomController.State.CLEARED)
	assert_eq(variant.chests.size(), 1)

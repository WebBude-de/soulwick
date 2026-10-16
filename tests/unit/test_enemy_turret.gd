extends GutTest
## Stationary turret (D-148): TurretRules cadence and target choice, SlowStatus on the player (no
## stacking, ends by itself, only with effective hits), the Turret node (shoots, slows, can be
## destroyed, never moves) and TurretPlacement (which rooms, which tiles).

const PLAYER_SCENE_PATH := "res://player/player.tscn"
const TEST_SAVE_PATH := "user://test_enemy_turret.cfg"
const CRYPT_TURRET := "res://enemies/data/turret_crypt.tres"

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.load_game()


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func after_each() -> void:
	for node in get_children():
		if node is Enemy or node is Projectile or node is StaticBody2D:
			node.queue_free()


func _player(at := Vector2.ZERO) -> Player:
	var player: Player = add_child_autofree((load(PLAYER_SCENE_PATH) as PackedScene).instantiate())
	player.global_position = at
	return player


func _turret(at := Vector2.ZERO, room := 4) -> Turret:
	var turret := Turret.create(load(CRYPT_TURRET), room)
	turret.position = at
	add_child_autofree(turret)
	return turret


# --- TurretRules: cadence ---

func test_rules_fire_after_first_delay_and_charge_then_in_a_fixed_cadence() -> void:
	var rules := TurretRules.new(300.0, 0.6, 1.8, 0.8)
	var shots: Array[float] = []
	var time := 0.0
	var step := 1.0 / 60.0
	while time < 8.0:
		time += step
		if rules.tick(step, Vector2.RIGHT):
			shots.append(time)
	assert_eq(shots.size(), 3, "0.8 + 0.6, then every 2.4 s within 8 s")
	assert_almost_eq(shots[0], 1.4, 0.05, "first delay + charge")
	assert_almost_eq(shots[1] - shots[0], rules.get_shot_interval(), 0.05)
	assert_almost_eq(shots[2] - shots[1], 2.4, 0.05)
	assert_eq(rules.shots, 3)


func test_rules_charge_breaks_off_without_target_until_the_aim_locks() -> void:
	var rules := TurretRules.new(300.0, 0.6, 1.8, 0.0)
	rules.tick(0.01, Vector2.RIGHT)
	assert_true(rules.is_charging(), "a target starts the charge")
	rules.tick(0.1, Vector2.ZERO)
	assert_false(rules.is_charging(), "target lost before the lock: no shot")
	assert_eq(rules.phase, TurretRules.Phase.IDLE)
	# Again, but lose the target after the aim locked: the shot goes along the locked aim.
	for i in 90:
		rules.tick(1.0 / 60.0, Vector2.DOWN)
		if rules.is_aim_locked():
			break
	assert_true(rules.is_aim_locked())
	var fired := false
	for i in 30:
		fired = rules.tick(1.0 / 60.0, Vector2.ZERO) or fired
	assert_true(fired, "locked shots leave anyway")
	assert_eq(rules.aim, Vector2.DOWN, "along the locked aim")


func test_rules_aim_follows_until_the_lock_then_holds() -> void:
	var rules := TurretRules.new(300.0, 0.6, 1.8, 0.0)
	rules.tick(0.01, Vector2.RIGHT)
	rules.tick(0.2, Vector2.UP)
	assert_eq(rules.aim, Vector2.UP, "follows while charging")
	rules.tick(0.25, Vector2.UP)
	assert_true(rules.is_aim_locked())
	rules.tick(0.05, Vector2.LEFT)
	assert_eq(rules.aim, Vector2.UP, "holds in the last 0.2 s")
	assert_gt(rules.get_charge_progress(), 0.8)


func test_rules_scale_with_depth_but_not_below_the_floor() -> void:
	var data: EnemyData = load(CRYPT_TURRET)
	var early := TurretRules.for_data(data, 4)
	var deep := TurretRules.for_data(data, 400)
	assert_almost_eq(early.cooldown, data.attack_cooldown, 0.001)
	assert_almost_eq(deep.cooldown, data.attack_cooldown * TurretRules.MIN_COOLDOWN_FACTOR, 0.001)
	assert_lt(deep.charge_time, early.charge_time, "shorter telegraph deeper down")
	assert_almost_eq(early.sight_range, data.attack_range, 0.001)


# --- TurretRules: target ---

## Stand-in target: EnemyTargeting asks is_alive() / is_protected() if a node has them.
class FakeTarget:
	extends Node2D
	var alive := true
	var protected := false

	func is_alive() -> bool:
		return alive

	func is_protected() -> bool:
		return protected


func _fake(at: Vector2) -> FakeTarget:
	var target: FakeTarget = add_child_autofree(FakeTarget.new())
	target.global_position = at
	return target


func test_choose_target_takes_the_nearest_living_player_in_range_and_sight() -> void:
	var near := _fake(Vector2(100, 0))
	var far := _fake(Vector2(-200, 0))
	var outside := _fake(Vector2(0, 400))
	var players: Array = [far, near, outside]
	assert_eq(TurretRules.choose_target(players, Vector2.ZERO, 300.0), near)
	near.alive = false
	assert_eq(TurretRules.choose_target(players, Vector2.ZERO, 300.0), far, "dead players are no target")
	far.protected = true
	assert_null(TurretRules.choose_target(players, Vector2.ZERO, 300.0), "protected and out of range: none")
	far.protected = false
	var hidden := func(node: Node2D) -> bool: return node != far
	assert_null(TurretRules.choose_target(players, Vector2.ZERO, 300.0, hidden), "not in sight")
	outside.global_position = Vector2(0, 250)
	assert_eq(TurretRules.choose_target(players, Vector2.ZERO, 300.0, hidden), outside, "next nearest in sight")
	var freed := FakeTarget.new()
	add_child(freed)
	freed.free()
	assert_eq(TurretRules.choose_target([freed, outside], Vector2.ZERO, 300.0), outside, "freed nodes are skipped")


# --- SlowStatus ---

func test_slow_reduces_speed_refreshes_without_stacking_and_ends() -> void:
	var player := _player()
	await wait_physics_frames(1)
	var base := player.move_speed
	var status := SlowStatus.apply(player, 0.65, 1.5)
	assert_not_null(status)
	assert_true(SlowStatus.is_slowed(player))
	assert_almost_eq(player.move_speed, base * 0.65, 0.01)
	await wait_seconds(0.5)
	SlowStatus.apply(player, 0.65, 1.5)
	assert_almost_eq(player.move_speed, base * 0.65, 0.01, "a second hit does not stack")
	assert_eq(player.get_children().filter(func(child: Node) -> bool: return child is SlowStatus).size(), 1, "one status per player")
	assert_almost_eq(SlowStatus.get_for(player).time_left, 1.5, 0.05, "refreshed to the full time")
	SlowStatus.apply(player, 0.8, 0.2)
	assert_almost_eq(player.move_speed, base * 0.65, 0.01, "the stronger slow stays")
	assert_almost_eq(SlowStatus.get_for(player).time_left, 1.5, 0.05, "a shorter slow does not cut it")
	await wait_seconds(1.7)
	assert_false(SlowStatus.is_slowed(player))
	assert_almost_eq(player.move_speed, base, 0.01, "speed back after the slow")
	assert_false(player.has_meta(ToxicPuddle.META_BASE_SPEED))


func test_slow_and_puddle_combine_as_strongest() -> void:
	var player := _player()
	await wait_physics_frames(1)
	var base := player.move_speed
	ToxicPuddle.apply_slow(player, 4242, ToxicPuddle.SLOW_FACTOR)
	SlowStatus.apply(player, 0.65, 0.3)
	assert_almost_eq(player.move_speed, base * minf(0.65, ToxicPuddle.SLOW_FACTOR), 0.01)
	await wait_seconds(0.5)
	assert_almost_eq(player.move_speed, base * ToxicPuddle.SLOW_FACTOR, 0.01, "the puddle stays")
	ToxicPuddle.apply_slow(player, 4242, 1.0)
	assert_almost_eq(player.move_speed, base, 0.01)


func test_slow_only_with_effective_hits() -> void:
	var player := _player()
	await wait_physics_frames(1)
	var damage := DamageData.new()
	damage.amount = 0.25
	damage.slow_factor = 0.65
	damage.slow_duration = 1.5
	var blocked := DamageResult.new()
	blocked.blocked = true
	assert_null(SlowStatus.apply_from_damage(player, blocked, damage), "blocked (dash, I-frames)")
	SlowStatus.apply_on_hit(player.hurtbox, blocked, 0.65, 1.5)
	assert_false(SlowStatus.is_slowed(player))
	var copy := damage.duplicate_for_target()
	assert_eq(copy.slow_factor, 0.65, "a copy keeps the slow")
	assert_eq(copy.slow_duration, 1.5)
	var result := player.hurtbox.receive_hit(copy)
	assert_true(result.is_effective())
	SlowStatus.apply_on_hit(player.hurtbox, result, copy.slow_factor, copy.slow_duration)
	assert_true(SlowStatus.is_slowed(player))
	assert_null(SlowStatus.apply(_turret(Vector2(500, 500)), 0.65, 1.5), "only players")


func test_slow_clear_and_freed_player() -> void:
	var player: Player = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate()
	add_child(player)
	await wait_physics_frames(1)
	var base := player.move_speed
	SlowStatus.apply(player, 0.5, 5.0).clear()
	await wait_physics_frames(1)
	assert_false(SlowStatus.is_slowed(player))
	assert_almost_eq(player.move_speed, base, 0.01, "clear gives the speed back")
	SlowStatus.apply(player, 0.5, 5.0)
	player.queue_free()
	await wait_physics_frames(2)
	assert_false(is_instance_valid(player), "the status goes with its player")


# --- Turret node ---

func test_turret_shoots_the_player_and_slows_him() -> void:
	var player := _player(Vector2(180, 30))
	var turret := _turret(Vector2.ZERO)
	watch_signals(turret)
	var start := turret.global_position
	await wait_seconds(0.3)
	assert_eq(turret.get_aim_target(), player, "aims at the player in range")
	var base := player.move_speed
	var before := player.health.get_health() + player.shield.get_shield()
	await wait_seconds(3.0)
	assert_signal_emitted_with_parameters(turret, "ability_used", [turret, &"turret_shot"])
	var lost := before - player.health.get_health() - player.shield.get_shield()
	assert_almost_eq(lost, 0.5, 0.01, "one small hit (0.25 raw, rounded to 0.5)")
	assert_true(SlowStatus.is_slowed(player), "the hit slows")
	assert_almost_eq(player.move_speed, base * TurretRules.SLOW_FACTOR, 0.01)
	assert_eq(turret.global_position, start, "never moves")


func test_turret_ignores_players_out_of_range_or_behind_a_wall() -> void:
	var far := _player(Vector2(500, 0))
	var turret := _turret(Vector2.ZERO)
	await wait_seconds(0.4)
	assert_null(turret.get_aim_target(), "out of range")
	far.global_position = Vector2(200, 0)
	var wall := StaticBody2D.new()
	wall.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 300)
	shape.shape = rect
	wall.add_child(shape)
	add_child(wall)
	wall.position = Vector2(100, 0)
	await wait_seconds(0.4)
	assert_null(turret.get_aim_target(), "no sight through a wall")
	assert_false(turret.rules.is_charging())
	wall.queue_free()
	await wait_seconds(0.4)
	assert_eq(turret.get_aim_target(), far, "in sight again")


func test_turret_telegraph_lights_up_before_the_shot() -> void:
	_player(Vector2(200, 0))
	var turret := _turret(Vector2.ZERO)
	var glow := turret.get_node(^"TelegraphCircle") as Node2D
	var line := turret.get_node(^"TelegraphLine") as Line2D
	var saw_charge := false
	for i in 120:
		await wait_physics_frames(1)
		if turret.rules != null and turret.rules.is_charging():
			saw_charge = true
			break
	assert_true(saw_charge)
	await wait_physics_frames(1)
	assert_true(glow.visible, "the eye lights up")
	assert_true(line.visible, "the aim line shows where")
	assert_gt(line.points[1].x, 0.0, "towards the player")
	assert_eq((turret.get_node(^"Sprite") as AnimatedSprite2D).animation, &"attack")


func test_turret_can_be_destroyed_and_drops_little_gold() -> void:
	var turret := _turret(Vector2.ZERO, 10)
	watch_signals(turret)
	await wait_physics_frames(2)
	assert_almost_eq(turret.health.get_max_health(), 12.0 * EnemyScaling.health_multiplier(10, false), 0.01)
	assert_eq(turret.get_knockback_resistance(), 1.0, "no knockback")
	assert_false(turret.uses_tactics(), "no group tactics")
	var damage := DamageData.new()
	damage.amount = 100.0
	turret.hurtbox.receive_hit(damage)
	assert_true(turret.is_dead())
	assert_signal_emitted(turret, "died")
	assert_eq((load(CRYPT_TURRET) as EnemyData).gold_drop, 1, "a coin at most")


func test_turret_emerges_before_it_shoots() -> void:
	var player := _player(Vector2(150, 0))
	var turret := _turret(Vector2.ZERO)
	turret.begin_emerge(0.3, 0.3)
	assert_true(turret.is_hidden_in_source())
	await wait_seconds(0.4)
	assert_true(turret.is_emerging())
	assert_false(turret.get_node(^"TelegraphLine").visible)
	await wait_seconds(0.6)
	assert_false(turret.is_emerging())
	assert_eq(turret.get_aim_target(), player)


func test_every_biome_has_its_turret() -> void:
	var ids := {&"crypt": &"bone_turret", &"slime_grotto": &"slime_spitter", &"shadow_realm": &"shadow_eye", &"ember_forge": &"ember_cauldron"}
	for biome: StringName in ids:
		var data := TurretPlacement.data_for_biome(biome)
		assert_not_null(data, String(biome))
		assert_eq(data.id, ids[biome])
		assert_true(Turret.is_turret_data(data))
		assert_eq(data.move_speed, 0.0, "stationary")
		assert_eq(NetEnemies.data_for(data.id), data, "network clients find the type by id")
		var frames := TurretArt.placeholder_frames(data)
		for animation in [&"idle", &"walk", &"attack", &"death"]:
			assert_true(frames.has_animation(animation), "%s: %s" % [data.id, animation])
		assert_gt(frames.get_frame_count(&"attack"), data.strike_frame, "strike frame inside the strip")
	assert_eq(TurretPlacement.data_for_biome(&"unknown").id, &"bone_turret")


# --- TurretPlacement ---

func test_turret_chance_grows_with_depth_and_starts_at_room_four() -> void:
	assert_eq(TurretPlacement.get_chances(3), Vector2.ZERO)
	var rng := RandomNumberGenerator.new()
	for i in 50:
		assert_eq(TurretPlacement.roll_count(3, rng), 0, "never before room 4")
	assert_gt(TurretPlacement.get_chances(4).x, 0.0)
	assert_eq(TurretPlacement.get_chances(4).y, 0.0, "one turret at most early on")
	assert_gt(TurretPlacement.get_chances(30).x, TurretPlacement.get_chances(15).x)
	var counts := {0: 0, 1: 0, 2: 0}
	rng.seed = 7
	for i in 2000:
		counts[TurretPlacement.roll_count(30, rng)] += 1
	var share := float(counts[1] + counts[2]) / 2000.0
	assert_almost_eq(share, TurretPlacement.get_chances(30).x, 0.04)
	assert_gt(counts[2], 0, "two turrets deeper down")


## Plain 12 x 8 room: entrance at the bottom (5, 7), exit at the top (6, 0), a 1-tile passage
## through an inner wall in column 8.
func _room_tiles() -> Dictionary:
	var walkable: Dictionary[Vector2i, bool] = {}
	for y in 8:
		for x in 12:
			if x == 8 and y != 4:
				continue
			walkable[Vector2i(x, y)] = true
	return walkable


func test_spots_stand_at_walls_away_from_doors_and_never_in_the_way() -> void:
	var walkable: Dictionary[Vector2i, bool] = _room_tiles()
	var free := walkable.duplicate()
	var doors: Array[Vector2i] = [Vector2i(5, 7), Vector2i(6, 0)]
	var pits: Dictionary[Vector2i, bool] = {}
	var rng := RandomNumberGenerator.new()
	for seed_value in 40:
		rng.seed = seed_value
		var spots := TurretPlacement.pick_tiles(free, walkable, pits, doors, [] as Array[Vector2i], 2, rng)
		assert_between(spots.size(), 1, 2)
		for spot in spots:
			assert_gt(TurretPlacement.count_walls(spot, walkable, pits), 0, "%s at a wall" % spot)
			for door in doors:
				assert_gte(Vector2(spot - door).length(), TurretPlacement.DOOR_CLEARANCE, "%s away from the doors" % spot)
			assert_ne(spot, Vector2i(8, 4), "not in the passage")
			assert_true(TurretPlacement.keeps_way(spot, walkable))
		if spots.size() == 2:
			assert_gte(Vector2(spots[0] - spots[1]).length(), TurretPlacement.SPACING)


func test_way_check_rejects_tiles_that_cut_a_path() -> void:
	var walkable: Dictionary[Vector2i, bool] = _room_tiles()
	assert_false(TurretPlacement.keeps_way(Vector2i(8, 4), walkable), "the passage tile")
	assert_false(TurretPlacement.keeps_way(Vector2i(7, 4), walkable), "right in front of the passage")
	assert_true(TurretPlacement.keeps_way(Vector2i(0, 0), walkable), "a corner")
	assert_true(TurretPlacement.keeps_way(Vector2i(3, 0), walkable), "along the north wall")
	assert_false(TurretPlacement.is_wall_spot(Vector2i(8, 4), walkable, {} as Dictionary[Vector2i, bool]), "one-tile passage")
	assert_false(TurretPlacement.is_wall_spot(Vector2i(4, 4), walkable, {} as Dictionary[Vector2i, bool]), "middle of the room")


func test_pits_are_no_walls_and_avoid_tiles_are_kept_free() -> void:
	var walkable: Dictionary[Vector2i, bool] = {}
	for y in 6:
		for x in 10:
			walkable[Vector2i(x, y)] = true
	var pits: Dictionary[Vector2i, bool] = {}
	for x in 10:
		pits[Vector2i(x, 6)] = true
	assert_eq(TurretPlacement.count_walls(Vector2i(4, 5), walkable, pits), 0, "an abyss edge is no wall")
	var rng := RandomNumberGenerator.new()
	var avoid: Array[Vector2i] = [Vector2i(0, 0), Vector2i(9, 0)]
	for seed_value in 30:
		rng.seed = seed_value
		for spot in TurretPlacement.pick_tiles(walkable.duplicate(), walkable, pits, [] as Array[Vector2i], avoid, 2, rng):
			assert_ne(spot.y, 5, "not at the abyss")
			for tile in avoid:
				assert_gte(Vector2(spot - tile).length(), TurretPlacement.SOURCE_CLEARANCE)


# --- TurretPlacement in a real room ---

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")


func _hall(room_index: int, arena: bool, dungeon_seed: int) -> RoomController:
	var room := HALL.instantiate() as RoomController
	for kind in RoomSequence.RoomKind.values():
		if (kind == RoomSequence.RoomKind.ARENA) == arena:
			room.room_kind = kind
			break
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = dungeon_seed
	room.setup(room_index, RoomSequence.RoomType.COMBAT, -1, false, context)
	var spawner := room.get_node("EnemySpawner") as EnemySpawner
	spawner.biomes = [] as Array[BiomeData]
	spawner.extra_types = [] as Array[EnemyData]
	spawner.enemy_types = [SKELETON] as Array[EnemyData]
	spawner.spawn_weights = [1.0] as Array[float]
	var group := EncounterGroup.new()
	group.allow_elites = false
	spawner.encounter_group = group
	add_child_autofree(room)
	return room


func test_populate_places_tracked_turrets_in_a_plain_combat_room() -> void:
	var room: RoomController = null
	for dungeon_seed in range(1, 40):
		var candidate := _hall(30, false, dungeon_seed)
		if TurretPlacement.roll_count(30, TurretPlacement.rng_for(candidate)) > 0:
			room = candidate
			break
		candidate.queue_free()
	assert_not_null(room, "some seed brings turrets")
	if room == null:
		return
	room.start_encounter()
	var before := room.get_alive_enemy_count()
	var turrets := TurretPlacement.populate(room)
	assert_between(turrets.size(), 1, TurretPlacement.MAX_TURRETS)
	assert_eq(room.get_alive_enemy_count(), before + turrets.size(), "they count for clearing the room")
	var doors: Array[Vector2i] = [room.tiles.get_entrance_inside_tile()]
	doors.append_array(room.tiles.get_exit_inside_tiles())
	for turret: Enemy in turrets:
		assert_true(turret is Turret)
		assert_eq(turret.get_parent(), room.enemy_container)
		assert_true(turret.is_hidden_in_source(), "comes out of the ground")
		var tile := RoomTiles.local_to_tile(room.tiles.to_local(turret.global_position))
		assert_true(room.tiles.is_navigation_blocked(tile), "others walk around it")
		for door in doors:
			assert_gte(Vector2(tile - door).length(), TurretPlacement.DOOR_CLEARANCE, "not at a door")
	var tile := RoomTiles.local_to_tile(room.tiles.to_local(turrets[0].global_position))
	turrets[0].health.take_damage(INF)
	assert_eq(room.get_alive_enemy_count(), before + turrets.size() - 1)
	await wait_seconds(Enemy.DEATH_DISSOLVE_TIME + Enemy.DEATH_ANIMATION_MAX_TIME + 0.2)
	assert_false(room.tiles.is_navigation_blocked(tile), "the tile is free again")


func test_no_turrets_early_or_in_an_arena() -> void:
	assert_false(TurretPlacement.can_have_turrets(_hall(3, false, 1)), "before room 4")
	assert_false(TurretPlacement.can_have_turrets(_hall(30, true, 1)), "not in an arena")
	assert_true(TurretPlacement.can_have_turrets(_hall(30, false, 1)))
	var wager := _hall(30, false, 1)
	assert_not_null(WagerAltar.attach_to(wager, 0.5))
	assert_false(TurretPlacement.can_have_turrets(wager), "not in a room with a wager altar")
	var a := TurretPlacement.rng_for(_hall(30, false, 5)).randi()
	var b := TurretPlacement.rng_for(_hall(30, false, 5)).randi()
	assert_eq(a, b, "same seed and room, same draw")

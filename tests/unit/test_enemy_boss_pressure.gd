extends GutTest
## Lava balls and stomp of the ember golem (BossPressure; playtest #a8a87397: kiting with the bow
## around the lava trench cost nothing). Timing, aiming and fairness rules, and the pieces in play.

const ENEMY_SCENE_PATH := "res://enemies/enemy_base.tscn"
const PLAYER_SCENE_PATH := "res://player/player.tscn"
const EMBER_GOLEM := "res://enemies/data/boss_ember_golem.tres"
const TEST_SAVE_PATH := "user://test_enemy_boss_pressure.cfg"

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
		if node is Enemy or node is Projectile or node is Blast or node is LavaPool:
			node.queue_free()


func _golem() -> EnemyData:
	return load(EMBER_GOLEM) as EnemyData


## A stand-in player: a plain Node2D in the tree counts as a living target.
func _dummy(at: Vector2) -> Node2D:
	var node: Node2D = add_child_autofree(Node2D.new())
	node.global_position = at
	return node


func _spawn_player(at: Vector2) -> Player:
	var player: Player = add_child_autofree((load(PLAYER_SCENE_PATH) as PackedScene).instantiate())
	player.global_position = at
	player.health.reset(999.0)
	return player


func test_only_bosses_with_pressure_data_get_one() -> void:
	assert_not_null(BossPressure.create(_golem()))
	assert_null(BossPressure.create(load("res://enemies/data/boss_bone_king.tres")))
	assert_null(BossPressure.create(load("res://enemies/data/golem.tres")), "the normal golem stays as it is")
	assert_null(BossPressure.create(null))


func test_lava_balls_come_more_often_the_longer_nobody_is_near() -> void:
	var data := _golem()
	var pressure := BossPressure.create(data)
	var far := [_dummy(Vector2(400, 0))]
	pressure.tick(0.1, Vector2.ZERO, far)
	assert_almost_eq(pressure.lob_interval(1), data.lob_interval, 0.05)
	for i in 30:
		pressure.tick(data.lob_ramp_time / 20.0, Vector2.ZERO, far)
	assert_almost_eq(pressure.lob_interval(1), data.lob_interval_min, 0.001, "down to the minimum after the ramp")
	assert_true(pressure.lob_interval(2) <= pressure.lob_interval(1), "phase two not slower")
	assert_true(pressure.lob_interval(2) >= BossPressure.MIN_WARNING)
	var near := [_dummy(Vector2(100, 0))]
	pressure.tick(0.1, Vector2.ZERO, near)
	assert_eq(pressure.far_time, 0.0, "a player in melee reach resets the ramp")
	assert_almost_eq(pressure.lob_interval(1), data.lob_interval, 0.001)


func test_lava_balls_go_at_the_farthest_player_out_of_reach() -> void:
	var pressure := BossPressure.create(_golem())
	var near := _dummy(Vector2(100, 0))
	var mid := _dummy(Vector2(0, 300))
	var far := _dummy(Vector2(-500, 0))
	var players := [near, mid, far]
	pressure.tick(0.1, Vector2.ZERO, players)
	assert_null(pressure.lob_target(Vector2.ZERO, players), "not before the first delay")
	pressure.tick(BossPressure.FIRST_LOB_DELAY, Vector2.ZERO, players)
	assert_eq(pressure.lob_target(Vector2.ZERO, players), far)
	pressure.lob_started(1)
	assert_null(pressure.lob_target(Vector2.ZERO, players), "the timer restarts with the throw")


func test_no_lava_balls_while_everybody_is_near() -> void:
	var pressure := BossPressure.create(_golem())
	var players := [_dummy(Vector2(120, 0))]
	pressure.tick(BossPressure.FIRST_LOB_DELAY + 1.0, Vector2.ZERO, players)
	assert_null(pressure.lob_target(Vector2.ZERO, players))


func test_stomp_only_when_somebody_crowds_the_boss() -> void:
	var pressure := BossPressure.create(_golem())
	assert_false(pressure.wants_stomp(Vector2.ZERO, [_dummy(Vector2(400, 0))], 1))
	var players := [_dummy(Vector2(60, 0))]
	assert_true(pressure.wants_stomp(Vector2.ZERO, players, 1))
	pressure.stomp_started(1)
	assert_false(pressure.wants_stomp(Vector2.ZERO, players, 1), "cooldown")
	pressure.tick(_golem().stomp_cooldown + 0.1, Vector2.ZERO, players)
	assert_true(pressure.wants_stomp(Vector2.ZERO, players, 1))


func test_warnings_and_stuns_stay_fair() -> void:
	var pressure := BossPressure.create(_golem())
	for phase in [1, 2]:
		assert_true(pressure.stomp_stun(phase) <= BossPressure.MAX_STUN, "stun at most 0.5 s")
		assert_true(pressure.stomp_stun(phase) > 0.0)
		assert_true(pressure.flight_time(phase) >= 0.5, "landing circles warn at least 0.5 s")
	assert_true(pressure.stomp_radius(2) > pressure.stomp_radius(1), "phase two reaches further")
	# Deepest telegraph scaling (0.7) and the phase-two factor (0.9) still leave 0.5 s.
	assert_true(pressure.stomp_warning(0.7 * BossRules.ENRAGE_TELEGRAPH_FACTOR) >= 0.5)


func test_lob_spots_and_lead() -> void:
	var spots := BossPressure.lob_spots(Vector2(100, 100), 4, 80.0, 3)
	assert_eq(spots.size(), 4)
	assert_eq(spots[0], Vector2(100, 100), "the first ball on the aim point")
	for i in range(1, 4):
		assert_almost_eq(spots[i].distance_to(Vector2(100, 100)), 80.0, 0.01)
	assert_eq(BossPressure.lead_point(Vector2(10, 0), Vector2(100, 0), 1.0), Vector2(10 + 100 * BossPressure.LEAD_SHARE, 0))
	var data := _golem()
	assert_eq(BossPressure.lob_count(data, 0, 1), data.lob_count)
	assert_eq(BossPressure.lob_count(data, 0, 2), data.lob_count + data.enrage_lob_count)
	assert_eq(BossPressure.lob_count(data, 2, 1), data.lob_count + 2 * BossPressure.LOBS_PER_TIER)


func test_pressure_measures_player_velocity() -> void:
	var pressure := BossPressure.create(_golem())
	var runner := _dummy(Vector2(400, 0))
	for i in 60:
		runner.global_position += Vector2(3, 0)
		pressure.tick(1.0 / 60.0, Vector2.ZERO, [runner])
	assert_almost_eq(pressure.get_velocity(runner).x, 180.0, 5.0)


func test_golem_throws_lava_balls_at_a_distant_player() -> void:
	var golem: Enemy = (load(ENEMY_SCENE_PATH) as PackedScene).instantiate()
	golem.data = _golem()
	golem.apply_scaling(60, false)
	add_child_autofree(golem)
	golem.global_position = Vector2(200, 200)
	var player := _spawn_player(Vector2(650, 200))
	var seen := {}
	golem.ability_used.connect(func(_e: Enemy, ability: StringName) -> void: seen[ability] = true)
	var lobbed: Array[Blast] = []
	for i in 60 * 5:
		await wait_physics_frames(1)
		# The player keeps its distance.
		player.global_position = Vector2(650, 200 + 60.0 * sin(i / 30.0))
		for node in get_children():
			if node is Blast and (node as Blast).is_lobbed() and not lobbed.has(node):
				lobbed.append(node)
		if seen.has(&"lava_ball") and not lobbed.is_empty():
			break
	assert_true(seen.has(&"lava_ball"), "the golem throws lava balls at a player who keeps away")
	assert_false(lobbed.is_empty(), "the balls land as lobbed blasts")
	for blast in lobbed:
		if is_instance_valid(blast):
			assert_true(blast.delay >= BossPressure.MIN_WARNING, "warning circle at least 0.5 s")
			assert_true(blast.pool_time > 0.0, "leaves a lava pool")
			assert_true(blast.tags.has(&"lava"))


func test_stomp_stuns_briefly_and_a_dash_avoids_it() -> void:
	var player := _spawn_player(Vector2(300, 300))
	await wait_physics_frames(2)
	var blast := Blast.spawn(self, player.global_position, 120.0, 1.0)
	blast.stun_duration = 0.4
	blast.look = Blast.LOOK_STOMP
	await wait_physics_frames(3)
	assert_true(player.is_stunned(), "the stomp stuns")
	await wait_seconds(1.2)
	assert_false(player.is_stunned(), "only briefly")
	var dodger := _spawn_player(Vector2(600, 300))
	await wait_physics_frames(2)
	assert_true(dodger.try_dash(Vector2.RIGHT))
	var health := dodger.health.get_health()
	var dodged := Blast.spawn(self, dodger.global_position, 120.0, 1.0)
	dodged.stun_duration = 0.4
	await wait_physics_frames(3)
	assert_false(dodger.is_stunned(), "a dash through the stomp avoids the stun")
	assert_eq(dodger.health.get_health(), health, "and the damage")


func test_lava_pool_burns_who_stands_in_it_and_goes_out() -> void:
	var player := _spawn_player(Vector2(300, 300))
	await wait_physics_frames(2)
	var start := player.health.get_health()
	var pool := LavaPool.spawn(self, player.global_position, 40.0, 1.5, 1.0, PhysicsLayers.PLAYER_HURTBOX, null)
	await wait_physics_frames(int(LavaPool.ARM_TIME * 60.0) - 6)
	assert_eq(player.health.get_health(), start, "time to step out first")
	await wait_seconds(0.6)
	assert_true(player.health.get_health() < start, "then it burns")
	await wait_seconds(1.2)
	assert_false(is_instance_valid(pool), "goes out after its time")


func test_lava_pool_on_a_client_is_only_a_picture() -> void:
	var pool := LavaPool.spawn(self, Vector2(300, 300), 40.0, 1.0, 0.0, 0, null)
	await wait_physics_frames(2)
	assert_false(pool.is_burning())

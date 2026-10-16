extends GutTest
## The side-view turret (M5 round 3): it stands on a floor, hangs from rock or sits on a wall, sees a
## player only without rock in between, lights up before it fires a slow orb (TurretRules telegraph),
## a hit slows the running but never the jump, weapons destroy it, and a client's turret only shows
## what the host decided (no own shots).

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const STEP := 1.0 / 60.0
const OPEN := [
	"##############",
	"#............#",
	"#............#",
	"#S.....T....D#",
	"##############",
]
const BLOCKED := [
	"##############",
	"#....#.......#",
	"#....#.......#",
	"#S...#.T....D#",
	"##############",
]
const HANGING := [
	"##############",
	"#......T.....#",
	"#............#",
	"#S..........D#",
	"##############",
]

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_side_turret_save.cfg"


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	SaveManager.save_path = _old_save_path


func after_each() -> void:
	HitStop.reset()
	await wait_process_frames(1)


func _segment(plan: Array, remote := false) -> SideSegment:
	var layout := SideLayout.parse(PackedStringArray(plan), &"turret_test")
	layout.biome_id = &"crypt"
	var segment := SideSegment.new()
	segment.setup(layout, 1, null, 11)
	add_child_autofree(segment)
	segment.global_position = Vector2(0, 9000)
	for turret in segment.get_turrets():
		turret.remote_controlled = remote
	return segment


func _player(segment: SideSegment) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.is_local = false
	add_child_autofree(player)
	segment.add_player(player)
	player.health.reset(999.0)
	return player


func _projectiles(segment: SideSegment) -> Array[Projectile]:
	var found: Array[Projectile] = []
	for child in segment.get_children():
		if child is Projectile and not child.is_queued_for_deletion():
			found.append(child)
	return found


func _wait_for_shot(turret: SideTurret, seconds: float) -> void:
	var frames := 0
	while turret.shots == 0 and frames < int(seconds * 60.0):
		await wait_physics_frames(1)
		frames += 1


func test_turret_lights_up_then_fires_a_slow_orb_at_the_player() -> void:
	var segment := _segment(OPEN)
	var player := _player(segment)
	var turret := segment.get_turrets()[0]
	assert_eq(turret.normal, Vector2.UP, "stands on the floor")
	watch_signals(turret)
	await _wait_for_shot(turret, 4.0)
	assert_eq(turret.get_target(), player, "aims at the player in sight")
	assert_signal_emitted(turret, "charge_started", "the eye lit up first")
	assert_signal_emitted(turret, "fired")
	assert_eq(turret.shots, 1)
	var shots := _projectiles(segment)
	assert_eq(shots.size(), 1, "one orb in the segment")
	if shots.is_empty():
		return
	assert_eq(shots[0].collision_mask, PhysicsLayers.PLAYER_HURTBOX, "it hits players only")
	assert_almost_eq(shots[0].speed, SideRules.TURRET_SHOT_SPEED, 0.01, "slow orb")
	assert_lt(shots[0].direction.x, 0.0, "towards the player on the left")
	assert_lt(absf(shots[0].direction.y), 0.5, "about horizontal on the same floor")


func test_rock_blocks_the_sight() -> void:
	var segment := _segment(BLOCKED)
	_player(segment)
	var turret := segment.get_turrets()[0]
	await wait_physics_frames(200)
	assert_null(turret.get_target(), "no target behind the rock")
	assert_eq(turret.shots, 0)


func test_hanging_turret_aims_down_never_into_its_rock() -> void:
	var segment := _segment(HANGING)
	var player := _player(segment)
	var turret := segment.get_turrets()[0]
	assert_eq(turret.normal, Vector2.DOWN, "hangs from the ceiling")
	assert_almost_eq(turret.get_muzzle_position().y, turret.global_position.y + SideTurret.MUZZLE_DISTANCE, 0.01, "the eye is below the mount")
	var above := Node2D.new()
	add_child_autofree(above)
	above.global_position = turret.global_position + Vector2(-100, -200)
	assert_gte(turret.aim_at(above).y, 0.0, "never shoots up into the rock")
	await _wait_for_shot(turret, 4.0)
	assert_eq(turret.shots, 1, "fires down at the player")
	assert_gt(_projectiles(segment)[0].direction.y if not _projectiles(segment).is_empty() else 1.0, 0.0)
	assert_true(player.is_alive())


func test_a_hit_slows_running_but_not_the_jump() -> void:
	var segment := _segment(OPEN)
	var player := _player(segment)
	await wait_physics_frames(3)
	var base_speed := player.move_speed
	var damage := DamageData.new()
	damage.amount = 0.25
	damage.hit_id = DamageData.next_hit_id()
	damage.slow_factor = TurretRules.SLOW_FACTOR
	damage.slow_duration = TurretRules.SLOW_DURATION
	player.hurtbox.receive_hit(damage)
	assert_almost_eq(player.move_speed, base_speed * TurretRules.SLOW_FACTOR, 0.5, "running is slowed")
	var jump := {"just": true}
	player.side_motion.input_source = func() -> PlayerSideMotion.SideInput:
		var input := PlayerSideMotion.SideInput.new()
		input.jump_just_pressed = jump["just"]
		input.jump_pressed = true
		jump["just"] = false
		return input
	player.side_motion.physics_step(STEP, true)
	assert_lt(player.velocity.y, -SideRules.JUMP_VELOCITY * 0.9, "the jump keeps its full height")


func test_weapons_destroy_it_without_gold() -> void:
	var segment := _segment(OPEN)
	var turret := segment.get_turrets()[0]
	watch_signals(turret)
	watch_signals(EventBus)
	var damage := DamageData.new()
	damage.amount = 999.0
	damage.hit_id = DamageData.next_hit_id()
	turret.hurtbox.receive_hit(damage)
	assert_true(turret.is_dead())
	assert_signal_emitted(turret, "died")
	assert_signal_emitted(EventBus, "enemy_damaged", "kill effects see the hit")
	assert_eq(turret.hurtbox.collision_layer, PhysicsLayers.ENEMY_HURTBOX)
	assert_false(turret.is_charging())
	# Counted through the signals: the turret frees itself after its death animation, possibly before
	# the next line runs when the frames are slow (full test run).
	var after_death := {"shots": 0, "charges": 0}
	turret.fired.connect(func(_t: SideTurret, _aim: Vector2) -> void: after_death["shots"] += 1)
	turret.charge_started.connect(func(_t: SideTurret, _aim: Vector2) -> void: after_death["charges"] += 1)
	await wait_physics_frames(20)
	assert_eq(after_death["shots"], 0, "a dead turret never fires")
	assert_eq(after_death["charges"], 0, "nor lights up")
	for child in segment.get_children():
		assert_false(child is GoldPickup, "no gold: the coins are the reward")
	await wait_seconds(SideTurret.DEATH_TIME + 0.1)
	assert_false(is_instance_valid(turret), "the rubble is gone after the death animation")


func test_a_remote_turret_only_shows_the_hosts_decisions() -> void:
	var segment := _segment(OPEN, true)
	_player(segment)
	var turret := segment.get_turrets()[0]
	await wait_physics_frames(200)
	assert_eq(turret.shots, 0, "a client's turret never decides a shot")
	assert_false(turret.is_charging())
	turret.apply_remote_charge(Vector2.LEFT)
	assert_true(turret.is_charging(), "the telegraph shows")
	assert_eq(turret.rules.aim, Vector2.LEFT)
	turret.apply_remote_fire(Vector2.LEFT)
	assert_false(turret.is_charging())
	assert_eq(_projectiles(segment).size(), 0, "the orb comes from the host (NetEnemies), not from here")
	turret.apply_remote_death()
	assert_true(turret.is_dead())


func test_rules_use_the_side_numbers_and_scale_with_depth() -> void:
	var early := SideTurret.rules_for(1)
	assert_almost_eq(early.sight_range, SideRules.TURRET_SIGHT_TILES * SideRules.TILE, 0.01)
	assert_almost_eq(early.charge_time, SideRules.TURRET_CHARGE_TIME, 0.01)
	var deep := SideTurret.rules_for(60)
	assert_lte(deep.get_shot_interval(), early.get_shot_interval(), "faster deeper down")
	assert_gte(deep.cooldown, SideRules.TURRET_COOLDOWN * TurretRules.MIN_COOLDOWN_FACTOR - 0.001)
	for biome in [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]:
		assert_not_null(SideTurret.data_for(biome), "%s has a turret look" % biome)

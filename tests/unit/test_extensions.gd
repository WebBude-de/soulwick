extends GutTest
## Extensions from 2026-10-13: darkness, elites, bosses, stun/blind, hitstop (D-062 .. D-070).

const PLAYER_SCENE := preload("res://player/player.tscn")


func test_extra_dark_rooms() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	assert_false(RoomSequence.roll_extra_dark(3, RoomSequence.RoomType.COMBAT_UPGRADE, rng), "never before room 6")
	assert_true(RoomSequence.roll_extra_dark(45, RoomSequence.RoomType.BOSS, rng), "the shadow realm is always dark")
	assert_false(RoomSequence.roll_extra_dark(9, RoomSequence.RoomType.SPECIAL, rng), "special rooms are never extra dark")
	var dark := 0
	for i in 4000:
		if RoomSequence.roll_extra_dark(7, RoomSequence.RoomType.COMBAT, rng):
			dark += 1
	assert_almost_eq(dark / 4000.0, 0.25, 0.03)


func test_elite_chance_grows_per_block() -> void:
	assert_eq(EnemySpawner.get_elite_chance(5), 0.0, "no elites before room 6")
	assert_almost_eq(EnemySpawner.get_elite_chance(6), 0.14, 0.0001)
	assert_almost_eq(EnemySpawner.get_elite_chance(500), 0.5, 0.0001, "capped")
	assert_gt(EnemySpawner.get_elite_chance(40), EnemySpawner.get_elite_chance(6))


func test_boss_per_boss_room() -> void:
	var spawner: EnemySpawner = autofree(EnemySpawner.new())
	var bone: EnemyData = load("res://enemies/data/boss_bone_king.tres")
	var queen: EnemyData = load("res://enemies/data/boss_slime_queen.tres")
	var lord: EnemyData = load("res://enemies/data/boss_shadow_lord.tres")
	spawner.bosses.assign([bone, queen, lord])
	assert_eq(spawner.get_boss_for_room(15), bone)
	assert_eq(spawner.get_boss_for_room(30), queen)
	assert_eq(spawner.get_boss_for_room(45), lord)
	assert_eq(spawner.get_boss_for_room(60), bone, "bosses take turns endlessly")


func test_stun_and_blind_only_on_effective_hits() -> void:
	var player: Player = add_child_autofree(PLAYER_SCENE.instantiate())
	watch_signals(player)
	var hit := DamageData.new()
	hit.amount = 1.0
	hit.stun_duration = 0.8
	hit.blind_duration = 4.0

	player.hurtbox.set_invulnerable(&"test", true)
	player.hurtbox.receive_hit(hit.duplicate_for_target())
	assert_false(player.is_stunned(), "blocked hits do not stun (D-017)")
	assert_signal_not_emitted(player, "blinded")

	player.hurtbox.set_invulnerable(&"test", false)
	player.hurtbox.receive_hit(hit.duplicate_for_target())
	assert_true(player.is_stunned(), "effective hit stuns")
	assert_signal_emitted(player, "blinded")


func test_hitstop_always_restores_time_scale() -> void:
	HitStop.trigger(get_tree().root, 0.02)
	HitStop.trigger(get_tree().root, 0.04)
	assert_lt(Engine.time_scale, 1.0)
	await wait_seconds(0.2, "wait for the release timers")
	assert_eq(Engine.time_scale, 1.0)


func test_spike_trap_only_targets_the_player() -> void:
	var trap: SpikeTrap = add_child_autofree(SpikeTrap.new())
	await wait_physics_frames(2)
	var hitbox: Hitbox = null
	for child in trap.get_children():
		if child is Hitbox:
			hitbox = child
	assert_not_null(hitbox)
	assert_eq(hitbox.collision_mask, PhysicsLayers.PLAYER_HURTBOX)

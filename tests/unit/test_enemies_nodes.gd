extends GutTest
## Enemy nodes: boss phase two (roar, invulnerability), champions, badges, hint cards and the
## toxic puddle slow.

const ENEMY_SCENE_PATH := "res://enemies/enemy_base.tscn"
const PLAYER_SCENE_PATH := "res://player/player.tscn"
const TEST_SAVE_PATH := "user://test_enemies_nodes.cfg"

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
	# Summoned minions and spawned effects are not autofreed.
	for node in get_children():
		if node is Enemy or node is Projectile or node is Blast:
			node.queue_free()


func _spawn(path: String, room := 15, miniboss := false, elite := Enemy.Elite.NONE) -> Enemy:
	var enemy: Enemy = (load(ENEMY_SCENE_PATH) as PackedScene).instantiate()
	enemy.data = load(path)
	enemy.apply_scaling(room, miniboss)
	enemy.make_elite(elite)
	add_child_autofree(enemy)
	return enemy


func test_boss_roars_into_phase_two() -> void:
	var boss := _spawn("res://enemies/data/boss_bone_king.tres")
	watch_signals(boss)
	await wait_physics_frames(2)
	assert_eq(boss.phase, 1)
	boss.health.take_damage(boss.health.get_max_health() * 0.3)
	await wait_physics_frames(2)
	assert_eq(boss.phase, 1, "above half health")
	boss.health.take_damage(boss.health.get_max_health() * 0.25)
	await wait_physics_frames(2)
	assert_eq(boss.phase, 2)
	assert_signal_emitted_with_parameters(boss, "phase_changed", [boss, 2])
	assert_true(boss.is_roaring())
	assert_true(boss.hurtbox.is_invulnerable(), "invulnerable while roaring")
	await wait_seconds(BossRules.ROAR_TIME + 0.2)
	assert_false(boss.is_roaring())
	assert_false(boss.hurtbox.is_invulnerable())
	assert_signal_emit_count(boss, "phase_changed", 1, "only once")


func test_normal_enemies_have_no_phases() -> void:
	var slime := _spawn("res://enemies/data/slime.tres", 3)
	watch_signals(slime)
	await wait_physics_frames(1)
	slime.health.take_damage(slime.health.get_max_health() * 0.6)
	await wait_physics_frames(3)
	assert_eq(slime.phase, 1)
	assert_signal_not_emitted(slime, "phase_changed")


func test_champion_gets_own_data_badges_and_phases() -> void:
	var base: EnemyData = load("res://enemies/data/slime.tres")
	var champion := _spawn("res://enemies/data/slime.tres", 10, true, Enemy.Elite.ARMORED)
	await wait_physics_frames(1)
	assert_true(champion.is_champion())
	assert_ne(champion.data, base, "champion copy")
	assert_eq(champion.data.special, EnemyData.Special.LEAP_SLAM)
	assert_eq(base.special, EnemyData.Special.NONE, "shared resource untouched")
	assert_has(champion.get_badges(), EnemyBadges.CHAMPION)
	assert_has(champion.get_badges(), EnemyBadges.ARMORED)
	champion.health.take_damage(champion.health.get_max_health() * 0.6)
	await wait_physics_frames(2)
	assert_eq(champion.phase, 2, "champions enrage too")


func test_bosses_show_no_head_badges() -> void:
	var boss := _spawn("res://enemies/data/boss_shadow_lord.tres", 45)
	await wait_physics_frames(1)
	assert_eq(boss.get_badges().size(), 0, "boss badges live in the boss bar")
	assert_has(boss.get_ability_badges(), EnemyBadges.BLIND)


func test_hint_card_only_once_per_type() -> void:
	var ui: DungeonUI = add_child_autofree(DungeonUI.new())
	ui.auto_enemy_hints = false
	var skeleton := _spawn("res://enemies/data/skeleton.tres", 6, false, Enemy.Elite.SWIFT)
	await wait_physics_frames(1)
	assert_false(SaveManager.is_unlocked(&"hint_skeleton"))
	ui.notice_enemy(skeleton)
	assert_true(SaveManager.is_unlocked(&"hint_skeleton"))
	assert_true(SaveManager.is_unlocked(&"hint_elite_swift"))
	assert_eq(ui._hint_queue.size(), 1, "one card shown, one queued")
	ui.notice_enemy(skeleton)
	assert_eq(ui._hint_queue.size(), 1, "seen hints are not repeated")


func test_boss_bar_shows_tier_and_phase() -> void:
	var ui: DungeonUI = add_child_autofree(DungeonUI.new())
	ui.auto_enemy_hints = false
	var boss: Enemy = (load(ENEMY_SCENE_PATH) as PackedScene).instantiate()
	boss.data = load("res://enemies/data/boss_slime_queen.tres")
	boss.apply_scaling(90, false)
	boss.set_boss_tier(1)
	add_child_autofree(boss)
	await wait_physics_frames(1)
	ui.show_boss_bar(boss)
	assert_eq(ui._boss_name.text, "Schleimkönigin II")
	assert_eq(ui._boss_phase.text, "Phase 1")
	boss.health.take_damage(boss.health.get_max_health() * 0.6)
	await wait_physics_frames(2)
	assert_string_contains(ui._boss_phase.text, "Phase 2")
	assert_false(ui._boss_marker.visible)


func test_toxic_puddle_slows_and_restores() -> void:
	var player: Player = add_child_autofree((load(PLAYER_SCENE_PATH) as PackedScene).instantiate())
	var base_speed := player.move_speed
	var puddle: ToxicPuddle = ToxicPuddle.new()
	add_child(puddle)
	puddle.global_position = player.global_position
	await wait_physics_frames(4)
	assert_true(puddle.is_slowing())
	assert_almost_eq(player.move_speed, base_speed * ToxicPuddle.SLOW_FACTOR, 0.01)
	puddle.queue_free()
	await wait_physics_frames(2)
	assert_almost_eq(player.move_speed, base_speed, 0.01, "speed restored when the puddle is gone")
	assert_false(player.has_meta(ToxicPuddle.META_BASE_SPEED))


func test_lava_crack_targets_only_the_player() -> void:
	var crack: LavaCrack = add_child_autofree(LavaCrack.new())
	await wait_physics_frames(2)
	var hitbox: Hitbox = null
	for child in crack.get_children():
		if child is Hitbox:
			hitbox = child
	assert_not_null(hitbox)
	assert_eq(hitbox.collision_mask, PhysicsLayers.PLAYER_HURTBOX)

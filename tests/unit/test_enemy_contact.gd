extends GutTest
## Boss contact damage and boss minions without ON_KILL rewards (playtest #ddb41969: standing inside
## the slime queen while her summons refilled the shield took no damage at all).

const ENEMY_SCENE_PATH := "res://enemies/enemy_base.tscn"
const PLAYER_SCENE_PATH := "res://player/player.tscn"
const SLIME_QUEEN := "res://enemies/data/boss_slime_queen.tres"
const TEST_SAVE_PATH := "user://test_enemy_contact.cfg"

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


func _spawn(path: String, room := 30) -> Enemy:
	var enemy: Enemy = (load(ENEMY_SCENE_PATH) as PackedScene).instantiate()
	enemy.data = load(path)
	enemy.apply_scaling(room, false)
	add_child_autofree(enemy)
	return enemy


func _spawn_player(at: Vector2) -> Player:
	var player: Player = add_child_autofree((load(PLAYER_SCENE_PATH) as PackedScene).instantiate())
	player.global_position = at
	player.health.reset(999.0)
	return player


func test_only_bosses_hurt_on_contact() -> void:
	assert_true(BossRules.has_contact_damage(load(SLIME_QUEEN)))
	assert_true(BossRules.has_contact_damage(load("res://enemies/data/boss_bone_king.tres")))
	assert_false(BossRules.has_contact_damage(load("res://enemies/data/slime.tres")))
	assert_false(BossRules.has_contact_damage(null))


func test_contact_damage_is_a_share_of_the_hit() -> void:
	assert_almost_eq(BossRules.contact_damage(2.5), 2.5 * BossRules.CONTACT_DAMAGE_FACTOR, 0.001)
	assert_eq(BossRules.contact_damage(0.4), DamageProcessor.MIN_DAMAGE, "never below the 0.5 step")
	assert_eq(BossRules.contact_damage(0.0), 0.0)


func test_minions_of_bosses_pay_no_kill_rewards() -> void:
	var queen: EnemyData = load(SLIME_QUEEN)
	var necromancer: EnemyData = load("res://enemies/data/necromancer.tres")
	assert_false(BossRules.minion_grants_kill_rewards(queen, true))
	assert_true(BossRules.minion_grants_kill_rewards(necromancer, true))
	assert_false(BossRules.minion_grants_kill_rewards(necromancer, false), "passed on to split children")


func test_player_inside_the_slime_queen_takes_damage() -> void:
	var boss := _spawn(SLIME_QUEEN)
	boss.global_position = Vector2(200, 200)
	# North of the boss: the body collision sits at its feet, so the player stands in the sprite.
	var spot := boss.global_position + Vector2(0, -20)
	var player := _spawn_player(spot)
	var contact_hits := [0]
	player.hurtbox.hit_received.connect(func(result: DamageResult, damage: DamageData) -> void:
		if damage.tags.has(&"contact") and result.is_effective():
			contact_hits[0] += 1)
	var start := player.health.get_health()
	for i in 60 * 3:
		# Holds its place inside the boss like a player walking into it (contact pushes out).
		player.global_position = boss.global_position + Vector2(0, -20)
		await wait_physics_frames(1)
	assert_true(boss.is_contact_active(), "contact runs while the boss fights")
	assert_gte(contact_hits[0], 2, "hurt again and again, not only on entering")
	assert_lt(player.health.get_health(), start, "standing inside the boss costs health")


func test_normal_enemy_has_no_contact_hitbox() -> void:
	var slime := _spawn("res://enemies/data/slime.tres", 5)
	await wait_physics_frames(3)
	assert_false(slime.can_touch())
	assert_false(slime.is_contact_active())


func test_no_contact_during_intro() -> void:
	var boss := _spawn(SLIME_QUEEN)
	boss.begin_intro(5.0)
	await wait_physics_frames(5)
	assert_false(boss.is_contact_active(), "passive while it speaks")
	boss.end_intro()
	await wait_physics_frames(3)
	assert_true(boss.is_contact_active())


func test_boss_minion_kill_carries_no_reward() -> void:
	var boss := _spawn(SLIME_QUEEN)
	boss.global_position = Vector2(300, 300)
	_spawn_player(Vector2(300, 420))
	var minions: Array[Enemy] = []
	boss.summoned.connect(func(minion: Enemy) -> void: minions.append(minion))
	boss._summon()
	assert_gt(minions.size(), 0, "the queen summoned")
	var rewards: Array[bool] = []
	var on_damaged := func(_enemy: Node2D, result: DamageResult, _damage: DamageData) -> void:
		if result.killed:
			rewards.append(result.grants_kill_rewards)
	EventBus.enemy_damaged.connect(on_damaged)
	var minion := minions[0]
	assert_false(minion.grants_kill_rewards)
	var damage := DamageData.new()
	damage.amount = 9999.0
	damage.hit_id = DamageData.next_hit_id()
	minion.hurtbox.receive_hit(damage)
	EventBus.enemy_damaged.disconnect(on_damaged)
	assert_eq(rewards, [false] as Array[bool], "the kill tells ON_KILL upgrades to skip it")


func test_normal_kill_still_pays_rewards() -> void:
	var slime := _spawn("res://enemies/data/slime.tres", 5)
	await wait_physics_frames(1)
	var rewards: Array[bool] = []
	var on_damaged := func(_enemy: Node2D, result: DamageResult, _damage: DamageData) -> void:
		if result.killed:
			rewards.append(result.grants_kill_rewards)
	EventBus.enemy_damaged.connect(on_damaged)
	var damage := DamageData.new()
	damage.amount = 9999.0
	damage.hit_id = DamageData.next_hit_id()
	slime.hurtbox.receive_hit(damage)
	EventBus.enemy_damaged.disconnect(on_damaged)
	assert_eq(rewards, [true] as Array[bool])

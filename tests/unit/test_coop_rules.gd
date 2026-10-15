extends GutTest
## The shared run (MP3, D-084, D-126) without a network: scaling numbers, exit rule, revive, payout,
## and the small hooks the network code uses (player revive, set HP/shield, upgrade stacks, enemy
## targets, damage numbers, purchase hook, run gold mirror, shop offers, enemy snapshots).

const TEST_SAVE_PATH := "user://test_coop_rules.cfg"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://enemies/enemy_base.tscn")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.load_game()


func after_all() -> void:
	await wait_seconds(0.2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func test_scaling_follows_the_d084_table() -> void:
	var counts := [1.0, 1.6, 2.2, 2.8]
	var normal := [1.0, 1.2, 1.4, 1.6]
	var bosses := [1.0, 1.7, 2.4, 3.1]
	for players in range(1, 5):
		assert_almost_eq(CoopRules.count_factor(players), counts[players - 1], 0.001, "count, %d players" % players)
		assert_almost_eq(CoopRules.health_factor(players, false), normal[players - 1], 0.001, "normal HP, %d players" % players)
		assert_almost_eq(CoopRules.health_factor(players, true), bosses[players - 1], 0.001, "boss HP, %d players" % players)
	assert_almost_eq(CoopRules.count_factor(0), 1.0, 0.001, "never below one player")


func test_scale_group_keeps_one_player_and_never_changes_the_original() -> void:
	assert_null(CoopRules.scale_group(null, 1), "one player: no group")
	var plain := CoopRules.scale_group(null, 2)
	assert_not_null(plain)
	assert_almost_eq(plain.count_factor, 1.6, 0.001)
	assert_almost_eq(plain.health_factor, 1.0, 0.001, "HP scales per enemy, not through the group")
	var swarm := EncounterGroup.new()
	swarm.count_factor = 1.5
	swarm.tags = [&"swarm"]
	var scaled := CoopRules.scale_group(swarm, 3)
	assert_almost_eq(scaled.count_factor, 1.5 * 2.2, 0.001)
	assert_eq(scaled.tags, swarm.tags, "theme kept")
	assert_almost_eq(swarm.count_factor, 1.5, 0.001, "the room's own group stays untouched")


func test_room_starts_when_everybody_is_in_or_the_countdown_ran_out() -> void:
	assert_true(CoopRules.should_start_room(2, 2, 0.0))
	assert_false(CoopRules.should_start_room(2, 1, 9.9))
	assert_true(CoopRules.should_start_room(2, 1, CoopRules.EXIT_COUNTDOWN))
	assert_true(CoopRules.should_start_room(0, 0, 0.0), "nobody standing: nothing to wait for")


func test_revive_needs_two_seconds_without_a_break() -> void:
	var progress := 0.0
	for i in 19:
		progress = CoopRules.revive_progress(progress, true, 0.1)
	assert_lt(progress, CoopRules.REVIVE_TIME)
	progress = CoopRules.revive_progress(progress, false, 0.1)
	assert_eq(progress, 0.0, "the helper stepped away: start again")
	for i in 21:
		progress = CoopRules.revive_progress(progress, true, 0.1)
	assert_gte(progress, CoopRules.REVIVE_TIME)


func test_payout_is_full_only_through_the_portal() -> void:
	assert_eq(CoopRules.payout_ratio(RunManager.EndReason.EXIT), 1.0)
	assert_eq(CoopRules.payout_ratio(RunManager.EndReason.DEATH), 0.5)
	assert_eq(CoopRules.payout_ratio(RunManager.EndReason.ABORT), 0.5, "host gone counts as abort (D-123)")


func test_a_downed_player_gets_up_with_two_hp() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	await wait_physics_frames(1)
	var revived := [false]
	player.revived.connect(func() -> void: revived[0] = true)
	player.health.take_damage(999.0)
	assert_true(player.is_downed())
	assert_false(player.is_alive())
	assert_false(player.is_physics_processing(), "a downed player lies still")
	player.revive(CoopRules.REVIVE_HEALTH)
	assert_true(player.is_alive())
	assert_eq(player.health.get_health(), 2.0)
	assert_true(player.is_physics_processing())
	assert_true(player.hurtbox.is_invulnerable(), "brief I-frames after getting up")
	assert_true(revived[0])
	player.revive(5.0)
	assert_eq(player.health.get_health(), 2.0, "revive does nothing to a living player")


func test_health_and_shield_take_the_hosts_values() -> void:
	var health := HealthComponent.new()
	add_child_autofree(health)
	health.reset(6.0)
	health.set_current(2.5)
	assert_eq(health.get_health(), 2.5)
	health.set_current(0.0)
	assert_eq(health.get_health(), 2.5, "set_current never kills")
	health.set_current(99.0)
	assert_eq(health.get_health(), 6.0, "capped at the maximum")
	var shield := ShieldComponent.new()
	add_child_autofree(shield)
	shield.set_current(40.0)
	assert_eq(shield.get_shield(), 40.0, "no softcap for a mirrored value")
	shield.set_current(-3.0)
	assert_eq(shield.get_shield(), 0.0)


func test_upgrade_stacks_can_be_copied_without_signals() -> void:
	var manager := UpgradeManager.new()
	manager.upgrade_pool.assign([load("res://upgrades/data/pierce.tres"), load("res://upgrades/data/double_shot.tres")])
	add_child_autofree(manager)
	var signals := [0]
	manager.upgrade_acquired.connect(func(_u: UpgradeData, _s: int) -> void: signals[0] += 1)
	var pierce := manager.upgrade_pool[0]
	manager.set_all_stacks({String(pierce.id): 2, "unknown": 0})
	assert_eq(manager.get_stacks(pierce.id), 2)
	assert_false(manager.get_all_stacks().has(&"unknown"), "zero stacks dropped")
	assert_eq(signals[0], 0, "copying stacks counts nothing twice")
	assert_eq(manager.find_upgrade(pierce.id), pierce)
	assert_null(manager.find_upgrade(&"nope"))


func test_enemies_ignore_protected_players() -> void:
	var near := PLAYER_SCENE.instantiate() as Player
	var far := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(near)
	add_child_autofree(far)
	near.global_position = Vector2(10, 0)
	far.global_position = Vector2(300, 0)
	await wait_physics_frames(1)
	assert_eq(EnemyTargeting.choose([near, far], Vector2.ZERO, null), near)
	near.set_protected(&"menu", true)
	assert_eq(EnemyTargeting.choose([near, far], Vector2.ZERO, near), far, "a menu hides the player (D-085)")
	far.health.take_damage(999.0)
	assert_null(EnemyTargeting.choose([near, far], Vector2.ZERO, null), "downed and protected: no target")
	near.set_protected(&"menu", false)


func test_damage_numbers_show_every_hit_in_single_player() -> void:
	assert_true(DamageNumber.shows_hit_by(null))


func test_purchase_hook_replaces_the_local_purchase() -> void:
	var economy := EconomySystem.new()
	economy.config = load("res://economy/data/economy_config.tres") if ResourceLoader.exists("res://economy/data/economy_config.tres") else EconomyConfig.new()
	add_child_autofree(economy)
	var calls := [0]
	economy.purchase_hook = func(_offer: ShopOffer, _player: Player, _upgrades: UpgradeManager, _slot: int) -> bool:
		calls[0] += 1
		return false
	var offer := ShopOffer.new()
	assert_false(economy.try_purchase(offer, null, null))
	assert_eq(calls[0], 1, "the network decides (MP3)")
	assert_false(offer.sold)


func test_run_gold_mirrors_the_host() -> void:
	RunManager.start_run()
	var seen := [-1]
	var on_gold := func(gold: int) -> void: seen[0] = gold
	RunManager.run_gold_changed.connect(on_gold)
	RunManager.sync_from_host(42, 50, 3)
	assert_eq(RunManager.get_run_gold(), 42)
	assert_eq(RunManager.get_run_gold_earned(), 50)
	assert_eq(RunManager.get_run_crystals(), 3)
	assert_eq(seen[0], 42)
	RunManager.sync_room(4)
	assert_eq(RunManager.get_current_room(), 4)
	RunManager.run_gold_changed.disconnect(on_gold)
	RunManager.end_run(RunManager.EndReason.ABORT)
	assert_eq(RunManager.get_last_summary().get("payout"), 21, "50 % of the mirrored pot")


func test_shop_offers_travel_as_plain_values() -> void:
	var offer := ShopOffer.new()
	offer.kind = ShopOffer.Kind.WEAPON
	offer.weapon = load("res://weapons/data/bow.tres")
	offer.price = 30
	var data := NetDungeon.serialize_offer(offer)
	assert_eq(data.size(), 6)
	assert_eq(int(data[0]), int(ShopOffer.Kind.WEAPON))
	assert_eq(str(data[2]), "res://weapons/data/bow.tres")
	assert_eq(int(data[3]), 30)
	assert_false(bool(data[5]))


func test_enemy_snapshot_carries_position_and_telegraph() -> void:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.data = load("res://enemies/data/slime.tres")
	add_child_autofree(enemy)
	await wait_physics_frames(1)
	enemy.global_position = Vector2(100, 50)
	var plain := NetEnemies.encode_enemy(7, enemy)
	assert_eq(plain.size(), NetEnemies.SNAPSHOT_FIELDS)
	assert_eq(int(plain[0]), 7)
	assert_almost_eq(plain[1], 100.0, 0.01)
	var circle := enemy.get_node(^"TelegraphCircle") as Node2D
	circle.visible = true
	var with_circle := NetEnemies.encode_enemy(7, enemy)
	assert_eq(with_circle.size(), NetEnemies.SNAPSHOT_FIELDS + NetEnemies.CIRCLE_FIELDS)
	assert_eq(int(with_circle[4]) & NetEnemies.FLAG_CIRCLE, NetEnemies.FLAG_CIRCLE)
	assert_eq(NetEnemies.data_for(&"slime"), load("res://enemies/data/slime.tres"), "enemy data by id")

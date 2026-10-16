extends GutTest
## Village meta progression (D-078, D-087): forge purchase rules with the 20-level table, locked
## upgrades, Proviant boosts (no crystal exchange any more), crystal payout and applying the upgrades
## to a run. Uses a test save file only.

const TEST_PATH := "user://test_meta_progression.cfg"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

var _old_path: String


func before_all() -> void:
	_old_path = SaveManager.save_path


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	SaveManager.save_path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	SaveManager.load_game()


func after_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + ".bak"))
	# P1-8: the last good copy would otherwise stand in for a broken test file.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + ".prev.bak"))
	SaveManager.save_path = _old_path
	SaveManager.load_game()


# --- Forge ---

func test_buy_spends_exact_cost_and_raises_level() -> void:
	SaveManager.add_permanent_gold(100)
	assert_eq(MetaProgression.get_next_cost(MetaProgression.VITALITY), 20)
	assert_true(MetaProgression.try_buy(MetaProgression.VITALITY))
	assert_eq(MetaProgression.get_level(MetaProgression.VITALITY), 1)
	assert_eq(SaveManager.get_permanent_gold(), 80)
	assert_eq(MetaProgression.get_next_cost(MetaProgression.VITALITY), 80, "second level costs 80")


func test_insufficient_gold_changes_nothing() -> void:
	SaveManager.add_permanent_gold(19)
	assert_false(MetaProgression.can_buy(MetaProgression.VITALITY))
	assert_false(MetaProgression.try_buy(MetaProgression.VITALITY))
	assert_eq(MetaProgression.get_level(MetaProgression.VITALITY), 0)
	assert_eq(SaveManager.get_permanent_gold(), 19)


func test_max_level_cannot_be_exceeded() -> void:
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_BOSS)
	SaveManager.add_permanent_gold(10000)
	for i in 3:
		assert_true(MetaProgression.try_buy(MetaProgression.DASH_TRAINING))
	var gold := SaveManager.get_permanent_gold()
	assert_eq(gold, 10000 - 60 - 140 - 260)
	assert_true(MetaProgression.is_maxed(MetaProgression.DASH_TRAINING))
	assert_eq(MetaProgression.get_next_cost(MetaProgression.DASH_TRAINING), -1)
	assert_false(MetaProgression.try_buy(MetaProgression.DASH_TRAINING))
	assert_eq(SaveManager.get_permanent_gold(), gold, "no gold spent at max level")
	assert_eq(MetaProgression.get_level(MetaProgression.DASH_TRAINING), 3)


func test_all_upgrades_match_the_d087_table() -> void:
	var expected := {
		MetaProgression.VITALITY: [20, 80, 140, 220, 320],
		MetaProgression.START_SHIELD: [30, 90, 160],
		MetaProgression.SHARPNESS: [70, 150, 260, 400],
		MetaProgression.GOLD_GREED: [60, 140, 250],
		MetaProgression.DASH_TRAINING: [60, 140, 260],
		MetaProgression.ARSENAL: [80, 160],
	}
	var total := 0
	for id in expected:
		assert_eq(MetaProgression.get_max_level(id), (expected[id] as Array).size(), String(id))
		assert_eq(MetaProgression.UPGRADES[id]["costs"], expected[id], "%s costs" % id)
		total += MetaProgression.get_max_level(id)
	assert_eq(total, 20, "28 -> 20 levels (D-087)")
	assert_almost_eq(MetaProgression.SHIELD_PER_LEVEL, 3.0, 0.0001)
	assert_almost_eq(MetaProgression.DAMAGE_PER_LEVEL, 0.10, 0.0001)
	assert_almost_eq(MetaProgression.GOLD_PER_LEVEL, 0.15, 0.0001)


func test_locked_upgrades_cannot_be_bought() -> void:
	SaveManager.add_permanent_gold(1000)
	for id in [MetaProgression.GOLD_GREED, MetaProgression.DASH_TRAINING, MetaProgression.ARSENAL]:
		assert_false(MetaUnlocks.is_upgrade_open(id), "%s locked in a fresh save" % id)
		assert_false(MetaProgression.can_buy(id))
		assert_false(MetaProgression.try_buy(id))
		assert_eq(MetaProgression.get_level(id), 0)
	assert_eq(SaveManager.get_permanent_gold(), 1000, "nothing spent")
	for id in [MetaProgression.VITALITY, MetaProgression.START_SHIELD, MetaProgression.SHARPNESS]:
		assert_true(MetaProgression.can_buy(id), "%s open from the start" % id)
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_BOSS)
	assert_true(MetaProgression.try_buy(MetaProgression.GOLD_GREED), "open after the first boss")


func test_unknown_upgrade_is_rejected() -> void:
	SaveManager.add_permanent_gold(1000)
	assert_false(MetaProgression.try_buy(&"does_not_exist"))
	assert_eq(SaveManager.get_permanent_gold(), 1000)


func test_levels_survive_reload() -> void:
	SaveManager.add_permanent_gold(200)
	MetaProgression.try_buy(MetaProgression.SHARPNESS)
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(MetaProgression.get_level(MetaProgression.SHARPNESS), 1)
	assert_eq(SaveManager.get_permanent_gold(), 130)
	assert_almost_eq(MetaProgression.get_damage_bonus(), 0.10, 0.0001)


func test_gold_multiplier_from_greed() -> void:
	assert_almost_eq(MetaProgression.get_gold_multiplier(), 1.0, 0.0001)
	SaveManager.set_meta_level(MetaProgression.GOLD_GREED, 3)
	assert_almost_eq(MetaProgression.get_gold_multiplier(), 1.45, 0.0001)


func test_arsenal_weapon_choice() -> void:
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_BOSS)
	assert_eq(MetaProgression.get_second_weapon(), &"")
	SaveManager.add_permanent_gold(240)
	MetaProgression.try_buy(MetaProgression.ARSENAL)
	assert_eq(MetaProgression.get_second_weapon(), MetaProgression.WEAPON_BOW)
	assert_false(MetaProgression.set_second_weapon(MetaProgression.WEAPON_STAFF), "staff needs level 2")
	MetaProgression.try_buy(MetaProgression.ARSENAL)
	assert_true(MetaProgression.set_second_weapon(MetaProgression.WEAPON_STAFF))
	assert_eq(MetaProgression.get_second_weapon(), MetaProgression.WEAPON_STAFF)


# --- Trader ---

func test_no_crystal_exchange_any_more() -> void:
	# D-087: crystals are only spent on Proviant; no way to turn them into gold or back.
	var script: Script = load("res://meta/meta_progression.gd")
	var methods: Array[String] = []
	for method in script.get_script_method_list():
		methods.append(method["name"])
	for removed in ["try_sell_crystals", "try_buy_crystals"]:
		assert_false(methods.has(removed), "%s removed" % removed)
	var constants := script.get_script_constant_map()
	assert_false(constants.has("CRYSTAL_SELL_PRICE"))
	assert_false(constants.has("CRYSTAL_BUY_PRICE"))
	for id in MetaProgression.BOOST_ORDER:
		assert_gt(MetaProgression.get_boost_price(id), 0, "Proviant still costs crystals")


func test_boost_is_consumed_by_next_run_only() -> void:
	SaveManager.add_permanent_crystals(5)
	assert_true(MetaProgression.try_buy_boost(MetaProgression.BOOST_GOLD))
	assert_false(MetaProgression.try_buy_boost(MetaProgression.BOOST_GOLD), "one of each kind")
	assert_eq(SaveManager.get_permanent_crystals(), 5 - MetaProgression.get_boost_price(MetaProgression.BOOST_GOLD))
	assert_true(SaveManager.has_pending_boost(MetaProgression.BOOST_GOLD))
	RunManager.start_run()
	assert_false(SaveManager.has_pending_boost(MetaProgression.BOOST_GOLD), "consumed at run start")
	assert_true(RunManager.has_run_boost(MetaProgression.BOOST_GOLD))
	assert_almost_eq(MetaProgression.get_gold_multiplier(), 1.25, 0.0001)
	RunManager.end_run(RunManager.EndReason.DEATH)
	assert_false(RunManager.has_run_boost(MetaProgression.BOOST_GOLD))
	RunManager.start_run()
	assert_false(RunManager.has_run_boost(MetaProgression.BOOST_GOLD), "not active in the run after")


func test_boost_needs_crystals() -> void:
	assert_false(MetaProgression.try_buy_boost(MetaProgression.BOOST_UPGRADE))
	assert_false(SaveManager.has_pending_boost(MetaProgression.BOOST_UPGRADE))


# --- Crystal payout ---

func test_crystal_payout_on_exit_is_full() -> void:
	RunManager.start_run()
	RunManager.add_run_crystals(7)
	RunManager.end_run(RunManager.EndReason.EXIT)
	assert_eq(SaveManager.get_permanent_crystals(), 7)
	assert_eq(RunManager.get_last_summary().get("crystal_payout"), 7)


func test_crystal_payout_on_death_rounds_up() -> void:
	RunManager.start_run()
	RunManager.add_run_crystals(7)
	RunManager.end_run(RunManager.EndReason.DEATH)
	assert_eq(SaveManager.get_permanent_crystals(), 4, "50 % of 7 rounded up")


func test_crystal_payout_on_abort_and_once_only() -> void:
	RunManager.start_run()
	RunManager.add_run_crystals(3)
	assert_eq(RunManager.get_run_crystals(), 3)
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.end_run(RunManager.EndReason.EXIT)
	assert_eq(SaveManager.get_permanent_crystals(), 2)
	assert_eq(RunManager.get_run_crystals(), 0)


func test_crystals_need_active_run() -> void:
	RunManager.add_run_crystals(5)
	assert_eq(RunManager.get_run_crystals(), 0)


# --- Applying to a run ---

func test_apply_to_run() -> void:
	SaveManager.set_meta_level(MetaProgression.VITALITY, 2)
	SaveManager.set_meta_level(MetaProgression.START_SHIELD, 1)
	SaveManager.set_meta_level(MetaProgression.DASH_TRAINING, 2)
	SaveManager.set_meta_level(MetaProgression.ARSENAL, 1)
	SaveManager.add_pending_boost(MetaProgression.BOOST_POTION)
	RunManager.start_run()
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	var base_health := player.health.get_max_health()
	var base_dash := player.dash_cooldown
	var lines := MetaProgression.apply_to_run(player, null)
	assert_almost_eq(player.health.get_max_health(), base_health + 2.0 + MetaProgression.BOOST_POTION_HEALTH, 0.001)
	assert_almost_eq(player.health.get_health(), player.health.get_max_health(), 0.001, "starts at full HP")
	assert_almost_eq(player.shield.get_shield(), 3.0, 0.001, "Startschild 1 = +3 (D-087)")
	assert_almost_eq(player.dash_cooldown, base_dash - 0.3, 0.001)
	assert_true(player.weapon_controller.has_weapon_type(WeaponData.WeaponType.BOW), "Arsenal adds the bow")
	assert_eq(lines.size(), 1, "the potion boost is reported")


# --- Statistics ---

func test_stats_tracker_counts_runs() -> void:
	var tracker := StatsTracker.new()
	add_child_autofree(tracker)
	RunManager.start_run()
	EventBus.room_entered.emit(7)
	EventBus.room_completed.emit(7)
	RunManager.add_run_gold(30)
	RunManager.try_spend_run_gold(10)
	RunManager.end_run(RunManager.EndReason.DEATH)
	assert_eq(SaveManager.get_stat(StatsTracker.RUNS), 1)
	assert_eq(SaveManager.get_stat(StatsTracker.DEATHS), 1)
	assert_eq(SaveManager.get_stat(StatsTracker.DEEPEST_ROOM), 7)
	assert_eq(SaveManager.get_stat(StatsTracker.ROOMS_CLEARED), 1)
	assert_eq(SaveManager.get_stat(StatsTracker.GOLD_EARNED), 30, "gold collected, before spending")
	assert_eq(SaveManager.get_stat(StatsTracker.GOLD_BANKED), 10, "50 % of the 20 remaining")
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_stat(StatsTracker.RUNS), 1, "statistics are saved")


func test_play_time_format() -> void:
	assert_eq(StatsTracker.format_play_time(59.0), "0 min")
	assert_eq(StatsTracker.format_play_time(12 * 60.0), "12 min")
	assert_eq(StatsTracker.format_play_time(3 * 3600.0 + 7 * 60.0), "3 h 07 min")

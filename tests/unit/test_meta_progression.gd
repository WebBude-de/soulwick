extends GutTest
## Village meta progression (D-078, D-087, KE4): forge purchase rules with the KONZEPT §5.1 table
## (36 levels), locked upgrades, start weapons, Proviant boosts (no crystal exchange any more), crystal
## payout and applying the forge to a run. Uses a test save file only.

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
	assert_eq(MetaProgression.get_next_cost(MetaProgression.SHIELD_PLATE), 40)
	assert_true(MetaProgression.try_buy(MetaProgression.SHIELD_PLATE))
	assert_eq(MetaProgression.get_level(MetaProgression.SHIELD_PLATE), 1)
	assert_eq(SaveManager.get_permanent_gold(), 60)
	assert_eq(MetaProgression.get_next_cost(MetaProgression.SHIELD_PLATE), 90, "second level costs 90")


func test_insufficient_gold_changes_nothing() -> void:
	SaveManager.add_permanent_gold(59)
	assert_false(MetaProgression.can_buy(MetaProgression.SMITH_SWORD))
	assert_false(MetaProgression.try_buy(MetaProgression.SMITH_SWORD))
	assert_eq(MetaProgression.get_level(MetaProgression.SMITH_SWORD), 0)
	assert_eq(SaveManager.get_permanent_gold(), 59)


func test_max_level_cannot_be_exceeded() -> void:
	SaveManager.add_permanent_gold(10000)
	for i in 5:
		assert_true(MetaProgression.try_buy(MetaProgression.SMITH_BOW))
	var gold := SaveManager.get_permanent_gold()
	assert_eq(gold, 10000 - 60 - 120 - 200 - 320 - 480)
	assert_true(MetaProgression.is_maxed(MetaProgression.SMITH_BOW))
	assert_eq(MetaProgression.get_next_cost(MetaProgression.SMITH_BOW), -1)
	assert_false(MetaProgression.try_buy(MetaProgression.SMITH_BOW))
	assert_eq(SaveManager.get_permanent_gold(), gold, "no gold spent at max level")
	assert_eq(MetaProgression.weapon_level(MetaProgression.WEAPON_BOW), 5)


func test_all_upgrades_match_the_konzept_table() -> void:
	var expected := {
		MetaProgression.ARSENAL_BOW: [80], MetaProgression.ARSENAL_STAFF: [120],
		MetaProgression.ARSENAL_DAGGER: [160], MetaProgression.ARSENAL_HAMMER: [200],
		MetaProgression.SECOND_SLOT: [300],
		MetaProgression.SHIELD_PLATE: [40, 90, 160],
		MetaProgression.LANTERN: [50, 110, 200],
	}
	for weapon in MetaProgression.WEAPON_ORDER:
		expected[MetaProgression.smith_id(weapon)] = [60, 120, 200, 320, 480]
	assert_eq(expected.size(), MetaProgression.UPGRADE_ORDER.size(), "every forge entry is listed")
	var total := 0
	for id in expected:
		assert_eq(MetaProgression.get_max_level(id), (expected[id] as Array).size(), String(id))
		assert_eq(Array(MetaProgression.UPGRADES[id]["costs"]), expected[id], "%s costs" % id)
		total += MetaProgression.get_max_level(id)
	assert_eq(total, 36, "25 weapon levels, 4 Arsenal, second slot, 3 + 3 equipment (KONZEPT §5.1)")
	assert_almost_eq(MetaProgression.WEAPON_DAMAGE_PER_LEVEL, 0.08, 0.0001)
	assert_almost_eq(MetaProgression.SHIELD_PER_LEVEL, 3.0, 0.0001)
	assert_almost_eq(MetaProgression.LANTERN_RADIUS_PER_LEVEL, 0.10, 0.0001)


func test_removed_upgrades_are_gone() -> void:
	# KE4 (D-194): Vitalität and Dash-Training are talents, Goldgier becomes Proviant, Schärfe is gone.
	for old in [&"vitality", &"sharpness", &"gold_greed", &"dash_training", &"start_shield", &"arsenal"]:
		assert_false(MetaProgression.UPGRADES.has(old), "%s left the forge" % old)
	var constants := (load("res://meta/meta_progression.gd") as Script).get_script_constant_map()
	for name in ["VITALITY", "SHARPNESS", "GOLD_GREED", "DASH_TRAINING", "START_SHIELD", "ARSENAL", "HEALTH_PER_LEVEL"]:
		assert_false(constants.has(name), name)
	assert_eq(MetaProgression.get_damage_bonus(), 0.0, "no global damage bonus any more")


func test_locked_upgrades_cannot_be_bought() -> void:
	SaveManager.add_permanent_gold(1000)
	for id in [MetaProgression.ARSENAL_BOW, MetaProgression.ARSENAL_HAMMER, MetaProgression.SECOND_SLOT]:
		assert_false(MetaUnlocks.is_upgrade_open(id), "%s locked in a fresh save" % id)
		assert_false(MetaProgression.can_buy(id))
		assert_false(MetaProgression.try_buy(id))
		assert_eq(MetaProgression.get_level(id), 0)
	assert_eq(SaveManager.get_permanent_gold(), 1000, "nothing spent")
	for id in [MetaProgression.SMITH_SWORD, MetaProgression.SMITH_HAMMER, MetaProgression.SHIELD_PLATE, MetaProgression.LANTERN]:
		assert_true(MetaProgression.can_buy(id), "%s open from the start" % id)
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_BOSS)
	assert_true(MetaProgression.try_buy(MetaProgression.ARSENAL_BOW), "open after the first boss")


func test_unknown_upgrade_is_rejected() -> void:
	SaveManager.add_permanent_gold(1000)
	assert_false(MetaProgression.try_buy(&"does_not_exist"))
	assert_false(MetaProgression.try_buy(&"vitality"), "old ids are unknown now")
	assert_eq(SaveManager.get_permanent_gold(), 1000)


func test_levels_survive_reload() -> void:
	SaveManager.add_permanent_gold(200)
	MetaProgression.try_buy(MetaProgression.SMITH_DAGGER)
	MetaProgression.try_buy(MetaProgression.LANTERN)
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(MetaProgression.weapon_level(MetaProgression.WEAPON_DAGGER), 1)
	assert_eq(MetaProgression.get_level(MetaProgression.LANTERN), 1)
	assert_eq(SaveManager.get_permanent_gold(), 90)
	assert_almost_eq(MetaProgression.weapon_damage_factor(MetaProgression.WEAPON_DAGGER), 1.08, 0.0001)
	assert_almost_eq(MetaProgression.get_light_radius_factor(), 1.1, 0.0001)


func test_gold_multiplier_without_greed() -> void:
	assert_almost_eq(MetaProgression.get_gold_multiplier(), 1.0, 0.0001)
	SaveManager.set_meta_level(&"gold_greed", 3)
	assert_almost_eq(MetaProgression.get_gold_multiplier(), 1.0, 0.0001, "Goldgier left the forge (KE4)")


func test_arsenal_and_start_weapons() -> void:
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_BOSS)
	assert_eq(MetaProgression.get_start_weapons(), [MetaProgression.WEAPON_SWORD] as Array[StringName], "sword by default")
	assert_eq(MetaProgression.get_unlocked_weapons(), [MetaProgression.WEAPON_SWORD] as Array[StringName])
	assert_false(MetaProgression.set_start_weapon(MetaProgression.WEAPON_BOW), "the bow needs its Arsenal entry")
	SaveManager.add_permanent_gold(1000)
	assert_true(MetaProgression.try_buy(MetaProgression.ARSENAL_BOW))
	assert_true(MetaProgression.is_weapon_unlocked(MetaProgression.WEAPON_BOW))
	assert_eq(MetaProgression.get_second_weapon(), &"", "no second slot yet")
	assert_false(MetaProgression.set_second_weapon(MetaProgression.WEAPON_BOW), "needs the second start slot")
	assert_true(MetaProgression.set_start_weapon(MetaProgression.WEAPON_BOW))
	assert_eq(MetaProgression.get_start_weapons(), [MetaProgression.WEAPON_BOW] as Array[StringName], "start with the bow only")
	assert_true(MetaProgression.try_buy(MetaProgression.SECOND_SLOT))
	assert_eq(MetaProgression.get_start_weapons(), [MetaProgression.WEAPON_BOW, MetaProgression.WEAPON_SWORD] as Array[StringName],
		"the new slot is filled with an unlocked weapon")
	assert_false(MetaProgression.set_second_weapon(MetaProgression.WEAPON_BOW), "not twice the same weapon")
	assert_false(MetaProgression.set_second_weapon(MetaProgression.WEAPON_STAFF), "the staff is locked")
	assert_true(MetaProgression.set_start_weapon(MetaProgression.WEAPON_SWORD), "picking the second one swaps")
	assert_eq(MetaProgression.get_start_weapons(), [MetaProgression.WEAPON_SWORD, MetaProgression.WEAPON_BOW] as Array[StringName])
	assert_true(MetaProgression.set_second_weapon(&""), "none is fine")
	assert_eq(MetaProgression.get_start_weapons(), [MetaProgression.WEAPON_SWORD] as Array[StringName])
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(MetaProgression.get_start_weapon(), MetaProgression.WEAPON_SWORD, "saved")


func test_unlocking_fills_an_empty_second_slot() -> void:
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_BOSS)
	SaveManager.add_permanent_gold(1000)
	assert_true(MetaProgression.try_buy(MetaProgression.SECOND_SLOT))
	assert_eq(MetaProgression.get_second_weapon(), &"", "only the sword is unlocked")
	assert_true(MetaProgression.try_buy(MetaProgression.ARSENAL_HAMMER))
	assert_eq(MetaProgression.get_second_weapon(), MetaProgression.WEAPON_HAMMER)


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
	assert_true(MetaProgression.try_buy_boost(MetaProgression.BOOST_GOLD_RAIN))
	assert_false(MetaProgression.try_buy_boost(MetaProgression.BOOST_GOLD_RAIN), "one of each kind")
	assert_eq(SaveManager.get_permanent_crystals(), 5 - MetaProgression.get_boost_price(MetaProgression.BOOST_GOLD_RAIN))
	assert_true(SaveManager.has_pending_boost(MetaProgression.BOOST_GOLD_RAIN))
	RunManager.start_run()
	assert_false(SaveManager.has_pending_boost(MetaProgression.BOOST_GOLD_RAIN), "consumed at run start")
	assert_true(RunManager.has_run_boost(MetaProgression.BOOST_GOLD_RAIN))
	assert_almost_eq(MetaProgression.get_gold_multiplier(), MetaProgression.GOLD_RAIN_FACTOR, 0.0001, "Goldregen doubles")
	RunManager.end_run(RunManager.EndReason.DEATH)
	assert_false(RunManager.has_run_boost(MetaProgression.BOOST_GOLD_RAIN))
	RunManager.start_run()
	assert_false(RunManager.has_run_boost(MetaProgression.BOOST_GOLD_RAIN), "not active in the run after")


func test_boost_needs_crystals() -> void:
	assert_false(MetaProgression.try_buy_boost(MetaProgression.BOOST_LUCKY_AMULET))
	assert_false(SaveManager.has_pending_boost(MetaProgression.BOOST_LUCKY_AMULET))


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
	assert_eq(SaveManager.get_permanent_crystals(), ceili(7 * RunManager.LOSS_PAYOUT_RATIO), "the loss share of 7 rounded up")


func test_crystal_payout_on_abort_and_once_only() -> void:
	RunManager.start_run()
	RunManager.add_run_crystals(3)
	assert_eq(RunManager.get_run_crystals(), 3)
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.end_run(RunManager.EndReason.EXIT)
	assert_eq(SaveManager.get_permanent_crystals(), ceili(3 * RunManager.LOSS_PAYOUT_RATIO))
	assert_eq(RunManager.get_run_crystals(), 0)


func test_crystals_need_active_run() -> void:
	RunManager.add_run_crystals(5)
	assert_eq(RunManager.get_run_crystals(), 0)


# --- Applying to a run ---

func test_apply_to_run() -> void:
	SaveManager.set_meta_level(MetaProgression.SHIELD_PLATE, 1)
	SaveManager.set_meta_level(MetaProgression.LANTERN, 2)
	SaveManager.set_meta_level(MetaProgression.SMITH_BOW, 3)
	SaveManager.set_meta_level(MetaProgression.ARSENAL_BOW, 1)
	SaveManager.set_meta_level(MetaProgression.SECOND_SLOT, 1)
	SaveManager.set_second_weapon(MetaProgression.WEAPON_BOW)
	SaveManager.add_pending_boost(MetaProgression.BOOST_HEALING_POTION)
	RunManager.start_run()
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	var base_health := player.health.get_max_health()
	var base_dash := player.dash_cooldown
	var lines := MetaProgression.apply_to_run(player, null)
	assert_almost_eq(player.health.get_max_health(), base_health + MetaProgression.HEALING_POTION_HEALTH, 0.001, "only the potion")
	assert_almost_eq(player.health.get_health(), player.health.get_max_health(), 0.001, "starts at full HP")
	assert_almost_eq(player.shield.get_shield(), 3.0, 0.001, "Schildplatte 1 = +3")
	assert_almost_eq(player.dash_cooldown, base_dash, 0.001, "Dash-Training is a talent now (KE4)")
	assert_eq(player.weapon_controller.get_weapon(0).id, MetaProgression.WEAPON_SWORD)
	assert_eq(player.weapon_controller.get_weapon(1).id, MetaProgression.WEAPON_BOW, "second start weapon")
	assert_eq(MetaProgression.player_weapon_level(player, MetaProgression.WEAPON_BOW), 3, "forge levels are state at the player")
	assert_almost_eq(MetaProgression.player_weapon_damage_bonus(player, player.weapon_controller.get_weapon(1)), 0.24, 0.0001)
	assert_almost_eq(MetaProgression.player_special_factor(player, player.weapon_controller.get_weapon(1)), 1.25, 0.0001, "level III")
	assert_almost_eq(MetaProgression.player_light_factor(player), 1.2, 0.0001)
	assert_eq(lines.size(), 1, "the potion boost is reported")


func test_apply_with_another_start_weapon() -> void:
	SaveManager.set_meta_level(MetaProgression.ARSENAL_DAGGER, 1)
	SaveManager.set_start_weapon(MetaProgression.WEAPON_DAGGER)
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	MetaProgression.apply_to_run(player, null)
	assert_eq(player.weapon_controller.get_weapon(0).id, MetaProgression.WEAPON_DAGGER, "the dagger replaces the sword")
	assert_null(player.weapon_controller.get_weapon(1), "one slot only")


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
	assert_eq(SaveManager.get_stat(StatsTracker.GOLD_BANKED), ceili(20 * RunManager.LOSS_PAYOUT_RATIO), "the loss share of the 20 remaining")
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_stat(StatsTracker.RUNS), 1, "statistics are saved")


func test_play_time_format() -> void:
	assert_eq(StatsTracker.format_play_time(59.0), "0 min")
	assert_eq(StatsTracker.format_play_time(12 * 60.0), "12 min")
	assert_eq(StatsTracker.format_play_time(3 * 3600.0 + 7 * 60.0), "3 h 07 min")

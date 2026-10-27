extends GutTest
## Proviant effects (KE5, KONZEPT §5.2): one check per Proviant through the pure rules of
## MetaProgression, Glück (weighted upgrade choice) and Händlerfreund (merchant prices), and the
## co-op state at the player (D-088, KONZEPT §9): every player carries his own Proviant snapshot,
## a player without one (guild run) has none. Uses a test save file only.

const TEST_PATH := "user://test_boosts_effects.cfg"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

var _old_locale: String
var _old_path: String


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	Loc.apply(&"de")
	_old_path = SaveManager.save_path


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	SaveManager.save_path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	SaveManager.load_game()


func after_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)
	for suffix in ["", ".bak", ".prev.bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + suffix))
	SaveManager.save_path = _old_path
	SaveManager.load_game()


## A plain node carrying a Proviant snapshot, like a player of a group run.
func _carrier(boosts: Array, luck := 0, merchant := 0) -> Node:
	var node := Node.new()
	autofree(node)
	MetaProgression.set_player_provisions(node, {"boosts": boosts, "luck": luck, "merchant_friend": merchant})
	return node


func _upgrade(id: StringName, category: UpgradeData.Category) -> UpgradeData:
	var upgrade := UpgradeData.new()
	upgrade.id = id
	upgrade.category = category
	return upgrade


## Two plain and two rare upgrades (rare = the wandering merchant's categories).
func _pool() -> Array[UpgradeData]:
	return [
		_upgrade(&"plain_a", UpgradeData.Category.ATTRIBUTE), _upgrade(&"plain_b", UpgradeData.Category.ATTRIBUTE),
		_upgrade(&"rare_a", UpgradeData.Category.MECHANIC), _upgrade(&"rare_b", UpgradeData.Category.EFFECT),
	]


# --- One check per Proviant ---

func test_gold_rain_doubles_gold() -> void:
	assert_almost_eq(MetaProgression.gold_factor_for([MetaProgression.BOOST_GOLD_RAIN]), 2.0, 0.0001)
	assert_almost_eq(MetaProgression.gold_factor_for([]), 1.0, 0.0001)
	SaveManager.add_pending_boost(MetaProgression.BOOST_GOLD_RAIN)
	assert_almost_eq(MetaProgression.get_gold_multiplier(), 1.0, 0.0001, "only while the run is on")
	RunManager.start_run()
	assert_almost_eq(MetaProgression.get_gold_multiplier(), 2.0, 0.0001, "every gold drop multiplies with it")


func test_lucky_amulet_gives_a_rare_upgrade() -> void:
	var rng := RandomNumberGenerator.new()
	for seed_value in 20:
		rng.seed = seed_value
		var upgrade := MetaProgression.pick_rare_upgrade(_pool(), rng)
		assert_true(MetaProgression.is_rare_upgrade(upgrade), "seed %d: %s is rare" % [seed_value, upgrade.id])
	var plain: Array[UpgradeData] = [_upgrade(&"plain", UpgradeData.Category.ATTRIBUTE)]
	assert_eq(MetaProgression.pick_rare_upgrade(plain, rng).id, &"plain", "any upgrade when none is rare")
	assert_null(MetaProgression.pick_rare_upgrade([] as Array[UpgradeData], rng))
	assert_eq(int(MetaProgression.boost_effect(MetaProgression.BOOST_LUCKY_AMULET)["rare_upgrades"]), 1)


func test_lucky_amulet_at_the_run_start() -> void:
	var manager := UpgradeManager.new()
	autofree(manager)
	manager.upgrade_pool = _pool()
	var context := DungeonContext.new()
	context.upgrade_manager = manager
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 7
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	var lines := MetaProgression.apply_provisions(player, {"boosts": ["lucky_amulet"]}, context)
	var owned := manager.get_active_upgrades()
	assert_eq(owned.size(), 1, "one upgrade")
	assert_true(MetaProgression.is_rare_upgrade(owned[0]), "a rare one")
	assert_eq(lines.size(), 1)
	assert_true(lines[0].begins_with("Glücksamulett: "), lines[0])


func test_clear_sight_protects_against_blindness() -> void:
	assert_true(MetaProgression.is_blind_immune_for([MetaProgression.BOOST_CLEAR_SIGHT]))
	assert_false(MetaProgression.is_blind_immune_for([MetaProgression.BOOST_KEEN_NOSE]))
	assert_true(MetaProgression.player_blind_immune(_carrier(["clear_sight"])))
	assert_false(MetaProgression.player_blind_immune(_carrier([])))


func test_healing_potion_adds_two_max_hp() -> void:
	assert_almost_eq(MetaProgression.max_health_bonus_for([MetaProgression.BOOST_HEALING_POTION]), 2.0, 0.0001)
	assert_almost_eq(MetaProgression.max_health_bonus_for([]), 0.0, 0.0001)
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	var base := player.health.get_max_health()
	var lines := MetaProgression.apply_provisions(player, {"boosts": ["healing_potion"]})
	assert_almost_eq(player.health.get_max_health(), base + 2.0, 0.0001)
	assert_almost_eq(player.health.get_health(), base + 2.0, 0.0001, "starts at full health")
	assert_eq(lines, ["Heiltrank: +2 Max-HP"] as Array[String])


func test_soul_anchor_keeps_half_on_death() -> void:
	assert_almost_eq(MetaProgression.loss_payout_ratio_for([MetaProgression.BOOST_SOUL_ANCHOR]), 0.5, 0.0001)
	assert_almost_eq(MetaProgression.loss_payout_ratio_for([]), RunManager.LOSS_PAYOUT_RATIO, 0.0001)
	var anchored := _carrier(["soul_anchor"])
	assert_almost_eq(MetaProgression.player_loss_payout_ratio(anchored), 0.5, 0.0001)
	# The hook of the integrator: the soul gate rules with the player's anchor.
	var has_anchor := MetaProgression.player_has_boost(anchored, SoulGateRules.SOUL_ANCHOR_BOOST)
	assert_eq(SoulGateRules.payout(9, RunManager.EndReason.DEATH, has_anchor), 5, "50 % of 9 rounded up")
	assert_eq(SoulGateRules.payout(9, RunManager.EndReason.DEATH, false), 3, "25 % of 9 rounded up")


func test_return_stone_opens_one_gate_per_run() -> void:
	assert_eq(MetaProgression.return_gates_for([MetaProgression.BOOST_RETURN_STONE]), 1)
	assert_eq(MetaProgression.return_gates_for([]), 0)
	var player := _carrier(["return_stone"])
	assert_true(MetaProgression.can_use_return_stone(player))
	MetaProgression.mark_return_stone_used(player)
	assert_false(MetaProgression.can_use_return_stone(player), "once per run")
	MetaProgression.set_player_provisions(player, {"boosts": ["return_stone"]})
	assert_true(MetaProgression.can_use_return_stone(player), "a new run brings a new stone")
	assert_false(MetaProgression.can_use_return_stone(_carrier([])), "nothing without the stone")


func test_keen_nose_marks_secrets() -> void:
	assert_true(MetaProgression.has_keen_nose_for([MetaProgression.BOOST_KEEN_NOSE]))
	assert_false(MetaProgression.has_keen_nose_for([MetaProgression.BOOST_GOLD_RAIN]))
	assert_true(MetaProgression.player_has_keen_nose(_carrier(["keen_nose"])))
	assert_false(MetaProgression.player_has_keen_nose(_carrier([])))


# --- Glück and Händlerfreund ---

func test_luck_weighs_rare_upgrades() -> void:
	assert_almost_eq(MetaProgression.luck_bonus_at(0), 0.0, 0.0001)
	assert_almost_eq(MetaProgression.luck_bonus_at(3), 0.3, 0.0001)
	assert_almost_eq(MetaProgression.luck_bonus_at(9), 0.3, 0.0001, "at most Glück III")
	var pool := _pool()
	assert_almost_eq(MetaProgression.upgrade_weight(pool[0], 2), 1.0, 0.0001, "plain upgrades stay")
	assert_almost_eq(MetaProgression.upgrade_weight(pool[2], 2), 1.2, 0.0001, "rare +10 % per level")


func test_luck_zero_draws_like_the_upgrade_manager() -> void:
	var manager := UpgradeManager.new()
	autofree(manager)
	manager.upgrade_pool = _pool()
	for seed_value in 10:
		var a := RandomNumberGenerator.new()
		a.seed = seed_value
		var b := RandomNumberGenerator.new()
		b.seed = seed_value
		assert_eq(MetaProgression.roll_weighted_offer(manager.get_available_upgrades(), a, 3, 0),
			manager.roll_offer([], b, 3), "seed %d: same offer without Glück" % seed_value)


func test_luck_brings_more_rare_upgrades() -> void:
	var rng := RandomNumberGenerator.new()
	var rare := [0, 0]
	for level_index in 2:
		rng.seed = 42
		for i in 4000:
			var offer := MetaProgression.roll_weighted_offer(_pool(), rng, 1, 0 if level_index == 0 else 3)
			if MetaProgression.is_rare_upgrade(offer[0]):
				rare[level_index] += 1
	assert_gt(rare[1], rare[0] + 200, "Glück III: rare upgrades come clearly more often (%d vs %d)" % [rare[1], rare[0]])
	var offer := MetaProgression.roll_weighted_offer(_pool(), rng, 3, 3)
	assert_eq(offer.size(), 3)
	assert_ne(offer[0], offer[1], "no duplicates within one offer")
	assert_ne(offer[1], offer[2])


func test_merchant_friend_lowers_prices() -> void:
	assert_eq(MetaProgression.merchant_price(25, 0), 25)
	assert_eq(MetaProgression.merchant_price(25, 1), 23, "22,5 rounded")
	assert_eq(MetaProgression.merchant_price(25, 2), 20)
	assert_eq(MetaProgression.merchant_price(30, 9), 24, "at most Händlerfreund II")
	assert_eq(MetaProgression.merchant_price(1, 2), 1, "never free")
	assert_eq(MetaProgression.merchant_price(0, 2), 0)
	assert_eq(MetaProgression.player_merchant_price(_carrier([], 0, 2), 15), 12)


# --- At the player (co-op, D-088, KONZEPT §9) ---

func test_snapshot_is_cleaned_up() -> void:
	var clean := MetaProgression.sanitize_provisions({
		"boosts": ["gold_rain", "gold_rain", "cheat", 5, "keen_nose", "soul_anchor", "clear_sight"],
		"luck": 99, "merchant_friend": "x",
	})
	assert_eq(clean["boosts"], ["gold_rain", "clear_sight", "soul_anchor"], "known ids once, catalog order, at most three")
	assert_eq(clean["luck"], 3)
	assert_eq(clean["merchant_friend"], 0)
	assert_eq(MetaProgression.sanitize_provisions("nonsense"), {"boosts": [], "luck": 0, "merchant_friend": 0})


func test_snapshot_of_the_world() -> void:
	SaveManager.set_trade_level(MetaProgression.TRADE_LUCK, 2)
	SaveManager.set_trade_level(MetaProgression.TRADE_MERCHANT_FRIEND, 1)
	var snapshot := MetaProgression.provision_snapshot([&"healing_potion", &"potion"])
	assert_eq(snapshot, {"boosts": ["healing_potion"], "luck": 2, "merchant_friend": 1})


func test_every_player_carries_his_own_provisions() -> void:
	var with_rain := _carrier(["gold_rain"], 1)
	var without := _carrier([])
	assert_true(MetaProgression.player_has_boost(with_rain, MetaProgression.BOOST_GOLD_RAIN))
	assert_false(MetaProgression.player_has_boost(without, MetaProgression.BOOST_GOLD_RAIN))
	assert_eq(MetaProgression.player_luck_level(with_rain), 1)
	assert_eq(MetaProgression.player_luck_level(without), 0)
	assert_almost_eq(MetaProgression.group_gold_factor([with_rain, without]), 1.5, 0.0001, "mean of the players")
	assert_almost_eq(MetaProgression.group_gold_factor([with_rain, without, _carrier([]), _carrier([])]), 1.25, 0.0001)
	assert_almost_eq(MetaProgression.group_gold_factor([]), 1.0, 0.0001)


func test_a_player_without_snapshot_has_no_provisions() -> void:
	var guild_player := Node.new()
	autofree(guild_player)
	assert_true(MetaProgression.get_player_provisions(guild_player).is_empty(), "guild runs: no Proviant")
	assert_true(MetaProgression.get_player_boosts(guild_player).is_empty())
	assert_eq(MetaProgression.player_merchant_level(guild_player), 0)
	assert_false(MetaProgression.player_blind_immune(null))


func test_solo_run_puts_the_packed_provisions_on_the_player() -> void:
	SaveManager.add_pending_boost(MetaProgression.BOOST_CLEAR_SIGHT)
	SaveManager.add_pending_boost(MetaProgression.BOOST_SOUL_ANCHOR)
	SaveManager.set_trade_level(MetaProgression.TRADE_MERCHANT_FRIEND, 2)
	RunManager.start_run()
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	var lines := MetaProgression.apply_to_run(player, null)
	assert_eq(MetaProgression.get_player_boosts(player),
		[MetaProgression.BOOST_CLEAR_SIGHT, MetaProgression.BOOST_SOUL_ANCHOR] as Array[StringName])
	assert_eq(MetaProgression.player_merchant_level(player), 2)
	assert_eq(lines, ["Klarsicht: keine Blindheit", "Seelenanker: 50 % beim Tod"] as Array[String])

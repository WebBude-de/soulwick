extends GutTest
## Trading post (KE5, KONZEPT §5.2): the Proviant catalog with its prices and icons, Proviant slots,
## the trade levels Proviant-Platz, Glück and Händlerfreund (costs, values per level, purchases),
## the mapping of the Proviant ids of older builds on load (no new save version) and the trading
## post page of the village. Uses a test save file only.

const TEST_PATH := "user://test_trading_post.cfg"
const ICON_DIR := "res://art/ui/trading/"

var _old_locale: String
var _old_path: String


func before_all() -> void:
	OnlineMenu.login_on_open = false
	_old_locale = TranslationServer.get_locale()
	Loc.apply(&"de")
	_old_path = SaveManager.save_path


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	SaveManager.save_path = TEST_PATH
	_remove_files()
	SaveManager.load_game()


func after_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)
	_remove_files()
	SaveManager.save_path = _old_path
	SaveManager.load_game()


func _remove_files() -> void:
	for suffix in ["", ".bak", ".v4.bak", ".v5.bak", ".prev.bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + suffix))


func _write(text: String) -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


# --- Catalog ---

func test_catalog_has_the_seven_provisions_of_the_konzept() -> void:
	var prices := {
		MetaProgression.BOOST_GOLD_RAIN: 4, MetaProgression.BOOST_LUCKY_AMULET: 3,
		MetaProgression.BOOST_CLEAR_SIGHT: 2, MetaProgression.BOOST_HEALING_POTION: 2,
		MetaProgression.BOOST_SOUL_ANCHOR: 3, MetaProgression.BOOST_RETURN_STONE: 5,
		MetaProgression.BOOST_KEEN_NOSE: 2,
	}
	assert_eq(MetaProgression.BOOST_ORDER.size(), prices.size())
	for id: StringName in prices:
		assert_eq(MetaProgression.get_boost_price(id), prices[id], "%s costs as in KONZEPT §5.2" % id)
		assert_true(ResourceLoader.exists(ICON_DIR + "boost_%s.png" % id), "%s has its delivered icon" % id)
		assert_ne(MetaProgression.get_boost_name(id), "", "%s has a name" % id)
		assert_false(MetaProgression.get_boost_name(id).begins_with("BOOST_"), "%s name is translated" % id)
		assert_false(MetaProgression.get_boost_effect(id).begins_with("BOOST_"), "%s effect is translated" % id)
		assert_false(MetaProgression.boost_effect(id).is_empty(), "%s has effect values" % id)
	assert_eq(MetaProgression.get_boost_price(&"unknown"), -1)
	assert_true(MetaProgression.boost_effect(&"unknown").is_empty())


func test_effect_texts_show_real_numbers() -> void:
	assert_eq(MetaProgression.get_boost_name(MetaProgression.BOOST_GOLD_RAIN), "Goldregen")
	assert_eq(MetaProgression.get_boost_effect(MetaProgression.BOOST_HEALING_POTION), "+2 Max-HP im nächsten Run")
	assert_eq(MetaProgression.get_boost_effect(MetaProgression.BOOST_SOUL_ANCHOR), "Beim Tod 50 % statt 25 % behalten")
	assert_eq(MetaProgression.get_trade_effect(MetaProgression.TRADE_LUCK), "Seltene Upgrades öfter in der Auswahl: +10 % je Stufe")
	assert_eq(MetaProgression.get_trade_step_name(MetaProgression.TRADE_LUCK, 2), "Glück II")


func test_ids_match_the_extraction_hooks() -> void:
	assert_eq(MetaProgression.BOOST_SOUL_ANCHOR, SoulGateRules.SOUL_ANCHOR_BOOST)
	assert_eq(MetaProgression.BOOST_RETURN_STONE, SoulGateRules.RETURN_STONE_BOOST)
	assert_almost_eq(MetaProgression.SOUL_ANCHOR_PAYOUT_RATIO, SoulGateRules.SOUL_ANCHOR_PAYOUT_RATIO, 0.0001)


func test_trade_level_ids_are_the_v5_save_keys() -> void:
	for id in MetaProgression.TRADE_ORDER:
		assert_true(SaveManager.TRADE_LEVEL_DEFAULTS.has(String(id)), "%s is stored in [trade_levels]" % id)
	assert_eq(MetaProgression.TRADE_ORDER.size(), SaveManager.TRADE_LEVEL_DEFAULTS.size())


# --- Proviant slots ---

func test_one_slot_at_the_start() -> void:
	SaveManager.add_permanent_crystals(20)
	assert_eq(MetaProgression.get_provision_slots(), 1)
	assert_true(MetaProgression.try_buy_boost(MetaProgression.BOOST_CLEAR_SIGHT))
	assert_false(MetaProgression.has_free_provision_slot())
	assert_false(MetaProgression.can_buy_boost(MetaProgression.BOOST_KEEN_NOSE), "the only slot is packed")
	assert_false(MetaProgression.try_buy_boost(MetaProgression.BOOST_KEEN_NOSE))
	assert_eq(SaveManager.get_permanent_crystals(), 18, "only the first one was paid")
	assert_eq(MetaProgression.get_packed_boosts(), [MetaProgression.BOOST_CLEAR_SIGHT] as Array[StringName])


func test_more_slots_take_more_provisions() -> void:
	SaveManager.add_permanent_crystals(40)
	assert_true(MetaProgression.try_buy_trade(MetaProgression.TRADE_PROVISION_SLOT))
	assert_eq(MetaProgression.get_provision_slots(), 2)
	assert_true(MetaProgression.try_buy_boost(MetaProgression.BOOST_GOLD_RAIN))
	assert_true(MetaProgression.try_buy_boost(MetaProgression.BOOST_SOUL_ANCHOR))
	assert_false(MetaProgression.try_buy_boost(MetaProgression.BOOST_KEEN_NOSE), "two slots, two Proviant")
	assert_false(MetaProgression.try_buy_boost(MetaProgression.BOOST_GOLD_RAIN), "one of each kind")
	assert_eq(SaveManager.get_permanent_crystals(), 40 - 8 - 4 - 3)


func test_provisions_are_used_up_by_the_next_run() -> void:
	SaveManager.add_permanent_crystals(5)
	assert_true(MetaProgression.try_buy_boost(MetaProgression.BOOST_RETURN_STONE))
	RunManager.start_run()
	assert_true(MetaProgression.get_packed_boosts().is_empty(), "consumed at the run start")
	assert_true(RunManager.has_run_boost(MetaProgression.BOOST_RETURN_STONE))
	assert_true(MetaProgression.has_free_provision_slot(), "the slot is free again")
	RunManager.end_run(RunManager.EndReason.EXIT)
	RunManager.start_run()
	assert_false(RunManager.has_run_boost(MetaProgression.BOOST_RETURN_STONE), "only for one run")


# --- Trade levels ---

func test_trade_level_costs_as_in_the_konzept() -> void:
	var costs := {
		MetaProgression.TRADE_PROVISION_SLOT: [8, 15],
		MetaProgression.TRADE_LUCK: [6, 12, 20],
		MetaProgression.TRADE_MERCHANT_FRIEND: [5, 10],
	}
	SaveManager.add_permanent_crystals(200)
	for id: StringName in costs:
		assert_true(ResourceLoader.exists(ICON_DIR + String(VillageUI.TRADE_ICON_FILES[id])), "%s has its icon" % id)
		for cost: int in costs[id]:
			var before := SaveManager.get_permanent_crystals()
			assert_eq(MetaProgression.get_trade_next_cost(id), cost)
			assert_true(MetaProgression.try_buy_trade(id))
			assert_eq(SaveManager.get_permanent_crystals(), before - cost, "%s spends exactly its cost" % id)
		assert_true(MetaProgression.is_trade_maxed(id))
		assert_eq(MetaProgression.get_trade_next_cost(id), -1)
		assert_false(MetaProgression.try_buy_trade(id), "%s is maxed" % id)
	assert_eq(SaveManager.get_permanent_crystals(), 200 - 23 - 38 - 15)


func test_trade_level_needs_crystals() -> void:
	SaveManager.add_permanent_crystals(5)
	assert_false(MetaProgression.can_buy_trade(MetaProgression.TRADE_LUCK))
	assert_eq(MetaProgression.trade_crystals_missing(MetaProgression.TRADE_LUCK), 1)
	assert_false(MetaProgression.try_buy_trade(MetaProgression.TRADE_LUCK))
	assert_eq(MetaProgression.get_trade_level(MetaProgression.TRADE_LUCK), 0)
	assert_eq(SaveManager.get_permanent_crystals(), 5)
	assert_false(MetaProgression.try_buy_trade(&"unknown"))


func test_trade_levels_survive_reload() -> void:
	SaveManager.add_permanent_crystals(30)
	MetaProgression.try_buy_trade(MetaProgression.TRADE_LUCK)
	MetaProgression.try_buy_trade(MetaProgression.TRADE_MERCHANT_FRIEND)
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(MetaProgression.get_trade_level(MetaProgression.TRADE_LUCK), 1)
	assert_eq(MetaProgression.get_trade_level(MetaProgression.TRADE_MERCHANT_FRIEND), 1)
	assert_eq(SaveManager.get_permanent_crystals(), 30 - 6 - 5)


func test_levels_above_the_maximum_count_as_the_maximum() -> void:
	SaveManager.set_trade_level(MetaProgression.TRADE_PROVISION_SLOT, 9)
	assert_eq(MetaProgression.get_trade_level(MetaProgression.TRADE_PROVISION_SLOT), 2)
	assert_eq(MetaProgression.get_provision_slots(), 3)


func test_trade_steps_with_real_values() -> void:
	var slot := MetaProgression.TRADE_PROVISION_SLOT
	assert_eq(MetaProgression.describe_trade_step(slot, 0), "Plätze 1 → 2")
	assert_eq(MetaProgression.describe_trade_step(slot, 2), "Plätze 3 (max.)")
	assert_eq(MetaProgression.describe_trade_step(MetaProgression.TRADE_LUCK, 0), "Seltene Upgrades 0 % → +10 %")
	assert_eq(MetaProgression.describe_trade_step(MetaProgression.TRADE_LUCK, 2), "Seltene Upgrades +20 % → +30 %")
	assert_eq(MetaProgression.describe_trade_step(MetaProgression.TRADE_MERCHANT_FRIEND, 1), "Händlerpreise −10 % → −20 %")
	assert_eq(MetaProgression.describe_trade_step(MetaProgression.TRADE_MERCHANT_FRIEND, 2), "Händlerpreise −20 % (max.)")
	assert_eq(MetaProgression.describe_trade_step(&"unknown", 0), "")


# --- Proviant ids of older builds ---

func test_old_proviant_ids_are_mapped_on_load() -> void:
	_write("""[meta]
version=5
[progress]
permanent_gold=0
permanent_crystals=3
[boosts]
pending=PackedStringArray("potion", "upgrade", "gold", "healing_potion")
""")
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_pending_boosts(), [MetaProgression.BOOST_HEALING_POTION,
		MetaProgression.BOOST_LUCKY_AMULET, MetaProgression.BOOST_GOLD_RAIN] as Array[StringName], "each once, new ids")
	assert_false(FileAccess.file_exists(TEST_PATH + ".v5.bak"), "no version step, no migration copy")
	assert_eq(SaveManager.save_game(), OK)
	var config := ConfigFile.new()
	config.load(TEST_PATH)
	assert_eq(config.get_value("meta", "version"), SaveManager.SAVE_VERSION)
	assert_eq(config.get_value("boosts", "pending"), PackedStringArray(["healing_potion", "lucky_amulet", "gold_rain"]))


func test_old_saves_keep_more_provisions_than_slots() -> void:
	_write("""[meta]
version=5
[progress]
permanent_gold=0
permanent_crystals=30
[boosts]
pending=PackedStringArray("potion", "upgrade", "gold")
""")
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(MetaProgression.get_packed_boosts().size(), 3, "nothing is lost (D-059)")
	assert_false(MetaProgression.can_buy_boost(MetaProgression.BOOST_KEEN_NOSE), "but no more until they are used")
	RunManager.start_run()
	assert_eq(RunManager.get_run_boosts().size(), 3, "all three go into the next run")


func test_migrate_maps_old_ids_of_every_version() -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "version", 2)
	config.set_value("boosts", "pending", PackedStringArray(["gold"]))
	SaveManager.migrate(config)
	assert_eq(config.get_value("boosts", "pending"), PackedStringArray(["gold_rain"]))
	var unknown := ConfigFile.new()
	unknown.set_value("meta", "version", 5)
	unknown.set_value("boosts", "pending", PackedStringArray(["something_else"]))
	SaveManager.migrate(unknown)
	assert_eq(unknown.get_value("boosts", "pending"), PackedStringArray(["something_else"]), "unknown ids stay untouched")


func test_v3_fixture_with_a_packed_potion_keeps_it() -> void:
	_write(FileAccess.get_file_as_string("res://tests/fixtures/save_v3_slot_test.cfg"))
	assert_eq(SaveManager.load_game(), OK)
	assert_true(SaveManager.has_pending_boost(MetaProgression.BOOST_HEALING_POTION))


# --- Trading post page ---

func _open_trader(crystals: int) -> VillageUI:
	SaveManager.mark_seen(VillageBuildings.get_intro_key(VillageBuildings.TRADER))
	SaveManager.add_permanent_crystals(crystals)
	var ui := VillageUI.new()
	add_child_autofree(ui)
	ui.open_trader()
	return ui


func test_page_shows_every_provision_and_trade_level() -> void:
	var ui := _open_trader(10)
	var modal := ui.get_building_modal()
	assert_not_null(modal)
	for id in MetaProgression.BOOST_ORDER:
		var button := modal.find_child("Boost_%s" % id, true, false) as Button
		assert_not_null(button, "%s offered" % id)
		var card := modal.find_child("Provision_%s" % id, true, false)
		var icon := card.find_children("*", "TextureRect", true, false)[0] as TextureRect
		assert_eq(icon.texture.resource_path, ICON_DIR + "boost_%s.png" % id, "%s shows its delivered icon" % id)
	for id in MetaProgression.TRADE_ORDER:
		var buy := modal.find_child("BuyTrade_%s" % id, true, false) as Button
		assert_not_null(buy, "%s offered" % id)
		var step := buy.get_parent().find_child("StepLabel", true, false) as Label
		assert_eq(step.text, MetaProgression.describe_next_trade_level(id))
	var slots := modal.find_child("ProvisionSlotsLabel", true, false) as Label
	assert_eq(slots.text, "Eingepackt: 0 von 1 Plätzen")
	modal.finish()


func test_page_buys_a_trade_level_and_shows_full_slots() -> void:
	var ui := _open_trader(20)
	var modal := ui.get_building_modal()
	(modal.find_child("Boost_%s" % MetaProgression.BOOST_KEEN_NOSE, true, false) as Button).pressed.emit()
	await _frames(2)
	assert_true(SaveManager.has_pending_boost(MetaProgression.BOOST_KEEN_NOSE))
	var packed := modal.find_child("Boost_%s" % MetaProgression.BOOST_KEEN_NOSE, true, false) as Button
	assert_eq(packed.text, "Eingepackt")
	var other := modal.find_child("Boost_%s" % MetaProgression.BOOST_CLEAR_SIGHT, true, false) as Button
	assert_true(other.disabled, "the only slot is packed")
	assert_eq((other.get_parent().find_child("SlotsFullLabel", true, false) as Label).text, "Kein Platz frei")
	(modal.find_child("BuyTrade_%s" % MetaProgression.TRADE_PROVISION_SLOT, true, false) as Button).pressed.emit()
	await _frames(2)
	assert_eq(MetaProgression.get_trade_level(MetaProgression.TRADE_PROVISION_SLOT), 1)
	assert_eq(SaveManager.get_permanent_crystals(), 20 - 2 - 8)
	other = modal.find_child("Boost_%s" % MetaProgression.BOOST_CLEAR_SIGHT, true, false) as Button
	assert_false(other.disabled, "a second slot is free")
	assert_eq((modal.find_child("ProvisionSlotsLabel", true, false) as Label).text, "Eingepackt: 1 von 2 Plätzen")
	modal.finish()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

extends GutTest
## Save format v5 (KE4, KONZEPT §5.1, D-059): the migration v4 -> v5 with one check per field
## (refund of Vitalität, Schärfe, Goldgier and Dash-Training once per world, Startschild ->
## Schildplatte, Arsenal -> unlocked weapons and second start slot, start weapon, world id, trading
## post levels, the village notice), real v4 files and fresh worlds. Uses a test save file only.

const TEST_PATH := "user://test_save_v5.cfg"
## A copy of a real v4 world of the project member (22.10.2026, no forge levels).
const FIXTURE_V4_REAL := "res://tests/fixtures/save_v4_real.cfg"
## A v4 world with every old forge upgrade bought (built from the v3 fixture's format).
const FIXTURE_V4_FORGE := "res://tests/fixtures/save_v4_forge_test.cfg"
const FIXTURE_V2_LEGACY := "res://tests/fixtures/save_v2_legacy.cfg"

var _old_locale: String
var _old_path: String


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	Loc.apply(&"de")
	_old_path = SaveManager.save_path


func before_each() -> void:
	SaveManager.save_path = TEST_PATH
	_remove_files()
	SaveManager.load_game()


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)
	_remove_files()
	SaveManager.save_path = _old_path
	SaveManager.load_game()


func _remove_files() -> void:
	for suffix in ["", ".bak", ".v2.bak", ".v3.bak", ".v4.bak", ".prev.bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + suffix))


func _write(text: String) -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _v4(upgrades: String, gold := 10, progress := "") -> String:
	return "[meta]\nversion=4\n[progress]\npermanent_gold=%d\n%s\n[meta_upgrades]\n%s\n" % [gold, progress, upgrades]


func _load_v4(upgrades: String, gold := 10, progress := "") -> void:
	_write(_v4(upgrades, gold, progress))
	assert_eq(SaveManager.load_game(), OK, "v4 loads")


func _saved() -> ConfigFile:
	assert_eq(SaveManager.save_game(), OK)
	var config := ConfigFile.new()
	assert_eq(config.load(TEST_PATH), OK)
	return config


# --- One check per field ---

func test_version_is_5() -> void:
	assert_eq(SaveManager.SAVE_VERSION, 5)
	_load_v4("")
	assert_eq(_saved().get_value("meta", "version"), 5)


func test_vitality_is_refunded() -> void:
	_load_v4("vitality=5")
	assert_eq(SaveManager.get_permanent_gold(), 10 + 20 + 80 + 140 + 220 + 320)
	assert_eq(SaveManager.get_meta_level(&"vitality"), 0)
	assert_false(_saved().has_section_key("meta_upgrades", "vitality"), "gone from the file")


func test_sharpness_is_refunded() -> void:
	_load_v4("sharpness=2")
	assert_eq(SaveManager.get_permanent_gold(), 10 + 70 + 150)
	assert_false(_saved().has_section_key("meta_upgrades", "sharpness"))


func test_gold_greed_is_refunded() -> void:
	_load_v4("gold_greed=3")
	assert_eq(SaveManager.get_permanent_gold(), 10 + 60 + 140 + 250)
	assert_almost_eq(MetaProgression.get_gold_multiplier(), 1.0, 0.0001, "no Goldgier effect any more")


func test_dash_training_is_refunded() -> void:
	_load_v4("dash_training=1")
	assert_eq(SaveManager.get_permanent_gold(), 10 + 60)


func test_levels_above_the_old_maximum_refund_the_maximum() -> void:
	assert_eq(SaveManager.refund_for_level("sharpness", 99), 70 + 150 + 260 + 400)
	assert_eq(SaveManager.refund_for_level("vitality", 0), 0)
	assert_eq(SaveManager.refund_for_level("start_shield", 3), 0, "kept upgrades are not refunded")


func test_start_shield_becomes_shield_plate() -> void:
	_load_v4("start_shield=2")
	assert_eq(MetaProgression.get_level(MetaProgression.SHIELD_PLATE), 2)
	assert_eq(SaveManager.get_permanent_gold(), 10, "same level, no refund")
	var config := _saved()
	assert_eq(config.get_value("meta_upgrades", "shield_plate"), 2)
	assert_false(config.has_section_key("meta_upgrades", "start_shield"))
	_load_v4("start_shield=7")
	assert_eq(MetaProgression.get_level(MetaProgression.SHIELD_PLATE), 3, "at most 3")


func test_arsenal_1_unlocks_the_bow() -> void:
	_load_v4("arsenal=1")
	assert_eq(MetaProgression.get_unlocked_weapons(), [MetaProgression.WEAPON_SWORD, MetaProgression.WEAPON_BOW] as Array[StringName])
	assert_true(MetaProgression.has_second_slot(), "the old Arsenal started with two weapons: kept")
	assert_eq(MetaProgression.get_start_weapons(), [MetaProgression.WEAPON_SWORD, MetaProgression.WEAPON_BOW] as Array[StringName],
		"v4 started with the bow even without a choice")
	assert_false(_saved().has_section_key("meta_upgrades", "arsenal"))


func test_arsenal_2_unlocks_bow_and_staff_and_keeps_the_choice() -> void:
	_load_v4("arsenal=2", 10, "second_weapon=\"staff\"")
	assert_eq(MetaProgression.get_unlocked_weapons(),
		[MetaProgression.WEAPON_SWORD, MetaProgression.WEAPON_BOW, MetaProgression.WEAPON_STAFF] as Array[StringName])
	assert_eq(MetaProgression.get_second_weapon(), MetaProgression.WEAPON_STAFF, "the old second weapon stays")
	assert_false(MetaProgression.is_weapon_unlocked(MetaProgression.WEAPON_DAGGER))
	assert_eq(SaveManager.get_permanent_gold(), 10, "no refund for Arsenal")


func test_start_weapon_defaults_to_the_sword() -> void:
	_load_v4("")
	assert_eq(SaveManager.get_start_weapon(), &"sword")
	assert_eq(_saved().get_value("progress", "start_weapon"), "sword")


func test_world_gets_an_id_that_stays() -> void:
	_load_v4("")
	var id := SaveManager.get_world_id()
	assert_true(SaveManager.is_valid_world_id(id), "UUID: %s" % id)
	assert_eq(_saved().get_value("world", "id"), id, "written as [world] id")
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_world_id(), id, "the same after reloading")
	assert_eq(SaveManager.migrate(_config_from(_v4(""))), 4)
	assert_ne(_migrated_id(), id, "another world gets another id")


func test_invalid_world_id_is_replaced() -> void:
	_write("[meta]\nversion=5\n[progress]\npermanent_gold=3\n[world]\nid=\"not-a-uuid\"\n")
	assert_eq(SaveManager.load_game(), OK, "an id is not worth rejecting the world")
	assert_true(SaveManager.is_valid_world_id(SaveManager.get_world_id()))
	assert_eq(SaveManager.get_permanent_gold(), 3)


func test_trade_levels_get_their_defaults() -> void:
	_load_v4("")
	var config := _saved()
	for key: String in ["provision_slot", "luck", "merchant_friend"]:
		assert_eq(config.get_value("trade_levels", key), 0, key)
		assert_eq(SaveManager.get_trade_level(StringName(key)), 0, key)


func test_trade_levels_persist_and_drop_invalid_values() -> void:
	SaveManager.set_trade_level(&"luck", 2)
	SaveManager.set_trade_level(&"provision_slot", 1)
	assert_eq(SaveManager.save_game(), OK)
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_trade_level(&"luck"), 2)
	assert_eq(SaveManager.get_trade_level(&"provision_slot"), 1)
	_write("[meta]\nversion=5\n[progress]\npermanent_gold=9\n[trade_levels]\nluck=\"many\"\nmerchant_friend=-2\n")
	assert_eq(SaveManager.load_game(), OK, "invalid trade levels are dropped, not fatal")
	assert_eq(SaveManager.get_trade_level(&"luck"), 0)
	assert_eq(SaveManager.get_trade_level(&"merchant_friend"), 0)
	assert_eq(SaveManager.get_permanent_gold(), 9)


func test_refund_happens_once_per_world() -> void:
	_load_v4("vitality=1")
	assert_eq(SaveManager.get_permanent_gold(), 30)
	assert_eq(SaveManager.save_game(), OK)
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_permanent_gold(), 30, "not again after saving and loading")
	# A v4 state that already carries the marker (e.g. merged with a migrated cloud state) is not paid twice.
	_write(_v4("vitality=1") + "[migration]\nv5_refund_gold=20\n")
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_permanent_gold(), 10, "the marker wins")
	assert_eq(SaveManager.get_meta_level(&"vitality"), 0)


func test_migration_report_and_village_notice() -> void:
	_write(FileAccess.get_file_as_string(FIXTURE_V4_FORGE))
	assert_eq(SaveManager.load_game(), OK)
	var report := SaveManager.get_v5_report()
	assert_eq(report["refund_gold"], 680)
	assert_eq(report["refunded"], PackedStringArray(["vitality:2", "sharpness:1", "gold_greed:3", "dash_training:1"]))
	assert_eq(report["shield_plate"], 2)
	assert_eq(report["weapons"], PackedStringArray(["bow", "staff"]))
	assert_true(SaveManager.is_v5_notice_pending())
	var lines := MetaProgression.take_migration_notice()
	assert_eq(lines, [
		"680 Gold zurück für Vitalität II, Schärfe I, Goldgier III und Dash-Training I.",
		"Startschild ist jetzt Schildplatte II.",
		"Als Startwaffen frei: Bogen und Stab.",
		"Vitalität und Dash-Training gibt es jetzt im Talentbaum im Zuhause.",
	] as Array[String])
	assert_true(MetaProgression.take_migration_notice().is_empty(), "only once")
	assert_eq(SaveManager.save_game(), OK)
	assert_eq(SaveManager.load_game(), OK)
	assert_false(SaveManager.is_v5_notice_pending(), "also after reloading")
	assert_eq(SaveManager.get_v5_report()["refund_gold"], 680, "the report itself stays (merge marker)")


func test_no_notice_when_nothing_changed() -> void:
	_load_v4("")
	assert_false(SaveManager.is_v5_notice_pending())
	assert_true(MetaProgression.take_migration_notice().is_empty())
	assert_eq(SaveManager.get_v5_report()["refund_gold"], 0)


func test_fresh_world_has_no_migration() -> void:
	assert_true(SaveManager.get_v5_report().is_empty())
	var config := _saved()
	assert_eq(config.get_value("meta", "version"), 5)
	assert_true(SaveManager.is_valid_world_id(config.get_value("world", "id")))
	assert_false(config.has_section("migration"))


func test_invalid_old_levels_are_still_rejected() -> void:
	_write(_v4("sharpness=\"high\""))
	assert_eq(SaveManager.load_game(), ERR_INVALID_DATA, "the migration leaves invalid values for the check")
	assert_eq(SaveManager.get_permanent_gold(), 0)


func test_backup_before_the_migration() -> void:
	var original := _v4("vitality=1")
	_write(original)
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(FileAccess.get_file_as_string(TEST_PATH + ".v4.bak"), original, "byte for byte")
	assert_eq(FileAccess.get_file_as_string(TEST_PATH), original, "loading alone does not rewrite the file")


# --- Real files ---

func test_real_v4_world_loads_without_loss() -> void:
	var original := FileAccess.get_file_as_string(FIXTURE_V4_REAL)
	assert_false(original.is_empty(), "fixture exists")
	_write(original)
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_permanent_gold(), 13)
	assert_eq(SaveManager.get_permanent_crystals(), 1)
	assert_eq(SaveManager.get_world_name(), "Test")
	assert_eq(SaveManager.get_stat(StatsTracker.DEEPEST_ROOM), 63)
	assert_true(MetaUnlocks.has_event(MetaUnlocks.EVENT_FIRST_BOSS))
	assert_true(SaveManager.has_seen(&"room_intro_shop"))
	assert_false(SaveManager.is_v5_notice_pending(), "nothing to say: no old forge levels")
	assert_eq(MetaProgression.get_start_weapons(), [MetaProgression.WEAPON_SWORD] as Array[StringName])
	var config := _saved()
	assert_eq(config.get_value("meta", "version"), 5)
	assert_eq(config.get_value("profile", "created"), 1792638786)
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_permanent_gold(), 13, "the same after saving and reloading")


func test_v4_forge_world_loads_everything() -> void:
	_write(FileAccess.get_file_as_string(FIXTURE_V4_FORGE))
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_permanent_gold(), 120 + 680)
	assert_eq(SaveManager.get_permanent_crystals(), 4)
	assert_true(SaveManager.has_pending_boost(MetaProgression.BOOST_GOLD_RAIN), "packed Goldbeutel stays, as Goldregen (KE5)")
	assert_eq(MetaProgression.get_level(MetaProgression.SHIELD_PLATE), 2)
	assert_eq(MetaProgression.get_start_weapons(), [MetaProgression.WEAPON_SWORD, MetaProgression.WEAPON_STAFF] as Array[StringName])
	assert_eq(SaveManager.get_world_display_name(), "Schmiedetal")
	assert_eq(SaveManager.get_stat(StatsTracker.KILLS), 700)


func test_v2_legacy_save_goes_through_every_step() -> void:
	_write(FileAccess.get_file_as_string(FIXTURE_V2_LEGACY))
	assert_eq(SaveManager.load_game(), OK)
	# v3 (D-087): Vitalität 3, Startschild 2, Schärfe 1, Dash 2, Goldgier 1, Arsenal 1; v5 refunds 570.
	assert_eq(SaveManager.get_permanent_gold(), 54 + 570)
	assert_eq(MetaProgression.get_level(MetaProgression.SHIELD_PLATE), 2)
	assert_true(MetaProgression.is_weapon_unlocked(MetaProgression.WEAPON_BOW))
	assert_true(SaveManager.is_valid_world_id(SaveManager.get_world_id()))
	assert_true(FileAccess.file_exists(TEST_PATH + ".v2.bak"), "backed up as the version it was")


# --- Helpers ---

func _config_from(text: String) -> ConfigFile:
	var config := ConfigFile.new()
	config.parse(text)
	return config


func _migrated_id() -> String:
	var config := _config_from(_v4(""))
	SaveManager.migrate(config)
	return String(config.get_value("world", "id"))

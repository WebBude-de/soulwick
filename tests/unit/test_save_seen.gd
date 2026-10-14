extends GutTest
## "Seen" flags for one-time explanations (D-087) in the save: persist, a fresh game has seen
## nothing, saves written before the [seen] section existed count as "everything seen" and lose no
## progress. Uses a test save file only.

const TEST_PATH := "user://test_save_seen.cfg"
## A complete v2 save as written before D-087 (no [seen] section).
const OLD_V2_SAVE := """[meta]
version=2
[progress]
permanent_gold=57
permanent_crystals=3
unlocked=PackedStringArray("hint_archer", "hint_slime")
second_weapon="bow"
[meta_upgrades]
vitality=2
start_shield=1
sharpness=3
dash_training=1
gold_greed=2
arsenal=1
[boosts]
pending=PackedStringArray("potion")
[stats]
play_time=1234.5
runs=7
kills=402
[settings]
volume_music=0.6
volume_sfx=0.9
"""

var _old_locale: String
var _old_path: String


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	# The expected texts are German; English is the default language (D-111).
	Loc.apply(&"de")
	_old_path = SaveManager.save_path


func before_each() -> void:
	SaveManager.save_path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + ".bak"))
	SaveManager.load_game()


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + ".bak"))
	for version in [1, 2]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + SaveManager.MIGRATION_BACKUP_SUFFIX % version))
	SaveManager.save_path = _old_path
	SaveManager.load_game()


func _write(text: String) -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_fresh_game_has_seen_nothing() -> void:
	assert_false(SaveManager.has_seen(&"intro_forge"))
	for id in VillageBuildings.ORDER:
		assert_true(VillageBuildings.needs_intro(id), String(id))


func test_mark_seen_once_and_persist() -> void:
	watch_signals(SaveManager)
	assert_true(SaveManager.mark_seen(&"intro_forge"))
	assert_false(SaveManager.mark_seen(&"intro_forge"), "second time is not new")
	assert_signal_emit_count(SaveManager, "seen_changed", 1)
	assert_eq(SaveManager.save_game(), OK)
	assert_eq(SaveManager.load_game(), OK)
	assert_true(SaveManager.has_seen(&"intro_forge"))
	assert_false(SaveManager.has_seen(&"intro_trader"), "other flags stay unseen")


func test_new_save_always_writes_seen_section() -> void:
	assert_eq(SaveManager.save_game(), OK)
	var config := ConfigFile.new()
	assert_eq(config.load(TEST_PATH), OK)
	assert_true(config.has_section("seen"), "even when nothing was seen yet")
	assert_eq(config.get_value("seen", "all"), false)
	assert_eq(config.get_value("meta", "version"), SaveManager.SAVE_VERSION)
	assert_eq(SaveManager.load_game(), OK)
	assert_false(SaveManager.has_seen(&"intro_forge"), "a new empty save is not treated as old")


func test_old_v2_save_loads_without_loss_and_counts_as_all_seen() -> void:
	_write(OLD_V2_SAVE)
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_permanent_gold(), 57)
	assert_eq(SaveManager.get_permanent_crystals(), 3)
	assert_true(SaveManager.is_unlocked(&"hint_archer"))
	assert_eq(SaveManager.get_meta_level(MetaProgression.SHARPNESS), 2, "v3: 3 x 5 % -> 2 x 10 % (D-087)")
	assert_eq(SaveManager.get_meta_level(MetaProgression.ARSENAL), 1)
	assert_eq(SaveManager.get_second_weapon(), MetaProgression.WEAPON_BOW)
	assert_true(SaveManager.has_pending_boost(MetaProgression.BOOST_POTION))
	assert_eq(SaveManager.get_stat(StatsTracker.KILLS), 402)
	assert_eq(SaveManager.get_display_name(), "Spielstand 1", "no [profile]: default name")
	assert_eq(SaveManager.get_character_id(), CharacterCatalog.DEFAULT_ID, "no [profile]: default character")
	for id in VillageBuildings.ORDER:
		assert_false(VillageBuildings.needs_intro(id), "old save: %s already explained (D-087)" % id)
	assert_false(FileAccess.file_exists(TEST_PATH + ".bak"), "not rejected")


func test_old_save_stays_all_seen_after_resave() -> void:
	_write(OLD_V2_SAVE)
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.save_game(), OK)
	assert_eq(SaveManager.load_game(), OK)
	assert_true(SaveManager.has_seen(&"intro_guild"))
	assert_true(SaveManager.has_seen(&"any_future_explanation"), "all seen survives the first save")
	assert_eq(SaveManager.get_permanent_gold(), 57)


func test_v1_save_counts_as_all_seen() -> void:
	_write("[meta]\nversion=1\n[progress]\npermanent_gold=9\n")
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_permanent_gold(), 9)
	assert_true(SaveManager.has_seen(&"intro_forge"))


func test_migrate_marks_missing_seen_section() -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "version", 2)
	config.set_value("progress", "permanent_gold", 5)
	assert_eq(SaveManager.migrate(config), 2)
	assert_eq(config.get_value("seen", "all"), true)
	var current := ConfigFile.new()
	current.set_value("meta", "version", 2)
	current.set_value("seen", "all", false)
	current.set_value("seen", "ids", PackedStringArray(["intro_forge"]))
	SaveManager.migrate(current)
	assert_eq(current.get_value("seen", "all"), false, "an existing [seen] section is kept")


func test_invalid_seen_values_are_dropped_not_fatal() -> void:
	_write("[meta]\nversion=2\n[progress]\npermanent_gold=50\n[seen]\nall=\"yes\"\nids=42\n")
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_permanent_gold(), 50)
	assert_false(SaveManager.has_seen(&"intro_forge"))


func test_rejected_save_starts_unseen() -> void:
	_write("[meta]\nversion=2\n[progress]\npermanent_gold=-1\n")
	assert_eq(SaveManager.load_game(), ERR_INVALID_DATA)
	assert_true(FileAccess.file_exists(TEST_PATH + ".bak"), "broken file is backed up")
	assert_false(SaveManager.has_seen(&"intro_forge"))


func test_old_save_still_shows_the_boss_story() -> void:
	_write(OLD_V2_SAVE)
	assert_eq(SaveManager.load_game(), OK)
	assert_true(SaveManager.has_seen(&"intro_forge"), "village explanations count as seen (D-087)")
	assert_false(SaveManager.has_seen(&"boss_intro_bone_king"), "the boss story is new content (BI2)")
	assert_true(SaveManager.mark_seen(&"boss_intro_bone_king"), "can be marked once")
	assert_false(SaveManager.mark_seen(&"boss_intro_bone_king"))
	assert_eq(SaveManager.save_game(), OK)
	assert_eq(SaveManager.load_game(), OK)
	assert_true(SaveManager.has_seen(&"boss_intro_bone_king"), "persisted")
	assert_false(SaveManager.has_seen(&"boss_intro_slime_queen"))
	assert_true(SaveManager.has_seen(&"intro_guild"), "all seen survives the save")

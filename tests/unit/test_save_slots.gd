extends GutTest
## Save slots and global settings (MM1): the pre-slot save lands unchanged in slot 1 exactly once,
## new slots start fresh (village explanations, D-087), profile and settings persist, deleting is
## safe. Works only in a test folder (SaveManager.set_storage_root), never on the real save.

const ROOT := "user://test_save_slots"
## A real v2 save of the project member (14.10.2026, before slots), with [seen] and [settings].
const REAL_V2_SAVE := """[meta]

version=2

[progress]

permanent_gold=54
permanent_crystals=6
unlocked=PackedStringArray("hint_archer", "hint_slime", "hint_champion", "hint_elite_swift", "hint_skeleton", "hint_shadow", "hint_elite_volatile", "hint_boss_bone_king", "hint_boss_phase", "hint_splitter_slime", "hint_bomber", "hint_elite_armored", "hint_boss_slime_queen", "hint_necromancer", "hint_boss_shadow_lord")
second_weapon="bow"

[meta_upgrades]

vitality=3
start_shield=2
sharpness=2
dash_training=2
gold_greed=1
arsenal=1

[boosts]

pending=PackedStringArray()

[stats]

play_time=4133.238631715503
runs=12
deepest_room=45
kills=1017
rooms_cleared=177
champions=24
bosses=9
exits=2
gold_earned=1012
best_run_gold=448
gold_banked=545
crystals_earned=22
deaths=2

[seen]

all=true
ids=PackedStringArray()

[settings]

volume_music=0.45
volume_sfx=1.0
"""
## A v2 save written before D-087 (no [seen]) and before slots.
const OLD_V2_NO_SEEN := "[meta]\nversion=2\n[progress]\npermanent_gold=12\n[settings]\nvolume_music=0.3\n"

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path


func before_each() -> void:
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()


func after_all() -> void:
	_wipe()
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()


func _wipe() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	for dir_path in [root.path_join("saves"), root]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			DirAccess.remove_absolute(dir_path.path_join(file))
	DirAccess.remove_absolute(root.path_join("saves"))
	DirAccess.make_dir_recursive_absolute(root)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## Writes the old save and re-reads the settings like a fresh game start.
func _install_legacy(text := REAL_V2_SAVE) -> void:
	_write(SaveManager.legacy_save_path, text)
	SaveManager.set_storage_root(ROOT)


func test_paths_point_into_the_test_folder() -> void:
	assert_true(SaveManager.saves_dir.begins_with(ROOT))
	assert_true(SaveManager.settings_path.begins_with(ROOT))
	assert_true(SaveManager.legacy_save_path.begins_with(ROOT))
	assert_eq(SaveManager.slot_path(2), ROOT.path_join("saves/slot_2.cfg"))


func test_old_save_is_copied_unchanged_into_slot_1() -> void:
	_install_legacy()
	assert_true(SaveManager.needs_legacy_import())
	assert_eq(SaveManager.import_legacy_save_into_slot(), 1)
	assert_eq(_read(SaveManager.slot_path(1)), REAL_V2_SAVE, "byte for byte")
	assert_eq(_read(SaveManager.legacy_save_path), REAL_V2_SAVE, "old file stays as it is")
	assert_eq(SaveManager.get_active_slot(), 1)
	assert_eq(SaveManager.get_permanent_gold(), 54)
	assert_eq(SaveManager.get_permanent_crystals(), 6)
	assert_eq(SaveManager.get_meta_level(MetaProgression.VITALITY), 3)
	assert_eq(SaveManager.get_second_weapon(), MetaProgression.WEAPON_BOW)
	assert_eq(SaveManager.get_stat(StatsTracker.DEEPEST_ROOM), 45)
	assert_true(SaveManager.is_unlocked(&"hint_boss_shadow_lord"))
	assert_true(SaveManager.has_seen(&"intro_forge"), "old save: everything seen (D-087)")
	assert_false(SaveManager.has_seen(&"boss_intro_bone_king"), "except the new boss story (BI2)")
	assert_false(FileAccess.file_exists(SaveManager.slot_path(1) + ".bak"), "not rejected")


func test_old_save_without_seen_section_still_counts_as_seen_in_slot() -> void:
	_install_legacy(OLD_V2_NO_SEEN)
	assert_eq(SaveManager.import_legacy_save_into_slot(), 1)
	assert_eq(SaveManager.get_permanent_gold(), 12)
	for id in VillageBuildings.ORDER:
		assert_false(VillageBuildings.needs_intro(id), String(id))


func test_volume_of_the_old_save_becomes_the_global_setting() -> void:
	_install_legacy()
	assert_almost_eq(SaveManager.get_volume(&"Music"), 0.45, 0.0001, "read before the import")
	SaveManager.import_legacy_save_into_slot()
	var settings := ConfigFile.new()
	assert_eq(settings.load(SaveManager.settings_path), OK, "settings written by the import")
	assert_almost_eq(float(settings.get_value("audio", "volume_music")), 0.45, 0.0001)
	assert_eq(settings.get_value("slots", "last"), 1)
	assert_eq(settings.get_value("slots", "legacy_imported"), true)


func test_import_happens_only_once() -> void:
	_install_legacy()
	assert_eq(SaveManager.import_legacy_save_into_slot(), 1)
	assert_eq(SaveManager.delete_slot(1), OK)
	SaveManager.set_storage_root(ROOT)
	assert_false(SaveManager.needs_legacy_import())
	assert_eq(SaveManager.import_legacy_save_into_slot(), 0, "a deleted import does not come back")
	assert_false(SaveManager.has_slot(1))


func test_import_takes_the_first_free_slot() -> void:
	assert_eq(SaveManager.create_slot(1, "Neu", CharacterCatalog.DEFAULT_ID, Color("#5fcd62")), OK)
	_install_legacy()
	assert_eq(SaveManager.import_legacy_save_into_slot(), 2, "slot 1 is not overwritten")
	assert_eq(SaveManager.get_slot_summary(1)["name"], "Neu")
	assert_eq(SaveManager.get_slot_summary(2)["gold"], 54)


func test_import_waits_when_all_slots_are_used() -> void:
	for slot in range(1, SaveSlots.SLOT_COUNT + 1):
		SaveManager.create_slot(slot, "S%d" % slot, CharacterCatalog.DEFAULT_ID, Color.WHITE)
	_install_legacy()
	assert_eq(SaveManager.import_legacy_save_into_slot(), 0)
	assert_true(SaveManager.needs_legacy_import(), "tried again once a slot is free")


func test_before_the_import_the_game_keeps_using_the_old_file() -> void:
	_install_legacy()
	assert_eq(SaveManager._startup_save_path(), SaveManager.legacy_save_path)
	SaveManager.import_legacy_save_into_slot()
	assert_eq(SaveManager._startup_save_path(), SaveManager.slot_path(1))


func test_new_slot_starts_fresh_with_village_explanations() -> void:
	_install_legacy()
	SaveManager.import_legacy_save_into_slot()
	assert_eq(SaveManager.create_slot(2, "Lena", CharacterCatalog.DEFAULT_ID, Color("#e0463a")), OK)
	assert_eq(SaveManager.get_active_slot(), 2)
	assert_eq(SaveManager.get_permanent_gold(), 0)
	assert_eq(SaveManager.get_meta_level(MetaProgression.VITALITY), 0)
	assert_eq(SaveManager.get_stat(StatsTracker.RUNS), 0)
	assert_false(SaveManager.has_seen(&"intro_forge"))
	for id in VillageBuildings.ORDER:
		assert_true(VillageBuildings.needs_intro(id), "new slot explains %s (D-087)" % id)
	assert_eq(SaveManager.load_game(), OK)
	assert_false(SaveManager.has_seen(&"intro_guild"), "also after reloading")
	assert_eq(SaveManager.get_slot_summary(1)["gold"], 54, "the old save is untouched")


func test_profile_is_saved_in_the_slot() -> void:
	assert_eq(SaveManager.create_slot(3, "  Mira der Mutige ist lang  ", &"hero", Color("#5fcd62")), OK)
	assert_eq(SaveManager.load_slot(3), OK)
	assert_eq(SaveManager.get_profile_name(), "Mira der Mutige", "trimmed to 16 characters")
	assert_eq(SaveManager.get_character_id(), &"hero")
	assert_eq(SaveManager.get_character_color().to_html(false), "5fcd62")
	assert_gt(SaveManager.get_last_played(), 0)
	var config := ConfigFile.new()
	assert_eq(config.load(SaveManager.slot_path(3)), OK)
	assert_eq(config.get_value("meta", "version"), SaveManager.SAVE_VERSION, "no version bump for [profile]")
	assert_eq(config.get_value("profile", "color"), "5fcd62")
	assert_false(config.has_section("settings"), "volumes are global now")


func test_empty_name_gets_the_slot_name() -> void:
	SaveManager.create_slot(2, "   ", &"hero", Color.WHITE)
	assert_eq(SaveManager.get_profile_name(), "Spielstand 2")


func test_unknown_character_falls_back_to_default() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveManager.saves_dir))
	_write(SaveManager.slot_path(1), "[meta]\nversion=2\n[profile]\ncharacter=\"ghost\"\ncolor=\"nonsense\"\n")
	assert_eq(SaveManager.load_slot(1), OK)
	assert_eq(CharacterCatalog.get_active().id, CharacterCatalog.DEFAULT_ID)
	assert_eq(SaveManager.get_character_color(), CharacterCatalog.get_active().default_color)


func test_create_refuses_used_or_invalid_slots() -> void:
	SaveManager.create_slot(1, "A", &"hero", Color.WHITE)
	assert_eq(SaveManager.create_slot(1, "B", &"hero", Color.WHITE), ERR_ALREADY_EXISTS)
	assert_eq(SaveManager.create_slot(0, "B", &"hero", Color.WHITE), ERR_PARAMETER_RANGE_ERROR)
	assert_eq(SaveManager.create_slot(SaveSlots.SLOT_COUNT + 1, "B", &"hero", Color.WHITE), ERR_PARAMETER_RANGE_ERROR)
	assert_eq(SaveManager.get_slot_summary(1)["name"], "A")


func test_load_slot_switches_progress_and_remembers_it() -> void:
	SaveManager.create_slot(1, "Eins", &"hero", Color.WHITE)
	SaveManager.add_permanent_gold(100)
	SaveManager.save_game()
	SaveManager.create_slot(2, "Zwei", &"hero", Color.WHITE)
	SaveManager.add_permanent_gold(7)
	SaveManager.save_game()
	assert_eq(SaveManager.load_slot(1), OK)
	assert_eq(SaveManager.get_permanent_gold(), 100)
	assert_eq(SaveManager.load_slot(2), OK)
	assert_eq(SaveManager.get_permanent_gold(), 7)
	SaveManager.load_slot(1)
	SaveManager.set_storage_root(ROOT)
	assert_eq(SaveManager.get_continue_slot(), 1, "last slot survives a restart")
	assert_eq(SaveManager.load_slot(3), ERR_FILE_NOT_FOUND)


func test_delete_slot_keeps_one_backup_and_clears_loaded_state() -> void:
	SaveManager.create_slot(1, "Weg", &"hero", Color.WHITE)
	SaveManager.add_permanent_gold(5)
	SaveManager.save_game()
	SaveManager.create_slot(2, "Bleibt", &"hero", Color.WHITE)
	SaveManager.load_slot(1)
	assert_eq(SaveManager.delete_slot(1), OK)
	assert_false(SaveManager.has_slot(1))
	assert_true(FileAccess.file_exists(SaveManager.slot_path(1) + SaveManager.DELETED_SUFFIX))
	assert_eq(SaveManager.get_permanent_gold(), 0, "deleted slot is not kept in memory")
	assert_eq(SaveManager.get_continue_slot(), 2)
	assert_eq(SaveManager.delete_slot(1), ERR_FILE_NOT_FOUND)
	assert_eq(SaveManager.get_free_slot(), 1)


func test_continue_slot_prefers_last_then_most_recent() -> void:
	assert_eq(SaveManager.get_continue_slot(), 0, "no slots yet")
	_write_slot(1, 100)
	_write_slot(3, 300)
	SaveManager.set_storage_root(ROOT)
	assert_eq(SaveManager.get_continue_slot(), 3, "most recently played")
	SaveManager.load_slot(1)
	assert_eq(SaveManager.get_continue_slot(), 1, "last used wins")


func _write_slot(slot: int, last_played: int) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveManager.saves_dir))
	_write(SaveManager.slot_path(slot), "[meta]\nversion=2\n[profile]\nlast_played=%d\n" % last_played)


func test_loading_a_slot_keeps_the_global_volume() -> void:
	SaveManager.set_volume(&"Music", 0.25)
	SaveManager.save_settings()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveManager.saves_dir))
	_write(SaveManager.slot_path(1), "[meta]\nversion=2\n[settings]\nvolume_music=0.9\n")
	SaveManager.load_slot(1)
	assert_almost_eq(SaveManager.get_volume(&"Music"), 0.25, 0.0001)
	SaveManager.set_storage_root(ROOT)
	assert_almost_eq(SaveManager.get_volume(&"Music"), 0.25, 0.0001, "settings file wins")


func test_plain_save_path_api_still_works() -> void:
	SaveManager.save_path = ROOT.path_join("custom.cfg")
	SaveManager.load_game()
	assert_eq(SaveManager.get_active_slot(), 0)
	SaveManager.add_permanent_gold(9)
	assert_eq(SaveManager.save_game(), OK)
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_permanent_gold(), 9)
	assert_eq(SaveManager.get_display_name(), "Spielstand 1")


func test_summary_of_old_and_broken_slots() -> void:
	_install_legacy()
	SaveManager.import_legacy_save_into_slot()
	var summary := SaveManager.get_slot_summary(1)
	assert_true(summary["exists"])
	assert_false(summary["broken"])
	assert_eq(summary["name"], "Spielstand 1")
	assert_eq(summary["deepest_room"], 45)
	assert_eq(summary["crystals"], 6)
	assert_almost_eq(float(summary["play_time"]), 4133.24, 0.01)
	assert_gt(int(summary["last_played"]), 0, "file time for saves without timestamp")
	assert_true(summary["all_seen"])
	_write(SaveManager.slot_path(2), "this is [not a config")
	assert_true(SaveManager.get_slot_summary(2)["broken"])
	assert_false(SaveManager.get_slot_summary(3)["exists"])


func test_name_and_time_formatting() -> void:
	assert_eq(SaveSlots.sanitize_name("  Ana\tBel  ", 1), "AnaBel")
	assert_eq(SaveSlots.sanitize_name("", 3), "Spielstand 3")
	assert_eq(SaveSlots.format_play_time(30.0), "< 1 min")
	assert_eq(SaveSlots.format_play_time(45.0 * 60.0), "45 min")
	assert_eq(SaveSlots.format_play_time(4133.0), "1:08 h")
	assert_eq(SaveSlots.format_last_played(0), "–")
	var now := int(Time.get_unix_time_from_system())
	assert_string_starts_with(SaveSlots.format_last_played(now, now), "heute")
	assert_string_contains(SaveSlots.format_last_played(now - 400 * 86400, now), ".")


func test_import_takes_the_old_volume_even_if_written_late() -> void:
	SaveManager.set_volume(&"Music", 0.8)
	_write(SaveManager.legacy_save_path, REAL_V2_SAVE)
	assert_eq(SaveManager.import_legacy_save_into_slot(), 1)
	assert_almost_eq(SaveManager.get_volume(&"Music"), 0.45, 0.0001)


# --- v2 -> v3 migration in slots (B2, D-087) ---

## Copies of real v2 saves (14.10.2026): the project member's slot "Test" (MM1, [profile] and [seen]
## with all=false) and the pre-slot save (with [settings] and forge levels).
const FIXTURE_SLOT := "res://tests/fixtures/save_v2_slot_test.cfg"
const FIXTURE_LEGACY := "res://tests/fixtures/save_v2_legacy.cfg"


func _install_slot(slot: int, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveManager.saves_dir))
	_write(SaveManager.slot_path(slot), text)


func test_real_v2_slot_migrates_without_loss() -> void:
	var original := FileAccess.get_file_as_string(FIXTURE_SLOT)
	assert_false(original.is_empty(), "fixture exists")
	_install_slot(1, original)
	SaveManager.set_storage_root(ROOT)
	assert_eq(SaveManager.load_slot(1), OK)
	_assert_test_slot("after loading")
	assert_eq(_read(SaveManager.slot_path(1) + ".v2.bak"), original, "untouched copy before the migration")
	assert_false(FileAccess.file_exists(SaveManager.slot_path(1) + ".bak"), "not rejected")
	assert_eq(SaveManager.save_game(), OK)
	var config := ConfigFile.new()
	assert_eq(config.load(SaveManager.slot_path(1)), OK)
	assert_eq(config.get_value("meta", "version"), 3)
	assert_eq(config.get_value("profile", "name"), "Test", "[profile] kept in the file")
	assert_eq(config.get_value("profile", "created"), 1791941206)
	assert_eq(config.get_value("seen", "all"), false, "[seen] kept as it was")
	assert_eq(SaveManager.load_slot(1), OK)
	_assert_test_slot("after saving and reloading")
	assert_eq(SaveManager.get_slot_summary(1)["name"], "Test")
	assert_eq(SaveManager.get_slot_summary(1)["crystals"], 11)


func _assert_test_slot(when: String) -> void:
	assert_eq(SaveManager.get_permanent_gold(), 43, when)
	assert_eq(SaveManager.get_permanent_crystals(), 11, when)
	assert_eq(SaveManager.get_profile_name(), "Test", when)
	assert_eq(SaveManager.get_character_id(), &"hero", when)
	assert_eq(SaveManager.get_character_color().to_html(false), "e0463a", when)
	assert_eq(SaveManager.get_stat(StatsTracker.KILLS), 316, when)
	assert_eq(SaveManager.get_stat(StatsTracker.BOSSES), 3, when)
	assert_almost_eq(float(SaveManager.get_stat(StatsTracker.PLAY_TIME)), 1289.24, 0.01, when)
	assert_true(SaveManager.is_unlocked(&"hint_boss_shadow_lord"), when)
	for id in ["intro_forge", "intro_trader", "intro_chronicle", "intro_guild", "intro_home", "boss_intro_bone_king",
			"boss_intro_slime_queen", "boss_intro_shadow_lord"]:
		assert_true(SaveManager.has_seen(StringName(id)), "%s: %s still seen" % [when, id])
	assert_false(SaveManager.has_seen(&"boss_intro_ember_golem"), "%s: unseen stays unseen" % when)
	for id in VillageBuildings.ALL:
		assert_true(MetaUnlocks.is_building_open(id), "%s: %s open (old save)" % [when, id])
	for id in MetaProgression.UPGRADE_ORDER:
		assert_true(MetaUnlocks.is_upgrade_open(id), "%s: %s open (old save)" % [when, id])
	assert_true(MetaUnlocks.take_announcements().is_empty(), "%s: no unlock message" % when)


func test_legacy_import_is_migrated_with_its_forge_levels() -> void:
	var original := FileAccess.get_file_as_string(FIXTURE_LEGACY)
	_install_legacy(original)
	assert_eq(SaveManager.import_legacy_save_into_slot(), 1)
	assert_eq(_read(SaveManager.legacy_save_path), original, "the old file stays as it is")
	assert_eq(_read(SaveManager.slot_path(1)), original, "the slot copy is only changed by the next save")
	assert_eq(_read(SaveManager.slot_path(1) + ".v2.bak"), original)
	var expected := {
		MetaProgression.VITALITY: 3, MetaProgression.START_SHIELD: 2, MetaProgression.SHARPNESS: 1,
		MetaProgression.DASH_TRAINING: 2, MetaProgression.GOLD_GREED: 1, MetaProgression.ARSENAL: 1,
	}
	for id in expected:
		assert_eq(SaveManager.get_meta_level(id), expected[id], String(id))
	assert_eq(SaveManager.get_permanent_gold(), 54)
	assert_eq(SaveManager.get_second_weapon(), MetaProgression.WEAPON_BOW)
	assert_true(SaveManager.has_seen(&"intro_forge"), "all seen (no ids, all=true)")
	assert_false(SaveManager.has_seen(&"boss_intro_bone_king"), "boss story still excluded (BI2)")
	assert_true(MetaUnlocks.is_upgrade_open(MetaProgression.ARSENAL))
	assert_almost_eq(SaveManager.get_volume(&"Music"), 0.45, 0.0001)


func test_every_slot_is_migrated_when_loaded() -> void:
	for slot in range(1, SaveSlots.SLOT_COUNT + 1):
		_install_slot(slot, "[meta]\nversion=2\n[progress]\npermanent_gold=%d\n[meta_upgrades]\nsharpness=%d\n[profile]\nname=\"S%d\"\n" % [slot * 10, slot * 2, slot])
	SaveManager.set_storage_root(ROOT)
	for slot in range(1, SaveSlots.SLOT_COUNT + 1):
		assert_eq(SaveManager.load_slot(slot), OK)
		assert_eq(SaveManager.get_meta_level(MetaProgression.SHARPNESS), slot, "slot %d: %d x 5 %% -> %d x 10 %%" % [slot, slot * 2, slot])
		assert_eq(SaveManager.get_permanent_gold(), slot * 10)
		assert_eq(SaveManager.get_profile_name(), "S%d" % slot)
		assert_true(FileAccess.file_exists(SaveManager.slot_path(slot) + ".v2.bak"), "slot %d backed up" % slot)
		assert_true(MetaUnlocks.has_event(MetaUnlocks.EVENT_FIRST_BOSS))


func test_new_slot_is_v3_and_starts_locked() -> void:
	assert_eq(SaveManager.create_slot(1, "Neu", CharacterCatalog.DEFAULT_ID), OK)
	var config := ConfigFile.new()
	assert_eq(config.load(SaveManager.slot_path(1)), OK)
	assert_eq(config.get_value("meta", "version"), 3)
	assert_false(MetaUnlocks.is_building_open(VillageBuildings.CHRONICLE))
	assert_false(MetaUnlocks.is_building_open(VillageBuildings.TRADER))
	assert_false(MetaUnlocks.is_upgrade_open(MetaProgression.ARSENAL))
	assert_false(FileAccess.file_exists(SaveManager.slot_path(1) + ".v2.bak"), "nothing to migrate")

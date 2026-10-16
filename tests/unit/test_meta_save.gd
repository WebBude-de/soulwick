extends GutTest
## Save format (D-059, D-078, D-087): migration from v1 keeps gold, v2 -> v3 converts every old forge
## level to the shorter table and counts as "everything unlocked", the untouched old file is kept as
## *.v2.bak, new values persist, invalid values are rejected. Uses a test save file only.

const TEST_PATH := "user://test_meta_save.cfg"
## Old v2 maximum per upgrade (KONZEPT_ENDLOS §6 before D-087) and the expected v3 level for every
## old level 0..max (D-087: new level = old effect rounded up to the new step, at most the new max).
const V2_TO_V3 := {
	"vitality": [0, 1, 2, 3, 4, 5],
	"start_shield": [0, 1, 2, 2, 3, 3],
	"sharpness": [0, 1, 1, 2, 2, 3, 3, 4, 4],
	"gold_greed": [0, 1, 2, 2, 3, 3],
	"dash_training": [0, 1, 2, 3],
	"arsenal": [0, 1, 2],
}

var _old_path: String


func before_all() -> void:
	_old_path = SaveManager.save_path


func before_each() -> void:
	SaveManager.save_path = TEST_PATH
	_remove_files()
	SaveManager.load_game()


func after_all() -> void:
	_remove_files()
	SaveManager.save_path = _old_path
	SaveManager.load_game()


func _remove_files() -> void:
	# P1-8: also the last good copy (.prev.bak), else it stands in for a broken test file.
	for suffix in ["", ".bak", ".v1.bak", ".v2.bak", ".prev.bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + suffix))


func _write(text: String) -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _v2_with_level(id: String, level: int) -> String:
	return "[meta]\nversion=2\n[progress]\npermanent_gold=10\n[meta_upgrades]\n%s=%d\n" % [id, level]


func test_v1_save_is_migrated_and_keeps_gold() -> void:
	_write("[meta]\nversion=1\n[progress]\npermanent_gold=123\nunlocked=PackedStringArray(\"forge\")\n[settings]\nvolume_music=0.5\n")
	var volume_before := SaveManager.get_volume(&"Music")
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_permanent_gold(), 123)
	assert_true(SaveManager.is_unlocked(&"forge"))
	assert_eq(SaveManager.get_permanent_crystals(), 0)
	assert_eq(SaveManager.get_meta_level(MetaProgression.VITALITY), 0)
	assert_true(SaveManager.get_pending_boosts().is_empty())
	# Volume is a global setting since MM1: migrated by load_settings (test_save_slots.gd), not per save.
	assert_eq(SaveManager.get_volume(&"Music"), volume_before, "loading a save keeps the global volume")
	assert_eq(SaveManager.save_game(), OK)
	var config := ConfigFile.new()
	config.load(TEST_PATH)
	assert_eq(config.get_value("meta", "version"), SaveManager.SAVE_VERSION, "written as the new version")
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_permanent_gold(), 123)


func test_migrate_reports_source_version() -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "version", 1)
	config.set_value("progress", "permanent_gold", 5)
	assert_eq(SaveManager.migrate(config), 1)
	assert_eq(config.get_value("meta", "version"), SaveManager.SAVE_VERSION)
	assert_eq(SaveManager.SAVE_VERSION, 4)
	assert_eq(config.get_value("progress", "permanent_crystals"), 0)
	assert_eq(config.get_value("progress", "permanent_gold"), 5)


# --- v2 -> v3 (B2, D-087) ---

func test_every_old_level_is_converted_by_the_rule() -> void:
	for id: String in V2_TO_V3:
		var expected: Array = V2_TO_V3[id]
		for old_level in expected.size():
			assert_eq(SaveManager.migrate_level_to_v3(id, old_level), expected[old_level], "%s %d" % [id, old_level])


func test_every_old_level_loads_as_the_new_level() -> void:
	for id: String in V2_TO_V3:
		var expected: Array = V2_TO_V3[id]
		for old_level in expected.size():
			_write(_v2_with_level(id, old_level))
			assert_eq(SaveManager.load_game(), OK, "%s %d loads" % [id, old_level])
			assert_eq(SaveManager.get_meta_level(StringName(id)), expected[old_level], "%s %d" % [id, old_level])
			assert_lte(expected[old_level], MetaProgression.get_max_level(StringName(id)), "never above the new max")
			assert_eq(SaveManager.get_permanent_gold(), 10, "no gold refunded")


func test_migrated_effect_is_never_lower_except_at_the_cap() -> void:
	# Old effect per level (v2): shield 2, sharpness 5 %, greed 10 %.
	var old_steps := {"start_shield": 2.0, "sharpness": 0.05, "gold_greed": 0.10}
	var new_steps := {"start_shield": MetaProgression.SHIELD_PER_LEVEL, "sharpness": MetaProgression.DAMAGE_PER_LEVEL,
		"gold_greed": MetaProgression.GOLD_PER_LEVEL}
	for id: String in old_steps:
		var expected: Array = V2_TO_V3[id]
		var max_level := MetaProgression.get_max_level(StringName(id))
		for old_level in expected.size():
			var old_effect: float = old_level * old_steps[id]
			var new_effect: float = expected[old_level] * new_steps[id]
			if expected[old_level] < max_level:
				assert_true(new_effect >= old_effect - 0.0001, "%s %d: %.2f -> %.2f" % [id, old_level, old_effect, new_effect])
			else:
				assert_almost_eq(new_effect, max_level * float(new_steps[id]), 0.0001, "%s %d capped" % [id, old_level])


func test_levels_above_the_old_max_are_capped() -> void:
	_write(_v2_with_level("sharpness", 99))
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_meta_level(MetaProgression.SHARPNESS), 4)
	assert_eq(SaveManager.migrate_level_to_v3("unknown_upgrade", 7), 7, "unknown ids keep their level")


func test_v3_save_is_not_converted_again() -> void:
	_write("[meta]\nversion=3\n[progress]\npermanent_gold=1\n[meta_upgrades]\nsharpness=4\nstart_shield=3\n")
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_meta_level(MetaProgression.SHARPNESS), 4)
	assert_eq(SaveManager.get_meta_level(MetaProgression.START_SHIELD), 3)
	assert_false(FileAccess.file_exists(TEST_PATH + ".v2.bak"), "no backup without a migration")
	assert_false(MetaUnlocks.has_event(MetaUnlocks.EVENT_FIRST_BOSS), "a v3 save is not unlocked by the migration")


func test_old_save_counts_as_everything_unlocked() -> void:
	_write("[meta]\nversion=2\n[progress]\npermanent_gold=5\nunlocked=PackedStringArray(\"hint_slime\")\n[seen]\nall=false\nids=PackedStringArray(\"intro_forge\")\n")
	assert_eq(SaveManager.load_game(), OK)
	for event in MetaUnlocks.EVENTS:
		assert_true(MetaUnlocks.has_event(event), String(event))
	for id in VillageBuildings.ALL:
		assert_true(MetaUnlocks.is_building_open(id), String(id))
	for id in MetaProgression.UPGRADE_ORDER:
		assert_true(MetaUnlocks.is_upgrade_open(id), String(id))
	assert_true(SaveManager.is_unlocked(&"hint_slime"), "old unlocks are kept")
	assert_true(MetaUnlocks.take_announcements().is_empty(), "no 'Neu freigeschaltet' for old saves")
	assert_true(SaveManager.has_seen(&"intro_forge"), "seen ids are kept")
	assert_false(SaveManager.has_seen(&"intro_guild"), "a v2 [seen] section is not turned into 'all seen'")


func test_migration_constants_match_meta_unlocks() -> void:
	var events: Array[String] = []
	var keys: Array[String] = []
	for event in MetaUnlocks.EVENTS:
		events.append(String(event))
		keys.append(String(MetaUnlocks.get_announce_key(event)))
	assert_eq(SaveManager.V3_UNLOCKED_EVENTS, events)
	assert_eq(SaveManager.V3_ANNOUNCED_IDS, keys)
	for id: String in SaveManager.V3_LEVEL_RULES:
		assert_eq(int(SaveManager.V3_LEVEL_RULES[id][2]), MetaProgression.get_max_level(StringName(id)), id)


func test_migration_keeps_a_backup_of_the_old_file() -> void:
	var original := _v2_with_level("sharpness", 5)
	_write(original)
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(FileAccess.get_file_as_string(TEST_PATH + ".v2.bak"), original, "byte for byte")
	assert_eq(FileAccess.get_file_as_string(TEST_PATH), original, "loading alone does not rewrite the file")
	assert_eq(SaveManager.save_game(), OK)
	var config := ConfigFile.new()
	assert_eq(config.load(TEST_PATH), OK)
	assert_eq(config.get_value("meta", "version"), SaveManager.SAVE_VERSION)
	assert_eq(config.get_value("meta_upgrades", "sharpness"), 3)
	_write(_v2_with_level("sharpness", 1))
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(FileAccess.get_file_as_string(TEST_PATH + ".v2.bak"), original, "the first backup is never overwritten")
	assert_false(FileAccess.file_exists(TEST_PATH + ".bak"), "not rejected")


func test_migrated_save_loads_again_unchanged() -> void:
	_write(_v2_with_level("start_shield", 4))
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.save_game(), OK)
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_meta_level(MetaProgression.START_SHIELD), 3, "converted once, not twice")


func test_v2_values_survive_reload() -> void:
	SaveManager.add_permanent_gold(10)
	SaveManager.add_permanent_crystals(4)
	SaveManager.set_meta_level(MetaProgression.START_SHIELD, 2)
	SaveManager.add_pending_boost(MetaProgression.BOOST_POTION)
	SaveManager.set_second_weapon(MetaProgression.WEAPON_BOW)
	SaveManager.add_stat(StatsTracker.KILLS, 12)
	SaveManager.add_stat(StatsTracker.PLAY_TIME, 61.5)
	assert_eq(SaveManager.save_game(), OK)
	SaveManager.add_permanent_crystals(100)
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_permanent_gold(), 10)
	assert_eq(SaveManager.get_permanent_crystals(), 4)
	assert_eq(SaveManager.get_meta_level(MetaProgression.START_SHIELD), 2)
	assert_true(SaveManager.has_pending_boost(MetaProgression.BOOST_POTION))
	assert_eq(SaveManager.get_second_weapon(), MetaProgression.WEAPON_BOW)
	assert_eq(SaveManager.get_stat(StatsTracker.KILLS), 12)
	assert_almost_eq(float(SaveManager.get_stat(StatsTracker.PLAY_TIME)), 61.5, 0.001)


func test_newer_version_is_rejected() -> void:
	_write("[meta]\nversion=5\n[progress]\npermanent_gold=500\n")
	assert_eq(SaveManager.load_game(), ERR_FILE_UNRECOGNIZED)
	assert_eq(SaveManager.get_permanent_gold(), 0)
	assert_true(FileAccess.file_exists(TEST_PATH + ".bak"), "kept as *.bak")


func test_invalid_crystals_are_rejected() -> void:
	_write("[meta]\nversion=2\n[progress]\npermanent_gold=50\npermanent_crystals=-1\n")
	assert_eq(SaveManager.load_game(), ERR_INVALID_DATA)
	assert_eq(SaveManager.get_permanent_gold(), 0)


func test_invalid_meta_level_is_rejected() -> void:
	_write("[meta]\nversion=2\n[progress]\npermanent_gold=50\n[meta_upgrades]\nvitality=\"high\"\n")
	assert_eq(SaveManager.load_game(), ERR_INVALID_DATA)
	assert_eq(SaveManager.get_meta_level(MetaProgression.VITALITY), 0)
	assert_true(FileAccess.file_exists(TEST_PATH + ".v2.bak"), "the backup before the migration exists too")


func test_invalid_stats_are_dropped_not_fatal() -> void:
	_write("[meta]\nversion=2\n[progress]\npermanent_gold=50\n[stats]\nkills=\"many\"\nruns=3\n")
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_permanent_gold(), 50)
	assert_eq(SaveManager.get_stat(StatsTracker.KILLS), 0)
	assert_eq(SaveManager.get_stat(StatsTracker.RUNS), 3)


func test_spend_permanent_gold_is_all_or_nothing() -> void:
	SaveManager.add_permanent_gold(10)
	assert_false(SaveManager.try_spend_permanent_gold(11))
	assert_eq(SaveManager.get_permanent_gold(), 10)
	assert_true(SaveManager.try_spend_permanent_gold(10))
	assert_eq(SaveManager.get_permanent_gold(), 0)

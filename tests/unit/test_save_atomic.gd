extends GutTest
## P1-8: saves are written crash-safely (SafeSave): .tmp, read back, rename; the file replaced is kept
## as .prev.bak; a broken file falls back to that copy; a crash between the steps is recovered; the
## web build and a failing rename write directly. Only in a test folder, never on the real save.

const SafeSaveScript := preload("res://meta/safe_save.gd")
const ROOT := "user://test_save_atomic"
## What a crash mid-write leaves: a cut section header (ConfigFile cannot parse it).
const BROKEN := "[meta\nversion="

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
	_reset_flags()
	SaveManager.set_storage_root(ROOT)
	SaveManager.save_path = _path("world.cfg")
	SaveManager.load_game()


func after_each() -> void:
	_reset_flags()


func after_all() -> void:
	_wipe()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ROOT))
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()


func _reset_flags() -> void:
	SafeSaveScript.force_direct_write = false
	SafeSaveScript.force_rename_failure = false


func _path(file: String) -> String:
	return ROOT.path_join(file)


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


## Reading a broken file on purpose makes Godot print a parse error: expected in these tests.
func _expect_parse_errors() -> void:
	for error in get_errors():
		if error.contains_text("ConfigFile parse error"):
			error.handled = true


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _config(gold: int) -> ConfigFile:
	var config := ConfigFile.new()
	config.set_value("meta", "version", SaveManager.SAVE_VERSION)
	config.set_value("progress", "permanent_gold", gold)
	return config


func _gold_in(path: String) -> int:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return -1
	return int(config.get_value("progress", "permanent_gold", -1))


# --- SafeSave ---

func test_write_leaves_no_tmp_and_no_backup_the_first_time() -> void:
	var path := _path("a.cfg")
	assert_eq(SafeSaveScript.write_config(_config(5), path), OK)
	assert_eq(_gold_in(path), 5)
	assert_false(FileAccess.file_exists(SafeSaveScript.tmp_path(path)), "no .tmp left")
	assert_false(FileAccess.file_exists(SafeSaveScript.backup_path(path)), "nothing to keep yet")


func test_second_write_keeps_the_previous_file() -> void:
	var path := _path("a.cfg")
	SafeSaveScript.write_config(_config(5), path)
	assert_eq(SafeSaveScript.write_config(_config(9), path), OK)
	assert_eq(_gold_in(path), 9)
	assert_eq(_gold_in(SafeSaveScript.backup_path(path)), 5, "last good copy")
	assert_false(FileAccess.file_exists(SafeSaveScript.tmp_path(path)))


func test_broken_file_is_never_kept_as_the_good_copy() -> void:
	var path := _path("a.cfg")
	SafeSaveScript.write_config(_config(5), path)
	SafeSaveScript.write_config(_config(9), path)
	_write(path, "[meta\nversion=")
	assert_eq(SafeSaveScript.write_config(_config(12), path), OK)
	assert_eq(_gold_in(path), 12)
	assert_eq(_gold_in(SafeSaveScript.backup_path(path)), 5, "the broken file did not replace the copy")
	_expect_parse_errors()


func test_keep_backup_false_leaves_the_copy_alone() -> void:
	var path := _path("a.cfg")
	SafeSaveScript.write_config(_config(5), path)
	SafeSaveScript.write_config(_config(9), path)
	SafeSaveScript.write_config(_config(12), path, false)
	assert_eq(_gold_in(SafeSaveScript.backup_path(path)), 5)


func test_unreadable_file_loads_the_last_good_copy() -> void:
	var path := _path("a.cfg")
	SafeSaveScript.write_config(_config(5), path)
	SafeSaveScript.write_config(_config(9), path)
	_write(path, BROKEN)
	var config := ConfigFile.new()
	var from_backup := [false]
	assert_eq(SafeSaveScript.load_config(config, path, from_backup), OK)
	assert_eq(int(config.get_value("progress", "permanent_gold")), 5)
	assert_true(from_backup[0])
	_expect_parse_errors()


func test_unreadable_file_without_copy_reports_the_error() -> void:
	var path := _path("a.cfg")
	_write(path, BROKEN)
	assert_ne(SafeSaveScript.load_config(ConfigFile.new(), path), OK)
	assert_eq(SafeSaveScript.load_config(ConfigFile.new(), _path("missing.cfg")), ERR_FILE_NOT_FOUND)
	_expect_parse_errors()


func test_crash_after_the_copy_restores_the_checked_tmp() -> void:
	# The file was moved away and the checked .tmp not yet renamed: the .tmp becomes the file.
	var path := _path("a.cfg")
	_config(7).save(SafeSaveScript.tmp_path(path))
	assert_true(SafeSaveScript.recover(path))
	assert_eq(_gold_in(path), 7)
	assert_false(FileAccess.file_exists(SafeSaveScript.tmp_path(path)))


func test_half_written_tmp_next_to_the_file_is_dropped() -> void:
	var path := _path("a.cfg")
	SafeSaveScript.write_config(_config(5), path)
	_write(SafeSaveScript.tmp_path(path), "[meta]\nversion=4\n[progress]\npermanent_gold=")
	assert_false(SafeSaveScript.recover(path))
	assert_eq(_gold_in(path), 5, "file untouched")
	assert_false(FileAccess.file_exists(SafeSaveScript.tmp_path(path)))
	_expect_parse_errors()


func test_broken_tmp_without_file_is_not_restored() -> void:
	var path := _path("a.cfg")
	_write(SafeSaveScript.tmp_path(path), "[meta\nbroken")
	assert_false(SafeSaveScript.recover(path))
	assert_false(FileAccess.file_exists(path))
	assert_false(FileAccess.file_exists(SafeSaveScript.tmp_path(path)))
	_expect_parse_errors()


func test_failing_rename_falls_back_to_direct_write() -> void:
	var path := _path("a.cfg")
	SafeSaveScript.write_config(_config(5), path)
	SafeSaveScript.force_rename_failure = true
	assert_eq(SafeSaveScript.write_config(_config(9), path), OK)
	assert_eq(_gold_in(path), 9)
	assert_eq(_gold_in(SafeSaveScript.backup_path(path)), 5)
	assert_false(FileAccess.file_exists(SafeSaveScript.tmp_path(path)))


func test_web_build_writes_directly_and_keeps_the_copy() -> void:
	SafeSaveScript.force_direct_write = true
	assert_false(SafeSaveScript.uses_rename())
	var path := _path("a.cfg")
	SafeSaveScript.write_config(_config(5), path)
	assert_eq(SafeSaveScript.write_config(_config(9), path), OK)
	assert_eq(_gold_in(path), 9)
	assert_eq(_gold_in(SafeSaveScript.backup_path(path)), 5)
	assert_false(FileAccess.file_exists(SafeSaveScript.tmp_path(path)))


func test_rename_works_on_this_platform() -> void:
	# Desktop builds rename; this is what the web check would have to prove there as well.
	assert_true(SafeSaveScript.uses_rename())
	var from := ProjectSettings.globalize_path(_path("r1.cfg"))
	var to := ProjectSettings.globalize_path(_path("r2.cfg"))
	_write(_path("r1.cfg"), "x")
	_write(_path("r2.cfg"), "y")
	assert_eq(DirAccess.rename_absolute(from, to), OK, "rename onto an existing file")
	assert_eq(FileAccess.get_file_as_string(_path("r2.cfg")), "x")


# --- SaveManager ---

func test_save_game_keeps_the_last_good_copy() -> void:
	SaveManager.add_permanent_gold(10)
	assert_eq(SaveManager.save_game(), OK)
	SaveManager.add_permanent_gold(5)
	assert_eq(SaveManager.save_game(), OK)
	assert_eq(_gold_in(SaveManager.save_path), 15)
	assert_eq(_gold_in(SafeSaveScript.backup_path(SaveManager.save_path)), 10)


func test_broken_save_loads_the_last_good_copy() -> void:
	SaveManager.add_permanent_gold(10)
	SaveManager.unlock_content(&"forge")
	SaveManager.save_game()
	SaveManager.add_permanent_gold(5)
	SaveManager.save_game()
	_write(SaveManager.save_path, BROKEN)
	assert_eq(SaveManager.load_game(), OK)
	assert_true(SaveManager.was_restored_from_backup())
	assert_eq(SaveManager.get_permanent_gold(), 10, "one save back, not a fresh start")
	assert_true(SaveManager.is_unlocked(&"forge"))
	assert_true(FileAccess.file_exists(SaveManager.save_path + ".bak"), "broken file kept as *.bak (D-059)")
	_expect_parse_errors()


func test_invalid_values_load_the_last_good_copy() -> void:
	SaveManager.add_permanent_gold(10)
	SaveManager.save_game()
	SaveManager.save_game()
	_write(SaveManager.save_path, "[meta]\nversion=4\n[progress]\npermanent_gold=-3\n")
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_permanent_gold(), 10)


func test_save_after_restore_does_not_lose_the_copy() -> void:
	SaveManager.add_permanent_gold(10)
	SaveManager.save_game()
	SaveManager.save_game()
	_write(SaveManager.save_path, BROKEN)
	SaveManager.load_game()
	SaveManager.add_permanent_gold(1)
	assert_eq(SaveManager.save_game(), OK)
	assert_eq(_gold_in(SaveManager.save_path), 11)
	assert_eq(_gold_in(SafeSaveScript.backup_path(SaveManager.save_path)), 10, "copy kept, broken file not copied over it")
	SaveManager.save_game()
	assert_eq(_gold_in(SafeSaveScript.backup_path(SaveManager.save_path)), 11, "from now on the copy rolls again")
	_expect_parse_errors()


func test_broken_save_without_copy_still_starts_fresh() -> void:
	_write(SaveManager.save_path, BROKEN)
	assert_eq(SaveManager.load_game(), ERR_FILE_CORRUPT)
	assert_false(SaveManager.was_restored_from_backup())
	assert_eq(SaveManager.get_permanent_gold(), 0)
	_expect_parse_errors()


func test_interrupted_save_is_finished_on_load() -> void:
	SaveManager.add_permanent_gold(10)
	SaveManager.save_game()
	# Crash right after the copy: only the .prev.bak and the checked .tmp exist.
	DirAccess.rename_absolute(ProjectSettings.globalize_path(SaveManager.save_path), ProjectSettings.globalize_path(SaveManager.save_path + ".moved"))
	_config(33).save(SafeSaveScript.tmp_path(SaveManager.save_path))
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_permanent_gold(), 33, "the newest checked state")


func test_settings_fall_back_to_their_copy() -> void:
	SaveManager.set_volume(&"Music", 0.3)
	SaveManager.save_settings()
	SaveManager.save_settings()
	_write(SaveManager.settings_path, BROKEN)
	SaveManager.load_settings()
	assert_almost_eq(SaveManager.get_volume(&"Music"), 0.3, 0.001)
	_expect_parse_errors()


func test_slot_summary_shows_the_copy_of_a_broken_slot() -> void:
	assert_eq(SaveManager.create_slot(1), OK)
	SaveManager.add_permanent_gold(20)
	SaveManager.save_game()
	_write(SaveManager.slot_path(1), BROKEN)
	var summary := SaveManager.get_slot_summary(1)
	assert_false(summary["broken"])
	assert_true(summary["from_backup"])
	assert_eq(summary["gold"], 0, "the copy is the state before the last save")
	_expect_parse_errors()


func test_deleted_slot_does_not_come_back_from_its_copy() -> void:
	assert_eq(SaveManager.create_slot(1), OK)
	SaveManager.save_game()
	assert_true(FileAccess.file_exists(SafeSaveScript.backup_path(SaveManager.slot_path(1))))
	assert_eq(SaveManager.delete_slot(1), OK)
	assert_false(FileAccess.file_exists(SafeSaveScript.backup_path(SaveManager.slot_path(1))))
	SaveManager.recover_storage()
	assert_false(SaveManager.has_slot(1))


func test_tests_never_use_the_real_save() -> void:
	assert_ne(SaveManager.save_path, SaveManager.DEFAULT_SAVE_PATH)
	assert_ne(SaveManager.settings_path, SaveManager.DEFAULT_SETTINGS_PATH)
	assert_true(SaveManager.saves_dir.begins_with(ROOT))

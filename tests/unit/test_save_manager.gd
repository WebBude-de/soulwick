extends GutTest
## Permanent save: survives reload, corrupt/wrong files are handled safely (D-040, ARCHITECTURE 5).

const TEST_PATH := "user://test_save_manager.cfg"

var _old_path: String


func before_all() -> void:
	_old_path = SaveManager.save_path


func before_each() -> void:
	SaveManager.save_path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	SaveManager.load_game()


func after_all() -> void:
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


func test_missing_file_starts_fresh() -> void:
	assert_eq(SaveManager.load_game(), ERR_FILE_NOT_FOUND)
	assert_eq(SaveManager.get_permanent_gold(), 0)


func test_permanent_values_survive_reload() -> void:
	SaveManager.add_permanent_gold(42)
	SaveManager.unlock_content(&"forge")
	assert_eq(SaveManager.save_game(), OK)
	SaveManager.add_permanent_gold(100)
	assert_eq(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_permanent_gold(), 42)
	assert_true(SaveManager.is_unlocked(&"forge"))


func test_corrupt_file_is_rejected() -> void:
	_write("this is not a config file [[[")
	assert_ne(SaveManager.load_game(), OK)
	assert_eq(SaveManager.get_permanent_gold(), 0)


func test_wrong_version_is_rejected() -> void:
	_write("[meta]\nversion=99\n[progress]\npermanent_gold=500\n")
	assert_eq(SaveManager.load_game(), ERR_FILE_UNRECOGNIZED)
	assert_eq(SaveManager.get_permanent_gold(), 0)


func test_invalid_gold_is_rejected() -> void:
	_write("[meta]\nversion=1\n[progress]\npermanent_gold=-5\n")
	assert_eq(SaveManager.load_game(), ERR_INVALID_DATA)
	assert_eq(SaveManager.get_permanent_gold(), 0)

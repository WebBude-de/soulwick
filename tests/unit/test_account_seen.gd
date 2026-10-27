extends GutTest
## Seen flags per account (KE1, KONZEPT §7.2, §10): marked once for the account, kept in
## progress.cfg (AccountProgress state "seen"), the old [seen] of every world on this machine taken
## over once (union; a pre-D-087 world counts as "everything seen" except boss and room intros),
## union as merge rule. Test folder only (SaveManager.set_storage_root), never the real save or
## progress.cfg (AGENTS.md rule 4).

const ROOT := "user://test_account_seen"

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
	AccountProgress.path_override = ""
	AccountProgress.reset()


func after_all() -> void:
	_wipe()
	AccountProgress.path_override = ""
	AccountProgress.reset()
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()
	PlayerProfile.reset()


func _wipe() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	for dir_path in [root.path_join("saves"), root]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			DirAccess.remove_absolute(dir_path.path_join(file))
	DirAccess.make_dir_recursive_absolute(root.path_join("saves"))


func _copy_fixture(fixture: String, slot: int) -> void:
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tests/fixtures/" + fixture),
			ProjectSettings.globalize_path(SaveManager.slot_path(slot)))


func test_a_fresh_account_sees_nothing_and_marks_once() -> void:
	SaveManager.create_slot(1, "Neu")
	assert_false(AccountSeen.has_seen(&"wick_tour"))
	assert_true(AccountSeen.mark_seen(&"wick_tour"), "new")
	assert_false(AccountSeen.mark_seen(&"wick_tour"), "only once")
	assert_true(AccountSeen.has_seen(&"wick_tour"))
	AccountProgress.reset()
	assert_true(AccountSeen.has_seen(&"wick_tour"), "kept in progress.cfg")
	assert_true(AccountProgress.current().has_state(AccountSeen.STATE_KEY))


func test_a_new_world_does_not_explain_again() -> void:
	SaveManager.create_slot(1, "Erste")
	AccountSeen.mark_seen(&"room_intro_escort")
	SaveManager.create_slot(2, "Zweite")
	SaveManager.load_slot(2)
	assert_false(SaveManager.has_seen(&"room_intro_escort"), "the new world itself knows nothing")
	assert_true(AccountSeen.has_seen(&"room_intro_escort"), "the account remembers it")


func test_old_worlds_are_taken_over_once() -> void:
	_copy_fixture("save_v3_slot_test.cfg", 1)
	_copy_fixture("save_v2_slot_test.cfg", 2)
	AccountProgress.reset()
	assert_true(AccountSeen.has_seen(&"unlock_first_boss"), "from the v3 world")
	assert_true(AccountSeen.has_seen(&"intro_guild"), "from both")
	assert_false(AccountSeen.has_seen(&"intro_wick"), "nothing else")
	assert_false(AccountSeen.is_all_seen())
	var ids := AccountSeen.get_ids()
	assert_eq(ids.size(), 11, "union without doubles")
	# A later change in a world file is not imported again (the import runs once).
	_copy_fixture("save_v2_legacy.cfg", 3)
	assert_false(AccountSeen.import_worlds(), "done before")
	assert_false(AccountSeen.is_all_seen())


func test_a_pre_d087_world_counts_as_everything_seen() -> void:
	_copy_fixture("save_v2_legacy.cfg", 1)
	AccountProgress.reset()
	assert_true(AccountSeen.is_all_seen(), "old save: everything seen (D-087)")
	assert_true(AccountSeen.has_seen(&"intro_forge"))
	assert_false(AccountSeen.has_seen(&"boss_intro_bone_king"), "boss intros are new for everyone (BI2)")
	assert_false(AccountSeen.has_seen(&"room_intro_escort"))


func test_the_import_never_writes_the_worlds() -> void:
	_copy_fixture("save_v2_slot_test.cfg", 1)
	var path := ProjectSettings.globalize_path(SaveManager.slot_path(1))
	var before := FileAccess.get_file_as_string(path)
	AccountProgress.reset()
	AccountSeen.import_worlds()
	assert_eq(FileAccess.get_file_as_string(path), before, "read only")
	assert_false(FileAccess.file_exists(path + ".v2.bak"), "no migration backup either")


func test_merge_is_a_union() -> void:
	var merged := AccountSeen.merge_states({"ids": ["a", "b"], "imported": true}, {"ids": PackedStringArray(["b", "c"]), "all": true})
	assert_eq(merged["ids"], ["a", "b", "c"])
	assert_true(merged["all"])
	assert_true(merged["imported"])
	assert_eq(AccountSeen.clean_state({"ids": [3, "", "x", "x"], "all": "yes"}), {"ids": ["x"], "all": false, "imported": false})

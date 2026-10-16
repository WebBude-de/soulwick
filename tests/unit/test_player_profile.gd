extends GutTest
## D-152: the player's profile (one name and look for the whole account, profile.cfg) and the save
## slots as worlds. Migration v3 -> v4 of real old slots (fixtures): nothing of the progress is lost,
## the old per-slot name/figure/colour moves to [legacy_profile] and is suggested once for the
## profile. Runs in a test folder (SaveManager.set_storage_root), never on the real save or profile.

const ROOT := "user://test_player_profile"
const FIXTURE_V2 := "res://tests/fixtures/save_v2_slot_test.cfg"
const FIXTURE_V3 := "res://tests/fixtures/save_v3_slot_test.cfg"

var _old_locale: String
var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	Loc.apply(&"de")
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path


func before_each() -> void:
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)
	_wipe()
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


func _install_slot(slot: int, fixture: String) -> String:
	var text := FileAccess.get_file_as_string(fixture)
	assert_false(text.is_empty(), "fixture %s exists" % fixture)
	var file := FileAccess.open(SaveManager.slot_path(slot), FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return text


# --- The profile file ---

func test_profile_lives_next_to_the_settings_and_never_in_the_real_folder() -> void:
	assert_eq(PlayerProfile.current().path, ROOT.path_join("profile.cfg"))
	SaveManager.settings_path = SaveManager.DEFAULT_SETTINGS_PATH
	PlayerProfile.reset()
	assert_true(PlayerProfile.is_script_run(), "GUT runs with -s")
	assert_eq(PlayerProfile.default_path(), "user://script_profile.cfg", "tests and tools never use user://profile.cfg")
	SaveManager.set_storage_root(ROOT)
	assert_eq(PlayerProfile.current().path, ROOT.path_join("profile.cfg"))


func test_fresh_profile_needs_the_first_start() -> void:
	var profile := PlayerProfile.current()
	assert_true(profile.needs_setup())
	assert_eq(profile.player_name, "")
	assert_eq(profile.get_display_name(), "Spieler")
	assert_eq(profile.look, PlayerLook.default_look())
	assert_false(FileAccess.file_exists(profile.path), "nothing written before the first start")


func test_setup_is_written_and_read_back() -> void:
	watch_signals(SaveManager)
	var look := PlayerLook.normalize({"character": "frost", "colors": {"hair": 7, "outfit": 3, "skin": 5, "accent": 2}})
	assert_false(PlayerProfile.current().complete_setup(" A ", look), "one letter is too short")
	assert_true(PlayerProfile.current().needs_setup())
	assert_true(PlayerProfile.current().complete_setup("  Mira <3 die Mutige!!  ", look))
	assert_signal_emitted(SaveManager, "profile_changed", "the player sprite follows")
	PlayerProfile.reset()
	var profile := PlayerProfile.current()
	assert_false(profile.needs_setup())
	assert_eq(profile.player_name, "Mira 3 die Mutig", "only API characters, 16 at most")
	assert_eq(profile.look, look)
	assert_true(profile.name_dirty and profile.look_dirty, "not on the server yet")


func test_name_rules_follow_the_api() -> void:
	assert_eq(PlayerProfile.sanitize_name("  Zoë  Öl_.-x "), "Zoë Öl_.-x")
	assert_eq(PlayerProfile.sanitize_name("<script>"), "script")
	assert_false(PlayerProfile.is_valid_name("!"))
	assert_true(PlayerProfile.is_valid_name("Al"))


func test_server_profile_wins_when_nothing_changed_here() -> void:
	var profile := PlayerProfile.current()
	profile.complete_setup("Kerze", PlayerLook.default_look())
	var changed := profile.take_server_profile({"id": "p-1", "name": "Docht", "appearance": {"character": "moss", "colors": {"hair": 1, "outfit": 2, "skin": 3}}})
	assert_true(changed)
	assert_eq(profile.player_name, "Docht")
	assert_eq(PlayerLook.get_character(profile.look), &"moss")
	assert_eq(PlayerLook.get_index(profile.look, PlayerLook.ACCENT), int(PlayerLook.default_colors(&"moss")["accent"]), "accent is optional in the API")
	assert_false(profile.name_dirty or profile.look_dirty)
	assert_eq(profile.synced_player_id, "p-1")
	assert_false(profile.take_server_profile({"id": "p-1", "name": "Docht", "appearance": null}), "no look on the server: ours stays")


# --- Worlds (save format v4) ---

func test_v3_slot_becomes_a_world_without_losing_progress() -> void:
	var original := _install_slot(1, FIXTURE_V3)
	assert_eq(SaveManager.load_slot(1), OK)
	assert_eq(FileAccess.get_file_as_string(SaveManager.slot_path(1) + ".v3.bak"), original, "untouched copy first")
	assert_false(FileAccess.file_exists(SaveManager.slot_path(1) + ".bak"), "not rejected")
	_assert_lumen_progress("after loading")
	assert_eq(SaveManager.get_world_display_name(), "Welt 1", "the slot was named after the player")
	assert_eq(SaveManager.get_legacy_profile().get("name"), "Lumen")
	assert_eq(SaveManager.save_game(), OK)
	var config := ConfigFile.new()
	assert_eq(config.load(SaveManager.slot_path(1)), OK)
	assert_eq(config.get_value("meta", "version"), 4)
	assert_eq(config.get_value("legacy_profile", "name"), "Lumen")
	assert_eq(config.get_value("legacy_profile", "color"), "a66ef0")
	assert_false(config.has_section_key("profile", "name"))
	assert_eq(config.get_value("profile", "created"), 1791941206, "creation time kept")
	assert_eq(SaveManager.load_slot(1), OK)
	_assert_lumen_progress("after saving and loading again")
	assert_eq(SaveManager.get_legacy_profile().get("name"), "Lumen", "kept through every save")


func _assert_lumen_progress(when: String) -> void:
	assert_eq(SaveManager.get_permanent_gold(), 43, when)
	assert_eq(SaveManager.get_permanent_crystals(), 11, when)
	assert_eq(SaveManager.get_meta_level(MetaProgression.VITALITY), 2, "%s: v3 levels unchanged" % when)
	assert_eq(SaveManager.get_meta_level(MetaProgression.SHARPNESS), 1, when)
	assert_true(SaveManager.has_pending_boost(MetaProgression.BOOST_POTION), when)
	assert_eq(SaveManager.get_stat(StatsTracker.KILLS), 316, when)
	assert_true(SaveManager.has_seen(&"intro_forge"), when)
	assert_false(SaveManager.has_seen(&"boss_intro_ember_golem"), when)
	assert_true(MetaUnlocks.has_event(MetaUnlocks.EVENT_FIRST_BOSS), when)


func test_v2_slot_goes_through_every_step() -> void:
	_install_slot(2, FIXTURE_V2)
	assert_eq(SaveManager.load_slot(2), OK)
	assert_eq(SaveManager.get_permanent_gold(), 43)
	assert_eq(SaveManager.get_world_display_name(), "Welt 2")
	assert_eq(SaveManager.get_legacy_profile().get("character"), "hero")
	assert_true(FileAccess.file_exists(SaveManager.slot_path(2) + ".v2.bak"))


func test_suggestion_takes_the_continue_slot_first_and_maps_the_old_figure() -> void:
	_install_slot(1, FIXTURE_V2)
	_install_slot(3, FIXTURE_V3)
	assert_eq(SaveManager.load_slot(3), OK)
	var suggestion := PlayerProfile.legacy_suggestion()
	assert_eq(suggestion.get("name"), "Lumen", "the slot of Weiterspielen (last used)")
	assert_eq(PlayerLook.get_character(suggestion.get("look")), &"wick", "hero -> wick")
	assert_eq(PlayerLook.get_index(suggestion.get("look"), PlayerLook.OUTFIT), 4, "violet clothes kept")
	assert_eq(SaveManager.load_slot(1), OK)
	suggestion = PlayerProfile.legacy_suggestion()
	assert_eq(suggestion.get("name"), "Test")
	assert_eq(PlayerLook.get_index(suggestion.get("look"), PlayerLook.OUTFIT), 1, "red")
	SaveManager.save_game()
	assert_eq(PlayerProfile.legacy_suggestion().get("name"), "Test", "also from a migrated v4 file")


func test_no_suggestion_for_new_worlds() -> void:
	SaveManager.create_slot(1, "Neu")
	assert_true(PlayerProfile.legacy_suggestion().is_empty())


func test_rename_a_world_on_disk_and_in_memory() -> void:
	SaveManager.create_slot(1, "Eins")
	SaveManager.create_slot(2)
	assert_eq(SaveManager.rename_slot(1, "Moorland"), OK)
	assert_eq(SaveManager.get_slot_summary(1)["name"], "Moorland", "not loaded: written to the file")
	assert_eq(SaveManager.rename_slot(2, "Hochland"), OK)
	assert_eq(SaveManager.get_world_name(), "Hochland", "loaded: in memory and saved")
	assert_eq(SaveManager.get_slot_summary(2)["name"], "Hochland")
	assert_eq(SaveManager.rename_slot(3, "x"), ERR_FILE_NOT_FOUND)

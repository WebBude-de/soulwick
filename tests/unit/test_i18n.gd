extends GutTest
## Two languages (D-111, UX3): localization/translations.csv is complete (en and de for every key,
## same placeholders), the imported .translation files match the CSV, every key used in ui/options
## and ui/main_menu exists, Loc resolves "auto" from the system language, and switching the locale
## translates open menus at once. Runs in a test folder (SaveManager.set_storage_root), never on
## the real settings/save.

const ROOT := "user://test_i18n"
const KEY_FOLDERS := ["res://ui/options", "res://ui/main_menu", "res://localization"]
## Any "UPPER_SNAKE" string literal in those folders is a translation key.
const KEY_PATTERN := "&?\"([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+)\""
const PLACEHOLDER_PATTERN := "%[sdf]"

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String
var _old_locale: String
var _csv: Dictionary = {}


func before_all() -> void:
	# No network from the menu's online version check (MP4).
	MainMenu.online_check = false
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	_old_locale = TranslationServer.get_locale()
	_csv = Loc.load_csv(Loc.CSV_PATH)


func before_each() -> void:
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()


func after_each() -> void:
	GameManager.clear_pause_reasons()


func after_all() -> void:
	MainMenu.online_check = true
	_wipe()
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()
	TranslationServer.set_locale(_old_locale)


func _wipe() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	for dir_path in [root.path_join("saves"), root]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			DirAccess.remove_absolute(dir_path.path_join(file))
	DirAccess.make_dir_recursive_absolute(root)


func _keys(language: StringName) -> PackedStringArray:
	var translation := _csv.get(language, null) as Translation
	return translation.get_message_list() if translation != null else PackedStringArray()


func _message(language: StringName, key: String) -> String:
	return String((_csv[language] as Translation).get_message(key))


func _placeholders(text: String) -> PackedStringArray:
	var regex := RegEx.create_from_string(PLACEHOLDER_PATTERN)
	var found: PackedStringArray = []
	for match in regex.search_all(text):
		found.append(match.get_string())
	return found


static func _scripts_in(folder: String) -> PackedStringArray:
	var files: PackedStringArray = []
	var dir := DirAccess.open(folder)
	if dir == null:
		return files
	for name in dir.get_files():
		if name.ends_with(".gd"):
			files.append(folder.path_join(name))
	for sub in dir.get_directories():
		files.append_array(_scripts_in(folder.path_join(sub)))
	return files


func test_csv_has_both_languages_for_every_key() -> void:
	assert_true(_csv.has(&"en") and _csv.has(&"de"), "columns en and de")
	var en_keys := _keys(&"en")
	assert_gt(en_keys.size(), 80, "a real key list")
	assert_eq(_keys(&"de").size(), en_keys.size())
	for key in en_keys:
		assert_false(_message(&"en", key).is_empty(), "%s has English" % key)
		assert_false(_message(&"de", key).is_empty(), "%s has German" % key)
		assert_eq(_placeholders(_message(&"en", key)), _placeholders(_message(&"de", key)), "%s: same placeholders" % key)
	# Duplicate keys would silently overwrite each other: count the lines.
	var file := FileAccess.open(Loc.CSV_PATH, FileAccess.READ)
	var seen: Dictionary = {}
	file.get_csv_line()
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.is_empty() or line[0].is_empty():
			continue
		assert_false(seen.has(line[0]), "%s appears once" % line[0])
		seen[line[0]] = true


func test_imported_translations_match_the_csv() -> void:
	Loc.install()
	for language in Loc.LANGUAGES:
		var loaded := TranslationServer.get_translation_object(String(language))
		assert_not_null(loaded, "%s is registered" % language)
		if loaded == null:
			continue
		for key in _keys(language):
			assert_eq(String(loaded.get_message(key)), _message(language, key),
				"%s/%s: translations.%s.translation is up to date (run godot --import after editing the CSV)" % [language, key, language])


func test_every_key_used_in_menus_and_options_exists() -> void:
	var regex := RegEx.create_from_string(KEY_PATTERN)
	var en_keys := _keys(&"en")
	var used := 0
	for folder in KEY_FOLDERS:
		for path in _scripts_in(folder):
			var source := FileAccess.get_file_as_string(path)
			for match in regex.search_all(source):
				var key := match.get_string(1)
				used += 1
				assert_true(en_keys.has(key), "%s: key %s is in translations.csv" % [path.get_file(), key])
	assert_gt(used, 60, "the menus use keys")


func test_auto_resolves_from_the_system_language() -> void:
	assert_eq(Loc.resolve(&"auto", "de"), &"de", "German system -> de")
	assert_eq(Loc.resolve(&"auto", "en"), &"en")
	assert_eq(Loc.resolve(&"auto", "fr"), &"en", "everything else -> English (default)")
	assert_eq(Loc.resolve(&"de", "en"), &"de", "explicit choice wins")
	assert_eq(Loc.resolve(&"en", "de"), &"en")
	assert_eq(Loc.resolve(&"xx", "de"), &"de", "unknown option counts as auto")
	assert_true(Loc.LANGUAGES.has(Loc.resolve(&"auto")), "without an override the OS language is used")


func test_switching_the_locale_translates_keys_and_is_stored() -> void:
	GameOptions.set_language(&"en")
	assert_eq(TranslationServer.get_locale(), "en")
	assert_eq(Loc.current_language(), &"en")
	assert_eq(Loc.t(&"MENU_OPTIONS"), "Options")
	assert_eq(Loc.t(&"MENU_SLOTS_HINT", [1, 3]), "1 / 3 used")
	assert_eq(Loc.t(&"NO_SUCH_KEY_XYZ"), "NO_SUCH_KEY_XYZ", "unknown keys come back unchanged")
	GameOptions.set_language(&"de")
	assert_eq(Loc.current_language(), &"de")
	assert_eq(Loc.t(&"MENU_OPTIONS"), "Optionen")
	assert_eq(Loc.t(&"MENU_SLOTS_HINT", [1, 3]), "1 / 3 belegt")
	var config := ConfigFile.new()
	assert_eq(config.load(SaveManager.settings_path), OK)
	assert_eq(config.get_value("options", "language"), "de", "stored in settings.cfg [options]")
	assert_true(Loc.has_key(&"MENU_OPTIONS", &"en"))
	assert_false(Loc.has_key(&"NO_SUCH_KEY_XYZ", &"en"))


func test_open_main_menu_switches_language_at_once() -> void:
	GameOptions.set_language(&"de")
	var menu := MainMenu.new()
	add_child_autofree(menu)
	var list := menu.get_list()
	assert_eq(list.get_entry_text(MainMenu.ENTRY_OPTIONS), "Optionen")
	assert_eq(list.get_entry_hint(MainMenu.ENTRY_SLOTS), "0 / 3 belegt")
	menu.activate(MainMenu.ENTRY_OPTIONS)
	var panel := menu.get_open_panel() as OptionsPanel
	await wait_physics_frames(2)
	assert_eq(panel.view.get_caption_text(OptionsView.Row.SFX), "Effekte")
	GameOptions.set_language(&"en")
	assert_eq(list.get_entry_text(MainMenu.ENTRY_OPTIONS), "Options", "plain keys re-translate themselves")
	assert_eq(list.get_entry_text(MainMenu.ENTRY_CONTINUE), "New game")
	assert_eq(list.get_entry_hint(MainMenu.ENTRY_SLOTS), "0 / 3 used", "composed hints are rebuilt")
	assert_eq(list.get_entry_hint(MainMenu.ENTRY_ONLINE), "soon")
	assert_eq(panel.view.get_caption_text(OptionsView.Row.SFX), "Effects", "the open options view follows")
	await wait_physics_frames(2)
	assert_true(panel.view.get_footer_text().ends_with("Esc back"), "footer in English: %s" % panel.view.get_footer_text())
	GameOptions.set_language(&"de")
	assert_eq(list.get_entry_text(MainMenu.ENTRY_OPTIONS), "Optionen")
	assert_eq(list.get_entry_hint(MainMenu.ENTRY_SLOTS), "0 / 3 belegt")
	await wait_physics_frames(2)
	assert_true(panel.view.get_footer_text().ends_with("Esc zurück"))
	panel.close()
	await wait_physics_frames(2)
	var slots := menu.open_slots()
	await wait_physics_frames(2)
	assert_true(slots.get_footer_text().begins_with("Klick oder"), "slot footer German: %s" % slots.get_footer_text())
	GameOptions.set_language(&"en")
	await wait_physics_frames(2)
	assert_true(slots.get_footer_text().begins_with("Click or"), "slot panel rebuilt in English: %s" % slots.get_footer_text())

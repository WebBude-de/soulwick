extends GutTest
## Main menu (MM1): imports the old save into slot 1, entries and placeholders, keyboard navigation,
## creating a fresh slot with a character, deleting only after confirmation, global volume. Runs in a
## test folder (SaveManager.set_storage_root), never on the real save.

const ROOT := "user://test_main_menu"
const OLD_SAVE := "[meta]\nversion=2\n[progress]\npermanent_gold=77\npermanent_crystals=4\n[stats]\ndeepest_room=31\nplay_time=600.0\n[seen]\nall=true\nids=PackedStringArray()\n[settings]\nvolume_music=0.4\n"

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String
var _old_music: float
var _old_sfx: float
var _old_locale: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	_old_music = SaveManager.get_volume(&"Music")
	_old_sfx = SaveManager.get_volume(&"SFX")
	_old_locale = TranslationServer.get_locale()


func before_each() -> void:
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()
	# The asserts read German texts; English is the default on English systems (D-111).
	GameOptions.set_language(&"de")


func after_each() -> void:
	GameManager.clear_pause_reasons()


func after_all() -> void:
	_wipe()
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.set_volume(&"Music", _old_music)
	SaveManager.set_volume(&"SFX", _old_sfx)
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


func _write_old_save() -> void:
	var file := FileAccess.open(SaveManager.legacy_save_path, FileAccess.WRITE)
	file.store_string(OLD_SAVE)
	file.close()
	SaveManager.set_storage_root(ROOT)


func _menu() -> MainMenu:
	var menu := MainMenu.new()
	add_child_autofree(menu)
	return menu


func _press(target: Object, keycode: Key) -> bool:
	return target.handle_input(MenuInput.key_event(keycode))


func test_menu_imports_old_save_and_offers_continue() -> void:
	_write_old_save()
	var menu := _menu()
	assert_true(SaveManager.has_slot(1), "old save moved into slot 1")
	assert_eq(SaveManager.get_slot_summary(1)["gold"], 77)
	var list := menu.get_list()
	assert_eq(list.get_entry_text(MainMenu.ENTRY_CONTINUE), "Weiterspielen")
	assert_eq(list.get_entry_hint(MainMenu.ENTRY_CONTINUE), "Spielstand 1")
	assert_eq(list.get_entry_hint(MainMenu.ENTRY_SLOTS), "1 / 3 belegt")
	assert_eq(list.get_selected_id(), MainMenu.ENTRY_CONTINUE)


func test_online_guild_is_a_disabled_placeholder() -> void:
	var list := _menu().get_list()
	assert_eq(list.get_entry_text(MainMenu.ENTRY_ONLINE), "Online / Gilde")
	assert_eq(list.get_entry_hint(MainMenu.ENTRY_ONLINE), "bald")
	assert_false(list.is_entry_enabled(MainMenu.ENTRY_ONLINE))
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	assert_eq(MainMenu.version_text(), ("v" + version) if not version.is_empty() else MainMenu.FALLBACK_VERSION)


func test_keyboard_skips_disabled_entries_and_wraps() -> void:
	var list := _menu().get_list()
	assert_true(_press(list, KEY_DOWN))
	assert_eq(list.get_selected_id(), MainMenu.ENTRY_SLOTS)
	_press(list, KEY_DOWN)
	assert_eq(list.get_selected_id(), MainMenu.ENTRY_OPTIONS, "Online / Gilde is skipped")
	_press(list, KEY_S)
	assert_eq(list.get_selected_id(), MainMenu.ENTRY_QUIT, "S works like the down arrow")
	_press(list, KEY_DOWN)
	assert_eq(list.get_selected_id(), MainMenu.ENTRY_CONTINUE, "wraps around")
	_press(list, KEY_UP)
	assert_eq(list.get_selected_id(), MainMenu.ENTRY_QUIT)


func test_without_any_save_the_first_entry_starts_a_new_game() -> void:
	var menu := _menu()
	assert_eq(menu.get_list().get_entry_text(MainMenu.ENTRY_CONTINUE), "Neues Spiel")
	menu.activate(MainMenu.ENTRY_CONTINUE)
	var panel := menu.get_open_panel() as CreateSlotPanel
	assert_not_null(panel, "opens Neuer Spielstand")
	assert_eq(panel.slot, 1)


func test_create_panel_offers_characters_and_their_colours() -> void:
	var menu := _menu()
	var panel := menu.open_create(2)
	await wait_physics_frames(2)
	assert_eq(panel.get_character().id, CharacterCatalog.DEFAULT_ID)
	assert_eq(panel.get_card_count(), CharacterCatalog.all().size() + CreateSlotPanel.LOCKED_CARDS, "hero plus 'bald' cards")
	assert_eq(panel.find_children("*", "LineEdit", true, false).size(), 1, "one name field")
	assert_eq(panel.get_color_count(), panel.get_character().color_choices.size(), "same colours as the wardrobe")
	assert_eq(panel.get_color(), panel.get_character().default_color, "starts with the default colour")
	assert_eq(panel.get_row(), CreateSlotPanel.Row.NAME)
	panel.handle_input(MenuInput.key_event(KEY_DOWN))
	assert_eq(panel.get_row(), CreateSlotPanel.Row.CHARACTER)
	panel.handle_input(MenuInput.key_event(KEY_DOWN))
	assert_eq(panel.get_row(), CreateSlotPanel.Row.COLOR)
	panel.handle_input(MenuInput.key_event(KEY_RIGHT))
	assert_eq(panel.get_color_index(), 1, "→ picks the next colour")
	panel.handle_input(MenuInput.key_event(KEY_3))
	assert_eq(panel.get_color_index(), 2, "number keys pick directly")


func test_creating_a_slot_with_a_colour_saves_it() -> void:
	var menu := _menu()
	var panel := menu.open_create(3)
	await wait_physics_frames(2)
	assert_true(panel.pick_color(1))
	var picked := panel.get_color()
	panel.confirm()
	await wait_physics_frames(2)
	assert_eq(SaveManager.get_active_slot(), 3)
	assert_true(SaveManager.has_character_color())
	assert_true(SaveManager.get_character_color().is_equal_approx(picked))
	assert_true((SaveManager.get_slot_summary(3)["color"] as Color).is_equal_approx(picked), "stored in the slot")


func test_creating_a_slot_starts_a_fresh_game() -> void:
	_write_old_save()
	var menu := _menu()
	watch_signals(menu)
	var panel := menu.open_create(2)
	await wait_physics_frames(2)
	panel.set_profile_name("  Lena  ")
	panel.confirm()
	await wait_seconds(MainMenu.FADE_TIME + 0.3)
	assert_signal_emitted(menu, "play_requested")
	assert_eq(SaveManager.get_active_slot(), 2)
	assert_eq(SaveManager.get_profile_name(), "Lena")
	assert_eq(SaveManager.get_character_id(), CharacterCatalog.DEFAULT_ID)
	assert_false(SaveManager.has_character_color(), "colour is picked later at home")
	assert_eq(SaveManager.get_permanent_gold(), 0)
	for id in VillageBuildings.ALL:
		assert_true(VillageBuildings.needs_intro(id), "fresh slot explains %s (D-087)" % id)
	assert_eq(SaveManager.get_slot_summary(1)["gold"], 77, "slot 1 untouched")


func test_continue_loads_the_last_slot() -> void:
	SaveManager.create_slot(3, "Drei", &"hero")
	SaveManager.add_permanent_gold(12)
	SaveManager.save_game()
	SaveManager.create_slot(1, "Eins", &"hero")
	SaveManager.load_slot(3)
	var menu := _menu()
	watch_signals(menu)
	assert_eq(menu.get_list().get_entry_hint(MainMenu.ENTRY_CONTINUE), "Drei")
	menu.activate(MainMenu.ENTRY_CONTINUE)
	assert_true(menu.is_starting())
	assert_eq(SaveManager.get_active_slot(), 3)
	assert_eq(SaveManager.get_permanent_gold(), 12)


func test_slot_panel_deletes_only_after_confirmation() -> void:
	SaveManager.create_slot(1, "Weg", &"hero")
	var menu := _menu()
	var panel := menu.open_slots()
	await wait_physics_frames(2)
	panel.select_slot(1)
	assert_true(_press(panel, KEY_DELETE))
	assert_true(panel.is_confirming_delete(), "asks first")
	assert_true(_press(panel, KEY_ESCAPE))
	assert_false(panel.is_confirming_delete())
	assert_true(SaveManager.has_slot(1), "Esc keeps the slot")
	_press(panel, KEY_DELETE)
	_press(panel, KEY_ENTER)
	assert_false(SaveManager.has_slot(1), "Enter in the question deletes")
	assert_eq(menu.get_list().get_entry_text(MainMenu.ENTRY_CONTINUE), "Neues Spiel")


func test_empty_slot_in_the_list_opens_create() -> void:
	var menu := _menu()
	var panel := menu.open_slots()
	await wait_physics_frames(2)
	panel.select_slot(2)
	_press(panel, KEY_ENTER)
	await wait_physics_frames(2)
	var create := menu.get_open_panel() as CreateSlotPanel
	assert_not_null(create)
	assert_eq(create.slot, 2)
	create.close()
	await wait_physics_frames(2)
	assert_true(menu.get_open_panel() is SlotPanel, "back returns to the slot list")


func test_options_change_the_global_volume() -> void:
	var menu := _menu()
	menu.activate(MainMenu.ENTRY_OPTIONS)
	var panel := menu.get_open_panel() as OptionsPanel
	assert_not_null(panel)
	await wait_physics_frames(2)
	var before := SaveManager.get_volume(&"Music")
	_press(panel, KEY_LEFT)
	assert_almost_eq(SaveManager.get_volume(&"Music"), maxf(0.0, before - OptionsPanel.STEP), 0.0001)
	_press(panel, KEY_ESCAPE)
	await wait_physics_frames(2)
	assert_null(menu.get_open_panel())
	var settings := ConfigFile.new()
	assert_eq(settings.load(SaveManager.settings_path), OK, "saved in the settings file")
	assert_almost_eq(float(settings.get_value("audio", "volume_music")), SaveManager.get_volume(&"Music"), 0.0001)


func test_escape_closes_panels_and_reactivates_the_list() -> void:
	var menu := _menu()
	menu.open_slots()
	assert_false(menu.get_list().active)
	_press(menu.get_open_panel(), KEY_ESCAPE)
	await wait_physics_frames(2)
	assert_null(menu.get_open_panel())
	assert_true(menu.get_list().active)

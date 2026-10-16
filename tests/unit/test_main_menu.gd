extends GutTest
## Main menu (MM1, D-152): imports the old save into slot 1, entries and placeholders, keyboard
## navigation, worlds (create with a name, rename, delete only after confirmation), the player's
## profile (first start "Wie heißt du?" with the old slot name as suggestion, "Figur"), global volume.
## Runs in a test folder (SaveManager.set_storage_root, the profile lives there too), never on the
## real save or profile.

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
	# No network from the menu's online version check (MP4).
	MainMenu.online_check = false
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
	# Most tests start with a profile; the first-start tests wipe it again.
	assert_true(PlayerProfile.current().path.begins_with(ROOT), "the profile lives in the test folder")
	PlayerProfile.current().complete_setup("Kerze", PlayerLook.default_look())


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
	SaveManager.set_volume(&"Music", _old_music)
	SaveManager.set_volume(&"SFX", _old_sfx)
	SaveManager.load_game()
	PlayerProfile.reset()
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
	assert_eq(list.get_entry_hint(MainMenu.ENTRY_CONTINUE), "Welt 1", "D-152: the world's name, not the player's")
	assert_eq(list.get_entry_hint(MainMenu.ENTRY_SLOTS), "1 / 3 belegt")
	assert_eq(list.get_selected_id(), MainMenu.ENTRY_CONTINUE)


func test_online_is_open_without_a_world() -> void:
	var menu := _menu()
	var list := menu.get_list()
	assert_eq(list.get_entry_text(MainMenu.ENTRY_ONLINE), "Online spielen")
	assert_eq(list.get_entry_hint(MainMenu.ENTRY_ONLINE), "Schnell · Gilden", "playtest 16.10.2026: no world needed first")
	assert_true(list.is_entry_enabled(MainMenu.ENTRY_ONLINE))
	menu.activate(MainMenu.ENTRY_ONLINE)
	var panel := menu.get_open_panel() as OnlinePanel
	assert_not_null(panel, "opens the online menu without a world")
	await wait_physics_frames(2)
	assert_not_null(panel.find_child("CreateRoom", true, false))
	assert_not_null(panel.find_child("NewWorldHint", true, false), "says that starting creates a world")
	assert_false(SaveManager.has_slot(1), "just looking creates no world")
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	assert_eq(MainMenu.version_text(), ("v" + version) if not version.is_empty() else MainMenu.FALLBACK_VERSION)


func test_online_without_a_world_creates_one_on_start() -> void:
	var menu := _menu()
	var panel := menu.open_online()
	await wait_physics_frames(2)
	panel.launch_requested.emit({"action": LobbyClient.LAUNCH_JOIN, "code": "ABCD23"})
	await wait_physics_frames(2)
	assert_true(menu.is_starting(), "the game starts")
	assert_true(SaveManager.has_slot(1), "a fresh world in the first free slot")
	assert_eq(SaveManager.get_active_slot(), 1)
	assert_eq(SaveManager.get_slot_summary(1)["name"], "Welt 1", "the usual default name")
	assert_eq(PlayerProfile.current().player_name, "Kerze", "the player stays who they are (D-152)")
	for id in VillageBuildings.ALL:
		assert_true(VillageBuildings.needs_intro(id), "the fresh world explains %s (D-087)" % id)
	var launch := LobbyClient.take_launch()
	assert_eq(launch.get("action"), LobbyClient.LAUNCH_JOIN)
	assert_eq(launch.get("code"), "ABCD23")


func test_online_with_worlds_uses_the_continue_world() -> void:
	SaveManager.create_slot(1, "Nebeltal")
	SaveManager.create_slot(2, "Moorhang")
	SaveManager.load_slot(2)
	var menu := _menu()
	assert_eq(MainMenu.online_world_slot(), 2, "the world of Weiterspielen")
	var panel := menu.open_online()
	await wait_physics_frames(2)
	assert_null(panel.find_child("NewWorldHint", true, false), "no hint with a world")
	panel.launch_requested.emit({"action": LobbyClient.LAUNCH_CREATE, "mode": LobbyClient.MODE_QUICK})
	await wait_physics_frames(2)
	assert_eq(SaveManager.get_active_slot(), 2)
	assert_false(SaveManager.has_slot(3), "no extra world")
	LobbyClient.take_launch()


func test_profile_works_without_a_world() -> void:
	var menu := _menu()
	var panel := menu.open_profile(false)
	await wait_physics_frames(2)
	assert_not_null(panel, "Figur opens without a world (D-152: the profile is not the world's)")
	assert_eq(PlayerProfile.current().get_display_name(), "Kerze")
	assert_eq(SaveManager.get_continue_slot(), 0, "still no world")


func test_online_opens_the_online_menu_with_a_save() -> void:
	SaveManager.create_slot(1, "Kerze", &"hero")
	var menu := _menu()
	var list := menu.get_list()
	assert_true(list.is_entry_enabled(MainMenu.ENTRY_ONLINE), "D-147: Online spielen is open with a save")
	assert_eq(list.get_entry_hint(MainMenu.ENTRY_ONLINE), "Schnell · Gilden")
	menu.activate(MainMenu.ENTRY_ONLINE)
	var panel := menu.get_open_panel() as OnlinePanel
	assert_not_null(panel, "opens the online menu")
	await wait_physics_frames(2)
	assert_not_null(panel.find_child("CreateRoom", true, false), "quick game first")
	assert_true(_press(panel, KEY_ESCAPE))
	await wait_physics_frames(2)
	assert_null(menu.get_open_panel(), "Esc closes it")


func test_a_room_from_the_main_menu_starts_the_game_with_the_wish() -> void:
	SaveManager.create_slot(2, "Kerze", &"hero")
	var menu := _menu()
	watch_signals(menu)
	var panel := menu.open_online()
	await wait_physics_frames(2)
	panel.launch_requested.emit({"action": LobbyClient.LAUNCH_CREATE, "mode": LobbyClient.MODE_GUILD, "guild_id": "g-1", "guild_name": "Lichtwacht"})
	await wait_physics_frames(2)
	assert_true(menu.is_starting(), "the save starts like Weiterspielen")
	assert_eq(SaveManager.get_active_slot(), 2)
	assert_true(LobbyClient.has_pending_launch())
	var launch := LobbyClient.take_launch()
	assert_eq(launch.get("mode"), LobbyClient.MODE_GUILD)
	assert_eq(launch.get("guild_id"), "g-1")
	assert_false(LobbyClient.has_pending_launch(), "taken once")


func test_keyboard_skips_disabled_entries_and_wraps() -> void:
	var menu := _menu()
	var list := menu.get_list()
	# The only way Online spielen is locked: this build is too old for the API (MP4).
	menu._on_online_checked(OnlineVersionCheck.Status.OUTDATED)
	assert_false(list.is_entry_enabled(MainMenu.ENTRY_ONLINE))
	assert_true(_press(list, KEY_DOWN))
	assert_eq(list.get_selected_id(), MainMenu.ENTRY_SLOTS)
	_press(list, KEY_DOWN)
	assert_eq(list.get_selected_id(), MainMenu.ENTRY_PROFILE)
	assert_eq(list.get_entry_hint(MainMenu.ENTRY_PROFILE), "Kerze", "the player's name")
	_press(list, KEY_DOWN)
	assert_eq(list.get_selected_id(), MainMenu.ENTRY_OPTIONS, "Online spielen (locked) is skipped")
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


func test_new_world_asks_only_for_its_name() -> void:
	var menu := _menu()
	var panel := menu.open_create(2)
	await wait_physics_frames(2)
	assert_eq(panel.find_children("*", "LineEdit", true, false).size(), 1, "one name field")
	assert_eq((panel.find_child("WorldName", true, false) as LineEdit).placeholder_text, "Welt 2")
	assert_eq(panel.find_children("*", "CharacterPreview", true, false).size(), 1, "the player's figure comes along")
	assert_eq(panel.get_world_name(), "Welt 2", "empty name = Welt 2")
	panel.set_world_name("Nebeltal")
	assert_eq(panel.get_world_name(), "Nebeltal")


func test_creating_a_slot_starts_a_fresh_game() -> void:
	_write_old_save()
	var menu := _menu()
	watch_signals(menu)
	var panel := menu.open_create(2)
	await wait_physics_frames(2)
	panel.set_world_name("  Lena  ")
	panel.confirm()
	await wait_seconds(MainMenu.FADE_TIME + 0.3)
	assert_signal_emitted(menu, "play_requested")
	assert_eq(SaveManager.get_active_slot(), 2)
	assert_eq(SaveManager.get_world_name(), "Lena", "the world's name")
	assert_eq(SaveManager.get_slot_summary(2)["name"], "Lena")
	assert_eq(PlayerProfile.current().player_name, "Kerze", "the player stays who they are (D-152)")
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


# --- D-152: the player's profile ---

func _wipe_profile() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.current().path))
	PlayerProfile.reset()


func test_first_start_asks_for_the_name_and_cannot_be_skipped() -> void:
	_wipe_profile()
	var menu := _menu()
	await wait_physics_frames(2)
	var panel := menu.get_open_panel() as ProfilePanel
	assert_not_null(panel, "Wie heißt du? opens by itself")
	assert_true(panel.first_start)
	assert_false(menu.get_list().active, "the menu waits")
	assert_true(_press(panel, KEY_ESCAPE), "Esc is swallowed")
	await wait_physics_frames(2)
	assert_eq(menu.get_open_panel(), panel, "Esc does not skip the first start")
	var editor := panel.editor
	editor.set_player_name("A")
	editor.confirm()
	await wait_physics_frames(2)
	assert_eq(menu.get_open_panel(), panel, "a one-letter name is refused")
	assert_string_contains(editor.get_message(), "mindestens 2")
	editor.set_player_name("Mira")
	editor.change_character(1)
	editor.pick_color(PlayerLook.HAIR, 3)
	editor.confirm()
	await wait_physics_frames(3)
	assert_null(menu.get_open_panel(), "saved: the menu is free")
	var profile := PlayerProfile.current()
	assert_false(profile.needs_setup())
	assert_eq(profile.player_name, "Mira")
	assert_eq(PlayerLook.get_character(profile.look), &"ember")
	assert_eq(PlayerLook.get_index(profile.look, PlayerLook.HAIR), 3)
	assert_true(FileAccess.file_exists(profile.path), "written to profile.cfg")
	assert_eq(menu.get_list().get_entry_hint(MainMenu.ENTRY_PROFILE), "Mira")


func test_first_start_suggests_the_name_of_an_old_slot_once() -> void:
	_wipe_profile()
	# A slot of an older build (v3) named the player: Test, hero, red clothes.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveManager.saves_dir))
	var file := FileAccess.open(SaveManager.slot_path(1), FileAccess.WRITE)
	file.store_string("[meta]\nversion=3\n[progress]\npermanent_gold=5\n[seen]\nall=true\nids=PackedStringArray()\n[profile]\nname=\"Test\"\ncharacter=\"hero\"\ncolor=\"e0463a\"\n")
	file.close()
	var menu := _menu()
	await wait_physics_frames(2)
	var panel := menu.get_open_panel() as ProfilePanel
	assert_not_null(panel)
	assert_eq(panel.editor.get_player_name(), "Test", "the old slot's name is the suggestion")
	assert_eq(PlayerLook.get_character(panel.editor.get_look()), &"wick", "hero is wick now")
	assert_eq(PlayerLook.get_index(panel.editor.get_look(), PlayerLook.OUTFIT), 1, "red clothes kept")
	assert_eq(menu.get_list().get_entry_hint(MainMenu.ENTRY_CONTINUE), "Welt 1", "the slot is a world now")


func test_figure_entry_opens_the_editor_and_the_scene_follows() -> void:
	var menu := _menu()
	menu.activate(MainMenu.ENTRY_PROFILE)
	var panel := menu.get_open_panel() as ProfilePanel
	assert_not_null(panel)
	await wait_physics_frames(2)
	assert_false(panel.first_start)
	var hero := menu.get_background().get_hero()
	var before := hero.sprite_frames
	panel.editor.change_character(1)
	assert_ne(hero.sprite_frames, before, "the scene figure shows the new look at once")
	assert_true(_press(panel, KEY_ESCAPE))
	await wait_physics_frames(2)
	assert_null(menu.get_open_panel(), "Esc goes back without saving")
	assert_eq(PlayerLook.get_character(PlayerProfile.current().look), &"wick", "nothing saved")


func test_slot_panel_renames_a_world() -> void:
	SaveManager.create_slot(1, "", &"")
	SaveManager.create_slot(2, "Zwei")
	var menu := _menu()
	var panel := menu.open_slots()
	await wait_physics_frames(2)
	panel.select_slot(1)
	assert_true(_press(panel, KEY_R))
	await wait_physics_frames(2)
	assert_true(panel.is_renaming())
	panel.confirm_rename("  Sumpfland ")
	await wait_physics_frames(2)
	assert_false(panel.is_renaming())
	assert_eq(SaveManager.get_slot_summary(1)["name"], "Sumpfland")
	panel.select_slot(1)
	panel.request_rename()
	panel.confirm_rename("")
	assert_eq(SaveManager.get_slot_summary(1)["name"], "Welt 1", "empty = default name again")
	assert_eq(SaveManager.get_slot_summary(2)["name"], "Zwei", "other worlds untouched")

extends GutTest
## P1-1 "Ein Einstieg statt zwei": the first start asks for name and look once, then creates Welt 1
## (MainMenu.create_default_world, the same as an online game without a world) and starts the game
## straight away. Players who already have a world stay in the menu as before. Runs in a test folder
## (SaveManager.set_storage_root, the profile lives there too), never on the real save or profile.

const ROOT := "user://test_first_start"

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String
var _old_locale: String


func before_all() -> void:
	MainMenu.online_check = false
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	_old_locale = TranslationServer.get_locale()


func before_each() -> void:
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()
	GameOptions.set_language(&"de")
	assert_true(PlayerProfile.current().path.begins_with(ROOT), "the profile lives in the test folder")
	# Every test here is a first start: no profile yet.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.current().path))
	PlayerProfile.reset()


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


func _menu() -> MainMenu:
	var menu := MainMenu.new()
	add_child_autofree(menu)
	return menu


func _first_start_panel(menu: MainMenu) -> ProfilePanel:
	var panel := menu.get_open_panel() as ProfilePanel
	assert_not_null(panel, "Wie heißt du? opens by itself")
	if panel != null:
		assert_true(panel.first_start)
	return panel


func test_first_start_goes_straight_into_welt_1() -> void:
	var menu := _menu()
	watch_signals(menu)
	await wait_physics_frames(2)
	var panel := _first_start_panel(menu)
	assert_false(SaveManager.has_slot(1), "no world before the name")
	panel.editor.set_player_name("Mira")
	panel.editor.confirm()
	await wait_physics_frames(3)
	assert_true(menu.is_starting(), "Los geht's starts the game, no second Los geht's")
	assert_true(SaveManager.has_slot(1), "Welt 1 was created")
	assert_eq(SaveManager.get_active_slot(), 1, "and is the loaded world")
	assert_eq(SaveManager.get_slot_summary(1)["name"], "Welt 1", "the usual default name")
	assert_eq(SaveManager.get_continue_slot(), 1, "Weiterspielen continues it next time")
	assert_eq(PlayerProfile.current().player_name, "Mira")
	assert_null(menu.get_open_panel(), "the profile panel is closed")
	assert_false(menu.get_list().active, "the menu list stays locked while fading out")
	for id in VillageBuildings.ALL:
		assert_true(VillageBuildings.needs_intro(id), "the fresh world explains %s (D-087)" % id)
	await wait_seconds(MainMenu.FADE_TIME + 0.2)
	assert_signal_emitted(menu, "play_requested", "the game scene follows")


func test_first_start_with_an_old_world_stays_in_the_menu() -> void:
	# A slot of an older build (v3, before profiles): the player already has a world.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveManager.saves_dir))
	var file := FileAccess.open(SaveManager.slot_path(1), FileAccess.WRITE)
	file.store_string("[meta]\nversion=3\n[progress]\npermanent_gold=5\n[seen]\nall=true\nids=PackedStringArray()\n[profile]\nname=\"Test\"\ncharacter=\"hero\"\ncolor=\"e0463a\"\n")
	file.close()
	var menu := _menu()
	await wait_physics_frames(2)
	var panel := _first_start_panel(menu)
	panel.editor.confirm()
	await wait_physics_frames(3)
	assert_false(menu.is_starting(), "existing players notice nothing: back in the menu")
	assert_null(menu.get_open_panel())
	assert_true(menu.get_list().active)
	assert_false(SaveManager.has_slot(2), "no extra world")
	assert_eq(menu.get_list().get_entry_text(MainMenu.ENTRY_CONTINUE), "Weiterspielen")


func test_figure_entry_never_creates_a_world() -> void:
	PlayerProfile.current().complete_setup("Kerze", PlayerLook.default_look())
	var menu := _menu()
	var panel := menu.open_profile(false)
	await wait_physics_frames(2)
	panel.editor.confirm()
	await wait_physics_frames(3)
	assert_false(menu.is_starting(), "only the first start goes on into the game")
	assert_false(SaveManager.has_slot(1))


func test_default_world_takes_the_first_free_slot() -> void:
	SaveManager.create_slot(1, "Nebeltal")
	assert_eq(MainMenu.create_default_world(), 2)
	assert_eq(SaveManager.get_slot_summary(2)["name"], "Welt 2")
	assert_eq(SaveManager.get_active_slot(), 2)
	for slot in range(3, SaveSlots.SLOT_COUNT + 1):
		SaveManager.create_slot(slot)
	assert_eq(MainMenu.create_default_world(), 0, "all slots used: nothing is created")

extends GutTest
## "Dein Fortschritt" on screen (D-188, KF1): the main menu entry "Fortschritt" with "Schmiede x/20"
## as its hint opens the overview of the world "Weiterspielen" without loading it, Esc closes it, the
## seven entries still end above the currency panel; the village chronicle shows the same overview
## next to its statistics. Runs in a test folder (SaveManager.set_storage_root), never on the real save.

const ROOT := "user://test_progress_view"

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String
var _old_locale: String
var _old_root_size: Vector2i


func before_all() -> void:
	MainMenu.online_check = false
	OnlineMenu.login_on_open = false
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	_old_locale = TranslationServer.get_locale()
	_old_root_size = get_tree().root.size


func before_each() -> void:
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()
	GameOptions.set_language(&"de")
	PlayerProfile.current().complete_setup("Kerze", PlayerLook.default_look())


func after_each() -> void:
	# Layout tests use a 720 px high screen; later tests expect the size they started with.
	get_tree().root.size = _old_root_size
	GameManager.clear_pause_reasons()


func after_all() -> void:
	MainMenu.online_check = true
	OnlineMenu.login_on_open = true
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


func _world_with_progress() -> void:
	SaveManager.create_slot(1, "Nebeltal")
	SaveManager.set_meta_level(MetaProgression.VITALITY, 3)
	SaveManager.set_meta_level(MetaProgression.START_SHIELD, 1)
	SaveManager.record_stat_max(StatsTracker.DEEPEST_ROOM, 16)
	SaveManager.add_stat(StatsTracker.BOSSES, 1)
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_RUN)
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_BOSS)
	SaveManager.save_game()


func test_menu_entry_shows_the_forge_and_opens_the_overview() -> void:
	_world_with_progress()
	# Another world is loaded: the overview still shows the world of "Weiterspielen".
	SaveManager.create_slot(2, "Moorhang")
	SaveManager.load_slot(1)
	var menu := MainMenu.new()
	add_child_autofree(menu)
	await wait_process_frames(2)
	var list := menu.get_list()
	assert_eq(list.get_entry_text(MainMenu.ENTRY_PROGRESS), "Fortschritt")
	assert_eq(list.get_entry_hint(MainMenu.ENTRY_PROGRESS), "Schmiede 4/20", "progress at a glance in the list")
	menu.activate(MainMenu.ENTRY_PROGRESS)
	var panel := menu.get_open_panel() as ProgressPanel
	assert_not_null(panel, "Fortschritt opens the overview")
	await wait_process_frames(2)
	var view := panel.view
	assert_eq(view.world["name"], "Nebeltal")
	assert_eq((view.find_child("ForgeValue", true, false) as Label).text, "4 / 20")
	var crypt := view.find_child("Biome0", true, false) as Control
	assert_eq((crypt.find_child("State", true, false) as Label).text, "Boss besiegt")
	var grotto := view.find_child("Biome1", true, false) as Control
	assert_eq((grotto.find_child("State", true, false) as Label).text, "Erreicht")
	assert_not_null(view.find_child("NextGoal", true, false), "Nächstes Ziel in gold on top")
	assert_not_null(view.find_child("Unlocks", true, false))
	assert_eq(SaveManager.get_active_slot(), 1, "looking loads nothing")
	assert_true(panel.handle_input(MenuInput.key_event(KEY_ESCAPE)))
	await wait_process_frames(2)
	assert_null(menu.get_open_panel(), "Esc closes it")


func test_overview_without_a_world() -> void:
	var menu := MainMenu.new()
	add_child_autofree(menu)
	await wait_process_frames(2)
	assert_eq(menu.get_list().get_entry_hint(MainMenu.ENTRY_PROGRESS), "Schmiede 0/20")
	var panel := menu.open_progress()
	await wait_process_frames(2)
	assert_false(panel.view.world["exists"])
	assert_eq((panel.view.find_child("NextGoal", true, false).get_child(0) as Label).text,
			"Nächstes Ziel: Beende deinen ersten Run – öffnet: Chronik")
	assert_false(SaveManager.has_slot(1), "no world is created by looking")


func test_seven_entries_end_above_the_currency_panel() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	_world_with_progress()
	var menu := MainMenu.new()
	add_child_autofree(menu)
	await wait_process_frames(3)
	var list := menu.get_list()
	assert_gte(list.get_entry_count(), 6)
	var currency := menu.get("_currency") as Control
	assert_lt(list.get_global_rect().end.y, currency.get_global_rect().position.y, "the list stays above gold and crystals")
	var panel := menu.open_progress()
	await wait_process_frames(3)
	assert_true(get_viewport().get_visible_rect().encloses(panel.get_global_rect()), "the overview fits a 720 px screen")


func test_chronicle_shows_the_overview_next_to_the_statistics() -> void:
	_world_with_progress()
	SaveManager.mark_seen(VillageBuildings.get_intro_key(VillageBuildings.CHRONICLE))
	var ui := VillageUI.new()
	add_child_autofree(ui)
	ui.open_chronicle()
	await wait_process_frames(3)
	var modal := ui.get_building_modal()
	assert_not_null(modal)
	var view := modal.find_child("ProgressView", true, false) as ProgressView
	assert_not_null(view, "Dein Fortschritt in the chronicle")
	assert_true(view.compact)
	assert_eq(view.world["name"], "Nebeltal", "the loaded world")
	assert_null(view.find_child("Unlocks", true, false), "compact: the statistics stand next to it")
	assert_eq((view.find_child("ForgeValue", true, false) as Label).text, "4 / 20")
	assert_true(get_viewport().get_visible_rect().encloses(modal.frame.get_global_rect()), "fits the screen")
	modal.finish()

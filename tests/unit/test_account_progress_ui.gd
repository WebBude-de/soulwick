extends GutTest
## Account level on screen (D-188, KF2): the account card in the main menu (badge, name, bar, XP;
## a click opens "Fortschritt"), the account part of the overview, the level row in the profile and
## at the mirror, a real run end that counts the run once (RunRecap.award_xp) and the "+XP" block
## that fills its bar and celebrates a level up. Test folder only (SaveManager.set_storage_root),
## never the real save, profile or progress.cfg.
## KE1: rank and free points on the card, "Rang gestiegen" at the run end, the run's danger level in
## its XP, and the entrance card in the village (shown only, D-196; the group level from outside).

const ROOT := "user://test_account_progress_ui"
const MobileUi := preload("res://ui/menus/mobile_ui.gd")
const NOON := 1792324800

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
	RunManager.end_run(RunManager.EndReason.ABORT)
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()
	AccountProgress.reset()
	GameOptions.set_language(&"de")
	PlayerProfile.current().complete_setup("Kerze", PlayerLook.default_look())


func after_each() -> void:
	# Layout tests use a 720 px high screen and a phone; later tests expect what they started with.
	get_tree().root.size = _old_root_size
	MobileUi.zoom_override = 0.0
	MobileUi.touch_override = -1
	MobileUi.phone_override = -1
	MobileUi.safe_inset_override = -1.0
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.set_danger_level(0)
	AccountProgress.spent_points_source = Callable()
	GameManager.clear_pause_reasons()


func after_all() -> void:
	MainMenu.online_check = true
	OnlineMenu.login_on_open = true
	_wipe()
	AccountProgress.reset()
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


func test_main_menu_shows_name_level_and_xp() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	AccountProgress.current().record_run("seed", {"rooms_cleared": 60}, NOON)
	var menu := MainMenu.new()
	add_child_autofree(menu)
	await wait_process_frames(3)
	var card := menu.get_account_card()
	assert_not_null(card, "account card in the main menu")
	assert_eq(card.get_level_text(), "Level 3", "60 rooms and the daily bonus: 325 XP")
	assert_eq(card.get_xp_text(), "25 / 300 XP")
	assert_eq(card.badge.get_number_text(), "3")
	assert_eq((card.find_child("Name", true, false) as Label).text, "Kerze")
	assert_true(get_viewport().get_visible_rect().encloses(card.get_global_rect()), "on screen")
	var list_rect := menu.get_list().get_global_rect()
	assert_false(card.get_global_rect().intersects(list_rect), "never over the menu list")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	card._gui_input(click)
	await wait_process_frames(2)
	var panel := menu.get_open_panel() as ProgressPanel
	assert_not_null(panel, "a click on the card opens Fortschritt")
	assert_false(card.visible, "hidden while a panel is open")
	var level := panel.view.find_child("AccountLevel", true, false) as Label
	assert_not_null(level, "the overview has the account part")
	assert_eq(level.text, "Level 3")
	assert_true(get_viewport().get_visible_rect().encloses(panel.get_global_rect()), "the overview fits a 720 px screen")
	var reward := (panel.view.summary["goals"] as Array).filter(func(goal: Dictionary) -> bool: return goal["kind"] == ProgressSummary.GOAL_REWARD)
	assert_eq(reward.size(), 1, "the next level reward is a goal")
	assert_eq(int(reward[0]["level"]), 5)


func test_profile_shows_level_and_next_reward() -> void:
	var menu := MainMenu.new()
	add_child_autofree(menu)
	await wait_process_frames(2)
	var panel := menu.open_profile(false)
	await wait_process_frames(2)
	var row := panel.find_child("LevelRow", true, false) as ProfileLevelRow
	assert_not_null(row, "Figur shows the account level")
	assert_eq(row.get_reward_text(), "Nächste Belohnung: Level 5")
	menu.close_panel()
	var first := ProfilePanel.create(true)
	add_child_autofree(first)
	await wait_process_frames(2)
	assert_null(first.find_child("LevelRow", true, false), "not on the first start")


func test_mirror_shows_the_level() -> void:
	SaveManager.create_slot(1, "Nebeltal")
	var ui := VillageUI.new()
	add_child_autofree(ui)
	ui.open_mirror()
	await wait_process_frames(2)
	var editor := ui.get_profile_editor()
	assert_not_null(editor)
	assert_not_null(editor.find_child("LevelRow", true, false), "the mirror shows the account level")
	ui.get_building_modal().finish()


func test_a_real_run_end_counts_once_and_builds_the_xp_block() -> void:
	SaveManager.create_slot(1, "Nebeltal")
	var recap := RunRecap.new()
	add_child_autofree(recap)
	RunManager.start_run()
	assert_false(recap.run_id.is_empty(), "every run gets an id")
	assert_eq(recap.award_xp(), {}, "nothing while the run is on")
	for room in 3:
		EventBus.room_completed.emit(room + 1)
		RunManager.advance_room()
	RunManager.end_run(RunManager.EndReason.EXIT)
	var result := recap.get_xp_result()
	assert_true(result.get("added", false), "counted at the run end")
	assert_eq(result["xp"], 15 + 20 + 20 + 25, "3 rooms, record room 4, portal, first run today")
	assert_eq(AccountProgress.current().get_total_xp(), 80)
	assert_true(AccountProgress.current().has_run(recap.run_id))
	assert_eq(recap.award_xp(), result, "a second call changes nothing")
	var view := recap.create_xp_view()
	assert_not_null(view)
	add_child_autofree(view)
	await wait_process_frames(2)
	view.skip()
	assert_true(view.is_done())
	assert_eq((view.find_child("Gain", true, false) as Label).text, "+80 XP")
	assert_eq((view.find_child("XpText", true, false) as Label).text, "80 / 100 XP")
	assert_string_contains((view.find_child("Parts", true, false) as Label).text, "Portal +20")
	assert_eq(AccountProgress.current().get_total_xp(), 80, "the view does not count again")


func test_xp_bar_fills_and_celebrates_a_level_up() -> void:
	var view := XpGainView.create({"xp": 60, "parts": [{"id": AccountProgress.PART_ROOMS, "count": 12, "xp": 60}],
			"xp_before": 90, "xp_after": 150, "level_before": 1, "level_after": 2})
	add_child_autofree(view)
	watch_signals(view)
	await wait_process_frames(2)
	assert_eq(view.get_shown_level(), 1, "starts at the old level")
	assert_almost_eq(view.bar.ratio, 0.9, 0.001)
	await wait_seconds(XpGainView.START_DELAY + XpGainView.FILL_TIME + 0.6)
	assert_signal_emitted_with_parameters(view, "leveled_up", [2])
	assert_eq(view.get_shown_level(), 2)
	assert_eq(view.get_banner_text(), "Level 2!")
	assert_true(view.is_done())
	assert_eq((view.find_child("Gain", true, false) as Label).text, "+60 XP · Level 2!")
	assert_almost_eq(view.bar.ratio, 50.0 / 200.0, 0.001, "150 XP: 50 of 200 into level 2")
	assert_not_null(get_tree().root.find_child("LevelUpBanner", false, false), "the banner floats over the dialog")


func test_reward_level_banner_names_the_reward() -> void:
	var view := XpGainView.create({"xp": 20, "parts": [], "xp_before": 990, "xp_after": 1010, "level_before": 4, "level_after": 5})
	add_child_autofree(view)
	await wait_process_frames(2)
	view.skip()
	assert_eq(view.get_shown_level(), 5)
	assert_eq(view.get_banner_text(), "Level 5!")


func test_phone_menu_keeps_its_zoom_and_shows_the_card_over_the_gold() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	MobileUi.touch_override = 1
	MobileUi.phone_override = 1
	MobileUi.zoom_override = 4.0 / 3.0
	MobileUi.safe_inset_override = 60.0
	SaveManager.create_slot(1, "Nebeltal")
	var menu := MainMenu.new()
	add_child_autofree(menu)
	await wait_process_frames(3)
	var stage := menu.get_list().get_parent() as Control
	assert_almost_eq(stage.scale.x, 4.0 / 3.0, 0.001, "seven entries still fit under the logo at the phone zoom")
	var card := menu.get_account_card().get_global_rect()
	var currency := (menu.get("_currency") as Control).get_global_rect()
	assert_true(MobileUi.safe_rect(get_viewport()).grow(0.5).encloses(card), "inside the safe area")
	assert_lte(card.end.y, currency.position.y + 0.5, "over gold and crystals")
	assert_false(card.intersects(menu.get_list().get_global_rect()), "never over the menu list")


# --- KE1: rank, talent points, danger level ---

func test_card_shows_rank_and_free_points() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var menu := MainMenu.new()
	add_child_autofree(menu)
	await wait_process_frames(3)
	var card := menu.get_account_card()
	assert_eq(card.get_rank_text(), "Funke I", "a new account")
	assert_eq(card.get_points_text(), "", "level 1: no point yet")
	assert_false(card.badge.show_points)
	AccountProgress.current().mark_synced([], AccountProgress.xp_for_level(7))
	card.refresh()
	assert_eq(card.get_rank_text(), "Kerze I", "level 7, no runs: G 3")
	assert_eq(card.rank_badge.danger, 3)
	assert_eq(card.get_points_text(), "6 Punkte frei")
	assert_true(card.badge.show_points, "the badge sparks while points are free")
	AccountProgress.spent_points_source = func() -> int: return 5
	card.refresh()
	assert_eq(card.get_points_text(), "1 Punkt frei")
	AccountProgress.spent_points_source = func() -> int: return 6
	card.refresh()
	assert_eq(card.get_points_text(), "")
	assert_true(get_viewport().get_visible_rect().encloses(card.get_global_rect()), "still on screen")
	assert_false(card.get_global_rect().intersects(menu.get_list().get_global_rect()), "never over the menu list")


func test_run_end_names_a_rank_change() -> void:
	assert_eq(RunRecap.rank_change_text(2, 3), "Rang gestiegen: Kerze I")
	assert_eq(RunRecap.rank_change_text(4, 2), "Rang gesunken: Funke III")
	assert_eq(RunRecap.rank_change_text(3, 3), "")
	var up := XpGainView.create({"xp": 20, "parts": [], "xp_before": 120, "xp_after": 140, "level_before": 2,
			"level_after": 2, "danger_before": 3, "danger_after": 4})
	add_child_autofree(up)
	await wait_process_frames(2)
	up.skip()
	assert_eq(up.get_rank_text(), "Rang gestiegen: Kerze II")
	assert_not_null(up.find_child("RankBadge", true, false), "with the new rank's badge")
	var same := XpGainView.create({"xp": 5, "parts": [], "xp_before": 0, "xp_after": 5, "level_before": 1,
			"level_after": 1, "danger_before": 0, "danger_after": 0})
	add_child_autofree(same)
	await wait_process_frames(1)
	assert_eq(same.get_rank_text(), "", "no line while the rank stays")
	assert_null(same.find_child("RankChange", true, false))


func test_a_run_counts_its_danger_level() -> void:
	SaveManager.create_slot(1, "Nebeltal")
	var recap := RunRecap.new()
	add_child_autofree(recap)
	RunManager.set_danger_level(4)
	RunManager.start_run()
	for room in 2:
		EventBus.room_completed.emit(room + 1)
		RunManager.advance_room()
	RunManager.end_run(RunManager.EndReason.DEATH)
	var result := recap.get_xp_result()
	var danger := (result["parts"] as Array).filter(func(part: Dictionary) -> bool: return part["id"] == AccountProgress.PART_DANGER)
	assert_eq(danger.size(), 1, "G 4 adds its part")
	assert_eq(int(danger[0]["count"]), 4)
	var entry := AccountProgress.current().entries[-1]
	assert_eq(entry["danger"], 4, "the entry keeps the run's level")


func test_entrance_shows_rank_danger_and_loot() -> void:
	var village_script := GDScript.new()
	village_script.source_code = "extends Node2D\nsignal dungeon_requested\n"
	village_script.reload()
	var village := Node2D.new()
	village.set_script(village_script)
	var entrance := Node2D.new()
	entrance.position = Vector2(300, 200)
	add_child_autofree(village)
	village.add_child(entrance)
	var ui := VillageUI.new()
	ui.entrance_anchor = entrance
	village.add_child(ui)
	ui.set_process(false)
	AccountProgress.current().mark_synced([], AccountProgress.xp_for_level(9))
	assert_eq(ui.get_entrance_danger(), 4, "own level: L 9, no runs")
	ui.update_entrance([Vector2(1200, 200)] as Array[Vector2])
	assert_null(ui.get_entrance_info(), "far away: nothing")
	ui.update_entrance([Vector2(320, 240)] as Array[Vector2])
	var card := ui.get_entrance_info()
	assert_not_null(card, "near the entrance")
	assert_eq(ui.entrance_texts(), ["Dein Rang", "Kerze II", "Gefahrenstufe 4 · Beute +20 %"] as Array[String])
	assert_eq((card.find_child("EntranceRank", true, false) as Label).text, "Kerze II")
	assert_null(card.find_child("*Button*", true, false), "shown only, nothing to pick (D-196)")
	village.emit_signal(&"dungeon_requested")
	assert_eq(RunManager.get_danger_level(), 4, "the entrance hands the own level to the run")
	ui.set_group_danger(6)
	assert_eq(ui.entrance_texts(), ["Eure Gruppe", "Flamme I", "Gefahrenstufe 6 · Beute +30 %"] as Array[String])
	assert_eq((card.find_child("EntranceRank", true, false) as Label).text, "Flamme I", "the shown card follows")
	village.emit_signal(&"dungeon_requested")
	assert_eq(RunManager.get_danger_level(), 6, "in a group the host's level")
	ui.set_group_danger(-1)
	assert_eq(ui.get_entrance_danger(), 4)
	ui.show_notice("Neu", ["Etwas"] as Array[String])
	ui.update_entrance([Vector2(320, 240)] as Array[Vector2])
	assert_null(ui.get_entrance_info(), "never together with a notice")

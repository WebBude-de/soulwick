extends GutTest
## UX1/UX3 options: one OptionsView in the main menu and the pause menu (tabs Allgemein / Bild /
## Tasten: volumes, master, language, window mode, VSync, screen shake, hit stop, damage numbers,
## reduced flashes, reset), stored globally in settings.cfg [options]; the controls list reads the
## InputMap. Runs in a test folder (SaveManager.set_storage_root), never on the real settings/save.

const ROOT := "user://test_ux_options"

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String
var _old_music: float
var _old_sfx: float
var _old_locale: String
var _old_master_db: float


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	_old_music = SaveManager.get_volume(&"Music")
	_old_sfx = SaveManager.get_volume(&"SFX")
	_old_locale = TranslationServer.get_locale()
	_old_master_db = AudioServer.get_bus_volume_db(0)


func before_each() -> void:
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()
	CameraShake.enabled = true
	# Tests read German texts: the language option is "de" in this folder.
	GameOptions.set_language(&"de")


func after_each() -> void:
	GameManager.clear_pause_reasons()
	CameraShake.enabled = true


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
	CameraShake.enabled = true
	TranslationServer.set_locale(_old_locale)
	AudioServer.set_bus_volume_db(0, _old_master_db)


func _wipe() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	for dir_path in [root.path_join("saves"), root]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			DirAccess.remove_absolute(dir_path.path_join(file))
	DirAccess.make_dir_recursive_absolute(root)


func _view() -> OptionsView:
	var view := OptionsView.new()
	add_child_autofree(view)
	return view


func _key(keycode: Key) -> InputEventKey:
	return MenuInput.key_event(keycode)


func _saved_option(key: String) -> Variant:
	var config := ConfigFile.new()
	if config.load(SaveManager.settings_path) != OK:
		return null
	return config.get_value("options", key, null)


func test_defaults() -> void:
	# No settings file at all: every option at its default.
	_wipe()
	SaveManager.load_settings()
	assert_eq(GameOptions.get_language(), &"auto")
	assert_eq(GameOptions.get_window_mode(), GameOptions.WINDOWED)
	assert_false(GameOptions.is_fullscreen())
	assert_true(GameOptions.is_vsync_enabled())
	assert_eq(GameOptions.get_screen_shake_strength(), 1.0)
	assert_true(GameOptions.is_screen_shake_enabled())
	assert_true(GameOptions.is_hit_stop_enabled())
	assert_true(GameOptions.are_damage_numbers_enabled())
	assert_false(GameOptions.is_reduce_flashes_enabled())
	assert_eq(GameOptions.get_flash_strength(), 1.0)
	assert_eq(GameOptions.get_master_volume(), 1.0)


func test_view_starts_on_music_row_of_the_general_tab() -> void:
	var view := _view()
	assert_eq(view.get_tab(), OptionsView.Tab.GENERAL)
	assert_eq(view.get_row(), OptionsView.Row.MUSIC)
	assert_eq(view.get_page(), OptionsView.Page.SETTINGS)
	assert_eq(view.get_tab_buttons().size(), 3, "Allgemein · Bild · Tasten")


func test_screen_shake_has_three_strengths_and_is_stored() -> void:
	var view := _view()
	view.select_row(OptionsView.Row.SHAKE)
	assert_eq(view.get_tab(), OptionsView.Tab.DISPLAY, "selecting a row switches to its tab")
	assert_true(view.handle_input(_key(KEY_LEFT)), "←/→ switches the choice")
	assert_eq(GameOptions.get_screen_shake_strength(), 0.5, "normal -> light")
	assert_true(CameraShake.enabled)
	view.handle_input(_key(KEY_LEFT))
	assert_eq(GameOptions.get_screen_shake_strength(), 0.0, "light -> off")
	assert_false(GameOptions.is_screen_shake_enabled())
	assert_false(CameraShake.enabled, "CameraShake reads the switch")
	assert_eq(_saved_option("screen_shake"), 0.0, "stored as strength in settings.cfg [options]")
	# Applying at start restores it from the file.
	CameraShake.enabled = true
	SaveManager.load_settings()
	GameOptions.apply_all()
	assert_false(CameraShake.enabled)
	view.handle_input(_key(KEY_ENTER))
	assert_eq(GameOptions.get_screen_shake_strength(), 0.5, "Enter cycles on (wraps)")
	assert_true(CameraShake.enabled)


func test_ux1_bool_options_are_migrated() -> void:
	SaveManager.set_option(&"screen_shake", false)
	assert_eq(GameOptions.get_screen_shake_strength(), 0.0, "old false = off")
	SaveManager.set_option(&"screen_shake", true)
	assert_eq(GameOptions.get_screen_shake_strength(), 1.0, "old true = normal")
	SaveManager.set_option(&"fullscreen", true)
	assert_eq(GameOptions.get_window_mode(), GameOptions.FULLSCREEN_MODE, "old fullscreen=true reads as fullscreen")
	assert_true(GameOptions.is_fullscreen())
	GameOptions.set_fullscreen(false)
	assert_eq(_saved_option("window_mode"), "windowed")
	assert_false(GameOptions.is_fullscreen(), "window_mode wins over the old flag once set")


func test_disabled_shake_adds_no_trauma() -> void:
	var camera := CameraRig.new()
	add_child_autofree(camera)
	camera.make_current()
	CameraShake.enabled = false
	CameraShake.shake(camera, 10.0)
	assert_eq(camera.get("_trauma"), 0.0, "no shake while switched off")
	CameraShake.enabled = true
	CameraShake.shake(camera, 10.0)
	assert_gt(camera.get("_trauma"), 0.0)


func test_window_mode_choice_is_stored() -> void:
	var view := _view()
	var buttons := view.get_choice_buttons(OptionsView.Row.WINDOW)
	assert_eq(buttons.size(), 3, "Fenster | Vollbild | Randlos")
	(buttons[1] as Button).pressed.emit()
	assert_eq(GameOptions.get_window_mode(), GameOptions.FULLSCREEN_MODE)
	assert_true(GameOptions.is_fullscreen())
	assert_eq(_saved_option("window_mode"), "fullscreen")
	assert_eq(view.get_row(), OptionsView.Row.WINDOW, "clicking selects the row")
	(buttons[2] as Button).pressed.emit()
	assert_eq(GameOptions.get_window_mode(), GameOptions.BORDERLESS)
	assert_true(GameOptions.is_fullscreen(), "borderless covers the screen too")
	assert_true(GameOptions.handle_shortcut(_key(KEY_F11)), "F11 toggles")
	assert_false(GameOptions.is_fullscreen())
	GameOptions.handle_shortcut(_key(KEY_F11))
	assert_eq(GameOptions.get_window_mode(), GameOptions.FULLSCREEN_MODE)
	(buttons[0] as Button).pressed.emit()
	assert_eq(GameOptions.get_window_mode(), GameOptions.WINDOWED)


func test_two_way_switches_are_stored_and_read_back() -> void:
	var view := _view()
	view.select_row(OptionsView.Row.VSYNC)
	view.handle_input(_key(KEY_LEFT))
	assert_false(GameOptions.is_vsync_enabled())
	assert_eq(_saved_option("vsync"), false)
	view.select_row(OptionsView.Row.HIT_STOP)
	view.handle_input(_key(KEY_ENTER))
	assert_false(GameOptions.is_hit_stop_enabled(), "Enter toggles")
	view.select_row(OptionsView.Row.DAMAGE_NUMBERS)
	view.handle_input(_key(KEY_RIGHT))
	assert_false(GameOptions.are_damage_numbers_enabled(), "wraps from An to Aus")
	view.select_row(OptionsView.Row.REDUCE_FLASHES)
	view.handle_input(_key(KEY_RIGHT))
	assert_true(GameOptions.is_reduce_flashes_enabled())
	assert_eq(GameOptions.get_flash_strength(), GameOptions.REDUCED_FLASH_STRENGTH)
	SaveManager.load_settings()
	assert_false(GameOptions.is_vsync_enabled(), "read back from the file")
	assert_false(GameOptions.is_hit_stop_enabled())
	assert_false(GameOptions.are_damage_numbers_enabled())
	assert_true(GameOptions.is_reduce_flashes_enabled())


func test_volume_rows_and_saving() -> void:
	var view := _view()
	var before := SaveManager.get_volume(&"SFX")
	view.select_row(OptionsView.Row.SFX)
	view.handle_input(_key(KEY_LEFT))
	assert_almost_eq(SaveManager.get_volume(&"SFX"), maxf(0.0, before - OptionsView.STEP), 0.0001)
	view.save_volumes()
	var config := ConfigFile.new()
	assert_eq(config.load(SaveManager.settings_path), OK)
	assert_almost_eq(float(config.get_value("audio", "volume_sfx")), SaveManager.get_volume(&"SFX"), 0.0001)
	assert_not_null(view.get_volume_slider(&"Music"))
	assert_not_null(view.get_volume_slider(&"Master"))


func test_master_volume_is_an_option_and_moves_the_master_bus() -> void:
	var view := _view()
	view.select_row(OptionsView.Row.MASTER)
	view.handle_input(_key(KEY_LEFT))
	view.handle_input(_key(KEY_LEFT))
	assert_almost_eq(GameOptions.get_master_volume(), 0.9, 0.0001)
	assert_almost_eq(float(_saved_option("master_volume")), 0.9, 0.0001, "stored at once in [options]")
	assert_almost_eq(AudioServer.get_bus_volume_db(0), linear_to_db(0.9), 0.01, "applied to bus Master")
	assert_almost_eq(SaveManager.get_volume(&"Music"), SaveManager.DEFAULT_VOLUMES[&"Music"], 0.0001, "music untouched")
	SaveManager.load_settings()
	GameOptions.apply_all()
	assert_almost_eq(AudioServer.get_bus_volume_db(0), linear_to_db(0.9), 0.01, "restored at start")


func test_rows_wrap_tabs_switch_and_escape_is_left_to_the_host() -> void:
	var view := _view()
	assert_eq(view.get_row(), OptionsView.Row.MUSIC)
	view.handle_input(_key(KEY_UP))
	assert_eq(view.get_row(), OptionsView.Row.TABS, "↑ from the first row reaches the tab strip")
	view.handle_input(_key(KEY_UP))
	assert_eq(view.get_row(), OptionsView.Row.RESET, "↑ from the tabs wraps to Zurücksetzen")
	view.handle_input(_key(KEY_DOWN))
	assert_eq(view.get_row(), OptionsView.Row.TABS)
	assert_true(view.handle_input(_key(KEY_RIGHT)))
	assert_eq(view.get_tab(), OptionsView.Tab.DISPLAY, "→ on the tab row switches the tab")
	view.handle_input(_key(KEY_DOWN))
	assert_eq(view.get_row(), OptionsView.Row.WINDOW)
	assert_true(view.handle_input(_key(KEY_E)), "E = next tab anywhere")
	assert_eq(view.get_tab(), OptionsView.Tab.CONTROLS)
	assert_eq(view.get_page(), OptionsView.Page.CONTROLS)
	assert_true(view.handle_input(_key(KEY_Q)))
	assert_eq(view.get_tab(), OptionsView.Tab.DISPLAY)
	assert_false(view.handle_input(_key(KEY_ESCAPE)), "Esc is left to the host")
	view.show_controls()
	assert_eq(view.get_page(), OptionsView.Page.CONTROLS)
	view.show_settings()
	assert_eq(view.get_tab(), OptionsView.Tab.GENERAL)


func test_reset_asks_first_and_restores_defaults_but_not_slots() -> void:
	SaveManager.create_slot(2, "Bleibt", &"hero")
	GameOptions.set_vsync(false)
	GameOptions.set_screen_shake_strength(0.0)
	GameOptions.set_master_volume(0.5)
	SaveManager.set_volume(&"Music", 0.3)
	var view := _view()
	view.select_row(OptionsView.Row.RESET)
	assert_true(view.handle_input(_key(KEY_ENTER)))
	assert_true(view.is_confirming_reset(), "asks first")
	assert_true(view.handle_input(_key(KEY_ESCAPE)), "Esc cancels the question (used by the view)")
	assert_false(view.is_confirming_reset())
	assert_false(GameOptions.is_vsync_enabled(), "nothing changed")
	view.handle_input(_key(KEY_ENTER))
	view.handle_input(_key(KEY_ENTER))
	assert_false(view.is_confirming_reset())
	assert_true(GameOptions.is_vsync_enabled())
	assert_eq(GameOptions.get_screen_shake_strength(), 1.0)
	assert_eq(GameOptions.get_master_volume(), 1.0)
	assert_eq(GameOptions.get_language(), &"auto")
	assert_almost_eq(SaveManager.get_volume(&"Music"), SaveManager.DEFAULT_VOLUMES[&"Music"], 0.0001)
	assert_almost_eq(view.get_volume_slider(&"Music").value, SaveManager.DEFAULT_VOLUMES[&"Music"], 0.0001, "slider follows")
	assert_true(SaveManager.has_slot(2), "save slots stay")
	assert_eq(SaveManager.get_profile_name(), "Bleibt")


func test_language_row_switches_the_locale_and_the_open_view() -> void:
	var view := _view()
	view.select_row(OptionsView.Row.LANGUAGE)
	assert_eq(view.get_caption_text(OptionsView.Row.MUSIC), "Musik")
	assert_true(view.handle_input(_key(KEY_LEFT)), "de -> en")
	assert_eq(GameOptions.get_language(), &"en")
	assert_eq(_saved_option("language"), "en")
	assert_eq(Loc.current_language(), &"en")
	assert_eq(view.get_caption_text(OptionsView.Row.MUSIC), "Music", "captions re-translate at once")
	assert_eq(view.get_caption_text(OptionsView.Row.LANGUAGE), "> Language")
	view.handle_input(_key(KEY_LEFT))
	assert_eq(GameOptions.get_language(), &"auto", "en -> auto")
	assert_eq(Loc.current_language(), Loc.resolve(&"auto"))
	GameOptions.set_language(&"de")
	assert_eq(view.get_caption_text(OptionsView.Row.MUSIC), "Musik")


func test_controls_list_reads_the_input_map_in_both_languages() -> void:
	assert_eq(ControlsInfo.key_text(ControlsInfo.ATTACK), "Linksklick")
	assert_eq(ControlsInfo.key_text(ControlsInfo.SPECIAL), "Rechtsklick")
	assert_eq(ControlsInfo.key_text(ControlsInfo.DASH), "Leertaste")
	assert_eq(ControlsInfo.key_text(ControlsInfo.PAUSE), "Esc")
	assert_eq(ControlsInfo.caption(ControlsInfo.MOVE), "Bewegen")
	assert_eq(ControlsInfo.key_text(ControlsInfo.MOVE).split(" ").size(), 4, "four move keys")
	for id in ControlsInfo.get_ids():
		assert_false(ControlsInfo.key_text(id).is_empty(), "%s has a key" % id)
		assert_false(ControlsInfo.caption(id).is_empty(), "%s has a caption" % id)
	GameOptions.set_language(&"en")
	assert_eq(ControlsInfo.key_text(ControlsInfo.ATTACK), "Left click")
	assert_eq(ControlsInfo.key_text(ControlsInfo.DASH), "Space")
	assert_eq(ControlsInfo.caption(ControlsInfo.MOVE), "Move")
	assert_eq(ControlsInfo.note(ControlsInfo.DASH), "briefly invulnerable")


func test_main_menu_and_pause_menu_use_the_same_view() -> void:
	var panel := OptionsPanel.new()
	add_child_autofree(panel)
	assert_not_null(panel.view, "main menu panel hosts an OptionsView")
	var ui := GameUI.new()
	add_child_autofree(ui)
	ui.open_pause_menu()
	await wait_physics_frames(1)
	var pause := ui.get_pause_modal()
	assert_not_null(pause)
	ui.open_options()
	await wait_physics_frames(1)
	var views := ui.find_children("*", "OptionsView", true, false)
	assert_eq(views.size(), 1, "pause menu opens the shared OptionsView")
	assert_false(pause.visible, "pause menu hides under the options")
	assert_true(GameManager.is_game_paused())
	(views[0] as OptionsView).back_requested.emit()
	await wait_physics_frames(2)
	assert_true(pause.visible, "back returns to the pause menu")
	assert_true(GameManager.has_pause_reason(GameManager.PAUSE_MENU), "pause menu keeps the game paused")
	pause.finish(&"resume")
	await wait_physics_frames(1)
	assert_false(GameManager.is_game_paused())


func test_pause_menu_moves_with_arrow_keys() -> void:
	var ui := GameUI.new()
	add_child_autofree(ui)
	ui.open_pause_menu()
	await wait_physics_frames(1)
	var pause := ui.get_pause_modal()
	assert_true(pause.input_handler.call(_key(KEY_DOWN)), "↓ moves the highlight")
	watch_signals(pause)
	# Second entry is "Optionen": Enter opens the options over the pause menu.
	assert_true(pause.input_handler.call(_key(KEY_ENTER)))
	await wait_physics_frames(1)
	assert_eq(ui.find_children("*", "OptionsView", true, false).size(), 1)
	assert_signal_not_emitted(pause, "finished")
	GameManager.clear_pause_reasons()

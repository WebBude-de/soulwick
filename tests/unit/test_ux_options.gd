extends GutTest
## UX1 options: one OptionsView in the main menu and the pause menu (volumes, window mode, screen
## shake, key overview), stored globally in settings.cfg [options]; the controls list reads the
## InputMap. Runs in a test folder (SaveManager.set_storage_root), never on the real settings/save.

const ROOT := "user://test_ux_options"

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String
var _old_music: float
var _old_sfx: float


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	_old_music = SaveManager.get_volume(&"Music")
	_old_sfx = SaveManager.get_volume(&"SFX")


func before_each() -> void:
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()
	CameraShake.enabled = true


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


func test_defaults_are_window_and_shake_on() -> void:
	assert_false(GameOptions.is_fullscreen())
	assert_true(GameOptions.is_screen_shake_enabled())


func test_screen_shake_switch_is_stored_and_respected() -> void:
	var view := _view()
	view.select_row(OptionsView.Row.SHAKE)
	assert_true(view.handle_input(_key(KEY_LEFT)), "←/→ switches the two-way choice")
	assert_false(GameOptions.is_screen_shake_enabled())
	assert_false(CameraShake.enabled, "CameraShake reads the switch")
	assert_eq(_saved_option("screen_shake"), false, "stored in settings.cfg [options]")
	# Applying at start restores it from the file.
	CameraShake.enabled = true
	SaveManager.load_settings()
	GameOptions.apply_all()
	assert_false(CameraShake.enabled)
	view.handle_input(_key(KEY_ENTER))
	assert_true(CameraShake.enabled, "Enter toggles back")


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
	assert_eq(buttons.size(), 2, "Fenster | Vollbild")
	(buttons[1] as Button).pressed.emit()
	assert_true(GameOptions.is_fullscreen())
	assert_eq(_saved_option("fullscreen"), true)
	assert_eq(view.get_row(), OptionsView.Row.WINDOW, "clicking selects the row")
	(buttons[0] as Button).pressed.emit()
	assert_false(GameOptions.is_fullscreen())


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


func test_rows_wrap_and_controls_page_goes_back_with_escape() -> void:
	var view := _view()
	assert_eq(view.get_row(), OptionsView.Row.MUSIC)
	view.handle_input(_key(KEY_UP))
	assert_eq(view.get_row(), OptionsView.Row.CONTROLS, "↑ from the first row wraps to the last")
	assert_true(view.handle_input(_key(KEY_ENTER)))
	assert_eq(view.get_page(), OptionsView.Page.CONTROLS)
	assert_true(view.handle_input(_key(KEY_ESCAPE)), "Esc on the key page is used by the view")
	assert_eq(view.get_page(), OptionsView.Page.SETTINGS)
	assert_false(view.handle_input(_key(KEY_ESCAPE)), "Esc on the settings page is left to the host")


func test_controls_list_reads_the_input_map() -> void:
	assert_eq(ControlsInfo.key_text(ControlsInfo.ATTACK), "Linksklick")
	assert_eq(ControlsInfo.key_text(ControlsInfo.SPECIAL), "Rechtsklick")
	assert_eq(ControlsInfo.key_text(ControlsInfo.DASH), "Leertaste")
	assert_eq(ControlsInfo.key_text(ControlsInfo.PAUSE), "Esc")
	assert_eq(ControlsInfo.key_text(ControlsInfo.MOVE).split(" ").size(), 4, "four move keys")
	for id in ControlsInfo.get_ids():
		assert_false(ControlsInfo.key_text(id).is_empty(), "%s has a key" % id)
		assert_false(ControlsInfo.caption(id).is_empty(), "%s has a caption" % id)


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

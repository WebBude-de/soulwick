extends GutTest
## L1 option "Lichteffekte: Hoch / Niedrig" (GameOptions -> LightingQuality) and the options window
## that keeps one size: switching tabs or rows, in German and in English, never resizes the main
## menu panel or the pause dialog. Runs in a test folder (SaveManager.set_storage_root), never on
## the real settings/save.

const ROOT := "user://test_lighting_fx_options"

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String
var _old_locale: String


func before_all() -> void:
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


func after_each() -> void:
	GameManager.clear_pause_reasons()
	LightingQuality.set_high(true)


func after_all() -> void:
	_wipe()
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()
	GameOptions.apply_light_effects()
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


# --- Option ---

func test_light_effects_default_high_and_stored() -> void:
	SaveManager.load_settings()
	assert_eq(GameOptions.get_light_effects(), GameOptions.LIGHT_HIGH, "Hoch is the default")
	GameOptions.apply_all()
	assert_true(LightingQuality.is_high())
	GameOptions.set_light_effects(GameOptions.LIGHT_LOW)
	assert_false(LightingQuality.is_high(), "applied at once")
	assert_eq(SaveManager.get_option(GameOptions.LIGHT_EFFECTS, ""), "low", "stored as an option")
	GameOptions.set_light_effects(&"nonsense")
	assert_eq(GameOptions.get_light_effects(), GameOptions.LIGHT_HIGH, "unknown values fall back to high")


func test_reset_restores_high() -> void:
	GameOptions.set_light_effects(GameOptions.LIGHT_LOW)
	GameOptions.reset_to_defaults()
	assert_eq(GameOptions.get_light_effects(), GameOptions.LIGHT_HIGH)
	assert_true(LightingQuality.is_high())


func test_options_row_switches_the_light_effects() -> void:
	var view := OptionsView.new()
	add_child_autofree(view)
	view.select_row(OptionsView.Row.LIGHT_EFFECTS)
	assert_eq(view.get_tab(), OptionsView.Tab.DISPLAY, "the row lives in the Bild tab")
	var buttons := view.get_choice_buttons(OptionsView.Row.LIGHT_EFFECTS)
	assert_eq(buttons.size(), 2, "Niedrig | Hoch")
	assert_eq(tr((buttons[0] as Button).text), "Niedrig")
	assert_eq(tr((buttons[1] as Button).text), "Hoch")
	view.change(-1)
	assert_eq(GameOptions.get_light_effects(), GameOptions.LIGHT_LOW)
	assert_false(LightingQuality.is_high())
	view.change(1)
	assert_eq(GameOptions.get_light_effects(), GameOptions.LIGHT_HIGH)
	assert_true(LightingQuality.is_high())


func test_low_quality_stops_ambient_particles() -> void:
	var particles: AmbientParticles = add_child_autofree(AmbientParticles.new())
	particles.set_biome(&"ember_forge")
	assert_true(particles.emitting)
	assert_true(particles.get_accent().emitting, "sparks fly in the ember forge")
	GameOptions.set_light_effects(GameOptions.LIGHT_LOW)
	assert_false(particles.emitting, "low: no ambient particles")
	assert_false(particles.get_accent().emitting)
	GameOptions.set_light_effects(GameOptions.LIGHT_HIGH)
	assert_true(particles.emitting, "back on with high")
	assert_true(particles.get_accent().emitting)


# --- Window keeps its size ---

## Minimum size of host for every tab and every row of the Bild tab (the size its container gives it).
func _sizes(host: Control, view: OptionsView) -> Array[Vector2]:
	var sizes: Array[Vector2] = []
	for tab in [OptionsView.Tab.DISPLAY, OptionsView.Tab.CONTROLS, OptionsView.Tab.GENERAL, OptionsView.Tab.DISPLAY]:
		view.show_tab(tab)
		await wait_process_frames(2)
		sizes.append(host.get_combined_minimum_size())
	for row in OptionsView.TAB_ROWS[OptionsView.Tab.DISPLAY]:
		view.select_row(row)
		await wait_process_frames(1)
		sizes.append(host.get_combined_minimum_size())
	return sizes


func _assert_all_equal(sizes: Array[Vector2], what: String) -> void:
	for size in sizes:
		assert_almost_eq(size.x, sizes[0].x, 0.5, what + ": width stays")
		assert_almost_eq(size.y, sizes[0].y, 0.5, what + ": height stays")


func test_main_menu_panel_keeps_its_size_on_every_tab() -> void:
	for language in [&"de", &"en"]:
		GameOptions.set_language(language)
		var panel := OptionsPanel.new()
		add_child_autofree(panel)
		await wait_process_frames(2)
		var sizes := await _sizes(panel, panel.view)
		_assert_all_equal(sizes, "main menu (%s)" % language)
		panel.queue_free()
		await wait_process_frames(1)


func test_pause_dialog_keeps_its_size_on_every_tab() -> void:
	for language in [&"de", &"en"]:
		GameOptions.set_language(language)
		var ui := GameUI.new()
		add_child_autofree(ui)
		ui.open_options()
		await wait_process_frames(2)
		var views := ui.find_children("*", "OptionsView", true, false)
		assert_eq(views.size(), 1)
		var view := views[0] as OptionsView
		var modal := view.get_parent()
		while modal != null and not modal is Modal:
			modal = modal.get_parent()
		assert_not_null(modal)
		var sizes := await _sizes((modal as Modal).frame, view)
		_assert_all_equal(sizes, "pause (%s)" % language)
		GameManager.clear_pause_reasons()
		ui.queue_free()
		await wait_process_frames(1)


func test_language_switch_in_the_open_view_keeps_tabs_equal() -> void:
	var panel := OptionsPanel.new()
	add_child_autofree(panel)
	await wait_process_frames(2)
	GameOptions.set_language(&"en")
	await wait_process_frames(2)
	_assert_all_equal(await _sizes(panel, panel.view), "after switching to English")

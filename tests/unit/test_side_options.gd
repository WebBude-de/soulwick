extends GutTest
## "Seitenwege auslassen" (M5, R8 options menu): the switch in the "Allgemein" tab stores the option
## SideWays reads, resets with the other options and is translated (en + de); the side dash is an
## input action of the project (keyboard Shift) with a gamepad button (GamepadInput).
## Runs in a test folder (SaveManager.set_storage_root), never on the real settings/save.

const ROOT := "user://test_side_options"

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
	SaveManager.set_storage_root(ROOT)


func before_each() -> void:
	SaveManager.set_option(SideRules.OPTION_SKIP, false)
	GameOptions.set_language(&"de")


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ROOT.path_join("settings.cfg")))
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	TranslationServer.set_locale(_old_locale)


func test_option_is_the_key_side_ways_reads() -> void:
	assert_eq(GameOptions.SKIP_SIDE_PATHS, SideRules.OPTION_SKIP)
	assert_false(GameOptions.is_skip_side_paths_enabled(), "segments are on by default")
	GameOptions.set_skip_side_paths(true)
	assert_true(SideWays.is_skipped())
	assert_true(GameOptions.is_skip_side_paths_enabled())
	GameOptions.reset_to_defaults()
	assert_false(SideWays.is_skipped(), "reset switches segments on again")


func test_switch_sits_in_the_general_tab() -> void:
	var view := OptionsView.new()
	add_child_autofree(view)
	assert_true((OptionsView.TAB_ROWS[OptionsView.Tab.GENERAL] as Array).has(OptionsView.Row.SKIP_SIDE_PATHS))
	view.select_row(OptionsView.Row.SKIP_SIDE_PATHS)
	assert_eq(view.get_tab(), OptionsView.Tab.GENERAL)
	assert_eq(view.get_caption_text(OptionsView.Row.SKIP_SIDE_PATHS), "> Seitenwege auslassen")
	var buttons := view.get_choice_buttons(OptionsView.Row.SKIP_SIDE_PATHS)
	assert_eq(buttons.size(), 2, "Aus | An")
	(buttons[1] as Button).pressed.emit()
	assert_true(SideWays.is_skipped(), "An: no side segments")
	view.change(1)
	assert_false(SideWays.is_skipped(), "→ wraps back to Aus")
	var notes := view.find_children("*", "Label", true, false).filter(func(node: Node) -> bool:
		return (node as Label).text == "SIDE_OPTION_SKIP_NOTE")
	assert_eq(notes.size(), 1, "a muted line says what the switch does")


func test_texts_in_both_languages() -> void:
	for key: StringName in [&"OPTIONS_SECTION_GAME", &"SIDE_OPTION_SKIP", &"SIDE_OPTION_SKIP_NOTE"]:
		TranslationServer.set_locale("en")
		var english := tr(key)
		TranslationServer.set_locale("de")
		var german := tr(key)
		assert_ne(english, String(key), "%s has an English text" % key)
		assert_ne(german, String(key), "%s has a German text" % key)
		assert_ne(english, german, "%s differs per language" % key)


func test_side_dash_is_a_project_action_with_key_and_gamepad() -> void:
	assert_true(ProjectSettings.has_setting("input/" + String(PlayerSideMotion.DASH_ACTION)), "side_dash in project.godot")
	assert_true(InputMap.has_action(PlayerSideMotion.DASH_ACTION))
	# The gamepad buttons come from GamepadInput (P0-2), added at start.
	load("res://player/input/gamepad_input.gd").ensure_actions()
	var key := false
	var pad := false
	for event in InputMap.action_get_events(PlayerSideMotion.DASH_ACTION):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == PlayerSideMotion.DASH_KEY:
			key = true
		if event is InputEventJoypadButton:
			pad = true
	assert_true(key, "Shift")
	assert_true(pad, "a gamepad button")

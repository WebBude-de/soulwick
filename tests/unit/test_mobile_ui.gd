extends GutTest
## Phones and touch screens (MobileUi, Projektmitglied 17.10.2026: "kein X im Pausemenü, Menü viel
## größer am Smartphone"): menu zoom and its pixel-art snapping, dialogs inside the safe area with an
## X, scrolling when too tall, key hints hidden on touch, the compact main menu, and the PC unchanged
## (zoom 1, no X, R8 limits). Phone and touch are simulated with MobileUi's test overrides. Uses a
## test save and a test settings folder, never the real ones.

const MobileUi := preload("res://ui/menus/mobile_ui.gd")
const KeyLine := preload("res://ui/widgets/key_line.gd")
const ROOT := "user://test_mobile_ui"
const PHONE_ZOOM := 4.0 / 3.0

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
	SaveManager.load_game()
	TranslationServer.set_locale("de")
	MainMenu.online_check = false
	MainMenu.ask_profile_on_start = false


func after_all() -> void:
	_reset_overrides()
	GameManager.clear_pause_reasons()
	MainMenu.online_check = true
	MainMenu.ask_profile_on_start = true
	_wipe()
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()
	TranslationServer.set_locale(_old_locale)


func before_each() -> void:
	_reset_overrides()


func after_each() -> void:
	_reset_overrides()
	GameManager.clear_pause_reasons()


func _reset_overrides() -> void:
	MobileUi.zoom_override = 0.0
	MobileUi.touch_override = -1
	MobileUi.phone_override = -1
	MobileUi.safe_inset_override = -1.0
	MobileUi.size_mode = MobileUi.SizeMode.AUTO


func _wipe() -> void:
	var folder := ProjectSettings.globalize_path(ROOT)
	for dir_path in [folder.path_join("saves"), folder]:
		var dir := DirAccess.open(dir_path)
		if dir != null:
			for file in dir.get_files():
				DirAccess.remove_absolute(dir_path.path_join(file))


## A phone: touch screen, phone, menus PHONE_ZOOM larger.
func _phone(safe_inset := 0.0) -> void:
	MobileUi.touch_override = 1
	MobileUi.phone_override = 1
	MobileUi.zoom_override = PHONE_ZOOM
	MobileUi.safe_inset_override = safe_inset


func _desktop() -> void:
	MobileUi.touch_override = 0
	MobileUi.phone_override = 0


func _confirm_dialog(rows := 0) -> Modal:
	var modal := UiDialog.create_menu(GameManager.PAUSE_CONFIRM, UiDialog.WIDTH_NARROW, "Wirklich?",
			"Ein Text, der umbricht, damit der Dialog etwas Höhe hat.", "ENTSCHEIDUNG")
	modal.cancel_result = &"cancelled"
	for i in rows:
		modal.content.add_child(UiKit.value_row("Zeile %d" % i, str(i)))
	UiDialog.add_buttons(modal, [
		{"text": "Ja", "key": "Enter", "result": &"yes", "default": true},
		{"text": "Nein", "key": "Esc", "result": &"no"},
	])
	modal.set_key_hints([["Enter", "ja"], ["Esc", "nein"]])
	modal.input_guard = 0.0
	return modal


# --- Rules ---

func test_zoom_snaps_to_whole_device_pixels_per_art_pixel() -> void:
	# 1280×720 window: one art pixel = 3 device pixels; 4 or 5 are the next even steps.
	assert_almost_eq(MobileUi.snap_zoom(1.31, 1.0), 4.0 / 3.0, 0.001)
	assert_almost_eq(MobileUi.snap_zoom(1.6, 1.0), 5.0 / 3.0, 0.001)
	# 2400×1080 phone (1.5 device pixels per viewport pixel): steps of 1/4.5.
	assert_almost_eq(MobileUi.snap_zoom(1.31, 1.5), 6.0 / 4.5, 0.001)
	assert_eq(MobileUi.snap_zoom(0.7, 1.0), 1.0, "never smaller than the PC")


func test_fit_zoom_lowers_until_the_width_fits() -> void:
	var zoom := MobileUi.fit_zoom(PHONE_ZOOM, Vector2(1205, 1), Vector2(1500, 700), 1.0)
	assert_lte(1205.0 * zoom, 1500.0, "fits")
	assert_almost_eq(zoom, 1.0, 0.001, "next lower even step is 1")
	assert_almost_eq(MobileUi.fit_zoom(PHONE_ZOOM, Vector2(600, 1), Vector2(1500, 700)), PHONE_ZOOM, 0.001)
	assert_eq(MobileUi.fit_zoom(PHONE_ZOOM, Vector2(2000, 1), Vector2(1500, 700)), 1.0, "too wide even at 1: stays 1")


func test_desktop_keeps_zoom_one_and_shows_keys() -> void:
	_desktop()
	assert_eq(MobileUi.menu_zoom(get_tree().root), 1.0)
	assert_false(MobileUi.hides_key_hints())
	assert_eq(MobileUi.min_touch_height(get_tree().root), 0.0, "no touch minimum on the PC")
	MobileUi.size_mode = MobileUi.SizeMode.LARGE
	assert_gt(MobileUi.menu_zoom(get_tree().root), 1.0, "option UI size 'Groß' also on the PC")


## Report #0efb405c: a 2560×1366 browser window showing 1349×720 (1.897 device pixels per pixel)
## gave the PC zoom 1.054 and a forge that scrolled a little. D-169: without touch exactly 1.
func test_desktop_zoom_stays_one_at_any_window_ratio() -> void:
	var odd_ratio := minf(2560.0 / 1349.0, 1366.0 / 720.0)
	for ratio in [1.0, 1.5, odd_ratio, 2.25]:
		assert_eq(MobileUi.zoom_for(false, 0.0, MobileUi.SizeMode.AUTO, ratio), 1.0, "PC at %.3f" % ratio)
		assert_eq(MobileUi.zoom_for(false, 0.0, MobileUi.SizeMode.NORMAL, ratio), 1.0)
	assert_gt(MobileUi.zoom_for(false, 0.0, MobileUi.SizeMode.LARGE, odd_ratio), 1.0, "'Groß' still on the PC")
	# Touch screens keep the snapping to whole device pixels (D-169).
	var touch := MobileUi.zoom_for(true, MobileUi.TARGET_BODY_DP / 1.3, MobileUi.SizeMode.AUTO, odd_ratio)
	assert_gt(touch, 1.0)
	var art := MobileUi.ART_PX * odd_ratio * touch
	assert_almost_eq(art, roundf(art), 0.001, "one art pixel = whole device pixels")


func test_desktop_dialog_taller_than_the_screen_scrolls() -> void:
	_desktop()
	var modal := _confirm_dialog(90)
	modal.show_on(self)
	await wait_process_frames(3)
	assert_eq(modal.zoom, 1.0)
	assert_true(modal.is_scrolling(), "too tall even at zoom 1: scrolls instead of being cut off")
	assert_lte(modal.get_panel_rect().size.y, get_viewport().get_visible_rect().size.y + 0.5, "on screen")
	assert_false(modal.has_close_button(), "still no X on the PC")
	modal.finish()


func test_phone_zoom_follows_the_physical_text_size() -> void:
	MobileUi.touch_override = 1
	MobileUi.phone_override = 1
	var viewport := get_tree().root
	var body_dp := MobileUi.BODY_PX * MobileUi.dp_per_pixel(viewport)
	var zoom := MobileUi.menu_zoom(viewport)
	if body_dp >= MobileUi.TARGET_BODY_DP:
		assert_eq(zoom, 1.0, "big screen: like the PC")
	else:
		assert_gt(zoom, 1.0, "small text gets bigger")
	assert_lte(zoom, MobileUi.MAX_ZOOM)
	MobileUi.size_mode = MobileUi.SizeMode.NORMAL
	assert_eq(MobileUi.menu_zoom(viewport), 1.0, "option 'Normal': like the PC")


# --- Dialogs ---

func test_desktop_dialog_is_unchanged() -> void:
	_desktop()
	var modal := _confirm_dialog()
	modal.show_on(self)
	await wait_process_frames(2)
	assert_eq(modal.zoom, 1.0)
	assert_false(modal.has_close_button(), "no X on the PC")
	assert_false(modal.is_scrolling())
	assert_true(modal.fits_screen(), "R8: at most 60 % of the screen")
	assert_true(modal.key_bar.find_children("*", "UiChip", true, false).size() > 0, "key caps on the PC")
	modal.finish()


func test_phone_dialog_is_larger_inside_the_safe_area_with_an_x() -> void:
	_phone(60.0)
	var modal := _confirm_dialog()
	modal.show_on(self)
	await wait_process_frames(3)
	assert_almost_eq(modal.zoom, PHONE_ZOOM, 0.001, "drawn larger")
	assert_true(modal.has_close_button(), "Esc closes it: X on touch")
	assert_true(modal.fits_safe_area(), "panel and X inside the safe area")
	var safe := MobileUi.safe_rect(get_viewport())
	assert_gt(safe.position.x, 0.0, "the simulated notch narrows the safe area")
	for chip: UiChip in modal.frame.find_children("*", "UiChip", true, false):
		if chip.name == &"Key" or chip.name == &"KeyCap":
			assert_false(chip.is_visible_in_tree(), "no key caps on touch: %s" % chip.get_text())
	var buttons := modal.focus_targets()
	assert_eq(buttons.size(), 2)
	for button in buttons:
		assert_gte(button.custom_minimum_size.y, MobileUi.min_touch_height(get_tree().root, PHONE_ZOOM) - 0.5, "tall enough to tap")
	watch_signals(modal)
	modal.get_close_button().pressed.emit()
	assert_signal_emitted_with_parameters(modal, "finished", [&"cancelled"])


func test_dialog_without_cancel_has_no_x() -> void:
	_phone()
	var modal := _confirm_dialog()
	modal.cancel_allowed = false
	modal.show_on(self)
	await wait_process_frames(2)
	assert_false(modal.has_close_button(), "upgrade choice, run end: no X")
	modal.finish()


func test_too_tall_dialog_scrolls_on_a_phone() -> void:
	_phone()
	var modal := _confirm_dialog(40)
	modal.show_on(self)
	await wait_process_frames(3)
	assert_true(modal.is_scrolling(), "40 rows scroll")
	assert_true(modal.fits_safe_area(), "the panel itself stays on screen")
	assert_almost_eq(modal.zoom, PHONE_ZOOM, 0.001, "the height does not shrink the text")
	modal.finish()


func test_pause_menu_has_an_x_that_resumes() -> void:
	_phone()
	var game_ui: GameUI = add_child_autofree(GameUI.new())
	game_ui.open_pause_menu()
	await wait_process_frames(3)
	var modal := game_ui.get_pause_modal()
	assert_not_null(modal)
	assert_true(modal.has_close_button(), "pause menu: X on touch")
	assert_true(modal.fits_safe_area())
	var footer := modal.content.get_node("Footer") as KeyLine
	assert_false(footer.get_text().is_empty())
	assert_false("Esc" in footer.label.text, "no keys in the footer on touch")
	modal.input_guard = 0.0
	modal.get_close_button().pressed.emit()
	await wait_process_frames(2)
	assert_null(game_ui.get_pause_modal(), "X resumes")


func test_desktop_pause_menu_has_no_x() -> void:
	_desktop()
	var game_ui: GameUI = add_child_autofree(GameUI.new())
	game_ui.open_pause_menu()
	await wait_process_frames(2)
	var modal := game_ui.get_pause_modal()
	assert_false(modal.has_close_button())
	assert_true(modal.fits_screen())
	modal.finish(&"resume")
	await wait_process_frames(1)


func test_key_line_shows_its_touch_text_or_hides() -> void:
	_phone()
	var line := KeyLine.new()
	line.setup(UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
	line.set_texts("↑↓ wählen · Esc zurück")
	add_child_autofree(line)
	assert_false(line.visible, "only keys: hidden on touch")
	line.set_touch_text("Raum 3 · Spiel pausiert")
	assert_true(line.visible)
	assert_eq(line.label.text, "Raum 3 · Spiel pausiert")
	_desktop()
	line.set_texts("↑↓ wählen · Esc zurück")
	assert_eq(line.label.text, "↑↓ wählen · Esc zurück", "keys again on the PC")


# --- Safe area and HUD layers ---

func test_fit_to_safe_area_keeps_a_layer_clear_of_the_notch() -> void:
	MobileUi.safe_inset_override = 90.0
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(layer)
	MobileUi.fit_to_safe_area(layer)
	var scale := MobileUi.device_scale(get_viewport())
	assert_almost_eq(layer.offset_left, 90.0 / scale, 0.5)
	assert_almost_eq(layer.offset_right, -90.0 / scale, 0.5)
	MobileUi.safe_inset_override = 0.0
	MobileUi.apply_safe_offsets(layer)
	assert_eq(layer.offset_left, 0.0, "no notch: full screen")


# --- Main menu ---

func test_compact_main_menu_fits_and_panels_get_an_x() -> void:
	_phone(60.0)
	var menu := MainMenu.new()
	add_child_autofree(menu)
	await wait_process_frames(3)
	var list := menu.get_list()
	var stage := list.get_parent() as Control
	assert_almost_eq(stage.scale.x, PHONE_ZOOM, 0.001, "logo and list drawn larger")
	assert_lte(list.position.y + list.get_combined_minimum_size().y, stage.size.y + 0.5, "the whole list fits")
	var safe := MobileUi.safe_rect(get_viewport())
	assert_gte(stage.position.x, safe.position.x - 0.5, "inside the safe area")
	var panel := menu.open_slots()
	await wait_process_frames(3)
	var panel_rect := panel.get_global_rect()
	assert_true(safe.grow(0.5).encloses(panel_rect), "the panel stays inside the safe area")
	assert_false(stage.visible, "phone: the panel has the screen alone")
	var close := menu.find_child("Close", true, false) as Button
	assert_not_null(close, "X on the panel")
	close.pressed.emit()
	await wait_process_frames(2)
	assert_null(menu.get_open_panel(), "X closes the panel like Esc")
	assert_true(stage.visible)


func test_desktop_main_menu_is_unchanged() -> void:
	_desktop()
	var menu := MainMenu.new()
	add_child_autofree(menu)
	await wait_process_frames(2)
	var stage := menu.get_list().get_parent() as Control
	assert_eq(stage.scale, Vector2.ONE)
	assert_eq(menu.get_list().position, UiKit.pxv(MainMenu.MENU_POSITION.x, MainMenu.MENU_POSITION.y))
	menu.open_slots()
	await wait_process_frames(2)
	assert_null(menu.find_child("Close", true, false), "no X on the PC")
	assert_true(stage.visible, "the list stays next to the panel")

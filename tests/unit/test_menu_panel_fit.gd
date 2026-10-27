extends GutTest
## Main menu panels and the options stay on screen (report 22.10.2026: "Optionen" stood out of the
## main menu at the top and the bottom, the pause dialog scrolled through a screen of empty space).
## Cause: a wrapping note on an options page was measured ~1 px wide before the first layout and
## asked for a screen of height; the view fixed that as the size of every page.
## The menu runs in SubViewports of the layout sizes the windows give (canvas_items, aspect expand:
## every 16:9 window from 1280×720 to 3840×2160 and borderless fullscreen is 1280×720, wider ones
## get wider, a portrait window taller), plus a short one that forces scrolling. Test save and
## settings folder, never the real ones.

const MobileUi := preload("res://ui/menus/mobile_ui.gd")
const ROOT := "user://test_menu_panel_fit"
## Layout sizes: 16:9 (720p … 4K, borderless), 21:9, 16:10, portrait 1080×2340 on a PC window.
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1707, 720), Vector2i(1280, 800), Vector2i(1280, 2773)]

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
	TranslationServer.set_locale("en")


func after_each() -> void:
	_reset_overrides()
	GameManager.clear_pause_reasons()


func _reset_overrides() -> void:
	MobileUi.zoom_override = 0.0
	MobileUi.touch_override = -1
	MobileUi.phone_override = -1
	MobileUi.safe_inset_override = -1.0


func _wipe() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	for dir_path in [root.path_join("saves"), root]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			DirAccess.remove_absolute(dir_path.path_join(file))


func _viewport(size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.gui_disable_input = false
	add_child_autofree(viewport)
	return viewport


func _menu_in(viewport: SubViewport) -> MainMenu:
	var menu := MainMenu.new()
	viewport.add_child(menu)
	return menu


func _assert_on_screen(panel: Control, viewport: SubViewport, what: String) -> void:
	var screen := Rect2(Vector2.ZERO, Vector2(viewport.size)).grow(0.5)
	var rect := panel.get_global_rect()
	assert_true(screen.encloses(rect), "%s: %s inside %s" % [what, rect, screen])


func _scroll_of(panel: Control) -> ScrollContainer:
	var found := panel.find_children("*", "ScrollContainer", true, false)
	return found[0] as ScrollContainer if not found.is_empty() else null


## A panel taller than any screen (the cap is what keeps it inside).
func _tall_panel(rows: int) -> MenuPanel:
	var panel := MenuPanel.new()
	panel.set_width(200)
	panel.add_header("", "Tall")
	for i in rows:
		var row := UiKit.text_label("Row %d" % i, UiKit.SIZE_BODY, UiKit.COLOR_TEXT)
		row.name = "Row%d" % i
		panel.content.add_child(row)
	panel.set_footer("Esc")
	return panel


# --- Options view: no empty space ---

func test_wrapping_labels_ask_for_their_lines_not_a_screen() -> void:
	for language in [&"en", &"de"]:
		TranslationServer.set_locale(language)
		var view := OptionsView.new()
		add_child_autofree(view)
		# Measured before the first layout on purpose: that is when the view fixes its page size.
		for node in view.find_children("*", "Label", true, false):
			var label := node as Label
			if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
				continue
			var line := label.get_theme_font(&"font").get_height(label.get_theme_font_size(&"font_size"))
			assert_lte(label.get_combined_minimum_size().y, line * 3.0 + 1.0, "%s (%s): a few lines high" % [label.text, language])
		view.queue_free()
		await wait_process_frames(1)


func test_every_tab_is_as_high_as_its_rows() -> void:
	var view := OptionsView.new()
	add_child_autofree(view)
	await wait_process_frames(2)
	var host := view.get_row_control(OptionsView.Row.MUSIC)
	while host != null and not host is MarginContainer:
		host = host.get_parent() as Control
	assert_not_null(host, "pages host")
	var room := UiKit.px(OptionsView.CHOICE_HEIGHT + 4.0)
	for tab in [OptionsView.Tab.GENERAL, OptionsView.Tab.DISPLAY, OptionsView.Tab.CONTROLS]:
		view.show_tab(tab)
		await wait_process_frames(2)
		var page: Control = null
		for child in host.get_children():
			if (child as Control).visible:
				page = child
		var rows := 0.0
		var shown := 0
		for child in page.get_children():
			if (child as Control).visible:
				rows += (child as Control).get_combined_minimum_size().y
				shown += 1
		rows += (page as VBoxContainer).get_theme_constant(&"separation") * maxi(0, shown - 1)
		assert_almost_eq(page.get_combined_minimum_size().y, rows, 1.0, "tab %d: page = its rows" % tab)
		assert_lte(host.get_combined_minimum_size().y - rows, room, "tab %d: at most one row of room under its rows" % tab)


# --- Main menu ---

func test_options_panel_fits_every_screen_size() -> void:
	for size in SIZES:
		var viewport := _viewport(size)
		var menu := _menu_in(viewport)
		await wait_process_frames(2)
		menu.activate(MainMenu.ENTRY_OPTIONS)
		var panel := menu.get_open_panel()
		await wait_process_frames(3)
		_assert_on_screen(panel, viewport, "options %s" % size)
		var scroll := _scroll_of(panel)
		assert_true(scroll == null or scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
				"%s: the options fit without scrolling" % size)
		viewport.queue_free()
		await wait_process_frames(1)


func test_other_panels_fit_every_screen_size() -> void:
	for size in [SIZES[0], SIZES[3]]:
		var viewport := _viewport(size)
		var menu := _menu_in(viewport)
		await wait_process_frames(2)
		for entry in [MainMenu.ENTRY_SLOTS, MainMenu.ENTRY_PROGRESS, MainMenu.ENTRY_PROFILE, MainMenu.ENTRY_ONLINE]:
			menu.activate(entry)
			await wait_process_frames(3)
			var panel := menu.get_open_panel()
			assert_not_null(panel, "%s opens a panel" % entry)
			if panel != null:
				_assert_on_screen(panel, viewport, "%s %s" % [entry, size])
				menu.close_panel()
			await wait_process_frames(1)
		viewport.queue_free()
		await wait_process_frames(1)


func test_too_tall_panel_is_capped_and_starts_at_its_top() -> void:
	var viewport := _viewport(Vector2i(1280, 720))
	var menu := _menu_in(viewport)
	await wait_process_frames(2)
	var panel := _tall_panel(80)
	menu._open_panel(panel)
	await wait_process_frames(3)
	_assert_on_screen(panel, viewport, "tall panel")
	assert_lte(panel.size.y, 720.0 - 2.0 * UiKit.px(MainMenu.CORNER_MARGIN) + 0.5, "at most the screen minus the margins")
	var scroll := _scroll_of(panel)
	assert_not_null(scroll, "the content scrolls")
	assert_eq(scroll.scroll_vertical, 0, "starts with its first row")
	var first := panel.content.get_child(0) as Control
	assert_true(scroll.get_global_rect().grow(0.5).encloses(first.get_global_rect()), "the header is in view")
	# Mouse wheel over a row scrolls the content.
	var row := panel.content.find_child("Row3", true, false) as Control
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.factor = 1.0
	wheel.position = row.get_global_rect().get_center()
	wheel.global_position = wheel.position
	viewport.push_input(wheel)
	var release := wheel.duplicate() as InputEventMouseButton
	release.pressed = false
	viewport.push_input(release)
	await wait_process_frames(2)
	assert_gt(scroll.scroll_vertical, 0, "the wheel scrolls")


func test_options_follow_the_selected_row_when_scrolling() -> void:
	# Shorter than any window gives: forces scrolling (large UI sizes, small browser windows).
	var viewport := _viewport(Vector2i(1280, 360))
	var menu := _menu_in(viewport)
	await wait_process_frames(2)
	menu.activate(MainMenu.ENTRY_OPTIONS)
	var panel := menu.get_open_panel() as OptionsPanel
	await wait_process_frames(3)
	_assert_on_screen(panel, viewport, "options 1280x360")
	var scroll := _scroll_of(panel)
	assert_not_null(scroll, "the options scroll")
	assert_eq(scroll.scroll_vertical, 0, "starts at the top")
	panel.view.select_row(OptionsView.Row.MUSIC)
	for i in 6:
		panel.handle_input(MenuInput.key_event(KEY_DOWN))
		await wait_process_frames(2)
	assert_eq(panel.view.get_row(), OptionsView.Row.RESET)
	await wait_process_frames(2)
	var actions := panel.view.get_row_control(OptionsView.Row.RESET)
	assert_gt(scroll.scroll_vertical, 0, "scrolled down with the selection")
	assert_true(scroll.get_global_rect().grow(0.5).encloses(actions.get_global_rect()), "the buttons are in view")
	panel.handle_input(MenuInput.key_event(KEY_DOWN))
	await wait_process_frames(3)
	assert_eq(panel.view.get_row(), OptionsView.Row.TABS)
	assert_eq(scroll.scroll_vertical, 0, "back at the tabs: back at the top")


func test_phone_options_fit_the_safe_area() -> void:
	MobileUi.touch_override = 1
	MobileUi.phone_override = 1
	MobileUi.zoom_override = 4.0 / 3.0
	MobileUi.safe_inset_override = 0.0
	# Portrait phone 1080×2340 and a landscape one.
	for size in [Vector2i(1080, 2340), Vector2i(2340, 1080)]:
		var viewport := _viewport(size)
		var menu := _menu_in(viewport)
		await wait_process_frames(3)
		menu.activate(MainMenu.ENTRY_OPTIONS)
		var panel := menu.get_open_panel()
		await wait_process_frames(3)
		var rect := panel.get_global_rect()
		var stage := panel.get_parent() as Control
		rect = Rect2(stage.get_global_transform() * panel.position, panel.size * stage.scale)
		assert_true(Rect2(Vector2.ZERO, Vector2(size)).grow(0.5).encloses(rect), "phone %s: %s on screen" % [size, rect])
		viewport.queue_free()
		await wait_process_frames(1)


# --- Pause menu ---

func test_pause_options_have_no_empty_space() -> void:
	var viewport := _viewport(Vector2i(1280, 720))
	var ui := GameUI.new()
	viewport.add_child(ui)
	await wait_process_frames(1)
	ui.open_options()
	await wait_process_frames(3)
	var views := ui.find_children("*", "OptionsView", true, false)
	assert_eq(views.size(), 1)
	var modal: Node = views[0]
	while modal != null and not modal is Modal:
		modal = modal.get_parent()
	assert_not_null(modal)
	var frame := (modal as Modal).frame
	assert_false((modal as Modal).is_scrolling(), "fits 1280x720 without scrolling")
	assert_true(Rect2(0, 0, 1280, 720).grow(0.5).encloses(frame.get_global_rect()), "on screen: %s" % frame.get_global_rect())
	assert_lt(frame.size.y, 720.0, "not a screen high")
	GameManager.clear_pause_reasons()

extends GutTest
## Report #d1a7f411 (23.10.2026, trading post: "Man sollte nicht runter scrollen müssen zum
## Close-Button"): in every building dialog only the body scrolls; title, currencies and
## "Schließen" stay on screen, the dialog itself does not scroll. The gamepad focus scrolls the body
## and reaches "Schließen". On a large screen nothing scrolls. Test save only.

const TEST_PATH := "user://test_village_dialog_scroll.cfg"
const AffordableScript := preload("res://world/village/village_affordable.gd")

var _old_path: String


func before_all() -> void:
	OnlineMenu.login_on_open = false
	_old_path = SaveManager.save_path
	GamepadInput.ensure_actions()


func before_each() -> void:
	SaveManager.save_path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	SaveManager.load_game()
	AffordableScript.clear_visits()
	# Everything open and affordable: the fullest dialogs.
	SaveManager.add_stat(StatsTracker.RUNS, 1)
	for event in [MetaUnlocks.EVENT_FIRST_RUN, MetaUnlocks.EVENT_FIRST_CRYSTAL, MetaUnlocks.EVENT_FIRST_BOSS]:
		MetaUnlocks.record_event(event)
	for building in [VillageBuildings.FORGE, VillageBuildings.TRADER, VillageBuildings.CHRONICLE]:
		SaveManager.mark_seen(VillageBuildings.get_intro_key(building))
	SaveManager.add_permanent_gold(100000)
	SaveManager.add_permanent_crystals(40)
	InputDevice.shared().set_kind(InputDevice.Kind.KEYBOARD_MOUSE)


func after_each() -> void:
	GameManager.clear_pause_reasons()
	InputDevice.shared().set_kind(InputDevice.Kind.KEYBOARD_MOUSE)


func after_all() -> void:
	OnlineMenu.login_on_open = true
	AffordableScript.clear_visits()
	for suffix in ["", ".bak", ".tmp", ".v2.bak", ".v3.bak", ".v4.bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + suffix))
	SaveManager.save_path = _old_path
	SaveManager.load_game()


func _ui_in(size: Vector2i) -> VillageUI:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.gui_disable_input = false
	add_child_autofree(viewport)
	var ui := VillageUI.new()
	viewport.add_child(ui)
	return ui


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _open(ui: VillageUI, building: StringName) -> void:
	match building:
		VillageBuildings.FORGE:
			ui.open_forge()
		VillageBuildings.TRADER:
			ui.open_trader()
		VillageBuildings.CHRONICLE:
			ui.open_chronicle()
	await _frames(4)


func _assert_close_on_screen(ui: VillageUI, size: Vector2i, what: String) -> void:
	var modal := ui.get_building_modal()
	var close := modal.find_child("CloseButton", true, false) as Button
	assert_not_null(close, what)
	var screen := Rect2(Vector2.ZERO, Vector2(size)).grow(0.5)
	assert_true(screen.encloses(close.get_global_rect()), "%s: Schließen on screen at %s" % [what, close.get_global_rect()])
	assert_false(modal.is_scrolling(), "%s: the dialog itself does not scroll" % what)
	assert_false(ui.get_body_scroll().is_ancestor_of(close), "%s: Schließen is outside the scroll area" % what)


func test_close_stays_visible_on_a_low_screen() -> void:
	var size := Vector2i(1280, 480)
	for building: StringName in [VillageBuildings.TRADER, VillageBuildings.FORGE, VillageBuildings.CHRONICLE]:
		var ui := _ui_in(size)
		await _open(ui, building)
		assert_not_null(ui.get_building_modal(), String(building))
		_assert_close_on_screen(ui, size, String(building))
		assert_true(ui.get_building_modal().frame.get_global_rect().size.y <= size.y + 0.5, "%s: panel fits" % building)
		ui.get_building_modal().finish()
		await _frames(1)


func test_the_trader_body_scrolls_on_a_low_screen() -> void:
	var ui := _ui_in(Vector2i(1280, 480))
	await _open(ui, VillageBuildings.TRADER)
	assert_true(ui.is_body_scrolling(), "the cards scroll")
	var bar := ui.get_body_scroll().get_v_scroll_bar()
	assert_gt(bar.max_value - bar.page, 0.0, "something to scroll")
	ui.get_building_modal().finish()


func test_nothing_scrolls_on_a_large_screen() -> void:
	var ui := _ui_in(Vector2i(1920, 1080))
	await _open(ui, VillageBuildings.TRADER)
	assert_false(ui.is_body_scrolling(), "1080 px: everything shows")
	assert_false(ui.get_building_modal().is_scrolling())
	ui.get_building_modal().finish()


func test_gamepad_focus_scrolls_the_body_and_reaches_close() -> void:
	InputDevice.shared().set_kind(InputDevice.Kind.GAMEPAD)
	var size := Vector2i(1280, 480)
	var ui := _ui_in(size)
	await _open(ui, VillageBuildings.TRADER)
	ui.get_building_modal().input_guard = 0.0
	assert_true(ui.get_body_scroll().follow_focus, "the focused entry scrolls into view")
	var close := ui.get_building_modal().find_child("CloseButton", true, false) as Button
	close.grab_focus()
	await _frames(2)
	assert_eq(ui.get_focused_button(), close, "Schließen takes the focus")
	_assert_close_on_screen(ui, size, "gamepad")
	ui.get_building_modal().finish()

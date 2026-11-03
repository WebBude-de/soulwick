extends GutTest
## FS7a follow-up for the talent tree at the candle altar (#d1a7f411 "Schließen soll immer sichtbar
## sein"): like the village buildings the head and the foot with "Schließen" stand fixed, only the body
## (paths and detail) scrolls, and its height comes from Modal.max_panel_height(), so on the PC,
## the square portrait screen, a low window and a zoomed touch screen the panel itself never scrolls.
## Gamepad focus still reaches the nodes below the fold and "Schließen". Fake wallet and storage;
## test save only.

const TEST_PATH := "user://test_talent_tree_layout.cfg"
const MobileUi := preload("res://ui/menus/mobile_ui.gd")
## PC, square portrait game screen (above the pad), low window (D-182, as test_village_menus_layout).
const SCREENS := [Vector2i(1280, 720), Vector2i(1280, 1280), Vector2i(1280, 480)]

var _old_locale: String
var _old_path: String


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	Loc.apply(&"de")
	_old_path = SaveManager.save_path
	SaveManager.save_path = TEST_PATH
	GamepadInput.ensure_actions()


func before_each() -> void:
	MenuInput.reset()
	InputDevice.shared().set_kind(InputDevice.Kind.KEYBOARD_MOUSE)


func after_each() -> void:
	MobileUi.touch_override = -1
	MobileUi.zoom_override = 0.0
	GameManager.clear_pause_reasons()
	InputDevice.shared().set_kind(InputDevice.Kind.KEYBOARD_MOUSE)
	MenuInput.reset()


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + suffix))
	SaveManager.save_path = _old_path


## The fullest view: points free, a spell slot with Lichtblitz (detail column at its tallest).
func _visit(can_edit := true) -> TalentTreeEdit:
	var state := TalentState.new()
	var edit := TalentTreeEdit.create(state, 30, can_edit)
	edit.crystals_source = func() -> int: return 10
	edit.spend_crystals = func(_amount: int) -> bool: return true
	edit.refund_crystals = func(_amount: int) -> void: pass
	edit.store = func(_stored: TalentState) -> Error: return OK
	if can_edit:
		for id: StringName in [&"light_foot", &"light_foot", &"light_foot", &"light_flash"]:
			edit.raise(id)
	return edit


func _dialog_in(size: Vector2i, can_edit := true) -> TalentTreeDialog:
	var viewport := SubViewport.new()
	viewport.size = size
	add_child_autofree(viewport)
	var host := Control.new()
	viewport.add_child(host)
	var dialog := TalentTreeDialog.create(_visit(can_edit))
	dialog.show_on(host)
	dialog.modal.input_guard = 0.0
	dialog.modal.pad_accept_guard = 0.0
	await _frames(4)
	return dialog


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _on_screen(size: Vector2i, control: Control) -> bool:
	return Rect2(Vector2.ZERO, Vector2(size)).grow(0.5).encloses(control.get_global_rect())


func _assert_close_fixed(dialog: TalentTreeDialog, size: Vector2i, what: String) -> void:
	var close := dialog.get_close_button()
	assert_not_null(close, what)
	assert_true(close.is_visible_in_tree(), "%s: Schließen shown" % what)
	assert_true(_on_screen(size, close), "%s: Schließen on screen %s" % [what, close.get_global_rect()])
	assert_false(dialog.get_body_scroll().is_ancestor_of(close), "%s: Schließen outside the scrolling body" % what)
	assert_false(dialog.modal.is_scrolling(), "%s: the panel itself never scrolls" % what)
	var header := dialog.modal.content.get_node_or_null(^"Header") as Control
	assert_not_null(header, "%s: the head sits in the Modal's content" % what)
	assert_false(dialog.get_body_scroll().is_ancestor_of(header), "%s: the head stays" % what)


# --- Head and foot fixed, only the body scrolls ---

func test_close_is_on_screen_and_outside_the_scroll_area() -> void:
	for size: Vector2i in SCREENS:
		for can_edit: bool in [true, false]:
			var dialog := await _dialog_in(size, can_edit)
			var what := "%s %s" % [size, "edit" if can_edit else "read-only"]
			gut.p("talent tree at %s: panel %s, body scrolls %s" % [what, dialog.modal.frame.size, dialog.is_body_scrolling()])
			_assert_close_fixed(dialog, size, what)
			assert_true(Rect2(Vector2.ZERO, Vector2(size)).grow(0.5).encloses(dialog.modal.get_panel_rect()), "%s: the panel fits" % what)
			dialog.close()
			await _frames(1)


func test_body_scrolls_only_when_the_screen_is_too_low() -> void:
	var low := await _dialog_in(Vector2i(1280, 480))
	assert_true(low.is_body_scrolling(), "480 px: the paths scroll")
	var bar := low.get_body_scroll().get_v_scroll_bar()
	assert_gt(bar.max_value - bar.page, 0.5, "there is something to scroll")
	low.close()
	await _frames(1)
	var tall := await _dialog_in(Vector2i(1280, 1280))
	assert_false(tall.is_body_scrolling(), "1280×1280: everything shows")
	tall.close()
	await _frames(1)


func test_touch_screen_with_zoom_keeps_close_outside_the_scroll() -> void:
	# A phone in landscape: bigger menus and the X; the body gives way, never the whole panel.
	MobileUi.touch_override = 1
	MobileUi.zoom_override = 4.0 / 3.0
	InputDevice.shared().set_kind(InputDevice.Kind.TOUCH)
	var size := Vector2i(1280, 720)
	var dialog := await _dialog_in(size)
	_assert_close_fixed(dialog, size, "touch 4/3")
	assert_true(dialog.modal.fits_safe_area(), "panel and X inside the screen")
	assert_true(dialog.modal.has_close_button(), "the X is there")
	assert_not_null(dialog.modal.content.get_node(^"Header").find_child("CloseRoom", false, false),
		"the head keeps its end free for the X")
	dialog.close()
	await _frames(1)


func test_gamepad_reaches_nodes_below_the_fold_and_close() -> void:
	InputDevice.shared().set_kind(InputDevice.Kind.GAMEPAD)
	var size := Vector2i(1280, 480)
	var dialog := await _dialog_in(size)
	assert_true(dialog.is_body_scrolling())
	_assert_close_fixed(dialog, size, "gamepad")
	var lowest := dialog.get_node_button(&"wind_runner")
	dialog.modal.focus_button(lowest)
	await _frames(3)
	assert_eq(dialog.selected_id, &"wind_runner", "the focused node is the chosen one")
	var view := dialog.get_body_scroll().get_global_rect().grow(0.5)
	assert_true(view.encloses(lowest.get_global_rect()), "the body scrolled the capstone into view")
	assert_true(_on_screen(size, dialog.get_close_button()), "Schließen still on screen")
	assert_true(dialog.modal.focus_targets().has(dialog.get_close_button()), "the D-pad can reach Schließen")
	var result: Array = []
	dialog.closed.connect(func(applied: bool) -> void: result.append(applied))
	dialog.modal.focus_button(dialog.get_close_button())
	assert_true(dialog.modal.press_focused(), "A on Schließen")
	await _frames(2)
	assert_eq(result.size(), 1, "closed")

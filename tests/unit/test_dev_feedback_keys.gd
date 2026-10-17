extends GutTest
## Open keys of the bug report tool (17.10.2026, 65 % keyboard without F keys): Ctrl + B (Cmd + B on
## macOS) opens it, also with a focused text field, but not plain B, AltGr + B or a held key; on a
## gamepad Back + Start pressed together open it, while Back or Start alone are only held back for
## the combo window and then replayed to the game in their order (pause and overview still work).
## Replays are captured through DevFeedback.replay, so nothing goes through the real Input.
## Reports go to a test folder, the save game is never touched.

const TEST_ROOT := "user://test_dev_feedback_keys"
const TEST_CONSENT := "user://test_dev_feedback_keys_consent.cfg"

var _old_save_path: String
var _old_root: String
var _old_override: int
var _old_delay: int
var _old_consent: String
var _replayed: Array[InputEvent] = []


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_dev_feedback_keys_save.cfg"
	_old_root = DevFeedback.root_dir
	_old_override = DevFeedback.enabled_override
	_old_delay = DevFeedback.release_delay_frames
	_old_consent = DevFeedback.consent_path
	DevFeedback.root_dir = TEST_ROOT
	DevFeedback.release_delay_frames = 0
	DevFeedback.consent_path = TEST_CONSENT
	# Start = pause_menu and Back = upgrade_overview (added at runtime).
	GamepadInput.ensure_actions()


func after_all() -> void:
	DirAccess.remove_absolute(TEST_CONSENT)
	DevFeedback.consent_path = _old_consent
	DevFeedback.root_dir = _old_root
	DevFeedback.enabled_override = _old_override
	DevFeedback.release_delay_frames = _old_delay
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	DevFeedback.enabled_override = 1
	DevFeedback.store_consent()
	_replayed.clear()


func after_each() -> void:
	GameManager.clear_pause_reasons()


# --- keyboard ------------------------------------------------------------------------------------

func test_ctrl_b_is_the_shortcut() -> void:
	assert_true(DevFeedback.is_shortcut(_ctrl_b()), "Ctrl + B (Cmd + B on macOS)")
	assert_true(DevFeedback.is_trigger(_ctrl_b()))
	assert_false(DevFeedback.is_shortcut(_key(KEY_B)), "plain B does nothing")
	assert_false(DevFeedback.is_trigger(_key(KEY_B)))
	var altgr := _ctrl_b()
	altgr.alt_pressed = true
	assert_false(DevFeedback.is_shortcut(altgr), "AltGr (Ctrl + Alt) + B types, it does not open")
	var echo := _ctrl_b()
	echo.echo = true
	assert_false(DevFeedback.is_trigger(echo), "a held key does not repeat")
	var released := _ctrl_b()
	released.pressed = false
	assert_false(DevFeedback.is_trigger(released))
	var other := _ctrl_b()
	other.keycode = KEY_N
	other.physical_keycode = KEY_N
	assert_false(DevFeedback.is_shortcut(other), "other Ctrl keys do nothing")
	var layout_b := _ctrl_b()
	layout_b.physical_keycode = KEY_X
	assert_true(DevFeedback.is_shortcut(layout_b), "the B as labelled (Dvorak: physical X)")
	var physical_x := _ctrl_b()
	physical_x.keycode = KEY_X
	assert_false(DevFeedback.is_shortcut(physical_x), "Ctrl + X stays cut on layouts with B at that place")
	var no_label := _ctrl_b()
	no_label.keycode = KEY_NONE
	assert_true(DevFeedback.is_shortcut(no_label), "physical B when the layout reports nothing")


func test_ctrl_b_opens_the_overlay() -> void:
	var feedback := _feedback()
	assert_true(feedback.handle_event(_ctrl_b()))
	assert_true(feedback.is_open())
	assert_true(GameManager.has_pause_reason(DevFeedback.PAUSE_REASON))
	assert_false(feedback.handle_event(_ctrl_b()), "Ctrl + B while open does nothing")
	feedback.get_overlay().cancel()
	assert_false(feedback.is_open())


func test_ctrl_b_works_in_a_text_field() -> void:
	var feedback := _feedback()
	var edit := LineEdit.new()
	add_child_autofree(edit)
	edit.grab_focus()
	assert_false(feedback.handle_event(_key(KEY_B)), "B is typed")
	assert_true(feedback.handle_event(_ctrl_b()), "Ctrl + B types nothing, so it opens")
	assert_eq(edit.text, "", "nothing reached the field")
	feedback.get_overlay().cancel()
	edit.release_focus()


func test_shortcut_text() -> void:
	var expected := "Cmd + B" if OS.has_feature("macos") else "Strg + B"
	assert_eq(DevFeedback.shortcut_text("Strg"), expected)


func test_nothing_with_the_switch_off() -> void:
	DevFeedback.enabled_override = 0
	var feedback := _feedback()
	assert_false(feedback.handle_event(_ctrl_b()))
	assert_false(feedback.handle_event(_pad(JOY_BUTTON_START)), "Start reaches the game at once")
	assert_false(feedback.is_pad_held())
	assert_false(feedback.is_open())


# --- gamepad -------------------------------------------------------------------------------------

func test_back_and_start_together_open_the_overlay() -> void:
	var feedback := _feedback()
	assert_true(feedback.handle_pad_event(_pad(JOY_BUTTON_BACK), 1000), "Back is held back")
	assert_true(feedback.is_pad_held())
	assert_false(feedback.is_open())
	assert_true(feedback.handle_pad_event(_pad(JOY_BUTTON_START), 1000 + DevFeedback.PAD_COMBO_MSEC), "Start in time")
	assert_true(feedback.is_open(), "the combo opens the overlay")
	assert_false(feedback.is_pad_held())
	assert_true(_replayed.is_empty(), "neither the overview nor the pause sees anything")
	assert_false(feedback.handle_pad_event(_pad(JOY_BUTTON_START, false), 1300), "releases go to the overlay")
	assert_false(feedback.handle_pad_event(_pad(JOY_BUTTON_BACK, false), 1310))
	feedback.flush_pad(5000)
	assert_true(_replayed.is_empty())
	feedback.get_overlay().cancel()


func test_start_then_back_opens_too() -> void:
	var feedback := _feedback()
	assert_true(feedback.handle_event(_pad(JOY_BUTTON_START)), "handle_event routes pad buttons")
	assert_true(feedback.handle_pad_event(_pad(JOY_BUTTON_BACK), Time.get_ticks_msec()))
	assert_true(feedback.is_open())
	assert_true(_replayed.is_empty())
	feedback.get_overlay().cancel()


func test_start_alone_still_pauses() -> void:
	var feedback := _feedback()
	var start := _pad(JOY_BUTTON_START)
	assert_true(feedback.handle_pad_event(start, 1000))
	feedback.flush_pad(1000 + DevFeedback.PAD_COMBO_MSEC)
	assert_true(_replayed.is_empty(), "still inside the window")
	feedback.flush_pad(1001 + DevFeedback.PAD_COMBO_MSEC)
	assert_eq(_replayed.size(), 1, "after the window Start goes to the game")
	assert_same(_replayed[0], start)
	assert_true(_replayed[0].is_action_pressed(GamepadInput.PAUSE_MENU), "still the pause action")
	assert_false(feedback.is_pad_held())
	assert_false(feedback.handle_pad_event(start as InputEventJoypadButton, 1300), "the replay passes the tool")
	assert_false(feedback.is_open())
	assert_false(feedback.handle_pad_event(_pad(JOY_BUTTON_START, false), 1400), "its release passes too")


func test_back_tapped_alone_is_replayed_with_its_release() -> void:
	var feedback := _feedback()
	assert_true(feedback.handle_pad_event(_pad(JOY_BUTTON_BACK), 1000))
	assert_true(feedback.handle_pad_event(_pad(JOY_BUTTON_BACK, false), 1080), "release held back too")
	assert_eq(_replayed.size(), 2, "press and release at once, in order")
	assert_true(_replayed[0].is_action_pressed(GamepadInput.UPGRADE_OVERVIEW), "first the press (overview)")
	assert_true(_replayed[1].is_released())
	assert_false(feedback.is_pad_held())
	assert_false(feedback.is_open())


func test_partner_too_late_is_no_combo() -> void:
	var feedback := _feedback()
	assert_true(feedback.handle_pad_event(_pad(JOY_BUTTON_START), 1000))
	assert_true(feedback.handle_pad_event(_pad(JOY_BUTTON_BACK), 1001 + DevFeedback.PAD_COMBO_MSEC))
	assert_false(feedback.is_open(), "too late")
	assert_eq(_replayed.size(), 2, "both reach the game")
	assert_eq((_replayed[0] as InputEventJoypadButton).button_index, JOY_BUTTON_START)
	assert_eq((_replayed[1] as InputEventJoypadButton).button_index, JOY_BUTTON_BACK)


func test_other_buttons_keep_their_order() -> void:
	var feedback := _feedback()
	assert_false(feedback.handle_pad_event(_pad(JOY_BUTTON_A), 1000), "other buttons pass at once")
	assert_true(feedback.handle_pad_event(_pad(JOY_BUTTON_BACK), 1000))
	assert_true(feedback.handle_pad_event(_pad(JOY_BUTTON_A), 1050), "A while Back waits")
	assert_eq(_replayed.size(), 2)
	assert_eq((_replayed[0] as InputEventJoypadButton).button_index, JOY_BUTTON_BACK, "Back first")
	assert_eq((_replayed[1] as InputEventJoypadButton).button_index, JOY_BUTTON_A)
	assert_false(feedback.is_open())


func test_two_pads_are_no_combo() -> void:
	var feedback := _feedback()
	assert_true(feedback.handle_pad_event(_pad(JOY_BUTTON_START, true, 0), 1000))
	assert_true(feedback.handle_pad_event(_pad(JOY_BUTTON_BACK, true, 1), 1050))
	assert_false(feedback.is_open(), "Start on one pad and Back on another")
	assert_eq(_replayed.size(), 2)


func test_the_same_button_twice_is_no_combo() -> void:
	var feedback := _feedback()
	assert_true(feedback.handle_pad_event(_pad(JOY_BUTTON_START), 1000))
	assert_true(feedback.handle_pad_event(_pad(JOY_BUTTON_START), 1050))
	assert_false(feedback.is_open())
	assert_eq(_replayed.size(), 2)


func test_combo_opens_in_pad_mode() -> void:
	var feedback := _feedback()
	feedback._track_touch(_pad(JOY_BUTTON_BACK))
	assert_true(feedback.handle_pad_event(_pad(JOY_BUTTON_BACK), 1000))
	assert_true(feedback.handle_pad_event(_pad(JOY_BUTTON_START), 1010))
	assert_true(feedback.get_overlay().pad_mode, "the overlay names the pad buttons")
	feedback.get_overlay().cancel()


# --- helpers -------------------------------------------------------------------------------------

func _feedback() -> DevFeedback:
	var feedback := DevFeedback.new()
	feedback.replay = func(event: InputEvent) -> void: _replayed.append(event)
	add_child_autofree(feedback)
	return feedback


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	return event


## Ctrl + B, on macOS Cmd + B (is_command_or_control_pressed reads the platform's key).
func _ctrl_b() -> InputEventKey:
	var event := _key(KEY_B)
	event.ctrl_pressed = true
	event.meta_pressed = OS.has_feature("macos")
	return event


func _pad(button: JoyButton, pressed := true, device := 0) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	event.device = device
	return event

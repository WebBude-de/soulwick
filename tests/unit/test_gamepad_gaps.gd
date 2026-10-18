extends GutTest
## Gamepad gaps closed in D-192: every game action has a pad button with a symbol, Xbox pads show
## the letters A/B/X/Y (others the neutral positions), the controls page names the D-pad for a choice
## and the stick for aiming, dialogs scroll with the D-pad (no buttons) or the right stick and keep
## the framed button in view, text fields take letters from the on-screen keyboard (PadKeyboard:
## world name, rename, profile name, bug report). Events are simulated InputEventJoypadButton /
## InputEventJoypadMotion pushed into the viewport.
## Runs in a test folder (SaveManager.set_storage_root), never on the real save or settings.

const ROOT := "user://test_gamepad_gaps"
const PadKeyboard := preload("res://ui/widgets/pad_keyboard.gd")
const PadNav := preload("res://ui/widgets/pad_nav.gd")

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String
var _old_locale: String


func before_all() -> void:
	MainMenu.online_check = false
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	_old_locale = TranslationServer.get_locale()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()
	GamepadInput.ensure_actions()
	TranslationServer.set_locale("de")


func before_each() -> void:
	MenuInput.reset()
	InputDevice.xbox_letters_override = -1
	InputDevice.shared().set_kind(InputDevice.Kind.GAMEPAD)


func after_each() -> void:
	var open := PadKeyboard.get_open()
	if open != null:
		open.finish(null)
	MenuInput.reset()
	InputDevice.xbox_letters_override = -1
	InputDevice.shared().set_kind(InputDevice.Kind.KEYBOARD_MOUSE)
	GameManager.clear_pause_reasons()
	_aim_stick(0.0)


func after_all() -> void:
	MainMenu.online_check = true
	await wait_seconds(0.1)
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()
	PlayerProfile.reset()
	TranslationServer.set_locale(_old_locale)


# --- Helpers ---

func _press(button: JoyButton) -> void:
	get_viewport().push_input(MenuInput.pad_button_event(button))
	get_viewport().push_input(MenuInput.pad_button_event(button, false))


func _aim_stick(value: float) -> void:
	Input.parse_input_event(MenuInput.pad_axis_event(JOY_AXIS_RIGHT_Y, value))
	Input.flush_buffered_events()


func _skip_touch() -> bool:
	if InputGlyphs.is_touch():
		pass_test("touch forced on this machine: touch symbols win")
		return true
	return false


## The open keyboard after its short input guard.
func _keyboard() -> Modal:
	var keyboard := PadKeyboard.get_open()
	if keyboard != null:
		keyboard.input_guard = 0.0
	return keyboard


# --- Inventory: every action has a pad button with a symbol ---

func test_every_game_and_menu_action_has_a_pad_button_with_a_symbol() -> void:
	if _skip_touch():
		return
	var actions: Array[StringName] = []
	actions.assign(PlayerInput.ACTIONS)
	actions.append_array([&"pause_menu", &"upgrade_overview", &"move_up", &"move_down", &"move_left",
			&"move_right", &"ui_accept", &"ui_cancel"])
	actions.append_array(GamepadInput.AIM_ACTIONS)
	for action in actions:
		assert_true(InputMap.has_action(action), "%s exists" % action)
		assert_ne(InputGlyphs.pad_id_for_action(action), &"", "%s has a pad button with a symbol" % action)
	# Side view (D-144): jump is the dash button, the side dash its own one.
	assert_eq(InputGlyphs.pad_id_for_action(PlayerSideMotion.JUMP_ACTION), InputGlyphs.PAD_SOUTH, "jump = A")
	assert_eq(InputGlyphs.pad_id_for_action(PlayerSideMotion.DASH_ACTION), InputGlyphs.PAD_EAST, "side dash = B")


func test_pad_buttons_drive_side_view_and_interaction_actions() -> void:
	var input := LocalKeyboardMouseInput.new()
	for pair: Array in [[JOY_BUTTON_A, PlayerInput.DASH], [JOY_BUTTON_B, PlayerInput.SIDE_DASH], [JOY_BUTTON_X, PlayerInput.INTERACT]]:
		Input.parse_input_event(MenuInput.pad_button_event(pair[0]))
		Input.flush_buffered_events()
		input.poll(null)
		assert_true(input.is_just_pressed(pair[1]), "%s presses %s" % [pair[0], pair[1]])
		Input.parse_input_event(MenuInput.pad_button_event(pair[0], false))
		Input.flush_buffered_events()
		input.poll(null)
		assert_false(input.is_pressed(pair[1]))


# --- Xbox letters (D-192) ---

func test_xbox_pads_show_letters_and_other_pads_positions() -> void:
	if _skip_touch():
		return
	assert_true(InputDevice.is_xbox_name("Xbox Series Controller"))
	assert_true(InputDevice.is_xbox_name("XInput Gamepad (GLFW)"))
	assert_true(InputDevice.is_xbox_name("Steam Deck Controller"))
	assert_false(InputDevice.is_xbox_name("PS5 Controller"))
	assert_false(InputDevice.is_xbox_name("Nintendo Switch Pro Controller"))
	assert_false(InputDevice.is_xbox_name("Steam Virtual Gamepad"), "may stand for a PlayStation pad")
	assert_false(InputDevice.has_xbox_letters(), "no pad known: neutral positions")
	assert_eq(InputGlyphs.id_for_action(&"dash"), InputGlyphs.PAD_SOUTH)
	InputDevice.xbox_letters_override = 1
	assert_eq(InputGlyphs.id_for_action(&"dash"), InputGlyphs.PAD_A)
	assert_eq(InputGlyphs.id_for_action(&"side_dash"), InputGlyphs.PAD_B)
	assert_eq(InputGlyphs.id_for_action(&"interact"), InputGlyphs.PAD_X)
	assert_eq(InputGlyphs.id_for_action(&"switch_weapon"), InputGlyphs.PAD_Y)
	assert_eq(PadNav.token_glyph("a"), InputGlyphs.PAD_A, "menu texts follow")
	assert_eq(InputGlyphs.id_for_name("Esc"), InputGlyphs.PAD_B)
	assert_eq(InputGlyphs.id_for_action(&"attack"), InputGlyphs.PAD_RT, "triggers stay")
	assert_not_null(InputGlyphs.texture(InputGlyphs.PAD_A), "the letter has a picture")
	InputDevice.xbox_letters_override = 0
	assert_eq(InputGlyphs.id_for_action(&"dash"), InputGlyphs.PAD_SOUTH)


# --- Controls page ---

func test_controls_page_names_dpad_and_stick_on_a_pad() -> void:
	if _skip_touch():
		return
	var row: HBoxContainer = autofree(KeyCap.row_for_control(ControlsInfo.CHOICE))
	var ids: Array[StringName] = []
	for cap: KeyCap in row.get_children():
		ids.append(cap.glyph_id)
	assert_eq(ids, [InputGlyphs.PAD_DPAD, InputGlyphs.PAD_SOUTH] as Array[StringName], "D-pad and A instead of 1 – 3")
	assert_eq(ControlsInfo.note(ControlsInfo.CHOICE), tr(&"CONTROLS_CHOICE_NOTE_PAD"))
	assert_eq(ControlsInfo.note(ControlsInfo.AIM), tr(&"CONTROLS_AIM_NOTE_PAD"))
	assert_false(ControlsInfo.note(ControlsInfo.AIM).contains("Maus"), "no mouse on a pad")
	InputDevice.shared().set_kind(InputDevice.Kind.KEYBOARD_MOUSE)
	var keys: HBoxContainer = autofree(KeyCap.row_for_control(ControlsInfo.CHOICE))
	assert_eq((keys.get_child(0) as KeyCap).get_text(), "1 – 3", "keyboard unchanged")
	assert_eq(ControlsInfo.note(ControlsInfo.AIM), tr(&"CONTROLS_AIM_NOTE"))


func test_boss_intro_hints_have_pad_texts() -> void:
	for key: StringName in [BossIntroView.SHORT_HINT_PAD, BossIntroView.STORY_HINT_PAD]:
		var text := tr(key)
		assert_ne(text, String(key), "%s is translated" % key)
		assert_true(text.contains("{x}") and text.contains("{a}"), "names the pad buttons")
		assert_false(PadNav.split(text).filter(func(part: Variant) -> bool: return part is Texture2D).is_empty(), "with pictures")


# --- Scrolling dialogs ---

## A dialog with a scroll area of rows (buttons when with_buttons) taller than the area.
func _scroll_modal(with_buttons: bool) -> Modal:
	var modal := Modal.create(&"test_pad_scroll")
	modal.pauses = false
	modal.input_guard = 0.0
	modal.pad_accept_guard = 0.0
	var scroll := ScrollContainer.new()
	scroll.name = "List"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(200, 80)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for i in 20:
		if with_buttons:
			var button := Button.new()
			button.text = "Eintrag %d" % i
			button.custom_minimum_size.y = 30
			button.set_meta(Modal.META_PAD_OPTION, true)
			list.add_child(button)
		else:
			var label := Label.new()
			label.text = "Zeile %d" % i
			label.custom_minimum_size.y = 30
			list.add_child(label)
	modal.content.add_child(scroll)
	modal.show_on(self)
	return modal


func test_dpad_scrolls_a_dialog_without_buttons() -> void:
	var modal := _scroll_modal(false)
	await wait_process_frames(3)
	var scroll := modal.find_child("List", true, false) as ScrollContainer
	assert_eq(modal.scroll_target(), scroll)
	assert_eq(scroll.scroll_vertical, 0)
	_press(JOY_BUTTON_DPAD_DOWN)
	await wait_process_frames(1)
	assert_gt(scroll.scroll_vertical, 0, "D-pad down scrolls")
	var after_one := scroll.scroll_vertical
	_press(JOY_BUTTON_DPAD_UP)
	await wait_process_frames(1)
	assert_lt(scroll.scroll_vertical, after_one, "D-pad up scrolls back")
	modal.finish(null)


func test_right_stick_scrolls_a_dialog() -> void:
	var modal := _scroll_modal(false)
	await wait_process_frames(3)
	var scroll := modal.find_child("List", true, false) as ScrollContainer
	_aim_stick(1.0)
	modal._process(0.25)
	_aim_stick(0.0)
	await wait_process_frames(1)
	assert_gt(scroll.scroll_vertical, 0, "right stick down scrolls")
	var bottom := scroll.scroll_vertical
	_aim_stick(-1.0)
	modal._process(0.1)
	_aim_stick(0.0)
	await wait_process_frames(1)
	assert_lt(scroll.scroll_vertical, bottom, "and up again")
	modal.finish(null)


func test_framed_button_is_scrolled_into_view() -> void:
	var modal := _scroll_modal(true)
	await wait_process_frames(3)
	var scroll := modal.find_child("List", true, false) as ScrollContainer
	assert_not_null(modal.get_focused_button(), "the pad frame starts on the first entry")
	for i in 8:
		_press(JOY_BUTTON_DPAD_DOWN)
		await wait_process_frames(1)
	var focused := modal.get_focused_button()
	assert_eq(focused.text, "Eintrag 8")
	assert_gt(scroll.scroll_vertical, 0, "the list follows the frame")
	var visible := scroll.get_global_rect()
	assert_true(visible.grow(1.0).encloses(focused.get_global_rect()), "the framed entry is on screen")
	modal.finish(null)


func test_tab_overview_scrolls_with_the_dpad() -> void:
	var upgrades: UpgradeManager = autofree(UpgradeManager.new())
	for path in DirAccess.get_files_at("res://upgrades/data/"):
		if path.ends_with(".tres"):
			upgrades.upgrade_pool.append(load("res://upgrades/data/" + path))
	for upgrade in upgrades.upgrade_pool:
		upgrades.acquire_upgrade(upgrade)
	var context := DungeonContext.new()
	context.upgrade_manager = upgrades
	var ui: DungeonUI = add_child_autofree(DungeonUI.new())
	ui.auto_enemy_hints = false
	ui.show_controls_hint = false
	ui.context = context
	ui.show_upgrade_overview()
	await wait_process_frames(3)
	var modals := ui.find_children("*", "Modal", true, false)
	assert_false(modals.is_empty(), "overview open")
	if modals.is_empty():
		return
	var modal := modals[modals.size() - 1] as Modal
	modal.input_guard = 0.0
	var scroll := modal.scroll_target()
	assert_not_null(scroll, "%d upgrades: the list scrolls" % upgrades.get_active_upgrades().size())
	if scroll == null:
		modal.finish(null)
		return
	_press(JOY_BUTTON_DPAD_DOWN)
	await wait_process_frames(1)
	assert_gt(scroll.scroll_vertical, 0, "D-pad down scrolls the upgrade list")
	modal.finish(null)
	await wait_process_frames(1)


# --- On-screen keyboard ---

func test_keyboard_types_a_world_name() -> void:
	var panel: CreateSlotPanel = add_child_autofree(CreateSlotPanel.create(2))
	await wait_process_frames(2)
	var edit := panel.find_child("WorldName", true, false) as LineEdit
	assert_true(edit.has_focus(), "the name field has the keys")
	_press(JOY_BUTTON_Y)
	var keyboard := _keyboard()
	assert_not_null(keyboard, "Y opens the keyboard")
	if keyboard == null:
		return
	assert_false(edit.has_focus(), "the field gives the keys to the keyboard")
	for character in ["\u00fc", "\u00f6", "\u00e4", "\u00df"]:
		assert_not_null(keyboard.call(&"get_key", character), "German layout has %s" % character)
	assert_false(GameManager.has_pause_reason(keyboard.pause_reason), "the keyboard pauses nothing")
	assert_not_null(keyboard.get_focused_button(), "the frame sits on a key")
	# Frame on "1" (first key): down to "q", right to "w", A types it (a capital: empty field).
	await wait_process_frames(2)
	assert_eq(keyboard.get_focused_button().text, "1")
	_press(JOY_BUTTON_DPAD_DOWN)
	assert_eq(keyboard.get_focused_button().text, "Q", "capitals shown while the next letter is one")
	_press(JOY_BUTTON_DPAD_RIGHT)
	_press(JOY_BUTTON_A)
	assert_eq(edit.text, "W", "first letter is a capital")
	_press(JOY_BUTTON_A)
	assert_eq(edit.text, "Ww", "then small letters")
	_press(JOY_BUTTON_X)
	assert_eq(edit.text, "W", "X deletes")
	_press(JOY_BUTTON_Y)
	assert_eq(edit.text, "W ", "Y types a space")
	keyboard.call(&"type_text", "e")
	assert_eq(edit.text, "W E", "after a space a capital again")
	_press(JOY_BUTTON_START)
	await wait_process_frames(1)
	assert_null(PadKeyboard.get_open(), "Start closes it")
	assert_true(edit.has_focus(), "the field has the keys again")
	assert_eq(panel.get_world_name(), "W E")


func test_keyboard_respects_the_length_limit_and_b_keeps_the_text() -> void:
	var panel: CreateSlotPanel = add_child_autofree(CreateSlotPanel.create(3))
	await wait_process_frames(2)
	var edit := panel.find_child("WorldName", true, false) as LineEdit
	var keyboard := panel.open_keyboard()
	assert_not_null(keyboard)
	keyboard.input_guard = 0.0
	for i in edit.max_length + 4:
		keyboard.call(&"type_text", "a")
	assert_eq(edit.text.length(), edit.max_length, "no more than the field takes")
	_press(JOY_BUTTON_B)
	await wait_process_frames(1)
	assert_null(PadKeyboard.get_open(), "B closes")
	assert_eq(edit.text.length(), edit.max_length, "the text stays")
	assert_true(is_instance_valid(panel) and panel.is_inside_tree(), "B closed only the keyboard, not the panel")


func test_keyboard_swallows_pad_buttons_of_the_menu_below() -> void:
	var panel: CreateSlotPanel = add_child_autofree(CreateSlotPanel.create(4))
	await wait_process_frames(2)
	watch_signals(panel)
	panel.open_keyboard()
	var keyboard := _keyboard()
	_press(JOY_BUTTON_A)
	assert_signal_not_emitted(panel, "confirmed", "A types, it does not start the world")
	assert_eq((panel.find_child("WorldName", true, false) as LineEdit).text, "1", "the framed key was typed")
	keyboard.finish(null)


func test_keyboard_for_the_profile_name_from_any_row() -> void:
	var editor := ProfileEditor.create("Kerze", PlayerLook.default_look())
	add_child_autofree(editor)
	await wait_process_frames(2)
	editor.row = ProfileEditor.Row.SKIN
	var event := MenuInput.pad_button_event(JOY_BUTTON_Y)
	assert_true(editor.handle_input(event), "Y is used")
	assert_eq(editor.row, ProfileEditor.Row.NAME, "goes to the name row")
	var keyboard := _keyboard()
	assert_not_null(keyboard)
	if keyboard == null:
		return
	var edit := keyboard.get(&"field") as LineEdit
	assert_eq(edit.text, "Kerze")
	keyboard.call(&"type_text", "n")
	assert_eq(edit.text, "Kerzen", "typed at the end of the name")
	keyboard.finish(null)


func test_keyboard_writes_the_bug_report_note() -> void:
	var overlay := DevFeedbackOverlay.new()
	var size := Vector2i(get_tree().root.get_visible_rect().size)
	var image := Image.create_empty(maxi(size.x, 64), maxi(size.y, 36), false, Image.FORMAT_RGBA8)
	overlay.setup(image, get_tree().root.get_visible_rect().size)
	add_child_autofree(overlay)
	await wait_process_frames(2)
	assert_true(overlay.handle_pad_button(MenuInput.pad_button_event(JOY_BUTTON_Y)), "Y is a pad key of the overlay")
	var keyboard := _keyboard()
	assert_not_null(keyboard, "the keyboard opens over the overlay")
	if keyboard == null:
		return
	assert_true(keyboard.get(&"field") is TextEdit, "for the note")
	keyboard.call(&"type_text", "k")
	_press(JOY_BUTTON_START)
	await wait_process_frames(1)
	assert_null(PadKeyboard.get_open(), "Start closes the keyboard first")
	assert_eq(overlay.build_note()["text"], "K", "typed into the note")
	assert_true(is_instance_valid(overlay) and overlay.is_inside_tree(), "the report is still open, not sent")


func test_keyboard_goes_with_its_menu_and_opens_only_once() -> void:
	var panel: CreateSlotPanel = add_child_autofree(CreateSlotPanel.create(5))
	await wait_process_frames(2)
	var keyboard := panel.open_keyboard()
	assert_not_null(keyboard)
	assert_eq(panel.open_keyboard(), keyboard, "a second Y keeps the open keyboard")
	panel.queue_free()
	await wait_process_frames(2)
	assert_null(PadKeyboard.get_open(), "the panel closed: the keyboard is gone too")

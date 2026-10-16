extends GutTest
## Menus with the gamepad (P0-2 step 2, Steam Deck) and the run end forge line (P1-3): the stick
## is debounced and repeats like a held key (MenuInput), dialogs move a focus frame over their
## buttons with the D-pad and press it with A (Modal), card rows and the shop take D-pad + A, the
## pause menu opens and closes with Start and resumes with B, key caps and key lines show the
## gamepad's buttons, the main menu and its panels work with D-pad + A + B. The run end names what
## the village gold buys and counts the first run as a record. Events are simulated
## InputEventJoypadButton/Motion pushed into the viewport.
## Runs in a test folder (SaveManager.set_storage_root), never on the real save or settings.

const ROOT := "user://test_pad_menus"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const KeyLine := preload("res://ui/widgets/key_line.gd")
const PadNav := preload("res://ui/widgets/pad_nav.gd")

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String
var _old_locale: String
var _upgrades: UpgradeManager


func before_all() -> void:
	MainMenu.online_check = false
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	_old_locale = TranslationServer.get_locale()
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()
	GamepadInput.ensure_actions()


func before_each() -> void:
	MenuInput.reset()
	InputDevice.shared().set_kind(InputDevice.Kind.KEYBOARD_MOUSE)
	RunManager.end_run(RunManager.EndReason.ABORT)
	_upgrades = autofree(UpgradeManager.new())
	for path in DirAccess.get_files_at("res://upgrades/data/"):
		if path.ends_with(".tres"):
			_upgrades.upgrade_pool.append(load("res://upgrades/data/" + path))


func after_each() -> void:
	MenuInput.reset()
	InputDevice.shared().set_kind(InputDevice.Kind.KEYBOARD_MOUSE)
	GameManager.clear_pause_reasons()


func after_all() -> void:
	MainMenu.online_check = true
	RunManager.end_run(RunManager.EndReason.ABORT)
	await wait_seconds(0.2)
	_wipe()
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()
	PlayerProfile.reset()
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


# --- Helpers ---

func _gamepad() -> void:
	InputDevice.shared().set_kind(InputDevice.Kind.GAMEPAD)


func _push(event: InputEvent) -> void:
	get_viewport().push_input(event)


## D-pad press and release (one step).
func _dpad(button: JoyButton) -> void:
	_push(MenuInput.pad_button_event(button))
	_push(MenuInput.pad_button_event(button, false))


func _button(button: JoyButton) -> void:
	_push(MenuInput.pad_button_event(button))
	_push(MenuInput.pad_button_event(button, false))


func _unguard(modal: Modal) -> void:
	modal.input_guard = 0.0
	modal.pad_accept_guard = 0.0


func _modal(root: Node) -> Modal:
	var found := root.find_children("*", "Modal", true, false)
	return found[found.size() - 1] as Modal if not found.is_empty() else null


func _upgrade(id: StringName) -> UpgradeData:
	for upgrade in _upgrades.upgrade_pool:
		if upgrade.id == id:
			return upgrade
	return null


func _dungeon_ui() -> DungeonUI:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 7
	context.upgrade_manager = _upgrades
	var economy: EconomySystem = autofree(EconomySystem.new())
	economy.config = EconomyConfig.new()
	context.economy = economy
	context.player = player
	var ui: DungeonUI = add_child_autofree(DungeonUI.new())
	ui.auto_enemy_hints = false
	ui.show_controls_hint = false
	ui.context = context
	context.ui = ui
	return ui


func _set_village_gold(amount: int) -> void:
	SaveManager.add_permanent_gold(amount - SaveManager.get_permanent_gold())


# --- MenuInput: stick and D-pad ---

func test_stick_steps_once_per_push_and_ignores_drift() -> void:
	var steps: Array[Vector2i] = []
	for value in [0.15, 0.25, 0.55, 0.7, 0.9, 1.0, 0.95, 1.0]:
		steps.append(MenuInput.direction(MenuInput.pad_axis_event(JOY_AXIS_LEFT_Y, value)))
	assert_eq(steps.count(Vector2i.DOWN), 1, "one push is one step: %s" % [steps])
	assert_eq(steps[2], Vector2i.DOWN, "the step comes when the stick passes STICK_PRESS")
	assert_eq(MenuInput.direction(MenuInput.pad_axis_event(JOY_AXIS_LEFT_Y, 0.4)), Vector2i.ZERO, "above release: still held")
	assert_eq(MenuInput.get_held(), Vector2i.DOWN)
	assert_eq(MenuInput.direction(MenuInput.pad_axis_event(JOY_AXIS_LEFT_Y, 0.1)), Vector2i.ZERO)
	assert_eq(MenuInput.get_held(), Vector2i.ZERO, "let go under STICK_RELEASE")
	assert_eq(MenuInput.direction(MenuInput.pad_axis_event(JOY_AXIS_LEFT_Y, -0.8)), Vector2i.UP, "the next push steps again")
	assert_true(MenuInput.is_up(MenuInput.pad_axis_event(JOY_AXIS_LEFT_Y, -0.3)) == false)


func test_one_event_is_decided_once() -> void:
	var event := MenuInput.pad_axis_event(JOY_AXIS_LEFT_X, 0.9)
	assert_true(MenuInput.is_right(event))
	assert_false(MenuInput.is_up(event))
	assert_true(MenuInput.is_right(event), "asking again gives the same answer, no second step")
	var drift := MenuInput.pad_axis_event(JOY_AXIS_LEFT_Y, 0.2)
	assert_false(MenuInput.is_down(drift), "drift on the other axis is no step (move_down has a 0.2 dead zone)")


func test_held_stick_and_dpad_repeat_like_a_key() -> void:
	assert_eq(MenuInput.direction(MenuInput.pad_axis_event(JOY_AXIS_LEFT_X, 1.0)), Vector2i.RIGHT)
	assert_eq(MenuInput.direction(MenuInput.pad_axis_event(JOY_AXIS_LEFT_X, 0.98)), Vector2i.ZERO, "jitter before the delay")
	MenuInput.clock_offset_ms = int(MenuInput.REPEAT_DELAY * 1000.0) + 10
	assert_eq(MenuInput.direction(MenuInput.pad_axis_event(JOY_AXIS_LEFT_X, 1.0)), Vector2i.RIGHT, "repeat after REPEAT_DELAY")
	assert_eq(MenuInput.direction(MenuInput.pad_axis_event(JOY_AXIS_LEFT_X, 0.99)), Vector2i.ZERO, "then every REPEAT_INTERVAL")
	MenuInput.reset()
	assert_eq(MenuInput.direction(MenuInput.pad_button_event(JOY_BUTTON_DPAD_DOWN)), Vector2i.DOWN)
	assert_eq(MenuInput.get_held(), Vector2i.DOWN)
	var repeat := MenuInput.action_event(MenuInput.get_held())
	assert_true(MenuInput.is_down(repeat), "repeats arrive as ui_down like an arrow key")
	assert_eq(MenuInput.direction(MenuInput.pad_button_event(JOY_BUTTON_DPAD_DOWN, false)), Vector2i.ZERO)
	assert_eq(MenuInput.get_held(), Vector2i.ZERO, "released D-pad stops repeating")
	assert_null(MenuInput.poll_repeat())


func test_a_and_b_are_accept_and_back() -> void:
	var a := MenuInput.pad_button_event(JOY_BUTTON_A)
	var b := MenuInput.pad_button_event(JOY_BUTTON_B)
	assert_true(MenuInput.is_accept(a))
	assert_true(MenuInput.is_pad_accept(a))
	assert_true(MenuInput.is_confirm(a), "A confirms where Space must not")
	assert_true(MenuInput.is_back(b))
	assert_true(MenuInput.is_pad_back(b))
	assert_false(MenuInput.is_confirm(MenuInput.key_event(KEY_SPACE)))
	assert_true(MenuInput.is_confirm(MenuInput.key_event(KEY_ENTER)))


# --- Key caps and key lines ---

func test_key_caps_show_gamepad_buttons_and_hide_number_keys() -> void:
	var enter := UiChip.key("Enter")
	var number := UiChip.key("1–3")
	var arrows := UiChip.key("←→")
	add_child_autofree(enter)
	add_child_autofree(number)
	add_child_autofree(arrows)
	assert_eq(enter.get_pad_glyph(), &"", "keyboard: the key name")
	assert_true(number.visible)
	_gamepad()
	assert_eq(enter.get_pad_glyph(), InputGlyphs.pad_id_for_action(&"ui_accept"), "Enter becomes A")
	assert_ne(enter.get_pad_glyph(), &"")
	assert_eq(arrows.get_pad_glyph(), InputGlyphs.PAD_DPAD, "arrows become the D-pad")
	assert_false(number.visible, "number keys have no gamepad button")
	InputDevice.shared().set_kind(InputDevice.Kind.KEYBOARD_MOUSE)
	assert_eq(enter.get_pad_glyph(), &"", "back to the key name with the keyboard")
	assert_true(number.visible)


func test_key_bar_entries_for_the_gamepad() -> void:
	var arrows := DungeonTexts.t(&"MENU_KEY_ARROWS")
	var enter := DungeonTexts.t(&"MENU_KEY_ENTER")
	var esc := DungeonTexts.t(&"MENU_KEY_ESC")
	var upgrade := Modal.pad_key_entries([["1–3", "wählen"], [arrows, "auswählen"], [enter, "bestätigen"]])
	assert_eq(upgrade.size(), 2, "numbers and arrows become one D-pad entry: %s" % [upgrade])
	assert_eq(String(upgrade[0][0]), arrows)
	assert_eq(String(upgrade[1][0]), enter)
	var shop := Modal.pad_key_entries([["1–6", "kaufen"]])
	assert_eq(shop.size(), 2)
	assert_eq(String(shop[1][0]), enter, "a dialog without Enter gets A with the number caption")
	assert_eq(String(shop[1][1]), "kaufen")
	var campfire := Modal.pad_key_entries([["1–3", "wählen"], [enter, "heilen"], [esc, "später"]])
	assert_eq(campfire.size(), 3)
	assert_eq(String(campfire[2][0]), esc)


func test_prompt_key_name_follows_the_device() -> void:
	var keyboard := PadNav.key_name(&"interact")
	assert_false(keyboard.is_empty(), "the bound key (E)")
	_gamepad()
	assert_eq(PadNav.key_name(&"interact"), "X", "the gamepad's X for the interaction prompt")
	assert_eq(PadNav.key_name(&"attack"), "RT")


func test_key_line_switches_to_the_gamepad_text() -> void:
	var line := KeyLine.new()
	line.setup(UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
	line.set_texts("Enter los · Esc zurück", "{a} los · {b} zurück")
	add_child_autofree(line)
	assert_false(line.is_showing_pad())
	_gamepad()
	assert_true(line.is_showing_pad(), "gamepad text with pictures")
	var parts := PadNav.split("{a} los · {b} zurück")
	assert_true(parts[0] is Texture2D, "{a} is a picture")
	assert_eq(String(parts[1]), " los · ")
	InputDevice.shared().set_kind(InputDevice.Kind.KEYBOARD_MOUSE)
	assert_false(line.is_showing_pad())


# --- Dungeon dialogs ---

func test_confirm_dialog_moves_the_frame_and_presses_with_a() -> void:
	_gamepad()
	var ui := _dungeon_ui()
	var result: Array = []
	var ask := func() -> void: result.append(await ui.confirm("Portal", "Dungeon verlassen?"))
	ask.call()
	await wait_physics_frames(2)
	var modal := _modal(ui)
	_unguard(modal)
	var focused := modal.get_focused_button()
	assert_not_null(focused, "a gamepad starts on the default button")
	assert_true(focused.has_meta(Modal.META_PAD_DEFAULT))
	_dpad(JOY_BUTTON_DPAD_RIGHT)
	assert_ne(modal.get_focused_button(), focused, "D-pad right moves to the other button")
	_button(JOY_BUTTON_A)
	await wait_physics_frames(1)
	assert_eq(result, [false], "A presses the framed button (Nein)")


func test_b_cancels_and_a_is_ignored_right_after_opening() -> void:
	_gamepad()
	var ui := _dungeon_ui()
	var result: Array = []
	var ask := func() -> void: result.append(await ui.confirm("Portal", "Dungeon verlassen?"))
	ask.call()
	await wait_physics_frames(2)
	var modal := _modal(ui)
	modal.input_guard = 0.0
	assert_true(modal.is_pad_accept_guarded(), "A is also the dash: ignored at first")
	_button(JOY_BUTTON_A)
	await wait_physics_frames(1)
	assert_eq(result, [], "a mashed dash does not confirm")
	_button(JOY_BUTTON_B)
	await wait_physics_frames(1)
	assert_eq(result, [false], "B cancels")


func test_upgrade_choice_with_dpad_and_a() -> void:
	_gamepad()
	var ui := _dungeon_ui()
	var offer: Array[UpgradeData] = [_upgrade(&"wide_swing"), _upgrade(&"strong_attack"), _upgrade(&"fast_attack")]
	var result: Array = []
	var ask := func() -> void: result.append(await ui.choose_upgrade(offer, "Truhe"))
	ask.call()
	await wait_physics_frames(2)
	var modal := _modal(ui)
	_unguard(modal)
	assert_eq(modal.get_meta(DungeonUI.DIALOG_KIND, &""), DungeonUI.DIALOG_UPGRADE_CHOICE)
	var cards := modal.find_children("*", "UiCard", true, false)
	assert_true((cards[0] as UiCard).focused, "a gamepad starts on the first card")
	# Stick: a push and its bounce are one step.
	for value in [0.6, 0.8, 1.0, 0.9]:
		_push(MenuInput.pad_axis_event(JOY_AXIS_LEFT_X, value))
	_push(MenuInput.pad_axis_event(JOY_AXIS_LEFT_X, 0.0))
	assert_true((cards[1] as UiCard).focused, "one stick push moves one card")
	var chips := modal.key_bar.find_children("Key", "UiChip", true, false)
	var glyphs: Array[StringName] = []
	for chip in chips:
		glyphs.append((chip as UiChip).get_pad_glyph())
	assert_has(glyphs, InputGlyphs.PAD_DPAD, "key bar: D-pad")
	assert_has(glyphs, InputGlyphs.pad_id_for_action(&"ui_accept"), "key bar: A")
	assert_has(glyphs, InputGlyphs.pad_id_for_action(&"upgrade_overview"), "first upgrade choice: the overview key (Tab) is Back")
	assert_ne(InputGlyphs.pad_id_for_action(&"upgrade_overview"), &"")
	_button(JOY_BUTTON_A)
	await wait_physics_frames(2)
	assert_eq(result, [offer[1]], "A picks the focused card")


func test_shop_grid_with_dpad() -> void:
	_gamepad()
	var ui := _dungeon_ui()
	RunManager.start_run()
	var offers: Array[ShopOffer] = []
	for i in 4:
		var offer := ShopOffer.new()
		offer.kind = ShopOffer.Kind.HEAL
		offer.price = 999
		offer.amount = 1.0
		offers.append(offer)
	var open := func() -> void: await ui.open_shop(offers, ui.context.player)
	open.call()
	await wait_physics_frames(2)
	var modal := _modal(ui)
	_unguard(modal)
	var grid := modal.find_child("Offers", true, false)
	var cards: Array[UiCard] = []
	for child in grid.get_children():
		if child is UiCard:
			cards.append(child)
	assert_true(cards[0].focused, "a gamepad starts on the first offer")
	_dpad(JOY_BUTTON_DPAD_DOWN)
	assert_true(cards[3].focused, "down moves one row (3 columns)")
	_dpad(JOY_BUTTON_DPAD_LEFT)
	assert_true(cards[2].focused)
	_button(JOY_BUTTON_B)
	await wait_physics_frames(1)
	assert_null(_modal(ui), "B closes the shop")
	RunManager.end_run(RunManager.EndReason.ABORT)


func test_campfire_buttons_with_dpad() -> void:
	_gamepad()
	var ui := _dungeon_ui()
	var upgrades: Array[UpgradeData] = [_upgrade(&"wide_swing"), _upgrade(&"strong_attack")]
	var result: Array = []
	var ask := func() -> void: result.append(await ui.choose_campfire_rest(2.0, true, upgrades))
	ask.call()
	await wait_physics_frames(2)
	var modal := _modal(ui)
	_unguard(modal)
	assert_eq(modal.get_focused_button().name, &"Heal", "the frame starts on the default (heal)")
	_dpad(JOY_BUTTON_DPAD_RIGHT)
	var focused := modal.get_focused_button()
	assert_ne(focused.name, &"Heal", "right goes to the upgrade list")
	_dpad(JOY_BUTTON_DPAD_DOWN)
	_button(JOY_BUTTON_A)
	await wait_physics_frames(1)
	assert_eq(result, [2], "A strengthens the second upgrade")


func test_gui_focus_content_steps_once_per_stick_push() -> void:
	var modal := Modal.create(&"test_pad_focus")
	var buttons: Array[Button] = []
	for i in 3:
		var button := Button.new()
		button.text = "Knopf %d" % i
		button.focus_mode = Control.FOCUS_ALL
		modal.content.add_child(button)
		buttons.append(button)
	modal.show_on(self)
	_unguard(modal)
	await wait_physics_frames(1)
	buttons[0].grab_focus()
	for value in [0.55, 0.7, 0.85, 1.0, 0.97, 1.0]:
		_push(MenuInput.pad_axis_event(JOY_AXIS_LEFT_Y, value))
	assert_true(buttons[1].has_focus(), "one stick push, one focus step (Godot alone steps per motion event)")
	_push(MenuInput.pad_axis_event(JOY_AXIS_LEFT_Y, 0.0))
	_dpad(JOY_BUTTON_DPAD_DOWN)
	assert_true(buttons[2].has_focus())
	modal.finish()
	await wait_physics_frames(1)


# --- Pause menu and run end ---

func test_pause_menu_opens_and_closes_with_start_and_resumes_with_b() -> void:
	var ui := GameUI.new()
	add_child_autofree(ui)
	_gamepad()
	_button(JOY_BUTTON_START)
	await wait_physics_frames(1)
	var modal := ui.get_pause_modal()
	assert_not_null(modal, "Start opens the pause menu")
	_unguard(modal)
	var footer := modal.find_child("Footer", true, false) as KeyLine
	assert_true(footer.is_showing_pad(), "pause key line with gamepad buttons")
	_dpad(JOY_BUTTON_DPAD_DOWN)
	_dpad(JOY_BUTTON_DPAD_RIGHT)
	assert_null(modal.get_focused_button(), "no second frame from the dialog")
	_button(JOY_BUTTON_START)
	await wait_physics_frames(1)
	assert_null(ui.get_pause_modal(), "Start closes it again")
	assert_false(GameManager.is_game_paused())
	_button(JOY_BUTTON_START)
	await wait_physics_frames(1)
	modal = ui.get_pause_modal()
	_unguard(modal)
	_button(JOY_BUTTON_B)
	await wait_physics_frames(1)
	assert_null(ui.get_pause_modal(), "B resumes")


func test_pause_menu_a_presses_the_selected_entry() -> void:
	var ui := GameUI.new()
	add_child_autofree(ui)
	ui.open_pause_menu()
	await wait_physics_frames(1)
	var modal := ui.get_pause_modal()
	_unguard(modal)
	_button(JOY_BUTTON_A)
	await wait_physics_frames(1)
	assert_null(ui.get_pause_modal(), "A on \"Weiter\" resumes")


func test_run_end_new_run_with_dpad_and_a() -> void:
	_gamepad()
	var ui := GameUI.new()
	add_child_autofree(ui)
	var result: Array = []
	var run_end := func() -> void: result.append(await ui.show_run_end({"reason": RunManager.EndReason.DEATH, "room": 6}, {"kills": 3, "record_before": 4}))
	run_end.call()
	await wait_physics_frames(2)
	var modal := _modal(ui)
	_unguard(modal)
	assert_true(modal.get_focused_button().has_meta(Modal.META_PAD_DEFAULT), "starts on \"Zurück ins Dorf\"")
	_dpad(JOY_BUTTON_DPAD_RIGHT)
	_button(JOY_BUTTON_A)
	await wait_physics_frames(1)
	assert_eq(result, [GameUI.RUN_END_NEW_RUN])


func test_first_run_is_a_record_and_the_forge_line_shows() -> void:
	assert_true(RunRecap.is_new_record(3, 0), "first run: always a record")
	assert_false(RunRecap.is_new_record(3, 5))
	assert_true(RunRecap.is_new_record(6, 5))
	assert_false(RunRecap.is_new_record(0, 0), "no room, no record")
	var ui := GameUI.new()
	add_child_autofree(ui)
	_set_village_gold(55)
	var run_end := func() -> void: await ui.show_run_end({"reason": RunManager.EndReason.DEATH, "room": 4}, {"kills": 2, "record_before": 0})
	run_end.call()
	await wait_physics_frames(2)
	var modal := _modal(ui)
	assert_not_null(modal.find_child("Record", true, false), "the first run is a record")
	var forge := modal.find_child("ForgeHint", true, false) as Label
	assert_not_null(forge, "the run end names what the village gold buys")
	assert_string_contains(forge.text, MetaProgression.get_upgrade_name(MetaProgression.VITALITY))
	assert_string_contains(forge.text, str(MetaProgression.get_next_cost(MetaProgression.VITALITY)))
	assert_true(modal.fits_screen(), "still under 60 % of the screen")
	assert_lte(modal.frame.get_combined_minimum_size().x, UiKit.px(GameUI.RUN_END_WIDTH) + 1.0, "no wider than the dialog")
	# The longer English line (after the translation import) still fits next to the village gold.
	var english := "Affordable in the village: Vitality III (320 gold)"
	var size := UiKit.font_px(UiKit.SIZE_BODY)
	var needed := UiKit.bold_font().get_string_size(english, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x \
			+ UiKit.get_font().get_string_size("Village gold 9999", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + UiKit.px(20)
	assert_lte(needed, UiKit.px(GameUI.RUN_END_WIDTH - UiDialog.PADDING.y * 2.0), "English fits: %.0f px" % needed)
	modal.finish(modal.accept_result)
	await wait_physics_frames(1)


func test_next_forge_step_is_the_cheapest_open_upgrade() -> void:
	# Costs are TESTWERTE (D-167): read them, do not repeat them.
	var cost := MetaProgression.get_next_cost(MetaProgression.VITALITY)
	var step := RunRecap.next_forge_step(cost - 4)
	assert_eq(step["id"], MetaProgression.VITALITY, "cheapest, first in forge order")
	assert_eq(int(step["level"]), 1)
	assert_eq(int(step["cost"]), cost)
	assert_eq(int(step["missing"]), 4, "Noch 4 Gold bis Vitalität I")
	assert_eq(int(RunRecap.next_forge_step(cost)["missing"]), 0, "affordable")
	assert_eq(RunRecap.roman(1), "I")
	assert_eq(RunRecap.roman(4), "IV")
	var text := GameUI.forge_hint_text(step)
	assert_string_contains(text, "4")
	assert_string_contains(text, "I")
	assert_eq(GameUI.forge_hint_text({}), "")


# --- Main menu ---

func test_main_menu_with_dpad_a_and_b() -> void:
	PlayerProfile.current().complete_setup("Kerze", PlayerLook.default_look())
	var menu: MainMenu = add_child_autofree(MainMenu.new())
	await wait_physics_frames(1)
	_gamepad()
	var list := menu.get_list()
	var first := list.get_selected_id()
	_dpad(JOY_BUTTON_DPAD_DOWN)
	assert_ne(list.get_selected_id(), first, "D-pad moves the list")
	assert_eq(list.get_selected_id(), MainMenu.ENTRY_SLOTS)
	_button(JOY_BUTTON_A)
	await wait_physics_frames(1)
	var panel := menu.get_open_panel()
	assert_true(panel is SlotPanel, "A opens the worlds")
	assert_true(panel.is_footer_pad(), "the footer shows gamepad buttons")
	_button(JOY_BUTTON_B)
	await wait_physics_frames(1)
	assert_null(menu.get_open_panel(), "B goes back")
	# Stick: one push, one step (the bounce of the stream is ignored).
	var before := list.get_selected_id()
	for value in [0.5, 0.7, 0.9, 1.0, 0.95]:
		_push(MenuInput.pad_axis_event(JOY_AXIS_LEFT_Y, value))
	_push(MenuInput.pad_axis_event(JOY_AXIS_LEFT_Y, 0.0))
	assert_ne(list.get_selected_id(), before)
	list.select_id(before)


func test_new_world_and_world_actions_with_the_gamepad() -> void:
	PlayerProfile.current().complete_setup("Kerze", PlayerLook.default_look())
	var menu: MainMenu = add_child_autofree(MainMenu.new())
	await wait_physics_frames(1)
	_gamepad()
	var free := SaveManager.get_free_slot()
	var create := menu.open_create(free)
	await wait_physics_frames(2)
	assert_true(create.is_footer_pad())
	_button(JOY_BUTTON_A)
	await wait_physics_frames(2)
	assert_true(SaveManager.has_slot(free), "A creates the world (default name, no keyboard)")
	assert_true(menu.is_starting())
	menu.queue_free()
	await wait_physics_frames(1)
	var again: MainMenu = add_child_autofree(MainMenu.new())
	await wait_physics_frames(1)
	var slots := again.open_slots()
	await wait_physics_frames(1)
	slots.select_slot(free)
	_button(JOY_BUTTON_Y)
	assert_true(slots.is_renaming(), "Y renames")
	await wait_physics_frames(1)
	_button(JOY_BUTTON_B)
	await wait_physics_frames(1)
	assert_false(slots.is_renaming(), "B cancels the name field")
	_button(JOY_BUTTON_X)
	assert_true(slots.is_confirming_delete(), "X asks before deleting")
	_button(JOY_BUTTON_B)
	assert_false(slots.is_confirming_delete())
	assert_true(SaveManager.has_slot(free), "nothing deleted")


func test_first_start_goes_on_with_a_only() -> void:
	PlayerProfile.reset()
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()
	assert_true(PlayerProfile.current().needs_setup())
	_gamepad()
	var menu: MainMenu = add_child_autofree(MainMenu.new())
	await wait_physics_frames(2)
	var panel := menu.get_open_panel() as ProfilePanel
	assert_not_null(panel, "Wie heißt du?")
	assert_true(panel.is_footer_pad())
	var saved: Array = []
	panel.saved.connect(func() -> void: saved.append(true))
	# Down out of the name field, through the rows to "Los geht's", A.
	_dpad(JOY_BUTTON_DPAD_DOWN)
	assert_eq(panel.editor.get_row(), ProfileEditor.Row.FIGURE)
	_dpad(JOY_BUTTON_DPAD_RIGHT)
	_button(JOY_BUTTON_A)
	await wait_physics_frames(3)
	assert_eq(saved, [true], "the first start goes on without a keyboard")
	assert_false(PlayerProfile.current().needs_setup(), "the default name was taken")
	PlayerProfile.current().complete_setup("Kerze", PlayerLook.default_look())

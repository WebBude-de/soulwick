extends GutTest
## Talent tree at the candle altar (KE8, KONZEPT §6.1/§6.2, D-196): the visit rules (TalentTreeEdit:
## setting points is free, taking them back costs 10 % in Seelenkristalle on confirm, read-only for
## co-op guests, spells into slots) and the dialog (TalentTreeDialog: three paths with four Ebenen,
## "Talentpunkte: n", node states, cost shown before paying) with mouse, keyboard, gamepad and touch.
## Wallet and storage are fakes: no save and no account file is touched.

const PROFILE_PATH := "user://test_talent_tree_ui_progress.cfg"

var _old_locale: String
var _old_save_path: String
## Fake wallet and storage of the visits.
var _crystals := 0
var _stored: Array[TalentState] = []
var _layer: CanvasLayer = null


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	Loc.apply(&"de")
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_talent_tree_ui.cfg"
	AccountProgress.path_override = PROFILE_PATH
	AccountProgress.reset()
	# The game's gamepad bindings (A = ui_accept, B = ui_cancel, D-pad), as at start.
	GamepadInput.ensure_actions()


func before_each() -> void:
	_crystals = 10
	_stored.clear()
	MenuInput.reset()
	_layer = CanvasLayer.new()
	# Above GUT's own output panel, so clicks reach the dialog like in the game.
	_layer.layer = 200
	add_child_autofree(_layer)


func after_each() -> void:
	GameManager.clear_pause_reasons()
	InputDevice.shared().set_kind(InputDevice.Kind.KEYBOARD_MOUSE)
	MenuInput.reset()


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)
	SaveManager.save_path = _old_save_path
	AccountProgress.path_override = ""
	AccountProgress.reset()
	for path in [PROFILE_PATH, PROFILE_PATH + ".prev.bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A visit with points free points on state, fake wallet and storage.
func _visit(points: int, state: TalentState = null, can_edit := true) -> TalentTreeEdit:
	var edit := TalentTreeEdit.create(state, points, can_edit)
	edit.crystals_source = func() -> int: return _crystals
	edit.spend_crystals = func(amount: int) -> bool:
		if amount > _crystals:
			return false
		_crystals -= amount
		return true
	edit.refund_crystals = func(amount: int) -> void: _crystals += amount
	edit.store = func(stored: TalentState) -> Error:
		_stored.append(stored)
		return OK
	return edit


func _state(levels: Dictionary) -> TalentState:
	var state := TalentState.new()
	for id: StringName in levels:
		state.levels[id] = int(levels[id])
	return state


func _dialog(edit: TalentTreeEdit) -> TalentTreeDialog:
	var dialog := TalentTreeDialog.create(edit)
	dialog.show_on(_layer)
	dialog.modal.input_guard = 0.0
	dialog.modal.pad_accept_guard = 0.0
	return dialog


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _pad(dialog: TalentTreeDialog, button: JoyButton) -> void:
	dialog.modal._unhandled_input(MenuInput.pad_button_event(button))
	dialog.modal._unhandled_input(MenuInput.pad_button_event(button, false))


func _key(dialog: TalentTreeDialog, keycode: Key) -> void:
	dialog.modal._unhandled_input(MenuInput.key_event(keycode))


# --- Rules of a visit ---

func test_setting_points_is_free_and_stays_in_the_budget() -> void:
	var edit := _visit(2)
	assert_true(edit.raise(&"light_foot"))
	assert_true(edit.raise(&"light_foot"))
	assert_false(edit.raise(&"light_foot"), "no third point with 2 available")
	assert_eq(edit.raise_reason(&"light_foot"), TalentTreeEdit.Reason.NO_POINTS)
	assert_eq(edit.get_free_points(), 0)
	assert_eq(edit.get_cost(), 0, "setting points is free")
	assert_true(edit.can_apply())
	assert_true(edit.apply())
	assert_eq(_crystals, 10, "nothing paid")
	assert_eq(_stored.size(), 1)
	assert_eq(_stored[0].get_level(&"light_foot"), 2)


func test_taking_back_costs_ten_percent_on_confirm_only() -> void:
	var edit := _visit(12, _state({&"vitality": 5, &"might": 3, &"steadfast": 2, &"shield_breaker": 2}))
	assert_eq(edit.get_cost(), 0)
	assert_true(edit.lower(&"shield_breaker"))
	assert_eq(edit.get_refunded_points(), 1)
	assert_eq(edit.get_cost(), 1, "at least one crystal")
	assert_eq(_crystals, 10, "nothing paid before confirming")
	edit.raise(&"light_foot")
	assert_eq(edit.get_cost(), 1, "raising elsewhere does not offset it (D-196)")
	assert_true(edit.apply())
	assert_eq(_crystals, 9, "paid on confirm")
	assert_eq(edit.get_cost(), 0, "the new distribution is the stored one")


func test_lowering_a_point_set_in_this_visit_is_free() -> void:
	var edit := _visit(3)
	edit.raise(&"vitality")
	edit.lower(&"vitality")
	assert_eq(edit.get_cost(), 0)
	assert_false(edit.is_dirty())


func test_respec_that_costs_more_than_the_world_has_is_refused() -> void:
	_crystals = 0
	var edit := _visit(5, _state({&"vitality": 5}))
	edit.lower(&"vitality")
	assert_false(edit.can_afford())
	assert_false(edit.can_apply())
	assert_false(edit.apply())
	assert_true(_stored.is_empty(), "nothing stored")


func test_storing_fails_gives_the_crystals_back() -> void:
	var edit := _visit(5, _state({&"vitality": 5}))
	edit.store = func(_state_arg: TalentState) -> Error: return ERR_CANT_OPEN
	edit.lower(&"vitality")
	assert_false(edit.apply())
	assert_eq(_crystals, 10, "refunded")
	assert_true(edit.is_dirty(), "the changes are still there")


func test_ebenen_open_after_points_in_the_path_and_higher_ones_hold() -> void:
	var edit := _visit(20)
	assert_eq(edit.get_node_state(&"swift_blade"), TalentTreeEdit.NodeState.LOCKED)
	assert_eq(edit.raise_reason(&"swift_blade"), TalentTreeEdit.Reason.LOCKED)
	for i in 3:
		edit.raise(&"light_foot")
	assert_eq(edit.get_node_state(&"light_foot"), TalentTreeEdit.NodeState.FULL)
	assert_eq(edit.get_node_state(&"swift_blade"), TalentTreeEdit.NodeState.AVAILABLE, "Ebene 2 opens after 3")
	edit.raise(&"swift_blade")
	assert_eq(edit.get_node_state(&"swift_blade"), TalentTreeEdit.NodeState.TAKEN)
	assert_eq(edit.lower_reason(&"light_foot"), TalentTreeEdit.Reason.HOLDS_HIGHER)


func test_spell_talents_fill_the_first_free_slot() -> void:
	var edit := _visit(10)
	edit.raise(&"light_flash")
	assert_eq(edit.get_spell_slots(), 1)
	assert_eq(edit.get_equipped_spell(0), &"light_flash", "Lichtblitz goes into its slot")
	for i in 3:
		edit.raise(&"spell_power")
	edit.raise(&"soul_shield")
	assert_eq(edit.get_equipped_spell(0), &"light_flash", "a full slot keeps its spell")
	assert_true(edit.equip_spell(&"soul_shield", 0))
	assert_eq(edit.get_equipped_spell(0), &"soul_shield")


func test_read_only_visit_changes_nothing() -> void:
	var edit := _visit(5, _state({&"vitality": 2}), false)
	assert_false(edit.raise(&"vitality"))
	assert_eq(edit.raise_reason(&"vitality"), TalentTreeEdit.Reason.READ_ONLY)
	assert_false(edit.lower(&"vitality"))
	assert_false(edit.can_apply())
	assert_false(edit.is_dirty())


func test_account_visit_reads_the_account_level() -> void:
	AccountProgress.reset()
	var progress := AccountProgress.current()
	progress.xp = AccountProgress.xp_for_level(4)
	var edit := TalentTreeEdit.for_account(true, progress)
	assert_eq(edit.available_points, 3, "level 4 gives 3 points")


# --- The dialog ---

func test_dialog_shows_three_paths_four_ebenen_and_the_points() -> void:
	var dialog := _dialog(_visit(3))
	await _frames(2)
	for talent_path in TalentDef.PATHS:
		var column := dialog.get_column(talent_path)
		assert_not_null(column, "column %s" % talent_path)
		assert_eq(column.rows.size(), 4, "four Ebenen in %s" % talent_path)
	assert_eq(dialog.find_children("Node_*", "TalentNodeButton", true, false).size(), 21, "every talent and spell node")
	assert_eq(dialog.get_points_text(), "Talentpunkte: 3")
	var tier := dialog.find_child("Tier2", true, false)
	assert_not_null(tier)
	assert_eq((tier.find_child("TierLabel", true, false) as Label).text, "Ebene 2", "the word is Ebene, not Rang")
	assert_eq(dialog.get_node_button(&"light_foot").state, TalentTreeEdit.NodeState.AVAILABLE)
	assert_eq(dialog.get_node_button(&"wind_runner").state, TalentTreeEdit.NodeState.LOCKED)
	assert_true(dialog.get_node_button(&"wind_runner").talent.is_capstone())
	dialog.close()


func test_dialog_fits_the_720p_screen() -> void:
	var dialog := _dialog(_visit(30))
	await _frames(2)
	var needed := dialog.modal.frame.get_combined_minimum_size()
	gut.p("talent tree panel: %s" % needed)
	assert_lt(needed.x, 1280.0, "fits the width of the PC view")
	assert_lt(needed.y, 720.0, "fits the height of the PC view")
	dialog.close()


func test_mouse_click_chooses_then_sets_a_point() -> void:
	var dialog := _dialog(_visit(3))
	await _frames(2)
	var node := dialog.get_node_button(&"vitality")
	node.pressed.emit()
	assert_eq(dialog.selected_id, &"vitality", "first click chooses")
	assert_eq(dialog.edit.get_level(&"vitality"), 0)
	node.pressed.emit()
	assert_eq(dialog.edit.get_level(&"vitality"), 1, "a click on the chosen node sets a point")
	assert_eq(dialog.get_points_text(), "Talentpunkte: 2")
	dialog.get_raise_button().pressed.emit()
	assert_eq(dialog.edit.get_level(&"vitality"), 2, "+ Punkt setzen")
	dialog.get_lower_button().pressed.emit()
	assert_eq(dialog.edit.get_level(&"vitality"), 1, "− Zurücknehmen")
	dialog.close()


func test_cost_is_shown_before_paying_and_confirm_pays() -> void:
	var dialog := _dialog(_visit(5, _state({&"vitality": 5})))
	await _frames(2)
	assert_eq(dialog.get_cost_text(), "Punkte setzen ist kostenlos.")
	dialog.choose(&"vitality")
	dialog.lower_selected()
	assert_eq(dialog.get_cost_text(), "Umskillen: 1 Seelenkristall", "the fee shows before anything is paid")
	assert_eq(_crystals, 10)
	dialog.request_apply()
	await _frames(2)
	var confirm := dialog.get_confirm()
	assert_not_null(confirm, "a fee asks first")
	var text := confirm.find_child("ConfirmText", true, false) as Label
	assert_string_contains(text.text, "Kosten: 1")
	assert_string_contains(text.text, "du hast 10")
	(confirm.find_child("PayButton", true, false) as Button).pressed.emit()
	await _frames(2)
	assert_eq(_crystals, 9, "paid")
	assert_eq(_stored.size(), 1)
	assert_eq(_stored[0].get_level(&"vitality"), 4)
	dialog.close()


func test_closing_with_free_changes_stores_them() -> void:
	var dialog := _dialog(_visit(2))
	await _frames(2)
	var result: Array = []
	dialog.closed.connect(func(applied: bool) -> void: result.append(applied))
	dialog.choose(&"might")
	dialog.raise_selected()
	dialog.request_close()
	await _frames(2)
	assert_eq(_stored.size(), 1, "stored on close")
	assert_eq(result, [true], "closed reports the stored change")


func test_closing_with_a_fee_asks_and_can_discard() -> void:
	var dialog := _dialog(_visit(5, _state({&"vitality": 5})))
	await _frames(2)
	dialog.choose(&"vitality")
	dialog.lower_selected()
	dialog.request_close()
	await _frames(2)
	var confirm := dialog.get_confirm()
	assert_not_null(confirm)
	(confirm.find_child("DiscardButton", true, false) as Button).pressed.emit()
	await _frames(2)
	assert_true(_stored.is_empty(), "nothing stored")
	assert_eq(_crystals, 10, "nothing paid")


func test_keyboard_enter_sets_and_delete_takes_back() -> void:
	var dialog := _dialog(_visit(3))
	await _frames(2)
	assert_eq(dialog.selected_id, &"light_foot", "the first node that takes a point is chosen")
	dialog.modal.focus_button(dialog.get_node_button(&"light_foot"))
	_key(dialog, KEY_ENTER)
	assert_eq(dialog.edit.get_level(&"light_foot"), 1, "Enter on the chosen node sets a point")
	_key(dialog, KEY_PLUS)
	assert_eq(dialog.edit.get_level(&"light_foot"), 2, "+ sets one")
	_key(dialog, KEY_DELETE)
	assert_eq(dialog.edit.get_level(&"light_foot"), 1, "Entf takes one back")
	_key(dialog, KEY_ESCAPE)
	await _frames(2)
	assert_eq(_stored.size(), 1, "Esc closes and keeps the free change")


func test_gamepad_dpad_chooses_a_sets_y_takes_back_b_closes() -> void:
	InputDevice.shared().set_kind(InputDevice.Kind.GAMEPAD)
	var dialog := _dialog(_visit(3))
	await _frames(3)
	var focused := dialog.modal.get_focused_button()
	assert_true(focused is TalentNodeButton, "the gamepad starts on a node")
	var start := dialog.selected_id
	_pad(dialog, JOY_BUTTON_DPAD_DOWN)
	await _frames(2)
	_pad(dialog, JOY_BUTTON_DPAD_RIGHT)
	await _frames(2)
	assert_ne(dialog.selected_id, start, "the D-pad moves the choice")
	var chosen := dialog.selected_id
	dialog.modal.focus_button(dialog.get_node_button(&"vitality"))
	await _frames(2)
	assert_eq(dialog.selected_id, &"vitality", "the focused node is the chosen one")
	_pad(dialog, JOY_BUTTON_A)
	assert_eq(dialog.edit.get_level(&"vitality"), 1, "A sets a point")
	_pad(dialog, JOY_BUTTON_X)
	assert_eq(dialog.edit.get_level(&"vitality"), 2, "X sets one too")
	_pad(dialog, JOY_BUTTON_Y)
	assert_eq(dialog.edit.get_level(&"vitality"), 1, "Y takes one back")
	assert_ne(chosen, &"")
	_pad(dialog, JOY_BUTTON_B)
	await _frames(2)
	assert_eq(_stored.size(), 1, "B closes")


func test_touch_taps_choose_and_set() -> void:
	InputDevice.shared().set_kind(InputDevice.Kind.TOUCH)
	var dialog := _dialog(_visit(3))
	await _frames(3)
	var node := dialog.get_node_button(&"spell_power")
	# Window coordinates: push_input applies the stretch transform of the root viewport.
	var point := get_viewport().get_final_transform() * node.get_global_rect().get_center()
	for i in 2:
		await _tap(point)
	assert_eq(dialog.selected_id, &"spell_power", "a tap chooses")
	assert_eq(dialog.edit.get_level(&"spell_power"), 1, "a second tap sets a point")
	dialog.close()


## A touch tap as the viewport sees it with touch-to-mouse emulation (press and release).
func _tap(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		click.position = point
		click.global_position = point
		click.pressed = pressed
		get_viewport().push_input(click)
		await wait_physics_frames(2)


func test_spells_go_into_the_slot() -> void:
	var dialog := _dialog(_visit(6))
	await _frames(2)
	assert_not_null(dialog.find_child("NoSpellHint", true, false), "without Lichtblitz a hint")
	dialog.choose(&"light_flash")
	dialog.raise_selected()
	await _frames(1)
	assert_not_null(dialog.find_child("Slot1", true, false), "the slot opens")
	assert_eq(dialog.edit.get_equipped_spell(0), &"light_flash")
	dialog.find_child("Slot1", true, false).pressed.emit()
	assert_eq(dialog.edit.get_equipped_spell(0), &"", "pressing the chosen slot empties it")
	(dialog.find_child("Spell_light_flash", true, false) as Button).pressed.emit()
	assert_eq(dialog.edit.get_equipped_spell(0), &"light_flash", "a spell button fills the slot")
	dialog.close()


func test_read_only_dialog_has_no_changing_buttons() -> void:
	var dialog := _dialog(_visit(5, _state({&"vitality": 2}), false))
	await _frames(2)
	assert_not_null(dialog.find_child("ViewOnlyNote", true, false))
	assert_false(dialog.get_apply_button().visible)
	assert_false(dialog.get_raise_button().is_visible_in_tree())
	dialog.choose(&"vitality")
	dialog.choose(&"vitality")
	assert_eq(dialog.edit.get_level(&"vitality"), 2, "a second click changes nothing")
	_key(dialog, KEY_ESCAPE)
	await _frames(2)
	assert_true(_stored.is_empty())


func test_every_text_key_has_both_languages() -> void:
	for key in [&"TALENT_TREE_TITLE", &"TALENT_TREE_POINTS", &"TALENT_TREE_TIER", &"TALENT_TREE_COST",
			&"TALENT_TREE_COST_ONE", &"TALENT_TREE_CONFIRM_TEXT", &"TALENT_TREE_VIEW_ONLY", &"TALENT_TREE_NO_SPELL"]:
		assert_true(Loc.has_key(key, &"de"), "%s de" % key)
		assert_true(Loc.has_key(key, &"en"), "%s en" % key)

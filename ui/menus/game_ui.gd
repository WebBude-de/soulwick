class_name GameUI
extends CanvasLayer
## Global dialogs of game.tscn: Esc pause menu (docs/design screen 08) with the shared options
## (OptionsView, same as the main menu) and the run end summary (screen 07, UX1: run statistics,
## "Zurück ins Dorf" or "Neuer Run"). F11 toggles fullscreen anywhere in the game.

signal abort_run_requested
signal main_menu_requested

## Results of show_run_end().
const RUN_END_VILLAGE: StringName = &"village"
const RUN_END_NEW_RUN: StringName = &"new_run"
## Own pause reason of the options dialog, so closing it keeps the pause menu's pause.
const PAUSE_OPTIONS: StringName = &"options"

## Pause panel width and run end dialog width in mockup pixels (ui_spec screens.pause / dialog).
const PAUSE_WIDTH := 170.0
const RUN_END_WIDTH := 262.0
const CONFIRM_WIDTH := 220.0
## Run end stat tiles (mockup pixels).
const STAT_TILE_SIZE := Vector2(54, 30)

## Set by WorldController so the pause menu can offer "Run abbrechen" only inside the dungeon.
var in_dungeon := false

var _pause_modal: Modal = null
var _pause_buttons: Array[Button] = []
var _pause_index := 0
var _recap: RunRecap = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	_recap = RunRecap.new()
	_recap.name = "RunRecap"
	add_child(_recap)


## The local player (WorldController, every world change): the run recap watches its hits.
func bind_player(player: Player) -> void:
	_recap.bind_player(player)


func get_recap() -> RunRecap:
	return _recap


func get_pause_modal() -> Modal:
	return _pause_modal


func _unhandled_input(event: InputEvent) -> void:
	if GameOptions.handle_shortcut(event):
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed(&"pause_menu"):
		return
	if _pause_modal != null:
		get_viewport().set_input_as_handled()
		UiSound.back(self)
		_pause_modal.finish(&"resume")
	elif not GameManager.is_game_paused():
		# Other dialogs handle Esc themselves; the pause menu only opens over running gameplay.
		get_viewport().set_input_as_handled()
		open_pause_menu()


func open_pause_menu() -> void:
	var modal := Modal.create(GameManager.PAUSE_MENU)
	modal.cancel_allowed = false
	_pause_modal = modal
	modal.frame.add_theme_stylebox_override("panel", UiKit.padded_style(&"normal", 10, 10))
	modal.set_width(PAUSE_WIDTH)
	modal.content.add_theme_constant_override("separation", int(UiKit.px(4)))
	var title := UiKit.title("Pause", UiKit.SIZE_TITLE_LARGE)
	modal.content.add_child(title)
	_pause_buttons.clear()
	_add_pause_button(modal, UiKit.menu_button("Weiterspielen", "Esc", modal.finish.bind(&"resume")))
	_add_pause_button(modal, UiKit.menu_button("Optionen", "Ton · Bild · Tasten", open_options))
	if in_dungeon:
		var payout := RunManager.calculate_payout(RunManager.get_run_gold(), RunManager.EndReason.ABORT)
		_add_pause_button(modal, UiKit.menu_button("Run abbrechen", "50 %% Gold · %d" % payout, modal.finish.bind(&"abort"), true))
	else:
		_add_pause_button(modal, UiKit.menu_button("Hauptmenü", "Fortschritt bleibt", modal.finish.bind(&"main_menu")))
	_add_pause_button(modal, UiKit.menu_button("Spiel beenden", "Run geht verloren" if in_dungeon else "", modal.finish.bind(&"quit")))
	var footer_parts: PackedStringArray = []
	if in_dungeon:
		footer_parts.append("Raum %d" % maxi(1, RunManager.get_current_room()))
	footer_parts.append("Spiel pausiert")
	footer_parts.append("↑↓ Enter · Esc fortsetzen")
	var footer := UiKit.text_label(" · ".join(footer_parts), UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal.content.add_child(footer)
	modal.input_handler = _on_pause_key
	_select_pause_button(0, false)
	# Untyped: a dialog freed from outside finishes with null.
	var choice: Variant = await modal.open(self)
	_pause_modal = null
	_pause_buttons.clear()
	match choice:
		&"abort":
			if await _confirm_abort():
				abort_run_requested.emit()
		&"main_menu":
			main_menu_requested.emit()
		&"quit":
			get_tree().quit()


## The shared options (OptionsView) over the hidden pause menu; Esc or "Zurück" returns to it.
func open_options() -> void:
	var modal := Modal.create(PAUSE_OPTIONS)
	modal.frame.add_theme_stylebox_override("panel", UiKit.padded_style(&"normal", MenuPanel.PADDING.x, MenuPanel.PADDING.y))
	modal.set_width(OptionsPanel.WIDTH)
	var view := OptionsView.new()
	view.listen_unhandled = true
	view.back_requested.connect(func() -> void:
		UiSound.back(view)
		modal.finish())
	modal.content.add_child(view)
	modal.set_footer("Spiel pausiert")
	var pause := _pause_modal
	if pause != null:
		pause.visible = false
	await modal.open(self)
	view.save_volumes()
	if pause != null and is_instance_valid(pause):
		pause.visible = true


## Run end (UX1): title by reason, room and cycle, cause of death, stat tiles (rooms, kills,
## upgrades, time), gold and crystal rows. Returns RUN_END_VILLAGE (Enter) or RUN_END_NEW_RUN (N).
## Same menu kit as the dungeon dialogs (UX2, UiDialog.create_menu): eyebrow, title, divider,
## option buttons with key caps and the key bar inside the panel.
## stats: RunRecap.get_stats(); empty = this GameUI's own recap.
func show_run_end(summary: Dictionary, stats: Dictionary = {}) -> StringName:
	if stats.is_empty():
		stats = _recap.get_stats()
	var reason: int = summary.get("reason", RunManager.EndReason.DEATH)
	var title_text := DungeonTexts.t(&"RUNEND_DEATH")
	var ratio_text := "50 %"
	var title_color := UiKit.COLOR_DANGER
	if reason == RunManager.EndReason.EXIT:
		title_text = DungeonTexts.t(&"RUNEND_EXIT")
		ratio_text = "100 %"
		title_color = UiKit.COLOR_GOLD
	elif reason == RunManager.EndReason.ABORT:
		title_text = DungeonTexts.t(&"RUNEND_ABORT")
		title_color = UiKit.COLOR_GOLD
	var room: int = summary.get("room", 1)
	var cycle := floori(float(maxi(1, room) - 1) / RoomSequence.CYCLE_LENGTH) + 1
	var modal := UiDialog.create_menu(GameManager.PAUSE_RUN_END, RUN_END_WIDTH, title_text,
			DungeonTexts.t(&"RUNEND_SUBTITLE", [room, cycle]), DungeonTexts.t(&"RUNEND_EYEBROW"), title_color, title_color)
	modal.cancel_allowed = false
	var record_before: int = stats.get("record_before", 0)
	if record_before > 0 and room > record_before:
		var record := UiKit.text_label(DungeonTexts.t(&"RUNEND_RECORD", [record_before]), UiKit.SIZE_BODY, UiKit.COLOR_GOLD, true)
		record.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		modal.content.add_child(record)
	var cause: String = stats.get("cause", "")
	if reason == RunManager.EndReason.DEATH and not cause.is_empty():
		var cause_label := UiKit.text_label(DungeonTexts.t(&"RUNEND_CAUSE", [cause]), UiKit.SIZE_BODY, UiKit.COLOR_DANGER_SOFT)
		cause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		modal.content.add_child(cause_label)
	modal.content.add_child(_stat_tiles([
		[str(stats.get("rooms_cleared", 0)), DungeonTexts.t(&"RUNEND_ROOMS")],
		[str(stats.get("kills", 0)), DungeonTexts.t(&"RUNEND_KILLS")],
		[str(stats.get("upgrades", 0)), DungeonTexts.t(&"RUNEND_UPGRADES")],
		[RunRecap.format_duration(stats.get("play_time", 0.0)), DungeonTexts.t(&"RUNEND_TIME")],
	]))
	var rows: Array = [
		[DungeonTexts.t(&"RUNEND_GOLD_EARNED"), str(summary.get("gold_earned", summary.get("remaining_gold", 0))), UiKit.COLOR_TEXT_SOFT],
		[DungeonTexts.t(&"RUNEND_GOLD_LEFT"), str(summary.get("remaining_gold", 0)), UiKit.COLOR_GOLD],
		[DungeonTexts.t(&"RUNEND_PAYOUT", [ratio_text]), "+%d" % summary.get("payout", 0), UiKit.COLOR_SUCCESS],
	]
	if summary.get("remaining_crystals", 0) > 0:
		rows.append([DungeonTexts.t(&"RUNEND_CRYSTALS", [ratio_text]), "+%d" % summary.get("crystal_payout", 0), UiKit.COLOR_CRYSTAL])
	rows.append([DungeonTexts.t(&"RUNEND_VILLAGE_GOLD"), str(SaveManager.get_permanent_gold()), UiKit.COLOR_TEXT])
	UiDialog.add_rows(modal, rows)
	UiDialog.add_buttons(modal, [
		{"text": DungeonTexts.t(&"RUNEND_TO_VILLAGE"), "key": DungeonTexts.t(&"MENU_KEY_ENTER"), "result": RUN_END_VILLAGE, "default": true},
		{"text": DungeonTexts.t(&"RUNEND_NEW_RUN"), "key": "N", "result": RUN_END_NEW_RUN},
	], false)
	modal.hotkeys[KEY_N] = modal.finish.bind(RUN_END_NEW_RUN)
	UiDialog.add_footnote(modal, DungeonTexts.t(&"RUNEND_FOOTNOTE"))
	modal.set_key_hints([
		[DungeonTexts.t(&"MENU_KEY_ENTER"), DungeonTexts.t(&"RUNEND_HINT_VILLAGE")],
		["N", DungeonTexts.t(&"RUNEND_HINT_NEW_RUN")],
	])
	var choice: Variant = await modal.open(self)
	return choice if choice is StringName else RUN_END_VILLAGE


func _stat_tiles(entries: Array) -> Control:
	var row := UiKit.hbox(int(UiKit.px(4)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for entry in entries:
		var tile := UiKit.panel(&"dark")
		tile.add_theme_stylebox_override("panel", UiKit.padded_style(&"dark", 3, 3))
		tile.custom_minimum_size = UiKit.pxv(STAT_TILE_SIZE.x, STAT_TILE_SIZE.y)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := UiKit.vbox(0)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		var value := UiKit.text_label(String(entry[0]), UiKit.SIZE_VALUE, UiKit.COLOR_TEXT, true)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(value)
		var caption := UiKit.eyebrow(String(entry[1]), UiKit.COLOR_MUTED)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(caption)
		tile.add_child(box)
		row.add_child(tile)
	return row


func _add_pause_button(modal: Modal, button: Button) -> void:
	var index := _pause_buttons.size()
	_pause_buttons.append(button)
	button.mouse_entered.connect(func() -> void: _select_pause_button(index, false))
	modal.content.add_child(button)


## ↑/↓ move the highlight through the pause menu, Enter presses it.
func _on_pause_key(event: InputEvent) -> bool:
	if _pause_buttons.is_empty():
		return false
	if MenuInput.is_up(event) or MenuInput.is_down(event):
		_select_pause_button(posmod(_pause_index + (-1 if MenuInput.is_up(event) else 1), _pause_buttons.size()), true)
		return true
	if MenuInput.is_enter(event):
		_pause_buttons[_pause_index].pressed.emit()
		return true
	return false


func _select_pause_button(index: int, by_key: bool) -> void:
	if by_key and index != _pause_index:
		UiSound.hover(self)
	_pause_index = index
	for i in _pause_buttons.size():
		var selected := i == index
		_pause_buttons[i].add_theme_stylebox_override("normal", UiKit.padded_style(&"button_hover" if selected else &"button", 4, 8))


func _confirm_abort() -> bool:
	var gold := RunManager.get_run_gold()
	var modal := UiDialog.create(GameManager.PAUSE_CONFIRM, CONFIRM_WIDTH, "Run wirklich abbrechen?",
		"Du behältst nur 50 % deines Run-Goldes (%d)." % gold)
	modal.cancel_result = false
	UiDialog.add_rows(modal, [
		["Run-Gold", str(gold), UiKit.COLOR_GOLD],
		["Gutschrift (50 %)", str(RunManager.calculate_payout(gold, RunManager.EndReason.ABORT)), UiKit.COLOR_SUCCESS],
	])
	UiDialog.add_buttons(modal, [
		{"text": "Abbrechen", "sub": "", "result": true},
		{"text": "Weiterspielen", "sub": "Esc", "result": false, "default": true},
	])
	return await modal.open(self)

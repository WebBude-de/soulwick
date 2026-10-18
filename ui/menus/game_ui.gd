class_name GameUI
extends CanvasLayer
## Global dialogs of game.tscn: Esc pause menu (docs/design screen 08) with the shared options
## (OptionsView, same as the main menu) and the run end summary (screen 07, UX1: run statistics,
## "Zurück ins Dorf" or "Neuer Run"). F11 toggles fullscreen anywhere in the game.
## Gamepad (P0-2 step 2): Start opens and closes the pause menu, D-pad/stick move through it, A
## presses, B resumes; the run end takes D-pad + A on its two buttons (Modal focus). The key lines
## show the gamepad's buttons while a gamepad is in use (KeyLine).
## Touch screens (MobileUi): the pause menu has an X (resume) and no key hints; Modal draws it larger
## on phones.
## P1-3: the run end names what the village gold buys now ("Im Dorf leistbar: Vitalität I (40 Gold)")
## or how much is missing for the cheapest forge step; the first run always counts as a record.

signal abort_run_requested
signal main_menu_requested

## Results of show_run_end().
const RUN_END_VILLAGE: StringName = &"village"
const RUN_END_NEW_RUN: StringName = &"new_run"
## Own pause reason of the options dialog, so closing it keeps the pause menu's pause.
const PAUSE_OPTIONS: StringName = &"options"

## Pause panel width and run end dialog width in mockup pixels (ui_spec screens.pause / dialog).
const PAUSE_WIDTH := 170.0
const RUN_END_WIDTH := 300.0
const CONFIRM_WIDTH := 220.0
## Run end stat tiles (mockup pixels; R8 lower, the dialog stays under 60 % of the screen).
const STAT_TILE_SIZE := Vector2(62, 24)
const SKULL_ICON: Texture2D = preload("res://art/ui/skull_icon.png")
const TROPHY_ICON: Texture2D = preload("res://art/ui/trophy_icon.png")
const KeyLine := preload("res://ui/widgets/key_line.gd")
const PadNav := preload("res://ui/widgets/pad_nav.gd")

## Set by WorldController so the pause menu can offer "Run abbrechen" only inside the dungeon.
var in_dungeon := false

var _pause_modal: Modal = null
var _pause_buttons: Array[Button] = []
var _pause_index := 0
var _recap: RunRecap = null
## Texts of the open pause menu: [node, key, args] (D-111). The language can change in the options
## opened from it, so _notification() sets them again.
var _pause_texts: Array = []


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
	modal.accent = UiKit.COLOR_GOLD
	# The X (touch screens) resumes like Esc, which GameUI handles itself (pause_menu action).
	modal.close_action = func() -> void:
		UiSound.back(self)
		modal.finish(&"resume")
	_pause_modal = modal
	modal.frame.add_theme_stylebox_override("panel", UiKit.padded_style(&"normal", 10, 10))
	modal.set_width(PAUSE_WIDTH)
	modal.content.add_theme_constant_override("separation", int(UiKit.px(4)))
	var title := UiKit.title(Loc.t(&"GAME_UI_PAUSE"), UiKit.SIZE_TITLE_LARGE)
	modal.content.add_child(title)
	_pause_buttons.clear()
	_pause_texts.clear()
	_pause_texts.append([title, &"GAME_UI_PAUSE", []])
	_add_pause_button(modal, _pause_button(&"GAME_UI_RESUME", &"", [], modal.finish.bind(&"resume")))
	_add_pause_button(modal, _pause_button(&"MENU_OPTIONS", &"MENU_OPTIONS_HINT", [], open_options))
	if in_dungeon:
		var payout := RunManager.calculate_payout(RunManager.get_run_gold(), RunManager.EndReason.ABORT)
		_add_pause_button(modal, _pause_button(&"GAME_UI_ABORT_RUN", &"GAME_UI_ABORT_RUN_HINT", [payout], modal.finish.bind(&"abort"), true))
	else:
		_add_pause_button(modal, _pause_button(&"GAME_UI_MAIN_MENU", &"GAME_UI_MAIN_MENU_HINT", [], modal.finish.bind(&"main_menu")))
	# A browser tab cannot close itself.
	if not OS.has_feature("web"):
		_add_pause_button(modal, _pause_button(&"GAME_UI_QUIT", &"GAME_UI_QUIT_HINT" if in_dungeon else &"", [], modal.finish.bind(&"quit")))
	var footer := KeyLine.new()
	footer.name = "Footer"
	footer.setup(UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
	footer.set_texts(_pause_footer_text(), _pause_footer_text(true))
	footer.set_touch_text(_pause_footer_text(false, true))
	_pause_texts.append([footer, &"", []])
	modal.content.add_child(footer)
	modal.input_handler = _on_pause_key
	_select_pause_button(0, false)
	# Untyped: a dialog freed from outside finishes with null.
	var choice: Variant = await modal.open(self)
	_pause_modal = null
	_pause_buttons.clear()
	_pause_texts.clear()
	match choice:
		&"abort":
			if await _confirm_abort():
				abort_run_requested.emit()
		&"main_menu":
			main_menu_requested.emit()
		&"quit":
			get_tree().quit()


## Pause menu entry: caption key, hint key ("Esc" for resume; &"" = none) with format args.
## The texts are resolved now (tools press buttons by their text) and again on a language change.
func _pause_button(key: StringName, hint_key: StringName, hint_args: Array, on_pressed: Callable, danger := false) -> Button:
	var hint := "Esc" if key == &"GAME_UI_RESUME" else (Loc.t(hint_key, hint_args) if hint_key != &"" else "")
	if key == &"GAME_UI_RESUME" and UiKit.MobileUi.hides_key_hints():
		hint = ""
	var button := UiKit.menu_button(Loc.t(key), hint, on_pressed, danger)
	_pause_texts.append([button, key, []])
	if hint_key != &"" and button.get_child_count() > 0 and button.get_child(0) is Label:
		_pause_texts.append([button.get_child(0), hint_key, hint_args])
	return button


## pad: the gamepad line ("{dpad} {a} · {b} fortsetzen", KeyLine tokens); touch: without keys.
func _pause_footer_text(pad := false, touch := false) -> String:
	var footer_parts: PackedStringArray = []
	if in_dungeon:
		footer_parts.append(Loc.t(&"GAME_UI_ROOM", [maxi(1, RunManager.get_current_room())]))
	footer_parts.append(Loc.t(&"MENU_PAUSED"))
	if not touch:
		footer_parts.append(PadNav.text(&"GAME_UI_PAUSE_KEYS_PAD", [], "{dpad} {a} · {b} resume") if pad else Loc.t(&"GAME_UI_PAUSE_KEYS"))
	return " · ".join(footer_parts)


## Language switch from the options over the pause menu: set its texts again (D-111 §5).
func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED:
		return
	for entry: Array in _pause_texts:
		var node: Node = entry[0]
		if not is_instance_valid(node):
			continue
		var text := _pause_footer_text() if entry[1] == &"" else Loc.t(entry[1], entry[2])
		if node is KeyLine:
			(node as KeyLine).set_texts(text, _pause_footer_text(true))
			(node as KeyLine).set_touch_text(_pause_footer_text(false, true))
		elif node is Button:
			(node as Button).text = text
		elif node is Label:
			(node as Label).text = text


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
	modal.accent = UiKit.COLOR_GOLD
	# "Spiel pausiert" inside the panel (R8: the footer line at the screen edge ran into the HUD).
	var paused := UiKit.text_label(Loc.t(&"MENU_PAUSED"), UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
	paused.name = "Paused"
	paused.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	modal.content.add_child(paused)
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
	var icon := SKULL_ICON if reason == RunManager.EndReason.DEATH else TROPHY_ICON
	var modal := UiDialog.create_menu(GameManager.PAUSE_RUN_END, RUN_END_WIDTH, title_text,
			DungeonTexts.t(&"RUNEND_SUBTITLE", [room, cycle]), DungeonTexts.t(&"RUNEND_EYEBROW"), title_color, title_color, icon)
	modal.cancel_allowed = false
	# Record and cause of death share one line (R8: compact).
	var notes := UiKit.hbox(int(UiKit.px(8)))
	notes.name = "Notes"
	notes.alignment = BoxContainer.ALIGNMENT_CENTER
	var record_before: int = stats.get("record_before", 0)
	if RunRecap.is_new_record(room, record_before):
		# The first run always counts as a record (P1-3): it has no "bisher Raum".
		var record_text := DungeonTexts.t(&"RUNEND_RECORD", [record_before]) if record_before > 0 else PadNav.text(&"RUNEND_RECORD_FIRST", [], "New record!")
		var record := UiKit.text_label(record_text, UiKit.SIZE_BODY, UiKit.COLOR_GOLD, true)
		record.name = "Record"
		notes.add_child(record)
	var cause: String = stats.get("cause", "")
	if reason == RunManager.EndReason.DEATH and not cause.is_empty():
		var cause_label := UiKit.text_label(DungeonTexts.t(&"RUNEND_CAUSE", [cause]), UiKit.SIZE_BODY, UiKit.COLOR_DANGER_SOFT)
		notes.add_child(cause_label)
	if notes.get_child_count() > 0:
		modal.content.add_child(notes)
	var tiles := _stat_tiles([
		[str(stats.get("rooms_cleared", 0)), DungeonTexts.t(&"RUNEND_ROOMS")],
		[str(stats.get("kills", 0)), DungeonTexts.t(&"RUNEND_KILLS")],
		[str(stats.get("upgrades", 0)), DungeonTexts.t(&"RUNEND_UPGRADES")],
		[RunRecap.format_duration(stats.get("play_time", 0.0)), DungeonTexts.t(&"RUNEND_TIME")],
	], title_color)
	modal.content.add_child(tiles)
	var rows: Array = [
		[DungeonTexts.t(&"RUNEND_GOLD_EARNED"), str(summary.get("gold_earned", summary.get("remaining_gold", 0))), UiKit.COLOR_TEXT_SOFT],
		[DungeonTexts.t(&"RUNEND_GOLD_LEFT"), str(summary.get("remaining_gold", 0)), UiKit.COLOR_GOLD],
		[DungeonTexts.t(&"RUNEND_PAYOUT", [ratio_text]), "+%d" % summary.get("payout", 0), UiKit.COLOR_SUCCESS],
	]
	if summary.get("remaining_crystals", 0) > 0:
		rows.append([DungeonTexts.t(&"RUNEND_CRYSTALS", [ratio_text]), "+%d" % summary.get("crystal_payout", 0), UiKit.COLOR_CRYSTAL])
	var village_gold := [DungeonTexts.t(&"RUNEND_VILLAGE_GOLD"), str(SaveManager.get_permanent_gold()), UiKit.COLOR_TEXT]
	var forge := _forge_hint(RunRecap.next_forge_step())
	if forge == null:
		rows.append(village_gold)
	modal.content.add_child(_row_grid(rows))
	if forge != null:
		# P1-3: what the village gold buys, on one line with the village gold (R8: no extra height
		# with crystals, the grid loses that row).
		var village := UiKit.value_row(String(village_gold[0]), String(village_gold[1]), UiKit.COLOR_TEXT, UiKit.SIZE_BODY)
		village.size_flags_horizontal = Control.SIZE_SHRINK_END
		var line := UiKit.hbox(int(UiKit.px(12)))
		line.name = "Village"
		forge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(forge)
		line.add_child(village)
		modal.content.add_child(line)
	# D-188 (KF2): "+XP" of the account level with its bar and the level-up banner (RunRecap counts
	# the run once for the account).
	var xp_view := _recap.create_xp_view()
	if xp_view != null:
		modal.content.add_child(xp_view)
	# Both buttons sit in the key bar (R8: no extra row; their key caps name the keys).
	var buttons := UiKit.hbox(int(UiKit.px(6)))
	buttons.name = "Buttons"
	var home := UiDialog.option_button(DungeonTexts.t(&"RUNEND_TO_VILLAGE"), "", DungeonTexts.t(&"MENU_KEY_ENTER"), modal.finish.bind(RUN_END_VILLAGE), true)
	buttons.add_child(home)
	var again := UiDialog.option_button(DungeonTexts.t(&"RUNEND_NEW_RUN"), "", "N", modal.finish.bind(RUN_END_NEW_RUN))
	buttons.add_child(again)
	modal.accept_allowed = true
	modal.accept_result = RUN_END_VILLAGE
	modal.hotkeys[KEY_N] = modal.finish.bind(RUN_END_NEW_RUN)
	var dealt: Array = []
	dealt.append_array(tiles.get_children())
	dealt.append(home)
	dealt.append(again)
	modal.deal(dealt)
	modal.set_key_hints([], true, buttons)
	var choice: Variant = await modal.open(self)
	return choice if choice is StringName else RUN_END_VILLAGE


## Four stat tiles in panel_dark with a thin band in the run end colour (R8).
func _stat_tiles(entries: Array, accent := UiKit.COLOR_GOLD) -> Control:
	var row := UiKit.hbox(int(UiKit.px(4)))
	row.name = "Stats"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for entry in entries:
		var tile := UiCard.new()
		tile.normal_kind = &"dark"
		tile.focused_kind = &"dark"
		tile.padding = Vector2(4, 3)
		tile.accent = Color(accent, 0.8)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.mouse_default_cursor_shape = Control.CURSOR_ARROW
		tile.custom_minimum_size = UiKit.pxv(STAT_TILE_SIZE.x, STAT_TILE_SIZE.y)
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


## "Im Dorf leistbar: Vitalität I (40 Gold)" (gold) or "Noch 18 Gold bis Vitalität I" (muted) for
## a RunRecap.next_forge_step(); null when there is nothing left to buy.
func _forge_hint(step: Dictionary) -> Label:
	var text := forge_hint_text(step)
	if text.is_empty():
		return null
	var affordable: bool = int(step.get("missing", 0)) <= 0
	var label := UiKit.text_label(text, UiKit.SIZE_BODY, UiKit.COLOR_GOLD if affordable else UiKit.COLOR_TEXT_SOFT, affordable)
	label.name = "ForgeHint"
	return label


## Text of a forge step ({} = ""): the upgrade with its next level as a Roman numeral.
static func forge_hint_text(step: Dictionary) -> String:
	if step.is_empty():
		return ""
	var upgrade := "%s %s" % [MetaProgression.get_upgrade_name(step["id"]), RunRecap.roman(int(step["level"]))]
	var missing := int(step.get("missing", 0))
	if missing <= 0:
		return PadNav.text(&"RUNEND_FORGE_AFFORDABLE", [upgrade, int(step["cost"])], "Affordable in the village: %s (%d gold)")
	return PadNav.text(&"RUNEND_FORGE_MISSING", [missing, upgrade], "%d more gold for %s")


## Value rows in two columns (gold, payout, crystals, village gold), so the run end stays low.
func _row_grid(rows: Array) -> Control:
	var grid := GridContainer.new()
	grid.name = "Rows"
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", int(UiKit.px(12)))
	grid.add_theme_constant_override("v_separation", int(UiKit.px(3)))
	for row: Array in rows:
		var color: Color = row[2] if row.size() > 2 else UiKit.COLOR_TEXT
		var line := UiKit.value_row(String(row[0]), String(row[1]), color, UiKit.SIZE_BODY)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(line)
	return grid


func _add_pause_button(modal: Modal, button: Button) -> void:
	var index := _pause_buttons.size()
	_pause_buttons.append(button)
	button.mouse_entered.connect(func() -> void: _select_pause_button(index, false))
	modal.content.add_child(button)


## ↑/↓ (D-pad, stick) move the highlight through the pause menu, Enter or A presses it, B resumes
## (Esc and Start resume through the pause_menu action, _unhandled_input).
func _on_pause_key(event: InputEvent) -> bool:
	if _pause_buttons.is_empty():
		return false
	if MenuInput.is_up(event) or MenuInput.is_down(event):
		_select_pause_button(posmod(_pause_index + (-1 if MenuInput.is_up(event) else 1), _pause_buttons.size()), true)
		return true
	if MenuInput.direction(event) != Vector2i.ZERO:
		# ←/→ mean nothing in the list (no second focus frame from Modal).
		return true
	if MenuInput.is_confirm(event):
		_pause_buttons[_pause_index].pressed.emit()
		return true
	if MenuInput.is_pad_back(event) and _pause_modal != null:
		UiSound.back(self)
		_pause_modal.finish(&"resume")
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
	var modal := UiDialog.create(GameManager.PAUSE_CONFIRM, CONFIRM_WIDTH, Loc.t(&"GAME_UI_ABORT_QUESTION"),
		Loc.t(&"GAME_UI_ABORT_TEXT", [gold]))
	modal.cancel_result = false
	UiDialog.add_rows(modal, [
		[Loc.t(&"GAME_UI_RUN_GOLD"), str(gold), UiKit.COLOR_GOLD],
		[DungeonTexts.t(&"RUNEND_PAYOUT", ["50 %"]), str(RunManager.calculate_payout(gold, RunManager.EndReason.ABORT)), UiKit.COLOR_SUCCESS],
	])
	UiDialog.add_buttons(modal, [
		{"text": Loc.t(&"GAME_UI_ABORT_CONFIRM"), "sub": "", "result": true},
		{"text": Loc.t(&"GAME_UI_RESUME"), "sub": "Esc", "result": false, "default": true},
	])
	return await modal.open(self)

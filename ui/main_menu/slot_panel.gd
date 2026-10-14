class_name SlotPanel
extends MenuPanel
## "Spielstände": one card per slot with name, character, record room, gold/crystals, play time and
## last played. Enter plays a used slot or opens "Neuer Spielstand" for an empty one, Del asks before
## deleting, Esc goes back. Mouse: hover selects a card, click = Enter, buttons below.
## Texts are translation keys (D-111); the cards are rebuilt on a language change.

signal play_requested(slot: int)
signal create_requested(slot: int)
signal slot_deleted(slot: int)

## Sizes in mockup pixels.
const WIDTH := 258.0
const CARD_HEIGHT := 42.0
const PREVIEW_SCALE := 2
const FOOTER_NORMAL: StringName = &"SLOTS_FOOTER"
const FOOTER_CONFIRM: StringName = &"SLOTS_FOOTER_CONFIRM"

var _summaries: Array[Dictionary] = []
var _cards: Array[Button] = []
var _selected := 0
var _confirm_delete := false
var _cards_box: VBoxContainer = null
var _actions: HBoxContainer = null


func _ready() -> void:
	set_width(WIDTH)
	add_header(&"MENU_SLOTS", &"SLOTS_TITLE")
	_cards_box = UiKit.vbox(int(UiKit.px(4)))
	content.add_child(_cards_box)
	_actions = UiKit.hbox(int(UiKit.px(6)))
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(_actions)
	var active := SaveManager.get_active_slot()
	refresh()
	if active > 0:
		select_slot(active)


## Re-reads all slots from disk and rebuilds the cards.
func refresh() -> void:
	_summaries.clear()
	for slot in range(1, SaveSlots.SLOT_COUNT + 1):
		_summaries.append(SaveManager.get_slot_summary(slot))
	for card in _cards:
		_cards_box.remove_child(card)
		card.queue_free()
	_cards.clear()
	for i in _summaries.size():
		var card := _build_card(i)
		_cards_box.add_child(card)
		_cards.append(card)
	_selected = clampi(_selected, 0, _summaries.size() - 1)
	_confirm_delete = false
	_update_state()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _cards_box != null and _actions != null:
		refresh()


func select_slot(slot: int) -> void:
	if slot >= 1 and slot <= _summaries.size():
		_select(slot - 1)


func get_selected_slot() -> int:
	return _selected + 1


func is_confirming_delete() -> bool:
	return _confirm_delete


func handle_input(event: InputEvent) -> bool:
	if _confirm_delete:
		if MenuInput.is_accept(event):
			confirm_delete()
			return true
		if MenuInput.is_back(event):
			cancel_delete()
			return true
		return MenuInput.is_up(event) or MenuInput.is_down(event)
	if MenuInput.is_up(event):
		_select(posmod(_selected - 1, _summaries.size()), true)
		return true
	if MenuInput.is_down(event):
		_select(posmod(_selected + 1, _summaries.size()), true)
		return true
	if MenuInput.is_accept(event):
		activate_selected()
		return true
	if MenuInput.is_delete(event):
		request_delete()
		return true
	if MenuInput.is_back(event):
		close()
		return true
	return false


## Enter: play a used slot, create in an empty one.
func activate_selected() -> void:
	var slot := get_selected_slot()
	Sfx.play_ui(self, &"ui_click")
	if _summaries[_selected].get("exists", false):
		play_requested.emit(slot)
	else:
		create_requested.emit(slot)


func request_delete() -> void:
	if not _summaries[_selected].get("exists", false):
		UiSound.error(self)
		return
	Sfx.play_ui(self, &"ui_open")
	_confirm_delete = true
	_update_state()


func confirm_delete() -> void:
	if not _confirm_delete:
		return
	var slot := get_selected_slot()
	_confirm_delete = false
	if SaveManager.delete_slot(slot) == OK:
		UiSound.play(self, UiSound.DELETE)
		refresh()
		slot_deleted.emit(slot)
	else:
		_update_state()


func cancel_delete() -> void:
	UiSound.back(self)
	_confirm_delete = false
	_update_state()


func _select(index: int, by_key := false) -> void:
	if _confirm_delete or index == _selected:
		return
	_selected = index
	if by_key:
		Sfx.play_ui(self, &"ui_click", -8.0)
	_update_state()


func _update_state() -> void:
	for i in _cards.size():
		var kind := &"gold" if i == _selected else &"dark"
		if _confirm_delete and i == _selected:
			kind = &"normal"
		var style := UiKit.padded_style(kind, 4, 6)
		for state in ["normal", "pressed", "disabled", "focus"]:
			_cards[i].add_theme_stylebox_override(state, style)
		# Hovering a card that is not selected lifts it slightly, without selecting it.
		var hover_kind := kind if kind != &"dark" else &"normal"
		_cards[i].add_theme_stylebox_override("hover", UiKit.padded_style(hover_kind, 4, 6))
		var warning := _cards[i].get_node_or_null(^"Warning") as Control
		if warning != null:
			warning.visible = _confirm_delete and i == _selected
		var body := _cards[i].get_node_or_null(^"Body") as Control
		if body != null:
			body.modulate.a = 0.25 if _confirm_delete and i == _selected else 1.0
	# Deferred: the button that triggered this may still be inside its pressed signal.
	_rebuild_actions.call_deferred()


func _rebuild_actions() -> void:
	for child in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	var used: bool = not _summaries.is_empty() and _summaries[_selected].get("exists", false)
	if _confirm_delete:
		var delete := MenuPanel.action_button(&"SLOTS_DELETE", "Enter", confirm_delete, true)
		delete.add_theme_color_override("font_color", UiKit.COLOR_DANGER_SOFT)
		delete.add_theme_color_override("font_hover_color", UiKit.COLOR_DANGER_SOFT.lightened(0.2))
		_actions.add_child(delete)
		_actions.add_child(MenuPanel.action_button(&"COMMON_CANCEL", "Esc", cancel_delete))
		set_footer(FOOTER_CONFIRM)
		return
	_actions.add_child(MenuPanel.action_button(&"SLOTS_PLAY" if used else &"SLOTS_CREATE", "Enter", activate_selected, true))
	var delete_button := MenuPanel.action_button(&"SLOTS_DELETE", &"KEY_DELETE", request_delete)
	delete_button.disabled = not used
	delete_button.modulate.a = 1.0 if used else 0.45
	_actions.add_child(delete_button)
	_actions.add_child(MenuPanel.action_button(&"COMMON_BACK", "Esc", close))
	set_footer(tr(FOOTER_NORMAL) % tr(&"SLOTS_ACTION_PLAY" if used else &"SLOTS_ACTION_CREATE"))


func _build_card(index: int) -> Button:
	var summary := _summaries[index]
	var slot := index + 1
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(0, UiKit.px(CARD_HEIGHT))
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Hover only highlights (with a soft tick); a click selects, so the mouse can travel to
	# "Löschen" without changing the selection. A second click on the selected card plays.
	card.mouse_entered.connect(func() -> void:
		if not _confirm_delete and index != _selected:
			Sfx.play_ui(self, &"ui_click", -12.0))
	card.pressed.connect(func() -> void:
		if _confirm_delete:
			return
		if index == _selected:
			activate_selected()
		else:
			_select(index, true))

	var margin := MarginContainer.new()
	margin.name = "Body"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, int(UiKit.px(6)))
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(UiKit.px(3)))
	card.add_child(margin)
	var row := UiKit.hbox(int(UiKit.px(6)))
	margin.add_child(row)

	var exists: bool = summary.get("exists", false)
	if exists:
		var preview := CharacterPreview.create(PREVIEW_SCALE)
		preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(preview)
		var data := CharacterCatalog.get_character(summary.get("character", CharacterCatalog.DEFAULT_ID))
		var color: Color = summary.get("color", Color(0, 0, 0, 0))
		preview.set_character(data, color if color.a > 0.0 else data.default_color)
	else:
		var plus := UiKit.text_label("+", UiKit.SIZE_TITLE_LARGE, UiKit.COLOR_DISABLED, true)
		plus.custom_minimum_size = Vector2.ONE * CharacterPreview.FRAME_SIZE * PREVIEW_SCALE
		plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(plus)

	var info := UiKit.vbox(int(UiKit.px(1)))
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(info)
	var top := UiKit.hbox(int(UiKit.px(4)))
	info.add_child(top)
	var title_text: String = summary.get("name", SaveSlots.default_name(slot)) if exists else tr(&"SLOTS_EMPTY")
	var name_label := UiKit.text_label(title_text, UiKit.SIZE_CARD_NAME, UiKit.COLOR_TEXT if exists else UiKit.COLOR_MUTED, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	top.add_child(name_label)
	var tag := tr(&"SLOTS_SLOT_NUMBER") % slot
	if exists and slot == SaveManager.get_active_slot():
		tag = tr(&"SLOTS_ACTIVE") + " · " + tag
	top.add_child(UiKit.eyebrow(tag, UiKit.COLOR_DISABLED))

	if not exists:
		info.add_child(UiKit.text_label(&"SLOTS_NEW_LINE1", UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT))
		info.add_child(UiKit.text_label(&"SLOTS_NEW_LINE2", UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED))
	elif summary.get("broken", false):
		info.add_child(UiKit.text_label(&"SLOTS_BROKEN", UiKit.SIZE_BODY, UiKit.COLOR_DANGER_SOFT))
		info.add_child(UiKit.text_label(&"SLOTS_BROKEN_NOTE", UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED))
	else:
		var data := CharacterCatalog.get_character(summary.get("character", CharacterCatalog.DEFAULT_ID))
		var record: int = summary.get("deepest_room", 0)
		var line := "%s · %s · %s" % [
			data.display_name if data != null else "",
			(tr(&"MENU_RECORD") % record) if record > 0 else tr(&"SLOTS_NO_RUN"),
			SaveSlots.format_play_time(summary.get("play_time", 0.0))]
		info.add_child(UiKit.text_label(line, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT))
		var bottom := UiKit.hbox(int(UiKit.px(6)))
		bottom.add_child(UiKit.icon_value(UiKit.GOLD_ICON, str(summary.get("gold", 0)), UiKit.COLOR_GOLD, UiKit.SIZE_BODY, 8.0))
		bottom.add_child(UiKit.icon_value(UiKit.CRYSTAL_ICON, str(summary.get("crystals", 0)), UiKit.COLOR_CRYSTAL, UiKit.SIZE_BODY, 8.0))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bottom.add_child(spacer)
		var when := UiKit.text_label(SaveSlots.format_last_played(summary.get("last_played", 0)), UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
		when.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bottom.add_child(when)
		info.add_child(bottom)

	if exists:
		var warning := UiKit.text_label(tr(&"SLOTS_DELETE_WARNING") % title_text, UiKit.SIZE_BODY, UiKit.COLOR_DANGER_SOFT, true)
		warning.name = "Warning"
		warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warning.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		warning.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		warning.visible = false
		card.add_child(warning)
	_set_children_ignore_mouse(card)
	return card


static func _set_children_ignore_mouse(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_children_ignore_mouse(child)

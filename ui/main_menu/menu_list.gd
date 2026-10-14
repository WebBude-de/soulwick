class_name MenuList
extends VBoxContainer
## Vertical main menu list (docs/design screen 13, art/ui/menu/menu.json "menu"): the selected entry
## has the button_hover frame, gold text and a gold ">" cursor; other entries have no frame; disabled
## entries are greyed out (#7a7396) and show their hint ("bald"). Keyboard: ↑/↓ (also W/S) skip
## disabled entries, Enter/Space activates. Mouse: hover selects, click activates.
## Entry texts and hints are translation keys or composed texts (D-111): keys re-translate
## themselves on a language change, composed hints are set again by the main menu.

signal activated(id: StringName)
signal selection_changed(id: StringName)

## Entry height, gap and paddings in mockup pixels (menu.json: item_padding [1, 8], gap 2).
const ITEM_HEIGHT := 22.0
const GAP := 3.0
const PADDING_X := 8.0
const CURSOR := ">"
const COLOR_ACTIVE := UiKit.COLOR_GOLD
const COLOR_INACTIVE := UiKit.COLOR_TEXT_SOFT
const COLOR_DISABLED := UiKit.COLOR_DISABLED

## False while a sub panel has the keyboard; the selection stays visible but the cursor dims.
var active := true:
	set(value):
		active = value
		_refresh()

var _ids: Array[StringName] = []
var _buttons: Array[Button] = []
var _labels: Array[Label] = []
var _hints: Array[Label] = []
var _cursors: Array[Label] = []
var _enabled: Array[bool] = []
var _selected := -1


func _init() -> void:
	add_theme_constant_override("separation", int(UiKit.px(GAP)))
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func add_entry(id: StringName, text: String, hint := "", enabled := true) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, UiKit.px(ITEM_HEIGHT))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, empty)
	var row := UiKit.hbox(int(UiKit.px(4)))
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = UiKit.px(PADDING_X)
	row.offset_right = -UiKit.px(PADDING_X)
	var cursor := UiKit.text_label(CURSOR, UiKit.SIZE_CARD_NAME, COLOR_ACTIVE, true)
	cursor.custom_minimum_size.x = UiKit.px(8)
	cursor.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(cursor)
	var label := UiKit.text_label(text, UiKit.SIZE_CARD_NAME, COLOR_INACTIVE, true)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var hint_label := UiKit.text_label(hint, UiKit.SIZE_EYEBROW, COLOR_DISABLED)
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(hint_label)
	button.add_child(row)
	var index := _ids.size()
	button.mouse_entered.connect(_on_hover.bind(index))
	button.pressed.connect(_on_pressed.bind(index))
	# Locked entries ("Online / Gilde – bald") answer a click with a short "not possible".
	button.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if active and not _enabled[index] and click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			UiSound.error(self))
	add_child(button)
	_ids.append(id)
	_buttons.append(button)
	_labels.append(label)
	_hints.append(hint_label)
	_cursors.append(cursor)
	_enabled.append(enabled)
	button.disabled = not enabled
	if _selected < 0 and enabled:
		_selected = index
	_refresh()
	return button


func set_entry(id: StringName, text: String, hint := "", enabled := true) -> void:
	var index := _ids.find(id)
	if index < 0:
		return
	_labels[index].text = text
	_hints[index].text = hint
	_enabled[index] = enabled
	_buttons[index].disabled = not enabled
	if not enabled and _selected == index:
		_move(1)
	_refresh()


func get_selected_id() -> StringName:
	return _ids[_selected] if _selected >= 0 and _selected < _ids.size() else &""


func select_id(id: StringName) -> void:
	var index := _ids.find(id)
	if index >= 0 and _enabled[index]:
		_select(index)


func is_entry_enabled(id: StringName) -> bool:
	var index := _ids.find(id)
	return index >= 0 and _enabled[index]


## Text as shown (a key is translated).
func get_entry_text(id: StringName) -> String:
	var index := _ids.find(id)
	return tr(_labels[index].text) if index >= 0 else ""


func get_entry_hint(id: StringName) -> String:
	var index := _ids.find(id)
	return tr(_hints[index].text) if index >= 0 else ""


## Keyboard handling; returns true if the event was used.
func handle_input(event: InputEvent) -> bool:
	if not active:
		return false
	if MenuInput.is_up(event):
		_move(-1)
		return true
	if MenuInput.is_down(event):
		_move(1)
		return true
	if MenuInput.is_accept(event):
		_activate(_selected)
		return true
	return false


func _move(step: int) -> void:
	if _ids.is_empty():
		return
	var index := _selected
	for i in _ids.size():
		index = posmod(index + step, _ids.size())
		if _enabled[index]:
			if index != _selected:
				Sfx.play_ui(self, &"ui_click", -8.0)
			_select(index)
			return


func _select(index: int) -> void:
	if index == _selected:
		return
	_selected = index
	_refresh()
	selection_changed.emit(_ids[index])


func _activate(index: int) -> void:
	if index < 0 or index >= _ids.size() or not _enabled[index]:
		return
	Sfx.play_ui(self, &"ui_click")
	activated.emit(_ids[index])


func _on_hover(index: int) -> void:
	if active and _enabled[index]:
		# Same soft tick as moving with the arrow keys.
		if index != _selected:
			Sfx.play_ui(self, &"ui_click", -8.0)
		_select(index)


func _on_pressed(index: int) -> void:
	_select(index)
	_activate(index)


func _refresh() -> void:
	for i in _ids.size():
		var selected := i == _selected
		var style: StyleBox = StyleBoxEmpty.new()
		if selected:
			style = UiKit.padded_style(&"button_hover" if active else &"button", 1, PADDING_X)
		_buttons[i].add_theme_stylebox_override("normal", style)
		_buttons[i].add_theme_stylebox_override("hover", style)
		_buttons[i].add_theme_stylebox_override("pressed", style)
		var color := COLOR_INACTIVE
		if not _enabled[i]:
			color = COLOR_DISABLED
		elif selected:
			color = COLOR_ACTIVE if active else UiKit.COLOR_TEXT
		_labels[i].add_theme_color_override("font_color", color)
		_cursors[i].modulate.a = (1.0 if active else 0.45) if selected else 0.0

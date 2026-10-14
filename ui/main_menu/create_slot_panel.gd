class_name CreateSlotPanel
extends MenuPanel
## "Neuer Spielstand": name, character and clothing colour, then start fresh. Today there is one
## character; locked placeholder cards ("bald") show that more will follow. The colour swatches are
## the character's CharacterData.color_choices (same as the wardrobe at home, where it can be
## changed later). Rows: Name (text field) · Charakter (←/→) · Farbe (←/→, 1–6) · buttons.
## ↑/↓ change the row, Enter starts, Esc goes back. Typing ticks softly (UiSound). A new save has
## seen nothing, so the village explains itself (D-087).

## color is transparent when the character's default colour was kept (SaveManager stores no colour).
signal confirmed(slot: int, profile_name: String, character_id: StringName, color: Color)
## The chosen character changed: the main menu shows it in the scene too.
signal character_changed(data: CharacterData)
## The shown clothing colour changed (pick or hover preview); the main menu recolours its figure.
signal color_changed(color: Color)

enum Row { NAME, CHARACTER, COLOR, START }

## Sizes in mockup pixels.
const WIDTH := 236.0
const CARD_SIZE := Vector2(52, 58)
const PREVIEW_SCALE := 3
const SWATCH_SIZE := 14.0
const SWATCH_GAP := 3.0
## Locked placeholder cards next to the real characters (TESTWERT: 2).
const LOCKED_CARDS := 2
const FOOTER := "↑↓ Zeile · ←→ ändern · 1–%d Farbe · Enter starten · Esc zurück"
const COSMETICS_NOTE := "Weitere Anpassungen später im Zuhause."

var slot := 1

var _row := Row.NAME
var _characters: Array[CharacterData] = []
var _character_index := 0
var _color_index := 0
var _name_edit: LineEdit = null
var _last_name_length := 0
var _cards: Array[PanelContainer] = []
var _previews: Array[CharacterPreview] = []
var _character_name: Label = null
var _character_text: Label = null
var _swatch_box: HBoxContainer = null
var _swatches: Array[Button] = []
var _color_name: Label = null
var _row_labels: Array[Label] = []
var _start_button: Button = null


static func create(target_slot: int) -> CreateSlotPanel:
	var panel := CreateSlotPanel.new()
	panel.slot = target_slot
	return panel


func _ready() -> void:
	set_width(WIDTH)
	_characters = CharacterCatalog.all()
	_character_index = maxi(0, _characters.find(CharacterCatalog.get_character(CharacterCatalog.DEFAULT_ID)))
	add_header("Platz %d" % slot, "Neuer Spielstand")

	content.add_child(_row_label("Name"))
	_name_edit = LineEdit.new()
	_name_edit.max_length = SaveSlots.NAME_MAX_LENGTH
	_name_edit.placeholder_text = SaveSlots.default_name(slot)
	_name_edit.add_theme_font_size_override("font_size", UiKit.font_px(UiKit.SIZE_CARD_NAME))
	_name_edit.add_theme_color_override("font_color", UiKit.COLOR_TEXT)
	_name_edit.add_theme_color_override("font_placeholder_color", UiKit.COLOR_DISABLED)
	_name_edit.add_theme_color_override("caret_color", UiKit.COLOR_GOLD)
	_name_edit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_name_edit.focus_entered.connect(func() -> void: _set_row(Row.NAME))
	_name_edit.text_submitted.connect(func(_text: String) -> void: confirm())
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_change_rejected.connect(func(_rejected: String) -> void: UiSound.error(self))
	content.add_child(_name_edit)

	content.add_child(_row_label("Charakter"))
	var cards := UiKit.hbox(int(UiKit.px(4)))
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(cards)
	for i in _characters.size():
		cards.add_child(_character_card(i))
	for i in LOCKED_CARDS:
		cards.add_child(_locked_card())
	_character_name = UiKit.text_label("", UiKit.SIZE_CARD_NAME, UiKit.COLOR_TEXT, true)
	_character_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_character_name)
	_character_text = UiKit.wrapped_text("", WIDTH - MenuPanel.PADDING.y * 2.0, UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
	_character_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_character_text)

	content.add_child(_row_label("Farbe"))
	var color_row := UiKit.hbox(int(UiKit.px(6)))
	color_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_swatch_box = UiKit.hbox(int(UiKit.px(SWATCH_GAP)))
	color_row.add_child(_swatch_box)
	_color_name = UiKit.text_label("", UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT, true)
	_color_name.custom_minimum_size.x = UiKit.px(34)
	_color_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	color_row.add_child(_color_name)
	content.add_child(color_row)
	var note := UiKit.text_label(COSMETICS_NOTE, UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(note)

	var actions := UiKit.hbox(int(UiKit.px(6)))
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_start_button = MenuPanel.action_button("Los geht's", "Enter", confirm, true)
	actions.add_child(_start_button)
	actions.add_child(MenuPanel.action_button("Zurück", "Esc", close))
	content.add_child(actions)

	_apply_character()
	_set_row(Row.NAME)
	_name_edit.grab_focus.call_deferred()


## Name as it will be saved (trimmed, default when empty).
func get_profile_name() -> String:
	return SaveSlots.sanitize_name(_name_edit.text, slot)


func set_profile_name(text: String) -> void:
	_name_edit.text = text
	_last_name_length = text.length()


func get_character() -> CharacterData:
	return _characters[_character_index] if not _characters.is_empty() else null


func get_row() -> Row:
	return _row


## Number of character cards including the locked placeholders.
func get_card_count() -> int:
	return _cards.size()


## Number of colour swatches of the current character.
func get_color_count() -> int:
	return _swatches.size()


func get_color_index() -> int:
	return _color_index


## The picked clothing colour (the character's default when nothing else was picked).
func get_color() -> Color:
	var data := get_character()
	if data == null or data.color_choices.is_empty():
		return data.default_color if data != null else Color.WHITE
	return data.color_choices[clampi(_color_index, 0, data.color_choices.size() - 1)]


## Colour to store: transparent while the default is kept (follows the character's default).
func get_saved_color() -> Color:
	var data := get_character()
	if data == null or data.color_choices.is_empty() or _color_index == _default_color_index(data):
		return Color(0, 0, 0, 0)
	return get_color()


func change_character(step: int) -> void:
	if _characters.size() <= 1:
		# Only one character today; the others are "bald".
		UiSound.error(self)
		return
	_character_index = posmod(_character_index + step, _characters.size())
	UiSound.step(self)
	_apply_character()


## Picks colour index (also keys 1–6 and clicks). Returns false if nothing changed.
func pick_color(index: int) -> bool:
	var data := get_character()
	if data == null or index < 0 or index >= data.color_choices.size():
		return false
	if index == _color_index:
		return false
	_color_index = index
	UiSound.toggle(self)
	_apply_color()
	return true


func change_color(step: int) -> void:
	var count := _swatches.size()
	if count > 0:
		pick_color(posmod(_color_index + step, count))


func confirm() -> void:
	var data := get_character()
	if data == null:
		return
	UiSound.play(self, UiSound.CONFIRM)
	confirmed.emit(slot, get_profile_name(), data.id, get_saved_color())


## The name field gets keys before the menu: arrows up/down, Enter and Esc are taken here so typing
## (also W/A/S/D and Space) stays in the field.
func _input(event: InputEvent) -> void:
	if _name_edit == null or not _name_edit.has_focus():
		return
	if event.is_action_pressed(&"ui_up", true) or event.is_action_pressed(&"ui_down", true):
		get_viewport().set_input_as_handled()
		_set_row(Row.START if event.is_action_pressed(&"ui_up", true) else Row.CHARACTER)
		UiSound.hover(self)
	elif MenuInput.is_enter(event):
		get_viewport().set_input_as_handled()
		confirm()
	elif MenuInput.is_back(event):
		get_viewport().set_input_as_handled()
		close()


func handle_input(event: InputEvent) -> bool:
	if MenuInput.is_back(event):
		close()
		return true
	if MenuInput.is_up(event):
		_set_row(posmod(_row - 1, Row.size()) as Row)
		UiSound.hover(self)
		return true
	if MenuInput.is_down(event):
		_set_row(posmod(_row + 1, Row.size()) as Row)
		UiSound.hover(self)
		return true
	if MenuInput.is_left(event) or MenuInput.is_right(event):
		var step := -1 if MenuInput.is_left(event) else 1
		if _row == Row.CHARACTER:
			change_character(step)
		elif _row == Row.COLOR:
			change_color(step)
		return true
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode >= KEY_1 and key.keycode <= KEY_9:
		var index := int(key.keycode - KEY_1)
		if index < _swatches.size():
			_set_row(Row.COLOR)
			pick_color(index)
			return true
	if MenuInput.is_accept(event):
		confirm()
		return true
	return false


func _on_name_changed(text: String) -> void:
	var length := text.length()
	UiSound.type_key(self, length < _last_name_length)
	_last_name_length = length


func _set_row(row: Row) -> void:
	_row = row
	if row == Row.NAME:
		if not _name_edit.has_focus():
			_name_edit.grab_focus()
		_name_edit.caret_column = _name_edit.text.length()
	elif _name_edit.has_focus():
		_name_edit.release_focus()
	for i in _row_labels.size():
		var selected := i == int(row)
		_row_labels[i].add_theme_color_override("font_color", UiKit.COLOR_GOLD if selected else UiKit.COLOR_MUTED)
		_row_labels[i].text = ("> " if selected else "") + String(_row_labels[i].get_meta(&"caption"))
	_name_edit.add_theme_stylebox_override("normal", UiKit.padded_style(&"gold" if row == Row.NAME else &"dark", 3, 5))
	_start_button.add_theme_color_override("font_color", UiKit.COLOR_GOLD if row == Row.START else UiKit.COLOR_TEXT)
	_style_cards()
	_style_swatches()
	set_footer(FOOTER % maxi(1, mini(9, _swatches.size())))


func _apply_character() -> void:
	var data := get_character()
	if data == null:
		return
	_character_name.text = data.display_name
	_character_text.text = data.description
	_color_index = _default_color_index(data)
	_build_swatches(data)
	_style_cards()
	character_changed.emit(data)
	_apply_color()


## Shows the picked colour on the card, in the scene (color_changed) and in the swatch row.
func _apply_color() -> void:
	var data := get_character()
	if data == null:
		return
	var color := get_color()
	if _character_index < _previews.size():
		_previews[_character_index].set_color(color)
	_color_name.text = data.get_color_name(_color_index)
	_style_swatches()
	color_changed.emit(color)


func _default_color_index(data: CharacterData) -> int:
	return data.get_color_index(data.default_color) if not data.color_choices.is_empty() else 0


func _style_cards() -> void:
	for i in _cards.size():
		var kind := &"dark"
		if i == _character_index:
			kind = &"gold" if _row == Row.CHARACTER else &"normal"
		_cards[i].add_theme_stylebox_override("panel", UiKit.padded_style(kind, 3, 3))


func _build_swatches(data: CharacterData) -> void:
	for swatch in _swatches:
		_swatch_box.remove_child(swatch)
		swatch.queue_free()
	_swatches.clear()
	for i in data.color_choices.size():
		var swatch := Button.new()
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.custom_minimum_size = UiKit.pxv(SWATCH_SIZE, SWATCH_SIZE)
		swatch.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		swatch.tooltip_text = "%s [%d]" % [data.get_color_name(i), i + 1]
		# Hover previews the colour (soft tick), leaving shows the picked one again.
		swatch.mouse_entered.connect(func() -> void:
			UiSound.hover(swatch)
			if _character_index < _previews.size():
				_previews[_character_index].set_color(data.color_choices[i])
			color_changed.emit(data.color_choices[i]))
		swatch.mouse_exited.connect(func() -> void:
			if _character_index < _previews.size():
				_previews[_character_index].set_color(get_color())
			color_changed.emit(get_color()))
		swatch.pressed.connect(func() -> void:
			_set_row(Row.COLOR)
			pick_color(i))
		_swatch_box.add_child(swatch)
		_swatches.append(swatch)
	_style_swatches()


func _style_swatches() -> void:
	var data := get_character()
	if data == null:
		return
	for i in _swatches.size():
		var selected := i == _color_index
		var normal := _swatch_style(data.color_choices[i], selected, false)
		for state in ["normal", "pressed", "focus"]:
			_swatches[i].add_theme_stylebox_override(state, normal)
		_swatches[i].add_theme_stylebox_override("hover", _swatch_style(data.color_choices[i], selected, true))


## Square pixel swatch: gold frame when picked (brighter in the colour row), light frame on hover.
func _swatch_style(color: Color, selected: bool, hover: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.anti_aliasing = false
	var frame := UiKit.COLOR_SHADOW
	if selected:
		frame = UiKit.COLOR_GOLD if _row == Row.COLOR else UiKit.COLOR_TEXT_SOFT
	elif hover:
		frame = UiKit.COLOR_TEXT
	style.border_color = frame
	style.set_border_width_all(UiKit.ART_SCALE if selected or hover else maxi(1, UiKit.ART_SCALE - 1))
	return style


func _character_card(index: int) -> PanelContainer:
	var data := _characters[index]
	var card := _card_frame()
	var box := card.get_child(0) as VBoxContainer
	var preview := CharacterPreview.create(PREVIEW_SCALE)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(preview)
	preview.set_character(data, data.default_color)
	_previews.append(preview)
	var name_label := UiKit.text_label(data.display_name, UiKit.SIZE_EYEBROW, UiKit.COLOR_TEXT_SOFT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	box.add_child(name_label)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			if index != _character_index:
				_character_index = index
				_apply_character()
			UiSound.click(self)
			_set_row(Row.CHARACTER))
	return card


## A greyed-out card with the default character as a dark silhouette and "bald".
func _locked_card() -> PanelContainer:
	var card := _card_frame()
	var box := card.get_child(0) as VBoxContainer
	var preview := CharacterPreview.create(PREVIEW_SCALE, false)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	preview.modulate = Color(UiKit.COLOR_SHADOW, 1.0)
	box.add_child(preview)
	var data := CharacterCatalog.get_character(CharacterCatalog.DEFAULT_ID)
	if data != null:
		preview.set_character(data, data.default_color)
		preview.get_sprite().pause()
	var label := UiKit.text_label("bald", UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	card.tooltip_text = "Weitere Charaktere folgen."
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			UiSound.error(self))
	return card


func _card_frame() -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = UiKit.pxv(CARD_SIZE.x, CARD_SIZE.y)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := UiKit.vbox(int(UiKit.px(1)))
	box.alignment = BoxContainer.ALIGNMENT_END
	card.add_child(box)
	_cards.append(card)
	return card


func _row_label(caption: String) -> Label:
	var label := UiKit.eyebrow(caption, UiKit.COLOR_MUTED)
	label.set_meta(&"caption", label.text)
	_row_labels.append(label)
	return label

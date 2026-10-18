class_name ProfileEditor
extends VBoxContainer
## The player's name and look (D-152), one editor for every place: the first start in the main menu
## ("Wie heißt du?", ProfilePanel), "Figur" in the main menu, the lobby (OnlineMenu, own slot
## "Aussehen ändern") and the village (mirror and Zuhause, VillageUI).
## Rows: Name (text field) · Figur (←/→: wick, ember, moss, frost, each with its start colours) ·
## Haare · Kleidung · Haut · Akzent (←/→ or 1–8: palette of PlayerLook) · Speichern. ↑/↓ change the
## row, Enter saves, Esc goes back (not on the first start). Mouse and touch: arrows, swatches and
## buttons are tap targets; the name field opens the on-screen keyboard. Keys come through
## handle_input() from the dialog around it (MenuPanel, Modal.input_handler, OnlineMenu).
## Gamepad (P0-2 step 2): D-pad/stick like the arrows (also out of the name field), A like Enter
## (in the name field too: on the first start an empty name becomes the default name), B like Esc,
## Y types the name on the on-screen keyboard (PadKeyboard, D-192).
## Saving (commit): the profile is written at once; with a live login the change goes to the server
## (OnlineSession.push_profile, PATCH /me). A refused name change ("Namen kannst du in 5 h wieder
## ändern") is shown here and the editor stays open; everything else emits saved.
## Sizes in mockup pixels (UiKit.px), texts are translation keys (D-111).

## Name and look are saved (and sent, if online).
signal saved
signal cancelled
## The shown look changed (pick or hover preview): the main menu recolours its scene figure.
signal look_changed(look: Dictionary)

enum Row { NAME, FIGURE, HAIR, OUTFIT, SKIN, ACCENT, CONFIRM }

const PadKeyboard := preload("res://ui/widgets/pad_keyboard.gd")

const ROW_SLOTS := {
	Row.HAIR: PlayerLook.HAIR, Row.OUTFIT: PlayerLook.OUTFIT, Row.SKIN: PlayerLook.SKIN, Row.ACCENT: PlayerLook.ACCENT,
}
const DEFAULT_WIDTH := 250.0
## Mockup pixels: caption column, swatch size and gap, arrow buttons, figure column.
const CAPTION_WIDTH := 40.0
const SWATCH_SIZE := 10.0
const SWATCH_GAP := 2.0
const ARROW_WIDTH := 10.0
const FIGURE_WIDTH := 78.0
## Whole-number art scale of the preview figure (32 px frames).
const PREVIEW_SCALE := 4

## First start: no way back, the button says "Los geht's".
var first_start := false
## Show "Zurück" (the village's Zuhause dialog has its own close button).
var show_cancel := true
var width := DEFAULT_WIDTH
var row := Row.NAME
var look: Dictionary = PlayerLook.default_look()

var _initial_name := ""
var _name_edit: LineEdit = null
var _last_name_length := 0
var _preview: CharacterPreview = null
var _figure_name: Label = null
var _figure_text: Label = null
var _captions: Dictionary = {}
var _swatches: Dictionary = {}
var _color_name: Label = null
var _message: Label = null
var _confirm_button: Button = null
var _cancel_button: Button = null
var _busy := false
## Swatch under the mouse ([slot, index]) for the hover preview, [] if none.
var _hover: Array = []


## initial_name: the current name ("" on the first start; the field shows the default then).
static func create(initial_name: String, initial_look: Dictionary, is_first_start := false, spec_width := DEFAULT_WIDTH) -> ProfileEditor:
	var editor := ProfileEditor.new()
	editor.name = "ProfileEditor"
	editor._initial_name = initial_name
	editor.look = PlayerLook.normalize(initial_look)
	editor.first_start = is_first_start
	editor.width = spec_width
	return editor


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_constant_override("separation", int(UiKit.px(4)))
	custom_minimum_size.x = UiKit.px(width)
	_build_name_row()
	var columns := UiKit.hbox(int(UiKit.px(6)))
	columns.add_child(_build_figure_column())
	columns.add_child(_build_color_column())
	add_child(columns)
	_message = UiKit.wrapped_text("", width, UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
	_message.name = "Message"
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.visible = false
	add_child(_message)
	var actions := UiKit.hbox(int(UiKit.px(6)))
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_confirm_button = MenuPanel.action_button(&"PROFILE_START" if first_start else &"PROFILE_SAVE", "Enter", confirm, true)
	_confirm_button.name = "SaveProfile"
	actions.add_child(_confirm_button)
	if show_cancel and not first_start:
		_cancel_button = MenuPanel.action_button(&"COMMON_BACK", "Esc", cancel)
		_cancel_button.name = "CancelProfile"
		actions.add_child(_cancel_button)
	add_child(actions)
	_apply_look()
	_set_row(Row.NAME)
	if is_visible_in_tree():
		_name_edit.grab_focus.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _confirm_button != null:
		_set_row(row)
		_apply_look()


# --- State ---

## The name as it will be saved (cleaned; "" if the field is empty).
func get_player_name() -> String:
	return PlayerProfile.sanitize_name(_name_edit.text) if _name_edit != null else PlayerProfile.sanitize_name(_initial_name)


func set_player_name(text: String) -> void:
	_name_edit.text = text
	_last_name_length = text.length()


func get_look() -> Dictionary:
	return look.duplicate(true)


func get_row() -> Row:
	return row


func is_busy() -> bool:
	return _busy


func get_message() -> String:
	return _message.text if _message != null and _message.visible else ""


## A line under the editor (errors in red), "" hides it.
func set_message(text: String, is_error := false) -> void:
	_message.text = text
	_message.visible = not text.is_empty()
	_message.add_theme_color_override("font_color", UiKit.COLOR_DANGER_SOFT if is_error else UiKit.COLOR_MUTED)


## Next or previous figure; it comes in its own start colours (PlayerLook.CHARACTER_DEFAULTS).
func change_character(step: int) -> void:
	var characters := PlayerLook.CHARACTERS
	var index := characters.find(PlayerLook.get_character(look))
	look = PlayerLook.with_character(look, characters[posmod(index + step, characters.size())])
	UiSound.step(self)
	_apply_look()


## Picks palette index of slot. Returns false if nothing changed.
func pick_color(slot: StringName, index: int) -> bool:
	if index < 0 or index >= PlayerLook.COLOR_COUNT or PlayerLook.get_index(look, slot) == index:
		return false
	look = PlayerLook.with_color(look, slot, index)
	UiSound.toggle(self)
	_apply_look()
	return true


func change_color(slot: StringName, step: int) -> void:
	pick_color(slot, posmod(PlayerLook.get_index(look, slot) + step, PlayerLook.COLOR_COUNT))


## Saves name and look (and sends them if online). A too short name stays here with a hint.
func confirm() -> void:
	if _busy:
		return
	var player_name := get_player_name()
	if player_name.is_empty() and first_start:
		# Controller only, no keyboard: the first start still goes on, the name can change later.
		player_name = tr(&"PROFILE_DEFAULT_NAME")
		set_player_name(player_name)
	if player_name.length() < PlayerProfile.NAME_MIN_LENGTH:
		UiSound.error(self)
		set_message(tr(&"PROFILE_NAME_TOO_SHORT") % PlayerProfile.NAME_MIN_LENGTH, true)
		_set_row(Row.NAME)
		return
	UiSound.play(self, UiSound.CONFIRM)
	_set_busy(true)
	var hint := await commit(self, player_name, look)
	if not is_inside_tree():
		return
	_set_busy(false)
	if hint.is_empty():
		saved.emit()
		return
	# The server kept the old name: show it again, the look is saved.
	set_player_name(PlayerProfile.current().player_name)
	set_message(hint, true)


func cancel() -> void:
	if first_start or _busy:
		return
	UiSound.back(self)
	cancelled.emit()


## Writes the profile and, with a live login, sends it (PATCH /me). Returns a hint for the player
## ("" = all fine, also offline: then it goes out with the next login).
static func commit(node: Node, player_name: String, new_look: Dictionary) -> String:
	var profile := PlayerProfile.current()
	if not profile.complete_setup(player_name, new_look):
		return Loc.t(&"PROFILE_NAME_TOO_SHORT", [PlayerProfile.NAME_MIN_LENGTH])
	var session := _live_session(node)
	if session == null:
		return ""
	var result := await session.push_profile()
	return OnlineSession.profile_hint(result)


static func _live_session(node: Node) -> OnlineSession:
	if node == null or not node.is_inside_tree():
		return null
	var session := node.get_tree().get_first_node_in_group(OnlineSession.GROUP) as OnlineSession
	return session if session != null and session.is_logged_in() else null


# --- Keys ---

## Keys of the dialog around the editor. true = used.
func handle_input(event: InputEvent) -> bool:
	if _busy:
		return event.is_action_type()
	if MenuInput.is_back(event):
		cancel()
		return true
	if PadKeyboard.is_open_event(event):
		open_keyboard()
		return true
	if _name_edit.has_focus():
		# Typing stays in the field; _input handles arrows, Enter and Esc there.
		return false
	if MenuInput.is_up(event):
		_set_row(posmod(row - 1, Row.size()) as Row)
		UiSound.hover(self)
		return true
	if MenuInput.is_down(event):
		_set_row(posmod(row + 1, Row.size()) as Row)
		UiSound.hover(self)
		return true
	if MenuInput.is_left(event) or MenuInput.is_right(event):
		var step := -1 if MenuInput.is_left(event) else 1
		if row == Row.FIGURE:
			change_character(step)
		elif ROW_SLOTS.has(row):
			change_color(ROW_SLOTS[row], step)
		return true
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode >= KEY_1 and key.keycode <= KEY_8 and ROW_SLOTS.has(row):
		pick_color(ROW_SLOTS[row], int(key.keycode - KEY_1))
		return true
	if MenuInput.is_accept(event):
		if row == Row.NAME:
			_set_row(Row.NAME)
		else:
			confirm()
		return true
	return false


## The name field gets keys before the dialog: arrows up/down, Enter and Esc are taken here so typing
## (also W/A/S/D and Space) stays in the field.
func _input(event: InputEvent) -> void:
	if _name_edit == null or not _name_edit.has_focus() or not is_visible_in_tree():
		return
	# Arrows, D-pad and stick only (W/A/S/D are letters of the name here).
	var direction := MenuInput.direction(event, false)
	if direction == Vector2i.UP or direction == Vector2i.DOWN:
		get_viewport().set_input_as_handled()
		_set_row(Row.CONFIRM if direction == Vector2i.UP else Row.FIGURE)
		UiSound.hover(self)
	elif PadKeyboard.is_open_event(event):
		get_viewport().set_input_as_handled()
		open_keyboard()
	elif MenuInput.is_confirm(event):
		get_viewport().set_input_as_handled()
		confirm()
	elif MenuInput.is_back(event):
		get_viewport().set_input_as_handled()
		if first_start:
			_set_row(Row.FIGURE)
		else:
			cancel()


## The name row with the on-screen keyboard over it (gamepad Y, from any row).
func open_keyboard() -> Modal:
	if _busy or _name_edit == null:
		return null
	_set_row(Row.NAME)
	return PadKeyboard.open_for(_name_edit)


# --- Building ---

func _build_name_row() -> void:
	var name_row := UiKit.hbox(int(UiKit.px(4)))
	var caption := _caption(Row.NAME, &"PROFILE_NAME")
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_row.add_child(caption)
	_name_edit = LineEdit.new()
	_name_edit.name = "NameEdit"
	_name_edit.max_length = PlayerProfile.NAME_MAX_LENGTH
	_name_edit.placeholder_text = tr(&"PROFILE_NAME_PLACEHOLDER")
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.add_theme_font_size_override("font_size", UiKit.font_px(UiKit.SIZE_CARD_NAME))
	_name_edit.add_theme_color_override("font_color", UiKit.COLOR_TEXT)
	_name_edit.add_theme_color_override("font_placeholder_color", UiKit.COLOR_DISABLED)
	_name_edit.add_theme_color_override("caret_color", UiKit.COLOR_GOLD)
	_name_edit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_name_edit.text = _initial_name
	_last_name_length = _initial_name.length()
	_name_edit.focus_entered.connect(func() -> void:
		if row != Row.NAME:
			_set_row(Row.NAME))
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_change_rejected.connect(func(_rejected: String) -> void: UiSound.error(self))
	name_row.add_child(_name_edit)
	add_child(name_row)


func _build_figure_column() -> Control:
	var column := UiKit.vbox(int(UiKit.px(2)))
	column.custom_minimum_size.x = UiKit.px(FIGURE_WIDTH)
	var stage := UiKit.panel(&"dark")
	stage.name = "FigureStage"
	stage.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview = CharacterPreview.create(PREVIEW_SCALE)
	_preview.name = "Preview"
	_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stage.add_child(_preview)
	stage.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			_set_row(Row.FIGURE))
	column.add_child(stage)
	var picker := UiKit.hbox(int(UiKit.px(2)))
	picker.alignment = BoxContainer.ALIGNMENT_CENTER
	picker.add_child(_arrow("PrevFigure", "‹", func() -> void:
		_set_row(Row.FIGURE)
		change_character(-1)))
	_figure_name = UiKit.text_label("", UiKit.SIZE_CARD_NAME, UiKit.COLOR_TEXT, true)
	_figure_name.name = "FigureName"
	_figure_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_figure_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_figure_name.clip_text = true
	picker.add_child(_figure_name)
	picker.add_child(_arrow("NextFigure", "›", func() -> void:
		_set_row(Row.FIGURE)
		change_character(1)))
	column.add_child(picker)
	_captions[Row.FIGURE] = _figure_name
	_figure_text = UiKit.wrapped_text("", FIGURE_WIDTH, UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
	_figure_text.name = "FigureText"
	_figure_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_figure_text)
	return column


func _build_color_column() -> Control:
	var column := UiKit.vbox(int(UiKit.px(3)))
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	for row_id: int in [Row.HAIR, Row.OUTFIT, Row.SKIN, Row.ACCENT]:
		var slot: StringName = ROW_SLOTS[row_id]
		var line := UiKit.hbox(int(UiKit.px(2)))
		line.name = "Row_%s" % slot
		var caption := _caption(row_id, PlayerLook.slot_name_key(slot))
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(caption)
		line.add_child(_arrow("Prev_%s" % slot, "‹", func() -> void:
			_set_row(row_id as Row)
			change_color(slot, -1)))
		var swatch_box := UiKit.hbox(int(UiKit.px(SWATCH_GAP)))
		var swatches: Array[Button] = []
		for i in PlayerLook.COLOR_COUNT:
			var swatch := _swatch(row_id as Row, slot, i)
			swatch_box.add_child(swatch)
			swatches.append(swatch)
		_swatches[slot] = swatches
		line.add_child(swatch_box)
		line.add_child(_arrow("Next_%s" % slot, "›", func() -> void:
			_set_row(row_id as Row)
			change_color(slot, 1)))
		column.add_child(line)
	_color_name = UiKit.text_label("", UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT)
	_color_name.name = "ColorName"
	_color_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_color_name)
	return column


func _swatch(row_id: Row, slot: StringName, index: int) -> Button:
	var swatch := Button.new()
	swatch.name = "Swatch_%s_%d" % [slot, index]
	swatch.focus_mode = Control.FOCUS_NONE
	swatch.custom_minimum_size = UiKit.pxv(SWATCH_SIZE, SWATCH_SIZE)
	swatch.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	swatch.tooltip_text = "%s [%d]" % [tr(PlayerLook.color_name_key(slot, index)), index + 1]
	swatch.mouse_entered.connect(func() -> void:
		UiSound.hover(swatch)
		_hover = [slot, index]
		_show_preview())
	swatch.mouse_exited.connect(func() -> void:
		_hover = []
		_show_preview())
	swatch.pressed.connect(func() -> void:
		_set_row(row_id)
		pick_color(slot, index))
	return swatch


func _arrow(node_name: String, text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = UiKit.pxv(ARROW_WIDTH, SWATCH_SIZE)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", UiKit.font_px(UiKit.SIZE_CARD_NAME))
	button.add_theme_color_override("font_color", UiKit.COLOR_MUTED)
	button.add_theme_color_override("font_hover_color", UiKit.COLOR_GOLD)
	button.pressed.connect(on_pressed)
	return button


## caption_key: translation key; gold with the "> " cursor when its row is selected.
func _caption(row_id: Row, caption_key: StringName) -> Label:
	var label := UiKit.eyebrow(caption_key, UiKit.COLOR_MUTED)
	label.uppercase = true
	label.custom_minimum_size.x = UiKit.px(CAPTION_WIDTH)
	label.set_meta(&"caption", caption_key)
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			_set_row(row_id))
	_captions[row_id] = label
	return label


# --- Showing ---

func _on_name_changed(text: String) -> void:
	var length := text.length()
	UiSound.type_key(self, length < _last_name_length)
	_last_name_length = length
	if not get_message().is_empty():
		set_message("")


func _set_busy(busy: bool) -> void:
	_busy = busy
	_confirm_button.disabled = busy
	if _cancel_button != null:
		_cancel_button.disabled = busy
	_name_edit.editable = not busy
	if busy:
		set_message(tr(&"PROFILE_SAVING"))


func _set_row(new_row: Row) -> void:
	row = new_row
	if _name_edit == null:
		return
	if row == Row.NAME:
		if not _name_edit.has_focus() and is_visible_in_tree():
			_name_edit.grab_focus()
		_name_edit.caret_column = _name_edit.text.length()
	elif _name_edit.has_focus():
		_name_edit.release_focus()
	for row_id: int in _captions:
		var label: Label = _captions[row_id]
		var selected := row_id == row
		if row_id == Row.FIGURE:
			label.add_theme_color_override("font_color", UiKit.COLOR_GOLD if selected else UiKit.COLOR_TEXT)
			continue
		label.add_theme_color_override("font_color", UiKit.COLOR_GOLD if selected else UiKit.COLOR_MUTED)
		label.text = ("> " if selected else "") + tr(label.get_meta(&"caption") as StringName)
	_name_edit.add_theme_stylebox_override("normal", UiKit.padded_style(&"gold" if row == Row.NAME else &"dark", 2, 4))
	_confirm_button.add_theme_color_override("font_color", UiKit.COLOR_GOLD if row == Row.CONFIRM else UiKit.COLOR_TEXT)
	_style_swatches()
	_show_color_name()


func _apply_look() -> void:
	var data := CharacterCatalog.get_character(PlayerLook.get_character(look))
	if data != null:
		_figure_name.text = tr(data.display_name)
		_figure_text.text = tr(data.description)
	_style_swatches()
	_show_color_name()
	_show_preview()


## The figure with the hovered colour (or the picked look); tells the main menu too.
func _show_preview() -> void:
	var shown := look
	if not _hover.is_empty():
		shown = PlayerLook.with_color(look, _hover[0], _hover[1])
	_preview.set_look(shown)
	look_changed.emit(shown)


func _show_color_name() -> void:
	if _color_name == null:
		return
	if ROW_SLOTS.has(row):
		var slot: StringName = ROW_SLOTS[row]
		_color_name.text = "%s · %s" % [tr(PlayerLook.slot_name_key(slot)), tr(PlayerLook.color_name_key(slot, PlayerLook.get_index(look, slot)))]
	else:
		_color_name.text = tr(&"PROFILE_COLOR_HINT")


func _style_swatches() -> void:
	for slot: StringName in _swatches:
		var picked := PlayerLook.get_index(look, slot)
		var active: bool = ROW_SLOTS.get(row, &"") == slot
		var buttons: Array[Button] = _swatches[slot]
		for i in buttons.size():
			var color := PlayerLook.color_of(slot, i)
			var normal := _swatch_style(color, i == picked, active, false)
			for state in ["normal", "pressed", "focus", "disabled"]:
				buttons[i].add_theme_stylebox_override(state, normal)
			buttons[i].add_theme_stylebox_override("hover", _swatch_style(color, i == picked, active, true))


## Square pixel swatch: gold frame when picked in the active row, light frame when picked elsewhere
## or hovered.
func _swatch_style(color: Color, picked: bool, active: bool, hover: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.anti_aliasing = false
	var frame := UiKit.COLOR_SHADOW
	if picked:
		frame = UiKit.COLOR_GOLD if active else UiKit.COLOR_TEXT_SOFT
	elif hover:
		frame = UiKit.COLOR_TEXT
	style.border_color = frame
	style.set_border_width_all(UiKit.ART_SCALE - 1 if picked or hover else 1)
	return style

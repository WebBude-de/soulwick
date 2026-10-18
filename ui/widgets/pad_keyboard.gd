extends Modal
## On-screen keyboard for the gamepad (D-192): a text field (LineEdit or TextEdit) gets letters
## without a real keyboard, e.g. the player's name, a world name or a bug report on a Steam Deck or
## a PC with only a pad. Hosts open it with Y while their field is in use (is_open_event,
## open_for); it types straight into the field, so nothing has to be copied back.
## Keys: D-pad/stick move the gold focus frame over the keys (Modal), A types the framed key,
## X deletes, Y types a space, LB switches capitals, Start or B close it (the text stays). The mouse
## can click the keys as well; touch devices keep their own on-screen keyboard and never open this.
## Capitals: the first letter of an empty field and after a space is a capital once (names), LB
## switches by hand.
## Sits on its own CanvasLayer as the last child of the root, so it reads the gamepad in _input
## before every menu and overlay (reverse tree order) and swallows its events; it does not pause
## the game (its host already did, if needed).
## Use: const PadKeyboard := preload("res://ui/widgets/pad_keyboard.gd") (no class_name: loaded by
## path like PadNav); if PadKeyboard.is_open_event(event): PadKeyboard.open_for(field).

signal text_typed(text: String)

const KeyLineScript := preload("res://ui/widgets/key_line.gd")
## Above every menu and the bug report overlay (DevFeedbackOverlay.LAYER 120).
const LAYER := 126
## Key rows per language (German QWERTZ with umlauts, else QWERTY); the last row is built in code.
## Letters, not texts: the umlauts are escaped so the text check (tools/i18n_check.py) skips them.
const ROWS := {
	&"de": ["1234567890", "qwertzuiop\u00fc", "asdfghjkl\u00f6\u00e4", "yxcvbnm\u00df-."],
	&"en": ["1234567890", "qwertyuiop", "asdfghjkl'", "zxcvbnm-.!"],
}
## Key size and gap in mockup pixels.
const KEY_SIZE := Vector2(14, 13)
const KEY_GAP := 2.0
const WIDE_KEY_WIDTH := 44.0
const PANEL_WIDTH := 210.0
const META_CHARACTER: StringName = &"pad_character"

## The field the keyboard types into (LineEdit or TextEdit).
var field: Control = null
## Capitals for the next letter (once) or on (locked by hand with LB).
var shift := false
var shift_locked := false

var _preview: Label = null
var _count: Label = null
var _letter_keys: Array[Button] = []
var _shift_key: Button = null
var _keys_line: VBoxContainer = null
var _layer: CanvasLayer = null
## finish(null) bound once, connected to the field's tree_exiting while open.
var _close_with_field: Callable = Callable()


## The event that opens the keyboard over a focused text field: Y on a gamepad.
static func is_open_event(event: InputEvent) -> bool:
	return MenuInput.is_pad_button(event, JOY_BUTTON_Y)


## Opens the keyboard for field (LineEdit or TextEdit) on top of everything; null without a usable
## field. The field gives up its GUI focus while the keyboard is open and gets it back afterwards.
static func open_for(target: Control) -> Modal:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return null
	if not (target is LineEdit or target is TextEdit):
		return null
	var open := get_open()
	if open != null:
		return open
	var keyboard: Modal = (load("res://ui/widgets/pad_keyboard.gd") as GDScript).new()
	keyboard.set(&"field", target)
	keyboard.call(&"_open")
	return keyboard


## The keyboard open right now (null if none), for hosts and tests.
static func get_open() -> Modal:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	for child in tree.root.get_children():
		if child is CanvasLayer and child.name == "PadKeyboardLayer":
			for modal in child.get_children():
				if modal is Modal and not modal.is_queued_for_deletion():
					return modal
	return null


func _init() -> void:
	pause_reason = &"pad_keyboard"
	pauses = false
	_build(&"normal")
	name = "PadKeyboard"
	cancel_allowed = true
	pad_accept_guard = 0.0
	input_guard = 0.1


func _open() -> void:
	set_width(PANEL_WIDTH)
	_build_keys()
	shift = _wants_capital()
	_refresh()
	_layer = CanvasLayer.new()
	_layer.name = "PadKeyboardLayer"
	_layer.layer = LAYER
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	field.get_tree().root.add_child(_layer)
	if field.has_focus():
		field.release_focus()
	finished.connect(_on_closed)
	# The menu with the field closes (or the world goes): the keyboard goes with it.
	_close_with_field = finish.bind(null)
	field.tree_exiting.connect(_close_with_field, CONNECT_ONE_SHOT)
	show_on(_layer)
	focus_button(_letter_keys[0] if not _letter_keys.is_empty() else null)


# --- Typing ---

## Types text at the caret (capitals while shift is on; a once-shift goes off after a letter).
func type_text(text: String) -> void:
	if not is_instance_valid(field):
		return
	var typed := text.to_upper() if shift else text
	var before := get_text()
	if field is LineEdit:
		var edit := field as LineEdit
		edit.insert_text_at_caret(typed)
		if edit.text != before:
			# insert_text_at_caret does not emit it; hosts tick and check the name on it.
			edit.text_changed.emit(edit.text)
	elif field is TextEdit:
		(field as TextEdit).insert_text_at_caret(typed)
	if get_text() == before:
		UiSound.error(self)
	elif typed.strip_edges() != "" and shift and not shift_locked:
		shift = false
	if text == " ":
		shift = shift_locked or _wants_capital()
	_refresh()
	text_typed.emit(get_text())


## Deletes the character before the caret.
func backspace() -> void:
	if not is_instance_valid(field):
		return
	if get_text().is_empty():
		UiSound.error(self)
		return
	if field is LineEdit:
		(field as LineEdit).delete_char_at_caret()
	elif field is TextEdit:
		(field as TextEdit).backspace()
	if not shift_locked:
		shift = _wants_capital()
	_refresh()
	text_typed.emit(get_text())


## LB / the "Aa" key: capitals on (locked) or off.
func toggle_shift() -> void:
	shift_locked = not (shift or shift_locked)
	shift = shift_locked
	UiSound.hover(self)
	_refresh()


## Text of the field right now.
func get_text() -> String:
	if field is LineEdit:
		return (field as LineEdit).text
	if field is TextEdit:
		return (field as TextEdit).text
	return ""


## The key with this character (lower case), null if the layout has none (tests, tools).
func get_key(character: String) -> Button:
	for key in _letter_keys:
		if String(key.get_meta(META_CHARACTER, "")) == character:
			return key
	return null


## A capital comes next: empty field or right after a space (names start with one).
func _wants_capital() -> bool:
	var text := get_text()
	return text.is_empty() or text.ends_with(" ")


# --- Input ---

## The gamepad (and the repeat steps of a held D-pad) is read here, before every other menu, and
## swallowed; mouse and touch go on to the key buttons. A real key closes the keyboard and goes on
## to the field.
func _input(event: InputEvent) -> void:
	if _done or not is_inside_tree():
		return
	if event is InputEventKey:
		if event.is_pressed() and not event.is_echo():
			finish(null)
		return
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventAction):
		return
	get_viewport().set_input_as_handled()
	if is_input_guarded():
		if MenuInput.is_pad_direction_event(event):
			MenuInput.direction(event)
		return
	handle_pad(event)


## One gamepad event (or a ui_* repeat step); true when it did something.
func handle_pad(event: InputEvent) -> bool:
	var step := MenuInput.direction(event, false)
	if step != Vector2i.ZERO:
		return move_focus(step)
	if MenuInput.is_pad_accept(event) or (event is InputEventAction and event.is_action_pressed(&"ui_accept")):
		return press_focused()
	if MenuInput.is_pad_button(event, JOY_BUTTON_X):
		backspace()
		return true
	if MenuInput.is_pad_button(event, JOY_BUTTON_Y):
		type_text(" ")
		return true
	if MenuInput.is_pad_button(event, JOY_BUTTON_LEFT_SHOULDER):
		toggle_shift()
		return true
	if MenuInput.is_pad_button(event, JOY_BUTTON_START) or MenuInput.is_pad_back(event):
		UiSound.back(self)
		finish(null)
		return true
	return false


func _on_closed(_result: Variant) -> void:
	if is_instance_valid(field) and field.tree_exiting.is_connected(_close_with_field):
		field.tree_exiting.disconnect(_close_with_field)
	if is_instance_valid(field) and field.is_inside_tree() and field.is_visible_in_tree() and field.focus_mode != Control.FOCUS_NONE:
		field.grab_focus()
		if field is LineEdit:
			(field as LineEdit).caret_column = (field as LineEdit).text.length()
	if is_instance_valid(_layer):
		_layer.queue_free()


# --- Building ---

func _build_keys() -> void:
	var title := UiKit.eyebrow(Loc.t(&"PAD_KEYBOARD_TITLE"), UiKit.COLOR_GOLD)
	title.uppercase = true
	content.add_child(title)
	var preview_box := UiKit.panel(&"dark")
	preview_box.add_theme_stylebox_override("panel", UiKit.padded_style(&"dark", 2, 4))
	var preview_row := UiKit.hbox(int(UiKit.px(4)))
	preview_box.add_child(preview_row)
	_preview = UiKit.text_label("", UiKit.SIZE_CARD_NAME, UiKit.COLOR_TEXT, true)
	_preview.name = "Preview"
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.clip_text = true
	_preview.text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
	preview_row.add_child(_preview)
	_count = UiKit.text_label("", UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
	_count.name = "Count"
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_row.add_child(_count)
	content.add_child(preview_box)
	var rows: Array = ROWS.get(Loc.current_language(), ROWS[&"en"])
	var grid := UiKit.vbox(int(UiKit.px(KEY_GAP)))
	grid.name = "Keys"
	for row_text: String in rows:
		var row := UiKit.hbox(int(UiKit.px(KEY_GAP)))
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		for character in row_text:
			var key := _key(character, KEY_SIZE.x, type_text.bind(character))
			key.set_meta(META_CHARACTER, character)
			_letter_keys.append(key)
			row.add_child(key)
		grid.add_child(row)
	var last := UiKit.hbox(int(UiKit.px(KEY_GAP)))
	last.alignment = BoxContainer.ALIGNMENT_CENTER
	_shift_key = _key("Aa", KEY_SIZE.x * 2.0, toggle_shift)
	_shift_key.name = "Shift"
	last.add_child(_shift_key)
	var space := _key(Loc.t(&"PAD_KEYBOARD_SPACE"), WIDE_KEY_WIDTH, type_text.bind(" "))
	space.name = "Space"
	last.add_child(space)
	var delete := _key(Loc.t(&"PAD_KEYBOARD_DELETE"), WIDE_KEY_WIDTH, backspace)
	delete.name = "Delete"
	last.add_child(delete)
	var done := _key(Loc.t(&"PAD_KEYBOARD_DONE"), WIDE_KEY_WIDTH, func() -> void: finish(null))
	done.name = "Done"
	done.add_theme_color_override("font_color", UiKit.COLOR_GOLD)
	last.add_child(done)
	grid.add_child(last)
	content.add_child(grid)
	_keys_line = KeyLineScript.new()
	_keys_line.call(&"setup", UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
	_keys_line.call(&"set_texts", &"PAD_KEYBOARD_KEYS", &"PAD_KEYBOARD_KEYS_PAD")
	content.add_child(_keys_line)



func _key(text: String, width: float, on_pressed: Callable) -> Button:
	var key := UiKit.button(text, on_pressed)
	key.name = "Key%d" % _letter_keys.size()
	key.custom_minimum_size = UiKit.pxv(width, KEY_SIZE.y)
	key.add_theme_font_size_override("font_size", UiKit.font_px(UiKit.SIZE_KEY_HINT))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var kind := &"button_hover" if state == "hover" or state == "pressed" else (&"button_disabled" if state == "disabled" else &"button")
		key.add_theme_stylebox_override(state, UiKit.padded_style(kind, 0, 1))
	key.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return key


## Preview with a caret, the letter count, and the letters in capitals while shift is on.
func _refresh() -> void:
	if _preview == null:
		return
	var text := get_text()
	_preview.text = text.replace("\n", " ") + "_"
	var limit := (field as LineEdit).max_length if field is LineEdit else 0
	_count.text = "%d/%d" % [text.length(), limit] if limit > 0 else ""
	for key in _letter_keys:
		var character := String(key.get_meta(META_CHARACTER, ""))
		key.text = character.to_upper() if shift else character
	if _shift_key != null:
		_shift_key.add_theme_color_override("font_color", UiKit.COLOR_GOLD if shift else UiKit.COLOR_TEXT)

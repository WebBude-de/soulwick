class_name DevFeedbackOverlay
extends CanvasLayer
## Full-screen bug report overlay (DevFeedback, # / F9 or the touch button): shows the frozen
## screenshot, lets the player drag numbered rectangles, type a shared note and one short note per
## rectangle, then send (Ctrl+Enter / "Senden") or discard (Esc / "Abbrechen"). Two tabs at the top
## of the panel pick the kind: "Fehler melden" (bug, always the default) or "Idee einreichen" (idea);
## both work the same, only title and placeholder differ. No categories (17.10.2026): where the
## report was made is read automatically (DevFeedbackContext).
## Desktop: left mouse drags a rectangle, Shift + drag draws a free stroke, right click removes the
## mark under the cursor. Touch (touch_mode, phones): a finger drags a rectangle, a long press on a
## mark removes it, the text fields open the on-screen keyboard (the panel moves above it) and the
## buttons replace the shortcuts. Ctrl+Tab switches the tab. Gamepad: LB/RB switch the tab, Start
## sends, B cancels (twice when something is written, like Esc).
## Every text is a translation key with fallback (DevFeedbackTexts, D-111); auto_translate is off so
## no other text is ever looked up as a key. One line tells the player what is sent to the developer team;
## before the very first send (needs_consent) a short notice has to be confirmed once.
## All input is swallowed while it is open: the GUI consumes mouse and focused text input, every
## other key is marked handled, so nothing reaches the game (no attack, no pause menu).

signal submitted(note: Dictionary)
signal cancelled
## The player confirmed the privacy notice (DevFeedback remembers it).
signal consent_given

const LAYER := 120
## Report kinds (contract field `kind`), in the order of the tabs; the first is the default.
const KINDS: Array[String] = ["bug", "idea"]
## Minimum height of a tab on phones (view pixels), large enough for a thumb.
const TAB_HEIGHT_TOUCH := 46.0
## Smaller drags are taken as clicks, not as rectangles (view pixels).
const MIN_RECT := 6.0
const STROKE_STEP := 3.0
const REMOVE_STROKE_DISTANCE := 10.0
## A second Esc within this time discards a note that already has content.
const CANCEL_CONFIRM_MSEC := 2000
const PANEL_HEIGHT := 196.0
## Phone layout: larger text and panel.
const PANEL_HEIGHT_TOUCH := 244.0
const FONT_SIZE_TOUCH := 21
## A finger resting this long without moving removes the mark under it.
const LONG_PRESS_MSEC := 550
## A finger that moved less than this (view pixels) still counts as resting.
const LONG_PRESS_MOVE := 14.0

const COLOR_MARK := Color(1.0, 0.16, 0.12, 1.0)
const COLOR_MARK_FILL := Color(1.0, 0.16, 0.12, 0.18)
const COLOR_DRAFT := Color(1.0, 0.55, 0.45, 1.0)
const COLOR_STROKE := Color(1.0, 0.85, 0.2, 1.0)
const COLOR_PANEL := Color(0.07, 0.06, 0.1, 0.94)
const COLOR_TEXT := Color("#e9e4d2")
const COLOR_MUTED := Color("#b9b3c9")
const COLOR_ACCENT := Color("#f2cf4a")
const FONT_SIZE := 15

## Marks in view coordinates: [{rect: Rect2, note: String}]; number = index + 1.
var marks: Array[Dictionary] = []
var strokes: Array[PackedVector2Array] = []
## Phone layout and finger input (set before the overlay enters the tree).
var touch_mode := false
## The privacy notice has to be confirmed before this send (first report of the installation).
var needs_consent := false
## "bug" or "idea" (KINDS); set_kind() keeps tabs, title and placeholder in step.
var kind := "bug"
## A gamepad was the last input: the status line names the pad buttons (set before _ready, and
## switched on by the first pad button).
var pad_mode := false

var _texture: Texture2D = null
var _view_size := Vector2(1280, 720)
var _root: Control
var _canvas: Control
var _panel: PanelContainer
var _text: TextEdit
var _mark_box: VBoxContainer
var _mark_hint: Label
var _status: Label
var _side_button: Button
var _header: Label
var _kind_buttons: Dictionary[String, Button] = {}
var _panel_on_top := false
var _drag_mode := 0  # 0 none, 1 rectangle, 2 stroke
var _drag_start := Vector2.ZERO
var _drag_rect := Rect2()
var _cancel_armed_at := -100000
var _finished := false
var _touch_finger := -1
var _touch_start := Vector2.ZERO
var _touch_start_msec := 0
var _touch_moved := false
## How far the panel is lifted above the on-screen keyboard (view pixels).
var _keyboard_lift := 0.0
var _consent: Control = null


## image: the frozen frame; view_size: canvas size of the root viewport.
func setup(image: Image, view_size: Vector2) -> void:
	if image != null and not image.is_empty():
		_texture = ImageTexture.create_from_image(image)
	if view_size.x > 0.0 and view_size.y > 0.0:
		_view_size = view_size


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	# On a phone the keyboard would cover the screenshot at once: the player taps the field.
	if not touch_mode:
		_text.grab_focus.call_deferred()


func _process(_delta: float) -> void:
	if touch_mode:
		check_long_press(Time.get_ticks_msec())
	_follow_keyboard()


# --- public API (also used by the tests) -------------------------------------------------------

func mark_count() -> int:
	return marks.size()


func get_mark_rect(index: int) -> Rect2:
	return marks[index]["rect"] if index >= 0 and index < marks.size() else Rect2()


## Adds a rectangle (view coordinates); returns its number (1-based).
func add_mark(rect: Rect2, note := "") -> int:
	marks.append({"rect": rect.abs(), "note": note})
	_rebuild_mark_list()
	_canvas.queue_redraw()
	return marks.size()


## Removes the topmost mark containing point, else a stroke passing near it.
func remove_mark_at(point: Vector2) -> bool:
	for i in range(marks.size() - 1, -1, -1):
		if (marks[i]["rect"] as Rect2).grow(2.0).has_point(point):
			marks.remove_at(i)
			_rebuild_mark_list()
			_canvas.queue_redraw()
			return true
	for i in range(strokes.size() - 1, -1, -1):
		for p in strokes[i]:
			if p.distance_to(point) <= REMOVE_STROKE_DISTANCE:
				strokes.remove_at(i)
				_canvas.queue_redraw()
				return true
	return false


func set_mark_note(index: int, note: String) -> void:
	if index < 0 or index >= marks.size():
		return
	marks[index]["note"] = note
	var edits := _mark_box.get_children()
	if index < edits.size():
		var edit := edits[index].get_child(1) as LineEdit
		if edit.text != note:
			edit.text = note


func set_text(text: String) -> void:
	_text.text = text


## Switches the tab ("bug" or "idea"; anything else is ignored). Text and marks stay.
func set_kind(value: String) -> void:
	if not KINDS.has(value):
		return
	kind = value
	for key in _kind_buttons:
		_kind_buttons[key].set_pressed_no_signal(key == kind)
	if _header != null:
		_header.text = "%s · %s" % [DevFeedbackTexts.kind_text(kind, 1),
			DevFeedbackTexts.t(&"BUG_REPORT_HINT_TOUCH" if touch_mode else &"BUG_REPORT_HINT_DESKTOP")]
	if _text != null:
		_text.placeholder_text = DevFeedbackTexts.kind_text(kind, 2)


func get_kind() -> String:
	return kind


## The other tab (direction 1 = right, -1 = left, wraps).
func switch_kind(direction := 1) -> void:
	var index := KINDS.find(kind)
	set_kind(KINDS[posmod(index + direction, KINDS.size())])


func has_content() -> bool:
	return not marks.is_empty() or not strokes.is_empty() or not _text.text.strip_edges().is_empty()


## The note as it stands (view coordinates).
func build_note() -> Dictionary:
	var mark_list: Array = []
	for mark in marks:
		mark_list.append({"rect": mark["rect"], "note": str(mark["note"]).strip_edges()})
	return {
		"text": _text.text.strip_edges(),
		"kind": kind,
		"marks": mark_list,
		"strokes": strokes.duplicate(),
		"view_size": _view_size,
	}


func submit() -> void:
	if _finished:
		return
	if needs_consent:
		show_consent()
		return
	_finished = true
	submitted.emit(build_note())


## The privacy notice in front of everything (first send only).
func show_consent() -> void:
	if _consent == null:
		_consent = _build_consent()
		_root.add_child(_consent)
	_consent.visible = true


func is_consent_open() -> bool:
	return _consent != null and _consent.visible


## "Einverstanden, senden": remembered by DevFeedback, then sent.
func confirm_consent() -> void:
	if _finished:
		return
	needs_consent = false
	if _consent != null:
		_consent.visible = false
	consent_given.emit()
	submit()


func close_consent() -> void:
	if _consent != null:
		_consent.visible = false


func cancel() -> void:
	if _finished:
		return
	_finished = true
	cancelled.emit()


## Input on the screenshot. Mouse: drag = rectangle, Shift + drag = stroke, right click = remove.
## Touch mode: fingers (handle_touch_event); the mouse emulated from a finger is ignored, a real
## mouse only counts while it does not also send touches (desktop with -- touch=1 in the menus).
func handle_canvas_event(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if touch_mode:
			handle_touch_event(event)
		return
	if touch_mode and (event.device == InputEvent.DEVICE_ID_EMULATION or Input.emulate_touch_from_mouse):
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_begin_drag(button.position, button.shift_pressed)
			else:
				_end_drag(button.position)
		elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			remove_mark_at(button.position)
	elif event is InputEventMouseMotion and _drag_mode != 0:
		_update_drag((event as InputEventMouseMotion).position)


## One finger: drag = rectangle; resting LONG_PRESS_MSEC on a mark = remove it (check_long_press).
func handle_touch_event(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _touch_finger >= 0:
				return
			_touch_finger = touch.index
			_touch_start = touch.position
			_touch_start_msec = Time.get_ticks_msec()
			_touch_moved = false
			_begin_drag(touch.position, false)
		elif touch.index == _touch_finger:
			_touch_finger = -1
			if _drag_mode != 0:
				_end_drag(touch.position)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index != _touch_finger or _drag_mode == 0:
			return
		if not _touch_moved and drag.position.distance_to(_touch_start) < LONG_PRESS_MOVE:
			return
		_touch_moved = true
		_update_drag(drag.position)


## Long press: a resting finger removes the mark (or stroke) under it; true when one went.
func check_long_press(now_msec: int) -> bool:
	if _touch_finger < 0 or _touch_moved or _drag_mode == 0:
		return false
	if now_msec - _touch_start_msec < LONG_PRESS_MSEC:
		return false
	_drag_mode = 0
	_drag_rect = Rect2()
	var removed := remove_mark_at(_touch_start)
	if removed:
		_set_status(DevFeedbackTexts.t(&"BUG_REPORT_MARK_REMOVED"), COLOR_ACCENT)
	_canvas.queue_redraw()
	return removed


# --- input -------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _finished:
		return
	if event is InputEventJoypadButton:
		handle_pad_button(event as InputEventJoypadButton)
		_handled()
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_ESCAPE:
				_on_escape()
				_handled()
				return
			if (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER) and key.is_command_or_control_pressed():
				submit()
				_handled()
				return
			if key.keycode == KEY_TAB and key.is_command_or_control_pressed():
				switch_kind(-1 if key.shift_pressed else 1)
				_handled()
				return
		if key.keycode == KEY_F9:
			_handled()
			return
		# Keys go to the focused text field; without focus in the overlay they are swallowed.
		var focus := _root.get_viewport().gui_get_focus_owner() if _root.is_inside_tree() else null
		if focus == null or not _root.is_ancestor_of(focus):
			_handled()


## Gamepad: LB/RB switch the tab, Start sends (or confirms the privacy notice), B cancels like Esc.
## true when the button was used.
func handle_pad_button(event: InputEventJoypadButton) -> bool:
	if not event.pressed or _finished:
		return false
	if not pad_mode:
		pad_mode = true
		_set_status(DevFeedbackTexts.t(&"BUG_REPORT_KEYS_PAD"), COLOR_MUTED)
	match event.button_index:
		JOY_BUTTON_LEFT_SHOULDER:
			switch_kind(-1)
		JOY_BUTTON_RIGHT_SHOULDER:
			switch_kind(1)
		JOY_BUTTON_START:
			if is_consent_open():
				confirm_consent()
			else:
				submit()
		JOY_BUTTON_B:
			_on_escape()
		_:
			return false
	return true


## Whatever the GUI did not take (keys a text field ignores, wheel, ...) stops here.
func _unhandled_input(_event: InputEvent) -> void:
	if not _finished:
		_handled()


func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _on_escape() -> void:
	if is_consent_open():
		close_consent()
		return
	if not has_content() or Time.get_ticks_msec() - _cancel_armed_at <= CANCEL_CONFIRM_MSEC:
		cancel()
		return
	_cancel_armed_at = Time.get_ticks_msec()
	_set_status(DevFeedbackTexts.t(&"BUG_REPORT_CONFIRM_DISCARD"), COLOR_MARK)


func _begin_drag(at: Vector2, stroke: bool) -> void:
	_drag_start = at
	_drag_rect = Rect2(at, Vector2.ZERO)
	if stroke:
		_drag_mode = 2
		strokes.append(PackedVector2Array([at]))
	else:
		_drag_mode = 1
	_canvas.queue_redraw()


func _update_drag(at: Vector2) -> void:
	if _drag_mode == 1:
		_drag_rect = Rect2(_drag_start, at - _drag_start).abs()
	elif _drag_mode == 2 and not strokes.is_empty():
		var line := strokes[strokes.size() - 1]
		if line.is_empty() or line[line.size() - 1].distance_to(at) >= STROKE_STEP:
			line.append(at)
			strokes[strokes.size() - 1] = line
	_canvas.queue_redraw()


func _end_drag(at: Vector2) -> void:
	var mode := _drag_mode
	_update_drag(at)
	_drag_mode = 0
	if mode == 1:
		var rect := _drag_rect.intersection(Rect2(Vector2.ZERO, _canvas.size if _canvas.size != Vector2.ZERO else _view_size))
		if rect.size.x >= MIN_RECT and rect.size.y >= MIN_RECT:
			add_mark(rect)
			if not touch_mode:
				_focus_mark_edit(marks.size() - 1)
	elif mode == 2 and not strokes.is_empty() and strokes[strokes.size() - 1].size() < 2:
		strokes.remove_at(strokes.size() - 1)
	_canvas.queue_redraw()


# --- drawing -----------------------------------------------------------------------------------

func _on_canvas_draw() -> void:
	var area := Rect2(Vector2.ZERO, _canvas.size)
	if _texture != null:
		_canvas.draw_texture_rect(_texture, area, false)
	else:
		_canvas.draw_rect(area, Color(0.1, 0.1, 0.12))
	# Thin frame: the game is frozen, this is the report tool.
	_canvas.draw_rect(area.grow(-1.0), COLOR_ACCENT, false, 2.0)
	var font := _canvas.get_theme_default_font()
	for line in strokes:
		if line.size() >= 2:
			_canvas.draw_polyline(line, COLOR_STROKE, 3.0, true)
	for i in marks.size():
		var rect: Rect2 = marks[i]["rect"]
		_canvas.draw_rect(rect, COLOR_MARK_FILL)
		_canvas.draw_rect(rect, COLOR_MARK, false, 2.0)
		_draw_number(font, rect.position, i + 1)
	if _drag_mode == 1 and _drag_rect.size != Vector2.ZERO:
		_canvas.draw_rect(_drag_rect, COLOR_MARK_FILL)
		_canvas.draw_rect(_drag_rect, COLOR_DRAFT, false, 2.0)


func _draw_number(font: Font, at: Vector2, number: int) -> void:
	var text := str(number)
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var box := Rect2(at, Vector2(size.x + 10.0, FONT_SIZE + 6.0))
	_canvas.draw_rect(box, COLOR_MARK)
	_canvas.draw_string(font, at + Vector2(5.0, FONT_SIZE + 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color.WHITE)


# --- building ----------------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_root.theme = _make_theme()
	add_child(_root)

	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.mouse_default_cursor_shape = Control.CURSOR_CROSS
	_canvas.focus_mode = Control.FOCUS_CLICK
	_canvas.draw.connect(_on_canvas_draw)
	_canvas.gui_input.connect(_on_canvas_gui_input)
	_root.add_child(_canvas)

	var header := Label.new()
	_header = header
	header.name = "Header"
	header.add_theme_color_override(&"font_color", COLOR_ACCENT)
	header.add_theme_stylebox_override(&"normal", _box(Color(0.0, 0.0, 0.0, 0.6), Color(0, 0, 0, 0), 0))
	header.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	header.grow_horizontal = Control.GROW_DIRECTION_BOTH
	header.offset_top = 4.0
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(header)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_root.add_child(_panel)
	_place_panel()
	var margin := MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 8)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	margin.add_child(column)

	var tab_row := HBoxContainer.new()
	tab_row.name = "Tabs"
	tab_row.add_theme_constant_override(&"separation", 4)
	column.add_child(tab_row)
	var group := ButtonGroup.new()
	for key in KINDS:
		var button := Button.new()
		button.name = "Tab_" + key
		button.text = DevFeedbackTexts.kind_text(key, 0)
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		if touch_mode:
			button.custom_minimum_size = Vector2(0.0, TAB_HEIGHT_TOUCH)
		_style_tab(button)
		button.pressed.connect(set_kind.bind(key))
		tab_row.add_child(button)
		_kind_buttons[key] = button
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_row.add_child(spacer)
	_status = Label.new()
	_status.name = "Status"
	_status.text = _keys_hint()
	_status.add_theme_color_override(&"font_color", COLOR_MUTED)
	tab_row.add_child(_status)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 8)
	column.add_child(body)
	_text = TextEdit.new()
	_text.name = "Note"
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.size_flags_stretch_ratio = 3.0
	body.add_child(_text)
	var mark_column := VBoxContainer.new()
	mark_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mark_column.size_flags_stretch_ratio = 2.0
	body.add_child(mark_column)
	_mark_hint = Label.new()
	_mark_hint.add_theme_color_override(&"font_color", COLOR_MUTED)
	mark_column.add_child(_mark_hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mark_column.add_child(scroll)
	_mark_box = VBoxContainer.new()
	_mark_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_mark_box)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override(&"separation", 6)
	column.add_child(buttons)
	var privacy := Label.new()
	privacy.name = "Privacy"
	privacy.text = DevFeedbackTexts.t(&"BUG_REPORT_PRIVACY")
	privacy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	privacy.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	privacy.add_theme_color_override(&"font_color", COLOR_MUTED)
	privacy.add_theme_font_size_override(&"font_size", _font_size() - 2)
	buttons.add_child(privacy)
	_side_button = Button.new()
	_side_button.focus_mode = Control.FOCUS_NONE
	_side_button.pressed.connect(_toggle_panel_side)
	buttons.add_child(_side_button)
	var cancel_button := Button.new()
	cancel_button.name = "Cancel"
	cancel_button.text = DevFeedbackTexts.t(&"BUG_REPORT_CANCEL")
	cancel_button.focus_mode = Control.FOCUS_NONE
	cancel_button.pressed.connect(cancel)
	buttons.add_child(cancel_button)
	var save_button := Button.new()
	save_button.name = "Send"
	save_button.text = DevFeedbackTexts.t(&"BUG_REPORT_SEND")
	save_button.focus_mode = Control.FOCUS_NONE
	save_button.add_theme_color_override(&"font_color", COLOR_ACCENT)
	save_button.pressed.connect(submit)
	buttons.add_child(save_button)
	_update_side_button()
	_rebuild_mark_list()
	set_kind(kind)


## Shortcut line: pad buttons after a pad input, keys on a desktop, nothing on a phone (buttons).
func _keys_hint() -> String:
	if pad_mode:
		return DevFeedbackTexts.t(&"BUG_REPORT_KEYS_PAD")
	return "" if touch_mode else DevFeedbackTexts.t(&"BUG_REPORT_KEYS_DESKTOP")


## Tabs: the chosen one is lit in the accent colour, the other stays plain.
func _style_tab(button: Button) -> void:
	var chosen := _box(Color(0.24, 0.19, 0.08), COLOR_ACCENT, 2)
	chosen.border_width_top = 3
	button.add_theme_stylebox_override(&"pressed", chosen)
	button.add_theme_stylebox_override(&"hover_pressed", chosen)
	button.add_theme_color_override(&"font_pressed_color", COLOR_ACCENT)
	button.add_theme_color_override(&"font_hover_pressed_color", COLOR_ACCENT)
	button.add_theme_color_override(&"font_color", COLOR_MUTED)


## Dimmed full screen with a centred box: title, notice, "Zurück" and "Einverstanden, senden".
func _build_consent() -> Control:
	var shade := ColorRect.new()
	shade.name = "Consent"
	shade.color = Color(0.0, 0.0, 0.0, 0.6)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(620.0 if not touch_mode else 760.0, 0.0)
	center.add_child(box)
	var margin := MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	box.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 12)
	margin.add_child(column)
	var title := Label.new()
	title.text = DevFeedbackTexts.t(&"BUG_REPORT_CONSENT_TITLE")
	title.add_theme_color_override(&"font_color", COLOR_ACCENT)
	column.add_child(title)
	var text := Label.new()
	text.text = DevFeedbackTexts.t(&"BUG_REPORT_CONSENT_TEXT")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(text)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override(&"separation", 8)
	column.add_child(buttons)
	var back := Button.new()
	back.name = "ConsentBack"
	back.text = DevFeedbackTexts.t(&"BUG_REPORT_CONSENT_BACK")
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(close_consent)
	buttons.add_child(back)
	var ok := Button.new()
	ok.name = "ConsentOk"
	ok.text = DevFeedbackTexts.t(&"BUG_REPORT_CONSENT_OK")
	ok.focus_mode = Control.FOCUS_NONE
	ok.add_theme_color_override(&"font_color", COLOR_ACCENT)
	ok.pressed.connect(confirm_consent)
	buttons.add_child(ok)
	return shade


func _place_panel() -> void:
	var height := _panel_height()
	if _panel_on_top:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		_panel.offset_top = 30.0
		_panel.offset_bottom = 30.0 + height
	else:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		_panel.offset_top = -height - _keyboard_lift
		_panel.offset_bottom = -_keyboard_lift
	_panel.offset_left = 0.0
	_panel.offset_right = 0.0


func _toggle_panel_side() -> void:
	_panel_on_top = not _panel_on_top
	_place_panel()
	_update_side_button()


func _update_side_button() -> void:
	_side_button.text = DevFeedbackTexts.t(&"BUG_REPORT_PANEL_DOWN" if _panel_on_top else &"BUG_REPORT_PANEL_UP")


func _panel_height() -> float:
	return PANEL_HEIGHT_TOUCH if touch_mode else PANEL_HEIGHT


func _font_size() -> int:
	return FONT_SIZE_TOUCH if touch_mode else FONT_SIZE


## Phones: the bottom panel rides above the on-screen keyboard while it is open.
func _follow_keyboard() -> void:
	var lift := 0.0
	if not _panel_on_top and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		var keyboard := DisplayServer.virtual_keyboard_get_height()
		var window_height := float(DisplayServer.window_get_size().y)
		if keyboard > 0 and window_height > 0.0:
			lift = clampf(keyboard * _view_size.y / window_height, 0.0, _view_size.y - _panel_height() - 30.0)
	if not is_equal_approx(lift, _keyboard_lift):
		_keyboard_lift = lift
		_place_panel()


func _rebuild_mark_list() -> void:
	if _mark_box == null:
		return
	# Rebuilt on add/remove only (never from a row's own signal), so freeing at once is safe.
	for child in _mark_box.get_children():
		child.free()
	_mark_hint.text = DevFeedbackTexts.t(&"BUG_REPORT_MARKS_HINT" if not marks.is_empty() else &"BUG_REPORT_MARKS_EMPTY")
	for i in marks.size():
		var row := HBoxContainer.new()
		var number := Label.new()
		number.text = "%d:" % (i + 1)
		number.custom_minimum_size = Vector2(26, 0)
		number.add_theme_color_override(&"font_color", COLOR_MARK)
		row.add_child(number)
		var edit := LineEdit.new()
		edit.text = str(marks[i]["note"])
		edit.placeholder_text = DevFeedbackTexts.t(&"BUG_REPORT_MARK_PLACEHOLDER") % (i + 1)
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.text_changed.connect(func(value: String) -> void: _on_mark_note_changed(row, value))
		row.add_child(edit)
		_mark_box.add_child(row)


func _on_mark_note_changed(row: Node, value: String) -> void:
	var index := row.get_index()
	if index >= 0 and index < marks.size():
		marks[index]["note"] = value


func _focus_mark_edit(index: int) -> void:
	if index < 0 or index >= _mark_box.get_child_count():
		return
	var edit := _mark_box.get_child(index).get_child(1) as LineEdit
	if edit != null and edit.is_inside_tree():
		edit.grab_focus.call_deferred()


func _on_canvas_gui_input(event: InputEvent) -> void:
	handle_canvas_event(event)
	_canvas.accept_event()


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override(&"font_color", color)


func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = _font_size()
	var panel := _box(COLOR_PANEL, Color(COLOR_ACCENT, 0.6), 1)
	theme.set_stylebox(&"panel", &"PanelContainer", panel)
	var normal := _box(Color(0.16, 0.14, 0.22), Color(0.35, 0.32, 0.45), 1)
	var hover := _box(Color(0.22, 0.2, 0.3), Color(0.55, 0.5, 0.65), 1)
	var pressed := _box(Color(0.55, 0.12, 0.1), COLOR_MARK, 2)
	for type: StringName in [&"Button"]:
		theme.set_stylebox(&"normal", type, normal)
		theme.set_stylebox(&"hover", type, hover)
		theme.set_stylebox(&"pressed", type, pressed)
		theme.set_stylebox(&"hover_pressed", type, pressed)
		theme.set_stylebox(&"focus", type, StyleBoxEmpty.new())
		theme.set_color(&"font_color", type, COLOR_TEXT)
		theme.set_color(&"font_pressed_color", type, Color.WHITE)
		theme.set_color(&"font_hover_color", type, Color.WHITE)
		theme.set_color(&"font_hover_pressed_color", type, Color.WHITE)
	var field := _box(Color(0.04, 0.035, 0.06, 0.95), Color(0.35, 0.32, 0.45), 1)
	var field_focus := _box(Color(0.04, 0.035, 0.06, 0.95), COLOR_ACCENT, 1)
	for type: StringName in [&"TextEdit", &"LineEdit"]:
		theme.set_stylebox(&"normal", type, field)
		theme.set_stylebox(&"focus", type, field_focus)
		theme.set_color(&"font_color", type, COLOR_TEXT)
		theme.set_color(&"font_placeholder_color", type, Color(COLOR_MUTED, 0.6))
		theme.set_color(&"caret_color", type, COLOR_ACCENT)
	theme.set_color(&"font_color", &"Label", COLOR_TEXT)
	return theme


static func _box(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(3)
	box.content_margin_left = 8.0
	box.content_margin_right = 8.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	return box

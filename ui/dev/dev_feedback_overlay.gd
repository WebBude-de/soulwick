class_name DevFeedbackOverlay
extends CanvasLayer
## Full-screen dev feedback overlay (DevFeedback, F9): shows the frozen screenshot, lets the
## developer drag numbered rectangles (left mouse; Shift + drag draws a free stroke; right click
## removes the mark under the cursor), type a shared note and one short note per rectangle, pick
## categories, then save (Ctrl+Enter / "Speichern") or discard (Esc / "Abbrechen").
## Texts are German and hard-coded on purpose: this is a local developer tool that never ships in
## a release build (DevFeedback.is_enabled), so it has no translation keys (exception to D-111).
## auto_translate is switched off so no text is ever looked up as a key.
## All input is swallowed while it is open: the GUI consumes mouse and focused text input, every
## other key is marked handled, so nothing reaches the game (no attack, no pause menu).

signal submitted(note: Dictionary)
signal cancelled

const LAYER := 120
const CATEGORIES: Array[String] = ["UI", "Grafik", "Licht", "Raum/Layout", "Gameplay", "Bug", "Text"]
## Smaller drags are taken as clicks, not as rectangles (view pixels).
const MIN_RECT := 6.0
const STROKE_STEP := 3.0
const REMOVE_STROKE_DISTANCE := 10.0
## A second Esc within this time discards a note that already has content.
const CANCEL_CONFIRM_MSEC := 2000
const PANEL_HEIGHT := 196.0

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
var _category_buttons: Dictionary[String, Button] = {}
var _panel_on_top := false
var _drag_mode := 0  # 0 none, 1 rectangle, 2 stroke
var _drag_start := Vector2.ZERO
var _drag_rect := Rect2()
var _cancel_armed_at := -100000
var _finished := false


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
	_text.grab_focus.call_deferred()


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


func set_category(category: String, on: bool) -> void:
	if _category_buttons.has(category):
		_category_buttons[category].button_pressed = on


func get_categories() -> Array[String]:
	var chosen: Array[String] = []
	for category in CATEGORIES:
		if _category_buttons[category].button_pressed:
			chosen.append(category)
	return chosen


func has_content() -> bool:
	return not marks.is_empty() or not strokes.is_empty() or not _text.text.strip_edges().is_empty()


## The note as it stands (view coordinates).
func build_note() -> Dictionary:
	var mark_list: Array = []
	for mark in marks:
		mark_list.append({"rect": mark["rect"], "note": str(mark["note"]).strip_edges()})
	return {
		"text": _text.text.strip_edges(),
		"categories": get_categories(),
		"marks": mark_list,
		"strokes": strokes.duplicate(),
		"view_size": _view_size,
	}


func submit() -> void:
	if _finished:
		return
	_finished = true
	submitted.emit(build_note())


func cancel() -> void:
	if _finished:
		return
	_finished = true
	cancelled.emit()


## Mouse input on the screenshot: drag = rectangle, Shift + drag = stroke, right click = remove.
func handle_canvas_event(event: InputEvent) -> void:
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


# --- input -------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _finished:
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
		if key.keycode == KEY_F9:
			_handled()
			return
		# Keys go to the focused text field; without focus in the overlay they are swallowed.
		var focus := _root.get_viewport().gui_get_focus_owner() if _root.is_inside_tree() else null
		if focus == null or not _root.is_ancestor_of(focus):
			_handled()


## Whatever the GUI did not take (keys a text field ignores, wheel, ...) stops here.
func _unhandled_input(_event: InputEvent) -> void:
	if not _finished:
		_handled()


func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _on_escape() -> void:
	if not has_content() or Time.get_ticks_msec() - _cancel_armed_at <= CANCEL_CONFIRM_MSEC:
		cancel()
		return
	_cancel_armed_at = Time.get_ticks_msec()
	_set_status("Nochmal Esc: Notiz verwerfen", COLOR_MARK)


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
	# Thin frame: the game is frozen, this is the dev tool.
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
	header.text = "DEV-FEEDBACK · Spiel pausiert · Ziehen: Rechteck · Umschalt+Ziehen: Strich · Rechtsklick: entfernen"
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

	var category_row := HBoxContainer.new()
	category_row.add_theme_constant_override(&"separation", 4)
	column.add_child(category_row)
	var category_label := Label.new()
	category_label.text = "Kategorie:"
	category_label.add_theme_color_override(&"font_color", COLOR_MUTED)
	category_row.add_child(category_label)
	for category in CATEGORIES:
		var button := Button.new()
		button.text = category
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		category_row.add_child(button)
		_category_buttons[category] = button
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	category_row.add_child(spacer)
	_status = Label.new()
	_status.text = "Strg+Enter: speichern · Esc: abbrechen"
	_status.add_theme_color_override(&"font_color", COLOR_MUTED)
	category_row.add_child(_status)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 8)
	column.add_child(body)
	_text = TextEdit.new()
	_text.name = "Note"
	_text.placeholder_text = "Was ist hier nicht gut? (gemeinsame Notiz, mehrzeilig)"
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
	_side_button = Button.new()
	_side_button.focus_mode = Control.FOCUS_NONE
	_side_button.pressed.connect(_toggle_panel_side)
	buttons.add_child(_side_button)
	var cancel_button := Button.new()
	cancel_button.text = "Abbrechen"
	cancel_button.focus_mode = Control.FOCUS_NONE
	cancel_button.pressed.connect(cancel)
	buttons.add_child(cancel_button)
	var save_button := Button.new()
	save_button.text = "Speichern"
	save_button.focus_mode = Control.FOCUS_NONE
	save_button.add_theme_color_override(&"font_color", COLOR_ACCENT)
	save_button.pressed.connect(submit)
	buttons.add_child(save_button)
	_update_side_button()
	_rebuild_mark_list()


func _place_panel() -> void:
	if _panel_on_top:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		_panel.offset_top = 30.0
		_panel.offset_bottom = 30.0 + PANEL_HEIGHT
	else:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		_panel.offset_top = -PANEL_HEIGHT
		_panel.offset_bottom = 0.0
	_panel.offset_left = 0.0
	_panel.offset_right = 0.0


func _toggle_panel_side() -> void:
	_panel_on_top = not _panel_on_top
	_place_panel()
	_update_side_button()


func _update_side_button() -> void:
	_side_button.text = "Leiste nach unten" if _panel_on_top else "Leiste nach oben"


func _rebuild_mark_list() -> void:
	if _mark_box == null:
		return
	# Rebuilt on add/remove only (never from a row's own signal), so freeing at once is safe.
	for child in _mark_box.get_children():
		child.free()
	_mark_hint.text = "Notiz je Markierung (optional):" if not marks.is_empty() else "Noch keine Markierung: Rechteck aufziehen"
	for i in marks.size():
		var row := HBoxContainer.new()
		var number := Label.new()
		number.text = "%d:" % (i + 1)
		number.custom_minimum_size = Vector2(26, 0)
		number.add_theme_color_override(&"font_color", COLOR_MARK)
		row.add_child(number)
		var edit := LineEdit.new()
		edit.text = str(marks[i]["note"])
		edit.placeholder_text = "kurze Notiz zu %d" % (i + 1)
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
	theme.default_font_size = FONT_SIZE
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

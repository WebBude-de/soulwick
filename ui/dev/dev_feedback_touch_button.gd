class_name DevFeedbackTouchButton
extends CanvasLayer
## TEMPORÄR (Beta): small bug button at the top right for phones, so players without a keyboard
## can open the bug report (DevFeedback). Shown only while the tool is on (DevFeedback.is_enabled)
## and touch is in use (TouchState, read only, or a finger touched the screen since the last
## keyboard/mouse input), hidden while the overlay is open. Sits at the right edge below the room
## line of the HUD and slides further down when something visible is there (room line with the heal
## countdown, room line moved below a boss bar; update_place, read only), so it covers neither the
## room number nor the gold. Remove this file (and its lines in DevFeedback) once the beta is over.
## The icon is a drawn placeholder (a little beetle); no sprite needed.

signal tapped

## Above the HUD and the touch controls (25), below the toast (121) and the overlay (120).
const LAYER := 119
## Button size and position in viewport pixels (1280x720): right edge like the HUD (8 * 1280/480),
## top below the two lines of the room info.
const SIZE := 30.0
const MARGIN_RIGHT := 21.0
const TOP := 78.0
## Free space kept below the HUD element above the button.
const GAP := 6.0
## How often the place is checked while the button is shown.
const PLACE_INTERVAL_MSEC := 300
## Elements larger than this share of the screen (full-screen roots, overlays) never push it down.
const MAX_BLOCKER_SHARE := 0.25
const ALPHA := 0.55
const ALPHA_PRESSED := 0.95
const COLOR_FILL := Color(0.05, 0.04, 0.08, 0.7)
const COLOR_RING := Color(1.0, 0.86, 0.62, 0.9)
const COLOR_BUG := Color(1.0, 0.93, 0.8, 1.0)

var button: Button
var _icon: Control
## Visibility is decided by DevFeedback (set_wanted); kept for tests.
var _wanted := false
var _next_place_msec := 0


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	button = Button.new()
	button.name = "BugButton"
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.custom_minimum_size = Vector2(SIZE, SIZE)
	button.size = Vector2(SIZE, SIZE)
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.offset_left = -MARGIN_RIGHT - SIZE
	button.offset_right = -MARGIN_RIGHT
	button.offset_top = TOP
	button.offset_bottom = TOP + SIZE
	button.modulate.a = ALPHA
	for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.button_down.connect(func() -> void: button.modulate.a = ALPHA_PRESSED)
	button.button_up.connect(func() -> void: button.modulate.a = ALPHA)
	button.pressed.connect(func() -> void: tapped.emit())
	add_child(button)
	_icon = Control.new()
	_icon.name = "Icon"
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon.draw.connect(_draw_icon)
	button.add_child(_icon)
	visible = false


func set_wanted(value: bool) -> void:
	_wanted = value
	if visible != value:
		visible = value
		button.modulate.a = ALPHA


func is_wanted() -> bool:
	return _wanted


## Moves the button below visible UI at its spot (checked every PLACE_INTERVAL_MSEC): starts at TOP
## and steps below every drawn Control (text, texture, panel, button) that meets the button.
func update_place(scan_root: Node, exclude: Node, now_msec := -1) -> void:
	var now := now_msec if now_msec >= 0 else Time.get_ticks_msec()
	if now < _next_place_msec or scan_root == null:
		return
	_next_place_msec = now + PLACE_INTERVAL_MSEC
	var view := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)
	var top := TOP
	for attempt in 6:
		var spot := Rect2(view.x - MARGIN_RIGHT - SIZE, top, SIZE, SIZE)
		var bottom := lowest_blocker(scan_root, spot, exclude, view.x * view.y * MAX_BLOCKER_SHARE)
		if bottom < 0.0:
			break
		top = bottom + GAP
	top = minf(top, view.y * 0.5)
	if not is_equal_approx(button.offset_top, top):
		button.offset_top = top
		button.offset_bottom = top + SIZE


## Lowest bottom edge of the drawn, visible Controls meeting spot (-1 when none). Skips the world
## (Node2D subtrees), hidden layers, other windows, exclude and this layer.
func lowest_blocker(node: Node, spot: Rect2, exclude: Node, max_area: float) -> float:
	if node == exclude or node == self or node is Node2D:
		return -1.0
	if node is Window and node != get_tree().root:
		return -1.0
	if node is CanvasLayer and not (node as CanvasLayer).visible:
		return -1.0
	var lowest := -1.0
	if node is Control:
		var control := node as Control
		if not control.is_visible_in_tree():
			return -1.0
		if _draws_something(control):
			var bounds := (control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)).abs()
			if bounds.get_area() > 0.0 and bounds.get_area() <= max_area and bounds.intersects(spot):
				lowest = bounds.end.y
	for child in node.get_children():
		lowest = maxf(lowest, lowest_blocker(child, spot, exclude, max_area))
	return lowest


static func _draws_something(control: Control) -> bool:
	if control is Label:
		return not (control as Label).text.strip_edges().is_empty()
	if control is RichTextLabel:
		return not (control as RichTextLabel).text.strip_edges().is_empty()
	return control is TextureRect or control is BaseButton or control is Panel or control is PanelContainer \
			or control is ProgressBar or control is TextureProgressBar


## Screen rectangle of the button (viewport pixels), e.g. for layout checks.
func get_button_rect() -> Rect2:
	return button.get_global_rect()


## Round dark plate with a ring and a beetle: body, head, six legs, two feelers.
func _draw_icon() -> void:
	var center := _icon.size * 0.5
	var radius := minf(_icon.size.x, _icon.size.y) * 0.5
	_icon.draw_circle(center, radius - 1.0, COLOR_FILL)
	_icon.draw_arc(center, radius - 1.5, 0.0, TAU, 32, COLOR_RING, 1.5, true)
	var s := radius / 15.0
	var body := center + Vector2(0, 2.0 * s)
	for side in [-1.0, 1.0]:
		for row in 3:
			var from := body + Vector2(side * 3.0 * s, (row - 1) * 3.5 * s)
			var to := from + Vector2(side * 4.5 * s, (row - 1) * 2.0 * s - 1.0 * s)
			_icon.draw_line(from, to, COLOR_BUG, 1.4 * s, true)
		var feeler_from := center + Vector2(side * 1.5 * s, -6.5 * s)
		_icon.draw_line(feeler_from, feeler_from + Vector2(side * 2.5 * s, -3.0 * s), COLOR_BUG, 1.2 * s, true)
	_icon.draw_set_transform(body, 0.0, Vector2(1.0, 1.3))
	_icon.draw_circle(Vector2.ZERO, 4.2 * s, COLOR_BUG)
	_icon.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_icon.draw_circle(center + Vector2(0, -5.0 * s), 2.6 * s, COLOR_BUG)
	_icon.draw_line(body + Vector2(0, -5.0 * s), body + Vector2(0, 5.4 * s), COLOR_FILL, 1.0 * s, true)

class_name Modal
extends Control
## Full-screen dialog that pauses the whole simulation while open (D-043).
## Usage: var modal := Modal.create(reason); fill modal.content; var result = await modal.open(parent)
## Look (docs/design): overlay rgba(21,19,31,0.78), centred panel. Keys are named either in the
## key bar inside the panel (set_key_hints: key caps + "Spiel pausiert", the dungeon menu kit of
## UX2) or, for older dialogs, in a footer line at the bottom of the screen (set_footer).
## R8: the scene stays visible under a lighter overlay, the panel pops in, cards are dealt in one
## after another (deal), an optional accent stripe in the mode/dialog colour runs down the left
## inner edge of the panel (accent), and no dialog is taller than UiKit.DIALOG_MAX_HEIGHT_RATIO of
## the screen (fits_screen, checked by the tests). Choosing stays instant: finish() returns at once.

signal finished(result: Variant)

const DIM_COLOR := UiKit.COLOR_OVERLAY
## Gap between content rows in mockup pixels (ui_spec dialog.gap; R8 tighter, dialogs max 60 %).
const CONTENT_GAP := 4.0
## Accent stripe on the left inner edge of the panel, mockup pixels (07_ui.md: 4-6 px of the colour).
const ACCENT_WIDTH := 3.0
## Cards dealt in after the panel: first delay and step (seconds, optics).
const DEAL_DELAY := 0.08
const DEAL_STEP := 0.05
## Footer distance from the bottom edge in mockup pixels.
const FOOTER_BOTTOM := 12.0

var content: VBoxContainer = null
## Key bar under content inside the panel (hidden until set_key_hints).
var key_bar: VBoxContainer = null
## The panel around content (PanelContainer); set custom_minimum_size here for fixed widths.
var frame: PanelContainer = null
var pause_reason: StringName = &""
## Esc/ui_cancel closes the dialog with this result; disabled when cancel_allowed is false.
var cancel_result: Variant = null
var cancel_allowed := true
## Enter closes the dialog with accept_result when accept_allowed (the highlighted default button).
var accept_result: Variant = null
var accept_allowed := false
## Number keys while open: Key (e.g. KEY_1) -> Callable. Used for "[1]" choices.
var hotkeys: Dictionary = {}
## Optional Callable for Enter instead of accept_result (e.g. confirm the focused card).
var accept_action: Callable = Callable()
## Optional key handler (event) -> bool, asked first (e.g. ↑/↓ through the pause menu buttons).
var input_handler: Callable = Callable()
## Colour of the stripe on the left inner edge of the panel (alpha 0 = none).
var accent := Color(0, 0, 0, 0):
	set(value):
		accent = value
		if frame != null:
			frame.queue_redraw()

var _done := false
var _dim: ColorRect = null
var _footer: Label = null
## Controls that pop in one after another once the panel is up (cards of a row).
var _deal: Array[Control] = []


static func create(reason: StringName, panel_kind := &"normal") -> Modal:
	var modal := Modal.new()
	modal.pause_reason = reason
	modal._build(panel_kind)
	return modal


func open(parent: Node) -> Variant:
	parent.add_child(self)
	GameManager.request_pause(pause_reason)
	Sfx.play_ui(self, &"ui_open")
	_animate_in()
	return await finished


## Lets these controls pop in one after another once the dialog opens (call before open()).
func deal(controls: Array) -> void:
	for control in controls:
		if control is Control:
			_deal.append(control)


## true while the panel is not taller than UiKit.DIALOG_MAX_HEIGHT_RATIO of the screen (07_ui.md).
func fits_screen() -> bool:
	return frame.get_combined_minimum_size().y <= get_viewport_rect().size.y * UiKit.DIALOG_MAX_HEIGHT_RATIO + 0.5


## Overlay fades in, the panel pops (slightly smaller, overshoot), then the dealt cards follow.
func _animate_in() -> void:
	var dim_target := _dim.color.a
	_dim.color.a = 0.0
	UiKit.ui_tween(_dim).tween_property(_dim, "color:a", dim_target, 0.18)
	UiKit.pop_in(frame, 0.0, 0.94, 0.22)
	for i in _deal.size():
		if is_instance_valid(_deal[i]):
			UiKit.pop_in(_deal[i], DEAL_DELAY + DEAL_STEP * i, 0.85, 0.26)


func finish(result: Variant = null) -> void:
	if _done:
		return
	_done = true
	GameManager.release_pause(pause_reason)
	finished.emit(result)
	queue_free()


## Overlay on/off (the portal dialog keeps the world visible, ui_spec dialog.overlay).
func set_dimmed(enabled: bool) -> void:
	_dim.color = DIM_COLOR if enabled else Color(0, 0, 0, 0)


## Key line at the bottom of the screen, e.g. "Klicken oder 1–3 · Enter bestätigt · Spiel pausiert".
func set_footer(text: String, color := UiKit.COLOR_DISABLED) -> void:
	if _footer == null:
		_footer = UiKit.text_label("", UiKit.SIZE_BODY, color)
		_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		_footer.offset_top = -UiKit.px(FOOTER_BOTTOM + UiKit.SIZE_BODY + 2)
		_footer.offset_bottom = -UiKit.px(FOOTER_BOTTOM)
		add_child(_footer)
	_footer.text = text
	_footer.add_theme_color_override("font_color", color)


## Key bar inside the panel, below everything in content: a divider, then key caps with captions
## (entries: [[key, caption], ...], e.g. [["1–3", "wählen"], ["Esc", "später"]]) and, with
## paused, "Spiel pausiert" on the right. action (e.g. the "Schließen" button of the shop) sits on
## the right of the bar and saves a row of its own. Calling it again replaces the bar.
func set_key_hints(entries: Array, paused := true, action: Control = null) -> void:
	for child in key_bar.get_children():
		child.queue_free()
	key_bar.visible = true
	key_bar.add_child(UiKit.separator())
	var row := UiKit.hbox(int(UiKit.px(8)))
	row.name = "Keys"
	key_bar.add_child(row)
	for entry: Array in entries:
		var pair := UiKit.hbox(int(UiKit.px(3)))
		pair.add_child(UiChip.key(String(entry[0])))
		var caption := UiKit.text_label(String(entry[1]), UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pair.add_child(caption)
		row.add_child(pair)
	var filler := Control.new()
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(filler)
	if action != null:
		action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		compact_buttons(action)
		row.add_child(action)
	if paused:
		var note := UiKit.text_label(DungeonTexts.t(&"MENU_PAUSED"), UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
		note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(note)


## Buttons in the key bar get less vertical padding (R8: dialogs max 60 % of the screen).
static func compact_buttons(control: Control) -> void:
	var buttons: Array = [control] if control is Button else control.find_children("*", "Button", true, false)
	for button: Button in buttons:
		for state in ["normal", "hover", "pressed", "disabled"]:
			var style := button.get_theme_stylebox(state).duplicate() as StyleBox
			var trim := maxf(0.0, style.content_margin_top - UiKit.px(2))
			style.content_margin_top -= trim
			style.content_margin_bottom -= trim
			button.add_theme_stylebox_override(state, style)


## Fixed panel width in mockup pixels (dialogs: 220 / 230 / 250, pause: 170).
func set_width(spec_width: float) -> void:
	frame.custom_minimum_size.x = UiKit.px(spec_width)


func _build(panel_kind: StringName) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UiKit.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_dim = UiKit.overlay()
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	frame = UiKit.panel(panel_kind)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.draw.connect(_draw_accent)
	center.add_child(frame)
	var outer := UiKit.vbox(int(UiKit.px(CONTENT_GAP)))
	frame.add_child(outer)
	content = UiKit.vbox(int(UiKit.px(CONTENT_GAP)))
	outer.add_child(content)
	key_bar = UiKit.vbox(int(UiKit.px(4)))
	key_bar.name = "KeyBar"
	key_bar.visible = false
	outer.add_child(key_bar)


## The accent stripe inside the panel border, from top to bottom (drawn under the content).
func _draw_accent() -> void:
	if accent.a <= 0.0:
		return
	# Right inside the outer frame of panel.png (3 art pixels), over its inner line.
	var inset := float(UiCard.FRAME_INSET * UiKit.ART_SCALE)
	var width := UiKit.px(ACCENT_WIDTH)
	frame.draw_rect(Rect2(inset, inset, width, frame.size.y - inset * 2.0), accent)
	frame.draw_rect(Rect2(inset + width, inset, UiKit.ART_SCALE, frame.size.y - inset * 2.0), Color(accent, 0.35))


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		# Hidden under a dialog opened on top of it (pause menu -> options).
		return
	if input_handler.is_valid() and input_handler.call(event):
		get_viewport().set_input_as_handled()
		return
	if cancel_allowed and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		UiSound.back(self)
		finish(cancel_result)
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if hotkeys.has(key.keycode):
		get_viewport().set_input_as_handled()
		(hotkeys[key.keycode] as Callable).call()
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		if accept_action.is_valid():
			get_viewport().set_input_as_handled()
			accept_action.call()
		elif accept_allowed:
			get_viewport().set_input_as_handled()
			finish(accept_result)


func _exit_tree() -> void:
	# Never leave a stale pause reason behind, e.g. when the world is freed with the dialog open.
	if not _done:
		_done = true
		GameManager.release_pause(pause_reason)

class_name Modal
extends Control
## Full-screen dialog that pauses the whole simulation while open (D-043).
## Usage: var modal := Modal.create(reason); fill modal.content; var result = await modal.open(parent)
## Look (docs/design): overlay rgba(21,19,31,0.78), centred panel, optional footer line at the bottom
## of the screen that names the keys and "Spiel pausiert".

signal finished(result: Variant)

const DIM_COLOR := UiKit.COLOR_OVERLAY
## Gap between content rows in mockup pixels (ui_spec dialog.gap).
const CONTENT_GAP := 6.0
## Footer distance from the bottom edge in mockup pixels.
const FOOTER_BOTTOM := 12.0

var content: VBoxContainer = null
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

var _done := false
var _dim: ColorRect = null
var _footer: Label = null


static func create(reason: StringName, panel_kind := &"normal") -> Modal:
	var modal := Modal.new()
	modal.pause_reason = reason
	modal._build(panel_kind)
	return modal


func open(parent: Node) -> Variant:
	parent.add_child(self)
	GameManager.request_pause(pause_reason)
	Sfx.play_ui(self, &"ui_open")
	# Small pop-in instead of an instant cut.
	modulate.a = 0.0
	create_tween().set_ignore_time_scale(true).tween_property(self, "modulate:a", 1.0, 0.15)
	return await finished


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
	center.add_child(frame)
	content = UiKit.vbox(int(UiKit.px(CONTENT_GAP)))
	frame.add_child(content)


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

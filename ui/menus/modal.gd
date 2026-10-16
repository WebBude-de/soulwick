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
## Input guard: for INPUT_GUARD after opening, clicks and keys are swallowed, so a click or key
## meant for the dialog before (or a quick double click) never picks in this one; a click has to
## begin after the guard. Open dialogs are counted (open_count) so DungeonUI can queue the next
## one until they are closed.
## Gamepad (P0-2 step 2, Steam Deck): A confirms like Enter (ui_accept), B cancels like Esc
## (ui_cancel). Dialogs without their own input_handler get a focus over their buttons: D-pad or
## left stick (MenuInput, debounced, repeats while held) move a gold frame from button to button
## (nearest one in that direction), A or Enter press the framed button. With a gamepad in use the
## frame starts on the default button (UiDialog marks it). A press of A in the first
## PAD_ACCEPT_GUARD seconds is ignored: A is also the dash, a player mashing it in a fight must not
## pick blindly. The key bar shows the gamepad's buttons while a gamepad is in use (number keys
## become "D-pad select"), and switches back and forth with the device.

signal finished(result: Variant)

## Seconds after opening in which clicks and keys are ignored (real time, TESTWERT).
const INPUT_GUARD := 0.25
## Seconds after opening in which the gamepad's A is ignored (it is also the dash; TESTWERT).
const PAD_ACCEPT_GUARD := 0.6
## Meta flags UiDialog sets on its option buttons: part of the gamepad focus / the default one.
const META_PAD_OPTION: StringName = &"pad_option"
const META_PAD_DEFAULT: StringName = &"pad_default"
## Gamepad focus frame: gold, ART_SCALE thick, this many mockup pixels outside the button.
const FOCUS_COLOR := UiKit.COLOR_GOLD
const FOCUS_MARGIN := 1.0
const PadNav := preload("res://ui/widgets/pad_nav.gd")

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

## Input guard of this dialog in seconds (INPUT_GUARD; 0 = none).
var input_guard := INPUT_GUARD
## Seconds the gamepad's A is ignored after opening (PAD_ACCEPT_GUARD; tests set 0).
var pad_accept_guard := PAD_ACCEPT_GUARD
## Optional (result) -> bool: finish() ignores results it rejects, e.g. a pick meant for another
## dialog (null always passes: a dialog freed or closed from outside).
var result_filter: Callable = Callable()
## > 0: the dialog closes itself with auto_finish_result this many seconds after it appeared
## (group games: an upgrade choice must not hold a player forever). The clock starts on show.
var auto_finish_after := 0.0
var auto_finish_result: Variant = null

var _done := false
var _dim: ColorRect = null
var _footer: Label = null
## Controls that pop in one after another once the panel is up (cards of a row).
var _deal: Array[Control] = []
## Full-screen catcher on top while the input guard runs (swallows clicks and hover).
var _guard_blocker: Control = null
var _shown_ms := -1
## Button under the gamepad focus frame (null = none).
var _pad_button: Button = null
var _focus_ring: Control = null
## Key bar as last set (rebuilt when the device changes): entries, paused, action control.
var _key_entries: Array = []
var _key_paused := true
var _key_action: Control = null
var _has_key_hints := false

## Instance ids of the dialogs on screen (any screen), see open_count().
static var _open_ids: Dictionary = {}


static func create(reason: StringName, panel_kind := &"normal") -> Modal:
	var modal := Modal.new()
	modal.pause_reason = reason
	modal._build(panel_kind)
	return modal


## Number of dialogs open right now (shown and not finished yet).
static func open_count() -> int:
	for id: int in _open_ids.keys():
		if not is_instance_id_valid(id):
			_open_ids.erase(id)
	return _open_ids.size()


func open(parent: Node) -> Variant:
	show_on(parent)
	return await finished


## Shows the dialog under parent without waiting for it (open() = show_on() + await finished).
func show_on(parent: Node) -> void:
	if _done:
		return
	parent.add_child(self)
	_open_ids[get_instance_id()] = true
	_shown_ms = Time.get_ticks_msec()
	# A stick or D-pad still held from the game (walking) must not move the focus.
	MenuInput.latch()
	var device := InputDevice.shared()
	if not device.changed.is_connected(_on_device_changed):
		device.changed.connect(_on_device_changed)
	if InputGlyphs.is_gamepad():
		_focus_default.call_deferred()
	GameManager.request_pause(pause_reason)
	Sfx.play_ui(self, &"ui_open")
	_start_input_guard()
	_animate_in()
	if auto_finish_after > 0.0:
		var timer := get_tree().create_timer(auto_finish_after, true, false, true)
		timer.timeout.connect(_on_auto_finish)


## true while clicks and keys are still swallowed after opening.
func is_input_guarded() -> bool:
	return _shown_ms >= 0 and input_guard > 0.0 and Time.get_ticks_msec() - _shown_ms < int(input_guard * 1000.0)


func _start_input_guard() -> void:
	if input_guard <= 0.0:
		return
	_guard_blocker = Control.new()
	_guard_blocker.name = "InputGuard"
	_guard_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_guard_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_guard_blocker)


func _process(_delta: float) -> void:
	if _guard_blocker != null and not is_input_guarded():
		_guard_blocker.queue_free()
		_guard_blocker = null
	if is_visible_in_tree() and not _done:
		# Held D-pad or stick: the next step as an arrow-key event (MenuInput).
		if not is_input_guarded():
			MenuInput.pump_repeat()
		if _pad_button != null:
			_focus_ring.queue_redraw()


## true while the gamepad's A is still ignored after opening (PAD_ACCEPT_GUARD).
func is_pad_accept_guarded() -> bool:
	return _shown_ms >= 0 and Time.get_ticks_msec() - _shown_ms < int(maxf(pad_accept_guard, input_guard) * 1000.0)


# --- Gamepad focus over the buttons ---

## Buttons the gamepad focus can reach: visible, enabled, clickable.
func focus_targets() -> Array[Button]:
	var result: Array[Button] = []
	for node in frame.find_children("*", "Button", true, false):
		var button := node as Button
		if button.is_visible_in_tree() and not button.disabled and button.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			result.append(button)
	return result


func get_focused_button() -> Button:
	return _pad_button if is_instance_valid(_pad_button) else null


## Puts the gamepad focus frame on button (null clears it).
func focus_button(button: Button) -> void:
	_pad_button = button if is_instance_valid(button) else null
	_focus_ring.visible = _pad_button != null
	_focus_ring.queue_redraw()


## Moves the focus to the nearest button in direction (D-pad / stick / arrows); without a focus it
## starts on the default button. Returns true when the dialog has buttons to move over.
func move_focus(step: Vector2i) -> bool:
	var targets := focus_targets()
	if targets.is_empty():
		return false
	var current := get_focused_button()
	if current == null or not targets.has(current):
		focus_button(_default_target(targets))
		UiSound.hover(self)
		return true
	var origin := current.get_global_rect().get_center()
	var best: Button = null
	var best_score := INF
	for target in targets:
		if target == current:
			continue
		var delta := target.get_global_rect().get_center() - origin
		var along := delta.dot(Vector2(step))
		if along <= 1.0:
			continue
		var score := along + absf(delta.cross(Vector2(step))) * 2.0
		if score < best_score:
			best_score = score
			best = target
	if best != null:
		focus_button(best)
		UiSound.hover(self)
	return true


## Presses the focused button (A / Enter). Returns false without a usable focus.
func press_focused() -> bool:
	var button := get_focused_button()
	if button == null or not button.is_visible_in_tree() or button.disabled:
		return false
	button.pressed.emit()
	return true


## With a gamepad in use the frame starts on the default option (dialogs built with UiDialog).
func _focus_default() -> void:
	if _done or input_handler.is_valid() or get_focused_button() != null:
		return
	var targets := focus_targets()
	for target in targets:
		if target.has_meta(META_PAD_OPTION):
			focus_button(_default_target(targets))
			return


func _default_target(targets: Array[Button]) -> Button:
	for target in targets:
		if target.has_meta(META_PAD_DEFAULT):
			return target
	for target in targets:
		if target.has_meta(META_PAD_OPTION):
			return target
	return targets[0]


func _draw_focus_ring() -> void:
	var button := get_focused_button()
	if button == null or not button.is_visible_in_tree():
		return
	var rect := _focus_ring.get_global_transform().affine_inverse() * button.get_global_rect()
	rect = rect.grow(UiKit.px(FOCUS_MARGIN))
	var width := float(UiKit.ART_SCALE)
	_focus_ring.draw_rect(Rect2(rect.position, Vector2(rect.size.x, width)), FOCUS_COLOR)
	_focus_ring.draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - width), Vector2(rect.size.x, width)), FOCUS_COLOR)
	_focus_ring.draw_rect(Rect2(rect.position, Vector2(width, rect.size.y)), FOCUS_COLOR)
	_focus_ring.draw_rect(Rect2(rect.position + Vector2(rect.size.x - width, 0), Vector2(width, rect.size.y)), FOCUS_COLOR)


## Keyboard/mouse <-> gamepad: the key bar symbols follow; a gamepad gets its focus frame.
func _on_device_changed(_kind: int) -> void:
	if _done:
		return
	if _has_key_hints:
		_build_key_hints()
	if InputGlyphs.is_gamepad():
		_focus_default()
	elif InputDevice.shared().kind == InputDevice.Kind.KEYBOARD_MOUSE and get_focused_button() != null:
		# The mouse picks by hovering; arrow keys bring the frame back.
		focus_button(null)


func _on_auto_finish() -> void:
	if not _done:
		finish(auto_finish_result)


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
	if result != null and result_filter.is_valid() and not result_filter.call(result):
		return
	_done = true
	_open_ids.erase(get_instance_id())
	if _shown_ms >= 0:
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
	_key_entries = entries.duplicate()
	_key_paused = paused
	_key_action = action
	_has_key_hints = true
	_build_key_hints()


## Key bar entries for the gamepad: number keys and arrows become one "D-pad auswählen" entry (and
## "A <caption>" when the dialog names no Enter); Enter, Esc and Tab show their buttons (UiChip).
static func pad_key_entries(entries: Array) -> Array:
	var arrows := DungeonTexts.t(&"MENU_KEY_ARROWS")
	var enter := DungeonTexts.t(&"MENU_KEY_ENTER")
	var has_accept := false
	for entry: Array in entries:
		if String(entry[0]) == enter:
			has_accept = true
	var result: Array = []
	var has_dpad := false
	for entry: Array in entries:
		var key := String(entry[0])
		var is_number := not key.is_empty() and key.left(1).is_valid_int()
		if key == arrows or is_number:
			if not has_dpad:
				result.append([arrows, DungeonTexts.t(&"MENU_HINT_MOVE")])
				has_dpad = true
			if is_number and not has_accept:
				result.append([enter, entry[1]])
				has_accept = true
			continue
		result.append(entry)
	return result


func _build_key_hints() -> void:
	var action := _key_action if is_instance_valid(_key_action) else null
	if action != null and action.get_parent() != null:
		# The action control (e.g. "Schließen") survives a rebuild.
		action.get_parent().remove_child(action)
	for child in key_bar.get_children():
		key_bar.remove_child(child)
		child.queue_free()
	var entries := pad_key_entries(_key_entries) if InputGlyphs.is_gamepad() else _key_entries
	var paused := _key_paused
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
		if not action.has_meta(&"compacted"):
			action.set_meta(&"compacted", true)
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
	_focus_ring = Control.new()
	_focus_ring.name = "PadFocus"
	_focus_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_focus_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_focus_ring.visible = false
	_focus_ring.draw.connect(_draw_focus_ring)
	add_child(_focus_ring)


## The accent stripe inside the panel border, from top to bottom (drawn under the content).
func _draw_accent() -> void:
	if accent.a <= 0.0:
		return
	# Right inside the outer frame of panel.png (3 art pixels), over its inner line.
	var inset := float(UiCard.FRAME_INSET * UiKit.ART_SCALE)
	var width := UiKit.px(ACCENT_WIDTH)
	frame.draw_rect(Rect2(inset, inset, width, frame.size.y - inset * 2.0), accent)
	frame.draw_rect(Rect2(inset + width, inset, UiKit.ART_SCALE, frame.size.y - inset * 2.0), Color(accent, 0.35))


## Content that moves with Godot's GUI focus (the guild menu in the village): D-pad and stick take
## one debounced step there (PadNav), before Godot would step on every stick motion event.
func _input(event: InputEvent) -> void:
	if _done or not is_visible_in_tree() or is_input_guarded():
		return
	if PadNav.step_gui_focus(event, frame):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		# Hidden under a dialog opened on top of it (pause menu -> options).
		return
	if is_input_guarded():
		# Just opened: a key still meant for the dialog before must not pick here.
		if MenuInput.is_pad_direction_event(event):
			# Keeps the stick state, so a stick pushed during the guard does not step afterwards.
			MenuInput.direction(event)
		if event.is_action_type():
			get_viewport().set_input_as_handled()
		return
	if MenuInput.is_pad_accept(event) and is_pad_accept_guarded():
		get_viewport().set_input_as_handled()
		return
	if input_handler.is_valid() and input_handler.call(event):
		get_viewport().set_input_as_handled()
		return
	if cancel_allowed and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		UiSound.back(self)
		finish(cancel_result)
		return
	var step := MenuInput.direction(event, false)
	if step != Vector2i.ZERO:
		if move_focus(step):
			get_viewport().set_input_as_handled()
		return
	if MenuInput.is_pad_accept(event):
		get_viewport().set_input_as_handled()
		_accept()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if hotkeys.has(key.keycode):
		get_viewport().set_input_as_handled()
		(hotkeys[key.keycode] as Callable).call()
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		if get_focused_button() != null or accept_action.is_valid() or accept_allowed:
			get_viewport().set_input_as_handled()
			_accept()


## Enter or A: the focused button, else accept_action, else the default result.
func _accept() -> void:
	if press_focused():
		return
	if accept_action.is_valid():
		accept_action.call()
	elif accept_allowed:
		finish(accept_result)


func _exit_tree() -> void:
	var device := InputDevice.shared()
	if device.changed.is_connected(_on_device_changed):
		device.changed.disconnect(_on_device_changed)
	# Never leave a stale pause reason behind, e.g. when the world is freed with the dialog open.
	_open_ids.erase(get_instance_id())
	if not _done:
		_done = true
		if _shown_ms >= 0:
			GameManager.release_pause(pause_reason)

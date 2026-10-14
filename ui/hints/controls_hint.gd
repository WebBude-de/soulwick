class_name ControlsHint
extends PanelContainer
## First-run controls card (UX1): small panel on the left edge of the first room, never pausing the
## game. Two steps of four keys each (move, aim, attack, dash, then special, weapon, use,
## overview). A row turns green as soon as the player uses that key; a step moves on when all four
## were used or after STAGE_TIME seconds. Shown once per save slot (SaveManager "hint_controls",
## marked when the card finishes). Reads input in _input without consuming it.

signal finished

const SEEN_ID: StringName = &"hint_controls"
const STAGES: Array[Array] = [
	[ControlsInfo.MOVE, ControlsInfo.AIM, ControlsInfo.ATTACK, ControlsInfo.DASH],
	[ControlsInfo.SPECIAL, ControlsInfo.SWITCH, ControlsInfo.INTERACT, ControlsInfo.OVERVIEW],
]
## Short captions for the card (the options page has the long ones).
const CAPTIONS := {
	ControlsInfo.MOVE: "Bewegen",
	ControlsInfo.AIM: "Zielen",
	ControlsInfo.ATTACK: "Angreifen",
	ControlsInfo.DASH: "Dash – ausweichen",
	ControlsInfo.SPECIAL: "Spezialangriff",
	ControlsInfo.SWITCH: "Waffe wechseln",
	ControlsInfo.INTERACT: "Benutzen",
	ControlsInfo.OVERVIEW: "Upgrades und Werte",
}
## TESTWERTE: longest time per step (unpaused game seconds), pause after the last key of a step.
const STAGE_TIME := 16.0
const DONE_LINGER := 0.9
## Mouse travel (px) that counts as "aimed".
const AIM_DISTANCE := 60.0
## Layout in mockup pixels.
const WIDTH := 124.0
const KEY_WIDTH := 46.0
const EDGE_MARGIN := 8.0

var _stage := -1
var _rows: Dictionary = {}
var _done: Dictionary = {}
var _time_left := 0.0
var _aim_travel := 0.0
var _finishing := false
var _list: VBoxContainer = null
var _eyebrow: Label = null


## True while the save has not seen the card yet.
static func should_show() -> bool:
	return not SaveManager.has_seen(SEEN_ID)


func _ready() -> void:
	theme = UiKit.get_theme()
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiKit.padded_style(&"dark", 5, 6))
	custom_minimum_size.x = UiKit.px(WIDTH)
	var box := UiKit.vbox(int(UiKit.px(3)))
	add_child(box)
	_eyebrow = UiKit.eyebrow("", UiKit.COLOR_GOLD)
	box.add_child(_eyebrow)
	_list = UiKit.vbox(int(UiKit.px(3)))
	box.add_child(_list)
	var footer := UiKit.text_label("Alle Tasten: Esc → Optionen", UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
	box.add_child(footer)
	minimum_size_changed.connect(_layout)
	get_viewport().size_changed.connect(_layout)
	EventBus.room_entered.connect(_on_room_entered)
	_show_stage(0)
	_layout.call_deferred()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.4)


func _process(delta: float) -> void:
	if _finishing:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_next_stage()


func _input(event: InputEvent) -> void:
	if _finishing or _stage < 0:
		return
	for id: StringName in STAGES[_stage]:
		if not _done.has(id) and _matches(id, event):
			mark_done(id)


func get_stage() -> int:
	return _stage


func is_done(id: StringName) -> bool:
	return _done.has(id)


## Row id as used: green caption, dimmed key. The step ends shortly after its last key.
func mark_done(id: StringName) -> void:
	if _done.has(id) or not _rows.has(id):
		return
	_done[id] = true
	var row := _rows[id] as Control
	var caption := row.get_meta(&"caption") as Label
	caption.add_theme_color_override("font_color", UiKit.COLOR_SUCCESS)
	var tween := row.create_tween()
	tween.tween_property(row, "modulate", Color(1.4, 1.4, 1.4, 1.0), 0.08)
	tween.tween_property(row, "modulate", Color(1, 1, 1, 0.55), 0.3)
	var all_done := true
	for other: StringName in STAGES[_stage]:
		if not _done.has(other):
			all_done = false
	if all_done:
		_time_left = minf(_time_left, DONE_LINGER)


## Fades out, marks the hint as seen for this save and frees itself.
func finish() -> void:
	if _finishing:
		return
	_finishing = true
	SaveManager.mark_seen(SEEN_ID)
	finished.emit()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)


func _next_stage() -> void:
	if _stage + 1 < STAGES.size():
		_show_stage(_stage + 1)
	else:
		finish()


func _show_stage(stage: int) -> void:
	_stage = stage
	_time_left = STAGE_TIME
	_rows.clear()
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_eyebrow.text = ("Steuerung %d / %d" % [stage + 1, STAGES.size()]).to_upper()
	for id: StringName in STAGES[stage]:
		var row := UiKit.hbox(int(UiKit.px(5)))
		row.add_child(OptionsView.key_chip(ControlsInfo.key_text(id), KEY_WIDTH))
		var caption := UiKit.text_label(CAPTIONS.get(id, ControlsInfo.caption(id)), UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT)
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(caption)
		row.set_meta(&"caption", caption)
		_list.add_child(row)
		_rows[id] = row
		row.modulate.a = 0.0
		row.create_tween().tween_property(row, "modulate:a", 1.0, 0.25).set_delay(0.06 * _rows.size())


func _matches(id: StringName, event: InputEvent) -> bool:
	if id == ControlsInfo.AIM:
		var motion := event as InputEventMouseMotion
		if motion == null:
			return false
		_aim_travel += motion.relative.length()
		return _aim_travel >= AIM_DISTANCE
	for action in ControlsInfo.actions(id):
		if event.is_action_pressed(action):
			return true
	return false


## Left edge, vertically centred (between the hearts and the weapon slots of the HUD).
func _layout() -> void:
	var parent_size := get_viewport_rect().size
	var own := get_combined_minimum_size()
	size = own
	position = Vector2(UiKit.px(EDGE_MARGIN), floorf((parent_size.y - own.y) * 0.5))


func _on_room_entered(room_index: int) -> void:
	# The card belongs to the first room; moving on ends it.
	if room_index >= 2:
		finish()

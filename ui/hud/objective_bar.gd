class_name ObjectiveBar
extends VBoxContainer
## Task bar at the top centre (KONZEPT_RAEUME_V2 §1.4, 07_ui.md, R3): mode symbol in the mode
## colour, mode name, progress text ("Welle 1/3 · 6 Gegner"), an optional bar (share or count) and
## the time or the share on the right; an optional status line under it ("Der Dorfbewohner bleibt
## stehen"). Danger (flame < 30 %) turns it red and lets it pulse. At the end a short success or
## failure moment, then it fades out. Shows a RoomObjective, computes nothing itself.
## DungeonUI owns it and hides it while the boss bar is up (the boss bar replaces it).
## Sizes in mockup pixels (UiKit.px).

## Faded out after the result moment.
signal done

const ICON_SIZE := 12.0
const MIN_WIDTH := 72.0
const PROGRESS_SIZE := Vector2(58, 3)
const VALUE_MIN_WIDTH := 16.0
## Result moment ("Geschafft!") before the bar fades (seconds, TESTWERT).
const RESULT_TIME := 1.8
const FADE_TIME := 0.4
## Danger pulse: speed (rad/s) and the brightest red.
const PULSE_SPEED := 7.0
const PULSE_COLOR := Color(1.45, 0.7, 0.7)
const DANGER_TINT := Color(1.0, 0.55, 0.5)

var objective: RoomObjective = null

var _panel: PanelContainer = null
var _icon: TextureRect = null
var _title: Label = null
var _detail: Label = null
var _value: Label = null
var _progress: ProgressBar = null
var _progress_fill: StyleBoxFlat = null
var _status_panel: PanelContainer = null
var _status: Label = null
var _pulse := 0.0
var _closing := false
## The result moment of the goal before (pop, wait, fade, close). A new goal cancels it, so the old
## goal's close never takes the new one away (R4a bug: next mode room within ~2.2 s).
var _result_tween: Tween = null


func _init() -> void:
	name = "ObjectiveBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", int(UiKit.px(2)))
	_build()


## Shows objective (and follows it until it ends).
func bind(goal: RoomObjective) -> void:
	_cancel_result()
	unbind()
	objective = goal
	_closing = false
	modulate = Color.WHITE
	_panel.scale = Vector2.ONE
	# A new goal pops in (R8).
	UiKit.pop_in(_panel, 0.0, 0.85, 0.24)
	goal.changed.connect(refresh)
	goal.finished.connect(_on_finished)
	goal.tree_exiting.connect(_on_objective_gone)
	refresh()


func unbind() -> void:
	if objective != null and is_instance_valid(objective):
		if objective.changed.is_connected(refresh):
			objective.changed.disconnect(refresh)
		if objective.finished.is_connected(_on_finished):
			objective.finished.disconnect(_on_finished)
		if objective.tree_exiting.is_connected(_on_objective_gone):
			objective.tree_exiting.disconnect(_on_objective_gone)
	objective = null


## true while a goal is shown (also during its result moment).
func is_active() -> bool:
	return objective != null and is_instance_valid(objective)


func refresh() -> void:
	if not is_active():
		return
	var color := objective.get_ui_color()
	var icon_texture := objective.get_icon()
	_icon.texture = icon_texture
	_icon.visible = icon_texture != null
	_icon.modulate = color
	if objective.is_finished():
		_title.text = DungeonTexts.t(&"OBJECTIVE_DONE" if objective.success else &"OBJECTIVE_FAILED")
		_title.add_theme_color_override("font_color", UiKit.COLOR_SUCCESS if objective.success else UiKit.COLOR_DANGER_SOFT)
		_detail.visible = false
		_progress.visible = false
		_value.visible = false
		_status_panel.visible = false
		_set_danger_look(false)
		return
	_title.text = objective.get_title()
	_title.add_theme_color_override("font_color", UiKit.COLOR_DANGER_SOFT if objective.danger else color)
	_detail.text = objective.label_text
	_detail.visible = not objective.label_text.is_empty()
	_progress.visible = objective.has_progress()
	if objective.has_progress():
		_progress.value = objective.get_ratio()
		_progress_fill.bg_color = UiKit.COLOR_DANGER if objective.danger else color
	var value_text := RoomObjective.format_time(objective.time_left) if objective.has_time() else objective.get_progress_text()
	_value.text = value_text
	_value.visible = not value_text.is_empty()
	_value.add_theme_color_override("font_color", UiKit.COLOR_DANGER_SOFT if objective.danger else UiKit.COLOR_TEXT)
	_status.text = objective.status_text
	_status_panel.visible = not objective.status_text.is_empty()
	_set_danger_look(objective.danger)


# --- For tests and tools ---

func get_title_text() -> String:
	return _title.text


func get_detail_text() -> String:
	return _detail.text if _detail.visible else ""


func get_value_text() -> String:
	return _value.text if _value.visible else ""


func get_status_text() -> String:
	return _status.text if _status_panel.visible else ""


func is_progress_shown() -> bool:
	return _progress.visible


func is_danger_shown() -> bool:
	return is_active() and objective.danger and not objective.is_finished()


func _process(delta: float) -> void:
	if not is_danger_shown():
		return
	_pulse += delta * PULSE_SPEED
	_panel.modulate = Color.WHITE.lerp(PULSE_COLOR, (sin(_pulse) + 1.0) * 0.5)


func _set_danger_look(on: bool) -> void:
	_panel.self_modulate = DANGER_TINT if on else Color.WHITE
	if not on:
		_panel.modulate = Color.WHITE
		_pulse = 0.0


func _on_finished(_success: bool) -> void:
	refresh()
	_closing = true
	_cancel_result()
	var goal := objective
	var tween := create_tween()
	_result_tween = tween
	_panel.scale = Vector2(1.08, 1.08)
	_panel.pivot_offset = _panel.size * 0.5
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(RESULT_TIME)
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(_close_after_result.bind(goal))


## End of the result moment: closes only if the bar still shows that goal.
func _close_after_result(goal: RoomObjective) -> void:
	_result_tween = null
	if objective != goal and objective != null:
		return
	_close()


## true while the result moment of a finished goal plays (for tests).
func is_showing_result() -> bool:
	return _result_tween != null and _result_tween.is_valid() and _result_tween.is_running()


func _cancel_result() -> void:
	if _result_tween != null and _result_tween.is_valid():
		_result_tween.kill()
	_result_tween = null


func _on_objective_gone() -> void:
	if _closing:
		# The room went away during the result moment: the moment still plays out.
		return
	unbind()
	_close()


func _close() -> void:
	_closing = false
	unbind()
	visible = false
	modulate = Color.WHITE
	done.emit()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Bar"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", UiKit.padded_style(&"dark", 3, 6))
	_panel.custom_minimum_size.x = UiKit.px(MIN_WIDTH)
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(_panel)
	var row := UiKit.hbox(int(UiKit.px(5)))
	_panel.add_child(row)
	_icon = UiKit.pixel_icon(null, ICON_SIZE)
	_icon.name = "Icon"
	_icon.custom_minimum_size = Vector2.ONE * UiKit.art_px(ICON_SIZE, 16.0)
	row.add_child(_icon)
	var middle := UiKit.vbox(int(UiKit.px(1)))
	middle.alignment = BoxContainer.ALIGNMENT_CENTER
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(middle)
	var line := UiKit.hbox(int(UiKit.px(5)))
	middle.add_child(line)
	_title = UiKit.text_label("", UiKit.SIZE_BODY, UiKit.COLOR_GOLD, true)
	_title.name = "Title"
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(_title)
	_detail = UiKit.text_label("", UiKit.SIZE_BODY, UiKit.COLOR_TEXT, true)
	_detail.name = "Detail"
	_detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(_detail)
	_progress = ProgressBar.new()
	_progress.name = "Progress"
	_progress.show_percentage = false
	_progress.max_value = 1.0
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress.custom_minimum_size = UiKit.pxv(PROGRESS_SIZE.x, PROGRESS_SIZE.y)
	_progress_fill = UiKit.bar_style(UiKit.COLOR_GOLD)
	_progress.add_theme_stylebox_override("fill", _progress_fill)
	_progress.add_theme_stylebox_override("background", UiKit.bar_style(UiKit.COLOR_SHADOW))
	middle.add_child(_progress)
	_value = UiKit.text_label("", UiKit.SIZE_KEY_HINT, UiKit.COLOR_TEXT, true)
	_value.name = "Value"
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value.custom_minimum_size.x = UiKit.px(VALUE_MIN_WIDTH)
	row.add_child(_value)
	_status_panel = PanelContainer.new()
	_status_panel.name = "Status"
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_panel.add_theme_stylebox_override("panel", UiKit.padded_style(&"dark", 2, 6))
	_status_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_status_panel.visible = false
	add_child(_status_panel)
	_status = UiKit.text_label("", UiKit.SIZE_BODY, UiKit.COLOR_DANGER_SOFT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_panel.add_child(_status)

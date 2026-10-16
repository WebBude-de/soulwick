class_name CoopWaitBanner
extends VBoxContainer
## The group countdown (online test 16.10.2026, like the truck of R.E.P.O.): a big number at the top
## centre of the screen (CoopWaitLine places it below the HUD's top bars, never over the middle of
## the playfield) with one line under it. A straggler gets it big - "7" over "Beeil dich!" - a
## player who waits gets the same number smaller over "Warte auf <Name> …". Every new second pops
## the number and ticks (UI sound countdown_tick); from CoopRules.WAIT_COUNTDOWN_URGENT seconds on it
## is red and pops harder. Look only: the host's countdown decides (NetDungeon, NetSide).
## Mouse ignored, readable on a phone (sizes in mockup pixels, UiKit scales them).

## Mockup pixels: the number for a straggler / for a waiting player, the line under it.
const HURRY_NUMBER_SIZE := 40
const WAIT_NUMBER_SIZE := 20
const HURRY_CAPTION_SIZE := UiKit.SIZE_HEADING
const WAIT_CAPTION_SIZE := UiKit.SIZE_BODY
const COLOR := Color(1.0, 0.85, 0.4)
const URGENT_COLOR := Color(1.0, 0.32, 0.26)
## Pop of a new second (scale), harder while urgent; the tick's volume (dB) for a straggler and for a
## waiting player.
const POP_SCALE := 1.35
const URGENT_POP_SCALE := 1.6
const POP_TIME := 0.25
const TICK_SOUND := &"countdown_tick"
const HURRY_TICK_DB := -4.0
const WAIT_TICK_DB := -14.0

## Tests and tools: seconds ticked, pops while urgent.
var ticks := 0
var urgent_ticks := 0

var _number: Label = null
var _caption: Label = null
var _seconds := -1
var _hurry := false
var _tween: Tween = null


func _init() -> void:
	name = "CoopWaitBanner"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 0)
	visible = false
	_number = _outlined(UiKit.text_label("", WAIT_NUMBER_SIZE, COLOR, true), 4.0)
	_number.name = "Number"
	add_child(_number)
	_caption = _outlined(UiKit.text_label("", WAIT_CAPTION_SIZE, COLOR, true), 2.0)
	_caption.name = "Caption"
	add_child(_caption)


## Shows the countdown: time_left (seconds, shown as whole seconds rounded up), the line under it,
## hurry = big for a straggler. Call it every frame while the countdown runs.
func show_countdown(time_left: float, caption: String, hurry: bool) -> void:
	var seconds := CoopRules.countdown_seconds(time_left)
	var urgent := CoopRules.countdown_urgent(time_left)
	var restyle := not visible or hurry != _hurry
	visible = true
	_hurry = hurry
	if _caption.text != caption:
		_caption.text = caption
	if restyle:
		_number.add_theme_font_size_override("font_size", UiKit.font_px(HURRY_NUMBER_SIZE if hurry else WAIT_NUMBER_SIZE))
		_caption.add_theme_font_size_override("font_size", UiKit.font_px(HURRY_CAPTION_SIZE if hurry else WAIT_CAPTION_SIZE))
	var color := URGENT_COLOR if urgent else COLOR
	_number.add_theme_color_override("font_color", color)
	_caption.add_theme_color_override("font_color", color if hurry else COLOR)
	if seconds != _seconds:
		var first := _seconds < 0
		_seconds = seconds
		_number.text = str(seconds)
		if not first or hurry:
			_tick(urgent)


func hide_countdown() -> void:
	if not visible:
		return
	visible = false
	_seconds = -1
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_number.scale = Vector2.ONE


## Whole seconds on screen (-1 = hidden), for tests and tools.
func get_seconds() -> int:
	return _seconds if visible else -1


func is_hurry() -> bool:
	return visible and _hurry


func is_urgent() -> bool:
	return visible and _seconds >= 0 and _seconds <= CoopRules.WAIT_COUNTDOWN_URGENT


func get_caption() -> String:
	return _caption.text if visible else ""


func get_number_color() -> Color:
	return _number.get_theme_color("font_color")


func get_number_font_size() -> int:
	return _number.get_theme_font_size("font_size")


func _tick(urgent: bool) -> void:
	ticks += 1
	if urgent:
		urgent_ticks += 1
	# The box lays the number out over its whole width (centred text): pop around the middle.
	_number.pivot_offset = Vector2(_number.size.x * 0.5, _number.get_combined_minimum_size().y * 0.5)
	_number.scale = Vector2.ONE * (URGENT_POP_SCALE if urgent else POP_SCALE)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_ignore_time_scale(true)
	_tween.tween_property(_number, "scale", Vector2.ONE, POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if is_inside_tree():
		Sfx.play_ui(self, TICK_SOUND, HURRY_TICK_DB if _hurry else WAIT_TICK_DB)


func _outlined(label: Label, outline: float) -> Label:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_constant_override("outline_size", int(UiKit.px(outline)))
	label.add_theme_color_override("font_outline_color", UiKit.COLOR_SHADOW)
	return label

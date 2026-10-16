class_name IntroCountdown
extends Control
## The 3-2-1 of the room intro (07_ui.md, R3): each number pops in, shrinks and fades; 0 shows
## "Los!". Look only; RoomIntro decides when (countdown_tick), DungeonUI shows it and plays the
## tick. Never blocks input (mouse ignored).
## Online test 16.10.2026 (texts over the enemies): the number sits in the top band right under the
## goal banner (DungeonUI sets top_px), smaller than before, not in the middle of the playfield.

## Number size in mockup pixels (TESTWERTE; were 30 and 22 in the middle of the screen).
const NUMBER_SIZE := 22
const GO_SIZE := 16
## Height of the number's centre as a share of the screen when nobody set top_px (upper third,
## above the player in the middle).
const CENTER_Y := 0.28
const POP_SCALE := 1.5

## Top edge of the number in viewport px (below the goal banner); negative = CENTER_Y.
var top_px := -1.0
const NUMBER_TIME := 0.5
const GO_TIME := 0.7

var _label: Label = null
var _tween: Tween = null


func _init() -> void:
	name = "IntroCountdown"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_label = UiKit.text_label("", NUMBER_SIZE, UiKit.COLOR_TEXT, true)
	_label.name = "Number"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_constant_override("outline_size", int(UiKit.px(3)))
	_label.add_theme_color_override("font_outline_color", UiKit.COLOR_SHADOW)
	_label.modulate.a = 0.0
	add_child(_label)


## Shows number (3, 2, 1) or "Los!" for 0, outlined in the mode colour.
func show_number(number: int, color := UiKit.COLOR_DANGER) -> void:
	var go := number <= 0
	_label.text = DungeonTexts.t(&"INTRO_GO") if go else str(number)
	_label.add_theme_font_size_override("font_size", UiKit.font_px(GO_SIZE if go else NUMBER_SIZE))
	_label.add_theme_color_override("font_color", color.lightened(0.35) if go else UiKit.COLOR_TEXT)
	_label.add_theme_color_override("font_outline_color", color.darkened(0.55))
	_label.reset_size()
	var view := get_viewport_rect().size
	var centre_y := top_px + _label.size.y * 0.5 if top_px >= 0.0 else view.y * CENTER_Y
	_label.position = Vector2(view.x * 0.5, centre_y) - _label.size * 0.5
	# Under a banner the pop grows downwards, never up into the banner.
	_label.pivot_offset = Vector2(_label.size.x * 0.5, 0.0 if top_px >= 0.0 else _label.size.y * 0.5)
	_label.scale = Vector2.ONE * POP_SCALE
	_label.modulate.a = 1.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_ignore_time_scale(true)
	_tween.set_parallel(true)
	_tween.tween_property(_label, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_label, "modulate:a", 0.0, 0.25).set_delay((GO_TIME if go else NUMBER_TIME) - 0.25)


## Hides the number at once (intro skipped or gone).
func clear() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_label.modulate.a = 0.0


## Where the number is on screen (viewport px; empty while hidden), for the overlay dodge.
func get_number_rect() -> Rect2:
	if _label.modulate.a <= 0.01:
		return Rect2()
	return _label.get_global_rect()


## The text on screen ("" when hidden), for tests.
func get_text() -> String:
	return _label.text if _label.modulate.a > 0.01 else ""

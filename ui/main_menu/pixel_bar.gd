class_name PixelBar
extends Control
## A small pixel progress bar (D-188, KF1/KF2): forge levels x/20 in the progress overview and the XP
## bar of the account level. Dark frame, dark track, a fill in the given colour with a light top
## line; whole art pixels so it stays crisp. ratio can be tweened (the run end fills it).

## Height of the bar in mockup pixels.
const DEFAULT_HEIGHT := 5.0

## 0..1, redraws on change.
var ratio := 0.0:
	set(value):
		ratio = clampf(value, 0.0, 1.0)
		queue_redraw()
var fill_color := UiKit.COLOR_GOLD:
	set(value):
		fill_color = value
		queue_redraw()


static func create(start_ratio := 0.0, color := UiKit.COLOR_GOLD, spec_width := 0.0, spec_height := DEFAULT_HEIGHT) -> PixelBar:
	var bar := PixelBar.new()
	bar.ratio = start_ratio
	bar.fill_color = color
	bar.custom_minimum_size = Vector2(UiKit.px(spec_width), UiKit.px(spec_height))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return bar


func _draw() -> void:
	var unit := float(UiKit.ART_SCALE)
	var outer := Rect2(Vector2.ZERO, size)
	draw_rect(outer, UiKit.COLOR_SHADOW)
	var inner := outer.grow(-unit)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	draw_rect(inner, UiKit.COLOR_BG)
	var width := floorf(inner.size.x * ratio / unit) * unit
	if ratio > 0.0:
		width = maxf(width, unit)
	if width <= 0.0:
		return
	var fill := Rect2(inner.position, Vector2(width, inner.size.y))
	draw_rect(fill, fill_color)
	draw_rect(Rect2(fill.position, Vector2(fill.size.x, unit)), fill_color.lightened(0.35))
	if fill.size.y > unit * 2.0:
		draw_rect(Rect2(fill.position + Vector2(0, fill.size.y - unit), Vector2(fill.size.x, unit)), fill_color.darkened(0.3))

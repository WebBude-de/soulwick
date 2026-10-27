class_name MatePointers
extends Control
## Co-op (MP5, D-191; D-184 OFFEN "Pfeil am Rand"): where the standing teammates are when they are off
## screen. At the screen edge an arrow in the mate's co-op colour points towards him, his name
## (shortened) beside it; nothing while he is on screen. Downed mates have their own markers
## (ui/hints/downed_markers.gd), so the NetDungeon feeds only standing mates. Look only: the arrow is
## the pixel arrow (PixelArrow, feedback #a1a651ae), tinted in the mate's colour; the NetDungeon calls
## set_targets() every frame with the viewport position, colour and name.

const NODE_NAME := &"MatePointers"
const COLOR_SHADOW := Color("#1c1a2b")
## Sizes in mockup px: half the arrow (for the name's place; the picture is PixelArrow's), edge
## margin (inside the downed markers' edge), name gap.
const ARROW := 9.0
const EDGE_MARGIN := 22.0
const NAME_GAP := 4.0
## Longest name shown at the edge (characters), the rest is cut with "…".
const NAME_CHARS := 8

## [{"point": Vector2 (viewport px of the mate), "color": Color, "name": String}]
var _targets: Array[Dictionary] = []


func _init() -> void:
	name = NODE_NAME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Standing mates to point at this frame; an empty list clears the arrows.
func set_targets(targets: Array[Dictionary]) -> void:
	if _targets.is_empty() and targets.is_empty():
		return
	_targets = targets
	queue_redraw()


func get_target_count() -> int:
	return _targets.size()


## Arrows drawn right now (mates off screen).
func get_arrow_count() -> int:
	var count := 0
	for target in _targets:
		if not is_on_screen(target.get("point", Vector2.ZERO)):
			count += 1
	return count


func get_view() -> Rect2:
	return get_viewport_rect()


func is_on_screen(point: Vector2) -> bool:
	return get_view().has_point(point)


## Point on view's edge (inside margin) on the way from its centre to point.
static func edge_point(view: Rect2, point: Vector2, margin: float) -> Vector2:
	var inner := view.grow(-margin)
	var centre := inner.get_center()
	var direction := point - centre
	if direction.is_zero_approx():
		return centre
	var half := inner.size * 0.5
	var scale_x := half.x / absf(direction.x) if not is_zero_approx(direction.x) else INF
	var scale_y := half.y / absf(direction.y) if not is_zero_approx(direction.y) else INF
	return centre + direction * minf(1.0, minf(scale_x, scale_y))


## The name as shown at the edge.
static func short_name(text: String) -> String:
	return text if text.length() <= NAME_CHARS else text.substr(0, NAME_CHARS - 1) + "…"


func _draw() -> void:
	var view := get_view()
	for target in _targets:
		var point: Vector2 = target.get("point", Vector2.ZERO)
		if is_on_screen(point):
			continue
		var at := edge_point(view, point, UiKit.px(EDGE_MARGIN))
		var angle := (point - view.get_center()).angle()
		var color: Color = target.get("color", Color.WHITE)
		_draw_arrow(at, angle, color)
		_draw_name(at, angle, short_name(str(target.get("name", ""))), color)


## The pixel arrow centred on point, its outline is the shadow (no smoothed polygon).
func _draw_arrow(point: Vector2, angle: float, color: Color) -> void:
	var size := PixelArrow.screen_size()
	draw_texture_rect(PixelArrow.texture_for(angle), Rect2((point - size * 0.5).round(), size), false, color)


## The name behind the arrow, towards the screen centre, kept inside the screen.
func _draw_name(point: Vector2, angle: float, text: String, color: Color) -> void:
	if text.is_empty():
		return
	var font := UiKit.FONT
	var font_size := UiKit.font_px(UiKit.SIZE_BODY)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var back := -Vector2.from_angle(angle)
	var centre := point + back * (UiKit.px(ARROW) + UiKit.px(NAME_GAP) + text_size.length() * 0.5)
	var view := get_view().grow(-2.0)
	var origin := centre - text_size * 0.5
	origin.x = clampf(origin.x, view.position.x, view.end.x - text_size.x)
	origin.y = clampf(origin.y, view.position.y, view.end.y - text_size.y)
	var baseline := origin + Vector2(0, font.get_ascent(font_size))
	draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(COLOR_SHADOW, 0.9))
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

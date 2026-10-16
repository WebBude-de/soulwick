extends Control
## Where the downed teammates are (D-084; feedback 16.10.2026): over a downed mate on screen a
## pulsing chevron (with a ring that fills while somebody helps), at the screen edge an arrow
## towards a mate off screen. Drawn, no sprites; look only. DungeonUI feeds it every frame with
## set_targets() from the players it watches. No class_name (preloaded).

const COLOR := Color("#ff7366")
const COLOR_HELP := Color("#5fcd62")
const COLOR_SHADOW := Color("#1c1a2b")
## Sizes in mockup px: chevron, its height over the body centre, edge arrow, edge margin, ring.
const CHEVRON := 6.0
const CHEVRON_LIFT := 34.0
const ARROW := 8.0
const EDGE_MARGIN := 16.0
const RING := 7.0
## Pulse of the chevron (per second) and how far it bobs (mockup px).
const PULSE_SPEED := 4.0
const BOB := 2.0

## [{"point": Vector2 (viewport px of the body), "share": float (revive 0..1), "lift": float}]
var _targets: Array[Dictionary] = []
var _time := 0.0


func _init() -> void:
	name = "DownedMarkers"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	if _targets.is_empty():
		return
	_time += delta
	queue_redraw()


## Downed mates to mark this frame (see _targets); an empty list clears the markers.
func set_targets(targets: Array[Dictionary]) -> void:
	var was_empty := _targets.is_empty()
	_targets = targets
	if not (was_empty and targets.is_empty()):
		queue_redraw()


func get_target_count() -> int:
	return _targets.size()


## True when point lies inside the visible screen with the edge margin (on screen: chevron).
func is_on_screen(point: Vector2) -> bool:
	return get_view().grow(-UiKit.px(EDGE_MARGIN)).has_point(point)


func get_view() -> Rect2:
	return get_viewport_rect()


## Point on the screen edge (inside the margin) on the way from the screen centre to point.
func edge_point(point: Vector2) -> Vector2:
	var view := get_view().grow(-UiKit.px(EDGE_MARGIN))
	var centre := view.get_center()
	var direction := point - centre
	if direction.is_zero_approx():
		return centre
	var half := view.size * 0.5
	var scale_x := half.x / absf(direction.x) if not is_zero_approx(direction.x) else INF
	var scale_y := half.y / absf(direction.y) if not is_zero_approx(direction.y) else INF
	return centre + direction * minf(1.0, minf(scale_x, scale_y))


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_time * PULSE_SPEED)
	for target in _targets:
		var point: Vector2 = target.get("point", Vector2.ZERO)
		var share: float = target.get("share", 0.0)
		if is_on_screen(point):
			var lift: float = target.get("lift", UiKit.px(CHEVRON_LIFT))
			var tip := point + Vector2(0.0, -lift - UiKit.px(BOB) * pulse)
			_draw_chevron(tip, share, pulse)
		else:
			_draw_edge_arrow(edge_point(point), (point - get_view().get_center()).angle(), share, pulse)


## Downward chevron with its tip at tip; a ring around it fills with the revive progress.
func _draw_chevron(tip: Vector2, share: float, pulse: float) -> void:
	var size := UiKit.px(CHEVRON)
	var outline := PackedVector2Array([tip + Vector2(0, 2), tip + Vector2(-size - 2, -size - 1), tip + Vector2(size + 2, -size - 1)])
	draw_colored_polygon(outline, COLOR_SHADOW)
	draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-size, -size), tip + Vector2(size, -size)]), Color(COLOR, 0.75 + 0.25 * pulse))
	if share > 0.0:
		_draw_ring(tip + Vector2(0.0, -size - UiKit.px(RING) - 2.0), share)


## Arrow at point on the screen edge, pointing along angle.
func _draw_edge_arrow(point: Vector2, angle: float, share: float, pulse: float) -> void:
	var size := UiKit.px(ARROW) * (1.0 + 0.12 * pulse)
	var forward := Vector2.from_angle(angle)
	var side := forward.orthogonal()
	var tip := point + forward * size
	var shape := PackedVector2Array([tip, point - forward * size * 0.6 + side * size * 0.8,
			point - forward * size * 0.2, point - forward * size * 0.6 - side * size * 0.8])
	var shadow := PackedVector2Array()
	for p in shape:
		shadow.append(p + Vector2(2, 2))
	draw_colored_polygon(shadow, COLOR_SHADOW)
	draw_colored_polygon(shape, COLOR)
	if share > 0.0:
		_draw_ring(point - forward * size * 1.6, share)


func _draw_ring(centre: Vector2, share: float) -> void:
	var radius := UiKit.px(RING)
	draw_arc(centre, radius, 0.0, TAU, 24, Color(COLOR_SHADOW, 0.85), 3.0)
	draw_arc(centre, radius, -PI * 0.5, -PI * 0.5 + TAU * clampf(share, 0.0, 1.0), 24, COLOR_HELP, 3.0)

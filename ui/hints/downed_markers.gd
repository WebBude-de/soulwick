extends Control
## Where the downed teammates are (D-084; feedback 16.10.2026): over a downed mate on screen a
## pulsing chevron (with a ring that fills while somebody helps), at the screen edge an arrow
## towards a mate off screen. Pixel art (D-218): chevron and ring drawn with PixelDraw, the arrow is
## PixelArrow; look only. DungeonUI feeds it every frame with
## set_targets() from the players it watches. No class_name (preloaded).

const COLOR := Color("#ff7366")
const COLOR_HELP := Color("#5fcd62")
const COLOR_SHADOW := Color("#1c1a2b")
## Sizes in mockup px: chevron, its height over the body centre, edge margin, ring.
## Chevron and ring are drawn in UI art pixels (UiKit.ART_SCALE screen px each, D-218), the edge
## arrow is the PixelArrow picture.
const CHEVRON := 6.0
const CHEVRON_LIFT := 34.0
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
	# Pulses in two hard steps (pixel art, D-218).
	var pulse := 1.0 if sin(_time * PULSE_SPEED) >= 0.0 else 0.0
	for target in _targets:
		var point: Vector2 = target.get("point", Vector2.ZERO)
		var share: float = target.get("share", 0.0)
		if is_on_screen(point):
			var lift: float = target.get("lift", UiKit.px(CHEVRON_LIFT))
			var tip := point + Vector2(0.0, -lift - UiKit.px(BOB) * pulse)
			_draw_chevron(tip, share, pulse)
		else:
			_draw_edge_arrow(edge_point(point), (point - get_view().get_center()).angle(), share, pulse)


## Downward pixel chevron with its tip at tip; a pixel ring above it fills with the revive progress.
func _draw_chevron(tip: Vector2, share: float, pulse: float) -> void:
	var a := float(UiKit.ART_SCALE)
	var at := PixelDraw.snap(tip, a)
	var outline := PackedVector2Array([at + Vector2(0, 1.5 * a), at + Vector2(-(CHEVRON + 1.5) * a, -(CHEVRON + 1.0) * a), at + Vector2((CHEVRON + 1.5) * a, -(CHEVRON + 1.0) * a)])
	PixelDraw.polygon(self, outline, COLOR_SHADOW, a)
	var fill := PackedVector2Array([at, at + Vector2(-CHEVRON * a, -CHEVRON * a), at + Vector2(CHEVRON * a, -CHEVRON * a)])
	PixelDraw.polygon(self, fill, Color(COLOR, 0.75 + 0.25 * pulse), a)
	if share > 0.0:
		_draw_ring(at + Vector2(0.0, -(CHEVRON + RING + 2.0) * a), share)


## The pixel arrow (PixelArrow, like the arrows to mates off screen) at point on the screen edge,
## pointing along angle, in the downed colour; its outline is the shadow.
func _draw_edge_arrow(point: Vector2, angle: float, share: float, pulse: float) -> void:
	var size := PixelArrow.screen_size()
	draw_texture_rect(PixelArrow.texture_for(angle), Rect2((point - size * 0.5).round(), size), false, Color(COLOR, 0.8 + 0.2 * pulse))
	if share > 0.0:
		var back := size.x * 0.5 + (RING + 1.0) * UiKit.ART_SCALE
		_draw_ring(point - Vector2.from_angle(angle) * back, share)


## Pixel ring: dark track, green part for the revive progress (from the top, clockwise).
func _draw_ring(centre: Vector2, share: float) -> void:
	var a := float(UiKit.ART_SCALE)
	PixelDraw.ring(self, centre, RING * a, Color(COLOR_SHADOW, 0.85), 1, a)
	PixelDraw.arc(self, centre, RING * a, -PI * 0.5, TAU * clampf(share, 0.0, 1.0), COLOR_HELP, 1, a)

class_name PixelRingWave
extends Node2D
## Expanding, fading pixel ring (D-218): the shock wave of a boss stomp without its art, and the
## pixel twin of RingWave (weapons/effects/ring_wave.gd, a smooth Line2D) with the same spawn()
## arguments. Grows with an ease-out from start_scale to radius, fades in FADE_STEPS hard steps and
## frees itself. Optics only.

## Fade-out in this many hard alpha steps.
const FADE_STEPS := 3

var radius := 40.0
var color := Color.WHITE
var start_scale := 0.2
## Ring thickness in art pixels.
var thickness := 2
## 0 = start, 1 = done (tweened).
var progress := 0.0:
	set(value):
		progress = value
		queue_redraw()


static func spawn(parent: Node, global_pos: Vector2, ring_radius: float, ring_color: Color, duration := 0.35, ring_width := 5.0, from_scale := 0.2) -> PixelRingWave:
	if parent == null or not parent.is_inside_tree() or ring_radius <= 0.0:
		return null
	var ring := PixelRingWave.new()
	ring.radius = ring_radius
	ring.color = ring_color
	ring.start_scale = from_scale
	ring.thickness = PixelLine.pixels_for_width(ring_width)
	ring.z_index = 5
	parent.add_child(ring)
	ring.global_position = PixelDraw.snap(global_pos)
	var tween := ring.create_tween()
	tween.tween_property(ring, "progress", 1.0, maxf(0.05, duration))
	tween.tween_callback(ring.queue_free)
	return ring


## Radius now (ease-out like RingWave's cubic scale tween).
func get_current_radius() -> float:
	var eased := 1.0 - pow(1.0 - clampf(progress, 0.0, 1.0), 3.0)
	return radius * lerpf(start_scale, 1.0, eased)


## Alpha share now: full, then FADE_STEPS hard steps down to nothing.
func get_fade() -> float:
	var left := 1.0 - clampf(progress, 0.0, 1.0)
	return ceilf(left * FADE_STEPS) / FADE_STEPS


func _draw() -> void:
	var fade := get_fade()
	if fade <= 0.0:
		return
	PixelDraw.ring(self, Vector2.ZERO, get_current_radius(), Color(color, color.a * fade), thickness)

class_name RingWave
extends Line2D
## Expanding, fading ring for weapon specials (nova, spin attack, ground slams). Frees itself.

const SEGMENTS := 36


static func spawn(parent: Node, global_pos: Vector2, radius: float, color: Color, duration := 0.35, ring_width := 5.0, start_scale := 0.2) -> RingWave:
	if parent == null or not parent.is_inside_tree() or radius <= 0.0:
		return null
	var ring := RingWave.new()
	for i in SEGMENTS:
		ring.add_point(Vector2.from_angle(TAU * float(i) / SEGMENTS) * radius)
	ring.closed = true
	ring.width = ring_width
	ring.default_color = color
	ring.joint_mode = Line2D.LINE_JOINT_ROUND
	ring.z_index = 5
	ring.scale = Vector2.ONE * start_scale
	parent.add_child(ring)
	ring.global_position = global_pos
	var tween := ring.create_tween().set_parallel()
	tween.tween_property(ring, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ring.queue_free)
	return ring

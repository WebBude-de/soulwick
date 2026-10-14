class_name Burst
extends RefCounted
## One-shot pixel particle bursts (hits, deaths, breaking crates, explosions).


static func spawn(parent: Node, global_pos: Vector2, color: Color, amount := 14, speed := 160.0, lifetime := 0.45, size := 4.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var particles := CPUParticles2D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.amount = amount
	particles.lifetime = lifetime
	particles.explosiveness = 1.0
	particles.direction = Vector2.UP
	particles.spread = 180.0
	particles.gravity = Vector2(0, 120)
	particles.initial_velocity_min = speed * 0.4
	particles.initial_velocity_max = speed
	particles.damping_min = speed * 0.8
	particles.damping_max = speed * 1.6
	particles.scale_amount_min = size * 0.6
	particles.scale_amount_max = size
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color, 0.0))
	particles.color_ramp = ramp
	particles.z_index = 6
	parent.add_child(particles)
	particles.global_position = global_pos
	particles.emitting = true
	particles.finished.connect(particles.queue_free)

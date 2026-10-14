class_name Burst
extends RefCounted
## One-shot pixel particle bursts (hits, deaths, breaking crates, explosions).
## L1: a burst of at least FLASH_MIN_AMOUNT particles also flashes a short light in its own colour,
## so hits and explosions tint the floor around them for a moment (optics only: flash lights never
## count as light for LightQuery). Off with LightingQuality low.

## TESTWERTE (L1): smallest burst that flashes, radius per particle speed, peak and duration share.
const FLASH_MIN_AMOUNT := 8
const FLASH_RADIUS_PER_SPEED := 0.75
const FLASH_RADIUS_MIN := 56.0
const FLASH_RADIUS_MAX := 200.0
const FLASH_PEAK := 0.5
const FLASH_DURATION_SHARE := 0.6


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
	if should_flash(amount):
		LightSource.flash(parent, global_pos, flash_radius(speed), maxf(0.12, lifetime * FLASH_DURATION_SHARE), color, FLASH_PEAK)


## True if a burst of this size flashes a coloured light (L1).
static func should_flash(amount: int) -> bool:
	return LightingQuality.is_high() and amount >= FLASH_MIN_AMOUNT


static func flash_radius(speed: float) -> float:
	return clampf(speed * FLASH_RADIUS_PER_SPEED, FLASH_RADIUS_MIN, FLASH_RADIUS_MAX)

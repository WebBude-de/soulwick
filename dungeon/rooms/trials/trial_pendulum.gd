class_name TrialPendulum
extends TrialHazard
## Pendulum blade over a lane column (pendulum_blade_8f, SPRITES_V5 §4; frames 0 and 4 are the
## outer positions). It swings all the time; while the blade passes the middle it sweeps the floor
## of its column (ACTIVE), near the outer positions the column is free. No extra warning: the swing
## itself shows the beat.

## Swing period range and the share of the swing that hurts (TESTWERTE).
const PERIOD_RANGE := Vector2(1.8, 2.6)
## Hurts while |cos(swing angle)| is below this (blade low in the middle of its arc).
const DANGER_BAND := 0.5
## The delivered strip cuts the blade off at the frame edges in its swung frames (bug report
## 22.10.2026 #214a0ff5, "immer noch ständig abgeschnitten"): only its hanging frame is drawn and the
## whole sprite swings round the chain's anchor (art px of a frame) by up to SWING_DEGREES to either
## side, so the blade is always whole. TESTWERT (look)
const HANG_FRAME := 2
const ANCHOR := Vector2(32, 3)
const SWING_DEGREES := 25.0

var period := 2.2

var _angle := 0.0
var _sprite: Sprite2D = null
## Turns round the anchor of the chain; holds the sprite.
var _arm: Node2D = null


## rect: content-local column (one tile wide, all lane rows); the chain hangs from its top.
func build(rect: Rect2) -> void:
	hit_rect = rect
	position = Vector2(rect.get_center().x, rect.end.y)
	_sprite = TrialArt.make_sprite(TrialArt.PENDULUM)
	_sprite.frame = HANG_FRAME
	# The sprite's pivot (bottom centre) stays on this node; the arm sits on the chain's anchor.
	var anchor := (ANCHOR - TrialArt.get_pivot(TrialArt.PENDULUM)) * SpriteStrip.PIXEL_SCALE
	_arm = Node2D.new()
	_arm.name = "Arm"
	_arm.position = anchor
	add_child(_arm)
	_sprite.position = -anchor
	_arm.add_child(_sprite)


## Period and start angle from the dungeon RNG (two random numbers).
func configure_swing(rng: RandomNumberGenerator) -> void:
	period = rng.randf_range(PERIOD_RANGE.x, PERIOD_RANGE.y)
	_angle = rng.randf() * TAU
	_update_swing(false)


func advance(delta: float) -> void:
	_angle = fmod(_angle + TAU * delta / maxf(period, 0.1), TAU)
	_update_swing(true)


func get_swing() -> float:
	return cos(_angle)


func _update_swing(announce: bool) -> void:
	var new_phase := Phase.ACTIVE if absf(cos(_angle)) < DANGER_BAND else Phase.IDLE
	if _arm != null:
		# cos 1 = frame 0 of the strip (blade out on the left), cos -1 = frame 4 (on the right).
		_arm.rotation = deg_to_rad(SWING_DEGREES) * cos(_angle)
	if new_phase == phase:
		return
	phase = new_phase
	if not announce:
		return
	phase_changed.emit(phase)
	if phase == Phase.ACTIVE and is_inside_tree():
		Sfx.play_at(self, &"sword_swing", global_position, -14.0)

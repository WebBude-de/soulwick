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
const FRAMES := 8

var period := 2.2

var _angle := 0.0
var _sprite: Sprite2D = null


## rect: content-local column (one tile wide, all lane rows); the chain hangs from its top.
func build(rect: Rect2) -> void:
	hit_rect = rect
	position = Vector2(rect.get_center().x, rect.end.y)
	_sprite = TrialArt.make_sprite(TrialArt.PENDULUM)
	add_child(_sprite)


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
	if _sprite != null:
		_sprite.frame = roundi(_angle / TAU * FRAMES) % FRAMES
	if new_phase == phase:
		return
	phase = new_phase
	if not announce:
		return
	phase_changed.emit(phase)
	if phase == Phase.ACTIVE and is_inside_tree():
		Sfx.play_at(self, &"sword_swing", global_position, -14.0)

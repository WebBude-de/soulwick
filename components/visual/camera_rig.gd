class_name CameraRig
extends Camera2D
## Player camera with trauma-based screen shake: trauma decays over time, the offset grows with
## trauma² and follows smooth noise, so small hits jiggle and big explosions really rumble.
## While stunned the view tilts to one side and sways ("the screen goes crooked").

const MAX_OFFSET := 18.0
const MAX_ROLL := 0.035
const DECAY_PER_SECOND := 1.8
## Stun sway: constant tilt plus a slow swing, in radians, and a drifting offset in px.
const STUN_TILT := 0.11
const STUN_SWING := 0.05
const STUN_DRIFT := 10.0
const STUN_FADE_IN := 0.15
const STUN_FADE_OUT := 0.3

var _trauma := 0.0
var _time := 0.0
var _noise := FastNoiseLite.new()
var _sway_left := 0.0
var _sway_total := 0.0
var _sway_time := 0.0
var _sway_side := 1.0


func _ready() -> void:
	_noise.seed = randi()
	_noise.frequency = 0.9
	ignore_rotation = false


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Tilts and sways the view for duration seconds (player stun).
func stun_sway(duration: float) -> void:
	if duration <= 0.0:
		return
	if _sway_left <= 0.0:
		_sway_side = -1.0 if randf() < 0.5 else 1.0
		_sway_time = 0.0
	_sway_left = maxf(_sway_left, duration)
	_sway_total = maxf(_sway_left, 0.001)


func get_sway_amount() -> float:
	if _sway_left <= 0.0:
		return 0.0
	var fade_in := clampf((_sway_total - _sway_left) / STUN_FADE_IN, 0.0, 1.0)
	var fade_out := clampf(_sway_left / STUN_FADE_OUT, 0.0, 1.0)
	var amount := minf(fade_in, fade_out)
	return amount * amount * (3.0 - 2.0 * amount)


func _process(delta: float) -> void:
	var shake_offset := Vector2.ZERO
	var roll := 0.0
	if _trauma > 0.0:
		_time += delta * 60.0
		_trauma = maxf(0.0, _trauma - DECAY_PER_SECOND * delta)
		var shake := _trauma * _trauma
		shake_offset = Vector2(_noise.get_noise_2d(_time, 0.0), _noise.get_noise_2d(0.0, _time)) * MAX_OFFSET * shake
		roll = _noise.get_noise_2d(_time, _time) * MAX_ROLL * shake
	if _sway_left > 0.0:
		_sway_left = maxf(0.0, _sway_left - delta)
		_sway_time += delta
		var sway := get_sway_amount() if _sway_left > 0.0 else 0.0
		roll += (STUN_TILT * _sway_side + STUN_SWING * sin(_sway_time * 5.0)) * sway
		shake_offset += Vector2(sin(_sway_time * 3.7), sin(_sway_time * 2.9) * 0.6) * STUN_DRIFT * sway
	offset = shake_offset
	rotation = roll

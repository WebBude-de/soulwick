class_name ShieldComponent
extends Node
## Shield absorbs damage before HP, never regenerates passively and has no hard cap (D-014).
## Gains above SOFTCAP_THRESHOLD only count at SOFTCAP_FACTOR. Effective gains are rounded DOWN to
## 0.5 steps; the remainder is carried to the next gain, so small gains above the softcap (e.g. 0.5 per
## kill -> 0.25) no longer round up to the full amount and skip the softcap (D-091).

signal shield_changed(current: float)

## Retuned from 50 to 15 so shields stay a buffer, not a wall (D-074).
const SOFTCAP_THRESHOLD := 15.0
const SOFTCAP_FACTOR := 0.5

var _current := 0.0
## Fraction below 0.5 left over from earlier gains (D-091).
var _carry := 0.0


## Effective gain per DECISIONS §6 without carry, rounded down to 0.5 (e.g. 10 + 10 -> +7.5).
static func compute_gain(shield_old: float, requested_gain: float) -> float:
	return floor_to_step(compute_raw_gain(shield_old, requested_gain))


## Effective gain before rounding.
static func compute_raw_gain(shield_old: float, requested_gain: float) -> float:
	if requested_gain <= 0.0:
		return 0.0
	var normal_gain := minf(requested_gain, maxf(0.0, SOFTCAP_THRESHOLD - shield_old))
	return normal_gain + SOFTCAP_FACTOR * (requested_gain - normal_gain)


static func floor_to_step(value: float) -> float:
	# Small epsilon so exact multiples (7.5) are not lost to float error.
	return DamageProcessor.DAMAGE_STEP * floorf(value / DamageProcessor.DAMAGE_STEP + 0.0001)


func get_shield() -> float:
	return _current


## Returns the shield actually gained.
func add_shield(requested_gain: float) -> float:
	if requested_gain <= 0.0:
		return 0.0
	var raw := compute_raw_gain(_current, requested_gain) + _carry
	var gain := floor_to_step(raw)
	_carry = maxf(0.0, raw - gain)
	if gain <= 0.0:
		return 0.0
	_current += gain
	shield_changed.emit(_current)
	return gain


## On-kill shield (D-091): only fills up to `cap`, never beyond. Returns the shield gained.
func add_shield_up_to(requested_gain: float, cap: float) -> float:
	if _current >= cap:
		return 0.0
	return add_shield(minf(requested_gain, cap - _current))


## Sets the shield directly (MP3: a network client takes the host's value), no softcap.
func set_current(value: float) -> void:
	var clamped := maxf(0.0, value)
	if is_equal_approx(clamped, _current):
		return
	_current = clamped
	shield_changed.emit(_current)


## Returns the damage actually absorbed.
func absorb(amount: float) -> float:
	var absorbed := minf(maxf(0.0, amount), _current)
	if absorbed <= 0.0:
		return 0.0
	_current -= absorbed
	shield_changed.emit(_current)
	return absorbed

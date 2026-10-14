class_name TrialHazard
extends Node2D
## One timed hazard of the gauntlet (spikes, flame jet, pendulum blade): idle -> warning ->
## active (hurts) -> idle. Timing comes from the dungeon RNG when the course is built (configure),
## the idle times cycle through a short pattern, so the beat changes between rounds.
## The trial content steps all hazards (advance) and asks hits(); hazards never hurt by themselves,
## so the decision "is a running player hit" stays in one place (TrialContent / TrialCourse).
## Position = centre of hit_rect's column; hit_rect is in the content's (= room's) coordinates.

signal phase_changed(phase: Phase)

enum Phase { IDLE, WARN, ACTIVE }

## Idle pattern length (rounds before the beat repeats).
const PATTERN_LENGTH := 3

var phase := Phase.IDLE
var hit_rect := Rect2()
var warn_time := 0.6
var active_time := 0.7
var idle_pattern: Array[float] = [1.5]

var _time_left := 0.0
var _pattern_index := 0


## Timing from the dungeon RNG: an idle pattern in idle_range, a random start in the first round.
## Draws PATTERN_LENGTH + 1 random numbers.
func configure(rng: RandomNumberGenerator, idle_range: Vector2, warn: float, active: float) -> void:
	warn_time = warn
	active_time = active
	idle_pattern.clear()
	for i in PATTERN_LENGTH:
		idle_pattern.append(rng.randf_range(idle_range.x, idle_range.y))
	phase = Phase.IDLE
	_pattern_index = 0
	_time_left = rng.randf_range(0.2, idle_pattern[0] + warn_time + active_time)
	_on_phase_changed()


## Same beat as other (state and pattern), e.g. to shift it afterwards with advance().
func copy_timing(other: TrialHazard) -> void:
	warn_time = other.warn_time
	active_time = other.active_time
	idle_pattern = other.idle_pattern.duplicate()
	phase = other.phase
	_pattern_index = other._pattern_index
	_time_left = other._time_left
	_on_phase_changed()


func advance(delta: float) -> void:
	_time_left -= delta
	while _time_left <= 0.0:
		match phase:
			Phase.IDLE:
				_set_phase(Phase.WARN, warn_time)
			Phase.WARN:
				_set_phase(Phase.ACTIVE, active_time)
			Phase.ACTIVE:
				_pattern_index = (_pattern_index + 1) % idle_pattern.size()
				_set_phase(Phase.IDLE, idle_pattern[_pattern_index])
	_on_advance(delta)


func is_dangerous() -> bool:
	return phase == Phase.ACTIVE


## Does the active hazard reach point (room-local), with margin for the player's body?
func hits(point: Vector2, margin := 0.0) -> bool:
	return is_dangerous() and hit_rect.grow(margin).has_point(point)


func _set_phase(new_phase: Phase, duration: float) -> void:
	phase = new_phase
	_time_left += maxf(duration, 0.05)
	_on_phase_changed()
	phase_changed.emit(phase)


## Override: visuals per phase.
func _on_phase_changed() -> void:
	pass


## Override: per-frame visuals.
func _on_advance(_delta: float) -> void:
	pass

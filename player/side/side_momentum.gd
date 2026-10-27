class_name SideMomentum
extends RefCounted
## Momentum ("Schwung", D-195 / SV1) of one player in side view: whoever runs on the ground in one
## direction without stopping gets faster - after START_DELAY seconds the running speed climbs from
## SideRules.RUN_SPEED_FACTOR (1.3× move speed) to MAX_FACTOR (2.0×) in RAMP_TIME seconds, the
## same cap everywhere (D-216: no higher cap, no boost fields). Momentum is kept through a jump (the
## timer only runs on the ground), and lost when the player stops on the ground (after HALT_GRACE),
## turns round, hits a wall, takes a hit, climbs or falls into a pit. No new key: it only reads the
## stick. Speed only feels: it never runs an enemy over (D-216).
## Pure state and rules, no nodes: PlayerSideMotion owns one per player (multiplayer rule: state at
## the player) and calls update() once per physics frame; tests drive it directly.
## All numbers TESTWERT (D-195, D-216).

## Running counts from this stick deflection on.
const AXIS_DEADZONE := 0.2
## Seconds of running before the speed starts to climb.
const START_DELAY := 0.6
## Seconds from the base factor to MAX_FACTOR.
const RAMP_TIME := 1.0
const BASE_FACTOR := SideRules.RUN_SPEED_FACTOR
## Highest factor (D-216: the same everywhere).
const MAX_FACTOR := 2.0
## Standing still on the ground this long loses the momentum (a short stick slip keeps it).
const HALT_GRACE := 0.1

## Running direction: +1 right, -1 left, 0 none yet.
var direction := 0
## Seconds run on the ground in direction (frozen in the air).
var run_time := 0.0
var _halt_time := 0.0


## Factor on the move speed after run_time seconds of running, at most cap.
static func factor_for(seconds: float, max_factor := MAX_FACTOR) -> float:
	var rate := (MAX_FACTOR - BASE_FACTOR) / RAMP_TIME
	return minf(maxf(BASE_FACTOR, max_factor), BASE_FACTOR + maxf(0.0, seconds - START_DELAY) * rate)


## Seconds of running that reach factor (inverse of factor_for; tests).
static func time_for(factor: float) -> float:
	if factor <= BASE_FACTOR:
		return 0.0
	return START_DELAY + (factor - BASE_FACTOR) / ((MAX_FACTOR - BASE_FACTOR) / RAMP_TIME)


## Direction the stick runs in: -1, 0, +1.
static func axis_direction(axis_x: float) -> int:
	if absf(axis_x) <= AXIS_DEADZONE:
		return 0
	return 1 if axis_x > 0.0 else -1


## Current factor on the move speed (BASE_FACTOR without momentum).
func factor() -> float:
	return factor_for(run_time)


func has_momentum() -> bool:
	return factor() > BASE_FACTOR + 0.0001


## One physics frame. on_floor: the body stands on the ground; axis_x: the stick. Returns true when
## the momentum was lost in this frame (stop or turn).
func update(delta: float, on_floor: bool, axis_x: float) -> bool:
	var pressed := axis_direction(axis_x)
	if pressed != 0 and direction != 0 and pressed != direction:
		# Turning round, on the ground or in the air.
		var lost := reset()
		direction = pressed
		return lost
	if not on_floor:
		# The jump keeps the momentum; the timer waits for the ground.
		_halt_time = 0.0
		return false
	if pressed == 0:
		_halt_time += delta
		if _halt_time >= HALT_GRACE:
			return reset()
		return false
	_halt_time = 0.0
	direction = pressed
	run_time += delta
	return false


## Loses the momentum (wall, hit, ladder, pit, stop). Returns true when there was some to lose.
func reset() -> bool:
	var had := has_momentum()
	direction = 0
	run_time = 0.0
	_halt_time = 0.0
	return had

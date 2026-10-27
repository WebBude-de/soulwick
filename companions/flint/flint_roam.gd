class_name FlintRoam
extends RefCounted
## Flint hovering freely around his home spot (feedback #7adeacba 23.10.2026: "Er soll freier sein,
## aber sich halt etwas an mich halten"): now and then he drifts to a new point near his spot, pauses
## there, and sometimes makes a little trip a bit farther out, as if curious. Walking, scared or
## asleep he roams less or not at all; for a cast he hurries back to his spot, where the spell starts.
## Optics only (D-088): its own RandomNumberGenerator (never the dungeon RNG), nothing reads it for
## gameplay, every machine may draw a remote Flint at a slightly different point. The companion
## checks each new goal (walls, the player's picture, light and leash) through accept.

## TESTWERTE (world px, s)
## A normal drift goes this far from the home spot, a trip (TRIP_CHANCE of the drifts) farther.
const DRIFT_RADIUS := 20.0
const TRIP_RADIUS := 44.0
const TRIP_CHANCE := 0.22
## Drifts never shorter than this share of their radius (no tiny twitches).
const MIN_REACH_SHARE := 0.35
## Pause at a point before the next drift; trips wait a little longer out there.
const PAUSE_MIN := 0.9
const PAUSE_MAX := 2.6
const TRIP_PAUSE_EXTRA := 0.8
## How fast he glides to a drift goal (1/s, exponential: slow and floaty) and back home for a cast.
const DRIFT_SHARPNESS := 1.6
const RETURN_SHARPNESS := 12.0
## Goals tried per drift before he stays where he is.
const GOAL_TRIES := 5
## First drift after this many seconds (a fresh Flint first settles at his spot).
const FIRST_PAUSE := 1.2

## The drawn offset from the home spot (px).
var offset := Vector2.ZERO
## The current goal relative to the home spot, before the calm share.
var goal := Vector2.ZERO
var _wait := FIRST_PAUSE
var _rng := RandomNumberGenerator.new()


func _init(seed_value := -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


## One frame. calm = how freely he roams (1 at rest, less walking or scared, 0 not at all);
## hurry_home: back to the spot fast (a cast). side_view keeps the goals at and above his spot (the
## floor is below). accept(goal) -> bool rejects goals he must not fly to. Returns offset.
func update(delta: float, calm: float, accept: Callable, hurry_home := false, side_view := false) -> Vector2:
	var share := clampf(calm, 0.0, 1.0)
	if hurry_home or share <= 0.0:
		var rate := RETURN_SHARPNESS if hurry_home else DRIFT_SHARPNESS
		offset = offset.lerp(Vector2.ZERO, 1.0 - exp(-rate * maxf(0.0, delta)))
		return offset
	_wait -= delta
	if _wait <= 0.0:
		_pick_goal(accept, side_view)
	offset = offset.lerp(goal * share, 1.0 - exp(-DRIFT_SHARPNESS * maxf(0.0, delta)))
	return offset


## Drops the goal at once and glides home (a goal that became blocked, a teleport).
func reset(instant := false) -> void:
	goal = Vector2.ZERO
	_wait = PAUSE_MIN
	if instant:
		offset = Vector2.ZERO


func _pick_goal(accept: Callable, side_view: bool) -> void:
	var trip := _rng.randf() < TRIP_CHANCE
	var radius := TRIP_RADIUS if trip else DRIFT_RADIUS
	_wait = _rng.randf_range(PAUSE_MIN, PAUSE_MAX) + (TRIP_PAUSE_EXTRA if trip else 0.0)
	for i in GOAL_TRIES:
		var candidate := Vector2.from_angle(_rng.randf() * TAU) * radius * _rng.randf_range(MIN_REACH_SHARE, 1.0)
		if side_view:
			candidate.y = -absf(candidate.y)
		if not accept.is_valid() or accept.call(candidate):
			goal = candidate
			return
	# Nowhere free to go: home.
	goal = Vector2.ZERO

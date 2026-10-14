class_name TrialRules
extends RefCounted
## Pure rules of the trial rooms (KONZEPT_RAEUME §6.1, D-102): what a mistake costs, that it never
## ends the run, the flawless reward and the light rule of the light run. No nodes, unit-testable.

## A mistake (hazard hit) costs half a heart (TESTWERT).
const MISTAKE_DAMAGE := 1.0  # TESTWERT
## Light run: in the dark the player loses half a heart every DARK_DAMAGE_INTERVAL seconds.
const DARK_DAMAGE := 1.0  # TESTWERT
const DARK_DAMAGE_INTERVAL := 2.0  # TESTWERT
## A trial never ends the run: a hit leaves at least this much health.
const MIN_HEALTH_LEFT := 0.5
## Flawless (no mistake from start to chest): soul crystals per player (TESTWERT).
const FLAWLESS_CRYSTALS := 1  # TESTWERT
## After a mistake the same player cannot make the next one for this long (also covers hits that
## the cap reduced to 0 and that therefore start no hit I-frames).
const MISTAKE_COOLDOWN := 0.6


## Damage a mistake may deal: amount, but never so much that shield + health drop below
## MIN_HEALTH_LEFT (in 0.5 steps, 0 = the hit only counts as a mistake).
static func capped_damage(amount: float, health: float, shield: float) -> float:
	var allowed := maxf(0.0, shield + health - MIN_HEALTH_LEFT)
	allowed = floorf(allowed / DamageProcessor.DAMAGE_STEP) * DamageProcessor.DAMAGE_STEP
	return clampf(amount, 0.0, allowed)


static func is_flawless(mistakes: int) -> bool:
	return mistakes <= 0


## The one light decision of the light run: is point inside one of the lit circles?
static func is_point_lit(point: Vector2, lights: PackedVector2Array, radius: float) -> bool:
	for light in lights:
		if light.distance_to(point) <= radius:
			return true
	return false


## Dark time after delta more seconds in the dark (or 0 back in the light) and whether that tick
## costs DARK_DAMAGE. Returns [new dark time, damage].
static func tick_darkness(dark_time: float, delta: float, lit: bool) -> Array[float]:
	if lit:
		return [0.0, 0.0]
	var time := dark_time + delta
	if time >= DARK_DAMAGE_INTERVAL:
		return [time - DARK_DAMAGE_INTERVAL, DARK_DAMAGE]
	return [time, 0.0]

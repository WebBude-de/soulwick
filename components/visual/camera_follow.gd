class_name CameraFollow
extends RefCounted
## Where the player camera looks (M4, Makeover 3 §9): a small dead zone around the followed point,
## a small lead in the walking direction and smoothing. Pure maths on world points, no nodes:
## CameraRig feeds the point it follows (the local player today, a group middle in coop later).
##
## Calm first (playtest 14.10.2026: the view must feel almost bound to the player): the lead is small
## and changes at a fixed slow rate (linear, never overshoots, a turn does not swing the view back);
## a short stop keeps everything still, a longer one glides the view onto the player in one motion.
## All values in world px (the design's 64×48 / 48 px).

## No lag while walking: past the dead zone the view moves exactly with the player, so a turn never
## lets it drift on in the old direction. Only sudden jumps (knockback into a wall, respawn, an intro
## letting go) glide, with SMOOTHING.
##
## Dead zone, full size: the followed point moves this far before the view follows. TESTWERT.
const DEAD_ZONE := Vector2(64.0, 48.0)
## Lead in the walking direction per axis (vertical in the ratio of the dead zone). TESTWERT.
const LEAD := Vector2(48.0, 36.0)
## How fast the lead may change (world px/s, linear): full lead after about 2 s of walking. TESTWERT.
const LEAD_RATE := 24.0
## Speed (world px/s) from which the point counts as walking.
const LEAD_MIN_SPEED := 40.0
## Standing still this long (s), dead zone and lead glide back onto the point together (rate 1/s),
## so the view is not left looking back where the player came from. TESTWERTE.
const RECENTER_DELAY := 0.8
const RECENTER_SPEED := 1.0
## Gliding after a sudden jump (1/s), like the old position_smoothing_speed 7.
const SMOOTHING := 7.0
## A change of the wanted centre bigger than this in one step (world px) glides instead of following
## directly (walking moves about 4 px per frame, a dash about 10).
const GLIDE_JUMP := 24.0
## Smoothing of a velocity derived from positions (targets without a velocity of their own).
const VELOCITY_SMOOTHING := 12.0
## A jump this far in one step (teleport, respawn, new world) snaps the view instead of gliding.
const SNAP_DISTANCE := 640.0

## Centre of the view (world px): anchor + lead + what is left of a glide.
var center := Vector2.ZERO
## Centre of the dead zone (world px).
var anchor := Vector2.ZERO
## Current lead (world px), added to the anchor.
var lead := Vector2.ZERO

var _point := Vector2.ZERO
var _velocity := Vector2.ZERO
var _still := 0.0
var _glide := Vector2.ZERO
var _started := false


## Puts the view on point at once: no dead zone offset, no lead, no gliding.
func reset(point: Vector2) -> void:
	center = point
	anchor = point
	lead = Vector2.ZERO
	_point = point
	_velocity = Vector2.ZERO
	_still = 0.0
	_glide = Vector2.ZERO
	_started = true


func is_started() -> bool:
	return _started


## Advances one frame and returns the new view centre. velocity: walking velocity of the point
## (INF = derive it from the positions). centred: someone else aims the camera (room intro swing):
## dead zone and lead glide onto the point itself.
func step(point: Vector2, delta: float, velocity := Vector2.INF, centred := false) -> Vector2:
	if not _started or point.distance_to(_point) > SNAP_DISTANCE:
		reset(point)
		return center
	if delta <= 0.0:
		return center
	if velocity.is_finite():
		_velocity = velocity
	else:
		var raw := (point - _point) / delta
		_velocity = _velocity.lerp(raw, 1.0 - exp(-VELOCITY_SMOOTHING * delta))
	_point = point
	var before := anchor + lead
	if centred:
		var k := 1.0 - exp(-SMOOTHING * delta)
		anchor = anchor.lerp(point, k)
		lead = lead.lerp(Vector2.ZERO, k)
		_still = 0.0
	else:
		anchor = follow_dead_zone(anchor, point, DEAD_ZONE * 0.5)
		if _velocity.length() >= LEAD_MIN_SPEED:
			_still = 0.0
			lead = lead.move_toward(_velocity.normalized() * LEAD, LEAD_RATE * delta)
		else:
			# A short stop changes nothing; a longer one centres anchor and lead together.
			_still += delta
			if _still >= RECENTER_DELAY:
				var k := 1.0 - exp(-RECENTER_SPEED * delta)
				anchor = anchor.lerp(point, k)
				lead = lead.lerp(Vector2.ZERO, k)
	var moved := anchor + lead - before
	if moved.length() > GLIDE_JUMP:
		_glide -= moved
	_glide = _glide.lerp(Vector2.ZERO, 1.0 - exp(-SMOOTHING * delta))
	center = anchor + lead + _glide
	return center


## Moves anchor just enough that point lies inside the box of half size half_size around it.
static func follow_dead_zone(anchor_point: Vector2, point: Vector2, half_size: Vector2) -> Vector2:
	var diff := point - anchor_point
	return anchor_point + Vector2(
			signf(diff.x) * maxf(absf(diff.x) - half_size.x, 0.0),
			signf(diff.y) * maxf(absf(diff.y) - half_size.y, 0.0))

class_name TouchStick
extends RefCounted
## One on-screen stick of the TouchOverlay (CP2): the finger that holds it, where it went down and
## where it is now. Two modes (option "Joysticks", Projektmitglied 17.10.2026):
## - fixed (default): the stick never leaves its resting place. Only a touch on or near its ring
##   takes it (grab radius); the deflection is measured from the resting centre, so a touch on the
##   edge counts at once, and a thumb outside the ring keeps full deflection without dragging the
##   stick along.
## - floating: the move stick starts wherever the thumb lands in its zone; the aim stick starts at
##   its resting place when the thumb lands on its ring and under the thumb anywhere else. Both
##   follow a thumb that leaves the ring.
## Pure geometry, no input events: the overlay feeds it.

## Share of the radius around the resting centre that takes a fixed stick (TESTWERT): a thumb
## landing slightly off the ring still grabs it.
const FIXED_GRAB_SHARE := 1.5

## Reach in viewport pixels.
var radius: float
## Share of the reach that counts as resting (no output).
var dead_zone: float
## Where the stick waits while no finger holds it.
var rest := Vector2.ZERO
## Fixed at its resting place (see above); false = floating.
var fixed := false
## Finger index holding the stick, -1 = free.
var finger := -1
var origin := Vector2.ZERO
var point := Vector2.ZERO


func _init(stick_radius: float, stick_dead_zone: float) -> void:
	radius = stick_radius
	dead_zone = stick_dead_zone


func is_held() -> bool:
	return finger >= 0


## The stick sits at center while free (layout).
func set_rest(center: Vector2) -> void:
	rest = center
	if finger < 0:
		origin = center
		point = center


## True if position lies on the resting ring (slightly generous, like the buttons).
func is_on_ring(position: Vector2) -> bool:
	return position.distance_to(rest) <= radius * 1.15


## A fixed stick only takes touches within its grab radius; a floating one any touch (the overlay
## checks its zone).
func can_grab(position: Vector2) -> bool:
	return not fixed or position.distance_to(rest) <= radius * FIXED_GRAB_SHARE


## A finger takes the stick at position. anchored (always when fixed): the stick stays at its
## resting place and the touch already counts as a deflection; otherwise it starts under the finger.
func begin(index: int, position: Vector2, anchored := false) -> Vector2:
	finger = index
	origin = rest if anchored or fixed else position
	point = position
	return drag(position)


## The holding finger moved; returns the stick vector.
func drag(position: Vector2) -> Vector2:
	var offset := position - origin
	if offset.length() > radius and not fixed:
		origin = position - offset.normalized() * radius
	point = position
	return vector(position - origin, radius, dead_zone)


## The finger let go: back to the resting place.
func end() -> void:
	finger = -1
	origin = rest
	point = rest


## Knob position for drawing.
func knob() -> Vector2:
	if finger < 0:
		return origin
	return origin + (point - origin).limit_length(radius)


## Offset (viewport pixels) → vector of length 0..1 with dead zone.
static func vector(offset: Vector2, reach: float, rest_share: float) -> Vector2:
	var strength := clampf(offset.length() / reach, 0.0, 1.0)
	if strength < rest_share or strength <= 0.0:
		return Vector2.ZERO
	return offset.normalized() * remap(strength, rest_share, 1.0, 0.0, 1.0)

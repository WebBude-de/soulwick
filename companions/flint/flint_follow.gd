class_name FlintFollow
extends RefCounted
## Where Flint hovers (KONZEPT §7.1): his home spot, loosely beside his player (two thirds of a
## tile), diagonally behind him on the side away from the aim (never in the swing, feedback #c849884e:
## not on the player's skin). Walking, he falls in behind and beside the walking direction and trails
## loosely (feedback #7adeacba 23.10.2026: "automatisch hinter mich fliegen", "gar nicht so an mir
## kleben"), never on the line the player walks along; far behind he hurries to catch up (leash).
## His flame never leaves a share of the lit radius around the player (the circle sits at the
## player, D-212), so he stays visible in the light: in the dark or blinded Flint huddles close.
## Free hovering around this spot (little trips, curiosity) is optics only (FlintRoam).
## Pure decisions without nodes or randomness (D-088): every machine computes the same spot from the
## player's position alone (no network state). Offsets are relative to the player's origin (body
## centre) and give Flint's pivot (the bottom of the candle). Walls are the companion's part
## (FlintCompanion: rays against PhysicsLayers.WORLD pick a spot on the player's side of a wall).

## TESTWERTE (world px, 64 px per tile)
## Behind the player against the walking direction at full walking speed (almost half a tile); the
## trailing of the smoothing (FOLLOW_SHARPNESS) adds about as much again.
const TRAIL_MAX := 28.0
## Speed (px/s) at which the trail is full; slower walking trails less.
const TRAIL_FULL_SPEED := 160.0
## Below this speed Flint just hovers beside the player.
const MIN_TRAIL_SPEED := 20.0
## Beside the player (x) at rest and how high the candle's bottom floats over the floor.
const SIDE_DISTANCE := 40.0
const HOVER_HEIGHT := 20.0
## At rest Flint also sits this far behind the player (north, away from the camera); aiming up he
## moves the same distance to the front instead, so he never hovers in an upward swing.
const REST_DEPTH := 14.0
## Beside the player at full walking speed (no rest depth): the rest spot blends into this the faster
## the player walks, so the trail fits in the light without leaving the path clearance.
const WALK_SIDE_DISTANCE := 28.0
## Flint's body centre stays at least this far from the player's origin at rest (half a tile).
const REST_MIN_DISTANCE := 32.0
## Scared: closer and lower, a third of the trail.
const HUDDLE_DISTANCE := 14.0
const HUDDLE_HEIGHT := 12.0
const HUDDLE_TRAIL_SHARE := 0.35
## Flint's body centre never comes closer than this to the walking line.
const PATH_CLEARANCE := 18.0
## Middle of his picture above the pivot: flame top to feet are art rows 10..30 of the 32 px frame,
## pivot row 30, scale 2 (D-217).
const BODY_CENTER := Vector2(0.0, -20.0)
## The flame stays within this share of the player's lit radius, but may always reach MIN_REACH.
const LIGHT_REACH_SHARE := 0.4
const MIN_REACH := 26.0
## How fast Flint catches up (1/s, exponential): loosely near his spot, hurrying when he fell behind
## (from CATCH_UP_FROM px off his spot, full CATCH_UP_SHARPNESS at CATCH_UP_FULL px).
const FOLLOW_SHARPNESS := 3.5
const CATCH_UP_SHARPNESS := 9.0
const CATCH_UP_FROM := 24.0
const CATCH_UP_FULL := 64.0
## Leash: Flint's body centre never drifts farther than this from the player's origin.
const LEASH_DISTANCE := 84.0
## A spot a wall cut short stays this far in front of the wall (px).
const WALL_MARGIN := 10.0
## Velocity estimate smoothing (1/s).
const VELOCITY_SHARPNESS := 10.0
## A jump farther than this (fall reset, room change, teleport) puts Flint there at once.
const SNAP_DISTANCE := 192.0
## Aim must point this far to the other side before Flint changes sides (no flicker).
const SIDE_HYSTERESIS := 0.3
## Player feet below the origin (Player.FEET_OFFSET).
const FEET_Y := 16.0
## The player's picture relative to his origin: the idle and walk frames use art x 10..22 and
## y 3..30 of the 32 px frame, origin (16, 22) (Player.SPRITE_ORIGIN), scale 2.
const PLAYER_PICTURE := Rect2(-12.0, -38.0, 24.0, 54.0)
## Flint's picture relative to his pivot: wax x 12..19 and flame top to feet y 10..30 of the 32 px
## frame (tools/generate_flint.py, D-217), pivot (16, 30), scale 2, with his bob
## (FlintCompanion.BOB_AMPLITUDE) above and below.
const FLINT_PICTURE := Rect2(-8.0, -42.0, 16.0, 46.0)
## Free pixels between the two pictures (edge to edge).
const PICTURE_GAP := 4.0


## +1 = right of the player, -1 = left. Flint hovers on the side away from the aim.
static func pick_side(current: float, aim: Vector2) -> float:
	if aim.x > SIDE_HYSTERESIS:
		return -1.0
	if aim.x < -SIDE_HYSTERESIS:
		return 1.0
	return current if current != 0.0 else 1.0


## Flint's pivot relative to the player's origin. velocity = the player's (estimated) velocity,
## side = pick_side, lit_radius = the player's lit radius (LightQuery.player_lit_radius),
## flame = the flame anchor relative to Flint's pivot, huddle = scared (close and low),
## side_view = a side-view segment (trail only sideways), aim = the player's aim (rest depth).
static func target_offset(velocity: Vector2, side: float, lit_radius: float, flame: Vector2, huddle := false, side_view := false, aim := Vector2.ZERO) -> Vector2:
	var direction := velocity
	if side_view:
		direction.y = 0.0
	var speed := direction.length()
	var walk_share := clampf(speed / TRAIL_FULL_SPEED, 0.0, 1.0) if speed > MIN_TRAIL_SPEED else 0.0
	var offset := Vector2(HUDDLE_DISTANCE if huddle else lerpf(SIDE_DISTANCE, WALK_SIDE_DISTANCE, walk_share), 0.0) * side
	offset.y = FEET_Y - (HUDDLE_HEIGHT if huddle else HOVER_HEIGHT)
	if not huddle and not side_view:
		offset.y += rest_depth(aim) * (1.0 - walk_share)
	if walk_share > 0.0:
		direction /= speed
		var trail := TRAIL_MAX * walk_share * (HUDDLE_TRAIL_SHARE if huddle else 1.0)
		offset = keep_off_path(offset - direction * trail, direction, side)
	return settle(offset, flame, lit_radius)


## The final spot: on the leash, the flame within the light share, the picture clear of the player's.
static func settle(offset: Vector2, flame: Vector2, lit_radius: float) -> Vector2:
	return keep_clear(keep_in_light(keep_on_leash(offset), flame, lit_radius), flame, lit_radius)


## Pulls the offset in so that Flint's body centre stays within LEASH_DISTANCE of the player.
static func keep_on_leash(offset: Vector2) -> Vector2:
	var body := offset + BODY_CENTER
	if body.length() <= LEASH_DISTANCE:
		return offset
	return body.normalized() * LEASH_DISTANCE - BODY_CENTER


## Vertical shift of the rest spot: REST_DEPTH behind the player (up), turning smoothly to the front
## (down) the more the player aims up, so the swing never reaches Flint and nothing flickers.
static func rest_depth(aim: Vector2) -> float:
	return -REST_DEPTH * (1.0 - 2.0 * clampf(-aim.y, 0.0, 1.0))


## Pushes the offset sideways until Flint's body centre is PATH_CLEARANCE away from the walking line
## (through the player's origin along direction, a unit vector).
static func keep_off_path(offset: Vector2, direction: Vector2, side: float) -> Vector2:
	var across := direction.orthogonal()
	var body := offset + BODY_CENTER
	var distance := body.dot(across)
	if absf(distance) >= PATH_CLEARANCE:
		return offset
	var sign_to := signf(distance)
	if sign_to == 0.0:
		# Exactly on the line: go to Flint's side (up when walking sideways).
		sign_to = 1.0 if across.dot(Vector2(side, -1.0)) >= 0.0 else -1.0
	return offset + across * (sign_to * PATH_CLEARANCE - distance)


## Pulls the offset in so that the flame stays within the share of the lit radius.
static func keep_in_light(offset: Vector2, flame: Vector2, lit_radius: float) -> Vector2:
	var reach := light_reach(lit_radius)
	var light := offset + flame
	if light.length() <= reach:
		return offset
	return light.normalized() * reach - flame


## How far the flame may be from the player's origin.
static func light_reach(lit_radius: float) -> float:
	return maxf(MIN_REACH, lit_radius * LIGHT_REACH_SHARE)


## The pivot spots (relative to the player's origin) where Flint's picture would come closer than
## PICTURE_GAP to the player's picture.
static func clear_zone() -> Rect2:
	var left := PLAYER_PICTURE.position.x - PICTURE_GAP - FLINT_PICTURE.end.x
	var right := PLAYER_PICTURE.end.x + PICTURE_GAP - FLINT_PICTURE.position.x
	var top := PLAYER_PICTURE.position.y - PICTURE_GAP - FLINT_PICTURE.end.y
	var bottom := PLAYER_PICTURE.end.y + PICTURE_GAP - FLINT_PICTURE.position.y
	return Rect2(left, top, right - left, bottom - top)


## True if Flint's picture at offset comes closer than PICTURE_GAP to the player's (the edge counts
## as clear).
static func overlaps_player(offset: Vector2) -> bool:
	var zone := clear_zone()
	const EPSILON := 0.001
	return offset.x > zone.position.x + EPSILON and offset.x < zone.end.x - EPSILON \
			and offset.y > zone.position.y + EPSILON and offset.y < zone.end.y - EPSILON


## Moves offset straight away from the middle of the player's picture until the pictures are clear
## (continuous: a spot sliding across the player slides round him).
static func push_out(offset: Vector2) -> Vector2:
	if not overlaps_player(offset):
		return offset
	var zone := clear_zone()
	var center := zone.get_center()
	var half := zone.size * 0.5
	var away := offset - center
	var depth := maxf(absf(away.x) / half.x, absf(away.y) / half.y)
	if depth < 0.0001:
		return Vector2(center.x, zone.position.y)
	return center + away / depth


## Pushes offset out of the player's picture and keeps the flame within the light reach: the way
## straight out when its flame is in reach, else the nearest spot at an edge of the clear zone that
## is (beside the player, low; in the dark Flint huddles at his feet instead of on him).
static func keep_clear(offset: Vector2, flame: Vector2, lit_radius: float) -> Vector2:
	if not overlaps_player(offset):
		return offset
	var pushed := push_out(offset)
	var reach := light_reach(lit_radius)
	if (pushed + flame).length() <= reach + 0.01:
		return pushed
	var zone := clear_zone()
	var best := pushed
	var best_distance := INF
	for edge_x: float in [zone.position.x, zone.end.x]:
		var spot := _edge_spot(Vector2(edge_x, offset.y), flame, reach, true)
		if spot != Vector2.INF and spot.distance_to(offset) < best_distance:
			best = spot
			best_distance = spot.distance_to(offset)
	for edge_y: float in [zone.position.y, zone.end.y]:
		var spot := _edge_spot(Vector2(offset.x, edge_y), flame, reach, false)
		if spot != Vector2.INF and spot.distance_to(offset) < best_distance:
			best = spot
			best_distance = spot.distance_to(offset)
	return best


## spot slid along its edge (vertical: y moves, else x) until its flame is within reach;
## Vector2.INF when that edge never comes close enough.
static func _edge_spot(spot: Vector2, flame: Vector2, reach: float, vertical: bool) -> Vector2:
	var light := spot + flame
	var fixed := light.x if vertical else light.y
	if absf(fixed) > reach:
		return Vector2.INF
	var span := sqrt(reach * reach - fixed * fixed)
	if vertical:
		return Vector2(spot.x, clampf(light.y, -span, span) - flame.y)
	return Vector2(clampf(light.x, -span, span) - flame.x, spot.y)


## One smoothing step from current to target, both relative to the player's origin: like step(), but
## when the straight way would cross the player's picture Flint goes round him (angle and distance
## around the middle of the clear zone, the shorter way, mostly over his head).
static func step_around(current: Vector2, target: Vector2, delta: float) -> Vector2:
	if current.distance_to(target) > SNAP_DISTANCE:
		return target
	var weight := 1.0 - exp(-follow_sharpness(current.distance_to(target)) * maxf(0.0, delta))
	var straight := current.lerp(target, weight)
	if not overlaps_player(straight):
		return straight
	var zone := clear_zone()
	var center := zone.get_center()
	var half := zone.size * 0.5
	var from := (current - center) / half
	var to := (target - center) / half
	var angle := lerp_angle(from.angle(), to.angle(), weight)
	var radius := lerpf(from.length(), to.length(), weight)
	return push_out(center + Vector2.from_angle(angle) * radius * half)


## One smoothing step towards target (Flint trails loosely behind).
static func step(current: Vector2, target: Vector2, delta: float) -> Vector2:
	var distance := current.distance_to(target)
	if distance > SNAP_DISTANCE:
		return target
	return current.lerp(target, 1.0 - exp(-follow_sharpness(distance) * maxf(0.0, delta)))


## Smoothing rate for a spot this far from its target: loose nearby, hurrying when far behind.
static func follow_sharpness(distance: float) -> float:
	var hurry := clampf((distance - CATCH_UP_FROM) / (CATCH_UP_FULL - CATCH_UP_FROM), 0.0, 1.0)
	return lerpf(FOLLOW_SHARPNESS, CATCH_UP_SHARPNESS, hurry)


## Velocity estimate from the player's movement (works the same for remote players whose position
## comes from the network). A jump (moved farther than SNAP_DISTANCE) resets it.
static func estimate_velocity(previous: Vector2, moved: Vector2, delta: float) -> Vector2:
	if delta <= 0.0:
		return previous
	if moved.length() > SNAP_DISTANCE:
		return Vector2.ZERO
	return previous.lerp(moved / delta, 1.0 - exp(-VELOCITY_SHARPNESS * delta))


# --- Walls (the companion casts the rays, these are the pure parts) ---

## The floor point under Flint at offset (where his shadow lies), relative to the player's origin.
static func ground_of(offset: Vector2) -> Vector2:
	return offset + Vector2(0.0, HOVER_HEIGHT)


## Where the companion's wall ray starts and ends for offset, relative to the player's origin: from
## between the player's centre and feet to the floor under Flint (side view: to his body), reaching
## WALL_MARGIN beyond it so he never hovers right at a wall.
static func wall_ray(offset: Vector2, side_view := false) -> PackedVector2Array:
	var from := Vector2(0.0, 0.0 if side_view else FEET_Y * 0.5)
	var to := offset + BODY_CENTER if side_view else ground_of(offset)
	var way := to - from
	if way.length() > 0.001:
		to += way.normalized() * WALL_MARGIN
	return PackedVector2Array([from, to])


## Other spots to try when a wall stands between the player and offset: the same spot on the other
## side, then straight behind the player's head, then in front of his feet.
static func wall_alternatives(offset: Vector2) -> Array[Vector2]:
	var zone := clear_zone()
	return [Vector2(-offset.x, offset.y), Vector2(0.0, zone.position.y), Vector2(0.0, zone.end.y)]


## offset pulled in along its wall ray until it ends WALL_MARGIN short of hit (relative to the
## player's origin): no free spot was found, so Flint stays on the player's side of the wall.
static func short_of_wall(offset: Vector2, hit: Vector2, side_view := false) -> Vector2:
	var ray := wall_ray(offset, side_view)
	var way := ray[1] - ray[0]
	if way.length() < 0.001:
		return offset
	var reach := maxf(0.0, (hit - ray[0]).length() - WALL_MARGIN)
	var end := ray[0] + way.normalized() * minf(reach, way.length())
	return end - BODY_CENTER if side_view else end - Vector2(0.0, HOVER_HEIGHT)

class_name EnemyTactics
extends RefCounted
## Rules and geometry of the group tactics (RAEUME §6, playtest 14.10.2026): slime
## packs that hop in turn and land beside and behind the player, melee enemies that spread over
## ring places around their target instead of queueing behind each other, some of them cutting off
## a fleeing target, and ranged enemies that now and then change sides.
## Pure functions and TESTWERTE only; the state per room lives in EnemyPack, the movement and the
## hop effects in Enemy. No randomness here (the caller passes numbers from the room's RNG).
## Strength grows with the room number (intensity): gentle from room 1, full from FULL_ROOM, so
## the first rooms stay easy (endless runner).

# --- Strength over the room number ---

## Room in which the tactics start (intensity START_INTENSITY there). TESTWERT
const FROM_ROOM := 1
## Room from which everything works at full strength (intensity 1). TESTWERT
const FULL_ROOM := 10
const START_INTENSITY := 0.0
## Cutting off a fleeing target starts in this room and is full from CUT_OFF_FULL_ROOM. TESTWERT
const CUT_OFF_FROM_ROOM := 6
const CUT_OFF_FULL_ROOM := 12

# --- Ring places (melee) ---

## Ring radius = attack range + RING_MARGIN, at least MIN_RING_RADIUS (px). Inside the ring an
## enemy is engaged and walks straight at its target. TESTWERT
const RING_MARGIN := 30.0
const MIN_RING_RADIUS := 64.0
## Share of the full circle the ring places cover: MIN_SPREAD at intensity 0, 1.0 at full
## intensity (then the places sit evenly around the target, some of them behind it). TESTWERT
const MIN_SPREAD := 0.3
## On the way to its place an enemy walks an arc around the target, at most this many radians
## per step, at a distance between the ring radius and ARC_RADIUS_FACTOR times of it.
const ARC_STEP := 0.8
const ARC_RADIUS_FACTOR := 1.8
## Every arc step also closes in a little (share of the current distance kept).
const ARC_SHRINK := 0.85
## The common reference angle of a target's ring turns at most this much per plan (no jitter).
const BASE_TURN := 0.6
## An enemy that does not reach its ring for this long walks straight at its target for
## DIRECT_TIME seconds (never stuck circling in a corner). TESTWERT
const SLOT_PATIENCE := 1.5
const DIRECT_TIME := 1.5
## Slower than this (px/s) while chasing counts as hanging.
const STUCK_SPEED := 15.0

# --- Cut-off ---

## A target counts as fleeing above this speed (px/s, smoothed). TESTWERT
const FLEE_SPEED := 60.0
## Share of the close-combat enemies of a target that cut off its way (at full strength). TESTWERT
const CUT_OFF_SHARE := 0.34
## How far ahead of the fleeing target a cutter blocks the way (px, at full strength). TESTWERT
const CUT_OFF_LEAD := 160.0

# --- Ranged ---

## Side changes start at this intensity. TESTWERT
const RANGED_SWITCH_FROM := 0.3
## Seconds between two side changes: x at RANGED_SWITCH_FROM, y at full intensity, plus up to
## SIDE_SWITCH_JITTER seconds from the room's RNG. TESTWERT
const SIDE_SWITCH_INTERVAL := Vector2(10.0, 6.0)
const SIDE_SWITCH_JITTER := 2.5
## A side change moves this far around the target (radians, from the room's RNG).
const SIDE_SWITCH_ANGLE := Vector2(1.2, 2.2)
## A side change ends at its new place or after this long (no shots meanwhile). TESTWERT
const RELOCATE_TIME := 2.5
const RELOCATE_TOLERANCE := 0.35

# --- Slime packs ---

## Slimes (tag "swarm") form packs of PACK_MIN..PACK_MAX animals per target. TESTWERT
const PACK_MIN := 3
const PACK_MAX := 5
## A pack that shrinks below this size breaks up (its members chase alone again).
const PACK_KEEP := 2
## A lone swarm enemy joins an existing pack of its target only this close (px).
const PACK_JOIN_DISTANCE := 320.0
## Hop: crouch with the landing marker, then fly. No damage in the air. TESTWERT
const HOP_WINDUP := 0.3
const HOP_AIR := 0.4
## Peak height of the sprite during a hop (art px before visual scaling).
const HOP_HEIGHT := 22.0
## Hop length: x at intensity 0, y at full intensity (px). TESTWERT
const HOP_DISTANCE := Vector2(80.0, 150.0)
## Shorter hops are not worth it: the slime walks instead.
const HOP_MIN_LENGTH := 36.0
## The members of a pack hop one after another, this many seconds apart ... TESTWERT
const HOP_STAGGER := 0.22
## ... and after the last one the pack rests this long: x at intensity 0, y at full. TESTWERT
const HOP_ROUND_PAUSE := Vector2(1.2, 0.5)
## Between its hops a pack member creeps on at this share of its speed. TESTWERT
const HOP_CREEP_FACTOR := 0.45
## After a refused hop (wall in the way) the slime walks at full speed this long.
const HOP_BLOCKED_TIME := 1.5
## A granted hop that is not taken within this time goes to the next member.
const HOP_GRANT_TIME := 0.1
## A pack member only hops while it is this much farther than its ring radius from the target.
const HOP_TARGET_MARGIN := 16.0
## A landing keeps at least this share of the ring radius from the target (now and predicted) ...
const LAND_RING_SHARE := 0.8
## ... and at least this far from every living player at the moment of landing (px).
const LAND_CLEARANCE := 40.0
## Short rest after a landing before the slime may attack.
const HOP_LAND_PAUSE := 0.15

# --- Planning ---

## Seconds between two plans of a room (places, cutters, packs). TESTWERT
const REPLAN_INTERVAL := 0.3


## 0 before FROM_ROOM, START_INTENSITY in FROM_ROOM, rising linearly to 1 in FULL_ROOM.
static func intensity(room_index: int) -> float:
	if room_index < FROM_ROOM:
		return 0.0
	if FULL_ROOM <= FROM_ROOM:
		return 1.0
	var t := clampf(float(room_index - FROM_ROOM) / float(FULL_ROOM - FROM_ROOM), 0.0, 1.0)
	return lerpf(START_INTENSITY, 1.0, t)


## 0 before CUT_OFF_FROM_ROOM, then rising to 1 in CUT_OFF_FULL_ROOM.
static func cut_off_intensity(room_index: int) -> float:
	if room_index < CUT_OFF_FROM_ROOM:
		return 0.0
	if CUT_OFF_FULL_ROOM <= CUT_OFF_FROM_ROOM:
		return 1.0
	return clampf(float(room_index - CUT_OFF_FROM_ROOM + 1) / float(CUT_OFF_FULL_ROOM - CUT_OFF_FROM_ROOM + 1), 0.0, 1.0)


## Number of cutters among close_count close-combat enemies of one target. Never all of them: at
## least one keeps chasing. Zero while the target does not flee or in the first rooms.
static func cut_off_count(close_count: int, room_index: int, target_speed: float) -> int:
	if close_count < 2 or target_speed < FLEE_SPEED:
		return 0
	var strength := cut_off_intensity(room_index)
	if strength <= 0.0:
		return 0
	return clampi(roundi(close_count * CUT_OFF_SHARE * strength), 1 if strength >= 0.5 else 0, close_count - 1)


## How far ahead a cutter blocks the way (grows with the cut-off strength).
static func cut_off_lead(room_index: int, ring: float) -> float:
	return lerpf(ring, maxf(ring, CUT_OFF_LEAD), cut_off_intensity(room_index))


static func ring_radius(data: EnemyData) -> float:
	if data == null:
		return MIN_RING_RADIUS
	return maxf(MIN_RING_RADIUS, data.attack_range + RING_MARGIN)


## Distance a ranged enemy keeps on its side: between its minimum distance and its range.
static func ranged_radius(data: EnemyData) -> float:
	if data == null:
		return 240.0
	if data.preferred_min_distance > 0.0:
		return (data.preferred_min_distance + data.attack_range) * 0.5
	return data.attack_range * 0.75


## Share of the full circle covered by the ring places at this intensity.
static func ring_spread(strength: float) -> float:
	return lerpf(MIN_SPREAD, 1.0, clampf(strength, 0.0, 1.0))


## count ring angles, centred on base, covering spread of the full circle, in ascending order.
## One place sits exactly on base.
static func ring_angles(count: int, base: float, spread: float) -> PackedFloat32Array:
	var angles := PackedFloat32Array()
	if count <= 0:
		return angles
	var step := TAU * clampf(spread, 0.0, 1.0) / float(count)
	for i in count:
		angles.append(base + (float(i) - float(count - 1) * 0.5) * step)
	return angles


## Slot index for every member: members and slots are both ordered by their angle relative to
## base, the i-th member gets the i-th slot (no crossing paths). slot_angles must be ascending
## around base (ring_angles).
static func assign_by_angle(member_angles: PackedFloat32Array, slot_angles: PackedFloat32Array, base: float) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(member_angles.size())
	var order: Array[int] = []
	for i in member_angles.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return angle_difference(base, member_angles[a]) < angle_difference(base, member_angles[b]))
	for rank in order.size():
		result[order[rank]] = mini(rank, slot_angles.size() - 1)
	return result


## Mean direction of angles (0 for an empty list or angles that cancel each other out).
static func circular_mean(angles: PackedFloat32Array) -> float:
	var sum := Vector2.ZERO
	for angle in angles:
		sum += Vector2.from_angle(angle)
	return sum.angle() if sum.length_squared() > 0.0001 else (angles[0] if not angles.is_empty() else 0.0)


## Turns previous towards wanted by at most max_turn radians.
static func turn_towards(previous: float, wanted: float, max_turn: float) -> float:
	return previous + clampf(angle_difference(previous, wanted), -max_turn, max_turn)


## Where an enemy at from walks to reach its place at slot_angle on the ring of radius around
## center: inside the ring it is engaged (returns center: straight at the target); close to its
## angle it walks to the place itself; otherwise it walks an arc around the target, at most
## ARC_STEP radians ahead, so it never runs through the target to get behind it.
static func approach_point(from: Vector2, center: Vector2, slot_angle: float, radius: float) -> Vector2:
	if from.distance_to(center) <= radius:
		return center
	return place_point(from, center, slot_angle, radius)


## Next point on the way to the place at slot_angle on the ring of radius around center, without
## engaging: the place itself once the angle is close, else one arc step around the target that
## also closes in a little (between radius and ARC_RADIUS_FACTOR times of it).
static func place_point(from: Vector2, center: Vector2, slot_angle: float, radius: float) -> Vector2:
	var offset := from - center
	var distance := offset.length()
	if distance < 1.0:
		return center + Vector2.from_angle(slot_angle) * radius
	var current := offset.angle()
	var delta := angle_difference(current, slot_angle)
	if absf(delta) <= ARC_STEP:
		return center + Vector2.from_angle(slot_angle) * radius
	var arc_radius := clampf(distance * ARC_SHRINK, radius, radius * ARC_RADIUS_FACTOR)
	return center + Vector2.from_angle(current + clampf(delta, -ARC_STEP, ARC_STEP)) * arc_radius


## Next point on the way around center to slot_angle, keeping the given radius (ranged side
## changes; never engages).
static func orbit_point(from: Vector2, center: Vector2, slot_angle: float, radius: float) -> Vector2:
	var offset := from - center
	if offset.length_squared() < 1.0:
		return center + Vector2.from_angle(slot_angle) * radius
	var current := offset.angle()
	var delta := angle_difference(current, slot_angle)
	if absf(delta) <= ARC_STEP:
		return center + Vector2.from_angle(slot_angle) * radius
	return center + Vector2.from_angle(current + clampf(delta, -ARC_STEP, ARC_STEP)) * radius


## Goal of a cutter: ahead of a target fleeing along flee (unit vector). A cutter beside or behind
## the target walks around it to the front; one already ahead steps onto the flight line, at
## most lead ahead, and waits there for the target to come (it does not run away in front of it).
static func cut_off_point(from: Vector2, center: Vector2, flee: Vector2, ring: float, lead: float) -> Vector2:
	var offset := from - center
	if offset.length() <= ring:
		return center
	var along := offset.dot(flee)
	if along < ring * 0.5:
		return place_point(from, center, flee.angle(), ring)
	return center + flee * clampf(along, ring, maxf(ring, lead))


## Moves point out of the circle of min_distance around center (radially; away from fallback
## when point lies exactly on center).
static func keep_away(point: Vector2, center: Vector2, min_distance: float, fallback := Vector2.RIGHT) -> Vector2:
	var offset := point - center
	if offset.length() >= min_distance:
		return point
	var direction := offset.normalized() if offset.length_squared() > 0.01 else fallback.normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	return center + direction * min_distance


# --- Hops ---

static func hop_distance(strength: float) -> float:
	return lerpf(HOP_DISTANCE.x, HOP_DISTANCE.y, clampf(strength, 0.0, 1.0))


static func hop_round_pause(strength: float) -> float:
	return lerpf(HOP_ROUND_PAUSE.x, HOP_ROUND_PAUSE.y, clampf(strength, 0.0, 1.0))


## Pack sizes for count swarm enemies of one target: as few packs as possible, each PACK_MIN..
## PACK_MAX, sizes differing by at most one. Empty below PACK_MIN.
static func pack_sizes(count: int) -> Array[int]:
	var sizes: Array[int] = []
	if count < PACK_MIN:
		return sizes
	var packs := ceili(float(count) / float(PACK_MAX))
	for i in packs:
		sizes.append(floori(float(count) / float(packs)) + (1 if i < count % packs else 0))
	return sizes


## Landing point of one hop from from towards the ring place at slot_angle around the target at
## center (moving with target_velocity): aims at where the target will be when the slime lands
## (more so at higher intensity), at most hop_distance long, and never inside LAND_RING_SHARE of
## the ring radius around the target, neither now nor predicted. Pure: walls are checked by the
## caller (EnemyHop.clear_landing).
static func hop_landing(from: Vector2, center: Vector2, target_velocity: Vector2, slot_angle: float, ring: float, strength: float) -> Vector2:
	var predicted := center + target_velocity * (HOP_WINDUP + HOP_AIR) * clampf(strength, 0.0, 1.0)
	var goal := place_point(from, predicted, slot_angle, ring)
	var hop := (goal - from).limit_length(hop_distance(strength))
	var landing := from + hop
	var away := from - center
	landing = keep_away(landing, predicted, ring * LAND_RING_SHARE, away)
	return keep_away(landing, center, ring * LAND_RING_SHARE, away)

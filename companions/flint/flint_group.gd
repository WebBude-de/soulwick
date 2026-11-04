class_name FlintGroup
extends RefCounted
## Where the one Flint of a group goes (WK13, D-225 §2): the middle of the standing players, pulled
## towards the one furthest behind (nobody stays alone in the dark). Players far apart fall into
## parts (a chain of players closer than PART_LINK is one part); Flint stays with the bigger part, on
## a tie with the host's. FlintCompanion builds his usual spot (beside, behind, walls) around this
## point instead of around a single player; alone the point is the player himself, so a solo Flint
## behaves exactly as before.
## Pure decisions from positions and velocities (D-088): no nodes, no randomness. Only the host (or a
## single machine) decides; clients draw Flint from the host's spot (NetFlint).

## TESTWERTE (world px, 64 px per tile)
## Players closer than this (chain) belong to the same part of the group: about two light radii, so
## a group spread over one screen stays one part.
const PART_LINK := 448.0
## Share of the way from the middle of the part to the player furthest behind.
const REAR_PULL := 0.35
## From this mean speed (px/s) "behind" means against the walking direction; slower, the player
## furthest from the middle counts as behind.
const WALKING_SPEED := 20.0
## The group point glides towards its target (1/s, exponential) and at most this fast (px/s); a jump
## farther than JUMP_DISTANCE (teleport, the group changed part across the map) puts it there at once.
const POINT_SHARPNESS := 5.0
const POINT_MAX_SPEED := 420.0
const JUMP_DISTANCE := 640.0


## The parts of the group: indexes into positions, each part in index order, parts ordered by their
## lowest index. Two players closer than link (or linked through others) share a part.
static func parts(positions: PackedVector2Array, link := PART_LINK) -> Array[PackedInt32Array]:
	var part_of := PackedInt32Array()
	part_of.resize(positions.size())
	part_of.fill(-1)
	var result: Array[PackedInt32Array] = []
	for start in positions.size():
		if part_of[start] != -1:
			continue
		var part := PackedInt32Array([start])
		part_of[start] = result.size()
		var next := 0
		while next < part.size():
			var current := part[next]
			next += 1
			for other in positions.size():
				if part_of[other] == -1 and positions[current].distance_to(positions[other]) <= link:
					part_of[other] = result.size()
					part.append(other)
		part.sort()
		result.append(part)
	return result


## The part Flint stays with: the biggest; on a tie the one with host_index, else the first.
static func main_part(positions: PackedVector2Array, host_index := 0, link := PART_LINK) -> PackedInt32Array:
	var best := PackedInt32Array()
	for part in parts(positions, link):
		if part.size() > best.size() or (part.size() == best.size() and part.has(host_index) and not best.has(host_index)):
			best = part
	return best


## Middle (mean position) of the players of part.
static func middle(positions: PackedVector2Array, part: PackedInt32Array) -> Vector2:
	if part.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for index in part:
		sum += positions[index]
	return sum / float(part.size())


## The player of part furthest behind: against the mean walking direction while the part walks,
## else the one furthest from the middle (the lowest index on a tie). -1 for an empty part.
static func rearmost(positions: PackedVector2Array, velocities: PackedVector2Array, part: PackedInt32Array) -> int:
	if part.is_empty():
		return -1
	var center := middle(positions, part)
	var heading := Vector2.ZERO
	for index in part:
		if index < velocities.size():
			heading += velocities[index]
	heading /= float(part.size())
	var walking := heading.length() >= WALKING_SPEED
	var best := part[0]
	var best_score := -INF
	for index in part:
		var away := positions[index] - center
		# Behind = the smallest step along the heading; at rest the largest distance from the middle.
		var score := -away.dot(heading.normalized()) if walking else away.length()
		if score > best_score + 0.001:
			best = index
			best_score = score
	return best


## Where Flint's group point wants to be: the middle of the main part pulled REAR_PULL towards its
## player furthest behind. One player: that player. No player: Vector2.INF.
static func target(positions: PackedVector2Array, velocities: PackedVector2Array, host_index := 0) -> Vector2:
	if positions.is_empty():
		return Vector2.INF
	if positions.size() == 1:
		return positions[0]
	var part := main_part(positions, host_index)
	var center := middle(positions, part)
	var rear := rearmost(positions, velocities, part)
	if rear < 0:
		return center
	return center.lerp(positions[rear], REAR_PULL)


## One gliding step of the group point towards goal (exponential, at most POINT_MAX_SPEED; farther
## than JUMP_DISTANCE it jumps).
static func glide(current: Vector2, goal: Vector2, delta: float) -> Vector2:
	var distance := current.distance_to(goal)
	if distance > JUMP_DISTANCE:
		return goal
	var step := distance * (1.0 - exp(-POINT_SHARPNESS * maxf(0.0, delta)))
	return current.move_toward(goal, minf(step, POINT_MAX_SPEED * maxf(0.0, delta)))

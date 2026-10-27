class_name EnemyHop
extends RefCounted
## One hop of a pack slime (RAEUME §6): crouch with a landing marker (HOP_WINDUP), then
## a short flight (HOP_AIR) in which the slime neither collides nor deals damage. The landing was
## checked against walls and abysses when the hop began and is checked against the players again
## when it lands: never on top of a player. State and physics checks only; the enemy shows it.

var start := Vector2.ZERO
var landing := Vector2.ZERO
var windup_left := EnemyTactics.HOP_WINDUP
var air_time := 0.0
var airborne := false


func _init(from: Vector2, to: Vector2) -> void:
	start = from
	landing = to


## 0..1 progress of the flight.
func get_progress() -> float:
	return clampf(air_time / EnemyTactics.HOP_AIR, 0.0, 1.0)


## Height of the sprite above its shadow at the current progress (art px times scale).
func get_height(scale: float) -> float:
	return sin(get_progress() * PI) * EnemyTactics.HOP_HEIGHT * scale


## Ground point the slime would stand on if the hop ended now (death in the air): the nearer of
## start and landing, both checked ground.
func get_ground_point() -> Vector2:
	return landing if get_progress() >= 0.5 else start


## The part of the hop from body_center (centre of the body circle) towards landing that the body
## can travel without touching a wall, prop or abyss (mask without players and enemies), a little
## short of the contact. Returns the shortened landing (enemy origin), or Vector2.INF when less
## than HOP_MIN_LENGTH is left. offset = enemy origin minus body centre.
static func clear_landing(body: CharacterBody2D, body_center: Vector2, offset: Vector2, landing_point: Vector2, radius: float, mask: int) -> Vector2:
	# landing_point is an enemy origin; the body circle sits at origin - offset.
	var motion := (landing_point - offset) - body_center
	if motion.length() < EnemyTactics.HOP_MIN_LENGTH:
		return Vector2.INF
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, body_center)
	query.motion = motion
	query.collision_mask = mask
	query.exclude = [body.get_rid()]
	var space := body.get_world_2d().direct_space_state
	var result := space.cast_motion(query)
	var fraction := 1.0
	if result.size() >= 1 and result[0] < 1.0:
		fraction = maxf(0.0, result[0] - 6.0 / motion.length())
	var travel := motion * fraction
	if travel.length() < EnemyTactics.HOP_MIN_LENGTH:
		return Vector2.INF
	return body_center + travel + offset


## Final landing: pushed out of LAND_CLEARANCE around every living player, as long as the pushed
## point is free ground; otherwise back to the start (the slime just hops on the spot).
static func safe_landing(body: CharacterBody2D, offset: Vector2, hop: EnemyHop, players: Array[Node2D], radius: float, mask: int) -> Vector2:
	var point := hop.landing
	# Never onto the other level of a plateau (M3): the edge is a wall for a hop too.
	if not HeightRules.same_level_points(hop.start - offset, point - offset):
		return hop.start
	var moved := false
	for player in players:
		var pushed := EnemyTactics.keep_away(point, player.global_position, EnemyTactics.LAND_CLEARANCE, hop.start - player.global_position)
		if pushed != point:
			point = pushed
			moved = true
	if not moved:
		return point
	if _is_free(body, point - offset, radius, mask) and HeightRules.same_level_points(hop.start - offset, point - offset):
		for player in players:
			if point.distance_to(player.global_position) < EnemyTactics.LAND_CLEARANCE - 0.5:
				return hop.start
		return point
	return hop.start


static func _is_free(body: CharacterBody2D, body_center: Vector2, radius: float, mask: int) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, body_center)
	query.collision_mask = mask
	query.exclude = [body.get_rid()]
	return body.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()

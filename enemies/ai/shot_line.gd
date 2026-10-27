class_name ShotLine
extends RefCounted
## Is a player standing in the line of a shot at a decoy (soul flame), and where does the shooter
## step to get past him (bug report 23.10.2026 #56d68b40, "Die Flamme bekommt basically nie
## Damage")? Archers sent after the flame shot straight at it; a player standing beside the flame on
## their line caught every arrow, so two defenders kept the flame almost untouched. A shooter whose
## line to its decoy is covered by a player now walks round the decoy until the line is free and
## shoots then; a player who keeps stepping into the line still blocks (good defending, wanted).
## Pure geometry plus one look at the living players (EnemyTargeting, D-088), no randomness.

## A player's hurt circle counts this much wider for the line test (px): the arrow's own size and a
## little air, so a shot that would graze him counts as covered. TESTWERT
const LINE_MARGIN := 6.0
## The shooter steps round its decoy by this angle per goal (radians, about 30 degrees). TESTWERT
const STEP_ANGLE := 0.5


## The first living player whose hurt circle lies on the segment from -> to (closer to from than to
## is), or null. projectile_radius: radius of the shooter's projectile.
static func blocking_player(tree: SceneTree, from: Vector2, to: Vector2, projectile_radius: float) -> Node2D:
	var length := from.distance_to(to)
	if length < 1.0:
		return null
	for player in EnemyTargeting.living_players(tree):
		var circle := hurt_circle(player)
		var centre: Vector2 = circle["centre"]
		if from.distance_to(centre) >= length:
			continue
		var closest := Geometry2D.get_closest_point_to_segment(centre, from, to)
		if closest.distance_to(centre) <= float(circle["radius"]) + projectile_radius + LINE_MARGIN:
			return player
	return null


## Where the shooter at from walks to get its line to target past blocker: round the target, to
## the side away from the blocker (the line turns off him), at the shooter's distance.
static func side_step_goal(from: Vector2, target: Vector2, blocker: Vector2) -> Vector2:
	var line := target - from
	var side := signf(line.cross(blocker - from))
	if side == 0.0:
		side = 1.0
	# Blocker left of the line (side < 0 in screen space) -> turn the shooter's place the other way.
	return target + (from - target).rotated(side * STEP_ANGLE)


## Centre and radius of a body's hurt circle (its Hurtbox's first circle), else its position and 12.
static func hurt_circle(body: Node2D) -> Dictionary:
	var hurtbox := body.get_node_or_null(^"Hurtbox") as Node2D
	if hurtbox != null:
		for child in hurtbox.get_children():
			var shape := child as CollisionShape2D
			if shape != null and shape.shape is CircleShape2D:
				return {"centre": shape.global_position, "radius": (shape.shape as CircleShape2D).radius * absf(shape.global_scale.x)}
	return {"centre": body.global_position, "radius": 12.0}

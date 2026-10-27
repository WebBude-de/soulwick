class_name SideContactRules
extends RefCounted
## Stomping side enemies (D-195 / SV1), decisions only: geometry and numbers, no nodes. Stomp
## (Stampfen): a player falling onto a side enemy from above beats a normal one and bounces
## STOMP_BOUNCE_TILES high. Nobody is run over (D-216): touching an enemy from the side is its
## contact damage at any speed. Which enemies take a stomp is the enemy's call
## (SideEnemy.on_stomped, SV4); PlayerSideMotion asks them.
## Rectangles are global, y grows downwards; the checks look one physics frame ahead, so the
## decision falls before the enemy's contact hitbox touches the player's hurtbox.
## All numbers TESTWERT (D-195, D-216).

## Bounce after a stomp: 1.5 tiles (v = sqrt(2 * GRAVITY * h)).
const STOMP_BOUNCE_TILES := 1.5
## The feet may already be this far below the enemy's top and still count as "from above" (px).
const STOMP_TOLERANCE := 14.0
## A stomp needs this much horizontal overlap beyond touching corners (px).
const STOMP_EDGE_INSET := 4.0
## Short protection after a stomp: the beaten enemy's contact cannot hurt in the same
## moment (seconds).
const CONTACT_GRACE := 0.2
## Damage tags of the default defeat (an enemy without the SV4 hooks).
const TAG_STOMP := &"stomp"


## Upward speed of the stomp bounce (px/s).
static func stomp_bounce_velocity() -> float:
	return SideRules.jump_velocity_for(STOMP_BOUNCE_TILES * SideRules.TILE)


## Whether a player landing now stomps the enemy whose body is enemy_rect: falling (fall_speed > 0),
## the feet came from above the enemy's top (previous_feet), they reach the top this frame or the
## next, and the body overlaps the enemy sideways (half_width = half the player's body width).
static func is_stomp(previous_feet: Vector2, feet: Vector2, fall_speed: float, half_width: float,
		enemy_rect: Rect2, delta: float) -> bool:
	if fall_speed <= 0.0 or not enemy_rect.has_area():
		return false
	var top := enemy_rect.position.y
	if previous_feet.y > top + STOMP_TOLERANCE or feet.y > enemy_rect.end.y:
		return false
	if feet.y + fall_speed * delta < top:
		return false
	var reach := enemy_rect.size.x * 0.5 + half_width - STOMP_EDGE_INSET
	return absf(feet.x - enemy_rect.get_center().x) <= reach


## Body rectangle of a side enemy (global): its get_body_rect() when it has one, else its
## get_body_size() standing on its origin (SideEnemy: the origin is the feet), else its first
## rectangular collision shape; empty when it has none of them.
static func enemy_body_rect(enemy: Node2D) -> Rect2:
	if enemy.has_method(&"get_body_rect"):
		var provided: Variant = enemy.call(&"get_body_rect")
		if provided is Rect2:
			return provided
	if enemy.has_method(&"get_body_size"):
		var size: Variant = enemy.call(&"get_body_size")
		if size is Vector2:
			var body: Vector2 = size
			return Rect2(enemy.global_position - Vector2(body.x * 0.5, body.y), body)
	for child in enemy.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null or shape_node.disabled:
			continue
		var box := shape_node.shape as RectangleShape2D
		if box != null:
			return Rect2(shape_node.global_position - box.size * 0.5, box.size)
	return Rect2()

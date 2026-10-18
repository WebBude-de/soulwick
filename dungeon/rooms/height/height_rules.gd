class_name HeightRules
extends RefCounted
## Decisions about height in one place (M3, Makeover 3 §8, D-088): on which level is a body or a
## point, may a hit reach from one level to the other, may an enemy jump, teleport or summon there.
## The level is never stored anywhere: it follows from where a body stands (the centre of its
## collision shape) and the HeightLayout of the room it stands in (HeightField). Every player has
## his own level that way, nothing has to be kept in sync (koop), no randomness.
## Rules (§8): projectiles and explosions change levels (a shot from above hits below), melee does
## not (no sword over the cliff, no slime bite up the edge); stairs and ladders belong to both levels.
## Enemies use stairs, never ladders (navigation, PhysicsLayers.LADDER); a plateau with only a
## ladder is a safe island for bow and staff (wanted, §2.3).

## Walking speed on a ladder (players only, ToxicPuddle.apply_slow). TESTWERT
const LADDER_SLOW := 0.55
## Navigation polygons of surface tiles stay this far (art px, 32 per tile) off an edge to the
## ground, so the navigation of both levels only meets at stairs. Larger than the map's edge
## connection margin (1 px). TESTWERT
const NAV_INSET := 3.0
## Thickness of an edge wall between a surface tile and the ground beside it (art px). TESTWERT
const EDGE_THICKNESS := 2.0
## Damage tags that always cross levels (shots, explosions); melee is a hit tagged "melee" without
## any of them.
const CROSSING_TAGS: Array[StringName] = [&"projectile", &"explosion"]
const MELEE_TAG := &"melee"
## Group of every live HeightField (one per room with a plateau).
const FIELDS_GROUP := &"height_fields"

const GROUND := HeightLayout.Level.GROUND
const PLATEAU := HeightLayout.Level.PLATEAU
const BOTH := HeightLayout.Level.BOTH


## Can a melee hit (or a touch) reach from level a to level b? Connectors reach both.
static func melee_reaches(a: int, b: int) -> bool:
	return a == BOTH or b == BOTH or a == b


## Level of a world point: the HeightField of the room it lies in, ground outside every plateau
## room (and in every room without one).
static func level_at(point: Vector2) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return GROUND
	for node in tree.get_nodes_in_group(FIELDS_GROUP):
		var field := node as HeightField
		if field != null and field.is_inside_tree() and field.covers(point):
			return field.level_at(point)
	return GROUND


## Level of a body: where the centre of its collision shape stands (players: their feet circle).
static func level_of(node: Node) -> int:
	if not has_height():
		return GROUND
	return level_at(body_point(node))


## Centre of the body's collision shape (the point walls and edges stop), else its position.
static func body_point(node: Node) -> Vector2:
	var body := node as Node2D
	if body == null:
		return Vector2.ZERO
	if body is CollisionObject2D:
		var shape := body.get_node_or_null(^"CollisionShape2D") as Node2D
		if shape != null:
			return shape.global_position
	return body.global_position


## Are a and b on the same level (or one of them on stairs or a ladder)?
static func same_level(a: Node, b: Node) -> bool:
	if a == null or b == null or not has_height():
		return true
	return melee_reaches(level_of(a), level_of(b))


static func same_level_points(a: Vector2, b: Vector2) -> bool:
	if not has_height():
		return true
	return melee_reaches(level_at(a), level_at(b))


## The one decision for hits (DamageProcessor): true when a melee hit must not land because
## attacker and target stand on different levels. Shots and explosions always land.
static func blocks_hit(damage: DamageData, target: Node) -> bool:
	if damage == null or not damage.tags.has(MELEE_TAG):
		return false
	for tag in CROSSING_TAGS:
		if damage.tags.has(tag):
			return false
	if not has_height():
		return false
	var source := damage.source as Node2D
	if source == null or not is_instance_valid(source) or target == null:
		return false
	return not melee_reaches(level_of(source), level_of(target))


## Point an enemy may move to without a level change (teleport, leap, summon): to itself when the
## destination lies on the other level or on a cliff, otherwise unchanged. from is where it stands.
static func keep_level(from: Vector2, destination: Vector2) -> Vector2:
	if not has_height():
		return destination
	var tree := Engine.get_main_loop() as SceneTree
	for node in tree.get_nodes_in_group(FIELDS_GROUP):
		var field := node as HeightField
		if field != null and field.is_inside_tree() and field.covers(destination):
			if field.is_cliff_at(destination):
				return from
			break
	return destination if melee_reaches(level_at(from), level_at(destination)) else from


## Is any room with a plateau alive? (Cheap early out for every rule above.)
static func has_height() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	return tree != null and tree.has_group(FIELDS_GROUP)

class_name TouchAimAssist
extends RefCounted
## Light aim assist for the touch aim stick, ranged weapons only (bow, staff; Claude 16.10.2026,
## delegated by the Projektmitglied, see D-155): while the aim stick is deflected and a living
## enemy the local player can see lies in a narrow cone around the stick direction and within the
## weapon's range, the aim snaps onto it. Several in the cone: the smallest angle wins, on a tie the
## nearer one. The gamepad's right stick uses the same assist (P0-2, GamepadInput, option
## "Zielhilfe (Gamepad)"). Melee weapons, mouse and keyboard never use it.
## Co-op: candidates come from the player's own tree and are measured from its own weapon; the
## visibility is the local viewer's darkness (only the local player reads touch or gamepad input). No random.

## Half opening of the snap cone around the stick direction in degrees (TESTWERT).
const CONE_DEGREES := 12.0
## Share of the weapon's attack_range (projectile travel distance) that counts as in range (TESTWERT).
const RANGE_SHARE := 1.0
## An enemy in the dark counts as seen from this faded alpha on (TESTWERT, like damage numbers).
const MIN_VISIBLE_ALPHA := 0.5
## Angles closer than this (radians) count as a tie; then the nearer enemy wins.
const TIE_ANGLE := 0.0005
const ENEMY_GROUP := &"enemies"


## Aim of this frame with the assist applied: direction onto the chosen enemy, otherwise aim
## unchanged. Only while the aim stick is deflected and body holds a ranged weapon.
static func apply(body: Node2D, aim_stick: Vector2, aim: Vector2) -> Vector2:
	if aim_stick == Vector2.ZERO or body == null or not body.is_inside_tree():
		return aim
	var max_range := ranged_reach(body)
	if max_range <= 0.0:
		return aim
	var origin := aim_origin(body)
	var points := visible_enemy_points(body)
	var index := pick_in_cone(origin, aim, points, max_range)
	return (points[index] - origin).normalized() if index >= 0 else aim


## Index of the point in the cone (half opening cone_degrees around direction) and within
## max_range of origin with the smallest angle; on a tie the nearer one. -1 if none.
static func pick_in_cone(origin: Vector2, direction: Vector2, points: Array[Vector2], max_range: float, cone_degrees := CONE_DEGREES) -> int:
	if direction == Vector2.ZERO or max_range <= 0.0:
		return -1
	var cone := deg_to_rad(cone_degrees)
	var range_squared := max_range * max_range
	var best := -1
	var best_angle := INF
	var best_distance := INF
	for i in points.size():
		var offset := points[i] - origin
		var distance := offset.length_squared()
		if distance <= 0.0001 or distance > range_squared:
			continue
		var angle := absf(direction.angle_to(offset))
		if angle > cone:
			continue
		var better := angle < best_angle - TIE_ANGLE
		var tie := absf(angle - best_angle) <= TIE_ANGLE
		if better or (tie and distance < best_distance):
			best = i
			best_angle = angle
			best_distance = distance
	return best


## Range in which the assist looks for enemies: the active weapon's travel distance if it is a
## ranged weapon (not melee), else 0 (no assist). Duck-typed like TouchInput.read_button_state.
static func ranged_reach(body: Node) -> float:
	var controller: Object = body.get(&"weapon_controller")
	if controller == null or not controller.has_method(&"get_active_weapon"):
		return 0.0
	var weapon := controller.call(&"get_active_weapon") as WeaponData
	if weapon == null or weapon.is_melee():
		return 0.0
	return weapon.attack_range * RANGE_SHARE


## Where shots leave from: the weapon controller (projectiles start there), else the body.
static func aim_origin(body: Node2D) -> Vector2:
	var controller := body.get(&"weapon_controller") as Node2D
	if controller != null and controller.is_inside_tree():
		return controller.global_position
	return body.global_position


## Positions of the living, visible enemies in body's tree: shown, not dead, not coming out of a
## source, and not hidden in the dark for the local viewer (DarknessVisibility, read only).
static func visible_enemy_points(body: Node2D) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var tree := body.get_tree()
	var darkness := tree.get_first_node_in_group(DarknessVisibility.GROUP) as DarknessVisibility
	for node in tree.get_nodes_in_group(ENEMY_GROUP):
		if not is_instance_valid(node) or not node is Node2D:
			continue
		var enemy := node as Node2D
		if not enemy.is_visible_in_tree():
			continue
		if enemy.has_method(&"is_dead") and enemy.call(&"is_dead"):
			continue
		if enemy.has_method(&"is_emerging") and enemy.call(&"is_emerging"):
			continue
		if darkness != null and darkness.get_enemy_alpha(enemy) < MIN_VISIBLE_ALPHA:
			continue
		points.append(enemy.global_position)
	return points

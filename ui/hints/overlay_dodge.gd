extends RefCounted
## Overlay texts make room for the fight (online test 16.10.2026: "Gegner sieht man oft schlecht,
## weil Texteinblendungen davor sind"). Banners, the status line, teaching cards and the intro
## countdown fade to DODGE_ALPHA while an enemy or a player stands under them on the local screen,
## and big banners shrink to a strip while enemies are on screen (DungeonUI). Look only: nothing
## here changes the game; the screen of this machine decides (coop: every player sees their own).
## No class_name (no global class cache entry needed): DungeonUI and the tests preload it.

## Alpha of an overlay with a body under it (TESTWERT).
const DODGE_ALPHA := 0.35
## Alpha change per second towards the target (TESTWERT).
const FADE_SPEED := 6.0
## Smallest body radius (world px) and the margin around a body (mockup px).
const MIN_RADIUS := 14.0
const PADDING := 4.0
## Sprites stand above the body centre: the body rect reaches this many radii up (and one down).
const HEAD_ROOM := 2.0
## Below this darkness alpha (DarknessVisibility) an enemy is not seen, so nothing makes room for it.
const MIN_SEEN_ALPHA := 0.1


## Screen rects (viewport px) of the living enemies and players of tree. Enemies still hidden in
## their spawn source or in the dark, and dead ones, do not count.
static func body_rects(tree: SceneTree) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if tree == null:
		return rects
	var darkness := tree.get_first_node_in_group(DarknessVisibility.GROUP) as DarknessVisibility
	for node in tree.get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_inside_tree() or enemy.is_dead():
			continue
		if not enemy.visible or enemy.is_hidden_in_source():
			continue
		if darkness != null and darkness.get_enemy_alpha(enemy) < MIN_SEEN_ALPHA:
			continue
		var radius := MIN_RADIUS
		if enemy.data != null:
			radius = maxf(MIN_RADIUS, enemy.data.body_radius * enemy.data.sprite_scale)
		rects.append(body_rect(enemy, radius))
	for node in tree.get_nodes_in_group(&"player"):
		var player := node as Player
		if player == null or not is_instance_valid(player) or not player.is_inside_tree() or not player.is_alive():
			continue
		rects.append(body_rect(player, MIN_RADIUS * 1.5))
	return rects


## Screen rect of a body of radius (world px) at node's origin, with head room and padding.
static func body_rect(node: CanvasItem, radius: float) -> Rect2:
	var transform := node.get_global_transform_with_canvas()
	var scale := maxf(0.01, transform.get_scale().x)
	var r := radius * scale + UiKit.px(PADDING)
	var centre := transform.origin
	return Rect2(centre.x - r, centre.y - r * HEAD_ROOM, r * 2.0, r * (HEAD_ROOM + 1.0))


## True when one of the bodies overlaps rect (an empty rect never covers anything).
static func is_covering(rect: Rect2, bodies: Array[Rect2]) -> bool:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return false
	for body in bodies:
		if rect.intersects(body):
			return true
	return false


## Next alpha of an overlay: towards DODGE_ALPHA while covered, back to rest (1) otherwise.
static func step(current: float, covered: bool, delta: float, rest := 1.0) -> float:
	return move_toward(current, DODGE_ALPHA if covered else rest, FADE_SPEED * maxf(0.0, delta))


## Living enemies inside view (viewport px): the fight is on this screen.
static func enemies_on_screen(tree: SceneTree, view: Rect2) -> int:
	var count := 0
	if tree == null:
		return count
	for node in tree.get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_inside_tree() or enemy.is_dead():
			continue
		if not enemy.visible or enemy.is_hidden_in_source():
			continue
		if view.has_point(enemy.get_global_transform_with_canvas().origin):
			count += 1
	return count


## Union of the on-screen rects of the visible controls under root (direct children only).
static func children_rect(root: Control) -> Rect2:
	var result := Rect2()
	if root == null:
		return result
	for child in root.get_children():
		var control := child as Control
		if control == null or not control.visible or control.is_queued_for_deletion():
			continue
		var rect := control.get_global_rect()
		result = rect if result.size == Vector2.ZERO else result.merge(rect)
	return result

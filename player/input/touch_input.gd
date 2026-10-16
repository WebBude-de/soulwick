class_name TouchInput
extends LocalKeyboardMouseInput
## The local player on a device with a touch screen (CP2): reads the on-screen controls of the
## TouchOverlay (stick, buttons) while a finger is in use, otherwise keyboard and mouse exactly like
## LocalKeyboardMouseInput. Aim has no mouse here: aim assist points at the nearest enemy in range,
## otherwise along the stick, otherwise keeps the last direction.

## Aim assist range in world pixels around the player (TESTWERT, CP0 question 5; touch only).
const AIM_ASSIST_RADIUS := 200.0
## Stick deflection below this does not turn the aim (thumb resting on the stick).
const AIM_MOVE_THRESHOLD := 0.3
const ENEMY_GROUP: StringName = &"enemies"

var state: TouchState
var _last_aim := Vector2.RIGHT


## Wraps the plain keyboard/mouse input of this machine into a TouchInput when a touch screen exists
## (or -- touch=1); everything else (RemoteInput, an existing TouchInput) stays as it is.
static func adapt(input: PlayerInput) -> PlayerInput:
	if input is LocalKeyboardMouseInput and not input is TouchInput and TouchState.is_touch_possible():
		return TouchInput.new()
	return input


func _init(touch_state: TouchState = null) -> void:
	state = touch_state if touch_state != null else TouchState.shared()


func poll(body: Node2D) -> void:
	var in_tree := body != null and body.is_inside_tree()
	if in_tree and state == TouchState.shared():
		TouchOverlay.ensure(body.get_tree())
	state.mark_polled(_is_side_view(body), _can_play(body))
	if in_tree:
		read_button_state(body, state)
	if not state.is_active():
		aim_direction = Vector2.ZERO
		super.poll(body)
		return
	move = state.move.limit_length(1.0)
	for action in ACTIONS:
		var down := state.went_down(action)
		_pressed[action] = down or state.is_held(action)
		_just_pressed[action] = down
	state.consume_presses()
	var origin := body.global_position if in_tree else Vector2.ZERO
	var target := nearest_enemy_direction(body, origin, AIM_ASSIST_RADIUS) if in_tree else Vector2.ZERO
	aim_direction = choose_aim(target, move, _last_aim)
	_last_aim = aim_direction
	aim_point = origin + aim_direction * 64.0


## What the overlay's buttons show for body (read only, duck-typed like the other checks): the
## weapon type of the active weapon (attack icon) and the cooldown shares of dash and special.
## The dash cooldown is the top-down dash; in a side view the button jumps.
static func read_button_state(body: Node, target: TouchState) -> void:
	var dash_share := 0.0
	if body.has_method(&"get_dash_cooldown_left") and not (body.has_method(&"is_side_view") and body.call(&"is_side_view")):
		var total := float(body.get(&"dash_cooldown")) if body.get(&"dash_cooldown") != null else 0.0
		dash_share = _share(float(body.call(&"get_dash_cooldown_left")), total)
	target.cooldowns[DASH] = dash_share
	var special_share := 0.0
	var weapon_type := -1
	var controller: Object = body.get(&"weapon_controller")
	if controller != null and controller.has_method(&"get_active_weapon"):
		var weapon := controller.call(&"get_active_weapon") as WeaponData
		if weapon != null:
			weapon_type = weapon.weapon_type
			var slot := int(controller.call(&"get_active_slot"))
			special_share = _share(float(controller.call(&"get_special_cooldown_left", slot)), weapon.special_cooldown)
	target.cooldowns[SPECIAL] = special_share
	target.weapon_type = weapon_type


static func _share(left: float, total: float) -> float:
	return clampf(left / total, 0.0, 1.0) if total > 0.0 and left > 0.0 else 0.0


## Aim of this frame: an assisted target first, then the stick, then the previous aim.
static func choose_aim(target_direction: Vector2, stick: Vector2, last_aim: Vector2) -> Vector2:
	if target_direction != Vector2.ZERO:
		return target_direction.normalized()
	if stick.length() >= AIM_MOVE_THRESHOLD:
		return stick.normalized()
	return last_aim if last_aim != Vector2.ZERO else Vector2.RIGHT


## Index of the closest point within radius of origin, -1 if none.
static func pick_nearest(origin: Vector2, points: Array[Vector2], radius: float) -> int:
	var best := -1
	var best_distance := radius * radius
	for i in points.size():
		var distance := origin.distance_squared_to(points[i])
		if distance <= best_distance:
			best_distance = distance
			best = i
	return best


## Direction to the nearest living, visible enemy within radius; Vector2.ZERO if none.
static func nearest_enemy_direction(body: Node2D, origin: Vector2, radius: float) -> Vector2:
	var points: Array[Vector2] = []
	for node in body.get_tree().get_nodes_in_group(ENEMY_GROUP):
		if not is_instance_valid(node) or not node is Node2D:
			continue
		var enemy := node as Node2D
		if not enemy.is_visible_in_tree():
			continue
		if enemy.has_method(&"is_dead") and enemy.call(&"is_dead"):
			continue
		if enemy.has_method(&"is_emerging") and enemy.call(&"is_emerging"):
			continue
		points.append(enemy.global_position)
	var index := pick_nearest(origin, points, radius)
	if index < 0 or points[index].is_equal_approx(origin):
		return Vector2.ZERO
	return (points[index] - origin).normalized()


func _is_side_view(body: Node2D) -> bool:
	return body != null and body.has_method(&"is_side_view") and body.call(&"is_side_view")


func _can_play(body: Node2D) -> bool:
	if body == null or not body.is_inside_tree():
		return false
	if body.has_method(&"is_input_locked") and body.call(&"is_input_locked"):
		return false
	return not (body.has_method(&"is_alive") and not body.call(&"is_alive"))

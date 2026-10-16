class_name TouchInput
extends LocalKeyboardMouseInput
## The local player on a device with a touch screen (CP2): reads the on-screen controls of the
## TouchOverlay (two sticks, buttons) while a finger is in use, otherwise keyboard and mouse exactly
## like LocalKeyboardMouseInput. Two-stick aim (Projektmitglied 16.10.2026): while the aim stick is
## deflected the player looks that way and attacks on its own (every weapon; bow and staff shoot
## that way); without it the player looks where it walks, otherwise keeps the last direction, and
## does not attack. The special (left button) goes off in that same direction; while it is held the
## aim stick does not attack, so the special is not blocked by a running swing.
## With a ranged weapon the aim stick snaps onto a visible enemy in a narrow cone (TouchAimAssist).

## Move stick deflection below this does not turn the aim (thumb resting on the stick).
const AIM_MOVE_THRESHOLD := 0.3
## Aim stick deflection (after its dead zone, 0..1) from which the player attacks on its own
## (TESTWERT); below it the stick only turns the aim, e.g. to line up the special.
const AUTO_ATTACK_THRESHOLD := 0.25
## A tap on the special stays requested this many physics frames (TESTWERT, 0.25 s at 60 fps), so a
## quick tap during a running swing is not lost: the auto-attack pauses and the special follows.
const SPECIAL_BUFFER_FRAMES := 15

var state: TouchState
var _last_aim := Vector2.RIGHT
var _was_attacking := false
var _special_buffer := 0


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
		_was_attacking = false
		_special_buffer = 0
		super.poll(body)
		return
	move = state.move.limit_length(1.0)
	var aim_stick := state.aim.limit_length(1.0)
	for action in ACTIONS:
		var down := state.went_down(action)
		_pressed[action] = down or state.is_held(action)
		_just_pressed[action] = down
	state.consume_presses()
	_special_buffer = SPECIAL_BUFFER_FRAMES if _just_pressed[SPECIAL] else maxi(0, _special_buffer - 1)
	_pressed[SPECIAL] = _pressed[SPECIAL] or _special_buffer > 0
	var attacking := wants_auto_attack(aim_stick, _pressed[SPECIAL]) or _pressed[ATTACK]
	_just_pressed[ATTACK] = _just_pressed[ATTACK] or (attacking and not _was_attacking)
	_pressed[ATTACK] = attacking
	_was_attacking = attacking
	var origin := body.global_position if in_tree else Vector2.ZERO
	aim_direction = choose_aim(aim_stick, move, _last_aim)
	if in_tree:
		aim_direction = TouchAimAssist.apply(body, aim_stick, aim_direction)
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


## Aim of this frame: the aim stick first, then the move stick, then the previous aim.
static func choose_aim(aim_stick: Vector2, move_stick: Vector2, last_aim: Vector2) -> Vector2:
	if aim_stick != Vector2.ZERO:
		return aim_stick.normalized()
	if move_stick.length() >= AIM_MOVE_THRESHOLD:
		return move_stick.normalized()
	return last_aim if last_aim != Vector2.ZERO else Vector2.RIGHT


## The aim stick attacks on its own while it is deflected far enough, except while the special is
## held (the special gets the next free moment instead of a new swing).
static func wants_auto_attack(aim_stick: Vector2, special_held: bool) -> bool:
	return not special_held and aim_stick.length() >= AUTO_ATTACK_THRESHOLD


func _is_side_view(body: Node2D) -> bool:
	return body != null and body.has_method(&"is_side_view") and body.call(&"is_side_view")


func _can_play(body: Node2D) -> bool:
	if body == null or not body.is_inside_tree():
		return false
	if body.has_method(&"is_input_locked") and body.call(&"is_input_locked"):
		return false
	return not (body.has_method(&"is_alive") and not body.call(&"is_alive"))

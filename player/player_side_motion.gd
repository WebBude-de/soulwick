class_name PlayerSideMotion
extends Node
## Side-view platform motion of one player (M5, gang segments). While active, Player hands its
## movement over to this node (Player.side_motion, three small hooks in player.gd): gravity with a
## short hang at the apex and faster falling, a 2.5-tile jump with coyote time, jump buffer and
## variable height, one double jump in the air, wall slide and wall jump on rock, a horizontal dash,
## ladders up and down, falling out of the segment. Weapons, hits, upgrades, health, shield and the
## HUD stay the player's own, so nothing else changes. The state lives here, per player (multiplayer
## rule): coyote and buffer timers, air jumps, the wall, the ladder, the last safe platform, the
## time outside the view; the public fields (air_jumps_left, has_double_jumped, is_wall_sliding,
## wall_side) can be mirrored to other peers.
## Decisions here, looks elsewhere: jumped / double_jumped / wall_jumped / landed /
## wall_slide_changed / fell_into_pit / returned drive squash, dust, sounds and the camera kick
## (SidePlayerFx), the body animation comes from get_animation().
## Inputs are read in exactly one place (_read_input); a bot or a network peer replaces them through
## input_source (the multiplayer branch maps it to player.input).

signal jumped(player: Player)
signal double_jumped(player: Player)
signal wall_jumped(player: Player)
## Wall slide started (true) or ended (false).
signal wall_slide_changed(player: Player, sliding: bool)
## On landing; fall_speed = downward speed right before touching the ground.
signal landed(player: Player, fall_speed: float)
signal fell_into_pit(player: Player)
## Back on the last platform after a pit; damage = HP lost (0.5 steps).
signal returned(player: Player, damage: float)

## Jump shares the dash key of the top-down view (design: "Sprung auf der Dash-Taste"); the side
## dash gets its own action, created at runtime until the integrator adds it to project.godot.
const JUMP_ACTION := &"dash"
const DASH_ACTION := &"side_dash"
const DASH_KEY := KEY_SHIFT
const INPUT_LOCK_PIT := &"side_pit"
const INVULNERABLE_PIT := &"side_pit"
## Body while in side view: a box is steadier on platform edges than the top-down circle.
const BODY_SIZE := Vector2(20, 44)
const BODY_CENTER := Vector2(0, -6)
const FLOOR_SNAP := 10.0
## Downward speed from which the body shows the fall frame instead of the jump.
const FALL_ANIMATION_SPEED := 120.0
const LAND_ANIMATION_TIME := 0.12
## A landing after at least this much air time plays the landing sound and dust.
const LAND_EFFECT_AIR_TIME := 0.25
## The double jump shows its own animation (salto) this long.
const DOUBLE_JUMP_ANIMATION_TIME := 0.32
## A wall still counts this long after the last contact (wall jump without pressing into it).
const WALL_GRACE_TIME := 0.1


## One frame of side-view input. Today read from Input; a bot or a network peer fills the same
## fields (input_source).
class SideInput:
	extends RefCounted
	var axis := Vector2.ZERO
	var jump_pressed := false
	var jump_just_pressed := false
	var dash_just_pressed := false
	var attack_pressed := false


## Callable() -> SideInput replacing the keyboard (bot, network). Invalid = Input.
var input_source: Callable
## Facing in the run: +1 right, -1 left (camera look-ahead, dash without input).
var facing := 1.0
## Seconds this player has been outside the segment camera's view (co-op catch-up).
var outside_time := 0.0
## Pits fallen into during this segment (tools, tests).
var pit_falls := 0
## Jumps left in the air (the double jump); back to SideRules.AIR_JUMPS on the ground, a ladder or
## a wall.
var air_jumps_left := SideRules.AIR_JUMPS
## The double jump of this air time is used.
var has_double_jumped := false
## Sliding down a rock wall right now, and on which side the wall is (-1 left, +1 right, 0 none).
var is_wall_sliding := false
var wall_side := 0
## Double jumps and wall jumps during this segment (tools, tests).
var double_jumps := 0
var wall_jumps := 0

var _player: Player = null
var _world: SideSegment = null
var _active := false
var _coyote_left := 0.0
var _buffer_left := 0.0
var _jumping := false
var _climbing := false
var _ladder := Rect2()
var _excepted: Array[PhysicsBody2D] = []
var _dash_direction := 1.0
var _on_floor := false
var _air_time := 0.0
var _fall_speed := 0.0
var _land_left := 0.0
var _pit_left := 0.0
var _safe_feet := Vector2.INF
var _saved_shape: Shape2D = null
var _saved_shape_position := Vector2.ZERO
var _saved_motion_mode := CharacterBody2D.MOTION_MODE_FLOATING
var _last_input := SideInput.new()
var _wall_grace := 0.0
var _wall_jump_lock := 0.0
var _double_jump_left := 0.0


## The side motion of player, created on first use.
static func attach(player: Player) -> PlayerSideMotion:
	if player.side_motion == null:
		var motion := PlayerSideMotion.new()
		motion.name = "SideMotion"
		player.add_child(motion)
		motion._player = player
		player.side_motion = motion
	return player.side_motion


## Adds the side dash action when project.godot does not have it (hook for the integrator).
static func ensure_actions() -> void:
	if InputMap.has_action(DASH_ACTION):
		return
	InputMap.add_action(DASH_ACTION)
	var key := InputEventKey.new()
	key.physical_keycode = DASH_KEY
	InputMap.action_add_event(DASH_ACTION, key)


func is_active() -> bool:
	return _active


func get_world() -> SideSegment:
	return _world


func is_climbing() -> bool:
	return _climbing


func is_on_floor() -> bool:
	return _on_floor


func is_in_pit() -> bool:
	return _pit_left > 0.0


## Feet position the next pit returns to (global), INF before the first platform.
func get_safe_feet() -> Vector2:
	return _safe_feet


func get_last_input() -> SideInput:
	return _last_input


## Switches the player into side view in world, feet at feet (global).
func enter(world: SideSegment, feet: Vector2) -> void:
	if _player == null:
		_player = get_parent() as Player
	ensure_actions()
	_world = world
	_active = true
	var shape_node := _player.get_node("CollisionShape2D") as CollisionShape2D
	_saved_shape = shape_node.shape
	_saved_shape_position = shape_node.position
	var box := RectangleShape2D.new()
	box.size = BODY_SIZE
	shape_node.shape = box
	shape_node.position = BODY_CENTER
	_saved_motion_mode = _player.motion_mode
	_player.motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	_player.up_direction = Vector2.UP
	_player.floor_snap_length = FLOOR_SNAP
	_player.velocity = Vector2.ZERO
	_player.global_position = feet - Player.FEET_OFFSET
	_safe_feet = feet
	facing = world.get_run_direction() if world != null else 1.0
	_coyote_left = 0.0
	_buffer_left = 0.0
	_jumping = false
	_climbing = false
	_on_floor = true
	_air_time = 0.0
	_pit_left = 0.0
	outside_time = 0.0
	pit_falls = 0
	double_jumps = 0
	wall_jumps = 0
	_reset_air_jumps()
	_set_wall_sliding(false, 0)
	_set_shadow_visible(false)
	PlayerSideArt.ensure(_player.get_node("Sprite") as AnimatedSprite2D)


## Back to the top-down view (the body shape, the floating motion, the shadow).
func exit() -> void:
	if not _active:
		return
	_stop_climbing()
	_set_wall_sliding(false, 0)
	if _pit_left > 0.0:
		_pit_left = 0.0
		_player.set_body_visible(true)
		_player.set_input_locked(INPUT_LOCK_PIT, false)
		_player.hurtbox.set_invulnerable(INVULNERABLE_PIT, false)
	var shape_node := _player.get_node("CollisionShape2D") as CollisionShape2D
	shape_node.shape = _saved_shape
	shape_node.position = _saved_shape_position
	_player.motion_mode = _saved_motion_mode
	_player.velocity = Vector2.ZERO
	_set_shadow_visible(true)
	_active = false
	_world = null


## One physics step (Player._physics_process). has_control = false while stunned or locked: gravity
## and the pit return go on, the input does not. Returns the movement input for the body animation.
func physics_step(delta: float, has_control: bool) -> Vector2:
	if not _active:
		return Vector2.ZERO
	if _pit_left > 0.0:
		_pit_left -= delta
		if _pit_left <= 0.0:
			return_from_pit()
		return Vector2.ZERO
	var input := _read_input() if has_control else SideInput.new()
	_last_input = input
	if absf(input.axis.x) > 0.1:
		facing = signf(input.axis.x)
	if input.dash_just_pressed and not _climbing:
		var direction := signf(input.axis.x) if absf(input.axis.x) > 0.2 else facing
		if _player.try_dash(Vector2(direction, 0)):
			_dash_direction = direction
			_jumping = false
	_update_ladder(input)
	if _player.is_dashing():
		_player.velocity = Vector2(_dash_direction * _player.dash_speed, 0.0)
	elif _climbing:
		_climb(input, delta)
	else:
		_run_and_jump(input, delta)
	var falling_speed := _player.velocity.y
	_player.move_and_slide()
	_after_move(falling_speed, delta)
	return Vector2(input.axis.x, 0.0) if not _climbing else input.axis


## Body animation for this frame (Player._update_visuals).
func get_animation(move_input: Vector2) -> StringName:
	if _player.is_dashing():
		return &"dash"
	if _climbing:
		return PlayerSideArt.CLIMB if absf(move_input.y) > 0.1 else &"idle"
	if is_wall_sliding:
		return PlayerSideArt.WALL_SLIDE
	if not _on_floor and _double_jump_left > 0.0:
		return PlayerSideArt.DOUBLE_JUMP
	if not _on_floor:
		return PlayerSideArt.FALL if _player.velocity.y > FALL_ANIMATION_SPEED else PlayerSideArt.JUMP
	if _land_left > 0.0:
		return PlayerSideArt.LAND
	return &"walk" if absf(move_input.x) > 0.1 else &"idle"


# --- Decisions ---

## Leaves the segment downwards: gone for PIT_RETURN_TIME, then back on the last platform.
func start_pit() -> void:
	if _pit_left > 0.0 or not _player.is_alive():
		return
	_stop_climbing()
	_pit_left = SideRules.PIT_RETURN_TIME
	pit_falls += 1
	_player.velocity = Vector2.ZERO
	_player.set_input_locked(INPUT_LOCK_PIT, true)
	_player.hurtbox.set_invulnerable(INVULNERABLE_PIT, true)
	_player.set_body_visible(false)
	fell_into_pit.emit(_player)


## Back on the last safe platform: the damage of an abyss in a room (D-115, decision of 15.10.2026:
## a whole heart past the shield, may kill), then the short invulnerability of a fall.
func return_from_pit() -> void:
	_pit_left = 0.0
	var feet := _safe_feet if _safe_feet != Vector2.INF else _world.get_start_feet()
	_player.global_position = feet - Player.FEET_OFFSET
	_player.velocity = Vector2.ZERO
	_player.set_body_visible(true)
	_player.set_input_locked(INPUT_LOCK_PIT, false)
	_player.hurtbox.set_invulnerable(INVULNERABLE_PIT, false)
	var dealt := PlayerFall.apply_fall_damage(_player, SideRules.pit_damage())
	if _player.is_alive():
		_player.grant_invulnerability(ChasmRules.RESPAWN_INVULNERABILITY)
	returned.emit(_player, dealt)


## Puts the player at feet (global) on the ground, e.g. the co-op catch-up.
func place_at(feet: Vector2) -> void:
	_stop_climbing()
	_player.global_position = feet - Player.FEET_OFFSET
	_player.velocity = Vector2.ZERO
	outside_time = 0.0


# --- Input ---

## The only place the side view reads input (multiplayer: player.input instead of Input).
func _read_input() -> SideInput:
	if input_source.is_valid():
		var provided: Variant = input_source.call()
		if provided is SideInput:
			return provided
	var input := SideInput.new()
	input.axis = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	input.jump_pressed = Input.is_action_pressed(JUMP_ACTION)
	input.jump_just_pressed = Input.is_action_just_pressed(JUMP_ACTION)
	input.dash_just_pressed = InputMap.has_action(DASH_ACTION) and Input.is_action_just_pressed(DASH_ACTION)
	input.attack_pressed = Input.is_action_pressed(&"attack")
	return input


# --- Movement ---

func _run_and_jump(input: SideInput, delta: float) -> void:
	var velocity := _player.velocity
	var target := input.axis.x * _player.move_speed * SideRules.RUN_SPEED_FACTOR
	if _wall_jump_lock > 0.0:
		# Right after a wall jump the stick cannot pull the body back into the wall.
		_wall_jump_lock -= delta
		target = velocity.x
	var acceleration := SideRules.GROUND_ACCELERATION if _on_floor else SideRules.AIR_ACCELERATION
	velocity.x = move_toward(velocity.x, target, acceleration * delta)
	velocity.y = minf(velocity.y + gravity_for(velocity.y) * delta, SideRules.MAX_FALL_SPEED)
	# Wall slide: in the air, falling, pressing into a rock wall.
	_wall_grace = maxf(0.0, _wall_grace - delta)
	if _wall_grace <= 0.0:
		wall_side = 0
	var sliding := not _on_floor and wall_side != 0 and _wall_grace > 0.0 and velocity.y > 0.0 \
			and input.axis.x * wall_side > 0.5
	if sliding:
		velocity.y = minf(velocity.y, SideRules.WALL_SLIDE_SPEED)
		_reset_air_jumps()
	_set_wall_sliding(sliding, wall_side)
	if _on_floor:
		_coyote_left = SideRules.COYOTE_TIME
	else:
		_coyote_left = maxf(0.0, _coyote_left - delta)
	if input.jump_just_pressed:
		_buffer_left = SideRules.JUMP_BUFFER_TIME
	else:
		_buffer_left = maxf(0.0, _buffer_left - delta)
	if _buffer_left > 0.0 and _coyote_left > 0.0:
		velocity.y = -SideRules.JUMP_VELOCITY
		_buffer_left = 0.0
		_coyote_left = 0.0
		_jumping = true
		_on_floor = false
		jumped.emit(_player)
	elif input.jump_just_pressed and not _on_floor and wall_side != 0 and _wall_grace > 0.0:
		velocity = Vector2(-wall_side * SideRules.WALL_JUMP_VELOCITY.x, -SideRules.WALL_JUMP_VELOCITY.y)
		facing = -float(wall_side)
		_wall_jump_lock = SideRules.WALL_JUMP_LOCK
		_wall_grace = 0.0
		_buffer_left = 0.0
		_jumping = true
		_reset_air_jumps()
		_set_wall_sliding(false, 0)
		wall_jumps += 1
		wall_jumped.emit(_player)
	elif input.jump_just_pressed and not _on_floor and air_jumps_left > 0:
		velocity.y = -SideRules.DOUBLE_JUMP_VELOCITY
		if absf(input.axis.x) > 0.1:
			# The second jump may turn: full speed in the pressed direction at once.
			velocity.x = input.axis.x * _player.move_speed * SideRules.RUN_SPEED_FACTOR
		air_jumps_left -= 1
		has_double_jumped = true
		double_jumps += 1
		_buffer_left = 0.0
		_jumping = true
		_double_jump_left = DOUBLE_JUMP_ANIMATION_TIME
		double_jumped.emit(_player)
	elif _jumping and velocity.y < 0.0 and not input.jump_pressed:
		# Variable height: letting go early cuts the rise.
		velocity.y *= SideRules.JUMP_CUT_FACTOR
		_jumping = false
	_player.velocity = velocity


## Gravity for a vertical speed: faster falling, a short hang around the apex (SideRules).
static func gravity_for(vertical_speed: float) -> float:
	var gravity := SideRules.GRAVITY * (SideRules.FALL_GRAVITY_FACTOR if vertical_speed > 0.0 else 1.0)
	if absf(vertical_speed) < SideRules.APEX_SPEED:
		gravity *= SideRules.APEX_GRAVITY_FACTOR
	return gravity


func _reset_air_jumps() -> void:
	air_jumps_left = SideRules.AIR_JUMPS
	has_double_jumped = false


func _set_wall_sliding(sliding: bool, side: int) -> void:
	if sliding == is_wall_sliding:
		return
	is_wall_sliding = sliding
	if not sliding and side == 0:
		wall_side = 0
	wall_slide_changed.emit(_player, sliding)


func _climb(input: SideInput, delta: float) -> void:
	var center_x := _ladder.get_center().x
	_player.global_position.x = move_toward(_player.global_position.x, center_x, 240.0 * delta)
	_player.velocity = Vector2(0.0, input.axis.y * SideRules.CLIMB_SPEED)
	var next_feet_y := _player.get_feet_position().y + _player.velocity.y * delta
	if input.axis.y < -0.1 and next_feet_y <= _ladder.position.y + 0.5:
		# This step reaches the top: stand on the top step instead of overshooting it.
		_player.global_position.y = _ladder.position.y - Player.FEET_OFFSET.y - 0.5
		_player.velocity = Vector2.ZERO
		_stop_climbing()
		return
	if input.jump_just_pressed:
		_stop_climbing()
		_player.velocity = Vector2(input.axis.x * _player.move_speed, -SideRules.JUMP_VELOCITY * 0.8)
		_jumping = true
		jumped.emit(_player)


func _update_ladder(input: SideInput) -> void:
	if _world == null:
		return
	var feet := _player.get_feet_position()
	if _climbing:
		var rect := _world.ladder_rect_at(feet)
		if not rect.has_area():
			_stop_climbing()
		elif input.axis.y < -0.1 and feet.y <= _ladder.position.y + 0.5:
			# At the top: stand on the top step.
			_player.global_position.y = _ladder.position.y - Player.FEET_OFFSET.y - 0.5
			_player.velocity.y = 0.0
			_stop_climbing()
		elif input.axis.y > 0.1 and feet.y >= _ladder.end.y - 1.0 and _player.is_on_floor():
			_stop_climbing()
		elif absf(input.axis.x) > 0.6 and absf(input.axis.y) < 0.4:
			_stop_climbing()
		return
	if _player.is_dashing():
		return
	var ladder := _world.ladder_rect_at(feet)
	if not ladder.has_area() or absf(_player.global_position.x - ladder.get_center().x) > SideRules.LADDER_GRAB_DISTANCE:
		return
	var going_up := input.axis.y < -0.5 and feet.y > ladder.position.y + 2.0
	var going_down := input.axis.y > 0.5 and feet.y < ladder.end.y - 2.0
	if going_up or going_down:
		_start_climbing(ladder)


func _start_climbing(ladder: Rect2) -> void:
	_climbing = true
	_ladder = ladder
	_jumping = false
	_reset_air_jumps()
	_set_wall_sliding(false, 0)
	_player.velocity = Vector2.ZERO
	# The one-way top steps let a climber through in both directions.
	for body in _world.get_ladder_bodies():
		if not _excepted.has(body):
			_player.add_collision_exception_with(body)
			_excepted.append(body)


func _stop_climbing() -> void:
	_climbing = false
	for body in _excepted:
		if is_instance_valid(body):
			_player.remove_collision_exception_with(body)
	_excepted.clear()


func _after_move(falling_speed: float, delta: float) -> void:
	var was_on_floor := _on_floor
	_on_floor = _player.is_on_floor() or _climbing
	_land_left = maxf(0.0, _land_left - delta)
	_double_jump_left = maxf(0.0, _double_jump_left - delta)
	# Rock walls (ledges and ladder steps are one-way and never count as walls).
	if not _on_floor and not _climbing and _player.is_on_wall():
		var normal := _player.get_wall_normal()
		if absf(normal.x) > 0.7:
			wall_side = -int(signf(normal.x))
			_wall_grace = WALL_GRACE_TIME
	if _on_floor:
		_set_wall_sliding(false, 0)
		wall_side = 0
		_wall_grace = 0.0
		_reset_air_jumps()
		_double_jump_left = 0.0
		if not was_on_floor and not _climbing:
			_land_left = LAND_ANIMATION_TIME
			if _air_time >= LAND_EFFECT_AIR_TIME:
				landed.emit(_player, maxf(falling_speed, _fall_speed))
			_jumping = false
		_air_time = 0.0
		_fall_speed = 0.0
	else:
		_air_time += delta
		_fall_speed = maxf(_fall_speed, _player.velocity.y)
	if _world == null:
		return
	var feet := _player.get_feet_position()
	if _on_floor and not _climbing and not _player.is_dashing():
		var safe := _world.safe_feet_for(feet)
		if safe != Vector2.INF:
			_safe_feet = safe
	if feet.y > _world.get_kill_y():
		start_pit()


func _set_shadow_visible(shadow_visible: bool) -> void:
	var shadow := _player.get_node_or_null("DropShadow") as CanvasItem
	if shadow != null:
		shadow.visible = shadow_visible

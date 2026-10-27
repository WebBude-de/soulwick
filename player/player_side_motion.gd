class_name PlayerSideMotion
extends Node
## Side-view platform motion of one player (M5, gang segments). While active, Player hands its
## movement over to this node (Player.side_motion, three small hooks in player.gd): gravity with a
## short hang at the apex and faster falling, a 2.5-tile jump with coyote time, jump buffer and
## variable height, one double jump in the air, wall slide and wall jump on rock, ladders up and
## down, falling out of the segment; no dash in side view (D-216: the jump is the only move key).
## Weapons, hits, upgrades, health, shield and the HUD stay the player's own, so nothing else
## changes. The state lives here, per player (multiplayer
## rule): coyote and buffer timers, air jumps, the wall, the ladder, the last safe platform, the
## time outside the view; the public fields (air_jumps_left, has_double_jumped, is_wall_sliding,
## wall_side) can be mirrored to other peers.
## Decisions here, looks elsewhere: jumped / double_jumped / wall_jumped / landed /
## wall_slide_changed / fell_into_pit / returned drive squash, dust, sounds and the camera kick
## (SidePlayerFx), the body animation comes from get_animation().
## Inputs are read in exactly one place (_read_input): the player's own input object (MP1: keyboard
## at this machine, RemoteInput for network players and bots), or input_source when a bot drives.
## Group game (co-op): the host decides every player's moves. A copy of another machine's player
## (moves_from_remote) never decides a jump, a wall slide or a landing itself; it moves with the
## host's velocity, takes the moves as events (apply_remote_move: the same signals, so salto and dust
## show on every machine) and the air state from the synced bits (apply_remote_air_state).
## Momentum and stomping (D-195, SV1, D-216): running on in one direction speeds the player up
## (momentum, SideMomentum, 1.3× to 2.0×), landing on a side enemy from above stomps it and bounces
## (SideContactRules); nobody is run over - touching an enemy from the side hurts at any speed (the
## enemy's contact). The enemy has the last word (SideEnemy.on_stomped, true = taken); only a
## machine that decides enemy contacts asks it (the host and a solo run: decides_enemy_contacts,
## never a copy, never an enemy that is a host's puppet), the bounce goes to the others as
## Move.STOMP. Slopes (SideSlopes): on a layout with slopes the body counts them as floor (enter).
## In side view the drop shadows under the player and Flint are hidden (they belong to the floor of
## the top-down view, feedback #e0486234).

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
## The player stomped an enemy (taken by the enemy) and bounces; enemy is null on a copy that only
## shows the host's stomp.
signal stomped(player: Player, enemy: Node2D)
## The momentum is gone (stop, turn, wall, hit, ladder, pit).
signal momentum_lost(player: Player)

## Jump shares the dash key of the top-down view (design: "Sprung auf der Dash-Taste"). The side
## dash is gone (D-216, feedback #9aeff0be); its action stays in project.godot and the input menus
## until the integrator removes it there, this motion never reads it.
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


## Short protection after a stomp (SideContactRules.CONTACT_GRACE).
const INVULNERABLE_CONTACT := &"side_contact"
## An enemy that refused a stomp is not asked again for this long (seconds, TESTWERT).
const REFUSED_MEMORY := 0.4


## Moves the host sends for the copies at the other machines (NetSide.side_move_net). New moves only
## at the end (the number travels).
enum Move { JUMP, DOUBLE_JUMP, WALL_JUMP, LAND, STOMP }


## One frame of side-view input, read from the player's input object; a bot fills the same fields
## (input_source).
class SideInput:
	extends RefCounted
	var axis := Vector2.ZERO
	var jump_pressed := false
	var jump_just_pressed := false
	var attack_pressed := false


## Callable() -> SideInput replacing the player's input (bot). Invalid = player.input.
var input_source: Callable
## Facing in the run: +1 right, -1 left (camera look-ahead).
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
## Network copy of a player who runs at another machine: jumps, double jumps, wall jumps, wall
## slides and landings come from the host (apply_remote_move, apply_remote_air_state), not from the
## replayed input; set by NetPlayerState. False for the player at this machine and at the host.
var moves_from_remote := false
## Momentum of this player (state at the player; every machine runs it from the same input).
var momentum := SideMomentum.new()
## This machine decides the stomps of this player (host, solo run). A client's NetSide turns it
## off for its own player (the host decides and sends Move.STOMP); a copy never decides anyway.
var decides_enemy_contacts := true
## Stomps during this segment (tools, tests).
var stomps := 0
## The ramp cell this player runs on (SideSlopes; Vector2i(-1, -1): none) and the ramp throws
## during this segment (tools, tests).
var ramp_cell := Vector2i(-1, -1)
var ramp_launches := 0

var _player: Player = null
var _world: SideSegment = null
var _active := false
var _coyote_left := 0.0
var _buffer_left := 0.0
var _jumping := false
var _climbing := false
var _ladder := Rect2()
var _excepted: Array[PhysicsBody2D] = []
var _on_floor := false
var _air_time := 0.0
var _fall_speed := 0.0
var _land_left := 0.0
var _pit_left := 0.0
var _safe_feet := Vector2.INF
var _saved_shape: Shape2D = null
var _saved_shape_position := Vector2.ZERO
var _saved_motion_mode := CharacterBody2D.MOTION_MODE_FLOATING
var _saved_floor_angle := 0.0
var _saved_floor_snap := 0.0
var _saved_constant_speed := false
var _last_input := SideInput.new()
var _wall_grace := 0.0
var _wall_jump_lock := 0.0
var _double_jump_left := 0.0
var _contact_grace_left := 0.0
var _stomp_left := 0.0
var _last_health := 0.0
var _last_shield := 0.0
## Instance id of an enemy that refused -> seconds until it may be asked again.
var _refused: Dictionary[int, float] = {}


## The side motion of player, created on first use.
static func attach(player: Player) -> PlayerSideMotion:
	if player.side_motion == null:
		var motion := PlayerSideMotion.new()
		motion.name = "SideMotion"
		player.add_child(motion)
		motion._player = player
		player.side_motion = motion
	return player.side_motion


## Hook for the HUD (weapon bar "Dash", key row; integrator): a player has the dash only outside
## side view (D-216, feedback #9aeff0be).
static func has_dash(player: Player) -> bool:
	return player != null and not player.is_side_view()


## Adds the side dash action when project.godot does not have it (input menus and Flint's hint still
## name it until the integrator removes it, D-216; never read here).
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


## Rising from a jump the player still holds (variable height; network state).
func is_jumping() -> bool:
	return _jumping


## Network copy of a player who runs at another machine (NetPlayerState): the ladder, the pit and
## the facing of the authoritative copy, so the replayed movement climbs and falls where it does.
func apply_remote_state(climbing: bool, in_pit: bool, remote_facing: float) -> void:
	if not _active or _player == null:
		return
	if remote_facing != 0.0:
		facing = signf(remote_facing)
	if in_pit:
		if _pit_left <= 0.0:
			start_pit()
		return
	if climbing and not _climbing and _world != null:
		var ladder := _world.ladder_rect_at(_player.get_feet_position())
		if ladder.has_area():
			_start_climbing(ladder)
	elif not climbing and _climbing:
		_stop_climbing()


## Network copy: a move the host decided for this player (Move), with the velocity right after it,
## the facing and (LAND) the fall speed. Same state changes and signals as at the host, so the looks
## (SidePlayerFx: stretch, salto, dust, landing) play on every machine.
func apply_remote_move(move: Move, remote_velocity: Vector2, remote_facing: float, fall_speed := 0.0) -> void:
	if not _active or _player == null:
		return
	if remote_facing != 0.0:
		facing = signf(remote_facing)
	match move:
		Move.JUMP:
			_player.velocity = remote_velocity
			_stop_climbing()
			_jumping = true
			_on_floor = false
			jumped.emit(_player)
		Move.DOUBLE_JUMP:
			_player.velocity = remote_velocity
			air_jumps_left = maxi(0, air_jumps_left - 1)
			has_double_jumped = true
			double_jumps += 1
			_jumping = true
			_on_floor = false
			_double_jump_left = DOUBLE_JUMP_ANIMATION_TIME
			double_jumped.emit(_player)
		Move.WALL_JUMP:
			_player.velocity = remote_velocity
			_jumping = true
			_on_floor = false
			_reset_air_jumps()
			_set_wall_sliding(false, 0)
			wall_jumps += 1
			wall_jumped.emit(_player)
		Move.LAND:
			_land_left = LAND_ANIMATION_TIME
			_double_jump_left = 0.0
			_jumping = false
			landed.emit(_player, fall_speed)
		Move.STOMP:
			# Only the height: a client's own player keeps its predicted run.
			_bounce(remote_velocity.y)
			stomps += 1
			stomped.emit(_player, null)


## Network copy: the air state of the host's copy (synced 30/s): wall slide and its side, double jump
## used. Starts and ends the slide look (wall_slide_changed) where the host's player slides.
func apply_remote_air_state(sliding: bool, remote_wall_side: int, double_jumped: bool) -> void:
	if not _active or _player == null:
		return
	if double_jumped != has_double_jumped:
		has_double_jumped = double_jumped
		air_jumps_left = SideRules.AIR_JUMPS - (1 if double_jumped else 0)
	if sliding:
		wall_side = signi(remote_wall_side)
	_set_wall_sliding(sliding, wall_side if sliding else 0)


## Feet position the next pit returns to (global), INF before the first platform.
func get_safe_feet() -> Vector2:
	return _safe_feet


func get_last_input() -> SideInput:
	return _last_input


## Running speed as a factor on the move speed right now (1.3 without momentum; looks, SV5).
func get_speed_factor() -> float:
	return momentum.factor()


## Loses the momentum (decision; momentum_lost drives the looks). Also the hook for a client whose
## HP or shield the host lowered.
func lose_momentum() -> void:
	if momentum.reset():
		momentum_lost.emit(_player)


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
	_set_up_floor(world != null and world.layout != null and not world.layout.slopes.is_empty())
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
	stomps = 0
	ramp_cell = Vector2i(-1, -1)
	ramp_launches = 0
	momentum.reset()
	_contact_grace_left = 0.0
	_refused.clear()
	_reset_air_jumps()
	_set_wall_sliding(false, 0)
	_set_shadow_visible(false)
	_watch_vitals(true)
	PlayerSideArt.ensure(_player.get_node("Sprite") as AnimatedSprite2D)
	SideSpeedArt.ensure(_player.get_node("Sprite") as AnimatedSprite2D)


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
	_contact_grace_left = 0.0
	_player.hurtbox.set_invulnerable(INVULNERABLE_CONTACT, false)
	_watch_vitals(false)
	momentum.reset()
	var shape_node := _player.get_node("CollisionShape2D") as CollisionShape2D
	shape_node.shape = _saved_shape
	shape_node.position = _saved_shape_position
	_player.motion_mode = _saved_motion_mode
	_player.floor_max_angle = _saved_floor_angle
	_player.floor_snap_length = _saved_floor_snap
	_player.floor_constant_speed = _saved_constant_speed
	_player.velocity = Vector2.ZERO
	_set_shadow_visible(true)
	_active = false
	_world = null


## One physics step (Player._physics_process). has_control = false while stunned or locked: gravity
## and the pit return go on, the input does not. Returns the movement input for the body animation.
func physics_step(delta: float, has_control: bool) -> Vector2:
	if not _active:
		return Vector2.ZERO
	_tick_contact_grace(delta)
	if _pit_left > 0.0:
		_pit_left -= delta
		if _pit_left <= 0.0:
			return_from_pit()
		return Vector2.ZERO
	var input := _read_input() if has_control else SideInput.new()
	_last_input = input
	if absf(input.axis.x) > 0.1:
		facing = signf(input.axis.x)
	_update_ladder(input)
	if _climbing:
		_climb(input, delta)
	else:
		_run_and_jump(input, delta)
	var falling_speed := _player.velocity.y
	var previous_feet := _player.get_feet_position()
	_player.move_and_slide()
	_after_move(falling_speed, delta)
	_check_enemy_contacts(previous_feet, falling_speed, delta)
	return Vector2(input.axis.x, 0.0) if not _climbing else input.axis


## Body animation for this frame (Player._update_visuals).
func get_animation(move_input: Vector2) -> StringName:
	if _climbing:
		return PlayerSideArt.CLIMB if absf(move_input.y) > 0.1 else &"idle"
	if is_wall_sliding:
		return PlayerSideArt.WALL_SLIDE
	if not _on_floor and _double_jump_left > 0.0:
		return PlayerSideArt.DOUBLE_JUMP
	if not _on_floor and _stomp_left > 0.0 and _has_animation(SideSpeedArt.STOMP):
		return SideSpeedArt.STOMP
	if not _on_floor:
		return PlayerSideArt.FALL if _player.velocity.y > FALL_ANIMATION_SPEED else PlayerSideArt.JUMP
	if _land_left > 0.0:
		return PlayerSideArt.LAND
	if absf(move_input.x) <= 0.1:
		return &"idle"
	if momentum.factor() >= SideSpeedArt.SPRINT_FACTOR and _has_animation(SideSpeedArt.SPRINT):
		return SideSpeedArt.SPRINT
	return &"walk"


func _has_animation(animation: StringName) -> bool:
	var sprite := _player.get_node_or_null("Sprite") as AnimatedSprite2D
	return sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation(animation)


# --- Decisions ---

## Leaves the segment downwards: gone for PIT_RETURN_TIME, then back on the last platform.
func start_pit() -> void:
	if _pit_left > 0.0 or not _player.is_alive():
		return
	_stop_climbing()
	lose_momentum()
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


# --- Enemies: stomp (D-195, SV1, D-216) ---

## Whether this machine decides the stomps of this player: the host and a solo run, never
## a copy of another machine's player, never a client's own player once NetSide switched it off.
func decides_contacts() -> bool:
	return decides_enemy_contacts and not moves_from_remote and _world != null and _player != null \
			and _player.is_alive()


## After the move: a stomp on an enemy below (it bounces). The enemy takes it or refuses it (then its
## own contact or reaction hurts, not this code); touching it from the side is the enemy's contact.
func _check_enemy_contacts(previous_feet: Vector2, fall_speed: float, delta: float) -> void:
	_tick_refused(delta)
	if not decides_contacts() or _pit_left > 0.0 or _climbing:
		return
	var feet := _player.get_feet_position()
	for enemy: Node2D in _world.get_enemies():
		if not _is_open_enemy(enemy):
			continue
		var rect := SideContactRules.enemy_body_rect(enemy)
		if SideContactRules.is_stomp(previous_feet, feet, fall_speed, BODY_SIZE.x * 0.5, rect, delta):
			if _ask_enemy(enemy, &"on_stomped", SideContactRules.TAG_STOMP):
				_take_stomp(enemy)
				return
			_refuse(enemy)


## A living enemy this machine runs itself (a client's enemies are the host's puppets with their
## physics off) and that did not just refuse this player.
func _is_open_enemy(enemy: Node2D) -> bool:
	if not is_instance_valid(enemy) or not enemy.is_physics_processing():
		return false
	if enemy.has_method(&"is_dead") and enemy.call(&"is_dead"):
		return false
	return not _refused.has(enemy.get_instance_id())


## Asks the enemy (SV4 hook: on_stomped(player) -> bool, true = taken). An enemy
## without the hook is a normal one: it is beaten through its hurtbox (kill rewards as usual).
func _ask_enemy(enemy: Node2D, hook: StringName, tag: StringName) -> bool:
	if enemy.has_method(hook):
		var answer: Variant = enemy.call(hook, _player)
		return answer is bool and answer
	return _defeat(enemy, tag)


func _defeat(enemy: Node2D, tag: StringName) -> bool:
	var enemy_hurtbox := enemy.get(&"hurtbox") as Hurtbox
	var enemy_health := enemy.get(&"health") as HealthComponent
	if enemy_hurtbox == null or enemy_health == null or enemy_health.is_dead():
		return false
	var damage := DamageData.new()
	damage.amount = ceilf(enemy_health.get_health()) + 1.0
	damage.source = _player
	damage.tags.assign([tag])
	damage.hit_id = DamageData.next_hit_id()
	damage.knockback = Vector2(signf(enemy.global_position.x - _player.global_position.x) * 200.0, 0.0)
	return not enemy_hurtbox.receive_hit(damage).blocked


func _take_stomp(enemy: Node2D) -> void:
	stomps += 1
	_bounce()
	_grant_contact_grace()
	stomped.emit(_player, enemy)


## Throws the body straight up with vertical_velocity (< 0; a spring, SV2): ends a running jump, so
## letting go of the button cannot cut the rise (variable height), and leaves the floor; the double
## jump stays free for the top.
func launch(vertical_velocity: float) -> void:
	_player.velocity.y = vertical_velocity
	_jumping = false
	_on_floor = false
	_coyote_left = 0.0
	_buffer_left = 0.0


## Up off a stomped enemy: STOMP_BOUNCE_TILES high (not cut by letting go of the jump), the double
## jump back. vertical_velocity < 0: the host's bounce speed (a copy or a client's own player).
func _bounce(vertical_velocity := 0.0) -> void:
	_player.velocity.y = vertical_velocity if vertical_velocity < 0.0 else -SideContactRules.stomp_bounce_velocity()
	_jumping = false
	_on_floor = false
	_coyote_left = 0.0
	_double_jump_left = 0.0
	_stomp_left = SideSpeedArt.STOMP_ANIMATION_TIME
	_reset_air_jumps()


func _grant_contact_grace() -> void:
	_contact_grace_left = SideContactRules.CONTACT_GRACE
	_player.hurtbox.set_invulnerable(INVULNERABLE_CONTACT, true)


func _tick_contact_grace(delta: float) -> void:
	if _contact_grace_left <= 0.0:
		return
	_contact_grace_left -= delta
	if _contact_grace_left <= 0.0:
		_player.hurtbox.set_invulnerable(INVULNERABLE_CONTACT, false)


## An enemy that refused is not asked again for REFUSED_MEMORY seconds (its own hit decides).
func _refuse(enemy: Node2D) -> void:
	_refused[enemy.get_instance_id()] = REFUSED_MEMORY


func _tick_refused(delta: float) -> void:
	for id: int in _refused.keys():
		_refused[id] -= delta
		if _refused[id] <= 0.0:
			_refused.erase(id)


## HP or shield going down is a hit (also a client's, whose vitals the host sets): momentum lost.
func _watch_vitals(watch: bool) -> void:
	var health := _player.health
	var shield := _player.shield
	if watch:
		_last_health = health.get_health() if health != null else 0.0
		_last_shield = shield.get_shield() if shield != null else 0.0
		if health != null and not health.health_changed.is_connected(_on_health_changed):
			health.health_changed.connect(_on_health_changed)
		if shield != null and not shield.shield_changed.is_connected(_on_shield_changed):
			shield.shield_changed.connect(_on_shield_changed)
		return
	if health != null and health.health_changed.is_connected(_on_health_changed):
		health.health_changed.disconnect(_on_health_changed)
	if shield != null and shield.shield_changed.is_connected(_on_shield_changed):
		shield.shield_changed.disconnect(_on_shield_changed)


func _on_health_changed(current: float, _maximum: float) -> void:
	if current < _last_health - 0.001:
		lose_momentum()
	_last_health = current


func _on_shield_changed(current: float) -> void:
	if current < _last_shield - 0.001:
		lose_momentum()
	_last_shield = current


# --- Input ---

## The only place the side view reads input: a bot's input_source, else player.input (polled by
## the player at the start of its physics frame; RemoteInput and the network work as in top-down).
func _read_input() -> SideInput:
	if input_source.is_valid():
		var provided: Variant = input_source.call()
		if provided is SideInput:
			return provided
	var input := SideInput.new()
	var commands := _player.input if _player != null else null
	if commands == null:
		return input
	input.axis = commands.move
	input.jump_pressed = commands.is_pressed(JUMP_ACTION)
	input.jump_just_pressed = commands.is_just_pressed(JUMP_ACTION)
	input.attack_pressed = commands.is_pressed(PlayerInput.ATTACK)
	return input


# --- Movement ---

func _run_and_jump(input: SideInput, delta: float) -> void:
	var velocity := _player.velocity
	if momentum.update(delta, _on_floor, input.axis.x):
		momentum_lost.emit(_player)
	var target := input.axis.x * _player.move_speed * momentum.factor()
	if _wall_jump_lock > 0.0:
		# Right after a wall jump the stick cannot pull the body back into the wall.
		_wall_jump_lock -= delta
		target = velocity.x
	var acceleration := SideRules.GROUND_ACCELERATION if _on_floor else SideRules.AIR_ACCELERATION
	velocity.x = move_toward(velocity.x, target, acceleration * delta)
	velocity.y = minf(velocity.y + gravity_for(velocity.y) * delta, SideRules.MAX_FALL_SPEED)
	if moves_from_remote:
		# A copy: the host decides jumps and slides (apply_remote_move / apply_remote_air_state).
		if is_wall_sliding:
			velocity.y = minf(velocity.y, SideRules.WALL_SLIDE_SPEED)
		_player.velocity = velocity
		return
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
			# The second jump may turn: full speed in the pressed direction at once (a turn has
			# just lost the momentum, so only straight on keeps it).
			velocity.x = input.axis.x * _player.move_speed * momentum.factor()
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
	if input.jump_just_pressed and not moves_from_remote:
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
	lose_momentum()
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
	_stomp_left = maxf(0.0, _stomp_left - delta)
	if momentum.direction != 0 and _player.is_on_wall() and not _climbing \
			and _player.get_wall_normal().x * momentum.direction < -0.7:
		# Ran into a wall (on the ground or in the air): the momentum is gone.
		lose_momentum()
	# Rock walls (ledges and ladder steps are one-way and never count as walls).
	if not _on_floor and not _climbing and not moves_from_remote and _player.is_on_wall():
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
		if not was_on_floor and not _climbing and not moves_from_remote:
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
	if _on_floor and not _climbing:
		var safe := _world.safe_feet_for(feet)
		if safe != Vector2.INF:
			_safe_feet = safe
	if feet.y > _world.get_kill_y():
		start_pit()


## The drop shadows of the top-down view under the player and everything carried along (Flint):
## hidden through their alpha, so the owners' own visible switches (pit, Flint's excursion) cannot
## bring them back in side view (feedback #e0486234).
func _set_shadow_visible(shadow_visible: bool) -> void:
	for shadow: Node in _player.find_children("*", "DropShadow", true, false):
		(shadow as CanvasItem).self_modulate.a = 1.0 if shadow_visible else 0.0


## The body's floor rules in side view (saved for exit): slopes count as floor at constant speed
## when the layout has some (SideSlopes.FLOOR_*), else the plain side-view snap.
func _set_up_floor(with_slopes: bool) -> void:
	_saved_floor_angle = _player.floor_max_angle
	_saved_floor_snap = _player.floor_snap_length
	_saved_constant_speed = _player.floor_constant_speed
	_player.floor_max_angle = deg_to_rad(SideSlopes.FLOOR_MAX_ANGLE_DEGREES) if with_slopes else deg_to_rad(45.0)
	_player.floor_snap_length = SideSlopes.FLOOR_SNAP if with_slopes else FLOOR_SNAP
	_player.floor_constant_speed = with_slopes

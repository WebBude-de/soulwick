class_name Player
extends CharacterBody2D
## Player body: WASD movement, 360° mouse aim, dash, hit I-frames and E interaction (PRD 4.3).
## HP/shield/weapons live in child components. Node origin = body centre; feet are below it.
## Abysses (A4): the dash is in the air; falling and the last safe spot live in the PlayerFall child.
## Several players (MP1): commands come only from the input object (keyboard/mouse or RemoteInput);
## camera, prompts and screen shake belong to the local player.

signal died
## MP3 (D-084): a downed player got up again (revived by a teammate or the cleared room).
signal revived
signal blinded(duration: float)
## Emitted when an effective hit stuns the player (screen tilt, post-process wobble).
signal stunned(duration: float)

const INVULNERABLE_DASH: StringName = &"dash"
const INVULNERABLE_HIT: StringName = &"hit"
const HIT_FLASH_COLOR := Color(1.0, 0.35, 0.35)
const HIT_FLASH_DURATION := 0.15
const INVULNERABLE_ALPHA := 0.5
const DASH_DUST_TEXTURE: Texture2D = preload("res://art/effects/dash_dust_4f.png")
## Body sprite: 32 px frames, the body centre sits at (16, 22), the hand at (19, 19).
const SPRITE_FRAME := Vector2i(32, 32)
const SPRITE_ORIGIN := Vector2(16, 22)
const HAND_OFFSET := Vector2(3, -3)
const FEET_OFFSET := Vector2(0, 16)
## Visual swing of the held sword, matches WeaponController.SWING_ACTIVE_TIME.
const WEAPON_SWING_TIME := 0.12
## How long a slammed weapon stays down on the aim direction after the impact.
const SLAM_HOLD_TIME := 0.15
## How fast the recoil kick of the held weapon settles, in px/s.
const WEAPON_KICK_RECOVERY := 60.0
const STUN_STAR_COUNT := 3
const STUN_STAR_RADIUS := 14.0
const STUN_STAR_HEIGHT := -40.0
const STATUS_TEXT_COLOR := Color(1.0, 0.9, 0.4)
## Drop shadow under the feet (half width in world px).
const SHADOW_RADIUS := 14.0
## I-frames after getting up from the floor (MP3, TESTWERT).
const REVIVE_INVULNERABILITY := 1.5

## PLATZHALTER: player move speed is not specified in the GDD.
@export var move_speed := 180.0
@export_group("Dash (TESTWERTE)")
@export var dash_duration := 0.2
@export var dash_speed := 450.0
@export var dash_cooldown := 1.5
@export_group("Hit I-frames")
## Started by every effective hit on shield or HP (D-017).
@export var hit_invulnerability_time := 0.5

var _dash_time_left := 0.0
var _dash_cooldown_left := 0.0
var _dash_direction := Vector2.RIGHT
var _hit_invulnerability_left := 0.0
var _aim := Vector2.RIGHT
var _weapon_swing_left := 0.0
var _weapon_swing_arc := 0.0
var _weapon_swing_time := WEAPON_SWING_TIME
var _weapon_swing_one_sided := false
var _weapon_kick := 0.0
var _focused_interactable: Interactable = null
var _stun_left := 0.0
var _input_locks: Dictionary[StringName, bool] = {}
var _protections: Dictionary[StringName, bool] = {}
var _stun_stars: Node2D = null
## Falling into an abyss and the last safe spot of this player (A4, D-086, D-088).
var fall: PlayerFall = null
## Side-view gang segments (M5): while active it moves this player (gravity, jump, ladders) instead
## of the top-down movement; null or inactive = top-down as always.
var side_motion: PlayerSideMotion = null
## Session id of this player (0..3, GameMode); set by the WorldController before add_child.
var player_id := 0
## Sits at this machine: own camera, interaction prompt, screen shake (MP1). Set before add_child.
var is_local := true
## Look of this player (MP2): {character: StringName, color: Color} of a remote player's save;
## empty = the loaded save's character and clothing colour, following the wardrobe live.
var appearance: Dictionary = {}
## Where this player's commands come from (MP1): keyboard and mouse by default, RemoteInput for
## players fed from outside (network later, bots and tests now). Never null. On a touch screen the
## local keyboard/mouse input becomes a TouchInput (CP2, on-screen controls; TouchInput.adapt).
var input: PlayerInput = TouchInput.adapt(LocalKeyboardMouseInput.new()):
	set(value):
		input = TouchInput.adapt(value) if value != null else RemoteInput.new()
		if weapon_controller != null:
			weapon_controller.input = input

@onready var health: HealthComponent = $HealthComponent
@onready var shield: ShieldComponent = $ShieldComponent
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var weapon_controller: WeaponController = $WeaponController
@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _weapon_pivot: Node2D = $WeaponPivot
@onready var _weapon_sprite: Sprite2D = $WeaponPivot/WeaponSprite
@onready var _interaction_area: Area2D = $InteractionArea
@onready var _prompt_label: Label = $PromptLabel
@onready var _camera: CameraRig = $Camera2D


func _ready() -> void:
	add_to_group(&"player")
	_sprite.offset = SpriteStrip.pivot_offset(SPRITE_FRAME, SPRITE_ORIGIN)
	_sprite.play(&"idle")
	SpriteFx.apply(_sprite)
	# Character and clothing colour of the active save slot (MM1); the wardrobe updates it live.
	_apply_appearance()
	SaveManager.profile_changed.connect(_apply_appearance)
	_build_stun_stars()
	DropShadow.attach(self, SHADOW_RADIUS, FEET_OFFSET.y)
	_camera.add_child(AmbientParticles.new())
	if not is_local:
		# Only the local player's camera shows the world (its ambient particles hang below it).
		_camera.enabled = false
		_camera.visible = false
	weapon_controller.input = input
	hurtbox.hit_received.connect(_on_hit_received)
	health.died.connect(_on_died)
	weapon_controller.weapon_changed.connect(_on_weapon_changed.unbind(2))
	weapon_controller.active_slot_changed.connect(_on_weapon_changed.unbind(1))
	weapon_controller.swing_started.connect(_on_swing_started)
	weapon_controller.slam_swing_started.connect(_on_slam_swing_started)
	weapon_controller.weapon_kick.connect(func(strength: float) -> void: _weapon_kick = maxf(_weapon_kick, strength))
	_prompt_label.visible = false
	UiKit.apply_prompt_style(_prompt_label)
	_on_weapon_changed()
	fall = PlayerFall.new()
	fall.name = "Fall"
	add_child(fall)
	fall.setup(self)


func _physics_process(delta: float) -> void:
	input.poll(self)
	_tick_timers(delta)
	var side_view := is_side_view()
	if not side_view:
		fall.update(delta)

	_aim = get_aim_direction()
	weapon_controller.aim_direction = _aim

	if is_stunned() or is_input_locked():
		if side_view:
			side_motion.physics_step(delta, false)
		else:
			velocity = Vector2.ZERO
			move_and_slide()
		_prompt_label.visible = false
		_update_visuals(Vector2.ZERO)
		return

	var move_input := input.move
	if side_view:
		move_input = side_motion.physics_step(delta, true)
	else:
		if input.is_just_pressed(PlayerInput.DASH) and can_dash():
			_start_dash(move_input, _aim)
		velocity = _dash_direction * dash_speed if is_dashing() else move_input * move_speed
		move_and_slide()

	if input.is_just_pressed(PlayerInput.SWITCH_WEAPON):
		weapon_controller.switch_weapon()
	# No attacks while dashing (D-016) or while carrying the soul lantern (A9).
	if not is_dashing() and input.is_pressed(PlayerInput.ATTACK) and LanternCarry.can_attack(self):
		weapon_controller.request_attack()

	_update_interaction()
	_update_visuals(move_input)


## Figure and colours (D-152): the look of a remote player (PlayerLook dictionary, or the MM1 pair
## character + color) or, without one, this player's profile.
func _apply_appearance() -> void:
	if appearance.is_empty():
		CharacterCatalog.apply_active(_sprite)
		return
	PlayerLook.apply(_sprite, PlayerLook.from_appearance(appearance))


func get_aim_direction() -> Vector2:
	return input.get_aim_direction(weapon_controller.global_position, _aim)


func is_alive() -> bool:
	return not health.is_dead()


## Group game (MP3, D-084): at 0 HP a player is down instead of gone while a teammate stands; the
## body lies there (death animation) until revive(). In single player 0 HP ends the run as before.
func is_downed() -> bool:
	return health.is_dead()


## Gets a downed player up with hp HP (D-084: 2 HP), brief I-frames. No effect on a living player.
func revive(hp: float) -> void:
	if not health.is_dead():
		return
	var maximum := health.get_max_health()
	health.reset(maximum)
	health.take_damage(maximum - clampf(hp, DamageProcessor.DAMAGE_STEP, maximum))
	set_physics_process(true)
	weapon_controller.set_physics_process(true)
	_weapon_pivot.visible = true
	_sprite.play(&"idle")
	grant_invulnerability(REVIVE_INVULNERABILITY)
	revived.emit()


func is_dashing() -> bool:
	return _dash_time_left > 0.0


func can_dash() -> bool:
	return not is_dashing() and _dash_cooldown_left <= 0.0


## Dash in a fixed direction (side-view segments, M5); false while dashing or cooling down.
func try_dash(direction: Vector2) -> bool:
	if not can_dash() or direction == Vector2.ZERO:
		return false
	_start_dash(direction.normalized(), direction.normalized())
	return true


## A side-view segment moves this player right now (M5).
func is_side_view() -> bool:
	return side_motion != null and side_motion.is_active()


func get_dash_cooldown_left() -> float:
	return _dash_cooldown_left


func get_feet_position() -> Vector2:
	return global_position + FEET_OFFSET


func is_stunned() -> bool:
	return _stun_left > 0.0


## Per-player input lock with named reasons (e.g. the boss intro), no global pause (D-088): the
## player stands still, cannot attack, dash or interact, but can still aim.
func set_input_locked(reason: StringName, locked: bool) -> void:
	if locked:
		_input_locks[reason] = true
		weapon_controller.cancel_attack()
		_weapon_swing_left = 0.0
	else:
		_input_locks.erase(reason)


func is_input_locked() -> bool:
	return not _input_locks.is_empty()


## Protected for a named reason (MP1, D-085/D-123: a menu open in a group game): no input, no
## damage, and enemies should ignore the player (is_protected(), hook for EnemyTargeting).
func set_protected(reason: StringName, protected: bool) -> void:
	if protected:
		_protections[reason] = true
	else:
		_protections.erase(reason)
	set_input_locked(reason, protected)
	hurtbox.set_invulnerable(reason, protected)


func is_protected() -> bool:
	return not _protections.is_empty()


## Falling into an abyss right now (input locked, invisible body, A4).
func is_falling() -> bool:
	return fall != null and fall.is_falling()


## Feet position the next fall returns to (per player, D-088).
func get_last_safe_position() -> Vector2:
	return fall.get_safe_feet_position() if fall != null else get_feet_position()


## Hit I-frames without a hit (landing after a fall): blinking, no damage for duration seconds.
func grant_invulnerability(duration: float) -> void:
	if duration <= 0.0 or health.is_dead():
		return
	_hit_invulnerability_left = maxf(_hit_invulnerability_left, duration)
	hurtbox.set_invulnerable(INVULNERABLE_HIT, true)


## Shows or hides body, held weapon and shadow (the fall animation draws its own sprite).
func set_body_visible(body_visible: bool) -> void:
	_sprite.visible = body_visible
	_weapon_pivot.visible = body_visible and not health.is_dead()
	var shadow := get_node_or_null("DropShadow") as CanvasItem
	if shadow != null:
		shadow.visible = body_visible


## No movement, attacks, dash or interaction while stunned (D-066).
func stun(duration: float) -> void:
	if health.is_dead() or duration <= 0.0:
		return
	_stun_left = maxf(_stun_left, duration)
	weapon_controller.cancel_attack()
	_weapon_swing_left = 0.0
	_stun_stars.visible = true
	_camera.stun_sway(duration)
	stunned.emit(duration)
	Sfx.play_at(self, &"stun", global_position)
	DamageNumber.spawn_text(get_parent(), global_position + Vector2(0, -56), "Betäubt!", STATUS_TEXT_COLOR)


func blind(duration: float) -> void:
	if health.is_dead() or duration <= 0.0:
		return
	blinded.emit(duration)
	Sfx.play_at(self, &"blind", global_position)
	DamageNumber.spawn_text(get_parent(), global_position + Vector2(0, -56), "Geblendet!", Color(0.75, 0.6, 1.0))


## Dash goes in movement direction, or in aim direction without movement input.
func _start_dash(move_input: Vector2, aim: Vector2) -> void:
	_dash_direction = move_input.normalized() if move_input != Vector2.ZERO else aim
	_dash_time_left = dash_duration
	_dash_cooldown_left = dash_cooldown
	weapon_controller.cancel_attack()
	_weapon_swing_left = 0.0
	hurtbox.set_invulnerable(INVULNERABLE_DASH, true)
	Sfx.play_at(self, &"dash", global_position)
	var dust_scale := Vector2.ONE * SpriteStrip.PIXEL_SCALE
	SpriteStrip.spawn_effect(get_parent(), get_feet_position(), DASH_DUST_TEXTURE, Vector2i(32, 32), 12.0, Vector2(16, 30), dust_scale)


func _tick_timers(delta: float) -> void:
	_dash_cooldown_left = maxf(0.0, _dash_cooldown_left - delta)
	if _dash_time_left > 0.0:
		_dash_time_left -= delta
		if _dash_time_left <= 0.0:
			hurtbox.set_invulnerable(INVULNERABLE_DASH, false)
	if _hit_invulnerability_left > 0.0:
		_hit_invulnerability_left -= delta
		if _hit_invulnerability_left <= 0.0:
			hurtbox.set_invulnerable(INVULNERABLE_HIT, false)
	_weapon_swing_left = maxf(0.0, _weapon_swing_left - delta)
	_weapon_kick = move_toward(_weapon_kick, 0.0, WEAPON_KICK_RECOVERY * delta)
	if _stun_left > 0.0:
		_stun_left -= delta
		_stun_stars.rotation += delta * 6.0
		if _stun_left <= 0.0:
			_stun_stars.visible = false


func _update_visuals(move_input: Vector2) -> void:
	var facing_left := _aim.x < 0.0
	_sprite.flip_h = facing_left
	if is_side_view():
		_play(side_motion.get_animation(move_input))
	elif is_dashing():
		_play(&"dash")
	elif move_input != Vector2.ZERO:
		_play(&"walk")
	else:
		_play(&"idle")
	_sprite.modulate.a = INVULNERABLE_ALPHA if _hit_invulnerability_left > 0.0 else 1.0

	var hand := HAND_OFFSET * SpriteStrip.PIXEL_SCALE
	_weapon_pivot.position = Vector2(-hand.x if facing_left else hand.x, hand.y)
	_weapon_pivot.position -= _aim * _weapon_kick
	var swing := 0.0
	if _weapon_swing_left > 0.0:
		if _weapon_swing_one_sided:
			# Raised behind, accelerating down onto the aim direction, then resting there.
			var progress := clampf(1.0 - (_weapon_swing_left - SLAM_HOLD_TIME) / maxf(0.01, _weapon_swing_time), 0.0, 1.0)
			swing = lerpf(-_weapon_swing_arc * 0.5, 0.0, ease(progress, 2.0))
		else:
			var progress := 1.0 - _weapon_swing_left / maxf(0.01, _weapon_swing_time)
			swing = lerpf(-_weapon_swing_arc * 0.5, _weapon_swing_arc * 0.5, progress)
		if facing_left:
			swing = -swing
	_weapon_pivot.rotation = _aim.angle() + swing
	_weapon_sprite.flip_v = facing_left
	# Draw the weapon behind the body while aiming up. Child order instead of z_index, so the weapon
	# y-sorts with the player and never pokes through houses or lamps the player stands behind.
	var weapon_behind := _aim.y < -0.3
	if weapon_behind != (_weapon_pivot.get_index() < _sprite.get_index()):
		move_child(_weapon_pivot, _sprite.get_index() if weapon_behind else _sprite.get_index() + 1)


func _play(animation: StringName) -> void:
	if _sprite.animation != animation:
		_sprite.play(animation)


func _update_interaction() -> void:
	var closest: Interactable = null
	var closest_distance := INF
	for area in _interaction_area.get_overlapping_areas():
		var interactable := area as Interactable
		if interactable == null or not interactable.is_available():
			continue
		var distance := global_position.distance_squared_to(interactable.global_position)
		if distance < closest_distance:
			closest = interactable
			closest_distance = distance
	_focused_interactable = closest
	# Only the player at this machine sees its prompt (MP1).
	_prompt_label.visible = closest != null and is_local
	if closest != null:
		var prompt_text := "E %s" % closest.prompt
		if _prompt_label.text != prompt_text:
			_prompt_label.text = prompt_text
			# The panel hugs the text, centered above the head.
			_prompt_label.reset_size()
			_prompt_label.position.x = -_prompt_label.size.x * 0.5
		if input.is_just_pressed(PlayerInput.INTERACT):
			closest.interact(self)


func _build_stun_stars() -> void:
	_stun_stars = Node2D.new()
	_stun_stars.position = Vector2(0, STUN_STAR_HEIGHT)
	_stun_stars.z_index = 40
	_stun_stars.visible = false
	add_child(_stun_stars)
	for i in STUN_STAR_COUNT:
		var star := PlaceholderShape.new()
		star.radius = 3.5
		star.color = Color(1.0, 0.92, 0.3)
		star.position = Vector2.from_angle(TAU * i / STUN_STAR_COUNT) * Vector2(STUN_STAR_RADIUS, STUN_STAR_RADIUS * 0.45)
		_stun_stars.add_child(star)


func _on_weapon_changed() -> void:
	var weapon := weapon_controller.get_active_weapon()
	_weapon_sprite.visible = weapon != null and weapon.sprite != null
	if weapon == null or weapon.sprite == null:
		return
	_weapon_sprite.texture = weapon.sprite
	_weapon_sprite.offset = SpriteStrip.pivot_offset(Vector2i(weapon.sprite.get_size()), weapon.sprite_pivot)
	# Placeholder recolouring/scaling until dedicated weapon art exists.
	_weapon_sprite.modulate = weapon.tint
	_weapon_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE * weapon.sprite_scale


func _on_swing_started(arc: float, duration: float) -> void:
	_weapon_swing_one_sided = false
	_weapon_swing_arc = arc
	_weapon_swing_time = duration
	_weapon_swing_left = duration


func _on_slam_swing_started(arc: float, wind_up: float) -> void:
	_weapon_swing_one_sided = true
	_weapon_swing_arc = arc
	_weapon_swing_time = wind_up
	_weapon_swing_left = wind_up + SLAM_HOLD_TIME


func _on_hit_received(result: DamageResult, damage: DamageData) -> void:
	# Set synchronously, so a second hit in the same frame is already blocked (serial handling, D-017).
	if result.is_effective() and not health.is_dead():
		_hit_invulnerability_left = hit_invulnerability_time
		hurtbox.set_invulnerable(INVULNERABLE_HIT, true)
		if is_local:
			CameraShake.shake(self, 7.0)
		HitStop.trigger(self, 0.08)
		Sfx.play_at(self, &"hit_player", global_position)
		# Status effects only come with effective hits (D-017).
		stun(damage.stun_duration)
		blind(damage.blind_duration)
		SlowStatus.apply_from_damage(self, result, damage)
	SpriteFx.flash(_sprite, HIT_FLASH_COLOR, HIT_FLASH_DURATION)


func _on_died() -> void:
	set_physics_process(false)
	velocity = Vector2.ZERO
	weapon_controller.cancel_attack()
	weapon_controller.set_physics_process(false)
	_weapon_pivot.visible = false
	_prompt_label.visible = false
	_stun_stars.visible = false
	_sprite.modulate.a = 1.0
	_sprite.play(&"death")
	Sfx.play_at(self, &"player_death", global_position)
	if is_local:
		CameraShake.shake(self, 10.0)
	# Dramatic slow motion before the run end screen.
	HitStop.trigger(self, 0.9, 0.3)
	died.emit()

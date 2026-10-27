class_name WeaponController
extends Node2D
## Two weapon slots, one active weapon, attack timing and triggering (D-022).
## Effective values come from StatCalculator plus run-wide upgrades; attacks and the UI weapon
## comparison read the same getters (D-034). Final damage is resolved by DamageProcessor.
## Left mouse: regular attacks (sword combo finisher every 3rd swing). Right mouse: weapon special
## with a per-slot cooldown. Every swing, slam, projectile and special is its own attack instance
## with its own hit ID (D-020, D-033).

signal weapon_changed(slot: int, weapon: WeaponData)
signal active_slot_changed(slot: int)
signal attack_performed(weapon: WeaponData)
## Right mouse ability was used.
signal special_performed(weapon: WeaponData)
## The special of slot finished its cooldown.
signal special_ready(slot: int)
## A melee swing started: arc in radians (TAU = spin), duration in seconds. For the held-weapon visual.
signal swing_started(arc: float, duration: float)
## A one-sided slam swing (hammer): the held weapon comes down onto the aim direction after
## wind_up seconds and stays there. For the held-weapon visual.
signal slam_swing_started(arc: float, wind_up: float)
## Recoil impulse for the held weapon sprite in pixels (pushed back against the aim direction).
signal weapon_kick(strength: float)
## Every combo_length-th swing of a combo weapon.
signal combo_finisher(weapon: WeaponData)
# Presentation hooks: the logic below only decides, WeaponFx (child node) shows and plays it
# (D-088: effects separate from logic, so remote players can replay the same signals).
## Projectiles left the muzzle or a spell was cast (strength 1 = normal shot).
signal muzzle_flashed(weapon: WeaponData, origin: Vector2, direction: Vector2, strength: float)
## Sword "Wirbelschlag" started: hit radius around the controller and how long it can hit.
signal spin_started(weapon: WeaponData, radius: float, duration: float)
## A slam, quake wave or nova hit was resolved at center with its real hit radius.
## kind: &"slam" (hammer primary), &"quake" (hammer special), &"nova" (staff special).
signal area_resolved(kind: StringName, center: Vector2, radius: float, color: Color)
## A running swing, spin or wind-up was aborted (dash, weapon switch, death).
signal attack_cancelled

const MAX_WEAPON_SLOTS := 2
## PLATZHALTER: how long one sword swing can hit. Not specified in the GDD.
const SWING_ACTIVE_TIME := 0.12
const SWING_ARC_SEGMENTS := 12
const CIRCLE_SEGMENTS := 24
const SWING_TEXTURE: Texture2D = preload("res://art/effects/sword_swing_4f.png")
## The swing art shows a ~100° crescent with 25 px radius, pivot (12, 24) in a 48 px frame.
const SWING_ART_RADIUS := 25.0
const SWING_ART_ANGLE := 100.0
## Angle between projectiles of one "Doppelschuss" attack.
const MULTI_SHOT_SPREAD_DEGREES := 8.0
## Projectiles spawn this far in front of the hand.
const MUZZLE_DISTANCE := 18.0
const PROJECTILE_TRAIL_LENGTH := 8

# --- TESTWERTE: combo ---
## A combo continues if the next swing starts within this time after the attack cooldown ended.
const COMBO_GRACE_TIME := 0.45
## Extra recovery after a finisher, gives it weight.
const FINISHER_RECOVERY := 0.15
const FINISHER_HIT_STOP := 0.06
const FINISHER_HIT_STOP_SCALE := 0.1

# --- TESTWERTE: specials ---
## Regular attacks are blocked this long after a special.
const SPECIAL_RECOVERY := 0.3
const SPIN_ACTIVE_TIME := 0.28
const SPIN_RANGE_MULTIPLIER := 1.3
const BOW_FAN_COUNT := 5
const BOW_FAN_SPREAD_DEGREES := 11.0
const BOW_FAN_EXTRA_PIERCE := 2
const NOVA_RADIUS_MULTIPLIER := 2.4
const KNIFE_COUNT := 3
const KNIFE_SPREAD_DEGREES := 14.0
const KNIFE_SPEED := 650.0
const KNIFE_RANGE := 320.0
const KNIFE_PIERCE := 1
const QUAKE_SLAMS := 3
const QUAKE_INTERVAL := 0.12
const QUAKE_RADIUS_MULTIPLIER := 0.85
## A dagger swing within this time after a dash is an ambush (every hit backstabs).
const AMBUSH_WINDOW := 0.5

@export var starting_weapon: WeaponData
## Hurtbox layer(s) this controller's attacks can hit (default: enemy_hurtbox).
@export_flags_2d_physics var target_hurtbox_mask := 16
## Reads the special action from input itself (gated by the owning Player's dash/stun state).
@export var handle_special_input := true

## Normalized aim direction, updated by the owner every physics frame.
var aim_direction := Vector2.RIGHT
## Run-wide upgrades; null outside the dungeon (village) means base values.
var upgrades: UpgradeManager = null
## Commands of the owning player (MP1), set by the Player; null = no special input (standalone
## controllers in tests). Never reads Input directly.
var input: PlayerInput = null

var _slots: Array[WeaponData] = [null, null]
var _active_slot := 0
var _cooldown_left := 0.0
var _swing_time_left := 0.0
var _special_cooldowns: Array[float] = [0.0, 0.0]
var _combo_count := 0
var _combo_window_left := 0.0
var _swing_is_finisher := false
var _finisher_landed := false
var _ambush_left := 0.0
## Queued area hits (hammer slams, quake waves, nova): {time_left, direction, distance, radius, damage, knockback, kind, color}.
var _pending_areas: Array[Dictionary] = []
var _spin_tween: Tween = null

@onready var _swing_hitbox: MeleeHitbox = $SwingHitbox
@onready var _swing_shape: CollisionPolygon2D = $SwingHitbox/CollisionPolygon2D
@onready var _swing_effect: AnimatedSprite2D = $SwingHitbox/SwingEffect


func _ready() -> void:
	_swing_hitbox.collision_mask = target_hurtbox_mask
	_swing_hitbox.hit_landed.connect(_on_swing_hit_landed)
	_swing_hitbox.backstab_landed.connect(_on_backstab_landed)
	_swing_effect.sprite_frames = SpriteStrip.make_frames(SWING_TEXTURE, Vector2i(48, 48), 24.0, false)
	_swing_effect.offset = SpriteStrip.pivot_offset(Vector2i(48, 48), Vector2(12, 24))
	_swing_effect.visible = false
	_swing_effect.animation_finished.connect(_swing_effect.hide)
	if starting_weapon != null:
		equip_weapon(starting_weapon, 0)


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	_combo_window_left = maxf(0.0, _combo_window_left - delta)
	for slot in MAX_WEAPON_SLOTS:
		if _special_cooldowns[slot] > 0.0:
			_special_cooldowns[slot] = maxf(0.0, _special_cooldowns[slot] - delta)
			if _special_cooldowns[slot] <= 0.0:
				special_ready.emit(slot)
	if _swing_time_left > 0.0:
		_swing_time_left -= delta
		if _swing_time_left <= 0.0:
			_swing_hitbox.end_attack()
	_process_pending_areas(delta)

	var player := get_parent() as Player
	if player != null and player.is_dashing():
		_ambush_left = AMBUSH_WINDOW
	else:
		_ambush_left = maxf(0.0, _ambush_left - delta)
	if handle_special_input and input != null and _owner_can_attack() and input.is_pressed(PlayerInput.SPECIAL):
		request_special()


func get_active_weapon() -> WeaponData:
	return _slots[_active_slot]


func get_active_slot() -> int:
	return _active_slot


func get_weapon(slot: int) -> WeaponData:
	if slot < 0 or slot >= MAX_WEAPON_SLOTS:
		return null
	return _slots[slot]


func get_owned_weapons() -> Array[WeaponData]:
	var owned: Array[WeaponData] = []
	for weapon in _slots:
		if weapon != null:
			owned.append(weapon)
	return owned


func has_weapon_type(weapon_type: WeaponData.WeaponType) -> bool:
	for weapon in _slots:
		if weapon != null and weapon.weapon_type == weapon_type:
			return true
	return false


## Returns the first empty slot or -1 if both are taken (then a slot must be replaced).
func find_free_slot() -> int:
	for slot in MAX_WEAPON_SLOTS:
		if _slots[slot] == null:
			return slot
	return -1


## Whether weapon may go into slot: no duplicate types across slots (D-022).
func can_equip(weapon: WeaponData, slot: int) -> bool:
	if weapon == null or slot < 0 or slot >= MAX_WEAPON_SLOTS:
		return false
	for other_slot in MAX_WEAPON_SLOTS:
		var other := _slots[other_slot]
		if other_slot != slot and other != null and other.weapon_type == weapon.weapon_type:
			return false
	return true


## Puts weapon into slot, replacing what was there. A new weapon starts with its special ready.
func equip_weapon(weapon: WeaponData, slot: int) -> bool:
	if not can_equip(weapon, slot):
		return false
	if slot == _active_slot:
		cancel_attack()
		reset_combo()
	_slots[slot] = weapon
	_special_cooldowns[slot] = 0.0
	weapon_changed.emit(slot, weapon)
	if _is_local_owner():
		EventBus.weapon_changed.emit(slot, weapon)
	return true


func switch_weapon() -> bool:
	return set_active_slot((_active_slot + 1) % MAX_WEAPON_SLOTS)


## Makes slot the active one (no effect if it already is or holds no weapon). Group games set the
## active slot of a remote player's copy with this (state from its owner's machine, never a replayed
## toggle), so every copy holds the weapon its owner holds.
func set_active_slot(slot: int) -> bool:
	if slot < 0 or slot >= MAX_WEAPON_SLOTS or slot == _active_slot or _slots[slot] == null:
		return false
	cancel_attack()
	reset_combo()
	_active_slot = slot
	active_slot_changed.emit(_active_slot)
	if _is_local_owner():
		EventBus.weapon_changed.emit(_active_slot, _slots[_active_slot])
	return true


## Global weapon events (EventBus) belong to the player at this machine; copies of remote players
## (group game) change their weapons silently. Standalone controllers (tests) count as local.
func _is_local_owner() -> bool:
	var player := get_parent() as Player
	return player == null or player.is_local


## A swing is active or a slam/nova is still winding up.
func is_attacking() -> bool:
	return _swing_time_left > 0.0 or not _pending_areas.is_empty()


func request_attack() -> bool:
	var weapon := get_active_weapon()
	if weapon == null or _cooldown_left > 0.0 or is_attacking() or not _owner_is_armed():
		return false
	_cooldown_left = StatCalculator.attack_cooldown(get_effective_attack_rate(weapon))
	match weapon.weapon_type:
		WeaponData.WeaponType.SWORD, WeaponData.WeaponType.DAGGER:
			_attack_swing(weapon)
		WeaponData.WeaponType.HAMMER:
			_attack_slam(weapon)
		_:
			_attack_projectiles(weapon)
	attack_performed.emit(weapon)
	return true


## Right mouse ability of the active weapon. Blocked while a swing/slam runs or on cooldown.
func request_special() -> bool:
	var weapon := get_active_weapon()
	if weapon == null or not is_special_ready(_active_slot) or is_attacking() or not _owner_is_armed():
		return false
	_special_cooldowns[_active_slot] = weapon.special_cooldown
	_cooldown_left = maxf(_cooldown_left, SPECIAL_RECOVERY)
	reset_combo()
	match weapon.weapon_type:
		WeaponData.WeaponType.SWORD:
			_special_spin(weapon)
		WeaponData.WeaponType.BOW:
			_special_arrow_fan(weapon)
		WeaponData.WeaponType.STAFF:
			_special_nova(weapon)
		WeaponData.WeaponType.DAGGER:
			_special_knives(weapon)
		WeaponData.WeaponType.HAMMER:
			_special_quake(weapon)
	special_performed.emit(weapon)
	return true


## Aborts a running swing or wind-up (e.g. on dash, D-016). Projectiles in flight are unaffected.
func cancel_attack() -> void:
	_swing_time_left = 0.0
	_swing_hitbox.end_attack()
	_swing_effect.visible = false
	_pending_areas.clear()
	if _spin_tween != null:
		_spin_tween.kill()
		_spin_tween = null
	attack_cancelled.emit()


# --- Combo and special state (read by HUD and tests) ---

## Swings in the current combo chain (0 after a pause or a finisher).
func get_combo_count() -> int:
	return _combo_count if _combo_window_left > 0.0 else 0


func is_next_swing_finisher() -> bool:
	var weapon := get_active_weapon()
	return weapon != null and weapon.combo_length > 0 and get_combo_count() + 1 >= weapon.combo_length


func reset_combo() -> void:
	_combo_count = 0
	_combo_window_left = 0.0


func get_special_cooldown_left(slot: int) -> float:
	if slot < 0 or slot >= MAX_WEAPON_SLOTS:
		return 0.0
	return _special_cooldowns[slot]


func is_special_ready(slot: int) -> bool:
	return get_special_cooldown_left(slot) <= 0.0


## 0 = just used, 1 = ready. For cooldown bars.
func get_special_charge(slot: int) -> float:
	var weapon := get_weapon(slot)
	if weapon == null or weapon.special_cooldown <= 0.0:
		return 1.0
	return clampf(1.0 - _special_cooldowns[slot] / weapon.special_cooldown, 0.0, 1.0)


func is_ambush_active() -> bool:
	return _ambush_left > 0.0


# --- Effective values (shared by attacks and UI) ---

## context_multiplier: situational multipliers such as finisher or special (D-019).
## Talents (KE6) add their percent next to the forge bonus and their situational factor
## (Ausweichkunst) to the context multiplier; neutral for a player without talents.
func get_effective_damage(weapon: WeaponData, context_multiplier := 1.0) -> float:
	var owner_player := get_parent()
	return StatCalculator.compute_raw_damage(
		weapon.base_damage,
		_modifier(UpgradeData.Effect.DAMAGE_FLAT, weapon),
		_modifier(UpgradeData.Effect.DAMAGE_PERCENT, weapon) + get_meta_damage_bonus(weapon)
			+ TalentEffects.damage_bonus(owner_player, weapon.tags),
		context_multiplier * TalentEffects.attack_multiplier(owner_player))


## The special with the forge's factor from level III on (KE4, MetaProgression.player_special_factor).
func get_effective_special_damage(weapon: WeaponData) -> float:
	return get_effective_damage(weapon, weapon.special_damage_multiplier * MetaProgression.player_special_factor(get_parent(), weapon))


func get_effective_attack_rate(weapon: WeaponData) -> float:
	return StatCalculator.compute_attack_rate(weapon.attack_rate, 0.0,
		_modifier(UpgradeData.Effect.ATTACK_RATE_PERCENT, weapon) + TalentEffects.attack_rate_bonus(get_parent(), weapon.tags))


func get_effective_projectile_speed(weapon: WeaponData) -> float:
	return weapon.projectile_speed * (1.0 + _modifier(UpgradeData.Effect.PROJECTILE_SPEED_PERCENT, weapon))


func get_effective_swing_angle(weapon: WeaponData) -> float:
	return weapon.swing_angle_degrees * (1.0 + _modifier(UpgradeData.Effect.SWING_ANGLE_PERCENT, weapon))


func get_effective_aoe_radius(weapon: WeaponData) -> float:
	return StatCalculator.compute_radius(weapon.aoe_radius, _modifier(UpgradeData.Effect.AOE_RADIUS_PERCENT, weapon))


func get_pierce_count(weapon: WeaponData) -> int:
	return roundi(_modifier(UpgradeData.Effect.PIERCE, weapon))


func get_bounce_count(weapon: WeaponData) -> int:
	return roundi(_modifier(UpgradeData.Effect.WALL_BOUNCE, weapon))


func get_projectile_count(weapon: WeaponData) -> int:
	return 1 + roundi(_modifier(UpgradeData.Effect.EXTRA_PROJECTILE, weapon))


## Radius of the staff's "Arkane Nova"; grows with "Größere Explosion" like the orb.
func get_nova_radius(weapon: WeaponData) -> float:
	return get_effective_aoe_radius(weapon) * NOVA_RADIUS_MULTIPLIER


## Forge bonus of weapon ("Waffe schmieden", KE4): from the forge snapshot stored at this player
## (MetaProgression.apply_forge_snapshot - solo the own save, in a quick game the host puts each
## player's lobby snapshot on that player's copy, guild runs none). So the host never adds its own
## save to the other players' attacks (D-081). weapon null = the active weapon (spells).
func get_meta_damage_bonus(weapon: WeaponData = null) -> float:
	if weapon == null:
		weapon = get_active_weapon()
	return MetaProgression.player_weapon_damage_bonus(get_parent(), weapon)


func _modifier(effect: UpgradeData.Effect, weapon: WeaponData) -> float:
	if upgrades == null:
		return 0.0
	return upgrades.get_modifier(effect, weapon.tags)


func _owner_can_attack() -> bool:
	var player := get_parent() as Player
	if player == null:
		return true
	return player.is_alive() and player.is_armed() and not player.is_dashing() and not player.is_stunned() \
		and LanternCarry.can_attack(player)


## An unarmed owner (the village, #80c94d8c) never attacks, whoever asks. Standalone controllers
## (tests) count as armed.
func _owner_is_armed() -> bool:
	var player := get_parent() as Player
	return player == null or player.is_armed()


# --- Regular attacks ---

func _create_damage(weapon: WeaponData, context_multiplier := 1.0, extra_tag: StringName = &"") -> DamageData:
	var damage := DamageData.new()
	if extra_tag == &"special":
		context_multiplier *= MetaProgression.player_special_factor(get_parent(), weapon)
	damage.amount = get_effective_damage(weapon, context_multiplier)
	damage.source = get_parent()
	damage.tags.assign(weapon.tags)
	if extra_tag != &"":
		damage.tags.append(extra_tag)
	return damage


func _attack_swing(weapon: WeaponData) -> void:
	var finisher := _advance_combo(weapon)
	var angle := get_effective_swing_angle(weapon)
	var radius := weapon.attack_range
	var knockback := weapon.knockback_strength
	var damage: DamageData
	if finisher:
		angle *= weapon.combo_angle_multiplier
		radius *= weapon.combo_range_multiplier
		knockback *= weapon.combo_knockback_multiplier
		damage = _create_damage(weapon, weapon.combo_damage_multiplier, &"finisher")
		_cooldown_left += FINISHER_RECOVERY
	else:
		damage = _create_damage(weapon)
	if weapon.combo_length > 0:
		_combo_window_left = _cooldown_left + COMBO_GRACE_TIME
	_swing_is_finisher = finisher
	_finisher_landed = false
	_start_swing(weapon, radius, angle, damage, knockback, SWING_ACTIVE_TIME)
	if finisher:
		_swing_effect.modulate = Color(1.4, 1.2, 0.8)
		Sfx.play_at(self, &"slam", global_position, -6.0)
		CameraShake.shake(self, 2.5)
		weapon_kick.emit(7.0)
		combo_finisher.emit(weapon)
	else:
		weapon_kick.emit(2.0 if weapon.weapon_type == WeaponData.WeaponType.DAGGER else 3.0)
	Sfx.play_at(self, &"sword_swing", global_position, -3.0 if weapon.weapon_type == WeaponData.WeaponType.DAGGER else 0.0)


## Counts a swing; returns true if this swing is the finisher (count resets afterwards).
func _advance_combo(weapon: WeaponData) -> bool:
	if weapon.combo_length <= 0:
		return false
	if _combo_window_left <= 0.0:
		_combo_count = 0
	_combo_count += 1
	if _combo_count >= weapon.combo_length:
		_combo_count = 0
		return true
	return false


func _start_swing(weapon: WeaponData, radius: float, angle_degrees: float, damage: DamageData, knockback: float, duration: float) -> void:
	var full_circle := angle_degrees >= 360.0
	if full_circle:
		_swing_shape.polygon = _build_circle_polygon(radius)
	else:
		_swing_shape.polygon = _build_swing_polygon(radius, deg_to_rad(angle_degrees))
	_swing_hitbox.rotation = aim_direction.angle()
	_swing_hitbox.knockback_strength = knockback
	_swing_hitbox.backstab_multiplier = weapon.backstab_multiplier
	_swing_hitbox.ambush = is_ambush_active()
	_swing_hitbox.begin_attack(damage)
	_swing_time_left = duration
	swing_started.emit(TAU if full_circle else deg_to_rad(angle_degrees), duration)
	if full_circle:
		# The spin has its own art (WeaponFx via spin_started), not the crescent.
		_swing_effect.visible = false
		return

	var radius_scale := radius / SWING_ART_RADIUS
	var arc_scale := angle_degrees / SWING_ART_ANGLE
	_swing_effect.scale = Vector2(radius_scale, radius_scale * arc_scale)
	_swing_effect.flip_v = aim_direction.x < 0.0
	_swing_effect.modulate = weapon.effect_color
	_swing_effect.visible = true
	_swing_effect.frame = 0
	_swing_effect.play(&"default")


## Hammer: wind-up, then one primary area hit in front of the player (one hit ID, D-020).
func _attack_slam(weapon: WeaponData) -> void:
	_queue_area(weapon.windup_time, aim_direction, weapon.attack_range, get_effective_aoe_radius(weapon),
		_create_damage(weapon), weapon.knockback_strength, &"slam", weapon.effect_color)
	# The held hammer comes down onto the aim direction exactly when the slam lands.
	slam_swing_started.emit(deg_to_rad(160.0), weapon.windup_time)
	Sfx.play_at(self, &"sword_swing", global_position, -2.0)


func _attack_projectiles(weapon: WeaponData) -> void:
	_fire_projectiles(weapon)
	var is_bow := weapon.weapon_type == WeaponData.WeaponType.BOW
	Sfx.play_at(self, &"bow_shot" if is_bow else &"staff_cast", global_position)
	weapon_kick.emit(5.0 if is_bow else 4.0)


## Every projectile is its own attack instance with a separate hit history (D-033).
func _fire_projectiles(weapon: WeaponData) -> void:
	var count := get_projectile_count(weapon)
	var spread := deg_to_rad(MULTI_SHOT_SPREAD_DEGREES)
	for i in count:
		var angle_offset := (float(i) - float(count - 1) * 0.5) * spread
		_spawn_projectile(weapon, aim_direction.rotated(angle_offset), _create_damage(weapon),
			get_effective_projectile_speed(weapon), weapon.attack_range, get_pierce_count(weapon), get_bounce_count(weapon))
	muzzle_flashed.emit(weapon, global_position + aim_direction * MUZZLE_DISTANCE, aim_direction, 1.0)


func _spawn_projectile(weapon: WeaponData, direction: Vector2, damage: DamageData, speed: float, distance: float, pierce: int, bounces: int) -> Projectile:
	var projectile := Projectile.create(damage, direction, speed, distance, target_hurtbox_mask)
	projectile.aoe_radius = get_effective_aoe_radius(weapon)
	projectile.pierce_remaining = pierce
	projectile.bounces_remaining = bounces
	projectile.knockback_strength = weapon.knockback_strength
	projectile.collision_radius = weapon.projectile_radius
	projectile.texture = weapon.projectile_texture
	projectile.frame_size = weapon.projectile_frame_size
	projectile.pivot = weapon.projectile_pivot
	projectile.fps = weapon.projectile_fps
	projectile.color = weapon.projectile_color
	projectile.light_radius = 110.0 if weapon.aoe_radius > 0.0 else 55.0
	projectile.trail_length = PROJECTILE_TRAIL_LENGTH
	projectile.trail_width = weapon.projectile_radius * 1.2
	projectile.trail_color = weapon.projectile_color
	projectile.launch(_get_projectile_parent(), global_position + direction * MUZZLE_DISTANCE)
	return projectile


## World node that holds projectiles and one-shot effects (next to the shooter).
func get_effect_parent() -> Node:
	return _get_projectile_parent()


## Projectiles live next to the shooter in the world.
func _get_projectile_parent() -> Node:
	var shooter := get_parent()
	if shooter != null and shooter.get_parent() != null:
		return shooter.get_parent()
	return get_tree().current_scene


# --- Specials ---

## Sword "Wirbelschlag": 360° swing with strong knockback, one hit ID. Grants no I-frames.
func _special_spin(weapon: WeaponData) -> void:
	var radius := weapon.attack_range * SPIN_RANGE_MULTIPLIER
	_swing_is_finisher = true
	_finisher_landed = false
	_start_swing(weapon, radius, 360.0, _create_damage(weapon, weapon.special_damage_multiplier, &"special"),
		weapon.knockback_strength * weapon.special_knockback_multiplier, SPIN_ACTIVE_TIME)
	_spin_tween = create_tween()
	_spin_tween.tween_property(_swing_hitbox, "rotation", _swing_hitbox.rotation + TAU, SPIN_ACTIVE_TIME)
	spin_started.emit(weapon, radius, SPIN_ACTIVE_TIME)
	weapon_kick.emit(6.0)


## Bow "Pfeilfächer": five piercing arrows, each with its own hit history (D-033).
func _special_arrow_fan(weapon: WeaponData) -> void:
	var spread := deg_to_rad(BOW_FAN_SPREAD_DEGREES)
	for i in BOW_FAN_COUNT:
		var angle_offset := (float(i) - float(BOW_FAN_COUNT - 1) * 0.5) * spread
		_spawn_projectile(weapon, aim_direction.rotated(angle_offset), _create_damage(weapon, weapon.special_damage_multiplier, &"special"),
			get_effective_projectile_speed(weapon) * 1.15, weapon.attack_range,
			get_pierce_count(weapon) + BOW_FAN_EXTRA_PIERCE, get_bounce_count(weapon))
	muzzle_flashed.emit(weapon, global_position + aim_direction * MUZZLE_DISTANCE, aim_direction, 2.0)
	Sfx.play_at(self, &"bow_shot", global_position, 3.0)
	CameraShake.shake(self, 3.0)
	weapon_kick.emit(10.0)


## Staff "Arkane Nova": one primary area hit around the player (one hit ID, so at most one
## "Explosiver Treffer" follows, D-031).
func _special_nova(weapon: WeaponData) -> void:
	_queue_area(0.0, Vector2.ZERO, 0.0, get_nova_radius(weapon),
		_create_damage(weapon, weapon.special_damage_multiplier, &"special"),
		weapon.knockback_strength * weapon.special_knockback_multiplier, &"nova", weapon.projectile_color)
	muzzle_flashed.emit(weapon, global_position + aim_direction * MUZZLE_DISTANCE, aim_direction, 1.5)
	Sfx.play_at(self, &"staff_cast", global_position, 3.0)
	weapon_kick.emit(4.0)


## Dagger "Klingenfächer": three thrown knives.
func _special_knives(weapon: WeaponData) -> void:
	var spread := deg_to_rad(KNIFE_SPREAD_DEGREES)
	for i in KNIFE_COUNT:
		var angle_offset := (float(i) - float(KNIFE_COUNT - 1) * 0.5) * spread
		_spawn_projectile(weapon, aim_direction.rotated(angle_offset),
			_create_damage(weapon, weapon.special_damage_multiplier, &"special"), KNIFE_SPEED, KNIFE_RANGE, KNIFE_PIERCE, 0)
	muzzle_flashed.emit(weapon, global_position + aim_direction * MUZZLE_DISTANCE, aim_direction, 1.0)
	Sfx.play_at(self, &"bow_shot", global_position, -2.0, 0.2)
	weapon_kick.emit(5.0)


## Hammer "Erdbeben": three slams marching along the aim direction, each its own attack instance.
func _special_quake(weapon: WeaponData) -> void:
	var radius := get_effective_aoe_radius(weapon) * QUAKE_RADIUS_MULTIPLIER
	var direction := aim_direction
	for i in QUAKE_SLAMS:
		_queue_area(weapon.windup_time + QUAKE_INTERVAL * i, direction, weapon.attack_range + radius * 1.5 * i, radius,
			_create_damage(weapon, weapon.special_damage_multiplier, &"special"),
			weapon.knockback_strength * weapon.special_knockback_multiplier, &"quake", weapon.effect_color)
	slam_swing_started.emit(deg_to_rad(200.0), weapon.windup_time)
	Sfx.play_at(self, &"charge", global_position, -3.0)


# --- Area hits (slam, quake, nova) ---

func _queue_area(delay: float, direction: Vector2, distance: float, radius: float, damage: DamageData, knockback: float, kind: StringName, color: Color) -> void:
	damage.hit_id = DamageData.next_hit_id()
	_pending_areas.append({
		"time_left": delay, "direction": direction, "distance": distance, "radius": radius,
		"damage": damage, "knockback": knockback, "kind": kind, "color": color,
	})


## Runs in _physics_process, so the area queries of AreaDamage are allowed.
func _process_pending_areas(delta: float) -> void:
	if _pending_areas.is_empty():
		return
	var due: Array[Dictionary] = []
	for entry in _pending_areas:
		entry["time_left"] -= delta
		if entry["time_left"] <= 0.0:
			due.append(entry)
	for entry in due:
		_pending_areas.erase(entry)
		_resolve_area(entry)


func _resolve_area(entry: Dictionary) -> void:
	var center := global_position + Vector2(entry["direction"]) * float(entry["distance"])
	center = _clip_to_walls(global_position, center)
	var radius: float = entry["radius"]
	var color: Color = entry["color"]
	var kind: StringName = entry["kind"]
	AreaDamage.apply(self, center, radius, target_hurtbox_mask, entry["damage"], entry["knockback"])
	area_resolved.emit(kind, center, radius, color)
	if kind != &"nova":
		weapon_kick.emit(8.0)


## Slams never land behind walls: the centre stops in front of the first wall.
func _clip_to_walls(from: Vector2, to: Vector2) -> Vector2:
	if from.is_equal_approx(to) or not is_inside_tree():
		return to
	var query := PhysicsRayQueryParameters2D.create(from, to, PhysicsLayers.WORLD)
	query.collide_with_areas = false
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return to
	var hit_position: Vector2 = hit["position"]
	return hit_position - (to - from).normalized() * 8.0


# --- Hit feedback ---

func _on_swing_hit_landed(_hurtbox: Hurtbox, _result: DamageResult) -> void:
	if not _swing_is_finisher or _finisher_landed:
		return
	_finisher_landed = true
	HitStop.trigger(self, FINISHER_HIT_STOP, FINISHER_HIT_STOP_SCALE)
	CameraShake.shake(self, 3.0)


func _on_backstab_landed(hurtbox: Hurtbox) -> void:
	var parent := _get_projectile_parent()
	Burst.spawn(parent, hurtbox.global_position, Color(1.0, 0.25, 0.3), 10, 140.0, 0.3, 3.0)
	DamageNumber.spawn_status(parent, hurtbox.global_position + Vector2(0, -48), &"STATUS_AMBUSH", Color(1.0, 0.4, 0.45))


static func _build_swing_polygon(radius: float, arc: float) -> PackedVector2Array:
	var points := PackedVector2Array([Vector2.ZERO])
	for i in SWING_ARC_SEGMENTS + 1:
		var angle := -arc * 0.5 + arc * float(i) / SWING_ARC_SEGMENTS
		points.append(Vector2.from_angle(angle) * radius)
	return points


static func _build_circle_polygon(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in CIRCLE_SEGMENTS:
		points.append(Vector2.from_angle(TAU * float(i) / CIRCLE_SEGMENTS) * radius)
	return points

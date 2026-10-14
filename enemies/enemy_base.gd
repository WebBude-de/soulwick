class_name Enemy
extends CharacterBody2D
## Shared enemy body and AI, driven by EnemyData:
## MELEE chases and strikes, RANGED keeps distance and shoots; optional radial volleys, special
## attacks (shield charge with stun, leap slam, teleport, self destruct, eruption) and summons.
## Every attack is telegraphed (D-021); the attack animation reaches its strike frame exactly when
## the telegraph ends. Normal enemies have no general I-frames (D-020).
## Bosses and champions have two phases (BossRules): below half health they roar (briefly
## invulnerable), get faster and chain specials, spiral volleys, landing rings and eruptions.
## Abysses (A4, D-086): the pit physics layer blocks enemies like a wall. A strong knockback
## towards a pit lifts that block until the knockback settles; an enemy that then stands over a
## pit falls and dies (a kill, its gold drops at the rim). Champions, golems and bosses never fall
## (ChasmRules.can_enemy_fall).

signal died(enemy: Enemy)
## A minion created by this enemy; the room tracks it like any other enemy.
signal summoned(minion: Enemy)
## Pushed into an abyss (A4); died is emitted right after.
signal fell_into_pit(enemy: Enemy)
## Bosses and champions: phase two started (the roar begins).
signal phase_changed(enemy: Enemy, phase: int)
## Every ability as it happens (volley, spiral, charge, leap, landing_ring, teleport, summon,
## eruption, chain, self_destruct, roar). Used by tools/boss_sim.gd and for effects.
signal ability_used(enemy: Enemy, ability: StringName)
## The boss intro is over (end_intro, safety timeout or death); the enemy fights from now on.
signal intro_ended(enemy: Enemy)
## Internal: the death animation is over or its time limit ran out (see _wait_for_death_animation).
signal death_wait_over

enum State { IDLE, CHASE, TELEGRAPH, ATTACK, CHARGE, LEAP, RECOVER, DEAD, ROAR }
enum Action { NORMAL, VOLLEY, SPECIAL, SUMMON }
enum Elite { NONE, SWIFT, ARMORED, VOLATILE }

const ENEMY_SCENE_PATH := "res://enemies/enemy_base.tscn"
const GOLD_PICKUP_SCENE: PackedScene = preload("res://economy/gold_pickup.tscn")
const HIT_SPARK_TEXTURE: Texture2D = preload("res://art/effects/hit_spark_3f.png")
## Projectile art for types without own projectiles (melee bosses, champion shadows).
const FALLBACK_PROJECTILE_TEXTURE: Texture2D = preload("res://art/projectiles/magic_orb_4f.png")
const SPRITE_FRAME := Vector2i(32, 32)
const DEATH_DISSOLVE_TIME := 0.5
## The death animation may run this much longer than planned before the enemy dissolves anyway ...
const DEATH_ANIMATION_MARGIN := 0.25
## ... and never longer than this (a broken fps value must not keep a corpse around).
const DEATH_ANIMATION_MAX_TIME := 2.0
## Enemy HP bar (docs/design ui_spec): 20 x 4 art pixels, #e0463a on #1c1a2b.
const HEALTH_BAR_FILL := Color("#e0463a")
const HEALTH_BAR_BACKGROUND := Color("#1c1a2b")
const HEALTH_BAR_SIZE := Vector2(20.0, 4.0) * SpriteStrip.PIXEL_SCALE
## Gap between HP bar and badge row, and the elite name size, in art pixels.
const BADGE_GAP := 4.0 * SpriteStrip.PIXEL_SCALE
const ELITE_LABEL_SIZE := 6.0 * SpriteStrip.PIXEL_SCALE
const CHAMPION_LABEL_COLOR := Color("#f2cf4a")
const MINIBOSS_VISUAL_SCALE := 1.5
const TELEGRAPH_COLOR := Color(1, 0.15, 0.1, 0.3)
const SPECIAL_TELEGRAPH_COLOR := Color(1, 0.85, 0.15, 0.35)
const ENRAGE_COLOR := Color(1.0, 0.25, 0.1)
const ELITE_COLORS := {
	Elite.SWIFT: Color(0.35, 0.9, 1.0),
	Elite.ARMORED: Color(0.75, 0.8, 0.95),
	Elite.VOLATILE: Color(1.0, 0.45, 0.1),
}
const ELITE_NAMES := {Elite.SWIFT: "Flink", Elite.ARMORED: "Gepanzert", Elite.VOLATILE: "Explosiv"}
const LEAP_TIME := 0.5
const TELEPORT_MIN_DISTANCE := 200.0
const TELEPORT_MAX_DISTANCE := 330.0
const FUSE_BEEP_INTERVAL := 0.15
const ERUPTION_RANGE := 420.0
const ERUPTION_DELAY := 0.75
const ERUPTION_RADIUS := 52.0
const ERUPTION_SPREAD := Vector2(70.0, 150.0)
## Summons without own summon cadence (champion escorts, high-tier bosses, phase two).
const FALLBACK_SUMMON_EVERY := 4
const FALLBACK_SUMMON_COUNT := 2
const ROAR_INVULNERABILITY := &"roar"
const INTRO_INVULNERABILITY := &"intro"
## Seconds between two target choices (nearest living player, EnemyTargeting). TESTWERT
const TARGET_INTERVAL := 0.5
## Obstacle avoidance: look this far ahead, then keep a found detour for a moment.
const STEER_LOOKAHEAD := 64.0
const DETOUR_TIME := 0.45
const DETOUR_ANGLES: Array[float] = [PI / 4.0, -PI / 4.0, PI / 2.0, -PI / 2.0, PI * 0.75, -PI * 0.75]

@export var data: EnemyData
## How fast knockback velocity decays, in px/s².
@export var knockback_friction := 900.0

## Gold dropped on death, set by the spawner (economy decides the amount).
var gold_drop := 0
var is_miniboss := false
var elite := Elite.NONE
## Global floor rectangle of the room (teleport targets); empty = around the target.
var arena := Rect2()
## 1 until a boss or champion drops below half health, then 2.
var phase := 1

var _state := State.IDLE
var _state_time_left := 0.0
var _action := Action.NORMAL
var _attack_direction := Vector2.RIGHT
var _leap_target := Vector2.ZERO
var _knockback_velocity := Vector2.ZERO
var _health_multiplier := 1.0
var _damage_multiplier := 1.0
var _speed_multiplier := 1.0
var _telegraph_multiplier := 1.0
var _cooldown_factor := 1.0
var _room_index := 1
var _boss_tier := 0
## Fallback minion for high boss tiers / champions without own summons.
var extra_summon_data: EnemyData = null
## Nearest living player, or a decoy the enemy was sent after (soul flame, A7).
var _target: Node2D = null
var _attack_count := 0
var _visual_scale := 1.0
var _sprite_scale := 1.0
var _shadow: DropShadow = null
var _fuse_timer := 0.0
var _base_mask := 0
var _detour := Vector2.ZERO
var _detour_left := 0.0
var _steer_shape := CircleShape2D.new()
var _champion_applied := false
var _enrage_pending := false
var _special_chain_left := 0
var _in_chain := false
var _minions: Array[Enemy] = []
var _badges: EnemyBadges = null
var _elite_label: Label = null
var _in_intro := false
var _intro_time_left := 0.0
var _death_wait_done := false
var _target_rethink_left := 0.0
var _unstick_count := 0
## Pathfinding around walls (A2); see EnemyNavigation.
var _navigation: EnemyNavigation = null
## Knocked back towards an abyss: the pit layer does not block until the knockback settles (A4).
var _pit_unbound := false
## Where the enemy stood when the push began (global): its gold drops there, at the rim.
var _pit_edge_position := Vector2.ZERO
var _pit_pusher: Node = null
var _fell_into_pit := false

@onready var health: HealthComponent = $HealthComponent
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _body_shape: CollisionShape2D = $CollisionShape2D
@onready var _hurtbox_shape: CollisionShape2D = $Hurtbox/CollisionShape2D
@onready var _attack_hitbox: Hitbox = $AttackHitbox
@onready var _attack_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D
@onready var _telegraph_circle: PlaceholderShape = $TelegraphCircle
@onready var _telegraph_line: Line2D = $TelegraphLine
@onready var _health_bar: ProgressBar = $HealthBar
@onready var _navigation_agent: NavigationAgent2D = $NavigationAgent


func _ready() -> void:
	if data == null:
		push_error("Enemy '%s' has no EnemyData assigned." % name)
		set_physics_process(false)
		return
	add_to_group(&"enemies")
	_base_mask = collision_mask
	_navigation = EnemyNavigation.new(self, _navigation_agent)
	SpriteFx.apply(_sprite)
	_apply_data()
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	hurtbox.hit_received.connect(_on_hit_received)
	_enter_state(State.IDLE)


## Applies room scaling (D-011). Works before or after the enemy entered the tree.
## Minibosses become champions: a modified copy of their data (ChampionRules).
func apply_scaling(room_index: int, miniboss: bool) -> void:
	_room_index = room_index
	is_miniboss = miniboss
	if miniboss and not _champion_applied and data != null and not data.is_boss:
		data = ChampionRules.make_champion_data(data)
		_champion_applied = true
	_health_multiplier = EnemyScaling.health_multiplier(room_index, miniboss)
	_damage_multiplier = EnemyScaling.damage_multiplier(room_index, miniboss)
	if is_node_ready() and data != null:
		_apply_data()


## Bosses get tougher and more complex with every cycle of the four bosses (D-076).
## Champions use the same tier in deeper cycles. Call before the enemy enters the tree.
func set_boss_tier(tier: int) -> void:
	_boss_tier = maxi(0, tier)


func get_boss_tier() -> int:
	return _boss_tier


## Elite modifier (D-069). Call before the enemy enters the tree.
func make_elite(kind: Elite) -> void:
	elite = kind


func is_dead() -> bool:
	return _state == State.DEAD


func is_champion() -> bool:
	return is_miniboss and not data.is_boss


## Bosses and champions fight in two phases.
func has_phases() -> bool:
	return data.is_boss or is_miniboss


func is_roaring() -> bool:
	return _state == State.ROAR


# --- Boss intro (BossIntro) ---

## Holds the enemy passive and invulnerable while the boss intro plays: it stands still, faces its
## target and does not attack. Ends with end_intro() or by itself after max_duration seconds, so a
## lost intro can never freeze a fight. No global pause (multiplayer guard rails).
func begin_intro(max_duration: float) -> void:
	if _state == State.DEAD or max_duration <= 0.0:
		return
	_in_intro = true
	_intro_time_left = max_duration
	hurtbox.set_invulnerable(INTRO_INVULNERABILITY, true)
	_attack_hitbox.end_attack()
	_special_chain_left = 0
	_in_chain = false
	_knockback_velocity = Vector2.ZERO
	_enter_state(State.IDLE)
	_play(&"idle")


func end_intro() -> void:
	if not _in_intro:
		return
	_in_intro = false
	_intro_time_left = 0.0
	hurtbox.set_invulnerable(INTRO_INVULNERABILITY, false)
	if _state != State.DEAD:
		_enter_state(State.IDLE)
	intro_ended.emit(self)


func is_in_intro() -> bool:
	return _in_intro


## Short squash on every babbled syllable of the intro (presentation, called by BossIntroView).
func intro_speak_pulse() -> void:
	if _state == State.DEAD or _sprite == null:
		return
	var tween := create_tween()
	tween.tween_property(_sprite, "scale", Vector2(_sprite_scale * 1.06, _sprite_scale * 0.94), 0.05)
	tween.tween_property(_sprite, "scale", Vector2.ONE * _sprite_scale, 0.08)


func _process_intro(delta: float) -> void:
	_intro_time_left -= delta
	if _intro_time_left <= 0.0:
		end_intro()
		return
	_update_target()
	velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	_update_animation(delta)


## Badges shown above the enemy (empty for bosses, see get_ability_badges).
func get_badges() -> Array[StringName]:
	return _badges.get_badges() if _badges != null else ([] as Array[StringName])


## Badges describing the enemy, also for bosses (boss bar).
func get_ability_badges() -> Array[StringName]:
	return EnemyBadges.badges_for(data, elite, is_champion())


func get_display_name() -> String:
	if elite != Elite.NONE:
		return "%s %s" % [ELITE_NAMES[elite], data.display_name]
	return data.display_name


func _apply_data() -> void:
	_speed_multiplier = EnemyScaling.speed_multiplier(_room_index)
	_telegraph_multiplier = EnemyScaling.telegraph_multiplier(_room_index)
	var health_factor := _health_multiplier * (1.0 + 0.4 * _boss_tier)
	match elite:
		Elite.SWIFT:
			_speed_multiplier *= 1.45
			_telegraph_multiplier *= 0.8
		Elite.ARMORED:
			health_factor *= 1.8
	_visual_scale = data.sprite_scale * (MINIBOSS_VISUAL_SCALE if is_miniboss else 1.0) * (1.15 if elite != Elite.NONE else 1.0)
	var radius := data.body_radius * _visual_scale
	_apply_art()
	(_body_shape.shape as CircleShape2D).radius = radius * 0.75
	if _navigation != null:
		_navigation.set_radius(radius * 0.75)
	_body_shape.position = Vector2(0.0, radius * 0.5)
	(_hurtbox_shape.shape as CircleShape2D).radius = radius
	(_attack_shape.shape as CircleShape2D).radius = data.attack_radius
	_telegraph_circle.radius = data.attack_radius
	_attack_hitbox.knockback_strength = data.knockback_strength
	_style_health_bar(radius)
	if _shadow == null:
		_shadow = DropShadow.attach(self, radius)
	# Under the feet: the body collision sits half a radius below the centre.
	_shadow.configure(radius * 1.1, radius * 0.9)
	_update_badges()
	health.reset(data.max_health * health_factor)
	if elite != Elite.NONE:
		SpriteFx.outline(_sprite, ELITE_COLORS[elite])
	elif data.is_boss:
		SpriteFx.outline(_sprite, Color(0.9, 0.3, 1.0), 0.6)
	var light_radius := data.light_radius if data.light_radius > 0.0 else (70.0 if elite != Elite.NONE or is_miniboss else 0.0)
	if light_radius > 0.0 and not has_node(^"Glow"):
		var glow := LightSource.new()
		glow.name = "Glow"
		glow.radius = light_radius
		glow.intensity = 0.8
		add_child(glow)
	_play(&"idle")


## Real art (EnemyArt naming convention) replaces the tinted placeholder automatically.
func _apply_art() -> void:
	var art := EnemyArt.get_art(data)
	var tint := data.tint
	_sprite_scale = SpriteStrip.PIXEL_SCALE * _visual_scale
	if art != null:
		_sprite.sprite_frames = art.frames
		_sprite.offset = SpriteStrip.pivot_offset(art.frame_size, art.origin)
		_sprite_scale = art.sprite_scale_for(_visual_scale)
		tint = Color.WHITE
	elif data.sprite_frames != null:
		_sprite.sprite_frames = data.sprite_frames
		_sprite.offset = SpriteStrip.pivot_offset(SPRITE_FRAME, data.sprite_origin)
	_sprite.scale = Vector2.ONE * _sprite_scale
	_sprite.modulate = Color(tint, data.idle_alpha)


func get_knockback_resistance() -> float:
	return maxf(data.knockback_resistance, 0.7 if elite == Elite.ARMORED else 0.0)


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	if _in_intro:
		_process_intro(delta)
		return
	_update_target()
	_navigation.tick(delta)
	_state_time_left -= delta
	_detour_left -= delta
	velocity = Vector2.ZERO
	if _enrage_pending and _state in [State.IDLE, State.CHASE, State.RECOVER]:
		_start_roar()

	match _state:
		State.IDLE:
			if _target != null:
				_enter_state(State.CHASE)
		State.CHASE:
			_process_chase()
		State.TELEGRAPH:
			_process_telegraph(delta)
		State.ATTACK:
			if _state_time_left <= 0.0:
				_attack_hitbox.end_attack()
				_enter_state(State.RECOVER)
		State.CHARGE:
			_process_charge()
		State.LEAP:
			pass
		State.RECOVER:
			if _state_time_left <= 0.0:
				_enter_state(State.CHASE)
		State.ROAR:
			if _state_time_left <= 0.0:
				_finish_roar()

	# Died inside this frame (self-destruct, own blast): _on_died owns the sprite now; moving on
	# would overwrite the death animation with idle and the enemy would never be freed.
	if _state == State.DEAD:
		return
	if _state != State.LEAP:
		if _pit_unbound:
			# Off its feet: only the push moves it, it cannot walk itself into or out of the abyss.
			velocity = Vector2.ZERO
		velocity += _knockback_velocity
		_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, knockback_friction * delta)
		move_and_slide()
		if _pit_unbound:
			_settle_after_push()
			if _state == State.DEAD:
				return
	if _state == State.CHARGE and _hit_wall_in_slide():
		# Ran into a wall: dazed for a moment, a window to punish the charge. Ends any chain.
		_attack_hitbox.end_attack()
		_special_chain_left = 0
		_in_chain = false
		_enter_state(State.RECOVER)
		_state_time_left = data.attack_cooldown * 1.6
		CameraShake.shake(self, 3.0)
	_update_animation(delta)


## Nearest living player (coop-ready, D-088), re-chosen every TARGET_INTERVAL and at once when
## the current target dies or leaves.
func _update_target() -> void:
	_target_rethink_left -= get_physics_process_delta_time()
	var current: Node2D = _target if is_instance_valid(_target) else null
	if current != null and _target_rethink_left > 0.0 and EnemyTargeting.is_alive(current):
		return
	_target_rethink_left = TARGET_INTERVAL
	_target = EnemyDecoy.choose_target(self, get_tree().get_nodes_in_group(&"player"), current)


## The enemy's current target (null = no living player). For tools and tests.
func get_target() -> Player:
	return _target as Player if is_instance_valid(_target) else null


## Pathfinding state, for tools and tests.
## Walking speed: data, depth scaling and enrage, plus the pact curse of the target (D-112).
func get_move_speed() -> float:
	return data.move_speed * _speed_multiplier * PlayerCurses.enemy_speed_factor(_target)


func get_navigation() -> EnemyNavigation:
	return _navigation


func _process_chase() -> void:
	if _target == null:
		_enter_state(State.IDLE)
		return
	var to_target := _target.global_position - global_position
	var distance := to_target.length()
	var direction := to_target / distance if distance > 0.001 else Vector2.RIGHT
	var speed := get_move_speed()

	var next := _next_action()
	if next == Action.VOLLEY and distance <= data.volley_range:
		_start_telegraph(direction, next)
		return
	if next == Action.SUMMON and distance <= data.volley_range:
		_start_telegraph(direction, next)
		return
	if next == Action.SPECIAL and _special_in_range(distance):
		_start_telegraph(direction, next)
		return

	match data.attack_kind:
		EnemyData.AttackKind.MELEE:
			if distance <= data.attack_range:
				_start_telegraph(direction, next if next == Action.SPECIAL else Action.NORMAL)
			else:
				velocity = _chase_direction(direction) * speed
		EnemyData.AttackKind.RANGED:
			if distance > data.attack_range:
				velocity = _chase_direction(direction) * speed
			elif distance < data.preferred_min_distance and _state_time_left > 0.0:
				velocity = _steer(-direction) * speed
			elif not _navigation.has_free_shot(_body_shape.global_position, _target.global_position):
				# In range, but a wall is in the way: find a firing position over the navigation.
				velocity = _firing_position_direction(direction) * speed
			else:
				_start_telegraph(direction, Action.NORMAL)


## Walking direction towards the target: straight with the old steering while the way is free,
## along the navigation path around walls, pillars and abysses when it is not (EnemyNavigation).
func _chase_direction(direction: Vector2) -> Vector2:
	var path_direction := _navigation.direction_to(_body_shape.global_position, _target.global_position)
	return _follow_path(path_direction, direction)


## Ranged enemies without a free shot walk the path towards the target until the shot is free.
func _firing_position_direction(direction: Vector2) -> Vector2:
	var path_direction := _navigation.path_direction(_body_shape.global_position, _target.global_position)
	return _follow_path(path_direction, direction)


func _follow_path(path_direction: Vector2, direction: Vector2) -> Vector2:
	if path_direction == Vector2.ZERO:
		return _steer(direction)
	if _detour_left > 0.0:
		return _detour
	if _navigation.is_stuck(get_physics_process_delta_time()):
		# Jammed by other enemies or a crate on the path (crates are not part of the navigation):
		# step aside for a moment, alternating sides, preferring the side without a wall.
		_unstick_count += 1
		var side := path_direction.orthogonal()
		var push := _crowd_push()
		if push.dot(side) < -0.1 or (absf(push.dot(side)) <= 0.1 and _unstick_count % 2 == 1):
			side = -side
		if _is_blocked(side):
			side = -side
		_detour = (side + path_direction * 0.35).normalized()
		_detour_left = DETOUR_TIME
		return _detour
	return path_direction


## Sum of the push-back normals of other enemies touched in the last move (zero without contact).
func _crowd_push() -> Vector2:
	var push := Vector2.ZERO
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_collider() is Enemy:
			push += collision.get_normal()
	return push


## Walks around pillars and walls instead of pushing against them: if a short circle cast in the
## wanted direction hits the world, try angled alternatives and keep the first free one briefly.
func _steer(direction: Vector2) -> Vector2:
	if _detour_left > 0.0:
		return _detour
	if not _is_blocked(direction):
		return direction
	for angle in DETOUR_ANGLES:
		var candidate := direction.rotated(angle)
		if not _is_blocked(candidate):
			_detour = candidate
			_detour_left = DETOUR_TIME
			return candidate
	return direction


func _is_blocked(direction: Vector2) -> bool:
	_steer_shape.radius = (_body_shape.shape as CircleShape2D).radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _steer_shape
	query.transform = Transform2D(0.0, _body_shape.global_position)
	query.motion = direction * STEER_LOOKAHEAD
	query.collision_mask = PhysicsLayers.WORLD
	query.exclude = [get_rid()]
	var result := get_world_2d().direct_space_state.cast_motion(query)
	return result.size() >= 1 and result[0] < 1.0


func _next_action() -> Action:
	var next := _attack_count + 1
	var summon_every := _get_summon_every()
	if summon_every > 0 and next % summon_every == 0 and _minion_capacity() > 0:
		return Action.SUMMON
	var special_every := maxi(1, data.special_every - _boss_tier) if data.special_every > 0 else 0
	if data.special != EnemyData.Special.NONE and special_every > 0 and next % special_every == 0:
		return Action.SPECIAL
	if data.volley_every > 0 and next % data.volley_every == 0:
		return Action.VOLLEY
	return Action.NORMAL


func _get_summon_data() -> EnemyData:
	if phase >= 2 and data.enrage_summon != null:
		return data.enrage_summon
	return data.summon_data if data.summon_data != null else extra_summon_data


func _get_summon_every() -> int:
	if data.summon_data != null and data.summon_every > 0:
		return data.summon_every
	return FALLBACK_SUMMON_EVERY if _get_summon_data() != null else 0


func _minion_capacity() -> int:
	# Minions may already be freed: read them untyped and keep only living ones.
	var alive: Array[Enemy] = []
	for i in _minions.size():
		var minion: Variant = _minions[i]
		if is_instance_valid(minion) and not (minion as Enemy).is_dead():
			alive.append(minion)
	_minions = alive
	return BossRules.MAX_MINIONS - _minions.size()


func _special_in_range(distance: float) -> bool:
	match data.special:
		EnemyData.Special.SHIELD_CHARGE:
			return distance <= data.charge_speed * data.charge_time * 0.9
		EnemyData.Special.LEAP_SLAM:
			return distance <= 380.0
		EnemyData.Special.TELEPORT:
			return true
		EnemyData.Special.SELF_DESTRUCT:
			return distance <= data.attack_range
		EnemyData.Special.ERUPTION:
			return distance <= ERUPTION_RANGE
	return false


func _start_telegraph(direction: Vector2, action: Action) -> void:
	_attack_direction = direction
	_action = action
	_enter_state(State.TELEGRAPH)
	_telegraph_circle.color = TELEGRAPH_COLOR
	_telegraph_line.default_color = Color(1, 0.2, 0.1, 0.7)
	match action:
		Action.VOLLEY, Action.SUMMON:
			_telegraph_circle.global_position = global_position
			_telegraph_circle.radius = 46.0 * _visual_scale
			_telegraph_circle.color = TELEGRAPH_COLOR if action == Action.VOLLEY else Color(0.4, 1.0, 0.4, 0.3)
			_telegraph_circle.visible = true
		Action.SPECIAL:
			var chain_factor := BossRules.CHAIN_TELEGRAPH_FACTOR if _in_chain else 1.0
			_state_time_left = data.special_telegraph_time * _telegraph_multiplier * chain_factor
			_start_special_telegraph(direction)
		_:
			if data.attack_kind == EnemyData.AttackKind.MELEE:
				_telegraph_circle.global_position = global_position + direction * data.attack_reach
				_telegraph_circle.radius = data.attack_radius
				_telegraph_circle.visible = true
			else:
				_telegraph_line.points = PackedVector2Array([Vector2.ZERO, direction * data.attack_range])
				_telegraph_line.visible = true
	_play_attack_animation(_state_time_left, action)


func _start_special_telegraph(direction: Vector2) -> void:
	match data.special:
		EnemyData.Special.SHIELD_CHARGE:
			_telegraph_line.default_color = Color(1, 0.85, 0.15, 0.8)
			_telegraph_line.points = PackedVector2Array([Vector2.ZERO, direction * data.charge_speed * data.charge_time])
			_telegraph_line.visible = true
			Sfx.play_at(self, &"charge", global_position)
		EnemyData.Special.LEAP_SLAM:
			_leap_target = _target.global_position if _target != null else global_position
			_telegraph_circle.global_position = _leap_target
			_telegraph_circle.radius = data.blast_radius
			_telegraph_circle.color = SPECIAL_TELEGRAPH_COLOR
			_telegraph_circle.visible = true
		EnemyData.Special.TELEPORT:
			create_tween().tween_property(_sprite, "modulate:a", 0.0, _state_time_left)
		EnemyData.Special.SELF_DESTRUCT:
			_telegraph_circle.global_position = global_position
			_telegraph_circle.radius = data.blast_radius
			_telegraph_circle.visible = true
			_fuse_timer = 0.0
		EnemyData.Special.ERUPTION:
			_leap_target = _target.global_position if _target != null else global_position
			_telegraph_circle.global_position = _leap_target
			_telegraph_circle.radius = data.blast_radius
			_telegraph_circle.color = SPECIAL_TELEGRAPH_COLOR
			_telegraph_circle.visible = true
			Sfx.play_at(self, &"fuse", global_position)


func _process_telegraph(delta: float) -> void:
	if _action == Action.SPECIAL and data.special == EnemyData.Special.SELF_DESTRUCT:
		# Chase while the fuse burns, blinking faster and faster.
		if _target != null:
			var to_target := (_target.global_position - global_position).normalized()
			var path_direction := _navigation.direction_to(_body_shape.global_position, _target.global_position)
			velocity = (path_direction if path_direction != Vector2.ZERO else to_target) * get_move_speed() * 0.6
		_telegraph_circle.global_position = global_position
		_fuse_timer -= delta
		if _fuse_timer <= 0.0:
			_fuse_timer = FUSE_BEEP_INTERVAL
			Sfx.play_at(self, &"fuse", global_position)
			SpriteFx.flash(_sprite, Color(1, 0.3, 0.1), 0.08)
	if _state_time_left <= 0.0:
		_perform_attack()


func _perform_attack() -> void:
	# Chained specials belong to the attack that started the chain.
	if not _in_chain:
		_attack_count += 1
	match _action:
		Action.VOLLEY:
			_fire_volley()
			_enter_state(State.RECOVER)
		Action.SUMMON:
			_summon()
			_enter_state(State.RECOVER)
		Action.SPECIAL:
			if not _in_chain:
				_special_chain_left = BossRules.special_repeats(_boss_tier, phase, data.enrage_special_repeats) if has_phases() else 0
			_perform_special()
		_:
			if data.attack_kind == EnemyData.AttackKind.MELEE:
				_attack_hitbox.position = _attack_direction * data.attack_reach
				_attack_hitbox.begin_attack(_create_damage())
				_enter_state(State.ATTACK)
			else:
				_fire_spread(_attack_direction, data.projectile_count)
				_enter_state(State.RECOVER)


func _perform_special() -> void:
	match data.special:
		EnemyData.Special.SHIELD_CHARGE:
			var damage := _create_damage()
			damage.stun_duration = data.stun_duration
			_attack_hitbox.position = _attack_direction * data.attack_reach
			_attack_hitbox.begin_attack(damage)
			_enter_state(State.CHARGE)
			_state_time_left = data.charge_time
			ability_used.emit(self, &"charge")
		EnemyData.Special.LEAP_SLAM:
			_leap()
		EnemyData.Special.TELEPORT:
			_teleport()
			var aim := (_target.global_position - global_position).normalized() if _target != null else _attack_direction
			_fire_spread(aim, 5 if data.is_boss else 3)
			_finish_special()
		EnemyData.Special.SELF_DESTRUCT:
			ability_used.emit(self, &"self_destruct")
			var blast := Blast.spawn(get_parent(), global_position, data.blast_radius, data.damage * _damage_multiplier)
			blast.source = self
			health.take_damage(INF)
		EnemyData.Special.ERUPTION:
			_spawn_eruptions(data.eruption_count, _leap_target, data.blast_radius)
			_finish_special()


## End of one special: chain the next one (phase two, higher tiers) or recover. After the last
## special of a sequence, phase-two eruptions break out around the player.
func _finish_special() -> void:
	if _state == State.DEAD:
		return
	if _special_chain_left > 0 and _target != null:
		_special_chain_left -= 1
		_in_chain = true
		var to_target := _target.global_position - global_position
		_start_telegraph(to_target.normalized() if to_target.length() > 0.001 else _attack_direction, Action.SPECIAL)
		ability_used.emit(self, &"chain")
		return
	_in_chain = false
	var eruptions := BossRules.eruption_count(_boss_tier, phase, data.enrage_eruptions) if has_phases() else 0
	if eruptions > 0 and _target != null:
		_spawn_eruptions(eruptions, _target.global_position, ERUPTION_RADIUS)
	_enter_state(State.RECOVER)


func _process_charge() -> void:
	velocity = _attack_direction * data.charge_speed
	if _state_time_left <= 0.0:
		_attack_hitbox.end_attack()
		_finish_special()


## Only walls and pillars stop a charge; the player and other enemies (minions) do not.
func _hit_wall_in_slide() -> bool:
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if not (collider is Player or collider is Enemy):
			return true
	return false


func _leap() -> void:
	_enter_state(State.LEAP)
	_state_time_left = LEAP_TIME
	collision_mask = 0
	Sfx.play_at(self, &"charge", global_position)
	ability_used.emit(self, &"leap")
	var start := global_position
	var target := _leap_target
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		global_position = start.lerp(target, t)
		_sprite.position.y = -sin(t * PI) * 90.0, 0.0, 1.0, LEAP_TIME)
	tween.tween_callback(_land)


func _land() -> void:
	if _state == State.DEAD:
		return
	collision_mask = _base_mask
	_pit_unbound = false
	_sprite.position.y = 0.0
	# A leap never ends in an abyss: the nearest walkable point instead (A4).
	if PitProbe.is_pit_at(get_world_2d(), global_position) and _navigation != null:
		global_position = _navigation.snap_to_navigation(global_position)
	var blast := Blast.spawn(get_parent(), global_position, data.blast_radius, data.damage * _damage_multiplier)
	blast.source = self
	blast.sound = &"slam"
	blast.shake = 10.0
	blast.color = data.placeholder_color
	var ring := BossRules.landing_ring_count(_boss_tier, phase, data.enrage_landing_ring) if has_phases() else 0
	if ring > 0:
		_fire_ring(ring, randf() * TAU, 0.75)
		ability_used.emit(self, &"landing_ring")
	_finish_special()


func _teleport() -> void:
	var destination := global_position
	if _target != null:
		for attempt in 12:
			var candidate := _target.global_position + Vector2.from_angle(randf() * TAU) * randf_range(TELEPORT_MIN_DISTANCE, TELEPORT_MAX_DISTANCE)
			if arena.size == Vector2.ZERO or arena.grow(-48.0).has_point(candidate):
				destination = candidate
				break
		# Never into a pillar or an inner wall: nearest walkable point (unchanged without navigation).
		destination = _navigation.snap_to_navigation(destination)
	Burst.spawn(get_parent(), global_position, data.placeholder_color, 16, 140.0)
	global_position = destination
	Burst.spawn(get_parent(), global_position, data.placeholder_color, 16, 140.0)
	Sfx.play_at(self, &"teleport", global_position)
	create_tween().tween_property(_sprite, "modulate:a", 1.0, 0.25)
	ability_used.emit(self, &"teleport")


## Delayed blasts with visible warning circles: the first exactly on center, the rest around it.
func _spawn_eruptions(count: int, center: Vector2, radius: float) -> void:
	if count <= 0:
		return
	for i in count:
		var offset := Vector2.ZERO
		if i > 0:
			offset = Vector2.from_angle(TAU * float(i) / float(maxi(1, count - 1)) + randf()) * randf_range(ERUPTION_SPREAD.x, ERUPTION_SPREAD.y)
		var spot := center + offset
		if arena.size != Vector2.ZERO:
			var inner := arena.grow(-32.0)
			spot = spot.clamp(inner.position, inner.end)
		var blast := Blast.spawn(get_parent(), spot, radius, data.damage * _damage_multiplier, ERUPTION_DELAY + 0.12 * i)
		blast.source = self
		blast.color = data.placeholder_color
		blast.shake = 4.0
	ability_used.emit(self, &"eruption")


func _summon() -> void:
	var minion_data := _get_summon_data()
	var capacity := _minion_capacity()
	if minion_data == null or capacity <= 0:
		return
	var scene := load(ENEMY_SCENE_PATH) as PackedScene
	var count := data.summon_count if data.summon_data != null else FALLBACK_SUMMON_COUNT
	count = mini(count + (BossRules.summon_bonus(phase) if has_phases() else 0), capacity)
	for i in count:
		var minion := scene.instantiate() as Enemy
		minion.data = minion_data
		var spot := global_position + Vector2.from_angle(TAU * float(i) / float(count) + randf()) * 64.0
		if arena.size != Vector2.ZERO:
			var inner := arena.grow(-40.0)
			spot = spot.clamp(inner.position, inner.end)
		# Never inside a wall or pillar (A2 navigation; A3 inner walls).
		if _navigation != null:
			spot = _navigation.snap_to_navigation(spot)
		var parent := get_parent() as Node2D
		minion.position = parent.to_local(spot) if parent != null else spot
		minion.apply_scaling(_room_index, false)
		minion.arena = arena
		get_parent().add_child(minion)
		_minions.append(minion)
		Burst.spawn(get_parent(), minion.global_position, minion_data.placeholder_color, 12, 120.0)
		summoned.emit(minion)
	Sfx.play_at(self, &"teleport", global_position)
	ability_used.emit(self, &"summon")


# --- Phase two ---

func _start_roar() -> void:
	_enrage_pending = false
	phase = 2
	_attack_hitbox.end_attack()
	_special_chain_left = 0
	_in_chain = false
	_enter_state(State.ROAR)
	var boss := data.is_boss
	_state_time_left = BossRules.ROAR_TIME if boss else BossRules.CHAMPION_ROAR_TIME
	hurtbox.set_invulnerable(ROAR_INVULNERABILITY, true)
	Sfx.play_at(self, &"boss_roar", global_position, 0.0 if boss else -6.0)
	CameraShake.shake(self, 10.0 if boss else 5.0)
	LightSource.flash(get_parent(), global_position, 260.0 if boss else 160.0, 0.6)
	Burst.spawn(get_parent(), global_position, ENRAGE_COLOR, 40 if boss else 20, 260.0, 0.6, 5.0)
	SpriteFx.flash(_sprite, ENRAGE_COLOR, 0.35)
	SpriteFx.outline(_sprite, ENRAGE_COLOR, 0.9)
	_telegraph_circle.global_position = global_position
	_telegraph_circle.radius = 60.0 * _visual_scale
	_telegraph_circle.color = Color(ENRAGE_COLOR, 0.2)
	_telegraph_circle.visible = true
	var pulse := create_tween()
	pulse.tween_property(_sprite, "scale", Vector2.ONE * _sprite_scale * 1.15, 0.15)
	pulse.tween_property(_sprite, "scale", Vector2.ONE * _sprite_scale, 0.3)
	_play(&"idle")
	phase_changed.emit(self, phase)
	ability_used.emit(self, &"roar")


func _finish_roar() -> void:
	hurtbox.set_invulnerable(ROAR_INVULNERABILITY, false)
	if data.is_boss:
		_speed_multiplier *= BossRules.ENRAGE_SPEED_FACTOR
		_cooldown_factor = BossRules.ENRAGE_COOLDOWN_FACTOR
		_telegraph_multiplier *= BossRules.ENRAGE_TELEGRAPH_FACTOR
	else:
		_speed_multiplier *= BossRules.CHAMPION_ENRAGE_SPEED_FACTOR
		_cooldown_factor = BossRules.CHAMPION_ENRAGE_COOLDOWN_FACTOR
	_enter_state(State.CHASE)
	# The roar calls for help right away.
	if _get_summon_data() != null:
		_summon()


func _create_damage() -> DamageData:
	var damage := DamageData.new()
	damage.amount = data.damage * _damage_multiplier
	damage.source = self
	damage.tags.assign(data.tags)
	damage.blind_duration = data.blind_duration
	return damage


## One ring, more rings in phase two / higher tiers (rotating a little each wave = spiral).
func _fire_volley() -> void:
	var count := data.volley_count + 6 * _boss_tier
	var waves := BossRules.volley_waves(_boss_tier, phase, data.enrage_spiral) if has_phases() else 1
	var base_angle := _attack_direction.angle()
	_fire_ring(count, base_angle)
	CameraShake.shake(self, 4.0)
	ability_used.emit(self, &"volley")
	if waves <= 1:
		return
	ability_used.emit(self, &"spiral")
	var tween := create_tween()
	for wave in range(1, waves):
		tween.tween_interval(BossRules.SPIRAL_WAVE_INTERVAL)
		tween.tween_callback(_fire_ring.bind(count, base_angle + wave * TAU / (count * 3.0)))


func _fire_ring(count: int, start_angle: float, speed_factor := 1.0) -> void:
	if _state == State.DEAD:
		return
	for i in count:
		_fire_projectile(_create_damage(), Vector2.from_angle(start_angle + TAU * float(i) / float(count)), speed_factor)
	Sfx.play_at(self, &"enemy_shoot", global_position)


func _fire_spread(direction: Vector2, count: int) -> void:
	var spread := deg_to_rad(14.0)
	for i in maxi(1, count):
		var angle := (float(i) - float(count - 1) * 0.5) * spread
		_fire_projectile(_create_damage(), direction.rotated(angle))
	Sfx.play_at(self, &"enemy_shoot", global_position)


func _fire_projectile(damage: DamageData, direction: Vector2, speed_factor := 1.0) -> void:
	var speed := (data.projectile_speed if data.projectile_speed > 0.0 else 240.0) * speed_factor
	var distance := maxf(data.attack_range, data.volley_range) * 1.5
	var projectile := Projectile.create(damage, direction, speed, distance, PhysicsLayers.PLAYER_HURTBOX)
	projectile.collision_radius = data.projectile_radius
	if data.projectile_texture != null:
		projectile.texture = data.projectile_texture
		projectile.frame_size = data.projectile_frame_size
		projectile.pivot = data.projectile_pivot
	else:
		projectile.texture = FALLBACK_PROJECTILE_TEXTURE
		projectile.frame_size = Vector2i(16, 16)
		projectile.pivot = Vector2(8, 8)
	projectile.fps = 1.0
	projectile.color = data.placeholder_color
	projectile.light_radius = 50.0
	projectile.launch(get_parent(), global_position + direction * 12.0)


func _enter_state(new_state: State) -> void:
	_state = new_state
	_telegraph_circle.visible = false
	_telegraph_line.visible = false
	match new_state:
		State.CHASE:
			_state_time_left = data.reposition_time
		State.TELEGRAPH:
			_state_time_left = data.telegraph_time * _telegraph_multiplier
		State.ATTACK:
			_state_time_left = data.attack_active_time
		State.RECOVER:
			var swift := 0.75 if elite == Elite.SWIFT else 1.0
			_state_time_left = data.attack_cooldown * EnemyScaling.cooldown_multiplier(_room_index) * swift * _cooldown_factor
		_:
			_state_time_left = 0.0


# --- Visuals ---

func _update_animation(delta: float) -> void:
	if _state == State.DEAD:
		return
	# Shadows fade in while they attack.
	if data.idle_alpha < 1.0:
		var attacking := _state in [State.TELEGRAPH, State.ATTACK, State.CHARGE]
		var target_alpha := 1.0 if attacking else data.idle_alpha
		if not (_action == Action.SPECIAL and data.special == EnemyData.Special.TELEPORT and _state == State.TELEGRAPH):
			_sprite.modulate.a = move_toward(_sprite.modulate.a, target_alpha, delta * 3.0)
	if _state in [State.TELEGRAPH, State.ATTACK, State.CHARGE, State.LEAP]:
		_sprite.flip_h = _attack_direction.x < 0.0
		return
	if _target != null:
		_sprite.flip_h = _target.global_position.x < global_position.x
	if _state == State.ROAR:
		return
	if velocity.length_squared() > 25.0:
		_play(&"walk")
	elif _state != State.RECOVER or not _sprite.animation in [&"attack", &"attack2", &"summon"]:
		_play(&"idle")


## Plays the attack animation so that its strike frame is reached exactly when the telegraph ends.
## Real art may bring "attack2" (specials) and "summon"; otherwise "attack" is used for everything.
func _play_attack_animation(duration: float, action := Action.NORMAL) -> void:
	var frames := _sprite.sprite_frames
	if frames == null or _state == State.DEAD:
		return
	var animation := &"attack"
	if action == Action.SPECIAL and frames.has_animation(&"attack2"):
		animation = &"attack2"
	elif action == Action.SUMMON and frames.has_animation(&"summon"):
		animation = &"summon"
	if not frames.has_animation(animation):
		return
	var fps := frames.get_animation_speed(animation)
	var strike := data.strike_frame if animation == &"attack" else maxi(1, frames.get_frame_count(animation) - 2)
	var lead_time := float(strike) / fps
	_sprite.play(animation)
	_sprite.speed_scale = lead_time / maxf(0.05, duration)


## Never while dead: only _on_died plays the death animation.
func _play(animation: StringName) -> void:
	var frames := _sprite.sprite_frames
	if frames == null or not frames.has_animation(animation) or _state == State.DEAD:
		return
	if _sprite.animation != animation or not _sprite.is_playing():
		_sprite.speed_scale = 1.0
		_sprite.play(animation)


func _style_health_bar(radius: float) -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = HEALTH_BAR_BACKGROUND
	var fill := StyleBoxFlat.new()
	fill.bg_color = HEALTH_BAR_FILL
	_health_bar.add_theme_stylebox_override("background", background)
	_health_bar.add_theme_stylebox_override("fill", fill)
	var width := maxf(HEALTH_BAR_SIZE.x, radius * 2.4)
	_health_bar.size = Vector2(width, HEALTH_BAR_SIZE.y)
	_health_bar.position = Vector2(-width * 0.5, -radius - 30.0 * _visual_scale)
	# Bosses show their health in the big boss bar instead.
	_health_bar.visible = not data.is_boss


## Readability: badges right above the health bar (elite kind, champion, abilities).
func _update_badges() -> void:
	var badges: Array[StringName] = []
	if not data.is_boss:
		badges = EnemyBadges.badges_for(data, elite, is_champion())
	if badges.is_empty():
		if _badges != null:
			_badges.set_badges(badges)
		return
	if _badges == null:
		_badges = EnemyBadges.new()
		_badges.name = "Badges"
		_badges.z_index = 20
		add_child(_badges)
	_badges.set_badges(badges)
	_badges.position = Vector2(0.0, _health_bar.position.y - BADGE_GAP)
	_update_elite_label()


## Elite kind or "Champion" as a small label right of the badge row (docs/design screen 11).
func _update_elite_label() -> void:
	var text := ""
	var color := CHAMPION_LABEL_COLOR
	if is_champion():
		text = "Champion"
	elif elite != Elite.NONE:
		text = ELITE_NAMES[elite]
		color = ELITE_COLORS[elite]
	if text.is_empty():
		if _elite_label != null:
			_elite_label.visible = false
		return
	if _elite_label == null:
		# World space (no camera zoom): sized in art pixels, not in UI mockup pixels.
		_elite_label = UiKit.text_label("", UiKit.SIZE_BODY, color, true)
		_elite_label.name = "EliteLabel"
		_elite_label.z_index = 20
		_elite_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_elite_label.add_theme_font_size_override("font_size", roundi(ELITE_LABEL_SIZE))
		add_child(_elite_label)
	_elite_label.visible = true
	_elite_label.text = text
	_elite_label.add_theme_color_override("font_color", color)
	_elite_label.reset_size()
	var badge_size := EnemyBadges.ICON_SIZE * EnemyBadges.ICON_SCALE
	_elite_label.position = Vector2(_badges.get_row_width() * 0.5 + 2.0, _badges.position.y - (badge_size + _elite_label.size.y) * 0.5)


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	if not _enrage_pending and has_phases() and _state != State.DEAD and BossRules.should_enrage(current, maximum, phase):
		_enrage_pending = true


func _on_hit_received(result: DamageResult, damage: DamageData) -> void:
	_knockback_velocity = damage.knockback * (1.0 - get_knockback_resistance())
	if not result.killed:
		_check_pit_push(damage.source)
	var top := global_position + Vector2(0.0, -data.body_radius * _visual_scale - 22.0)
	DamageNumber.spawn_for_result(get_parent(), top, result)
	SpriteStrip.spawn_effect(get_parent(), global_position, HIT_SPARK_TEXTURE, Vector2i(16, 16), 15.0, Vector2(8, 8), Vector2.ONE * SpriteStrip.PIXEL_SCALE)
	Burst.spawn(get_parent(), global_position, data.placeholder_color, 6, 110.0, 0.3, 3.0)
	SpriteFx.flash(_sprite)
	Sfx.play_at(self, &"hit_enemy", global_position)
	CameraShake.shake(self, 1.5)
	EventBus.enemy_damaged.emit(self, result, damage)


func _on_died() -> void:
	_enter_state(State.DEAD)
	end_intro()
	_attack_hitbox.end_attack()
	velocity = Vector2.ZERO
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	hurtbox.set_deferred("monitorable", false)
	_health_bar.visible = false
	if _badges != null:
		_badges.visible = false
	if _shadow != null:
		_shadow.fade_out(DEATH_DISSOLVE_TIME)
	_sprite.position.y = 0.0
	_sprite.modulate.a = 1.0
	_drop_gold()
	# A split slime that falls takes its children with it.
	if not _fell_into_pit:
		_spawn_on_death()
	died.emit(self)
	Sfx.play_at(self, &"enemy_death", global_position)
	Burst.spawn(get_parent(), global_position, data.placeholder_color, 18 if not data.is_boss else 60, 200.0, 0.6, 5.0)
	HitStop.trigger(self, 0.25 if data.is_boss else 0.045)
	CameraShake.shake(self, 12.0 if data.is_boss else 3.0)
	if elite == Elite.VOLATILE:
		var blast := Blast.spawn(get_parent(), global_position, 72.0, maxf(1.0, data.damage * _damage_multiplier), 0.7)
		blast.source = self
	_sprite.speed_scale = 1.0
	if _fell_into_pit:
		_play_fall()
		return
	if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(&"death"):
		_sprite.play(&"death")
		await _wait_for_death_animation()
	SpriteFx.dissolve(_sprite, DEATH_DISSOLVE_TIME, data.placeholder_color).tween_callback(queue_free)


## Waits for the end of the death animation, but never longer than its planned length plus
## DEATH_ANIMATION_MARGIN (looping death animations of foreign art, an animation that got replaced).
## Timer and sprite are children of this enemy, so nothing resumes after it was freed.
func _wait_for_death_animation() -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = minf(DEATH_ANIMATION_MAX_TIME, death_animation_time(_sprite.sprite_frames) + DEATH_ANIMATION_MARGIN)
	add_child(timer)
	_death_wait_done = false
	_sprite.animation_finished.connect(_end_death_wait, CONNECT_ONE_SHOT)
	timer.timeout.connect(_end_death_wait)
	timer.start()
	await death_wait_over
	if _sprite.animation_finished.is_connected(_end_death_wait):
		_sprite.animation_finished.disconnect(_end_death_wait)
	timer.queue_free()


func _end_death_wait() -> void:
	if _death_wait_done:
		return
	_death_wait_done = true
	death_wait_over.emit()


## Seconds the "death" animation of frames plays once at speed_scale 1 (0 without one).
static func death_animation_time(frames: SpriteFrames) -> float:
	if frames == null or not frames.has_animation(&"death"):
		return 0.0
	var fps := frames.get_animation_speed(&"death")
	if fps <= 0.0:
		return DEATH_ANIMATION_MAX_TIME
	var units := 0.0
	for i in frames.get_frame_count(&"death"):
		units += frames.get_frame_duration(&"death", i)
	return units / fps


func _spawn_on_death() -> void:
	if data.death_spawn == null or data.death_spawn_count <= 0:
		return
	var scene := load(ENEMY_SCENE_PATH) as PackedScene
	for i in data.death_spawn_count:
		var child := scene.instantiate() as Enemy
		child.data = data.death_spawn
		child.position = position + Vector2.from_angle(TAU * i / data.death_spawn_count) * 20.0
		# Never inside an abyss (A4): the nearest walkable point instead.
		var parent := get_parent() as Node2D
		if parent != null and _navigation != null and PitProbe.is_pit_at(get_world_2d(), parent.to_global(child.position)):
			child.position = parent.to_local(_navigation.snap_to_navigation(parent.to_global(child.position)))
		child.apply_scaling(_room_index, false)
		child.arena = arena
		get_parent().add_child.call_deferred(child)
		summoned.emit(child)
	ability_used.emit(self, &"split")


func _drop_gold() -> void:
	if gold_drop <= 0:
		return
	var pickup := GOLD_PICKUP_SCENE.instantiate() as GoldPickup
	pickup.amount = gold_drop
	pickup.position = position
	var parent := get_parent() as Node2D
	if _fell_into_pit and parent != null:
		# At the rim it was pushed from, never over the abyss (A4).
		pickup.position = parent.to_local(_pit_edge_position)
	# Deferred: death happens inside a hit callback.
	get_parent().add_child.call_deferred(pickup)


# --- Abyss (A4, D-086) ---

## Normal enemies and elites can be pushed into an abyss; champions, golems and bosses never.
func can_fall_into_pit() -> bool:
	return not _in_intro and ChasmRules.can_enemy_fall(data, is_champion())


func has_fallen_into_pit() -> bool:
	return _fell_into_pit


func is_pit_unbound() -> bool:
	return _pit_unbound


## Called with every hit: a strong enough knockback whose slide reaches an abyss lifts the pit
## block (and the enemy's own walking) until it settles. Nothing changes without a pit nearby.
func _check_pit_push(pusher: Node) -> void:
	if _pit_unbound or _state == State.DEAD or _state == State.LEAP or not can_fall_into_pit():
		return
	var speed := _knockback_velocity.length()
	if not ChasmRules.knockback_can_push(speed) or not is_inside_tree():
		return
	var world := get_world_2d()
	var center := _body_shape.global_position
	var direction := _knockback_velocity / speed
	var reach := ChasmRules.knockback_travel(speed, knockback_friction) + RoomTiles.TILE_WORLD * 0.5
	var distance := RoomTiles.TILE_WORLD * 0.25
	var towards_pit := false
	while distance <= reach:
		if PitProbe.is_pit_at(world, center + direction * distance):
			towards_pit = true
			break
		distance += RoomTiles.TILE_WORLD * 0.25
	if not towards_pit:
		return
	_pit_unbound = true
	_pit_edge_position = global_position
	_pit_pusher = pusher
	collision_mask &= ~PhysicsLayers.PIT


## The push is over: over the abyss -> fall, else the pit blocks again.
func _settle_after_push() -> void:
	if _knockback_velocity.length() > ChasmRules.ENEMY_SETTLE_SPEED:
		return
	_pit_unbound = false
	if PitProbe.is_pit_at(get_world_2d(), _body_shape.global_position):
		fall_into_pit()
	else:
		collision_mask |= PhysicsLayers.PIT & _base_mask


## Falls and dies: a kill like any other (EventBus, room count, on-kill effects), credited to the
## source of the push; no death spawns, the gold at the rim.
func fall_into_pit() -> void:
	if _state == State.DEAD or _fell_into_pit:
		return
	_fell_into_pit = true
	_pit_unbound = false
	if _pit_edge_position == Vector2.ZERO:
		_pit_edge_position = global_position
	fell_into_pit.emit(self)
	var damage := DamageData.new()
	damage.amount = ceilf(health.get_health()) + 1.0
	damage.source = _pit_pusher if is_instance_valid(_pit_pusher) else null
	damage.tags.assign([ChasmRules.DAMAGE_TAG])
	damage.hit_id = DamageData.next_hit_id()
	var result := DamageProcessor.process_hit(damage, health, null, false)
	EventBus.enemy_damaged.emit(self, result, damage)


## Shrinks, turns and fades into the dark instead of the death animation.
func _play_fall() -> void:
	Sfx.play_at(self, ChasmRules.fall_sound(), global_position, -6.0)
	var tween := create_tween().set_parallel()
	tween.tween_property(_sprite, "scale", _sprite.scale * 0.2, ChasmRules.FALL_TIME).set_ease(Tween.EASE_IN)
	tween.tween_property(_sprite, "rotation", 1.2, ChasmRules.FALL_TIME)
	tween.tween_property(_sprite, "position:y", 18.0, ChasmRules.FALL_TIME)
	tween.tween_property(_sprite, "modulate", Color(0.2, 0.2, 0.3, 0.0), ChasmRules.FALL_TIME)
	tween.chain().tween_callback(queue_free)

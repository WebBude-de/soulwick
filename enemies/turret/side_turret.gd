class_name SideTurret
extends Node2D
## The stationary turret of a side-view segment (M5 round 3, team member 16.10.2026: "ein kleines
## Teil, das stationär dasteht und dich immer abschießt"). It stands on a floor, hangs from the rock
## above or sits on a rock wall (SideLayout.turret_normal), watches for the nearest living player in
## sight (rock blocks the view, ledges do not), lights up (TurretRules telegraph: the eye grows, a red
## line shows the aim and holds still shortly before the shot) and fires a slow orb horizontally or
## at a slant. A hit costs a little and slows the running for a moment (TurretRules.SLOW_FACTOR on
## the DamageData, Player applies it); jumping stays the same. Weapons destroy it (enemy hurtbox,
## EventBus.enemy_damaged like SideEnemy), no gold (the coins are the reward).
## Cadence and aim come from TurretRules (the same object as the room turret, side numbers in
## SideRules), the body here is only look, hits and the shot.
## Group game: the host decides (charge_started / fired / died go to the clients through NetSide);
## a client's turret is remote_controlled: it shows the telegraph and the recoil when the host says
## so and fires nothing itself (NetEnemies brings the host's orb as a harmless picture).

## The eye lit up (aim = unit direction, the telegraph line follows until the lock).
signal charge_started(turret: SideTurret, aim: Vector2)
## The shot left along aim.
signal fired(turret: SideTurret, aim: Vector2)
signal died(turret: SideTurret)

const DATA_PATH := "res://enemies/data/turret_%s.tres"
const FALLBACK_BIOME := &"crypt"
const FRAME := Vector2i(32, 32)
## Feet pivot of the turret art (TurretArt, SPRITES_V10 §5): the mount point.
const FEET_PIVOT := Vector2(16, 30)
## The eye sits this far out of the mount (world px; art eye at y 10 above feet 30, ×2).
const MUZZLE_DISTANCE := 40.0
## Hurtbox: radius and how far out of the mount its centre sits.
const HURT_RADIUS := 20.0
const HURT_DISTANCE := 22.0
const GLOW_RADIUS := Vector2(5.0, 15.0)
const LINE_COLOR := Color(1.0, 0.25, 0.15)
const LINE_ALPHA := Vector2(0.15, 0.8)
const LINE_WIDTH := 2.0
const RECOIL_TIME := 0.2
const DEATH_TIME := 0.6
## The room turret got much stronger on 17.10.2026 (feedback #3aae30f6: health 12 -> 60, damage
## 0.1 -> 0.4 in turret_*.tres); the small side-view turret keeps the D-151 numbers (12 health and
## 0.1 damage before depth scaling). TESTWERT
const SIDE_HEALTH_SHARE := 0.2
const SIDE_DAMAGE_SHARE := 0.25
const SHOT_FPS := 8.0
const SHOT_LIGHT := 40.0
const SHOT_TRAIL := 6
const SHOT_SOUND := &"turret_shot"
const SHOT_SOUND_FALLBACK := &"enemy_shoot"
const CHARGE_SOUND := &"turret_charge"

var data: EnemyData = null
var biome_id: StringName = FALLBACK_BIOME
var room_index := 1
## Unit vector out of the mount (UP = standing on a floor, DOWN = hanging, LEFT / RIGHT = on a wall).
var normal := Vector2.UP
var segment: SideSegment = null
## Client of a group game: the host decides charges, shots and the death (NetSide).
var remote_controlled := false
var rules: TurretRules = null
var health: HealthComponent = null
var hurtbox: Hurtbox = null
## Shots fired here (host / single player) and charges shown (tests, tools).
var shots := 0
var charges := 0

var _dead := false
var _target: Node2D = null
var _retarget_left := 0.0
var _recoil_left := 0.0
## Client: a charge shown for the host (seconds left, total).
var _remote_charge_left := 0.0
var _sprite: AnimatedSprite2D = null
var _eye_light: LightSource = null


## Before entering the tree. mount_normal: SideLayout.turret_normal of its cell.
func setup(biome: StringName, index: int, owner_segment: SideSegment, mount_normal: Vector2i) -> void:
	biome_id = biome
	room_index = index
	segment = owner_segment
	normal = Vector2(mount_normal) if mount_normal != Vector2i.ZERO else Vector2.UP
	data = data_for(biome)


## The biome's turret data (the room turret's numbers and look), the crypt's for unknown biomes.
static func data_for(biome: StringName) -> EnemyData:
	for candidate in [biome, FALLBACK_BIOME]:
		var path := DATA_PATH % candidate
		if ResourceLoader.exists(path):
			return load(path) as EnemyData
	return null


## Side numbers (SideRules) through the same scaling as every enemy (TurretRules.for_data).
static func rules_for(index: int) -> TurretRules:
	var cooldown_factor := maxf(TurretRules.MIN_COOLDOWN_FACTOR, EnemyScaling.cooldown_multiplier(index))
	return TurretRules.new(SideRules.TURRET_SIGHT_TILES * SideRules.TILE,
			SideRules.TURRET_CHARGE_TIME * EnemyScaling.telegraph_multiplier(index),
			SideRules.TURRET_COOLDOWN * cooldown_factor, SideRules.TURRET_FIRST_DELAY)


func _ready() -> void:
	z_index = -1
	rules = rules_for(room_index)
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	var art := EnemyArt.get_art(data)
	if art != null:
		_sprite.sprite_frames = art.frames
		# ArtSet.origin is the body centre; the feet sit EnemyArt.FEET_TO_BODY frame heights lower.
		_sprite.offset = SpriteStrip.pivot_offset(art.frame_size, art.origin + Vector2(0.0, art.frame_size.y * EnemyArt.FEET_TO_BODY))
		_sprite.scale = Vector2.ONE * art.sprite_scale_for(1.0)
	else:
		_sprite.sprite_frames = TurretArt.placeholder_frames(data)
		_sprite.offset = SpriteStrip.pivot_offset(FRAME, FEET_PIVOT)
		_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	# The art looks up out of a floor; hanging and wall mounts turn it out of their rock.
	_sprite.rotation = normal.angle() + PI * 0.5
	add_child(_sprite)
	SpriteFx.apply(_sprite)
	_play(&"idle")
	_eye_light = LightSource.new()
	_eye_light.name = "EyeLight"
	_eye_light.radius = data.light_radius if data != null and data.light_radius > 0.0 else 46.0
	_eye_light.intensity = 0.45
	_eye_light.flicker = 0.05
	_eye_light.color = TurretArt.get_eye_color(data)
	_eye_light.position = normal * MUZZLE_DISTANCE
	add_child(_eye_light)

	health = HealthComponent.new()
	health.name = "HealthComponent"
	var base := data.max_health * SIDE_HEALTH_SHARE if data != null else 12.0
	health.max_health = maxf(1.0, roundf(base * EnemyScaling.health_multiplier(room_index, false) * SideRules.TURRET_HEALTH_FACTOR))
	add_child(health)
	health.died.connect(_on_died)
	hurtbox = Hurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.health = health
	hurtbox.collision_layer = PhysicsLayers.ENEMY_HURTBOX
	hurtbox.collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = HURT_RADIUS
	shape.shape = circle
	hurtbox.add_child(shape)
	hurtbox.position = normal * HURT_DISTANCE
	add_child(hurtbox)
	hurtbox.hit_received.connect(_on_hit_received)


func is_dead() -> bool:
	return _dead


func get_muzzle_position() -> Vector2:
	return global_position + normal * MUZZLE_DISTANCE


## The player it aims at right now (null = none in sight). Tests and tools.
func get_target() -> Node2D:
	return _target if is_instance_valid(_target) else null


func is_charging() -> bool:
	return _remote_charge_left > 0.0 if remote_controlled else (rules != null and rules.is_charging())


func _physics_process(delta: float) -> void:
	if _dead or rules == null:
		return
	if remote_controlled:
		_remote_charge_left = maxf(0.0, _remote_charge_left - delta)
		_update_look(delta)
		return
	_retarget_left -= delta
	if _retarget_left <= 0.0 or not _still_valid(_target):
		_retarget_left = TurretRules.RETARGET_INTERVAL
		var candidates: Array = []
		if segment != null:
			candidates.assign(segment.get_players())
		_target = TurretRules.choose_target(candidates, get_muzzle_position(), rules.sight_range, can_see)
	var direction := Vector2.ZERO
	if _target != null:
		direction = aim_at(_target)
	var was_charging := rules.is_charging()
	var shot := rules.tick(delta, direction)
	if rules.is_charging() and not was_charging:
		_show_charge(rules.aim)
		charge_started.emit(self, rules.aim)
	if shot:
		_fire(rules.aim)
	_update_look(delta)


## Unit direction from the eye to a target's body; never back into the own mount.
func aim_at(target: Node2D) -> Vector2:
	var direction := TurretRules.direction_to(get_muzzle_position(), target.global_position)
	if direction.dot(normal) < 0.0:
		direction = (direction - normal * direction.dot(normal)).normalized()
		if direction == Vector2.ZERO:
			direction = normal
	return direction


## Sight: no rock between the eye and the target (ledges let it through), on the same side of the
## mount. Callable for TurretRules.choose_target.
func can_see(target: Node2D) -> bool:
	if target == null or segment == null or segment.layout == null:
		return false
	var from := get_muzzle_position()
	if (target.global_position - global_position).dot(normal) < -SideRules.TILE * 0.25:
		return false
	return segment.layout.line_clear(segment.to_local(from), segment.to_local(target.global_position))


func _still_valid(target: Node2D) -> bool:
	if not EnemyTargeting.is_targetable(target):
		return false
	return get_muzzle_position().distance_to(target.global_position) <= rules.sight_range


# --- Group game (NetSide) ---

## The host's turret lit up: show the telegraph here for the same time.
func apply_remote_charge(aim: Vector2) -> void:
	if _dead:
		return
	rules.aim = aim.normalized() if aim != Vector2.ZERO else normal
	_remote_charge_left = rules.charge_time
	_show_charge(rules.aim)


## The host's turret fired: recoil, flash and sound here; the orb comes through NetEnemies.
func apply_remote_fire(aim: Vector2) -> void:
	if _dead:
		return
	_remote_charge_left = 0.0
	rules.aim = aim.normalized() if aim != Vector2.ZERO else normal
	_shot_look(rules.aim)


## The host's turret was destroyed.
func apply_remote_death() -> void:
	if not _dead:
		health.take_damage(health.get_health() + 1.0)


# --- Effects ---

func _show_charge(aim: Vector2) -> void:
	charges += 1
	rules.aim = aim
	if is_inside_tree():
		Sfx.play_at(self, CHARGE_SOUND, global_position, -8.0)
	var frames := _sprite.sprite_frames
	if frames == null or not frames.has_animation(&"attack"):
		return
	var fps := maxf(0.1, frames.get_animation_speed(&"attack"))
	var strike := clampi(data.strike_frame if data != null else TurretArt.STRIKE_FRAME, 1, maxi(1, frames.get_frame_count(&"attack") - 1))
	_sprite.play(&"attack")
	_sprite.speed_scale = (float(strike) / fps) / maxf(0.05, rules.charge_time)


func _fire(direction: Vector2) -> void:
	shots += 1
	var damage := DamageData.new()
	damage.amount = (data.damage * SIDE_DAMAGE_SHARE if data != null else 0.1) * EnemyScaling.damage_multiplier(room_index, false)
	damage.source = self
	if data != null:
		damage.tags.assign(data.tags)
	damage.slow_factor = TurretRules.SLOW_FACTOR
	damage.slow_duration = TurretRules.SLOW_DURATION
	var projectile := Projectile.create(damage, direction, SideRules.TURRET_SHOT_SPEED, rules.get_shot_distance(), PhysicsLayers.PLAYER_HURTBOX)
	var eye := TurretArt.get_eye_color(data)
	projectile.collision_radius = data.projectile_radius if data != null else 6.0
	projectile.texture = TurretArt.get_shot_texture(data)
	projectile.frame_size = TurretArt.SHOT_FRAME
	projectile.pivot = TurretArt.SHOT_PIVOT
	projectile.fps = SHOT_FPS
	projectile.color = eye
	if projectile.texture == TurretArt.SHOT_FALLBACK:
		projectile.modulate = eye.lightened(0.2)
	projectile.light_radius = SHOT_LIGHT
	projectile.trail_length = SHOT_TRAIL
	projectile.trail_width = 3.0
	projectile.trail_color = eye
	projectile.launch(get_parent(), get_muzzle_position() + direction * 8.0)
	_shot_look(direction)
	fired.emit(self, direction)


func _shot_look(direction: Vector2) -> void:
	_recoil_left = RECOIL_TIME
	if not is_inside_tree():
		return
	var sound := SHOT_SOUND if ResourceLoader.exists("res://audio/sfx/%s.wav" % SHOT_SOUND) else SHOT_SOUND_FALLBACK
	Sfx.play_at(self, sound, global_position, -4.0)
	Burst.spawn(get_parent(), get_muzzle_position() + direction * 6.0, TurretArt.get_eye_color(data), 5, 70.0, 0.25, 2.5)


func _update_look(delta: float) -> void:
	# Hanging and wall mounts keep the art the right way round; only floor mounts turn to the target.
	if normal == Vector2.UP:
		_sprite.flip_h = rules.aim.x < 0.0
	if is_charging():
		_eye_light.intensity = lerpf(0.45, 1.0, _charge_progress())
	else:
		_eye_light.intensity = 0.45
		_recoil_left -= delta
		if _recoil_left <= 0.0:
			_play(&"idle")
	queue_redraw()


func _charge_progress() -> float:
	if remote_controlled:
		return clampf(1.0 - _remote_charge_left / maxf(0.05, rules.charge_time), 0.0, 1.0)
	return rules.get_charge_progress()


## Telegraph: the glow in the eye grows, the red line shows where the orb goes (holds at the lock).
func _draw() -> void:
	if _dead or rules == null or not is_charging():
		return
	var progress := _charge_progress()
	var eye := TurretArt.get_eye_color(data)
	var muzzle := normal * MUZZLE_DISTANCE
	var locked := rules.is_aim_locked() if not remote_controlled else progress > 0.75
	var alpha := LINE_ALPHA.y if locked else lerpf(LINE_ALPHA.x, LINE_ALPHA.y * 0.8, progress)
	draw_line(muzzle, muzzle + rules.aim * rules.sight_range, Color(LINE_COLOR, alpha), LINE_WIDTH)
	var radius := lerpf(GLOW_RADIUS.x, GLOW_RADIUS.y, progress)
	draw_circle(muzzle, radius, Color(eye, lerpf(0.15, 0.45, progress)))
	draw_arc(muzzle, radius, 0.0, TAU, 24, Color(eye, 0.9), 1.5)


func _play(animation: StringName) -> void:
	if _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation(animation):
		return
	if _sprite.animation != animation:
		_sprite.speed_scale = 1.0
		_sprite.play(animation)


func _on_hit_received(result: DamageResult, damage: DamageData) -> void:
	SpriteFx.flash(_sprite)
	if is_inside_tree():
		Sfx.play_at(self, &"hit_enemy", global_position, -4.0)
	EventBus.enemy_damaged.emit(self, result, damage)


func _on_died() -> void:
	if _dead:
		return
	_dead = true
	_remote_charge_left = 0.0
	hurtbox.set_deferred(&"monitorable", false)
	_eye_light.intensity = 0.0
	queue_redraw()
	_sprite.speed_scale = 1.0
	_play(&"death")
	if is_inside_tree():
		Sfx.play_at(self, &"enemy_death", global_position, -2.0)
		Burst.spawn(get_parent(), global_position + normal * HURT_DISTANCE, TurretArt.get_eye_color(data), 12, 120.0, 0.45, 3.0)
	died.emit(self)
	if is_inside_tree():
		get_tree().create_timer(DEATH_TIME, false).timeout.connect(queue_free)

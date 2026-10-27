class_name Turret
extends Enemy
## Stationary tower (D-151): never moves, watches for the nearest living player in range and sight
## and shoots a slow orb at it in a fixed cadence. A hit hurts and slows the player (SlowStatus), so
## running circles around the other enemies costs something. Since 17.10.2026 (feedback #3aae30f6,
## "zentraler, dafür viel stärker, wie ein Turm in League of Legends") it stands near the middle of
## the room (TurretPlacement) and is a tough target (turret_*.tres: health 60, damage 0.4, 2 gold,
## all TESTWERT). It can be destroyed and counts as an enemy of the room (clearing needs it gone).
## Rules (target, cadence, aim) live in TurretRules, the look in TurretArt; this node only connects
## them to the Enemy body: health, hits, death, coming out of the ground (begin_emerge), network
## puppets (NetEnemies sends the scene path of this node; a puppet runs no physics, the snapshots
## carry its animation, the glow circle and the aim line).
## Telegraph: the eye lights up (attack animation, a growing glow circle in the eye colour) and a
## red aim line shows where the shot goes; the line holds still for TurretRules.AIM_LOCK_TIME.
## Always visible (feedback #3aae30f6, 17.10.2026: "den hat man nie gesehen"): a turret never fades
## out in the dark (DarknessVisibility.ALWAYS_VISIBLE_META) and carries its own red glow, which
## flares up while it charges (CHARGE_LIGHT_FACTOR), so a shot never comes out of nowhere.

const SCENE_PATH := "res://enemies/turret/turret.tscn"
const TAG := &"turret"
## The eye sits this far above the body centre (world px); shots leave from there.
const MUZZLE_OFFSET := Vector2(0.0, -24.0)
## Glow circle in the eye: radius at the start and at the end of a charge.
const GLOW_RADIUS := Vector2(5.0, 14.0)
const LINE_COLOR := Color(1.0, 0.25, 0.15)
const LINE_ALPHA := Vector2(0.2, 0.85)
## Aim line width while the aim follows and once it holds (a PixelLine, D-218: 2 px = one art
## pixel, 3 px = two).
const LINE_WIDTH := Vector2(2.0, 3.0)
## Own glow (Enemy "Glow" light, data.light_radius) at the shot, as a multiple of its idle radius;
## it grows over the charge. Optics only. TESTWERT
const CHARGE_LIGHT_FACTOR := 2.2
## Back to idle this long after a shot.
const RECOIL_TIME := 0.2
## Shot look: fps of the orb strip, light around it, trail.
const SHOT_FPS := 8.0
const SHOT_LIGHT := 40.0
const SHOT_TRAIL := 6
const SHOT_SOUND := &"turret_shot"
const SHOT_SOUND_FALLBACK := &"enemy_shoot"
const CHARGE_SOUND := &"turret_charge"

## Cadence and aim (null until the first physics step after apply_scaling).
var rules: TurretRules = null

var _aim_target: Node2D = null
var _retarget_left := 0.0
var _recoil_left := 0.0
var _body_sprite: AnimatedSprite2D = null
var _glow: PlaceholderShape = null
var _line: Line2D = null
## Idle radius of the own glow (0 until the glow exists).
var _glow_light_radius := 0.0


## A turret of data for room_index, not yet in the tree (position it, add it, then begin_emerge).
static func create(turret_data: EnemyData, room_index: int) -> Turret:
	var turret := (load(SCENE_PATH) as PackedScene).instantiate() as Turret
	turret.data = turret_data
	turret.apply_scaling(room_index, false)
	return turret


static func is_turret_data(enemy_data: EnemyData) -> bool:
	return enemy_data != null and enemy_data.tags.has(TAG)


func _ready() -> void:
	_body_sprite = get_node(^"Sprite") as AnimatedSprite2D
	_glow = get_node(^"TelegraphCircle") as PlaceholderShape
	_line = get_node(^"TelegraphLine") as Line2D
	# Before Enemy._ready: DarknessVisibility registers enemies when they are ready.
	set_meta(DarknessVisibility.ALWAYS_VISIBLE_META, true)
	super._ready()
	if data == null:
		return
	_apply_placeholder_look()


## Turrets are never champions; the rules follow the new room.
func apply_scaling(room_index: int, _miniboss: bool) -> void:
	super.apply_scaling(room_index, false)
	rules = null
	if is_node_ready() and data != null:
		_apply_placeholder_look()


## The player the turret aims at (null = none in range and sight). For tools and tests.
func get_aim_target() -> Node2D:
	return _aim_target if is_instance_valid(_aim_target) else null


func get_muzzle_position() -> Vector2:
	return global_position + MUZZLE_OFFSET


func _physics_process(delta: float) -> void:
	if data == null or is_dead():
		return
	if is_in_intro():
		# Hidden in the ground or coming out of it: the Enemy hold does everything.
		super._physics_process(delta)
		_hide_telegraph()
		return
	if rules == null:
		rules = TurretRules.for_data(data, get_room_index())
	_retarget_left -= delta
	if _retarget_left <= 0.0 or not _still_valid(_aim_target):
		_retarget_left = TurretRules.RETARGET_INTERVAL
		_aim_target = TurretRules.choose_target(get_tree().get_nodes_in_group(&"player"), global_position, rules.sight_range, _can_see)
	var direction := Vector2.ZERO
	if _aim_target != null:
		direction = TurretRules.direction_to(get_muzzle_position(), _aim_target.global_position)
	var was_charging := rules.is_charging()
	var fired := rules.tick(delta, direction)
	if rules.is_charging() and not was_charging:
		_start_charge()
	if fired:
		_fire(rules.aim)
	_update_look(delta)


## Alive, targetable and in range (sight is checked on every retarget only).
func _still_valid(target: Node2D) -> bool:
	if not EnemyTargeting.is_targetable(target):
		return false
	return global_position.distance_to(target.global_position) <= rules.sight_range


## No wall or pillar between the turret and the target (projectiles stop at the same layer).
func _can_see(target: Node2D) -> bool:
	var ray := PhysicsRayQueryParameters2D.create(global_position, target.global_position, PhysicsLayers.WORLD)
	ray.collide_with_areas = false
	ray.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


func _start_charge() -> void:
	Sfx.play_at(self, CHARGE_SOUND, global_position, -8.0)
	var frames := _body_sprite.sprite_frames
	if frames == null or not frames.has_animation(&"attack"):
		return
	# The strike frame (brightest eye) is reached exactly when the shot leaves.
	var fps := maxf(0.1, frames.get_animation_speed(&"attack"))
	var strike := clampi(data.strike_frame, 1, maxi(1, frames.get_frame_count(&"attack") - 1))
	_body_sprite.play(&"attack")
	_body_sprite.speed_scale = (float(strike) / fps) / maxf(0.05, rules.charge_time)


func _fire(direction: Vector2) -> void:
	var damage := DamageData.new()
	damage.amount = data.damage * EnemyScaling.damage_multiplier(get_room_index(), false)
	damage.source = self
	damage.tags.assign(data.tags)
	damage.slow_factor = TurretRules.SLOW_FACTOR
	damage.slow_duration = TurretRules.SLOW_DURATION
	var speed := data.projectile_speed if data.projectile_speed > 0.0 else 150.0
	var projectile := Projectile.create(damage, direction, speed, rules.get_shot_distance(), PhysicsLayers.PLAYER_HURTBOX)
	var eye := TurretArt.get_eye_color(data)
	projectile.collision_radius = data.projectile_radius
	projectile.texture = TurretArt.get_shot_texture(data)
	var own_art := projectile.texture != TurretArt.SHOT_FALLBACK
	projectile.frame_size = data.projectile_frame_size if data.projectile_texture != null else TurretArt.SHOT_FRAME
	projectile.pivot = data.projectile_pivot if data.projectile_texture != null else TurretArt.SHOT_PIVOT
	projectile.fps = SHOT_FPS
	projectile.color = eye
	if not own_art:
		# The shared orb in the turret's colour (on network clients it keeps its own colour).
		projectile.modulate = eye.lightened(0.2)
	projectile.light_radius = SHOT_LIGHT
	projectile.trail_length = SHOT_TRAIL
	projectile.trail_width = 3.0
	projectile.trail_color = eye
	# The slow rides on the DamageData (slow_factor / slow_duration): Player._on_hit_received applies it,
	# so it also lands after the turret is gone and on network copies of the hit.
	projectile.launch(get_parent(), get_muzzle_position() + direction * 8.0)
	var sound := SHOT_SOUND if ResourceLoader.exists("res://audio/sfx/%s.wav" % SHOT_SOUND) else SHOT_SOUND_FALLBACK
	Sfx.play_at(self, sound, global_position, -4.0)
	Burst.spawn(get_parent(), get_muzzle_position(), eye, 5, 70.0, 0.25, 2.5)
	_recoil_left = RECOIL_TIME
	ability_used.emit(self, &"turret_shot")


func _update_look(delta: float) -> void:
	_body_sprite.flip_h = rules.aim.x < 0.0
	if rules.is_charging():
		var progress := rules.get_charge_progress()
		var eye := TurretArt.get_eye_color(data)
		_glow.global_position = get_muzzle_position()
		_glow.radius = lerpf(GLOW_RADIUS.x, GLOW_RADIUS.y, progress)
		_glow.color = Color(eye, lerpf(0.15, 0.45, progress))
		_glow.outline_color = Color(eye, 0.9)
		_glow.visible = true
		var alpha := LINE_ALPHA.y if rules.is_aim_locked() else lerpf(LINE_ALPHA.x, LINE_ALPHA.y * 0.8, progress)
		_line.default_color = Color(LINE_COLOR, alpha)
		_line.points = PackedVector2Array([Vector2.ZERO, rules.aim * rules.sight_range])
		_line.visible = true
		return
	_hide_telegraph()
	_recoil_left -= delta
	if _recoil_left <= 0.0 and _body_sprite.animation != &"idle" and _body_sprite.sprite_frames != null and _body_sprite.sprite_frames.has_animation(&"idle"):
		_body_sprite.speed_scale = 1.0
		_body_sprite.play(&"idle")


## Optics that follow the telegraph nodes, so network puppets (no physics, snapshots set the glow
## circle and the line) flare up the same way: the own glow grows with the glow circle, the aim line
## thickens once it holds (full alpha).
func _process(_delta: float) -> void:
	if _glow == null or _line == null:
		return
	var factor := 1.0
	if _glow.visible:
		var progress := inverse_lerp(GLOW_RADIUS.x, GLOW_RADIUS.y, _glow.radius)
		factor = lerpf(1.0, CHARGE_LIGHT_FACTOR, clampf(progress, 0.0, 1.0))
	_set_glow_light(factor)
	if _line.visible:
		_line.width = LINE_WIDTH.y if _line.default_color.a >= LINE_ALPHA.y - 0.01 else LINE_WIDTH.x


## Own glow at factor times its idle radius (1 = idle).
func _set_glow_light(factor: float) -> void:
	var light := get_node_or_null(^"Glow") as LightSource
	if light == null:
		return
	if _glow_light_radius <= 0.0:
		_glow_light_radius = light.radius
	light.radius = _glow_light_radius * factor
	light.intensity = lerpf(0.8, 1.0, clampf(factor - 1.0, 0.0, 1.0))


func _hide_telegraph() -> void:
	if _glow != null:
		_glow.visible = false
	if _line != null:
		_line.visible = false


## Code-drawn tower in the biome palette while no real art exists (EnemyArt wins when it does).
func _apply_placeholder_look() -> void:
	if _body_sprite == null or _body_sprite.sprite_frames != null:
		return
	_body_sprite.sprite_frames = TurretArt.placeholder_frames(data)
	_body_sprite.offset = SpriteStrip.pivot_offset(TurretArt.FRAME, data.sprite_origin)
	_body_sprite.speed_scale = 1.0
	_body_sprite.play(&"idle")

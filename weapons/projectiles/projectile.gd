class_name Projectile
extends Hitbox
## Straight-flying projectile for bow, staff and archer.
## Direct projectiles damage on contact; AOE projectiles (aoe_radius > 0) never deal direct damage
## but resolve one primary area hit that includes the touched target (D-024).
## Walls are found by a ray per frame, which also yields the normal for "Wandabprall".
## Pierce, bounce and hit history are tracked per projectile (D-033).

const SCENE_PATH := "res://weapons/projectiles/projectile.tscn"
const EXPLOSION_TEXTURE: Texture2D = preload("res://art/effects/explosion_6f.png")
## The explosion art shows a 45 px radius at scale 1 (see art/index.json).
const EXPLOSION_ART_RADIUS := 45.0
const WALL_SKIN := 2.0

var direction := Vector2.RIGHT
var speed := 300.0
var max_distance := 600.0
var pierce_remaining := 0
var bounces_remaining := 0
var aoe_radius := 0.0
var collision_radius := 4.0
var texture: Texture2D = null
var frame_size := Vector2i(16, 16)
var pivot := Vector2(8, 8)
var fps := 10.0
var color := Color.WHITE
## Light circle in the dungeon darkness (0 = none).
var light_radius := 0.0
## Fading pixel trail behind the projectile (PixelTrail, D-218): number of remembered positions
## (0 = no trail).
var trail_length := 0
var trail_width := 4.0
var trail_color := Color.WHITE

var _pending_damage: DamageData = null
var _travelled := 0.0
var _finished := false
var _trail: PixelTrail = null

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _shape: CollisionShape2D = $CollisionShape2D


## Creates a configured projectile. Set optional fields (aoe_radius, texture, ...) before launch().
## target_hurtbox_mask selects who can be hit.
static func create(damage: DamageData, move_direction: Vector2, move_speed: float, distance: float, target_hurtbox_mask: int) -> Projectile:
	# load() instead of preload(): the scene references this script, preload would be cyclic.
	var projectile := (load(SCENE_PATH) as PackedScene).instantiate() as Projectile
	projectile._pending_damage = damage
	# Shots fly over cliffs (M3, HeightRules); thrown knives were melee until now.
	if not damage.tags.has(&"projectile"):
		damage.tags.append(&"projectile")
	projectile.direction = move_direction.normalized()
	projectile.speed = move_speed
	projectile.max_distance = distance
	projectile.collision_mask = target_hurtbox_mask
	return projectile


func launch(parent: Node, global_origin: Vector2) -> void:
	# Position before entering the tree, so _ready (trail, light) already sees the real origin.
	var parent_2d := parent as Node2D
	position = parent_2d.to_local(global_origin) if parent_2d != null else global_origin
	parent.add_child(self)
	global_position = global_origin


func _ready() -> void:
	super._ready()
	var circle := CircleShape2D.new()
	circle.radius = collision_radius
	_shape.shape = circle
	if texture != null:
		_sprite.sprite_frames = SpriteStrip.make_frames(texture, frame_size, fps, true)
		_sprite.offset = SpriteStrip.pivot_offset(frame_size, pivot)
		_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		_sprite.play(&"default")
	rotation = direction.angle()
	if light_radius > 0.0:
		var light := LightSource.new()
		light.radius = light_radius
		light.intensity = 0.85
		add_child(light)
	if trail_length > 0:
		_build_trail()
	hit_landed.connect(_on_hit_landed)
	begin_attack(_pending_damage)


func _physics_process(delta: float) -> void:
	if _finished:
		return
	var step := direction * speed * delta
	var wall := _raycast_wall(global_position, global_position + step)
	if wall.is_empty():
		global_position += step
		_travelled += step.length()
	else:
		var hit_position: Vector2 = wall["position"]
		var normal: Vector2 = wall["normal"]
		_travelled += global_position.distance_to(hit_position)
		if bounces_remaining > 0:
			bounces_remaining -= 1
			global_position = hit_position + normal * WALL_SKIN
			direction = direction.bounce(normal).normalized()
			rotation = direction.angle()
		else:
			global_position = hit_position
			_impact()
			return
	_update_trail()
	super._physics_process(delta)
	if not _finished and _travelled >= max_distance:
		_impact()


func _handle_contact(hurtbox: Hurtbox) -> void:
	if aoe_radius > 0.0:
		_impact()
		return
	super._handle_contact(hurtbox)


func _on_hit_landed(_hurtbox: Hurtbox, _result: DamageResult) -> void:
	if pierce_remaining > 0:
		pierce_remaining -= 1
	else:
		_finish()


func _raycast_wall(from: Vector2, to: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to, PhysicsLayers.WORLD)
	query.collide_with_areas = false
	return get_world_2d().direct_space_state.intersect_ray(query)


func _impact() -> void:
	if aoe_radius > 0.0 and _template != null:
		AreaDamage.apply(self, global_position, aoe_radius, collision_mask, _template, knockback_strength)
		# Whole scale (FS2b): the art's pixels stay even; the area hit keeps the exact radius.
		var art_scale := PixelDraw.whole_scale(aoe_radius / EXPLOSION_ART_RADIUS)
		SpriteStrip.spawn_effect(get_parent(), global_position, EXPLOSION_TEXTURE, Vector2i(96, 96), 14.0, Vector2(48, 48), Vector2(art_scale, art_scale))
		LightSource.flash(get_parent(), global_position, aoe_radius * 2.5, 0.4)
		Burst.spawn(get_parent(), global_position, color, 16, aoe_radius * 3.0, 0.45, 4.0)
		Sfx.play_at(get_parent(), &"explosion", global_position, -4.0)
		CameraShake.shake(self, 4.0)
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	end_attack()
	_release_trail()
	queue_free()


## The trail lives in world space (top_level), so its points are global positions.
func _build_trail() -> void:
	_trail = PixelTrail.new()
	_trail.width = trail_width
	_trail.color = trail_color
	_trail.max_points = trail_length
	_trail.z_index = -1
	add_child(_trail)
	# No initial point here: the first physics step adds the real start position.


func _update_trail() -> void:
	if _trail == null:
		return
	_trail.add_point(global_position)


## Hands the trail to the world so it fades out after the projectile is gone.
func _release_trail() -> void:
	var parent := get_parent()
	if _trail == null or parent == null:
		return
	var trail := _trail
	_trail = null
	remove_child(trail)
	parent.add_child(trail)
	trail.fade_out(0.18)

class_name LavaPool
extends Node2D
## Burning lava left behind by a lava ball (BossPressure, TESTWERTE): hurts players standing in it
## every TICK_INTERVAL, each tick a new attack instance (D-020; hit I-frames and the dash protect as
## always), first after ARM_TIME so a player can step out of the impact. Goes out after its
## lifetime or when its thrower died. Without a target mask (network client) only a picture.
## Code-drawn in pixel art (PixelDraw, D-218); art/effects/lava_pool_4f.png replaces the drawing
## when present.

const TICK_INTERVAL := 0.8
const ARM_TIME := 0.35
const FADE_TIME := 0.5
const ART_PATH := "res://art/effects/lava_pool_4f.png"
const ART_FRAME := Vector2i(32, 32)
const ART_FPS := 5.0
const BASE_COLOR := Color(0.95, 0.35, 0.08, 0.75)
const CRUST_COLOR := Color(0.3, 0.1, 0.05, 0.9)
const BUBBLE_COLOR := Color(1.0, 0.85, 0.4, 0.9)
const TAGS: Array[StringName] = [&"lava", &"fire", &"trap"]

var radius := 36.0
var lifetime := 2.5
var damage := 0.5
var target_mask := PhysicsLayers.PLAYER_HURTBOX
var source: Node = null

var _time := 0.0
var _tick_left := ARM_TIME
var _hitbox: Hitbox = null
var _sprite: AnimatedSprite2D = null


static func spawn(parent: Node, global_pos: Vector2, pool_radius: float, pool_lifetime: float, tick_damage: float, mask: int, thrower: Node) -> LavaPool:
	var pool := LavaPool.new()
	pool.radius = pool_radius
	pool.lifetime = pool_lifetime
	pool.damage = tick_damage
	pool.target_mask = mask
	pool.source = thrower if is_instance_valid(thrower) else null
	parent.add_child(pool)
	pool.global_position = global_pos
	return pool


func _ready() -> void:
	z_index = -9
	if target_mask != 0 and damage > 0.0:
		_hitbox = Hitbox.new()
		_hitbox.collision_layer = 0
		_hitbox.collision_mask = target_mask
		var shape := CircleShape2D.new()
		shape.radius = radius
		var collision := CollisionShape2D.new()
		collision.shape = shape
		_hitbox.add_child(collision)
		add_child(_hitbox)
	var glow := LightSource.new()
	glow.radius = radius * 1.4
	glow.intensity = 0.5
	glow.flicker = 0.1
	add_child(glow)
	if ResourceLoader.exists(ART_PATH):
		_sprite = AnimatedSprite2D.new()
		_sprite.sprite_frames = SpriteStrip.make_frames(load(ART_PATH) as Texture2D, ART_FRAME, ART_FPS, true)
		# Whole scale (FS2b): the art's pixels stay even; the hitbox keeps the exact radius.
		_sprite.scale = Vector2.ONE * PixelDraw.whole_scale(radius * 2.0 / float(ART_FRAME.x))
		_sprite.play(&"default")
		add_child(_sprite)


func is_burning() -> bool:
	return _hitbox != null and _hitbox.is_active()


func _physics_process(delta: float) -> void:
	_time += delta
	if _time >= lifetime or _thrower_died():
		queue_free()
		set_physics_process(false)
		return
	var left := lifetime - _time
	if _hitbox != null:
		if left <= FADE_TIME * 0.5:
			_hitbox.end_attack()
		else:
			_tick_left -= delta
			if _tick_left <= 0.0:
				_tick_left = TICK_INTERVAL
				_hitbox.end_attack()
				_hitbox.begin_attack(_create_damage())
	modulate.a = clampf(minf(_time / 0.15, left / FADE_TIME), 0.0, 1.0)
	queue_redraw()


func _create_damage() -> DamageData:
	var hit := DamageData.new()
	hit.amount = damage
	hit.source = source if is_instance_valid(source) else null
	hit.tags.assign(TAGS)
	return hit


func _thrower_died() -> bool:
	if source == null:
		return false
	if not is_instance_valid(source):
		return true
	return source.has_method(&"is_dead") and bool(source.call(&"is_dead"))


func _draw() -> void:
	if _sprite != null:
		return
	# Pixel art (D-218): stepped discs, bubbles that grow and fade in hard steps.
	var wobble := 1.0 + 0.05 * sin(_time * 3.0)
	PixelDraw.disc(self, Vector2.ZERO, radius * wobble, CRUST_COLOR)
	PixelDraw.disc(self, Vector2.ZERO, radius * 0.85 * wobble, BASE_COLOR)
	PixelDraw.disc(self, Vector2(radius * 0.3, -radius * 0.15), radius * 0.45 * wobble, Color(BUBBLE_COLOR, 0.35))
	for i in 3:
		var phase := fmod(_time * 1.2 + i * 0.33, 1.0)
		var spot := Vector2.from_angle(i * 2.1) * radius * 0.45
		PixelDraw.disc(self, spot, 1.5 + 3.5 * phase, Color(BUBBLE_COLOR, PixelDraw.stepped(1.0 - phase, 3)))

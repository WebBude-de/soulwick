@tool
class_name LavaCrack
extends Node2D
## Ember-forge floor hazard (KONZEPT_ENDLOS §2): a glowing crack that periodically erupts, like a
## spike trap: idle -> warning (bright, sparks) -> burst (hurts the player) -> idle. Only the player
## is targeted. Dormant while the player is far away (rooms are prepared ahead).
## Code-drawn; art/environment/props/lava_crack_4f.png replaces the drawing when present.

enum Phase { IDLE, WARN, ACTIVE }

const SIZE := Vector2(60.0, 26.0)
const IDLE_TIME := 2.8
const WARN_TIME := 0.8
const ACTIVE_TIME := 0.35
const DAMAGE := 1.0
const WAKE_DISTANCE := 760.0
const ART_PATH := "res://art/environment/props/lava_crack_4f.png"
const CRUST_COLOR := Color(0.1, 0.05, 0.04)
const GLOW_COLOR := Color(1.0, 0.4, 0.08)
const HOT_COLOR := Color(1.0, 0.85, 0.35)
const POINTS: Array[Vector2] = [Vector2(-30, 2), Vector2(-18, -6), Vector2(-8, 4), Vector2(4, -5), Vector2(14, 5), Vector2(24, -3), Vector2(30, 3)]

var _phase := Phase.IDLE
var _time_left := 0.0
var _time := 0.0
var _hitbox: Hitbox = null
var _light: LightSource = null
var _sprite: AnimatedSprite2D = null


func _ready() -> void:
	z_index = -9
	if Engine.is_editor_hint():
		return
	_time_left = randf_range(0.6, IDLE_TIME)
	_hitbox = Hitbox.new()
	_hitbox.collision_layer = 0
	_hitbox.collision_mask = PhysicsLayers.PLAYER_HURTBOX
	var shape := RectangleShape2D.new()
	shape.size = SIZE
	var collision := CollisionShape2D.new()
	collision.shape = shape
	_hitbox.add_child(collision)
	add_child(_hitbox)
	_light = LightSource.new()
	_light.radius = 46.0
	_light.intensity = 0.45
	_light.flicker = 0.12
	add_child(_light)
	if ResourceLoader.exists(ART_PATH):
		_sprite = AnimatedSprite2D.new()
		_sprite.sprite_frames = SpriteStrip.make_frames(load(ART_PATH), Vector2i(32, 32), 6.0, true)
		_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		_sprite.play(&"default")
		add_child(_sprite)


func _physics_process(delta: float) -> void:
	_time += delta
	if Engine.is_editor_hint():
		queue_redraw()
		return
	if _phase == Phase.IDLE and not _player_near():
		queue_redraw()
		return
	_time_left -= delta
	if _time_left <= 0.0:
		match _phase:
			Phase.IDLE:
				_phase = Phase.WARN
				_time_left = WARN_TIME
				_light.radius = 70.0
				_light.intensity = 0.8
				Sfx.play_at(self, &"fuse", global_position, -8.0)
			Phase.WARN:
				_phase = Phase.ACTIVE
				_time_left = ACTIVE_TIME
				var damage := DamageData.new()
				damage.amount = DAMAGE
				damage.tags.assign([&"trap", &"fire"])
				_hitbox.begin_attack(damage)
				Burst.spawn(get_parent(), global_position, GLOW_COLOR, 18, 170.0, 0.5, 4.0)
				LightSource.flash(get_parent(), global_position, 120.0, 0.4)
				Sfx.play_at(self, &"explosion", global_position, -10.0)
				CameraShake.shake(self, 1.5)
			Phase.ACTIVE:
				_phase = Phase.IDLE
				_time_left = IDLE_TIME
				_hitbox.end_attack()
				_light.radius = 46.0
				_light.intensity = 0.45
	if _phase == Phase.WARN and randf() < 0.3:
		Burst.spawn(get_parent(), global_position + Vector2(randf_range(-SIZE.x, SIZE.x) * 0.4, 0.0), HOT_COLOR, 2, 60.0, 0.3, 2.0)
	if _sprite != null:
		_sprite.modulate = _art_brightness()
	queue_redraw()


func is_active() -> bool:
	return _phase == Phase.ACTIVE


func is_warning() -> bool:
	return _phase == Phase.WARN


func _player_near() -> bool:
	var player := EnemyTargeting.nearest_living(get_tree().get_nodes_in_group(&"player"), global_position)
	return player != null and player.global_position.distance_to(global_position) <= WAKE_DISTANCE


func _glow_color() -> Color:
	match _phase:
		Phase.WARN:
			return HOT_COLOR.lerp(GLOW_COLOR, 0.5 + 0.5 * sin(_time * 30.0))
		Phase.ACTIVE:
			return HOT_COLOR
	return Color(GLOW_COLOR, 0.55 + 0.2 * sin(_time * 3.0))


## The art already glows orange; it only gets brighter while warning and erupting.
func _art_brightness() -> Color:
	match _phase:
		Phase.WARN:
			return Color.WHITE * (1.25 + 0.35 * sin(_time * 30.0))
		Phase.ACTIVE:
			return Color(1.8, 1.6, 1.3)
	return Color(0.75, 0.75, 0.75)


func _draw() -> void:
	if _sprite != null:
		return
	var crust := PackedVector2Array()
	for point in POINTS:
		crust.append(point)
	draw_polyline(crust, CRUST_COLOR, 12.0)
	var width := 4.0
	if _phase == Phase.WARN:
		width = 6.0
	elif _phase == Phase.ACTIVE:
		width = 10.0
	draw_polyline(crust, _glow_color(), width)
	if _phase == Phase.ACTIVE:
		for point in POINTS:
			draw_circle(point + Vector2(0, -8), 6.0, Color(HOT_COLOR, 0.8))

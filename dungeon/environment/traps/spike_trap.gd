@tool
class_name SpikeTrap
extends Node2D
## Floor spike trap (D-069): idle -> visible warning -> spikes out (hurts the player) -> retract.
## Only the player hurtbox is targeted, enemies walk over it safely.

enum Phase { IDLE, WARN, ACTIVE }

const SIZE := 52.0
const IDLE_TIME := 2.2
const WARN_TIME := 0.6
const ACTIVE_TIME := 0.7
const DAMAGE := 1.0
const PLATE_COLOR := Color(0.18, 0.16, 0.22)
const HOLE_COLOR := Color(0.07, 0.06, 0.09)
const SPIKE_COLOR := Color(0.82, 0.82, 0.9)
const WARN_COLOR := Color(1.0, 0.3, 0.2, 0.35)
## Frames: retracted / warning / extended (docs/design/sprites/delivered/SPRITES_V2.md §2). Replaces the drawing if present.
const ART_PATH := "res://art/environment/props/spike_trap_3f.png"

var _phase := Phase.IDLE
var _time_left := 0.0
var _hitbox: Hitbox = null
var _sprite: Sprite2D = null


func _ready() -> void:
	z_index = -9
	if ResourceLoader.exists(ART_PATH):
		_sprite = Sprite2D.new()
		_sprite.texture = load(ART_PATH)
		_sprite.hframes = 3
		_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		add_child(_sprite)
	if Engine.is_editor_hint():
		return
	_time_left = randf_range(0.5, IDLE_TIME)
	_hitbox = Hitbox.new()
	_hitbox.collision_layer = 0
	_hitbox.collision_mask = PhysicsLayers.PLAYER_HURTBOX
	var shape := RectangleShape2D.new()
	shape.size = Vector2(SIZE, SIZE)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	_hitbox.add_child(collision)
	add_child(_hitbox)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_time_left -= delta
	if _time_left > 0.0:
		return
	match _phase:
		Phase.IDLE:
			_phase = Phase.WARN
			_time_left = WARN_TIME
		Phase.WARN:
			_phase = Phase.ACTIVE
			_time_left = ACTIVE_TIME
			var damage := DamageData.new()
			damage.amount = DAMAGE
			damage.tags.assign([&"trap"])
			_hitbox.begin_attack(damage)
			Sfx.play_at(self, &"trap", global_position, -4.0)
		Phase.ACTIVE:
			_phase = Phase.IDLE
			_time_left = IDLE_TIME
			_hitbox.end_attack()
	queue_redraw()


func is_active() -> bool:
	return _phase == Phase.ACTIVE


func _draw() -> void:
	if _sprite != null:
		_sprite.frame = _phase
		_sprite.modulate = Color(1.5, 0.85, 0.75) if _phase == Phase.WARN else Color.WHITE
		return
	# Pixel art (D-218): holes and spikes from whole art pixels.
	var half := SIZE * 0.5
	PixelDraw.rect(self, Rect2(-half, -half, SIZE, SIZE), PLATE_COLOR)
	if _phase == Phase.WARN:
		PixelDraw.rect(self, Rect2(-half, -half, SIZE, SIZE), WARN_COLOR)
	var step := SIZE / 3.0
	for gx in 3:
		for gy in 3:
			var center := Vector2(-half + step * (gx + 0.5), -half + step * (gy + 0.5))
			PixelDraw.disc(self, center, 3.0, HOLE_COLOR)
			var height := 0.0
			if _phase == Phase.WARN:
				height = 3.0
			elif _phase == Phase.ACTIVE:
				height = 11.0
			if height > 0.0:
				PixelDraw.polygon(self, PackedVector2Array([center + Vector2(-4, 2), center + Vector2(4, 2), center + Vector2(0, -height)]), SPIKE_COLOR)

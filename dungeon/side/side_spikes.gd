class_name SideSpikes
extends Node2D
## Floor spikes of a side segment (M5), timed like the room spike trap (D-069): rest, a visible
## warning, spikes out (hurt the player, shield first), back in. Enemies are never hurt. The node
## origin is the floor line in the middle of its tile. Drawn as a placeholder until
## art/environment/side/spikes_side_3f.png (SPRITES_V9) exists.

enum Phase { IDLE, WARN, ACTIVE }

## TESTWERTE
const IDLE_TIME := 1.6
const WARN_TIME := 0.5
const ACTIVE_TIME := 0.9
const DAMAGE := 1.0
const WIDTH := 56.0
const HEIGHT := 24.0
const ART_PATH := "res://art/environment/side/spikes_side_3f.png"
const BASE_COLOR := Color(0.2, 0.18, 0.24)
const SPIKE_COLOR := Color(0.82, 0.82, 0.9)
const WARN_COLOR := Color(1.0, 0.35, 0.25)
const SPIKES := 5

var phase := Phase.IDLE

var _time_left := IDLE_TIME
var _hitbox: Hitbox = null
var _sprite: Sprite2D = null


## Start offset in seconds so several traps do not fire together.
func setup(offset: float) -> void:
	_time_left = clampf(offset, 0.1, IDLE_TIME)


func _ready() -> void:
	z_index = -1
	if ResourceLoader.exists(ART_PATH):
		_sprite = Sprite2D.new()
		_sprite.texture = load(ART_PATH)
		_sprite.hframes = 3
		_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		_sprite.offset = Vector2(0, -_sprite.texture.get_height() * 0.5)
		add_child(_sprite)
	_hitbox = Hitbox.new()
	_hitbox.name = "Hitbox"
	_hitbox.collision_layer = 0
	_hitbox.collision_mask = PhysicsLayers.PLAYER_HURTBOX
	var shape := RectangleShape2D.new()
	shape.size = Vector2(WIDTH, HEIGHT)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0, -HEIGHT * 0.5)
	_hitbox.add_child(collision)
	add_child(_hitbox)


func _physics_process(delta: float) -> void:
	_time_left -= delta
	if _time_left > 0.0:
		return
	match phase:
		Phase.IDLE:
			phase = Phase.WARN
			_time_left = WARN_TIME
		Phase.WARN:
			phase = Phase.ACTIVE
			_time_left = ACTIVE_TIME
			var damage := DamageData.new()
			damage.amount = DAMAGE
			damage.tags.assign([&"trap"])
			_hitbox.begin_attack(damage)
			Sfx.play_at(self, &"trap", global_position, -6.0)
		Phase.ACTIVE:
			phase = Phase.IDLE
			_time_left = IDLE_TIME
			_hitbox.end_attack()
	queue_redraw()


func is_active() -> bool:
	return phase == Phase.ACTIVE


func _draw() -> void:
	if _sprite != null:
		_sprite.frame = phase
		return
	var half := WIDTH * 0.5
	draw_rect(Rect2(-half, -5.0, WIDTH, 5.0), BASE_COLOR)
	var height := 5.0
	var color := SPIKE_COLOR
	if phase == Phase.WARN:
		height = 9.0
		color = WARN_COLOR
	elif phase == Phase.ACTIVE:
		height = HEIGHT
	var step := WIDTH / SPIKES
	for i in SPIKES:
		var x := -half + step * (i + 0.5)
		draw_colored_polygon(PackedVector2Array([Vector2(x - step * 0.4, -4.0), Vector2(x + step * 0.4, -4.0), Vector2(x, -4.0 - height)]), color)

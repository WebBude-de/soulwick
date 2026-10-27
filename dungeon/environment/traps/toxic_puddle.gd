@tool
class_name ToxicPuddle
extends Node2D
## Slime-grotto floor hazard (D-075): while the player stands in it they are slowed
## and take small poison damage at a fixed interval. Enemies are not affected (it is their home).
## Code-drawn bubbling puddle; art/environment/props/toxic_puddle_4f.png replaces it when present.

const RADIUS := 44.0
const SLOW_FACTOR := 0.6
const TICK_INTERVAL := 1.1
const DAMAGE := 0.5
const ART_PATH := "res://art/environment/props/toxic_puddle_4f.png"
const BASE_COLOR := Color(0.25, 0.75, 0.2, 0.75)
const RIM_COLOR := Color(0.55, 1.0, 0.35, 0.9)
const BUBBLE_COLOR := Color(0.75, 1.0, 0.55, 0.9)
## Player speed modifiers: meta keys on the player while no speed-modifier API exists.
const META_SLOWS := &"hazard_slows"
const META_BASE_SPEED := &"hazard_base_speed"
const SLOW_SOURCE := &"toxic_puddle"

var _hitbox: Hitbox = null
var _tick_left := 0.0
var _time := 0.0
var _slowed: Player = null
var _seed := 0.0
var _sprite: AnimatedSprite2D = null


func _ready() -> void:
	z_index = -9
	_seed = randf() * 10.0
	if Engine.is_editor_hint():
		return
	_hitbox = Hitbox.new()
	_hitbox.collision_layer = 0
	_hitbox.collision_mask = PhysicsLayers.PLAYER_HURTBOX
	var shape := CircleShape2D.new()
	shape.radius = RADIUS * 0.85
	var collision := CollisionShape2D.new()
	collision.shape = shape
	_hitbox.add_child(collision)
	add_child(_hitbox)
	var glow := LightSource.new()
	glow.radius = RADIUS * 1.1
	glow.intensity = 0.35
	glow.flicker = 0.08
	add_child(glow)
	if ResourceLoader.exists(ART_PATH):
		_sprite = AnimatedSprite2D.new()
		_sprite.sprite_frames = SpriteStrip.make_frames(load(ART_PATH), Vector2i(32, 32), 5.0, true)
		# 32 px art at 3x (whole pixels) roughly covers the 88 px puddle.
		_sprite.scale = Vector2.ONE * 3.0
		_sprite.play(&"default")
		add_child(_sprite)


func _exit_tree() -> void:
	_set_slowed(null)


func _physics_process(delta: float) -> void:
	_time += delta
	if Engine.is_editor_hint():
		queue_redraw()
		return
	var player := _get_player_inside()
	_set_slowed(player)
	if player == null:
		_tick_left = 0.0
		if _hitbox.is_active():
			_hitbox.end_attack()
	else:
		_tick_left -= delta
		if _tick_left <= 0.0:
			_tick_left = TICK_INTERVAL
			# A fresh attack hits again once (respects dash and hit I-frames).
			_hitbox.end_attack()
			var damage := DamageData.new()
			damage.amount = DAMAGE
			damage.tags.assign([&"trap", &"poison"])
			_hitbox.begin_attack(damage)
			Burst.spawn(get_parent(), player.global_position, BUBBLE_COLOR, 6, 60.0, 0.4, 3.0)
	queue_redraw()


func is_slowing() -> bool:
	return _slowed != null


func _get_player_inside() -> Player:
	for area in _hitbox.get_overlapping_areas():
		if area is Hurtbox and area.get_parent() is Player and (area.get_parent() as Player).is_alive():
			return area.get_parent() as Player
	return null


func _set_slowed(player: Player) -> void:
	if player == _slowed:
		return
	if _slowed != null and is_instance_valid(_slowed):
		apply_slow(_slowed, get_instance_id(), 1.0)
	_slowed = player
	if player != null:
		apply_slow(player, get_instance_id(), SLOW_FACTOR)


## Sets (factor < 1) or clears (factor >= 1) one slow source on the player. Uses
## Player.set_speed_modifier(source, factor) if it exists; otherwise scales move_speed and keeps
## the original value as meta until the last source is gone.
static func apply_slow(player: Player, source_id: int, factor: float) -> void:
	if player.has_method(&"set_speed_modifier"):
		player.call(&"set_speed_modifier", StringName("%s_%d" % [SLOW_SOURCE, source_id]), factor)
		return
	var slows: Dictionary = player.get_meta(META_SLOWS, {})
	if not player.has_meta(META_BASE_SPEED):
		player.set_meta(META_BASE_SPEED, player.move_speed)
	var base: float = player.get_meta(META_BASE_SPEED)
	if factor >= 1.0:
		slows.erase(source_id)
	else:
		slows[source_id] = factor
	var strongest := 1.0
	for value: float in slows.values():
		strongest = minf(strongest, value)
	player.move_speed = base * strongest
	if slows.is_empty():
		player.remove_meta(META_SLOWS)
		player.remove_meta(META_BASE_SPEED)
	else:
		player.set_meta(META_SLOWS, slows)


func _draw() -> void:
	if _sprite != null:
		return
	# Irregular blob out of a few overlapping pixel discs, slowly breathing (pixel art, D-218).
	var wobble := 1.0 + 0.04 * sin(_time * 2.0 + _seed)
	PixelDraw.disc(self, Vector2.ZERO, RADIUS * wobble, BASE_COLOR)
	PixelDraw.disc(self, Vector2(RADIUS * 0.45, -RADIUS * 0.2), RADIUS * 0.6 * wobble, BASE_COLOR)
	PixelDraw.disc(self, Vector2(-RADIUS * 0.5, RADIUS * 0.15), RADIUS * 0.55 * wobble, BASE_COLOR)
	PixelDraw.ring(self, Vector2.ZERO, RADIUS * wobble, RIM_COLOR)
	for i in 4:
		var phase := fmod(_time * 0.8 + i * 0.27 + _seed, 1.0)
		var spot := Vector2.from_angle(i * 1.9 + _seed) * RADIUS * (0.2 + 0.15 * i)
		PixelDraw.disc(self, spot, 2.0 + 4.0 * phase, Color(BUBBLE_COLOR, PixelDraw.stepped(1.0 - phase, 3)))

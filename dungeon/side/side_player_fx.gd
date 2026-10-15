class_name SidePlayerFx
extends Node
## The look of one player's moves in a side segment (M5 round 2), driven only by the signals of
## PlayerSideMotion (decision and effect stay apart): stretch at the take-off, a salto and a dust
## ring at the double jump, squash, dust and a landing sound at every landing, a camera kick at hard
## landings, crumbs and a scrape at a wall slide. Squash and stretch scale the player's body sprite
## around the feet; everything is put back when the player leaves the segment (detach).

## TESTWERTE (look)
const TAKE_OFF_STRETCH := Vector2(0.8, 1.22)
const DOUBLE_JUMP_STRETCH := Vector2(0.86, 1.16)
const WALL_JUMP_STRETCH := Vector2(0.84, 1.18)
## Strongest landing squash (x wider, y lower) at a hard landing.
const MAX_LAND_SQUASH := 0.32
const SQUASH_RETURN_SPEED := 14.0
const SALTO_TIME := 0.32
## Camera kick (px down) for a hard landing, scaled up to the maximum fall speed.
const LAND_KICK := Vector2(8.0, 16.0)
const SLIDE_DUST_INTERVAL := 0.09
const SLIDE_SOUND_INTERVAL := 0.32

var player: Player = null
var segment: SideSegment = null

var _sprite: AnimatedSprite2D = null
var _base_scale := Vector2.ONE
var _base_position := Vector2.ZERO
var _base_rotation := 0.0
var _stretch := Vector2.ONE
var _salto_left := 0.0
var _salto_direction := 1.0
var _slide_dust_left := 0.0
var _slide_sound_left := 0.0


static func attach(target: Player, owner_segment: SideSegment) -> SidePlayerFx:
	var fx := SidePlayerFx.new()
	fx.name = "SideFx"
	fx.player = target
	fx.segment = owner_segment
	owner_segment.add_child(fx)
	fx._connect()
	return fx


func _connect() -> void:
	_sprite = player.get_node_or_null("Sprite") as AnimatedSprite2D
	if _sprite != null:
		_base_scale = _sprite.scale
		_base_position = _sprite.position
		_base_rotation = _sprite.rotation
	var motion := player.side_motion
	motion.jumped.connect(_on_jumped)
	motion.double_jumped.connect(_on_double_jumped)
	motion.wall_jumped.connect(_on_wall_jumped)
	motion.landed.connect(_on_landed)
	motion.fell_into_pit.connect(_on_fell_into_pit)
	motion.returned.connect(_on_returned)


## Puts the sprite back and lets go of the motion's signals.
func detach() -> void:
	if is_instance_valid(player) and player.side_motion != null:
		var motion := player.side_motion
		for connection: Array in [[motion.jumped, _on_jumped], [motion.double_jumped, _on_double_jumped],
				[motion.wall_jumped, _on_wall_jumped], [motion.landed, _on_landed],
				[motion.fell_into_pit, _on_fell_into_pit], [motion.returned, _on_returned]]:
			var sig: Signal = connection[0]
			if sig.is_connected(connection[1]):
				sig.disconnect(connection[1])
	if is_instance_valid(_sprite):
		_sprite.scale = _base_scale
		_sprite.position = _base_position
		_sprite.rotation = _base_rotation
	queue_free()


## Current squash/stretch factor of the body (tests).
func get_stretch() -> Vector2:
	return _stretch


func is_spinning() -> bool:
	return _salto_left > 0.0


func _process(delta: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(_sprite):
		return
	_stretch = _stretch.lerp(Vector2.ONE, 1.0 - exp(-SQUASH_RETURN_SPEED * delta))
	var rotation := 0.0
	if _salto_left > 0.0:
		_salto_left = maxf(0.0, _salto_left - delta)
		var progress := 1.0 - _salto_left / SALTO_TIME
		rotation = _salto_direction * TAU * ease(progress, -1.6)
	# Scale around the feet: the feet stay on the ground while the body squashes.
	_sprite.scale = _base_scale * _stretch
	_sprite.position = _base_position + Vector2(0.0, Player.FEET_OFFSET.y * (1.0 - _stretch.y))
	_sprite.rotation = _base_rotation + rotation
	var motion := player.side_motion
	if motion != null and motion.is_wall_sliding:
		_slide_dust_left -= delta
		_slide_sound_left -= delta
		var wall := Vector2(motion.wall_side * PlayerSideMotion.BODY_SIZE.x * 0.5, -6.0)
		if _slide_dust_left <= 0.0:
			_slide_dust_left = SLIDE_DUST_INTERVAL
			SideDust.spawn(segment, player.global_position + wall, SideDust.Kind.SLIDE, 0.5, motion.wall_side)
		if _slide_sound_left <= 0.0:
			_slide_sound_left = SLIDE_SOUND_INTERVAL
			Sfx.play_at(segment, SideRules.sound_or(SideRules.SOUND_WALL_SLIDE, &"stone_grind"), player.global_position, -18.0)
	else:
		_slide_dust_left = 0.0
		_slide_sound_left = 0.0


func _on_jumped(_who: Player) -> void:
	_stretch = TAKE_OFF_STRETCH
	SideDust.spawn(segment, player.get_feet_position(), SideDust.Kind.PUFF, 0.4)
	Sfx.play_at(segment, SideRules.sound_or(SideRules.SOUND_JUMP, SideRules.SOUND_JUMP_FALLBACK), player.global_position, -10.0)


func _on_double_jumped(_who: Player) -> void:
	_stretch = DOUBLE_JUMP_STRETCH
	_salto_left = SALTO_TIME
	_salto_direction = player.side_motion.facing
	SideDust.spawn(segment, player.get_feet_position(), SideDust.Kind.RING, 0.6)
	Sfx.play_at(segment, SideRules.sound_or(SideRules.SOUND_DOUBLE_JUMP, SideRules.SOUND_JUMP_FALLBACK), player.global_position, -8.0)


func _on_wall_jumped(_who: Player) -> void:
	_stretch = WALL_JUMP_STRETCH
	var away := player.side_motion.facing
	SideDust.spawn(segment, player.global_position + Vector2(-away * PlayerSideMotion.BODY_SIZE.x * 0.5, 0.0), SideDust.Kind.PUFF, 0.5, away)
	Sfx.play_at(segment, SideRules.sound_or(SideRules.SOUND_JUMP, SideRules.SOUND_JUMP_FALLBACK), player.global_position, -9.0)


func _on_landed(_who: Player, fall_speed: float) -> void:
	var hard := fall_speed >= SideRules.HARD_LANDING_SPEED
	var strength := clampf((fall_speed - 200.0) / (SideRules.MAX_FALL_SPEED - 200.0), 0.15, 1.0)
	var squash := MAX_LAND_SQUASH * strength
	_stretch = Vector2(1.0 + squash, 1.0 - squash)
	_salto_left = 0.0
	SideDust.spawn(segment, player.get_feet_position(), SideDust.Kind.CLOUD, strength)
	var sound := SideRules.SOUND_LAND_HARD if hard else SideRules.SOUND_LAND
	Sfx.play_at(segment, SideRules.sound_or(sound, SideRules.SOUND_LAND_FALLBACK), player.get_feet_position(), -6.0 if hard else -12.0)
	if hard and segment.camera != null:
		segment.camera.kick(Vector2(0.0, lerpf(LAND_KICK.x, LAND_KICK.y, strength)))


func _on_fell_into_pit(_who: Player) -> void:
	_salto_left = 0.0
	_stretch = Vector2.ONE
	Sfx.play_at(segment, ChasmRules.fall_sound(), player.global_position, -4.0)


func _on_returned(_who: Player, _damage: float) -> void:
	_stretch = Vector2(1.2, 0.8)
	Burst.spawn(segment, player.global_position, Color(0.8, 0.75, 1.0), 10, 110.0, 0.4, 3.0)

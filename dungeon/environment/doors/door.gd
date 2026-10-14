class_name Door
extends StaticBody2D
## One-tile door on the world layer. Node origin = top-left corner of its tile.

const CLOSED_TEXTURE: Texture2D = preload("res://art/environment/props/door_closed.png")
const OPENING_TEXTURE: Texture2D = preload("res://art/environment/props/door_open_4f.png")

var is_open := false

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	var frames := SpriteStrip.make_frames(CLOSED_TEXTURE, Vector2i(32, 32), 1.0, false, &"closed")
	SpriteStrip.add_strip(frames, &"open", OPENING_TEXTURE, Vector2i(32, 32), 8.0, false)
	_sprite.sprite_frames = frames
	_apply(is_open, true)


func open() -> void:
	_apply(true, false)


func close() -> void:
	_apply(false, false)


func set_open_instant(value: bool) -> void:
	_apply(value, true)


func _apply(value: bool, instant: bool) -> void:
	is_open = value
	if not is_node_ready():
		return
	_shape.set_deferred("disabled", value)
	if value:
		_sprite.play(&"open")
		if instant:
			_sprite.frame = _sprite.sprite_frames.get_frame_count(&"open") - 1
	else:
		_sprite.play(&"closed")

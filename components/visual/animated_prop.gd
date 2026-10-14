@tool
class_name AnimatedProp
extends AnimatedSprite2D
## Looping prop animation built from a single sprite strip (torch, coin, portal, merchant).

@export var strip: Texture2D:
	set(value):
		strip = value
		_rebuild()
@export var frame_size := Vector2i(32, 32):
	set(value):
		frame_size = value
		_rebuild()
@export var fps := 8.0:
	set(value):
		fps = value
		_rebuild()
## Pivot in frame pixels that sits on the node origin.
@export var pivot := Vector2(16, 31):
	set(value):
		pivot = value
		_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if strip == null:
		return
	sprite_frames = SpriteStrip.make_frames(strip, frame_size, fps, true)
	offset = SpriteStrip.pivot_offset(frame_size, pivot)
	play(&"default")

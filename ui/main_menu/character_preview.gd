class_name CharacterPreview
extends Control
## A character standing idle at a whole-number pixel scale, recoloured live (slot cards, create
## dialog). The sprite is centred in the control; feet sit on the bottom edge.

## Frame size of character sprites in art pixels (HANDOUT: figures 32×32, feet at y = 29).
const FRAME_SIZE := 32.0
const FEET_Y := 30.0

var _sprite: AnimatedSprite2D = null
var _art_scale := 1
var _shadow: ColorRect = null


static func create(art_scale: int, with_shadow := true) -> CharacterPreview:
	var preview := CharacterPreview.new()
	preview._art_scale = maxi(1, art_scale)
	preview.custom_minimum_size = Vector2.ONE * FRAME_SIZE * preview._art_scale
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if with_shadow:
		preview._shadow = ColorRect.new()
		preview._shadow.color = Color(UiKit.COLOR_SHADOW, 0.55)
		preview._shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.add_child(preview._shadow)
	preview._sprite = AnimatedSprite2D.new()
	preview._sprite.centered = false
	preview._sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview._sprite.scale = Vector2.ONE * preview._art_scale
	preview.add_child(preview._sprite)
	preview.resized.connect(preview._layout)
	return preview


func set_character(data: CharacterData, color: Color) -> void:
	if data == null:
		return
	data.apply_to(_sprite, color)
	if not _sprite.is_playing() or _sprite.animation != &"idle":
		_sprite.play(&"idle")
	_layout()


func set_color(color: Color) -> void:
	CharacterData.set_tint_color(_sprite, color)


func get_sprite() -> AnimatedSprite2D:
	return _sprite


func _layout() -> void:
	var frame := FRAME_SIZE * _art_scale
	var origin := Vector2(floorf((size.x - frame) * 0.5), floorf(size.y - frame))
	_sprite.position = origin
	if _shadow != null:
		# Flat 14×2 shadow under the feet.
		var width := 14.0 * _art_scale
		_shadow.size = Vector2(width, 2.0 * _art_scale)
		_shadow.position = Vector2(floorf((size.x - width) * 0.5), origin.y + (FEET_Y - 2.0) * _art_scale)

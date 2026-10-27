class_name FlintAura
extends Node2D
## Flint's soft warm glow (D-217, FlintShine): a child of his sprite drawn behind it
## (show_behind_parent) and centred on his flame (FlintCompanion moves it with the frame's anchor),
## breathing like the website's `.wick-glow`. Added like light (BLEND_MODE_ADD), so it warms the
## ground around him in the bright village and glows in the dungeon, never paints the figure itself.
## It inherits the sprite's scale (art pixels), rotation and alpha (excursion, see-through over
## enemies). Optics only.

## TESTWERT: radius of the glow in art pixels of the sprite (x PIXEL_SCALE in the world).
const RADIUS := 22.0

## Seconds of breathing so far (FlintCompanion reads it to let his light breathe along).
var time := 0.0


func _init() -> void:
	name = "FlintAura"
	show_behind_parent = true
	# The gradient stays soft although the figure is drawn with nearest filtering.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


func _draw() -> void:
	FlintShine.draw_glow(self, Vector2.ZERO, RADIUS, time)

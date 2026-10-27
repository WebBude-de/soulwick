class_name PixelVignette
extends Control
## Full-rect vignette in hard bands on the UI art-pixel grid (D-218): replaces a TextureRect with a
## smooth radial GradientTexture2D. ramp runs from the centre (offset 0) to the corners (offset 1)
## like FILL_RADIAL from the centre to a corner; steps bands of pixel cells (PixelDraw.radial_bands).
## Drawn once and on resize only; fade it with modulate. Optics only.

## Colour from the centre (0) to the corners (1).
var ramp: Gradient = null:
	set(value):
		ramp = value
		queue_redraw()
var steps := 5
## Screen px per art pixel (UiKit.ART_SCALE in the UI).
var pixel := float(UiKit.ART_SCALE)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	if ramp != null:
		PixelDraw.radial_bands(self, Rect2(Vector2.ZERO, size), ramp, steps, pixel)

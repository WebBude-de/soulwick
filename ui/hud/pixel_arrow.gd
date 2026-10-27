class_name PixelArrow
extends RefCounted
## The arrow of the co-op hints in pixel style (feedback #a1a651ae 23.10.2026 "Der Pfeil sollte auch
## Pixel-Style sein"): the delivered 16 px teammate arrow (art/ui/teammate_arrow.png, white with a
## #1c1a2b outline, pointing right; tinted with modulate) turned into DIRECTIONS steps with nearest
## sampling, so every turned picture is still whole art pixels without smoothing; drawn upscaled by
## UiKit.ART_SCALE with nearest filtering. Used by the wait arrow (CoopWaitLine) and the arrows to
## mates off screen (MatePointers). Without the file a code-drawn pixel arrow of the same shape.

const ART_PATH := "res://art/ui/teammate_arrow.png"
## Turned pictures per full circle (22.5 degree steps).
const DIRECTIONS := 16
## Canvas of a turned picture (art px): room for the 16 px arrow at any angle.
const CANVAS := 24
const OUTLINE := Color("#1c1a2b")

static var _cache: Array[Texture2D] = []


## The picture pointing closest to angle (radians, 0 = right), art size CANVAS x CANVAS.
static func texture_for(angle: float) -> Texture2D:
	if _cache.is_empty():
		_build()
	return _cache[direction_index(angle)]


## Which of the DIRECTIONS pictures points closest to angle.
static func direction_index(angle: float) -> int:
	var step := TAU / DIRECTIONS
	return posmod(roundi(angle / step), DIRECTIONS)


## Size on screen of a picture (CANVAS art px times UiKit.ART_SCALE).
static func screen_size() -> Vector2:
	return Vector2.ONE * CANVAS * UiKit.ART_SCALE


## The source picture: the delivered arrow or the code arrow.
static func source_image() -> Image:
	if ResourceLoader.exists(ART_PATH):
		var texture := load(ART_PATH) as Texture2D
		if texture != null:
			var image := texture.get_image()
			if image != null:
				if image.is_compressed():
					image.decompress()
				image.convert(Image.FORMAT_RGBA8)
				return image
	return placeholder_image()


## A 16 px pixel arrow pointing right, white with outline (the shape of teammate_arrow.png).
static func placeholder_image() -> Image:
	var image := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		var reach := 13 - floori(absi(y * 2 - 15) / 2.0)
		for x in range(2, reach + 1):
			image.set_pixel(x, y, OUTLINE if x == 2 or x == reach or y == 0 or y == 15 else Color.WHITE)
	return image


## source turned by angle around its middle, nearest sampling (no new colours), on a CANVAS canvas.
static func turned(source: Image, angle: float) -> Image:
	var image := Image.create_empty(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	var middle := Vector2(CANVAS, CANVAS) * 0.5
	var source_middle := Vector2(source.get_width(), source.get_height()) * 0.5
	for y in CANVAS:
		for x in CANVAS:
			var from := (Vector2(x, y) + Vector2(0.5, 0.5) - middle).rotated(-angle) + source_middle
			var sx := floori(from.x)
			var sy := floori(from.y)
			if sx >= 0 and sy >= 0 and sx < source.get_width() and sy < source.get_height():
				image.set_pixel(x, y, source.get_pixel(sx, sy))
	return image


static func _build() -> void:
	var source := source_image()
	for i in DIRECTIONS:
		_cache.append(ImageTexture.create_from_image(turned(source, TAU * i / DIRECTIONS)))

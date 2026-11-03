extends RefCounted
## Level of a forge or trade row as pixel pips (FS7a, reports #e0d2989d/#f6fe6427): one square per
## level, gold up to the reached level, dark after it ("Stufe 2/5" = ■■□□□), instead of the small
## "Stufe 0/5" line under the name that made every row two lines high. The tooltip keeps the text.
## Drawn in code (no art file needed); preload: const LevelPips := preload(…).

## Pip size and gap in art pixels (upscaled by UiKit.ART_SCALE like all UI art).
const PIP := 4
const GAP := 1
const FILLED := UiKit.COLOR_GOLD
const EMPTY := UiKit.COLOR_LINE
const EMPTY_EDGE := UiKit.COLOR_EMPTY_SLOT

static var _textures: Dictionary = {}


## The pips of level out of max_level as a TextureRect (named LevelPips, tooltip "Stufe 2/5").
static func create(level: int, max_level: int) -> TextureRect:
	var texture := texture_for(level, max_level)
	var rect := TextureRect.new()
	rect.name = "LevelPips"
	rect.texture = texture
	# Left-aligned in its column (the column is as wide as five pips).
	rect.stretch_mode = TextureRect.STRETCH_KEEP
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rect.mouse_filter = Control.MOUSE_FILTER_PASS
	rect.tooltip_text = Loc.t(&"VILLAGE_UI_LEVEL", [clampi(level, 0, max_level), max_level])
	return rect


## The upscaled pip strip (cached); an empty 1×1 texture for max_level < 1.
static func texture_for(level: int, max_level: int) -> Texture2D:
	var count := maxi(0, max_level)
	var filled := clampi(level, 0, count)
	var key := "%d/%d" % [filled, count]
	if _textures.has(key):
		return _textures[key]
	var width := maxi(1, count * (PIP + GAP) - GAP)
	var image := Image.create(width, PIP, false, Image.FORMAT_RGBA8)
	for index in count:
		var left := index * (PIP + GAP)
		for y in PIP:
			for x in PIP:
				image.set_pixel(left + x, y, _pip_color(index < filled, x, y))
	var texture := UiKit.upscale(ImageTexture.create_from_image(image))
	_textures[key] = texture
	return texture


## Filled: gold with a darker bottom row; empty: dark with a lighter frame.
static func _pip_color(filled: bool, x: int, y: int) -> Color:
	if filled:
		return FILLED.darkened(0.3) if y == PIP - 1 else FILLED
	var edge := x == 0 or y == 0 or x == PIP - 1 or y == PIP - 1
	return EMPTY_EDGE if edge else EMPTY

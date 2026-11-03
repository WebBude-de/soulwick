class_name SideTilt
extends SideCrumble
## A tilting platform of the jump trial (Kippplattform, SV2, D-195, plan "//"): two tiles wide, it
## wobbles as soon as a player stands on it, tips over after SideElementRules.TILT_DELAY seconds
## and falls, and is back after TILT_RESPAWN once nobody is in the way. A SideCrumble with its own
## timing and look, so the decision, the co-op sync (NetSide via SideSegment.get_crumbles) and the
## tests are the crumble's. Art: tilt_platform_<biome>_4f.png (4 frames side by side: still,
## wobbling, tipping, falling; delivered 64×16, any height works, pivot in the middle), else the
## ledge pieces tinted darker. The picture is lifted by the empty rows above its
## slab (SidePixels.surface_row), so the feet stand on the drawn top (FS1).
## Pixel look (D-218, feedback #e0486234 "wenn die Plattform kaputt geht ist die Textur verbuggt"):
## the sprite is never rotated (a turned picture leaves the art-pixel grid); the wobble is the
## crumble's shake in whole pixels, the tilt comes from the frames. A delivered frame cut off at the
## top and bottom edge of its frame (the tipping and falling frames of the first delivery) is replaced
## by the still slab sheared column by column (whole pixels, SHEAR_TIPPING / SHEAR_FALLING), in a
## picture high enough for the whole slab.

const ART_PATH := "res://art/environment/side/tilt_platform_%s_4f.png"
## Frame of the first delivery (the real size comes from the sheet: frame_size).
const ART_FRAME := Vector2i(64, 16)
const ART_FRAMES := 4
const FRAME_STILL := 0
const FRAME_WOBBLE := 1
const FRAME_TIPPING := 2
const FRAME_FALLING := 3
## Slope (art pixels down per pixel to the right) of the sheared stand-in frames (TESTWERT, look).
const SHEAR_TIPPING := 0.2
const SHEAR_FALLING := 0.45
const PLACEHOLDER_TINT := Color(0.8, 0.72, 0.62)
## Surface row of the delivered art when the picture cannot be read.
const SURFACE_ROW_FALLBACK := 4

## "<sheet path>|<frame>" -> sheared stand-in picture (null = the delivered frame fits).
static var _stand_ins: Dictionary = {}

var _sprite: Sprite2D = null
var _sheet: Texture2D = null


func shake_time() -> float:
	return SideElementRules.TILT_DELAY


func respawn_time() -> float:
	return SideElementRules.TILT_RESPAWN


func _build_look() -> void:
	var path := ART_PATH % biome_id
	if not ResourceLoader.exists(path):
		path = ART_PATH % SideTiles.FALLBACK_BIOME
	if ResourceLoader.exists(path):
		_sheet = load(path) as Texture2D
		_sprite = Sprite2D.new()
		_sprite.name = "Art"
		_sprite.texture = _sheet
		_sprite.hframes = ART_FRAMES
		_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		# Pivot (middle) of the art = the middle of the two cells' top strip, lifted to the slab.
		var frame := frame_size(_sheet)
		var lift := SidePixels.surface_row(_sheet, Rect2i(Vector2i.ZERO, frame), SURFACE_ROW_FALLBACK)
		_sprite.position = Vector2(cells * SideRules.TILE * 0.5, (frame.y * 0.5 - lift) * SpriteStrip.PIXEL_SCALE)
		_pieces.add_child(_sprite)
		return
	super._build_look()
	_pieces.modulate = PLACEHOLDER_TINT


func _look_step() -> void:
	if _sprite == null:
		return
	match state:
		State.SOLID:
			_show_frame(FRAME_STILL)
		State.SHAKING:
			_show_frame(FRAME_WOBBLE if shake_progress() < 0.5 else FRAME_TIPPING)
		State.FALLEN:
			_show_frame(FRAME_FALLING)


## Shows a frame of the sheet, or its sheared stand-in when the delivered one is cut off.
func _show_frame(frame: int) -> void:
	var stand_in := stand_in_for(_sheet, frame)
	if stand_in == null:
		if _sprite.texture != _sheet:
			_sprite.texture = _sheet
			_sprite.hframes = ART_FRAMES
		_sprite.frame = frame
		return
	if _sprite.texture != stand_in:
		_sprite.hframes = 1
		_sprite.frame = 0
		_sprite.texture = stand_in


## The picture shown for a frame (tests): the sheet's frame or the stand-in.
func get_frame_picture() -> Image:
	if _sprite == null:
		return null
	var image := _sprite.texture.get_image()
	if _sprite.hframes > 1:
		var frame := frame_size(_sheet)
		image = image.get_region(Rect2i(_sprite.frame * frame.x, 0, frame.x, frame.y))
	return image


## Size of one frame of sheet (the sheet holds ART_FRAMES side by side).
static func frame_size(sheet: Texture2D) -> Vector2i:
	if sheet == null:
		return ART_FRAME
	return Vector2i(floori(sheet.get_width() / float(ART_FRAMES)), sheet.get_height())


## Whether frame of sheet runs into the top and the bottom edge (a slab cut off by the frame).
static func is_cut_off(sheet: Texture2D, frame: int) -> bool:
	var image := _sheet_image(sheet)
	if image == null:
		return false
	var size := frame_size(sheet)
	var region := Rect2i(frame * size.x, 0, size.x, size.y)
	return _row_has_pixels(image, region, 0) and _row_has_pixels(image, region, size.y - 1)


## Stand-in for a cut-off tipping or falling frame: the still slab sheared in whole art pixels around
## its middle column, in a picture tall enough for all of it (same width, same middle). null when the
## delivered frame fits or is no tipping/falling frame.
static func stand_in_for(sheet: Texture2D, frame: int) -> Texture2D:
	if sheet == null or (frame != FRAME_TIPPING and frame != FRAME_FALLING):
		return null
	var key := "%s|%d" % [sheet.resource_path, frame]
	if _stand_ins.has(key):
		return _stand_ins[key]
	var texture: Texture2D = null
	if is_cut_off(sheet, frame):
		var image := sheared(_sheet_image(sheet).get_region(Rect2i(Vector2i.ZERO, frame_size(sheet))),
				SHEAR_TIPPING if frame == FRAME_TIPPING else SHEAR_FALLING)
		texture = ImageTexture.create_from_image(image)
	_stand_ins[key] = texture
	return texture


## image sheared column by column: column x moves down by round((x - middle) * slope) whole pixels;
## the result is taller by twice the largest shift, so the middle row stays in the middle.
static func sheared(image: Image, slope: float) -> Image:
	var middle := image.get_width() >> 1
	var reach := ceili(absf(slope) * middle)
	var result := Image.create_empty(image.get_width(), image.get_height() + reach * 2, false, Image.FORMAT_RGBA8)
	for x in image.get_width():
		var shift := roundi((x - middle) * slope)
		for y in image.get_height():
			result.set_pixel(x, y + reach + shift, image.get_pixel(x, y))
	return result


static func _sheet_image(sheet: Texture2D) -> Image:
	if sheet == null:
		return null
	var image := sheet.get_image()
	if image == null or image.is_empty():
		return null
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image


static func _row_has_pixels(image: Image, region: Rect2i, row: int) -> bool:
	for x in range(region.position.x, region.end.x):
		if image.get_pixel(x, region.position.y + row).a > 0.0:
			return true
	return false

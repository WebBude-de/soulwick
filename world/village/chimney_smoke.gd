class_name ChimneySmoke
extends CPUParticles2D
## Slow grey smoke puffs from a chimney (B3). Placed by tools/generate_village.py at the chimney top
## of a building sprite. Puffs live in world space and drift with a light wind; pure optics.
## Pixel art (D-218, FS2c): a puff is one frame of puff_sheet() drawn at the whole scale ART_SCALE (one
## texel = one village art pixel); it grows by stepping through the frames (CanvasItemMaterial particle
## animation), not by a smooth scale, and starts at a random frame instead of a random size; it
## fades in FADE_STEPS hard steps (constant colour ramp).

## TESTWERT: puffs, lifetime (s), rise speed (world px/s) and wind (world px/s²).
const PUFFS := 12
const LIFETIME := 3.6
const RISE := Vector2(12.0, 20.0)
const WIND := Vector2(7.0, -3.0)
const COLOR_START := Color(0.9, 0.88, 0.94, 0.8)
const COLOR_END := Color(0.62, 0.6, 0.72, 0.0)
## Whole scale of the puff texels (world px per texel = the village art pixel, D-218).
const ART_SCALE := PixelDraw.WORLD_PIXEL
## Radii (art pixels) of the puff frames a puff steps through over its life: 4, 8 and 12 world px
## across, the sizes the old smooth growth (scale 1 to 3 of the 4 px puff) covered.
const PUFF_RADII: Array[int] = [1, 2, 3]
## The latest frame a puff may start at (share of the sheet: the first two frames).
const START_SPREAD := 0.34
## Hard steps of the fade from COLOR_START to COLOR_END.
const FADE_STEPS := 4

static var _puff: Texture2D = null
static var _sheet: Texture2D = null


## Round 4×4 pixel puff (corners cut), for small sparks (VillageEntrance); the chimneys use puff_sheet().
static func puff_texture() -> Texture2D:
	if _puff == null:
		var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		for corner in [Vector2i(0, 0), Vector2i(3, 0), Vector2i(0, 3), Vector2i(3, 3)]:
			image.set_pixelv(corner, Color(0, 0, 0, 0))
		_puff = ImageTexture.create_from_image(image)
	return _puff


## The puff frames side by side, small to large: stepped pixel discs (PixelDraw) of PUFF_RADII art
## pixels, white (the colour ramp tints), each frame as wide as the largest. Shared by all chimneys.
static func puff_sheet() -> Texture2D:
	if _sheet == null:
		_sheet = ImageTexture.create_from_image(paint_puff_sheet())
	return _sheet


static func paint_puff_sheet() -> Image:
	var side := PUFF_RADII[PUFF_RADII.size() - 1] * 2
	var raster := PixelDraw.Raster.new(Vector2i(side * PUFF_RADII.size(), side))
	for i in PUFF_RADII.size():
		var center := Vector2(side * i + side * 0.5, side * 0.5)
		PixelDraw.disc(raster, center, float(PUFF_RADII[i]), Color.WHITE, 1.0)
	return raster.image


## COLOR_START to COLOR_END in FADE_STEPS hard steps (constant interpolation, no smooth fade).
static func fade_ramp() -> Gradient:
	var ramp := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in FADE_STEPS:
		offsets.append(float(i) / FADE_STEPS)
		colors.append(COLOR_START.lerp(COLOR_END, float(i) / FADE_STEPS))
	ramp.offsets = offsets
	ramp.colors = colors
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	return ramp


func _init() -> void:
	amount = PUFFS
	lifetime = LIFETIME
	preprocess = LIFETIME
	local_coords = false
	z_index = 4
	texture = ChimneySmoke.puff_sheet()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	direction = Vector2.UP
	spread = 12.0
	gravity = WIND
	initial_velocity_min = RISE.x
	initial_velocity_max = RISE.y
	scale_amount_min = ART_SCALE
	scale_amount_max = ART_SCALE
	var frames := CanvasItemMaterial.new()
	frames.particles_animation = true
	frames.particles_anim_h_frames = PUFF_RADII.size()
	frames.particles_anim_v_frames = 1
	frames.particles_anim_loop = false
	material = frames
	anim_speed_min = 1.0
	anim_speed_max = 1.0
	anim_offset_min = 0.0
	anim_offset_max = START_SPREAD
	color_ramp = ChimneySmoke.fade_ramp()
	emitting = true

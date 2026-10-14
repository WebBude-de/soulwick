class_name ChimneySmoke
extends CPUParticles2D
## Slow grey smoke puffs from a chimney (B3). Placed by tools/generate_village.py at the chimney top
## of a building sprite. Puffs live in world space and drift with a light wind; pure optics.

## TESTWERT: puffs, lifetime (s), rise speed (world px/s) and wind (world px/s²).
const PUFFS := 12
const LIFETIME := 3.6
const RISE := Vector2(12.0, 20.0)
const WIND := Vector2(7.0, -3.0)
const COLOR_START := Color(0.9, 0.88, 0.94, 0.8)
const COLOR_END := Color(0.62, 0.6, 0.72, 0.0)

static var _puff: Texture2D = null


## Round 4×4 pixel puff (corners cut), shared by all chimneys and VillageAmbience.
static func puff_texture() -> Texture2D:
	if _puff == null:
		var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		for corner in [Vector2i(0, 0), Vector2i(3, 0), Vector2i(0, 3), Vector2i(3, 3)]:
			image.set_pixelv(corner, Color(0, 0, 0, 0))
		_puff = ImageTexture.create_from_image(image)
	return _puff


func _init() -> void:
	amount = PUFFS
	lifetime = LIFETIME
	preprocess = LIFETIME
	local_coords = false
	z_index = 4
	texture = ChimneySmoke.puff_texture()
	direction = Vector2.UP
	spread = 12.0
	gravity = WIND
	initial_velocity_min = RISE.x
	initial_velocity_max = RISE.y
	scale_amount_min = 2.0
	scale_amount_max = 3.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.0))
	scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, COLOR_START)
	ramp.set_color(1, COLOR_END)
	color_ramp = ramp
	emitting = true

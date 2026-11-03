class_name VillageAmbience
extends CPUParticles2D
## Floating light over the whole village (B3): pollen by day, glowing fireflies in the evening (local
## clock). Pure optics, so randf()/the system clock are fine here. Village calls setup() with the map.
## Pixel art (D-218, FS2c): every mote is one village art pixel (a white texel at the whole scale
## ART_SCALE), no fractional sizes, blinking and fading in hard steps (constant colour ramp). Like
## all ambient particles off on "Lichteffekte: Niedrig" (L1, LightingQuality), checked while running
## so the option applies at once.

enum Mode { POLLEN, FIREFLIES }

## TESTWERT: evening from EVENING_START to EVENING_END o'clock (local time).
const EVENING_START := 19
const EVENING_END := 6
## TESTWERT: particles over the whole map, lifetime (s).
const POLLEN_AMOUNT := 46
const FIREFLY_AMOUNT := 34
const LIFETIME := 9.0
const POLLEN_COLOR := Color("#fff3c4")
const FIREFLY_COLOR := Color("#d8f27a")
## Whole scale of the one-texel mote: one village art pixel (world px).
const ART_SCALE := PixelDraw.WORLD_PIXEL

static var _mote: Texture2D = null

var mode := Mode.POLLEN
## Set by apply_mode: from then on _process follows the light-effects option.
var _configured := false


## True between EVENING_START and EVENING_END o'clock.
static func is_evening(hour: int) -> bool:
	return hour >= EVENING_START or hour < EVENING_END


static func mode_for_hour(hour: int) -> Mode:
	return Mode.FIREFLIES if is_evening(hour) else Mode.POLLEN


func _init() -> void:
	local_coords = false
	z_index = 6
	emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	texture = VillageAmbience.mote_texture()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scale_amount_min = ART_SCALE
	scale_amount_max = ART_SCALE
	emitting = false


## One white texel (the colour ramp tints it), drawn at ART_SCALE.
static func mote_texture() -> Texture2D:
	if _mote == null:
		var image := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_mote = ImageTexture.create_from_image(image)
	return _mote


## Ambient motes only on "Lichteffekte: Hoch" (L1).
func _process(_delta: float) -> void:
	if not _configured:
		return
	var wanted := LightingQuality.is_high()
	if emitting != wanted:
		emitting = wanted


## Covers map (world px); mode from the local clock unless given.
func setup(map: Rect2, hour := -1) -> void:
	if hour < 0:
		hour = int(Time.get_time_dict_from_system()["hour"])
	position = map.get_center()
	emission_rect_extents = map.size * 0.5
	apply_mode(mode_for_hour(hour))


func apply_mode(value: Mode) -> void:
	mode = value
	lifetime = LIFETIME
	preprocess = LIFETIME
	direction = Vector2(1, -0.3)
	spread = 180.0
	var ramp := Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	if value == Mode.FIREFLIES:
		amount = FIREFLY_AMOUNT
		gravity = Vector2.ZERO
		initial_velocity_min = 4.0
		initial_velocity_max = 12.0
		# Blinking: on, off, on again before fading out.
		ramp.set_color(0, Color(FIREFLY_COLOR, 0.0))
		ramp.set_color(1, Color(FIREFLY_COLOR, 0.0))
		for point: Vector2 in [Vector2(0.15, 1.0), Vector2(0.35, 0.15), Vector2(0.55, 1.0), Vector2(0.8, 0.6)]:
			ramp.add_point(point.x, Color(FIREFLY_COLOR, point.y))
		var glow := CanvasItemMaterial.new()
		glow.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = glow
	else:
		amount = POLLEN_AMOUNT
		gravity = Vector2(3.0, 1.0)
		initial_velocity_min = 3.0
		initial_velocity_max = 9.0
		ramp.set_color(0, Color(POLLEN_COLOR, 0.0))
		ramp.set_color(1, Color(POLLEN_COLOR, 0.0))
		ramp.add_point(0.2, Color(POLLEN_COLOR, 0.8))
		ramp.add_point(0.8, Color(POLLEN_COLOR, 0.6))
		material = null
	color_ramp = ramp
	_configured = true
	emitting = LightingQuality.is_high()

class_name VillageAmbience
extends CPUParticles2D
## Floating light over the whole village (B3): pollen by day, glowing fireflies in the evening (local
## clock). Pure optics, so randf()/the system clock are fine here. Village calls setup() with the map.

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

var mode := Mode.POLLEN


## True between EVENING_START and EVENING_END o'clock.
static func is_evening(hour: int) -> bool:
	return hour >= EVENING_START or hour < EVENING_END


static func mode_for_hour(hour: int) -> Mode:
	return Mode.FIREFLIES if is_evening(hour) else Mode.POLLEN


func _init() -> void:
	local_coords = false
	z_index = 6
	emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	texture = ChimneySmoke.puff_texture()
	emitting = false


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
	if value == Mode.FIREFLIES:
		amount = FIREFLY_AMOUNT
		gravity = Vector2.ZERO
		initial_velocity_min = 4.0
		initial_velocity_max = 12.0
		scale_amount_min = 0.5
		scale_amount_max = 0.8
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
		scale_amount_min = 0.5
		scale_amount_max = 0.75
		ramp.set_color(0, Color(POLLEN_COLOR, 0.0))
		ramp.set_color(1, Color(POLLEN_COLOR, 0.0))
		ramp.add_point(0.2, Color(POLLEN_COLOR, 0.8))
		ramp.add_point(0.8, Color(POLLEN_COLOR, 0.6))
		material = null
	color_ramp = ramp
	emitting = true

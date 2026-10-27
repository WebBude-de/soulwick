class_name SideAmbience
extends Node2D
## Air of a side segment (M5 round 3): small particles drifting through the whole segment in the
## biome's mood - dust in the crypt, rising spores in the grotto, violet wisps in the shadow realm,
## embers in the ember forge - and something rising out of every pit (mist, or sparks above the
## forge's glow). Look only; CPU particles, so the browser build shows them too. Pixel art (D-218):
## every particle is a square of whole art pixels (sizes rounded by pixel_size) and fades in hard
## steps (constant colour ramp).

## [colour, amount per 1000 px of width, direction, speed, gravity y, size, additive] per biome.
const AIR: Dictionary[StringName, Array] = {
	&"crypt": [Color(0.8, 0.78, 0.95, 0.35), 14, Vector2(1, 0.2), 8.0, 2.0, 2.0, false],
	&"slime_grotto": [Color(0.6, 1.0, 0.5, 0.5), 16, Vector2(0.2, -1), 14.0, -3.0, 2.0, true],
	&"shadow_realm": [Color(0.7, 0.5, 1.0, 0.45), 14, Vector2(0, -1), 12.0, -4.0, 3.0, true],
	&"ember_forge": [Color(1.0, 0.55, 0.2, 0.8), 22, Vector2(0.15, -1), 34.0, -12.0, 2.0, true],
}
## Rising out of the pits: [colour, amount per pit column, speed, size, additive].
const PIT: Dictionary[StringName, Array] = {
	&"crypt": [Color(0.55, 0.6, 0.85, 0.22), 3, 18.0, 7.0, false],
	&"slime_grotto": [Color(0.4, 0.85, 0.35, 0.25), 3, 20.0, 7.0, true],
	&"shadow_realm": [Color(0.5, 0.3, 0.85, 0.3), 3, 22.0, 7.0, true],
	&"ember_forge": [Color(1.0, 0.5, 0.15, 0.85), 6, 70.0, 2.5, true],
}
const AIR_LIFETIME := 9.0
const PIT_LIFETIME := 2.4

var layout: SideLayout = null
var air: CPUParticles2D = null
var pits: Array[CPUParticles2D] = []


static func create(segment_layout: SideLayout) -> SideAmbience:
	var ambience := SideAmbience.new()
	ambience.name = "Ambience"
	ambience.layout = segment_layout
	return ambience


func _ready() -> void:
	if layout == null:
		return
	var biome := layout.biome_id if AIR.has(layout.biome_id) else &"crypt"
	var size := layout.world_size()
	var setting: Array = AIR[biome]
	air = _particles(setting[0], maxi(8, int(setting[1] * size.x / 1000.0)), AIR_LIFETIME, setting[6])
	air.name = "Air"
	air.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	air.emission_rect_extents = size * 0.5
	air.position = size * 0.5
	air.direction = setting[2]
	air.spread = 35.0
	air.initial_velocity_min = setting[3] * 0.5
	air.initial_velocity_max = setting[3]
	air.gravity = Vector2(0, setting[4])
	air.scale_amount_min = pixel_size(setting[5])
	air.scale_amount_max = air.scale_amount_min
	air.preprocess = AIR_LIFETIME
	air.z_index = -2
	add_child(air)
	var pit: Array = PIT[biome]
	var previous := -10
	for column in layout.pit_columns():
		# One emitter per pit run, as wide as the run.
		if column == previous + 1 and not pits.is_empty():
			var last := pits[pits.size() - 1]
			last.emission_rect_extents.x += SideRules.TILE * 0.5
			last.position.x += SideRules.TILE * 0.5
			last.amount += int(pit[1])
			previous = column
			continue
		previous = column
		var emitter := _particles(pit[0], int(pit[1]), PIT_LIFETIME, pit[4])
		emitter.name = "Pit%d" % column
		emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		emitter.emission_rect_extents = Vector2(SideRules.TILE * 0.5, 8.0)
		emitter.position = Vector2((column + 0.5) * SideRules.TILE, size.y + 16.0)
		emitter.direction = Vector2(0, -1)
		emitter.spread = 12.0
		emitter.initial_velocity_min = pit[2] * 0.6
		emitter.initial_velocity_max = pit[2]
		emitter.gravity = Vector2.ZERO
		emitter.scale_amount_min = pixel_size(pit[3])
		emitter.scale_amount_max = emitter.scale_amount_min
		emitter.preprocess = PIT_LIFETIME
		emitter.z_index = -4
		add_child(emitter)
		pits.append(emitter)


## A particle size (px) rounded to whole art pixels, at least one.
static func pixel_size(size: float) -> float:
	return SidePixels.whole(size)


func _particles(color: Color, amount: int, lifetime: float, additive: bool) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.amount = maxi(1, amount)
	particles.lifetime = lifetime
	particles.local_coords = false
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color, 0.0))
	ramp.set_color(1, Color(color, 0.0))
	ramp.add_point(0.2, color)
	ramp.add_point(0.75, Color(color, color.a * 0.6))
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	particles.color_ramp = ramp
	if additive:
		var material := CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		particles.material = material
	return particles

class_name AmbientParticles
extends CPUParticles2D
## Slow ambient pixel particles around the camera view (dust, spores, wisps, embers), one preset per
## biome. Lives under the player camera; particles stay in world space, so they drift past while
## the player walks and only show inside the light circles. Off (NONE) by default, e.g. village.
## L1: a second, additive "accent" emitter adds what makes a biome feel alive - sparks flying up in
## the ember forge, glinting drips in the slime grotto, single bright motes in the crypt, rising
## soul sparks in the shadow realm. LightingQuality low switches both emitters off.
## Visual randomness only (CPUParticles2D), never the dungeon RNG.

enum Preset { NONE, DUST, SPORES, WISPS, EMBERS }

const GROUP := &"ambient_particles"
## Emission area around the view centre (half extents, world px).
const AREA := Vector2(700.0, 420.0)
const BIOME_PRESETS := {
	&"crypt": Preset.DUST,
	&"slime_grotto": Preset.SPORES,
	&"shadow_realm": Preset.WISPS,
	&"ember_forge": Preset.EMBERS,
}
const ACCENT_NAME := "Accent"

var preset := Preset.NONE

var _accent: CPUParticles2D = null


## Sets the preset on every AmbientParticles node in the tree (normally the one under the camera).
static func set_biome_for(context: Node, biome_id: StringName) -> void:
	if context == null or not context.is_inside_tree():
		return
	for node in context.get_tree().get_nodes_in_group(GROUP):
		(node as AmbientParticles).set_biome(biome_id)


static func preset_for_biome(biome_id: StringName) -> Preset:
	return BIOME_PRESETS.get(biome_id, Preset.NONE)


func _init() -> void:
	local_coords = false
	z_index = 5
	emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	emission_rect_extents = AREA
	emitting = false
	_accent = CPUParticles2D.new()
	_accent.name = ACCENT_NAME
	_accent.local_coords = false
	_accent.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_accent.emission_rect_extents = AREA
	_accent.emitting = false
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_accent.material = additive
	add_child(_accent)


func _enter_tree() -> void:
	add_to_group(GROUP)


func set_biome(biome_id: StringName) -> void:
	set_preset(preset_for_biome(biome_id))


func get_accent() -> CPUParticles2D:
	return _accent


## Re-applies the current preset after LightingQuality changed.
func refresh_quality() -> void:
	var current := preset
	preset = Preset.NONE
	set_preset(current)


func set_preset(value: Preset) -> void:
	if value == preset and (emitting or value == Preset.NONE):
		return
	preset = value
	emitting = false
	_accent.emitting = false
	if value == Preset.NONE or not LightingQuality.is_high():
		return
	match value:
		Preset.DUST:
			_configure(36, 7.0, Vector2(0, -1), 180.0, 4.0, 12.0, Vector2(0, 2), Color(0.8, 0.76, 0.9, 0.35), 2.0)
			# Single bright motes that catch the torch light.
			_configure_accent(8, 5.0, Vector2(0, -1), 180.0, 2.0, 6.0, Vector2(0, 1), Color(1.0, 0.9, 0.75, 0.5), 2.0, true)
		Preset.SPORES:
			_configure(30, 8.0, Vector2(0, -1), 60.0, 6.0, 16.0, Vector2(0, -3), Color(0.55, 1.0, 0.55, 0.5), 2.0)
			# Glinting drips: short, falling, blinking.
			_configure_accent(14, 1.4, Vector2(0, 1), 8.0, 30.0, 60.0, Vector2(0, 160), Color(0.7, 1.0, 0.95, 0.85), 2.0, true)
		Preset.WISPS:
			_configure(24, 6.0, Vector2(0, -1), 90.0, 8.0, 20.0, Vector2(0, -4), Color(0.7, 0.5, 1.0, 0.45), 4.0)
			# Soul sparks rising slowly.
			_configure_accent(10, 4.0, Vector2(0, -1), 25.0, 10.0, 24.0, Vector2(0, -6), Color(0.62, 0.72, 1.0, 0.7), 2.0, true)
		Preset.EMBERS:
			_configure(40, 4.0, Vector2(0, -1), 35.0, 20.0, 45.0, Vector2(0, -10), Color(1.0, 0.6, 0.18, 0.9), 2.0)
			# Sparks: fast, bright, short.
			_configure_accent(22, 1.6, Vector2(0, -1), 30.0, 60.0, 120.0, Vector2(0, -40), Color(1.0, 0.82, 0.4, 1.0), 2.0, false)
	preprocess = lifetime
	emitting = true
	restart()
	_accent.preprocess = _accent.lifetime
	_accent.emitting = true
	_accent.restart()


func _configure(count: int, life: float, dir: Vector2, spread_deg: float, speed_min: float, speed_max: float,
		grav: Vector2, color_value: Color, pixel: float) -> void:
	amount = count
	lifetime = life
	direction = dir
	spread = spread_deg
	initial_velocity_min = speed_min
	initial_velocity_max = speed_max
	gravity = grav
	scale_amount_min = pixel
	scale_amount_max = pixel
	# Fades in and out in hard steps (pixel art, D-218).
	var ramp := Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	ramp.set_color(0, Color(color_value, 0.0))
	ramp.set_color(1, Color(color_value, 0.0))
	ramp.add_point(0.1, Color(color_value, color_value.a * 0.5))
	ramp.add_point(0.2, color_value)
	ramp.add_point(0.8, Color(color_value, color_value.a * 0.5))
	ramp.add_point(0.9, Color(color_value, color_value.a * 0.25))
	color_ramp = ramp


## blink: the particle flashes on and off a few times (glints) instead of fading in and out once.
func _configure_accent(count: int, life: float, dir: Vector2, spread_deg: float, speed_min: float, speed_max: float,
		grav: Vector2, color_value: Color, pixel: float, blink: bool) -> void:
	_accent.amount = count
	_accent.lifetime = life
	_accent.direction = dir
	_accent.spread = spread_deg
	_accent.initial_velocity_min = speed_min
	_accent.initial_velocity_max = speed_max
	_accent.gravity = grav
	_accent.scale_amount_min = pixel
	_accent.scale_amount_max = pixel
	# Hard steps only (pixel art, D-218): blinking glints or a stepped fade.
	var ramp := Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	ramp.set_color(0, Color(color_value, 0.0))
	ramp.set_color(1, Color(color_value, 0.0))
	if blink:
		for step in [0.1, 0.3, 0.55, 0.75]:
			ramp.add_point(step, color_value)
			ramp.add_point(step + 0.08, Color(color_value, color_value.a * 0.2))
	else:
		ramp.add_point(0.05, color_value)
		ramp.add_point(0.6, Color(color_value, color_value.a * 0.7))
		ramp.add_point(0.8, Color(color_value, color_value.a * 0.35))
	_accent.color_ramp = ramp

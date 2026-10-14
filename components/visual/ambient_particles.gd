class_name AmbientParticles
extends CPUParticles2D
## Slow ambient pixel particles around the camera view (dust, spores, wisps, embers), one preset per
## biome. Lives under the player camera; particles stay in world space, so they drift past while
## the player walks and only show inside the light circles. Off (NONE) by default, e.g. village.

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

var preset := Preset.NONE


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


func _enter_tree() -> void:
	add_to_group(GROUP)


func set_biome(biome_id: StringName) -> void:
	set_preset(preset_for_biome(biome_id))


func set_preset(value: Preset) -> void:
	if value == preset:
		return
	preset = value
	emitting = false
	if value == Preset.NONE:
		return
	match value:
		Preset.DUST:
			_configure(36, 7.0, Vector2(0, -1), 180.0, 4.0, 12.0, Vector2(0, 2), Color(0.8, 0.76, 0.9, 0.35), 2.0)
		Preset.SPORES:
			_configure(30, 8.0, Vector2(0, -1), 60.0, 6.0, 16.0, Vector2(0, -3), Color(0.55, 1.0, 0.55, 0.5), 2.0)
		Preset.WISPS:
			_configure(24, 6.0, Vector2(0, -1), 90.0, 8.0, 20.0, Vector2(0, -4), Color(0.7, 0.5, 1.0, 0.45), 3.0)
		Preset.EMBERS:
			_configure(40, 4.0, Vector2(0, -1), 35.0, 20.0, 45.0, Vector2(0, -10), Color(1.0, 0.6, 0.18, 0.9), 2.0)
	preprocess = lifetime
	emitting = true
	restart()


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
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color_value, 0.0))
	ramp.set_color(1, Color(color_value, 0.0))
	ramp.add_point(0.2, color_value)
	ramp.add_point(0.8, color_value)
	color_ramp = ramp

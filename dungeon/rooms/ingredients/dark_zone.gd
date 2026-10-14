class_name DarkZone
extends Node2D
## Dark zone (ingredient "Dunkelzonen", KONZEPT_RAEUME §3.3): a patch of thick darkness on the floor
## that shrinks the light circle of whoever stands in it. The decision lives in one place,
## get_vision_factor_at(), for any point, so every player gets their own factor (Koop); the effect
## (a smaller vision radius) is applied by the VisionOverlay (hook, see the A3 report). The patch
## itself is drawn here: a soft dark blob with slowly drifting wisps.

const GROUP := &"dark_zones"
## Radius in world px and the vision factor in its middle (TESTWERTE).
const DEFAULT_RADIUS := 150.0
const DEFAULT_VISION_FACTOR := 0.6
## Share of the radius with the full factor; outside it the factor eases back to 1.
const CORE_SHARE := 0.5
const SHADE_ALPHA := 0.55
const Z := -5
const TEXTURE_SIZE := 64

@export var radius := DEFAULT_RADIUS
@export_range(0.0, 1.0) var vision_factor := DEFAULT_VISION_FACTOR

static var _texture: Texture2D = null

var _time := 0.0
var _shade: Sprite2D = null


## Vision radius factor at a global point: the strongest dark zone wins, 1.0 outside all zones.
static func get_vision_factor_at(tree: SceneTree, global_point: Vector2) -> float:
	var factor := 1.0
	if tree == null:
		return factor
	for node in tree.get_nodes_in_group(GROUP):
		var zone := node as DarkZone
		if zone != null and zone.is_inside_tree():
			factor = minf(factor, zone.get_factor_at(global_point))
	return factor


## Factor of this zone at a global point (smooth edge, no hard jump of the light circle).
func get_factor_at(global_point: Vector2) -> float:
	var distance := global_position.distance_to(global_point)
	if distance >= radius:
		return 1.0
	var depth := 1.0 - smoothstep(radius * CORE_SHARE, radius, distance)
	return lerpf(1.0, vision_factor, depth)


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	z_index = Z
	_shade = Sprite2D.new()
	_shade.texture = _get_texture()
	_shade.scale = Vector2.ONE * (radius * 2.0 / TEXTURE_SIZE)
	_shade.modulate = Color(1, 1, 1, SHADE_ALPHA)
	add_child(_shade)


func _process(delta: float) -> void:
	# Optics only: the blob breathes a little.
	_time += delta
	_shade.modulate.a = SHADE_ALPHA * (0.9 + 0.1 * sin(_time * 0.8))
	_shade.rotation = _time * 0.05


## Radial gradient, black in the middle, transparent at the edge.
static func _get_texture() -> Texture2D:
	if _texture != null:
		return _texture
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.0, 0.0, 0.02, 1.0))
	gradient.set_color(1, Color(0.0, 0.0, 0.02, 0.0))
	gradient.add_point(0.55, Color(0.0, 0.0, 0.02, 0.75))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = TEXTURE_SIZE
	texture.height = TEXTURE_SIZE
	_texture = texture
	return _texture

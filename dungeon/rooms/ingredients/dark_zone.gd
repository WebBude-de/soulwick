class_name DarkZone
extends Node2D
## Dark zone (ingredient "Dunkelzonen", D-113): a patch of thick darkness on the floor
## that shrinks the light circle of whoever stands in it. The decision lives in one place,
## get_vision_factor_at(), for any point, so every player gets their own factor (Koop); the effect
## (a smaller vision radius) is applied by the VisionOverlay (hook, see the A3 report). The patch
## itself is drawn here: a dark pixel blob that fades out in a few hard steps (D-218) and breathes.

const GROUP := &"dark_zones"
## Radius in world px and the vision factor in its middle (TESTWERTE).
const DEFAULT_RADIUS := 150.0
const DEFAULT_VISION_FACTOR := 0.6
## Share of the radius with the full factor; outside it the factor eases back to 1.
const CORE_SHARE := 0.5
const SHADE_ALPHA := 0.55
const Z := -5
## The patch fades out in this many hard rings.
const SHADE_STEPS := 4

@export var radius := DEFAULT_RADIUS
@export_range(0.0, 1.0) var vision_factor := DEFAULT_VISION_FACTOR

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
	_shade.texture = get_shade_texture(radius)
	_shade.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# One texel per art pixel (D-218).
	_shade.scale = Vector2.ONE * PixelDraw.WORLD_PIXEL
	_shade.modulate = Color(1, 1, 1, SHADE_ALPHA)
	add_child(_shade)


func _process(delta: float) -> void:
	# Optics only: the blob breathes a little (no turning: its pixels stay on the grid).
	_time += delta
	_shade.modulate.a = SHADE_ALPHA * (0.9 + 0.1 * sin(_time * 0.8))


## Dark patch for a zone of zone_radius world px: black in the middle, SHADE_STEPS hard steps to
## transparent at the edge (pixel art, D-218; cached per size in PixelDraw).
static func get_shade_texture(zone_radius: float) -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.0, 0.0, 0.02, 1.0))
	gradient.set_color(1, Color(0.0, 0.0, 0.02, 0.0))
	gradient.add_point(0.55, Color(0.0, 0.0, 0.02, 0.75))
	var radius_pixels := maxi(1, roundi(zone_radius / PixelDraw.WORLD_PIXEL))
	return PixelDraw.stepped_glow_texture(radius_pixels, gradient, SHADE_STEPS)

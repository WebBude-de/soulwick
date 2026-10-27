@tool
class_name PixelLine
extends Line2D
## A Line2D drawn as pixel dashes (D-218): the aim lines of enemy telegraphs (TelegraphLine in
## enemies/enemy_base.tscn, the turret's aim line). Callers keep using it like any Line2D (points,
## default_color, width, visible); the smooth line of the engine is hidden (a transparent gradient)
## and the line is drawn instead with PixelDraw on the world art-pixel grid: width 2 = one art pixel,
## 3 or more = two. Moves redraw, so the dashes stay on the grid while the enemy walks.

## Dash and gap length in art pixels.
@export var dash := 3
@export var gap := 2

static var _hidden: Gradient = null


func _init() -> void:
	set_notify_transform(true)
	gradient = _hidden_gradient()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_visible_in_tree():
		queue_redraw()


## Line thickness in art pixels for a Line2D width in world px.
static func pixels_for_width(line_width: float) -> int:
	return maxi(1, roundi(line_width / PixelDraw.WORLD_PIXEL))


func _draw() -> void:
	if points.size() < 2:
		return
	var world := get_global_transform()
	# World frame: the dashes sit on the world art-pixel grid, whatever the node's transform.
	draw_set_transform_matrix(world.affine_inverse())
	var thickness := pixels_for_width(width)
	for i in range(1, points.size()):
		PixelDraw.dashed_line(self, world * points[i - 1], world * points[i], default_color, dash, gap, thickness)
	draw_set_transform_matrix(Transform2D.IDENTITY)


static func _hidden_gradient() -> Gradient:
	if _hidden == null:
		_hidden = Gradient.new()
		_hidden.offsets = PackedFloat32Array([0.0])
		_hidden.colors = PackedColorArray([Color(0, 0, 0, 0)])
	return _hidden

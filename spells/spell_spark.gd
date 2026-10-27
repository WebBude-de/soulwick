class_name SpellSpark
extends Node2D
## A small light that flies from Flint's flame to a target and bursts there (looks of Seelenschild
## and Heilfunke: "der Effekt geht von Flint aus", KONZEPT §6.2). Follows a moving target node.
## Optics only; frees itself on arrival. Drawn in pixel art (PixelDraw, D-218): a pixel disc with a
## see-through rim, stepping over the world art-pixel grid.

const FLIGHT_TIME := 0.25
const RADIUS := 3.0

var color := Color.WHITE
## Where it flies: target's global position (when set and valid), else end.
var target: Node2D = null
var end := Vector2.ZERO
var _start := Vector2.ZERO
var _age := 0.0


## Spark from global from_pos to target (a node it follows, or null for to_pos) under parent.
static func spawn(parent: Node, from_pos: Vector2, follow: Node2D, to_pos: Vector2, spark_color: Color) -> SpellSpark:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	var spark := SpellSpark.new()
	spark.color = spark_color
	spark.target = follow
	spark.end = to_pos
	spark.z_index = 6
	parent.add_child(spark)
	spark.global_position = from_pos
	spark._start = from_pos
	return spark


func _process(delta: float) -> void:
	_age += delta
	var goal := target.global_position if target != null and is_instance_valid(target) else end
	var share := clampf(_age / FLIGHT_TIME, 0.0, 1.0)
	# A slight arc upwards, like a spark thrown from the flame.
	global_position = _start.lerp(goal, share) + Vector2(0.0, -18.0 * sin(share * PI))
	queue_redraw()
	if share >= 1.0:
		Burst.spawn(get_parent(), goal, color, 8, 90.0, 0.35, 3.0)
		queue_free()


func _draw() -> void:
	PixelDraw.align_to_world_grid(self)
	paint(self)


## The spark around item's origin (a CanvasItem in _draw, or a PixelDraw.Raster in tests).
func paint(item: Object) -> void:
	PixelDraw.disc(item, Vector2.ZERO, RADIUS + PixelDraw.WORLD_PIXEL, Color(color, 0.4))
	PixelDraw.disc(item, Vector2.ZERO, RADIUS, color)

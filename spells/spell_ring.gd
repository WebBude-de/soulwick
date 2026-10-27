class_name SpellRing
extends Node2D
## Drawn placeholder of an area spell's effect (SPRITES_V13 §B5 until the strips are delivered): a
## ring in the spell's colour that grows from start_radius to end_radius and fades, then frees
## itself. Optics only. Pixel art (PixelDraw, D-218): a stepped ring of WIDTH art pixels with a
## one-pixel light inner edge on the world grid, fading in FADE_STEPS hard steps.

const DURATION := 0.4
## Ring width in art pixels.
const WIDTH := 2
const FADE_STEPS := 3

var color := Color.WHITE
var start_radius := 8.0
var end_radius := 64.0
var duration := DURATION
var _age := 0.0


## A ring at global_pos under parent (null when parent is gone).
static func spawn(parent: Node, global_pos: Vector2, ring_color: Color, from_radius: float, to_radius: float,
		seconds := DURATION) -> SpellRing:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	var ring := SpellRing.new()
	ring.color = ring_color
	ring.start_radius = from_radius
	ring.end_radius = to_radius
	ring.duration = maxf(0.05, seconds)
	ring.z_index = 5
	parent.add_child(ring)
	ring.global_position = global_pos
	return ring


func get_radius() -> float:
	return lerpf(start_radius, end_radius, ease(clampf(_age / duration, 0.0, 1.0), 0.4))


func _process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	PixelDraw.align_to_world_grid(self)
	paint(self)


## Alpha share now: 1 at the start, then FADE_STEPS hard steps down to nothing.
func get_fade() -> float:
	var share := clampf(_age / duration, 0.0, 1.0)
	return PixelDraw.stepped(1.0 - share * share, FADE_STEPS)


## The ring as it is now around item's origin (a CanvasItem in _draw, or a PixelDraw.Raster).
func paint(item: Object) -> void:
	var alpha := get_fade()
	if alpha <= 0.0:
		return
	var radius := get_radius()
	PixelDraw.ring(item, Vector2.ZERO, radius, Color(color, 0.85 * alpha), WIDTH)
	var inner := radius - WIDTH * PixelDraw.WORLD_PIXEL
	if inner >= PixelDraw.WORLD_PIXEL:
		PixelDraw.ring(item, Vector2.ZERO, inner, Color(1, 1, 1, 0.5 * alpha), 1)

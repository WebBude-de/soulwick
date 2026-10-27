class_name PixelTrail
extends Node2D
## Fading trail of pixels behind a flying thing (D-218), e.g. the projectile trail: replaces a
## smooth Line2D with round caps and a gradient. Keeps the last max_points positions in world
## coordinates (top_level) and draws them with PixelDraw on the world art-pixel grid: the oldest end
## thin and see-through, the newest end width wide at MAX_ALPHA, in FADE_STEPS hard alpha steps.
## fade_out() lets it fade in the same hard steps and frees it. Optics only.

const FADE_STEPS := 3
## Alpha of the newest end (the old Line2D gradient ended at 0.75).
const MAX_ALPHA := 0.75
## Width of the oldest end as a share of width (the old taper curve started at 0.2).
const TAIL_WIDTH := 0.2

var color := Color.WHITE
## Width of the newest end in world px (like Line2D.width).
var width := 4.0
## Number of remembered positions; older ones drop off.
var max_points := 8
## 1 = shown, 0 = gone (fade_out tweens it).
var fade := 1.0:
	set(value):
		fade = value
		queue_redraw()

var _points := PackedVector2Array()


func _init() -> void:
	top_level = true


## Remembers a world position at the newest end.
func add_point(point: Vector2) -> void:
	_points.append(point)
	while _points.size() > maxi(1, max_points):
		_points.remove_at(0)
	queue_redraw()


func get_point_count() -> int:
	return _points.size()


func get_points() -> PackedVector2Array:
	return _points


## Fades out in hard steps over duration, then frees itself.
func fade_out(duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(self, "fade", 0.0, maxf(0.01, duration))
	tween.tween_callback(queue_free)


func _draw() -> void:
	# top_level: the node's frame is the world, so the points are drawn as they are.
	paint(self)


## The trail in world coordinates into item (this node in _draw, or a PixelDraw.Raster).
func paint(item: Object) -> void:
	var count := _points.size()
	var shown := PixelDraw.stepped(fade, FADE_STEPS)
	if count < 2 or shown <= 0.0:
		return
	var full := PixelLine.pixels_for_width(width)
	# Runs of segments with the same alpha step and width, newest first: a cell two runs share (their
	# joint) is drawn once, by the brighter newer run, so see-through colours never stack.
	var runs: Array[Array] = []
	var start := 0
	var style := _style(1, count, full)
	for i in range(2, count + 1):
		var next := _style(i, count, full) if i < count else Vector2i(-1, -1)
		if next == style:
			continue
		runs.push_front([start, i, style])
		start = i - 1
		style = next
	var taken := {}
	for run: Array in runs:
		var run_style: Vector2i = run[2]
		var cells := {}
		var points := _points.slice(run[0], run[1])
		for k in range(1, points.size()):
			PixelDraw._line_cells(cells, points[k - 1] / PixelDraw.WORLD_PIXEL, points[k] / PixelDraw.WORLD_PIXEL, 1, 0, run_style.y, 0)
		for cell: Vector2i in cells.keys():
			if taken.has(cell):
				cells.erase(cell)
			else:
				taken[cell] = true
		var alpha := float(run_style.x) / FADE_STEPS * MAX_ALPHA * shown
		PixelDraw._draw_cells(item, cells, Color(color, color.a * alpha), PixelDraw.WORLD_PIXEL)


## Alpha step (1..FADE_STEPS) and width (art pixels) of the segment that ends at point index of count.
func _style(index: int, count: int, full: int) -> Vector2i:
	var share := float(index) / float(count - 1)
	var step := maxi(1, ceili(share * FADE_STEPS))
	var thickness := maxi(1, roundi(full * lerpf(TAIL_WIDTH, 1.0, share)))
	return Vector2i(step, thickness)

class_name SidePixels
extends RefCounted
## Pixel-art drawing for the side view (D-218): a thin wrapper around PixelDraw (components/visual/,
## FS2b) with the side view's habits, so the callers in dungeon/side/ stay unchanged. Every effect,
## marker and guide line of the side view is drawn on the art-pixel grid of the world (1 art pixel =
## SpriteStrip.PIXEL_SCALE = 2 px) with hard edges. Side-view specifics kept here: snap() rounds
## down (an art pixel's top-left corner), rect() leaves out what rounds to nothing, disc() and ring()
## take a squash factor, glow() an optional core, and the *_rects() variants return the rects for
## tests. Coordinates are local to the canvas item; keep its global position on the grid (snap()) and
## it lines up with the art around it. Light and darkness of the light system stay soft (D-218).

## World px per art pixel.
const PIXEL := PixelDraw.WORLD_PIXEL
## Alpha steps of a fade (fade()).
const FADE_STEPS := 3
## Share of opaque pixels that makes a row the walkable surface of a platform picture (surface_row).
const SURFACE_SHARE := PixelDraw.SURFACE_SHARE


## A point snapped onto the art-pixel grid (rounded down).
static func snap(point: Vector2) -> Vector2:
	return PixelDraw.snap_down(point, PIXEL)


## A length rounded to whole art pixels (at least one).
static func whole(length: float) -> float:
	return PixelDraw.whole(length, PIXEL)


## Alpha a (0..1) of something fading over t (0..1) in FADE_STEPS hard steps.
static func fade(alpha: float, t: float, steps := FADE_STEPS) -> float:
	return alpha * PixelDraw.stepped(1.0 - t, steps)


## A filled rect snapped to the grid; nothing when it rounds to nothing.
static func rect(canvas: Object, area: Rect2, color: Color) -> void:
	var from := (area.position / PIXEL).round()
	var to := (area.end / PIXEL).round()
	if to.x <= from.x or to.y <= from.y:
		return
	PixelDraw.rect(canvas, area, color, PIXEL)


## The outline of a rect, width in art pixels.
static func frame(canvas: Object, area: Rect2, color: Color, width_px := 1) -> void:
	PixelDraw.rect_outline(canvas, area, color, width_px, PIXEL)


## One square of size_px art pixels at a point (its top-left on the grid).
static func dot(canvas: Object, at: Vector2, color: Color, size_px := 1) -> void:
	PixelDraw.rect(canvas, Rect2(snap(at), Vector2.ONE * PIXEL * maxi(1, size_px)), color, PIXEL)


## A line of pixel squares from a to b (width in art pixels); runs on one row become one rect each.
static func line(canvas: Object, a: Vector2, b: Vector2, color: Color, width_px := 1) -> void:
	PixelDraw.line(canvas, a, b, color, width_px, PIXEL)


## The rects of line() (tests: all on the grid).
static func line_rects(a: Vector2, b: Vector2, width_px := 1) -> Array[Rect2]:
	var recorder := PixelDraw.Recorder.new()
	line(recorder, a, b, Color.WHITE, width_px)
	return recorder.rects


## A dashed pixel line from a to b: dash_px art pixels drawn, gap_px left out, starting phase_px
## into the pattern (a moving pattern reads as direction).
static func dashed(canvas: Object, a: Vector2, b: Vector2, color: Color, dash_px := 2, gap_px := 2,
		width_px := 1, phase_px := 0) -> void:
	PixelDraw.dashed_line(canvas, a, b, color, dash_px, gap_px, width_px, PIXEL, phase_px)


static func polyline(canvas: Object, points: PackedVector2Array, color: Color, width_px := 1) -> void:
	PixelDraw.polyline(canvas, points, color, width_px, PIXEL)


## A filled disc (squash < 1 flattens it into an ellipse), one rect per art-pixel row.
static func disc(canvas: Object, center: Vector2, radius: float, color: Color, squash := 1.0) -> void:
	ring(canvas, center, radius, color, 0, squash)


## A pixel ring of width_px art pixels (0 = filled), squash < 1 flattens it into an ellipse.
static func ring(canvas: Object, center: Vector2, radius: float, color: Color, width_px := 1, squash := 1.0) -> void:
	var radii := Vector2(radius, radius * squash)
	if width_px <= 0:
		PixelDraw.ellipse(canvas, center, radii, color, PIXEL)
	else:
		PixelDraw.ellipse_ring(canvas, center, radii, color, width_px, PIXEL)


## The rects of ring() (tests: all on the grid).
static func ring_rects(center: Vector2, radius: float, width_px := 1, squash := 1.0) -> Array[Rect2]:
	var recorder := PixelDraw.Recorder.new()
	ring(recorder, center, radius, Color.WHITE, width_px, squash)
	return recorder.rects


## A glow of a few hard steps: discs from radius inwards, each brighter (no soft halo).
static func glow(canvas: Object, center: Vector2, radius: float, color: Color, steps := 3, core := Color(0, 0, 0, 0)) -> void:
	for step in steps:
		var share := 1.0 - float(step) / steps
		disc(canvas, center, radius * share, Color(color, color.a * float(step + 1) / steps))
	if core.a > 0.0:
		disc(canvas, center, maxf(PIXEL, radius / (steps + 1)), core)


## A filled polygon (even-odd): every art pixel whose centre lies inside, one rect per span.
static func polygon(canvas: Object, points: PackedVector2Array, color: Color) -> void:
	PixelDraw.polygon(canvas, points, color, PIXEL)


## The rects of polygon() (tests: all on the grid).
static func polygon_rects(points: PackedVector2Array) -> Array[Rect2]:
	var recorder := PixelDraw.Recorder.new()
	polygon(recorder, points, Color.WHITE)
	return recorder.rects


## Whether a rect lies on the art-pixel grid (position and size whole art pixels; tests).
static func is_on_grid(area: Rect2) -> bool:
	return PixelDraw.is_on_grid(area, PIXEL)


## A vertical colour ramp in hard bands (no smooth gradient): steps bands from top to bottom.
static func bands(canvas: Object, area: Rect2, top_color: Color, bottom_color: Color, steps := 4) -> void:
	PixelDraw.bands(canvas, area, top_color, bottom_color, steps, PIXEL)


## Where the walkable top of a platform picture begins (PixelDraw.surface_row).
static func surface_row(texture: Texture2D, region: Rect2i, fallback := 0) -> int:
	return PixelDraw.surface_row(texture, region, fallback)

@tool
class_name PixelDraw
extends RefCounted
## Shared pixel-art drawing for code-drawn effects, markers and guide lines (D-218 "Nur
## Pixel-Effekte"): every shape is built from whole art pixels on a grid (in the world 1 art pixel
## = WORLD_PIXEL = 2 px, like the sprites drawn at SpriteStrip.PIXEL_SCALE; in the UI
## UiKit.ART_SCALE), with hard edges and no anti-aliasing. Circles are stepped pixel rings, lines
## pixel dots or dashes, a glow a few hard steps instead of a smooth gradient. New effects use these
## helpers instead of draw_circle/draw_arc/draw_line/GradientTexture2D, so they all look alike.
## Exception: light and darkness of the lighting system (D-141) and Flint's soft glow (D-217).
## The grid is the one of the canvas item's local coordinates (whole multiples of pixel from its
## origin); callers that want a world grid draw in a world-aligned frame (PlaceholderShape,
## PixelLine). item is the CanvasItem that draws (call inside its _draw) or a PixelDraw.Raster
## (tests, previews: paints into an Image without a renderer). Static helpers only (D-044: no
## autoload). The side view draws through SidePixels (dungeon/side/), a thin wrapper around these
## helpers with the side view's grid rules (FS2b).

## World px per art pixel (sprites are drawn at 2x).
const WORLD_PIXEL := 2.0

## Share of opaque pixels that makes a row the walkable surface of a platform picture (surface_row).
const SURFACE_SHARE := 0.75

static var _textures: Dictionary = {}
static var _surface_rows: Dictionary[String, int] = {}


## point rounded to the nearest grid corner.
static func snap(point: Vector2, pixel := WORLD_PIXEL) -> Vector2:
	return (point / pixel).round() * pixel


## value (0..1, e.g. an alpha that fades) rounded up to one of steps hard steps: fades in a few
## visible steps instead of smoothly.
static func stepped(value: float, steps := 4) -> float:
	var count := maxi(1, steps)
	return ceilf(clampf(value, 0.0, 1.0) * count) / count


## Filled pixel circle around center (snapped to the grid).
static func disc(item: Object, center: Vector2, radius: float, color: Color, pixel := WORLD_PIXEL) -> void:
	ellipse(item, center, Vector2(radius, radius), color, pixel)


## Filled pixel ellipse with the half axes radii (world px).
static func ellipse(item: Object, center: Vector2, radii: Vector2, color: Color, pixel := WORLD_PIXEL) -> void:
	_spans(item, center, radii, Vector2.ZERO, color, pixel)


## Pixel ring: the outer thickness art pixels of a circle of radius.
static func ring(item: Object, center: Vector2, radius: float, color: Color, thickness := 1, pixel := WORLD_PIXEL) -> void:
	ellipse_ring(item, center, Vector2(radius, radius), color, thickness, pixel)


static func ellipse_ring(item: Object, center: Vector2, radii: Vector2, color: Color, thickness := 1, pixel := WORLD_PIXEL) -> void:
	var inner := radii - Vector2.ONE * float(maxi(1, thickness)) * pixel
	_spans(item, center, radii, inner.max(Vector2.ZERO), color, pixel)


## Part of a pixel ring: from from_angle (radians, 0 = right, clockwise on screen) over sweep.
static func arc(item: Object, center: Vector2, radius: float, from_angle: float, sweep: float, color: Color, thickness := 1, pixel := WORLD_PIXEL) -> void:
	if sweep <= 0.0 or radius <= 0.0:
		return
	if sweep >= TAU:
		ring(item, center, radius, color, thickness, pixel)
		return
	var c := snap(center, pixel)
	var r := maxf(radius / pixel, 0.75)
	var inner := maxf(0.0, r - float(maxi(1, thickness)))
	var rows := ceili(r)
	for j in range(-rows, rows):
		var yc := j + 0.5
		var outer_n := half_cells(r, r, yc)
		if outer_n <= 0:
			continue
		var inner_n := half_cells(inner, inner, yc) if inner > 0.0 else 0
		for i in range(-outer_n, outer_n):
			if i >= -inner_n and i < inner_n:
				continue
			var angle := Vector2(i + 0.5, yc).angle()
			if fposmod(angle - from_angle, TAU) <= sweep:
				item.draw_rect(Rect2(c + Vector2(i, j) * pixel, Vector2.ONE * pixel), color)


## Concentric pixel discs from radius inwards, each step a little more opaque: a glow in steps hard
## steps instead of a gradient (color.a is the strength of the core).
static func glow(item: Object, center: Vector2, radius: float, color: Color, steps := 3, pixel := WORLD_PIXEL) -> void:
	var count := maxi(1, steps)
	for k in count:
		var step_radius := radius * float(count - k) / count
		disc(item, center, step_radius, Color(color, color.a / count), pixel)


## Solid pixel line, thickness art pixels wide.
static func line(item: Object, from: Vector2, to: Vector2, color: Color, thickness := 1, pixel := WORLD_PIXEL) -> void:
	dashed_line(item, from, to, color, 1, 0, thickness, pixel)


## Line of pixel dashes: dash art pixels on, gap off, starting phase pixels into the pattern
## (a moving phase makes the dashes march).
static func dashed_line(item: Object, from: Vector2, to: Vector2, color: Color, dash := 2, gap := 2, thickness := 1, pixel := WORLD_PIXEL, phase := 0) -> void:
	var cells := {}
	_line_cells(cells, from / pixel, to / pixel, dash, gap, thickness, phase)
	_draw_cells(item, cells, color, pixel)


## Solid pixel lines through points. Every pixel is drawn once, also at the joints and where a
## thick line overlaps itself, so see-through colours stay even.
static func polyline(item: Object, points: PackedVector2Array, color: Color, thickness := 1, pixel := WORLD_PIXEL) -> void:
	var cells := {}
	for i in range(1, points.size()):
		_line_cells(cells, points[i - 1] / pixel, points[i] / pixel, 1, 0, thickness, 0)
	_draw_cells(item, cells, color, pixel)


## Collects the cells (Vector2i keys) of a line from a to b (in cells) into cells.
static func _line_cells(cells: Dictionary, a: Vector2, b: Vector2, dash: int, gap: int, thickness: int, phase: int) -> void:
	var steps := maxi(1, roundi(maxf(absf(b.x - a.x), absf(b.y - a.y))))
	var period := maxi(1, dash + maxi(0, gap))
	var size := maxi(1, thickness)
	var shift := floori((size - 1) * 0.5)
	for k in steps + 1:
		if posmod(k + phase, period) >= dash:
			continue
		var cell := Vector2i(a.lerp(b, float(k) / steps).floor()) - Vector2i(shift, shift)
		for dy in size:
			for dx in size:
				cells[cell + Vector2i(dx, dy)] = true


## Draws a set of cells, neighbours in a row merged into one rectangle.
static func _draw_cells(item: Object, cells: Dictionary, color: Color, pixel: float) -> void:
	var keys: Array = cells.keys()
	keys.sort_custom(func(p: Vector2i, q: Vector2i) -> bool: return p.y < q.y or (p.y == q.y and p.x < q.x))
	var i := 0
	while i < keys.size():
		var start: Vector2i = keys[i]
		var run := 1
		while i + run < keys.size() and keys[i + run] == start + Vector2i(run, 0):
			run += 1
		item.draw_rect(Rect2(Vector2(start) * pixel, Vector2(run, 1) * pixel), color)
		i += run


## Filled polygon: every grid cell whose centre lies inside (even-odd rule).
static func polygon(item: Object, points: PackedVector2Array, color: Color, pixel := WORLD_PIXEL) -> void:
	if points.size() < 3:
		return
	var cells := PackedVector2Array()
	var top := INF
	var bottom := -INF
	for point in points:
		var cell := point / pixel
		cells.append(cell)
		top = minf(top, cell.y)
		bottom = maxf(bottom, cell.y)
	for j in range(floori(top), ceili(bottom)):
		var yc := j + 0.5
		var crossings: Array[float] = []
		for i in cells.size():
			var p := cells[i]
			var q := cells[(i + 1) % cells.size()]
			if (p.y <= yc) != (q.y <= yc):
				crossings.append(p.x + (yc - p.y) / (q.y - p.y) * (q.x - p.x))
		crossings.sort()
		for k in range(0, crossings.size() - 1, 2):
			var first := ceili(crossings[k] - 0.5)
			var last := floori(crossings[k + 1] - 0.5)
			if last >= first:
				item.draw_rect(Rect2(Vector2(first, j) * pixel, Vector2(last - first + 1, 1) * pixel), color)


## Pixel diamond: a centre pixel and radius steps around it (radius 0 = one pixel).
static func diamond(item: Object, center: Vector2, radius: int, color: Color, pixel := WORLD_PIXEL) -> void:
	var c := snap(center - Vector2.ONE * pixel * 0.5, pixel)
	for j in range(-radius, radius + 1):
		var half := radius - absi(j)
		item.draw_rect(Rect2(c + Vector2(-half, j) * pixel, Vector2(half * 2 + 1, 1) * pixel), color)


## Outline of the same pixel diamond (centre pixel on the origin) as a staircase polygon, for a
## Polygon2D or a collision-free marker node.
static func diamond_points(radius: int, pixel := WORLD_PIXEL) -> PackedVector2Array:
	var r := maxi(0, radius)
	var right := PackedVector2Array()
	var left := PackedVector2Array()
	for j in range(-r, r + 1):
		var half := (r - absi(j)) + 0.5
		var top := (j - 0.5) * pixel
		var bottom := (j + 0.5) * pixel
		right.append(Vector2(half * pixel, top))
		right.append(Vector2(half * pixel, bottom))
		left.append(Vector2(-half * pixel, top))
		left.append(Vector2(-half * pixel, bottom))
	left.reverse()
	right.append_array(left)
	return right


## Rectangle with position and size rounded to the grid.
static func rect(item: Object, area: Rect2, color: Color, pixel := WORLD_PIXEL) -> void:
	var start := snap(area.position, pixel)
	var end := snap(area.end, pixel)
	item.draw_rect(Rect2(start, (end - start).max(Vector2.ONE * pixel)), color)


## Frame of thickness art pixels inside the grid-rounded rectangle.
static func rect_outline(item: Object, area: Rect2, color: Color, thickness := 1, pixel := WORLD_PIXEL) -> void:
	var start := snap(area.position, pixel)
	var size := (snap(area.end, pixel) - start).max(Vector2.ONE * pixel)
	var t := minf(float(maxi(1, thickness)) * pixel, minf(size.x, size.y) * 0.5)
	item.draw_rect(Rect2(start, Vector2(size.x, t)), color)
	item.draw_rect(Rect2(start + Vector2(0, size.y - t), Vector2(size.x, t)), color)
	item.draw_rect(Rect2(start + Vector2(0, t), Vector2(t, size.y - 2.0 * t)), color)
	item.draw_rect(Rect2(start + Vector2(size.x - t, t), Vector2(t, size.y - 2.0 * t)), color)


## Small picture from text rows ('#' = pixel), top left at origin (snapped).
static func bitmap(item: Object, origin: Vector2, rows: PackedStringArray, color: Color, pixel := WORLD_PIXEL) -> void:
	var start := snap(origin, pixel)
	for y in rows.size():
		var row := rows[y]
		var x := 0
		while x < row.length():
			if row[x] != "#":
				x += 1
				continue
			var run := 1
			while x + run < row.length() and row[x + run] == "#":
				run += 1
			item.draw_rect(Rect2(start + Vector2(x, y) * pixel, Vector2(run, 1) * pixel), color)
			x += run


## Cells on each side of the centre column in the row whose centre lies yc cells from the centre,
## for an ellipse with the half axes rx, ry (in cells): every cell whose centre is inside counts.
static func half_cells(rx: float, ry: float, yc: float) -> int:
	if ry <= 0.0 or absf(yc) > ry:
		return 0
	return floori(rx * sqrt(1.0 - (yc / ry) * (yc / ry)) + 0.5)


## A radial glow texture in hard steps, white (tint with modulate), one texel per art pixel: show
## it on a Sprite2D scaled by the art pixel size with nearest filtering. ramp: colour/alpha from the
## centre (offset 0) to the rim (offset 1), sampled once per step. Cached per radius and ramp.
static func stepped_glow_texture(radius_pixels: int, ramp: Gradient, steps := 4) -> ImageTexture:
	var r := maxi(1, radius_pixels)
	var count := maxi(1, steps)
	var key := "%d|%d|%s" % [r, count, str(ramp.colors) + str(ramp.offsets)]
	if _textures.has(key):
		return _textures[key]
	var image := Image.create_empty(r * 2, r * 2, false, Image.FORMAT_RGBA8)
	for y in r * 2:
		for x in r * 2:
			var d := (Vector2(x, y) + Vector2(0.5, 0.5) - Vector2(r, r)).length() / r
			if d > 1.0:
				continue
			var step := mini(count - 1, floori(d * count))
			image.set_pixel(x, y, ramp.sample((step + 0.5) / count))
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture


## Draws the rows of an ellipse (outer half axes) without the cells inside inner (zero = filled).
static func _spans(item: Object, center: Vector2, outer: Vector2, inner: Vector2, color: Color, pixel: float) -> void:
	if outer.x <= 0.0 or outer.y <= 0.0:
		return
	var c := snap(center, pixel)
	var rx := maxf(outer.x / pixel, 0.75)
	var ry := maxf(outer.y / pixel, 0.75)
	var ix := inner.x / pixel
	var iy := inner.y / pixel
	var rows := ceili(ry)
	for j in range(-rows, rows):
		var yc := j + 0.5
		var outer_n := half_cells(rx, ry, yc)
		if outer_n <= 0:
			continue
		var inner_n := half_cells(ix, iy, yc) if ix > 0.0 and iy > 0.0 else 0
		var y := c.y + j * pixel
		if inner_n <= 0:
			item.draw_rect(Rect2(c.x - outer_n * pixel, y, outer_n * 2 * pixel, pixel), color)
			continue
		var width := (outer_n - inner_n) * pixel
		if width <= 0.0:
			continue
		item.draw_rect(Rect2(c.x - outer_n * pixel, y, width, pixel), color)
		item.draw_rect(Rect2(c.x + inner_n * pixel, y, width, pixel), color)


## Call first in the _draw of a moving, unrotated, unscaled Node2D: shifts the drawing so its origin
## sits on the world grid, so the shape steps in whole art pixels like the art around it instead of
## sliding between them. The node moves on unchanged; only the picture snaps.
static func align_to_world_grid(node: Node2D, pixel := WORLD_PIXEL) -> void:
	node.draw_set_transform(snap(node.global_position, pixel) - node.global_position)


## point rounded down onto the grid (the top-left corner of the art pixel it lies in).
static func snap_down(point: Vector2, pixel := WORLD_PIXEL) -> Vector2:
	return (point / pixel).floor() * pixel


## length rounded to whole art pixels, at least one.
static func whole(length: float, pixel := WORLD_PIXEL) -> float:
	return maxf(pixel, roundf(length / pixel) * pixel)


## Scale of an effect sprite that is fitted to a radius (hit radius / art radius): rounded to the
## nearest whole number, at least 1, so the art's pixels stay whole and even (FS2b). Only the picture
## snaps; the hit area keeps its exact radius.
static func whole_scale(raw: float) -> float:
	return maxf(1.0, roundf(raw))


## Whether area lies on the grid (position and size whole art pixels).
static func is_on_grid(area: Rect2, pixel := WORLD_PIXEL) -> bool:
	for value in [area.position.x, area.position.y, area.size.x, area.size.y]:
		var rest := fposmod(value, pixel)
		if not is_equal_approx(rest, 0.0) and not is_equal_approx(rest, pixel):
			return false
	return true


## A vertical colour ramp in steps hard bands from top to bottom (no smooth gradient); bands that
## round to nothing are left out.
static func bands(item: Object, area: Rect2, top_color: Color, bottom_color: Color, steps := 4, pixel := WORLD_PIXEL) -> void:
	var count := maxi(1, steps)
	var height := area.size.y / count
	for step in count:
		var color := top_color.lerp(bottom_color, (step + 0.5) / count)
		if color.a <= 0.0:
			continue
		var from := snap(Vector2(area.position.x, area.position.y + height * step), pixel)
		var to := snap(Vector2(area.end.x, area.position.y + height * (step + 1)), pixel)
		if to.x > from.x and to.y > from.y:
			item.draw_rect(Rect2(from, to - from), color)


## A radial ramp in steps hard bands over area, e.g. a vignette: a cell's band is its distance from
## the centre, 0 in the middle and 1 in the corners (like a GradientTexture2D with FILL_RADIAL from
## the centre to a corner), coloured ramp.sample((band + 0.5) / steps). At most two rects per band and
## row, so a full-screen vignette is a few hundred rects, drawn once.
static func radial_bands(item: Object, area: Rect2, ramp: Gradient, steps := 4, pixel := WORLD_PIXEL) -> void:
	var count := maxi(1, steps)
	var cols := ceili(area.size.x / pixel)
	var rows := ceili(area.size.y / pixel)
	if cols <= 0 or rows <= 0:
		return
	var half := Vector2(cols, rows) * 0.5
	var origin := snap(area.position, pixel)
	for j in rows:
		var ny := (j + 0.5 - half.y) / half.y
		for band in count:
			var color := ramp.sample((band + 0.5) / count)
			if color.a <= 0.0:
				continue
			var outer := Vector2i(0, cols - 1) if band == count - 1 else _band_cells(half.x, ny, float(band + 1) / count)
			outer = Vector2i(maxi(outer.x, 0), mini(outer.y, cols - 1))
			if outer.x > outer.y:
				continue
			var inner := _band_cells(half.x, ny, float(band) / count) if band > 0 else Vector2i(1, 0)
			var y := origin.y + j * pixel
			if inner.x > inner.y:
				item.draw_rect(Rect2(origin.x + outer.x * pixel, y, (outer.y - outer.x + 1) * pixel, pixel), color)
				continue
			if inner.x > outer.x:
				item.draw_rect(Rect2(origin.x + outer.x * pixel, y, (inner.x - outer.x) * pixel, pixel), color)
			if outer.y > inner.y:
				item.draw_rect(Rect2(origin.x + (inner.y + 1) * pixel, y, (outer.y - inner.y) * pixel, pixel), color)


## First and last column (cells) of a row at height ny (-1..1) whose centres are closer to the
## middle than distance (0..1, 1 = corner); first > last when none is.
static func _band_cells(half_x: float, ny: float, distance: float) -> Vector2i:
	var squared := 2.0 * distance * distance - ny * ny
	if squared <= 0.0:
		return Vector2i(1, 0)
	var reach := sqrt(squared) * half_x
	return Vector2i(ceili(half_x - reach - 0.5), floori(half_x + reach - 0.5))


## A colour ramp in steps hard steps as a texture one texel high and steps texels wide (sampled once
## per step): stretch it over a TextureRect with nearest filtering for a banded shade instead of a
## smooth GradientTexture2D.
static func stepped_ramp_texture(ramp: Gradient, steps := 4) -> ImageTexture:
	var count := maxi(1, steps)
	var image := Image.create_empty(count, 1, false, Image.FORMAT_RGBA8)
	for step in count:
		image.set_pixel(step, 0, ramp.sample((step + 0.5) / count))
	return ImageTexture.create_from_image(image)


## The first row (texels) of region in which at least SURFACE_SHARE of the pixels are opaque: where
## the walkable top of a platform picture begins (rivets, rails or air above it do not count).
## Platforms shift their picture up by this many art pixels so the feet stand on the drawn slab
## (FS1: the player stood 6-8 px above the moving and tilting platforms). Cached per picture and
## region; fallback when the picture cannot be read.
static func surface_row(texture: Texture2D, region: Rect2i, fallback := 0) -> int:
	if texture == null:
		return fallback
	var id := texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id())
	var key := "%s|%s" % [id, region]
	if _surface_rows.has(key):
		return _surface_rows[key]
	var image := texture.get_image()
	var row := fallback
	if image != null:
		if image.is_compressed():
			image.decompress()
		var area := region.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		for y in range(area.position.y, area.end.y):
			var opaque := 0
			for x in range(area.position.x, area.end.x):
				if image.get_pixel(x, y).a > 0.5:
					opaque += 1
			if area.size.x > 0 and opaque >= area.size.x * SURFACE_SHARE:
				row = y - area.position.y
				break
	_surface_rows[key] = row
	return row


## Stand-in for a CanvasItem that only keeps the rectangles drawn into it (tests; SidePixels' *_rects).
class Recorder extends RefCounted:
	var rects: Array[Rect2] = []

	func draw_rect(area: Rect2, _color: Color, _filled := true, _width := -1.0, _antialiased := false) -> void:
		rects.append(area)


## Stand-in for a CanvasItem in tests and previews: paints every draw_rect into an Image (alpha
## blended over what is there; origin = where the item's (0, 0) lies in the image) and keeps the
## rectangles, so shapes can be checked and looked at without a renderer.
class Raster extends RefCounted:
	var image: Image
	var origin := Vector2.ZERO
	var rects: Array[Rect2] = []

	func _init(size: Vector2i, image_origin := Vector2.ZERO, background := Color(0, 0, 0, 0)) -> void:
		image = Image.create_empty(maxi(1, size.x), maxi(1, size.y), false, Image.FORMAT_RGBA8)
		image.fill(background)
		origin = image_origin

	func draw_rect(area: Rect2, color: Color, _filled := true, _width := -1.0, _antialiased := false) -> void:
		rects.append(area)
		var start := Vector2i((area.position + origin).round())
		var end := Vector2i((area.end + origin).round())
		for y in range(maxi(0, start.y), mini(image.get_height(), end.y)):
			for x in range(maxi(0, start.x), mini(image.get_width(), end.x)):
				image.set_pixel(x, y, image.get_pixel(x, y).blend(color))

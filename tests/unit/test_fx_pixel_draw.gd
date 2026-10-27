extends GutTest
## D-218 "Nur Pixel-Effekte": PixelDraw builds every shape from whole art pixels on the grid (no
## smoothed edges, no soft gradients), and the effects that use it keep that rule: telegraph circles
## (PlaceholderShape), aim lines (PixelLine), stomp rings (PixelRingWave), bursts and stepped glows.

const PIXEL := PixelDraw.WORLD_PIXEL


func _on_grid(value: float, pixel := PIXEL) -> bool:
	return is_equal_approx(fposmod(value, pixel), 0.0) or is_equal_approx(fposmod(value, pixel), pixel)


func _assert_rects_on_grid(rects: Array[Rect2], pixel := PIXEL) -> void:
	assert_gt(rects.size(), 0, "something was drawn")
	for area in rects:
		assert_true(_on_grid(area.position.x, pixel) and _on_grid(area.position.y, pixel), "starts on the grid: %s" % area)
		assert_true(_on_grid(area.size.x, pixel) and _on_grid(area.size.y, pixel), "whole art pixels: %s" % area)


## Distinct alpha values of the painted pixels.
func _alphas(image: Image) -> Dictionary:
	var found := {}
	for y in image.get_height():
		for x in image.get_width():
			found[snappedf(image.get_pixel(x, y).a, 0.01)] = true
	return found


func test_disc_is_whole_art_pixels_and_hard_edged() -> void:
	var raster := PixelDraw.Raster.new(Vector2i(80, 80), Vector2(40, 40))
	PixelDraw.disc(raster, Vector2(0.7, -0.4), 30.0, Color.RED)
	_assert_rects_on_grid(raster.rects)
	var alphas := _alphas(raster.image)
	assert_eq(alphas.size(), 2, "only empty and full pixels, no anti-aliasing: %s" % str(alphas.keys()))
	var area := 0.0
	for rect in raster.rects:
		area += rect.get_area()
	assert_almost_eq(area, PI * 30.0 * 30.0, PI * 30.0 * 30.0 * 0.06, "about the area of the circle")


func test_disc_is_symmetric() -> void:
	var raster := PixelDraw.Raster.new(Vector2i(60, 60), Vector2(30, 30))
	PixelDraw.disc(raster, Vector2.ZERO, 17.0, Color.WHITE)
	var image := raster.image
	var uneven := 0
	for y in 60:
		for x in 60:
			if image.get_pixel(x, y).a != image.get_pixel(59 - x, y).a or image.get_pixel(x, y).a != image.get_pixel(x, 59 - y).a:
				uneven += 1
	assert_eq(uneven, 0, "mirrored left/right and top/bottom")


func test_ring_is_closed_and_thin() -> void:
	var raster := PixelDraw.Raster.new(Vector2i(100, 100), Vector2(50, 50))
	PixelDraw.ring(raster, Vector2.ZERO, 40.0, Color.WHITE)
	_assert_rects_on_grid(raster.rects)
	var image := raster.image
	# Every ray from the centre crosses the ring (no gaps), and the middle stays empty.
	for i in 72:
		var direction := Vector2.from_angle(TAU * i / 72.0)
		var hit := false
		for step in range(60, 84):
			var point := Vector2(50, 50) + direction * step * 0.5
			if image.get_pixelv(Vector2i(point)).a > 0.0:
				hit = true
				break
		assert_true(hit, "ring closed at %d degrees" % (i * 5))
	assert_eq(image.get_pixel(50, 50).a, 0.0, "a ring, not a disc")


func test_arc_covers_the_share_from_the_top() -> void:
	var raster := PixelDraw.Raster.new(Vector2i(60, 60), Vector2(30, 30))
	PixelDraw.arc(raster, Vector2.ZERO, 20.0, -PI * 0.5, TAU * 0.25, Color.WHITE)
	_assert_rects_on_grid(raster.rects)
	var image := raster.image
	assert_gt(image.get_pixel(31, 11).a, 0.0, "starts at the top")
	assert_gt(image.get_pixel(49, 29).a, 0.0, "reaches the right after a quarter")
	assert_eq(image.get_pixel(11, 30).a, 0.0, "nothing on the left")
	assert_eq(image.get_pixel(30, 49).a, 0.0, "nothing at the bottom")


func test_lines_draw_every_pixel_once() -> void:
	var raster := PixelDraw.Raster.new(Vector2i(120, 80), Vector2.ZERO)
	PixelDraw.polyline(raster, PackedVector2Array([Vector2(3, 5), Vector2(60, 40), Vector2(110, 10)]), Color(1, 0, 0, 0.5), 3)
	_assert_rects_on_grid(raster.rects)
	var alphas := _alphas(raster.image)
	assert_eq(alphas.size(), 2, "see-through lines stay even, no darker joints: %s" % str(alphas.keys()))


func test_dashed_line_has_gaps() -> void:
	var raster := PixelDraw.Raster.new(Vector2i(60, 8), Vector2.ZERO)
	PixelDraw.dashed_line(raster, Vector2(0, 2), Vector2(58, 2), Color.WHITE, 3, 2)
	_assert_rects_on_grid(raster.rects)
	var on := 0
	for x in 60:
		if raster.image.get_pixel(x, 2).a > 0.0:
			on += 1
	assert_almost_eq(float(on) / 60.0, 0.6, 0.1, "3 on, 2 off")


func test_diamond_polygon_is_a_pixel_diamond() -> void:
	var raster := PixelDraw.Raster.new(Vector2i(20, 20), Vector2(10, 10))
	# The centre pixel straddles the origin: moved by half a pixel, the outline lies on the grid.
	var points := PixelDraw.diamond_points(2)
	for i in points.size():
		points[i] += Vector2.ONE * PIXEL * 0.5
	PixelDraw.polygon(raster, points, Color.WHITE)
	var cells := 0
	for y in 20:
		for x in 20:
			if raster.image.get_pixel(x, y).a > 0.0:
				cells += 1
	assert_eq(cells, 13 * 4, "1 + 3 + 5 + 3 + 1 art pixels of 2 x 2 px")


func test_stepped_glow_texture_has_only_hard_steps() -> void:
	var ramp := Gradient.new()
	ramp.set_color(0, Color.WHITE)
	ramp.set_color(1, Color(1, 1, 1, 0))
	var texture := PixelDraw.stepped_glow_texture(20, ramp, 4)
	assert_eq(texture.get_size(), Vector2(40, 40), "one texel per art pixel")
	var alphas := _alphas(texture.get_image())
	assert_eq(alphas.size(), 5, "four steps and the empty corners: %s" % str(alphas.keys()))
	assert_same(PixelDraw.stepped_glow_texture(20, ramp, 4), texture, "cached")


func test_stepped_values() -> void:
	assert_eq(PixelDraw.stepped(1.0, 4), 1.0)
	assert_eq(PixelDraw.stepped(0.6, 4), 0.75)
	assert_eq(PixelDraw.stepped(0.0, 4), 0.0)


func test_telegraph_circle_is_pixel_art() -> void:
	var raster := PixelDraw.Raster.new(Vector2i(100, 100), Vector2(50, 50))
	PlaceholderShape.paint_circle(raster, 46.0, Color(1, 0.15, 0.1, 0.3), Color(1, 0.2, 0.1, 0.9))
	_assert_rects_on_grid(raster.rects)
	var alphas := _alphas(raster.image)
	assert_eq(alphas.size(), 3, "empty, fill and rim only: %s" % str(alphas.keys()))


func test_telegraph_circle_redraws_on_the_world_grid() -> void:
	var shape := PlaceholderShape.new()
	add_child_autofree(shape)
	shape.position = Vector2(10.3, 7.9)
	shape.scale = Vector2.ONE * 0.5
	assert_eq(shape.radius, 12.0, "same properties as before")
	await wait_process_frames(2)
	assert_true(shape.is_visible_in_tree())


func test_pixel_line_hides_the_smooth_line() -> void:
	var scene := load("res://enemies/enemy_base.tscn") as PackedScene
	var enemy := scene.instantiate()
	var line := enemy.get_node(^"TelegraphLine") as Line2D
	assert_true(line is PixelLine, "enemy aim lines are pixel lines")
	assert_not_null(line.gradient, "the engine's smooth line is see-through")
	assert_eq(line.gradient.sample(0.5).a, 0.0)
	assert_eq(PixelLine.pixels_for_width(2.0), 1, "width 2 = one art pixel")
	assert_eq(PixelLine.pixels_for_width(3.0), 2, "a locked turret line is thicker")
	enemy.free()


func test_ring_wave_grows_and_fades_in_steps() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	var ring := PixelRingWave.spawn(root, Vector2(5, 5), 60.0, Color.ORANGE, 0.4, 7.0, 0.15)
	assert_not_null(ring)
	assert_eq(ring.thickness, 4, "7 px wide = 4 art pixels")
	ring.progress = 0.0
	assert_almost_eq(ring.get_current_radius(), 9.0, 0.01)
	ring.progress = 0.5
	assert_gt(ring.get_current_radius(), 45.0, "eases out")
	var fades := {}
	for i in 11:
		ring.progress = i / 10.0
		fades[ring.get_fade()] = true
	assert_eq(fades.size(), PixelRingWave.FADE_STEPS + 1, "full, steps, gone: %s" % str(fades.keys()))


func test_burst_particles_are_whole_art_pixels() -> void:
	assert_eq(Burst.particle_size(4.0), 4.0)
	assert_eq(Burst.particle_size(5.0), 4.0)
	assert_eq(Burst.particle_size(1.0), 2.0, "at least one art pixel")
	var ramp := Burst.stepped_fade(Color.RED)
	assert_eq(ramp.interpolation_mode, Gradient.GRADIENT_INTERPOLATE_CONSTANT, "fades in hard steps")
	assert_eq(ramp.get_point_count(), Burst.FADE_STEPS + 1)

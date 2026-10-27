extends GutTest
## Report #2e95d42c (23.10.2026, "Der Kreis ist hässlich. Alles in Pixeloptik"): the marker of Flint's
## village tour is a pixel ellipse: only colours of Flint's flame palette (D-198), no soft edges, a
## closed line one pixel wide, pulsing in whole pixels, drawn on the art pixel grid without smoothing.


func test_ring_has_only_flint_colours_and_hard_edges() -> void:
	var image := VillageTour.ring_image(VillageTour.RING_RADIUS_X, VillageTour.RING_RADIUS_Y)
	var allowed := [VillageTour.RING_COLOR, VillageTour.RING_LIGHT, Color(VillageTour.RING_EMBER, 0.55)]
	var used := 0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a == 0.0:
				continue
			used += 1
			var known := false
			for wanted: Color in allowed:
				if color.is_equal_approx(wanted) or (absf(color.r - wanted.r) < 0.01 and absf(color.g - wanted.g) < 0.01 \
						and absf(color.b - wanted.b) < 0.01 and absf(color.a - wanted.a) < 0.01):
					known = true
			assert_true(known, "pixel (%d, %d) %s is a palette colour" % [x, y, color])
	assert_gt(used, 100, "a visible ring")


func test_ring_line_is_closed() -> void:
	var cells := VillageTour.ellipse_cells(VillageTour.RING_RADIUS_X, VillageTour.RING_RADIUS_Y)
	var cell_set := {}
	for cell in cells:
		cell_set[cell] = true
	for cell in cells:
		var neighbours := 0
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if (dx != 0 or dy != 0) and cell_set.has(cell + Vector2i(dx, dy)):
					neighbours += 1
		assert_gte(neighbours, 2, "%s continues on both sides" % cell)
	assert_true(cell_set.has(Vector2i(VillageTour.RING_RADIUS_X, 0)) and cell_set.has(Vector2i(0, VillageTour.RING_RADIUS_Y)), "half axes reached")


func test_pulse_moves_in_whole_pixel_steps() -> void:
	var seen := {}
	for i in 60:
		var step := VillageTour.pulse_step(i * 0.05)
		assert_between(step, 0, VillageTour.PULSE_STEPS - 1)
		seen[step] = true
	assert_eq(seen.size(), VillageTour.PULSE_STEPS, "every size shows")
	var small := VillageTour.ring_texture(0).get_size()
	var big := VillageTour.ring_texture(VillageTour.PULSE_STEPS - 1).get_size()
	assert_eq(big - small, Vector2(2, 2) * (VillageTour.PULSE_STEPS - 1), "one art pixel per step and side")


func test_positions_and_alpha_are_stepped() -> void:
	assert_eq(VillageTour.snap_to_art(Vector2(101.2, 57.9)), Vector2(102, 58))
	for alpha in [0.1, 0.3, 0.6, 0.99]:
		var stepped := VillageTour.stepped_alpha(alpha)
		assert_almost_eq(fmod(stepped * VillageTour.ALPHA_STEPS, 1.0), 0.0, 0.0001, "%s -> %s" % [alpha, stepped])
	assert_eq(VillageTour.stepped_alpha(0.0), 0.0)


func test_the_marker_draws_without_smoothing() -> void:
	var marker := VillageTour.new()
	add_child_autofree(marker)
	var drawing := marker.get_node(^"HighlightLayer/Highlight") as CanvasItem
	assert_eq(drawing.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)

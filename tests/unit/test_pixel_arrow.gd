extends GutTest
## The co-op arrows in pixel style (feedback #a1a651ae 23.10.2026): PixelArrow turns the 16 px arrow
## in art pixels with nearest sampling (no smoothed in-between colours), the wait arrow and the
## arrows to mates off screen draw it with nearest filtering.


func _colours(image: Image) -> Dictionary:
	var found := {}
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.0:
				found[pixel.to_html()] = true
	return found


func test_turned_arrows_keep_the_art_colours() -> void:
	var source := PixelArrow.source_image()
	var allowed := _colours(source)
	for i in PixelArrow.DIRECTIONS:
		var image := PixelArrow.texture_for(TAU * i / PixelArrow.DIRECTIONS).get_image()
		assert_eq(image.get_size(), Vector2i(PixelArrow.CANVAS, PixelArrow.CANVAS))
		for colour: String in _colours(image):
			assert_true(allowed.has(colour), "direction %d: no smoothed colour %s" % [i, colour])
		for y in image.get_height():
			for x in image.get_width():
				var alpha := image.get_pixel(x, y).a
				assert_true(alpha == 0.0 or alpha == 1.0, "hard edges only")


func test_the_picture_points_where_asked() -> void:
	assert_eq(PixelArrow.direction_index(0.0), 0)
	assert_eq(PixelArrow.direction_index(PI * 0.5), PixelArrow.DIRECTIONS / 4)
	assert_eq(PixelArrow.direction_index(-PI * 0.5), PixelArrow.DIRECTIONS * 3 / 4)
	var right := PixelArrow.texture_for(0.0).get_image()
	var down := PixelArrow.texture_for(PI * 0.5).get_image()
	# The tip: the opaque pixel farthest along the direction.
	assert_gt(_extent(right, Vector2.RIGHT), PixelArrow.CANVAS * 0.5, "right arrow reaches right")
	assert_gt(_extent(down, Vector2.DOWN), PixelArrow.CANVAS * 0.5, "down arrow reaches down")


func _extent(image: Image, direction: Vector2) -> float:
	var best := -INF
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				best = maxf(best, Vector2(x, y).dot(direction))
	return best


func test_the_wait_arrow_is_a_pixel_sprite() -> void:
	var line := CoopWaitLine.new()
	add_child_autofree(line)
	var arrow := line.get_node("Arrow") as Sprite2D
	assert_not_null(arrow, "a sprite, not a smooth polygon")
	assert_eq(arrow.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_eq(arrow.scale, Vector2.ONE * UiKit.ART_SCALE, "whole art pixels")
	var pointers := MatePointers.new()
	add_child_autofree(pointers)
	assert_eq(pointers.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)

extends GutTest
## Organic water (M1, playtest 15.10.2026): pools and puddles drawn per pixel without the tile grid,
## one water palette per biome for both, shapes from the tiles (no dungeon RNG), slow shimmer.

const RECT_POOL: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_room_water_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _frame(texture: Texture2D, frame: int, size: Vector2i) -> Image:
	return texture.get_image().get_region(Rect2i(Vector2i(frame * size.x, 0), size))


func test_pools_are_the_connected_water_areas() -> void:
	var tiles: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(5, 5), Vector2i(5, 6), Vector2i(1, 1)]
	var pools := ShallowWater.pools(tiles)
	assert_eq(pools.size(), 2)
	assert_eq(pools[0].size() + pools[1].size(), 5)


func test_a_pool_has_no_grid_outline() -> void:
	var texture := WaterArt.pool_strip(RECT_POOL, &"crypt")
	var size := Vector2i(3, 2) * WaterArt.TILE
	assert_eq(texture.get_width(), size.x * WaterArt.FRAMES, "four frames side by side")
	assert_eq(texture.get_height(), size.y)
	var image := _frame(texture, 0, size)
	# Corners round: the tile corner pixels stay floor, the middle is water.
	for corner: Vector2i in [Vector2i(0, 0), Vector2i(size.x - 1, 0), Vector2i(0, size.y - 1), Vector2i(size.x - 1, size.y - 1)]:
		assert_eq(image.get_pixelv(corner).a, 0.0, "corner %s clear" % corner)
	assert_gt(image.get_pixelv(size / 2).a, 0.5, "water in the middle")
	# The long edges wave: the first water row differs from column to column.
	var tops := {}
	for x in range(12, size.x - 12):
		for y in size.y:
			if image.get_pixel(x, y).a > 0.0:
				tops[y] = true
				break
	assert_gt(tops.size(), 2, "the north shore is no straight line (%s)" % [tops.keys()])
	# Never outside its tiles, never on their very edge.
	for y in size.y:
		for x in [0, size.x - 1]:
			assert_eq(image.get_pixel(x, y).a, 0.0, "edge column clear at %d" % y)


func test_inner_corners_swing_round() -> void:
	# An L: the inner corner (tile corner (2, 1) * 32) keeps floor in a wide arc around it.
	var tiles: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]
	var water: Dictionary[Vector2i, bool] = {}
	for tile in tiles:
		water[tile] = true
	var corner := Vector2(1, 1) * WaterArt.TILE
	assert_lt(WaterArt.edge_distance(corner + Vector2(2, 2), water), 0.0, "next to the inner corner: floor")
	assert_lt(WaterArt.edge_distance(corner + Vector2(-3, 3), water), 0.0, "diagonal in the arc: floor")
	assert_gt(WaterArt.edge_distance(corner + Vector2(-14, -14), water), 0.0, "further in: water")


func test_shape_comes_from_the_tiles_only() -> void:
	var a := WaterArt.pool_strip(RECT_POOL, &"slime_grotto")
	var b := WaterArt.pool_strip(RECT_POOL.duplicate(), &"slime_grotto")
	assert_eq(a, b, "same tiles, same picture (cached)")
	assert_eq(WaterArt.seed_of(RECT_POOL), WaterArt.seed_of(RECT_POOL.duplicate()))
	var moved: Array[Vector2i] = []
	for tile in RECT_POOL:
		moved.append(tile + Vector2i(4, 0))
	assert_ne(WaterArt.seed_of(moved), WaterArt.seed_of(RECT_POOL), "another place, another shape")


func test_pools_and_puddles_share_the_biome_palette() -> void:
	var size := Vector2i(3, 2) * WaterArt.TILE
	var seen := {}
	for biome: StringName in [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]:
		var colors := WaterArt.palette(biome)
		var allowed := {}
		for key in colors:
			var color: Color = colors[key]
			allowed[Color(color.r, color.g, color.b).to_html(false)] = true
		var pool := _frame(WaterArt.pool_strip(RECT_POOL, biome), 0, size)
		var puddle := _frame(WaterArt.puddle_strip(biome, 3), 0, Vector2i(WaterArt.TILE, WaterArt.TILE))
		var body := 0
		for image: Image in [pool, puddle]:
			for y in image.get_height():
				for x in image.get_width():
					var pixel := image.get_pixel(x, y)
					if pixel.a == 0.0:
						continue
					var key := Color(pixel.r, pixel.g, pixel.b).to_html(false)
					if allowed.has(key) or _is_between(pixel, colors["body"], colors["deep"]) or _is_between(pixel, colors["body"], colors["reflect"]) or _is_between(pixel, colors["deep"], colors["reflect"]):
						body += 1
					else:
						fail_test("%s: colour %s outside the water palette" % [biome, key])
						return
		assert_gt(body, 100, "%s: water drawn" % biome)
		var body_key := (colors["body"] as Color).to_html(false)
		assert_false(seen.has(body_key), "%s: own water colour" % biome)
		seen[body_key] = true


## Is c on the line between colours a and b (blends of the depth bands)?
func _is_between(c: Color, a: Color, b: Color) -> bool:
	for i in 41:
		var t := i / 40.0
		var mix := a.lerp(b, t)
		if absf(mix.r - c.r) < 0.012 and absf(mix.g - c.g) < 0.012 and absf(mix.b - c.b) < 0.012:
			return true
	return false


func test_shimmer_changes_from_frame_to_frame() -> void:
	var size := Vector2i(3, 2) * WaterArt.TILE
	var texture := WaterArt.pool_strip(RECT_POOL, &"shadow_realm")
	assert_ne(_frame(texture, 0, size).get_data(), _frame(texture, 1, size).get_data(), "ripples and glints move")


func test_shallow_water_draws_one_picture_per_pool_and_slows_per_tile() -> void:
	var water := ShallowWater.new()
	add_child_autofree(water)
	var tiles: Array[Vector2i] = RECT_POOL.duplicate()
	tiles.append(Vector2i(8, 8))
	water.build(tiles, 32.0, &"crypt")
	var pictures := 0
	for child in water.get_children():
		if child is AnimatedProp:
			pictures += 1
	assert_eq(pictures, 2, "two pools")
	assert_eq(water.get_node("Area").get_child_count(), tiles.size(), "slow area stays on the tiles")

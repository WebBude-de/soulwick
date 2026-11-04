extends GutTest
## Where decoration may stand (WK5, WK7, DecorGrid): the home's grid (floor, back wall, window slots,
## the cells of altar, mirror, broom, stand and door), the three layers (flat under standing, wall),
## no blocking piece on a player, and the way check (every free floor cell reachable from the door).
## Pure data, no save file.


func _placements(list: Array) -> Array[Dictionary]:
	return DecorState.parse_list(PackedStringArray(list))


func _starter() -> Array[Dictionary]:
	return _placements(DecorState.STARTER_HOME)


func test_home_grid_matches_the_room() -> void:
	var grid := DecorGrid.for_home()
	assert_eq(grid.size, Vector2i(HomeLayout.COLS, HomeLayout.ROWS))
	assert_almost_eq(grid.tile, 64.0, 0.01, "32 px tiles at scale 2")
	assert_true(grid.floor_cells.has(Vector2i(0, HomeLayout.WALL_ROWS)), "floor starts under the back wall")
	assert_false(grid.floor_cells.has(Vector2i(3, 1)), "the back wall is no floor")
	assert_false(grid.floor_cells.has(HomeLayout.DOOR_CELL), "nothing on the door")
	assert_true(grid.wall_cells.has(Vector2i(6, 1)))
	for col in HomeLayout.WINDOW_COLS:
		assert_true(grid.window_cells.has(Vector2i(col, 1)), "a window slot under window %d" % col)
	assert_eq(grid.window_cells.size(), HomeLayout.WINDOW_COLS.size(), "KE8b: three windows")


func test_the_starter_set_fits_its_own_grid() -> void:
	var grid := DecorGrid.for_home()
	var placements := _starter()
	assert_eq(placements.size(), DecorState.STARTER_HOME.size(), "every entry parses")
	for entry in placements:
		var item := DecorCatalog.get_item(String(entry["id"]))
		assert_not_null(item, String(entry["id"]))
		assert_eq(grid.check(item, entry["cell"], int(entry["rot"]), placements, int(entry["index"])), DecorGrid.OK,
			"%s fits where it stands" % entry["id"])
	assert_true(grid.keeps_way(placements), "nobody is walled in")
	# KE8b: placed one after another (the way the migration and fit_list do it) every piece fits too.
	var fit := DecorState.fit_list(PackedStringArray(DecorState.STARTER_HOME), grid)
	assert_eq(fit["stored"], PackedStringArray(), "nothing of the starter set goes to the storage")


func test_ke8b_the_room_is_small_and_furnished() -> void:
	assert_eq(Vector2i(HomeLayout.COLS, HomeLayout.ROWS), Vector2i(11, 7), "TESTWERT: 11×7 tiles")
	var grid := DecorGrid.for_home()
	var covered := {}
	for entry in _starter():
		var item := DecorCatalog.get_item(String(entry["id"]))
		if item.is_wall():
			continue
		for cell in DecorGrid.cells_of(item, entry["cell"], int(entry["rot"])):
			covered[cell] = true
	var share := float(covered.size()) / float(grid.floor_cells.size())
	assert_gt(share, 0.35, "the floor is lived in (%d of %d cells)" % [covered.size(), grid.floor_cells.size()])
	var walls := 0
	for entry in _starter():
		if DecorCatalog.get_item(String(entry["id"])).is_wall():
			walls += 1
	assert_gte(walls, 3, "things hang on the wall")


func test_standing_pieces_never_overlap_but_a_rug_lies_under_them() -> void:
	var grid := DecorGrid.for_home()
	var placements := _placements(["armchair_cozy:3:5:0"])
	assert_eq(grid.check(DecorCatalog.get_item("chair_cozy"), Vector2i(3, 5), 0, placements), DecorGrid.REASON_TAKEN)
	assert_eq(grid.check(DecorCatalog.get_item("rug_small_cozy"), Vector2i(2, 5), 0, placements), DecorGrid.OK, "rug under the chair")
	var with_rug := _placements(["rug_small_cozy:2:5:0"])
	assert_eq(grid.check(DecorCatalog.get_item("rug_round_cozy"), Vector2i(3, 5), 0, with_rug), DecorGrid.REASON_TAKEN, "rugs do not overlap")


func test_wall_pieces_hang_on_the_back_wall_and_keep_the_window_free() -> void:
	var grid := DecorGrid.for_home()
	var picture := DecorCatalog.get_item("picture_village_rustic")
	assert_eq(grid.check(picture, Vector2i(6, 1), 0, []), DecorGrid.OK)
	assert_eq(grid.check(picture, Vector2i(6, 4), 0, []), DecorGrid.REASON_WALL, "not on the floor")
	assert_eq(grid.check(picture, Vector2i(HomeLayout.WINDOW_COLS[0], 1), 0, []), DecorGrid.REASON_WALL, "not over the window")
	var box := DecorCatalog.get_item("window_box_cozy")
	assert_eq(grid.check(box, Vector2i(HomeLayout.WINDOW_COLS[0], 1), 0, []), DecorGrid.OK, "the window box belongs there")
	var chair := DecorCatalog.get_item("chair_cozy")
	assert_eq(grid.check(chair, Vector2i(6, 1), 0, []), DecorGrid.REASON_PLACE, "furniture stands on the floor")


func test_altar_mirror_spawn_and_door_stay_free() -> void:
	var grid := DecorGrid.for_home()
	var chest := DecorCatalog.get_item("chest_cozy")
	assert_eq(grid.check(chest, HomeLayout.DOOR_CELL, 0, []), DecorGrid.REASON_PLACE, "door")
	assert_eq(grid.check(chest, Vector2i(5, 2), 0, []), DecorGrid.REASON_PLACE, "altar")
	assert_eq(grid.check(chest, Vector2i(7, 2), 0, []), DecorGrid.REASON_PLACE, "mirror")
	assert_eq(grid.check(chest, Vector2i(5, 5), 0, []), DecorGrid.REASON_PLACE, "spawn")
	assert_eq(grid.check(chest, Vector2i(4, 6), 0, []), DecorGrid.REASON_PLACE, "catalog stand")
	assert_eq(grid.check(chest, Vector2i(6, 6), 0, []), DecorGrid.REASON_PLACE, "broom")
	var rug := DecorCatalog.get_item("rug_small_cozy")
	assert_eq(grid.check(rug, Vector2i(5, 5), 0, []), DecorGrid.OK, "a rug may lie at the spawn")


func test_a_blocking_piece_is_never_set_on_a_player() -> void:
	var grid := DecorGrid.for_home()
	var chest := DecorCatalog.get_item("chest_cozy")
	var feet: Array[Vector2] = [Vector2(3.5, 5.5) * grid.tile]
	assert_eq(grid.check(chest, Vector2i(3, 5), 0, [], -1, feet), DecorGrid.REASON_PLAYER)
	assert_eq(grid.check(DecorCatalog.get_item("rug_small_cozy"), Vector2i(3, 5), 0, [], -1, feet), DecorGrid.OK, "walk on rugs")


func test_nobody_walls_in_a_corner() -> void:
	var grid := DecorGrid.for_home()
	var chest := DecorCatalog.get_item("chest_cozy")
	var placements := _placements(["chest_cozy:1:6:0"])
	assert_eq(grid.check(chest, Vector2i(0, 5), 0, placements), DecorGrid.REASON_WAY, "the corner tile would be cut off")
	assert_eq(grid.check(chest, Vector2i(0, 4), 0, placements), DecorGrid.OK)


func test_the_altar_keeps_a_free_side() -> void:
	var grid := DecorGrid.for_home()
	var chest := DecorCatalog.get_item("chest_cozy")
	var placements := _placements(["chest_cozy:4:2:0", "chest_cozy:6:2:0"])
	assert_eq(grid.check(chest, Vector2i(5, 3), 0, placements), DecorGrid.REASON_WAY, "altar closed in")


func test_moving_a_piece_ignores_its_old_place() -> void:
	var grid := DecorGrid.for_home()
	var placements := _placements(["sofa_cozy:6:5:0"])
	var sofa := DecorCatalog.get_item("sofa_cozy")
	assert_eq(grid.check(sofa, Vector2i(7, 5), 0, placements), DecorGrid.REASON_TAKEN)
	assert_eq(grid.check(sofa, Vector2i(7, 5), 0, placements, 0), DecorGrid.OK, "one step to the right")
	assert_eq(grid.placement_at(placements, Vector2i(8, 5)), 0)
	assert_eq(grid.placement_at(placements, Vector2i(9, 5)), -1)


func test_cells_and_foot_points() -> void:
	var grid := DecorGrid.for_home()
	var bed := DecorCatalog.get_item("bed_single_cozy")
	assert_eq(DecorGrid.cells_of(bed, Vector2i(1, 2), 0).size(), 6, "2×3")
	assert_eq(grid.foot_of(bed, Vector2i(1, 2), 0), Vector2(2 * 64.0, 5 * 64.0), "bottom centre of the footprint")
	var picture := DecorCatalog.get_item("tapestry_cozy")
	assert_eq(DecorGrid.cells_of(picture, Vector2i(4, 1), 0), [Vector2i(4, 1), Vector2i(5, 1)] as Array[Vector2i])
	assert_eq(grid.foot_of(picture, Vector2i(4, 1), 0), Vector2(5 * 64.0, 2 * 64.0), "hangs down to the wall's lower edge")
	assert_eq(grid.cell_at(Vector2(130, 70)), Vector2i(2, 1))

extends GutTest
## The seam of two joined rooms (M2, PassageSeam): with one tile of corridor the rooms paint over each
## other; every cell belongs to the room whose floor and wall ring hold it (the shared wall line to
## the room whose floor touches it), the other erases its copy and gets it back when the owner goes.

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_passage_seam_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func test_owner_of_the_shared_tiles() -> void:
	var size := Vector2i(15, 9)
	var end := ExitRules.exit_corridor_end(Vector2i.ZERO, size, ExitRules.NORTH, 7)
	var upper := ExitRules.origin_for(end, size, ExitRules.SOUTH, 7)
	assert_eq(upper.y + size.y, -2, "the upper room's south wall lies on the crown row")
	# The lower room's ring row -3 is the upper room's floor.
	assert_eq(PassageSeam.owner_of(Vector2i(3, -3), Vector2i.ZERO, size, upper, size), PassageSeam.Owner.SECOND)
	# The shared wall line: crown of the lower room, south wall of the upper one (its floor touches it).
	assert_eq(PassageSeam.owner_of(Vector2i(3, -2), Vector2i.ZERO, size, upper, size), PassageSeam.Owner.SECOND)
	# The front row of the lower room, under the upper room's ring.
	assert_eq(PassageSeam.owner_of(Vector2i(3, -1), Vector2i.ZERO, size, upper, size), PassageSeam.Owner.FIRST)
	# Rock on rock.
	assert_eq(PassageSeam.owner_of(Vector2i(-2, -3), Vector2i.ZERO, size, upper, size), PassageSeam.Owner.NONE)
	# West/east: the next room's wall column follows the door column.
	var side_end := ExitRules.exit_corridor_end(Vector2i.ZERO, size, ExitRules.EAST, 4)
	var east := ExitRules.origin_for(side_end, size, ExitRules.WEST, 4)
	assert_eq(east.x, size.x + 2)
	assert_eq(PassageSeam.owner_of(Vector2i(size.x, 2), Vector2i.ZERO, size, east, size), PassageSeam.Owner.FIRST, "this room's east wall")
	assert_eq(PassageSeam.owner_of(Vector2i(size.x + 1, 2), Vector2i.ZERO, size, east, size), PassageSeam.Owner.SECOND, "the next room's west wall")


func _room(index: int, origin: Vector2i, entrance: Vector2i, exit: Vector2i) -> RoomController:
	var room := HALL.instantiate() as RoomController
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	room.setup(index, RoomSequence.RoomType.COMBAT, -1, false, context)
	room.apply_door_plan(entrance, [exit] as Array[Vector2i])
	room.position = Vector2(origin) * RoomTiles.TILE_WORLD
	add_child_autofree(room)
	return room


## Walkable tiles of room (world) inside other's painted rectangle where other still has a cell that is
## no floor of its own.
func _foreign_rock(room: RoomController, other: RoomController) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var origin := PassageSeam.origin_of(room)
	var other_origin := PassageSeam.origin_of(other)
	var other_rect := other.tiles.get_painted_rect()
	var other_floor := other.tiles.get_floor_mask()
	for tile: Vector2i in room.tiles.get_walkable_tiles():
		var in_other := tile + origin - other_origin
		if other_rect.has_point(in_other) and other.tiles.get_cell_source_id(in_other) != -1 and not other_floor.has(in_other):
			found.append(tile + origin)
	return found


func test_joined_rooms_keep_their_floors_and_give_back_on_leave() -> void:
	var probe := HALL.instantiate() as RoomController
	var size := (probe.get_node("Tiles") as RoomTiles).room_size
	var place := (probe.get_node("Tiles") as RoomTiles).exit_x
	var entrance_x := (probe.get_node("Tiles") as RoomTiles).entrance_x
	probe.free()
	var lower := _room(3, Vector2i.ZERO, Vector2i(ExitRules.SOUTH, entrance_x), Vector2i(ExitRules.NORTH, place))
	var end := ExitRules.exit_corridor_end(Vector2i.ZERO, size, ExitRules.NORTH, place)
	var upper := _room(4, ExitRules.origin_for(end, size, ExitRules.SOUTH, entrance_x), Vector2i(ExitRules.SOUTH, entrance_x), Vector2i(ExitRules.NORTH, place))
	assert_false(_foreign_rock(upper, lower).is_empty(), "before the seam the lower room's ring lies on the upper floor")
	var erased := PassageSeam.join(lower, upper)
	assert_gt(erased, 0)
	assert_eq(_foreign_rock(upper, lower), [] as Array[Vector2i], "no rock of the lower room on the upper floor")
	assert_eq(_foreign_rock(lower, upper), [] as Array[Vector2i], "no rock of the upper room on the lower floor")
	var given := PassageSeam.get_erased(lower, upper)
	assert_false(given.is_empty())
	PassageSeam.release(upper, [lower])
	for cell in given:
		assert_ne(lower.tiles.get_cell_source_id(cell), -1, "cell %s is back" % cell)
	assert_true(PassageSeam.get_erased(lower, upper).is_empty())


## M1 finding: a room that leaves never gives cells back onto the floor or walls of a newer live room.
func test_release_keeps_clear_of_a_newer_room() -> void:
	var probe := HALL.instantiate() as RoomController
	var size := (probe.get_node("Tiles") as RoomTiles).room_size
	var place := (probe.get_node("Tiles") as RoomTiles).exit_x
	var entrance_x := (probe.get_node("Tiles") as RoomTiles).entrance_x
	probe.free()
	var lower := _room(3, Vector2i.ZERO, Vector2i(ExitRules.SOUTH, entrance_x), Vector2i(ExitRules.NORTH, place))
	var end := ExitRules.exit_corridor_end(Vector2i.ZERO, size, ExitRules.NORTH, place)
	var upper_origin := ExitRules.origin_for(end, size, ExitRules.SOUTH, entrance_x)
	var upper := _room(4, upper_origin, Vector2i(ExitRules.SOUTH, entrance_x), Vector2i(ExitRules.NORTH, place))
	PassageSeam.join(lower, upper)
	var given := PassageSeam.get_erased(lower, upper)
	assert_false(given.is_empty())
	# A newer room stands where the leaving one stood.
	var newer := _room(5, upper_origin, Vector2i(ExitRules.SOUTH, entrance_x), Vector2i(ExitRules.NORTH, place))
	PassageSeam.release(upper, [lower, newer])
	var body := ExitRules.body_rect_of(size)
	body.position += upper_origin
	var kept_clear := 0
	for cell in given:
		if body.has_point(cell):
			assert_eq(lower.tiles.get_cell_source_id(cell), -1, "cell %s stays off the newer room" % cell)
			kept_clear += 1
		else:
			assert_ne(lower.tiles.get_cell_source_id(cell), -1, "cell %s is back" % cell)
	assert_gt(kept_clear, 0)


## G2 (playtest 15.10.2026, notes 5/6): the rock row between two joined rooms is drawn from both
## floors - its edges towards both, like the rock over the passage - and gets its own pieces back
## when the other room leaves.
func test_shared_rock_is_drawn_from_both_floors() -> void:
	var probe := HALL.instantiate() as RoomController
	var size := (probe.get_node("Tiles") as RoomTiles).room_size
	var place := (probe.get_node("Tiles") as RoomTiles).exit_x
	var entrance_x := (probe.get_node("Tiles") as RoomTiles).entrance_x
	probe.free()
	var lower := _room(3, Vector2i.ZERO, Vector2i(ExitRules.SOUTH, entrance_x), Vector2i(ExitRules.NORTH, place))
	var end := ExitRules.exit_corridor_end(Vector2i.ZERO, size, ExitRules.NORTH, place)
	var upper := _room(4, ExitRules.origin_for(end, size, ExitRules.SOUTH, entrance_x), Vector2i(ExitRules.SOUTH, entrance_x), Vector2i(ExitRules.NORTH, place))
	if not lower.tiles.is_terrain_drawn() or not upper.tiles.is_terrain_drawn():
		pass_test("no rock terrain in this build")
		return
	var before: Dictionary = {}
	for room in [lower, upper]:
		var rock := (room as RoomController).tiles.get_rock_layer()
		for cell in rock.get_used_cells():
			before[[room, cell]] = rock.get_cell_atlas_coords(cell)
	PassageSeam.join(lower, upper)
	# Both floors without the door corridors (the passage lies under the rock, PassageCover).
	var union: Dictionary[Vector2i, bool] = {}
	var corridors: Dictionary[Vector2i, bool] = {}
	for room in [lower, upper]:
		var tiles := (room as RoomController).tiles
		var origin := PassageSeam.origin_of(room)
		for tile in tiles.get_door_corridor_tiles():
			corridors[tile + origin] = true
		for tile in tiles.get_floor_mask():
			if not tiles.get_door_corridor_tiles().has(tile):
				union[tile + origin] = true
	var checked := 0
	for pair in [[lower, upper], [upper, lower]]:
		var room: RoomController = pair[0]
		var rock := room.tiles.get_rock_layer()
		var origin := PassageSeam.origin_of(room)
		var source := RockTerrain.rock_source(room.tiles.get_look())
		for cell in PassageSeam.get_mended(room, pair[1]):
			assert_eq(rock.get_cell_atlas_coords(cell), RockTerrain.piece_for(cell + origin, union), "%s %s" % [room.name, cell])
			checked += 1
		# Every piece next to the other room's floor matches the pieces over the passage.
		var other_origin := PassageSeam.origin_of(pair[1])
		for tile in (pair[1] as RoomController).tiles.get_floor_mask():
			var near := tile + other_origin - origin + Vector2i.DOWN
			if rock.get_cell_source_id(near) == source and not union.has(near + origin) and not corridors.has(near + origin) and not RockTerrain.is_enclosed(near + origin, union):
				assert_eq(rock.get_cell_atlas_coords(near), RockTerrain.piece_for(near + origin, union), "%s %s below the other floor" % [room.name, near])
	gut.p("mended pieces: %d" % checked)
	PassageSeam.release(upper, [lower])
	var rock := lower.tiles.get_rock_layer()
	for cell in rock.get_used_cells():
		if before.has([lower, cell]):
			assert_eq(rock.get_cell_atlas_coords(cell), before[[lower, cell]], "piece %s is back" % cell)
	assert_true(PassageSeam.get_mended(lower, upper).is_empty())

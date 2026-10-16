extends GutTest
## The rock over a passage (M2 tunnel, PassageCover): the walls of both rooms drawn again as if the
## passage were not there - the crown runs closed over a north gate with the same piece as beside it,
## the fronts beside the gate are plain fronts, a side passage is closed over its door tile and the
## corridor, and no floor tile is ever covered.

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_passage_cover_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _room(index: int, origin: Vector2i, entrance: Vector2i, exit: Vector2i) -> RoomController:
	var room := HALL.instantiate() as RoomController
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	room.setup(index, RoomSequence.RoomType.COMBAT, -1, false, context)
	room.apply_door_plan(entrance, [exit] as Array[Vector2i])
	room.position = Vector2(origin) * RoomTiles.TILE_WORLD
	add_child_autofree(room)
	return room


func _probe() -> Dictionary:
	var probe := HALL.instantiate() as RoomController
	var tiles := probe.get_node("Tiles") as RoomTiles
	var info := {"size": tiles.room_size, "exit_x": tiles.exit_x, "entrance_x": tiles.entrance_x}
	probe.free()
	return info


func _cells(plan: Array[Dictionary]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for entry in plan:
		cells.append(entry["cell"])
	return cells


func _atlas_at(plan: Array[Dictionary], cell: Vector2i) -> Vector3i:
	for entry in plan:
		if entry["cell"] == cell:
			return entry["atlas"]
	return Vector3i(0, 0, -1)


func test_north_passage_is_closed_like_the_wall_beside_it() -> void:
	var info := _probe()
	var size: Vector2i = info["size"]
	var place: int = info["exit_x"]
	var lower := _room(3, Vector2i.ZERO, Vector2i(ExitRules.SOUTH, info["entrance_x"]), Vector2i(ExitRules.NORTH, place))
	var end := ExitRules.exit_corridor_end(Vector2i.ZERO, size, ExitRules.NORTH, place)
	var upper_origin := ExitRules.origin_for(end, size, ExitRules.SOUTH, info["entrance_x"])
	var upper := _room(4, upper_origin, Vector2i(ExitRules.SOUTH, info["entrance_x"]), Vector2i(ExitRules.NORTH, place))
	PassageSeam.join(lower, upper)
	var door_cell := RoomTiles.door_tile_of(ExitRules.NORTH, place, size)
	var passage := PassageCover.passage_cells(door_cell, Vector2i.UP, upper)
	assert_eq(passage.size(), 2, "door tile and one corridor tile")
	var plan := PassageCover.plan([lower, upper], door_cell, Vector2i.UP, true)
	var cells := _cells(plan)
	assert_false(cells.has(door_cell), "the arch and the gate show on the door tile")
	for a in [-1, 0, 1]:
		assert_true(cells.has(passage[1] + Vector2i(a, 0)), "corridor row covered, column %d" % a)
	assert_true(cells.has(door_cell + Vector2i.LEFT) and cells.has(door_cell + Vector2i.RIGHT), "fronts beside the door")
	var closed := PassageCover.closed_floor([lower, upper], passage)
	for cell in cells:
		assert_false(closed.has(cell), "no floor covered: %s" % cell)
	if lower.tiles.is_terrain_drawn():
		var source := RockTerrain.rock_source(lower.tiles.get_look())
		var front := RockTerrain.front_coords(RockTerrain.Front.MIDDLE)
		assert_eq(_atlas_at(plan, door_cell + Vector2i.LEFT), Vector3i(front.x, front.y, source), "plain front left")
		assert_eq(_atlas_at(plan, door_cell + Vector2i.RIGHT), Vector3i(front.x, front.y, source), "plain front right")
		# The crown over the corridor is the piece the upper room paints a few tiles beside it.
		var beside := passage[1] + Vector2i(3, 0)
		var rock := upper.tiles.get_rock_layer()
		var local := beside - PassageSeam.origin_of(upper)
		var painted := Vector3i(rock.get_cell_atlas_coords(local).x, rock.get_cell_atlas_coords(local).y, rock.get_cell_source_id(local))
		assert_eq(_atlas_at(plan, passage[1]), painted, "the crown runs straight through")


func test_side_passage_closes_the_side_wall() -> void:
	var info := _probe()
	var size: Vector2i = info["size"]
	var lower := HALL.instantiate() as RoomController
	var slots := (lower.get_node("Tiles") as RoomTiles).get_door_slots(ExitRules.EAST)
	var west_slots := (lower.get_node("Tiles") as RoomTiles).get_door_slots(ExitRules.WEST)
	lower.free()
	if slots.is_empty() or west_slots.is_empty():
		pass_test("the hall has no side doors")
		return
	var first := _room(3, Vector2i.ZERO, Vector2i(ExitRules.SOUTH, info["entrance_x"]), Vector2i(ExitRules.EAST, slots[0]))
	var end := ExitRules.exit_corridor_end(Vector2i.ZERO, size, ExitRules.EAST, slots[0])
	var second := _room(4, ExitRules.origin_for(end, size, ExitRules.WEST, west_slots[0]), Vector2i(ExitRules.WEST, west_slots[0]), Vector2i(ExitRules.NORTH, info["exit_x"]))
	PassageSeam.join(first, second)
	var door_cell := RoomTiles.door_tile_of(ExitRules.EAST, slots[0], size)
	var passage := PassageCover.passage_cells(door_cell, Vector2i.RIGHT, second)
	assert_eq(passage.size(), 2, "door tile and the next room's wall")
	var plan := PassageCover.plan([first, second], door_cell, Vector2i.RIGHT, false)
	var cells := _cells(plan)
	for cell in passage:
		for a in [-1, 0, 1]:
			assert_true(cells.has(cell + Vector2i(0, a)), "covered: %s" % (cell + Vector2i(0, a)))
	# G2: the rock over the upper wall (a front only while the passage was floor) is drawn again.
	var closed := PassageCover.closed_floor([first, second], passage)
	for cell in passage:
		var above := cell + Vector2i(0, -2)
		if not closed.has(above):
			assert_true(cells.has(above), "rock over the upper wall: %s" % above)
	for cell in cells:
		assert_false(closed.has(cell), "no floor covered: %s" % cell)
		assert_lte(absi(cell.y - door_cell.y), 2, "only the passage and the rock right around it: %s" % cell)

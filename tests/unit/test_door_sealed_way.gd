extends GutTest
## Bug report 26.10.2026 #51c557a8 (room 22, Schleimgrotte, "Das sieht verbuggt aus"): over the sealed
## north gate of a branch room a T of corridor floor stood in the rock. The lintel of the gate had been
## copied while the way behind it still stood (the light edge of its floor), and the room's corridor
## end came back when the way was freed (PassageSeam.release). Once the way has left the tree, the
## lintel of a sealed gate is built from the door's room alone (DoorView._on_way_left), like the wall
## over a blocked entrance (PassageCover.sealed_plan).

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_door_sealed_way_save.cfg"
	DoorArt.art_dir = DoorStyle.ART_DIR
	DoorArt.clear_cache()


func after_all() -> void:
	SaveManager.save_path = _old_save_path
	DoorArt.clear_cache()


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
	var info := {
		"size": tiles.room_size,
		"exit_x": tiles.exit_x,
		"entrance_x": tiles.entrance_x,
		"east": tiles.get_door_slots(ExitRules.EAST),
		"west": tiles.get_door_slots(ExitRules.WEST),
	}
	probe.free()
	return info


## The way not taken fades out like in DungeonManager._fade_out_way/_free_faded: the gate is sealed
## first, then the room gives back its cells and the way leaves the tree.
func _drop_way(gate: Door, lower: RoomController, way: RoomController) -> void:
	gate.seal()
	PassageSeam.release(way, [lower, way])
	remove_child(way)
	way.free()
	await wait_frames(2)


func _door_tile(gate: Door, room: RoomController) -> Vector2i:
	return room.tiles.local_to_map(room.tiles.to_local(gate.global_position + Vector2.ONE * RoomTiles.TILE_WORLD * 0.5))


func _region_of(tiles: RoomTiles, atlas: Vector3i) -> Rect2:
	var source := tiles.tile_set.get_source(atlas.z) as TileSetAtlasSource
	return Rect2(source.get_tile_texture_region(Vector2i(atlas.x, atlas.y)))


## Room-local cells covered by a lintel piece of the gate.
func _covered(gate: Door, door_tile: Vector2i) -> Dictionary:
	var cells := {}
	for piece in gate.view.get_lintel():
		cells[door_tile + Vector2i((piece.position / RoomTiles.TILE_WORLD).round())] = piece
	return cells


func test_sealed_north_gate_lintel_follows_its_room_once_the_way_is_gone() -> void:
	var info := _probe()
	var size: Vector2i = info["size"]
	var place: int = info["exit_x"]
	var lower := _room(3, Vector2i.ZERO, Vector2i(ExitRules.SOUTH, info["entrance_x"]), Vector2i(ExitRules.NORTH, place))
	var end := ExitRules.exit_corridor_end(Vector2i.ZERO, size, ExitRules.NORTH, place)
	var way := _room(4, ExitRules.origin_for(end, size, ExitRules.SOUTH, info["entrance_x"]), Vector2i(ExitRules.SOUTH, info["entrance_x"]), Vector2i(ExitRules.NORTH, place))
	PassageSeam.join(lower, way)
	var gate := GateCloser.gate_between(lower)
	gate.view.build_lintel([lower, way] as Array[Node2D])
	var door_tile := _door_tile(gate, lower)
	var crown := door_tile + Vector2i.UP
	var before: Sprite2D = _covered(gate, door_tile).get(crown)
	assert_not_null(before, "the crown over the gate is covered while the way stands")
	var before_region := before.region_rect if before != null else Rect2()
	assert_true(gate.view.is_tunnel())
	await _drop_way(gate, lower, way)
	assert_true(gate.view.is_way_gone())
	assert_false(gate.view.is_tunnel(), "nobody walks into a sealed gate")
	# The room's wall as if gap and corridor were not there (like a blocked entrance).
	var expected := {}
	for entry: Dictionary in PassageCover.sealed_plan(lower, door_tile, Vector2i.UP):
		expected[entry["cell"]] = entry["atlas"]
	var covered := _covered(gate, door_tile)
	for cell: Vector2i in PassageCover.sealed_cells(lower.tiles, door_tile, Vector2i.UP):
		assert_true(covered.has(cell), "corridor cell %s of the room lies under the rock" % cell)
	var compared := 0
	for cell: Vector2i in covered:
		var piece: Sprite2D = covered[cell]
		if not piece.region_enabled:
			continue  # the door tile with the opening of the arch cut out
		# Beyond the wall's own pieces only plain rock (the rock over the corridor's last front).
		var atlas: Vector3i = expected.get(cell, lower.tiles.get_rock_fill_cell())
		assert_eq(piece.region_rect, _region_of(lower.tiles, atlas), "piece %s at %s drawn like the room's wall" % [piece.name, cell])
		compared += 1
	assert_gt(compared, 2)
	var after: Sprite2D = covered.get(crown)
	assert_not_null(after)
	if after != null:
		assert_ne(after.region_rect, before_region, "the light edge of the way's floor is gone from the crown")


func test_open_gate_keeps_its_lintel_when_nothing_was_sealed() -> void:
	var info := _probe()
	var size: Vector2i = info["size"]
	var place: int = info["exit_x"]
	var lower := _room(3, Vector2i.ZERO, Vector2i(ExitRules.SOUTH, info["entrance_x"]), Vector2i(ExitRules.NORTH, place))
	var end := ExitRules.exit_corridor_end(Vector2i.ZERO, size, ExitRules.NORTH, place)
	var way := _room(4, ExitRules.origin_for(end, size, ExitRules.SOUTH, info["entrance_x"]), Vector2i(ExitRules.SOUTH, info["entrance_x"]), Vector2i(ExitRules.NORTH, place))
	PassageSeam.join(lower, way)
	var gate := GateCloser.gate_between(lower)
	gate.view.build_lintel([lower, way] as Array[Node2D])
	var count := gate.view.get_lintel().size()
	PassageSeam.release(way, [lower, way])
	remove_child(way)
	way.free()
	await wait_frames(2)
	assert_false(gate.view.is_way_gone(), "only a sealed branch gate rebuilds")
	assert_eq(gate.view.get_lintel().size(), count)


func test_sealed_side_gate_keeps_its_notch_once_the_way_is_gone() -> void:
	var info := _probe()
	var east: Array = info["east"]
	var west: Array = info["west"]
	if east.is_empty() or west.is_empty():
		pass_test("the hall has no side doors")
		return
	var size: Vector2i = info["size"]
	var first := _room(3, Vector2i.ZERO, Vector2i(ExitRules.SOUTH, info["entrance_x"]), Vector2i(ExitRules.EAST, east[0]))
	var end := ExitRules.exit_corridor_end(Vector2i.ZERO, size, ExitRules.EAST, east[0])
	var way := _room(4, ExitRules.origin_for(end, size, ExitRules.WEST, west[0]), Vector2i(ExitRules.WEST, west[0]), Vector2i(ExitRules.NORTH, info["exit_x"]))
	PassageSeam.join(first, way)
	var gate := GateCloser.gate_between(first)
	gate.view.build_lintel([first, way] as Array[Node2D])
	var door_tile := _door_tile(gate, first)
	await _drop_way(gate, first, way)
	assert_true(gate.view.is_way_gone())
	assert_not_null(gate.view.get_side_notch(), "the notch stays in the side wall")
	var covered := _covered(gate, door_tile)
	for cell: Vector2i in PassageCover.sealed_cells(first.tiles, door_tile, Vector2i.RIGHT):
		if cell != door_tile:
			assert_true(covered.has(cell), "corridor cell %s behind the notch lies under the rock" % cell)

extends GutTest
## Corridors with character (R5): the corridor tiles (M2: the entrance gap and anything up to the gate
## of the room before), a style per run, room and wall from a hash (no dungeon RNG), every style
## dressed from plan decoration that never blocks the way.

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_corridor_dressing_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func test_tiles_between_the_doors() -> void:
	var size := Vector2i(15, 9)
	# M2: the gate of the room before right behind the entrance gap - the gap is the corridor.
	var one := CorridorDressing.tiles_between(Vector2i(RoomTiles.DoorSide.SOUTH, 7), size, Vector2i(7, 10))
	assert_eq(one, [Vector2i(7, 9)] as Array[Vector2i], "one tile: the entrance gap")
	# A longer corridor: the previous room's north exit door three tiles further down.
	var south := CorridorDressing.tiles_between(Vector2i(RoomTiles.DoorSide.SOUTH, 7), size, Vector2i(7, 12))
	assert_eq(south, [Vector2i(7, 9), Vector2i(7, 10), Vector2i(7, 11)] as Array[Vector2i])
	var west := CorridorDressing.tiles_between(Vector2i(RoomTiles.DoorSide.WEST, 4), size, Vector2i(-2, 4))
	assert_eq(west, [Vector2i(-1, 4)] as Array[Vector2i])
	var east := CorridorDressing.tiles_between(Vector2i(RoomTiles.DoorSide.EAST, 4), size, Vector2i(17, 4))
	assert_eq(east, [Vector2i(15, 4), Vector2i(16, 4)] as Array[Vector2i])
	assert_true(CorridorDressing.tiles_between(Vector2i(RoomTiles.DoorSide.SOUTH, 7), size, Vector2i(3, 12)).is_empty(), "doors that do not line up")


func test_style_is_a_stable_hash() -> void:
	var seen := {}
	for room_index in range(1, 200):
		var style := CorridorDressing.pick_style(4711, room_index, RoomTiles.DoorSide.WEST)
		assert_eq(style, CorridorDressing.pick_style(4711, room_index, RoomTiles.DoorSide.WEST), "same run, same room, same style")
		seen[style] = true
		assert_ne(CorridorDressing.pick_style(4711, room_index, RoomTiles.DoorSide.SOUTH), CorridorDressing.Style.NICHE, "no niche in a north corridor (no wall front)")
	assert_eq(seen.size(), CorridorDressing.Style.size(), "every style comes up")


func test_every_style_dresses_without_blocking() -> void:
	for biome: StringName in CorridorDressing.STRAIGHT_ITEMS:
		for style in CorridorDressing.Style.values():
			var room := HALL.instantiate() as Node2D
			add_child_autofree(room)
			var dressing := CorridorDressing.new()
			dressing.style = style
			dressing.biome_id = biome
			dressing.direction = Vector2i.LEFT
			dressing.tiles.assign([Vector2i(-2, 4), Vector2i(-3, 4)])
			room.add_child(dressing)
			var props := dressing.get_props()
			assert_false(props.is_empty(), "%s %d has props" % [biome, style])
			for prop in props:
				assert_true(DecoProp.has_item(prop.item), "%s is a known decoration" % prop.item)
				assert_false(prop.is_solid(), "%s never blocks the corridor" % prop.item)


func test_attach_dresses_the_entrance_corridor() -> void:
	var room := HALL.instantiate() as RoomController
	var tiles := room.get_node("Tiles") as RoomTiles
	room.apply_door_plan(Vector2i(RoomTiles.DoorSide.SOUTH, tiles.entrance_x), [Vector2i(RoomTiles.DoorSide.NORTH, tiles.exit_x)] as Array[Vector2i])
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	room.setup(3, RoomSequence.RoomType.COMBAT, -1, false, context)
	add_child_autofree(room)
	# M2: the gate of the room before right behind the entrance gap - nothing to dress (playtest).
	assert_null(CorridorDressing.attach(room, Vector2i(tiles.entrance_x, tiles.room_size.y + 1), 99, 3, &"slime_grotto"), "the one-tile corridor stays bare")
	# A longer corridor: only its tiles beyond the gap could be dressed, and only with the switch on.
	var other_door := Vector2i(tiles.entrance_x, tiles.room_size.y + 3)
	var dressing := CorridorDressing.attach(room, other_door, 99, 3, &"slime_grotto")
	if not CorridorDressing.DRESS_CORRIDORS:
		assert_null(dressing, "no decoration in corridors (playtest 14.10.2026)")
		return
	assert_not_null(dressing)
	assert_eq(dressing.tiles, [Vector2i(tiles.entrance_x, tiles.room_size.y + 1), Vector2i(tiles.entrance_x, tiles.room_size.y + 2)] as Array[Vector2i], "not the entrance gap")
	assert_eq(dressing.direction, Vector2i.DOWN)
	assert_null(CorridorDressing.attach(room, Vector2i(0, 0), 99, 3, &"crypt"), "nothing between doors that do not line up")

extends GutTest
## Both ways of a branch are built before the choice (R5): a branch is only offered when both rooms
## fit next to the previous room and to each other (DungeonManager._ways_fit, no RNG); fork rooms
## always fit, two special rooms behind two north doors need enough room between the doors.

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")

var _old_save_path: String
var _manager: DungeonManager = null


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_branch_ways_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	# Not in the tree: only the placement maths of the manager are used.
	_manager = DungeonManager.new()
	_manager.set(&"_combat_catalog", RoomCatalog.create([]))


func after_each() -> void:
	_manager.free()


func _tiles(size: Vector2i, north: Array[int]) -> RoomTiles:
	var tiles := RoomTiles.new()
	tiles.room_size = size
	var slots: Array[Vector2i] = [Vector2i(RoomTiles.DoorSide.SOUTH, size.x / 2)]
	for place in north:
		slots.append(Vector2i(RoomTiles.DoorSide.NORTH, place))
	slots.append(Vector2i(RoomTiles.DoorSide.WEST, size.y / 2))
	slots.append(Vector2i(RoomTiles.DoorSide.EAST, size.y / 2))
	tiles.door_slots = slots
	autofree(tiles)
	return tiles


func _special_pair() -> Array[BranchOption]:
	return [BranchOption.create(BranchOption.Kind.SPECIAL, RoomSequence.SpecialType.SHOP), BranchOption.create(BranchOption.Kind.SPECIAL, RoomSequence.SpecialType.FOUNTAIN)]


func _combat_pair() -> Array[BranchOption]:
	return [BranchOption.create(BranchOption.Kind.ELITE_NEST, -1, BranchOption.ELITE_NEST_ID), BranchOption.create(BranchOption.Kind.SAFE)]


## Footprint of a previous room right below the branch room (south entrance), joined like the chain
## does it (M2: one corridor tile, ExitRules.exit_corridor_end).
func _previous_below(tiles: RoomTiles) -> ExitRules.Footprint:
	var join := RoomTiles.corridor_end_of(RoomTiles.DoorSide.SOUTH, tiles.room_size.x / 2, tiles.room_size)
	var size := Vector2i(15, 9)
	var origin := join - (ExitRules.exit_corridor_end(Vector2i.ZERO, size, RoomTiles.DoorSide.NORTH, 7))
	assert_eq(ExitRules.exit_corridor_end(origin, size, RoomTiles.DoorSide.NORTH, 7), join)
	return ExitRules.footprint_of(origin, size, Vector2i(RoomTiles.DoorSide.SOUTH, 7), 0, [Vector2i(RoomTiles.DoorSide.NORTH, 7)] as Array[Vector2i])


func test_west_east_fork_fits() -> void:
	var tiles := _tiles(Vector2i(21, 9), [10])
	var exits: Array[Vector2i] = [Vector2i(RoomTiles.DoorSide.WEST, 4), Vector2i(RoomTiles.DoorSide.EAST, 4)]
	assert_true(_manager._ways_fit(Vector2i.ZERO, tiles, exits, _combat_pair(), 7, _previous_below(tiles)))


func test_two_special_rooms_need_room_between_their_doors() -> void:
	var wide := _tiles(Vector2i(21, 9), [2, 18])
	var far: Array[Vector2i] = [Vector2i(RoomTiles.DoorSide.NORTH, 2), Vector2i(RoomTiles.DoorSide.NORTH, 18)]
	assert_true(_manager._ways_fit(Vector2i.ZERO, wide, far, _special_pair(), 4, _previous_below(wide)), "doors 16 apart: both rest rooms fit")
	var close := _tiles(Vector2i(15, 9), [6, 9])
	var near: Array[Vector2i] = [Vector2i(RoomTiles.DoorSide.NORTH, 6), Vector2i(RoomTiles.DoorSide.NORTH, 9)]
	assert_false(_manager._ways_fit(Vector2i.ZERO, close, near, _special_pair(), 4, _previous_below(close)), "doors 3 apart: the second room has no place")


func test_share_of_combat_templates_offering_a_special_branch() -> void:
	var catalog := RoomCatalog.load_default()
	var fits := 0
	var hosts := 0
	for entry in catalog.get_entries():
		if not RoomSequence.SOLO_ROOM_SIZES.has(entry.size_class) or not entry.is_plain_fight():
			continue
		var room := entry.scene.instantiate()
		var tiles := room.get_node("Tiles") as RoomTiles
		var pair := BranchRules.pick_exit_pair(tiles, _special_pair(), [RoomTiles.DoorSide.NORTH] as Array[int], [0] as Array[int])
		if pair.size() == 2:
			hosts += 1
			if _manager._ways_fit(Vector2i.ZERO, tiles, pair, _special_pair(), 4, _previous_below(tiles)):
				fits += 1
		room.free()
	gut.p("special branch: %d of %d templates with two north doors fit both rest rooms" % [fits, hosts])
	assert_gt(hosts, 0)
	assert_gt(fits, 0, "some templates can show two special rooms at once")


func test_chain_state_round_trip() -> void:
	_manager.set(&"_previous_special", 3)
	_manager.set(&"_previous_variant", &"flame")
	_manager.set(&"_branch_cycle", 2)
	var state := _manager._capture_chain()
	_manager.set(&"_previous_special", -1)
	_manager.set(&"_previous_variant", &"")
	_manager.set(&"_branch_cycle", -1)
	_manager._restore_chain(state)
	assert_eq(_manager.get(&"_previous_special"), 3)
	assert_eq(_manager.get(&"_previous_variant"), &"flame")
	assert_eq(_manager.get(&"_branch_cycle"), 2)


func test_live_room_limit() -> void:
	assert_eq(_manager.get_live_room_limit(), DungeonManager.MAX_LIVE_ROOMS)
	assert_eq(DungeonManager.MAX_LIVE_ROOMS_BRANCH, DungeonManager.MAX_LIVE_ROOMS + 1, "one more while a branch shows both ways")

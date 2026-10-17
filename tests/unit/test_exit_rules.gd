extends GutTest
## Way-finding (A10, D-105, D-117): doors in every wall (RoomTiles geometry), the exit
## rules (never the entrance wall, north before rooms entered from the south only, weighted turns),
## joining rooms with one corridor tile (M2: the next room's wall is the corridor), the overlap rule
## (rock on rock is fine, never on a floor, wall or corridor) with longer corridors, and the door
## places of every combat template.

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_exit_rules_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


# --- Door geometry ---

func test_door_tiles_on_every_wall() -> void:
	var size := Vector2i(15, 9)
	assert_eq(RoomTiles.door_tile_of(RoomTiles.DoorSide.NORTH, 7, size), Vector2i(7, -1))
	assert_eq(RoomTiles.door_tile_of(RoomTiles.DoorSide.SOUTH, 7, size), Vector2i(7, 9))
	assert_eq(RoomTiles.door_tile_of(RoomTiles.DoorSide.WEST, 4, size), Vector2i(-1, 4))
	assert_eq(RoomTiles.door_tile_of(RoomTiles.DoorSide.EAST, 4, size), Vector2i(15, 4))
	assert_eq(RoomTiles.inside_tile_of(RoomTiles.DoorSide.WEST, 4, size), Vector2i(0, 4))
	assert_eq(RoomTiles.inside_tile_of(RoomTiles.DoorSide.EAST, 4, size), Vector2i(14, 4))
	assert_eq(RoomTiles.inside_tile_of(RoomTiles.DoorSide.SOUTH, 7, size), Vector2i(7, 8))


func test_corridors_run_through_the_ring_and_get_longer() -> void:
	var size := Vector2i(15, 9)
	assert_eq(RoomTiles.corridor_tiles_of(RoomTiles.DoorSide.NORTH, 7, size).size(), 3, "north: rows -1..-3")
	assert_eq(RoomTiles.corridor_tiles_of(RoomTiles.DoorSide.SOUTH, 7, size).size(), 2)
	assert_eq(RoomTiles.corridor_tiles_of(RoomTiles.DoorSide.EAST, 4, size), [Vector2i(15, 4), Vector2i(16, 4)] as Array[Vector2i])
	assert_eq(RoomTiles.corridor_end_of(RoomTiles.DoorSide.WEST, 4, size, 3), Vector2i(-5, 4), "three extra tiles")
	var painted := RoomTiles.get_painted_rects_of(size, RoomTiles.DoorSide.WEST, 3, 4)
	assert_eq(painted.size(), 2, "ring and corridor strip")
	assert_eq(painted[1], Rect2i(-5, 3, 3, 3), "strip: the three new corridor tiles and a wall on each side")


func test_room_tiles_walk_through_a_side_entrance() -> void:
	var room := HALL.instantiate() as RoomController
	autofree(room)
	var tiles := room.get_node("Tiles") as RoomTiles
	var east := tiles.get_door_slots(RoomTiles.DoorSide.EAST)
	assert_false(east.is_empty(), "the hall has an east door place")
	room.apply_door_plan(Vector2i(RoomTiles.DoorSide.EAST, east[0]), [Vector2i(RoomTiles.DoorSide.NORTH, tiles.exit_x)] as Array[Vector2i], 2)
	assert_eq(tiles.get_entrance_inside_tile(), Vector2i(tiles.room_size.x - 1, east[0]))
	var walkable := tiles.get_walkable_tiles()
	assert_true(walkable.has(Vector2i(tiles.room_size.x + 3, east[0])), "longer entrance corridor is walkable")
	assert_false(walkable.has(Vector2i(tiles.entrance_x, tiles.room_size.y)), "no south door any more")
	var reached := tiles.get_reachable_tiles()
	assert_true(reached.has(tiles.get_exit_inside_tile()), "exit reachable from the east entrance")


# --- Exit rules ---

func test_exit_never_on_the_entrance_wall() -> void:
	var all: Array[int] = [ExitRules.NORTH, ExitRules.EAST, ExitRules.WEST]
	var combat := RoomSequence.RoomType.COMBAT
	assert_eq(ExitRules.allowed_exit_sides(ExitRules.SOUTH, combat, all), all)
	assert_eq(ExitRules.allowed_exit_sides(ExitRules.WEST, combat, all), [ExitRules.NORTH, ExitRules.EAST] as Array[int])
	assert_eq(ExitRules.allowed_exit_sides(ExitRules.EAST, combat, all), [ExitRules.NORTH, ExitRules.WEST] as Array[int])


func test_north_before_rooms_entered_from_the_south() -> void:
	var all: Array[int] = [ExitRules.NORTH, ExitRules.EAST, ExitRules.WEST]
	for next_type in [RoomSequence.RoomType.SPECIAL, RoomSequence.RoomType.MINIBOSS, RoomSequence.RoomType.BOSS, RoomSequence.RoomType.CAMPFIRE]:
		assert_eq(ExitRules.allowed_exit_sides(ExitRules.WEST, next_type, all), [ExitRules.NORTH] as Array[int], "type %d" % next_type)
	var north_only: Array[int] = [ExitRules.NORTH]
	assert_eq(ExitRules.allowed_exit_sides(ExitRules.SOUTH, RoomSequence.RoomType.COMBAT, north_only), north_only, "catacomb: no side places")


func test_turns_are_weighted_and_need_no_long_corridor() -> void:
	var sides: Array[int] = [ExitRules.NORTH, ExitRules.EAST, ExitRules.WEST]
	var counts := {ExitRules.NORTH: 0, ExitRules.EAST: 0, ExitRules.WEST: 0}
	for i in 1000:
		counts[ExitRules.roll_exit(sides, [0, 0, 0] as Array[int], (i + 0.5) / 1000.0)] += 1
	assert_almost_eq(counts[ExitRules.NORTH] / 1000.0, 0.5, 0.01)
	assert_almost_eq(counts[ExitRules.EAST] / 1000.0, 0.25, 0.01)
	assert_almost_eq(counts[ExitRules.WEST] / 1000.0, 0.25, 0.01)
	for i in 100:
		assert_ne(ExitRules.roll_exit(sides, [0, 5, 0] as Array[int], i / 100.0), ExitRules.EAST, "a turn needing a long corridor is skipped")
	assert_eq(ExitRules.roll_exit([ExitRules.NORTH] as Array[int], [9] as Array[int], 0.9), ExitRules.NORTH, "north is never filtered out")


# --- Joining and overlap ---

func test_joined_rooms_share_the_corridor_end() -> void:
	var first := Vector2i(15, 9)
	var second := Vector2i(19, 11)
	var end := ExitRules.exit_corridor_end(Vector2i.ZERO, first, ExitRules.EAST, 4)
	var origin := ExitRules.origin_for(end, second, ExitRules.WEST, 5)
	assert_eq(origin + RoomTiles.corridor_end_of(ExitRules.WEST, 5, second), end)
	assert_eq(origin, Vector2i(17, -1), "M2: the west room's floor starts two columns behind the east wall")
	var a := ExitRules.footprint_of(Vector2i.ZERO, first, Vector2i(ExitRules.SOUTH, 7), 0, [Vector2i(ExitRules.EAST, 4)] as Array[Vector2i])
	var b := ExitRules.footprint_of(origin, second, Vector2i(ExitRules.WEST, 5), 0)
	var cut := a.get_bounds().intersection(b.get_bounds())
	assert_eq(cut.size.x, ExitRules.shared_lines(ExitRules.EAST), "neighbours share the corridor and the wall column")


## M2: one gate (the exit door of the room left) and one tile of corridor (the next room's wall)
## between the two floors, on every wall.
func test_one_corridor_tile_between_gate_and_floor() -> void:
	var first := Vector2i(15, 9)
	var second := Vector2i(17, 11)
	for exit: Vector2i in [Vector2i(ExitRules.NORTH, 7), Vector2i(ExitRules.EAST, 4), Vector2i(ExitRules.WEST, 4)]:
		var entrance_side := RoomTiles.opposite_side(exit.x)
		var place := 8 if entrance_side == ExitRules.SOUTH else 5
		var end := ExitRules.exit_corridor_end(Vector2i.ZERO, first, exit.x, exit.y)
		var origin := ExitRules.origin_for(end, second, entrance_side, place)
		var gate := RoomTiles.door_tile_of(exit.x, exit.y, first)
		var inside := origin + RoomTiles.inside_tile_of(entrance_side, place, second)
		var direction: Vector2i = RoomTiles.SIDE_DIRECTIONS[exit.x]
		assert_eq(inside, gate + direction * 2, "side %d: gate, one corridor tile, floor" % exit.x)
		assert_eq(origin + RoomTiles.door_tile_of(entrance_side, place, second), gate + direction, "side %d: the corridor tile is the next room's entrance" % exit.x)
	assert_eq(ExitRules.join_overlap(ExitRules.NORTH), 2, "north: the next room's south wall lies on the crown")
	assert_eq(ExitRules.join_overlap(ExitRules.EAST), 1)


func test_rock_on_rock_is_fine_but_never_on_a_floor() -> void:
	var size := Vector2i(15, 9)
	var a := ExitRules.footprint_of(Vector2i.ZERO, size, Vector2i(ExitRules.SOUTH, 7), 0)
	var ring_only := ExitRules.footprint_of(Vector2i(18, 0), size, Vector2i(ExitRules.SOUTH, 7), 0)
	assert_false(a.clashes(ring_only), "outer rings share column 16 (rock on rock)")
	var on_floor := ExitRules.footprint_of(Vector2i(17, 0), size, Vector2i(ExitRules.SOUTH, 7), 0)
	assert_true(a.clashes(on_floor), "the other ring covers this room's wall")


func test_a_longer_corridor_clears_a_live_room() -> void:
	# Room 16 east of room 17 (17 entered from the east), room 18 above 17: without a longer
	# corridor 18's ring row would cover 16's north wall (smoke test 14.10.2026).
	var room16 := ExitRules.footprint_of(Vector2i(0, 0), Vector2i(19, 11), Vector2i(ExitRules.SOUTH, 9), 0, [Vector2i(ExitRules.WEST, 5)] as Array[Vector2i])
	var end16 := ExitRules.exit_corridor_end(Vector2i.ZERO, Vector2i(19, 11), ExitRules.WEST, 5)
	var origin17 := ExitRules.origin_for(end16, Vector2i(15, 9), ExitRules.EAST, 4)
	var end17 := ExitRules.exit_corridor_end(origin17, Vector2i(15, 9), ExitRules.NORTH, 13)
	var others: Array[ExitRules.Footprint] = [room16]
	var extra := ExitRules.extra_needed(end17, Vector2i(19, 11), Vector2i(ExitRules.SOUTH, 9), others)
	assert_gt(extra, 0, "the plain place clashes")
	assert_lt(extra, 4, "a short corridor is enough")
	assert_false(ExitRules.joined_footprint(end17, Vector2i(19, 11), Vector2i(ExitRules.SOUTH, 9), extra).clashes(room16))


func test_straight_on_never_needs_a_longer_corridor() -> void:
	var size := Vector2i(19, 11)
	var previous := ExitRules.footprint_of(Vector2i.ZERO, size, Vector2i(ExitRules.SOUTH, 9), 0, [Vector2i(ExitRules.NORTH, 9)] as Array[Vector2i])
	var end := ExitRules.exit_corridor_end(Vector2i.ZERO, size, ExitRules.NORTH, 9)
	var origin := ExitRules.origin_for(end, size, ExitRules.SOUTH, 9)
	var end2 := ExitRules.exit_corridor_end(origin, size, ExitRules.NORTH, 9)
	var others: Array[ExitRules.Footprint] = [previous]
	assert_eq(ExitRules.extra_needed(end2, size, Vector2i(ExitRules.SOUTH, 9), others), 0)


## M2: a niche behind the north wall and a way north exclude each other; a plain fight with only
## north niche places leaves through a side wall that needs no longer corridor (the niche's roll picks).
func test_a_niche_behind_the_north_wall_turns_the_way_aside() -> void:
	var sides: Array[int] = [ExitRules.NORTH, ExitRules.EAST, ExitRules.WEST]
	assert_eq(DungeonManager._side_exit_for_niche(sides, [0, 0, 0] as Array[int], 0.1), ExitRules.EAST)
	assert_eq(DungeonManager._side_exit_for_niche(sides, [0, 0, 0] as Array[int], 0.9), ExitRules.WEST)
	assert_eq(DungeonManager._side_exit_for_niche(sides, [0, 5, 0] as Array[int], 0.1), ExitRules.WEST, "no turn that needs a longer corridor")
	assert_eq(DungeonManager._side_exit_for_niche([ExitRules.NORTH] as Array[int], [0] as Array[int], 0.5), -1, "north only: no niche behind the north wall")


# --- Templates ---

func test_combat_templates_have_side_door_places() -> void:
	var catalog := RoomCatalog.create()
	for entry in catalog.get_entries():
		var room := entry.scene.instantiate() as RoomController
		autofree(room)
		var tiles := room.get_node("Tiles") as RoomTiles
		assert_eq(tiles.door_slots, entry.door_slots, "%s: scene and resource agree" % entry.id)
		var catacomb := entry.shape == RoomTemplate.Shape.CATACOMB
		for side: int in [RoomTiles.DoorSide.WEST, RoomTiles.DoorSide.EAST]:
			assert_eq(tiles.allows_door(side), not catacomb, "%s: side %d" % [entry.id, side])
			assert_eq(entry.allows_entrance(side), not catacomb, "%s: entrance side %d" % [entry.id, side])
		var reached := tiles.get_reachable_tiles()
		var markers := IngredientScatter.get_marker_tiles(room)
		for slot in tiles.door_slots:
			assert_true(reached.has(RoomTiles.inside_tile_of(slot.x, slot.y, tiles.room_size)), "%s: place %s reachable" % [entry.id, slot])
			if slot.x == RoomTiles.DoorSide.WEST or slot.x == RoomTiles.DoorSide.EAST:
				var inside := RoomTiles.inside_tile_of(slot.x, slot.y, tiles.room_size)
				for marker in markers:
					assert_gt(maxi(absi(marker.x - inside.x), absi(marker.y - inside.y)), 2, "%s: marker %s away from the side entrance" % [entry.id, marker])
				for tile in RoomTiles.door_lane_of(slot.x, slot.y, tiles.room_size, 2):
					assert_false(tiles.is_pit(tile) or tiles.is_bridge(tile), "%s: no abyss in the side lane %s" % [entry.id, tile])


func test_a_room_entered_from_the_side_reaches_every_exit() -> void:
	var catalog := RoomCatalog.create()
	for entry in catalog.get_entries():
		for side: int in [RoomTiles.DoorSide.WEST, RoomTiles.DoorSide.EAST]:
			if not entry.allows_entrance(side):
				continue
			var room := entry.scene.instantiate() as RoomController
			autofree(room)
			var tiles := room.get_node("Tiles") as RoomTiles
			var exits: Array[Vector2i] = []
			for exit_side: int in [RoomTiles.DoorSide.NORTH, RoomTiles.opposite_side(side)]:
				exits.append(Vector2i(exit_side, ExitRules.pick_place(tiles.get_door_slots(exit_side), ExitRules.wall_length(exit_side, tiles.room_size))))
			room.apply_door_plan(Vector2i(side, tiles.get_door_slots(side)[0]), exits)
			var reached := tiles.get_reachable_tiles()
			for inside in tiles.get_exit_inside_tiles():
				assert_true(reached.has(inside), "%s from side %d: exit %s" % [entry.id, side, inside])


func test_catalog_picks_only_templates_with_the_entrance_wall() -> void:
	var catalog := RoomCatalog.create()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 200:
		var entry := catalog.pick_template(RoomSequence.RoomKind.NORMAL, RoomSequence.SOLO_ROOM_SIZES, rng, &"", 10, RoomTiles.DoorSide.WEST)
		assert_true(entry.allows_entrance(RoomTiles.DoorSide.WEST), entry.id)
		assert_ne(entry.shape, RoomTemplate.Shape.CATACOMB)

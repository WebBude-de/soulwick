extends GutTest
## Arches never cut off (R5, 04_wandsystem.md): at every north door place of every template the arch
## (48 px, cave mouth and boss gate 64 px wide - half a tile beside the door tile, M2 -, 1.5 / 1.75
## tiles tall) stands on solid wall - front and both crowns beside the corridor are wall, no floor, no
## niche - and no wall fixture of the plan hangs inside it.

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_door_arch_fit_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _templates() -> Array[RoomTemplate]:
	var entries: Array[RoomTemplate] = []
	var seen := {}
	for catalog: RoomCatalog in [RoomCatalog.load_default(), RoomCatalog.load_plans()]:
		if catalog == null:
			continue
		for entry in catalog.get_entries():
			if entry.scene != null and not seen.has(entry.scene.resource_path):
				seen[entry.scene.resource_path] = true
				entries.append(entry)
	return entries


func test_every_north_door_place_has_room_for_its_arch() -> void:
	var checked := 0
	var problems: Array[String] = []
	for entry in _templates():
		var room := entry.scene.instantiate()
		var tiles := room.get_node("Tiles") as RoomTiles
		for place in tiles.get_door_slots(RoomTiles.DoorSide.NORTH):
			tiles.exit_side = RoomTiles.DoorSide.NORTH
			tiles.exit_x = place
			tiles.branch_exit = Vector2i(RoomTiles.NO_DOOR, 0)
			var floor_mask := tiles.get_floor_mask()
			checked += 1
			# The corridor itself is floor; the frame overlaps the front and the crown beside it.
			for row in [-1, -2, -3]:
				assert_true(floor_mask.has(Vector2i(place, row)), "%s: corridor at %d, row %d" % [entry.id, place, row])
				for column in [place - 1, place + 1]:
					if floor_mask.has(Vector2i(column, row)):
						problems.append("%s: floor beside the arch at (%d, %d)" % [entry.id, column, row])
		room.free()
	assert_gt(checked, 100, "north door places checked: %d" % checked)
	assert_eq(problems, [] as Array[String], "arches stand on solid wall")


func test_no_wall_fixture_inside_an_arch() -> void:
	var problems: Array[String] = []
	for entry in _templates():
		var room := entry.scene.instantiate()
		var tiles := room.get_node("Tiles") as RoomTiles
		var places := tiles.get_door_slots(RoomTiles.DoorSide.NORTH)
		for prop in room.get_node("Props").get_children():
			var deco := prop as DecoProp
			if deco == null or int(DecoProp.ITEMS.get(deco.item, {}).get("layer", -1)) != DecoProp.Layer.WALL:
				continue
			var tile := RoomTiles.local_to_tile(deco.position - Vector2(0, 1))
			if tile.y != -1:
				continue
			for place in places:
				if absi(tile.x - place) <= 1:
					problems.append("%s: %s at column %d next to the door place %d" % [entry.id, deco.item, tile.x, place])
		room.free()
	assert_eq(problems, [] as Array[String], "wall fixtures keep clear of the arches")

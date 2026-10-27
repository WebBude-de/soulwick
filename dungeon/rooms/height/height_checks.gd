class_name HeightChecks
extends RefCounted
## Checks of the height of a live room (M3) for tools/smoke_test.gd (hook for the integrator, next to
## RoomPlanChecks.problems, which already checks the rules of the layout): the room built its
## HeightField with one wall per cliff run and edge, every living player stops at cliffs, every
## enemy of the room at cliffs and ladders, every height tile is a floor cell (D-205: the ground in
## front of a half-high front belongs to the room).
## problems() returns readable lines, empty = fine (also for rooms without height).


static func problems(room: Node) -> Array[String]:
	var result: Array[String] = []
	var tiles := room.get_node_or_null(^"Tiles") as RoomTiles
	if tiles == null or not tiles.has_height() or not tiles.is_terrain_drawn():
		return result
	var field := tiles.get_height_field()
	if field == null or not field.is_inside_tree():
		result.append("no HeightField in a room with plateaus")
		return result
	if not field.is_in_group(HeightRules.FIELDS_GROUP):
		result.append("HeightField not in the group %s" % HeightRules.FIELDS_GROUP)
	var layout := tiles.get_height_layout()
	var unit := float(tiles.tile_set.tile_size.x)
	var cliffs := field.get_node_or_null(^"Cliffs") as HeightBody
	var expected := HeightField.wall_rects(layout, unit).size()
	if cliffs == null or cliffs.get_child_count() != expected:
		result.append("cliff walls: %d shapes, expected %d" % [cliffs.get_child_count() if cliffs != null else 0, expected])
	elif cliffs.collision_layer != PhysicsLayers.CLIFF:
		result.append("cliff walls on layer %d" % cliffs.collision_layer)
	if not layout.ladders.is_empty() and field.get_node_or_null(^"Ladders") == null:
		result.append("ladders without the enemy block")
	if field.get_connectors().size() != layout.ladders.size() + layout.stairs.size():
		result.append("%d switch areas for %d stairs and ladders" % [field.get_connectors().size(), layout.ladders.size() + layout.stairs.size()])
	# Every height tile is a floor cell: the surface, and the ground in front of a half-high front.
	for tile: Vector2i in layout.get_height_tiles():
		if tiles.get_cell_source_id(tile) == -1:
			result.append("height tile %s without a floor cell" % tile)
			break
	for player in room.get_tree().get_nodes_in_group(&"player"):
		if player is Player and (player as Player).collision_mask & PhysicsLayers.CLIFF == 0:
			result.append("%s walks through cliffs" % player.name)
	var container := room.get_node_or_null(^"EnemyContainer")
	if container != null:
		for enemy in container.get_children():
			var body := enemy as Enemy
			if body == null or body.collision_mask == 0:
				continue
			if body.collision_mask & (PhysicsLayers.CLIFF | PhysicsLayers.LADDER) != (PhysicsLayers.CLIFF | PhysicsLayers.LADDER):
				result.append("%s walks through cliffs or ladders" % body.name)
	return result

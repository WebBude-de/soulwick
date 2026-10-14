class_name RoomPlanChecks
extends RefCounted
## The rules of a built plan room (R1, D-120, docs/design/claude_design_antwort/02_grundrisse.md),
## checked on the room itself: on a template that is only instantiated (unit tests) as well as on a
## live room of a run (smoke test). tools/generate_room_templates.py checks the same rules on the
## plan before it writes a template; this is the second line, after door plans, branch doors and
## secret niches were applied at runtime.
##   - every floor tile reachable on foot from the entrance, with every solid prop and every floor
##     source counted as blocked (sources are never in the way);
##   - every door free: no abyss, no solid prop, no source in its lane (three tiles wide, two deep);
##   - no decoration, no floor source on a tile that is the only way (articulation point);
##   - spike traps only with a reason: a chest close by or a side passage.
## problems() returns readable lines, empty = fine.

## Rows of a door lane that stay free (generator DOOR_LANE_ROWS).
const LANE_ROWS := 2
## A trap needs a chest within this Chebyshev distance or must lie in a side passage.
const TRAP_CHEST_DISTANCE := 2
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]


static func problems(room: Node) -> Array[String]:
	var result: Array[String] = []
	var tiles := room.get_node_or_null("Tiles") as RoomTiles
	if tiles == null:
		result.append("no Tiles")
		return result
	var floor_rect := Rect2i(Vector2i.ZERO, tiles.room_size)
	var walkable := tiles.get_walkable_tiles()
	var niche: Dictionary[Vector2i, bool] = {}
	if not tiles.is_niche_open():
		for tile in tiles.get_niche_tiles():
			niche[tile] = true
	var solids := solid_tiles(room)
	var sources := floor_source_tiles(room)
	var open: Dictionary[Vector2i, bool] = {}
	for tile: Vector2i in walkable:
		if not solids.has(tile) and not sources.has(tile) and not niche.has(tile):
			open[tile] = true
	var none: Dictionary[Vector2i, bool] = {}
	var reached := RoomTiles.flood_fill(open, none, tiles.get_entrance_inside_tile(), 0)
	var cut_off: Array[Vector2i] = []
	for tile: Vector2i in open:
		if floor_rect.has_point(tile) and not reached.has(tile):
			cut_off.append(tile)
	if not cut_off.is_empty():
		result.append("floor cut off from the entrance: %s" % [cut_off.slice(0, 5)])
	var doors: Array[Vector2i] = [tiles.get_entrance_door()]
	doors.append_array(tiles.get_exit_doors())
	for door in doors:
		if not reached.has(RoomTiles.inside_tile_of(door.x, door.y, tiles.room_size)):
			result.append("door %s not reachable" % door)
		for tile in RoomTiles.door_lane_of(door.x, door.y, tiles.room_size, LANE_ROWS):
			if tiles.is_pit(tile):
				result.append("abyss %s in the lane of door %s" % [tile, door])
			elif solids.has(tile):
				result.append("solid prop %s in the lane of door %s" % [tile, door])
			elif sources.has(tile):
				result.append("source %s in the lane of door %s" % [tile, door])
	# Only ways: tiles whose loss splits the floor.
	var floor_tiles: Dictionary[Vector2i, bool] = {}
	for tile: Vector2i in walkable:
		if floor_rect.has_point(tile) and not niche.has(tile):
			floor_tiles[tile] = true
	var cut := articulation_points(floor_tiles)
	for tile: Vector2i in sources:
		if cut.has(tile):
			result.append("source %s stands in the only way" % tile)
	for prop in decoration_props(room):
		for tile in prop_tiles(prop):
			if cut.has(tile):
				result.append("%s at %s stands in the only way" % [prop.name, tile])
	var chests: Array[Vector2i] = []
	for prop in _props(room):
		if prop is TreasureChest:
			chests.append(RoomTiles.local_to_tile(prop.position))
	for prop in _props(room):
		if not (prop is SpikeTrap or prop is LavaCrack or prop is ToxicPuddle):
			continue
		var tile := RoomTiles.local_to_tile(prop.position)
		var near_chest := false
		for chest in chests:
			near_chest = near_chest or maxi(absi(chest.x - tile.x), absi(chest.y - tile.y)) <= TRAP_CHEST_DISTANCE
		var neighbours := 0
		for direction in DIRECTIONS:
			if floor_tiles.has(tile + direction):
				neighbours += 1
		if not near_chest and neighbours > 2:
			result.append("trap at %s without a reason" % tile)
	return result


## Floor tiles blocked by props: DecoProp tiles, crates, barrels, rubble, chests, light islands.
static func solid_tiles(room: Node) -> Dictionary[Vector2i, bool]:
	var result: Dictionary[Vector2i, bool] = {}
	for prop in _props(room):
		if prop is DecoProp:
			for tile in (prop as DecoProp).get_blocked_tiles():
				result[tile] = true
		elif RoomController.is_solid_prop(prop):
			result[RoomTiles.local_to_tile(prop.position)] = true
	return result


## Tiles of the floor sources (graves, puddles, rifts, vents, sarcophagi; not the wall gates).
static func floor_source_tiles(room: Node) -> Dictionary[Vector2i, bool]:
	var result: Dictionary[Vector2i, bool] = {}
	var container := room.get_node_or_null(RoomController.SOURCES_NODE)
	if container == null:
		return result
	for marker in container.get_children():
		if marker is Marker2D and int(marker.get_meta(&"wall_side", -1)) < 0:
			result[marker.get_meta(&"tile", RoomTiles.local_to_tile(marker.position))] = true
	return result


## Props that are decoration (not torches, not fixtures in a wall front, no objective light).
static func decoration_props(room: Node) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for prop in _props(room):
		var name := String(prop.name)
		if name.begins_with("Torch") or name.begins_with("Niche") or name.begins_with("Chains") or name.begins_with("Cobweb"):
			continue
		if name.begins_with("Crystal") or name.begins_with("Brazier") or name.begins_with("TorchStand"):
			continue
		result.append(prop)
	return result


static func prop_tiles(prop: Node2D) -> Array[Vector2i]:
	if prop is DecoProp and (prop as DecoProp).is_solid():
		return (prop as DecoProp).get_blocked_tiles()
	var single: Array[Vector2i] = [RoomTiles.local_to_tile(prop.position)]
	return single


## Tiles whose removal splits the 4-neighbour graph over nodes (iterative Tarjan).
static func articulation_points(nodes: Dictionary[Vector2i, bool]) -> Dictionary[Vector2i, bool]:
	var result: Dictionary[Vector2i, bool] = {}
	var index: Dictionary[Vector2i, int] = {}
	var low: Dictionary[Vector2i, int] = {}
	var counter := 0
	var roots: Array[Vector2i] = []
	roots.assign(nodes.keys())
	roots.sort()
	for root in roots:
		if index.has(root):
			continue
		index[root] = counter
		low[root] = counter
		counter += 1
		var children := 0
		# Stack entries: [node, parent (or root itself), next direction index].
		var stack: Array = [[root, root, 0]]
		while not stack.is_empty():
			var top: Array = stack[stack.size() - 1]
			var node: Vector2i = top[0]
			var parent: Vector2i = top[1]
			var advanced := false
			while top[2] < DIRECTIONS.size():
				var next: Vector2i = node + DIRECTIONS[top[2]]
				top[2] += 1
				if not nodes.has(next) or (next == parent and node != root):
					continue
				if index.has(next):
					low[node] = mini(low[node], index[next])
				else:
					index[next] = counter
					low[next] = counter
					counter += 1
					if node == root:
						children += 1
					stack.append([next, node, 0])
					advanced = true
					break
			if advanced:
				continue
			stack.pop_back()
			if node != root:
				low[parent] = mini(low[parent], low[node])
				if parent != root and low[node] >= index[parent]:
					result[parent] = true
		if children > 1:
			result[root] = true
	return result


static func _props(room: Node) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var props := room.get_node_or_null("Props")
	if props == null:
		return result
	for child in props.get_children():
		if child is Node2D and not child.is_queued_for_deletion():
			result.append(child)
	return result

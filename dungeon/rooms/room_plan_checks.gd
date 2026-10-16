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
##   - spike traps only with a reason: a chest close by or a side passage;
##   - no one-tile slots between two solid or unwalkable things (rock, wall, abyss), no wall front
##     right above an abyss (M1, playtest 14.10.2026); bridges are ways on purpose;
##   - no wall front beside an abyss, no abyss touching another abyss or rock only at a corner
##     (playtest 15.10.2026);
##   - every wall torch (plan torches and door torches) hangs fully on one wall front, nothing of it
##     below the front in the floor (M1, playtest 15.10.2026).
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
	result.append_array(slot_problems(tiles))
	result.append_array(torch_problems(room))
	return result


## Wall torches whose art does not lie on one wall front (the visible pixels of the first frame).
static func torch_problems(room: Node) -> Array[String]:
	var result: Array[String] = []
	var tiles := room.get_node_or_null("Tiles") as RoomTiles
	if tiles == null or tiles.tile_set == null:
		return result
	var floor_mask := tiles.get_floor_mask()
	var unit := float(tiles.tile_set.tile_size.x)
	var stack: Array[Node] = [room]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var torch := node as AnimatedProp
		if torch == null or torch.strip == null or not torch.is_visible_in_tree():
			continue
		var file := torch.strip.resource_path.get_file()
		if not file.begins_with("torch_") or file.contains("stand"):
			continue
		var art := torch_rect(torch, tiles).grow(-0.5)
		var low := Vector2i(floori(art.position.x / unit), floori(art.position.y / unit))
		var high := Vector2i(floori(art.end.x / unit), floori(art.end.y / unit))
		if low != high:
			result.append("%s spans tiles %s..%s, not one front" % [room.get_path_to(torch), low, high])
		elif floor_mask.has(low) or not WallAutotile.is_front(low, floor_mask):
			result.append("%s hangs on %s, no wall front" % [room.get_path_to(torch), low])
	return result


## Visible pixels of a torch's first frame in the layer space of tiles.
static func torch_rect(torch: AnimatedProp, tiles: RoomTiles) -> Rect2:
	var frame := torch.sprite_frames.get_frame_texture(torch.animation, 0) if torch.sprite_frames != null else null
	if frame == null:
		return Rect2()
	var image := frame.get_image()
	if image.is_compressed():
		image.decompress()
	var used := image.get_used_rect()
	var size := Vector2(frame.get_size())
	var origin := torch.offset - (size / 2.0 if torch.centered else Vector2.ZERO)
	var to_tiles := tiles.get_global_transform().affine_inverse() * torch.get_global_transform()
	var a := to_tiles * (origin + Vector2(used.position))
	var b := to_tiles * (origin + Vector2(used.end))
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (a - b).abs())


## One-tile slots and wall fronts right above the abyss (M1).
static func slot_problems(tiles: RoomTiles) -> Array[String]:
	var result: Array[String] = []
	var floor_mask := tiles.get_floor_mask()
	var floor_rect := Rect2i(Vector2i.ZERO, tiles.room_size)
	for tile: Vector2i in floor_mask:
		if not floor_rect.has_point(tile) or tiles.is_pit(tile) or tiles.is_bridge(tile):
			continue
		if _closed(tiles, floor_mask, tile + Vector2i.LEFT) and _closed(tiles, floor_mask, tile + Vector2i.RIGHT):
			result.append("one-tile slot at %s (west/east)" % tile)
		elif _closed(tiles, floor_mask, tile + Vector2i.UP) and _closed(tiles, floor_mask, tile + Vector2i.DOWN):
			result.append("one-tile slot at %s (north/south)" % tile)
	for pit in tiles.get_pit_tiles():
		if not floor_mask.has(pit + Vector2i.UP):
			result.append("wall front right above the abyss at %s" % pit)
	result.append_array(abyss_problems(tiles))
	return result


## Clean abyss edges (playtest 15.10.2026, notes 3, 5 and 6): no wall front beside an abyss tile,
## and an abyss never touches another abyss or rock only at a corner (two rims pinched into one
## point). The abyss of the plan (pit_rects with their bridges); holes made at runtime come and go.
## Same rule as abyss_contact_problem in tools/generate_room_templates.py.
static func abyss_problems(tiles: RoomTiles) -> Array[String]:
	var result: Array[String] = []
	var floor_mask := tiles.get_floor_mask()
	var runtime: Dictionary[Vector2i, bool] = {}
	for tile in tiles.get_runtime_pit_tiles():
		runtime[tile] = true
	var abyss: Dictionary[Vector2i, bool] = {}
	for tile in tiles.get_pit_tiles():
		if not runtime.has(tile):
			abyss[tile] = true
	var bridges: Dictionary[Vector2i, bool] = {}
	for tile in tiles.get_bridge_tiles():
		abyss[tile] = true
		bridges[tile] = true
	for tile: Vector2i in abyss:
		if not bridges.has(tile):
			for side: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT]:
				if WallAutotile.is_front(tile + side, floor_mask):
					result.append("wall front beside the abyss at %s" % tile)
		for d: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
			var a := tile + Vector2i(d.x, 0)
			var b := tile + Vector2i(0, d.y)
			if abyss.has(a) or abyss.has(b) or not floor_mask.has(a) or not floor_mask.has(b):
				continue
			if abyss.has(tile + d):
				result.append("abyss tiles %s and %s touch only at a corner" % [tile, tile + d])
			elif not floor_mask.has(tile + d):
				result.append("abyss at %s touches rock %s only at a corner" % [tile, tile + d])
	return result


static func _closed(tiles: RoomTiles, floor_mask: Dictionary[Vector2i, bool], tile: Vector2i) -> bool:
	return not floor_mask.has(tile) or tiles.is_pit(tile)


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

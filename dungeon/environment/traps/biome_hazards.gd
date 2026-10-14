class_name BiomeHazards
extends RefCounted
## Places the biome's floor hazards (toxic puddles, lava cracks; BiomeData.hazard_scene) on free
## floor tiles of a room. Keeps doors, the walking lanes in front of them, pillars, spawn markers
## and existing traps free. Pure tile picking is separate (pick_tiles) and unit-tested.
##
## Integration (RoomController._ready, after the biome tint):
##     BiomeHazards.place(self, tiles, spawner.get_biome(room_index), room_index, room_type, context.rng)

## Tiles kept free around doors (rows from the edge in front of entrance/exit).
const DOOR_CLEARANCE := 2
## Chebyshev distance in tiles between two hazards / a hazard and a blocked tile.
const MIN_SPACING := 2
const PLACEMENT_ATTEMPTS := 60


## Spawns the hazards of this room. Returns the created nodes (children of room).
static func place(room: Node2D, tiles: RoomTiles, biome: BiomeData, room_index: int, room_type: RoomSequence.RoomType, rng: RandomNumberGenerator) -> Array[Node2D]:
	var placed: Array[Node2D] = []
	if biome == null or biome.hazard_scene == null or tiles == null:
		return placed
	var count := biome.get_hazard_count(room_index, room_type, rng)
	if count <= 0:
		return placed
	var blocked := _collect_blocked_tiles(room, tiles)
	var picked := pick_tiles(tiles.room_size, tiles.pillar_tiles, tiles.entrance_x, tiles.exit_x, blocked, count, rng)
	for tile in picked:
		var hazard := biome.hazard_scene.instantiate() as Node2D
		hazard.position = tiles.position + RoomTiles.tile_center(tile)
		if hazard is LavaCrack and rng.randf() < 0.5:
			hazard.rotation = PI * 0.5
		room.add_child(hazard)
		placed.append(hazard)
	return placed


## Up to count distinct floor tiles: not on/next to pillars or blocked tiles, not in the door lanes,
## not on the outermost ring, at least MIN_SPACING apart. Deterministic for a given rng state.
static func pick_tiles(room_size: Vector2i, pillars: Array[Vector2i], entrance_x: int, exit_x: int, blocked: Array[Vector2i], count: int, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for x in range(1, room_size.x - 1):
		for y in range(1, room_size.y - 1):
			var tile := Vector2i(x, y)
			if _near_any(tile, pillars, 1) or _near_any(tile, blocked, 1):
				continue
			if absi(x - exit_x) <= 1 and y <= DOOR_CLEARANCE:
				continue
			if absi(x - entrance_x) <= 1 and y >= room_size.y - 1 - DOOR_CLEARANCE:
				continue
			candidates.append(tile)
	var picked: Array[Vector2i] = []
	var attempts := 0
	while picked.size() < count and not candidates.is_empty() and attempts < PLACEMENT_ATTEMPTS:
		attempts += 1
		var tile: Vector2i = candidates.pop_at(rng.randi_range(0, candidates.size() - 1))
		if not _near_any(tile, picked, MIN_SPACING - 1):
			picked.append(tile)
	return picked


static func _near_any(tile: Vector2i, others: Array[Vector2i], distance: int) -> bool:
	for other in others:
		if absi(tile.x - other.x) <= distance and absi(tile.y - other.y) <= distance:
			return true
	return false


## Spawn markers, the content anchor and existing traps of the room (as tiles).
static func _collect_blocked_tiles(room: Node2D, tiles: RoomTiles) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for node in room.find_children("*", "Node2D", true, false):
		if node is Marker2D or node is SpikeTrap or node is ToxicPuddle or node is LavaCrack:
			var local := _position_in(room, node as Node2D) - tiles.position
			result.append(Vector2i((local / RoomTiles.TILE_WORLD).floor()))
	return result


## Position relative to room, also before the room entered the tree.
static func _position_in(room: Node2D, node: Node2D) -> Vector2:
	var transform := node.transform
	var parent := node.get_parent()
	while parent != null and parent != room:
		if parent is Node2D:
			transform = (parent as Node2D).transform * transform
		parent = parent.get_parent()
	return transform.origin

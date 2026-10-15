class_name PassageSeam
extends RefCounted
## The seam between two joined rooms (M2, 11_makeover3_komplett.md §11/§12): with one gate per
## transition and at most one tile of corridor the rooms overlap (ExitRules.JOIN_OVERLAP) - the next
## room's south wall lies on this room's wall crown, its west/east wall right behind this room's door.
## Both rooms paint their own ring of rock there, so every cell painted by both belongs to one of them,
## decided by their floors (rooms from plans are no rectangles, 30.png):
##   - a floor tile (corridors included) to the room it is floor of; floor of both (the end of a
##     corridor lying in the next room, 42.png) to the room whose own floor it is, not a corridor,
##   - a wall tile right beside the floor of only one room to that room,
##   - beside both floors to the room it is the wall front of (its floor right below),
##   - anything else (rock on rock) stays as it is.
## The other room erases its copy of the cell, so the owner's floor, wall pieces (light edges along
## its floor) and collision show, whichever room is drawn on top. When the owner goes (unloaded,
## faded branch way) the erased cells come back (release), so no hole stays behind.
## A cell counts on every layer that draws the room: the RoomTiles layer itself (collision) and its
## draw-only child layers (campfire blend, cave rock, zones and overlays of M1), not the rock backdrop.
## Two looks side by side (playtest 14.10.2026, M1: a built room next to a cave): the cave rock
## surrounds the built room, whose walls end with their own edge. The built room gives up its outer
## rock ring and its backdrop wherever the cave room's rock lies (never next to its own floor or
## corridors, so its walls still block), so no rectangle of the other rock shows between them.
## Corridor and gate tiles carry no loose decoration (M1 overlays) of either room.
## Tiles only, no RNG, no gameplay state.

## Erased cells on a room's RoomTiles: {instance id of the owner room: {layer name: {cell: [source,
## atlas, alt]}}}; the RoomTiles layer itself is &"".
const META_ERASED := &"passage_seam_erased"
## Child layers that never take part in the seam of the walls (the rock ring below every room).
const SKIPPED_LAYERS: Array[StringName] = [&"Backdrop", &"BiomeBlendBackdrop"]
const BACKDROP_LAYER := &"Backdrop"
## M1's layer of loose decoration on the floor (pebbles, tufts, bones): none in corridors.
const OVERLAY_LAYER := &"Overlays"

enum Owner { NONE, FIRST, SECOND }


## Settles every cell first and second both paint; returns the number of erased cells.
static func join(first: Node2D, second: Node2D) -> int:
	var first_tiles := _tiles_of(first)
	var second_tiles := _tiles_of(second)
	if first_tiles == null or second_tiles == null:
		return 0
	var first_origin := origin_of(first)
	var second_origin := origin_of(second)
	var first_rect := Rect2i(first_origin + first_tiles.get_painted_rect().position, first_tiles.get_painted_rect().size)
	var second_rect := Rect2i(second_origin + second_tiles.get_painted_rect().position, second_tiles.get_painted_rect().size)
	var overlap := first_rect.intersection(second_rect)
	if overlap.size == Vector2i.ZERO:
		return 0
	var erased := 0
	var first_floor := _world_floor(first_tiles, first_origin)
	var second_floor := _world_floor(second_tiles, second_origin)
	var first_corridors := _world_corridors(first_tiles, first_origin)
	var second_corridors := _world_corridors(second_tiles, second_origin)
	for y in range(overlap.position.y, overlap.end.y):
		for x in range(overlap.position.x, overlap.end.x):
			var world := Vector2i(x, y)
			var in_first := world - first_origin
			var in_second := world - second_origin
			if not _painted(first_tiles, in_first) or not _painted(second_tiles, in_second):
				continue
			match owner_by_floor(world, first_floor, second_floor, first_corridors, second_corridors):
				Owner.FIRST:
					_erase(second_tiles, in_second, first)
					erased += 1
				Owner.SECOND:
					_erase(first_tiles, in_first, second)
					erased += 1
	erased += _clear_corridors(first, second) + _clear_corridors(second, first)
	if is_cave_look(first_tiles) != is_cave_look(second_tiles):
		erased += _yield_to_cave(second, first) if is_cave_look(first_tiles) else _yield_to_cave(first, second)
	return erased


## Is a room drawn in M1's cave look (rock terrain) rather than as a built room?
static func is_cave_look(tiles: RoomTiles) -> bool:
	return tiles != null and tiles.has_method(&"is_cave_look") and bool(tiles.call(&"is_cave_look"))


## No loose decoration on the corridor and gate tiles of room (keyed by other).
static func _clear_corridors(room: Node2D, other: Node2D) -> int:
	var tiles := _tiles_of(room)
	if tiles == null:
		return 0
	var overlay: TileMapLayer = _layers_of(tiles).get(OVERLAY_LAYER)
	if overlay == null:
		return 0
	var count := 0
	for cell in tiles.get_door_corridor_tiles():
		if overlay.get_cell_source_id(cell) != -1:
			_erase_layer(tiles, OVERLAY_LAYER, overlay, cell, other)
			count += 1
	return count


## The built room gives up its outer rock (ring and backdrop) where the cave room's rock lies, except
## right beside its own walkable tiles (its corridors keep their walls).
static func _yield_to_cave(built: Node2D, cave: Node2D) -> int:
	var tiles := _tiles_of(built)
	var cave_tiles := _tiles_of(cave)
	var origin := origin_of(built)
	var cave_origin := origin_of(cave)
	var cave_area := cave_tiles.get_backdrop_rect()
	cave_area.position += cave_origin
	var body := ExitRules.body_rect_of(tiles.room_size)
	var walkable := tiles.get_walkable_tiles()
	var floor_mask := tiles.get_floor_mask()
	var count := 0
	var layers := _layers_of(tiles)
	var backdrop := _backdrop_of(tiles)
	var area := tiles.get_backdrop_rect()
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			if body.has_point(cell) or floor_mask.has(cell) or not cave_area.has_point(cell + origin):
				continue
			if _beside(cell, walkable):
				continue
			for layer_name: StringName in layers:
				var layer: TileMapLayer = layers[layer_name]
				if layer.get_cell_source_id(cell) != -1:
					_erase_layer(tiles, layer_name, layer, cell, cave)
					count += 1
			if backdrop != null and backdrop.get_cell_source_id(cell) != -1:
				_erase_layer(tiles, BACKDROP_LAYER, backdrop, cell, cave)
				count += 1
	return count


## A walkable tile within one tile (8 neighbours) of cell?
static func _beside(cell: Vector2i, walkable: Dictionary) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if walkable.has(cell + Vector2i(dx, dy)):
				return true
	return false


## gone leaves: every room in others gets back the cells it gave up for gone - except cells that lie
## in the floor and wall ring of another live room by now (a newer room may have been placed there;
## giving them back would put rock and collision on its floor).
static func release(gone: Node, others: Array) -> void:
	if gone == null:
		return
	var key := gone.get_instance_id()
	var bodies: Dictionary = {}
	for other: Variant in others:
		var live := other as Node2D
		if live != null and is_instance_valid(live) and live != gone and _tiles_of(live) != null:
			var body := ExitRules.body_rect_of(_tiles_of(live).room_size)
			bodies[live] = Rect2i(body.position + origin_of(live), body.size)
	for other: Variant in others:
		var room := other as Node2D
		if room == null or not is_instance_valid(room) or room == gone:
			continue
		var tiles := _tiles_of(room)
		if tiles == null or not tiles.has_meta(META_ERASED):
			continue
		var origin := origin_of(room)
		var erased: Dictionary = tiles.get_meta(META_ERASED)
		if not erased.has(key):
			continue
		var layers := _layers_of(tiles)
		var backdrop := _backdrop_of(tiles)
		if backdrop != null:
			layers[BACKDROP_LAYER] = backdrop
		var by_layer: Dictionary = erased[key]
		for layer_name: StringName in by_layer:
			var layer: TileMapLayer = layers.get(layer_name)
			if layer == null:
				continue
			var cells: Dictionary = by_layer[layer_name]
			for cell: Vector2i in cells:
				if _in_other_body(cell + origin, room, bodies):
					continue
				var entry: Array = cells[cell]
				layer.set_cell(cell, entry[0], entry[1], entry[2])
		erased.erase(key)


static func _in_other_body(world: Vector2i, room: Node, bodies: Dictionary) -> bool:
	for live: Node in bodies:
		if live != room and (bodies[live] as Rect2i).has_point(world):
			return true
	return false


## Cells room gave up for other (room-local), empty if none.
static func get_erased(room: Node, other: Node) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var tiles := _tiles_of(room)
	if tiles == null or other == null or not tiles.has_meta(META_ERASED):
		return cells
	var erased: Dictionary = tiles.get_meta(META_ERASED)
	if erased.has(other.get_instance_id()):
		var by_layer: Dictionary = erased[other.get_instance_id()]
		for layer_name: StringName in by_layer:
			for cell: Vector2i in by_layer[layer_name]:
				if not cells.has(cell):
					cells.append(cell)
	return cells


## Who keeps a world tile both rooms paint (rooms given by origin and size, see the class comment).
static func owner_of(tile: Vector2i, first_origin: Vector2i, first_size: Vector2i, second_origin: Vector2i, second_size: Vector2i) -> Owner:
	var in_first := ExitRules.body_rect_of(first_size).has_point(tile - first_origin)
	var in_second := ExitRules.body_rect_of(second_size).has_point(tile - second_origin)
	if in_first != in_second:
		return Owner.FIRST if in_first else Owner.SECOND
	if not in_first:
		return Owner.NONE
	var near_first := _near_floor(first_size).has_point(tile - first_origin)
	var near_second := _near_floor(second_size).has_point(tile - second_origin)
	if near_first != near_second:
		return Owner.FIRST if near_first else Owner.SECOND
	return Owner.NONE


## Who keeps a world tile both rooms paint, from their floors (world tiles, corridors included) and
## their door corridors (world tiles).
static func owner_by_floor(tile: Vector2i, first_floor: Dictionary, second_floor: Dictionary, first_corridors: Dictionary = {}, second_corridors: Dictionary = {}) -> Owner:
	var floor_first := first_floor.has(tile)
	var floor_second := second_floor.has(tile)
	if floor_first != floor_second:
		return Owner.FIRST if floor_first else Owner.SECOND
	if floor_first:
		var own_first := not first_corridors.has(tile)
		var own_second := not second_corridors.has(tile)
		if own_first != own_second:
			return Owner.FIRST if own_first else Owner.SECOND
		return Owner.NONE
	var near_first := _beside(tile, first_floor)
	var near_second := _beside(tile, second_floor)
	if near_first != near_second:
		return Owner.FIRST if near_first else Owner.SECOND
	if near_first:
		var front_first := first_floor.has(tile + Vector2i.DOWN)
		var front_second := second_floor.has(tile + Vector2i.DOWN)
		if front_first != front_second:
			return Owner.FIRST if front_first else Owner.SECOND
	return Owner.NONE


static func _world_floor(tiles: RoomTiles, origin: Vector2i) -> Dictionary:
	var world: Dictionary = {}
	for tile: Vector2i in tiles.get_floor_mask():
		world[tile + origin] = true
	return world


static func _world_corridors(tiles: RoomTiles, origin: Vector2i) -> Dictionary:
	var world: Dictionary = {}
	for tile: Vector2i in tiles.get_door_corridor_tiles():
		world[tile + origin] = true
	return world


## World tile of a room's tile (0, 0) (same as DungeonManager.get_room_origin).
static func origin_of(room: Node2D) -> Vector2i:
	return Vector2i((room.position / RoomTiles.TILE_WORLD).round())


## Floor and the wall tiles right around it (the north wall's front row, not its crown).
static func _near_floor(size: Vector2i) -> Rect2i:
	return Rect2i(-Vector2i.ONE, size + Vector2i(2, 2))


static func _erase(tiles: RoomTiles, cell: Vector2i, owner: Node) -> void:
	var layers := _layers_of(tiles)
	for layer_name: StringName in layers:
		var layer: TileMapLayer = layers[layer_name]
		if layer.get_cell_source_id(cell) != -1:
			_erase_layer(tiles, layer_name, layer, cell, owner)


## Erases one cell of one layer of tiles and remembers it under owner (given back by release).
static func _erase_layer(tiles: RoomTiles, layer_name: StringName, layer: TileMapLayer, cell: Vector2i, owner: Node) -> void:
	var erased: Dictionary = tiles.get_meta(META_ERASED, {})
	var key := owner.get_instance_id()
	var by_layer: Dictionary = erased.get(key, {})
	var cells: Dictionary = by_layer.get(layer_name, {})
	if not cells.has(cell):
		cells[cell] = [layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell)]
	by_layer[layer_name] = cells
	erased[key] = by_layer
	tiles.set_meta(META_ERASED, erased)
	layer.erase_cell(cell)


static func _backdrop_of(tiles: RoomTiles) -> TileMapLayer:
	for child in tiles.get_children(true):
		if child is TileMapLayer and StringName(child.name) == BACKDROP_LAYER:
			return child
	return null


static func _tiles_of(room: Node) -> RoomTiles:
	if room == null or not is_instance_valid(room):
		return null
	return room.get_node_or_null("Tiles") as RoomTiles


## Every layer that draws the room's cells by name: the RoomTiles layer (&"") and its tile layer
## children (internal ones included) except the rock backdrop.
static func _layers_of(tiles: RoomTiles) -> Dictionary[StringName, TileMapLayer]:
	var layers: Dictionary[StringName, TileMapLayer] = {&"": tiles}
	for child in tiles.get_children(true):
		if child is TileMapLayer and not SKIPPED_LAYERS.has(StringName(child.name)):
			layers[StringName(child.name)] = child
	return layers


## Does the room draw anything at cell (any of its layers)?
static func _painted(tiles: RoomTiles, cell: Vector2i) -> bool:
	for layer: TileMapLayer in _layers_of(tiles).values():
		if layer.get_cell_source_id(cell) != -1:
			return true
	return false

extends GutTest
## Walls as one 47-piece terrain and organic plans (M1, Makeover 3 §2.1/§10, playtest 14.10.2026),
## over every template of both catalogs, every biome and mirror:
##   - every border between floor and solid gets a terrain piece with its edge, corners included
##     (the piece matches the 8-neighbour mask; the delivered sheets hold all 47 pieces);
##   - no enclosed rock on the rock layer (the backdrop shows it, a room never covers its
##     neighbour's edges);
##   - no one-tile slots between solid things, no wall front right above an abyss;
##   - props never overlap (visible art rects), overlays never lie under props, sources or
##     objectives, nothing that lies on the floor reaches over abyss or rock;
##   - everything is reachable on foot from the entrance and from every side door.

const SHEETS: Array[String] = [
	"res://art/environment/tiles/rock_blob_crypt_soft.json",
	"res://art/environment/tiles/rock_blob_crypt.json",
]
const BIOMES: Array[StringName] = [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]
const BIOME_TILESET_PATH := "res://dungeon/environment/%s_tileset.tres"
const BASE_TILESET_PATH := "res://dungeon/environment/dungeon_tileset.tres"
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
## Pixels two visible rects may share before they count as overlapping (rounding of the art).
const OVERLAP_TOLERANCE := 1.0

var _old_save_path: String
var _entries: Array[RoomTemplate] = []


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_room_terrain_save.cfg"
	var seen := {}
	for catalog: RoomCatalog in [RoomCatalog.create(), RoomCatalog.load_plans()]:
		for entry in catalog.get_entries():
			if entry.scene != null and not seen.has(entry.scene.resource_path):
				seen[entry.scene.resource_path] = true
				_entries.append(entry)


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _tileset_of(entry: RoomTemplate) -> TileSet:
	var biome: StringName = entry.allowed_biomes[0] if not entry.allowed_biomes.is_empty() else &"crypt"
	var path := BIOME_TILESET_PATH % biome
	return load(path if ResourceLoader.exists(path) else BASE_TILESET_PATH) as TileSet


## The room in the tree, painted with its biome's tileset.
func _room(entry: RoomTemplate) -> RoomController:
	var room := entry.scene.instantiate() as RoomController
	add_child_autofree(room)
	room.tiles.use_tileset(_tileset_of(entry))
	room.tiles.paint()
	return room


# --- the terrain ---

func test_the_sheets_hold_all_47_pieces_and_the_fronts() -> void:
	for path in SHEETS:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var tiles: Dictionary = data["tiles"]
		for mask in RockTerrain.MASKS:
			assert_true(tiles.has("r%d" % mask), "%s: r%d" % [path, mask])
			var cell: Dictionary = tiles["r%d" % mask]
			assert_eq(RockTerrain.rock_coords(mask), Vector2i(int(cell["col"]), int(cell["row"])), "%s: r%d where the sheet has it" % [path, mask])
		for front: String in ["front_left", "front_mid", "front_right", "front_single"]:
			var cell: Dictionary = tiles[front]
			assert_eq(RockTerrain.front_coords(["front_left", "front_mid", "front_right", "front_single"].find(front)), Vector2i(int(cell["col"]), int(cell["row"])), "%s: %s" % [path, front])
	# Every 8-bit mask maps to one of the 47 pieces; corner bits only with both sides.
	var pieces := {}
	for mask in 256:
		var normal := RockTerrain.normalize(mask)
		assert_true(RockTerrain.MASKS.has(normal), "mask %d -> %d is a piece" % [mask, normal])
		pieces[normal] = true
	assert_eq(pieces.size(), 47)


func test_every_floor_border_gets_its_edge_in_every_template() -> void:
	var checked := 0
	var problems: Array[String] = []
	for entry in _entries:
		var room := _room(entry)
		var tiles := room.get_node("Tiles") as RoomTiles
		assert_true(tiles.is_terrain_drawn(), "%s: the terrain is drawn" % entry.id)
		assert_eq(tiles.get_look() == RockTerrain.Look.CAVE, tiles.rock_style == RoomTiles.RockStyle.BLOB, "%s: look follows the plan" % entry.id)
		assert_true(tiles.is_cave_look(), "%s: soft rock in every room (caves and halls match)" % entry.id)
		var rock := tiles.get_rock_layer()
		var floor_mask := tiles.get_floor_mask()
		var rect := tiles.get_painted_rect()
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var tile := Vector2i(x, y)
				if floor_mask.has(tile):
					if rock.get_cell_source_id(tile) != -1:
						problems.append("%s: rock piece on floor %s" % [entry.id, tile])
					continue
				var borders := false
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						borders = borders or floor_mask.has(tile + Vector2i(dx, dy))
				if not borders:
					if rock.get_cell_source_id(tile) != -1:
						problems.append("%s: enclosed rock %s drawn on the room (covers neighbours)" % [entry.id, tile])
					continue
				checked += 1
				if rock.get_cell_source_id(tile) != RockTerrain.rock_source(tiles.get_look()):
					problems.append("%s: no terrain piece at border %s" % [entry.id, tile])
					continue
				var expected := RockTerrain.piece_for(tile, floor_mask)
				if rock.get_cell_atlas_coords(tile) != expected:
					problems.append("%s: piece %s at %s, mask wants %s" % [entry.id, rock.get_cell_atlas_coords(tile), tile, expected])
				if not WallAutotile.is_front(tile, floor_mask) and RockTerrain.mask_for(tile, floor_mask) == RockTerrain.FULL:
					problems.append("%s: border %s without an edge" % [entry.id, tile])
				# Collision stays with the room layer: an invisible solid tile on every solid cell.
				if tiles.get_cell_source_id(tile) != RockTerrain.SOURCE_GROUND or tiles.get_cell_atlas_coords(tile) != RockTerrain.SOLID:
					if tiles.get_floor_rect().has_point(RoomTiles.tile_to_local(tile)):
						problems.append("%s: no solid cell under the rock at %s" % [entry.id, tile])
		room.free()
	assert_gt(checked, 10000, "border tiles checked")
	assert_eq(problems.slice(0, 20), [] as Array[String], "%d problems: %s" % [problems.size(), "; ".join(problems.slice(0, 6))])


func test_corner_bits_follow_the_floor() -> void:
	# A rock tile with floor only diagonally (inner corner): all four sides rock, one corner open.
	var floor_mask: Dictionary[Vector2i, bool] = {Vector2i(1, 1): true}
	var mask := RockTerrain.mask_for(Vector2i.ZERO, floor_mask)
	assert_eq(mask, RockTerrain.N | RockTerrain.NE | RockTerrain.E | RockTerrain.S | RockTerrain.SW | RockTerrain.W | RockTerrain.NW, "only the SE corner open")
	assert_ne(RockTerrain.rock_coords(mask), RockTerrain.rock_coords(RockTerrain.FULL), "drawn with its inner corner")
	# Outer corner: floor west and south, so neither of their corners counts.
	floor_mask = {Vector2i(-1, 0): true, Vector2i(0, 1): true, Vector2i(-1, 1): true}
	assert_eq(RockTerrain.mask_for(Vector2i.ZERO, floor_mask), RockTerrain.N | RockTerrain.NE | RockTerrain.E)


# --- plan rules ---

func _blocked(tiles: RoomTiles, floor_mask: Dictionary[Vector2i, bool], tile: Vector2i) -> bool:
	return not floor_mask.has(tile) or tiles.is_pit(tile)


func test_no_one_tile_slots_and_no_front_over_an_abyss() -> void:
	var problems: Array[String] = []
	for entry in _entries:
		var room := entry.scene.instantiate() as RoomController
		var tiles := room.get_node("Tiles") as RoomTiles
		var floor_mask := tiles.get_floor_mask()
		for tile: Vector2i in floor_mask:
			if not Rect2i(Vector2i.ZERO, tiles.room_size).has_point(tile) or tiles.is_pit(tile) or tiles.is_bridge(tile):
				continue
			if _blocked(tiles, floor_mask, tile + Vector2i.LEFT) and _blocked(tiles, floor_mask, tile + Vector2i.RIGHT):
				problems.append("%s: slot at %s (west/east)" % [entry.id, tile])
			if _blocked(tiles, floor_mask, tile + Vector2i.UP) and _blocked(tiles, floor_mask, tile + Vector2i.DOWN):
				problems.append("%s: slot at %s (north/south)" % [entry.id, tile])
		for pit in tiles.get_pit_tiles():
			if not floor_mask.has(pit + Vector2i.UP):
				problems.append("%s: wall front right above the abyss at %s" % [entry.id, pit])
		room.free()
	assert_eq(problems.slice(0, 20), [] as Array[String], "%d problems: %s" % [problems.size(), "; ".join(problems.slice(0, 6))])


func test_everything_is_reachable_from_every_entrance() -> void:
	var problems: Array[String] = []
	for entry in _entries:
		var room := entry.scene.instantiate() as RoomController
		var tiles := room.get_node("Tiles") as RoomTiles
		var walkable := tiles.get_walkable_tiles()
		var solids := RoomPlanChecks.solid_tiles(room)
		var sources := RoomPlanChecks.floor_source_tiles(room)
		var open: Dictionary[Vector2i, bool] = {}
		for tile: Vector2i in walkable:
			if not solids.has(tile) and not sources.has(tile):
				open[tile] = true
		var starts: Array[Vector2i] = [tiles.get_entrance_inside_tile()]
		var start_marker := room.get_player_start_marker()
		if start_marker != null:
			starts.append(RoomTiles.local_to_tile(start_marker.position))
		for side in [RoomTiles.DoorSide.WEST, RoomTiles.DoorSide.EAST]:
			for place in tiles.get_door_slots(side):
				starts.append(RoomTiles.inside_tile_of(side, place, tiles.room_size))
		var targets: Array[Vector2i] = []
		for slot in tiles.door_slots:
			targets.append(RoomTiles.inside_tile_of(slot.x, slot.y, tiles.room_size))
		for marker in room.get_sources():
			targets.append(marker.get_meta(&"floor_tile"))
		for marker in room.get_objectives():
			var tile: Vector2i = marker.get_meta(&"tile")
			if not solids.has(tile):
				targets.append(tile)
		for tile: Vector2i in open:
			if Rect2i(Vector2i.ZERO, tiles.room_size).has_point(tile):
				targets.append(tile)
		var none: Dictionary[Vector2i, bool] = {}
		for start in starts:
			var reached := RoomTiles.flood_fill(open, none, start, 0)
			for target in targets:
				# Sources and solid things count as blocked: one of their sides must be reachable.
				var near := reached.has(target)
				for direction in DIRECTIONS:
					near = near or ((sources.has(target) or solids.has(target)) and reached.has(target + direction))
				if not near:
					problems.append("%s: %s not reachable from %s" % [entry.id, target, start])
					break
		room.free()
	assert_eq(problems.slice(0, 20), [] as Array[String], "%d problems: %s" % [problems.size(), "; ".join(problems.slice(0, 6))])


# --- props ---

## Visible rect (room-local px) of everything a prop draws, from the alpha bounds of its art.
func _visible_rect(prop: Node2D, room: Node2D) -> Rect2:
	var result := Rect2()
	var found := false
	var stack: Array[Node] = [prop]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var texture: Texture2D = null
		var region := Rect2()
		var offset := Vector2.ZERO
		var centered := true
		if node is DropShadow or node is LightSource:
			continue
		if node is AnimatedSprite2D:
			var animated := node as AnimatedSprite2D
			if animated.sprite_frames == null:
				continue
			texture = animated.sprite_frames.get_frame_texture(animated.animation, 0)
			offset = animated.offset
			centered = animated.centered
		elif node is Sprite2D:
			var sprite := node as Sprite2D
			texture = sprite.texture
			offset = sprite.offset
			centered = sprite.centered
			if sprite.region_enabled:
				region = sprite.region_rect
			elif sprite.hframes > 1 or sprite.vframes > 1:
				var frame_size := sprite.texture.get_size() / Vector2(sprite.hframes, sprite.vframes) if sprite.texture != null else Vector2.ZERO
				region = Rect2(Vector2(sprite.frame_coords) * frame_size, frame_size)
		else:
			continue
		if texture == null or not (node as CanvasItem).visible:
			continue
		var image := texture.get_image()
		if image == null:
			continue
		if image.is_compressed():
			image.decompress()
		if region.size == Vector2.ZERO:
			region = Rect2(Vector2.ZERO, texture.get_size())
		var used := image.get_region(Rect2i(region)).get_used_rect()
		if used.size == Vector2i.ZERO:
			continue
		var origin := offset - (region.size / 2.0 if centered else Vector2.ZERO)
		var local := Rect2(origin + Vector2(used.position), Vector2(used.size))
		var canvas := node as Node2D
		# A negative scale mirrors through the transform below; flip_h mirrors the art itself.
		if (node is Sprite2D and (node as Sprite2D).flip_h) or (node is AnimatedSprite2D and (node as AnimatedSprite2D).flip_h):
			local = Rect2(Vector2(-local.end.x, local.position.y), local.size)
		var to_room := room.get_global_transform().affine_inverse() * canvas.get_global_transform()
		var a := to_room * local.position
		var b := to_room * local.end
		var world := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (a - b).abs())
		result = world if not found else result.merge(world)
		found = true
	return result if found else Rect2()


func test_props_never_overlap_and_lie_on_floor() -> void:
	var problems: Array[String] = []
	var props_checked := 0
	for entry in _entries:
		var room := _room(entry)
		var tiles := room.get_node("Tiles") as RoomTiles
		var floor_mask := tiles.get_floor_mask()
		var rects: Array = []
		for prop in room.get_node("Props").get_children():
			var node := prop as Node2D
			if node == null:
				continue
			var rect := _visible_rect(node, room)
			if rect.size == Vector2.ZERO:
				continue
			rects.append([String(node.name), rect.grow(-OVERLAP_TOLERANCE), node])
			props_checked += 1
			var deco := node as DecoProp
			var layer := int(DecoProp.ITEMS.get(deco.item, {}).get("layer", DecoProp.Layer.STANDING)) if deco != null else DecoProp.Layer.STANDING
			if String(node.name).begins_with("Torch") and not String(node.name).begins_with("TorchStand"):
				layer = DecoProp.Layer.WALL
			if layer == DecoProp.Layer.WALL:
				continue
			var origin := RoomTiles.local_to_tile(node.position - Vector2(0, 1))
			if not floor_mask.has(origin) or tiles.is_pit(origin):
				problems.append("%s: %s stands off the floor at %s" % [entry.id, node.name, origin])
			if layer == DecoProp.Layer.FLOOR:
				for tile in _tiles_under(rect.grow(-2.0)):
					if not floor_mask.has(tile) or tiles.is_pit(tile):
						problems.append("%s: %s reaches over %s (abyss or rock)" % [entry.id, node.name, tile])
						break
		for i in rects.size():
			for j in range(i + 1, rects.size()):
				var a: Array = rects[i]
				var b: Array = rects[j]
				if (a[0] as String).begins_with("Drip") or (b[0] as String).begins_with("Drip"):
					continue
				if (a[1] as Rect2).intersects(b[1]):
					problems.append("%s: %s overlaps %s" % [entry.id, a[0], b[0]])
		# Overlays: never under a prop, a source or an objective.
		var taken: Dictionary[Vector2i, bool] = {}
		for marker in room.get_sources():
			taken[marker.get_meta(&"tile")] = true
		for marker in room.get_objectives():
			taken[marker.get_meta(&"tile")] = true
		for item: Array in rects:
			for tile in _tiles_under((item[1] as Rect2).grow(-4.0)):
				taken[tile] = true
		for cell in tiles.overlay_cells:
			var tile := Vector2i(cell.x, cell.y)
			if taken.has(tile):
				problems.append("%s: overlay under a thing at %s (%s)" % [entry.id, tile, _what_at(room, rects, tile)])
			if not floor_mask.has(tile) or tiles.is_pit(tile):
				problems.append("%s: overlay off the floor at %s" % [entry.id, tile])
		for cell in tiles.zone_cells:
			if not floor_mask.has(Vector2i(cell.x, cell.y)):
				problems.append("%s: zone off the floor at %s" % [entry.id, Vector2i(cell.x, cell.y)])
		# Sources, objectives and spawn markers on walkable floor.
		var walkable := tiles.get_walkable_tiles()
		for marker in room.get_sources():
			if not walkable.has(marker.get_meta(&"floor_tile")):
				problems.append("%s: %s off the floor" % [entry.id, marker.name])
		for marker in room.get_objectives():
			if not walkable.has(marker.get_meta(&"tile")):
				problems.append("%s: %s off the floor" % [entry.id, marker.name])
		for marker in room.get_node("SpawnPoints").get_children():
			if not walkable.has(RoomTiles.local_to_tile((marker as Node2D).position)):
				problems.append("%s: %s off the floor" % [entry.id, marker.name])
		room.free()
	assert_gt(props_checked, 1000)
	assert_eq(problems.slice(0, 20), [] as Array[String], "%d problems: %s" % [problems.size(), "; ".join(problems.slice(0, 6))])


func _tiles_under(rect: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var low := RoomTiles.local_to_tile(rect.position)
	var high := RoomTiles.local_to_tile(rect.end)
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			result.append(Vector2i(x, y))
	return result


# --- caves ---

func test_cave_plans_are_no_boxes() -> void:
	var caves := 0
	for entry in _entries:
		if entry.role != RoomTemplate.ROLE_COMBAT or entry.rock_style != RoomTiles.RockStyle.BLOB:
			continue
		caves += 1
		var room := entry.scene.instantiate() as RoomController
		var tiles := room.get_node("Tiles") as RoomTiles
		var walls := tiles.get_wall_tiles()
		var rect_area := tiles.room_size.x * tiles.room_size.y
		assert_lt(tiles.get_walkable_tiles().size(), rect_area, "%s: not the full rectangle" % entry.id)
		assert_false(walls.is_empty() and not tiles.has_pits(), "%s: rock or abyss inside" % entry.id)
		if entry.size_class != RoomSequence.RoomSize.L:
			assert_between(tiles.room_size.x + 4, 17, 23, "%s: cave width (Makeover 3 §9)" % entry.id)
			assert_between(tiles.room_size.y + 5, 11, 13, "%s: cave height" % entry.id)
		assert_true(tiles.cave_mouth, "%s: cave mouth for M2" % entry.id)
		room.free()
	assert_gt(caves, 100, "cave templates")


func test_zones_and_overlays_are_drawn() -> void:
	var entry: RoomTemplate = null
	for candidate in _entries:
		if candidate.plan_id == &"tropfsteinhoehle" and candidate.allowed_biomes.has(&"slime_grotto") and not candidate.mirrored:
			entry = candidate
	assert_not_null(entry)
	var room := _room(entry)
	var tiles := room.tiles
	assert_false(tiles.zone_cells.is_empty())
	assert_false(tiles.overlay_cells.is_empty())
	assert_gt(tiles.get_zone_layer().get_used_cells().size(), 10, "zones drawn")
	assert_gt(tiles.get_overlay_layer().get_used_cells().size(), 10, "overlays drawn")
	for cell in tiles.get_zone_layer().get_used_cells():
		assert_eq(tiles.get_zone_layer().get_cell_source_id(cell), RockTerrain.SOURCE_ZONES)
	# The backdrop is the cave's own rock, and the hook for rock fills says so.
	var fill := tiles.get_rock_fill_cell()
	assert_eq(fill.z, RockTerrain.SOURCE_ROCK)
	assert_eq(tiles.get_backdrop().get_cell_source_id(Vector2i(-6, -6)), RockTerrain.SOURCE_ROCK)


func _what_at(room: RoomController, rects: Array, tile: Vector2i) -> String:
	var names: Array[String] = []
	for item: Array in rects:
		if _tiles_under((item[1] as Rect2).grow(-4.0)).has(tile):
			names.append(item[0])
	for marker in room.get_sources() + room.get_objectives():
		if marker.get_meta(&"tile") == tile:
			names.append(marker.name)
	return ", ".join(names)

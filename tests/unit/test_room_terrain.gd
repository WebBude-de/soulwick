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
##   - everything is reachable on foot from the entrance and from every side door;
##   - wall things (torches, niches, chains) hang fully on rock, their lowest row on a front
##     (playtest 15.10.2026: a torch stem below a front);
##   - inner corners and steps are round: the band's joint, fillets in the floor, fronts that end
##     at a step get their rounded end piece (playtest 15.10.2026).

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
					var fillet := 0 if tiles.is_pit(tile) else RockTerrain.fillet_bits(tile, floor_mask)
					if rock.get_cell_source_id(tile) != -1 and (fillet == 0 or rock.get_cell_atlas_coords(tile) != RockTerrain.fillet_coords(fillet)):
						problems.append("%s: rock piece on floor %s" % [entry.id, tile])
					continue
				# Plateaus are no rock (half height, D-205): the HeightField draws them.
				if tiles.get_height_layout().get_height_tiles().has(tile):
					if rock.get_cell_source_id(tile) != -1:
						problems.append("%s: rock piece on the plateau at %s" % [entry.id, tile])
					continue
				# Rock borders on floor, or on a front beside it (the side wall's edge goes up to it).
				var borders := WallAutotile.is_front(tile + Vector2i.LEFT, floor_mask) or WallAutotile.is_front(tile + Vector2i.RIGHT, floor_mask)
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
				# Collision stays with the room layer: an invisible solid tile on every solid cell, its
				# outer corners rounded like the art (the height of a plateau has its walls on the
				# HeightField, M3, test_height_room).
				if not RockTerrain.is_solid_cell(tiles.get_cell_source_id(tile), tiles.get_cell_atlas_coords(tile)):
					if tiles.get_floor_rect().has_point(RoomTiles.tile_to_local(tile)):
						problems.append("%s: no solid cell under the rock at %s" % [entry.id, tile])
				elif tiles.get_cell_atlas_coords(tile).x != RockTerrain.solid_corners(tile, floor_mask):
					problems.append("%s: collision corners at %s do not follow the art" % [entry.id, tile])
		room.free()
	assert_gt(checked, 10000, "border tiles checked")
	assert_eq(problems.slice(0, 20), [] as Array[String], "%d problems: %s" % [problems.size(), "; ".join(problems.slice(0, 6))])


func test_corner_bits_follow_the_floor() -> void:
	# A rock tile with floor only diagonally (inner corner): all four sides rock, one corner open.
	var floor_mask: Dictionary[Vector2i, bool] = {Vector2i(1, -1): true}
	var mask := RockTerrain.mask_for(Vector2i.ZERO, floor_mask)
	assert_eq(mask, RockTerrain.N | RockTerrain.E | RockTerrain.SE | RockTerrain.S | RockTerrain.SW | RockTerrain.W | RockTerrain.NW, "only the NE corner open")
	assert_ne(RockTerrain.rock_coords(mask), RockTerrain.rock_coords(RockTerrain.FULL), "drawn with its inner corner")
	# Outer corner: floor west and south, so neither of their corners counts.
	floor_mask = {Vector2i(-1, 0): true, Vector2i(0, 1): true, Vector2i(-1, 1): true}
	assert_eq(RockTerrain.mask_for(Vector2i.ZERO, floor_mask), RockTerrain.N | RockTerrain.NE | RockTerrain.E)


func test_inner_corners_and_steps_are_round() -> void:
	# A floor cell with rock beside and below: fillets in its lower corners, none on an abyss side.
	var floor_mask: Dictionary[Vector2i, bool] = {Vector2i(0, 0): true, Vector2i(0, -1): true, Vector2i(1, -1): true}
	assert_eq(RockTerrain.fillet_bits(Vector2i(0, 0), floor_mask), RockTerrain.FILLET_LEFT | RockTerrain.FILLET_RIGHT, "rock left, right and below")
	assert_eq(RockTerrain.fillet_bits(Vector2i(0, -1), floor_mask), 0, "floor below: no lower corner")
	floor_mask[Vector2i(1, 0)] = true
	assert_eq(RockTerrain.fillet_bits(Vector2i(0, 0), floor_mask), RockTerrain.FILLET_LEFT, "floor right")
	# A step: the front row y 0 (x 0..1) steps forward to a front at (2, 1). A front ends round only
	# where floor lies beside it; against rock it runs square into that rock's edge, which counts the
	# front as open (playtest 15.10.2026, notes 4/7/10).
	var step: Dictionary[Vector2i, bool] = {Vector2i(0, 1): true, Vector2i(1, 1): true, Vector2i(0, 2): true, Vector2i(1, 2): true, Vector2i(2, 2): true}
	assert_eq(RockTerrain.piece_for(Vector2i(0, 0), step), RockTerrain.front_coords(RockTerrain.Front.MIDDLE), "front runs square into the side wall")
	assert_eq(RockTerrain.piece_for(Vector2i(1, 0), step), RockTerrain.front_coords(RockTerrain.Front.MIDDLE), "front runs square into the step")
	assert_eq(RockTerrain.piece_for(Vector2i(2, 1), step), RockTerrain.front_coords(RockTerrain.Front.LEFT), "front of the step: floor left, rock right")
	assert_eq(RockTerrain.mask_for(Vector2i(-1, 0), step) & RockTerrain.E, 0, "the side wall's edge goes up beside the front")
	assert_eq(RockTerrain.mask_for(Vector2i(2, 0), step) & RockTerrain.W, 0, "the step's crown has its edge towards the front beside it")
	assert_eq(RockTerrain.variant_bits(Vector2i(2, 0), step), RockTerrain.FOOT_LEFT | RockTerrain.JOINT_LEFT, "and turns it round into its own front's top line, joined to the other front's")
	assert_eq(RockTerrain.piece_for(Vector2i(2, 0), step), RockTerrain.variant_coords(RockTerrain.mask_for(Vector2i(2, 0), step), RockTerrain.FOOT_LEFT | RockTerrain.JOINT_LEFT))
	assert_true(RockTerrain.is_enclosed(Vector2i(0, -1), step), "the crown over a straight front stays to the backdrop (the front draws its line)")
	# The composed sheet: the band runs round the inner corner, the fillet piece holds rock only in
	# its corner.
	var tileset := (load(BIOME_TILESET_PATH % &"slime_grotto") as TileSet).duplicate() as TileSet
	assert_true(RockTerrain.ensure_sources(tileset))
	var image := (tileset.get_source(RockTerrain.SOURCE_ROCK) as TileSetAtlasSource).texture.get_image()
	var band := RockTerrain.band_colors(image)
	var inner := RockTerrain.rock_coords(RockTerrain.N | RockTerrain.E | RockTerrain.S | RockTerrain.W | RockTerrain.SE | RockTerrain.SW | RockTerrain.NW) * RockTerrain.TILE
	assert_eq(image.get_pixel(inner.x + RockTerrain.TILE - 1, inner.y), band[0], "inner corner: the band's joint at the corner point")
	# A side wall beside a front: its edge turns into the front's top line at the joint.
	var joint := RockTerrain.variant_coords(RockTerrain.N | RockTerrain.S | RockTerrain.SW | RockTerrain.W | RockTerrain.NW, RockTerrain.JOINT_RIGHT) * RockTerrain.TILE
	assert_eq(image.get_pixel(joint.x + RockTerrain.TILE - 1, joint.y + RockTerrain.BAND - 1), band[0], "joint: light at the corner point")
	assert_eq(image.get_pixel(joint.x + RockTerrain.TILE - RockTerrain.BAND, joint.y), image.get_pixel(joint.x + RockTerrain.TILE / 2, joint.y + RockTerrain.TILE / 2), "joint: no band above the front's line")
	# A crown over the end of a front: its rounded foot shows the front face outside the curve.
	var block := RockTerrain.N | RockTerrain.NE | RockTerrain.E | RockTerrain.SE | RockTerrain.S
	var foot := RockTerrain.variant_coords(block, RockTerrain.FOOT_LEFT) * RockTerrain.TILE
	var single := RockTerrain.front_coords(RockTerrain.Front.SINGLE) * RockTerrain.TILE
	assert_eq(image.get_pixel(foot.x, foot.y + RockTerrain.TILE - 1), image.get_pixel(single.x, single.y + RockTerrain.BAND + RockTerrain.BAND - 1), "foot corner shows the face")
	assert_eq(image.get_pixel(foot.x + 1, foot.y + RockTerrain.TILE - RockTerrain.BAND - 1), band[0], "the side edge runs down to the curve")
	# Every front starts with the band (middle rows on top, light rows towards the face).
	var middle := RockTerrain.front_coords(RockTerrain.Front.MIDDLE) * RockTerrain.TILE
	assert_eq(image.get_pixel(middle.x + RockTerrain.TILE / 2, middle.y), band[RockTerrain.BAND - 1], "front top line: middle colour first")
	assert_eq(image.get_pixel(middle.x + RockTerrain.TILE / 2, middle.y + RockTerrain.BAND - 1), band[0], "then light")
	var fillet := RockTerrain.fillet_coords(RockTerrain.FILLET_LEFT) * RockTerrain.TILE
	assert_gt(image.get_pixel(fillet.x, fillet.y + RockTerrain.TILE - 1).a, 0.5, "fillet: rock in the corner")
	assert_eq(image.get_pixel(fillet.x + RockTerrain.TILE / 2, fillet.y + RockTerrain.TILE / 2).a, 0.0, "fillet: clear elsewhere")


func test_fillets_lie_in_the_lower_inner_corners_of_every_template() -> void:
	var problems: Array[String] = []
	var fillets := 0
	for entry in _entries:
		var room := _room(entry)
		var tiles := room.get_node("Tiles") as RoomTiles
		var rock := tiles.get_rock_layer()
		var floor_mask := tiles.get_floor_mask()
		for tile: Vector2i in floor_mask:
			if not tiles.is_painted(tile):
				continue
			var bits := 0 if tiles.is_pit(tile) else RockTerrain.fillet_bits(tile, floor_mask)
			var has_piece := rock.get_cell_source_id(tile) != -1
			if bits == 0 and has_piece:
				problems.append("%s: rock on floor %s" % [entry.id, tile])
			elif bits != 0:
				fillets += 1
				if rock.get_cell_atlas_coords(tile) != RockTerrain.fillet_coords(bits):
					problems.append("%s: fillet %d missing at %s" % [entry.id, bits, tile])
		room.free()
	assert_gt(fillets, 100, "inner corners found")
	assert_eq(problems.slice(0, 20), [] as Array[String], "%d problems: %s" % [problems.size(), "; ".join(problems.slice(0, 6))])


# --- plan rules ---

## A half-high plateau closes no slot: the floor ring around it may be one tile wide (D-205).
func _blocked(tiles: RoomTiles, floor_mask: Dictionary[Vector2i, bool], tile: Vector2i) -> bool:
	if tiles.has_height() and tiles.get_height_layout().get_height_tiles().has(tile):
		return false
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
		# Sources and mode objects on a plateau surface (M3b, D-189) lie on the upper level:
		# RoomPlanChecks.height_problems / height_enemy_problems check that level.
		var surface: Dictionary[Vector2i, bool] = tiles.get_height_layout().surface if tiles.has_height() else ({} as Dictionary[Vector2i, bool])
		for start in starts:
			var reached := RoomTiles.flood_fill(open, none, start, 0)
			for target in targets:
				if surface.has(target):
					continue
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
				# Fully on rock, the lowest row a front: nothing hangs out under it into the floor.
				var cover := _tiles_under(rect.grow(-1.0))
				var bottom := cover[cover.size() - 1].y
				for tile in cover:
					if floor_mask.has(tile):
						problems.append("%s: %s hangs over the floor at %s" % [entry.id, node.name, tile])
						break
					if tile.y == bottom and not WallAutotile.is_front(tile, floor_mask):
						problems.append("%s: %s ends on %s, no front" % [entry.id, node.name, tile])
						break
				continue
			var origin := RoomTiles.local_to_tile(node.position - Vector2(0, 1))
			# A chest may stand on a plateau surface (M3).
			if (not floor_mask.has(origin) and not tiles.get_height_layout().surface.has(origin)) or tiles.is_pit(origin):
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
		# Sources, objectives and spawn markers on walkable floor; sources and objectives may also stand
		# on a plateau surface (M3b, D-189), spawn markers never.
		var walkable := tiles.get_walkable_tiles()
		var plateau: Dictionary[Vector2i, bool] = tiles.get_height_layout().surface if tiles.has_height() else ({} as Dictionary[Vector2i, bool])
		for marker in room.get_sources():
			var source_tile: Vector2i = marker.get_meta(&"floor_tile")
			if not walkable.has(source_tile) and not plateau.has(source_tile):
				problems.append("%s: %s off the floor" % [entry.id, marker.name])
		for marker in room.get_objectives():
			var objective_tile: Vector2i = marker.get_meta(&"tile")
			if not walkable.has(objective_tile) and not plateau.has(objective_tile):
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


# --- playtest 15.10.2026 (G1): collision, abyss faces, abyss contacts ---

func test_collision_rounds_the_outer_corners_like_the_art() -> void:
	# A lone block (two tiles tall): its top corners and the lower corners of its front are outer
	# corners; the crown's lower corners sit on the front (solid below), so they stay square.
	var floor_mask: Dictionary[Vector2i, bool] = {}
	for y in range(-2, 4):
		for x in range(-2, 3):
			floor_mask[Vector2i(x, y)] = true
	floor_mask.erase(Vector2i(0, 0))
	floor_mask.erase(Vector2i(0, 1))
	assert_eq(RockTerrain.solid_corners(Vector2i(0, 0), floor_mask), RockTerrain.CORNER_TL | RockTerrain.CORNER_TR, "crown: round top")
	assert_eq(RockTerrain.solid_corners(Vector2i(0, 1), floor_mask), RockTerrain.CORNER_BL | RockTerrain.CORNER_BR, "front: round foot")
	# Rock across a corner keeps it square (no pinch to slip through).
	floor_mask.erase(Vector2i(-1, -1))
	assert_eq(RockTerrain.solid_corners(Vector2i(0, 0), floor_mask), RockTerrain.CORNER_TR)
	var square := RockTerrain.solid_polygon(0)
	assert_eq(square.size(), 4, "a plain solid tile is the square")
	var round := RockTerrain.solid_polygon(RockTerrain.CORNER_TL | RockTerrain.CORNER_BR)
	assert_eq(round.size(), 2 + 2 * (RockTerrain.COLLISION_STEPS + 1), "two rounded corners")
	var half := RockTerrain.TILE / 2.0
	assert_false(round.has(Vector2(-half, -half)), "the rounded corner point is cut")
	assert_true(round.has(Vector2(half, -half)), "the square corner stays")
	# The tileset carries every variant with its polygon.
	var tileset := (load(BASE_TILESET_PATH) as TileSet).duplicate() as TileSet
	assert_true(RockTerrain.ensure_sources(tileset))
	var source := tileset.get_source(RockTerrain.SOURCE_GROUND) as TileSetAtlasSource
	for bits in RockTerrain.SOLID_VARIANTS:
		var data := source.get_tile_data(RockTerrain.solid_coords(bits), 0)
		assert_eq(data.get_collision_polygon_points(0, 0), RockTerrain.solid_polygon(bits), "variant %d" % bits)
		assert_null(data.get_navigation_polygon(0), "no navigation on rock")


func test_the_abyss_face_sinks_below_the_rim() -> void:
	var entry := _entry_of("brueckenkreuz_crypt")
	assert_not_null(entry, "brueckenkreuz_crypt in the catalog")
	if entry == null:
		return
	var room := _room(entry)
	var tiles := room.tiles
	var cliffs := tiles.get_cliff_tiles()
	assert_gt(cliffs.size(), 4, "the abysses have north edges")
	var node := tiles.get_node_or_null(RoomTiles.CLIFF_NAME)
	assert_not_null(node)
	if node != null:
		var faces := 0
		for child in node.get_children():
			if not child.is_queued_for_deletion():
				faces += 1
		assert_eq(faces, cliffs.size(), "one face per north edge tile")
	var art := ((tiles.tile_set.get_source(AbyssAutotile.ART_SOURCE_ID) as TileSetAtlasSource).texture.get_image())
	art.decompress()
	art.convert(Image.FORMAT_RGBA8)
	var face := RockTerrain.face_image(&"crypt")
	assert_not_null(face)
	# A north edge with the abyss going on to the east and down: rim on top and to the west.
	var image := AbyssFace.build(face, art, AbyssAutotile.E | AbyssAutotile.S, 0)
	var piece := AbyssAutotile.make_piece(art, AbyssAutotile.E | AbyssAutotile.S, 0)
	assert_eq(image.get_pixel(16, 0).a, 0.0, "the north rim stays the abyss's own (no wall front over it)")
	assert_eq(image.get_pixel(0, 16).a, 0.0, "the west rim runs up to the north rim")
	var below_rim := 0
	while below_rim < 31 and image.get_pixel(16, below_rim).a == 0.0:
		below_rim += 1
	assert_lt(below_rim, 12, "the face starts right under the rim")
	assert_gt(image.get_pixel(16, below_rim).a, 0.9, "opaque under the rim")
	assert_lt(image.get_pixel(16, 31).a, 0.1, "gone at the foot: no strip, no line, the abyss below goes on")
	assert_lt(image.get_pixel(16, below_rim).get_luminance(), face.get_pixel(16, below_rim).get_luminance(), "darker than the rock")
	assert_ne(piece.get_pixel(16, 2), Color(0, 0, 0, 0))
	room.free()


func test_abyss_edges_never_pinch_or_meet_a_front() -> void:
	var problems: Array[String] = []
	for entry in _entries:
		var room := entry.scene.instantiate() as RoomController
		for problem in RoomPlanChecks.abyss_problems(room.get_node("Tiles") as RoomTiles):
			problems.append("%s: %s" % [entry.id, problem])
		room.free()
	assert_eq(problems.slice(0, 20), [] as Array[String], "%d problems: %s" % [problems.size(), "; ".join(problems.slice(0, 6))])
	# The rule catches both cases on a made-up room.
	var tiles := RoomTiles.new()
	tiles.room_size = Vector2i(10, 8)
	tiles.pit_rects = [Rect2i(2, 2, 2, 2), Rect2i(4, 4, 2, 2)] as Array[Rect2i]
	tiles.wall_rects = [Rect2i(0, 5, 3, 2)] as Array[Rect2i]
	var found := "; ".join(RoomPlanChecks.abyss_problems(tiles))
	assert_string_contains(found, "touch only at a corner")
	tiles.pit_rects = [Rect2i(3, 5, 2, 2)] as Array[Rect2i]
	tiles.wall_rects = [Rect2i(0, 4, 3, 2)] as Array[Rect2i]
	found = "; ".join(RoomPlanChecks.abyss_problems(tiles))
	assert_string_contains(found, "wall front beside the abyss")
	tiles.free()


func _entry_of(id: String) -> RoomTemplate:
	for entry in _entries:
		if entry.id == id:
			return entry
	return null


func test_abyss_rim_corners_run_round() -> void:
	var tileset := (load(BASE_TILESET_PATH) as TileSet).duplicate() as TileSet
	assert_true(AbyssRims.ensure_source(tileset), "the round pieces are added")
	var art := (tileset.get_source(AbyssAutotile.ART_SOURCE_ID) as TileSetAtlasSource).texture.get_image()
	art.decompress()
	art.convert(Image.FORMAT_RGBA8)
	var void_tile := art.get_region(Rect2i(AbyssAutotile.ART_VOID[0] * 32, Vector2i(32, 32)))
	var top_left: Array = AbyssRims.CORNERS[0]
	var outer := AbyssRims.corner_patch(art, top_left, true)
	var inner := AbyssRims.corner_patch(art, top_left, false)
	var edge := art.get_region(Rect2i(AbyssAutotile.ART_EDGE[AbyssAutotile.N] * 32, Vector2i(32, 32)))
	assert_eq(outer.get_pixel(0, 0), edge.get_pixel(0, 0), "outer corner: rim right in the corner")
	assert_eq(outer.get_pixel(7, 7), void_tile.get_pixel(7, 7), "outer corner: void inside the ring")
	assert_eq(inner.get_pixel(0, 0), edge.get_pixel(0, 0), "inner corner: rim round the corner point")
	assert_eq(inner.get_pixel(7, 7), void_tile.get_pixel(7, 7), "inner corner: void away from it")
	# The pieces of a room come from the round set.
	var piece := AbyssRims.make_piece(art, AbyssAutotile.E | AbyssAutotile.S, 0)
	assert_eq(piece.get_pixel(0, 0), outer.get_pixel(0, 0))
	assert_eq(RoomTiles.SOURCE_ABYSS_PIECES, AbyssRims.SOURCE_ID)

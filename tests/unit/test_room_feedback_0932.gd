extends GutTest
## Bug reports 22.10.2026 09:32 (solo run, seed -4728548023312275300, shadow realm to ember forge):
##   - #8688874c, #04d852ea, #13907370, #1ba4ff36 ("falsche Biom-Textur"): the notch of a side gate in
##     the ember forge showed the first biome's notch (cache keyed by the TileSet, no RID; fixed with
##     #da48eb51): after other biomes the notch rows are the same pictures as in a fresh ember room;
##   - #7e751eb6 ("unsichtbare Mauer"): the band at the top of a free rock block is open at its ends;
##   - #21660828 ("man kann hier an der Kante hoch"): stairs and ladders are closed towards the
##     ground beside them (walls, navigation, reachability); nobody steps onto them from the side;
##   - plateau surfaces are cached per surface and surroundings, not per surface tiles alone;
##   - a room of a biome with its own tiles builds its height twice while it sets up: its plateau band
##     pieces reach the room once (a deferred add_child of freed pieces crashed the engine).

const SEELEN := "res://dungeon/rooms/combat/seelen_katakombe_ember_forge.tscn"
const ASCHEGRUBE := "res://dungeon/rooms/combat/aschegrube_ember_forge.tscn"
## Room indices of the biomes (RoomSequence.get_biome): crypt and ember forge.
const CRYPT_ROOM := 3
const EMBER_ROOM := 46

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_room_feedback_0932_save.cfg"


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func _context() -> DungeonContext:
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 932
	return context


func _room(path: String, index: int, entrance: Vector2i, exit: Vector2i, origin := Vector2i.ZERO) -> RoomController:
	var room := (load(path) as PackedScene).instantiate() as RoomController
	room.setup(index, RoomSequence.RoomType.COMBAT, -1, false, _context())
	room.apply_door_plan(entrance, [exit] as Array[Vector2i])
	room.position = Vector2(origin) * RoomTiles.TILE_WORLD
	add_child(room)
	return room


func _template(path: String, index: int) -> RoomController:
	var room := (load(path) as PackedScene).instantiate() as RoomController
	room.setup(index, RoomSequence.RoomType.COMBAT, -1, false, _context())
	add_child_autofree(room)
	return room


## Pictures of the notch rows of an east side gate between two rooms of the biome of index.
func _notch_images(index: int) -> Array[PackedByteArray]:
	var images: Array[PackedByteArray] = []
	var probe := (load(SEELEN) as PackedScene).instantiate() as RoomController
	var probe_tiles := probe.get_node("Tiles") as RoomTiles
	var size := probe_tiles.room_size
	var entrance_x := probe_tiles.entrance_x
	var exit_x := probe_tiles.exit_x
	var east := probe_tiles.get_door_slots(ExitRules.EAST)
	var west := probe_tiles.get_door_slots(ExitRules.WEST)
	probe.free()
	if east.is_empty() or west.is_empty():
		return images
	var first := _room(SEELEN, index, Vector2i(ExitRules.SOUTH, entrance_x), Vector2i(ExitRules.EAST, east[0]))
	var end := ExitRules.exit_corridor_end(Vector2i.ZERO, size, ExitRules.EAST, east[0])
	var second := _room(SEELEN, index + 1, Vector2i(ExitRules.WEST, west[0]), Vector2i(ExitRules.NORTH, exit_x), ExitRules.origin_for(end, size, ExitRules.WEST, west[0]))
	await wait_process_frames(2)
	PassageSeam.join(first, second)
	var gate := GateCloser.gate_between(first)
	gate.set_open_instant(true)
	gate.view.build_lintel([first, second] as Array[Node2D])
	var pieces: Array[Sprite2D] = []
	for piece in gate.view.get_lintel():
		if String(piece.name).begins_with("NotchRow"):
			pieces.append(piece)
	pieces.sort_custom(func(a: Sprite2D, b: Sprite2D) -> bool: return String(a.name) < String(b.name))
	for piece in pieces:
		images.append(piece.texture.get_image().get_data())
	first.queue_free()
	second.queue_free()
	await wait_process_frames(3)
	return images


func test_side_notch_shows_the_biome_of_its_room_after_other_biomes() -> void:
	DoorView._textures.clear()
	var fresh := await _notch_images(EMBER_ROOM)
	if fresh.is_empty():
		pending("no side gate or no terrain art in this build")
		return
	DoorView._textures.clear()
	var crypt := await _notch_images(CRYPT_ROOM)
	var after := await _notch_images(EMBER_ROOM)
	assert_ne(crypt, fresh, "crypt and ember forge notches differ")
	assert_eq(after.size(), fresh.size())
	assert_eq(after, fresh, "the ember notch after the crypt is the ember notch, not the cached crypt one")


func test_band_on_a_rock_block_is_open_at_its_ends() -> void:
	var room := _template(SEELEN, EMBER_ROOM)
	await wait_physics_frames(3)
	var tiles := room.tiles
	if not tiles.is_terrain_drawn():
		pending("no terrain art")
		return
	var floor_mask := tiles.get_floor_mask()
	# A plateau is no rock block (it has the HeightField's band, D-205; test_room_feedback_1022).
	var height := tiles.get_height_layout().get_height_tiles()
	var ends: Array[Vector2i] = []
	for y in tiles.room_size.y:
		for x in tiles.room_size.x:
			var tile := Vector2i(x, y)
			if not floor_mask.has(tile) and not height.has(tile) and RockTerrain.is_lip(tile, floor_mask) and floor_mask.has(tile + Vector2i.RIGHT):
				ends.append(tile)
	assert_false(ends.is_empty(), "the catacomb has free rock blocks")
	var space := room.get_world_2d().direct_space_state
	var unit := RoomTiles.TILE_WORLD
	var band := RockTerrain.LIP_WALK * SpriteStrip.PIXEL_SCALE
	for tile in ends:
		var top := Vector2(tile) * unit
		assert_false(_solid(space, room.to_global(top + Vector2(unit * 0.5, band * 0.5))), "%s: the band is walkable" % tile)
		assert_false(_solid(space, room.to_global(top + Vector2(unit * 0.98, band * 0.5))), "%s: no cap at the block's end" % tile)
		assert_true(_solid(space, room.to_global(top + Vector2(unit * 0.5, band + unit * 0.2))), "%s: the block below the band" % tile)


func test_stairs_are_closed_to_the_ground_beside_them() -> void:
	# Plateau rows 0-1, cliff row 2 with stairs at its east end, ground all around.
	var plateau: Array[Vector2i] = []
	for y in 3:
		for x in 4:
			plateau.append(Vector2i(x, y))
	var stairs: Array[Vector2i] = [Vector2i(3, 2)]
	plateau.erase(Vector2i(3, 2))
	var ground: Dictionary[Vector2i, bool] = {}
	for y in range(-1, 5):
		for x in range(-1, 6):
			ground[Vector2i(x, y)] = true
	var layout := HeightLayout.build(plateau, [] as Array[Vector2i], stairs, ground)
	assert_eq(layout.connector_sides.get(Vector2i(3, 2), 0), 2, "open ground east of the stairs")
	assert_false(layout.can_step(Vector2i(4, 2), Vector2i(3, 2)), "not onto the stairs from the side")
	assert_false(layout.can_step(Vector2i(3, 2), Vector2i(4, 2)), "not off the stairs to the side")
	assert_true(layout.can_step(Vector2i(3, 3), Vector2i(3, 2)), "up from the foot")
	assert_true(layout.can_step(Vector2i(3, 2), Vector2i(3, 1)), "on to the surface")
	var open: Dictionary[Vector2i, bool] = ground.duplicate()
	for tile: Vector2i in layout.surface:
		open[tile] = true
	open[Vector2i(3, 2)] = true
	var reached := HeightLayout.reachable(layout, open, Vector2i(5, 2))
	assert_true(reached.has(Vector2i(0, 0)), "the surface is still reached over the stairs")
	var unit := 32.0
	var found := false
	for rect in HeightField.wall_rects(layout, unit):
		if is_equal_approx(rect.get_center().x, 4.0 * unit) and rect.position.y <= 2.0 * unit and rect.end.y >= 2.0 * unit + HeightField.front_of(unit):
			found = true
	assert_true(found, "a wall on the stairs' east side along the whole (half-high, D-205) front")


func test_live_stairs_block_the_ground_beside_them() -> void:
	var room := _template(ASCHEGRUBE, 51)
	await wait_physics_frames(3)
	var tiles := room.tiles
	var layout := tiles.get_height_layout()
	if layout.connector_sides.is_empty() or not tiles.is_terrain_drawn():
		pending("no stairs beside the ground in this build")
		return
	var space := room.get_world_2d().direct_space_state
	var unit := float(tiles.tile_set.tile_size.x)
	for tile: Vector2i in layout.connector_sides:
		var sides: int = layout.connector_sides[tile]
		var x := float(tile.x + 1) if sides & 2 else float(tile.x)
		var point := tiles.to_global(Vector2(x * unit, float(tile.y) * unit + HeightField.front_of(unit) * 0.5))
		assert_true(_solid(space, point, PhysicsLayers.CLIFF), "%s: closed towards the ground beside it" % tile)
	# Enemies: the stairs' navigation keeps off that side.
	var inset := RoomTiles.inset_polygon(2, unit, HeightRules.NAV_INSET)
	var right := -INF
	for point in inset.vertices:
		right = maxf(right, point.x)
	assert_almost_eq(right, unit / 2.0 - HeightRules.NAV_INSET, 0.001)


func test_plateau_band_reaches_a_biome_room_once() -> void:
	var room := _template(SEELEN, EMBER_ROOM)
	await wait_process_frames(4)
	var tiles := room.tiles
	if not tiles.is_terrain_drawn() or not tiles.has_height():
		pending("no terrain art")
		return
	var bands := 0
	for child in room.get_children():
		if String(child.name).begins_with(HeightField.LIPS_NAME):
			bands += 1
	assert_eq(bands, 1, "one y-sorted plateau band in the room")
	assert_eq(tiles.get_height_field().get_lips().get_parent(), room)


func test_plateau_surface_cache_tells_surroundings_apart() -> void:
	var plateau: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	var stairs: Array[Vector2i] = [Vector2i(0, 2)]
	var cliff_row: Array[Vector2i] = [Vector2i(1, 2)]
	var open_north: Dictionary[Vector2i, bool] = {}
	var rock_north: Dictionary[Vector2i, bool] = {}
	for y in range(-1, 5):
		for x in range(-1, 3):
			open_north[Vector2i(x, y)] = true
			if y >= 0:
				rock_north[Vector2i(x, y)] = true
	var a := HeightLayout.build(plateau + cliff_row, [] as Array[Vector2i], stairs, open_north)
	var b := HeightLayout.build(plateau + cliff_row, [] as Array[Vector2i], stairs, rock_north)
	assert_eq(a.surface.keys().size(), b.surface.keys().size(), "the same surface tiles")
	var fill := Image.create_empty(PlateauArt.TILE, PlateauArt.TILE, false, Image.FORMAT_RGBA8)
	fill.fill(Color(0.5, 0.4, 0.3))
	var first: Dictionary = PlateauArt.surface_texture(a, fill, "test_0932")
	var second: Dictionary = PlateauArt.surface_texture(b, fill, "test_0932")
	assert_ne(first["texture"], second["texture"], "other surroundings, another picture")


func _solid(space: PhysicsDirectSpaceState2D, point: Vector2, mask := PhysicsLayers.WORLD) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = mask
	return not space.intersect_point(query).is_empty()

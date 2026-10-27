extends GutTest
## Bug reports 22.10.2026 (solo run, seed -4728548023312275300, crypt to shadow realm):
##   - #952d645f: an inner corner of a plateau gets its rim up to the top of the other part's cliff;
##   - #5724ea7c, #006de12a (D-206): no tunnel before the boss gate - nothing dark, nobody darkened,
##     its frame whole (since 23.10.2026 #876edf4a the crown runs closed over the passage with the
##     arch's opening cut out); a cut arch top is closed with the outline;
##   - #da48eb51, #09ae5f43, #d43c7121: the notch of a side gate is cached per sheet texture, not per
##     TileSet (no RID: every biome reused the first one); its closed share above the floor lies over
##     a player in the passage like the tunnel's rock (no head sticking out);
##   - #214a0ff5: the pendulum swings its hanging frame, the blade is never cut by the frame;
##   - #f5026f89: no secret niche in a plateau, its cliff, stairs or ladder;
##   - #35292dbf: no free-standing rock block glued to a plateau (plan rule, jagd_saeulenhalle);
##   - #25371167, #276ffad7: plateaus stand free and half high (D-205, CR6; test_height_half);
##   - #784047ba, #81959d11, #bbdc6153, #c1f94cec, #db6117ad: one rule for every raised mass - from the
##     north a figure walks a band into it and is drawn behind it (plateaus: HeightField band and
##     y-sorted surface, rock: lips), no invisible caps, fronts beside floor sort at their foot.

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const WAFFENKAMMER: PackedScene = preload("res://dungeon/rooms/rest/waffenkammer_crypt.tscn")
const BOSS_ROOM: PackedScene = preload("res://dungeon/rooms/boss/boss_room.tscn")
const WEICHE_HOEHLE := "res://dungeon/rooms/combat/weiche_hoehle_mirror_shadow_realm.tscn"
const RUNDHOEHLE := "res://dungeon/rooms/combat/rundhoehle_mirror_slime_grotto.tscn"
const JAGD := "res://dungeon/rooms/combat/jagd_saeulenhalle_shadow_realm.tscn"
const CRYPT_TILESET := "res://dungeon/environment/dungeon_tileset.tres"
const SLIME_TILESET := "res://dungeon/environment/slime_grotto_tileset.tres"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_room_feedback_1022_save.cfg"
	DoorArt.art_dir = DoorStyle.ART_DIR
	DoorArt.clear_cache()


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path
	DoorArt.clear_cache()


func _context() -> DungeonContext:
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 22
	return context


func _room(scene: PackedScene, index: int, entrance: Vector2i, exit: Vector2i, origin := Vector2i.ZERO, slot := -1) -> RoomController:
	var room := scene.instantiate() as RoomController
	room.setup(index, RoomSequence.RoomType.COMBAT, -1, false, _context())
	if slot > 0:
		room.slot_index = slot
	room.apply_door_plan(entrance, [exit] as Array[Vector2i])
	room.position = Vector2(origin) * RoomTiles.TILE_WORLD
	add_child_autofree(room)
	return room


func _template(path: String) -> RoomController:
	var room := (load(path) as PackedScene).instantiate() as RoomController
	room.setup(7, RoomSequence.RoomType.COMBAT, -1, false, _context())
	add_child_autofree(room)
	return room


## L-shaped plateau like halbmond_mirror: rows 0-1 wide, row 2 narrower; the cliff row of the narrow
## part is row 3, the wide part's ends have their cliffs in row 2.
func _l_layout() -> HeightLayout:
	var plateau: Array[Vector2i] = []
	for x in range(0, 7):
		plateau.append(Vector2i(x, 0))
		plateau.append(Vector2i(x, 1))
	for x in range(1, 6):
		plateau.append(Vector2i(x, 2))
	var ground: Dictionary[Vector2i, bool] = {}
	for y in range(-1, 5):
		for x in range(-1, 8):
			ground[Vector2i(x, y)] = true
	var stairs: Array[Vector2i] = [Vector2i(3, 2)]
	plateau.erase(Vector2i(3, 2))
	return HeightLayout.build(plateau, [] as Array[Vector2i], stairs, ground)


func test_inner_corner_of_a_plateau_has_its_rim() -> void:
	var layout := _l_layout()
	assert_true(layout.cliffs.has(Vector2i(6, 1)), "the end of the wide part drops in row 1")
	assert_true(layout.surface.has(Vector2i(5, 1)), "beside it the narrow part goes on")
	assert_true(PlateauArt.has_rim(layout, Vector2i(5, 1), Vector2i.RIGHT), "the edge runs up beside the other cliff")
	assert_true(PlateauArt.has_rim(layout, Vector2i(1, 1), Vector2i.LEFT))
	assert_false(PlateauArt.has_rim(layout, Vector2i(5, 1), Vector2i.DOWN), "its own cliff below continues the slab")
	assert_false(PlateauArt.has_rim(layout, Vector2i(5, 1), Vector2i.UP))
	var fill := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	fill.fill(Color(0.6, 0.4, 0.3))
	var surface := PlateauArt.surface_texture(layout, fill, "test_inner_corner")
	var image := (surface["texture"] as Texture2D).get_image()
	var origin: Vector2i = surface["origin"]
	var at := Vector2i(5, 1) * PlateauArt.TILE - origin
	var edge := image.get_pixel(at.x + PlateauArt.TILE - 1, at.y + 16)
	var inside := image.get_pixel(at.x + 16, at.y + 16)
	assert_ne(edge, inside, "the rim is drawn along the side towards the cliff")
	assert_eq(edge, PlateauArt.RIM_FALLBACK[0], "dark outline at the very edge")


func test_boss_gate_passage_is_no_tunnel() -> void:
	var probe := WAFFENKAMMER.instantiate() as RoomController
	var lower_tiles := probe.get_node("Tiles") as RoomTiles
	var lower_size := lower_tiles.room_size
	var lower_entrance := lower_tiles.entrance_x
	var exit_x := lower_tiles.exit_x
	probe.free()
	var boss_probe := BOSS_ROOM.instantiate() as RoomController
	var boss_tiles := boss_probe.get_node("Tiles") as RoomTiles
	var boss_size := boss_tiles.room_size
	var boss_entrance := boss_tiles.entrance_x
	var boss_exit := boss_tiles.exit_x
	boss_probe.free()
	# Slot 14: the next slot is the boss (RoomSequence), the exit is the boss gate.
	var lower := _room(WAFFENKAMMER, 14, Vector2i(ExitRules.SOUTH, lower_entrance), Vector2i(ExitRules.NORTH, exit_x), Vector2i.ZERO, 14)
	var end := ExitRules.exit_corridor_end(Vector2i.ZERO, lower_size, ExitRules.NORTH, exit_x)
	var upper := _room(BOSS_ROOM, 15, Vector2i(ExitRules.SOUTH, boss_entrance), Vector2i(ExitRules.NORTH, boss_exit), ExitRules.origin_for(end, boss_size, ExitRules.SOUTH, boss_entrance), 15)
	await wait_process_frames(2)
	PassageSeam.join(lower, upper)
	var gate := GateCloser.gate_between(lower)
	assert_not_null(gate)
	if gate == null:
		return
	assert_true(gate.get_style().is_boss(), "the exit before the boss is the boss gate")
	DoorSigns.show_way(gate, upper)
	# D-206: no tunnel before the boss - no dark in the arch, nobody darkened. Since bug report
	# 23.10.2026 #876edf4a the crown runs closed over the passage with the arch's opening cut out
	# (test_room_feedback_1023).
	var view := gate.view
	assert_false(view.is_tunnel(), "the boss gate's passage is no tunnel")
	assert_true(view.get_lintel().is_empty(), "no arch view over the passage")
	for extra in [^"ShadeTop", ^"TunnelFade", ^"ShadeFloor"]:
		assert_null(view.get_node_or_null(extra), "%s: nothing dark over the passage" % extra)
	var rects := view.get_passage_rects()
	assert_gt(rects.size(), 1, "the passage reaches the boss room")
	for rect in rects:
		assert_false(DoorView.is_in_tunnel(get_tree(), gate.to_global(rect.get_center())), "a player at %s is not darkened" % rect.position)
	var walls := view.get_passage_walls()
	if lower.tiles.is_terrain_drawn():
		assert_eq(walls.size(), 2 * (rects.size() - 1), "rock beside every passage tile")
		assert_eq(view.get_passage_roof().size(), rects.size() - 1, "and over it")
	# The delivered arch is cut at its top: the outline closes it.
	var image := Image.create_empty(8, 4, false, Image.FORMAT_RGBA8)
	image.set_pixel(3, 0, Color(0.6, 0.58, 0.7))
	image.set_pixel(4, 0, DoorArt.OUTLINE)
	assert_eq(DoorArt.close_cut_top(image), 1)
	assert_eq(image.get_pixel(3, 0), DoorArt.OUTLINE)
	var block := Image.create_empty(8, 4, false, Image.FORMAT_RGBA8)
	block.fill(Color(0.6, 0.58, 0.7))
	assert_eq(DoorArt.close_cut_top(block), 0, "a rock-block picture stays")


func test_notch_cache_key_follows_the_biome_sheet() -> void:
	var view: DoorView = autofree(DoorView.new())
	var keys: Array[String] = []
	for path in [CRYPT_TILESET, SLIME_TILESET]:
		var room: Node2D = autofree(Node2D.new())
		var tiles: RoomTiles = RoomTiles.new()
		tiles.name = "Tiles"
		tiles.tile_set = load(path)
		room.add_child(tiles)
		keys.append(view._entry_key({"room": room, "atlas": Vector3i(0, 0, RoomTiles.SOURCE_ID)}))
	assert_ne(keys[0], keys[1], "crypt and slime grotto notches are cached apart")
	assert_false(keys[0].begins_with("0:"), "keyed by a real texture")


func test_notch_rock_above_the_floor_covers_a_player_deeper_in() -> void:
	var probe := HALL.instantiate() as RoomController
	var probe_tiles := probe.get_node("Tiles") as RoomTiles
	var size := probe_tiles.room_size
	var entrance_x := probe_tiles.entrance_x
	var exit_x := probe_tiles.exit_x
	var slots := probe_tiles.get_door_slots(ExitRules.EAST)
	var west_slots := probe_tiles.get_door_slots(ExitRules.WEST)
	probe.free()
	if slots.is_empty() or west_slots.is_empty():
		pass_test("the hall has no side doors")
		return
	var first := _room(HALL, 3, Vector2i(ExitRules.SOUTH, entrance_x), Vector2i(ExitRules.EAST, slots[0]))
	var end := ExitRules.exit_corridor_end(Vector2i.ZERO, size, ExitRules.EAST, slots[0])
	var second := _room(HALL, 4, Vector2i(ExitRules.WEST, west_slots[0]), Vector2i(ExitRules.NORTH, exit_x), ExitRules.origin_for(end, size, ExitRules.WEST, west_slots[0]))
	await wait_process_frames(2)
	PassageSeam.join(first, second)
	var gate := GateCloser.gate_between(first)
	gate.set_open_instant(true)
	gate.view.build_lintel([first, second] as Array[Node2D])
	var view := gate.view
	if view.get_lintel().is_empty():
		pass_test("no terrain tiles in this build")
		return
	var open_pieces := 0
	var closed_pieces := 0
	for piece in view.get_lintel():
		if not String(piece.name).begins_with("NotchRow") or piece.position.y >= 0.0:
			continue
		if String(piece.name).ends_with("Closed"):
			closed_pieces += 1
			assert_true(bool(piece.get_meta(&"over_player")), "%s: the tunnel's rock" % piece.name)
			# East wall: the closed share is the outer (right) side of the door tile.
			assert_gt(piece.position.x, 0.0, "%s on the outer side" % piece.name)
		else:
			open_pieces += 1
			assert_false(bool(piece.get_meta(&"over_player")), "%s: the notch's front stays behind" % piece.name)
	assert_gt(closed_pieces, 0)
	assert_gt(open_pieces, 0)
	# A player deeper in the passage: the closed share above the floor lies over him.
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.global_position = gate.to_global(Vector2(RoomTiles.TILE_WORLD * 1.4, 32)) - Player.FEET_OFFSET
	await wait_process_frames(10)
	for piece in view.get_lintel():
		if String(piece.name).ends_with("Closed"):
			assert_eq(piece.z_index, DoorView.LINTEL_Z, "%s over the player" % piece.name)


func test_pendulum_swings_its_hanging_frame() -> void:
	var pendulum: TrialPendulum = autofree(TrialPendulum.new())
	pendulum.build(TrialLayout.column_rect(TrialLayout.LANE_A, 9))
	var arm := pendulum.get_node("Arm") as Node2D
	var sprite := arm.get_child(0) as Sprite2D
	var limit := deg_to_rad(TrialPendulum.SWING_DEGREES) + 0.001
	for i in 90:
		pendulum.advance(1.0 / 30.0)
		assert_eq(sprite.frame, TrialPendulum.HANG_FRAME, "always the whole blade")
		assert_lte(absf(arm.rotation), limit)
		assert_almost_eq(arm.rotation, deg_to_rad(TrialPendulum.SWING_DEGREES) * pendulum.get_swing(), 0.001)
	# The arm turns round the chain's anchor; the frame's foot stays on the lane's south edge.
	var foot := arm.position + sprite.position
	assert_almost_eq(foot.length(), 0.0, 0.01)


func test_no_secret_niche_in_a_plateau() -> void:
	var room := _template(WEICHE_HOEHLE)
	await wait_process_frames(2)
	var tiles := room.tiles
	var height: Dictionary[Vector2i, bool] = {}
	for list: Array[Vector2i] in [tiles.plateau_tiles, tiles.ladder_tiles, tiles.stair_tiles]:
		for tile in list:
			height[tile] = true
	assert_false(height.is_empty(), "the cave has its two plateaus")
	for site in SecretRules.find_sites(tiles, {}):
		for tile in site.niche + site.opening + site.get_enclosure():
			assert_false(height.has(tile), "niche at %s reaches into the height at %s" % [site.crack, tile])


func test_no_rock_block_glued_to_a_plateau() -> void:
	var room := _template(JAGD)
	await wait_process_frames(2)
	var tiles := room.tiles
	var layout := tiles.get_height_layout()
	var floor_mask := tiles.get_floor_mask()
	for tile: Vector2i in layout.plateau:
		for side: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT]:
			var other := tile + side
			if layout.plateau.has(other) or layout.is_connector(other):
				continue
			assert_true(floor_mask.has(other) or not Rect2i(Vector2i.ZERO, tiles.room_size).has_point(other), "%s beside the plateau is floor" % other)


func test_plateau_stands_free_instead_of_half_a_wall() -> void:
	# D-205 (CR6) replaces the half wall face of D-201 point 4: the plateau is half high and keeps a
	# tile of floor to the rock, so nothing rises above it any more.
	var room := _template(RUNDHOEHLE)
	await wait_process_frames(2)
	var tiles := room.tiles
	var layout := tiles.get_height_layout()
	assert_true(PlateauArt.walled_tiles(layout).is_empty(), "the gallery no longer runs against the north wall")
	for tile: Vector2i in layout.get_height_tiles():
		assert_eq(layout.rock_beside(tile), tile, "%s: floor all round" % tile)
	var field := tiles.get_height_field()
	if field == null:
		pending("no terrain art")
		return
	for child in field.get_children():
		assert_false(String(child.name).begins_with("WallFace"), "no half wall face any more")


func test_ground_walks_into_the_band_behind_a_plateau() -> void:
	var room := _template(JAGD)
	await wait_process_frames(3)
	var tiles := room.tiles
	var layout := tiles.get_height_layout()
	var north: Array[Vector2i] = []
	for tile: Vector2i in layout.edge_sides:
		if int(layout.edge_sides[tile]) & 1:
			north.append(tile)
	north.sort()
	assert_false(north.is_empty(), "the gallery has a north edge to the ground")
	var tile := north[north.size() / 2]
	var unit := float(tiles.tile_set.tile_size.x)
	var band := HeightField.band_of(unit)
	assert_gt(band, 0.0)
	var walls := HeightField.wall_rects(layout, unit)
	var found := false
	for rect in walls:
		if is_equal_approx(rect.position.y + rect.size.y * 0.5, float(tile.y) * unit + band) and rect.position.x == float(tile.x) * unit:
			found = true
	assert_true(found, "the north edge wall of %s lies band_of() into the tile" % tile)
	var in_band := tiles.to_global(Vector2(float(tile.x) + 0.5, float(tile.y)) * unit + Vector2(0.0, band * 0.5))
	var below := tiles.to_global((Vector2(tile) + Vector2(0.5, 0.75)) * unit)
	assert_eq(HeightRules.level_at(in_band), HeightRules.GROUND, "in the band: on the ground")
	assert_eq(HeightRules.level_at(below), HeightRules.PLATEAU)
	# The band again in the room's y-sort, sorted at its line.
	var lips := tiles.get_height_field().get_lips()
	assert_not_null(lips)
	if lips == null:
		return
	assert_eq(lips.get_parent(), room, "sorted with the room's figures")
	assert_true(lips.y_sort_enabled)
	assert_eq(lips.get_child_count(), north.size(), "one band piece per north edge")
	for piece: Sprite2D in lips.get_children():
		assert_almost_eq(piece.region_rect.size.y, HeightField.BAND, 0.01, "only the band: flat things on the plateau stay seen")
	var band_line := tiles.to_global(Vector2(0.0, float(tile.y) * unit + band)).y - room.global_position.y
	var sorted_at := false
	for piece: Sprite2D in lips.get_children():
		if is_equal_approx(piece.position.y, band_line - HeightField.SORT_FEET):
			sorted_at = true
	assert_true(sorted_at, "a piece sorts at the band line of the north edge")
	# Every navigation polygon of a north edge tile keeps off the band.
	var inset := RoomTiles.inset_polygon(1, unit, HeightRules.NAV_INSET, band)
	var top := INF
	for point in inset.vertices:
		top = minf(top, point.y)
	assert_almost_eq(top, -unit / 2.0 + HeightRules.NAV_INSET + band, 0.001)


func test_fronts_beside_floor_sort_at_their_foot() -> void:
	var room := _template(JAGD)
	await wait_process_frames(3)
	var tiles := room.tiles
	if not tiles.is_terrain_drawn():
		pending("no terrain art")
		return
	var fronts := tiles.sorted_front_lips(tiles.get_floor_mask())
	assert_false(fronts.is_empty(), "the pillar's face has floor beside it")
	for front in fronts:
		assert_false(tiles.front_fixtures.has(front), "%s: no fixture covered" % front)
	assert_false(RockTerrain.LIP_CAPS, "the band behind a block is open at its ends")
	assert_eq(RockTerrain.lip_caps(fronts[0] + Vector2i.UP, tiles.get_floor_mask()), 0)

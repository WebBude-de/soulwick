extends GutTest
## Bug reports 23.10.2026 (solo runs in the crypt and the slime grotto, seeds 6935191255933611860 and
## 8900120934407522844):
##   - #302ea822 (halbmond_crypt): where a plateau reaches one row further south, its surface beside
##     the shorter column's cliff is closed (HeightLayout.foot_sides) - nobody walks up from the side;
##   - #08fe4567, #019f28b3 (saeulenhalle, weiche_hoehle): a figure walking north comes
##     RockTerrain.FRONT_REACH closer to an upper edge - the foot of a rock front or a cliff and,
##     on a plateau, its north edge (one-way walls: from the north the band stays as it was);
##   - #0bfc40e0: the tunnel rock of a side passage always lies over every figure (Flint included);
##   - #c17c0ed8: the dark of a side notch runs evenly along its whole edge, lighter;
##   - #876edf4a: the crown runs closed over the boss gate's passage, the arch's opening cut out;
##   - #b28a0f5e: the soul gate of the campfire stands free of the walls, with a shadow and its light
##     on the floor;
##   - #9a693e5f: a decoration group leaves a gap between its standing parts open.

const HALBMOND := "res://dungeon/rooms/combat/halbmond_crypt.tscn"
const SAEULENHALLE := "res://dungeon/rooms/combat/saeulenhalle_crypt.tscn"
const WEICHE_HOEHLE := "res://dungeon/rooms/combat/weiche_hoehle_crypt.tscn"
const RIFTS := "res://dungeon/rooms/combat/risse_schlucht_slime_grotto.tscn"
const CAMPFIRE := "res://dungeon/rooms/campfire/campfire_room.tscn"
const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const BRUNNENGROTTE: PackedScene = preload("res://dungeon/rooms/rest/brunnengrotte_crypt.tscn")
const BOSS_ROOM: PackedScene = preload("res://dungeon/rooms/boss/boss_room.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_room_feedback_1023_save.cfg"
	DoorArt.art_dir = DoorStyle.ART_DIR
	DoorArt.clear_cache()


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path
	DoorArt.clear_cache()


func after_each() -> void:
	HitStop.reset()
	await wait_process_frames(1)


func _context() -> DungeonContext:
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 23
	return context


func _template(path: String, type := RoomSequence.RoomType.COMBAT, portal := false) -> RoomController:
	var room := (load(path) as PackedScene).instantiate() as RoomController
	room.setup(7, type, -1, portal, _context())
	add_child_autofree(room)
	return room


func _player_at_feet(feet: Vector2) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.global_position = feet - Player.FEET_OFFSET
	return player


## Global point of a layer point given in tiles of the room's layer.
func _at(tiles: RoomTiles, tile_point: Vector2) -> Vector2:
	return tiles.to_global(tile_point * Vector2(tiles.tile_set.tile_size))


## Does the player hit something when he moves by motion from where he stands?
func _blocked(player: Player, motion: Vector2) -> bool:
	return player.test_move(player.global_transform, motion)


# --- #302ea822 ---

func test_the_surface_beside_a_shorter_cliff_is_closed() -> void:
	var room := _template(HALBMOND)
	await wait_physics_frames(3)
	var tiles := room.tiles
	var layout := tiles.get_height_layout()
	# Column 7 has its cliff in row 4, column 8 reaches row 5: (8, 4) is surface beside that cliff.
	assert_true(layout.cliffs.has(Vector2i(7, 4)) and layout.surface.has(Vector2i(8, 4)), "the plan still has the step")
	assert_eq(int(layout.foot_sides.get(Vector2i(8, 4), 0)) & 8, 8, "its west side is an edge")
	assert_eq(int(layout.foot_sides.get(Vector2i(12, 4), 0)) & 2, 2, "the same at the other end")
	# On the ground in front of the shorter cliff, walking east: a wall, not the surface.
	var player := _player_at_feet(_at(tiles, Vector2(7.6, 4.8)))
	await wait_physics_frames(3)
	assert_eq(HeightRules.level_of(player), HeightRules.GROUND)
	assert_true(_blocked(player, Vector2(24, 0)), "nobody walks onto the plateau from the side")
	assert_false(_blocked(player, Vector2(0, 16)), "the ground in front of the cliff stays open")


# --- #08fe4567 ---

func test_a_figure_comes_closer_to_the_foot_of_a_rock_front() -> void:
	assert_eq(RockTerrain.FRONT_REACH, 4, "TESTWERT: 4 art px")
	var front := RockTerrain.solid_polygon(0, false, true)
	var bottom := -INF
	for point in front:
		bottom = maxf(bottom, point.y)
	assert_almost_eq(bottom, RockTerrain.TILE * 0.5 - RockTerrain.FRONT_REACH, 0.01, "the collision ends above the foot line")
	assert_true(RockTerrain.is_solid_cell(RockTerrain.SOURCE_GROUND, RockTerrain.solid_coords(3, true, 2, true)))
	assert_true(RockTerrain.is_lip_coords(RockTerrain.solid_coords(0, true, 0, true)))
	assert_false(RockTerrain.is_front_coords(RockTerrain.solid_coords(0, true, 0, false)))
	var room := _template(SAEULENHALLE)
	await wait_physics_frames(3)
	var tiles := room.tiles
	if not tiles.is_terrain_drawn():
		pass_test("no terrain tiles in this build")
		return
	# A pillar's front row: rock with floor right below it.
	var floor_mask := tiles.get_floor_mask()
	var pillar := Vector2i(-1, -1)
	for y in tiles.room_size.y:
		for x in tiles.room_size.x:
			var tile := Vector2i(x, y)
			if not floor_mask.has(tile) and floor_mask.has(tile + Vector2i.DOWN) and floor_mask.has(tile + Vector2i.UP + Vector2i.UP + Vector2i.UP):
				pillar = tile
				break
		if pillar.x >= 0:
			break
	assert_ne(pillar, Vector2i(-1, -1), "a free-standing pillar")
	assert_true(RockTerrain.is_front_coords(tiles.get_cell_atlas_coords(pillar)), "its front tile has the shorter collision")
	var foot_line := _at(tiles, Vector2(pillar) + Vector2(0.5, 1.0)).y
	var unit_scale := tiles.global_scale.y
	var player := _player_at_feet(Vector2(_at(tiles, Vector2(pillar) + Vector2(0.5, 1.0)).x, foot_line + 12.0))
	await wait_physics_frames(3)
	# The body circle sits 17 px above the feet: before, it touched the rock 17 px below the foot line.
	assert_false(_blocked(player, Vector2(0, -0.5)), "12 px below the foot line he still stands free")
	assert_true(_blocked(player, Vector2(0, -RockTerrain.FRONT_REACH * unit_scale)), "a few px further the front stops him")


# --- #019f28b3 ---

func test_on_a_plateau_a_figure_walks_closer_to_its_north_edge() -> void:
	var room := _template(WEICHE_HOEHLE)
	await wait_physics_frames(3)
	var tiles := room.tiles
	var layout := tiles.get_height_layout()
	var north: Array[Vector2i] = []
	for tile: Vector2i in layout.edge_sides:
		if int(layout.edge_sides[tile]) & 1 and not layout.foot_sides.has(tile):
			north.append(tile)
	north.sort()
	assert_gt(north.size(), 1)
	var tile := north[north.size() / 2]
	var one_way: Array[int] = []
	var rects := HeightField.wall_rects(layout, float(tiles.tile_set.tile_size.x), one_way)
	assert_eq(one_way.size(), rects.size())
	assert_true(one_way.has(HeightBody.ONE_WAY_FROM_NORTH) and one_way.has(HeightBody.ONE_WAY_FROM_SOUTH), "two one-way walls at a north edge")
	var art := tiles.global_scale.y
	var top := _at(tiles, Vector2(tile)).y
	var x := _at(tiles, Vector2(tile) + Vector2(0.5, 0.0)).x
	# On the plateau: before, his feet stopped 35 px below the edge's tile top (band 16 + wall + body).
	var player := _player_at_feet(Vector2(x, top + 30.0))
	await wait_physics_frames(3)
	assert_eq(HeightRules.level_of(player), HeightRules.PLATEAU)
	assert_false(_blocked(player, Vector2(0, -2.0)), "on the plateau he walks on towards the edge")
	assert_true(_blocked(player, Vector2(0, -(RockTerrain.FRONT_REACH + 2) * art)), "and stops before it")
	# On the ground behind it: the band is as deep as before (HeightField.BAND), the wall of the
	# plateau side does not stop him.
	player.global_position = Vector2(x, top - 24.0) - Player.FEET_OFFSET
	await wait_physics_frames(3)
	assert_eq(HeightRules.level_of(player), HeightRules.GROUND)
	assert_false(_blocked(player, Vector2(0, 24.0 + HeightField.BAND * art - 4.0)), "from the north he walks into the band")
	assert_true(_blocked(player, Vector2(0, 24.0 + HeightField.BAND * art + 2.0)), "the band line stops him")
	assert_false(_blocked(player, Vector2(0, -8.0)), "and he walks back north")


# --- #0bfc40e0, #c17c0ed8 ---

func _hall(index: int, origin: Vector2i, entrance: Vector2i, exit: Vector2i) -> RoomController:
	var room := HALL.instantiate() as RoomController
	room.setup(index, RoomSequence.RoomType.COMBAT, -1, false, _context())
	room.apply_door_plan(entrance, [exit] as Array[Vector2i])
	room.position = Vector2(origin) * RoomTiles.TILE_WORLD
	add_child_autofree(room)
	return room


func _side_passage() -> Door:
	var probe := HALL.instantiate() as RoomController
	var probe_tiles := probe.get_node("Tiles") as RoomTiles
	var size := probe_tiles.room_size
	var entrance_x := probe_tiles.entrance_x
	var exit_x := probe_tiles.exit_x
	var slots := probe_tiles.get_door_slots(ExitRules.EAST)
	var west_slots := probe_tiles.get_door_slots(ExitRules.WEST)
	probe.free()
	if slots.is_empty() or west_slots.is_empty():
		return null
	var first := _hall(3, Vector2i.ZERO, Vector2i(ExitRules.SOUTH, entrance_x), Vector2i(ExitRules.EAST, slots[0]))
	var end := ExitRules.exit_corridor_end(Vector2i.ZERO, size, ExitRules.EAST, slots[0])
	var second := _hall(4, ExitRules.origin_for(end, size, ExitRules.WEST, west_slots[0]), Vector2i(ExitRules.WEST, west_slots[0]), Vector2i(ExitRules.NORTH, exit_x))
	PassageSeam.join(first, second)
	var gate := GateCloser.gate_between(first)
	gate.set_open_instant(true)
	gate.view.build_lintel([first, second] as Array[Node2D])
	return gate


func test_the_tunnel_rock_always_lies_over_every_figure() -> void:
	var gate := _side_passage()
	if gate == null or gate.view.get_lintel().is_empty():
		pass_test("no side passage with terrain in this build")
		return
	await wait_process_frames(5)
	var view := gate.view
	var over := 0
	for piece in view.get_lintel():
		var expected := DoorView.LINTEL_Z if bool(piece.get_meta(&"over_player", false)) else DoorView.SIDE_COVER_LOW_Z
		assert_eq(piece.z_index, expected, "%s with nobody in the passage" % piece.name)
		if piece.z_index == DoorView.LINTEL_Z:
			over += 1
			# Flint and every figure draw at z 0 or below (D-211: SORT_LIFT only changes the y-sort).
			assert_gt(_absolute_z(piece), 0, "%s above the figures" % piece.name)
			var centre := piece.to_global(piece.get_rect().get_center())
			assert_true(DoorView.is_under_rock(get_tree(), centre), "%s: the hook knows its rock" % piece.name)
	assert_gt(over, 2, "the tunnel's rock")
	# Somebody walks in and out again: nothing changes.
	var player := _player_at_feet(gate.to_global(Vector2(24, 32)))
	await wait_process_frames(10)
	player.global_position = gate.to_global(Vector2(-96, 32)) - Player.FEET_OFFSET
	await wait_process_frames(10)
	for piece in view.get_lintel():
		if bool(piece.get_meta(&"over_player", false)):
			assert_eq(piece.z_index, DoorView.LINTEL_Z, "%s stays over the figures" % piece.name)
	assert_false(DoorView.is_under_rock(get_tree(), gate.to_global(Vector2(-96, 32))), "the room floor is no rock")


func _absolute_z(item: CanvasItem) -> int:
	var z := 0
	var node: Node = item
	while node is CanvasItem:
		z += (node as CanvasItem).z_index
		if not (node as CanvasItem).z_as_relative:
			break
		node = node.get_parent()
	return z


func test_the_dark_of_a_side_notch_runs_evenly_along_its_edge() -> void:
	var notch := DoorArt.side_notch_image()
	var height := notch.get_height()
	assert_eq(height, 32 + DoorArt.NOTCH_RISE, "over the whole front above the door tile")
	assert_eq(DoorArt.NOTCH_RISE, 32)
	var back := notch.get_pixel(31, height / 2).a
	assert_lt(back, 0.6, "not too dark")
	assert_gt(back, 0.4, "still a shadow")
	for y in range(DoorArt.NOTCH_FADE_ENDS, height - DoorArt.NOTCH_FADE_ENDS):
		assert_almost_eq(notch.get_pixel(31, y).a, back, 0.01, "the same along the edge (row %d)" % y)
	assert_lt(notch.get_pixel(31, 0).a, back * 0.5, "a soft top, no hard line")
	assert_almost_eq(notch.get_pixel(0, height / 2).a, 0.0, 0.01, "clear at the mouth")


# --- #876edf4a ---

func test_the_crown_runs_closed_over_the_boss_gate_with_the_arch_cut_out() -> void:
	var probe := BRUNNENGROTTE.instantiate() as RoomController
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
	var lower := BRUNNENGROTTE.instantiate() as RoomController
	lower.setup(14, RoomSequence.RoomType.SPECIAL, RoomSequence.SpecialType.FOUNTAIN, false, _context())
	lower.slot_index = 14
	lower.apply_door_plan(Vector2i(ExitRules.SOUTH, lower_entrance), [Vector2i(ExitRules.NORTH, exit_x)] as Array[Vector2i])
	add_child_autofree(lower)
	var end := ExitRules.exit_corridor_end(Vector2i.ZERO, lower_size, ExitRules.NORTH, exit_x)
	var upper := BOSS_ROOM.instantiate() as RoomController
	upper.setup(15, RoomSequence.RoomType.BOSS, -1, false, _context())
	upper.slot_index = 15
	upper.apply_door_plan(Vector2i(ExitRules.SOUTH, boss_entrance), [Vector2i(ExitRules.NORTH, boss_exit)] as Array[Vector2i])
	upper.position = Vector2(ExitRules.origin_for(end, boss_size, ExitRules.SOUTH, boss_entrance)) * RoomTiles.TILE_WORLD
	add_child_autofree(upper)
	await wait_process_frames(2)
	PassageSeam.join(lower, upper)
	var gate := GateCloser.gate_between(lower)
	assert_true(gate != null and gate.get_style().is_boss(), "the exit before the boss is the boss gate")
	if gate == null:
		return
	gate.set_open_instant(true)
	gate.view.build_lintel([lower, upper] as Array[Node2D])
	var view := gate.view
	assert_false(view.is_tunnel(), "no tunnel: nobody darkened")
	assert_true(view.get_lintel().is_empty(), "no arch view, no dark")
	for extra in [^"ShadeTop", ^"TunnelFade", ^"ShadeFloor"]:
		assert_null(view.get_node_or_null(extra), "%s: nothing dark over the passage" % extra)
	if not lower.tiles.is_terrain_drawn():
		pass_test("no terrain tiles in this build")
		return
	var roof := view.get_passage_roof()
	assert_eq(roof.size(), view.get_passage_rects().size() - 1, "a roof piece over every passage tile")
	assert_eq(view.get_passage_walls().size(), 2 * roof.size(), "the crown beside it")
	var cut := 0
	for piece in roof:
		assert_eq(piece.z_index, DoorView.LINTEL_Z, "%s over the figures" % piece.name)
		if not piece.region_enabled:
			cut += 1
	assert_gt(cut, 0, "the arch's opening is cut out of the roof")
	var top := view.get_node_or_null(^"FrameTop") as Sprite2D
	assert_not_null(top, "the top of the arch stands in front of the crown")
	if top != null:
		assert_gt(top.z_index, DoorView.LINTEL_Z)
	assert_true(DoorView.is_under_rock(get_tree(), gate.to_global(Vector2(-40, -32))), "the crown beside the way is rock over the figures")


# --- #b28a0f5e ---

func test_the_campfire_soul_gate_stands_free_on_the_floor() -> void:
	var room := _template(CAMPFIRE, RoomSequence.RoomType.CAMPFIRE, true)
	await wait_process_frames(3)
	var tiles := room.tiles
	var anchor := room.get_node("PortalAnchor") as Node2D
	var tile := tiles.local_to_map(tiles.to_local(anchor.global_position))
	var floor_mask := tiles.get_floor_mask()
	for dy in range(-2, 1):
		for dx in range(-1, 2):
			assert_true(floor_mask.has(tile + Vector2i(dx, dy)), "floor at %s around and above the gate" % (tile + Vector2i(dx, dy)))
	var gate := SoulGate.find_in(room)
	assert_not_null(gate, "the campfire has its gate")
	if gate == null:
		return
	var shadow := gate.get_node_or_null(^"DropShadow") as DropShadow
	assert_not_null(shadow, "a shadow at its foot")
	if shadow != null:
		assert_almost_eq(shadow.radius, SoulGate.SHADOW_HALF_WIDTH, 0.01)
	var glow := gate.get_node_or_null(^"FloorGlow") as Sprite2D
	if ResourceLoader.exists(DoorView.CONE_PATH):
		assert_not_null(glow, "its light on the floor")
		if glow != null:
			assert_lt(glow.z_index, 0, "under the figures")


# --- #9a693e5f ---

func test_a_decoration_group_leaves_its_gap_open() -> void:
	var parts := DecoProp.solid_parts(Vector2(-84, 86), PackedVector2Array([Vector2(8, 60)]))
	assert_eq(parts, [Vector2(-84, 8), Vector2(60, 86)] as Array[Vector2])
	assert_eq(DecoProp.solid_parts(Vector2(-84, 86), PackedVector2Array()), [Vector2(-84, 86)] as Array[Vector2])
	var room := _template(RIFTS)
	await wait_physics_frames(3)
	var group := room.get_node("Props/Group1") as DecoProp
	assert_eq(group.item, &"group_large_1")
	assert_false(group.solid_gaps.is_empty(), "the gap between the mushrooms and the stone is measured")
	var body := group.get_node("Body") as StaticBody2D
	assert_eq(body.get_child_count(), group.solid_gaps.size() + 1, "one shape per standing part")
	# A player walks through the gap from the north.
	var gap := group.solid_gaps[0]
	var middle := (gap.x + gap.y) * 0.5 * (-1.0 if group.flip else 1.0)
	var player := _player_at_feet(group.global_position + Vector2(middle, -40.0))
	await wait_physics_frames(3)
	assert_false(_blocked(player, Vector2(0, 80)), "through the gap")
	var stone := (gap.y + 20.0) * (-1.0 if group.flip else 1.0)
	player.global_position = group.global_position + Vector2(stone, -40.0) - Player.FEET_OFFSET
	await wait_physics_frames(3)
	assert_true(_blocked(player, Vector2(0, 80)), "the stone beside it stays solid")


# --- Navigation of a room painted while hidden (enemies-dev report 23.10.2026, #03d88a6b) ---

func test_a_room_painted_hidden_builds_its_navigation_once_it_shows() -> void:
	var room := (load(HALBMOND) as PackedScene).instantiate() as RoomController
	room.setup(7, RoomSequence.RoomType.COMBAT, -1, false, _context())
	var tiles := room.get_node(^"Tiles") as RoomTiles
	tiles.hold_paint()
	add_child_autofree(room)
	room.visible = false
	await wait_process_frames(1)
	tiles.release_paint()
	await wait_physics_frames(3)
	room.visible = true
	await wait_physics_frames(12)
	var layout := tiles.get_height_layout()
	var east := Vector2i(-1, -1)
	for tile: Vector2i in layout.edge_sides:
		if int(layout.edge_sides[tile]) & 2:
			east = tile
			break
	assert_ne(east, Vector2i(-1, -1), "a surface tile with an edge to the ground in the east")
	var on_plateau := _at(tiles, Vector2(east) + Vector2(0.85, 0.7))
	var beside := _at(tiles, Vector2(east) + Vector2(1.15, 0.7))
	var path := NavigationServer2D.map_get_path(tiles.get_navigation_map(), beside, on_plateau, true)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	assert_gt(length, 3.0 * RoomTiles.TILE_WORLD, "from the ground beside the edge only over the stairs (%.0f px)" % length)


# --- #a831f005 (trial room, 23.10.2026 04:31) ---

func test_opening_the_trial_shortcut_keeps_the_seam_to_the_next_room() -> void:
	var trial_scene := load("res://dungeon/rooms/trials/trial_room.tscn") as PackedScene
	var next_scene := load("res://dungeon/rooms/boss/miniboss_room.tscn") as PackedScene
	var probe := next_scene.instantiate() as RoomController
	var next_size := (probe.get_node("Tiles") as RoomTiles).room_size
	var next_entrance := (probe.get_node("Tiles") as RoomTiles).entrance_x
	var next_exit := (probe.get_node("Tiles") as RoomTiles).exit_x
	probe.free()
	var trial := trial_scene.instantiate() as RoomController
	trial.setup(9, RoomSequence.RoomType.SPECIAL, SpecialTable.TRIAL, false, _context())
	trial.slot_index = 9
	trial.apply_door_plan(Vector2i(ExitRules.SOUTH, TrialLayout.ENTRANCE_X), [Vector2i(ExitRules.NORTH, TrialLayout.EXIT_X)] as Array[Vector2i])
	add_child_autofree(trial)
	var end := ExitRules.exit_corridor_end(Vector2i.ZERO, TrialLayout.ROOM_SIZE, ExitRules.NORTH, TrialLayout.EXIT_X)
	var next := next_scene.instantiate() as RoomController
	next.setup(10, RoomSequence.RoomType.MINIBOSS, -1, false, _context())
	next.slot_index = 10
	next.apply_door_plan(Vector2i(ExitRules.SOUTH, next_entrance), [Vector2i(ExitRules.NORTH, next_exit)] as Array[Vector2i])
	next.position = Vector2(ExitRules.origin_for(end, next_size, ExitRules.SOUTH, next_entrance)) * RoomTiles.TILE_WORLD
	add_child_autofree(next)
	await wait_process_frames(2)
	PassageSeam.join(trial, next)
	assert_eq(_trial_cells_on(trial, next), [] as Array[Vector2i], "after the join no cell of the trial room lies on the next floor")
	var content := (load("res://dungeon/rooms/trials/trial_content.tscn") as PackedScene).instantiate() as TrialContent
	content.forced_kind = SpecialTable.TrialKind.GAUNTLET
	trial.add_child(content)
	content.setup(trial.context, trial)
	content._on_chest_opened(null)
	await wait_process_frames(3)
	for tile in TrialLayout.get_gate_tiles():
		assert_true(trial.tiles.is_walkable(tile), "the shortcut %s is open" % tile)
	assert_eq(_trial_cells_on(trial, next), [] as Array[Vector2i], "the shortcut leaves the seam alone (no rock squares beside the passage)")


## World tiles of the next room's floor where the trial room has a cell (collision or rock picture).
func _trial_cells_on(trial: RoomController, next: RoomController) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var trial_origin := PassageSeam.origin_of(trial)
	var next_origin := PassageSeam.origin_of(next)
	var rock := trial.tiles.get_rock_layer()
	for tile: Vector2i in next.tiles.get_floor_mask():
		var local := tile + next_origin - trial_origin
		if trial.tiles.get_floor_mask().has(local):
			continue
		if trial.tiles.get_cell_source_id(local) >= 0 or (rock != null and rock.get_cell_source_id(local) >= 0):
			cells.append(tile + next_origin)
	return cells

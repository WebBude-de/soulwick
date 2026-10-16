extends GutTest
## G2 (playtest 15.10.2026): the arch of a north gate keeps its look while a player walks through, the
## player darkens with the depth and is seen only through the opening (the rock over the arch is cut
## to it, the wall and the frame lie over him) until he hides under the closed crown; a side gate is a
## notch drawn by the terrain running into the dark, its rock lies over the players only while one is
## in the passage; a blocked entrance is closed by the room's own wall (no cut-off corridor) with
## rubble at its foot; in a room between two biomes the rock over a passage takes the blend.

const DOOR_SCENE: PackedScene = preload("res://dungeon/environment/doors/door.tscn")
const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_door_tunnel_view_save.cfg"
	DoorArt.art_dir = DoorStyle.ART_DIR
	DoorArt.clear_cache()


func after_all() -> void:
	SaveManager.save_path = _old_save_path
	DoorArt.clear_cache()


func _room(index: int, origin: Vector2i, entrance: Vector2i, exit: Vector2i) -> RoomController:
	var room := HALL.instantiate() as RoomController
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	room.setup(index, RoomSequence.RoomType.COMBAT, -1, false, context)
	room.apply_door_plan(entrance, [exit] as Array[Vector2i])
	room.position = Vector2(origin) * RoomTiles.TILE_WORLD
	add_child_autofree(room)
	return room


func _probe() -> Dictionary:
	var probe := HALL.instantiate() as RoomController
	var tiles := probe.get_node("Tiles") as RoomTiles
	var info := {"size": tiles.room_size, "exit_x": tiles.exit_x, "entrance_x": tiles.entrance_x}
	probe.free()
	return info


## Two joined rooms with a north passage; the gate of the lower one, open, its lintel built.
func _north_passage() -> Door:
	var info := _probe()
	var size: Vector2i = info["size"]
	var place: int = info["exit_x"]
	var lower := _room(3, Vector2i.ZERO, Vector2i(ExitRules.SOUTH, info["entrance_x"]), Vector2i(ExitRules.NORTH, place))
	var end := ExitRules.exit_corridor_end(Vector2i.ZERO, size, ExitRules.NORTH, place)
	var upper := _room(4, ExitRules.origin_for(end, size, ExitRules.SOUTH, info["entrance_x"]), Vector2i(ExitRules.SOUTH, info["entrance_x"]), Vector2i(ExitRules.NORTH, place))
	PassageSeam.join(lower, upper)
	var gate := GateCloser.gate_between(lower)
	gate.set_open_instant(true)
	gate.view.build_lintel([lower, upper] as Array[Node2D])
	return gate


func _image(texture: Texture2D) -> Image:
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image


func test_arch_visibility_runs_from_entry_to_deep() -> void:
	assert_almost_eq(DoorView.arch_visibility(0.0), DoorView.ARCH_VISIBLE_ENTRY, 0.001)
	assert_almost_eq(DoorView.arch_visibility(1.0), DoorView.ARCH_VISIBLE_DEEP, 0.001)
	assert_almost_eq(DoorView.arch_visibility(2.0), DoorView.ARCH_VISIBLE_DEEP, 0.001, "clamped")
	assert_true(DoorView.arch_visibility(0.5) < DoorView.arch_visibility(0.1), "darker further in")
	# Note 8: seen, but in the shadow (no black spot, not lit like the room).
	for depth in [0.0, 0.5, 1.0]:
		assert_between(DoorView.arch_visibility(depth), 0.3, 0.75)


func test_frame_top_keeps_the_opening_see_through() -> void:
	for cave in [false, true]:
		for soft in [false, true]:
			var style := DoorStyle.for_door(&"crypt")
			style.apply_room_look(cave, soft)
			var key := "cave %s soft %s" % [cave, soft]
			var top := DoorArt.frame_top_image(style)
			var shade := DoorArt.opening_top_image(style)
			assert_not_null(top, key)
			assert_not_null(shade, key)
			if top == null or shade == null:
				continue
			var above := 0
			var dark := 0
			for point: Vector2i in DoorArt.passage_mask(style):
				if point.y < style.leaf_offset.y:
					above += 1
					assert_almost_eq(top.get_pixelv(point).a, 0.0, 0.01, "%s: no dark in the frame itself" % key)
					dark += 1 if shade.get_pixelv(point).a > 0.2 else 0
			# A cave mouth may open no higher than its door tile.
			if above > 0:
				assert_gt(dark, 0, "%s: the tunnel dark is its own sprite" % key)


func test_cut_opening_takes_the_arch_out_of_the_crown_only() -> void:
	var style := DoorStyle.for_door(&"crypt")
	style.apply_room_look(false, true)
	var piece := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	piece.fill(Color(0.3, 0.3, 0.4))
	# The crown right above the door tile reaches into the top of the arch.
	var over := DoorArt.cut_opening(piece, style, Vector2(0, -64), 2.0, 2.0)
	assert_gt(int(over["cut"]), 0)
	var image: Image = over["image"]
	assert_almost_eq(image.get_pixel(16, 31).a, 0.0, 0.01, "the middle of the arch is open")
	assert_almost_eq(image.get_pixel(0, 0).a, 1.0, 0.01, "the rock beside it stays")
	# Two tiles to the side nothing is cut.
	var beside := DoorArt.cut_opening(piece, style, Vector2(128, -64), 2.0, 2.0)
	assert_eq(int(beside["cut"]), 0)


func test_player_in_the_arch_is_seen_in_its_shadow() -> void:
	var gate := _north_passage()
	var view := gate.view
	if view.get_lintel().is_empty():
		pass_test("no terrain tiles in this build")
		return
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	# Feet in the middle of the arch.
	player.global_position = gate.to_global(Vector2(32, 32)) - Player.FEET_OFFSET
	await wait_process_frames(30)
	assert_true(view.is_arch_view(), "the player stands in the arch")
	for child in view.get_children():
		if String(child.name).begins_with("LintelCut"):
			assert_true((child as Sprite2D).visible, "%s: the rock over the arch is cut to the opening" % child.name)
	assert_null(view.get_node_or_null("TunnelShade"), "no shade over the opening (note 20)")
	assert_almost_eq(player.modulate.r, DoorView.arch_visibility(0.5), 0.06, "the player darkens, not black")
	assert_almost_eq(player.modulate.a, 1.0, 0.01)
	# The wall around the opening and the frame lie over him: nothing reaches past the arch.
	for piece in view.get_lintel():
		if is_zero_approx(piece.position.y):
			assert_eq(piece.z_index, DoorView.LINTEL_Z, "%s over the player" % piece.name)
	if view.get_frame_sprite() != null:
		assert_gt(view.get_frame_sprite().z_index, 0, "the frame over the player")
	assert_false(DoorView.is_in_tunnel(get_tree(), player.global_position + Player.FEET_OFFSET), "the arch hides nothing")
	# Under the crown: hidden, the rock closed again.
	player.global_position = gate.to_global(Vector2(32, -20)) - Player.FEET_OFFSET
	await wait_process_frames(30)
	assert_false(view.is_arch_view(), "the full rock covers the passage")
	for piece in view.get_lintel():
		if piece.position.y < 0.0:
			assert_gte(piece.z_index, DoorView.LINTEL_Z, "%s over the player" % piece.name)
		elif is_zero_approx(piece.position.y):
			assert_eq(piece.z_index, DoorView.FRONT_PATCH_Z, "%s back behind the players" % piece.name)
	assert_true(DoorView.is_in_tunnel(get_tree(), gate.to_global(Vector2(32, -32))), "the corridor still hides")
	# Back in the room: his colour comes back.
	player.global_position = gate.to_global(Vector2(32, 160)) - Player.FEET_OFFSET
	await wait_process_frames(30)
	assert_almost_eq(player.modulate.r, 1.0, 0.01)


func test_an_arch_cuts_the_crown_while_a_player_stands_in_it() -> void:
	var gate := _north_passage()
	var view := gate.view
	if view.get_lintel().is_empty():
		pass_test("no terrain tiles in this build")
		return
	# A built arch rises above its door tile (a cave mouth may not).
	var style := gate.get_style()
	style.apply_room_look(false, false)
	view.apply_style(style, false)
	view.show_state(true)
	var cuts: Array[Sprite2D] = []
	for child in view.get_children():
		if String(child.name).begins_with("LintelCut"):
			cuts.append(child)
	assert_false(cuts.is_empty(), "the crown over the arch has a cut twin")
	for cut in cuts:
		assert_false(cut.visible, "hidden while nobody is in the arch")
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.global_position = gate.to_global(Vector2(32, 40)) - Player.FEET_OFFSET
	await wait_process_frames(10)
	assert_true(view.is_arch_view())
	for cut in cuts:
		assert_true(cut.visible, "the player shows through the arch")
		assert_eq(cut.z_index, DoorView.LINTEL_Z)
	var shade_top := view.get_node("ShadeTop") as Sprite2D
	assert_lt(shade_top.z_index, 0, "the dark of the tunnel lies behind him")
	player.global_position = gate.to_global(Vector2(32, -24)) - Player.FEET_OFFSET
	await wait_process_frames(10)
	assert_false(view.is_arch_view())
	for cut in cuts:
		assert_false(cut.visible, "closed rock over him in the corridor")
	assert_gt(shade_top.z_index, DoorView.LINTEL_Z)


func test_door_tile_beside_the_arch_shows_the_front() -> void:
	var gate := _north_passage()
	var view := gate.view
	if view.get_lintel().is_empty():
		pass_test("no terrain tiles in this build")
		return
	var on_door: Sprite2D = null
	for piece in view.get_lintel():
		if piece.position == Vector2.ZERO:
			on_door = piece
	assert_not_null(on_door, "a front patch on the door tile")
	if on_door == null:
		return
	assert_eq(on_door.z_index, DoorView.FRONT_PATCH_Z, "behind the arch, the gate and the players")
	var image := _image(on_door.texture)
	assert_almost_eq(image.get_pixel(image.get_width() / 2, image.get_height() - 1).a, 0.0, 0.01, "open in the arch")


func test_side_passage_hides_only_behind_its_notch() -> void:
	var view := DoorView.new()
	view.side = RoomTiles.DoorSide.EAST
	add_child_autofree(view)
	view._passage_rects.append(Rect2(Vector2.ZERO, Vector2(64, 64)))
	view._passage_rects.append(Rect2(Vector2(64, 0), Vector2(64, 64)))
	view.add_to_group(DoorView.TUNNEL_GROUP)
	# The notch shows the player; the passage behind it hides him.
	assert_eq(view.get_hidden_rects().size(), 1)
	assert_false(DoorView.is_in_tunnel(get_tree(), Vector2(32, 32)))
	assert_true(DoorView.is_in_tunnel(get_tree(), Vector2(96, 32)))


func test_blocked_entrance_is_closed_by_the_wall() -> void:
	var info := _probe()
	var room := _room(1, Vector2i.ZERO, Vector2i(ExitRules.SOUTH, info["entrance_x"]), Vector2i(ExitRules.NORTH, info["exit_x"]))
	var entrance := Door.entrance_of(room)
	assert_not_null(entrance)
	if entrance == null:
		return
	entrance.block()
	await wait_process_frames(2)
	var tiles := room.tiles
	var door_tile := RoomTiles.door_tile_of(tiles.entrance_side, tiles.entrance_x, tiles.room_size)
	var passage := PassageCover.sealed_cells(tiles, door_tile, Vector2i.DOWN)
	assert_gte(passage.size(), 2, "the gap and its corridor")
	var plan := PassageCover.sealed_plan(room, door_tile, Vector2i.DOWN)
	var cells: Array[Vector2i] = []
	for entry in plan:
		cells.append(entry["cell"])
	var floor_mask := tiles.get_floor_mask()
	for cell in passage:
		assert_true(cells.has(cell), "closed: %s" % cell)
	assert_true(cells.has(passage[passage.size() - 1] + Vector2i.DOWN), "no edge left at the end of the corridor")
	for cell in cells:
		assert_false(floor_mask.has(cell) and not passage.has(cell), "no floor of the room covered: %s" % cell)
	if tiles.is_terrain_drawn():
		assert_false(entrance.view.get_seal().is_empty(), "the wall is drawn over the gap")
		for piece in entrance.view.get_seal():
			assert_true(piece.visible)
			assert_eq(piece.z_index, DoorView.SEAL_Z)
		# The wall over the gap is the room's plain wall beside it.
		var beside := door_tile + Vector2i(3, 0)
		var rock := tiles.get_rock_layer()
		for entry in plan:
			if entry["cell"] == door_tile and rock != null and rock.get_cell_source_id(beside) >= 0:
				var atlas: Vector3i = entry["atlas"]
				assert_eq(Vector2i(atlas.x, atlas.y), rock.get_cell_atlas_coords(beside), "the wall line runs straight")
	for piece in entrance.view.get_rubble():
		assert_true(piece.visible, "rubble at the foot")
		assert_eq(piece.z_index, DoorView.RUBBLE_Z)
	# An entrance that opens again shows the gap.
	entrance.set_open_instant(true)
	for piece in entrance.view.get_seal():
		assert_false(piece.visible)


## Two joined rooms with a side passage (east exit of the first); null if the hall has no side doors.
func _side_passage() -> Door:
	var info := _probe()
	var size: Vector2i = info["size"]
	var probe := HALL.instantiate() as RoomController
	var slots := (probe.get_node("Tiles") as RoomTiles).get_door_slots(ExitRules.EAST)
	var west_slots := (probe.get_node("Tiles") as RoomTiles).get_door_slots(ExitRules.WEST)
	probe.free()
	if slots.is_empty() or west_slots.is_empty():
		return null
	var first := _room(3, Vector2i.ZERO, Vector2i(ExitRules.SOUTH, info["entrance_x"]), Vector2i(ExitRules.EAST, slots[0]))
	var end := ExitRules.exit_corridor_end(Vector2i.ZERO, size, ExitRules.EAST, slots[0])
	var second := _room(4, ExitRules.origin_for(end, size, ExitRules.WEST, west_slots[0]), Vector2i(ExitRules.WEST, west_slots[0]), Vector2i(ExitRules.NORTH, info["exit_x"]))
	PassageSeam.join(first, second)
	var gate := GateCloser.gate_between(first)
	gate.set_open_instant(true)
	gate.view.build_lintel([first, second] as Array[Node2D])
	return gate


func test_side_gate_is_a_notch_running_into_the_dark() -> void:
	var notch := DoorArt.side_notch_image()
	assert_almost_eq(notch.get_pixel(0, 16).a, 0.0, 0.01, "clear at the mouth")
	assert_gt(notch.get_pixel(31, 16).a, 0.9, "dark at the back")
	assert_lt(notch.get_pixel(12, 16).a, notch.get_pixel(20, 16).a, "darker further in")
	var gate := _side_passage()
	if gate == null:
		pass_test("the hall has no side doors")
		return
	var view := gate.view
	if view.get_lintel().is_empty():
		pass_test("no terrain tiles in this build")
		return
	assert_not_null(view.get_side_notch())
	for piece in view.get_lintel():
		assert_ne(piece.position, Vector2.ZERO, "the door tile stays open (the notch)")
		assert_eq(piece.z_index, DoorView.SIDE_COVER_LOW_Z, "%s under a player beside the wall" % piece.name)
	# A player walks in: the rock lies over him.
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.global_position = gate.to_global(Vector2(24, 32)) - Player.FEET_OFFSET
	await wait_process_frames(10)
	var over := 0
	for piece in view.get_lintel():
		if piece.position.y < 0.0 and is_zero_approx(piece.position.x):
			assert_eq(piece.z_index, DoorView.SIDE_COVER_LOW_Z, "%s: the wall face above the notch stays behind him" % piece.name)
		elif piece.position.y > 0.0 or (piece.position.x * view.get_inward().x < 0.0):
			assert_eq(piece.z_index, DoorView.LINTEL_Z, "%s over the player in the passage" % piece.name)
			over += 1
	assert_gt(over, 0)
	player.global_position = gate.to_global(Vector2(-96, 32)) - Player.FEET_OFFSET
	await wait_process_frames(10)
	for piece in view.get_lintel():
		assert_eq(piece.z_index, DoorView.SIDE_COVER_LOW_Z)


func test_rock_over_a_passage_takes_the_biome_blend() -> void:
	var gate := _north_passage()
	var view := gate.view
	if view.get_lintel().is_empty():
		pass_test("no terrain tiles in this build")
		return
	var room := gate.get_parent() as RoomController
	var grotto: TileSet = load("res://dungeon/environment/slime_grotto_tileset.tres")
	room.tiles.set_biome_blend(grotto, Color.WHITE, float(room.tiles.room_size.y), -2.0)
	view.apply_style(gate.get_style(), false)
	view.show_state(true)
	var blended := 0
	for piece in view.get_lintel():
		var twin := piece.get_node_or_null("Blend") as Sprite2D
		if twin != null:
			blended += 1
			assert_same(twin.material, room.tiles.get_blend_layer().material, "the room's blend mask")
	assert_gt(blended, 0, "the second biome over the rock")

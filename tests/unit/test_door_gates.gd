extends GutTest
## One gate per transition (M2, 11_makeover3_komplett.md §11/§12): openings show what lies behind
## them (playtest 14.10.2026: no dark sheet in an arch, a cave mouth, an open gate or the exit
## portal), the light cone of a shut gate shines at 30 %, a side door's sign never covers its torch,
## and the gate of the room left shuts behind the group once everyone is inside the next room.

const DOOR_SCENE: PackedScene = preload("res://dungeon/environment/doors/door.tscn")
const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const PORTAL: Texture2D = preload("res://art/environment/props/exit_portal_6f.png")
## A dark sheet: this many pixels square, all opaque and dark.
const SHEET := 4

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_door_gates_save.cfg"
	DoorArt.art_dir = DoorStyle.ART_DIR
	DoorArt.clear_cache()


func after_all() -> void:
	SaveManager.save_path = _old_save_path
	DoorArt.clear_cache()


func _image(texture: Texture2D) -> Image:
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image


## Top-left of a SHEET x SHEET block of opaque dark pixels inside rect, (-1, -1) if there is none.
func _dark_sheet(image: Image, rect: Rect2i) -> Vector2i:
	for y in range(rect.position.y, rect.end.y - SHEET + 1):
		for x in range(rect.position.x, rect.end.x - SHEET + 1):
			var solid := true
			for dy in SHEET:
				for dx in SHEET:
					var c := image.get_pixel(x + dx, y + dy)
					solid = solid and c.a > 0.5 and c.get_luminance() < 0.15
			if solid:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


# --- Openings ---

func test_arches_and_cave_mouths_are_open_up_to_the_top() -> void:
	var styles: Array[DoorStyle] = []
	for biome in DoorStyle.BIOMES:
		for cave in [false, true]:
			var style := DoorStyle.for_door(biome)
			style.apply_room_look(cave)
			styles.append(style)
	var soft := DoorStyle.for_door(&"crypt")
	soft.apply_room_look(true, true)
	styles.append(soft)
	styles.append(DoorStyle.for_door(&"crypt", DoorStyle.KIND_BOSS))
	for style in styles:
		var image := _image(DoorArt.get_frame(style))
		# The passage: between the posts, from the arch's top inside edge down to the floor line.
		var top := 0
		var middle := image.get_width() / 2
		while top < image.get_height() and image.get_pixel(middle, top).a > 0.05:
			top += 1
		assert_lt(top, style.leaf_offset.y + 1, "%s: the passage is open above the door tile" % style.get_key())
		var rect := Rect2i(style.leaf_offset.x + 2, top, style.leaf_size.x - 4, image.get_height() - top)
		assert_eq(_dark_sheet(image, rect), Vector2i(-1, -1), "%s: no dark sheet in the opening" % style.get_key())


func test_gates_are_see_through_while_open() -> void:
	for gate in [DoorStyle.GATE_SLAB, DoorStyle.GATE_BARS]:
		var style := DoorStyle.for_door(&"crypt")
		style.apply_room_look(false, false, gate == DoorStyle.GATE_BARS)
		var image := _image(DoorArt.get_leaf_strip(style))
		var size := DoorStyle.GATE_SIZE
		# Opening frames and the open one: no dark sheet behind the slab or between the bars.
		for frame in range(1, DoorArt.LEAF_FRAMES):
			var rect := Rect2i(frame * size.x, 0, size.x, size.y)
			assert_eq(_dark_sheet(image, rect), Vector2i(-1, -1), "%s frame %d" % [gate, frame + 1])
		var open := image.get_region(Rect2i(3 * size.x, 0, size.x, size.y))
		var clear := 0
		for y in size.y - 4:
			for x in size.x:
				if open.get_pixel(x, y).a < 0.05:
					clear += 1
		assert_gt(float(clear) / float(size.x * (size.y - 4)), 0.8, "%s: the open gate is free" % gate)


func test_closed_gate_looks_like_wall() -> void:
	var image := _image(DoorArt.get_leaf_strip(DoorStyle.for_door(&"crypt")))
	var size := DoorStyle.GATE_SIZE
	var opaque := 0
	for y in size.y:
		for x in size.x:
			if image.get_pixel(x, y).a > 0.5:
				opaque += 1
	assert_gt(float(opaque) / float(size.x * size.y), 0.9, "a shut slab fills the opening")


func test_exit_portal_shows_the_wall_above_its_swirl() -> void:
	var raw := _image(PORTAL)
	# Older art painted a dark sheet over the swirl; open_fill clears it, newer art has none.
	var opened := _image(DoorArt.open_fill(PORTAL, DoorArt.PORTAL_FILL))
	for f in 6:
		assert_eq(_dark_sheet(opened, Rect2i(f * 32 + 8, 6, 16, 9)), Vector2i(-1, -1), "frame %d: see-through above the swirl" % f)
	assert_eq(opened.get_pixel(16, 30), raw.get_pixel(16, 30), "the swirl itself stays")


# --- Light of the way ---

func test_shut_gate_shows_its_way_dimmed() -> void:
	var door := DOOR_SCENE.instantiate() as Door
	door.configure(&"crypt")
	add_child_autofree(door)
	door.show_way(RoomObjective.FLAME, RoomObjective.get_mode_color(RoomObjective.FLAME))
	await wait_physics_frames(2)
	assert_almost_eq(door.view.get_cone_share(), DoorView.CONE_CLOSED_SHARE, 0.01)
	assert_almost_eq(door.view.get_way_light().intensity, DoorView.WAY_LIGHT_INTENSITY * DoorView.CONE_CLOSED_SHARE, 0.01)
	door.open()
	await wait_seconds(DoorView.CONE_SHARE_TIME + 0.2)
	assert_almost_eq(door.view.get_cone_share(), 1.0, 0.01, "open: full light")
	assert_gt(door.view.get_cone_sprite().modulate.a, DoorView.CONE_ALPHA * 0.8)


func test_side_sign_stays_clear_of_the_torch() -> void:
	for side in [RoomTiles.DoorSide.WEST, RoomTiles.DoorSide.EAST]:
		var door := DOOR_SCENE.instantiate() as Door
		door.set_side(side)
		door.configure(&"slime_grotto")
		add_child_autofree(door)
		door.show_way(RoomObjective.SOULS, RoomObjective.get_mode_color(RoomObjective.SOULS))
		var symbol := door.view.get_symbol_sprite()
		var torches := door.view.get_torches()
		assert_eq(torches.size(), 1)
		var symbol_bottom := symbol.position.y + symbol.texture.get_height() * symbol.scale.y * 0.5
		var torch_top := torches[0].position.y - torches[0].pivot.y * torches[0].scale.y
		assert_lt(symbol_bottom, torch_top, "side %d: the sign hangs above the torch" % side)


func test_mouth_has_pebbles_and_moss() -> void:
	var door := DOOR_SCENE.instantiate() as Door
	door.configure(&"slime_grotto")
	add_child_autofree(door)
	assert_eq(door.view.get_mouth_deco().size(), DoorView.MOUTH_DECO.size())


# --- No way back ---

func _room(index: int, origin: Vector2) -> RoomController:
	var room := HALL.instantiate() as RoomController
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	room.setup(index, RoomSequence.RoomType.COMBAT, -1, false, context)
	var tiles := room.get_node("Tiles") as RoomTiles
	room.apply_door_plan(Vector2i(RoomTiles.DoorSide.SOUTH, tiles.entrance_x), [Vector2i(RoomTiles.DoorSide.NORTH, tiles.exit_x)] as Array[Vector2i])
	room.position = origin
	add_child_autofree(room)
	return room


func test_gate_shuts_once_everyone_is_inside() -> void:
	var left := _room(3, Vector2.ZERO)
	var entered := _room(4, Vector2(0, -64 * 30))
	var gate := GateCloser.gate_between(left)
	gate.set_open_instant(true)
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	# Still in the old room: the gate waits.
	player.global_position = left.to_global(left.tiles.get_floor_rect().get_center())
	var closer := GateCloser.close_behind(left, entered)
	assert_not_null(closer)
	assert_same(GateCloser.close_behind(left, entered), closer, "one watcher per room")
	await wait_physics_frames(3)
	assert_true(gate.is_open, "nobody is inside yet")
	assert_false(GateCloser.all_players_inside(entered, get_tree()))
	# Inside the new room: the gate shuts behind him and blocks.
	player.global_position = entered.to_global(entered.tiles.get_floor_rect().get_center())
	watch_signals(gate)
	await wait_physics_frames(3)
	assert_true(GateCloser.all_players_inside(entered, get_tree()))
	assert_false(gate.is_open, "no way back")
	assert_signal_emitted_with_parameters(gate, "state_changed", [false, false])
	assert_false((gate.get_node("CollisionShape2D") as CollisionShape2D).disabled, "the gate blocks players and enemies")
	assert_null(entered.get_node_or_null(NodePath(GateCloser.NODE_NAME)), "the watcher is done")


func test_nothing_to_shut_without_an_open_gate() -> void:
	var left := _room(3, Vector2.ZERO)
	var entered := _room(4, Vector2(0, -64 * 30))
	assert_null(GateCloser.close_behind(left, entered), "the gate is still shut")
	assert_null(GateCloser.close_behind(null, entered))

extends GutTest
## Nothing pops up (R5): a prepared room lies dark under its veil (floor and walls, not the entrance
## corridor) until a player steps into the entrance corridor or the room activates.

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_room_veil_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _room(entrance_side := RoomTiles.DoorSide.SOUTH) -> RoomController:
	var room := HALL.instantiate() as RoomController
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	room.setup(2, RoomSequence.RoomType.COMBAT, -1, false, context)
	var tiles := room.get_node("Tiles") as RoomTiles
	var place := tiles.entrance_x if entrance_side == RoomTiles.DoorSide.SOUTH else tiles.get_door_slots(entrance_side)[0]
	var exits: Array[Vector2i] = [Vector2i(RoomTiles.DoorSide.NORTH, tiles.exit_x)]
	room.apply_door_plan(Vector2i(entrance_side, place), exits)
	add_child_autofree(room)
	return room


func test_veil_rect_leaves_the_entrance_side_open() -> void:
	var size := Vector2i(15, 9)
	var body := ExitRules.body_rect_of(size)
	var south := RoomVeil.get_veil_rect(size, RoomTiles.DoorSide.SOUTH)
	assert_eq(south.end.y, body.end.y, "south entrance: the corridor below stays visible")
	assert_eq(south.position.y, body.position.y - 1, "one tile of rock above")
	var west := RoomVeil.get_veil_rect(size, RoomTiles.DoorSide.WEST)
	assert_eq(west.position.x, body.position.x, "west entrance: no rock covered on that side")
	assert_eq(west.end.y, body.end.y + 1)
	var east := RoomVeil.get_veil_rect(size, RoomTiles.DoorSide.EAST)
	assert_eq(east.end.x, body.end.x)
	for side: int in [RoomTiles.DoorSide.SOUTH, RoomTiles.DoorSide.WEST, RoomTiles.DoorSide.EAST]:
		var rect := RoomVeil.get_veil_rect(size, side)
		var outside := RoomTiles.corridor_end_of(side, 4, size)
		assert_false(rect.has_point(outside), "the corridor end stays free (side %d)" % side)


func test_texture_has_soft_edges() -> void:
	var texture := RoomVeil.make_texture(Vector2i(6, 4))
	var image := texture.get_image()
	assert_eq(image.get_size(), Vector2i(6, 4) * RoomVeil.PIXELS_PER_TILE)
	assert_lt(image.get_pixel(0, 0).a, 0.2, "transparent border")
	assert_almost_eq(image.get_pixel(image.get_width() / 2, image.get_height() / 2).a, 1.0, 0.01, "solid inside")


func test_veil_covers_the_room_until_lifted() -> void:
	var room := _room()
	var veil := RoomVeil.attach(room)
	assert_same(RoomVeil.attach(room), veil, "one veil per room")
	assert_same(RoomVeil.of(room), veil)
	assert_false(veil.is_lifted())
	assert_true(veil.visible)
	assert_almost_eq(veil.get_sheet().modulate.a, RoomVeil.VEIL_ALPHA, 0.001)
	assert_eq(veil.z_index, RoomVeil.VEIL_Z)
	watch_signals(veil)
	RoomVeil.lift_room(room)
	assert_true(veil.is_lifted())
	assert_signal_emitted(veil, "lifted")
	await wait_seconds(RoomVeil.LIFT_TIME + 0.15)
	assert_false(veil.visible, "the room is lit")
	RoomVeil.lift_room(room)
	assert_signal_emit_count(veil, "lifted", 1, "lifts once")


func test_player_in_the_entrance_corridor_lifts_the_veil() -> void:
	var room := _room(RoomTiles.DoorSide.WEST)
	var veil := RoomVeil.attach(room)
	var tiles := room.tiles
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.global_position = room.to_global(RoomTiles.tile_center(Vector2i(0, tiles.entrance_x) + Vector2i(4, 0)))
	await wait_physics_frames(4)
	assert_false(veil.is_lifted(), "a player inside the floor alone does not count before the corridor")
	player.global_position = room.to_global(RoomTiles.tile_center(RoomTiles.corridor_end_of(tiles.entrance_side, tiles.entrance_x, tiles.room_size)))
	await wait_physics_frames(4)
	assert_true(veil.is_lifted(), "stepping into the entrance corridor lights the room")


func test_instant_lift_hides_at_once() -> void:
	var room := _room()
	var veil := RoomVeil.attach(room)
	veil.lift(true)
	assert_false(veil.visible)

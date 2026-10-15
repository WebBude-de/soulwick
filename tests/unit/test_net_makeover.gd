extends GutTest
## Shared run after the makeover (M2, M4, M5; D-140, D-143, D-144; MULTIPLAYER.md §3e): the group
## camera keeps the local player in view, a player who gets up behind a shut gate joins the team,
## stragglers land past the gate, the side view reads the player's input object (so RemoteInput and
## the network drive it), the side state travels as bits and is replayed on a copy, and the same run
## seed and slot plan the same side way on every machine.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const STEP := 1.0 / 60.0
const PLAN := [
	"####################",
	"#..................#",
	"#..................#",
	"#..................#",
	"#..................#",
	"#.....H=====.......#",
	"#.....H............#",
	"#S....H.........oD.#",
	"##########...#######",
]
const ALIVE_SOURCE := "extends Node2D\nvar alive := true\nfunc is_alive() -> bool:\n\treturn alive\n"

var _old_save_path: String
var _segment: SideSegment = null


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_net_makeover_save.cfg"
	SaveManager.load_game()


func after_all() -> void:
	SideWays.force_for_tests = false
	RunManager.end_run(RunManager.EndReason.ABORT)
	SaveManager.save_path = _old_save_path


func after_each() -> void:
	SideWays.force_for_tests = false
	HitStop.reset()
	await wait_process_frames(1)


# --- Group camera (M4) ---

func _body(at: Vector2, alive := true) -> Node2D:
	var script := GDScript.new()
	script.source_code = ALIVE_SOURCE
	script.reload()
	var node := Node2D.new()
	node.set_script(script)
	add_child_autofree(node)
	node.global_position = at
	node.set(&"alive", alive)
	return node


func test_the_group_camera_keeps_the_local_player_and_near_mates() -> void:
	var local := _body(Vector2(100, 100))
	var near := _body(Vector2(400, 220))
	var group := CoopRules.camera_group(local, [near, local])
	assert_eq(group.size(), 2, "local player and the mate near him")
	assert_eq(group[0], local, "the local player comes first")
	var middle := (group[0].global_position + group[1].global_position) * 0.5
	var offset := (middle - local.global_position).abs()
	assert_true(offset.x <= CoopRules.CAMERA_KEEP.x and offset.y <= CoopRules.CAMERA_KEEP.y, "the middle stays near the local player")


func test_the_group_camera_drops_far_and_downed_mates() -> void:
	var local := _body(Vector2.ZERO, false)
	var far := _body(Vector2(CoopRules.CAMERA_KEEP.x + 50.0, 0))
	var downed := _body(Vector2(30, 0), false)
	var near := _body(Vector2(0, CoopRules.CAMERA_KEEP.y - 10.0))
	var group := CoopRules.camera_group(local, [far, downed, near, null])
	assert_eq(group, [local, near] as Array[Node2D], "a downed local player stays the anchor, far and downed mates drop out")
	assert_eq(CoopRules.camera_group(null, [near]).size(), 0, "no local player: nothing")


func test_the_camera_rig_follows_the_provider() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	var mate := _body(Vector2(200, 0))
	var rig := player.get_node("Camera2D") as CameraRig
	assert_eq(rig.camera_targets().size(), 1, "alone: the carrier")
	rig.set_targets_provider(func() -> Array: return CoopRules.camera_group(player, [player, mate]))
	assert_eq(rig.camera_targets().size(), 2, "with the group provider both are in view")


# --- Gate and revive (M2, D-143) ---

func test_a_player_up_behind_a_shut_gate_joins_the_nearest_mate() -> void:
	var floor_rect := Rect2(0, 0, 640, 448)
	var mates: Array[Vector2] = [Vector2(500, 300), Vector2(100, 100)]
	assert_eq(CoopRules.rejoin_point(Vector2(90, 600), floor_rect, false, mates), Vector2(100, 100), "behind the shut gate: at the nearest mate")
	assert_eq(CoopRules.rejoin_point(Vector2(100, 600), floor_rect, true, mates), Vector2.INF, "the gate is still open: he walks")
	assert_eq(CoopRules.rejoin_point(Vector2(200, 200), floor_rect, false, mates), Vector2.INF, "inside the room: he stays")
	assert_eq(CoopRules.rejoin_point(Vector2(100, 600), floor_rect, false, [] as Array[Vector2]), Vector2.INF, "nobody to join")


func _room(scene: PackedScene, room_index := 3, slot := 3) -> RoomController:
	var room := scene.instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 77
	room.setup(room_index, RoomSequence.RoomType.COMBAT, -1, false, context)
	room.slot_index = slot
	add_child_autofree(room)
	return room


func test_stragglers_land_past_the_gate_on_floor() -> void:
	var checked := 0
	for entry in RoomCatalog.create().get_entries().slice(0, 12):
		var room := _room(entry.scene)
		var start := room.get_player_start()
		var inside := room.get_arena().grow(-GateCloser.INSIDE_MARGIN)
		assert_true(inside.has_point(start), "%s: the player start lies past the gate margin" % entry.scene.resource_path.get_file())
		for index in 4:
			var point := NetDungeon.gather_point(room, start + WorldController.get_spawn_offset(index), start)
			assert_true(inside.has_point(point), "%s: straggler %d lands inside" % [entry.scene.resource_path.get_file(), index])
			var tiles := room.get_node("Tiles") as RoomTiles
			assert_true(tiles.is_walkable(RoomTiles.local_to_tile(room.to_local(point))), "on walkable floor")
		assert_eq(NetDungeon.gather_point(room, room.get_arena().position - Vector2(100, 100), start), start, "outside the floor: the start")
		checked += 1
	assert_gt(checked, 0)


# --- Side view (M5) ---

func _layout() -> SideLayout:
	var layout := SideLayout.parse(PackedStringArray(PLAN), &"test")
	layout.biome_id = &"crypt"
	return layout


func _side_player(input: PlayerInput) -> Player:
	_segment = SideSegment.new()
	_segment.setup(_layout(), 1, null, 42)
	add_child_autofree(_segment)
	_segment.global_position = Vector2(0, 5000)
	_segment.set_physics_process(false)
	var player := PLAYER_SCENE.instantiate() as Player
	player.is_local = false
	player.input = input
	add_child_autofree(player)
	player.set_physics_process(false)
	_segment.add_player(player)
	return player


func _run(player: Player, frames: int) -> void:
	for i in frames:
		player._physics_process(STEP)


func test_the_side_view_reads_the_players_input_object() -> void:
	var input := RemoteInput.new()
	var player := _side_player(input)
	await wait_physics_frames(3)
	_run(player, 10)
	var ground := player.get_feet_position().y
	assert_true(player.side_motion.is_on_floor(), "stands on the start")
	input.press(PlayerInput.DASH)
	_run(player, 12)
	assert_lt(player.get_feet_position().y, ground - 64.0, "the jump (dash key) came through RemoteInput")
	assert_true(player.side_motion.is_jumping())
	input.release(PlayerInput.DASH)
	_run(player, 90)
	assert_true(player.side_motion.is_on_floor(), "landed again")
	var x := player.global_position.x
	input.set_move(Vector2.RIGHT)
	input.tap(PlayerInput.SIDE_DASH)
	_run(player, 2)
	assert_true(player.is_dashing(), "the side dash came through RemoteInput")
	_run(player, 10)
	assert_gt(player.global_position.x, x + 60.0, "dashed to the right")


func test_the_side_state_travels_as_bits() -> void:
	var input := RemoteInput.new()
	var player := _side_player(input)
	await wait_physics_frames(3)
	_run(player, 10)
	var bits := NetPlayerState.side_bits_of(player)
	assert_eq(bits & NetPlayerState.SIDE_ACTIVE, NetPlayerState.SIDE_ACTIVE)
	assert_eq(bits & NetPlayerState.SIDE_ON_FLOOR, NetPlayerState.SIDE_ON_FLOOR, "on the floor")
	input.press(PlayerInput.DASH)
	input.set_move(Vector2.LEFT)
	_run(player, 6)
	bits = NetPlayerState.side_bits_of(player)
	assert_eq(bits & NetPlayerState.SIDE_ON_FLOOR, 0, "in the air")
	assert_eq(bits & NetPlayerState.SIDE_JUMPING, NetPlayerState.SIDE_JUMPING, "jumping")
	assert_eq(bits & NetPlayerState.SIDE_FACING_LEFT, NetPlayerState.SIDE_FACING_LEFT, "facing left")
	_segment.remove_players()
	assert_eq(NetPlayerState.side_bits_of(player), 0, "top-down: no side state")


func test_a_copy_climbs_and_falls_where_the_host_does() -> void:
	var player := _side_player(RemoteInput.new())
	await wait_physics_frames(3)
	var motion := player.side_motion
	# Feet at the foot of the ladder (column 6, rows 5-7).
	motion.place_at(_segment.to_global(SideLayout.feet_of(Vector2i(6, 7))))
	motion.apply_remote_state(true, false, -1.0)
	assert_true(motion.is_climbing(), "climbs as at the host")
	assert_eq(motion.facing, -1.0, "faces as at the host")
	motion.apply_remote_state(false, false, 1.0)
	assert_false(motion.is_climbing(), "off the ladder as at the host")
	motion.apply_remote_state(false, true, 1.0)
	assert_true(motion.is_in_pit(), "in the pit as at the host")


func test_the_same_seed_and_slot_plan_the_same_side_way() -> void:
	SideWays.force_for_tests = true
	var signatures: Array[String] = []
	for machine in 2:
		var room := _room(HALL, 3, 3)
		var next := _room(HALL, 4, 4)
		next.position = Vector2(0, -2000)
		var gate := SideWays.plan(room, next, 4711, false, false, false)
		assert_not_null(gate, "machine %d: a side way (test aid)" % machine)
		signatures.append(NetSide.signature_of(gate))
	assert_ne(signatures[0], "")
	assert_eq(signatures[0], signatures[1], "host and client plan the same segment")
	var other := SideWays.plan(_room(HALL, 3, 3), _room(HALL, 4, 4), 4711, true, false, false)
	assert_null(other, "never twice in a row, also with the test aid")
	var skipped := SideWays.plan(_room(HALL, 3, 3), _room(HALL, 4, 4), 4711, false, false, true)
	assert_null(skipped, "the host's skip option holds")
	var differs := false
	for seed in [1, 2, 3, 4, 5, 6]:
		var gate := SideWays.plan(_room(HALL, 3, 3), _room(HALL, 4, 4), seed, false, false, false)
		differs = differs or NetSide.signature_of(gate) != signatures[0]
	assert_true(differs, "other seeds give other segments")


# --- Tunnels (M2, PassageCover) ---

const PASSAGE_SOURCE := "extends Node2D\nvar rects: Array[Rect2] = []\nfunc get_passage_rects() -> Array[Rect2]:\n\treturn rects\n"


func test_a_player_in_a_tunnel_is_hidden_with_his_name_tag() -> void:
	# Every player (local, remote) sorts below the rock over the passage, on every machine.
	var player := autofree(PLAYER_SCENE.instantiate()) as Player
	assert_lt(player.z_index, DoorView.LINTEL_Z, "the rock lies above every player")
	var script := GDScript.new()
	script.source_code = PASSAGE_SOURCE
	script.reload()
	var view := Node2D.new()
	view.set_script(script)
	add_child_autofree(view)
	view.global_position = Vector2(320, 64)
	view.set(&"rects", [Rect2(0, 0, 64, 64), Rect2(0, -64, 64, 64)] as Array[Rect2])
	assert_true(CoopRules.in_passage(Vector2(352, 96), [view]), "in the door tile")
	assert_true(CoopRules.in_passage(Vector2(352, 32), [view]), "in the corridor behind it")
	assert_false(CoopRules.in_passage(Vector2(352, 160), [view]), "in the room in front")
	assert_false(CoopRules.in_passage(Vector2(322, 96), [view]), "on the edge (inset like DoorView)")
	assert_false(CoopRules.in_passage(Vector2(352, 96), [null]), "no view")
	var tag := Label.new()
	tag.name = "NameTag"
	player.add_child(tag)
	NetPlayers.set_tag_hidden(player, true)
	assert_false(tag.visible, "the name tag goes with him")
	NetPlayers.set_tag_hidden(player, false)
	assert_true(tag.visible, "and comes back outside")

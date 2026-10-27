extends GutTest
## Bug reports 22.10.2026 11:17 (rooms 3, 6 and 57 of two runs).
##   #eba92e17 (room 6, geleit_pfad_crypt, escort): "Der kommt hier nicht runter. Und muss einen Pfad
##   finden" - a slime on the plateau has to come down the stairs to its target below, the player or
##   the lost villager.
##   #bcff6539 (room 3): stepping out of a side passage into the room behind it the rock of the wall
##   stays over the player until his picture has left it ("mach den Layer an der Kante").
##   #331603b8 (room 57): a player walking along the south side of a side passage is under its rock.

const ESCORT_ROOM := "res://dungeon/rooms/combat/geleit_pfad_crypt.tscn"
const HALL := "res://dungeon/rooms/combat/combat_hall.tscn"
const ENEMY_SCENE: PackedScene = preload("res://enemies/enemy_base.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const SLIME: EnemyData = preload("res://enemies/data/slime.tres")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
const SPLITTER: EnemyData = preload("res://enemies/data/splitter_slime.tres")
## Seed of the run of #eba92e17.
const FEEDBACK_SEED := -7817677183151461459
## Seconds every enemy gets to stand next to its target on its level. TESTWERT
const REACH_LIMIT := 10.0
const REACH_DISTANCE := 96.0

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_room_feedback_1117_save.cfg"


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()


func after_each() -> void:
	HitStop.reset()
	await wait_process_frames(1)


func _room(path: String, room_index: int) -> RoomController:
	var room := (load(path) as PackedScene).instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = FEEDBACK_SEED
	room.setup(room_index, RoomSequence.RoomType.COMBAT, -1, false, context)
	add_child_autofree(room)
	return room


func _at(room: RoomController, tile: Vector2i) -> Vector2:
	return room.tiles.to_global(room.tiles.map_to_local(tile))


func _tile(room: RoomController, node: Node2D) -> Vector2i:
	return room.tiles.local_to_map(room.tiles.to_local(node.global_position))


func _player(room: RoomController, tile: Vector2i) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.global_position = _at(room, tile) - Vector2(0, 8)
	player.health.reset(9999.0)
	return player


func _enemies(room: RoomController, data: EnemyData, tiles: Array[Vector2i]) -> Array[Enemy]:
	var enemies: Array[Enemy] = []
	for tile in tiles:
		assert_true(room.tiles.get_height_layout().surface.has(tile), "%s is plateau surface" % tile)
		var enemy: Enemy = ENEMY_SCENE.instantiate()
		enemy.data = data
		enemy.arena = room.get_arena()
		enemy.apply_scaling(room.room_index, false)
		room.enemy_container.add_child(enemy)
		enemy.global_position = _at(room, tile)
		enemies.append(enemy)
	return enemies


## Runs until every enemy stood next to target on its level once; the ones that never did.
func _never_reached(player: Player, target: Node2D, enemies: Array[Enemy], room: RoomController) -> Array[String]:
	var reached := {}
	for frame in int(REACH_LIMIT * 60.0):
		await wait_physics_frames(1)
		player.health.reset(9999.0)
		for enemy in enemies:
			if is_instance_valid(enemy) and enemy.global_position.distance_to(target.global_position) < REACH_DISTANCE and HeightRules.same_level(enemy, target):
				reached[enemy.get_instance_id()] = true
		if reached.size() == enemies.size():
			break
	var missing: Array[String] = []
	for enemy in enemies:
		if is_instance_valid(enemy) and not reached.has(enemy.get_instance_id()):
			missing.append("%s at %s, level %d" % [enemy.data.id, _tile(room, enemy), HeightRules.level_of(enemy)])
	return missing


## #eba92e17: slimes and skeletons on the plateau of the escort room walk down its stairs to a
## player on the ground east and south of it.
func test_enemies_on_the_escort_plateau_come_down_to_the_player() -> void:
	for data: EnemyData in [SLIME, SKELETON]:
		for player_tile: Vector2i in [Vector2i(11, 5), Vector2i(10, 2), Vector2i(3, 5)]:
			var room := _room(ESCORT_ROOM, 6)
			await wait_physics_frames(12)
			var player := _player(room, player_tile)
			var enemies := _enemies(room, data, [Vector2i(8, 1), Vector2i(8, 2), Vector2i(5, 1), Vector2i(7, 2)] as Array[Vector2i])
			var missing := await _never_reached(player, player, enemies, room)
			assert_eq(missing, [] as Array[String], "%s come down to the player at %s within %.0f s" % [data.id, player_tile, REACH_LIMIT])
			player.queue_free()
			room.queue_free()
			await wait_physics_frames(2)


## #eba92e17 in its mode: enemies on the plateau sent after the lost villager (EnemyDecoy) come down
## the stairs to him, whatever slime it was.
func test_enemies_on_the_escort_plateau_come_down_to_the_villager() -> void:
	for data: EnemyData in [SLIME, SPLITTER, SKELETON]:
		var room := _room(ESCORT_ROOM, 6)
		var mode := EscortMode.attach(room, 6)
		assert_not_null(mode, "the escort mode fits its room")
		await wait_physics_frames(12)
		var player := _player(room, Vector2i(16, 6))
		var villager_tile := _tile(room, mode.villager)
		assert_eq(HeightRules.level_of(mode.villager), HeightRules.GROUND, "the villager waits on the ground at %s" % villager_tile)
		var enemies := _enemies(room, data, [Vector2i(8, 1), Vector2i(8, 2), Vector2i(5, 1), Vector2i(7, 2)] as Array[Vector2i])
		for enemy in enemies:
			EnemyDecoy.assign(enemy, mode.villager)
		mode.villager.set_max_hearts(999)
		var missing := await _never_reached(player, mode.villager, enemies, room)
		assert_eq(missing, [] as Array[String], "%s come down to the villager at %s within %.0f s" % [data.id, villager_tile, REACH_LIMIT])
		player.queue_free()
		room.queue_free()
		await wait_physics_frames(2)


## Two joined halls with a side passage (east exit of the first), its gate open and its rock built;
## null without side doors or terrain art.
func _side_passage() -> Door:
	var probe := (load(HALL) as PackedScene).instantiate() as RoomController
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
	await wait_process_frames(2)
	PassageSeam.join(first, second)
	var gate := GateCloser.gate_between(first)
	gate.set_open_instant(true)
	gate.view.build_lintel([first, second] as Array[Node2D])
	if gate.view.get_lintel().is_empty():
		return null
	return gate


func _hall(index: int, origin: Vector2i, entrance: Vector2i, exit: Vector2i) -> RoomController:
	var room := (load(HALL) as PackedScene).instantiate() as RoomController
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	room.setup(index, RoomSequence.RoomType.COMBAT, -1, false, context)
	room.apply_door_plan(entrance, [exit] as Array[Vector2i])
	room.position = Vector2(origin) * RoomTiles.TILE_WORLD
	add_child_autofree(room)
	return room


## Is the rock of the passage over the players (its deeper pieces on LINTEL_Z)?
func _rock_over(view: DoorView) -> bool:
	for piece in view.get_lintel():
		if bool(piece.get_meta(&"over_player", false)):
			return piece.z_index == DoorView.LINTEL_Z
	return false


## Puts the player's feet at a door-local point, lets him settle; his feet where they ended up.
func _feet_at(player: Player, gate: Door, local: Vector2) -> Vector2:
	player.global_position = gate.to_global(local) - Player.FEET_OFFSET
	await wait_physics_frames(4)
	await wait_process_frames(6)
	return gate.to_local(player.global_position + Player.FEET_OFFSET)


func test_rock_of_a_side_passage_lies_over_a_player_at_its_south_side() -> void:
	var gate := await _side_passage()
	if gate == null:
		pass_test("no side passage with terrain in this build")
		return
	var view := gate.view
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	for rect in view.get_passage_rects():
		var feet := await _feet_at(player, gate, Vector2(rect.get_center().x, rect.end.y - 2.0))
		assert_gt(feet.y, rect.end.y - 4.0, "the feet stay at the south side of the passage (%s)" % feet)
		assert_true(_rock_over(view), "the rock lies over a player at the south side of %s (#331603b8)" % rect)
		feet = await _feet_at(player, gate, Vector2(rect.get_center().x, rect.position.y + 2.0))
		assert_true(_rock_over(view), "and at its north side (feet %s)" % feet)


func test_rock_of_a_side_passage_cuts_a_player_at_its_edge_when_he_steps_out() -> void:
	var gate := await _side_passage()
	if gate == null:
		pass_test("no side passage with terrain in this build")
		return
	var view := gate.view
	var rects := view.get_passage_rects()
	var last: Rect2 = rects[rects.size() - 1]
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	# East exit: the room behind begins at the end of the last passage tile.
	var edge := last.end.x
	for step: float in [2.0, 8.0, DoorView.SIDE_EXIT_REACH - 2.0]:
		var feet := await _feet_at(player, gate, Vector2(edge + step, last.get_center().y))
		assert_almost_eq(feet.x, edge + step, 1.0, "the player stands %.0f px in the room behind" % step)
		assert_true(_rock_over(view), "%.0f px out of the passage his picture still reaches over the wall: the wall cuts it (#bcff6539)" % step)
	# Bug report 23.10.2026 #0bfc40e0 ("Mach den Tunnel einfach immer on top layer"): the tunnel's rock
	# stays over every figure when he has left it (it used to drop under the characters, G2 note 19).
	await _feet_at(player, gate, Vector2(edge + DoorView.SIDE_EXIT_REACH + 6.0, last.get_center().y))
	assert_true(_rock_over(view), "out of the passage the rock stays over the figures")
	await _feet_at(player, gate, Vector2(edge + 8.0, last.position.y - RoomTiles.TILE_WORLD * 0.5))
	assert_true(_rock_over(view), "beside the wall above the passage too")
	assert_eq(view.side_exit_rect(last).end.x, edge + DoorView.SIDE_EXIT_REACH, "the exit lane reaches SIDE_EXIT_REACH into the room")

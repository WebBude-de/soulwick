extends GutTest
## Long room chains (M2, playtest 14.10.2026 "kommt nicht in den nächsten Raum"): the real
## DungeonManager streams SLOTS slots for several seeds (branches made frequent, the first way taken).
## Live rooms never cover each other except two neighbours along their corridor; every exit leads
## through one corridor tile (plus a longer corridor's extra tiles) into the entrance of the next
## room, and neither room's rock lies on the other's floor or corridor (PassageSeam). The physics of
## the same rules is checked at runtime by tools/smoke_test.gd.

const DUNGEON: PackedScene = preload("res://dungeon/dungeon.tscn")
const SLOTS := 34
const SEEDS: Array[int] = [424242, 7311, 9157]

var _old_save_path: String
var _old_phase := 0


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_passage_chain_save.cfg"
	_old_phase = GameManager.get_phase()
	BranchRules.chance_override = 0.7


func after_all() -> void:
	BranchRules.chance_override = -1.0
	RunManager.end_run(RunManager.EndReason.DEATH)
	GameManager.set_phase(_old_phase as GameManager.Phase)
	SaveManager.save_path = _old_save_path


func test_long_chains_join_with_one_corridor_tile() -> void:
	for seed_value in SEEDS:
		var dungeon := DUNGEON.instantiate() as DungeonManager
		dungeon.seed_value = seed_value
		add_child(dungeon)
		await wait_physics_frames(2)
		var joins := 0
		for slot in range(2, SLOTS + 1):
			var before := dungeon.get_room_at_slot(slot - 1)
			var room := dungeon.get_room_at_slot(slot)
			if room == null and before != null and before.is_branch_room():
				before.choose_branch(0)
				room = dungeon.get_room_at_slot(slot)
			assert_not_null(room, "seed %d: slot %d prepared" % [seed_value, slot])
			if room == null or before == null:
				break
			joins += int(_check_join(seed_value, before, room))
			dungeon._on_player_entered_room(room)
			_check_live(seed_value, slot, dungeon)
		assert_eq(joins, SLOTS - 1, "seed %d: every transition checked" % seed_value)
		remove_child(dungeon)
		dungeon.free()
		await wait_physics_frames(1)


## The way from before into room: gate, one corridor tile (+ extra), floor; no foreign rock.
func _check_join(seed_value: int, before: RoomController, room: RoomController) -> bool:
	var exit := before.get_chosen_exit()
	var direction: Vector2i = RoomTiles.SIDE_DIRECTIONS[exit.x]
	var gate := DungeonManager.get_room_origin(before) + RoomTiles.door_tile_of(exit.x, exit.y, before.tiles.room_size)
	var inside := DungeonManager.get_room_origin(room) + room.tiles.get_entrance_inside_tile()
	var between := (inside - gate).x * direction.x + (inside - gate).y * direction.y - 1
	var label := "seed %d: %s -> %s" % [seed_value, before.name, room.name]
	assert_eq(inside - gate, direction * (between + 1), "%s: the entrance lines up with the gate" % label)
	assert_eq(between, 1 + room.tiles.entrance_corridor_extra, "%s: one corridor tile behind the gate" % label)
	assert_eq(_foreign_rock(room, before), [] as Array[Vector2i], "%s: floor of the new room free" % label)
	assert_eq(_foreign_rock(before, room), [] as Array[Vector2i], "%s: floor of the old room free" % label)
	return true


func _check_live(seed_value: int, slot: int, dungeon: DungeonManager) -> void:
	var rooms := dungeon.room_container.get_children()
	assert_lte(rooms.size(), dungeon.get_live_room_limit(), "seed %d slot %d: live rooms" % [seed_value, slot])
	for a in rooms.size():
		for b in range(a + 1, rooms.size()):
			var first := rooms[a] as RoomController
			var second := rooms[b] as RoomController
			if absi(first.slot_index - second.slot_index) == 1:
				continue
			assert_false(DungeonManager.rooms_clash(first, second), "seed %d slot %d: %s and %s apart" % [seed_value, slot, first.name, second.name])


## Walkable tiles of room (world) where other still paints something that is no floor of its own.
func _foreign_rock(room: RoomController, other: RoomController) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var origin := DungeonManager.get_room_origin(room)
	var other_origin := DungeonManager.get_room_origin(other)
	var other_rect := other.tiles.get_painted_rect()
	var other_floor := other.tiles.get_floor_mask()
	for tile: Vector2i in room.tiles.get_walkable_tiles():
		var in_other := tile + origin - other_origin
		if other_rect.has_point(in_other) and other.tiles.get_cell_source_id(in_other) != -1 and not other_floor.has(in_other):
			found.append(tile + origin)
	return found

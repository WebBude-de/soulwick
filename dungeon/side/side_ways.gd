class_name SideWays
extends RefCounted
## Where the dungeon runs through side segments (M5): the one call the room chain needs. For the way
## from a room to the next one it asks SideRules (after the campfire, the ladder way of a branch,
## 10 % after a rest room; never before the boss, never twice in a row, never when switched off),
## draws the layout of the next room's biome with the segment's own RNG (derived from the run seed
## and the slot, the dungeon stream stays untouched) and puts a SideGate into the corridor.
## DungeonManager hook: see the M5 report (_plan_side_way, _on_side_gate_passed).


## The gate for the way from room to next, or null when that way stays a plain corridor.
## previous_was_side: the way into room ran through a segment. ladder_way: the group took the
## ladder door of a branch.
static func plan(room: RoomController, next: RoomController, run_seed: int, previous_was_side: bool,
		ladder_way := false) -> SideGate:
	if room == null or next == null or not room.is_inside_tree():
		return null
	var rng := SideRules.make_rng(run_seed, next.slot_index)
	var reason := SideRules.roll_reason(room.is_campfire(), ladder_way, is_rest_room(room),
			next.room_type == RoomSequence.RoomType.BOSS, previous_was_side, is_skipped(), rng)
	if reason == SideRules.Reason.NONE:
		return null
	var biome_id := RoomCatalog.biome_id_for_room(next.room_index)
	var gate := SideGate.new()
	gate.name = "SideGate"
	gate.layout = SidePlans.pick(biome_id, rng)
	gate.reason = reason
	gate.from_room = room
	gate.next_room = next
	gate.rng_seed = rng.randi()
	room.add_child(gate)
	gate.cover(room.to_global(RoomTiles.tile_center(room.get_exit_tile())),
			next.to_global(RoomTiles.tile_center(next.get_entrance_tile())))
	return gate


## Rest rooms (shop, weapons, fountain, upgrade altar); the trial is no rest.
static func is_rest_room(room: RoomController) -> bool:
	return room.room_type == RoomSequence.RoomType.SPECIAL and room.special_type != RoomSequence.SpecialType.TRIAL


## "Seitenwege auslassen" (option of R8's menu, key SideRules.OPTION_SKIP).
static func is_skipped() -> bool:
	return bool(SaveManager.get_option(SideRules.OPTION_SKIP, false))

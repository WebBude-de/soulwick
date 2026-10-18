class_name SideWays
extends RefCounted
## Where the dungeon runs through side segments (M5): the one call the room chain needs. For the way
## from a room to the next one it asks SideRules (after the campfire, the ladder way of a branch,
## 18 % after a rest room (SideRules.AFTER_REST_CHANCE); never before the boss, never twice in a row, never when switched off),
## draws the layout of the next room's biome with the segment's own RNG (derived from the run seed
## and the slot, the dungeon stream stays untouched) and puts a SideGate into the corridor.
## DungeonManager: _plan_side_way (on entering a room, and for the chosen way of a branch with
## ladder_way = true for the ladder door), _on_side_gate_passed starts SideTransit; reason_for tells
## before a branch is rolled whether the way into it is a segment (no ladder door then).

## Test aid (net_run_smoke side=1): every way that may be a segment is one (same limits: never
## before the boss, never twice in a row). Set on every machine before the run. Never in the game.
static var force_for_tests := false


## The gate for the way from room to next, or null when that way stays a plain corridor.
## previous_was_side: the way into room ran through a segment. ladder_way: the group took the
## ladder door of a branch. skip: "Seitenwege auslassen" (in a group game the host's option decides).
static func plan(room: RoomController, next: RoomController, run_seed: int, previous_was_side: bool,
		ladder_way := false, skip := is_skipped()) -> SideGate:
	if room == null or next == null or not room.is_inside_tree():
		return null
	var rng := SideRules.make_rng(run_seed, next.slot_index)
	var reason := _roll(room, next, previous_was_side, ladder_way, skip, rng)
	if reason == SideRules.Reason.NONE:
		return null
	var biome_id := RoomCatalog.biome_id_for_room(next.room_index)
	var gate := SideGate.new()
	gate.name = "SideGate"
	# The ladder way always brings its chest: only plans with a niche (the same draws).
	gate.layout = SidePlans.pick(biome_id, rng, SideRules.has_chest(reason))
	gate.layout.chest_enabled = SideRules.has_chest(reason)
	gate.reason = reason
	gate.from_room = room
	gate.next_room = next
	gate.rng_seed = rng.randi()
	room.add_child(gate)
	gate.cover(room.to_global(RoomTiles.tile_center(room.get_exit_tile())),
			next.to_global(RoomTiles.tile_center(next.get_entrance_tile())))
	return gate


## Why the way from room to next runs through a segment (Reason.NONE: a plain corridor), the same
## answer plan() gives later: the segment's RNG comes from the run seed and the slot, so it can be
## asked before the rooms are in the tree (DungeonManager: may a branch behind next show a ladder
## door; never two segments in a row).
static func reason_for(room: RoomController, next: RoomController, run_seed: int, previous_was_side: bool,
		ladder_way := false, skip := is_skipped()) -> SideRules.Reason:
	if room == null or next == null:
		return SideRules.Reason.NONE
	return _roll(room, next, previous_was_side, ladder_way, skip, SideRules.make_rng(run_seed, next.slot_index))


static func _roll(room: RoomController, next: RoomController, previous_was_side: bool, ladder_way: bool, skip: bool,
		rng: RandomNumberGenerator) -> SideRules.Reason:
	var next_is_boss := next.room_type == RoomSequence.RoomType.BOSS
	var reason := SideRules.roll_reason(room.is_campfire(), ladder_way, is_rest_room(room),
			next_is_boss, previous_was_side, skip, rng)
	if reason == SideRules.Reason.NONE and force_for_tests and SideRules.allows_ladder_way(next_is_boss, previous_was_side, skip):
		reason = SideRules.Reason.AFTER_REST
	return reason


## Rest rooms (shop, weapons, fountain, upgrade altar); the trial is no rest.
static func is_rest_room(room: RoomController) -> bool:
	return room.room_type == RoomSequence.RoomType.SPECIAL and room.special_type != RoomSequence.SpecialType.TRIAL


## "Seitenwege auslassen" (option of R8's menu, key SideRules.OPTION_SKIP).
static func is_skipped() -> bool:
	return bool(SaveManager.get_option(SideRules.OPTION_SKIP, false))

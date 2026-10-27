class_name SoulGateRules
extends RefCounted
## Pure rules of the extraction (KE3, KONZEPT §2, D-194 point 1, D-196 point 3): what the soul gate
## pays and shows, how far the next gate is, and the hooks for the Proviant of KE5 (return stone,
## soul anchor). Where gates stand is RoomSequence.roll_portal (place 4) plus the campfire
## (DungeonManager.CAMPFIRE_EXIT_PORTAL). No nodes, fully unit-testable.

## Proviant ids as proposed for KE5 (MetaProgression decides the final ids there).
const SOUL_ANCHOR_BOOST: StringName = &"soul_anchor"
const RETURN_STONE_BOOST: StringName = &"return_stone"
## TESTWERT (D-196 point 3): death and abort pay this much with the soul anchor instead of
## RunManager.LOSS_PAYOUT_RATIO (25 %).
const SOUL_ANCHOR_PAYOUT_RATIO := 0.5


## Ratio of the run gold and crystals paid on death or abort; the soul anchor raises it (KE5 hook).
static func loss_payout_ratio(has_soul_anchor: bool) -> float:
	return SOUL_ANCHOR_PAYOUT_RATIO if has_soul_anchor else RunManager.LOSS_PAYOUT_RATIO


## Payout of remaining (gold or crystals) for an end reason, like RunManager.calculate_payout but
## with the soul anchor: the gate pays everything, a loss the ratio rounded up (D-062). Hook for the
## integrator: RunManager.calculate_payout(x, reason) -> payout(x, reason, has_run_boost(SOUL_ANCHOR_BOOST)).
static func payout(remaining: int, reason: int, has_soul_anchor := false) -> int:
	if remaining <= 0:
		return 0
	if reason == RunManager.EndReason.EXIT:
		return remaining
	return ceili(remaining * loss_payout_ratio(has_soul_anchor))


## "Jetzt sichern": gold and crystals the gate pays right now, danger loot bonus included (D-197),
## exactly what RunManager.end_run(EXIT) books. x = gold, y = crystals.
static func secure_amounts(run_gold: int, run_crystals: int, danger: int) -> Vector2i:
	return Vector2i(EconomySystem.apply_danger_loot(maxi(0, run_gold), danger),
			EconomySystem.apply_danger_loot(maxi(0, run_crystals), danger))


## "Weiter": depth bonus of the next five-room block in whole percent (gate in room 4: rooms 6-10
## give +10 %; campfire after room 15: rooms 16-20 give +30 %).
static func onward_bonus_percent(room_index: int) -> int:
	var next_block_room := (EnemyScaling.get_block(maxi(1, room_index)) + 1) * EnemyScaling.ROOMS_PER_BLOCK + 1
	return EconomyConfig.depth_bonus_percent(next_block_room)


## Rooms until the next place a gate can stand (place 4 of a cycle, or the campfire behind a boss
## room when campfire_gate), counted from room_index; "frühestens", as place 4 rolls (RoomSequence).
## A campfire counts with its boss room's number: gate in room 14 -> 1 (campfire after 15),
## campfire after 15 -> 4 (room 19), room 4 -> 5.
static func rooms_to_next_gate(room_index: int, campfire_gate := true) -> int:
	for next in range(maxi(0, room_index) + 1, maxi(0, room_index) + 1 + RoomSequence.CYCLE_LENGTH):
		var room_type := RoomSequence.get_room_type(next)
		if room_type == RoomSequence.RoomType.SPECIAL or (campfire_gate and room_type == RoomSequence.RoomType.BOSS):
			return next - room_index
	return RoomSequence.CYCLE_LENGTH


## Return stone (KE5 hook, KONZEPT §2): once per run it opens a gate anywhere, but not while a boss,
## champion or arena fight is running and not where a gate stands already. The host asks this and
## then calls room.spawn_exit_portal() (D-126: only over the host, the clients get the event).
static func can_open_return_gate(room: RoomController, already_used: bool) -> bool:
	if already_used or room == null or not is_instance_valid(room) or room.has_portal:
		return false
	if room.state == RoomController.State.PREPARED or room.state == RoomController.State.UNLOADED:
		return false
	return room.state == RoomController.State.CLEARED or not is_big_fight(room)


## Boss, champion (miniboss) and arena rooms: the return stone waits until they are cleared.
static func is_big_fight(room: RoomController) -> bool:
	return room.room_type == RoomSequence.RoomType.BOSS or room.room_type == RoomSequence.RoomType.MINIBOSS \
			or room.is_arena_room()

class_name WaveRules
extends RefCounted
## Pure rules of enemy waves (A5, KONZEPT_RAEUME 3.1, D-086 overflow). No nodes, unit-testable.
## Arena rooms (RoomKind.ARENA, D-100) fight 2-3 waves; the next wave comes as soon as at most
## NEXT_WAVE_AT_REMAINING enemies of the running wave are left. Normal combat rooms keep their
## waves (D-074) and wait until the running wave is cleared. Overflow: more enemies than spawn
## places -> the rest arrives as an extra wave.

## Earlier rooms are normal combat rooms only (D-100). TESTWERT (D-118: 6 -> 10, playtest; keep equal
## to RoomSequence.CHASM_FROM_ROOM, where the room kind draw starts)
const ARENA_FROM_ROOM := 10
## Waves of an arena: two, three from ARENA_DEEP_FROM_ROOM (TESTWERTE). Never fewer than the
## waves a normal room of the same depth already has (D-074).
const ARENA_WAVES := 2
const ARENA_WAVES_DEEP := 3
const ARENA_DEEP_FROM_ROOM := 30  # TESTWERT (D-118: 15 -> 30, like the second wave of normal rooms)
## An arena wave of one would call the next wave at once. TESTWERT (D-118: 2 -> 3)
const ARENA_MIN_WAVE_SIZE := 3
## Each arena wave rolls the normal count of the room (D-074) times this factor, never below the
## smallest normal count: an arena fights 2-3 such waves, so it stays harder than a normal room
## without doubling it. TESTWERT (D-118: 0.75 -> 1.0, playtest: the arena is the busy room)
const ARENA_WAVE_SIZE_FACTOR := 1.0
## Arena: the next wave starts when at most this many enemies of the running wave are left.
## TESTWERT (D-118: 1 -> 0, playtest: the next wave only once the running one is cleared)
const NEXT_WAVE_AT_REMAINING := 0
## Share of arenas that are an ambush. 0 since D-120 (Raeume v2: no ambush any more; enemies come out
## of visible sources, R2). Kept with the roll until the cleanup removes the ambush texts and tools.
const AMBUSH_CHANCE := 0.0
## No enemy steps out of a wall closer than this to any player (KONZEPT_RAEUME 3.1). TESTWERT
const MIN_PLAYER_DISTANCE := 96.0
## Enemies of one wave come from at least this many walls; an ambush from (almost) all. TESTWERTE
const MIN_SIDES := 2
const AMBUSH_MIN_SIDES := 3

## Banner name and one-line explanation for the first-time card (UX2, D-110), as translation keys
## (D-111, rows for localization/translations.csv are proposed in the A5 report). Shown by the UI,
## not by the room (RoomController.arena_started, is_arena_room, is_ambush_room). INTRO_GENRE_*
## are the genres for SaveManager.has_seen("room_intro_<genre>").
const ARENA_TITLE := &"ROOM_ARENA_TITLE"
const ARENA_INTRO_TEXT := &"ROOM_ARENA_INTRO"
const AMBUSH_TITLE := &"ROOM_AMBUSH_TITLE"
const AMBUSH_INTRO_TEXT := &"ROOM_AMBUSH_INTRO"
const INTRO_GENRE_ARENA := &"arena"
const INTRO_GENRE_AMBUSH := &"ambush"


## Is this room fought as an arena with waves from the walls?
static func is_arena(room_type: RoomSequence.RoomType, room_kind: int, room_index: int) -> bool:
	return RoomSequence.is_normal_combat(room_type) and room_kind == RoomSequence.RoomKind.ARENA and room_index >= ARENA_FROM_ROOM


## Rolled waves of a combat room before any overflow wave.
static func get_wave_count(room_index: int, arena: bool) -> int:
	var waves := RoomSequence.get_wave_count(room_index)
	if arena:
		waves = maxi(waves, ARENA_WAVES_DEEP if room_index >= ARENA_DEEP_FROM_ROOM else ARENA_WAVES)
	return waves


## Enemy count of one wave from the rolled count of the room (EnemySpawner.roll_enemy_count).
## smallest: lower end of the room's normal count range (RoomSequence.get_enemy_count_range).
## fixed_count: the count comes from room data (EncounterGroup.count_range) and is kept as it is.
static func get_wave_size(rolled: int, arena: bool, smallest := 1, fixed_count := false) -> int:
	if not arena or fixed_count:
		return rolled
	return maxi(maxi(ARENA_MIN_WAVE_SIZE, smallest), roundi(rolled * ARENA_WAVE_SIZE_FACTOR))


## May the next wave come while alive_in_wave enemies of the running wave are still alive?
static func should_start_next_wave(alive_in_wave: int, arena: bool) -> bool:
	return alive_in_wave <= (NEXT_WAVE_AT_REMAINING if arena else 0)


## Ambush or plain arena (always plain since D-120). Draws exactly one random number of the RNG.
static func roll_ambush(rng: RandomNumberGenerator) -> bool:
	return rng.randf() < AMBUSH_CHANCE


## Overflow (D-086): every rolled wave larger than the spawn places of one wave (capacity) is
## split, the rest follows as an extra wave right behind it. [6, 3] with capacity 5 -> [5, 1, 3].
static func plan_wave_sizes(rolled_counts: Array[int], capacity: int) -> Array[int]:
	var sizes: Array[int] = []
	for count in rolled_counts:
		sizes.append_array(RoomSequence.split_into_waves(count, capacity))
	return sizes


## Room-local positions of all living players (coop: every player counts, D-088).
static func get_player_positions(room: Node2D) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if room == null or not room.is_inside_tree():
		return positions
	for node in room.get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player != null and is_instance_valid(player) and player.is_alive():
			positions.append(room.to_local(player.global_position))
	return positions


## Distance from local_pos to the nearest of the given player positions (INF without players).
static func distance_to_nearest(local_pos: Vector2, player_positions: Array[Vector2]) -> float:
	var best := INF
	for player_pos in player_positions:
		best = minf(best, local_pos.distance_to(player_pos))
	return best

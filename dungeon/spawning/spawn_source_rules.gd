class_name SpawnSourceRules
extends RefCounted
## Pure rules of enemy sources (R2, RAEUME §5, design answer 03_gegner_auftritt.md):
## which sources one push uses and when each enemy comes out. No nodes, unit-testable.
## SpawnSources applies the rules to a room, SpawnSource and Enemy.begin_emerge show them.
##
## Marker contract with the room plans (R1): the room has a node "Sources" with Marker2D children;
## meta "source_kind" is one of KIND_IDS. Gates and wall rifts also carry meta "wall_side"
## (SIDE_IDS or 0-3 like RoomTiles.DoorSide): the wall the opening sits in, seen from the floor tile
## in front of it - a gate in the north wall is "north", its enemies step out southwards; optional
## "tile" (wall tile) and "floor_tile" (Vector2i) name the tiles directly. Floor sources ignore
## wall_side (the R1 generator writes -1).

enum Kind { GRAVE, SARCOPHAGUS, PUDDLE, RIFT, VENT, GATE, RIFT_WALL }

const KIND_IDS: Array[StringName] = [&"grave", &"sarcophagus", &"puddle", &"rift", &"vent", &"gate", &"rift_wall"]
const SIDE_IDS: Array[StringName] = [&"north", &"east", &"south", &"west"]
## Floor source of each biome (BiomeData.id) for rooms without markers: the old spawn points
## become sources of this kind.
const BIOME_KINDS := {
	&"crypt": Kind.GRAVE,
	&"slime_grotto": Kind.PUDDLE,
	&"shadow_realm": Kind.RIFT,
	&"ember_forge": Kind.VENT,
}
## Sounds (R9 generates them; missing files stay silent).
const SOUNDS := {
	Kind.GRAVE: &"spawn_grave",
	Kind.SARCOPHAGUS: &"spawn_sarcophagus",
	Kind.PUDDLE: &"spawn_puddle",
	Kind.RIFT: &"spawn_rift",
	Kind.VENT: &"spawn_vent",
	Kind.GATE: &"spawn_gate",
	Kind.RIFT_WALL: &"spawn_rift",
}

## Seconds of warning (light, sound, animation) before the first enemy of a source comes out.
## TESTWERT (design answer: 1 s)
const WARN_TIME := 1.0
## Seconds an enemy needs to come out (passive and invulnerable). TESTWERT
const EMERGE_TIME := 0.5
## Enemies sharing one source come one after the other. TESTWERT
const SAME_SOURCE_DELAY := 0.6
## The sources of one push light up one after the other, never all in the same instant. TESTWERT
const SOURCE_STAGGER := 0.2
## No enemy comes out of the floor closer than this to any living player (px). TESTWERT
const MIN_PLAYER_DISTANCE := 160.0
## Wall gates: the enemy steps one tile into the room (px, A5 value). TESTWERT
const GATE_MIN_PLAYER_DISTANCE := 96.0
## One source brings at most this many enemies per push (they queue). TESTWERT
const PER_SOURCE := 2
## Share of a room's sources one push may use at most - never all of them. TESTWERT
const MAX_ACTIVE_SHARE := 0.6
## A push of several enemies comes out of at least this many sources (when it has that many
## enemies and the room the sources): "von mehreren Seiten". TESTWERT
const MIN_SOURCES_PER_PUSH := 3
## Pushes out of wall gates spread over at least this many walls (when the room has them).
const MIN_WALLS := 2
## Gates of an arena without gate markers (fallback in the outer walls). TESTWERT (plan: 6 gates)
const ARENA_GATE_COUNT := 6
## Preference by direction seen from the nearest player: behind it, beside it, in front of it.
## TESTWERTE (RAEUME §5: "meist hinter dem Spieler")
const WEIGHT_BEHIND := 3.0
const WEIGHT_SIDE := 2.0
const WEIGHT_FRONT := 1.0
## dot(front, direction to the source) at or below BEHIND_DOT = behind, at or above FRONT_DOT = in front.
const BEHIND_DOT := -0.3
const FRONT_DOT := 0.3
## Random share of a source's score: weight x (JITTER_FLOOR + 0..1), so a source in front still
## gets a turn now and then and the pattern does not become predictable. TESTWERT
const JITTER_FLOOR := 0.35
## Queued enemies of one floor source stand a little apart (px), so they do not overlap.
const QUEUE_SPREAD := 14.0


## Kind of a marker id ("grave", ...); -1 for an unknown id.
static func kind_from_id(id: Variant) -> int:
	if id is int:
		return id if id >= 0 and id < KIND_IDS.size() else -1
	return KIND_IDS.find(StringName(str(id).strip_edges().to_lower()))


static func kind_id(kind: int) -> StringName:
	return KIND_IDS[kind] if kind >= 0 and kind < KIND_IDS.size() else &""


## Wall side of a marker (meta "wall_side"): "north"/"east"/"south"/"west" or 0-3; -1 if unknown.
static func side_from_meta(value: Variant) -> int:
	if value is int:
		return value if value >= 0 and value < SIDE_IDS.size() else -1
	if value is float:
		return side_from_meta(roundi(value))
	if value == null:
		return -1
	var text := str(value).strip_edges().to_lower()
	if text.is_valid_int():
		return side_from_meta(text.to_int())
	return SIDE_IDS.find(StringName(text))


## Floor source of a biome; graves for an unknown biome.
static func biome_kind(biome_id: StringName) -> int:
	return BIOME_KINDS.get(biome_id, Kind.GRAVE)


## Gates and wall rifts sit in a wall; the enemy steps out onto the floor tile in front of them.
static func is_wall_kind(kind: int) -> bool:
	return kind == Kind.GATE or kind == Kind.RIFT_WALL


static func sound_for(kind: int) -> StringName:
	return SOUNDS.get(kind, &"spawn_grave")


## Sources one push may use at most out of source_count: never all of three or more (at most
## MAX_ACTIVE_SHARE, at least two); a room with one or two sources uses them all ("mehrere" wins).
static func max_active(source_count: int) -> int:
	if source_count <= 2:
		return maxi(0, source_count)
	return mini(source_count - 1, maxi(2, ceili(source_count * MAX_ACTIVE_SHARE)))


## Enemies one push of a room with source_count sources brings without queueing more than
## PER_SOURCE at a source (SpawnSources.get_capacity never goes below the room's spawn points).
static func capacity(source_count: int) -> int:
	return max_active(source_count) * PER_SOURCE


## Sources a push of count enemies uses: enough for PER_SOURCE each and at least
## MIN_SOURCES_PER_PUSH ("mehrere Quellen"), at most max_active(total) and the usable ones.
static func sources_for(count: int, usable: int, total: int) -> int:
	if count <= 0 or usable <= 0:
		return 0
	var wanted := maxi(ceili(float(count) / PER_SOURCE), mini(MIN_SOURCES_PER_PUSH, count))
	return clampi(wanted, 1, mini(maxi(1, max_active(total)), usable))


## Preference of a source at spot: behind the nearest player (opposite its front), beside it or
## in front of it. A player without a known front counts as "beside" (neutral).
static func direction_weight(spot: Vector2, players: Array[Vector2], fronts: Array[Vector2]) -> float:
	var nearest := -1
	var best := INF
	for i in players.size():
		var distance := spot.distance_squared_to(players[i])
		if distance < best:
			best = distance
			nearest = i
	if nearest < 0 or nearest >= fronts.size() or fronts[nearest].length_squared() < 0.0001:
		return WEIGHT_SIDE
	var to_spot := spot - players[nearest]
	if to_spot.length_squared() < 0.0001:
		return WEIGHT_SIDE
	var dot := to_spot.normalized().dot(fronts[nearest].normalized())
	if dot <= BEHIND_DOT:
		return WEIGHT_BEHIND
	if dot >= FRONT_DOT:
		return WEIGHT_FRONT
	return WEIGHT_SIDE


## One push of count enemies: returns count source indices (a source repeats when its enemies
## queue). spots: room-local places of the sources; groups: wall side per source (-1 = floor
## source) - a push out of walls spreads over MIN_WALLS walls first; players/fronts: living players
## (room-local) and their facing (zero = unknown); last_used: sources of the previous push, used only
## when the others do not suffice ("jede Welle andere Tore"). Sources closer than min_distance to
## any player are skipped; if none is left, the farthest one still serves.
## Draws exactly spots.size() random numbers, however the players stand (stable RNG stream).
static func pick(spots: Array[Vector2], groups: Array[int], count: int, players: Array[Vector2], fronts: Array[Vector2], last_used: Array[int], min_distance: float, rng: RandomNumberGenerator) -> Array[int]:
	var slots: Array[int] = []
	var total := spots.size()
	if total == 0 or count <= 0:
		return slots
	var jitter: Array[float] = []
	for i in total:
		jitter.append(rng.randf())
	var usable: Array[int] = []
	for i in total:
		if WaveRules.distance_to_nearest(spots[i], players) >= min_distance:
			usable.append(i)
	if usable.is_empty():
		usable.append(farthest(spots, players))
	var scores: Dictionary = {}
	for i in usable:
		scores[i] = direction_weight(spots[i], players, fronts) * (JITTER_FLOOR + jitter[i])
	var fresh: Array[int] = []
	var stale: Array[int] = []
	for i in usable:
		if last_used.has(i):
			stale.append(i)
		else:
			fresh.append(i)
	var by_score := func(a: int, b: int) -> bool:
		if not is_equal_approx(scores[a], scores[b]):
			return scores[a] > scores[b]
		return a < b
	fresh.sort_custom(by_score)
	stale.sort_custom(by_score)
	var wanted := sources_for(count, usable.size(), total)
	var chosen: Array[int] = []
	# Walls first: the best fresh source of each wall, until MIN_WALLS walls are in.
	var walls: Dictionary = {}
	for i in fresh:
		if chosen.size() >= wanted or walls.size() >= MIN_WALLS:
			break
		var group: int = groups[i] if i < groups.size() else -1
		if group >= 0 and not walls.has(group):
			walls[group] = true
			chosen.append(i)
	for list: Array[int] in [fresh, stale]:
		for i in list:
			if chosen.size() >= wanted:
				break
			if not chosen.has(i):
				chosen.append(i)
	for slot in count:
		slots.append(chosen[slot % chosen.size()])
	return slots


## Height (M3b, D-189, Projektmitglied 18.10.2026): sources on a plateau with stairs serve ranged
## enemies first ("Druck von oben"), close-combat enemies come out on the ground. slots: source index
## per enemy (pick); ranged: per enemy; high: per source (on a plateau surface); open: sources a push
## may add (usable: far enough from every player); max_sources: distinct sources a push may use at
## most (max_active). Three steps, no randomness, the order of the enemies decides:
##   1. a ranged enemy on the ground swaps with a close-combat enemy on a plateau;
##   2. ranged enemies left on the ground move up to a plateau source with room (fewer than
##      PER_SOURCE there), one already in use first, else an open one while the push stays within
##      max_sources;
##   3. close-combat enemies left on a plateau move down to a ground source of the push with room.
## What finds no room stays (a plateau has stairs: its enemies walk down). Returns the new slots.
static func sort_by_height(slots: Array[int], ranged: Array[bool], high: Array[bool], open: Array[int], max_sources: int) -> Array[int]:
	var result: Array[int] = slots.duplicate()
	if not high.has(true) or result.is_empty():
		return result
	# 1. Swaps keep every source's load.
	for i in result.size():
		if not _is_flag(ranged, i) or _is_flag(high, result[i]):
			continue
		for j in result.size():
			if not _is_flag(ranged, j) and _is_flag(high, result[j]):
				var swap := result[i]
				result[i] = result[j]
				result[j] = swap
				break
	# 2. Ranged enemies up.
	for i in result.size():
		if _is_flag(ranged, i) and not _is_flag(high, result[i]):
			var target := _source_with_room(result, i, high, true, open, max_sources)
			if target >= 0:
				result[i] = target
	# 3. Close-combat enemies down (only to ground sources the push already uses).
	for i in result.size():
		if not _is_flag(ranged, i) and _is_flag(high, result[i]):
			var target := _source_with_room(result, i, high, false, [] as Array[int], 0)
			if target >= 0:
				result[i] = target
	return result


## A source of the wanted height for the enemy at index mover with fewer than PER_SOURCE other
## enemies of slots: the least loaded one in use (lowest index on a tie), else the first of extra
## while the others use fewer than max_sources distinct sources; -1 if none.
static func _source_with_room(slots: Array[int], mover: int, high: Array[bool], want_high: bool, extra: Array[int], max_sources: int) -> int:
	var counts: Dictionary[int, int] = {}
	for i in slots.size():
		if i != mover:
			counts[slots[i]] = counts.get(slots[i], 0) + 1
	var best := -1
	var keys: Array[int] = []
	keys.assign(counts.keys())
	keys.sort()
	for source in keys:
		if _is_flag(high, source) != want_high or counts[source] >= PER_SOURCE:
			continue
		if best < 0 or counts[source] < counts[best]:
			best = source
	if best >= 0 or counts.size() >= max_sources:
		return best
	for source in extra:
		if _is_flag(high, source) == want_high and not counts.has(source):
			return source
	return -1


static func _is_flag(flags: Array[bool], index: int) -> bool:
	return index >= 0 and index < flags.size() and flags[index]


## Index of the spot farthest from every player (the first one without players).
static func farthest(spots: Array[Vector2], players: Array[Vector2]) -> int:
	var best := 0
	var best_distance := -1.0
	for i in spots.size():
		var distance := WaveRules.distance_to_nearest(spots[i], players)
		if distance > best_distance:
			best_distance = distance
			best = i
	return best


## Seconds from the start of a push until the source with the given order (0 = first) begins to
## warn.
static func warn_start(order: int, start_delay := 0.0) -> float:
	return start_delay + maxi(0, order) * SOURCE_STAGGER


## Seconds from the start of a push until the place-th enemy (0 = first) of the source with the
## given order begins to come out; it fights EMERGE_TIME later.
static func emerge_start(order: int, place: int, start_delay := 0.0) -> float:
	return warn_start(order, start_delay) + WARN_TIME + maxi(0, place) * SAME_SOURCE_DELAY


## Seconds until every enemy of a push is out: sources sources, at most per_source enemies each.
static func release_time(sources: int, per_source: int, start_delay := 0.0) -> float:
	return emerge_start(maxi(1, sources) - 1, maxi(1, per_source) - 1, start_delay) + EMERGE_TIME


## Offset of the place-th enemy of a floor source: 0, right, left, further right, ...
static func queue_offset(place: int) -> Vector2:
	if place <= 0:
		return Vector2.ZERO
	var step := ceili(place / 2.0)
	var direction := 1.0 if place % 2 == 1 else -1.0
	return Vector2(direction * QUEUE_SPREAD * step, 4.0)

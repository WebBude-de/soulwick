class_name SoulsRules
extends RefCounted
## Rules of the minigame "Seelen sammeln" (KONZEPT_RAEUME_V2 §3.6, design answer 01_raumarten.md,
## R4a): the numbers (TESTWERTE) and the pure decisions - where the souls appear, when the next one
## comes, how many crystals a count is worth. No nodes, no effects: SoulsMode applies them.

const ID: StringName = &"souls"
## Plan mode of the templates made for it (RoomTemplate.mode, plan header "mode: souls").
const PLAN_MODE: StringName = &"souls"
## First room the mode may appear in (Zyklus 3, KONZEPT_RAEUME_V2 §2). TESTWERT
const MIN_ROOM := 11
## Share among the minigames of a draw (R4b mode table). TESTWERT
const WEIGHT := 1.0
## Objective marker of the plan (cell '*'): a fixed place a soul appears at.
const SPOT_MARKER: StringName = &"soul"

## Souls of a round, one after another, each at its own fixed place. TESTWERT
const SOUL_COUNT := 12
## Time of the round (s). TESTWERT
const TIME_LIMIT := 45.0
## A soul stays this long, then it fades (s). TESTWERT
const SOUL_LIFETIME := 6.0
## A new soul every SPAWN_INTERVAL s (12 × 3.5 s: the last one still fits into the time); when none
## is left to take, the next comes after EMPTY_GAP s already (quick players get them sooner). TESTWERTE
const SPAWN_INTERVAL := 3.5
const EMPTY_GAP := 0.8
const FIRST_DELAY := 0.4
## A player takes a soul with the feet this close to its place (px). TESTWERT
const COLLECT_RADIUS := 40.0
## Every soul taken lets the sources spit enemies, one push per beat (Takt) while any are owed and
## fewer than PUSH_MAX_ALIVE are up. TESTWERTE
const ENEMIES_PER_SOUL := 1
const PUSH_BEAT := 1.5
const PUSH_MAX_ALIVE := 8
## The room's own encounter times this: the souls bring the rest. TESTWERT
const ENCOUNTER_FACTOR := 0.6
## Soul crystals by count (taken -> crystals), highest first. Less than the last = no bonus. TESTWERTE
const CRYSTAL_STEPS: Array[Vector2i] = [Vector2i(12, 3), Vector2i(9, 2), Vector2i(6, 1)]
## The bar turns red for the last seconds.
const DANGER_TIME := 10.0
## Places the plan does not have are filled from free floor, this far from every door (tiles).
const DOOR_CLEARANCE := 2.5
## Souls flickering during the intro (design answer: "Kamera zeigt drei Seelen aufflackern").
const PREVIEW_COUNT := 3


## Soul crystals for count souls taken (0 = no bonus).
static func crystals_for(count: int) -> int:
	for step in CRYSTAL_STEPS:
		if count >= step.x:
			return step.y
	return 0


## May the next soul appear now? clock: seconds of the round; next_at: planned time; spawned: souls
## out so far.
static func should_spawn(clock: float, next_at: float, spawned: int) -> bool:
	return spawned < SOUL_COUNT and clock < TIME_LIMIT and clock >= next_at


## Planned time of the next soul after one appeared at clock.
static func next_after_spawn(clock: float) -> float:
	return clock + SPAWN_INTERVAL


## None left to take: the next one comes sooner (never later than planned).
static func next_when_empty(clock: float, planned: float) -> float:
	return minf(planned, clock + EMPTY_GAP)


## The round is over: time up, or every soul came and none is left.
static func is_round_over(clock: float, spawned: int, visible: int) -> bool:
	return clock >= TIME_LIMIT or (spawned >= SOUL_COUNT and visible <= 0)


static func is_taken(feet_distance: float) -> bool:
	return feet_distance <= COLLECT_RADIUS


static func should_push(since_last_push: float, owed: int, alive: int) -> bool:
	return owed > 0 and since_last_push >= PUSH_BEAT and alive < PUSH_MAX_ALIVE


## count places: the plan's own first (in their order), the rest from candidates, each as far as
## possible from all places chosen so far (ties: tile order), DOOR_CLEARANCE from every tile in avoid.
static func fill_spots(plan_spots: Array[Vector2i], candidates: Array[Vector2i], count: int, avoid: Array[Vector2i] = []) -> Array[Vector2i]:
	var spots: Array[Vector2i] = []
	for tile in plan_spots:
		if spots.size() >= count:
			break
		if not spots.has(tile):
			spots.append(tile)
	var pool: Array[Vector2i] = []
	for tile in candidates:
		if spots.has(tile) or _distance_to(tile, avoid) < DOOR_CLEARANCE:
			continue
		pool.append(tile)
	pool.sort_custom(_tile_before)
	while spots.size() < count and not pool.is_empty():
		var best_index := -1
		var best_distance := -1.0
		for i in pool.size():
			var distance := _distance_to(pool[i], spots)
			if distance > best_distance + 0.0001:
				best_distance = distance
				best_index = i
		if best_index < 0:
			break
		spots.append(pool.pop_at(best_index))
	return spots


## The order the places light up in: a shuffle with the mode's RNG (one draw per place).
static func shuffled_order(count: int, rng: RandomNumberGenerator) -> Array[int]:
	var order: Array[int] = []
	for i in count:
		order.append(i)
	for i in range(count - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := order[i]
		order[i] = order[j]
		order[j] = swap
	return order


static func _distance_to(tile: Vector2i, others: Array[Vector2i]) -> float:
	var nearest := INF
	for other in others:
		nearest = minf(nearest, Vector2(tile - other).length())
	return nearest


static func _tile_before(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)

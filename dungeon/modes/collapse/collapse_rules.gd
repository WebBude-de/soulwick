class_name CollapseRules
extends RefCounted
## Rules of the minigame "Einsturz" (RAEUME §3.10, design answer 01_raumarten.md, R4a):
## the numbers (TESTWERTE) and the pure decisions - which floor breaks in which order, when, and
## which way stays. No nodes, no effects: CollapseMode applies them.
## The order is fixed per room (seeded): the floor breaks in fields of 2×2 tiles from the outside
## in - outside meaning far from the way that stays (the shortest way from the entrance to the exit,
## widened). A field never cuts floor off from that way: tiles it would leave as an island break
## with it, so every tile still standing can always be walked to the exit.

const ID: StringName = &"collapse"
## Plan mode of the templates made for it (RoomTemplate.mode, plan header "mode: collapse").
const PLAN_MODE: StringName = &"collapse"
## First room the mode may appear in (2. Biom, RAEUME §2). TESTWERT
const MIN_ROOM := 16
## Share among the minigames of a draw (R4b mode table). TESTWERT
const WEIGHT := 1.0
## Objective marker of the plan (cell 'X'): floor that already carries cracks; its field breaks
## first among the fields as far out.
const FIELD_MARKER: StringName = &"collapse_field"

## Survive this long (s, banner "überlebe 30 s"). TESTWERT
const DURATION := 30.0
## Cracks and red glow this long before a field breaks (s). TESTWERT
const WARN_TIME := 1.0
## The first field breaks at START_DELAY, the last END_CALM before the end. TESTWERTE
const START_DELAY := 1.5
const END_CALM := 2.0
## Fields marked as "next" (faint cracks, task bar). Design answer: "die nächsten 3 Felder".
const LOOKAHEAD := 3
## Edge of a field in tiles.
const FIELD_SIZE := 2
## The way that stays: the shortest way from entrance to exit plus this many tiles on each side
## (4-neighbours), and the first DOOR_DEPTH tiles in front of every door. TESTWERTE
const WAY_HALF_WIDTH := 1
const DOOR_DEPTH := 2
## The room's own encounter times this: vents push more while the floor breaks. TESTWERT
const ENCOUNTER_FACTOR := 0.7
## Pushes out of vents/sources still on solid floor: every PUSH_INTERVAL s from PUSH_FIRST to
## PUSH_LAST, PUSH_SIZE enemies, never while PUSH_MAX_ALIVE are up, at least
## PUSH_MIN_PLAYER_DISTANCE from every player. TESTWERTE
const PUSH_FIRST := 4.0
const PUSH_INTERVAL := 7.0
const PUSH_LAST := 22.0
const PUSH_SIZE := 2
const PUSH_MAX_ALIVE := 6
const PUSH_MIN_PLAYER_DISTANCE := 160.0
## Standing still does not pay (playtest 23.10.2026 #9c8ebbe0, "man steht einfach und wartet"): a
## player whose feet stay within STILL_RADIUS px for STILL_TIME s gets a sinkhole - the 2×2 plate
## under his feet cracks for WARN_TIME and gives way, also on the way that stays; it closes again
## after SINK_TIME s, so the way still stands at the end. Never on the floor around a plateau
## (height_guard, D-189), never in the last WARN_TIME s. Every player for himself. TESTWERTE
const STILL_TIME := 2.5
const STILL_RADIUS := 40.0
const SINK_TIME := 4.0

const DIRECTIONS_4: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
## Room thirds -> text key (row, column): north/middle/south × west/middle/east.
const COMPASS_KEYS: Array[StringName] = [
	&"COMPASS_NW", &"COMPASS_N", &"COMPASS_NE",
	&"COMPASS_W", &"COMPASS_CENTER", &"COMPASS_E",
	&"COMPASS_SW", &"COMPASS_S", &"COMPASS_SE",
]


## Times the fields break at (s after the start), evenly from START_DELAY to DURATION - END_CALM.
static func break_times(count: int) -> PackedFloat32Array:
	var times := PackedFloat32Array()
	if count <= 0:
		return times
	var span := DURATION - END_CALM - START_DELAY
	for i in count:
		times.append(START_DELAY + (span * i / float(count - 1) if count > 1 else 0.0))
	return times


static func should_warn(clock: float, break_at: float) -> bool:
	return clock >= break_at - WARN_TIME


static func should_break(clock: float, break_at: float) -> bool:
	return clock >= break_at


static func is_survived(clock: float) -> bool:
	return clock >= DURATION


static func should_push(clock: float, since_last_push: float, alive: int) -> bool:
	return clock >= PUSH_FIRST and clock <= PUSH_LAST and since_last_push >= PUSH_INTERVAL and alive < PUSH_MAX_ALIVE


## Has a player stood still long enough for a sinkhole (still_for: seconds within STILL_RADIUS)?
static func is_still_too_long(still_for: float) -> bool:
	return still_for >= STILL_TIME


## Is the feet position still the resting place (within STILL_RADIUS of where they came to rest)?
static func is_resting(anchor: Vector2, feet: Vector2) -> bool:
	return anchor.distance_to(feet) <= STILL_RADIUS


## May a sinkhole start at this time of the collapse (it has to open before the end)?
static func may_sink(clock: float) -> bool:
	return clock >= START_DELAY and clock < DURATION - WARN_TIME


## The 2×2 plate under the feet (room-local px): the feet tile and its neighbours on the side of the
## tile the feet stand on, so the hole lies around them. Only tiles of open (floor that may sink),
## sorted.
static func sinkhole_tiles(feet: Vector2, open: Dictionary[Vector2i, bool]) -> Array[Vector2i]:
	var tile := RoomTiles.local_to_tile(feet)
	var inside := feet - RoomTiles.tile_to_local(tile)
	var step := Vector2i(1 if inside.x >= RoomTiles.TILE_WORLD * 0.5 else -1, 1 if inside.y >= RoomTiles.TILE_WORLD * 0.5 else -1)
	var tiles: Array[Vector2i] = []
	for candidate: Vector2i in [tile, tile + Vector2i(step.x, 0), tile + Vector2i(0, step.y), tile + step]:
		if open.has(candidate):
			tiles.append(candidate)
	tiles.sort_custom(_tile_before)
	return tiles


## Shortest way over walkable tiles (4 directions, breadth first, neighbours in a fixed order, so the
## same room always gives the same way). Empty when goal cannot be reached.
static func shortest_way(walkable: Dictionary[Vector2i, bool], start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var way: Array[Vector2i] = []
	if not walkable.has(start) or not walkable.has(goal):
		return way
	var came_from: Dictionary[Vector2i, Vector2i] = {start: start}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var tile := queue[head]
		head += 1
		if tile == goal:
			break
		for direction in DIRECTIONS_4:
			var next := tile + direction
			if walkable.has(next) and not came_from.has(next):
				came_from[next] = tile
				queue.append(next)
	if not came_from.has(goal):
		return way
	var tile := goal
	way.append(tile)
	while tile != start:
		tile = came_from[tile]
		way.append(tile)
	way.reverse()
	return way


## The way plus half_width tiles of floor on each side (repeated 4-neighbour growth inside floor).
static func widen(way: Array[Vector2i], floor_tiles: Dictionary[Vector2i, bool], half_width: int) -> Dictionary[Vector2i, bool]:
	var kept: Dictionary[Vector2i, bool] = {}
	for tile in way:
		kept[tile] = true
	for i in half_width:
		var grown: Array[Vector2i] = []
		for tile: Vector2i in kept:
			for direction in DIRECTIONS_4:
				var next := tile + direction
				if floor_tiles.has(next) and not kept.has(next):
					grown.append(next)
		for tile in grown:
			kept[tile] = true
	return kept


## Height (M3b, D-186/D-189): floor within one tile (eight neighbours) of a plateau, its stairs or
## its ladder - it never breaks, so no abyss opens under or beside a cliff and the way up stays.
static func height_guard(height_tiles: Dictionary[Vector2i, bool], floor_tiles: Dictionary[Vector2i, bool]) -> Dictionary[Vector2i, bool]:
	var guard: Dictionary[Vector2i, bool] = {}
	for tile: Vector2i in height_tiles:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var next := tile + Vector2i(dx, dy)
				if floor_tiles.has(next) and not height_tiles.has(next):
					guard[next] = true
	return guard


## Joins every kept tile to start: a kept tile not reached from start over kept tiles gets the
## shortest way over walkable (itself counted as walkable) to the first reached kept tile, so the
## kept floor never holds an island. Changes kept.
static func join_kept(kept: Dictionary[Vector2i, bool], walkable: Dictionary[Vector2i, bool], start: Vector2i) -> void:
	var keys: Array[Vector2i] = []
	keys.assign(kept.keys())
	keys.sort_custom(_tile_before)
	for tile in keys:
		var reached := _reach_from(kept, start)
		if reached.has(tile):
			continue
		var open := walkable.duplicate()
		open[tile] = true
		for step in shortest_way(open, tile, start):
			if reached.has(step):
				break
			kept[step] = true


## The fields in the order they break. floor_tiles: every floor tile that may break or stays
## (no walls, no abyss); kept: the way that stays (never breaks); marked: plan tiles with cracks.
## rng: one draw per field (order among fields equally far out), the mode's RNG.
## Returns Array of Array[Vector2i]; every non-kept floor tile is in exactly one field.
static func build_fields(floor_tiles: Dictionary[Vector2i, bool], kept: Dictionary[Vector2i, bool], marked: Array[Vector2i], rng: RandomNumberGenerator) -> Array:
	var distance := _distances(floor_tiles, kept)
	var blocks: Dictionary[Vector2i, Array] = {}
	var block_keys: Array[Vector2i] = []
	var candidates: Array[Vector2i] = []
	for tile: Vector2i in floor_tiles:
		if not kept.has(tile):
			candidates.append(tile)
	candidates.sort_custom(_tile_before)
	for tile in candidates:
		var key := Vector2i(floori(tile.x / float(FIELD_SIZE)), floori(tile.y / float(FIELD_SIZE)))
		if not blocks.has(key):
			blocks[key] = []
			block_keys.append(key)
		blocks[key].append(tile)
	var entries: Array[Dictionary] = []
	for key in block_keys:
		var tiles: Array = blocks[key]
		var nearest := 1 << 20
		var has_mark := false
		for tile: Vector2i in tiles:
			nearest = mini(nearest, distance.get(tile, 1 << 20))
			has_mark = has_mark or marked.has(tile)
		entries.append({"tiles": tiles, "distance": nearest, "marked": has_mark, "roll": rng.randf()})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["distance"] != b["distance"]:
			return a["distance"] > b["distance"]
		if a["marked"] != b["marked"]:
			return a["marked"]
		return a["roll"] < b["roll"])
	# Islands break with the field that cut them off.
	var standing: Dictionary[Vector2i, bool] = {}
	for tile in candidates:
		standing[tile] = true
	var fields: Array = []
	for entry in entries:
		var field: Array[Vector2i] = []
		for tile: Vector2i in entry["tiles"]:
			if standing.has(tile):
				field.append(tile)
				standing.erase(tile)
		if field.is_empty():
			continue
		var reached := _reach(standing, kept)
		var cut_off: Array[Vector2i] = []
		for tile: Vector2i in standing:
			if not reached.has(tile):
				cut_off.append(tile)
		cut_off.sort_custom(_tile_before)
		for tile in cut_off:
			field.append(tile)
			standing.erase(tile)
		fields.append(field)
	return fields


## Text key of the room third a field lies in (room_size in tiles).
static func compass_key(field: Array[Vector2i], room_size: Vector2i) -> StringName:
	if field.is_empty():
		return &"COMPASS_CENTER"
	var center := Vector2.ZERO
	for tile in field:
		center += Vector2(tile) + Vector2(0.5, 0.5)
	center /= field.size()
	var column := clampi(floori(center.x / maxf(1.0, room_size.x / 3.0)), 0, 2)
	var row := clampi(floori(center.y / maxf(1.0, room_size.y / 3.0)), 0, 2)
	return COMPASS_KEYS[row * 3 + column]


## Room-local centre of a field (px).
static func field_center(field: Array[Vector2i]) -> Vector2:
	if field.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for tile in field:
		sum += RoomTiles.tile_center(tile)
	return sum / field.size()


## Steps (4 directions, over floor) from every floor tile to the nearest kept tile.
static func _distances(floor_tiles: Dictionary[Vector2i, bool], kept: Dictionary[Vector2i, bool]) -> Dictionary[Vector2i, int]:
	var distance: Dictionary[Vector2i, int] = {}
	var queue: Array[Vector2i] = []
	var sorted_kept: Array[Vector2i] = []
	sorted_kept.assign(kept.keys())
	sorted_kept.sort_custom(_tile_before)
	for tile in sorted_kept:
		distance[tile] = 0
		queue.append(tile)
	var head := 0
	while head < queue.size():
		var tile := queue[head]
		head += 1
		for direction in DIRECTIONS_4:
			var next := tile + direction
			if floor_tiles.has(next) and not distance.has(next):
				distance[next] = distance[tile] + 1
				queue.append(next)
	return distance


## Standing tiles reachable on foot from the kept way.
static func _reach(standing: Dictionary[Vector2i, bool], kept: Dictionary[Vector2i, bool]) -> Dictionary[Vector2i, bool]:
	var reached: Dictionary[Vector2i, bool] = {}
	var queue: Array[Vector2i] = []
	for tile: Vector2i in kept:
		queue.append(tile)
	var head := 0
	while head < queue.size():
		var tile := queue[head]
		head += 1
		for direction in DIRECTIONS_4:
			var next := tile + direction
			if standing.has(next) and not reached.has(next):
				reached[next] = true
				queue.append(next)
	return reached


## Kept tiles reachable from start over kept tiles (start itself always).
static func _reach_from(kept: Dictionary[Vector2i, bool], start: Vector2i) -> Dictionary[Vector2i, bool]:
	var reached: Dictionary[Vector2i, bool] = {start: true}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var tile := queue[head]
		head += 1
		for direction in DIRECTIONS_4:
			var next := tile + direction
			if kept.has(next) and not reached.has(next):
				reached[next] = true
				queue.append(next)
	return reached


static func _tile_before(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)

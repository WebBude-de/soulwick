class_name IngredientScatter
extends Node2D
## Scatters 2-3 ingredients of the biome's IngredientSet into a normal combat room when the room is
## built (KONZEPT_RAEUME §3.3): cover, trap groups, inner wall pieces, chokepoints/niches, light
## islands with dark zones, explosive barrels and small abyss holes (A4, from room 6). The generator puts this node into every combat
## template and lists the ingredients the shape allows (arena: little cover, catacomb: no extra walls).
##
## Decisions and effects are separate: plan_room() is a pure function of the room layout, the set and
## a RandomNumberGenerator and returns a Plan (tested over many seeds); _build() only turns a plan into
## nodes and wall tiles. Rules of every plan:
## - only on free, reachable floor; never on spawn markers, reserved tiles or the door lanes;
## - blocking pieces keep one tile to every spawn marker and stay away from the entrance;
## - after every blocking piece each floor tile that was reachable from the entrance stays reachable
##   (walking, plus a dash over 1-tile abyss gaps), so no way, door or marker is cut off;
## - nothing lands on a bridge or in an abyss; holes keep every reachable tile reachable on foot
##   (enemies cannot dash) and count as blocking for the rules above.
##
## Randomness: one number of the dungeon RNG (context.rng) seeds the room's own generator, so the
## number of draws on the dungeon RNG does not depend on the ingredients (reproducible runs, Koop).
##
## Since the room plans (R1, D-120) no template scatters any more: the generator writes allowed = []
## (no random props, decoration comes in groups from the plan). The node stays in every combat
## template and keeps its one draw, so the dungeon RNG stream does not change; the planner itself is
## kept for later use (tests still check it as a pure function).

signal scattered(scatter: IngredientScatter)

## Rows in front of a door that stay completely free (door lanes, 3 tiles wide).
const DOOR_LANE_DEPTH := 3
## Chebyshev distance in tiles blocking pieces keep from the tile inside the entrance.
const ENTRANCE_KEEP_OUT := 2
## Explosive barrels keep this distance from the entrance (no blast right at the door). TESTWERT
const EXPLOSIVE_ENTRANCE_DISTANCE := 4
## Inner wall pieces keep one free tile to other walls, pillars and to the outer wall.
const WALL_SPACING := 2
## Light islands keep this distance from each other; dark zones from light islands and doors.
const LIGHT_SPACING := 4
const DARK_ZONE_DOOR_DISTANCE := 3
const PLACEMENT_ATTEMPTS := 40
const ALL_KINDS: Array[int] = [0, 1, 2, 3, 4, 5, 6]

## Items a placement puts into the room.
const ITEM_COVER := &"cover"
const ITEM_TRAP := &"trap"
const ITEM_WALL := &"wall"
const ITEM_LIGHT := &"light"
const ITEM_DARK_ZONE := &"dark_zone"
const ITEM_EXPLOSIVE := &"explosive"
const ITEM_PIT := &"pit"
const BLOCKING_ITEMS: Array[StringName] = [&"cover", &"wall", &"light", &"explosive", &"pit"]
## Hole shapes of the PITS ingredient (tile offsets): single, wide, tall, square.
const PIT_SHAPES: Array = [
	[Vector2i(0, 0)],
	[Vector2i(0, 0), Vector2i(1, 0)],
	[Vector2i(0, 0), Vector2i(0, 1)],
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
]
## Holes keep this Chebyshev distance to each other (one solid tile between them).
const PIT_SPACING := 2

## Inner wall shapes of the WALLS ingredient (tile offsets, crown and front, SPRITES_V6): pillar,
## block, short wall, upright wall, corner. Every column is at least two tiles tall.
const WALL_SHAPES: Array = [
	[Vector2i(0, 0), Vector2i(0, 1)],
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
	[Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)],
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2)],
]
## Niches (KONZEPT_RAEUME §3.3) by open side: wall tiles around the pocket at (0, 0), all of them
## at least two tiles tall; the pocket and the tile in front of the opening stay free.
const NICHES := {
	Vector2i.DOWN: [Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0)],
	Vector2i.UP: [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 2), Vector2i(0, 2), Vector2i(1, 2)],
	Vector2i.RIGHT: [Vector2i(-1, -2), Vector2i(0, -2), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(-1, 2), Vector2i(0, 2)],
	Vector2i.LEFT: [Vector2i(0, -2), Vector2i(1, -2), Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2)],
}

## IngredientSet.Kind values this template allows (written by the generator per shape).
@export var allowed: Array[int] = ALL_KINDS.duplicate()
## Tiles nothing may be placed on (chest, catacomb ambush spots), on top of markers and door lanes.
@export var reserved_tiles: Array[Vector2i] = []
## false = never scatter on its own (tools and tests call scatter_with()).
@export var auto_scatter := true

var plan: Plan = null
var _built: Array[Node2D] = []


## One placed piece of an ingredient.
class Placement:
	extends RefCounted
	var ingredient := 0
	var item: StringName = &""
	var tile := Vector2i.ZERO
	## Inner wall tiles (WALLS, CHOKEPOINTS) or hole tiles (PITS); tile is the first of them.
	var wall_tiles: Array[Vector2i] = []
	## Cover scene index or trap rotation flag.
	var variant := 0

	func is_blocking() -> bool:
		return BLOCKING_ITEMS.has(item)

	func get_tiles() -> Array[Vector2i]:
		if not wall_tiles.is_empty():
			return wall_tiles
		var single: Array[Vector2i] = [tile]
		return single


## Result of plan_room(): the drawn ingredients and every piece.
class Plan:
	extends RefCounted
	var ingredients: Array[int] = []
	var placements: Array[Placement] = []

	func get_blocked_tiles() -> Array[Vector2i]:
		var result: Array[Vector2i] = []
		for placement in placements:
			if placement.is_blocking():
				result.append_array(placement.get_tiles())
		return result

	func get_tiles_of(item: StringName) -> Array[Vector2i]:
		var result: Array[Vector2i] = []
		for placement in placements:
			if placement.item == item:
				result.append_array(placement.get_tiles())
		return result

	func get_wall_tiles() -> Array[Vector2i]:
		return get_tiles_of(ITEM_WALL)

	func get_pit_tiles() -> Array[Vector2i]:
		return get_tiles_of(ITEM_PIT)


## Everything plan_room() needs to know about a room, built once from its RoomTiles.
class Layout:
	extends RefCounted
	var room_size := Vector2i.ZERO
	var entrance_inside := Vector2i.ZERO
	var exit_inside := Vector2i.ZERO
	## Walkable tiles of the template (floor and door corridors without walls and pits).
	var walkable: Dictionary[Vector2i, bool] = {}
	var pits: Dictionary[Vector2i, bool] = {}
	## Blocked floor tiles of the template (pillars, inner walls).
	var static_blocked: Dictionary[Vector2i, bool] = {}
	## Floor tiles reachable from the entrance before scattering, in a fixed order (y, then x).
	var floor_tiles: Array[Vector2i] = []
	var reachable: Dictionary[Vector2i, bool] = {}
	## Tiles reachable on foot, without a dash (enemies): chasm rooms reach every floor tile on foot.
	var walk_reachable: Dictionary[Vector2i, bool] = {}
	## No piece at all: door lanes, spawn markers, reserved tiles.
	var forbidden: Dictionary[Vector2i, bool] = {}
	## No blocking piece: forbidden plus the ring around every spawn marker and the entrance.
	var keep_clear: Dictionary[Vector2i, bool] = {}
	var markers: Array[Vector2i] = []
	var max_dash_gap := RoomTiles.MAX_DASH_GAP

	static func from_tiles(tiles: RoomTiles, marker_tiles: Array[Vector2i], reserved: Array[Vector2i]) -> Layout:
		var layout := Layout.new()
		layout.room_size = tiles.room_size
		layout.entrance_inside = tiles.get_entrance_inside_tile()
		layout.exit_inside = tiles.get_exit_inside_tile()
		layout.walkable = tiles.get_walkable_tiles()
		for tile in tiles.get_pit_tiles():
			layout.pits[tile] = true
		for tile in tiles.get_blocked_tiles():
			layout.static_blocked[tile] = true
		layout.reachable = tiles.get_reachable_tiles()
		var none: Dictionary[Vector2i, bool] = {}
		layout.walk_reachable = RoomTiles.flood_fill(layout.walkable, none, layout.entrance_inside, 0)
		# Bridges stay free (no crate, trap or hole on the only way over an abyss).
		for tile in tiles.get_bridge_tiles():
			layout.forbidden[tile] = true
			layout.keep_clear[tile] = true
		for y in tiles.room_size.y:
			for x in tiles.room_size.x:
				var tile := Vector2i(x, y)
				if layout.reachable.has(tile):
					layout.floor_tiles.append(tile)
		layout.markers = marker_tiles.duplicate()
		var lanes: Array[Vector2i] = []
		for dy in DOOR_LANE_DEPTH:
			for dx in [-1, 0, 1]:
				lanes.append(layout.exit_inside + Vector2i(dx, dy))
				lanes.append(layout.entrance_inside + Vector2i(dx, -dy))
		for tile in lanes + marker_tiles + reserved:
			layout.forbidden[tile] = true
			layout.keep_clear[tile] = true
		for marker in marker_tiles:
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					layout.keep_clear[marker + Vector2i(dx, dy)] = true
		for dy in range(-ENTRANCE_KEEP_OUT, ENTRANCE_KEEP_OUT + 1):
			for dx in range(-ENTRANCE_KEEP_OUT, ENTRANCE_KEEP_OUT + 1):
				layout.keep_clear[layout.entrance_inside + Vector2i(dx, dy)] = true
		return layout


func _ready() -> void:
	if not auto_scatter or Engine.is_editor_hint():
		return
	var room := get_parent() as RoomController
	if room == null or room.context == null or room.context.rng == null:
		return
	# Exactly one draw on the dungeon RNG per room, whatever gets scattered.
	var rng := RandomNumberGenerator.new()
	rng.seed = room.context.rng.randi()
	var spawner := room.get_node_or_null("EnemySpawner") as EnemySpawner
	var biome := spawner.get_biome(room.room_index) if spawner != null else null
	scatter_with(IngredientSet.for_biome(biome), room.room_index, rng)


## Plans and builds the ingredients of this room (parent = the room, siblings Tiles, SpawnPoints).
func scatter_with(ingredient_set: IngredientSet, room_index: int, rng: RandomNumberGenerator) -> Plan:
	var tiles := get_parent().get_node_or_null("Tiles") as RoomTiles
	if tiles == null:
		return null
	var layout := Layout.from_tiles(tiles, get_marker_tiles(get_parent()), reserved_tiles)
	plan = plan_room(layout, ingredient_set, allowed, room_index, rng)
	_build(plan, tiles, ingredient_set)
	scattered.emit(self)
	return plan


## Blocking tiles of the current plan (crates, barrels, walls, light pedestals).
func get_blocked_tiles() -> Array[Vector2i]:
	if plan == null:
		var none: Array[Vector2i] = []
		return none
	return plan.get_blocked_tiles()


func get_built_nodes() -> Array[Node2D]:
	return _built.duplicate()


## Spawn marker tiles of a room (children of SpawnPoints), relative to its Tiles.
static func get_marker_tiles(room: Node) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var points := room.get_node_or_null("SpawnPoints")
	var tiles := room.get_node_or_null("Tiles") as Node2D
	if points == null:
		return result
	var origin := tiles.position if tiles != null else Vector2.ZERO
	for marker in points.get_children():
		if marker is Marker2D:
			result.append(RoomTiles.local_to_tile((marker as Marker2D).position - origin))
	return result


# --- Planning (pure) ---

## 2-3 ingredients (IngredientSet.count) out of the allowed ones, weighted by the set, drawn without
## repetition; an ingredient that finds no valid spot is skipped and the next one is drawn.
static func plan_room(layout: Layout, ingredient_set: IngredientSet, allowed_kinds: Array[int], room_index: int, rng: RandomNumberGenerator) -> Plan:
	var result := Plan.new()
	if ingredient_set == null or layout.floor_tiles.is_empty():
		return result
	var wanted := rng.randi_range(ingredient_set.count.x, ingredient_set.count.y)
	var pool: Array[int] = []
	var weights: Array[float] = []
	for kind in allowed_kinds:
		var weight := ingredient_set.get_weight(kind as IngredientSet.Kind)
		if kind == IngredientSet.Kind.EXPLOSIVES and room_index < ingredient_set.explosives_from_room:
			weight = 0.0
		if kind == IngredientSet.Kind.PITS and room_index < ingredient_set.pits_from_room:
			weight = 0.0
		if weight > 0.0 and not pool.has(kind):
			pool.append(kind)
			weights.append(weight)
	var state := ScatterState.new(layout)
	while result.ingredients.size() < wanted and not pool.is_empty():
		var index := _pick_weighted(weights, rng)
		var kind: int = pool[index]
		pool.remove_at(index)
		weights.remove_at(index)
		var placements := _place(kind, layout, ingredient_set, state, rng)
		if placements.is_empty():
			continue
		result.ingredients.append(kind)
		result.placements.append_array(placements)
	return result


## True if every floor tile reachable before scattering (and not covered now) is still reachable
## from the entrance with blocked as additional obstacles; the exit always has to be. What was
## reachable on foot stays reachable on foot (enemies do not dash over abyss gaps, A4).
static func keeps_paths(layout: Layout, blocked: Dictionary[Vector2i, bool]) -> bool:
	var walkable := layout.walkable.duplicate()
	for tile in blocked:
		walkable.erase(tile)
	var reached := RoomTiles.flood_fill(walkable, layout.pits, layout.entrance_inside, layout.max_dash_gap)
	if not reached.has(layout.exit_inside):
		return false
	for tile in layout.reachable:
		if not blocked.has(tile) and not reached.has(tile):
			return false
	if layout.pits.is_empty():
		return true
	var none: Dictionary[Vector2i, bool] = {}
	var on_foot := RoomTiles.flood_fill(walkable, none, layout.entrance_inside, 0)
	for tile in layout.walk_reachable:
		if not blocked.has(tile) and not on_foot.has(tile):
			return false
	return true


## Planning state shared by the ingredients of one room.
class ScatterState:
	extends RefCounted
	var layout: Layout
	var occupied: Dictionary[Vector2i, bool] = {}
	var blocked: Dictionary[Vector2i, bool] = {}
	var lights: Array[Vector2i] = []

	func _init(room_layout: Layout) -> void:
		layout = room_layout

	func is_free(tile: Vector2i) -> bool:
		return layout.reachable.has(tile) and not occupied.has(tile) and not layout.forbidden.has(tile)

	func can_block(tile: Vector2i) -> bool:
		return is_free(tile) and not layout.keep_clear.has(tile)

	## Wall pieces must look like walls: crown above every front (WallAutotile.is_valid_mass).
	func is_valid_wall(tiles: Array[Vector2i]) -> bool:
		var mass := layout.static_blocked.duplicate()
		for tile in tiles:
			mass[tile] = true
		return WallAutotile.is_valid_mass(mass, layout.room_size)

	## Blocking tiles accepted only if no reachable floor gets cut off.
	func try_block(tiles: Array[Vector2i]) -> bool:
		var test := blocked.duplicate()
		for tile in tiles:
			test[tile] = true
		if not IngredientScatter.keeps_paths(layout, test):
			return false
		for tile in tiles:
			blocked[tile] = true
			occupied[tile] = true
		return true

	func occupy(tiles: Array[Vector2i]) -> void:
		for tile in tiles:
			occupied[tile] = true

	## Chebyshev distance to the nearest static or planned obstacle (and the outer wall).
	func obstacle_distance(tile: Vector2i) -> int:
		var best := mini(mini(tile.x + 1, layout.room_size.x - tile.x), mini(tile.y + 1, layout.room_size.y - tile.y))
		for other: Vector2i in layout.static_blocked.keys() + blocked.keys():
			best = mini(best, maxi(absi(tile.x - other.x), absi(tile.y - other.y)))
		return best


static func _place(kind: int, layout: Layout, ingredient_set: IngredientSet, state: ScatterState, rng: RandomNumberGenerator) -> Array[Placement]:
	match kind:
		IngredientSet.Kind.COVER:
			return _place_cover(ingredient_set, state, rng)
		IngredientSet.Kind.TRAPS:
			return _place_traps(ingredient_set, state, rng)
		IngredientSet.Kind.WALLS:
			return _place_walls(ingredient_set, state, rng)
		IngredientSet.Kind.CHOKEPOINTS:
			return _place_chokepoint(state, rng)
		IngredientSet.Kind.LIGHT:
			return _place_light(ingredient_set, state, rng)
		IngredientSet.Kind.EXPLOSIVES:
			return _place_explosives(ingredient_set, state, rng)
		IngredientSet.Kind.PITS:
			return _place_pits(ingredient_set, state, rng)
	var none: Array[Placement] = []
	return none


## A cluster of crates and barrels (2-4 pieces) on neighbouring tiles.
static func _place_cover(ingredient_set: IngredientSet, state: ScatterState, rng: RandomNumberGenerator) -> Array[Placement]:
	var result: Array[Placement] = []
	var pieces := rng.randi_range(ingredient_set.cover_pieces.x, ingredient_set.cover_pieces.y)
	for attempt in PLACEMENT_ATTEMPTS:
		var cluster := _grow_cluster(_random_tile(state, rng), pieces, state.can_block, rng)
		if cluster.size() < mini(2, pieces) or not state.try_block(cluster):
			continue
		for tile in cluster:
			result.append(_make(IngredientSet.Kind.COVER, ITEM_COVER, tile, rng.randi_range(0, ingredient_set.cover_scenes.size() - 1)))
		return result
	return result


## One group of the biome's trap (2-4 on neighbouring tiles). Traps do not block the way.
static func _place_traps(ingredient_set: IngredientSet, state: ScatterState, rng: RandomNumberGenerator) -> Array[Placement]:
	var result: Array[Placement] = []
	var pieces := rng.randi_range(ingredient_set.trap_pieces.x, ingredient_set.trap_pieces.y)
	for attempt in PLACEMENT_ATTEMPTS:
		var cluster := _grow_cluster(_random_tile(state, rng), pieces, state.is_free, rng)
		if cluster.size() < mini(2, pieces):
			continue
		state.occupy(cluster)
		for tile in cluster:
			result.append(_make(IngredientSet.Kind.TRAPS, ITEM_TRAP, tile, rng.randi_range(0, 1)))
		return result
	return result


## 1-3 inner wall pieces (pillar, short wall, corner) with a free tile around each.
static func _place_walls(ingredient_set: IngredientSet, state: ScatterState, rng: RandomNumberGenerator) -> Array[Placement]:
	var result: Array[Placement] = []
	var pieces := rng.randi_range(ingredient_set.wall_pieces.x, ingredient_set.wall_pieces.y)
	for piece in pieces:
		for attempt in PLACEMENT_ATTEMPTS:
			var anchor := _random_tile(state, rng)
			var shape: Array = WALL_SHAPES[rng.randi_range(0, WALL_SHAPES.size() - 1)]
			var tiles: Array[Vector2i] = []
			var valid := true
			for offset: Vector2i in shape:
				var tile := anchor + offset
				if not state.can_block(tile) or state.obstacle_distance(tile) < WALL_SPACING:
					valid = false
					break
				tiles.append(tile)
			if valid and state.is_valid_wall(tiles) and state.try_block(tiles):
				result.append(_make_wall(IngredientSet.Kind.WALLS, tiles))
				break
	return result


## A chokepoint (two wall stubs with a 1-2 tile gap) or a niche (walls around one free tile).
static func _place_chokepoint(state: ScatterState, rng: RandomNumberGenerator) -> Array[Placement]:
	var result: Array[Placement] = []
	for attempt in PLACEMENT_ATTEMPTS:
		var anchor := _random_tile(state, rng)
		var tiles: Array[Vector2i] = []
		var keep_free: Array[Vector2i] = []
		if rng.randf() < 0.5:
			# Gate: stub a, gap, stub b along one axis (horizontal stubs two rows deep: crown, front).
			var horizontal := rng.randf() < 0.5
			var along := Vector2i.RIGHT if horizontal else Vector2i.DOWN
			var depth := 2 if horizontal else 1
			var stub_a := rng.randi_range(2, 3)
			var gap := rng.randi_range(1, 2)
			var stub_b := rng.randi_range(2, 3)
			for i in stub_a + gap + stub_b:
				for row in depth:
					var tile := anchor + along * i + Vector2i.DOWN * row
					if i >= stub_a and i < stub_a + gap:
						keep_free.append(tile)
					else:
						tiles.append(tile)
		else:
			# Niche open to one side: the pocket and the tile in front of it stay free.
			var open: Vector2i = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT][rng.randi_range(0, 3)]
			keep_free.append(anchor)
			keep_free.append(anchor + open)
			for offset: Vector2i in NICHES[open]:
				tiles.append(anchor + offset)
		var valid := true
		for tile in tiles:
			if not state.can_block(tile) or state.obstacle_distance(tile) < WALL_SPACING:
				valid = false
				break
		for tile in keep_free:
			if not state.is_free(tile) or state.layout.static_blocked.has(tile):
				valid = false
				break
		if not valid or not state.is_valid_wall(tiles) or not state.try_block(tiles):
			continue
		# The gap / pocket stays empty, so no later piece closes it.
		state.occupy(keep_free)
		result.append(_make_wall(IngredientSet.Kind.CHOKEPOINTS, tiles))
		return result
	return result


## 1-2 light islands (crystal or torch stand) apart from each other, maybe a dark zone away from them.
## Empty only if neither fits.
static func _place_light(ingredient_set: IngredientSet, state: ScatterState, rng: RandomNumberGenerator) -> Array[Placement]:
	var result: Array[Placement] = []
	var pieces := rng.randi_range(ingredient_set.light_pieces.x, ingredient_set.light_pieces.y)
	for piece in pieces:
		for attempt in PLACEMENT_ATTEMPTS:
			var tile := _random_tile(state, rng)
			# Row 0 already has the wall torches; islands light the rest of the room.
			if tile.y < 2 or not state.can_block(tile) or _near(tile, state.lights, LIGHT_SPACING):
				continue
			var single: Array[Vector2i] = [tile]
			if not state.try_block(single):
				continue
			state.lights.append(tile)
			result.append(_make(IngredientSet.Kind.LIGHT, ITEM_LIGHT, tile))
			break
	# Without room for an island (catacomb corridors) the ingredient is a dark zone alone.
	if result.is_empty() or rng.randf() < ingredient_set.dark_zone_chance:
		var doors: Array[Vector2i] = [state.layout.entrance_inside, state.layout.exit_inside]
		for attempt in PLACEMENT_ATTEMPTS:
			var tile := _random_tile(state, rng)
			if not state.is_free(tile) or _near(tile, state.lights, LIGHT_SPACING) or _near(tile, doors, DARK_ZONE_DOOR_DISTANCE):
				continue
			var single: Array[Vector2i] = [tile]
			state.occupy(single)
			result.append(_make(IngredientSet.Kind.LIGHT, ITEM_DARK_ZONE, tile))
			break
	return result


## 1-3 explosive barrels, sometimes side by side for a chain reaction; never close to the entrance.
static func _place_explosives(ingredient_set: IngredientSet, state: ScatterState, rng: RandomNumberGenerator) -> Array[Placement]:
	var result: Array[Placement] = []
	var pieces := rng.randi_range(ingredient_set.explosive_pieces.x, ingredient_set.explosive_pieces.y)
	var entrance: Array[Vector2i] = [state.layout.entrance_inside]
	var can_hold := func(tile: Vector2i) -> bool:
		return state.can_block(tile) and not _near(tile, entrance, EXPLOSIVE_ENTRANCE_DISTANCE)
	for attempt in PLACEMENT_ATTEMPTS:
		var cluster := _grow_cluster(_random_tile(state, rng), pieces, can_hold, rng)
		if cluster.is_empty() or not state.try_block(cluster):
			continue
		for tile in cluster:
			result.append(_make(IngredientSet.Kind.EXPLOSIVES, ITEM_EXPLOSIVE, tile))
		return result
	return result


## 1-2 small abyss holes (A4) on open floor, apart from each other and from walls, away from the
## door lanes and markers; the room stays walkable without a dash.
static func _place_pits(ingredient_set: IngredientSet, state: ScatterState, rng: RandomNumberGenerator) -> Array[Placement]:
	var result: Array[Placement] = []
	var pieces := rng.randi_range(ingredient_set.pit_pieces.x, ingredient_set.pit_pieces.y)
	var holes: Array[Vector2i] = []
	for piece in pieces:
		for attempt in PLACEMENT_ATTEMPTS:
			var anchor := _random_tile(state, rng)
			var shape: Array = PIT_SHAPES[rng.randi_range(0, PIT_SHAPES.size() - 1)]
			var tiles: Array[Vector2i] = []
			var valid := true
			for offset: Vector2i in shape:
				var tile := anchor + offset
				if not state.can_block(tile) or state.obstacle_distance(tile) < WALL_SPACING or _near(tile, holes, PIT_SPACING + 1):
					valid = false
					break
				tiles.append(tile)
			# Holes block like walls (not even a dash crosses them in the path check).
			if valid and state.try_block(tiles):
				holes.append_array(tiles)
				var placement := _make(IngredientSet.Kind.PITS, ITEM_PIT, tiles[0])
				placement.wall_tiles = tiles.duplicate()
				result.append(placement)
				break
	return result


static func _make(kind: int, item: StringName, tile: Vector2i, variant := 0) -> Placement:
	var placement := Placement.new()
	placement.ingredient = kind
	placement.item = item
	placement.tile = tile
	placement.variant = variant
	return placement


static func _make_wall(kind: int, tiles: Array[Vector2i]) -> Placement:
	var placement := _make(kind, ITEM_WALL, tiles[0])
	placement.wall_tiles = tiles.duplicate()
	return placement


static func _random_tile(state: ScatterState, rng: RandomNumberGenerator) -> Vector2i:
	var tiles := state.layout.floor_tiles
	return tiles[rng.randi_range(0, tiles.size() - 1)]


## Up to size tiles grown from start over 4-neighbours that pass accept (start included if valid).
static func _grow_cluster(start: Vector2i, size: int, accept: Callable, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var cluster: Array[Vector2i] = []
	if not accept.call(start):
		return cluster
	cluster.append(start)
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var guard := 0
	while cluster.size() < size and guard < size * 8:
		guard += 1
		var from := cluster[rng.randi_range(0, cluster.size() - 1)]
		var next := from + directions[rng.randi_range(0, 3)]
		if not cluster.has(next) and accept.call(next):
			cluster.append(next)
	return cluster


static func _near(tile: Vector2i, others: Array[Vector2i], distance: int) -> bool:
	for other in others:
		if absi(tile.x - other.x) < distance and absi(tile.y - other.y) < distance:
			return true
	return false


static func _pick_weighted(weights: Array[float], rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for weight in weights:
		total += weight
	var roll := rng.randf() * total
	for i in weights.size():
		roll -= weights[i]
		if roll < 0.0:
			return i
	return weights.size() - 1


# --- Building (effects) ---

func _build(room_plan: Plan, tiles: RoomTiles, ingredient_set: IngredientSet) -> void:
	if room_plan == null or ingredient_set == null:
		return
	var walls: Array[Rect2i] = []
	var holes: Array[Vector2i] = []
	for placement in room_plan.placements:
		match placement.item:
			ITEM_WALL:
				for tile in placement.wall_tiles:
					walls.append(Rect2i(tile, Vector2i.ONE))
			ITEM_PIT:
				holes.append_array(placement.wall_tiles)
			ITEM_COVER:
				var cover := _add_prop(ingredient_set.cover_scenes[placement.variant], placement.tile, tiles, true)
				if cover is Rubble:
					cover.modulate = ingredient_set.rubble_tint
			ITEM_EXPLOSIVE:
				_add_prop(ingredient_set.explosive_scene, placement.tile, tiles, true)
			ITEM_TRAP:
				var trap := _add_prop(ingredient_set.trap_scene, placement.tile, tiles, false)
				if trap != null:
					trap.modulate = ingredient_set.trap_tint
					if trap is LavaCrack and placement.variant == 1:
						trap.rotation = PI * 0.5
			ITEM_LIGHT:
				var island := LightIsland.create(ingredient_set.light_style, ingredient_set.light_color)
				island.position = tiles.position + _base_of(placement.tile)
				_add_built(island)
				SortLift.lift(island)
			ITEM_DARK_ZONE:
				var zone := DarkZone.new()
				zone.position = tiles.position + RoomTiles.tile_center(placement.tile)
				_add_built(zone)
	tiles.add_wall_rects(walls)
	tiles.add_pit_tiles(holes)


## Crates, barrels and traps: on the tile centre (traps) or with their base line on the tile.
func _add_prop(scene: PackedScene, tile: Vector2i, tiles: RoomTiles, on_base: bool) -> Node2D:
	if scene == null:
		return null
	var prop := scene.instantiate() as Node2D
	prop.position = tiles.position + (_base_of(tile) if on_base else RoomTiles.tile_center(tile))
	_add_built(prop)
	if on_base:
		# Breakables sort by their base line against the characters' feet (like template props).
		SortLift.lift(prop)
	return prop


func _add_built(node: Node2D) -> void:
	add_child(node)
	_built.append(node)


## Base line of a standing prop on a tile (same spot as the generator's crates and barrels).
static func _base_of(tile: Vector2i) -> Vector2:
	return Vector2((tile.x + 0.5) * RoomTiles.TILE_WORLD, (tile.y + 1) * RoomTiles.TILE_WORLD - 8.0)

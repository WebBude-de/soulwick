class_name TurretPlacement
extends RefCounted
## Which combat rooms get turrets and where they stand (D-151). Hook for the room: call populate(room)
## once when the encounter starts (RoomController.start_encounter, after the first wave); it creates
## the turrets, lets them come out of the ground and has the room track them like any enemy.
## Rules (all TESTWERTE):
## - Only plain normal combat rooms (no arena, no combat variant or mode, no wager altar, no
##   boss/champion/special room), from room FROM_ROOM on; the chance and a second turret grow with depth (CHANCES).
## - Spots (Projektmitglied 17.10.2026, feedback #3aae30f6: "Türme gerne zentraler, dafür viel
##   stärker"): free floor tiles (VariantSpots.free_tiles: reachable, no prop, not the door tiles)
##   near the middle of the room. A spot stands in the open (all eight neighbours walkable, so it
##   never cuts a way and never stands in or against a wall); one of the CENTRE_POOL tiles closest
##   to the centre of the free floor is drawn (at most CENTRE_SPREAD tiles behind the closest). A
##   room without an open tile takes the closest tile that keeps the way (never a one-tile
##   passage). Always at least DOOR_CLEARANCE tiles from every
##   door, SOURCE_CLEARANCE from enemy sources, objectives and the player start, never on a spawn
##   marker, no water, not next to an abyss, SPACING apart. A room without such a spot gets none.
## - Chance from a generator derived from the dungeon seed and the room number: it never draws from
##   the dungeon RNG, so the dungeon of a seed stays the same (like EnemyPack). Host only: network
##   clients get the turrets as puppets (NetEnemies).

const FROM_ROOM := 4
## [first room, chance of one turret, chance of a second one] - the last row whose room is reached.
const CHANCES: Array[Vector3] = [Vector3(4, 0.4, 0.0), Vector3(15, 0.5, 0.3), Vector3(30, 0.6, 0.45)]
const MAX_TURRETS := 2
## Tiles from every door (3: the middle of a room with doors at both ends stays allowed). TESTWERT
const DOOR_CLEARANCE := 3.0
const SOURCE_CLEARANCE := 1.5
const SPACING := 5.0
## The turret is drawn among at most this many candidate tiles closest to the room centre, and only
## among those at most CENTRE_SPREAD tiles farther from it than the closest one. TESTWERT
const CENTRE_POOL := 6
const CENTRE_SPREAD := 2.5
## Coming out of the ground: hidden this long, then rising (Enemy.begin_emerge).
const EMERGE_WAIT := 0.6
const EMERGE_RISE := 0.6
const DATA_PATH := "res://enemies/data/turret_%s.tres"
const DEFAULT_BIOME := &"crypt"
const NEIGHBOURS_4: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
## The eight neighbours in ring order (each one touches the next).
const RING_8: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
	Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
]


## Creates the turrets of this room (none for most rooms), adds them to its enemy container, tracks
## them and starts their emergence. Returns them (empty = none). Call once per encounter.
static func populate(room: RoomController) -> Array[Enemy]:
	var placed: Array[Enemy] = []
	if not can_have_turrets(room):
		return placed
	var rng := rng_for(room)
	var count := roll_count(room.room_index, rng)
	if count <= 0:
		return placed
	var biome := room.spawner.get_biome(room.room_index) if room.spawner != null else null
	var data := data_for_biome(biome.id if biome != null else DEFAULT_BIOME)
	if data == null:
		return placed
	var tiles := room.tiles
	var free := VariantSpots.free_tiles(room)
	for tile: Vector2i in free.keys():
		if tiles.is_water(tile):
			free.erase(tile)
	# Plain spawn markers stay usable: only their own tile is taken (sources, objectives and the
	# player start keep SOURCE_CLEARANCE, _avoid_tiles). Markers spread over the middle of a room,
	# a wider ring around each would push the turret back to the walls.
	for marker in room.get_spawn_markers():
		free.erase(RoomTiles.local_to_tile(room.to_local(marker.global_position)))
	var pits: Dictionary[Vector2i, bool] = {}
	for tile in tiles.get_pit_tiles():
		pits[tile] = true
	var doors: Array[Vector2i] = [tiles.get_entrance_inside_tile()]
	doors.append_array(tiles.get_exit_inside_tiles())
	var spots := pick_tiles(free, tiles.get_walkable_tiles(), pits, doors, _avoid_tiles(room), count, rng)
	for tile in spots:
		var turret := Turret.create(data, room.room_index)
		var container := room.enemy_container
		# Tile centres are in room space (like every other RoomTiles.tile_center user); the RoomTiles
		# layer itself is scaled, so tiles.to_global would put the turret at twice the offset, mostly
		# outside the room where nobody can reach it and the room never clears (D-151 follow-up).
		turret.position = container.to_local(room.to_global(RoomTiles.tile_center(tile)))
		turret.arena = room.get_arena()
		if room.context != null and room.context.economy != null:
			turret.gold_drop = roundi(room.context.economy.get_gold_drop(data, room.room_index, false) * MetaProgression.get_gold_multiplier())
		container.add_child(turret)
		# Other enemies walk around it like around a crate, until it breaks.
		tiles.set_navigation_blocked(tile, true)
		turret.tree_exiting.connect(_free_tile.bind(tiles, tile), CONNECT_ONE_SHOT)
		room.track_enemy(turret)
		turret.begin_emerge(EMERGE_WAIT, EMERGE_RISE, Enemy.Emerge.RISE)
		placed.append(turret)
	return placed


## Plain normal combat room from FROM_ROOM on (no arena, variant or mode).
static func can_have_turrets(room: RoomController) -> bool:
	if room == null or not is_instance_valid(room) or room.tiles == null or room.enemy_container == null:
		return false
	if not RoomSequence.is_normal_combat(room.room_type) or room.room_index < FROM_ROOM:
		return false
	if room.is_arena_room():
		return false
	# A wager altar room is not a plain fight either (VariantTable: minigame, wager altar or plain);
	# its bet (no damage, time limit, curses) is made on the room as it was offered.
	return room.get_variant_id() == VariantTable.NONE and not room.has_wager_altar()


## Number of turrets for a room (0..MAX_TURRETS), two draws from rng.
static func roll_count(room_index: int, rng: RandomNumberGenerator) -> int:
	var chances := get_chances(room_index)
	if chances == Vector2.ZERO:
		return 0
	var first := rng.randf() < chances.x
	var second := rng.randf() < chances.y
	if not first:
		return 0
	return mini(MAX_TURRETS, 2 if second else 1)


## (chance of one turret, chance of a second one) for a room; ZERO before FROM_ROOM.
static func get_chances(room_index: int) -> Vector2:
	var result := Vector2.ZERO
	for row in CHANCES:
		if room_index >= int(row.x):
			result = Vector2(row.y, row.z)
	return result


## Generator of this room: derived from the dungeon seed and the room number, never drawn from the
## dungeon RNG itself.
static func rng_for(room: RoomController) -> RandomNumberGenerator:
	var dungeon_seed := 0
	if room.context != null and room.context.rng != null:
		dungeon_seed = room.context.rng.seed
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([dungeon_seed, room.room_index, "turret"])
	return rng


## Turret type of a biome (turret_<biome id>.tres), the crypt's for unknown biomes.
static func data_for_biome(biome_id: StringName) -> EnemyData:
	var path := DATA_PATH % String(biome_id)
	if not ResourceLoader.exists(path):
		path = DATA_PATH % String(DEFAULT_BIOME)
	return load(path) as EnemyData if ResourceLoader.exists(path) else null


## Up to count spots out of free (see the class comment). walkable: floor and door corridors without
## walls, props and pits; pits: abyss tiles (no wall); doors: floor tiles at the doors; avoid: tiles
## to keep SOURCE_CLEARANCE from. Open tiles closest to the centre of free first; draws with rng,
## stable order.
static func pick_tiles(free: Dictionary[Vector2i, bool], walkable: Dictionary[Vector2i, bool], pits: Dictionary[Vector2i, bool],
		doors: Array[Vector2i], avoid: Array[Vector2i], count: int, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var open: Array[Vector2i] = []
	var fallback: Array[Vector2i] = []
	for tile in VariantSpots.sorted_tiles(free):
		if touches_pit(tile, pits):
			continue
		if not VariantSpots.is_clear_of(tile, doors, DOOR_CLEARANCE) or not VariantSpots.is_clear_of(tile, avoid, SOURCE_CLEARANCE):
			continue
		if is_open_spot(tile, walkable):
			open.append(tile)
		elif keeps_way(tile, walkable) and not is_passage(tile, walkable, pits):
			fallback.append(tile)
	var pool := open if not open.is_empty() else fallback
	var centre := centre_of(free)
	pool = sort_by_centre(pool, centre)
	var picked: Array[Vector2i] = []
	while picked.size() < count:
		var choices: Array[Vector2i] = []
		var limit := INF
		for tile in pool:
			if not VariantSpots.is_clear_of(tile, picked, SPACING):
				continue
			var distance := Vector2(tile).distance_to(centre)
			if choices.is_empty():
				limit = distance + CENTRE_SPREAD
			elif distance > limit:
				break
			choices.append(tile)
			if choices.size() >= CENTRE_POOL:
				break
		if choices.is_empty():
			break
		picked.append(choices[rng.randi_range(0, choices.size() - 1)])
	return picked


## All eight neighbours walkable: the turret stands free in the room, nothing walks into a dead end
## because of it and it never stands in or against a wall.
static func is_open_spot(tile: Vector2i, walkable: Dictionary[Vector2i, bool]) -> bool:
	for offset in RING_8:
		if not walkable.has(tile + offset):
			return false
	return true


## Wall or rock (no abyss) on two opposite sides: a one-tile passage.
static func is_passage(tile: Vector2i, walkable: Dictionary[Vector2i, bool], pits: Dictionary[Vector2i, bool]) -> bool:
	var north := _is_solid(tile + Vector2i.UP, walkable, pits)
	var south := _is_solid(tile + Vector2i.DOWN, walkable, pits)
	var west := _is_solid(tile + Vector2i.LEFT, walkable, pits)
	var east := _is_solid(tile + Vector2i.RIGHT, walkable, pits)
	return (north and south) or (west and east)


## Mean tile of a set (its centre of mass, in tile units); ZERO for an empty set.
static func centre_of(tiles: Dictionary[Vector2i, bool]) -> Vector2:
	if tiles.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for tile: Vector2i in tiles.keys():
		sum += Vector2(tile)
	return sum / float(tiles.size())


## tiles ordered by distance to centre (closest first), ties in the given (stable) order. Insertion
## sort: rooms have a few hundred tiles at most and no lambda is needed.
static func sort_by_centre(tiles: Array[Vector2i], centre: Vector2) -> Array[Vector2i]:
	var sorted: Array[Vector2i] = []
	var distances: Array[float] = []
	for tile in tiles:
		var distance := Vector2(tile).distance_squared_to(centre)
		var at := distances.bsearch(distance, false)
		sorted.insert(at, tile)
		distances.insert(at, distance)
	return sorted


## Wall or rock on at least one side, but not on two opposite sides (a one-tile passage). The
## former turret spot (D-151 before 17.10.2026); kept for tools and tests.
static func is_wall_spot(tile: Vector2i, walkable: Dictionary[Vector2i, bool], pits: Dictionary[Vector2i, bool]) -> bool:
	return count_walls(tile, walkable, pits) > 0 and not is_passage(tile, walkable, pits)


## An abyss next to the tile (eight neighbours): nobody should have to fight at the edge for it.
static func touches_pit(tile: Vector2i, pits: Dictionary[Vector2i, bool]) -> bool:
	for offset in RING_8:
		if pits.has(tile + offset):
			return true
	return false


static func count_walls(tile: Vector2i, walkable: Dictionary[Vector2i, bool], pits: Dictionary[Vector2i, bool]) -> int:
	var walls := 0
	for offset in NEIGHBOURS_4:
		if _is_solid(tile + offset, walkable, pits):
			walls += 1
	return walls


## Taking tile out of the walkable floor leaves its walkable neighbours connected to each other
## around it: in the ring of eight neighbours (each touches the next) the open tiles that reach the
## tile through an edge form at most one run. Nothing walks into a dead end because a turret stands
## there.
static func keeps_way(tile: Vector2i, walkable: Dictionary[Vector2i, bool]) -> bool:
	var size := RING_8.size()
	var open: Array[bool] = []
	var start := -1
	for i in size:
		open.append(walkable.has(tile + RING_8[i]))
		if not open[i] and start < 0:
			start = i
	if start < 0:
		return true
	var runs := 0
	var in_run := false
	var has_edge := false
	for step in size:
		var index := (start + 1 + step) % size
		if open[index]:
			in_run = true
			# Odd ring places are the four edge neighbours; a lone corner does not touch the tile.
			has_edge = has_edge or index % 2 == 1
		else:
			if in_run and has_edge:
				runs += 1
			in_run = false
			has_edge = false
	return runs <= 1


static func _is_solid(tile: Vector2i, walkable: Dictionary[Vector2i, bool], pits: Dictionary[Vector2i, bool]) -> bool:
	return not walkable.has(tile) and not pits.has(tile)


static func _avoid_tiles(room: RoomController) -> Array[Vector2i]:
	var avoid: Array[Vector2i] = []
	var markers: Array[Marker2D] = room.get_sources()
	markers.append_array(room.get_objectives())
	var start := room.get_player_start_marker()
	if start != null:
		markers.append(start)
	for marker in markers:
		avoid.append(RoomTiles.local_to_tile(room.to_local(marker.global_position)))
	return avoid


static func _free_tile(tiles: RoomTiles, tile: Vector2i) -> void:
	if tiles != null and is_instance_valid(tiles):
		tiles.set_navigation_blocked(tile, false)

class_name SpawnSources
extends Node2D
## Every enemy source of one room and the way enemies come out of them (R2, RAEUME §5).
## Enemies no longer stand there suddenly: each push picks a few sources, mostly behind or beside
## the players and never close to any of them (SpawnSourceRules, own RNG from the dungeon seed);
## each source warns for 1 s with light and sound, then its enemies come out one after another,
## passive and invulnerable (Enemy.begin_emerge), and fight. Decision here, look in SpawnSource.
##
## Sources come from the room plan (R1 marker contract, see SpawnSourceRules): a node "Sources"
## with Marker2D children, meta "source_kind" and, for gates and wall rifts, "wall_side".
## Fallback while a room has no markers: the old spawn points become floor sources of the biome
## (crypt graves, grotto puddles, shadow rifts, ember vents); an arena gets ARENA_GATE_COUNT gates in
## its outer walls (WallGates). Arenas use gates only, every wave other gates; no ambush (D-120).
## Sarcophagi bring elites and champions; bosses keep their own intro.
## Height (M3b, D-189): a floor source may lie on a plateau with stairs; ranged enemies of a push take
## those first, close-combat enemies the ones on the ground (SpawnSourceRules.sort_by_height).
##
## Entry point for the RoomController (integrator): SpawnSources.setup(room) in _ready, then
## spawn_wave() per wave and release_encounter() for the champion room. Child of the room at its
## origin, so room-local and own coordinates are the same.

## An enemy is out of its source and fights.
signal enemy_emerged(enemy: Enemy)

const NODE_NAME := &"SpawnSources"
## Marker contract with the room plans (R1).
const MARKER_NODE := ^"Sources"
const META_KIND := &"source_kind"
const META_SIDE := &"wall_side"
## Optional (R1 generator writes them): tile of the source and, for wall sources, the floor tile an
## enemy steps onto.
const META_TILE := &"tile"
const META_FLOOR_TILE := &"floor_tile"
## A champion's own source is this much bigger (it is 1.5 times the size of its kind).
const CHAMPION_SOURCE_SCALE := 1.4

var room_index := 0
## Arena: wall gates only.
var arena_only := false
## True when the sources come from the room plan's markers, false for the fallback.
var from_markers := false

var _room: RoomController = null
var _biome_id := &""
var _sources: Array[SpawnSource] = []
## Sources made for one champion (its spot in the middle of the room): never used for pushes.
var _champion_sources: Array[SpawnSource] = []
var _last: Array[SpawnSource] = []
## Floor sources on a plateau surface (M3b).
var _high: Dictionary[SpawnSource, bool] = {}
var _rng := RandomNumberGenerator.new()
var _built := false


func _init() -> void:
	name = NODE_NAME
	y_sort_enabled = true


## Builds the sources of a combat or champion room and adds them to it; null for rooms without an
## encounter of their own (special rooms, campfire) and for boss rooms (the boss intro shows the
## boss). Call once in RoomController._ready, after _setup_waves (needs is_arena). Safe to call
## again: returns the existing node. The sources are built one frame later (after anything that
## still changes the floor) or on first use, whichever comes first.
static func setup(room: RoomController) -> SpawnSources:
	if room == null or not is_instance_valid(room):
		return null
	var existing := of(room)
	if existing != null:
		return existing
	if not (RoomSequence.is_normal_combat(room.room_type) or room.room_type == RoomSequence.RoomType.MINIBOSS):
		return null
	var sources := SpawnSources.new()
	sources._room = room
	sources.room_index = room.room_index
	sources.arena_only = room.is_arena_room()
	var biome: BiomeData = room.spawner.get_biome(room.room_index) if room.spawner != null else null
	sources._biome_id = biome.id if biome != null else &""
	sources._rng.seed = derive_seed(room)
	room.add_child(sources)
	room.completed.connect(sources._on_room_completed)
	sources.build.call_deferred()
	return sources


## The sources of a room (null before setup or for rooms without sources).
static func of(room: Node) -> SpawnSources:
	if room == null or not is_instance_valid(room):
		return null
	return room.get_node_or_null(NodePath(NODE_NAME)) as SpawnSources


## Seed of the source choice: from the dungeon seed and the room number, never a draw from the
## dungeon RNG itself (like EnemyPack, D-130), so the dungeon of a seed stays the same.
static func derive_seed(room: RoomController) -> int:
	var dungeon_seed := 0
	if room.context != null and room.context.rng != null:
		dungeon_seed = room.context.rng.seed
	return hash([dungeon_seed, room.room_index, "spawn_sources"])


## Reads the markers (or the fallback) and builds the source nodes. Runs once.
func build() -> void:
	if _built or _room == null or not is_instance_valid(_room):
		return
	_built = true
	for marker in get_plan_markers(_room):
		_add_from_marker(marker)
	from_markers = not _pool().is_empty()
	if from_markers:
		return
	# Fallback: no usable markers (yet). Clear half-built plan sources that cannot serve.
	for source in _sources:
		source.queue_free()
	_sources.clear()
	_high.clear()
	if arena_only:
		_build_fallback_gates()
	else:
		var kind := SpawnSourceRules.biome_kind(_biome_id)
		for marker in _room.get_spawn_markers():
			_add(SpawnSource.create_floor(kind, marker.position))


func is_built() -> bool:
	return _built


## Marker2D children of the room's "Sources" node (R1 plan), empty without.
static func get_plan_markers(room: Node) -> Array[Marker2D]:
	var markers: Array[Marker2D] = []
	var holder := room.get_node_or_null(MARKER_NODE)
	if holder == null:
		return markers
	for child in holder.get_children():
		if child is Marker2D:
			markers.append(child)
	return markers


func get_sources() -> Array[SpawnSource]:
	build()
	return _sources.duplicate()


## Sources normal enemies of a push come out of (arena: gates only; sarcophagi are for elites).
func get_pool() -> Array[SpawnSource]:
	build()
	return _pool()


## Enemies one push brings at most (D-086 overflow: more become an extra wave): PER_SOURCE per
## usable source, never fewer than the room's spawn points - the wave sizes stay those of D-086 and
## D-118; a room with few sources lets more enemies queue at each one instead.
func get_capacity() -> int:
	var pool := get_pool()
	if pool.is_empty():
		return 0
	var spawn_points := _room.get_spawn_markers().size() if _room != null and is_instance_valid(_room) else 0
	return maxi(SpawnSourceRules.capacity(pool.size()), spawn_points)


## Is the source on a plateau surface (M3b)?
func is_high(source: SpawnSource) -> bool:
	return _high.has(source)


## Sources the latest push used (tests, tools).
func get_last_sources() -> Array[SpawnSource]:
	return _last.duplicate()


## One push of count normal enemies: picks the sources, lets the spawner create the enemies
## (types and elites from the dungeon RNG as before) and sends them through their sources. Elites
## take a free sarcophagus if the room has one. Returns the enemies (already in container).
func spawn_wave(spawner: EnemySpawner, count: int, container: Node2D, context: DungeonContext, arena := Rect2()) -> Array[Enemy]:
	var enemies: Array[Enemy] = []
	var chosen := choose(count)
	if chosen.is_empty() or spawner == null:
		return enemies
	var positions: Array[Vector2] = []
	for source in chosen:
		positions.append(source.spot)
	enemies = spawner.spawn_enemies(room_index, positions, container, context, arena)
	sort_by_height(enemies, chosen)
	_give_sarcophagi_to_elites(enemies, chosen)
	release(enemies, chosen)
	return enemies


## Sources for count enemies (one entry per enemy; a source repeats when enemies queue).
## Decision only, no effect: SpawnSourceRules.pick with the living players of the room.
func choose(count: int) -> Array[SpawnSource]:
	var chosen: Array[SpawnSource] = []
	var pool := get_pool()
	if pool.is_empty() or count <= 0:
		return chosen
	var spots: Array[Vector2] = []
	var groups: Array[int] = []
	var last: Array[int] = []
	for i in pool.size():
		spots.append(pool[i].spot)
		groups.append(pool[i].get_group())
		if _last.has(pool[i]):
			last.append(i)
	var players := get_player_states()
	var min_distance := SpawnSourceRules.GATE_MIN_PLAYER_DISTANCE if arena_only else SpawnSourceRules.MIN_PLAYER_DISTANCE
	for index in SpawnSourceRules.pick(spots, groups, count, players[0], players[1], last, min_distance, _rng):
		chosen.append(pool[index])
	_last.clear()
	for source in chosen:
		if not _last.has(source):
			_last.append(source)
	return chosen


## Sends enemies (in the tree) through their sources: enemies[i] uses sources[i % size]. The
## sources light up one after the other (SpawnSourceRules timing); start_delay: extra wait.
func release(enemies: Array[Enemy], sources: Array[SpawnSource], start_delay := 0.0) -> void:
	if sources.is_empty():
		return
	var order: Dictionary = {}
	var counts: Dictionary = {}
	for i in enemies.size():
		var source := sources[i % sources.size()]
		if not order.has(source):
			order[source] = order.size()
		counts[source] = int(counts.get(source, 0)) + 1
	var places: Dictionary = {}
	for i in enemies.size():
		var enemy := enemies[i]
		var source := sources[i % sources.size()]
		var place: int = places.get(source, 0)
		places[source] = place + 1
		if not is_instance_valid(enemy) or enemy.is_dead():
			continue
		source.bring(enemy, self, SpawnSourceRules.emerge_start(order[source], place, start_delay), place)
		if not enemy.intro_ended.is_connected(_on_enemy_out):
			enemy.intro_ended.connect(_on_enemy_out, CONNECT_ONE_SHOT)
	for source: SpawnSource in order:
		source.play(SpawnSourceRules.warn_start(order[source], start_delay), counts[source])


## Champion room (EnemySpawner.spawn_encounter): the champion rises from a sarcophagus (crypt) or a
## big source of its biome where it stands - or from a sarcophagus of the plan - its escort comes
## out of the room's sources. Bosses are left alone (boss intro).
func release_encounter(enemies: Array[Enemy]) -> void:
	build()
	var escort: Array[Enemy] = []
	var lead_delay := 0.0
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.data == null or enemy.data.is_boss:
			continue
		if enemy.is_miniboss:
			var source := _champion_source(enemy)
			release([enemy] as Array[Enemy], [source] as Array[SpawnSource])
			lead_delay = SpawnSourceRules.SOURCE_STAGGER
		else:
			escort.append(enemy)
	if escort.is_empty():
		return
	var chosen := choose(escort.size())
	if not chosen.is_empty():
		sort_by_height(escort, chosen)
		release(escort, chosen, lead_delay)


## Room-local positions and facing directions of all living players: [Array[Vector2], Array[Vector2]].
## Facing = walking direction, standing still = aim; zero if unknown (coop: every player counts).
func get_player_states() -> Array:
	var positions: Array[Vector2] = []
	var fronts: Array[Vector2] = []
	if not is_inside_tree():
		return [positions, fronts]
	for player in EnemyTargeting.living_players(get_tree()):
		positions.append(to_local(player.global_position))
		fronts.append(facing_of(player))
	return [positions, fronts]


## Where a player looks or walks (unit vector, zero if unknown).
static func facing_of(player: Node2D) -> Vector2:
	var body := player as CharacterBody2D
	if body != null and body.velocity.length() > 30.0:
		return body.velocity.normalized()
	if player.has_method(&"get_aim_direction"):
		var aim: Vector2 = player.call(&"get_aim_direction")
		if aim.length_squared() > 0.0001:
			return aim.normalized()
	return Vector2.ZERO


func _pool() -> Array[SpawnSource]:
	var pool: Array[SpawnSource] = []
	for source in _sources:
		if not is_instance_valid(source):
			continue
		if arena_only and source.kind != SpawnSourceRules.Kind.GATE:
			continue
		if source.kind == SpawnSourceRules.Kind.SARCOPHAGUS or _champion_sources.has(source):
			continue
		pool.append(source)
	return pool


func _add(source: SpawnSource) -> SpawnSource:
	_sources.append(source)
	add_child(source)
	return source


func _add_from_marker(marker: Marker2D) -> void:
	var kind := SpawnSourceRules.kind_from_id(marker.get_meta(META_KIND, ""))
	if kind < 0:
		push_warning("Room %d: spawn source marker %s has no valid source_kind." % [room_index, marker.name])
		return
	if not SpawnSourceRules.is_wall_kind(kind):
		var source := _add(SpawnSource.create_floor(kind, marker.position))
		var tile: Vector2i = marker.get_meta(META_TILE, RoomTiles.local_to_tile(marker.position))
		if _room.tiles != null and _room.tiles.has_height() and _room.tiles.get_height_layout().surface.has(tile):
			_high[source] = true
		return
	var side := SpawnSourceRules.side_from_meta(marker.get_meta(META_SIDE, null))
	if side < 0:
		push_warning("Room %d: wall source %s has no valid wall_side." % [room_index, marker.name])
		return
	var direction: Vector2i = RoomTiles.SIDE_DIRECTIONS[side]
	if marker.has_meta(META_TILE) and marker.has_meta(META_FLOOR_TILE):
		# The plan names both tiles (R1 generator): wall tile of the opening and floor in front.
		_add(SpawnSource.create_wall(kind, side, marker.get_meta(META_TILE), marker.get_meta(META_FLOOR_TILE)))
		return
	# Else the marker sits in the wall tile of the opening; one on the floor in front of it works too.
	var tile := RoomTiles.local_to_tile(marker.position)
	var wall := tile
	if _room.tiles.is_walkable(tile):
		wall = tile + direction
	_add(SpawnSource.create_wall(kind, side, wall, wall - direction))


## Arena without gate markers: ARENA_GATE_COUNT gates in the outer walls, away from doors and props
## (as the A5 arena did), spread over at least two walls.
func _build_fallback_gates() -> void:
	var tiles := _room.tiles
	var props: Array[Vector2] = []
	var prop_nodes: Array[Node] = _room.get_node("Props").get_children()
	for child in _room.get_children():
		if child.has_method(&"get_built_nodes"):
			prop_nodes.append_array(child.call(&"get_built_nodes"))
	for prop in prop_nodes:
		var node := prop as Node2D
		if node != null and is_instance_valid(node):
			props.append(_room.to_local(node.global_position) if node.is_inside_tree() else node.position)
	var doors: Array[Vector2i] = [_room.get_entrance_tile()]
	doors.append_array(_room.get_exit_tiles())
	var gates := WallGates.find_gates(tiles.get_reachable_tiles(), tiles.room_size, doors, props)
	for gate in WallGates.place(gates, SpawnSourceRules.ARENA_GATE_COUNT, WaveRules.MIN_SIDES, _rng):
		_add(SpawnSource.create_wall(SpawnSourceRules.Kind.GATE, gate.side, gate.wall_tile, gate.floor_tile))


## Height (M3b, D-189): ranged enemies of a push go to sources on a plateau, close-combat enemies to
## the ground (decision SpawnSourceRules.sort_by_height; chosen[i] is the source of enemies[i]). A
## plateau source outside the push may serve when it is far enough from every player.
func sort_by_height(enemies: Array[Enemy], chosen: Array[SpawnSource]) -> void:
	if _high.is_empty() or chosen.is_empty():
		return
	var pool := _pool()
	var count := mini(enemies.size(), chosen.size())
	var slots: Array[int] = []
	var ranged: Array[bool] = []
	for i in count:
		slots.append(pool.find(chosen[i]))
		var enemy := enemies[i]
		ranged.append(is_instance_valid(enemy) and enemy.data != null and enemy.data.attack_kind == EnemyData.AttackKind.RANGED)
	if slots.has(-1):
		return
	var high: Array[bool] = []
	var open: Array[int] = []
	var players: Array[Vector2] = get_player_states()[0]
	var min_distance := SpawnSourceRules.GATE_MIN_PLAYER_DISTANCE if arena_only else SpawnSourceRules.MIN_PLAYER_DISTANCE
	for i in pool.size():
		high.append(_high.has(pool[i]))
		if WaveRules.distance_to_nearest(pool[i].spot, players) >= min_distance:
			open.append(i)
	var sorted := SpawnSourceRules.sort_by_height(slots, ranged, high, open, SpawnSourceRules.max_active(pool.size()))
	for i in count:
		chosen[i] = pool[sorted[i]]
	_last.clear()
	for source in chosen:
		if not _last.has(source):
			_last.append(source)


## Elites of a push swap into free sarcophagi of the room (farthest from the players first).
func _give_sarcophagi_to_elites(enemies: Array[Enemy], chosen: Array[SpawnSource]) -> void:
	var free: Array[SpawnSource] = []
	for source in _sources:
		if is_instance_valid(source) and source.kind == SpawnSourceRules.Kind.SARCOPHAGUS and not source.is_active():
			free.append(source)
	if free.is_empty():
		return
	var players: Array[Vector2] = get_player_states()[0]
	for i in range(free.size() - 1, -1, -1):
		if WaveRules.distance_to_nearest(free[i].spot, players) < SpawnSourceRules.MIN_PLAYER_DISTANCE:
			free.remove_at(i)
	free.sort_custom(func(a: SpawnSource, b: SpawnSource) -> bool:
		return WaveRules.distance_to_nearest(a.spot, players) > WaveRules.distance_to_nearest(b.spot, players))
	for i in enemies.size():
		if free.is_empty():
			return
		if enemies[i].elite != Enemy.Elite.NONE:
			chosen[i] = free.pop_front()


## The champion's source: a free sarcophagus of the plan far from the players, else a new one
## where it stands (crypt: sarcophagus, other biomes: a big source of the biome).
func _champion_source(champion: Enemy) -> SpawnSource:
	var players: Array[Vector2] = get_player_states()[0]
	var best: SpawnSource = null
	var best_distance := SpawnSourceRules.MIN_PLAYER_DISTANCE
	for source in _sources:
		if is_instance_valid(source) and source.kind == SpawnSourceRules.Kind.SARCOPHAGUS and not source.is_active():
			var distance := WaveRules.distance_to_nearest(source.spot, players)
			if distance >= best_distance:
				best_distance = distance
				best = source
	if best != null:
		return best
	var kind := SpawnSourceRules.Kind.SARCOPHAGUS if SpawnSourceRules.biome_kind(_biome_id) == SpawnSourceRules.Kind.GRAVE else SpawnSourceRules.biome_kind(_biome_id)
	var source := SpawnSource.create_floor(kind, to_local(champion.global_position))
	source.scale = Vector2.ONE * CHAMPION_SOURCE_SCALE
	_champion_sources.append(source)
	return _add(source)


func _on_enemy_out(enemy: Enemy) -> void:
	if is_instance_valid(enemy) and not enemy.is_dead():
		enemy_emerged.emit(enemy)


func _on_room_completed(_room_node: RoomController) -> void:
	for source in _sources:
		if is_instance_valid(source):
			source.go_quiet()

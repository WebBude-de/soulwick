class_name RiftsMode
extends RoomMode
## Minigame "Risse schließen" (RAEUME §3.7, design answer 01_raumarten.md, R4b; replaces
## the summoning rifts of D-114): "Zerstöre die Risse, aus denen Gegner kommen."
##   Intro:  the rifts already stand in the walls (the plan's wall rifts, '!'), still and
##           invulnerable like guards (Enemy.begin_intro); camera and Flint on them, banner
##           "Schließe die Risse" (playtest 23.10.2026 #f5470311: they only appeared with the fight,
##           so the intro showed bare walls).
##   Fight:  every rift has health and a bar (SummoningRift) and sends one enemy every
##           RiftRules.PUSH_INTERVAL seconds through its wall rift (the room's SpawnSource: warning,
##           the enemy steps out of the wall) while fewer than RiftRules.MAX_ALIVE enemies live.
##           Once the first rift is closed the floor sources join in. Task bar:
##           rifts open, a bar of the rifts' remaining health, the time for the crystal.
##   End:    all rifts closed = success; then the rest must be beaten (the rifts count for the room
##           like any enemy). Bonus chest; every rift closed within 40 s = +1 soul crystal.
## Rooms without wall rifts in their plan get 2-3 rifts at the walls that call their enemies
## themselves (the old way). Co-op: +1 rift per extra player (MP5).

## Loaded at use (no preload: the mode scripts stay out of the load cycles of the room scripts).
const RIFT_SCENE_PATH := "res://enemies/variants/summoning_rift.tscn"
const RIFT_DATA_PATH := "res://enemies/data/summoning_rift.tres"
## Biome colour of the (neutral) rift art (SPRITES_V5 §3: "wird eingefärbt").
const BIOME_COLORS := {
	&"crypt": Color(0.75, 1.0, 0.95),
	&"slime_grotto": Color(0.65, 1.0, 0.55),
	&"shadow_realm": Color(0.85, 0.65, 1.0),
	&"ember_forge": Color(1.0, 0.75, 0.5),
}
## A rift in a wall stands this far above the centre of the floor tile in front of the wall, so it
## seems to tear out of the brick front and can still be hit from the floor.
const WALL_RIFT_LIFT := 20.0

var rifts: Array[SummoningRift] = []

## Plan rifts: floor tile in front of each wall rift (from the Sources markers "rift_wall").
var _wall_tiles: Array[Vector2i] = []
## Rooms without plan rifts: rift tiles at the walls.
var _free_tiles: Array[Vector2i] = []
## Rift -> its wall source (plan rifts only).
var _rift_sources: Dictionary[SummoningRift, SpawnSource] = {}
## Rift -> the floor tile it was placed on.
var _rift_tiles: Dictionary[SummoningRift, Vector2i] = {}
## Rift -> seconds until its next push.
var _push_in: Dictionary[SummoningRift, float] = {}
var _closed := 0
var _total_health := 0.0
var _crystal_decided := false


func can_host() -> bool:
	return not _plan_rift_tiles().is_empty() or _candidates().size() >= RiftRules.COUNT.x


func _on_attach() -> void:
	# Height (M3b): nothing of the mode stands at the foot of stairs or a ladder.
	HeightRules.keep_feet_free(room.tiles, _free)
	_wall_tiles = _plan_rift_tiles()
	if _wall_tiles.is_empty():
		var count := RiftRules.rift_count(_rng.randf(), 1)
		_free_tiles = VariantSpots.pick_spread(_candidates(), count, RiftRules.MIN_TILE_DISTANCE, _rng)
		if _free_tiles.size() < RiftRules.COUNT.x:
			# Few wall spots close together (small or odd shapes): closer rifts rather than one.
			_free_tiles = VariantSpots.pick_spread(_candidates(), count, RiftRules.MIN_TILE_DISTANCE * 0.5, _rng)
	# Built right away: the rifts already show through the open door and in the intro; they wait
	# still and invulnerable until the fight starts (_on_fight_started wakes them).
	for tile in _wall_tiles:
		_place_rift(tile, true)
	for tile in _free_tiles:
		_place_rift(tile, false)
	# The room's sources are built deferred (SpawnSources.setup): the wall rifts take theirs after.
	_bind_wall_sources.call_deferred()


func _shape_group(group: EncounterGroup) -> EncounterGroup:
	return VariantEncounterGroup.wrap(group, self, RiftRules.FIRST_WAVE_FACTOR)


## The intro camera: on the first rift (the middle of all rifts may be bare floor between them).
func get_focus() -> Vector2:
	var points := get_rift_points()
	return points[0] if not points.is_empty() else Vector2.INF


## Global points of the rifts (their art in the wall), in the order they were placed.
func get_rift_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for rift in get_open_rifts():
		if rift.is_inside_tree():
			points.append(rift.global_position + Vector2(0, -WALL_RIFT_LIFT if rift.in_wall else 0.0))
	if points.is_empty() and room != null:
		for tile in (_wall_tiles if not _wall_tiles.is_empty() else _free_tiles):
			points.append(room.to_global(RoomTiles.tile_center(tile)))
	return points


## Flint's first-time tour (WK11): a rift in the wall, another one to hit, then what is left.
func get_flint_steps() -> Array[FlintGuideStep]:
	var points := get_rift_points()
	var second := points[1] if points.size() > 1 else Vector2.INF
	return RoomFlint.steps(RoomObjective.RIFTS, [get_focus(), second])


func _setup_objective(goal: RoomObjective) -> void:
	var total := get_rift_tile_count()
	goal.set_ratio(0.0)
	goal.set_time(RiftRules.FAST_TIME)
	goal.set_label(DungeonTexts.t(&"OBJECTIVE_RIFTS", [total, total]))


func _on_fight_started() -> void:
	# Co-op: extra rifts for more players (D-109), at free wall tiles; they tear open now.
	var extra := RiftRules.extra_rifts(get_player_count())
	if extra > 0:
		var taken: Array[Vector2i] = _wall_tiles.duplicate()
		taken.append_array(_free_tiles)
		var pool: Array[Vector2i] = []
		for tile in _candidates():
			if VariantSpots.is_clear_of(tile, taken, RiftRules.MIN_TILE_DISTANCE):
				pool.append(tile)
		for tile in VariantSpots.pick_spread(pool, extra, RiftRules.MIN_TILE_DISTANCE, _rng):
			_free_tiles.append(tile)
			_place_rift(tile, false)
	_bind_wall_sources()
	var index := 0
	for rift in get_open_rifts():
		_open_rift(rift, RiftRules.FIRST_DELAY + RiftRules.STAGGER * index)
		index += 1
	_total_health = 0.0
	for rift in get_open_rifts():
		_total_health += rift.health.get_max_health()
	_refresh_bar()


func _step(delta: float) -> void:
	for rift: SummoningRift in _push_in.keys():
		if not is_instance_valid(rift) or rift.is_dead():
			_push_in.erase(rift)
			continue
		var left: float = _push_in[rift] - delta
		if left <= 0.0:
			left = RiftRules.PUSH_INTERVAL
			_push_from(rift)
		_push_in[rift] = left
	if not _crystal_decided and not RiftRules.is_fast(elapsed) and objective != null and objective.has_time():
		objective.clear_time()
	_refresh_bar()


func get_rift_tile_count() -> int:
	return _wall_tiles.size() + _free_tiles.size()


func get_wall_rift_tiles() -> Array[Vector2i]:
	return _wall_tiles.duplicate()


func get_open_rifts() -> Array[SummoningRift]:
	var open: Array[SummoningRift] = []
	for i in rifts.size():
		var rift: Variant = rifts[i]
		if is_instance_valid(rift) and not (rift as SummoningRift).is_dead():
			open.append(rift)
	return open


func get_closed_count() -> int:
	return _closed


## The wall source a plan rift sends its enemies through (null for other rifts).
func get_source_of(rift: SummoningRift) -> SpawnSource:
	return _rift_sources.get(rift)


## Living enemies that are not rifts (the rule "fewer than RiftRules.MAX_ALIVE").
func get_alive_minions() -> int:
	var count := 0
	for enemy in get_living_enemies():
		if not enemy is SummoningRift:
			count += 1
	return count


## One push of a plan rift through its wall source (public for tests and tools): one enemy if the
## room allows it, plus the floor sources once a rift is closed.
func push_from(rift: SummoningRift) -> Array[Enemy]:
	return _push_from(rift)


func _push_from(rift: SummoningRift) -> Array[Enemy]:
	var enemies: Array[Enemy] = []
	if not RiftRules.can_summon(get_alive_minions()):
		return enemies
	var source: SpawnSource = _rift_sources.get(rift)
	if source == null or not is_instance_valid(source):
		return enemies
	rift.pulse()
	enemies = release_from([source] as Array[SpawnSource], 1)
	var vents := RiftRules.vent_count(_closed)
	if vents > 0 and RiftRules.can_summon(get_alive_minions()):
		var floor_sources := _floor_sources()
		if not floor_sources.is_empty():
			enemies.append_array(release_from([floor_sources[_rng.randi_range(0, floor_sources.size() - 1)]] as Array[SpawnSource], vents))
	return enemies


## A rift on tile, in the room but still and invulnerable (not yet tracked by the room).
func _place_rift(tile: Vector2i, in_wall: bool) -> SummoningRift:
	var rift := (load(RIFT_SCENE_PATH) as PackedScene).instantiate() as SummoningRift
	rift.data = load(RIFT_DATA_PATH) as EnemyData
	rift.name = "SummoningRift%d" % rifts.size()
	rift.position = RoomTiles.tile_center(tile) + (Vector2(0, -WALL_RIFT_LIFT) if in_wall else Vector2.ZERO)
	rift.in_wall = in_wall
	rift.arena = room.get_arena()
	rift.apply_scaling(room.room_index, false)
	var biome := room.spawner.get_biome(room.room_index)
	rift.rift_color = BIOME_COLORS.get(biome.id if biome != null else &"", Color.WHITE)
	room.enemy_container.add_child(rift)
	rift.begin_intro(GUARD_HOLD_TIME)
	rift.died.connect(_on_rift_closed)
	rift.health.health_changed.connect(_on_rift_health_changed)
	rifts.append(rift)
	_rift_tiles[rift] = tile
	return rift


## The wall rifts take their wall sources (built deferred by SpawnSources): the mode sends its
## enemies through them, the rift itself only shows it. No second hole beside the rift: the wall
## stays whole and closes with the rift (playtest 15.10.2026). Runs again at the fight start.
func _bind_wall_sources() -> void:
	for rift in get_open_rifts():
		if not rift.in_wall or _rift_sources.has(rift):
			continue
		var source := _wall_source_at(_rift_tiles.get(rift, VariantSpots.INVALID))
		if source != null:
			source.hide_opening()
			_rift_sources[rift] = source


## The fight starts: the rift wakes (hurtable, tracked by the room) and starts sending enemies.
func _open_rift(rift: SummoningRift, first_delay: float) -> void:
	_wake(rift)
	track_enemy(rift)
	if _rift_sources.has(rift):
		_push_in[rift] = first_delay
	else:
		rift.may_summon = _may_summon
		rift.summoner = _summon
		rift.activate(first_delay)
	if is_inside_tree():
		Burst.spawn(room.enemy_container, rift.global_position + Vector2(0, -40), rift.rift_color, 18, 150.0)
		Sfx.play_at(self, &"rift_open", rift.global_position, -6.0)


func _may_summon(_rift: SummoningRift) -> bool:
	return RiftRules.can_summon(get_alive_minions())


func _summon(_rift: SummoningRift, spot: Vector2) -> Array[Enemy]:
	if not RiftRules.can_summon(get_alive_minions()):
		return []
	var positions: Array[Vector2] = [room.enemy_container.to_local(spot)]
	return spawn_enemies(positions)


func _on_rift_closed(rift: Enemy) -> void:
	_closed += 1
	var source: SpawnSource = _rift_sources.get(rift as SummoningRift)
	if source != null and is_instance_valid(source):
		source.go_quiet()
	_push_in.erase(rift as SummoningRift)
	var left := get_open_rifts().size()
	if left > 0:
		show_banner(DungeonTexts.t(&"VARIANT_RIFT_CLOSED"), DungeonTexts.t(&"VARIANT_RIFT_CLOSED_SUB", [left]))
	else:
		_crystal_decided = true
		set_bonus(true)
		end_goal(true)
		show_banner(DungeonTexts.t(&"VARIANT_RIFT_CLOSED"), DungeonTexts.t(&"VARIANT_RIFTS_ALL_CLOSED_SUB"), BONUS_COLOR)
		give_crystals(RiftRules.fast_crystals(elapsed), &"MODE_RIFTS_FAST", &"MODE_RIFTS_FAST_SUB")
	_refresh_bar()


func _on_rift_health_changed(_current: float, _maximum: float) -> void:
	_refresh_bar()


func _on_room_done() -> void:
	if bonus == Bonus.ACHIEVED:
		var centre := room.content_anchor.position if room.content_anchor != null else Vector2(room.tiles.room_size) * RoomTiles.TILE_WORLD * 0.5
		spawn_bonus_chests(centre)
		show_banner(DungeonTexts.t(&"VARIANT_BONUS_TITLE"), DungeonTexts.t(&"VARIANT_BONUS_SUB"), BONUS_COLOR)


func _refresh_bar() -> void:
	# Before the fight (no health total yet) the label from _setup_objective stays.
	if objective == null or objective.is_finished() or rifts.is_empty() or _total_health <= 0.0:
		return
	var left := 0.0
	for rift in get_open_rifts():
		left += rift.health.get_health()
	objective.set_ratio(1.0 - left / maxf(0.001, _total_health))
	objective.set_label(DungeonTexts.t(&"OBJECTIVE_RIFTS", [get_open_rifts().size(), rifts.size()]))
	if objective.has_time():
		objective.set_time(maxf(0.0, RiftRules.FAST_TIME - elapsed))


## Floor tiles in front of the plan's wall rifts (Sources markers of kind rift_wall).
func _plan_rift_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for marker in room.get_sources_of(&"rift_wall"):
		var floor_tile: Vector2i = marker.get_meta(&"floor_tile", RoomTiles.local_to_tile(marker.position))
		tiles.append(floor_tile)
	return tiles


## The room's wall source in front of which tile lies (built by SpawnSources).
func _wall_source_at(tile: Vector2i) -> SpawnSource:
	var sources := get_sources()
	if sources == null:
		return null
	for source in sources.get_sources():
		if is_instance_valid(source) and source.kind == SpawnSourceRules.Kind.RIFT_WALL and source.floor_tile == tile:
			return source
	return null


## Floor sources (no wall rifts, no gates) away from the players for the vents' share.
func _floor_sources() -> Array[SpawnSource]:
	var result: Array[SpawnSource] = []
	var sources := get_sources()
	if sources == null:
		return result
	var players: Array[Vector2] = sources.get_player_states()[0]
	for source in sources.get_pool():
		if not source.is_wall_source() and WaveRules.distance_to_nearest(source.spot, players) >= SpawnSourceRules.MIN_PLAYER_DISTANCE:
			result.append(source)
	return result


## Free tiles at a wall, away from the doors; without enough of them any free tile away from the doors.
func _candidates() -> Array[Vector2i]:
	var doors: Array[Vector2i] = [room.tiles.get_entrance_inside_tile(), room.tiles.get_exit_inside_tile()]
	var at_walls := VariantSpots.wall_tiles(_free, room.tiles.get_walkable_tiles(), doors, RiftRules.DOOR_CLEARANCE)
	if at_walls.size() >= RiftRules.COUNT.y:
		return at_walls
	var any: Array[Vector2i] = []
	for tile: Vector2i in VariantSpots.sorted_tiles(_free):
		if VariantSpots.is_clear_of(tile, doors, RiftRules.DOOR_CLEARANCE):
			any.append(tile)
	return any

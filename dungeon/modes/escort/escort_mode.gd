class_name EscortMode
extends CombatVariant
## Minigame "Geleit" (KONZEPT_RAEUME_V2 §3.3, design answer 01_raumarten.md, R4a): a lost villager
## with a small lantern waits in the room (plan marker escort_start); after the intro he walks a
## glowing path to the exit. Enemies go for him first (EnemyDecoy, EscortRules.TARGET_SHARE). He stops
## and calls for help while an enemy is closer than 3 tiles and walks 1.2 times faster with a player
## beside him. Every enemy hit costs him a heart. Rarely (5 %) it is a chicken with a lantern.
##   Arrived: success - the remaining enemies flee from his light (they fall), a bonus chest appears
##            at the exit and the rescue is noted in the save (RescueRecord, the village shows it, R7).
##   Fallen:  no bonus - the enemies stay, the room is cleared as usual. Never costs the run.
## The room stays shut while he walks (holds_completion). Task bar: his hearts, progress in %, a status
## line while he stands or walks faster. Pushes of enemies out of sources near his way keep it busy.
## Decisions (walk, stop, arrive, fall) emit signals and change state; looks follow (LostVillager,
## EscortPathView). Randomness: the variant RNG (seeded once from the dungeon RNG). Co-op: every
## living player counts for "beside him", one more heart per extra player.

## He reached the exit (chicken: the rare chicken).
signal rescued(mode: EscortMode, chicken: bool)
## His last heart is gone.
signal villager_lost(mode: EscortMode)

enum Walk { WAITING, WALKING, STOPPED, ARRIVED, DOWN }

## Seconds he needs to walk out through the opened exit before he fades.
const LEAVE_TIME := 1.2

var villager: LostVillager = null
var path_view: EscortPathView = null
var objective: RoomObjective = null
var is_chicken := false
var walk_state := Walk.WAITING
## Tiles of his way (room-local), from his start to the tile inside the exit.
var path_tiles: Array[Vector2i] = []
## Room-local feet positions along the way (tile centres).
var path_points := PackedVector2Array()
var path_total := 0.0
var travelled := 0.0
var pushes_sent := 0

var _elapsed := 0.0
var _since_push := 0.0
var _help_left := 0.0
var _player_beside := false
var _tint := Color.WHITE


## Hangs the escort mode onto a prepared normal combat room (like CombatVariant.attach_to; until the
## R4b mode table registers it, tests and tools use this). rng_seed: one number of the dungeon RNG,
## drawn by the caller in any case. null if the room cannot host it (no way to the exit).
static func attach(target: RoomController, rng_seed: int) -> EscortMode:
	if target == null or not is_instance_valid(target) or not target.has_room_kind() or CombatVariant.of(target) != null:
		return null
	var mode := EscortMode.new()
	mode.variant_id = EscortRules.ID
	mode.room = target
	mode.context = target.context
	mode._rng.seed = rng_seed
	mode._free = VariantSpots.free_tiles(target)
	if not mode.can_host():
		mode.free()
		return null
	mode.name = NODE_NAME
	mode.y_sort_enabled = true
	target.add_child(mode)
	mode._connect_room()
	mode._on_attach()
	return mode


# --- CombatVariant ---

func can_host() -> bool:
	_plan_path()
	return path_tiles.size() >= 2


func _on_attach() -> void:
	is_chicken = EscortRules.is_chicken(_rng.randf())
	_tint = LostVillager.CLOAK_TINTS[_rng.randi() % LostVillager.CLOAK_TINTS.size()]
	if path_tiles.is_empty():
		_plan_path()
	# Built right away: he already waits behind the open door, his lantern glows through it.
	villager = LostVillager.new()
	villager.name = "LostVillager"
	villager.build(is_chicken, EscortRules.max_hearts(1), _tint)
	villager.position = path_points[0] - Player.FEET_OFFSET
	add_child(villager)
	villager.hit.connect(_on_villager_hit)
	villager.fell.connect(_on_villager_fell)
	path_view = EscortPathView.new()
	path_view.name = "EscortPath"
	path_view.build(path_tiles)
	add_child(path_view)
	for tile in path_tiles:
		_free.erase(tile)


## Fewer enemies at the start: the pushes along his way bring the rest.
func _shape_group(group: EncounterGroup) -> EncounterGroup:
	return VariantEncounterGroup.wrap(group, self, EscortRules.ENCOUNTER_FACTOR)


## The room is entered: goal, task bar and intro (camera on him, banner, 3-2-1), the path lights up.
func _on_room_player_entered(entered_room: RoomController) -> void:
	super(entered_room)
	begin_intro()


func _on_start() -> void:
	if objective == null:
		# Started without an entry (tools): goal and bar without the intro.
		_create_objective()
		path_view.reveal()
	var players := get_player_count()
	if players > 1:
		villager.set_max_hearts(EscortRules.max_hearts(players))
	walk_state = Walk.WALKING
	for enemy in get_living_enemies():
		_choose_target(enemy)
	_refresh_bar()


func holds_completion() -> bool:
	return _started and not _finished and (walk_state == Walk.WALKING or walk_state == Walk.STOPPED)


func _is_bonus_met() -> bool:
	return walk_state == Walk.ARRIVED


func _on_finish() -> void:
	if villager == null or not is_instance_valid(villager):
		return
	if walk_state == Walk.ARRIVED:
		# The exit opens: he walks out through it and is on his way home.
		_walk_out()
	elif walk_state == Walk.DOWN:
		villager.fade_out(1.2)


func _on_enemy_added(enemy: Enemy) -> void:
	_choose_target(enemy)


func _physics_process(delta: float) -> void:
	if _started and not _finished:
		step(delta)


## One step of the escort (public for tests and tools: a large delta fast-forwards his walk).
func step(delta: float) -> void:
	if not _started or (walk_state != Walk.WALKING and walk_state != Walk.STOPPED):
		return
	_elapsed += delta
	_since_push += delta
	if EscortRules.should_push(_since_push, _elapsed, get_living_enemies().size()):
		send_push()
	var feet := villager.global_position + Player.FEET_OFFSET
	var stop := EscortRules.should_stop(nearest_enemy_distance())
	_player_beside = EscortRules.is_player_beside(_nearest_player_distance(feet))
	if stop:
		if walk_state != Walk.STOPPED:
			walk_state = Walk.STOPPED
			_help_left = 0.0
		_help_left -= delta
		if _help_left <= 0.0:
			_call_for_help()
		villager.set_look(LostVillager.Look.SCARED, _facing_left())
	else:
		walk_state = Walk.WALKING
		travelled = minf(path_total, travelled + EscortRules.walk_speed(_player_beside) * delta)
		_place_villager()
		villager.set_look(LostVillager.Look.WALK, _facing_left())
	path_view.set_progress(get_progress())
	_refresh_bar()
	if path_total - travelled <= EscortRules.ARRIVE_DISTANCE:
		_arrive()


## Share of the way done (0..1).
func get_progress() -> float:
	return EscortRules.progress(travelled, path_total)


func is_villager_alive() -> bool:
	return villager != null and is_instance_valid(villager) and villager.is_alive()


func is_player_beside() -> bool:
	return _player_beside


## Distance from the villager to the nearest enemy that is out of its source (INF without).
func nearest_enemy_distance() -> float:
	if villager == null or not is_instance_valid(villager):
		return INF
	var nearest := INF
	for enemy in get_living_enemies():
		if enemy.is_hidden_in_source() or enemy.is_emerging():
			continue
		nearest = minf(nearest, enemy.global_position.distance_to(villager.global_position))
	return nearest


## Starts goal, task bar and intro once (room entered). Public for tools that stage rooms.
func begin_intro() -> void:
	if objective != null or _finished:
		return
	_create_objective()
	path_view.reveal()
	villager.say(_help_text())
	RoomIntro.start(room, objective, villager.global_position)


## A small push out of the sources near his way (at least PUSH_MIN_PLAYER_DISTANCE from every player).
## Returns the enemies (tracked by the room).
func send_push() -> Array[Enemy]:
	_since_push = 0.0
	var sources := SpawnSources.of(room)
	if sources == null or villager == null:
		return []
	var chosen := _push_sources(sources)
	if chosen.is_empty():
		return []
	var positions: Array[Vector2] = []
	for source in chosen:
		positions.append(source.spot)
	var enemies := room.spawner.spawn_enemies(room.room_index, positions, room.enemy_container, _spawn_context(), room.get_arena())
	sources.release(enemies, chosen)
	for enemy in enemies:
		track_enemy(enemy)
	if not enemies.is_empty():
		pushes_sent += 1
	return enemies


# --- Decisions ---

func _arrive() -> void:
	if walk_state == Walk.ARRIVED or walk_state == Walk.DOWN:
		return
	walk_state = Walk.ARRIVED
	travelled = path_total
	_place_villager()
	villager.set_rescued()
	villager.say(DungeonTexts.t(&"MODE_ESCORT_CHICKEN_THANKS" if is_chicken else &"MODE_ESCORT_THANKS"), 2.4)
	set_bonus(true)
	RescueRecord.record(is_chicken)
	rescued.emit(self, is_chicken)
	if objective != null:
		objective.set_status("")
		objective.set_ratio(1.0)
		objective.finish(true)
	path_view.fade_all()
	show_banner(DungeonTexts.t(&"MODE_ESCORT_RESCUED_TITLE"), DungeonTexts.t(&"MODE_ESCORT_CHICKEN_RESCUED_SUB" if is_chicken else &"MODE_ESCORT_RESCUED_SUB"), BONUS_COLOR)
	if is_inside_tree():
		Sfx.play_ui(self, &"upgrade", -4.0)
		LightSource.flash(self, villager.global_position, 420.0, 0.6)
	spawn_bonus_chests(_chest_spot())
	_dispel_enemies()
	room.check_completion()


func _on_villager_fell(_villager: LostVillager) -> void:
	if walk_state == Walk.ARRIVED or walk_state == Walk.DOWN:
		return
	walk_state = Walk.DOWN
	set_bonus(false)
	villager_lost.emit(self)
	if objective != null:
		objective.set_status("")
		objective.finish(false)
	path_view.fade_all()
	show_banner(DungeonTexts.t(&"MODE_ESCORT_CHICKEN_LOST_TITLE" if is_chicken else &"MODE_ESCORT_LOST_TITLE"), DungeonTexts.t(&"MODE_ESCORT_LOST_SUB"), LOST_COLOR)
	# The enemies stay: the room is cleared as usual.
	room.check_completion()


func _on_villager_hit(_villager: LostVillager, _damage: DamageData) -> void:
	_refresh_bar()


## 60 % of the enemies go for him (one roll each, variant RNG) while he is a target.
func _choose_target(enemy: Enemy) -> void:
	if enemy.has_meta(&"escort_rolled") or not is_villager_alive():
		return
	enemy.set_meta(&"escort_rolled", true)
	if EscortRules.targets_villager(_rng.randf()):
		EnemyDecoy.assign(enemy, villager)


## Sources for a push: not busy, far enough from every player, within the band around him; nearest
## to the point a few tiles ahead of him on his way first.
func _push_sources(sources: SpawnSources) -> Array[SpawnSource]:
	var players := get_players()
	var ahead := room.to_global(EscortRules.point_at(path_points, travelled + RoomTiles.TILE_WORLD * 3.0))
	var near := villager.global_position
	var in_band: Array[SpawnSource] = []
	var fallback: Array[SpawnSource] = []
	for source in sources.get_pool():
		if source.is_active():
			continue
		var spot := sources.to_global(source.spot)
		var clear := true
		for player in players:
			if player.global_position.distance_to(spot) < EscortRules.PUSH_MIN_PLAYER_DISTANCE:
				clear = false
				break
		if not clear:
			continue
		var distance := spot.distance_to(near)
		if distance >= EscortRules.PUSH_VILLAGER_RANGE.x and distance <= EscortRules.PUSH_VILLAGER_RANGE.y:
			in_band.append(source)
		elif distance >= EscortRules.PUSH_VILLAGER_RANGE.x:
			fallback.append(source)
	var pool := in_band if not in_band.is_empty() else fallback
	pool.sort_custom(func(a: SpawnSource, b: SpawnSource) -> bool:
		return sources.to_global(a.spot).distance_to(ahead) < sources.to_global(b.spot).distance_to(ahead))
	var chosen: Array[SpawnSource] = []
	for source in pool:
		if chosen.size() >= EscortRules.PUSH_SIZE:
			break
		chosen.append(source)
	# One source may bring two when only one fits.
	while not chosen.is_empty() and chosen.size() < EscortRules.PUSH_SIZE:
		chosen.append(chosen[0])
	return chosen


# --- Effects ---

func _create_objective() -> void:
	objective = RoomObjective.create(RoomObjective.ESCORT)
	if is_chicken:
		objective.goal_key = &"MODE_ESCORT_CHICKEN_GOAL"
	RoomObjective.attach(room, objective)
	_refresh_bar()


func _refresh_bar() -> void:
	if objective == null or objective.is_finished():
		return
	objective.set_label(DungeonTexts.t(&"OBJECTIVE_ESCORT_HEARTS", [villager.hearts, villager.max_hearts]))
	objective.set_ratio(get_progress())
	objective.set_danger(villager.hearts <= 1)
	var status := ""
	if walk_state == Walk.STOPPED:
		status = DungeonTexts.t(&"OBJECTIVE_ESCORT_CHICKEN_STOPPED" if is_chicken else &"OBJECTIVE_ESCORT_STOPPED")
	elif walk_state == Walk.WALKING and _player_beside:
		status = DungeonTexts.t(&"OBJECTIVE_ESCORT_CHICKEN_FAST" if is_chicken else &"OBJECTIVE_ESCORT_FAST")
	objective.set_status(status)


func _call_for_help() -> void:
	_help_left = EscortRules.HELP_CALL_INTERVAL
	villager.say(_help_text())
	if is_inside_tree():
		Sfx.play_at(self, &"escort_help", villager.global_position, -4.0)


func _help_text() -> String:
	return DungeonTexts.t(&"MODE_ESCORT_CHICKEN_HELP" if is_chicken else &"MODE_ESCORT_HELP")


func _place_villager() -> void:
	villager.position = EscortRules.point_at(path_points, travelled) - Player.FEET_OFFSET


func _facing_left() -> bool:
	var here := EscortRules.point_at(path_points, travelled)
	var next := EscortRules.point_at(path_points, travelled + 24.0)
	return next.x < here.x - 0.5


## His light drives the rest off: every enemy left falls apart (the room may close).
func _dispel_enemies() -> void:
	for enemy in get_living_enemies():
		if is_inside_tree():
			Burst.spawn(self, enemy.global_position, LightPalette.WARM, 10, 120.0, 0.5)
		enemy.health.take_damage(INF)


## Chest next to the exit, at the end of his way (room-local).
func _chest_spot() -> Vector2:
	var inward := -RoomTiles.SIDE_DIRECTIONS[room.tiles.exit_side]
	var end := path_tiles[path_tiles.size() - 1]
	return RoomTiles.tile_center(end + inward)


func _walk_out() -> void:
	if not is_inside_tree():
		villager.queue_free()
		return
	var door := RoomTiles.tile_center(room.get_exit_tile())
	var outward := Vector2(RoomTiles.SIDE_DIRECTIONS[room.tiles.exit_side])
	var target := door + outward * RoomTiles.TILE_WORLD * 0.5 - Player.FEET_OFFSET
	villager.set_look(LostVillager.Look.WALK, target.x < villager.position.x - 0.5)
	var tween := villager.create_tween()
	tween.tween_interval(0.5)
	tween.tween_property(villager, "position", target, LEAVE_TIME)
	tween.tween_callback(villager.fade_out.bind(0.5))


# --- Way ---

## His way: from the plan's escort_start (else a free tile just inside the entrance) to the tile
## inside the exit, over walkable floor without props, sources and abysses; water costs more.
func _plan_path() -> void:
	path_tiles.clear()
	path_points = PackedVector2Array()
	path_total = 0.0
	var tiles := room.tiles
	var walkable: Dictionary[Vector2i, bool] = {}
	var floor_rect := Rect2i(Vector2i.ZERO, tiles.room_size)
	for tile: Vector2i in tiles.get_walkable_tiles():
		if floor_rect.has_point(tile) and not tiles.is_navigation_blocked(tile):
			walkable[tile] = true
	for marker in room.get_sources():
		walkable.erase(marker.get_meta(&"tile", RoomTiles.local_to_tile(marker.position)))
	for node in VariantSpots.occupied_nodes(room):
		if RoomController.is_solid_prop(node):
			walkable.erase(RoomTiles.local_to_tile(node.position))
	var water: Dictionary[Vector2i, bool] = {}
	for tile in tiles.get_water_tiles():
		water[tile] = true
	var goal := tiles.get_exit_inside_tile()
	walkable[goal] = true
	var start := _start_tile(walkable)
	if start == VariantSpots.INVALID:
		return
	path_tiles = EscortRules.find_path(walkable, water, start, goal)
	for tile in path_tiles:
		path_points.append(RoomTiles.tile_center(tile))
	path_total = EscortRules.path_length(path_points)


func _start_tile(walkable: Dictionary[Vector2i, bool]) -> Vector2i:
	for marker in room.get_objectives_of(EscortRules.START_MARKER):
		var tile: Vector2i = marker.get_meta(&"tile", RoomTiles.local_to_tile(marker.position))
		if walkable.has(tile):
			return tile
	# No plan marker: two tiles inside the entrance, on the nearest walkable tile.
	var inward := -RoomTiles.SIDE_DIRECTIONS[room.tiles.entrance_side]
	var wanted := room.tiles.get_entrance_inside_tile() + inward * 2
	var best := VariantSpots.INVALID
	var best_distance := INF
	for tile: Vector2i in walkable:
		var distance := Vector2(tile - wanted).length()
		if distance < best_distance - 0.001 or (absf(distance - best_distance) <= 0.001 and EscortRules._tile_before(tile, best)):
			best = tile
			best_distance = distance
	return best


func _nearest_player_distance(feet: Vector2) -> float:
	var nearest := INF
	for player in get_players():
		nearest = minf(nearest, player.get_feet_position().distance_to(feet))
	return nearest

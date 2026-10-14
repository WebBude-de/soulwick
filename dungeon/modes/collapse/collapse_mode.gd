class_name CollapseMode
extends CombatVariant
## Minigame "Einsturz" (KONZEPT_RAEUME_V2 §3.10, design answer 01_raumarten.md, R4a): banner "Der
## Boden bricht – überlebe 30 s"; the floor breaks in fields of 2×2 tiles in a fixed order from the
## outside in (CollapseRules): the next three carry faint cracks, a field about to go cracks open over
## a red glow for 1 s, then it is abyss (RoomTiles.add_pit_tiles). Enemies on it fall (a kill), so do
## props and spawn sources; champions and golems that never fall are pushed onto solid floor.
## Players fall like on any abyss (PlayerFall, D-115: a whole heart); they land on the way that stays,
## next to where they fell (PlayerFall.set_landing), never on floor that is about to break.
##   After 30 s: only the way from the entrance to the exit stands, the bonus chest waits at its end;
##   the rest of the enemies is beaten as usual. Never costs the run (only the falls cost hearts).
## The room stays shut while the floor breaks (holds_completion). Task bar: time, the rooms thirds
## of the next fields, red while a player stands on a field about to break. Decisions (warn, break,
## survive) change state and emit signals; looks follow (CollapseView). Randomness: the variant RNG
## (order among fields equally far out).

signal field_warned(mode: CollapseMode, index: int)
signal field_broken(mode: CollapseMode, index: int, tiles: Array[Vector2i])
signal survived(mode: CollapseMode)

enum FieldState { STANDING, WARNED, BROKEN }

var objective: RoomObjective = null
var view: CollapseView = null
## Fields in the order they break (Array of Array[Vector2i], room-local tiles).
var fields: Array = []
var field_states: Array[FieldState] = []
var break_at := PackedFloat32Array()
## The way that stays (room-local tiles).
var kept: Dictionary[Vector2i, bool] = {}
## Shortest way from the entrance to the exit (the middle of the kept way).
var way: Array[Vector2i] = []
var clock := 0.0
var broken_count := 0
var is_survived := false
var pushes_sent := 0

var _since_push := CollapseRules.PUSH_INTERVAL
var _marked: Array[Vector2i] = []
## Players whose falls land on the way while the floor breaks (connected once each).
var _watched: Array[Player] = []


## Hangs the collapse mode onto a prepared normal combat room (like CombatVariant.attach_to; until the
## R4b mode table registers it, tests and tools use this). rng_seed: one number of the dungeon RNG.
## null if the room has no way from the entrance to the exit or nothing that could break.
static func attach(target: RoomController, rng_seed: int) -> CollapseMode:
	if target == null or not is_instance_valid(target) or not target.has_room_kind() or CombatVariant.of(target) != null:
		return null
	var mode := CollapseMode.new()
	mode.variant_id = CollapseRules.ID
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
	_plan_way()
	return way.size() >= 2


func _on_attach() -> void:
	if way.is_empty():
		_plan_way()
	for marker in room.get_objectives_of(CollapseRules.FIELD_MARKER):
		_marked.append(marker.get_meta(&"tile", RoomTiles.local_to_tile(marker.position)))
	fields = CollapseRules.build_fields(_floor_tiles(), kept, _marked, _rng)
	break_at = CollapseRules.break_times(fields.size())
	field_states.clear()
	for i in fields.size():
		field_states.append(FieldState.STANDING)
	# Built right away: the cracked plates already show through the open door.
	view = CollapseView.new()
	view.name = "CollapseView"
	view.setup(fields, _marked)
	add_child(view)
	view.set_queued(get_next_fields())


func _shape_group(group: EncounterGroup) -> EncounterGroup:
	return VariantEncounterGroup.wrap(group, self, CollapseRules.ENCOUNTER_FACTOR)


## The room is entered: goal, task bar and intro (camera on the first field, banner, 3-2-1).
func _on_room_player_entered(entered_room: RoomController) -> void:
	super(entered_room)
	begin_intro()


func _on_start() -> void:
	if objective == null:
		_create_objective()
	clock = 0.0
	_watch_falls()
	_refresh_bar()


func _on_finish() -> void:
	for player in _watched:
		if is_instance_valid(player) and player.fall != null and player.fall.fall_started.is_connected(_on_player_fall_started):
			player.fall.fall_started.disconnect(_on_player_fall_started)
	_watched.clear()


func _exit_tree() -> void:
	_on_finish()


func holds_completion() -> bool:
	return _started and not _finished and not is_survived


func _is_bonus_met() -> bool:
	return is_survived


func _physics_process(delta: float) -> void:
	if _started and not _finished:
		step(delta)


## One step of the collapse (public for tests and tools: a large delta breaks everything due).
func step(delta: float) -> void:
	if not _started or is_survived:
		return
	var left := delta
	while left > 0.0 and not is_survived:
		var part := minf(left, 0.25)
		left -= part
		_advance(part)
	_drop_what_stands_on_pits()
	_watch_falls()
	_refresh_bar()


## Starts goal, task bar and intro once (room entered). Public for tools that stage rooms.
func begin_intro() -> void:
	if objective != null or _finished:
		return
	_create_objective()
	var focus := room.to_global(CollapseRules.field_center(fields[0])) if not fields.is_empty() else Vector2.INF
	RoomIntro.start(room, objective, focus)


## Indices of the next LOOKAHEAD fields that still stand (warned ones included).
func get_next_fields() -> Array[int]:
	var next: Array[int] = []
	for i in fields.size():
		if field_states[i] != FieldState.BROKEN:
			next.append(i)
			if next.size() >= CollapseRules.LOOKAHEAD:
				break
	return next


func get_time_left() -> float:
	return maxf(0.0, CollapseRules.DURATION - clock)


## Is the room-local tile part of a field that is about to break?
func is_warned_tile(tile: Vector2i) -> bool:
	for i in fields.size():
		if field_states[i] == FieldState.WARNED and (fields[i] as Array).has(tile):
			return true
	return false


## Pushes out of floor sources still standing, away from every player. Returns the enemies.
func send_push() -> Array[Enemy]:
	_since_push = 0.0
	var sources := SpawnSources.of(room)
	if sources == null:
		return []
	var players := get_players()
	var pool: Array[SpawnSource] = []
	for source in sources.get_pool():
		if source.is_active() or not source.visible:
			continue
		if not source.is_wall_source() and room.tiles.is_pit(RoomTiles.local_to_tile(source.spot)):
			continue
		var spot := sources.to_global(source.spot)
		var clear := true
		for player in players:
			if player.global_position.distance_to(spot) < CollapseRules.PUSH_MIN_PLAYER_DISTANCE:
				clear = false
				break
		if clear:
			pool.append(source)
	if pool.is_empty():
		return []
	var chosen: Array[SpawnSource] = []
	for i in CollapseRules.PUSH_SIZE:
		chosen.append(pool[_rng.randi_range(0, pool.size() - 1)])
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

func _advance(delta: float) -> void:
	clock += delta
	_since_push += delta
	for i in fields.size():
		if field_states[i] == FieldState.STANDING and CollapseRules.should_warn(clock, break_at[i]):
			_warn(i)
		if field_states[i] == FieldState.WARNED and CollapseRules.should_break(clock, break_at[i]):
			_break(i)
	if CollapseRules.should_push(clock, _since_push, get_living_enemies().size()):
		send_push()
	if CollapseRules.is_survived(clock):
		_survive()


func _warn(index: int) -> void:
	field_states[index] = FieldState.WARNED
	view.warn(index)
	field_warned.emit(self, index)
	if is_inside_tree():
		Sfx.play_at(self, &"collapse_crack", room.to_global(CollapseRules.field_center(fields[index])), -4.0)


func _break(index: int) -> void:
	field_states[index] = FieldState.BROKEN
	broken_count += 1
	var tiles: Array[Vector2i] = []
	tiles.assign(fields[index])
	room.tiles.add_pit_tiles(tiles)
	for tile in tiles:
		_free.erase(tile)
	view.crumble(index)
	view.set_queued(get_next_fields())
	_drop_on(tiles)
	field_broken.emit(self, index, tiles)
	if is_inside_tree():
		Sfx.play_at(self, &"collapse_fall", room.to_global(CollapseRules.field_center(fields[index])), -3.0)
		CameraShake.shake(self, 2.0)


func _survive() -> void:
	if is_survived:
		return
	is_survived = true
	# Fields still due break now (a large fast-forward step), so the way alone stands.
	for i in fields.size():
		if field_states[i] != FieldState.BROKEN:
			_break(i)
	set_bonus(true)
	survived.emit(self)
	if objective != null:
		objective.set_status("")
		objective.finish(true)
	show_banner(DungeonTexts.t(&"MODE_COLLAPSE_DONE_TITLE"), DungeonTexts.t(&"MODE_COLLAPSE_DONE_SUB"), BONUS_COLOR)
	spawn_bonus_chests(RoomTiles.tile_center(_chest_tile()))
	room.check_completion()


## Everything standing on the broken tiles goes down with them: enemies fall (champions and golems,
## who never fall, step onto solid floor), props and floor sources sink into the dark.
func _drop_on(tiles: Array[Vector2i]) -> void:
	var broken: Dictionary[Vector2i, bool] = {}
	for tile in tiles:
		broken[tile] = true
	for enemy in get_living_enemies():
		if broken.has(_enemy_tile(enemy)):
			_drop_enemy(enemy)
	var props := room.get_node_or_null("Props")
	if props != null:
		for prop in props.get_children():
			var node := prop as Node2D
			if node != null and not node is TreasureChest and broken.has(RoomTiles.local_to_tile(node.position)):
				_sink(node, true)
	var sources := SpawnSources.of(room)
	if sources != null:
		for source in sources.get_sources():
			if not source.is_wall_source() and source.visible and broken.has(RoomTiles.local_to_tile(source.spot)):
				source.go_quiet()
				_sink(source, false)


## Enemies that came out over a hole later (a wave from a source that fell) go down too.
func _drop_what_stands_on_pits() -> void:
	for enemy in get_living_enemies():
		if enemy.is_hidden_in_source() or enemy.is_emerging() or enemy.is_airborne():
			continue
		if room.tiles.is_pit(_enemy_tile(enemy)):
			_drop_enemy(enemy)


func _drop_enemy(enemy: Enemy) -> void:
	if enemy.is_hidden_in_source() or enemy.is_emerging():
		return
	if enemy.can_fall_into_pit():
		enemy.fall_into_pit()
		return
	var tile := _nearest_solid(_enemy_tile(enemy))
	if tile != VariantSpots.INVALID:
		enemy.global_position = room.to_global(RoomTiles.tile_center(tile))
		if is_inside_tree():
			Burst.spawn(self, enemy.global_position, Color(0.55, 0.5, 0.48), 8, 90.0)


## A prop or source sinks into the abyss (shrinks and fades); props are freed, sources only hidden
## (the room's SpawnSources keeps its list).
func _sink(node: Node2D, free_it: bool) -> void:
	if not is_inside_tree():
		if free_it:
			node.queue_free()
		else:
			node.visible = false
		return
	var tween := node.create_tween().set_parallel()
	tween.tween_property(node, "scale", node.scale * 0.3, 0.45).set_ease(Tween.EASE_IN)
	tween.tween_property(node, "modulate:a", 0.0, 0.45)
	if free_it:
		tween.chain().tween_callback(node.queue_free)
	else:
		tween.chain().tween_callback(node.hide)


## A player falls in this room: the landing is the tile of the way nearest to the fall (the room's
## choice, D-115 allows it); the damage stays the rule's.
func _on_player_fall_started(player: Player) -> void:
	if _finished or not is_inside_tree() or player == null:
		return
	var feet := room.to_local(player.get_feet_position())
	if not Rect2(Vector2.ZERO, Vector2(room.tiles.room_size) * RoomTiles.TILE_WORLD).grow(RoomTiles.TILE_WORLD).has_point(feet):
		return
	var tile := landing_tile(RoomTiles.local_to_tile(feet))
	if tile != VariantSpots.INVALID:
		player.fall.set_landing(room.to_global(RoomTiles.tile_center(tile)))


## Tile of the way that stays nearest to from (never a pit, never under a prop).
func landing_tile(from: Vector2i) -> Vector2i:
	var best := VariantSpots.INVALID
	var best_distance := INF
	for tile: Vector2i in kept:
		if room.tiles.is_pit(tile) or room.tiles.is_navigation_blocked(tile):
			continue
		var distance := Vector2(tile - from).length()
		if distance < best_distance - 0.001 or (absf(distance - best_distance) <= 0.001 and CollapseRules._tile_before(tile, best)):
			best = tile
			best_distance = distance
	return best


func _watch_falls() -> void:
	for player in get_players():
		if player.fall != null and not _watched.has(player):
			_watched.append(player)
			player.fall.fall_started.connect(_on_player_fall_started)


# --- Effects ---

func _create_objective() -> void:
	objective = RoomObjective.create(RoomObjective.COLLAPSE)
	objective.goal_args = [roundi(CollapseRules.DURATION)]
	RoomObjective.attach(room, objective)
	objective.set_time(CollapseRules.DURATION, false)
	_refresh_bar()


func _refresh_bar() -> void:
	if objective == null or objective.is_finished():
		return
	var names: Array[String] = []
	for index in get_next_fields():
		var place := DungeonTexts.t(CollapseRules.compass_key(fields[index], room.tiles.room_size))
		if not names.has(place):
			names.append(place)
	if names.is_empty():
		objective.set_label(DungeonTexts.t(&"OBJECTIVE_COLLAPSE_HOLD"))
	else:
		objective.set_label(DungeonTexts.t(&"OBJECTIVE_COLLAPSE_NEXT", [" · ".join(names)]))
	objective.set_ratio(clock / CollapseRules.DURATION)
	if _started:
		objective.set_time(get_time_left(), true)
	var on_warned := false
	for player in get_players():
		if is_warned_tile(RoomTiles.local_to_tile(room.to_local(player.get_feet_position()))):
			on_warned = true
			break
	objective.set_danger(on_warned)
	objective.set_status(DungeonTexts.t(&"OBJECTIVE_COLLAPSE_RUN") if on_warned else "")


# --- Layout ---

## The way that stays: shortest way from the entrance to the exit over floor without props and
## sources, widened, plus the tiles in front of every door and a way to every chest of the plan.
func _plan_way() -> void:
	way.clear()
	kept.clear()
	var floor_tiles := _floor_tiles()
	var walkable := floor_tiles.duplicate()
	for tile: Vector2i in floor_tiles:
		if room.tiles.is_navigation_blocked(tile):
			walkable.erase(tile)
	for marker in room.get_sources():
		walkable.erase(marker.get_meta(&"tile", RoomTiles.local_to_tile(marker.position)))
	var start := room.tiles.get_entrance_inside_tile()
	var goal := room.tiles.get_exit_inside_tile()
	walkable[start] = true
	walkable[goal] = true
	way = CollapseRules.shortest_way(walkable, start, goal)
	if way.is_empty():
		return
	var all_ways := way.duplicate()
	# A second exit (branch) keeps its way too.
	for other in room.tiles.get_exit_inside_tiles():
		if other != goal:
			walkable[other] = true
			all_ways.append_array(CollapseRules.shortest_way(walkable, start, other))
	kept = CollapseRules.widen(all_ways, floor_tiles, CollapseRules.WAY_HALF_WIDTH)
	var doors: Array[Vector2i] = [Vector2i(room.tiles.entrance_side, room.tiles.entrance_x)]
	doors.append_array(room.tiles.get_exit_doors())
	for door in doors:
		for tile in RoomTiles.door_lane_of(door.x, door.y, room.tiles.room_size, CollapseRules.DOOR_DEPTH):
			if floor_tiles.has(tile):
				kept[tile] = true
	# Chests of the plan stay reachable.
	var props := room.get_node_or_null("Props")
	if props != null:
		for prop in props.get_children():
			if prop is TreasureChest:
				var chest_tile := RoomTiles.local_to_tile((prop as Node2D).position)
				walkable[chest_tile] = true
				for tile in CollapseRules.shortest_way(walkable, chest_tile, start):
					if kept.has(tile):
						break
					kept[tile] = true


## Floor that may break or stays: inside the floor rectangle, no wall, no abyss.
func _floor_tiles() -> Dictionary[Vector2i, bool]:
	var floor_tiles: Dictionary[Vector2i, bool] = {}
	var floor_rect := Rect2i(Vector2i.ZERO, room.tiles.room_size)
	for tile: Vector2i in room.tiles.get_walkable_tiles():
		if floor_rect.has_point(tile):
			floor_tiles[tile] = true
	for tile: Vector2i in room.tiles.get_runtime_pit_tiles():
		floor_tiles.erase(tile)
	return floor_tiles


## The chest at the end of the way: the kept tile nearest to the exit, off the door lane.
func _chest_tile() -> Vector2i:
	var exit_inside := room.tiles.get_exit_inside_tile()
	var inward := -RoomTiles.SIDE_DIRECTIONS[room.tiles.exit_side]
	var wanted := exit_inside + inward * 2
	var best := exit_inside
	var best_distance := INF
	for tile: Vector2i in kept:
		if room.tiles.is_pit(tile) or room.tiles.is_navigation_blocked(tile) or way.has(tile):
			continue
		var distance := Vector2(tile - wanted).length()
		if distance < best_distance - 0.001 or (absf(distance - best_distance) <= 0.001 and CollapseRules._tile_before(tile, best)):
			best = tile
			best_distance = distance
	return best


func _nearest_solid(from: Vector2i) -> Vector2i:
	var best := VariantSpots.INVALID
	var best_distance := INF
	for tile: Vector2i in room.tiles.get_walkable_tiles():
		if not Rect2i(Vector2i.ZERO, room.tiles.room_size).has_point(tile):
			continue
		var distance := Vector2(tile - from).length()
		if distance < best_distance:
			best = tile
			best_distance = distance
	return best


func _enemy_tile(enemy: Enemy) -> Vector2i:
	return RoomTiles.local_to_tile(room.to_local(enemy.global_position + Vector2(0, 8)))

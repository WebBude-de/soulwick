class_name RoomMode
extends CombatVariant
## A minigame of a combat room (RAEUME §1, §3, D-120): one goal in one sentence, the same
## intro (door, camera on the goal, banner, 3-2-1), a task bar, a clear end and a bonus. The base of
## Flamme hüten, Reliquie holen, Risse schließen, Jagd and Lichtfeuer (R4b) and of R4a's modes.
##
## What a mode gets here:
##   - goal and intro: when the first player walks in, a RoomObjective of objective_mode is attached
##     to the room and RoomIntro starts with the camera on get_focus() (_setup_objective fills it).
##     RoomController.activate() waits for the intro (RoomIntro.after_intro). The goal is ended with
##     end_goal(success); a goal still open when the room is done ends with the bonus.
##   - guards from the plan (Objectives markers "guard", metadata enemy): place_guard() puts them in
##     the room before the fight, still and invulnerable (Enemy.begin_intro), release_guards() lets
##     them fight. A mode that brings its whole first wave itself (guards, the crowned one) answers
##     uses_own_first_wave() and the RoomController hook RoomVariants.spawn_first_wave() takes it
##     instead of a wave out of the sources; without the hook the guards join the room's wave.
##   - enemies only out of sources (R2): push_from_sources() / release_from() send enemies through
##     the room's SpawnSources (warning, coming out); rooms without sources fall back to the markers.
##   - plan markers: get_marker_tiles(kind) reads the Objectives markers of the plan (R1 contract);
##     every mode also finds its own spots in any combat room (VariantSpots), so it works with any
##     template when no plan of its mode fits.
## Decisions stay in the modes' rule classes; this class only wires them to the room (D-088).

## Guards wait before the fight at most this long (the hold ends earlier with the fight).
const GUARD_HOLD_TIME := 3600.0
const OBJECTIVES_NODE := ^"Objectives"

## RoomObjective mode of the goal (RoomObjective.MODES); defaults to the mode id.
var objective_mode: StringName = &""
var objective: RoomObjective = null
var guards: Array[Enemy] = []
## Seconds since the fight started (the modes' clocks read it).
var elapsed := 0.0

var _guards_released := false
var _first_wave_given := false


# --- Interface for RoomVariants ---

## true: the mode brings the room's first wave itself (spawn_first_wave), no wave out of the sources.
func uses_own_first_wave() -> bool:
	return false


## RoomController hook (RoomVariants.spawn_first_wave): the first wave of the room - the guards and
## whatever the mode adds (_own_first_wave). The room tracks them. Empty = the room spawns as usual.
func spawn_first_wave() -> Array[Enemy]:
	if not uses_own_first_wave() or _first_wave_given:
		return []
	_first_wave_given = true
	var enemies := _own_first_wave()
	_guards_released = true
	for enemy in guards:
		_wake(enemy)
	return enemies


## The goal of the room (null before the first player walked in).
func get_objective() -> RoomObjective:
	return objective


## Global point the intro camera shows (INF = no swing).
func get_focus() -> Vector2:
	return Vector2.INF


## Starts goal and intro (normally when the first player walks in; tests call it directly).
func start_intro() -> RoomIntro:
	if objective == null:
		objective = RoomObjective.create(objective_mode if objective_mode != &"" else variant_id)
		_setup_objective(objective)
		RoomObjective.attach(room, objective)
	if _started or not is_inside_tree():
		return null
	return RoomIntro.start(room, objective, get_focus())


## Ends the goal once: success shows "Geschafft!" in the task bar, otherwise "Verpasst".
func end_goal(success: bool) -> void:
	if objective != null and is_instance_valid(objective) and not objective.is_finished():
		objective.finish(success)


# --- Overrides of CombatVariant ---

func _on_room_player_entered(entered_room: RoomController) -> void:
	super(entered_room)
	start_intro()
	_on_player_entered()


func _on_start() -> void:
	if objective == null:
		# Fight without an entry (tools, tests): the goal still shows.
		objective = RoomObjective.create(objective_mode if objective_mode != &"" else variant_id)
		_setup_objective(objective)
		RoomObjective.attach(room, objective)
	release_guards()
	_on_fight_started()


func _on_finish() -> void:
	end_goal(bonus == Bonus.ACHIEVED)
	_on_room_done()


func _physics_process(delta: float) -> void:
	if _started and not _finished:
		step(delta)


## One step of the mode's clock (public: tests and tools fast-forward with it; the smoke test calls
## step(41.0) once to get past every time limit).
func step(delta: float) -> void:
	if not _started or _finished:
		return
	elapsed += delta
	_step(delta)


# --- For the modes ---

## Fill the goal (title/goal keys come from RoomObjective.MODES; goal_args, label, progress, time).
func _setup_objective(_goal: RoomObjective) -> void:
	pass


## The first player walked in (after the intro started).
func _on_player_entered() -> void:
	pass


## The fight began (after the intro, guards released).
func _on_fight_started() -> void:
	pass


## The room is done (bonus decided).
func _on_room_done() -> void:
	pass


## One step of the clock (elapsed already advanced).
func _step(_delta: float) -> void:
	pass


## Enemies of the mode's own first wave besides the guards (the crowned one). Already in the room.
func _own_first_wave() -> Array[Enemy]:
	var enemies: Array[Enemy] = []
	for enemy in guards:
		if is_instance_valid(enemy) and not enemy.is_dead():
			enemies.append(enemy)
	return enemies


# --- Plan markers ---

## Objective markers of the plan of one kind ("relic", "guard", ...), empty for rooms without plan.
func get_markers(kind: StringName) -> Array[Marker2D]:
	var result: Array[Marker2D] = []
	var holder := room.get_node_or_null(OBJECTIVES_NODE) if room != null else null
	if holder == null:
		return result
	for child in holder.get_children():
		var marker := child as Marker2D
		if marker != null and StringName(marker.get_meta(&"objective_kind", &"")) == kind:
			result.append(marker)
	return result


## Tiles of the objective markers of one kind (metadata tile, else the marker position).
func get_marker_tiles(kind: StringName) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for marker in get_markers(kind):
		tiles.append(marker_tile(marker))
	return tiles


static func marker_tile(marker: Marker2D) -> Vector2i:
	if marker.has_meta(&"tile"):
		return marker.get_meta(&"tile")
	return RoomTiles.local_to_tile(marker.position)


## Room-local floor point of a tile for objects whose origin is their base line.
static func floor_point(tile: Vector2i) -> Vector2:
	return RoomTiles.tile_center(tile) + Vector2(0, RoomTiles.TILE_WORLD * 0.25)


# --- Guards ---

## Guards of the plan ("guard" markers, metadata enemy) placed before the fight; with fewer than
## at_least markers more stand on free tiles of extra_tiles. Returns every guard placed.
func place_plan_guards(at_least := 0, extra_tiles: Array[Vector2i] = []) -> Array[Enemy]:
	var placed: Array[Enemy] = []
	for marker in get_markers(&"guard"):
		var tile := marker_tile(marker)
		var guard := place_guard(StringName(marker.get_meta(&"enemy", &"")), tile)
		if guard != null:
			placed.append(guard)
	var index := 0
	while placed.size() < at_least and index < extra_tiles.size():
		var guard := place_guard(&"", extra_tiles[index])
		index += 1
		if guard != null:
			placed.append(guard)
	return placed


## One guard of the enemy type enemy_id (an id of the biome's table; another type of the biome if it
## does not live there) standing still on tile until the fight starts.
func place_guard(enemy_id: StringName, tile: Vector2i) -> Enemy:
	var data := pick_enemy_data(enemy_id)
	if data == null:
		return null
	_free.erase(tile)
	var guard := create_enemy(data, RoomTiles.tile_center(tile))
	guard.name = "Guard%d" % guards.size()
	guards.append(guard)
	guard.begin_intro(GUARD_HOLD_TIME)
	return guard


## Lets the guards fight (the room tracks them unless the first-wave hook already did).
func release_guards() -> void:
	if _guards_released:
		return
	_guards_released = true
	for guard in guards:
		if is_instance_valid(guard) and not guard.is_dead():
			_wake(guard)
			track_enemy(guard)


## Enemy type for a guard: enemy_id if the biome's table of this room has it, else the most frequent
## type of the table (the spawner's own types without a biome).
func pick_enemy_data(enemy_id: StringName) -> EnemyData:
	var types: Array[EnemyData] = []
	var weights: Array[float] = []
	var biome := room.spawner.get_biome(room.room_index)
	if biome != null:
		var table := biome.get_table(room.room_index)
		types = table[0]
		weights = table[1]
	if types.is_empty():
		types = room.spawner.enemy_types
		weights = room.spawner.spawn_weights
	var best: EnemyData = null
	var best_weight := -1.0
	for i in types.size():
		var data := types[i]
		if data == null or data.is_boss:
			continue
		if enemy_id != &"" and data.id == enemy_id:
			return data
		var weight: float = weights[i] if i < weights.size() else 1.0
		if weight > best_weight:
			best_weight = weight
			best = data
	return best


## The fastest plainly visible melee type of the biome's table of this room (the crowned one runs;
## no see-through shadow), else the most frequent one.
func pick_runner_data() -> EnemyData:
	var types: Array[EnemyData] = []
	var biome := room.spawner.get_biome(room.room_index)
	if biome != null:
		types = biome.get_table(room.room_index)[0]
	if types.is_empty():
		types = room.spawner.enemy_types
	var best: EnemyData = null
	for data in types:
		if data == null or data.is_boss or data.attack_kind != EnemyData.AttackKind.MELEE or data.special == EnemyData.Special.SELF_DESTRUCT or data.idle_alpha < 0.9:
			continue
		if best == null or data.move_speed > best.move_speed:
			best = data
	return best if best != null else pick_enemy_data(&"")


## A plain enemy of a given type at a room-local point, in the room (not tracked, no elite).
## plain_only: no trait of the room may change it (the crowned one never becomes a bone heap).
func create_enemy(data: EnemyData, local_position: Vector2, plain_only := false) -> Enemy:
	var enemy := EnemySpawner.ENEMY_SCENE.instantiate() as Enemy
	if plain_only:
		enemy.set_meta(GravediggerTrait.ROLLED_META, true)
	enemy.data = data
	enemy.position = local_position
	enemy.arena = room.get_arena()
	enemy.apply_scaling(room.room_index, false)
	if context != null and context.economy != null:
		enemy.gold_drop = roundi(context.economy.get_gold_drop(data, room.room_index, false) * MetaProgression.get_gold_multiplier())
	room.enemy_container.add_child(enemy)
	return enemy


# --- Enemy sources (R2) ---

## The room's enemy sources (null for rooms without).
func get_sources() -> SpawnSources:
	return SpawnSources.of(room) if room != null else null


## One push of count normal enemies out of the room's sources (mostly behind the players), tracked
## by the room; at the markers if the room has no sources. Types and elites from the mode's RNG.
func push_from_sources(count: int) -> Array[Enemy]:
	var enemies: Array[Enemy] = []
	if room == null or count <= 0:
		return enemies
	var sources := get_sources()
	if sources != null and not sources.get_pool().is_empty():
		enemies = sources.spawn_wave(room.spawner, count, room.enemy_container, _spawn_context(), room.get_arena())
	else:
		var positions: Array[Vector2] = []
		for spot in EnemySpawner.pick_marker_positions(room.get_spawn_markers(), count, _rng):
			positions.append(spot)
		enemies = spawn_enemies(positions)
	for enemy in enemies:
		track_enemy(enemy)
	return enemies


## count enemies out of exactly these sources (one after the other, a source repeats when there are
## more enemies than sources), tracked by the room.
func release_from(chosen: Array[SpawnSource], count: int) -> Array[Enemy]:
	var enemies: Array[Enemy] = []
	var sources := get_sources()
	if sources == null or chosen.is_empty() or count <= 0:
		return enemies
	var order: Array[SpawnSource] = []
	var positions: Array[Vector2] = []
	for i in count:
		var source := chosen[i % chosen.size()]
		order.append(source)
		positions.append(source.spot)
	enemies = room.spawner.spawn_enemies(room.room_index, positions, room.enemy_container, _spawn_context(), room.get_arena())
	sources.release(enemies, order)
	for enemy in enemies:
		track_enemy(enemy)
	return enemies


## Every source of the room goes quiet (no glimmer): the mode's time is over.
func quiet_sources() -> void:
	var sources := get_sources()
	if sources == null:
		return
	for source in sources.get_sources():
		if is_instance_valid(source):
			source.go_quiet()


# --- Reward ---

## Soul crystals for the group (D-109) with a banner.
func give_crystals(amount: int, title_key: StringName, subtitle_key: StringName) -> void:
	if amount <= 0:
		return
	RunManager.add_run_crystals(amount)
	show_banner(DungeonTexts.t(title_key), DungeonTexts.t(subtitle_key, [amount]), BONUS_COLOR)


## The room is dark for this mode: wall torches out (returned so they can come back).
func hide_wall_torches() -> Array[Node2D]:
	var hidden: Array[Node2D] = []
	var props := room.get_node_or_null("Props") if room != null else null
	if props == null:
		return hidden
	for prop in props.get_children():
		if prop is Node2D and String(prop.name).begins_with("Torch") and (prop as Node2D).visible:
			(prop as Node2D).visible = false
			hidden.append(prop as Node2D)
	return hidden


func get_vision_overlay() -> VisionOverlay:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(VisionOverlay.GROUP) as VisionOverlay


## Untyped on purpose: guards may already be freed, and a typed parameter fails before the check.
func _wake(candidate: Variant) -> void:
	if not is_instance_valid(candidate):
		return
	var enemy := candidate as Enemy
	if enemy != null and not enemy.is_dead() and enemy.is_in_intro():
		enemy.end_intro()

class_name SoulsMode
extends CombatVariant
## Minigame "Seelen sammeln" (KONZEPT_RAEUME_V2 §3.6, design answer 01_raumarten.md, R4a): after the
## intro 12 soul lights appear one after another at fixed places (the plan's soul markers, filled up
## from free floor), each for 6 s; 45 s for the round. Every soul taken makes the sources spit enemies,
## one push per beat. The task bar counts "Seelen x/12" with the time.
##   End of the round (time up, or every soul came and went): soul crystals by count
##   (SoulsRules.CRYSTAL_STEPS) lie by the exit; too few = no bonus. Then the rest of the enemies is
##   beaten as usual. Never costs the run.
## The room stays shut while the round runs (holds_completion). Decisions (spawn, take, fade, end)
## change state and emit signals; the looks follow (SoulWisp). Randomness: the variant RNG (order of
## the places). Co-op: every living player takes souls; the crystals are the group's (run crystals).

signal soul_taken(mode: SoulsMode, wisp: SoulWisp, player: Player)
signal soul_lost(mode: SoulsMode, wisp: SoulWisp)
signal round_over(mode: SoulsMode, collected: int, crystals: int)

var objective: RoomObjective = null
## Room-local tiles of the places, in the order the souls appear.
var spots: Array[Vector2i] = []
var clock := 0.0
var spawned := 0
var collected := 0
var lost := 0
var crystals := 0
var is_round_over := false
## Enemies the taken souls still owe (pushed one per beat).
var owed_enemies := 0

var _wisps: Array[SoulWisp] = []
var _previews: Array[SoulWisp] = []
var _next_at := SoulsRules.FIRST_DELAY
var _since_push := SoulsRules.PUSH_BEAT
var _crystal: SecretCrystal = null


## Hangs the souls mode onto a prepared normal combat room (like CombatVariant.attach_to; until the
## R4b mode table registers it, tests and tools use this). rng_seed: one number of the dungeon RNG.
## null if the room has no room for twelve places.
static func attach(target: RoomController, rng_seed: int) -> SoulsMode:
	if target == null or not is_instance_valid(target) or not target.has_room_kind() or CombatVariant.of(target) != null:
		return null
	var mode := SoulsMode.new()
	mode.variant_id = SoulsRules.ID
	mode.room = target
	mode.context = target.context
	mode._rng.seed = rng_seed
	# Height (M3b): nothing of the mode stands at the foot of stairs or a ladder.
	mode._free = HeightRules.keep_feet_free(target.tiles, VariantSpots.free_tiles(target))
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
	_plan_spots()
	return spots.size() >= SoulsRules.SOUL_COUNT


func _on_attach() -> void:
	if spots.is_empty():
		_plan_spots()
	var order := SoulsRules.shuffled_order(spots.size(), _rng)
	var ordered: Array[Vector2i] = []
	for index in order:
		ordered.append(spots[index])
	spots = ordered


func _shape_group(group: EncounterGroup) -> EncounterGroup:
	return VariantEncounterGroup.wrap(group, self, SoulsRules.ENCOUNTER_FACTOR)


## The room is entered: goal, task bar and intro (the first souls flicker up, banner, 3-2-1).
func _on_room_player_entered(entered_room: RoomController) -> void:
	super(entered_room)
	begin_intro()


func _on_start() -> void:
	if objective == null:
		_create_objective()
	for preview in _previews:
		if is_instance_valid(preview):
			preview.fade()
	_previews.clear()
	clock = 0.0
	_next_at = SoulsRules.FIRST_DELAY
	_refresh_bar()


func holds_completion() -> bool:
	return _started and not _finished and not is_round_over


func _is_bonus_met() -> bool:
	return crystals > 0


func _physics_process(delta: float) -> void:
	if _started and not _finished:
		step(delta)


## One step of the round (public for tests and tools: a large delta fast-forwards it - souls that
## would have come and gone meanwhile fade untaken).
func step(delta: float) -> void:
	if not _started or is_round_over:
		return
	var left := delta
	while left > 0.0 and not is_round_over:
		var part := minf(left, 0.25)
		left -= part
		_advance(part)
	_refresh_bar()


## Starts goal, task bar and intro once (room entered). Public for tools that stage rooms.
func begin_intro() -> void:
	if objective != null or _finished:
		return
	_create_objective()
	for i in mini(SoulsRules.PREVIEW_COUNT, spots.size()):
		var preview := SoulWisp.new()
		preview.name = "SoulPreview%d" % i
		preview.build(spots[i], true)
		add_child(preview)
		_previews.append(preview)
	var focus := room.to_global(RoomTiles.tile_center(spots[0])) if not spots.is_empty() else Vector2.INF
	RoomIntro.start(room, objective, focus)


## Souls that can be taken right now.
func get_visible_wisps() -> Array[SoulWisp]:
	var visible: Array[SoulWisp] = []
	for wisp in _wisps:
		if is_instance_valid(wisp) and wisp.is_visible_soul():
			visible.append(wisp)
	return visible


func get_time_left() -> float:
	return maxf(0.0, SoulsRules.TIME_LIMIT - clock)


## A player takes a soul (also called by step when a player's feet reach it).
func take(wisp: SoulWisp, player: Player) -> bool:
	if is_round_over or wisp == null or not is_instance_valid(wisp) or not wisp.is_visible_soul():
		return false
	collected += 1
	owed_enemies += SoulsRules.ENEMIES_PER_SOUL
	_wisps.erase(wisp)
	wisp.take()
	soul_taken.emit(self, wisp, player)
	if get_visible_wisps().is_empty():
		_next_at = SoulsRules.next_when_empty(clock, _next_at)
	_refresh_bar()
	return true


## Spits the owed enemies of one beat out of the room's sources (behind the players, SpawnSources).
func send_push() -> Array[Enemy]:
	_since_push = 0.0
	var sources := SpawnSources.of(room)
	if sources == null or owed_enemies <= 0:
		return []
	var enemies := sources.spawn_wave(room.spawner, 1, room.enemy_container, _spawn_context(), room.get_arena())
	owed_enemies = maxi(0, owed_enemies - maxi(1, enemies.size()))
	for enemy in enemies:
		track_enemy(enemy)
	return enemies


# --- Round ---

func _advance(delta: float) -> void:
	clock += delta
	_since_push += delta
	# Souls taken by a player's feet.
	for wisp in get_visible_wisps():
		var player := _player_at(wisp)
		if player != null:
			take(wisp, player)
	# Souls whose time is up.
	for wisp in get_visible_wisps():
		wisp.age += delta
		if wisp.age >= wisp.lifetime:
			_lose(wisp)
	if SoulsRules.should_spawn(clock, _next_at, spawned):
		_spawn_next()
	if SoulsRules.should_push(_since_push, owed_enemies, get_living_enemies().size()):
		send_push()
	if SoulsRules.is_round_over(clock, spawned, get_visible_wisps().size()):
		_end_round()


func _spawn_next() -> void:
	var wisp := SoulWisp.new()
	wisp.name = "Soul%d" % spawned
	wisp.build(spots[spawned % spots.size()])
	add_child(wisp)
	_wisps.append(wisp)
	spawned += 1
	_next_at = SoulsRules.next_after_spawn(clock)


func _lose(wisp: SoulWisp) -> void:
	lost += 1
	_wisps.erase(wisp)
	wisp.fade()
	soul_lost.emit(self, wisp)
	if get_visible_wisps().is_empty():
		_next_at = SoulsRules.next_when_empty(clock, _next_at)


## Time up or every soul came: the rest fades, the crystals by count, the room may close.
func _end_round() -> void:
	if is_round_over:
		return
	is_round_over = true
	for wisp in get_visible_wisps():
		lost += 1
		wisp.fade()
	_wisps.clear()
	owed_enemies = 0
	crystals = SoulsRules.crystals_for(collected)
	set_bonus(crystals > 0)
	round_over.emit(self, collected, crystals)
	if objective != null:
		objective.set_count(collected, SoulsRules.SOUL_COUNT)
		objective.finish(crystals > 0)
	if crystals > 0:
		_place_crystals()
		var sub_key := &"MODE_SOULS_DONE_SUB_ONE" if crystals == 1 else &"MODE_SOULS_DONE_SUB"
		show_banner(DungeonTexts.t(&"MODE_SOULS_DONE_TITLE", [collected]), DungeonTexts.t(sub_key, [crystals]), BONUS_COLOR)
	else:
		show_banner(DungeonTexts.t(&"MODE_SOULS_DONE_TITLE", [collected]), DungeonTexts.t(&"MODE_SOULS_NONE_SUB"), LOST_COLOR)
	room.check_completion()


## The crystals lie by the exit, on the way out (walking over them takes them, SecretCrystal).
func _place_crystals() -> void:
	_crystal = SecretCrystal.new()
	_crystal.name = "SoulCrystals"
	_crystal.amount = crystals
	var inward := -RoomTiles.SIDE_DIRECTIONS[room.tiles.exit_side]
	var tile := VariantSpots.nearest_free(_free, room.tiles.get_exit_inside_tile() + inward)
	_crystal.position = RoomTiles.tile_center(tile if tile != VariantSpots.INVALID else room.tiles.get_exit_inside_tile())
	add_child(_crystal)
	if is_inside_tree():
		Burst.spawn(self, _crystal.global_position + Vector2(0, -24), BONUS_COLOR, 20, 140.0)
		LightSource.flash(self, _crystal.global_position + Vector2(0, -24), 180.0, 0.5)


## The crystal pickup by the exit (null before the end or without bonus).
func get_crystal_pickup() -> SecretCrystal:
	return _crystal if is_instance_valid(_crystal) else null


# --- Effects ---

func _create_objective() -> void:
	objective = RoomObjective.create(RoomObjective.SOULS)
	objective.goal_args = [SoulsRules.SOUL_COUNT]
	RoomObjective.attach(room, objective)
	objective.set_time(SoulsRules.TIME_LIMIT, false)
	_refresh_bar()


func _refresh_bar() -> void:
	if objective == null or objective.is_finished():
		return
	objective.set_count(collected, SoulsRules.SOUL_COUNT)
	objective.set_label(DungeonTexts.t(&"OBJECTIVE_SOULS", [collected, SoulsRules.SOUL_COUNT]))
	if _started:
		objective.set_time(get_time_left(), true)
		objective.set_danger(get_time_left() <= SoulsRules.DANGER_TIME)


func _player_at(wisp: SoulWisp) -> Player:
	var place := wisp.global_position
	for player in get_players():
		if SoulsRules.is_taken(player.get_feet_position().distance_to(place)):
			return player
	return null


# --- Places ---

## The plan's soul places first, filled up to SOUL_COUNT from free floor away from the doors and the
## sources (every place is reachable on foot: VariantSpots.free_tiles; a plan place may also lie on a
## plateau players reach over its stairs or ladder, M3b).
func _plan_spots() -> void:
	var plan_spots: Array[Vector2i] = []
	for marker in room.get_objectives_of(SoulsRules.SPOT_MARKER):
		var tile: Vector2i = marker.get_meta(&"tile", RoomTiles.local_to_tile(marker.position))
		if _free.has(tile) or HeightRules.is_reached_surface(room.tiles, tile):
			plan_spots.append(tile)
	var blocked: Dictionary[Vector2i, bool] = {}
	for marker in room.get_sources():
		blocked[marker.get_meta(&"tile", RoomTiles.local_to_tile(marker.position))] = true
	var candidates: Array[Vector2i] = []
	for tile: Vector2i in _free:
		if not blocked.has(tile):
			candidates.append(tile)
	var doors: Array[Vector2i] = [room.tiles.get_entrance_inside_tile()]
	doors.append_array(room.tiles.get_exit_inside_tiles())
	spots = SoulsRules.fill_spots(plan_spots, candidates, SoulsRules.SOUL_COUNT, doors)

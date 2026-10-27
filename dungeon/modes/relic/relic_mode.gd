class_name RelicMode
extends RoomMode
## Minigame "Reliquie holen" (RAEUME §3.5, design answer 01_raumarten.md, R4b; replaces
## the lantern bearer of D-116): "Hol die Reliquie und bring sie zum Altar."
##   Intro:  camera on the relic at the far end (plan marker relic), banner "Hol die Reliquie".
##   Fight:  only the guards of the plan stand there at first. When the relic is first lifted every
##           grave of the room breaks open at once (RelicRules.WAKE_FACTOR of a wave out of all
##           sources); they chase the carrier, the guards do with 60 % (EnemyDecoy). The carrier
##           walks slower and cannot attack, dash stays (LanternCarry); a hit drops the relic. Task bar
##           "Reliquie 0/1", the time for the bonus and a carrier line.
##   End:    every relic on the altar within 40 s = success (bonus chest at the altar). Later the
##           relics fly home by themselves (no bonus). The room stays shut until they lie on the
##           altar, so the room can always be finished.
## From room 26 (cycle 6) two relics. Co-op: one carries, the others protect; hand over by putting it
## down.

var relics: Array[Relic] = []
var altar: RelicAltar = null

var _woken := false
var _chasers: Array[Enemy] = []
var _placed := 0
var _sent_home := false


func can_host() -> bool:
	return _altar_tile() != VariantSpots.INVALID and not _relic_tiles().is_empty()


func uses_own_first_wave() -> bool:
	return true


func _on_attach() -> void:
	# Height (M3b): nothing of the mode stands at the foot of stairs or a ladder.
	HeightRules.keep_feet_free(room.tiles, _free)
	var altar_tile := _altar_tile()
	_free.erase(altar_tile)
	altar = RelicAltar.new()
	altar.name = "RelicAltar"
	altar.position = floor_point(altar_tile)
	altar.build()
	add_child(altar)
	room.tiles.set_navigation_blocked(altar_tile, true)
	var biome := room.spawner.get_biome(room.room_index)
	var biome_id: StringName = biome.id if biome != null else &"crypt"
	for tile in _relic_tiles():
		_free.erase(tile)
		var relic := Relic.new()
		relic.name = "Relic%d" % relics.size()
		relic.position = floor_point(tile)
		relic.altar = altar
		relic.build(biome_id)
		add_child(relic)
		relic.picked_up.connect(_on_picked_up)
		relic.dropped.connect(_on_dropped)
		relic.placed.connect(_on_placed)
		relics.append(relic)
	# Guards of the plan; without them a few near the relic.
	place_plan_guards(RelicRules.MIN_GUARDS, _guard_fallback_tiles())


## Without the first-wave hook the room adds a small wave of its own (the graves wake later).
func _shape_group(group: EncounterGroup) -> EncounterGroup:
	return VariantEncounterGroup.wrap(group, self, RelicRules.FALLBACK_WAVE_FACTOR)


func get_focus() -> Vector2:
	if relics.is_empty() or not relics[0].is_inside_tree():
		return Vector2.INF
	return relics[0].global_position


## Flint's first-time tour (WK11): the relic, the altar, the graves that wake when it is lifted.
func get_flint_steps() -> Array[FlintGuideStep]:
	var relic := get_focus()
	var altar_point := altar.global_position if altar != null and is_instance_valid(altar) and altar.is_inside_tree() else Vector2.INF
	return RoomFlint.steps(RoomObjective.RELIC, [relic, altar_point, RoomFlint.source_point(room, relic)])


func _setup_objective(goal: RoomObjective) -> void:
	goal.set_count(0, relics.size())
	goal.set_time(RelicRules.BONUS_TIME)
	_refresh_bar()


func _on_fight_started() -> void:
	for enemy in get_living_enemies():
		_choose_target(enemy)
	for relic in relics:
		if relic.is_carried() and not _woken:
			# Lifted before the door shut: the graves break open right away.
			wake_graves()
	_refresh_bar()


func _step(_delta: float) -> void:
	if RelicRules.relics_return(elapsed, _placed, relics.size()) and not _sent_home:
		_send_home()
	_refresh_bar()


func holds_completion() -> bool:
	return RelicRules.holds_room(_started, _placed, relics.size()) and not _finished


func get_placed_count() -> int:
	return _placed


func is_woken() -> bool:
	return _woken


func get_chasers() -> Array[Enemy]:
	var living: Array[Enemy] = []
	for i in _chasers.size():
		var enemy: Variant = _chasers[i]
		if is_instance_valid(enemy) and not (enemy as Enemy).is_dead():
			living.append(enemy)
	return living


## The carrier of a relic (null if nobody carries one).
func get_carrier() -> Player:
	for relic in relics:
		if relic.is_carried() and is_instance_valid(relic.carrier):
			return relic.carrier
	return null


## Every grave breaks open (first lift): a push out of all sources away from the players.
func wake_graves() -> Array[Enemy]:
	_woken = true
	var size := RelicRules.wake_size(room.spawner.roll_enemy_count(room.room_index, _rng))
	var chosen := _wake_sources()
	var enemies: Array[Enemy] = []
	if chosen.is_empty():
		enemies = push_from_sources(size)
	else:
		enemies = release_from(chosen, size)
	# The ones out of the graves always go for the carrier (design answer: "Skelette jagen den
	# Träger"); guards and late arrivals choose by RelicRules.CHASER_SHARE.
	var carrier := get_carrier()
	for enemy in enemies:
		if not _chasers.has(enemy):
			_chasers.append(enemy)
		if carrier != null:
			EnemyDecoy.assign(enemy, carrier)
	if not enemies.is_empty():
		show_banner(DungeonTexts.t(&"MODE_RELIC_WAKE"), DungeonTexts.t(&"MODE_RELIC_WAKE_SUB"), LOST_COLOR)
	return enemies


func _on_room_done() -> void:
	if bonus == Bonus.ACHIEVED:
		spawn_bonus_chests(altar.position + Vector2(RoomTiles.TILE_WORLD, 0))
		show_banner(DungeonTexts.t(&"VARIANT_BONUS_TITLE"), DungeonTexts.t(&"VARIANT_BONUS_SUB"), BONUS_COLOR)


func _is_bonus_met() -> bool:
	return _placed >= relics.size() and RelicRules.bonus_open(elapsed)


## One roll per enemy (mode RNG): does it chase the carrier?
func _on_enemy_added(enemy: Enemy) -> void:
	_choose_target(enemy)


func _choose_target(enemy: Enemy) -> void:
	if enemy.has_meta(&"relic_rolled"):
		return
	enemy.set_meta(&"relic_rolled", true)
	if RelicRules.is_chaser(_rng.randf()):
		_chasers.append(enemy)
		var carrier := get_carrier()
		if carrier != null:
			EnemyDecoy.assign(enemy, carrier)


func _on_picked_up(_relic: Relic, player: Player) -> void:
	for enemy in get_chasers():
		EnemyDecoy.assign(enemy, player)
	if _started and not _woken:
		wake_graves()
	_refresh_bar()


func _on_dropped(_relic: Relic, _player: Player, by_hit: bool) -> void:
	for enemy in get_chasers():
		EnemyDecoy.clear(enemy)
	if by_hit and _started:
		show_banner(DungeonTexts.t(&"MODE_RELIC_DROPPED"), DungeonTexts.t(&"MODE_RELIC_DROPPED_SUB"), LOST_COLOR)
	_refresh_bar()


func _on_placed(_relic: Relic, player: Player) -> void:
	_placed += 1
	for enemy in get_chasers():
		EnemyDecoy.clear(enemy)
	if _placed >= relics.size():
		var by_player := player != null and RelicRules.bonus_open(elapsed)
		set_bonus(by_player)
		end_goal(by_player)
		if by_player:
			show_banner(DungeonTexts.t(&"MODE_RELIC_PLACED"), DungeonTexts.t(&"MODE_RELIC_PLACED_SUB"), RoomObjective.get_mode_ui_color(RoomObjective.RELIC))
		if room != null and is_instance_valid(room):
			room.check_completion()
	_refresh_bar()


## Time is up: the relics still away float home (decided at once, so the room may close).
func _send_home() -> void:
	_sent_home = true
	set_bonus(false)
	end_goal(false)
	show_banner(DungeonTexts.t(&"MODE_RELIC_RETURNS"), DungeonTexts.t(&"MODE_NO_BONUS"), LOST_COLOR)
	for relic in relics:
		if not relic.is_placed():
			relic.send_home()


func _refresh_bar() -> void:
	if objective == null or objective.is_finished():
		return
	objective.set_count(_placed, relics.size())
	objective.set_time(RelicRules.time_left(elapsed) if _started else RelicRules.BONUS_TIME)
	objective.set_label(DungeonTexts.t(&"OBJECTIVE_RELIC", [_placed, relics.size()]))
	var carrier := get_carrier()
	objective.set_status(DungeonTexts.t(&"OBJECTIVE_RELIC_CARRIED") if carrier != null else "")


## Sources for the wake: every source of the room at least WAKE_MIN_PLAYER_DISTANCE from all players
## ("alle Gräber brechen auf"); empty when the room has none.
func _wake_sources() -> Array[SpawnSource]:
	var chosen: Array[SpawnSource] = []
	var sources := get_sources()
	if sources == null:
		return chosen
	var players: Array[Vector2] = sources.get_player_states()[0]
	for source in sources.get_pool():
		if WaveRules.distance_to_nearest(source.spot, players) >= RelicRules.WAKE_MIN_PLAYER_DISTANCE:
			chosen.append(source)
	return chosen


## The altar of the plan (relic_altar marker), else a free tile beside the entrance.
func _altar_tile() -> Vector2i:
	for tile in get_marker_tiles(&"relic_altar"):
		return tile
	var side := room.tiles.entrance_side
	var along := Vector2i.DOWN if side == RoomTiles.DoorSide.WEST or side == RoomTiles.DoorSide.EAST else Vector2i.RIGHT
	var entrance := room.tiles.get_entrance_inside_tile()
	for offset in [2, -2, 3, -3, 1, -1]:
		var tile: Vector2i = entrance + along * offset
		if _free.has(tile):
			return tile
	return VariantSpots.altar_tile(_free, entrance, along)


## The relics of the plan (relic markers), else the free tiles farthest from the entrance; two from
## RelicRules.DOUBLE_FROM_ROOM.
func _relic_tiles() -> Array[Vector2i]:
	var wanted := RelicRules.relic_count(room.room_index)
	var tiles: Array[Vector2i] = []
	for tile in get_marker_tiles(&"relic"):
		if tiles.size() < wanted:
			tiles.append(tile)
	var entrance := room.tiles.get_entrance_inside_tile()
	var far := VariantSpots.sorted_tiles(_free)
	far.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a - entrance).length_squared() > Vector2(b - entrance).length_squared())
	for tile in far:
		if tiles.size() >= wanted:
			break
		if VariantSpots.is_clear_of(tile, tiles, 6.0):
			tiles.append(tile)
	return tiles


## Free tiles near the first relic for guards when the plan has none.
func _guard_fallback_tiles() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if relics.is_empty():
		return result
	var origin := RoomTiles.local_to_tile(relics[0].position)
	var near := VariantSpots.sorted_tiles(_free)
	near.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a - origin).length_squared() < Vector2(b - origin).length_squared())
	for tile in near:
		if Vector2(tile - origin).length() >= 2.0 and VariantSpots.is_clear_of(tile, result, 2.0):
			result.append(tile)
		if result.size() >= RelicRules.MIN_GUARDS:
			break
	return result

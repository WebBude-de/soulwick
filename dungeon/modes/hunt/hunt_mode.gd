class_name HuntMode
extends RoomMode
## Minigame "Jagd" (KONZEPT_RAEUME_V2 §3.8, design answer 01_raumarten.md, R4b; replaces the bounty
## variant of D-114): "Fang den Gekrönten, bevor er entkommt."
##   Intro:  camera on the crowned one (plan marker crowned), banner "Fang den Gekrönten". The escape
##           hole (plan marker escape_hole) is already there, closed.
##   Fight:  he and the guards of the plan stand in the hall (no sources). Once he sees a player he
##           flees: the hole opens over 15 s (HuntRules), he zigzags between the pillars away from the
##           players and runs for the hole in the last seconds; the guards stand in the way. Task bar:
##           how far the hole is open (red near the end) and the distance to him.
##   End:    caught (killed) = his loot: lots of gold, sometimes a bonus chest with an upgrade.
##           Escaped = he is gone without loot; the rest of the room as usual.
## Co-op: everyone hunts the same crowned one (the nearest player decides nothing special).

const HOLE_Z := -1

var crowned: Enemy = null
var flight: BountyFlight = null

var _hole: AnimatedSprite2D = null
var _hole_tile := VariantSpots.INVALID
var _caught_at := Vector2.ZERO
var _loot_upgrade := false


func can_host() -> bool:
	return _crowned_tile() != VariantSpots.INVALID


func uses_own_first_wave() -> bool:
	return true


func _on_attach() -> void:
	var tile := _crowned_tile()
	_free.erase(tile)
	var data := _crowned_data()
	crowned = create_enemy(data, RoomTiles.tile_center(tile), true)
	crowned.name = "Crowned"
	crowned.gold_drop = HuntRules.loot_gold(crowned.gold_drop)
	crowned.begin_intro(GUARD_HOLD_TIME)
	flight = BountyFlight.attach(crowned)
	flight.watching = false
	flight.spotted.connect(_on_spotted)
	flight.escaped.connect(_on_escaped)
	crowned.died.connect(_on_crowned_died)
	_loot_upgrade = HuntRules.loot_has_upgrade(_rng.randf())
	_hole_tile = _plan_hole_tile()
	if _hole_tile != VariantSpots.INVALID:
		_free.erase(_hole_tile)
		_build_hole(RoomTiles.tile_center(_hole_tile))
	place_plan_guards(HuntRules.MIN_GUARDS, _guard_fallback_tiles(tile))


func _shape_group(group: EncounterGroup) -> EncounterGroup:
	return VariantEncounterGroup.wrap(group, self, HuntRules.FALLBACK_WAVE_FACTOR)


func get_focus() -> Vector2:
	return crowned.global_position if crowned != null and is_instance_valid(crowned) and crowned.is_inside_tree() else Vector2.INF


func _own_first_wave() -> Array[Enemy]:
	var enemies := super()
	if crowned != null and is_instance_valid(crowned) and not crowned.is_dead():
		_wake(crowned)
		enemies.append(crowned)
	return enemies


func _setup_objective(goal: RoomObjective) -> void:
	goal.set_ratio(0.0)
	goal.set_label(DungeonTexts.t(&"OBJECTIVE_HUNT_WAIT"))


func _on_fight_started() -> void:
	if crowned != null and is_instance_valid(crowned) and not crowned.is_dead():
		if crowned.is_in_intro():
			# Without the first-wave hook he joins the room's own wave here.
			_wake(crowned)
			track_enemy(crowned)
		flight.evade_points = _evade_points()
		flight.watching = true
	else:
		set_bonus(false)


func _step(_delta: float) -> void:
	_update_hole()
	_refresh_bar()


func is_caught() -> bool:
	return flight != null and flight.is_caught()


func is_escaped() -> bool:
	return flight != null and flight.is_escaped()


func get_hole() -> AnimatedSprite2D:
	return _hole


func has_loot_upgrade() -> bool:
	return _loot_upgrade


func _on_spotted(_flight: BountyFlight) -> void:
	if _hole == null:
		# No hole in the plan: one far from him and the players.
		var origin := RoomTiles.local_to_tile(room.to_local(crowned.global_position))
		var away := get_player_tiles()
		away.append(room.tiles.get_entrance_inside_tile())
		away.append(room.tiles.get_exit_inside_tile())
		var tile := VariantSpots.far_tile(_free, origin, HuntRules.HOLE_MIN_TILES, away, HuntRules.HOLE_PLAYER_TILES, _rng)
		var local := RoomTiles.tile_center(tile) if tile != VariantSpots.INVALID else room.to_local(crowned.global_position)
		_build_hole(local)
	flight.hole_position = room.to_global(_hole.position - Vector2(0, 8))
	show_banner(DungeonTexts.t(&"MODE_HUNT_SPOTTED"), DungeonTexts.t(&"MODE_HUNT_SPOTTED_SUB", [roundi(HuntRules.CATCH_TIME)]), RoomObjective.get_mode_ui_color(RoomObjective.HUNT))
	if is_inside_tree():
		Sfx.play_at(self, &"bounty_hole", flight.hole_position, -6.0)


## Escaped: the enemy leaves the room without a death (no gold, no kill) - the room counts it as
## gone through its died signal, so the room still completes as usual.
func _on_escaped(_flight: BountyFlight) -> void:
	set_bonus(false)
	end_goal(false)
	if is_instance_valid(crowned) and not crowned.is_dead():
		crowned.gold_drop = 0
		crowned.hurtbox.set_deferred("monitorable", false)
		crowned.visible = false
		crowned.died.emit(crowned)
		crowned.queue_free()
	_close_hole()
	show_banner(DungeonTexts.t(&"MODE_HUNT_ESCAPED"), DungeonTexts.t(&"MODE_HUNT_ESCAPED_SUB"), LOST_COLOR)
	if is_inside_tree() and flight != null:
		Burst.spawn(self, room.to_local(flight.hole_position), Color(0.2, 0.15, 0.3), 14, 90.0)
		Sfx.play_at(self, &"bounty_escape", flight.hole_position, -6.0)


func _on_crowned_died(enemy: Enemy) -> void:
	if flight == null or flight.is_escaped():
		return
	_caught_at = room.to_local(enemy.global_position)
	if set_bonus(true):
		end_goal(true)
		show_banner(DungeonTexts.t(&"MODE_HUNT_CAUGHT"), DungeonTexts.t(&"MODE_HUNT_CAUGHT_SUB"), BONUS_COLOR)
	_close_hole()


func _is_bonus_met() -> bool:
	return false


## His loot: the gold drops with him; sometimes a chest with an upgrade choice where he fell.
func _on_room_done() -> void:
	if bonus == Bonus.ACHIEVED and _loot_upgrade:
		spawn_bonus_chests(_caught_at)


## The hole opens frame by frame with the time.
func _update_hole() -> void:
	if _hole == null or not is_instance_valid(_hole) or flight == null or not flight.is_fleeing():
		return
	var count := VariantArt.get_frame_count(VariantArt.ESCAPE_HOLE)
	_hole.frame = mini(count - 1, floori(flight.get_hole_progress() * count))


func _refresh_bar() -> void:
	if objective == null or objective.is_finished() or flight == null:
		return
	if not flight.is_fleeing():
		return
	var progress := flight.get_hole_progress()
	objective.set_ratio(progress)
	objective.set_danger(progress >= HuntRules.DANGER_PROGRESS)
	var distance := 0
	var players: Array[Vector2] = []
	if is_inside_tree() and is_instance_valid(crowned):
		for node in EnemyTargeting.living_players(get_tree()):
			players.append(node.global_position)
		distance = roundi(WaveRules.distance_to_nearest(crowned.global_position, players) / RoomTiles.TILE_WORLD) if not players.is_empty() else 0
	objective.set_label(DungeonTexts.t(&"OBJECTIVE_HUNT", [distance]))


func _build_hole(local: Vector2) -> void:
	_hole = VariantArt.make_animated(VariantArt.ESCAPE_HOLE, false)
	_hole.name = "EscapeHole"
	_hole.z_index = HOLE_Z
	_hole.position = local + Vector2(0, 8)
	_hole.stop()
	_hole.frame = 0
	add_child(_hole)
	var glow := LightSource.new()
	glow.name = "Glow"
	glow.radius = 70.0
	glow.intensity = 0.35
	_hole.add_child(glow)


func _close_hole() -> void:
	if _hole == null or not is_instance_valid(_hole) or not is_inside_tree():
		return
	var hole := _hole
	var tween := hole.create_tween()
	tween.tween_property(hole, "modulate:a", 0.0, 0.6)
	tween.tween_callback(hole.queue_free)


## Spots he zigzags between: free floor tiles of the room, every second one (global floor points).
func _evade_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for tile in VariantSpots.sorted_tiles(_free):
		if (tile.x + tile.y) % 2 == 0 and VariantSpots.is_open(tile, _free):
			points.append(room.to_global(RoomTiles.tile_center(tile)))
	return points


## The crowned one of the plan, else a free tile far from the entrance.
func _crowned_tile() -> Vector2i:
	for tile in get_marker_tiles(&"crowned"):
		return tile
	var entrance := room.tiles.get_entrance_inside_tile()
	var best := VariantSpots.INVALID
	var best_distance := -1.0
	for tile in VariantSpots.sorted_tiles(_free):
		var distance := Vector2(tile - entrance).length()
		if distance > best_distance and VariantSpots.is_open(tile, _free):
			best_distance = distance
			best = tile
	return best


## The crowned one is of the guards' kind when the biome has it (crypt: a skeleton, like the design
## answer), else the fastest plainly visible melee type of the biome.
func _crowned_data() -> EnemyData:
	for marker in get_markers(&"guard"):
		var id := StringName(marker.get_meta(&"enemy", &""))
		var data := pick_enemy_data(id)
		if data != null and data.id == id:
			return data
	return pick_runner_data()


func _plan_hole_tile() -> Vector2i:
	for tile in get_marker_tiles(&"escape_hole"):
		return tile
	return VariantSpots.INVALID


## Free tiles between him and the entrance for guards when the plan has none.
func _guard_fallback_tiles(crowned_tile: Vector2i) -> Array[Vector2i]:
	var entrance := room.tiles.get_entrance_inside_tile()
	var candidates: Array[Vector2i] = []
	for tile in VariantSpots.sorted_tiles(_free):
		var to_entrance := Vector2(tile - entrance).length()
		var to_crowned := Vector2(tile - crowned_tile).length()
		if to_entrance >= 4.0 and to_crowned >= 2.0:
			candidates.append(tile)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a - crowned_tile).length_squared() < Vector2(b - crowned_tile).length_squared())
	var result: Array[Vector2i] = []
	for tile in candidates:
		if VariantSpots.is_clear_of(tile, result, 3.0):
			result.append(tile)
		if result.size() >= HuntRules.MIN_GUARDS:
			break
	return result

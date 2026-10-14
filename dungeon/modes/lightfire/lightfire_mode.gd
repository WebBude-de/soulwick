class_name LightfireMode
extends RoomMode
## Minigame "Lichtfeuer" (KONZEPT_RAEUME_V2 §3.9, design answer 01_raumarten.md, R4b; replaces the
## torch room and the stone guardian variant of D-116): "Entzünde alle Feuer – im Dunkeln sind die
## Wächter unbesiegbar."
##   Intro:  camera on the cold torch stands (plan markers torch_stand_unlit), banner "Entzünde alle
##           Feuer". The room is almost dark: wall torches out, the players' light circle at half its
##           size (LightingProfile draws the deep darkness for the mode id, hook in the R4b report).
##   Fight:  a hit or E lights a stand for good (RoomTorch); every fire is a warm island of light and
##           widens the players' circle. Stone guardians (plan markers stone_guardian) advance in the
##           dark and leap; in a fire's light they freeze and can be broken - in the dark they are
##           stone (the players' own small circles hold them too, D-116). A few
##           normal enemies come out of the sources. Task bar: "Wächter 3 · Feuer" with fires 2/6.
##   End:    every fire burning and every guardian broken = success: bonus chest, the light comes back.
##           Otherwise the room is done as usual when every enemy is beaten (no bonus).
## Co-op: +1 guardian per extra player (MP5); every player can light stands.

## Loaded at use (no preload: the mode scripts stay out of the load cycles of the room scripts).
const GUARDIAN_SCENE_PATH := "res://enemies/variants/stone_guardian.tscn"
const GUARDIAN_DATA_PATH := "res://enemies/data/stone_guardian.tres"
const TINT := Color("#ffd8a0")

var torches: Array[RoomTorch] = []
var stone_guardians: Array[StoneGuardian] = []

## Burning stands of the plan ('t', built by the generator; their light counts already).
var _prelit := 0
var _guardian_tiles: Array[Vector2i] = []
var _vision_radius := -1.0
var _hidden_torches: Array[Node2D] = []
var _darkened := false


func can_host() -> bool:
	return not get_marker_tiles(&"torch_stand_unlit").is_empty() or _fire_candidates().size() >= LightfireRules.FIRE_COUNT.x


func _on_attach() -> void:
	var unlit := get_marker_tiles(&"torch_stand_unlit")
	_prelit = get_marker_tiles(&"torch_stand").size()
	if unlit.is_empty():
		var candidates := _fire_candidates()
		var count := LightfireRules.fire_count(_rng.randf(), candidates.size())
		unlit = VariantSpots.pick_spread(candidates, count, LightfireRules.FIRE_MIN_TILE_DISTANCE, _rng)
		if unlit.size() < LightfireRules.FIRE_COUNT.x:
			unlit = VariantSpots.pick_spread(candidates, count, LightfireRules.FIRE_MIN_TILE_DISTANCE * 0.5, _rng)
	for tile in unlit:
		_free.erase(tile)
		var torch := RoomTorch.new()
		torch.name = "RoomTorch%d" % torches.size()
		torch.position = floor_point(tile)
		torch.build(TINT, LightfireRules.FIRE_LIGHT_RADIUS)
		add_child(torch)
		torch.ignited.connect(_on_torch_ignited)
		torches.append(torch)
	if _prelit == 0 and not torches.is_empty():
		# Without a burning stand in the plan the one nearest the entrance burns already.
		_nearest_torch(room.tiles.get_entrance_inside_tile()).ignite(null)
	_guardian_tiles = get_marker_tiles(&"stone_guardian")
	if _guardian_tiles.is_empty():
		var count := LightfireRules.guardian_count(_rng.randf(), 1)
		_guardian_tiles = VariantSpots.pick_spread(_guardian_candidates(), count, LightfireRules.GUARDIAN_MIN_TILE_DISTANCE, _rng)
	for tile in _guardian_tiles:
		_free.erase(tile)
		_place_guardian(tile)


func _shape_group(group: EncounterGroup) -> EncounterGroup:
	return VariantEncounterGroup.wrap(group, self, LightfireRules.ROOM_COUNT_FACTOR)


## The cold stands: the middle of them.
func get_focus() -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for torch in torches:
		if not torch.lit and torch.is_inside_tree():
			sum += torch.global_position
			count += 1
	return sum / count if count > 0 else Vector2.INF


func _setup_objective(goal: RoomObjective) -> void:
	_refresh_bar(goal)


func _on_player_entered() -> void:
	# After the DungeonManager set the room's light (it runs deferred, one frame later).
	if is_inside_tree():
		get_tree().process_frame.connect(_darken_room, CONNECT_ONE_SHOT)


func _on_fight_started() -> void:
	if not _darkened:
		_darken_room()
	# Co-op: extra guardians for more players (D-109), from the same candidates.
	var extra := LightfireRules.extra_guardians(get_player_count())
	if extra > 0:
		var pool: Array[Vector2i] = []
		for tile in _guardian_candidates():
			if VariantSpots.is_clear_of(tile, _guardian_tiles, LightfireRules.GUARDIAN_MIN_TILE_DISTANCE):
				pool.append(tile)
		for tile in VariantSpots.pick_spread(pool, extra, LightfireRules.GUARDIAN_MIN_TILE_DISTANCE, _rng):
			_guardian_tiles.append(tile)
			_place_guardian(tile)
	for guardian in get_living_guardians():
		track_enemy(guardian)
		guardian.activate()
		if is_inside_tree():
			Burst.spawn(room.enemy_container, guardian.global_position + Vector2(0, -30), StoneGuardian.DUST_COLOR, 10, 80.0)
	_refresh_bar(objective)


func get_lit_count() -> int:
	var count := _prelit
	for torch in torches:
		if torch.lit:
			count += 1
	return count


func get_fire_count() -> int:
	return torches.size() + _prelit


func get_living_guardians() -> Array[StoneGuardian]:
	var living: Array[StoneGuardian] = []
	for i in stone_guardians.size():
		var guardian: Variant = stone_guardians[i]
		if is_instance_valid(guardian) and not (guardian as StoneGuardian).is_dead():
			living.append(guardian)
	return living


func get_guardian_tiles() -> Array[Vector2i]:
	return _guardian_tiles.duplicate()


func _is_bonus_met() -> bool:
	return LightfireRules.is_complete(get_lit_count(), get_fire_count(), get_living_guardians().size())


func _on_room_done() -> void:
	_restore_light()
	if bonus == Bonus.ACHIEVED:
		var centre := room.content_anchor.position if room.content_anchor != null else Vector2(room.tiles.room_size) * RoomTiles.TILE_WORLD * 0.5
		spawn_bonus_chests(centre)
		show_banner(DungeonTexts.t(&"VARIANT_BONUS_TITLE"), DungeonTexts.t(&"VARIANT_BONUS_SUB"), BONUS_COLOR)


## A dormant statue on a free tile (in the tree before the fight, not yet counted by the room).
func _place_guardian(tile: Vector2i) -> StoneGuardian:
	var guardian := (load(GUARDIAN_SCENE_PATH) as PackedScene).instantiate() as StoneGuardian
	guardian.data = load(GUARDIAN_DATA_PATH) as EnemyData
	guardian.name = "StoneGuardian%d" % stone_guardians.size()
	guardian.position = RoomTiles.tile_center(tile)
	guardian.arena = room.get_arena()
	guardian.player_light_counts = LightfireRules.PLAYER_LIGHT_HOLDS_GUARDIANS
	guardian.apply_scaling(room.room_index, false)
	room.enemy_container.add_child(guardian)
	guardian.died.connect(_on_guardian_died)
	stone_guardians.append(guardian)
	return guardian


func _on_guardian_died(_guardian: Enemy) -> void:
	var left := get_living_guardians().size()
	if left > 0:
		show_banner(DungeonTexts.t(&"VARIANT_GUARDIAN_BROKEN"), DungeonTexts.t(&"VARIANT_GUARDIAN_LEFT_SUB", [left]))
	else:
		show_banner(DungeonTexts.t(&"VARIANT_GUARDIAN_BROKEN"), DungeonTexts.t(&"VARIANT_GUARDIANS_ALL_SUB"), BONUS_COLOR)
	_check_complete()
	_refresh_bar(objective)


func _on_torch_ignited(_torch: RoomTorch, _by: Node) -> void:
	_apply_vision()
	var lit := get_lit_count()
	if LightfireRules.all_lit(lit, get_fire_count()):
		show_banner(DungeonTexts.t(&"MODE_LIGHTFIRE_ALL"), DungeonTexts.t(&"MODE_LIGHTFIRE_ALL_SUB"), RoomObjective.get_mode_ui_color(RoomObjective.LIGHTFIRE))
	elif _started:
		show_banner(DungeonTexts.t(&"VARIANT_TORCH_LIT"), DungeonTexts.t(&"VARIANT_TORCH_LIT_SUB", [get_fire_count() - lit]))
	_check_complete()
	_refresh_bar(objective)


func _check_complete() -> void:
	if not _started or bonus != Bonus.OPEN:
		return
	if LightfireRules.is_complete(get_lit_count(), get_fire_count(), get_living_guardians().size()):
		set_bonus(true)
		end_goal(true)


func _refresh_bar(goal: RoomObjective) -> void:
	if goal == null or goal.is_finished():
		return
	goal.set_count(get_lit_count(), get_fire_count())
	goal.set_label(DungeonTexts.t(&"OBJECTIVE_LIGHTFIRE", [get_living_guardians().size()]))


## Dark room: the wall torches go out, the light circle shrinks to what the fires allow.
func _darken_room() -> void:
	if _darkened or _finished or room == null or not is_instance_valid(room):
		return
	_darkened = true
	_hidden_torches = hide_wall_torches()
	_vision_radius = RoomVariants.room_vision_radius(room)
	_apply_vision()


func _apply_vision() -> void:
	if _vision_radius < 0.0 or _finished:
		return
	var overlay := get_vision_overlay()
	if overlay != null:
		var factor := LightfireRules.vision_factor(get_lit_count(), get_fire_count())
		overlay.set_vision(DungeonManager.DUNGEON_DARKNESS, _vision_radius * factor)


## The room is done: the wall torches burn again and the light circle is back.
func _restore_light() -> void:
	for torch in _hidden_torches:
		if is_instance_valid(torch):
			torch.visible = true
	_hidden_torches.clear()
	if _vision_radius < 0.0:
		return
	var overlay := get_vision_overlay()
	if overlay != null:
		overlay.set_vision(DungeonManager.DUNGEON_DARKNESS, _vision_radius)


func _nearest_torch(tile: Vector2i) -> RoomTorch:
	var best: RoomTorch = torches[0]
	var best_distance := INF
	for torch in torches:
		var distance := Vector2(RoomTiles.local_to_tile(torch.position) - tile).length_squared()
		if distance < best_distance:
			best_distance = distance
			best = torch
	return best


## Free tiles away from both doors (rooms without plan stands).
func _fire_candidates() -> Array[Vector2i]:
	var doors: Array[Vector2i] = [room.tiles.get_entrance_inside_tile(), room.tiles.get_exit_inside_tile()]
	var result: Array[Vector2i] = []
	for tile: Vector2i in VariantSpots.sorted_tiles(_free):
		if VariantSpots.is_clear_of(tile, doors, LightfireRules.FIRE_DOOR_CLEARANCE):
			result.append(tile)
	return result


## Free tiles away from the entrance (the players come from there); without enough of them any
## free tile away from both doors.
func _guardian_candidates() -> Array[Vector2i]:
	var entrance := room.tiles.get_entrance_inside_tile()
	var doors: Array[Vector2i] = [entrance, room.tiles.get_exit_inside_tile()]
	var far: Array[Vector2i] = []
	var any: Array[Vector2i] = []
	for tile: Vector2i in VariantSpots.sorted_tiles(_free):
		if not VariantSpots.is_clear_of(tile, doors, 2.0):
			continue
		any.append(tile)
		if Vector2(tile - entrance).length() >= LightfireRules.GUARDIAN_ENTRANCE_TILES:
			far.append(tile)
	return far if far.size() >= LightfireRules.GUARDIAN_COUNT.y else any

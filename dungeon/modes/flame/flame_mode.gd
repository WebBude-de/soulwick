class_name FlameMode
extends RoomMode
## Minigame "Flamme hüten" (KONZEPT_RAEUME_V2 §3.4, design answer 01_raumarten.md, R4b; replaces the
## soul flame variant of D-114): "Halte die Seelenflamme 40 s am Leben."
##   Intro:  camera on the flame in the middle (plan marker soul_flame), banner "Halte die Flamme 40 s".
##   Fight:  enemies come out of the sources in short pushes (FlameRules: every 8 s, sooner when the
##           room is almost empty, other sources each time); 70 % of them go for the flame (EnemyDecoy).
##           Task bar: flame health as a bar (red below 30 %) and the time left. The flame's light
##           shrinks with its health.
##   End:    after 40 s the sources go dark and the rest must be beaten - flame alive = success
##           (bonus chest; untouched flame +1 soul crystal). Flame out = no bonus, the room gets
##           darker, the fight goes on. The room stays shut while the raid time runs.
## Co-op: +50 % flame health per extra player (MP5).

var flame: SoulFlame = null

var _since_push := 0.0
var _pushes := 0
var _raid_over := false


func can_host() -> bool:
	return _flame_tile() != VariantSpots.INVALID


func _on_attach() -> void:
	# Built right away: the flame already burns behind the open door.
	var tile := _flame_tile()
	flame = SoulFlame.new()
	flame.name = "SoulFlame"
	flame.position = RoomTiles.tile_center(tile)
	flame.build(FlameRules.flame_health(room.room_index, 1))
	add_child(flame)
	_free.erase(tile)
	flame.extinguished.connect(_on_flame_extinguished)
	flame.health.health_changed.connect(_on_flame_health_changed)


func _shape_group(group: EncounterGroup) -> EncounterGroup:
	return VariantEncounterGroup.wrap(group, self, FlameRules.FIRST_WAVE_FACTOR)


func get_focus() -> Vector2:
	return flame.global_position if flame != null and flame.is_inside_tree() else Vector2.INF


func _setup_objective(goal: RoomObjective) -> void:
	goal.goal_args = [roundi(FlameRules.DURATION)]
	goal.auto_danger = true
	goal.set_ratio(flame.get_health_ratio() if flame != null else 1.0)
	goal.set_time(FlameRules.DURATION)
	_refresh_label()


func _on_fight_started() -> void:
	# Co-op: the flame gets its extra health once the group is known.
	var players := get_player_count()
	if players > 1 and flame.is_alive():
		flame.health.reset(FlameRules.flame_health(room.room_index, players))
	for enemy in get_living_enemies():
		_choose_target(enemy)
	_refresh_bar()


func _step(delta: float) -> void:
	_since_push += delta
	if FlameRules.should_push(elapsed, _since_push, room.get_alive_enemy_count(), flame != null and flame.is_alive()):
		send_push()
	if not _raid_over and not FlameRules.holds_room(elapsed, _started):
		_end_raid()
	_refresh_bar()


func holds_completion() -> bool:
	return FlameRules.holds_room(elapsed, _started) and not _finished


func get_pushes_sent() -> int:
	return _pushes


func is_raid_over() -> bool:
	return _raid_over


## One push out of the sources (decision in FlameRules.should_push; public for tests and tools).
func send_push() -> Array[Enemy]:
	_since_push = 0.0
	var size := FlameRules.push_size(room.spawner.roll_enemy_count(room.room_index, _rng))
	var enemies := push_from_sources(size)
	if not enemies.is_empty():
		_pushes += 1
	return enemies


func _is_bonus_met() -> bool:
	return flame != null and flame.is_alive()


func _on_room_done() -> void:
	if bonus == Bonus.ACHIEVED:
		spawn_bonus_chests(flame.position + Vector2(0, Player.FEET_OFFSET.y + RoomTiles.TILE_WORLD))
		show_banner(DungeonTexts.t(&"VARIANT_BONUS_TITLE"), DungeonTexts.t(&"VARIANT_BONUS_SUB"), BONUS_COLOR)


## 70 % of the enemies go for the flame (one roll each, mode RNG).
func _on_enemy_added(enemy: Enemy) -> void:
	_choose_target(enemy)


func _choose_target(enemy: Enemy) -> void:
	if enemy.has_meta(&"flame_rolled") or flame == null or not flame.is_alive() or enemy in guards:
		return
	enemy.set_meta(&"flame_rolled", true)
	if FlameRules.is_raider(_rng.randf()):
		EnemyDecoy.assign(enemy, flame)


## Raid over: the sources go dark, no more pushes; the room may complete once the rest is beaten.
func _end_raid() -> void:
	_raid_over = true
	quiet_sources()
	if flame != null and flame.is_alive():
		var ratio := flame.get_health_ratio()
		set_bonus(true)
		end_goal(true)
		show_banner(DungeonTexts.t(&"VARIANT_SOUL_FLAME_HELD"), DungeonTexts.t(&"VARIANT_SOUL_FLAME_HELD_SUB"), RoomObjective.get_mode_ui_color(RoomObjective.FLAME))
		give_crystals(FlameRules.full_flame_crystals(ratio), &"MODE_FLAME_FULL", &"MODE_FLAME_FULL_SUB")
	room.check_completion()


func _on_flame_extinguished(_flame: SoulFlame) -> void:
	set_bonus(false)
	end_goal(false)
	show_banner(DungeonTexts.t(&"VARIANT_SOUL_FLAME_LOST"), DungeonTexts.t(&"VARIANT_SOUL_FLAME_LOST_SUB"), LOST_COLOR)
	_darken_room()


func _on_flame_health_changed(_current: float, _maximum: float) -> void:
	_refresh_bar()


func _refresh_bar() -> void:
	if objective == null or objective.is_finished() or flame == null:
		return
	objective.set_ratio(flame.get_health_ratio())
	objective.set_time(FlameRules.time_left(elapsed))
	_refresh_label()


func _refresh_label() -> void:
	if objective == null or flame == null:
		return
	objective.set_label(DungeonTexts.t(&"OBJECTIVE_FLAME", [roundi(flame.get_health_ratio() * 100.0)]))


## The room gets darker without the flame (vision overlay, like the DungeonManager sets it).
func _darken_room() -> void:
	var overlay := get_vision_overlay()
	if overlay != null:
		overlay.set_vision(DungeonManager.DUNGEON_DARKNESS, RoomVariants.room_vision_radius(room) * FlameRules.OUT_VISION_FACTOR)


## The flame of the plan (soul_flame marker), else the most central open floor tile.
func _flame_tile() -> Vector2i:
	for tile in get_marker_tiles(&"soul_flame"):
		return tile
	var centre := RoomTiles.local_to_tile(room.content_anchor.position) if room.content_anchor != null else room.tiles.room_size / 2
	return VariantSpots.nearest_open(_free, centre)

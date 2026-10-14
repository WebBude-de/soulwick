class_name SoulFlameVariant
extends CombatVariant
## Variant "Seelenflamme beschützen" (KONZEPT_RAEUME §4.1): a soul flame burns in the middle of the
## room. For VariantRules.FLAME_DURATION seconds after the door shut, raid waves come (every
## FLAME_WAVE_INTERVAL s, earlier when at most FLAME_WAVE_AT_ALIVE enemies are left); then the rest
## must be beaten. About 70 % of all enemies go for the flame (EnemyDecoy; needs the enemy_base
## hook), the others for the players. Flame alive at the end -> bonus chest. Flame out -> no
## bonus, the room gets darker, the fight goes on. The room stays shut during the raid time
## (holds_completion, RoomController hook).

var flame: SoulFlame = null

var _elapsed := 0.0
var _since_wave := 0.0
var _waves_sent := 0
var _raid_over := false


func can_host() -> bool:
	return _flame_tile() != VariantSpots.INVALID


func _on_attach() -> void:
	# Built right away: the flame already burns behind the open door.
	var tile := _flame_tile()
	flame = SoulFlame.new()
	flame.name = "SoulFlame"
	flame.position = RoomTiles.tile_center(tile)
	flame.build(VariantRules.flame_health(room.room_index, 1))
	add_child(flame)
	_free.erase(tile)
	flame.extinguished.connect(_on_flame_extinguished)


func _on_start() -> void:
	# Co-op: the flame gets its extra health once the group is known.
	var players := get_player_count()
	if players > 1 and flame.is_alive():
		flame.health.reset(VariantRules.flame_health(room.room_index, players))
	for enemy in get_living_enemies():
		_choose_target(enemy)
	# The room's name comes with the genre banner (UX2, D-110); the raid time stands above the flame.


func _physics_process(delta: float) -> void:
	if _started and not _finished:
		step(delta)


## One step of the raid timer (public for tests and tools).
func step(delta: float) -> void:
	if not _started or _finished:
		return
	_elapsed += delta
	_since_wave += delta
	if flame != null:
		flame.show_time_left(VariantRules.FLAME_DURATION - _elapsed if not _raid_over else -1.0)
	if VariantRules.should_send_wave(_elapsed, _since_wave, room.get_alive_enemy_count(), flame != null and flame.is_alive()):
		send_wave()
	if not _raid_over and not VariantRules.flame_holds_room(_elapsed, _started):
		_end_raid()


func holds_completion() -> bool:
	return VariantRules.flame_holds_room(_elapsed, _started) and not _finished


func get_elapsed() -> float:
	return _elapsed


func get_waves_sent() -> int:
	return _waves_sent


func is_raid_over() -> bool:
	return _raid_over


## A raid wave at spawn markers away from the players and the flame.
func send_wave() -> Array[Enemy]:
	_since_wave = 0.0
	var size := VariantRules.flame_wave_size(room.spawner.roll_enemy_count(room.room_index, _rng))
	var positions := _wave_positions(size)
	var enemies := spawn_enemies(positions)
	for enemy in enemies:
		track_enemy(enemy)
	if not enemies.is_empty():
		_waves_sent += 1
		show_banner(DungeonTexts.t(&"VARIANT_SOUL_FLAME_WAVE"), DungeonTexts.t(&"VARIANT_SOUL_FLAME_WAVE_SUB"), LOST_COLOR)
		if is_inside_tree():
			Sfx.play_ui(self, &"boss_roar", -12.0)
	return enemies


func _is_bonus_met() -> bool:
	return flame != null and flame.is_alive()


func _on_finish() -> void:
	if bonus == Bonus.ACHIEVED:
		spawn_bonus_chests(flame.position + Vector2(0, Player.FEET_OFFSET.y))
		show_banner(DungeonTexts.t(&"VARIANT_BONUS_TITLE"), DungeonTexts.t(&"VARIANT_BONUS_SUB"), BONUS_COLOR)


## 70 % of the enemies go for the flame (one roll each, variant RNG).
func _on_enemy_added(enemy: Enemy) -> void:
	_choose_target(enemy)


func _choose_target(enemy: Enemy) -> void:
	if enemy.has_meta(&"soul_flame_rolled") or flame == null or not flame.is_alive():
		return
	enemy.set_meta(&"soul_flame_rolled", true)
	if VariantRules.is_raider(_rng.randf()):
		EnemyDecoy.assign(enemy, flame)


## Raid over: no more waves, the room may complete once the rest is beaten.
func _end_raid() -> void:
	_raid_over = true
	if flame != null:
		flame.show_time_left(-1.0)
	if flame != null and flame.is_alive():
		show_banner(DungeonTexts.t(&"VARIANT_SOUL_FLAME_HELD"), DungeonTexts.t(&"VARIANT_SOUL_FLAME_HELD_SUB"))
	room.check_completion()


func _on_flame_extinguished(_flame: SoulFlame) -> void:
	set_bonus(false)
	show_banner(DungeonTexts.t(&"VARIANT_SOUL_FLAME_LOST"), DungeonTexts.t(&"VARIANT_SOUL_FLAME_LOST_SUB"), LOST_COLOR)
	_darken_room()


## The room gets darker without the flame (vision overlay, like the DungeonManager sets it).
func _darken_room() -> void:
	if not is_inside_tree():
		return
	var overlay := get_tree().get_first_node_in_group(VisionOverlay.GROUP) as VisionOverlay
	if overlay != null:
		overlay.set_vision(DungeonManager.DUNGEON_DARKNESS, RoomVariants.room_vision_radius(room) * VariantRules.FLAME_OUT_VISION_FACTOR)


## Spawn markers at least FLAME_SPAWN_MIN_DISTANCE from the flame and every player; if too few
## qualify, the farthest ones from the flame fill up.
func _wave_positions(count: int) -> Array[Vector2]:
	var markers := room.get_spawn_markers()
	var players := WaveRules.get_player_positions(room)
	var good: Array[Vector2] = []
	var rest: Array[Vector2] = []
	for marker in markers:
		var spot := marker.position
		var far_from_players := WaveRules.distance_to_nearest(spot, players) >= VariantRules.FLAME_SPAWN_MIN_DISTANCE
		var far_from_flame := flame == null or spot.distance_to(flame.position) >= VariantRules.FLAME_SPAWN_MIN_DISTANCE
		if far_from_players and far_from_flame:
			good.append(spot)
		else:
			rest.append(spot)
	var positions: Array[Vector2] = []
	while positions.size() < count and not good.is_empty():
		positions.append(good.pop_at(_rng.randi_range(0, good.size() - 1)))
	rest.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return flame == null or a.distance_to(flame.position) > b.distance_to(flame.position))
	while positions.size() < count and not rest.is_empty():
		positions.append(rest.pop_front())
	return positions


## Most central open floor tile of the room (the flame needs room around it).
func _flame_tile() -> Vector2i:
	var centre := RoomTiles.local_to_tile(room.content_anchor.position) if room.content_anchor != null else room.tiles.room_size / 2
	return VariantSpots.nearest_open(_free, centre)

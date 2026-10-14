class_name StoneGuardianVariant
extends CombatVariant
## Variant "Steinwächter" (KONZEPT_RAEUME §4.3, A9; crypt and shadow realm): 2-4 knight statues stand
## in the room from the start (dormant, far from the entrance). When the door shuts they wake: in the
## dark they advance and leap, in the light they freeze and can be beaten (StoneGuardian). Every
## light counts - each player's own circle (co-op: every player covers a corner), crystals, torches;
## the room's wall torches count here too, so the light the player sees is the light that holds them.
## Normal enemies come as well (fewer). The guardians count for the room like every enemy; the room
## is done when all guardians and all enemies are gone. Success = room cleared (KONZEPT names no
## failure), like rifts and gravedigger.

const GUARDIAN_SCENE: PackedScene = preload("res://enemies/variants/stone_guardian.tscn")
const GUARDIAN_DATA: EnemyData = preload("res://enemies/data/stone_guardian.tres")

var guardians: Array[StoneGuardian] = []
var _guardian_tiles: Array[Vector2i] = []


func can_host() -> bool:
	return _candidates().size() >= LightVariantRules.GUARDIAN_COUNT.x


func _on_attach() -> void:
	var count := LightVariantRules.guardian_count(_rng.randf(), 1)
	_guardian_tiles = VariantSpots.pick_spread(_candidates(), count, LightVariantRules.GUARDIAN_MIN_TILE_DISTANCE, _rng)
	for tile in _guardian_tiles:
		_free.erase(tile)
		_place_guardian(tile)
	_count_wall_torches()


func _shape_group(group: EncounterGroup) -> EncounterGroup:
	return VariantEncounterGroup.wrap(group, self, LightVariantRules.GUARDIAN_ROOM_COUNT_FACTOR)


func _on_start() -> void:
	# Co-op: extra guardians for more players (D-109), from the same candidates.
	var extra := LightVariantRules.guardian_count(0.0, get_player_count()) - LightVariantRules.guardian_count(0.0, 1)
	if extra > 0:
		var pool: Array[Vector2i] = []
		for tile in _candidates():
			if VariantSpots.is_clear_of(tile, _guardian_tiles, LightVariantRules.GUARDIAN_MIN_TILE_DISTANCE):
				pool.append(tile)
		for tile in VariantSpots.pick_spread(pool, extra, LightVariantRules.GUARDIAN_MIN_TILE_DISTANCE, _rng):
			_guardian_tiles.append(tile)
			_place_guardian(tile)
	for guardian in get_living_guardians():
		track_enemy(guardian)
		guardian.activate()
		if is_inside_tree():
			Burst.spawn(room.enemy_container, guardian.global_position + Vector2(0, -30), StoneGuardian.DUST_COLOR, 10, 80.0)


func get_guardian_tiles() -> Array[Vector2i]:
	return _guardian_tiles.duplicate()


func get_living_guardians() -> Array[StoneGuardian]:
	var living: Array[StoneGuardian] = []
	for i in guardians.size():
		var guardian: Variant = guardians[i]
		if is_instance_valid(guardian) and not (guardian as StoneGuardian).is_dead():
			living.append(guardian)
	return living


func _on_finish() -> void:
	if bonus == Bonus.ACHIEVED:
		var centre := room.content_anchor.position if room.content_anchor != null else Vector2(room.tiles.room_size) * RoomTiles.TILE_WORLD * 0.5
		spawn_bonus_chests(centre)
		show_banner(DungeonTexts.t(&"VARIANT_BONUS_TITLE"), DungeonTexts.t(&"VARIANT_BONUS_SUB"), BONUS_COLOR)


## A dormant statue on a free tile (in the tree before the fight, not yet counted by the room).
func _place_guardian(tile: Vector2i) -> StoneGuardian:
	var guardian := GUARDIAN_SCENE.instantiate() as StoneGuardian
	guardian.data = GUARDIAN_DATA
	guardian.name = "StoneGuardian%d" % guardians.size()
	guardian.position = RoomTiles.tile_center(tile)
	guardian.arena = room.get_arena()
	guardian.apply_scaling(room.room_index, false)
	room.enemy_container.add_child(guardian)
	guardian.died.connect(_on_guardian_died)
	guardians.append(guardian)
	return guardian


func _on_guardian_died(_guardian: Enemy) -> void:
	var left := get_living_guardians().size()
	if left > 0:
		show_banner(DungeonTexts.t(&"VARIANT_GUARDIAN_BROKEN"), DungeonTexts.t(&"VARIANT_GUARDIAN_LEFT_SUB", [left]))
	else:
		show_banner(DungeonTexts.t(&"VARIANT_GUARDIAN_BROKEN"), DungeonTexts.t(&"VARIANT_GUARDIANS_ALL_SUB"), BONUS_COLOR)


## The wall torches of the template light the room like any torch: they hold the guardians too.
func _count_wall_torches() -> void:
	var props := room.get_node_or_null("Props")
	if props == null:
		return
	for prop in props.get_children():
		if not String(prop.name).begins_with("Torch"):
			continue
		for child in prop.get_children():
			var light := child as LightSource
			if light != null:
				light.counts_as_light = true


## Free tiles away from the entrance (the players come from there); without enough of them any
## free tile away from both doors.
func _candidates() -> Array[Vector2i]:
	var entrance := room.tiles.get_entrance_inside_tile()
	var doors: Array[Vector2i] = [entrance, room.tiles.get_exit_inside_tile()]
	var far: Array[Vector2i] = []
	var any: Array[Vector2i] = []
	for tile: Vector2i in VariantSpots.sorted_tiles(_free):
		if not VariantSpots.is_clear_of(tile, doors, 2.0):
			continue
		any.append(tile)
		if Vector2(tile - entrance).length() >= LightVariantRules.GUARDIAN_ENTRANCE_TILES:
			far.append(tile)
	return far if far.size() >= LightVariantRules.GUARDIAN_COUNT.y else any

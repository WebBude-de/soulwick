class_name RiftsVariant
extends CombatVariant
## Variant "Beschwörungsrisse" (KONZEPT_RAEUME §4.2): when the door shuts, 2-3 rifts tear open at
## the walls. Every rift calls one enemy every RIFT_SUMMON_INTERVAL s while fewer than
## RIFT_MAX_ALIVE enemies live. Rifts are enemies with health and a bar (SummoningRift); a closed
## rift stops. The room is done when all rifts and all enemies are gone - the room's normal rule,
## because rifts and their minions count for the room. The first wave is smaller (the rifts bring
## the rest). Success = room cleared (KONZEPT names no failure).

const RIFT_SCENE: PackedScene = preload("res://enemies/variants/summoning_rift.tscn")
const RIFT_DATA: EnemyData = preload("res://enemies/data/summoning_rift.tres")
## Biome colour of the (neutral) rift art (SPRITES_V5 §3: "wird eingefärbt").
const BIOME_COLORS := {
	&"crypt": Color(0.75, 1.0, 0.95),
	&"slime_grotto": Color(0.65, 1.0, 0.55),
	&"shadow_realm": Color(0.85, 0.65, 1.0),
	&"ember_forge": Color(1.0, 0.75, 0.5),
}

var rifts: Array[SummoningRift] = []
## Rift tiles chosen on attach (one roll for the count, spots with the variant RNG).
var _rift_tiles: Array[Vector2i] = []


func can_host() -> bool:
	return _candidates().size() >= VariantRules.RIFT_COUNT.x


func _on_attach() -> void:
	var count := VariantRules.rift_count(_rng.randf(), 1)
	_rift_tiles = VariantSpots.pick_spread(_candidates(), count, VariantRules.RIFT_MIN_TILE_DISTANCE, _rng)
	if _rift_tiles.size() < VariantRules.RIFT_COUNT.x:
		# Few wall spots close together (small or odd shapes): closer rifts rather than one.
		_rift_tiles = VariantSpots.pick_spread(_candidates(), count, VariantRules.RIFT_MIN_TILE_DISTANCE * 0.5, _rng)


func _shape_group(group: EncounterGroup) -> EncounterGroup:
	return VariantEncounterGroup.wrap(group, self, VariantRules.RIFT_ROOM_COUNT_FACTOR)


func _on_start() -> void:
	# Co-op: extra rifts for more players (D-109), from the same candidates.
	var extra := VariantRules.rift_count(0.0, get_player_count()) - VariantRules.rift_count(0.0, 1)
	if extra > 0:
		var pool: Array[Vector2i] = []
		for tile in _candidates():
			if VariantSpots.is_clear_of(tile, _rift_tiles, VariantRules.RIFT_MIN_TILE_DISTANCE):
				pool.append(tile)
		_rift_tiles.append_array(VariantSpots.pick_spread(pool, extra, VariantRules.RIFT_MIN_TILE_DISTANCE, _rng))
	for i in _rift_tiles.size():
		_open_rift(_rift_tiles[i], VariantRules.RIFT_FIRST_DELAY + 0.8 * i)


func get_rift_tiles() -> Array[Vector2i]:
	return _rift_tiles.duplicate()


func get_open_rifts() -> Array[SummoningRift]:
	var open: Array[SummoningRift] = []
	for i in rifts.size():
		var rift: Variant = rifts[i]
		if is_instance_valid(rift) and not (rift as SummoningRift).is_dead():
			open.append(rift)
	return open


## Living enemies that are not rifts (the rule "fewer than six").
func get_alive_minions() -> int:
	var count := 0
	for enemy in get_living_enemies():
		if not enemy is SummoningRift:
			count += 1
	return count


func _open_rift(tile: Vector2i, first_delay: float) -> SummoningRift:
	var rift := RIFT_SCENE.instantiate() as SummoningRift
	rift.data = RIFT_DATA
	rift.name = "SummoningRift%d" % rifts.size()
	rift.position = RoomTiles.tile_center(tile)
	rift.arena = room.get_arena()
	rift.apply_scaling(room.room_index, false)
	var biome := room.spawner.get_biome(room.room_index)
	rift.rift_color = BIOME_COLORS.get(biome.id if biome != null else &"", Color.WHITE)
	rift.may_summon = _may_summon
	rift.summoner = _summon
	room.enemy_container.add_child(rift)
	track_enemy(rift)
	rift.activate(first_delay)
	rift.died.connect(_on_rift_closed)
	rifts.append(rift)
	if is_inside_tree():
		Burst.spawn(room.enemy_container, rift.global_position + Vector2(0, -40), rift.rift_color, 18, 150.0)
		Sfx.play_at(self, &"rift_open", rift.global_position, -6.0)
	return rift


func _may_summon(_rift: SummoningRift) -> bool:
	return VariantRules.can_summon(get_alive_minions())


func _summon(_rift: SummoningRift, spot: Vector2) -> Array[Enemy]:
	if not VariantRules.can_summon(get_alive_minions()):
		return []
	var positions: Array[Vector2] = [room.enemy_container.to_local(spot)]
	return spawn_enemies(positions)


func _on_rift_closed(_rift: Enemy) -> void:
	var left := get_open_rifts().size()
	if left > 0:
		show_banner(DungeonTexts.t(&"VARIANT_RIFT_CLOSED"), DungeonTexts.t(&"VARIANT_RIFT_CLOSED_SUB", [left]))
	else:
		show_banner(DungeonTexts.t(&"VARIANT_RIFT_CLOSED"), DungeonTexts.t(&"VARIANT_RIFTS_ALL_CLOSED_SUB"), BONUS_COLOR)


func _on_finish() -> void:
	if bonus == Bonus.ACHIEVED:
		var centre := room.content_anchor.position if room.content_anchor != null else Vector2(room.tiles.room_size) * RoomTiles.TILE_WORLD * 0.5
		spawn_bonus_chests(centre)
		show_banner(DungeonTexts.t(&"VARIANT_BONUS_TITLE"), DungeonTexts.t(&"VARIANT_BONUS_SUB"), BONUS_COLOR)


## Free tiles at a wall, away from the doors; without enough of them any free tile away from the doors.
func _candidates() -> Array[Vector2i]:
	var doors: Array[Vector2i] = [room.tiles.get_entrance_inside_tile(), room.tiles.get_exit_inside_tile()]
	var at_walls := VariantSpots.wall_tiles(_free, room.tiles.get_walkable_tiles(), doors, VariantRules.RIFT_DOOR_CLEARANCE)
	if at_walls.size() >= VariantRules.RIFT_COUNT.y:
		return at_walls
	var any: Array[Vector2i] = []
	for tile: Vector2i in VariantSpots.sorted_tiles(_free):
		if VariantSpots.is_clear_of(tile, doors, VariantRules.RIFT_DOOR_CLEARANCE):
			any.append(tile)
	return any

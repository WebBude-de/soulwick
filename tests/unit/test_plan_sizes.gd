extends GutTest
## Plan rooms after wave C: L plans for groups of 3-4 players (D-084) for clear, arena and every mode
## in every biome, never drawn in a single-player run (RoomCatalog.pick_template keeps to S/M even in
## its fallbacks); every mode works in its L plan; the souls plans have their 12 places (D-135);
## explosive barrels sit right beside a cracked wall of the plan so the niche opens without a bomber;
## most single-player templates can show two special rooms behind two north doors (branch, R5).

const BIOMES: Array[StringName] = [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]
## Plan modes (RoomTemplate.mode) of the minigames, ModeRegistry id -> plan mode.
const MODE_PLANS := {
	&"escort": &"escort", &"souls": &"souls", &"collapse": &"collapse", &"flame": &"flame",
	&"relic": &"relic", &"rifts": &"rifts", &"hunt": &"hunt", &"lightfire": &"beacon",
}
const ROOMS: Array[int] = [7, 22, 37, 52]
const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const SOULS_L: PackedScene = preload("res://dungeon/rooms/combat/seelen_l_crypt.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
## Share of single-player plain-fight templates that can show two special rooms at once (branch,
## R5; 77 of 92 after wave C, 29 before). TESTWERT
const MIN_BRANCH_SHARE := 0.8

var _old_save_path: String
var _catalog: RoomCatalog
var _large: Array[RoomSequence.RoomSize] = [RoomSequence.RoomSize.L]


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_plan_sizes_save.cfg"
	_catalog = RoomCatalog.create()


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()


func after_each() -> void:
	HitStop.reset()
	await wait_process_frames(1)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _large_entries() -> Array[RoomTemplate]:
	var result: Array[RoomTemplate] = []
	for entry in _catalog.get_entries():
		if entry.size_class == RoomSequence.RoomSize.L:
			result.append(entry)
	return result


func _markers(room: Node, container: String) -> Array[Marker2D]:
	var result: Array[Marker2D] = []
	var holder := room.get_node_or_null(container)
	if holder != null:
		for child in holder.get_children():
			if child is Marker2D:
				result.append(child)
	return result


## A plan room set up like test_mode_plans: skeletons only, no elites.
func _room(scene: PackedScene, room_index: int) -> RoomController:
	var room := scene.instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = _rng(41)
	room.setup(room_index, RoomSequence.RoomType.COMBAT, -1, false, context)
	var spawner := room.get_node("EnemySpawner") as EnemySpawner
	spawner.biomes = [] as Array[BiomeData]
	spawner.extra_types = [] as Array[EnemyData]
	spawner.enemy_types = [SKELETON] as Array[EnemyData]
	spawner.spawn_weights = [1.0] as Array[float]
	var group := EncounterGroup.new()
	group.allow_elites = false
	group.count_range = Vector2i(4, 4)
	spawner.encounter_group = group
	add_child_autofree(room)
	return room


# --- L plans ---

func test_every_kind_has_l_plans_in_every_biome() -> void:
	for biome in BIOMES:
		assert_true(_catalog.has_kind(RoomSequence.RoomKind.NORMAL, _large, biome), "%s: clear L plan" % biome)
		assert_true(_catalog.has_kind(RoomSequence.RoomKind.ARENA, _large, biome), "%s: arena L plan" % biome)
		for id: StringName in MODE_PLANS:
			assert_true(_catalog.has_kind(RoomSequence.RoomKind.NORMAL, _large, biome, 0, -1, MODE_PLANS[id]), "%s: %s L plan" % [biome, id])
	var clear_plans := {}
	for entry in _large_entries():
		if entry.mode == RoomTemplate.MODE_CLEAR:
			clear_plans[entry.plan_id] = true
	assert_gte(clear_plans.size(), 3, "several clear L plans: a group does not see the same hall every room")


func test_l_templates_are_large_and_have_room_for_a_group() -> void:
	var entries := _large_entries()
	assert_gte(entries.size(), 40, "L templates generated")
	for entry in entries:
		assert_eq(entry.role, RoomTemplate.ROLE_COMBAT)
		assert_between(entry.room_size.x, 23, 27, "%s: width (27-31 grid columns)" % entry.id)
		assert_between(entry.room_size.y, 10, 12, "%s: height (15-17 grid rows)" % entry.id)
		assert_gte(entry.spawn_tiles.size(), RoomSequence.get_min_spawn_points(RoomSequence.RoomSize.L), "%s: spawn markers (D-086)" % entry.id)
		assert_true(entry.allows_entrance(RoomTiles.DoorSide.WEST) and entry.allows_entrance(RoomTiles.DoorSide.EAST), "%s: side doors" % entry.id)
		var room := entry.scene.instantiate() as RoomController
		assert_eq(int(room.room_size_class), RoomSequence.RoomSize.L, "%s: scene says L" % entry.id)
		assert_eq(RoomPlanChecks.problems(room), [] as Array[String], "%s keeps the plan rules" % entry.id)
		room.free()


func test_single_player_never_draws_an_l_room() -> void:
	var rng := _rng(12)
	var modes: Array[StringName] = [&""]
	for id: StringName in MODE_PLANS:
		modes.append(MODE_PLANS[id])
	for room_index in [2, 9, 17, 24, 38, 52]:
		for kind in [RoomSequence.RoomKind.NORMAL, RoomSequence.RoomKind.ARENA, RoomSequence.RoomKind.CHASM]:
			for side in [-1, RoomTiles.DoorSide.WEST, RoomTiles.DoorSide.EAST]:
				for mode in modes:
					for i in 3:
						var entry := _catalog.pick_template(kind, RoomSequence.SOLO_ROOM_SIZES, rng, &"", room_index, side, mode)
						assert_ne(entry.size_class, RoomSequence.RoomSize.L, "room %d kind %d side %d mode %s: %s" % [room_index, kind, side, mode, entry.id])


func test_group_sizes_draw_l_rooms_of_the_mode_and_biome() -> void:
	var rng := _rng(13)
	for room_index in ROOMS:
		var biome := RoomCatalog.biome_id_for_room(room_index)
		for side in [-1, RoomTiles.DoorSide.WEST, RoomTiles.DoorSide.EAST]:
			var plain := _catalog.pick_template(RoomSequence.RoomKind.NORMAL, _large, rng, &"", room_index, side)
			assert_eq(plain.size_class, RoomSequence.RoomSize.L)
			assert_true(plain.allows_biome(biome) and plain.is_plain_fight(), plain.id)
			var arena := _catalog.pick_template(RoomSequence.RoomKind.ARENA, _large, rng, &"", room_index, side)
			assert_eq(arena.room_kind, RoomSequence.RoomKind.ARENA, arena.id)
			assert_eq(arena.size_class, RoomSequence.RoomSize.L)
			for id: StringName in MODE_PLANS:
				var entry := _catalog.pick_template(RoomSequence.RoomKind.NORMAL, _large, rng, &"", room_index, side, MODE_PLANS[id])
				assert_eq(entry.mode, MODE_PLANS[id], "%s in room %d" % [entry.id, room_index])
				assert_eq(entry.size_class, RoomSequence.RoomSize.L)
				assert_true(entry.allows_biome(biome))


func test_fallback_keeps_to_the_allowed_sizes() -> void:
	var catalog := RoomCatalog.new()
	catalog.add_template(HALL)
	catalog.add_entry(RoomCatalog.load_default().find_by_path(SOULS_L.resource_path))
	var rng := _rng(4)
	for i in 20:
		var entry := catalog.pick_template(RoomSequence.RoomKind.NORMAL, RoomSequence.SOLO_ROOM_SIZES, rng, &"", 0, -1, &"souls")
		assert_eq(entry.scene, HALL, "no souls plan in S/M: any S/M room rather than the L plan")
	var large := catalog.pick_template(RoomSequence.RoomKind.NORMAL, _large, rng, &"", 0, -1, &"souls")
	assert_eq(large.scene, SOULS_L, "a group gets it")
	assert_eq(RoomCatalog.sizes_up_to(RoomSequence.SOLO_ROOM_SIZES), RoomSequence.SOLO_ROOM_SIZES)
	assert_eq(RoomCatalog.sizes_up_to(_large).size(), 3)
	assert_eq(RoomCatalog.sizes_up_to([] as Array[RoomSequence.RoomSize]), [] as Array[RoomSequence.RoomSize])


func test_every_mode_works_in_its_l_plan() -> void:
	for id: StringName in MODE_PLANS:
		for biome_index in 2:
			var room_index: int = ROOMS[biome_index * 2 + (1 if id == &"escort" else 0)]
			var biome := RoomCatalog.biome_id_for_room(room_index)
			var entry := _catalog.pick_template(RoomSequence.RoomKind.NORMAL, _large, _rng(3), biome, 0, -1, MODE_PLANS[id])
			var room := _room(entry.scene, room_index)
			var attached := RoomVariants.attach(room, VariantTable.pick_for(id), _rng(5))
			assert_eq(attached, id, "%s attaches to %s" % [id, entry.id])
			var mode := CombatVariant.of(room)
			assert_not_null(mode, "%s in %s" % [id, entry.id])
			if mode is SoulsMode:
				assert_eq((mode as SoulsMode).spots.size(), SoulsRules.SOUL_COUNT, "%s: all soul places from the plan" % entry.id)
			if mode is EscortMode:
				var escort := mode as EscortMode
				assert_false(escort.path_tiles.is_empty(), "%s: the villager has a way" % entry.id)
				assert_eq(escort.path_tiles[0], room.get_objectives_of(&"escort_start")[0].get_meta(&"tile"), "%s: from the plan marker" % entry.id)
			room.queue_free()
			await wait_process_frames(1)


# --- Souls, explosive barrels, branch places ---

func test_souls_plans_have_twelve_places() -> void:
	for entry in _catalog.get_entries():
		if entry.mode != &"souls":
			continue
		var room := entry.scene.instantiate() as RoomController
		assert_eq(room.get_objectives_of(SoulsRules.SPOT_MARKER).size(), SoulsRules.SOUL_COUNT, "%s: 12 soul places (D-135)" % entry.id)
		room.free()


func test_explosive_barrels_open_a_cracked_wall_of_the_plan() -> void:
	var barrels := 0
	for entry in _catalog.get_entries():
		var room := entry.scene.instantiate() as RoomController
		var tiles := room.get_node("Tiles") as RoomTiles
		var cracks := tiles.secret_cracks
		for prop in room.get_node("Props").get_children():
			if not String(prop.name).begins_with("Explosive"):
				continue
			barrels += 1
			var tile := RoomTiles.local_to_tile((prop as Node2D).position)
			var beside := false
			for crack in cracks:
				beside = beside or (tile.y == crack.y + 1 and absi(tile.x - crack.x) == 1)
			assert_true(beside, "%s: barrel %s right beside a cracked wall %s" % [entry.id, tile, cracks])
			assert_eq(int(prop.get_meta(RoomController.META_MIN_ROOM, 0)), 3, "%s: barrels from room 3" % entry.id)
		if not cracks.is_empty():
			# The plan's cracked walls are real sites: free floor in front, solid rock around.
			var sites := SecretRules.find_sites(tiles, _forbidden(room), [])
			assert_false(sites.is_empty(), "%s: a niche fits behind %s" % [entry.id, cracks])
		room.free()
	assert_gte(barrels, 8, "explosive barrels in several clear plans")


func test_most_single_player_templates_can_show_two_special_rooms() -> void:
	# Two rest rooms behind the two outermost north places (BranchRules.pick_exit_pair) must fit side
	# by side (DungeonManager._ways_fit, R5): the plans keep those places 8+ columns apart.
	var manager := DungeonManager.new()
	manager.set(&"_combat_catalog", RoomCatalog.create([] as Array[PackedScene]))
	var options: Array[BranchOption] = [BranchOption.create(BranchOption.Kind.SPECIAL, RoomSequence.SpecialType.SHOP), BranchOption.create(BranchOption.Kind.SPECIAL, RoomSequence.SpecialType.FOUNTAIN)]
	var fits := 0
	var total := 0
	for entry in _catalog.get_entries():
		if not RoomSequence.SOLO_ROOM_SIZES.has(entry.size_class) or not entry.is_plain_fight():
			continue
		total += 1
		var room := entry.scene.instantiate()
		var tiles := room.get_node("Tiles") as RoomTiles
		var pair := BranchRules.pick_exit_pair(tiles, options, [RoomTiles.DoorSide.NORTH] as Array[int], [0] as Array[int])
		if pair.size() == 2 and manager._ways_fit(Vector2i.ZERO, tiles, pair, options, 4, _previous_below(tiles)):
			fits += 1
		room.free()
	manager.free()
	gut.p("special branch fits in %d of %d single-player templates" % [fits, total])
	assert_gte(float(fits) / float(total), MIN_BRANCH_SHARE)


## A previous room right below (south entrance), like test_branch_ways.
func _previous_below(tiles: RoomTiles) -> ExitRules.Footprint:
	var exit_end := RoomTiles.corridor_end_of(RoomTiles.DoorSide.SOUTH, tiles.room_size.x / 2, tiles.room_size)
	var size := Vector2i(15, 9)
	var origin := ExitRules.origin_for(exit_end, size, RoomTiles.DoorSide.NORTH, 7)
	return ExitRules.footprint_of(origin, size, Vector2i(RoomTiles.DoorSide.SOUTH, 7), 0, [Vector2i(RoomTiles.DoorSide.NORTH, 7)] as Array[Vector2i])


## Tiles a secret niche may not stand in front of: spawn markers and props (DungeonManager).
func _forbidden(room: RoomController) -> Dictionary:
	var forbidden := {}
	for marker in _markers(room, "SpawnPoints"):
		forbidden[RoomTiles.local_to_tile(marker.position)] = true
	for prop in room.get_node("Props").get_children():
		var node := prop as Node2D
		if node != null and not String(node.name).begins_with("Torch"):
			forbidden[RoomTiles.local_to_tile(node.position)] = true
			forbidden[RoomTiles.local_to_tile(node.position + Vector2(0, -8))] = true
	return forbidden

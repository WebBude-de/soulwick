extends GutTest
## Height in the mode plans and the L plans (M3b, D-189, Makeover 3 §4/§8): every mode has a plan
## with a plateau, the L plans for 3-4 players most of all; the flame stands on a plateau with stairs
## (enemies reach it), the relic on a ladder island (the bottleneck), the escort way runs on the ground
## below a cliff, souls on a plateau count as plan places, the collapse never breaks the floor around
## a plateau; things players take or light stand off the edges, sources and guards on a plateau only
## where it has stairs, and nothing of a mode closes the foot of stairs or a ladder.

const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
## Modes (plan header "mode") that have a plan with a plateau.
const MODES: Array[StringName] = [&"flame", &"relic", &"escort", &"souls", &"collapse", &"rifts", &"hunt", &"beacon", &"arena"]
## L plans with height (13 L plans in all). TESTWERT of the M3b package.
const MIN_L_HEIGHT_PLANS := 9
const FLAME_ROOM := "res://dungeon/rooms/combat/flamme_schrein_crypt.tscn"
const RELIC_ROOM := "res://dungeon/rooms/combat/reliquie_kammer_crypt.tscn"
const ESCORT_ROOM := "res://dungeon/rooms/combat/geleit_pfad_slime_grotto.tscn"
const SOULS_ROOM := "res://dungeon/rooms/combat/seelen_l_shadow_realm.tscn"
const COLLAPSE_ROOM := "res://dungeon/rooms/combat/einsturz_l_ember_forge.tscn"
## Plan objects players take or light (objective_kind) and the chest.
const TAKEN_KINDS: Array[StringName] = [&"relic", &"soul", &"torch_stand", &"torch_stand_unlit"]

var _old_save_path: String
var _catalog: RoomCatalog


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_height_modes_save.cfg"
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


func _room(path: String, room_index := 20) -> RoomController:
	var room := (load(path) as PackedScene).instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 41
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


func _attach(room: RoomController, id: StringName) -> RoomMode:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	assert_eq(RoomVariants.attach(room, VariantTable.pick_for(id), rng), id, "%s attached" % id)
	return CombatVariant.of(room) as RoomMode


func _layout(room: RoomController) -> HeightLayout:
	return room.tiles.get_height_layout()


## Does the plateau group holding tile have stairs?
func _has_stairs(layout: HeightLayout, tile: Vector2i) -> bool:
	for group in layout.components():
		if group.has(tile):
			for other: Vector2i in group:
				if layout.stairs.has(other):
					return true
	return false


# --- Every template ---

func test_every_mode_and_most_l_plans_have_height() -> void:
	var modes := {}
	var l_plans := {}
	for entry in _catalog.get_entries():
		var room := entry.scene.instantiate() as RoomController
		var tiles := room.get_node("Tiles") as RoomTiles
		if tiles.has_height():
			modes[entry.mode] = true
			if entry.size_class == RoomSequence.RoomSize.L:
				l_plans[entry.plan_id] = true
		room.free()
	for mode in MODES:
		assert_true(modes.has(mode), "a %s plan with a plateau" % mode)
	assert_gte(l_plans.size(), MIN_L_HEIGHT_PLANS, "L plans with height: %s" % [l_plans.keys()])


func test_things_on_plateaus_keep_the_rules() -> void:
	var on_plateaus := 0
	for entry in _catalog.get_entries():
		var room := entry.scene.instantiate() as RoomController
		var tiles := room.get_node("Tiles") as RoomTiles
		if not tiles.has_height():
			room.free()
			continue
		var layout := tiles.get_height_layout()
		var name := String(entry.id)
		assert_eq(RoomPlanChecks.height_enemy_problems(room, tiles), [] as Array[String], name)
		for marker in room.get_objectives():
			var tile: Vector2i = marker.get_meta(&"tile")
			if not layout.surface.has(tile):
				continue
			on_plateaus += 1
			var kind := StringName(marker.get_meta(&"objective_kind"))
			if TAKEN_KINDS.has(kind):
				assert_true(layout.is_inner_surface(tile), "%s: %s at %s off the edges" % [name, kind, tile])
			if kind == &"guard" or kind == &"soul_flame":
				assert_true(_has_stairs(layout, tile), "%s: %s at %s on a plateau with stairs" % [name, kind, tile])
		for prop in room.get_node("Props").get_children():
			var tile := RoomTiles.local_to_tile(prop.position)
			if prop is TreasureChest and layout.surface.has(tile):
				assert_true(layout.is_inner_surface(tile), "%s: chest at %s off the edges" % [name, tile])
		for marker in room.get_node("SpawnPoints").get_children():
			assert_false(layout.get_height_tiles().has(RoomTiles.local_to_tile(marker.position)), "%s: spawn points on the ground" % name)
		room.free()
	assert_gt(on_plateaus, 10, "mode objects and guards on plateaus")


# --- The modes ---

func test_the_flame_burns_on_a_plateau_enemies_reach_over_the_stairs() -> void:
	var room := _room(FLAME_ROOM)
	var mode := _attach(room, &"flame") as FlameMode
	await wait_physics_frames(2)
	var tile := RoomTiles.local_to_tile(mode.flame.position)
	assert_true(_layout(room).surface.has(tile), "the flame on the plateau")
	assert_true(room.tiles.get_height_reachable_tiles(true).has(tile), "enemies walk up to it")
	assert_eq(HeightRules.level_of(mode.flame), HeightRules.PLATEAU)
	for foot in _layout(room).get_connector_feet():
		assert_false(mode._free.has(foot), "the foot of the stairs stays free (bonus chest)")


func test_the_relic_lies_on_a_ladder_island() -> void:
	var room := _room(RELIC_ROOM)
	var mode := _attach(room, &"relic") as RelicMode
	await wait_physics_frames(2)
	var tile := RoomTiles.local_to_tile(mode.relics[0].position)
	var layout := _layout(room)
	assert_true(layout.is_inner_surface(tile), "the relic up there, off the edges")
	assert_false(_has_stairs(layout, tile), "only a ladder: the bottleneck")
	assert_true(room.tiles.get_height_reachable_tiles().has(tile), "players climb up")
	assert_false(room.tiles.get_height_reachable_tiles(true).has(tile), "enemies wait below")
	assert_false(layout.surface.has(RoomTiles.local_to_tile(mode.altar.position)), "the altar below")


func test_the_escort_way_runs_on_the_ground_below_the_plateau() -> void:
	var room := _room(ESCORT_ROOM, 8)
	var mode := EscortMode.attach(room, 5)
	assert_not_null(mode)
	var layout := _layout(room)
	var below := false
	for tile in mode.path_tiles:
		assert_false(layout.get_height_tiles().has(tile), "the way stays on the ground: %s" % tile)
		for dy in range(1, 3):
			below = below or layout.cliffs.has(tile - Vector2i(0, dy)) or layout.stairs.has(tile - Vector2i(0, dy))
	assert_true(below, "the way passes below the cliff (archers above)")
	var plateau_sources := 0
	for marker in room.get_sources():
		if layout.surface.has(marker.get_meta(&"tile")):
			plateau_sources += 1
	assert_eq(plateau_sources, 1, "a source up there")


func test_souls_on_a_plateau_are_plan_places() -> void:
	var room := _room(SOULS_ROOM, 12)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	assert_eq(RoomVariants.attach(room, VariantTable.pick_for(&"souls"), rng), &"souls")
	var mode := CombatVariant.of(room) as SoulsMode
	var layout := _layout(room)
	var up := 0
	for marker in room.get_objectives_of(SoulsRules.SPOT_MARKER):
		var tile: Vector2i = marker.get_meta(&"tile")
		assert_true(mode.spots.has(tile), "plan place %s used" % tile)
		if layout.surface.has(tile):
			up += 1
	assert_eq(up, 3, "three souls wait up there")
	assert_eq(mode.spots.size(), SoulsRules.SOUL_COUNT)


func test_the_collapse_never_breaks_the_floor_around_a_plateau() -> void:
	var room := _room(COLLAPSE_ROOM, 17)
	var mode := CollapseMode.attach(room, 13)
	assert_not_null(mode)
	var layout := _layout(room)
	var guard := CollapseRules.height_guard(layout.get_height_tiles(), mode._floor_tiles())
	assert_gt(guard.size(), 0)
	for tile: Vector2i in guard:
		assert_true(mode.kept.has(tile), "%s beside the plateau stays" % tile)
	for field: Array in mode.fields:
		for tile: Vector2i in field:
			assert_false(guard.has(tile), "no field at %s beside the plateau" % tile)
	# Every kept tile is joined to the entrance over kept tiles (no island).
	var reached := RoomTiles.flood_fill(mode.kept, {} as Dictionary[Vector2i, bool], room.tiles.get_entrance_inside_tile(), 0)
	for tile: Vector2i in mode.kept:
		assert_true(reached.has(tile), "kept %s joined to the way" % tile)
	# Everything breaks (as after 30 s): still no cliff, stairs or ladder over the abyss.
	var broken: Array[Vector2i] = []
	for field: Array in mode.fields:
		broken.append_array(field)
	room.tiles.add_pit_tiles(broken)
	assert_eq(RoomPlanChecks.height_problems(room.tiles), [] as Array[String], "no cliff over the abyss")


func test_join_kept_and_height_guard() -> void:
	var floor_tiles: Dictionary[Vector2i, bool] = {}
	for x in 6:
		for y in 4:
			floor_tiles[Vector2i(x, y)] = true
	var height: Dictionary[Vector2i, bool] = {Vector2i(9, 9): true, Vector2i(5, 3): true}
	floor_tiles.erase(Vector2i(5, 3))
	var guard := CollapseRules.height_guard(height, floor_tiles)
	assert_eq(guard.size(), 3, "the floor in the eight neighbours of the plateau tile")
	var kept: Dictionary[Vector2i, bool] = {Vector2i(0, 0): true, Vector2i(4, 3): true}
	CollapseRules.join_kept(kept, floor_tiles, Vector2i(0, 0))
	var reached := RoomTiles.flood_fill(kept, {} as Dictionary[Vector2i, bool], Vector2i(0, 0), 0)
	assert_true(reached.has(Vector2i(4, 3)), "joined over the shortest way")
	assert_lte(kept.size(), 8)


func test_ranged_enemies_on_a_plateau_hold_it_against_a_target_below() -> void:
	assert_false(EnemyPack.holds_high_ground(null))

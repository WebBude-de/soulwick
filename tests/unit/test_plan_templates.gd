extends GutTest
## Room templates from plans (R1, D-120, tools/generate_room_templates.py): every template on disk
## keeps the plan rules (RoomPlanChecks), the spawn marker counts (D-086), the marker contract for
## R2 and R4 (Sources, Objectives, PlayerStart), metadata matching the scene; enough plans per biome
## and kind; boss, miniboss, rest and campfire plans; water, rock faces under abysses, no random
## scatter any more.

const BIOMES: Array[StringName] = [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]
const SOURCE_KINDS: Array[StringName] = [&"grave", &"sarcophagus", &"puddle", &"rift", &"vent", &"gate", &"rift_wall"]
## Clear plans per biome (task R1: at least six, mirrored copies not counted).
const MIN_CLEAR_PLANS := 6
const MINIBOSS: PackedScene = preload("res://dungeon/rooms/boss/miniboss_room.tscn")
const CAMPFIRE: PackedScene = preload("res://dungeon/rooms/campfire/campfire_room.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

var _old_save_path: String
var _catalog: RoomCatalog


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_plan_templates_save.cfg"
	_catalog = RoomCatalog.create()


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _all_entries() -> Array[RoomTemplate]:
	var entries := _catalog.get_entries()
	entries.append_array(RoomCatalog.load_plans().get_entries())
	return entries


func _instantiate(scene: PackedScene) -> RoomController:
	var room := scene.instantiate() as RoomController
	autofree(room)
	return room


func _markers(room: Node, container: String) -> Array[Marker2D]:
	var result: Array[Marker2D] = []
	var holder := room.get_node_or_null(container)
	if holder == null:
		return result
	for child in holder.get_children():
		if child is Marker2D:
			result.append(child)
	return result


func _entry(id: StringName) -> RoomTemplate:
	for entry in _all_entries():
		if entry.id == id:
			return entry
	return null


func test_every_template_keeps_the_plan_rules() -> void:
	var checked := 0
	for entry in _all_entries():
		var room := _instantiate(entry.scene)
		var problems := RoomPlanChecks.problems(room)
		assert_eq(problems, [] as Array[String], "%s: %s" % [entry.id, problems])
		checked += 1
	assert_gt(checked, 100, "every template checked")


func test_spawn_markers_per_size_and_role() -> void:
	for entry in _all_entries():
		var room := _instantiate(entry.scene)
		var count := _markers(room, "SpawnPoints").size()
		if entry.role == RoomTemplate.ROLE_COMBAT:
			assert_between(count, RoomSequence.get_min_spawn_points(entry.size_class), RoomSequence.MAX_SPAWN_POINTS, "%s: %d markers (D-086)" % [entry.id, count])
		else:
			assert_eq(count, 5, "%s: boss, rest and campfire rooms keep five markers (D-009)" % entry.id)
		var tiles := room.get_node("Tiles") as RoomTiles
		var reachable := tiles.get_reachable_tiles(0)
		for marker in _markers(room, "SpawnPoints"):
			assert_true(reachable.has(RoomTiles.local_to_tile(marker.position)), "%s: %s on reachable floor" % [entry.id, marker.name])
		assert_true(tiles.get_walkable_tiles().has(Vector2i(tiles.entrance_x, tiles.room_size.y - 2)), "%s: player start free" % entry.id)


func test_templates_match_their_scenes() -> void:
	for entry in _all_entries():
		var room := _instantiate(entry.scene)
		var tiles := room.get_node("Tiles") as RoomTiles
		assert_eq(tiles.room_size, entry.room_size, "%s: size" % entry.id)
		assert_eq(entry.shape, RoomTemplate.Shape.PLAN, "%s: built from a plan" % entry.id)
		assert_ne(entry.plan_id, &"", "%s: plan id" % entry.id)
		assert_eq(entry.allowed_biomes.size(), 1, "%s: one biome per template" % entry.id)
		assert_eq(tiles.door_slots, entry.door_slots, "%s: door places" % entry.id)
		var spawn_tiles: Array[Vector2i] = []
		for marker in _markers(room, "SpawnPoints"):
			spawn_tiles.append(RoomTiles.local_to_tile(marker.position))
		assert_eq(spawn_tiles, entry.spawn_tiles, "%s: spawn tiles" % entry.id)
		if entry.role == RoomTemplate.ROLE_COMBAT:
			assert_eq(int(room.room_kind), int(entry.room_kind), "%s: kind" % entry.id)
			assert_eq(int(room.room_size_class), int(entry.size_class), "%s: size class" % entry.id)


func test_enough_clear_plans_per_biome() -> void:
	for biome in BIOMES:
		var plans := {}
		for entry in _catalog.get_entries():
			if entry.mode == RoomTemplate.MODE_CLEAR and entry.allows_biome(biome) and RoomSequence.SOLO_ROOM_SIZES.has(entry.size_class):
				plans[entry.plan_id] = true
		assert_gte(plans.size(), MIN_CLEAR_PLANS, "%s: %d clear plans %s" % [biome, plans.size(), plans.keys()])


func test_arena_plans_have_gates_in_the_wall() -> void:
	for biome in BIOMES:
		var found := 0
		for entry in _catalog.get_entries():
			if entry.room_kind != RoomSequence.RoomKind.ARENA or not entry.allows_biome(biome):
				continue
			found += 1
			assert_eq(entry.mode, RoomTemplate.MODE_ARENA)
			var gates := _instantiate(entry.scene).get_sources_of(&"gate")
			assert_gte(gates.size(), 4, "%s: gates in the walls" % entry.id)
		assert_gte(found, 3, "%s: three arena plans" % biome)


func test_marker_contract() -> void:
	for entry in _all_entries():
		var room := _instantiate(entry.scene)
		var tiles := room.get_node("Tiles") as RoomTiles
		var walkable := tiles.get_walkable_tiles()
		for marker in _markers(room, "Sources"):
			var kind := StringName(marker.get_meta(&"source_kind", &""))
			assert_true(SOURCE_KINDS.has(kind), "%s: %s kind %s" % [entry.id, marker.name, kind])
			var tile: Vector2i = marker.get_meta(&"tile")
			var floor_tile: Vector2i = marker.get_meta(&"floor_tile")
			var wall_side: int = marker.get_meta(&"wall_side")
			assert_eq(RoomTiles.local_to_tile(marker.position), tile, "%s: %s sits on its tile" % [entry.id, marker.name])
			# A floor source may also lie on a plateau surface (M3b, D-189).
			var on_plateau := tiles.has_height() and tiles.get_height_layout().surface.has(floor_tile)
			assert_true(walkable.has(floor_tile) or on_plateau, "%s: %s has floor to step out on" % [entry.id, marker.name])
			if kind == &"gate" or kind == &"rift_wall":
				assert_eq(wall_side, RoomTiles.DoorSide.NORTH, "%s: gates sit in a front facing south" % entry.id)
				assert_eq(floor_tile, tile + Vector2i.DOWN)
				assert_false(walkable.has(tile), "%s: a gate is part of the wall" % entry.id)
				assert_true(tiles.front_fixtures.has(tile), "%s: the gate front is a fixture" % entry.id)
			else:
				assert_eq(wall_side, -1)
				assert_eq(floor_tile, tile)
		for marker in _markers(room, "Objectives"):
			assert_ne(StringName(marker.get_meta(&"objective_kind", &"")), &"", "%s: %s has a kind" % [entry.id, marker.name])
			assert_true(marker.has_meta(&"tile"))
		assert_not_null(room.get_player_start_marker(), "%s: player start" % entry.id)


func test_floor_sources_follow_the_biome() -> void:
	var own := {&"crypt": [&"grave", &"sarcophagus"], &"slime_grotto": [&"puddle"], &"shadow_realm": [&"rift"], &"ember_forge": [&"vent"]}
	for entry in _all_entries():
		var room := _instantiate(entry.scene)
		var biome: StringName = entry.allowed_biomes[0]
		for marker in room.get_sources():
			var kind := StringName(marker.get_meta(&"source_kind"))
			if kind == &"gate" or kind == &"rift_wall":
				continue
			assert_true((own[biome] as Array).has(kind), "%s (%s): %s" % [entry.id, biome, kind])


func test_mode_plans_exist_for_every_biome() -> void:
	for mode: StringName in [&"escort", &"flame", &"relic", &"souls", &"rifts", &"hunt", &"beacon", &"collapse"]:
		for biome in BIOMES:
			assert_true(_catalog.has_kind(RoomSequence.RoomKind.NORMAL, RoomSequence.SOLO_ROOM_SIZES, biome, 0, -1, mode), "%s plan in %s" % [mode, biome])


func test_boss_rest_and_campfire_plans() -> void:
	var boss_scenes := {}
	for biome in BIOMES:
		var boss := RoomCatalog.find_boss_scene(biome)
		assert_not_null(boss, "%s: boss room" % biome)
		boss_scenes[boss] = true
		var boss_room := _instantiate(boss)
		assert_false(boss_room.get_objectives_of(&"boss").is_empty(), "%s: the boss has its place" % biome)
		for special in [RoomSequence.SpecialType.SHOP, RoomSequence.SpecialType.WEAPON, RoomSequence.SpecialType.FOUNTAIN, RoomSequence.SpecialType.UPGRADE]:
			var rest := RoomCatalog.pick_plan(RoomTemplate.ROLE_REST, biome, special)
			assert_not_null(rest, "%s: rest plan for special %d" % [biome, special])
			assert_true(rest.special_types.has(special))
			assert_true(rest.allows_biome(biome))
		assert_not_null(RoomCatalog.pick_plan(RoomTemplate.ROLE_MINIBOSS, biome), "%s: miniboss plan" % biome)
	assert_eq(boss_scenes.size(), 4, "every biome its own boss room (01_raumarten.md)")
	var campfire := _instantiate(CAMPFIRE)
	assert_false(campfire.get_objectives_of(&"campfire").is_empty(), "the fire has its place")
	assert_eq(RoomTiles.local_to_tile(campfire.get_node("ContentAnchor").position), campfire.get_objectives_of(&"campfire")[0].get_meta(&"tile"))
	assert_eq(_markers(_instantiate(MINIBOSS), "SpawnPoints").size(), 5)


func test_rest_plans_draw_with_the_rng() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var reference := RandomNumberGenerator.new()
	reference.seed = 3
	var entry := RoomCatalog.pick_plan(RoomTemplate.ROLE_REST, &"crypt", RoomSequence.SpecialType.SHOP, rng)
	reference.randf()
	assert_not_null(entry)
	assert_eq(rng.randi(), reference.randi(), "one draw")
	assert_eq(RoomCatalog.pick_plan(RoomTemplate.ROLE_REST, &"crypt", RoomSequence.SpecialType.SHOP), RoomCatalog.pick_plan(RoomTemplate.ROLE_REST, &"crypt", RoomSequence.SpecialType.SHOP), "without rng: always the first")


func test_no_random_scatter_in_plan_rooms() -> void:
	for entry in _catalog.get_entries():
		var scatter := _instantiate(entry.scene).get_node_or_null("Ingredients") as IngredientScatter
		assert_not_null(scatter, "%s: keeps the scatter node (one RNG draw)" % entry.id)
		assert_eq(scatter.allowed, [] as Array[int], "%s: but it places nothing (R1)" % entry.id)


func test_torches_keep_clear_of_the_exit_door() -> void:
	for entry in _all_entries():
		var room := _instantiate(entry.scene)
		var tiles := room.get_node("Tiles") as RoomTiles
		for prop in room.get_node("Props").get_children():
			var node := prop as Node2D
			if String(node.name).begins_with("Torch") and not String(node.name).begins_with("TorchStand") and node.position.y < 0.0:
				var column := floori(node.position.x / RoomTiles.TILE_WORLD)
				assert_gte(absi(column - tiles.exit_x), 4, "%s: %s next to the exit door (D1)" % [entry.id, node.name])


func test_water_slows_players_only_while_wading() -> void:
	var room := _instantiate(_entry(&"zwei_kammern_slime_grotto").scene)
	add_child(room)
	var tiles := room.tiles
	var water := tiles.get_water_tiles()
	assert_false(water.is_empty(), "the left chamber has water")
	assert_not_null(tiles.get_water(), "the overlay is built")
	assert_true(tiles.is_walkable(water[0]), "water is floor")
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	var speed := player.move_speed
	player.global_position = room.to_global(RoomTiles.tile_center(water[0])) - Player.FEET_OFFSET
	await wait_physics_frames(4)
	assert_true(tiles.get_water().is_slowing(player), "slowed in the water")
	assert_lt(player.move_speed, speed)
	player.global_position = room.to_global(RoomTiles.tile_center(tiles.get_entrance_inside_tile())) - Player.FEET_OFFSET
	await wait_physics_frames(4)
	assert_false(tiles.get_water().is_slowing(player))
	assert_almost_eq(player.move_speed, speed, 0.01, "full speed again")


func test_abyss_plans_get_a_rock_face_and_free_bridges() -> void:
	var room := _instantiate(_entry(&"brueckenkreuz_shadow_realm").scene)
	add_child(room)
	var tiles := room.tiles
	assert_true(tiles.has_pits())
	var cliffs := 0
	for child in tiles.get_children(true):
		if child.name == RoomTiles.CLIFF_NAME:
			cliffs = child.get_child_count()
	assert_gt(cliffs, 0, "rock faces under the north edges of the pits")
	var on_foot := tiles.get_reachable_tiles(0)
	for bridge in tiles.get_bridge_tiles():
		assert_true(on_foot.has(bridge), "bridge %s walkable" % bridge)
	var solids := RoomPlanChecks.solid_tiles(room)
	for bridge in tiles.get_bridge_tiles():
		assert_false(solids.has(bridge), "nothing stands on bridge %s" % bridge)


func test_deco_blocks_navigation_on_all_its_tiles() -> void:
	var room := _instantiate(_entry(&"grabhalle").scene)
	add_child(room)
	await wait_physics_frames(1)
	var pillar: DecoProp = null
	for prop in room.get_node("Props").get_children():
		if prop is DecoProp and (prop as DecoProp).item == &"pillar_fallen":
			pillar = prop
	assert_not_null(pillar, "the fallen pillar of the plan")
	assert_eq(pillar.get_blocked_tiles().size(), 2, "two tiles")
	for tile in pillar.get_blocked_tiles():
		assert_true(room.tiles.is_navigation_blocked(tile), "no navigation on %s" % tile)


func test_props_of_deeper_rooms_leave_early_rooms() -> void:
	var room := _instantiate(_entry(&"grabhalle").scene)
	var barrel := Node2D.new()
	barrel.name = "Explosive9"
	barrel.set_meta(RoomController.META_MIN_ROOM, 3)
	room.get_node("Props").add_child(barrel)
	room.setup(2, RoomSequence.RoomType.COMBAT, -1, false, null)
	add_child(room)
	assert_null(room.get_node("Props").get_node_or_null("Explosive9"), "no explosive barrel in room 2")

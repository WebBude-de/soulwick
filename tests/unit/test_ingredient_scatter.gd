extends GutTest
## Ingredient scatter (D-113, A3). Since the room plans (R1, D-120) the templates no
## longer scatter (allowed = []): a plan room keeps the one dungeon RNG draw and builds nothing. The
## planner itself stays a pure function and is still checked on plan layouts: over many seeds and
## with the set of every biome it never blocks a way, a door or a spawn marker, places 2-3
## ingredients, keeps every rule of its set and is reproducible.

const BIOMES: Array[StringName] = [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]
const SEEDS_PER_ROOM := 2
const DISTRIBUTION_SEEDS := 400
## Open plan layouts the planner is checked on (crypt copies).
const OPEN_PLANS: Array[StringName] = [&"arena_tore_crypt", &"kreuzgang_crypt", &"gewoelbe_crypt", &"combat_hall_crypt"]

var _old_save_path: String
var _catalog: RoomCatalog


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_ingredient_scatter_save.cfg"
	_catalog = RoomCatalog.create()


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## Layout and scatter node of a template (not in the tree).
func _prepare(entry: RoomTemplate) -> Array:
	var room := entry.scene.instantiate()
	autofree(room)
	var tiles := room.get_node("Tiles") as RoomTiles
	var scatter := room.get_node("Ingredients") as IngredientScatter
	var layout := IngredientScatter.Layout.from_tiles(tiles, IngredientScatter.get_marker_tiles(room), scatter.reserved_tiles)
	return [layout, scatter, tiles]


func _entry(id: StringName) -> RoomTemplate:
	for entry in _catalog.get_entries():
		if entry.id == id:
			return entry
	return null


func test_every_biome_has_a_set() -> void:
	for biome in BIOMES:
		var ingredient_set := IngredientSet.load_for_id(biome)
		assert_not_null(ingredient_set, "%s set" % biome)
		assert_eq(ingredient_set.biome_id, biome)
		assert_not_null(ingredient_set.trap_scene, "%s trap group" % biome)
		assert_false(ingredient_set.cover_scenes.is_empty(), "%s cover" % biome)
	# Explosive barrels: crypt and ember forge only (D-113).
	assert_gt(IngredientSet.load_for_id(&"crypt").get_weight(IngredientSet.Kind.EXPLOSIVES), 0.0)
	assert_gt(IngredientSet.load_for_id(&"ember_forge").get_weight(IngredientSet.Kind.EXPLOSIVES), 0.0)
	assert_eq(IngredientSet.load_for_id(&"slime_grotto").get_weight(IngredientSet.Kind.EXPLOSIVES), 0.0)
	assert_eq(IngredientSet.load_for_id(&"shadow_realm").get_weight(IngredientSet.Kind.EXPLOSIVES), 0.0)


func test_biome_data_points_to_its_set() -> void:
	for biome in BIOMES:
		var data := load("res://dungeon/biomes/%s.tres" % biome) as BiomeData
		assert_eq(IngredientSet.for_biome(data).biome_id, biome, "%s.tres -> its ingredient set" % biome)
	assert_eq(IngredientSet.for_biome(null).biome_id, &"crypt", "fallback")


func test_scatter_never_blocks_ways_doors_or_markers() -> void:
	var plans := 0
	var all_kinds: Array[int] = IngredientScatter.ALL_KINDS
	for entry in _catalog.get_entries():
		if entry.mode != RoomTemplate.MODE_CLEAR or entry.allowed_biomes[0] != &"crypt":
			continue
		var prepared := _prepare(entry)
		var layout: IngredientScatter.Layout = prepared[0]
		for biome in BIOMES:
			var ingredient_set := IngredientSet.load_for_id(biome)
			for i in SEEDS_PER_ROOM:
				var seed_value := hash([entry.id, biome, i])
				var plan := IngredientScatter.plan_room(layout, ingredient_set, all_kinds, 10, _rng(seed_value))
				plans += 1
				_check_plan(plan, layout, all_kinds, "%s/%s/%d" % [entry.id, biome, i])
	assert_gt(plans, 100)


func _check_plan(plan: IngredientScatter.Plan, layout: IngredientScatter.Layout, allowed: Array[int], label: String) -> void:
	var blocked: Dictionary[Vector2i, bool] = {}
	var used: Dictionary[Vector2i, bool] = {}
	for placement in plan.placements:
		assert_true(allowed.has(placement.ingredient), "%s: only allowed ingredients" % label)
		for tile in placement.get_tiles():
			assert_false(used.has(tile), "%s: two pieces on %s" % [label, tile])
			used[tile] = true
			assert_true(layout.reachable.has(tile), "%s: %s on free reachable floor" % [label, tile])
			assert_false(layout.forbidden.has(tile), "%s: %s on a marker, door lane or reserved tile" % [label, tile])
			if placement.is_blocking():
				blocked[tile] = true
				assert_false(layout.keep_clear.has(tile), "%s: blocking %s next to a marker or the entrance" % [label, tile])
	assert_true(IngredientScatter.keeps_paths(layout, blocked), "%s: every way stays open" % label)
	var mass := layout.static_blocked.duplicate()
	for tile in plan.get_wall_tiles():
		mass[tile] = true
	assert_true(WallAutotile.is_valid_mass(mass, layout.room_size), "%s: scattered walls have crown and front" % label)
	# The same check by hand: exit and every marker reachable with all blocking pieces in place.
	var walkable := layout.walkable.duplicate()
	for tile in blocked:
		walkable.erase(tile)
	var reached := RoomTiles.flood_fill(walkable, layout.pits, layout.entrance_inside, layout.max_dash_gap)
	assert_true(reached.has(layout.exit_inside), "%s: exit reachable" % label)
	for marker in layout.markers:
		assert_true(reached.has(marker), "%s: marker %s reachable" % [label, marker])


func test_two_or_three_ingredients_per_room() -> void:
	var counts := {}
	var all_kinds: Array[int] = IngredientScatter.ALL_KINDS
	for id in OPEN_PLANS:
		var prepared := _prepare(_entry(id))
		for i in 10:
			var biome: StringName = BIOMES[i % BIOMES.size()]
			var plan := IngredientScatter.plan_room(prepared[0], IngredientSet.load_for_id(biome), all_kinds, 10, _rng(i * 31 + 7))
			assert_between(plan.ingredients.size(), 2, 3, "%s seed %d: %s" % [id, i, plan.ingredients])
			counts[plan.ingredients.size()] = counts.get(plan.ingredients.size(), 0) + 1
	assert_true(counts.has(2) and counts.has(3), "both 2 and 3 occur: %s" % counts)


## An open rectangular hall (21 x 11, a few markers): the planner's own playground. Since M1 the
## plan rooms are caves full of rock and keep two tiles between solid things, so a long chokepoint
## gate rarely finds a spot there; plan rooms scatter nothing anyway (R1).
func _open_layout() -> IngredientScatter.Layout:
	var tiles := RoomTiles.new()
	autofree(tiles)
	tiles.room_size = Vector2i(21, 11)
	tiles.entrance_x = 10
	tiles.exit_x = 10
	var markers: Array[Vector2i] = [Vector2i(3, 2), Vector2i(17, 2), Vector2i(10, 4), Vector2i(3, 8), Vector2i(17, 8)]
	return IngredientScatter.Layout.from_tiles(tiles, markers, [] as Array[Vector2i])


func test_distribution_over_many_seeds() -> void:
	var layout := _open_layout()
	var all_kinds: Array[int] = IngredientScatter.ALL_KINDS
	var counts := {}
	var crypt := IngredientSet.load_for_id(&"crypt")
	for i in DISTRIBUTION_SEEDS:
		var plan := IngredientScatter.plan_room(layout, crypt, all_kinds, 12, _rng(1000 + i))
		for kind in plan.ingredients:
			counts[kind] = counts.get(kind, 0) + 1
	var lines: Array[String] = []
	for kind in all_kinds:
		lines.append("%s %d" % [IngredientSet.get_kind_name(kind), counts.get(kind, 0)])
		assert_gt(counts.get(kind, 0), DISTRIBUTION_SEEDS * 0.15, "%s appears often enough" % IngredientSet.get_kind_name(kind))
	gut.p("crypt, open hall, %d seeds: %s" % [DISTRIBUTION_SEEDS, ", ".join(lines)])
	# Weighted: the light ingredient (1.0) comes clearly more often than explosives (0.6).
	assert_gt(counts.get(IngredientSet.Kind.LIGHT, 0), counts.get(IngredientSet.Kind.EXPLOSIVES, 0))


func test_explosives_follow_the_set() -> void:
	var layout := _open_layout()
	var all_kinds: Array[int] = IngredientScatter.ALL_KINDS
	for i in 120:
		var grotto := IngredientScatter.plan_room(layout, IngredientSet.load_for_id(&"slime_grotto"), all_kinds, 12, _rng(i))
		assert_false(grotto.ingredients.has(IngredientSet.Kind.EXPLOSIVES), "never in the slime grotto")
		var early := IngredientScatter.plan_room(layout, IngredientSet.load_for_id(&"ember_forge"), all_kinds, 1, _rng(i))
		assert_false(early.ingredients.has(IngredientSet.Kind.EXPLOSIVES), "not in room 1")


func test_plan_rooms_scatter_nothing() -> void:
	for entry in _catalog.get_entries():
		var scatter := (_prepare(entry)[1]) as IngredientScatter
		assert_eq(scatter.allowed, [] as Array[int], "%s: no random props (R1)" % entry.id)


func test_plan_is_reproducible() -> void:
	var prepared := _prepare(_entry(&"gewoelbe_crypt"))
	var a := IngredientScatter.plan_room(prepared[0], IngredientSet.load_for_id(&"ember_forge"), IngredientScatter.ALL_KINDS, 20, _rng(5))
	var b := IngredientScatter.plan_room(prepared[0], IngredientSet.load_for_id(&"ember_forge"), IngredientScatter.ALL_KINDS, 20, _rng(5))
	assert_eq(a.ingredients, b.ingredients)
	assert_eq(a.get_blocked_tiles(), b.get_blocked_tiles())
	assert_eq(a.get_tiles_of(IngredientScatter.ITEM_TRAP), b.get_tiles_of(IngredientScatter.ITEM_TRAP))


func test_plan_room_keeps_its_one_dungeon_rng_draw_and_builds_nothing() -> void:
	var entry := _entry(&"kreuzgang_crypt")
	var context := DungeonContext.new()
	context.rng = _rng(77)
	var room := entry.scene.instantiate() as RoomController
	room.setup(12, RoomSequence.RoomType.COMBAT, -1, false, context)
	add_child_autofree(room)
	var scatter := room.get_node("Ingredients") as IngredientScatter
	assert_not_null(scatter.plan, "the scatter ran when the room was built")
	assert_eq(scatter.plan.ingredients, [] as Array[int], "but placed nothing (R1)")
	assert_eq(scatter.get_built_nodes().size(), 0)
	var reference := _rng(77)
	reference.randi()
	assert_eq(context.rng.randi(), reference.randi(), "exactly one draw on the dungeon RNG, as before")


func test_scatter_skips_rooms_without_context() -> void:
	var room := _entry(&"combat_hall_crypt").scene.instantiate()
	add_child_autofree(room)
	assert_null((room.get_node("Ingredients") as IngredientScatter).plan, "tools and editor rooms stay empty")

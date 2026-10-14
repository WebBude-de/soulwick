extends GutTest
## Chasm templates and abyss holes (A4, KONZEPT_RAEUME §3.1-3.3): bridge hall, islands, walkway and
## ring around a hole in S/M/L; every floor tile reachable on foot (enemies), at least one dash
## shortcut, markers never on an abyss or a bridge, chasm rooms from room 6 only, and the ingredient
## "small abyss holes" from room 6 that keeps every tile reachable on foot.

const CHASM_SHAPES: Array[RoomTemplate.Shape] = [RoomTemplate.Shape.BRIDGE_HALL, RoomTemplate.Shape.ISLANDS,
	RoomTemplate.Shape.WALKWAY, RoomTemplate.Shape.RING_HOLE]
const BIOMES: Array[StringName] = [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]

var _old_save_path: String
var _catalog: RoomCatalog


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_chasm_templates_save.cfg"
	_catalog = RoomCatalog.create()


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _chasm_entries() -> Array[RoomTemplate]:
	var result: Array[RoomTemplate] = []
	for entry in _catalog.get_entries():
		if entry.room_kind == RoomSequence.RoomKind.CHASM:
			result.append(entry)
	return result


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_every_chasm_shape_in_s_m_l() -> void:
	var entries := _chasm_entries()
	assert_eq(entries.size(), 12)
	for shape in CHASM_SHAPES:
		var sizes := {}
		for entry in entries:
			if entry.shape == shape:
				sizes[entry.size_class] = true
		assert_eq(sizes.size(), 3, "%s in S, M and L" % RoomTemplate.get_shape_name(shape))
	for entry in entries:
		assert_eq(entry.min_room, 6, "%s: chasm rooms from room 6 (D-100)" % entry.id)
		assert_eq(RoomTemplate.get_room_name(entry.room_kind, entry), "Abgrund", "%s: named on entry (D-110)" % entry.id)


func test_chasm_layouts_work_on_foot_and_with_a_dash() -> void:
	for entry in _chasm_entries():
		var room := entry.scene.instantiate()
		autofree(room)
		var tiles := room.get_node("Tiles") as RoomTiles
		assert_true(tiles.has_pits(), "%s: abyss" % entry.id)
		assert_false(tiles.get_bridge_tiles().is_empty(), "%s: bridges" % entry.id)
		var on_foot := tiles.get_reachable_tiles(0)
		assert_true(on_foot.has(tiles.get_exit_inside_tile()), "%s: exit on foot" % entry.id)
		for tile: Vector2i in tiles.get_walkable_tiles():
			assert_true(on_foot.has(tile), "%s: %s reachable on foot (enemies cannot dash)" % [entry.id, tile])
		# A dash shortcut: two floor tiles with one pit tile between them.
		var shortcut := false
		for tile: Vector2i in on_foot:
			for step: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				if tiles.is_pit(tile + step) and on_foot.has(tile + step * 2):
					shortcut = true
		assert_true(shortcut, "%s: a one-tile gap to dash over" % entry.id)
		for tile in entry.spawn_tiles:
			assert_false(tiles.is_pit(tile) or tiles.is_bridge(tile), "%s: marker %s on solid floor" % [entry.id, tile])
		# Doors: no abyss right inside them.
		for tile: Vector2i in [tiles.get_entrance_inside_tile(), tiles.get_entrance_inside_tile() + Vector2i.UP, tiles.get_exit_inside_tile(), tiles.get_exit_inside_tile() + Vector2i.DOWN]:
			assert_false(tiles.is_pit(tile) or tiles.is_bridge(tile), "%s: door lane %s" % [entry.id, tile])
		# Template props (torches, bones) never stand over the abyss.
		for prop in room.get_node("Props").get_children():
			var tile := RoomTiles.local_to_tile((prop as Node2D).position - tiles.position)
			assert_false(tiles.is_pit(tile) or tiles.is_bridge(tile), "%s: %s over the abyss" % [entry.id, prop.name])


func test_scatter_keeps_bridges_free_and_chasm_rooms_walkable() -> void:
	for entry in _chasm_entries():
		var room := entry.scene.instantiate()
		autofree(room)
		var tiles := room.get_node("Tiles") as RoomTiles
		var scatter := room.get_node("Ingredients") as IngredientScatter
		assert_false(scatter.allowed.has(IngredientSet.Kind.PITS), "%s: no extra holes" % entry.id)
		assert_false(scatter.allowed.has(IngredientSet.Kind.WALLS), "%s: no extra walls" % entry.id)
		var layout := IngredientScatter.Layout.from_tiles(tiles, IngredientScatter.get_marker_tiles(room), scatter.reserved_tiles)
		for biome in BIOMES:
			for i in 5:
				var plan := IngredientScatter.plan_room(layout, IngredientSet.load_for_id(biome), scatter.allowed, 12, _rng(hash([entry.id, biome, i])))
				var blocked: Dictionary[Vector2i, bool] = {}
				for placement in plan.placements:
					for tile in placement.get_tiles():
						assert_false(tiles.is_bridge(tile) or tiles.is_pit(tile), "%s/%s: piece on %s over the abyss" % [entry.id, biome, tile])
						if placement.is_blocking():
							blocked[tile] = true
				var walkable := layout.walkable.duplicate()
				for tile in blocked:
					walkable.erase(tile)
				var none: Dictionary[Vector2i, bool] = {}
				var on_foot := RoomTiles.flood_fill(walkable, none, layout.entrance_inside, 0)
				for tile in layout.walk_reachable:
					assert_true(blocked.has(tile) or on_foot.has(tile), "%s/%s: %s still reachable on foot" % [entry.id, biome, tile])


func test_holes_only_from_room_six() -> void:
	var entry := _catalog.find_by_path("res://dungeon/rooms/combat/normal_rectangle_m.tscn")
	var room := entry.scene.instantiate()
	autofree(room)
	var tiles := room.get_node("Tiles") as RoomTiles
	var layout := IngredientScatter.Layout.from_tiles(tiles, IngredientScatter.get_marker_tiles(room), [] as Array[Vector2i])
	var all_kinds: Array[int] = IngredientScatter.ALL_KINDS
	var holes_seen := 0
	for i in 200:
		var early := IngredientScatter.plan_room(layout, IngredientSet.load_for_id(&"crypt"), all_kinds, 5, _rng(i))
		assert_false(early.ingredients.has(IngredientSet.Kind.PITS), "never in rooms 1-5")
		var deep := IngredientScatter.plan_room(layout, IngredientSet.load_for_id(BIOMES[i % 4]), all_kinds, 6, _rng(i))
		if deep.ingredients.has(IngredientSet.Kind.PITS):
			holes_seen += 1
			var holes := deep.get_pit_tiles()
			assert_between(holes.size(), 1, 8)
			var blocked: Dictionary[Vector2i, bool] = {}
			for tile in deep.get_blocked_tiles():
				blocked[tile] = true
			var walkable := layout.walkable.duplicate()
			for tile in blocked:
				walkable.erase(tile)
			var none: Dictionary[Vector2i, bool] = {}
			var on_foot := RoomTiles.flood_fill(walkable, none, layout.entrance_inside, 0)
			assert_true(on_foot.has(layout.exit_inside), "seed %d: exit on foot" % i)
			for marker in layout.markers:
				assert_true(on_foot.has(marker), "seed %d: marker %s on foot" % [i, marker])
			for hole in holes:
				assert_false(layout.keep_clear.has(hole), "seed %d: hole %s next to a marker or a door" % [i, hole])
	assert_gt(holes_seen, 20, "every biome has holes from room 6 (%d of 200)" % holes_seen)
	assert_true(IngredientScatter.ALL_KINDS.has(IngredientSet.Kind.PITS))


func test_holes_are_built_as_abyss() -> void:
	var entry := _catalog.find_by_path("res://dungeon/rooms/combat/normal_rectangle_m.tscn")
	# Find a dungeon seed whose room gets holes, then build it.
	for seed_value in 200:
		var context := DungeonContext.new()
		context.rng = _rng(seed_value)
		var room := entry.scene.instantiate() as RoomController
		room.setup(9, RoomSequence.RoomType.COMBAT, -1, false, context)
		add_child_autofree(room)
		var scatter := room.get_node("Ingredients") as IngredientScatter
		if not scatter.plan.ingredients.has(IngredientSet.Kind.PITS):
			room.queue_free()
			continue
		for tile in scatter.plan.get_pit_tiles():
			assert_true(room.tiles.is_pit(tile), "hole %s" % tile)
			assert_false(room.tiles.get_walkable_tiles().has(tile))
		await wait_process_frames(1)
		return
	fail_test("no seed with holes")

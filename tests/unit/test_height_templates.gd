extends GutTest
## Plateaus in the room templates (M3, Makeover 3 §8, tools/generate_room_templates.py): every
## template with height keeps the height rules, at most two plateaus covering 10-25 % of the floor,
## stairs and ladders in the cliff row with free ground at their foot; enough plans with height in
## every biome, a ladder plateau (safe island) and a chest on a plateau among them.

## Plans with plateaus (mirrored copies and biomes not counted). TESTWERT of the M3 package.
const MIN_HEIGHT_PLANS := 4

var _old_save_path: String
var _catalog: RoomCatalog


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_height_templates_save.cfg"
	_catalog = RoomCatalog.create()


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _height_rooms() -> Array[RoomController]:
	var rooms: Array[RoomController] = []
	var entries := _catalog.get_entries()
	entries.append_array(RoomCatalog.load_plans().get_entries())
	for entry in entries:
		var room := entry.scene.instantiate() as RoomController
		autofree(room)
		if (room.get_node("Tiles") as RoomTiles).has_height():
			rooms.append(room)
	return rooms


func test_templates_with_height_keep_the_rules() -> void:
	var rooms := _height_rooms()
	assert_gt(rooms.size(), 0, "templates with plateaus exist")
	for room in rooms:
		var tiles := room.get_node("Tiles") as RoomTiles
		var layout := tiles.get_height_layout()
		var name := room.scene_file_path.get_file()
		assert_eq(RoomPlanChecks.height_problems(tiles), [] as Array[String], name)
		var groups := layout.components()
		assert_between(groups.size(), 1, 2, "%s: one or two plateaus" % name)
		var height := layout.get_height_tiles().size()
		var share := float(height) / float(tiles.get_walkable_tiles().size() + height)
		assert_between(share, 0.09, 0.26, "%s: plateaus cover %.0f %% of the floor" % [name, share * 100.0])
		for tile: Vector2i in layout.ladders.keys() + layout.stairs.keys():
			assert_true(tiles.get_reachable_tiles(0).has(tile + Vector2i.DOWN), "%s: free ground at the foot of %s" % [name, tile])


func test_enough_plans_with_height_in_every_biome() -> void:
	var plans := {}
	var biomes := {}
	var ladder_only := false
	var chest_on_plateau := false
	for room in _height_rooms():
		var template := RoomTemplate.of(room)
		if template == null:
			template = RoomCatalog.find_template_of(room)
		var tiles := room.get_node("Tiles") as RoomTiles
		var layout := tiles.get_height_layout()
		var key := String(template.plan_id) if template != null else room.scene_file_path
		plans[key] = true
		if template != null:
			for biome in template.allowed_biomes:
				biomes[biome] = true
		for group in layout.components():
			var stairs := false
			for tile: Vector2i in group:
				stairs = stairs or layout.stairs.has(tile)
			ladder_only = ladder_only or not stairs
		for prop in room.get_node("Props").get_children():
			if prop is TreasureChest and layout.surface.has(RoomTiles.local_to_tile(prop.position)):
				chest_on_plateau = true
	assert_gte(plans.size(), MIN_HEIGHT_PLANS, "plans with plateaus: %s" % [plans.keys()])
	for biome: StringName in [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]:
		assert_true(biomes.has(biome), "plateaus in %s" % biome)
	assert_true(ladder_only, "a plateau with only a ladder: a safe island for bow and staff")
	assert_true(chest_on_plateau, "a chest on a plateau")

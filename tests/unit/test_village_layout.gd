extends GutTest
## B3 Dorf beleben: compact layout, decoration never on paths/doors/spawn (fixed seed), every door
## and the dungeon entrance reachable from the spawn (physics flood fill with the player's body),
## several buildings in every camera view, neighbour houses without doors, chimney smoke, the formerly
## unused art in the scene, props from SPRITES_V4 off the paths. Runs in a test folder
## (SaveManager.set_storage_root), never on the real save.

const ROOT := "user://test_village_layout"
const VILLAGE_SCENE := "res://world/village/village.tscn"
## Player body from player.tscn: circle radius 9, 8 px below the origin; feet 16 px below it.
const BODY_RADIUS := 9.0
const BODY_OFFSET := Vector2(0, 8)
const GRID := 16.0
## Camera view at 1280×720 (zoom 1).
const VIEW := Vector2(1280, 720)
## Buildings (incl. neighbour houses and the entrance) are props at least this wide (world px).
const BUILDING_WIDTH := 120.0

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()


func after_each() -> void:
	GameManager.clear_pause_reasons()


func after_all() -> void:
	_wipe()
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()


func _wipe() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	for dir_path in [root.path_join("saves"), root]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			DirAccess.remove_absolute(dir_path.path_join(file))
	DirAccess.make_dir_recursive_absolute(root)


func _village() -> Village:
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	add_child_autofree(village)
	return village


func _paths(village: Node) -> Array[Rect2]:
	var ground := village.get_node("Ground") as VillageTiles
	var tile := 32.0 * ground.scale.x
	var result: Array[Rect2] = []
	for rect in ground.path_rects:
		result.append(Rect2(Vector2(rect.position) * tile, Vector2(rect.size) * tile))
	return result


func _map(village: Village) -> Rect2:
	return Rect2(village.get_camera_limits())


## Door and entrance circles: [{"id", "centre", "radius"}].
func _doors(village: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for building in village.get_node("Buildings").get_children():
		for area in building.find_children("*", "Interactable", true, false):
			var shape := area.get_node("CollisionShape2D") as CollisionShape2D
			var id := String(building.get_meta(&"building_id")) if building.has_meta(&"building_id") else String(building.name)
			result.append({"id": id, "centre": shape.global_position, "radius": (shape.shape as CircleShape2D).radius})
	return result


func _on_path(point: Vector2, paths: Array[Rect2], margin := 0.0) -> bool:
	for path in paths:
		if path.grow(margin).has_point(point):
			return true
	return false


# --- Layout ---

func test_map_is_compact() -> void:
	var village := _village()
	var map := _map(village)
	assert_lt(map.size.x * map.size.y, 36.0 * 24.0 * 64.0 * 64.0 * 0.75, "at least a quarter smaller than the old 36×24 map")
	assert_gte(map.size.x, VIEW.x, "camera never shows outside the map")
	assert_gte(map.size.y, VIEW.y)


func test_every_camera_view_shows_several_buildings() -> void:
	var village := _village()
	var map := _map(village)
	var buildings: Array[Rect2] = []
	for prop in village.get_node("Buildings").get_children():
		var rect := VillageDecor.sprite_rect_of(prop)
		if prop is StaticBody2D and rect.size.x >= BUILDING_WIDTH:
			buildings.append(rect)
	assert_gte(buildings.size(), 10, "5 buildings, the entrance and the neighbour houses")
	var fewest := 99
	var x := VIEW.x * 0.5
	while x <= map.size.x - VIEW.x * 0.5:
		var y := VIEW.y * 0.5
		while y <= map.size.y - VIEW.y * 0.5:
			var view := Rect2(Vector2(x, y) - VIEW * 0.5, VIEW)
			var seen := 0
			for rect in buildings:
				if view.intersection(rect).get_area() >= rect.get_area() * 0.5:
					seen += 1
			fewest = mini(fewest, seen)
			y += 32.0
		x += 32.0
	gut.p("fewest buildings in a camera view: %d" % fewest)
	assert_gte(fewest, 4, "at least four buildings at least half in view from every camera position (found %d)" % fewest)


func test_neighbour_houses_are_solid_without_door() -> void:
	var village := _village()
	var houses := 0
	var textures := {}
	for prop in village.get_node("Buildings").get_children():
		if not prop.has_meta(&"neighbour_house"):
			continue
		houses += 1
		assert_false(prop.has_meta(&"building_id"), "%s has no dialog" % prop.name)
		assert_eq(prop.find_children("*", "Interactable", true, false).size(), 0, "%s has no door" % prop.name)
		assert_not_null(prop.get_node_or_null("CollisionShape2D"), "%s is solid" % prop.name)
		textures[((prop.get_node("Sprite") as Sprite2D).texture.resource_path).get_file()] = true
	assert_gte(houses, 4)
	for file in ["house_1.png", "house_2.png", "house_3.png"]:
		assert_true(textures.has(file), "%s in use" % file)


func test_formerly_unused_art_is_in_the_village() -> void:
	var village := _village()
	var used := {}
	for prop in village.get_node("Buildings").get_children():
		var sprite := prop.get_node_or_null("Sprite") as Sprite2D
		if sprite != null and sprite.texture != null and not sprite.texture.resource_path.is_empty():
			used[sprite.texture.resource_path.get_file()] = true
		# Animated props (fountain, well) keep their strip on an AnimatedProp.
		var animated := prop.get_node_or_null("Sprite") as AnimatedProp
		if animated != null and animated.strip != null:
			used[animated.strip.resource_path.get_file()] = true
	for file in ["fountain_4f.png", "barrel.png", "crate.png", "well_4f.png", "market_stall.png"]:
		assert_true(used.has(file), "%s placed" % file)
	assert_gte(village.get_node("Buildings").find_children("Lamp*", "", false, false).size(), 4, "lamps")


func test_chimneys_smoke() -> void:
	var village := _village()
	var smoke := village.find_children("*", "ChimneySmoke", true, false)
	assert_gte(smoke.size(), 4)
	for node in smoke:
		assert_true((node as ChimneySmoke).emitting)
	assert_not_null(village.get_node("Buildings/Home/Smoke"), "smoke from the player's home")


# --- Decoration scatter ---

func test_decoration_is_deterministic() -> void:
	var village := _village()
	var rules := VillageDecor.collect_rules(village)
	var first := VillageDecor.plan(rules)
	var second := VillageDecor.plan(rules)
	assert_eq(first.size(), second.size())
	for i in first.size():
		assert_eq(first[i]["position"], second[i]["position"])
		assert_eq(first[i]["art"], second[i]["art"])
	var decor := village.get_node("Decor") as VillageDecor
	assert_eq(decor.placements.size(), first.size(), "the village places exactly the plan")
	assert_eq(decor.get_child_count(), first.size())


func test_decoration_never_on_paths_doors_or_spawn() -> void:
	var village := _village()
	var decor := village.get_node("Decor") as VillageDecor
	gut.p("decoration items: %d" % decor.placements.size())
	assert_gte(decor.placements.size(), 40, "enough decoration (found %d)" % decor.placements.size())
	var paths := _paths(village)
	var doors := _doors(village)
	# D-152: the mirror next to Zuhause is used with E like a door.
	assert_eq(doors.size(), VillageBuildings.ALL.size() + 2, "five doors, the mirror and the entrance")
	var spawn := (village.get_node("PlayerSpawn") as Node2D).global_position
	var inner := _map(village).grow(-64.0)
	var kinds := {}
	for item in decor.placements:
		var rect: Rect2 = item["rect"]
		kinds[item["art"]] = true
		assert_true(inner.encloses(rect), "%s inside the fence" % item["art"])
		for path in paths:
			assert_false(path.intersects(rect), "%s at %s not on a path" % [item["art"], item["position"]])
		for door in doors:
			assert_gt(VillageDecor.rect_circle_distance(rect, door["centre"]), door["radius"], "%s off the door of %s" % [item["art"], door["id"]])
		assert_gt(VillageDecor.rect_circle_distance(rect, spawn), 96.0, "%s away from the spawn" % item["art"])
	assert_gte(kinds.size(), 4, "several kinds of decoration")


func test_decoration_does_not_collide() -> void:
	var village := _village()
	assert_eq(village.get_node("Decor").find_children("*", "CollisionObject2D", true, false).size(), 0)
	# Animals carry an Area2D to be spoken to (WK12, VillageAnimal); nothing solid.
	assert_eq(village.get_node("Villagers").find_children("*", "PhysicsBody2D", true, false).size(), 0, "villagers never block")


## Report #d83bda23: flat decoration (grass, stones, flowers) and the rubble lie under characters,
## their weapons and shadows (not y-sorted over a sword pointing down); the small bush stays sorted.
## #5a560cd1: no walkable decoration flower beds next to the solid ones.
func test_flat_decoration_lies_under_characters() -> void:
	var village := _village()
	var decor := village.get_node("Decor") as VillageDecor
	var ground_z := (village.get_node("Ground") as CanvasItem).z_index
	var flat := 0
	for i in decor.placements.size():
		var art: String = decor.placements[i]["art"]
		var holder := decor.get_child(i) as Node2D
		assert_ne(art, "flower_bed", "beds are solid props, not scattered decoration")
		if VillageDecor.is_flat(art):
			flat += 1
			assert_lt(holder.z_index, DropShadow.Z, "%s under shadows and weapons" % art)
			assert_gt(holder.z_index, ground_z, "%s above the ground" % art)
		else:
			assert_eq(holder.z_index, 0, "%s y-sorted like a prop" % art)
	assert_gt(flat, 20, "most decoration is flat")
	for rubble_name in ["Rubble1", "Rubble2"]:
		var rubble := village.get_node_or_null("Buildings/" + rubble_name) as CanvasItem
		if rubble != null:
			assert_lt(rubble.z_index, DropShadow.Z, "%s lies flat" % rubble_name)


## Opaque part of a prop's sprite in village coordinates (Rect2() without a Sprite2D).
func _opaque_rect(prop: Node) -> Rect2:
	var sprite := prop.get_node_or_null("Sprite") as Sprite2D
	if sprite == null or sprite.texture == null:
		return Rect2()
	var used := sprite.texture.get_image().get_used_rect()
	var local := sprite.get_rect()
	var x := local.position.x + (local.size.x - used.end.x if sprite.flip_h else float(used.position.x))
	var rect := Rect2(Vector2(x, local.position.y + used.position.y), Vector2(used.size))
	var xform := sprite.global_transform
	return Rect2(xform * rect.position, xform.basis_xform(rect.size)).abs()


## Reports #5a560cd1, #0a088654, #90544fa9: beds, crates, barrels and the market stall block like the
## hay bales: a box as wide as the visible art (at most 8 px less), standing on its bottom edge and
## covering its lower part, never sticking out of it.
func test_prop_hitboxes_match_their_art() -> void:
	var village := _village()
	var checked := {}
	for prop in village.get_node("Buildings").get_children():
		var prop_name := String(prop.name)
		var kind := prop_name.rstrip("0123456789")
		if not kind in ["Bed", "Crate", "Barrel", "MarketStall", "HayBale"]:
			continue
		var holder := prop.get_node_or_null("CollisionShape2D") as CollisionShape2D
		assert_not_null(holder, "%s is solid" % prop_name)
		if holder == null:
			continue
		var box_shape := holder.shape as RectangleShape2D
		assert_not_null(box_shape, "%s has a box, not a small circle" % prop_name)
		if box_shape == null:
			continue
		var box := Rect2(holder.global_position - box_shape.size * 0.5, box_shape.size)
		var art := _opaque_rect(prop)
		assert_true(art.has_area(), "%s has art" % prop_name)
		assert_true(art.grow(0.5).encloses(box), "%s: box %s inside the art %s" % [prop_name, box, art])
		assert_gte(box.size.x, art.size.x - 8.5, "%s: about as wide as it looks" % prop_name)
		assert_almost_eq(box.end.y, art.end.y, 4.5, "%s: on its bottom edge" % prop_name)
		assert_between(box.size.y, art.size.y * 0.3, art.size.y * 0.65, "%s: the lower part" % prop_name)
		checked[kind] = true
	assert_eq(checked.size(), 5, "beds, crates, barrels, the stall and the hay bales: %s" % [checked.keys()])


## Report #d73e649d: the bush (ground tile, never drawn in front of the player) stops a player from
## the north with the feet on its upper edge, not before it; bush and stump keep inside their art.
func test_bush_and_stump_hitboxes_inside_their_art() -> void:
	var tileset := load("res://world/village/village_tileset.tres") as TileSet
	var source := tileset.get_source(0) as TileSetAtlasSource
	# Art extents in tile px from the centre: bush x -12..12, y -4..12; stump x -8..8, y -6..11.
	for entry in [[VillageTiles.BUSH, Rect2(-12, -4, 24, 16)], [VillageTiles.STUMP, Rect2(-8, -6, 16, 17)]]:
		var data := source.get_tile_data(entry[0], 0)
		assert_eq(data.get_collision_polygons_count(0), 1)
		var points := data.get_collision_polygon_points(0, 0)
		var box := Rect2(points[0], Vector2.ZERO)
		for point in points:
			box = box.expand(point)
		var art: Rect2 = entry[1]
		assert_true(art.encloses(box), "%s: %s inside %s" % [entry[0], box, art])
		assert_gt(box.position.y, art.position.y, "%s: the top of the art is walkable" % entry[0])


func test_rule_rejects_paths_doors_and_spawn() -> void:
	var village := _village()
	var rules := VillageDecor.collect_rules(village)
	var paths := _paths(village)
	var on_path := Rect2(paths[0].get_center() - Vector2(8, 8), Vector2(16, 16))
	assert_false(VillageDecor.is_allowed(on_path, rules), "on a path")
	var door: Dictionary = _doors(village)[0]
	assert_false(VillageDecor.is_allowed(Rect2(door["centre"] - Vector2(8, 8), Vector2(16, 16)), rules), "on a door")
	var spawn := (village.get_node("PlayerSpawn") as Node2D).global_position
	assert_false(VillageDecor.is_allowed(Rect2(spawn + Vector2(40, 0), Vector2(16, 16)), rules), "next to the spawn")


# --- Reachability ---

func test_all_doors_and_the_entrance_are_reachable() -> void:
	var village := _village()
	await wait_physics_frames(3)
	var space := village.get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var body := CircleShape2D.new()
	body.radius = BODY_RADIUS
	query.shape = body
	query.collision_mask = PhysicsLayers.WORLD
	query.collide_with_areas = false
	var map := _map(village)
	var start := (village.get_node("PlayerSpawn") as Node2D).global_position
	var origin := start - (start / GRID).floor() * GRID
	var is_free := func(cell: Vector2i) -> bool:
		var point := origin + Vector2(cell) * GRID
		if not map.has_point(point):
			return false
		query.transform = Transform2D(0.0, point + BODY_OFFSET)
		return space.intersect_shape(query, 1).is_empty()
	var first := Vector2i((start / GRID).floor())
	assert_true(is_free.call(first), "spawn is free")
	var reached := {first: true}
	var open: Array[Vector2i] = [first]
	while not open.is_empty():
		var cell: Vector2i = open.pop_back()
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + step
			if not reached.has(next) and is_free.call(next):
				reached[next] = true
				open.append(next)
	gut.p("walkable cells (16 px): %d" % reached.size())
	assert_gt(reached.size(), 1500, "a large walkable area")
	for door in _doors(village):
		var ok := false
		for cell: Vector2i in reached:
			var point := origin + Vector2(cell) * GRID
			if point.distance_to(door["centre"]) <= float(door["radius"]):
				ok = true
				break
		assert_true(ok, "%s reachable from the spawn" % door["id"])


func test_props_from_sprites_v4_stay_off_paths_and_doors() -> void:
	# Not added to the tree: the reserved spots count even while the art is missing.
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	var tile := 64.0
	var ground := village.get_node("Ground") as VillageTiles
	var paths: Array[Rect2] = []
	for rect in ground.path_rects:
		paths.append(Rect2(Vector2(rect.position) * tile, Vector2(rect.size) * tile))
	var doors: Array[Vector2] = []
	for building in village.get_node("Buildings").get_children():
		var door := building.get_node_or_null("Door") as Node2D
		if door != null:
			doors.append((building as Node2D).position + door.position)
	var props := 0
	for prop in village.get_node("Buildings").get_children():
		if not prop is VillageProp:
			continue
		props += 1
		var footprint := (prop as VillageProp).get_footprint((prop as Node2D).position)
		for path in paths:
			assert_false(path.intersects(footprint), "%s off the paths" % prop.name)
		for door in doors:
			assert_gt(VillageDecor.rect_circle_distance(footprint, door), 48.0, "%s off the doors" % prop.name)
	assert_gte(props, 8)
	village.free()


func test_villager_routes_stay_on_paths_and_off_doors() -> void:
	var village := _village()
	var paths := _paths(village)
	var doors := _doors(village)
	var walkers := 0
	for node in village.get_node("Villagers").get_children():
		var villager := node as Villager
		if villager == null or villager.optional:
			continue
		walkers += 1
		var route := villager.route
		var count := route.size() if villager.loop else route.size() - 1
		for i in count:
			var a := route[i]
			var b := route[(i + 1) % route.size()]
			var steps := maxi(1, int(a.distance_to(b) / 8.0))
			for s in steps + 1:
				var point := a.lerp(b, float(s) / steps)
				assert_true(_on_path(point, paths, 4.0), "%s walks on the path at %s" % [villager.name, point])
		for point in route:
			for door in doors:
				assert_gt(point.distance_to(door["centre"]), float(door["radius"]), "%s does not stop in a door" % villager.name)
	assert_between(walkers, 2, 4, "2–4 villagers")

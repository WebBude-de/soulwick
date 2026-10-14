extends GutTest
## R7: the rescued from the escort (D-135, RescueRecord) live in the village: one walker per rescued
## villager in rescue order with the escort's cloak colours and a lantern lit at night, rescued
## chickens join the chickens in their territory; both capped. Routes stay on paved ground and off
## the doors. Runs in a test folder (SaveManager.set_storage_root), never on the real save.

const ROOT := "user://test_village_rescued"
const VILLAGE_SCENE := "res://world/village/village.tscn"
const TILE := 64.0

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


func before_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
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


func _rescue(villagers: int, chickens: int) -> void:
	for i in villagers:
		RescueRecord.record(false)
	for i in chickens:
		RescueRecord.record(true)


func test_fresh_save_has_no_rescued() -> void:
	var village := _village()
	assert_eq(village.get_rescued_walkers(false).size(), 0)
	assert_eq(village.get_rescued_walkers(true).size(), 0)
	assert_gt(village.get_node("Villagers").get_child_count(), 3, "the usual villagers still walk")


func test_one_walker_per_rescued_in_rescue_order() -> void:
	_rescue(3, 1)
	var village := _village()
	var walkers := village.get_rescued_walkers(false)
	assert_eq(walkers.size(), 3)
	for walker in walkers:
		var slot := int(walker.get_meta(&"rescued_slot"))
		assert_lt(slot, 3, "the first slots")
		assert_eq(walker.get_cloak(), LostVillager.CLOAK_TINTS[slot % LostVillager.CLOAK_TINTS.size()], "escort cloak colour")
		assert_eq(walker.art_name, "lost_villager", "the escort figure")
		var lantern := walker.get_node_or_null("Lantern") as LightSource
		assert_not_null(lantern, "carries the lantern")
		assert_true(lantern.is_in_group(VillageEvening.NIGHT_GROUP), "lit at night only")
	assert_eq(village.get_rescued_walkers(true).size(), 1, "the rescued chicken")


func test_rescued_are_capped() -> void:
	_rescue(20, 9)
	var village := _village()
	assert_eq(village.get_rescued_walkers(false).size(), Village.MAX_RESCUED_VILLAGERS)
	assert_eq(village.get_rescued_walkers(true).size(), Village.MAX_RESCUED_CHICKENS)
	assert_eq(Village.rescued_shown(false), Village.MAX_RESCUED_VILLAGERS)


func test_rescued_routes_stay_on_paved_ground_and_off_doors() -> void:
	_rescue(Village.MAX_RESCUED_VILLAGERS, 0)
	var village := _village()
	var ground := village.get_node("Ground") as VillageTiles
	var paved: Array[Rect2] = []
	for rect in ground.get_paved_rects():
		paved.append(Rect2(Vector2(rect.position) * TILE, Vector2(rect.size) * TILE).grow(4.0))
	var doors: Array[Vector2] = []
	for building in village.get_node("Buildings").get_children():
		var door := building.get_node_or_null("Door") as Node2D
		if door != null:
			doors.append(door.global_position)
	for walker in village.get_rescued_walkers(false):
		var route := walker.route
		var count := route.size() if walker.loop else route.size() - 1
		for i in count:
			var a := route[i]
			var b := route[(i + 1) % route.size()]
			var steps := maxi(1, int(a.distance_to(b) / 8.0))
			for s in steps + 1:
				var point := a.lerp(b, float(s) / steps)
				var on_paved := false
				for rect in paved:
					if rect.has_point(point):
						on_paved = true
						break
				assert_true(on_paved, "%s walks on paved ground at %s" % [walker.name, point])
		for point in route:
			for door in doors:
				assert_gt(point.distance_to(door), 32.0, "%s does not stop in a door" % walker.name)


func test_chicken_territories_stay_off_paths() -> void:
	_rescue(0, Village.MAX_RESCUED_CHICKENS)
	var village := _village()
	var ground := village.get_node("Ground") as VillageTiles
	var chickens: Array[Villager] = village.get_rescued_walkers(true)
	for node in village.get_node("Villagers").get_children():
		if node is Villager and (node as Villager).art_name == "chicken" and not node.has_meta(&"rescued_chicken_slot"):
			chickens.append(node as Villager)
	assert_gte(chickens.size(), 2 + Village.MAX_RESCUED_CHICKENS)
	for chicken in chickens:
		for point in chicken.route:
			for rect in ground.path_rects:
				assert_false(Rect2(Vector2(rect.position) * TILE, Vector2(rect.size) * TILE).has_point(point), "%s keeps to its territory, off the lanes" % chicken.name)

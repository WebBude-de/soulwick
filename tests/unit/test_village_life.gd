extends GutTest
## B3 Dorf beleben: villagers walk their route back and forth or in a loop and wait at the points,
## pollen by day and fireflies in the evening, placeholders until the SPRITES_V4 art exists.
## No save access.

const FALLBACK_FRAMES := "res://art/characters/npcs/smith_frames.tres"


func _villager(points: PackedVector2Array, looping := false) -> Villager:
	var villager := Villager.new()
	villager.route = points
	villager.loop = looping
	villager.speed = 40.0
	villager.pause_min = 0.0
	villager.pause_max = 0.0
	villager.art_name = "test_villager_without_art"
	villager.fallback_frames = load(FALLBACK_FRAMES) as SpriteFrames
	villager.set_process(false)
	add_child_autofree(villager)
	return villager


func test_next_index_back_and_forth() -> void:
	var state := [0, true]
	var visited: Array[int] = [0]
	for i in 6:
		state = Villager.next_index(state[0], 3, false, state[1])
		visited.append(state[0])
	assert_eq(visited, [0, 1, 2, 1, 0, 1, 2] as Array[int])


func test_next_index_loop() -> void:
	var state := [0, true]
	var visited: Array[int] = [0]
	for i in 4:
		state = Villager.next_index(state[0], 3, true, state[1])
		visited.append(state[0])
	assert_eq(visited, [0, 1, 2, 0, 1] as Array[int])


func test_villager_walks_from_point_to_point() -> void:
	var villager := _villager(PackedVector2Array([Vector2(100, 100), Vector2(200, 100)]))
	assert_eq(villager.get_feet(), Vector2(100, 100), "starts on the first point (feet)")
	for i in 10:
		villager._process(0.25)
	assert_almost_eq(villager.get_feet().x, 200.0, 0.01, "arrived at the second point")
	assert_almost_eq(villager.get_feet().y, 100.0, 0.01, "stays on the line")
	# One frame notices the arrival, then 10 frames back.
	for i in 11:
		villager._process(0.25)
	assert_almost_eq(villager.get_feet().x, 100.0, 0.01, "and back again")


func test_villager_waits_at_points() -> void:
	var villager := _villager(PackedVector2Array([Vector2(0, 0), Vector2(400, 0)]))
	villager.pause_min = 5.0
	villager.pause_max = 5.0
	for i in 40:
		villager._process(0.5)
	# 400 px at 40 px/s = 10 s, plus a 5 s stop at the end: then halfway back after 20 s at most.
	assert_lt(villager.get_feet().x, 400.0)
	assert_gt(villager.get_feet().x, 150.0, "stopped at the end before walking back")


func test_villager_uses_fallback_with_tint_and_has_no_collision() -> void:
	var villager := _villager(PackedVector2Array([Vector2(0, 0), Vector2(10, 0)]))
	var sprite := villager.get_node("Sprite") as AnimatedSprite2D
	assert_not_null(sprite)
	assert_eq(sprite.sprite_frames, load(FALLBACK_FRAMES))
	assert_eq(villager.find_children("*", "CollisionObject2D", true, false).size(), 0)


## A stand-in player (group &"player", origin FEET_OFFSET above the feet like Player).
func _player_at(feet: Vector2) -> Node2D:
	var player := Node2D.new()
	player.add_to_group(&"player")
	player.position = feet - Villager.FEET_OFFSET
	add_child_autofree(player)
	return player


## Report #ec4f0b9f: a walking villager goes around a player standing in its way and walks on.
func test_villager_steps_around_a_player_in_its_way() -> void:
	var villager := _villager(PackedVector2Array([Vector2(100, 100), Vector2(400, 100)]))
	var blocker := Vector2(160, 100)
	_player_at(blocker)
	var closest := INF
	for i in 80:
		villager._process(0.05)
		closest = minf(closest, villager.get_feet().distance_to(blocker))
	assert_gt(closest, 20.0, "around the player, not through (closest %.1f px)" % closest)
	assert_gt(villager.get_feet().x, 220.0, "and on along its way")
	assert_eq(villager.find_children("*", "CollisionObject2D", true, false).size(), 0, "still never blocks")
	for i in 80:
		villager._process(0.05)
	assert_almost_eq(villager.get_side_offset().length(), 0.0, 0.01, "back on its route")


## Report #ec4f0b9f: running into a villager makes it hop aside with a "?" and stand for a moment.
func test_villager_hops_aside_when_a_player_runs_into_it() -> void:
	var villager := _villager(PackedVector2Array([Vector2(100, 100), Vector2(400, 100)]))
	var player := _player_at(Vector2(100, 40))
	villager._process(0.05)
	assert_false(villager.is_dodging(), "a player standing far away changes nothing")
	player.position += Vector2(0, 45)
	villager._process(0.05)
	assert_true(villager.is_dodging(), "the player ran into it (900 px/s, 15 px away)")
	assert_not_null(villager.get_huh(), "a confused '?' above the head")
	var x_before := villager.get_feet().x
	for i in 6:
		villager._process(0.05)
	assert_gt(villager.get_side_offset().x, Villager.DODGE_DISTANCE - 0.5, "hopped across the player's way")
	assert_almost_eq(villager.get_feet().x - x_before, Villager.DODGE_DISTANCE, 1.0, "without walking on meanwhile")
	for i in 40:
		villager._process(0.05)
	assert_false(villager.is_dodging(), "walks on after a moment")
	assert_null(villager.get_huh(), "the '?' is gone")


func test_villager_never_hops_into_something_solid() -> void:
	var villager := _villager(PackedVector2Array([Vector2(100, 100), Vector2(400, 100)]))
	# A wall right where the hop would go first (to the right of the player's way).
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(40, 200)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector2(145, 100)
	add_child_autofree(wall)
	await wait_physics_frames(2)
	assert_false(villager.is_spot_free(Vector2(138, 100)), "the wall blocks")
	assert_true(villager.is_spot_free(Vector2(66, 100)))
	var player := _player_at(Vector2(100, 40))
	villager._process(0.05)
	player.position += Vector2(0, 45)
	villager._process(0.05)
	for i in 6:
		villager._process(0.05)
	assert_lt(villager.get_side_offset().x, -Villager.DODGE_DISTANCE + 0.5, "hopped to the free side")


func test_village_villagers_sound_confused_animals_stay_silent() -> void:
	var village: Node = (load("res://world/village/village.tscn") as PackedScene).instantiate()
	var humans := 0
	var animals := 0
	for node in village.get_node("Villagers").get_children():
		var walker := node as Villager
		if walker == null:
			continue
		if walker.animal != &"":
			animals += 1
			assert_eq(walker.dodge_sound, &"", "%s: no villager sound for animals" % walker.name)
		else:
			humans += 1
			assert_eq(walker.dodge_sound, &"villager_huh", "%s says 'hm?'" % walker.name)
	village.free()
	assert_gt(humans, 3)
	assert_gt(animals, 2)
	assert_true(ResourceLoader.exists(Sfx.SFX_DIR + "villager_huh.wav"), "tools/generate_audio.py village")


func test_optional_animal_without_art_frees_itself() -> void:
	var cat := Villager.new()
	cat.route = PackedVector2Array([Vector2.ZERO, Vector2(10, 0)])
	cat.art_name = "test_animal_without_art"
	cat.optional = true
	add_child(cat)
	assert_true(cat.is_queued_for_deletion(), "nothing without art")
	await wait_process_frames(1)
	assert_false(is_instance_valid(cat))


func test_evening_shows_fireflies() -> void:
	assert_true(VillageAmbience.is_evening(20))
	assert_true(VillageAmbience.is_evening(2))
	assert_false(VillageAmbience.is_evening(6))
	assert_false(VillageAmbience.is_evening(14))
	var ambience := VillageAmbience.new()
	add_child_autofree(ambience)
	var map := Rect2(0, 0, 1920, 1216)
	ambience.setup(map, 21)
	assert_eq(ambience.mode, VillageAmbience.Mode.FIREFLIES)
	assert_eq(ambience.emission_rect_extents, map.size * 0.5, "covers the whole map")
	assert_true(ambience.emitting)
	ambience.setup(map, 11)
	assert_eq(ambience.mode, VillageAmbience.Mode.POLLEN)


func test_placeholders_until_art_exists() -> void:
	for art in ["flowers_1", "flowers_2", "flowers_3", "grass_tuft", "stones", "bush_small", "garden_fence", "flower_bed", "hay_bale", "bench", "signpost", "pond"]:
		assert_not_null(VillageArt.get_texture(art), "%s: file or placeholder" % art)
	if not VillageArt.has_art("cart"):
		assert_null(VillageArt.get_texture("cart"), "no placeholder for the cart")
	if not VillageArt.has_character_art("chicken"):
		assert_not_null(VillageArt.get_character_frames("chicken"), "chicken placeholder")
	if not VillageArt.has_character_art("cat"):
		assert_null(VillageArt.get_character_frames("cat"), "no cat without art")


func test_tileset_placeholder_has_transparent_background() -> void:
	if VillageArt.has_art("garden_fence"):
		pass_test("real art in use")
		return
	var image := VillageArt.get_texture("garden_fence").get_image()
	assert_eq(image.get_pixel(0, 0).a, 0.0, "grass removed")
	var opaque := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				opaque += 1
	assert_gt(opaque, 100, "the fence stays")

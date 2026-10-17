extends GutTest
## The shared light decision (A9, D-116): any number of light circles - every
## player's own circle (state at the player), LightSources that count (torches, crystals, lantern),
## never flashes or enemy glows - and the pure circle test that the light run uses too.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_light_query_save.cfg"


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func _light(at: Vector2, radius: float, counts: bool) -> LightSource:
	var light := LightSource.new()
	light.radius = radius
	light.counts_as_light = counts
	add_child_autofree(light)
	light.global_position = at
	return light


func _player(at: Vector2, drawn_radius: float) -> Player:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.global_position = at
	LightQuery.set_player_radius(player, drawn_radius)
	return player


# --- Pure part ---

func test_point_in_any_of_many_circles() -> void:
	var circles: Array[Vector3] = [LightQuery.circle(Vector2(0, 0), 100.0), LightQuery.circle(Vector2(500, 0), 50.0)]
	assert_true(LightQuery.is_in_circles(Vector2(60, 60), circles), "inside the first")
	assert_true(LightQuery.is_in_circles(Vector2(540, 0), circles), "inside the second")
	assert_true(LightQuery.is_in_circles(Vector2(100, 0), circles), "the edge counts")
	assert_false(LightQuery.is_in_circles(Vector2(300, 0), circles), "between them it is dark")
	assert_false(LightQuery.is_in_circles(Vector2.ZERO, [] as Array[Vector3]), "no light, no lit point")
	assert_false(LightQuery.is_in_circles(Vector2.ZERO, [LightQuery.circle(Vector2.ZERO, 0.0)] as Array[Vector3]), "a zero circle lights nothing")


func test_circles_from_points_match_the_old_light_run_rule() -> void:
	var points := PackedVector2Array([Vector2(0, 0), Vector2(400, 0)])
	var circles := LightQuery.circles_from_points(points, 140.0)
	for point: Vector2 in [Vector2(0, 139), Vector2(0, 141), Vector2(270, 0), Vector2(250, 30), Vector2(400, -140)]:
		assert_eq(LightQuery.is_in_circles(point, circles), TrialRules.is_point_lit(point, points, 140.0), "same decision at %s" % point)


func test_player_circle_counts_without_its_soft_edge() -> void:
	assert_almost_eq(LightQuery.player_lit_radius(300.0), 300.0 - LightQuery.PLAYER_SOFT_EDGE, 0.001)
	assert_eq(LightQuery.player_lit_radius(40.0), 0.0, "never negative")


# --- Players (co-op: every living player has a circle) ---

func test_every_living_player_lights_its_own_circle() -> void:
	var a := _player(Vector2(0, 0), 300.0)
	var b := _player(Vector2(1000, 0), 200.0)
	var tree := get_tree()
	assert_true(LightQuery.is_lit(tree, Vector2(200, 0)), "in player A's circle (225)")
	assert_false(LightQuery.is_lit(tree, Vector2(240, 0)), "outside A's lit part")
	assert_true(LightQuery.is_lit(tree, Vector2(1100, 0)), "in player B's circle (125)")
	assert_false(LightQuery.is_lit(tree, Vector2(500, 0)), "between the players")
	assert_false(LightQuery.is_lit(tree, Vector2(200, 0), false), "players can be left out (light run)")
	assert_eq(LightQuery.player_circles(tree).size(), 2)
	b.free()
	assert_false(LightQuery.is_lit(tree, Vector2(1100, 0)), "a player who is gone has no light")
	assert_eq(LightQuery.get_player_radius(a), 300.0, "the radius is state at the player")


func test_player_without_a_written_radius_uses_the_default() -> void:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.global_position = Vector2(0, 0)
	assert_eq(LightQuery.get_player_radius(player), LightQuery.DEFAULT_PLAYER_RADIUS)
	assert_true(LightQuery.is_lit(get_tree(), Vector2(0, LightQuery.DEFAULT_PLAYER_RADIUS - LightQuery.PLAYER_SOFT_EDGE - 1.0)))


# --- Light sources ---

func test_only_lights_that_count_are_light() -> void:
	var tree := get_tree()
	var effect := _light(Vector2(0, 0), 200.0, false)
	assert_false(LightQuery.is_lit(tree, Vector2(10, 0)), "flashes, projectiles and enemy glows do not count")
	effect.counts_as_light = true
	assert_true(LightQuery.is_lit(tree, Vector2(10, 0)), "switched on later")
	assert_true(LightQuery.is_lit(tree, Vector2(200.0 * LightSource.DEFAULT_LIT_SHARE - 1.0, 0)))
	assert_false(LightQuery.is_lit(tree, Vector2(200.0 * LightSource.DEFAULT_LIT_SHARE + 1.0, 0)), "the soft edge is dark")
	effect.visible = false
	assert_false(LightQuery.is_lit(tree, Vector2(10, 0)), "a light that is out lights nothing")
	effect.visible = true
	effect.counts_as_light = false
	assert_false(effect.is_in_group(LightSource.GAMEPLAY_GROUP))


func test_ground_offset_moves_the_lit_circle_under_the_flame() -> void:
	var light := _light(Vector2(0, -64), 100.0, true)
	light.ground_offset = Vector2(0, 64)
	assert_eq(light.get_lit_center(), Vector2.ZERO)
	assert_true(LightQuery.is_lit(get_tree(), Vector2(0, 70)), "lit below the stand's foot")
	assert_false(LightQuery.is_lit(get_tree(), Vector2(0, -150)), "not around the flame")


func test_light_islands_count_as_light() -> void:
	var island := LightIsland.create(IngredientSet.LightStyle.TORCH_STAND, Color.WHITE)
	add_child_autofree(island)
	island.global_position = Vector2(300, 300)
	assert_true(island.light.counts_as_light)
	assert_true(LightQuery.is_lit(get_tree(), Vector2(300, 340)), "next to the stand")
	assert_false(LightQuery.is_lit(get_tree(), Vector2(300, 300 + LightIsland.TORCH_RADIUS)), "outside its lit circle")


func test_flash_never_counts() -> void:
	LightSource.flash(self, Vector2(0, 0), 300.0, 0.2)
	await wait_process_frames(1)
	assert_false(LightQuery.is_lit(get_tree(), Vector2(10, 0)))

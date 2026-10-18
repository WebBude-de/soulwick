extends GutTest
## Height of a room as pure tile data (M3, HeightLayout, HeightRules): cliffs and surface from the
## plan markers, edges, levels, steps between levels (stairs for everyone, ladders for players only),
## the plan rules and the hit decision without a tree.

const GROUND := HeightLayout.Level.GROUND
const PLATEAU := HeightLayout.Level.PLATEAU
const BOTH := HeightLayout.Level.BOTH


## 9 x 8 floor; plateau in the north-east (columns 5-8, rows 0-2), its cliff row 2 with stairs at
## (6, 2) and a ladder at (8, 2).
func _layout(with_stairs := true, with_ladder := true) -> HeightLayout:
	var plateau: Array[Vector2i] = []
	for y in 3:
		for x in range(5, 9):
			plateau.append(Vector2i(x, y))
	var ladders: Array[Vector2i] = []
	var stairs: Array[Vector2i] = []
	if with_stairs:
		stairs.append(Vector2i(6, 2))
		plateau.erase(Vector2i(6, 2))
	if with_ladder:
		ladders.append(Vector2i(8, 2))
		plateau.erase(Vector2i(8, 2))
	var ground: Dictionary[Vector2i, bool] = {}
	for y in 8:
		for x in 9:
			ground[Vector2i(x, y)] = true
	return HeightLayout.build(plateau, ladders, stairs, ground)


func test_cliffs_surface_and_edges_follow_from_the_markers() -> void:
	var layout := _layout()
	assert_eq(layout.cliffs.keys().size(), 2, "the cliff row without stairs and ladder")
	assert_true(layout.cliffs.has(Vector2i(5, 2)) and layout.cliffs.has(Vector2i(7, 2)))
	assert_eq(layout.surface.size(), 8, "two rows of surface above the cliff")
	assert_false(layout.ground.has(Vector2i(6, 1)), "height tiles are no ground")
	assert_eq(layout.edge_sides.get(Vector2i(5, 0), 0), 8, "west edge of the plateau towards the ground")
	assert_eq(layout.edge_sides.get(Vector2i(5, 1), 0), 8)
	assert_false(layout.edge_sides.has(Vector2i(6, 1)), "above the stairs: no edge")
	assert_eq(layout.problems(), [] as Array[String])


func test_levels_of_tiles() -> void:
	var layout := _layout()
	assert_eq(layout.level_of(Vector2i(6, 0)), PLATEAU)
	assert_eq(layout.level_of(Vector2i(6, 2)), BOTH, "stairs belong to both levels")
	assert_eq(layout.level_of(Vector2i(8, 2)), BOTH, "so does the ladder")
	assert_eq(layout.level_of(Vector2i(5, 2)), GROUND, "only a body below can stand at a cliff")
	assert_eq(layout.level_of(Vector2i(2, 5)), GROUND)


func test_steps_between_levels() -> void:
	var layout := _layout()
	assert_false(layout.can_step(Vector2i(4, 1), Vector2i(5, 1)), "no step over the edge")
	assert_false(layout.can_step(Vector2i(5, 3), Vector2i(5, 2)), "no step onto a cliff")
	assert_true(layout.can_step(Vector2i(6, 3), Vector2i(6, 2)), "up the stairs")
	assert_true(layout.can_step(Vector2i(6, 2), Vector2i(6, 1)))
	assert_true(layout.can_step(Vector2i(8, 3), Vector2i(8, 2)), "players climb the ladder")
	assert_false(layout.can_step(Vector2i(8, 3), Vector2i(8, 2), true), "enemies never do")


func test_reachable_over_stairs_and_ladders_only() -> void:
	var open: Dictionary[Vector2i, bool] = {}
	for y in 8:
		for x in 9:
			open[Vector2i(x, y)] = true
	for tile: Vector2i in _layout().cliffs:
		open.erase(tile)
	var with_both := _layout()
	assert_true(HeightLayout.reachable(with_both, open, Vector2i(1, 6)).has(Vector2i(7, 0)), "up over the stairs")
	var ladder_only := _layout(false, true)
	var open_ladder := open.duplicate()
	open_ladder.erase(Vector2i(6, 2))
	assert_true(HeightLayout.reachable(ladder_only, open_ladder, Vector2i(1, 6)).has(Vector2i(7, 0)), "players: up the ladder")
	assert_false(HeightLayout.reachable(ladder_only, open_ladder, Vector2i(1, 6), true).has(Vector2i(7, 0)), "enemies: a ladder plateau is a safe island")


func test_plan_rules_catch_broken_height() -> void:
	var none := _layout(false, false)
	assert_string_contains(str(none.problems()), "neither stairs nor a ladder")
	var ground: Dictionary[Vector2i, bool] = {}
	for y in 6:
		for x in 6:
			ground[Vector2i(x, y)] = true
	var thin: Array[Vector2i] = [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)]
	var stairs: Array[Vector2i] = [Vector2i(2, 2)]
	thin.erase(Vector2i(2, 2))
	var sliver := HeightLayout.build(thin, [] as Array[Vector2i], stairs, ground)
	assert_string_contains(str(sliver.problems()), "no plateau surface above it", "a plateau needs two rows")
	var pits: Dictionary[Vector2i, bool] = {Vector2i(5, 3): true}
	assert_string_contains(str(_layout().problems(pits)), "right above an abyss", "no cliff over the abyss")


func test_melee_reaches_only_the_own_level() -> void:
	assert_true(HeightRules.melee_reaches(GROUND, GROUND))
	assert_true(HeightRules.melee_reaches(PLATEAU, PLATEAU))
	assert_false(HeightRules.melee_reaches(GROUND, PLATEAU))
	assert_true(HeightRules.melee_reaches(BOTH, PLATEAU), "from the stairs both ways")
	assert_true(HeightRules.melee_reaches(GROUND, BOTH))


func test_hits_without_height_are_never_blocked() -> void:
	var damage := DamageData.new()
	damage.tags.assign([&"melee"])
	assert_false(HeightRules.blocks_hit(damage, null), "no plateau room alive: nothing to block")
	assert_false(HeightRules.blocks_hit(null, null))

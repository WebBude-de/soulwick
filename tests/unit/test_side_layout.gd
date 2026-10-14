extends GutTest
## Side-segment plans (M5): four per biome, each mirrored, all following the plan rules (width,
## platforms, pits, ladder, coins, golden coin, enemies, spikes, start and door reachable with a
## 2.5-tile jump, no dead end, every item in reach); parsing, mirroring, the jump graph and the
## coordinates the segment uses.

const MINI := [
	"##########",
	"#........#",
	"#.....o..#",
	"#...==...#",
	"#S....H.D#",
	"####..H###",
	"####..####",
]


func test_every_biome_has_four_plans() -> void:
	for biome in [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]:
		var ids := SidePlans.ids_for(biome)
		assert_eq(ids.size(), 4, "four plans for %s" % biome)
		for id in ids:
			assert_eq(SidePlans.biome_of(id), biome)
			assert_false(SidePlans.get_rows(id).is_empty(), "%s has rows" % id)
	assert_eq(SidePlans.all_ids().size(), 16)


func test_every_plan_and_its_mirror_follows_the_rules() -> void:
	for id in SidePlans.all_ids():
		var layout := SidePlans.build(id)
		assert_eq(layout.check(), PackedStringArray(), "%s follows the rules" % id)
		assert_eq(layout.mirrored().check(), PackedStringArray(), "%s mirrored follows the rules" % id)


func test_plan_numbers_stay_in_the_ranges() -> void:
	for id in SidePlans.all_ids():
		var layout := SidePlans.build(id)
		assert_between(layout.size.x, 40, 60, "%s width" % id)
		assert_eq(layout.size.y, SideRules.ROWS, "%s height" % id)
		assert_between(layout.count_platforms(), 8, 14, "%s platforms" % id)
		assert_between(layout.count_pits(), 1, 2, "%s pits" % id)
		assert_between(layout.coins.size(), 6, 12, "%s coins" % id)
		assert_between(layout.slimes.size() + layout.skeletons.size(), 1, 3, "%s enemies" % id)
		assert_eq(layout.spikes.size(), 1, "%s spike trap" % id)
		assert_true(layout.golden_coin.x >= 0, "%s golden coin" % id)
		assert_false(layout.ladders.is_empty(), "%s ladder" % id)
		assert_gt(layout.door.x, layout.start.x, "%s runs to the right" % id)


func test_mirroring_swaps_start_and_door_side() -> void:
	var layout := SidePlans.build(&"crypt_steps")
	var mirrored := layout.mirrored()
	assert_true(mirrored.is_mirrored)
	assert_eq(mirrored.size, layout.size)
	assert_eq(mirrored.start, Vector2i(layout.size.x - 1 - layout.start.x, layout.start.y))
	assert_eq(mirrored.door, Vector2i(layout.size.x - 1 - layout.door.x, layout.door.y))
	assert_eq(mirrored.run_direction(), -1.0)
	assert_eq(layout.run_direction(), 1.0)
	assert_eq(mirrored.coins.size(), layout.coins.size())


func test_parse_finds_every_object() -> void:
	var layout := SideLayout.parse(PackedStringArray(MINI), &"mini")
	assert_eq(layout.start, Vector2i(1, 4))
	assert_eq(layout.door, Vector2i(8, 4))
	assert_eq(layout.coins, [Vector2i(6, 2)] as Array[Vector2i])
	assert_eq(layout.ladders[6], Vector2i(4, 5), "ladder column 6 from row 4 to 5")
	assert_true(layout.is_ledge(Vector2i(4, 3)))
	assert_true(layout.is_rock(Vector2i(0, 0)))
	assert_true(layout.is_rock(Vector2i(-1, 3)), "outside left is rock")
	assert_false(layout.is_blocking(Vector2i(4, 9)), "below the plan is open (pits fall out)")
	assert_eq(layout.pit_columns(), [4, 5] as Array[int])


func test_stand_cells_and_ladder_top() -> void:
	var layout := SideLayout.parse(PackedStringArray(MINI), &"mini")
	assert_true(layout.is_standable(Vector2i(1, 4)), "on the ground")
	assert_true(layout.is_standable(Vector2i(4, 2)), "on the ledge")
	assert_true(layout.is_ladder_top(Vector2i(6, 4)))
	assert_true(layout.is_standable(Vector2i(6, 3)), "on the ladder's top step")
	assert_false(layout.is_standable(Vector2i(4, 5)), "over the pit")


func test_jump_graph_reaches_the_door() -> void:
	var layout := SidePlans.build(&"crypt_steps")
	var path := layout.find_path(layout.start, layout.door)
	assert_gt(path.size(), 2)
	assert_eq(path[0], layout.start)
	assert_eq(path[-1], layout.door)
	for i in range(1, path.size()):
		assert_true(layout.neighbours(path[i - 1]).has(path[i]), "every step is an edge")


func test_jump_rules_follow_the_physics() -> void:
	var layout := SideLayout.parse(PackedStringArray([
		"##############",
		"#............#",
		"#............#",
		"#......=.....#",
		"#............#",
		"#..=.........#",
		"#S...........#",
		"##############",
	]), &"reach")
	var start := Vector2i(1, 6)
	assert_true(layout.neighbours(start).has(Vector2i(3, 4)), "two rows up, two columns over")
	assert_false(layout.neighbours(start).has(Vector2i(7, 2)), "four rows up is too high")
	assert_true(layout.neighbours(Vector2i(3, 4)).has(Vector2i(6, 6)), "a drop of two rows, three columns")
	assert_false(layout.neighbours(Vector2i(3, 4)).has(Vector2i(8, 6)), "five columns is too far")


func test_coordinates() -> void:
	assert_eq(SideLayout.feet_of(Vector2i(2, 3)), Vector2(2.5 * 64.0, 4 * 64.0))
	assert_eq(SideLayout.cell_at(Vector2(130, 200)), Vector2i(2, 3))
	var layout := SideLayout.parse(PackedStringArray(MINI), &"mini")
	var ladder := layout.ladder_rect(6)
	assert_eq(ladder, Rect2(6 * 64.0, 4 * 64.0, 64.0, 128.0))
	assert_eq(layout.ladder_rect_at(Vector2(6 * 64.0 + 30.0, 6 * 64.0)), ladder, "feet on the ground below")
	assert_eq(layout.ladder_rect_at(Vector2(6 * 64.0 + 30.0, 4 * 64.0)), ladder, "feet on the top step")
	assert_false(layout.ladder_rect_at(Vector2(5 * 64.0, 6 * 64.0)).has_area(), "next column")
	assert_almost_eq(layout.kill_y(), 7.75 * 64.0, 0.01)

extends GutTest
## Side-segment plans (M5): four per biome, each mirrored, all following the plan rules (width,
## platforms, pits, ladder, coins, golden coin, enemies, spikes, start and door reachable with a
## 2.5-tile jump, no dead end, every item in reach); parsing, mirroring, the jump graph and the
## coordinates the segment uses. Round 2: the double jump (golden coin in every plan, on the way in
## half of them), crumbling ledges in the other half. Round 3: six plans per biome, a turret mount in
## every plan (floor, ceiling or wall, away from start and door), pools that slow and shorten jumps,
## spike runs. D-144: a chest niche in every plan, off the way, a detour without the double jump.
## SV2 (D-195): four jump trial plans per biome on top (SideTrialPlans, tiers, up to 22 rows); their
## elements and rules: tests/unit/test_side_elements.gd.

const MINI := [
	"##########",
	"#........#",
	"#.....o..#",
	"#...==...#",
	"#S....H.D#",
	"####..H###",
	"####..####",
]


func test_every_biome_has_six_plans_and_four_jump_trials() -> void:
	for biome in [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]:
		var ids := SidePlans.ids_for(biome)
		assert_eq(ids.size(), 10, "six plans and four jump trials for %s" % biome)
		assert_eq((SidePlans.BIOME_PLANS[biome] as Array).size(), 6, "six plans of rounds 1-3")
		assert_eq((SideTrialPlans.BIOME_PLANS[biome] as Array).size(), 4, "four jump trial plans (SV2)")
		for id in ids:
			assert_eq(SidePlans.biome_of(id), biome)
			assert_false(SidePlans.get_rows(id).is_empty(), "%s has rows" % id)
	assert_eq(SidePlans.all_ids().size(), 40)


func test_every_plan_and_its_mirror_follows_the_rules() -> void:
	for id in SidePlans.all_ids():
		var layout := SidePlans.build(id)
		assert_eq(layout.check(), PackedStringArray(), "%s follows the rules" % id)
		assert_eq(layout.mirrored().check(), PackedStringArray(), "%s mirrored follows the rules" % id)


func test_plan_numbers_stay_in_the_ranges() -> void:
	for id in SidePlans.all_ids():
		var layout := SidePlans.build(id)
		var trial := SideTrialPlans.PLANS.has(id)
		assert_between(layout.size.x, 40, 60, "%s width" % id)
		if trial:
			assert_between(layout.size.y, SideRules.ROWS, SideRules.MAX_ROWS, "%s height" % id)
		else:
			assert_eq(layout.size.y, SideRules.ROWS, "%s height" % id)
		assert_between(layout.count_platforms(), 8, 14 + layout.size.y - SideRules.ROWS, "%s platforms" % id)
		assert_between(layout.count_pits(), 1, 2, "%s pits" % id)
		assert_between(layout.coins.size(), SideLayout.COIN_RANGE.x, SideLayout.COIN_RANGE.y, "%s coins" % id)
		assert_between(layout.enemy_cells().size(), 1, 3, "%s enemies" % id)
		assert_between(layout.spikes.size(), 0 if not layout.saws.is_empty() else 1, 3, "%s spike traps" % id)
		assert_between(layout.turrets.size(), 1, 2, "%s turret mounts" % id)
		assert_true(layout.golden_coin.x >= 0, "%s golden coin" % id)
		if not trial:
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
	assert_true(layout.neighbours(start, false).has(Vector2i(3, 4)), "two rows up, two columns over")
	assert_false(layout.neighbours(start, false).has(Vector2i(7, 2)), "four rows up is too high")
	assert_true(layout.neighbours(Vector2i(3, 4), false).has(Vector2i(6, 6)), "a drop of two rows, three columns")
	assert_false(layout.neighbours(Vector2i(3, 4), false).has(Vector2i(8, 6)), "five columns is too far")


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


func test_every_plan_has_a_chest_niche_off_the_way() -> void:
	for biome in [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]:
		assert_eq(SidePlans.chest_ids_for(biome), SidePlans.ids_for(biome), "every %s plan has a niche" % biome)
	for id in SidePlans.all_ids():
		for mirrored in [false, true]:
			var layout := SidePlans.build(id, mirrored)
			assert_true(layout.chest.x >= 0, "%s: chest niche" % id)
			assert_false(layout.way_cells().has(layout.chest), "%s: the chest stands off the way" % id)
			assert_false(layout.pit_columns().has(layout.chest.x), "%s: never over a pit" % id)
			var open_side := layout.is_standable(layout.chest + Vector2i.LEFT) or layout.is_standable(layout.chest + Vector2i.RIGHT)
			assert_true(open_side, "%s: an open stand cell beside the chest" % id)


func test_a_chest_on_the_way_or_none_breaks_the_rules() -> void:
	var rows := SidePlans.get_rows(&"crypt_shaft")
	# The old niche on the door floor: the way to the door walks over it.
	rows[5] = rows[5].substr(0, 38) + "C" + rows[5].substr(39)
	rows[8] = rows[8].substr(0, 4) + "#" + rows[8].substr(5)
	var errors := ",".join(SideLayout.parse(rows, &"on_way").check())
	assert_string_contains(errors, "stands on the way")
	rows[5] = rows[5].substr(0, 38) + "." + rows[5].substr(39)
	assert_string_contains(",".join(SideLayout.parse(rows, &"none").check()), "no chest niche")


func test_every_golden_coin_needs_the_double_jump() -> void:
	for id in SidePlans.all_ids():
		for mirrored in [false, true]:
			var layout := SidePlans.build(id, mirrored)
			var reach := layout.reachable_from(layout.start, true)
			var launch := layout.launch_cell_for(layout.golden_coin, reach)
			assert_true(launch.x >= 0, "%s: a launch spot under the golden coin" % id)
			assert_between(launch.y - layout.golden_coin.y, 3, SideLayout.ITEM_REACH_ROWS_DOUBLE,
					"%s: 3-4 rows above the launch spot (one jump is not enough)" % id)


func test_half_the_plans_need_the_double_jump_on_the_way_half_have_crumbling_ledges() -> void:
	var on_way := 0
	var crumbling := 0
	for biome in SidePlans.BIOME_PLANS:
		var biome_way := 0
		var biome_crumble := 0
		# The four plans of rounds 1-2 (round 3 added two per biome with pools and spike runs).
		for id in SidePlans.ids_for(biome).slice(0, 4):
			var layout := SidePlans.build(id)
			if layout.way_needs_double_jump():
				biome_way += 1
			if not layout.crumbles.is_empty():
				biome_crumble += 1
		assert_eq(biome_way, 2, "%s: two plans ask for the double jump on the way" % biome)
		assert_eq(biome_crumble, 2, "%s: two plans have a crumbling ledge" % biome)
		on_way += biome_way
		crumbling += biome_crumble
	assert_eq(on_way, 8)
	assert_eq(crumbling, 8)


func test_crumbling_ledges_parse_and_block() -> void:
	var layout := SideLayout.parse(PackedStringArray([
		"##########",
		"#........#",
		"#..~~~...#",
		"#S......D#",
		"##########",
	]), &"crumble")
	assert_eq(layout.crumbles, [Vector3i(3, 5, 2)] as Array[Vector3i])
	assert_true(layout.is_crumble(Vector2i(4, 2)))
	assert_true(layout.is_blocking(Vector2i(4, 2)), "stood on like a ledge")
	assert_false(layout.is_ledge(Vector2i(4, 2)), "not painted as a ledge tile")
	assert_true(layout.is_standable(Vector2i(4, 1)))


func test_double_jump_graph_reaches_higher_and_further() -> void:
	var layout := SideLayout.parse(PackedStringArray([
		"################",
		"#..............#",
		"#..............#",
		"#..=...........#",
		"#..............#",
		"#..............#",
		"#S.....#.......#",
		"################",
	]), &"double")
	var start := Vector2i(1, 6)
	var high := Vector2i(3, 2)
	assert_false(layout.neighbours(start, false).has(high), "four rows up: no single jump")
	assert_true(layout.neighbours(start, true).has(high), "but a double jump")
	assert_true(layout.needs_double_jump(start, high))
	var far := Vector2i(5, 6)
	assert_true(layout.neighbours(start, false).has(Vector2i(4, 6)), "walking")
	assert_false(layout.needs_double_jump(start, Vector2i(3, 6)))
	assert_eq(layout.find_path(start, high, false), [] as Array[Vector2i], "no way without the double jump")
	assert_false(layout.find_path(start, high, true).is_empty())
	assert_true(layout.neighbours(start, true).has(far))


# --- Round 3: turrets, pools, spike runs ---

func test_turret_mounts_sit_on_rock_away_from_start_and_door() -> void:
	var kinds := {}
	for id in SidePlans.all_ids():
		for mirrored in [false, true]:
			var layout := SidePlans.build(id, mirrored)
			for turret in layout.turrets:
				var normal := layout.turret_normal(turret)
				assert_ne(normal, Vector2i.ZERO, "%s: turret %s has a mount" % [id, turret])
				kinds[normal] = true
				assert_gte(absi(turret.x - layout.start.x), SideRules.TURRET_MIN_DISTANCE, "%s: not at the start" % id)
				assert_gte(absi(turret.x - layout.door.x), SideRules.TURRET_MIN_DISTANCE, "%s: not at the door" % id)
	assert_true(kinds.has(Vector2i.UP), "turrets standing on a floor")
	assert_true(kinds.has(Vector2i.DOWN), "turrets hanging from the ceiling")
	assert_true(kinds.has(Vector2i.LEFT) or kinds.has(Vector2i.RIGHT), "turrets on a wall")


func test_turret_normal_follows_the_rock() -> void:
	var layout := SideLayout.parse(PackedStringArray([
		"########",
		"#..T...#",
		"#....T##",
		"#.T....#",
		"########",
	]), &"mounts")
	assert_eq(layout.turrets.size(), 3)
	assert_eq(layout.turret_normal(Vector2i(3, 1)), Vector2i.DOWN, "hangs from the ceiling")
	assert_eq(layout.turret_normal(Vector2i(5, 2)), Vector2i.LEFT, "sits on the wall to its right")
	assert_eq(layout.turret_normal(Vector2i(2, 3)), Vector2i.UP, "stands on the floor")
	assert_eq(layout.turret_normal(Vector2i(2, 2)), Vector2i.ZERO, "free air has no mount")
	assert_true(layout.is_standable(Vector2i(2, 3)), "a floor turret does not block the way")


func test_round_three_plans_have_a_pool_and_a_spike_run() -> void:
	for biome in SidePlans.BIOME_PLANS:
		var ids := SidePlans.ids_for(biome)
		for id in ids.slice(4, 6):
			var layout := SidePlans.build(id)
			assert_eq(layout.pools.size(), 1, "%s: a pool" % id)
			assert_gte(layout.spikes.size(), 2, "%s: a spike run" % id)
			assert_eq(layout.turrets.size(), 2 if id != &"shadow_mire" else 1, "%s: turret mounts" % id)
			assert_eq(layout.check(), PackedStringArray(), "%s follows the rules" % id)


func test_pools_parse_slow_and_shorten_jumps() -> void:
	var layout := SideLayout.parse(PackedStringArray([
		"##############",
		"#............#",
		"#............#",
		"#S...........#",
		"####www#######",
		"##############",
	]), &"pool")
	assert_eq(layout.pools, [Vector3i(4, 6, 4)] as Array[Vector3i])
	assert_true(layout.is_pool(Vector2i(5, 4)))
	assert_false(layout.is_blocking(Vector2i(5, 4)), "water is no floor")
	assert_true(layout.is_standable(Vector2i(5, 4)), "the pool's bottom is")
	assert_true(layout.is_in_pool(SideLayout.feet_of(Vector2i(5, 4))))
	var water := Vector2i(6, 4)
	assert_true(layout.neighbours(water, false).has(Vector2i(7, 3)), "out of the pool, one column over")
	assert_false(layout.neighbours(water, false).has(Vector2i(9, 3)), "no long jump out of the water")
	assert_true(layout.neighbours(Vector2i(7, 3), false).has(Vector2i(10, 3)), "the same jump from dry ground")
	var floating := SideLayout.parse(PackedStringArray(["#########", "#S.www.D#", "#.......#"]), &"floating")
	var errors := ",".join(floating.check())
	assert_string_contains(errors, "without a floor")


func test_line_of_sight_stops_at_rock_not_at_ledges() -> void:
	var layout := SideLayout.parse(PackedStringArray([
		"##########",
		"#........#",
		"#...#....#",
		"#..===...#",
		"#........#",
		"##########",
	]), &"sight")
	var from := SideLayout.cell_center(Vector2i(1, 2))
	assert_false(layout.line_clear(from, SideLayout.cell_center(Vector2i(7, 2))), "the rock block")
	assert_true(layout.line_clear(SideLayout.cell_center(Vector2i(1, 1)), SideLayout.cell_center(Vector2i(7, 1))), "above it")
	assert_true(layout.line_clear(SideLayout.cell_center(Vector2i(2, 4)), SideLayout.cell_center(Vector2i(4, 2)) + Vector2(-60, 0)), "through a ledge")

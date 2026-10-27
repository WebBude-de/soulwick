extends GutTest
## Plans of the practice run (WK10, TutorialPlans): the hall keeps its rules (stations in order from
## west to east, the abyss one dash wide and across the hall, every marker reachable from the start
## with a dash over the abyss) and the side-view stretch needs the double jump but has no pit, no
## enemy and no spikes (practising never costs a heart). The built hall matches the plan.

const SAVE_PATH := "user://test_tutorial_plans_save.cfg"

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = SAVE_PATH


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func test_the_hall_follows_its_rules() -> void:
	var problems := TutorialPlans.check()
	assert_eq(problems, PackedStringArray(), "hall plan problems: %s" % "; ".join(problems))


func test_every_station_is_reachable_only_with_a_dash() -> void:
	var reach := TutorialPlans.reachable()
	assert_true(reach.has(TutorialPlans.find_one(TutorialPlans.GATE)), "the gate is reachable with a dash")
	var pits: Dictionary[Vector2i, bool] = {}
	for cell in TutorialPlans.find(TutorialPlans.PIT):
		pits[cell] = true
	var on_foot := RoomTiles.flood_fill(TutorialPlans.walkable(), pits, TutorialPlans.find_one(TutorialPlans.START), 0)
	assert_false(on_foot.has(TutorialPlans.sign_cell(2)), "station 3 lies behind the abyss: walking is not enough")
	assert_true(on_foot.has(TutorialPlans.sign_cell(1)), "station 2 is reachable on foot")


func test_check_finds_broken_plans() -> void:
	var rows: Array[String] = []
	rows.assign(TutorialPlans.HALL)
	rows[1] = rows[1].replace("2", ".")
	assert_false(TutorialPlans.check(rows).is_empty(), "a missing station sign is found")
	rows.assign(TutorialPlans.HALL)
	rows[3] = rows[3].replace("_", ".")
	assert_false(TutorialPlans.check(rows).is_empty(), "an abyss with a way round is found")


func test_the_side_stretch_needs_the_double_jump_and_has_no_pit() -> void:
	var problems := TutorialPlans.check_jump()
	assert_eq(problems, PackedStringArray(), "jump plan problems: %s" % "; ".join(problems))
	var layout := TutorialPlans.jump_layout()
	assert_eq(layout.biome_id, TutorialPlans.JUMP_BIOME)
	assert_eq(layout.count_pits(), 0, "no pit: a fall would cost a heart")
	for spot: Array in TutorialPlans.JUMP_HINTS:
		assert_true(int(spot[0]) > layout.start.x and int(spot[0]) < layout.door.x, "hint column %d lies on the way" % spot[0])


func test_the_ditch_is_cleared_with_momentum_or_walked_through() -> void:
	var layout := TutorialPlans.jump_layout()
	var ditch := TutorialPlans.JUMP_DITCH
	var before := Vector2i(ditch.x - 1, layout.start.y)
	var after := Vector2i(ditch.y + 1, layout.start.y)
	assert_true(layout.is_standable(before) and layout.is_standable(after), "ground on both sides of the ditch")
	assert_true(layout.is_standable(Vector2i(ditch.x, layout.start.y + 2)), "the ditch has a floor")
	assert_false(layout.find_path(before, after, true).is_empty(), "who falls short walks through and jumps out")


func test_the_built_hall_matches_the_plan() -> void:
	var area := TutorialArea.new()
	add_child_autofree(area)
	await wait_physics_frames(2)
	assert_eq(area.tiles.room_size, TutorialPlans.hall_size())
	assert_eq(area.dummies.size(), TutorialPlans.find(TutorialPlans.DUMMY).size(), "one straw dummy per 'd'")
	assert_true(area.shield_dummy.shielded)
	assert_eq(area.signs.size(), 4, "a sign per station")
	assert_eq(area.doors.size(), TutorialPlans.door_cells().size())
	for door in area.doors:
		assert_false(door.is_open, "every door is shut at the start")
	assert_false(area.jump_door.is_open)
	var pit_east := area.get_pit_east_x()
	var pit_west := area.get_pit_west_x()
	assert_almost_eq(pit_east - pit_west, RoomTiles.TILE_WORLD, 0.1, "the abyss is one tile wide")
	var probe := PitProbe.probe_for(area)
	var middle_y := area.get_pit_run_up_feet().y
	assert_true(probe.call(Vector2((pit_east + pit_west) * 0.5, middle_y)), "the abyss is on the pit layer (PlayerFall sees it)")
	assert_false(probe.call(area.get_start_feet()), "the start is solid ground")
	for zone in range(1, 5):
		assert_true(area.get_zone_start_x(zone) > area.get_zone_start_x(zone - 1), "zones run from west to east")

extends GutTest
## Jump trial (Sprungprobe, SV2, D-195): tiers by depth and danger, the plan characters of the
## elements and the SV4 enemies, the jump graph over them (rides, spring launches, the shaft climb;
## no dash jump since D-216), the plan rules (fair: no blind jump, lanterns in long plans, element kinds per
## tier), and the element nodes in a segment - moving platforms and saws on a seeded clock (the same
## on every machine), springs throw, tilting platforms and bridge pieces fall like crumbles, lanterns
## light up and are safe return spots. The bot plays every plan in dungeon/side/side_check.gd.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const STEP := 1.0 / 60.0

## Every element in one small plan: a sideways platform (track "-"), a lift (track "|"), a spring,
## a tilting platform, a bridge, a saw on an upright rail, a wide gap, a shaft and a lantern.
const ALL := [
	"##############################",
	"#............................#",
	"#..........*.................#",
	"#.........#*#................#",
	"#.........#*#..+.............#",
	"#.........#*#..X.............#",
	"#.........#*#..+....|........#",
	"#S.L..j...#*#.......V........#",
	"#####.#...###.MM---.#.......D#",
	"#####//.______......##.....###",
	"##########.........###.....###",
]

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_side_elements_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func after_each() -> void:
	HitStop.reset()
	await wait_process_frames(1)


func _segment(layout: SideLayout, rng_seed := 7) -> SideSegment:
	var segment := SideSegment.new()
	segment.setup(layout, 1, null, rng_seed)
	add_child_autofree(segment)
	segment.global_position = SideSegment.WORLD_ORIGIN
	return segment


# --- Tiers ---

func test_tier_follows_the_room_and_the_danger_level() -> void:
	assert_eq(SideRules.tier_for(1), 1)
	assert_eq(SideRules.tier_for(15), 1, "rooms 1-15")
	assert_eq(SideRules.tier_for(16), 2)
	assert_eq(SideRules.tier_for(45), 2, "rooms 16-45")
	assert_eq(SideRules.tier_for(46), 3, "from room 46")
	assert_eq(SideRules.tier_for(3, SideRules.TIER_3_FROM_DANGER), 3, "or from danger level 6")
	assert_eq(SideRules.tier_for(20, SideRules.TIER_3_FROM_DANGER - 1), 2)


func test_pick_takes_the_plans_of_the_tier_and_below_with_the_same_draws() -> void:
	for biome: StringName in [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]:
		for tier in [1, 2, 3]:
			for plan_id in SidePlans.ids_for(biome, tier):
				assert_lte(SidePlans.tier_of(plan_id), tier, "%s in tier %d" % [plan_id, tier])
		assert_gt(SidePlans.ids_for(biome, 3).size(), SidePlans.ids_for(biome, 1).size(), "%s: deeper, more plans" % biome)
	var a := SideRules.make_rng(11, 20)
	var b := SideRules.make_rng(11, 20)
	var easy := SidePlans.pick(&"crypt", a, false, 1)
	SidePlans.pick(&"crypt", b, false, 3)
	assert_eq(a.state, b.state, "the tier changes the pool, not the number of draws")
	assert_lte(easy.tier, 1)
	for run_seed in 60:
		var layout := SidePlans.pick(&"shadow_realm", SideRules.make_rng(run_seed, 9), true, 2)
		assert_lte(layout.tier, 2, "%s: tier 2 at most" % layout.plan_id)
		assert_gte(layout.chest.x, 0, "the ladder way keeps its chest")


func test_every_element_comes_alone_in_a_tier_one_plan_first() -> void:
	var alone: Dictionary[StringName, bool] = {}
	for plan_id: StringName in SideTrialPlans.PLANS:
		var layout := SidePlans.build(plan_id)
		var kinds := layout.element_kinds()
		assert_true(SideElementRules.tier_allows(layout.tier, kinds.size()), "%s: %d kinds in tier %d" % [plan_id, kinds.size(), layout.tier])
		if layout.tier == 1 and kinds.size() == 1:
			alone[kinds[0]] = true
	for kind in [SideElementRules.KIND_MOVER, SideElementRules.KIND_SPRING, SideElementRules.KIND_TILT,
			SideElementRules.KIND_SAW, SideElementRules.KIND_BRIDGE, SideElementRules.KIND_SHAFT]:
		assert_true(alone.has(kind), "%s alone in a tier-1 plan" % kind)
	for plan_id in SidePlans.BIOME_PLANS[&"crypt"]:
		assert_eq(SidePlans.tier_of(plan_id), 1, "the plans of rounds 1-3 are tier 1")


func test_jump_trials_are_taller_harder_and_have_lanterns() -> void:
	var tall := 0
	var tiers := {1: 0, 2: 0, 3: 0}
	for plan_id: StringName in SideTrialPlans.PLANS:
		var layout := SidePlans.build(plan_id)
		tiers[layout.tier] += 1
		if layout.size.y > SideRules.ROWS:
			tall += 1
			assert_false(layout.lanterns.is_empty(), "%s: a tall plan has a lantern" % plan_id)
		if layout.tier >= 2:
			assert_false(layout.lanterns.is_empty(), "%s: tier %d has a lantern" % [plan_id, layout.tier])
		assert_lte(layout.size.y, SideRules.MAX_ROWS)
	assert_gte(tall, 3, "plans up to 22 rows")
	assert_gt(tiers[2], 0)
	assert_gt(tiers[3], 0)


# --- Parsing and the jump graph ---

func test_parse_finds_every_element() -> void:
	var layout := SideLayout.parse(PackedStringArray(ALL), &"all")
	assert_eq(layout.movers.size(), 2)
	var sideways := layout.movers[1] if layout.movers[0].is_vertical() else layout.movers[0]
	var lift := layout.movers[0] if layout.movers[0].is_vertical() else layout.movers[1]
	assert_eq([sideways.first, sideways.last, sideways.row, sideways.low, sideways.high], [14, 15, 8, 0, 3])
	assert_eq([lift.first, lift.row, lift.low, lift.high], [20, 7, -1, 0], "the lift rides up its track")
	assert_eq(layout.springs, [Vector2i(6, 7)] as Array[Vector2i])
	assert_eq(layout.tilts, [Vector3i(5, 6, 9)] as Array[Vector3i])
	assert_eq(layout.bridges, [Vector3i(8, 13, 9)] as Array[Vector3i])
	assert_eq(layout.saws.size(), 1)
	assert_eq(layout.saws[0].axis, Vector2i.DOWN, "an upright rail")
	assert_eq([layout.saws[0].low, layout.saws[0].high], [-1, 1])
	assert_eq(layout.shafts, [Rect2i(11, 2, 1, 6)] as Array[Rect2i])
	assert_eq(layout.lanterns, [Vector2i(3, 7)] as Array[Vector2i])
	assert_true(layout.is_blocking(Vector2i(5, 9)), "a tilting platform is stood on")
	assert_true(layout.is_element_ground(Vector2i(9, 9)), "a bridge piece can fall away")
	assert_false(layout.is_blocking(Vector2i(14, 8)), "a moving platform is no static ground")
	assert_eq(layout.element_kinds().size(), 6)


func test_plan_characters_of_the_side_enemies() -> void:
	var layout := SideLayout.parse(PackedStringArray([
		"############",
		"#....b.....#",
		"#..........#",
		"#..........#",
		"#S.s.k.i.uD#",
		"############",
	]), &"enemies")
	var cells := layout.enemy_cells()
	assert_eq(cells.size(), 5)
	assert_eq(cells[0], Vector3i(3, 4, SideEnemy.Kind.SLIME), "slimes first (old seeds)")
	assert_eq(cells[1], Vector3i(5, 4, SideEnemy.Kind.SKELETON), "then skeletons")
	assert_eq(cells[2], Vector3i(5, 1, SideEnemy.Kind.BAT), "then the SV4 kinds in plan order")
	assert_eq(cells[3], Vector3i(7, 4, SideEnemy.Kind.SPIKE_HEDGEHOG))
	assert_eq(cells[4], Vector3i(9, 4, SideEnemy.Kind.SHIELD_BEARER))
	var errors := ",".join(layout.check())
	assert_string_contains(errors, "bat at (5, 1): its path crosses", "a bat needs air for its arc (SideEnemyChain.fits)")


func test_graph_rides_platforms_and_launches_from_springs() -> void:
	var layout := SideLayout.parse(PackedStringArray(ALL), &"all")
	var riding := layout.mover_stand_cells()
	assert_true(riding.has(Vector2i(14, 7)) and riding.has(Vector2i(18, 7)), "stand cells along the whole track")
	assert_true(layout.neighbours(Vector2i(14, 7), false).has(Vector2i(18, 7)), "a ride from one end to the other")
	assert_true(layout.neighbours(Vector2i(20, 5), false).has(Vector2i(20, 6)), "the lift goes up and down")
	assert_eq(layout.mover_of(Vector2i(16, 7)), riding[Vector2i(16, 7)])
	assert_eq(layout.mover_of(Vector2i(2, 7)), -1, "firm ground rides nothing")
	var spring_layout := SideLayout.parse(PackedStringArray([
		"##########",
		"#........#",
		"#....====#",
		"#........#",
		"#........#",
		"#..=.....#",
		"#........#",
		"#S.j.....#",
		"##########",
	]), &"spring")
	var spring := Vector2i(3, 7)
	assert_true(spring_layout.neighbours(spring, false).has(Vector2i(3, 4)), "four rows up from a spring")
	assert_true(spring_layout.needs_double_jump(spring, Vector2i(5, 1)), "six rows: the spring and the double jump")
	assert_false(spring_layout.neighbours(Vector2i(2, 7), true).has(Vector2i(5, 1)), "without the spring no way up there")


func test_graph_wide_gaps_need_the_double_jump_and_the_shaft_wall_jumps() -> void:
	var layout := SideLayout.parse(PackedStringArray(ALL), &"all")
	assert_false(layout.neighbours(Vector2i(21, 8), true).has(Vector2i(27, 8)), "five tiles: no jump reaches (no dash, D-216)")
	var gap := SideLayout.parse(PackedStringArray([
		"##########",
		"#........#",
		"#........#",
		"#S.....D.#",
		"###...####",
	]), &"gap")
	assert_false(gap.neighbours(Vector2i(2, 3), false).has(Vector2i(6, 3)), "three tiles of pit: no plain jump")
	assert_true(gap.needs_double_jump(Vector2i(2, 3), Vector2i(6, 3)), "the double jump (the old dash gaps)")
	assert_false("!" in SideTrialPlans.PLANS.values().reduce(func(all: String, rows: Array) -> String: return all + "".join(rows), ""), "no dash gap left in a plan")
	var shaft := SideLayout.parse(PackedStringArray([
		"##########",
		"#........#",
		"#........#",
		"#...#**###",
		"#...#**###",
		"#...#**###",
		"#...#**###",
		"#...#**###",
		"#S...**.D#",
		"##########",
	]), &"shaft")
	var bottom := Vector2i(5, 8)
	assert_eq(shaft.shafts, [Rect2i(5, 3, 2, 6)] as Array[Rect2i])
	assert_ne(shaft.shaft_climb(bottom, Vector2i(7, 2)), Rect2i(), "out over the wall's top by wall jumps")
	assert_true(shaft.neighbours(bottom, false).has(Vector2i(7, 2)))
	assert_false(shaft.neighbours(Vector2i(1, 8), true).has(Vector2i(7, 2)), "no jump gets up there")


# --- Plan rules ---

func test_plan_rules_catch_bad_elements() -> void:
	var errors := ",".join(SideLayout.parse(PackedStringArray([
		"##############################",
		"#............................#",
		"#............................#",
		"#.............M..............#",
		"#.....X......................#",
		"#S....../...............D....#",
		"#####.....###.......#.....####",
		"#####...###########.#.....####",
	]), &"bad").check())
	assert_string_contains(errors, "without a track")
	assert_string_contains(errors, "without a rail")
	assert_string_contains(errors, "is not 2 wide")
	assert_string_contains(errors, "element kinds do not fit tier 1")


func test_a_long_plan_needs_a_lantern_and_no_blind_jump() -> void:
	var rows := PackedStringArray()
	rows.append("##########")
	for i in 14:
		rows.append("#........#")
	rows.append("#S......D#")
	rows.append("##....####")
	rows.append("##....####")
	var layout := SideLayout.parse(rows, &"tall")
	assert_string_contains(",".join(layout.check()), "a long plan without a lantern")
	var drop := SideLayout.parse(PackedStringArray([
		"##########",
		"#S.......#",
		"####.....#",
		"#........#",
		"#........#",
		"#........#",
		"#........#",
		"#........#",
		"#........#",
		"#.....D..#",
		"##########",
	]), &"drop")
	assert_string_contains(",".join(drop.check()), "blind jump", "a drop of eight rows is blind")


func test_every_trial_plan_and_its_mirror_follows_the_rules() -> void:
	for plan_id: StringName in SideTrialPlans.PLANS:
		for mirrored in [false, true]:
			var layout := SidePlans.build(plan_id, mirrored)
			assert_eq(layout.check(), PackedStringArray(), "%s%s" % [plan_id, " mirrored" if mirrored else ""])


# --- Timing (the same on every machine) ---

func test_ping_pong_rests_at_both_ends_and_eases() -> void:
	var length := 256.0
	var speed := 100.0
	var pause := 0.5
	assert_eq(SideElementRules.ping_pong(0.2, length, speed, pause), 0.0, "rest at the start")
	assert_almost_eq(SideElementRules.ping_pong(pause + length / speed * 0.5, length, speed, pause), length * 0.5, 0.01)
	assert_eq(SideElementRules.ping_pong(pause + length / speed + 0.2, length, speed, pause), length, "rest at the end")
	var cycle := SideElementRules.period(length, speed, pause)
	assert_almost_eq(SideElementRules.ping_pong(1.3 + cycle, length, speed, pause, true), SideElementRules.ping_pong(1.3, length, speed, pause, true), 0.001)
	assert_eq(SideElementRules.phase_for(42, 1, cycle), SideElementRules.phase_for(42, 1, cycle), "phase from seed and index")
	assert_ne(SideElementRules.phase_for(42, 1, cycle), SideElementRules.phase_for(42, 2, cycle))


func test_platforms_and_saws_run_on_the_seeded_clock() -> void:
	var first := _segment(SidePlans.build(&"crypt_gauntlet"), 99)
	var second := _segment(SidePlans.build(&"crypt_gauntlet"), 99)
	var other := _segment(SidePlans.build(&"crypt_gauntlet"), 100)
	assert_eq(first.get_movers().size(), 1)
	assert_eq(first.get_saws().size(), 1)
	for time in [0.0, 1.7, 4.2]:
		first.apply_element_clock(time)
		second.apply_element_clock(time)
		assert_eq(first.get_movers()[0].position, second.get_movers()[0].position, "same seed, same place at %.1f s" % time)
		assert_eq(first.get_saws()[0].local_center_at(time), second.get_saws()[0].local_center_at(time))
	assert_ne(first.get_movers()[0].phase, other.get_movers()[0].phase, "another slot, another phase")
	first.apply_element_clock(3.0)
	assert_almost_eq(first.get_element_clock(), 3.0, 0.001, "the host's clock on a client")
	var mover := first.get_movers()[0]
	var plan := mover.mover
	for step in 40:
		var offset := mover.offset_tiles_at(step * 0.25)
		assert_between(offset, float(plan.low) - 0.01, float(plan.high) + 0.01, "the platform stays on its track")


func test_enemies_come_from_the_kinds_factory_with_the_old_draws() -> void:
	var segment := _segment(SidePlans.build(&"crypt_steps"), 7)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# _build_spikes draws first (one offset per run), then one draw per enemy.
	var layout := segment.layout
	var previous := Vector2i(-10, -10)
	for cell in layout.spikes:
		if cell != previous + Vector2i.RIGHT:
			rng.randf_range(0.4, SideSpikes.IDLE_TIME)
		previous = cell
	var enemies := segment.get_enemies()
	assert_eq(enemies.size(), layout.enemy_cells().size())
	for enemy in enemies:
		var expected := RandomNumberGenerator.new()
		expected.seed = rng.randi()
		assert_eq(enemy.get(&"_rng").seed, expected.seed, "one draw per enemy, as before SV2")
	var trial := _segment(SidePlans.build(&"shadow_leap"))
	var kinds := {}
	for enemy in trial.get_enemies():
		kinds[enemy.kind] = enemy
	assert_true(kinds.has(SideEnemy.Kind.BAT), "a bat from its plan character")
	assert_true(kinds[SideEnemy.Kind.BAT] is SideBat, "made by SideEnemyKinds")


# --- Element nodes ---

func test_spring_throws_four_and_a_half_tiles_up() -> void:
	assert_almost_eq(SideElementRules.spring_velocity(), sqrt(2.0 * SideRules.GRAVITY * 4.5 * SideRules.TILE), 0.01)
	var segment := _segment(SidePlans.build(&"crypt_springs"))
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.set_physics_process(false)
	segment.add_player(player)
	var spring := segment.get_springs()[0]
	player.global_position = spring.global_position - Player.FEET_OFFSET
	player.velocity = Vector2.ZERO
	watch_signals(spring)
	spring._physics_process(STEP)
	assert_signal_emitted(spring, "launched")
	assert_almost_eq(player.velocity.y, -SideElementRules.spring_velocity(), 0.01)
	assert_eq(spring.launches, 1)
	spring._physics_process(STEP)
	assert_eq(spring.launches, 1, "not twice at once")
	segment.remove_players()


func test_tilting_platform_and_bridge_fall_after_their_delays() -> void:
	var tilt := SideTilt.new()
	tilt.cells = 2
	add_child_autofree(tilt)
	tilt.touch()
	tilt.step(SideElementRules.TILT_DELAY - 0.05)
	assert_eq(tilt.state, SideCrumble.State.SHAKING)
	tilt.step(0.1)
	assert_eq(tilt.state, SideCrumble.State.FALLEN, "falls 0.4 s after the touch")
	tilt.step(SideElementRules.TILT_RESPAWN + 0.1)
	assert_eq(tilt.state, SideCrumble.State.SOLID, "and comes back")
	var bridge := SideBridge.new()
	add_child_autofree(bridge)
	bridge.touch()
	bridge.step(SideElementRules.BRIDGE_DELAY + 0.02)
	assert_eq(bridge.state, SideCrumble.State.FALLEN, "a bridge piece breaks right behind the runner")
	bridge.step(SideElementRules.BRIDGE_RESPAWN - 0.5, false)
	assert_eq(bridge.state, SideCrumble.State.FALLEN)
	var segment := _segment(SidePlans.build(&"crypt_gauntlet"))
	var pieces := 0
	for crumble in segment.get_crumbles():
		if crumble is SideBridge:
			pieces += 1
	assert_eq(pieces, 10, "one crumble per bridge piece (co-op sync by index)")


func test_lantern_lights_and_return_spots_avoid_the_elements() -> void:
	var segment := _segment(SidePlans.build(&"crypt_gauntlet"))
	var layout := segment.layout
	var lantern := segment.get_lanterns()[0]
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.set_physics_process(false)
	segment.add_player(player)
	assert_false(lantern.is_lit)
	player.global_position = lantern.global_position - Player.FEET_OFFSET
	lantern._physics_process(STEP)
	assert_true(lantern.is_lit, "lit by a player passing")
	assert_true(layout.is_safe_spot(layout.lanterns[0]), "a lantern is a return spot")
	var bridge := Vector2i(layout.bridges[0].x, layout.bridges[0].z - 1)
	assert_false(layout.is_safe_spot(bridge), "never on a bridge")
	assert_eq(segment.safe_feet_for(segment.to_global(SideLayout.feet_of(bridge))), Vector2.INF)
	var near_saw := layout.saws[0].cell + Vector2i(-1, 1)
	assert_false(layout.is_safe_spot(near_saw), "never next to a saw's rail")
	assert_true(layout.is_safe_spot(layout.start), "firm ground stays a return spot")
	segment.remove_players()


func test_segment_builds_the_elements_of_its_plan() -> void:
	for plan_id: StringName in SideTrialPlans.PLANS:
		var segment := _segment(SidePlans.build(plan_id))
		var layout := segment.layout
		assert_eq(segment.get_movers().size(), layout.movers.size(), "%s: platforms" % plan_id)
		assert_eq(segment.get_saws().size(), layout.saws.size(), "%s: saws" % plan_id)
		assert_eq(segment.get_springs().size(), layout.springs.size(), "%s: springs" % plan_id)
		assert_eq(segment.get_lanterns().size(), layout.lanterns.size(), "%s: lanterns" % plan_id)
		assert_eq(segment.get_enemies().size(), layout.enemy_cells().size(), "%s: enemies" % plan_id)
		var hints := segment.get_node_or_null("ElementHints")
		assert_eq(hints != null, not layout.shafts.is_empty(), "%s: hints" % plan_id)

extends GutTest
## The obstacle run (Hindernislauf, D-216): four runs per biome composed of checked pieces (opening,
## two-way piece, hard part) with lanterns at the seams, one golden coin, one chest niche, thinned
## coins and every run rule plain and mirrored; the pieces keep no boost fields and no enemy chains;
## a run as a world builds its slopes, ends at the door (no finish arch, no rush node) and sets the
## body up for the slopes until the player leaves; a player runs over a hill without a jump and
## keeps the momentum, a ramp throws them up. The bot plays every run: dungeon/side/side_check.gd.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const BIOMES: Array[StringName] = [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]
const HILL_PLAN := [
	"##########################",
	"#........................#",
	"#........................#",
	"#........................#",
	"#........................#",
	"#..........(####)........#",
	"#.S.......(######)....D..#",
	"##########################",
]
const RAMP_PLAN := [
	"##############################",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#.S...............(..........#",
	"###################...########",
	"###################...########",
	"##############################",
]

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_side_obstacle_run_save.cfg"


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	SaveManager.save_path = _old_save_path


func after_each() -> void:
	HitStop.reset()
	await wait_process_frames(1)


func _segment(layout: SideLayout) -> SideSegment:
	var segment := SideSegment.new()
	segment.setup(layout, 1, null, 11)
	add_child_autofree(segment)
	segment.global_position = SideSegment.WORLD_ORIGIN
	return segment


func _plan(rows: Array) -> SideLayout:
	var layout := SideLayout.parse(PackedStringArray(rows), &"test_slopes")
	layout.biome_id = &"crypt"
	return layout


func _player(segment: SideSegment) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.is_local = false
	add_child_autofree(player)
	segment.add_player(player)
	return player


## Drives player to the right (jump never pressed).
func _run_right(player: Player) -> void:
	player.side_motion.input_source = func() -> PlayerSideMotion.SideInput:
		var input := PlayerSideMotion.SideInput.new()
		input.axis = Vector2(1, 0)
		return input


# --- Runs ---

func test_four_runs_per_biome_with_a_tier_each() -> void:
	for biome in BIOMES:
		var ids := ObstacleRunPlans.ids_for(biome)
		assert_eq(ids.size(), 4, "%s: four runs" % biome)
		for run_id in ids:
			assert_eq(ObstacleRunPlans.biome_of(run_id), biome)
			var pieces := ObstacleRunPlans.pieces_of(run_id)
			assert_eq(pieces.size(), 3, "%s: opening, two ways, hard part" % run_id)
			assert_true(SidePlans.PLANS.has(pieces[ObstacleRunPlans.PIECE_OPENING]), "%s: an opening of rounds 1-3" % run_id)
			assert_true(SideTwoWayPlans.has_plan(pieces[ObstacleRunPlans.PIECE_TWO_WAY]), "%s: a two-way piece" % run_id)
			assert_true(SideTrialPlans.PLANS.has(pieces[ObstacleRunPlans.PIECE_HARD]), "%s: a jump trial as the hard part" % run_id)
			assert_eq(ObstacleRunPlans.tier_of(run_id), SidePlans.tier_of(pieces[ObstacleRunPlans.PIECE_HARD]), "%s: the hard part's tier" % run_id)
	assert_eq(ObstacleRunPlans.all_ids().size(), 16)
	assert_eq(ObstacleRunPlans.ids_for(&"unknown"), ObstacleRunPlans.ids_for(&"crypt"), "unknown biomes take the crypt's")


func test_every_run_keeps_the_rules_plain_and_mirrored() -> void:
	for run_id in ObstacleRunPlans.all_ids():
		for mirrored in [false, true]:
			var layout := ObstacleRunPlans.build(run_id, mirrored)
			assert_true(layout.is_obstacle_run())
			assert_eq(layout.check(), PackedStringArray(), "%s%s" % [run_id, " (mirrored)" if mirrored else ""])


func test_compose_puts_lanterns_on_the_seams_and_keeps_one_of_each() -> void:
	var run_id := &"grotto_run_climb"
	var layout := ObstacleRunPlans.build(run_id)
	var pieces := ObstacleRunPlans.pieces_of(run_id)
	var width := 0
	for piece in pieces:
		width += SideTwoWayPlans.get_rows(piece)[0].length() if SideTwoWayPlans.has_plan(piece) else SidePlans.get_rows(piece)[0].length()
	assert_eq(layout.size.x, width - 2 * (pieces.size() - 1), "the walls between the pieces go")
	var piece_lanterns := 0
	for piece in pieces:
		if not SideTwoWayPlans.has_plan(piece):
			piece_lanterns += SidePlans.build(piece).lanterns.size()
	assert_eq(layout.lanterns.size(), piece_lanterns + pieces.size() - 1, "a lantern where each later piece starts")
	assert_eq("".join(layout.rows).count(SideLayout.START), 1, "one start")
	assert_eq("".join(layout.rows).count(SideLayout.DOOR), 1, "one door")
	assert_eq("".join(layout.rows).count(SideLayout.GOLDEN_COIN), 1, "one golden coin (the hard part's)")
	assert_eq("".join(layout.rows).count(SideLayout.CHEST), 1, "one chest niche (the opening's)")
	assert_lt(layout.chest.x, SidePlans.get_rows(pieces[0])[0].length(), "in the opening")
	assert_gt(layout.golden_coin.x, layout.size.x - SidePlans.get_rows(pieces[2])[0].length(), "in the hard part")
	assert_eq(layout.run_direction(), 1.0)
	var mirrored := ObstacleRunPlans.build(run_id, true)
	assert_eq(mirrored.run_direction(), -1.0, "mirrored runs to the left")
	assert_eq(mirrored.pieces, layout.pieces, "and keeps its pieces")


func test_a_run_pays_about_a_combat_room() -> void:
	for run_id in ObstacleRunPlans.all_ids():
		var layout := ObstacleRunPlans.build(run_id)
		var piece_coins := 0
		for piece in layout.pieces:
			var rows := SideTwoWayPlans.get_rows(piece) if SideTwoWayPlans.has_plan(piece) else SidePlans.get_rows(piece)
			piece_coins += "".join(rows).count(SideLayout.COIN) + "".join(rows).count(SideLayout.GOLDEN_COIN)
		piece_coins -= 1
		assert_eq(layout.coins.size(), ceili(piece_coins / float(SideRules.RUN_COIN_KEEP_EVERY)), "%s: every third coin" % run_id)
		assert_between(layout.coins.size(), ObstacleRunPlans.COIN_RANGE.x, ObstacleRunPlans.COIN_RANGE.y)


func test_pick_draws_a_run_of_the_tier_the_same_on_every_machine() -> void:
	for run_seed in 30:
		var layout := ObstacleRunPlans.pick(&"ember_forge", SideRules.make_rng(run_seed, 5), 3)
		assert_true(layout.is_obstacle_run())
		assert_gte(layout.tier, 2, "tier 3 draws tiers 2 and 3")
		assert_eq(layout.biome_id, &"ember_forge")
		var again := ObstacleRunPlans.pick(&"ember_forge", SideRules.make_rng(run_seed, 5), 3)
		assert_eq(again.plan_id, layout.plan_id)
		assert_eq(again.is_mirrored, layout.is_mirrored)
		assert_eq(again.turrets_enabled, layout.turrets_enabled)
	for run_seed in 30:
		assert_eq(ObstacleRunPlans.pick(&"crypt", SideRules.make_rng(run_seed, 5), 1).tier, 1, "tier 1 draws tier 1")


func test_two_way_pieces_have_no_boost_fields_and_no_enemy_chains() -> void:
	for biome in BIOMES:
		for piece in SideTwoWayPlans.ids_for(biome):
			var layout := SideLayout.parse(SideTwoWayPlans.get_rows(piece), piece)
			assert_false("".join(layout.rows).contains("B"), "%s: no boost field (D-216)" % piece)
			assert_gte(layout.slopes.size(), 4, "%s: slopes" % piece)
			assert_gte(SideSlopes.ramps_of(layout).size(), 1, "%s: a ramp" % piece)
			for row in layout.size.y:
				var columns: Array[int] = []
				for enemy in layout.enemy_cells():
					if enemy.y == row and not SideEnemyKinds.char_for(enemy.z as SideEnemy.Kind) in ["i", "u"]:
						columns.append(enemy.x)
				columns.sort()
				for k in range(1, columns.size()):
					assert_gt(columns[k] - columns[k - 1], 4, "%s: single enemies, no chain (row %d)" % [piece, row])


# --- A run as a world ---

func test_a_run_builds_its_slopes_and_ends_at_the_door() -> void:
	var segment := _segment(ObstacleRunPlans.build(&"crypt_run_lift"))
	var layout := segment.layout
	var slopes := segment.get_node("Slopes") as SideSlopes
	assert_eq(slopes.get_body().get_child_count(), layout.slopes.size(), "a collision polygon per slope cell")
	assert_null(segment.get_node_or_null("Rush"), "no rush node any more")
	assert_eq(segment.get_lanterns().size(), layout.lanterns.size())
	assert_eq(segment.get_enemies().size(), layout.enemy_cells().size())
	var player := _player(segment)
	var angle := player.floor_max_angle
	assert_almost_eq(rad_to_deg(angle), SideSlopes.FLOOR_MAX_ANGLE_DEGREES, 0.01, "slopes count as floor")
	assert_true(player.floor_constant_speed)
	assert_false(segment.is_at_door(player))
	player.side_motion.place_at(segment.get_door_feet())
	await wait_physics_frames(3)
	assert_true(segment.is_at_door(player))
	assert_true(segment.is_finished, "alone the door ends the run")
	segment.remove_players()
	assert_false(player.floor_constant_speed, "the body as before")
	var piece := _segment(SidePlans.build(&"crypt_steps"))
	assert_null(piece.get_node_or_null("Slopes"), "no slopes, no slope node")


func test_running_over_a_hill_without_a_jump_keeps_the_momentum() -> void:
	var segment := _segment(_plan(HILL_PLAN))
	var player := _player(segment)
	_run_right(player)
	var top := INF
	var stuck := 0
	var last_x := player.global_position.x
	for frame in 150:
		await wait_physics_frames(1)
		top = minf(top, segment.to_local(player.get_feet_position()).y)
		if absf(player.global_position.x - last_x) < 0.1 and frame > 5:
			stuck += 1
		last_x = player.global_position.x
		if segment.to_local(player.get_feet_position()).x > 19.5 * SideRules.TILE:
			break
	var feet := segment.to_local(player.get_feet_position())
	assert_gt(feet.x, 19.0 * SideRules.TILE, "over the hill (%s)" % feet)
	assert_lt(top, 5.2 * SideRules.TILE, "up on the hill's top (%.0f)" % top)
	assert_eq(stuck, 0, "never stuck at a slope")
	assert_eq(player.side_motion.pit_falls, 0)
	assert_true(player.side_motion.momentum.has_momentum(), "the slopes keep the momentum (%.2f×)" % player.side_motion.get_speed_factor())
	segment.remove_players()


func test_a_ramp_throws_the_runner_up() -> void:
	var segment := _segment(_plan(RAMP_PLAN))
	var player := _player(segment)
	player.side_motion.place_at(segment.to_global(SideLayout.feet_of(Vector2i(10, 5))))
	_run_right(player)
	var launched := false
	for frame in 300:
		await wait_physics_frames(1)
		var feet := segment.to_local(player.get_feet_position())
		if feet.x > 19.0 * SideRules.TILE and player.velocity.y < -60.0 and not player.side_motion.is_on_floor():
			launched = true
			break
	assert_true(launched, "up into the air off the ramp without a jump (%s, %.2f×)" % [
			segment.to_local(player.get_feet_position()), player.side_motion.get_speed_factor()])
	assert_eq(player.side_motion.ramp_launches, 1, "one throw, counted at the player")
	segment.remove_players()

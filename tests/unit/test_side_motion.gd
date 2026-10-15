extends GutTest
## Side-view motion of the real player (M5) in a small segment, stepped by hand with the real body
## physics: standing, a 2.5-tile jump, variable height, coyote time, jump buffer, the horizontal
## dash, ladders up and down, a pit (an abyss's damage past the shield, back on the last platform,
## may kill), coins, the door, the co-op catch-up, the body animations and leaving the side view
## (shape and motion mode restored). Round 2: double jump, apex hang, wall slide and wall jump,
## crumbling ledges, squash/stretch, salto and the camera kick. The autopilot crosses the segment.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const STEP := 1.0 / 60.0
const PLAN := [
	"####################",
	"#..................#",
	"#..................#",
	"#..................#",
	"#..................#",
	"#.....H=====.......#",
	"#.....H............#",
	"#S....H.........oD.#",
	"##########...#######",
]

var _old_save_path: String
var _input := PlayerSideMotion.SideInput.new()
var _segment: SideSegment = null


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_side_motion_save.cfg"


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	_input = PlayerSideMotion.SideInput.new()


func after_each() -> void:
	HitStop.reset()
	await wait_process_frames(1)


func _layout() -> SideLayout:
	var layout := SideLayout.parse(PackedStringArray(PLAN), &"test")
	layout.biome_id = &"crypt"
	return layout


## A segment with one player (or two), physics ready, stepped by hand.
func _setup(players := 1, plan: Array = PLAN) -> Array[Player]:
	_segment = SideSegment.new()
	var layout := SideLayout.parse(PackedStringArray(plan), &"test")
	layout.biome_id = &"crypt"
	_segment.setup(layout, 1, null, 42)
	add_child_autofree(_segment)
	_segment.global_position = Vector2(0, 5000)
	_segment.set_physics_process(false)
	var result: Array[Player] = []
	for i in players:
		var player := PLAYER_SCENE.instantiate() as Player
		add_child_autofree(player)
		player.set_physics_process(false)
		_segment.add_player(player)
		player.side_motion.input_source = func() -> PlayerSideMotion.SideInput: return _take_input()
		result.append(player)
	await wait_physics_frames(3)
	return result


func _take_input() -> PlayerSideMotion.SideInput:
	var input := _input
	var next := PlayerSideMotion.SideInput.new()
	next.axis = input.axis
	next.jump_pressed = input.jump_pressed
	_input = next
	return input


func _press(axis := Vector2.ZERO, jump_just := false, jump_held := false, dash := false) -> void:
	_input.axis = axis
	_input.jump_just_pressed = jump_just
	_input.jump_pressed = jump_held or jump_just
	_input.dash_just_pressed = dash


func _run(players: Array[Player], frames: int) -> void:
	for i in frames:
		for player in players:
			player._physics_process(STEP)
		_segment._physics_process(STEP)


func _feet_local(player: Player) -> Vector2:
	return _segment.to_local(player.get_feet_position())


func test_enter_and_exit_switch_body_and_motion() -> void:
	var players := await _setup()
	var player := players[0]
	assert_true(player.is_side_view())
	assert_true((player.get_node("CollisionShape2D") as CollisionShape2D).shape is RectangleShape2D)
	assert_eq(player.motion_mode, CharacterBody2D.MOTION_MODE_GROUNDED)
	assert_eq(_feet_local(player), SideLayout.feet_of(Vector2i(1, 7)), "feet on the start")
	_segment.remove_players()
	assert_false(player.is_side_view())
	assert_true((player.get_node("CollisionShape2D") as CollisionShape2D).shape is CircleShape2D, "the round body is back")
	assert_eq(player.motion_mode, CharacterBody2D.MOTION_MODE_FLOATING)


func test_stands_on_the_ground() -> void:
	var player := (await _setup())[0]
	_run([player], 30)
	assert_true(player.side_motion.is_on_floor())
	assert_almost_eq(_feet_local(player).y, 8 * 64.0, 1.5, "feet on the ground line")


func test_full_jump_is_two_and_a_half_tiles() -> void:
	var player := (await _setup())[0]
	_run([player], 10)
	var ground := _feet_local(player).y
	_press(Vector2.ZERO, true, true)
	var top := ground
	for i in 60:
		_run([player], 1)
		top = minf(top, _feet_local(player).y)
	assert_almost_eq(ground - top, 2.5 * 64.0, 10.0, "rise of a held jump")
	assert_true(player.side_motion.is_on_floor(), "back on the ground")


func test_short_press_jumps_lower() -> void:
	var player := (await _setup())[0]
	_run([player], 10)
	var ground := _feet_local(player).y
	_press(Vector2.ZERO, true, true)
	_run([player], 2)
	_press()
	var top := ground
	for i in 60:
		_run([player], 1)
		top = minf(top, _feet_local(player).y)
	assert_lt(ground - top, 0.6 * 2.5 * 64.0, "letting go cuts the jump")


func test_coyote_time_and_its_end() -> void:
	var player := (await _setup())[0]
	# On the ledge (row 5, columns 7-11), walk off its right end.
	player.side_motion.place_at(_segment.to_global(SideLayout.feet_of(Vector2i(11, 4))))
	_run([player], 5)
	_press(Vector2.RIGHT)
	var frames := 0
	while player.side_motion.is_on_floor() and frames < 60:
		_run([player], 1)
		frames += 1
	assert_false(player.side_motion.is_on_floor(), "walked off")
	_run([player], 3)
	_press(Vector2.RIGHT, true, true)
	_run([player], 1)
	assert_lt(player.velocity.y, -500.0, "a jump 0.05 s after leaving the edge still works")
	assert_false(player.side_motion.has_double_jumped, "that was the ground jump (coyote), not the air jump")
	# Second case: too late.
	player.side_motion.place_at(_segment.to_global(SideLayout.feet_of(Vector2i(11, 4))))
	_press()
	_run([player], 10)
	_press(Vector2.RIGHT)
	frames = 0
	while player.side_motion.is_on_floor() and frames < 60:
		_run([player], 1)
		frames += 1
	_run([player], 9)
	_press(Vector2.RIGHT, true, true)
	_run([player], 1)
	assert_true(player.side_motion.has_double_jumped, "0.15 s after the edge: no ground jump, the air jump")
	assert_almost_eq(player.velocity.y, -SideRules.DOUBLE_JUMP_VELOCITY, 1.0)


func test_jump_buffer_jumps_on_landing() -> void:
	var player := (await _setup())[0]
	_run([player], 10)
	_press(Vector2.ZERO, true, true)
	_run([player], 1)
	_press()
	# Fall until just above the ground, press jump a few frames early.
	var ground := 8 * 64.0
	var frames := 0
	while frames < 120:
		_run([player], 1)
		frames += 1
		if player.velocity.y > 0.0 and ground - _feet_local(player).y < 28.0:
			break
	_press(Vector2.ZERO, true, true)
	_run([player], 1)
	_press(Vector2.ZERO, false, true)
	var jumped := false
	for i in 12:
		_run([player], 1)
		if player.velocity.y < -500.0:
			jumped = true
			break
	assert_true(jumped, "the early press jumps when the feet touch the ground")


func test_dash_is_horizontal() -> void:
	var player := (await _setup())[0]
	_run([player], 10)
	var y := _feet_local(player).y
	var x := _feet_local(player).x
	_press(Vector2.ZERO, false, false, true)
	_run([player], 1)
	assert_true(player.is_dashing())
	assert_almost_eq(player.velocity.y, 0.0, 0.01)
	_press()
	_run([player], 10)
	assert_gt(_feet_local(player).x - x, 60.0, "dashed in the facing direction (right)")
	assert_almost_eq(_feet_local(player).y, y, 2.0)


func test_ladder_up_and_down() -> void:
	var player := (await _setup())[0]
	player.side_motion.place_at(_segment.to_global(SideLayout.feet_of(Vector2i(6, 7))))
	_run([player], 5)
	_press(Vector2.UP)
	_run([player], 2)
	assert_true(player.side_motion.is_climbing(), "up on the ladder")
	_run([player], 120)
	assert_false(player.side_motion.is_climbing(), "off at the top")
	assert_almost_eq(_feet_local(player).y, 5 * 64.0, 2.0, "standing on the top step")
	_press()
	_run([player], 10)
	assert_almost_eq(_feet_local(player).y, 5 * 64.0, 2.0, "the top step holds")
	_press(Vector2.DOWN)
	_run([player], 2)
	assert_true(player.side_motion.is_climbing(), "down through the top step")
	_run([player], 120)
	assert_almost_eq(_feet_local(player).y, 8 * 64.0, 2.0, "at the bottom")


func test_pit_costs_an_abyss_heart_past_the_shield_and_returns() -> void:
	var player := (await _setup())[0]
	player.shield.add_shield(3.0)
	var hp := player.health.get_health()
	var shield := player.shield.get_shield()
	player.side_motion.place_at(_segment.to_global(SideLayout.feet_of(Vector2i(9, 7))))
	_run([player], 10)
	var safe := player.side_motion.get_safe_feet()
	assert_ne(safe, Vector2.INF)
	_press(Vector2.RIGHT)
	var frames := 0
	while not player.side_motion.is_in_pit() and frames < 200:
		_run([player], 1)
		frames += 1
	assert_true(player.side_motion.is_in_pit(), "fell out of the segment")
	assert_true(player.is_input_locked())
	_press()
	_run([player], ceili(SideRules.PIT_RETURN_TIME / STEP) + 1)
	assert_false(player.side_motion.is_in_pit())
	assert_eq(player.health.get_health(), hp - ChasmRules.fall_damage(), "a whole heart like an abyss")
	assert_eq(player.shield.get_shield(), shield, "past the shield")
	assert_true(player.hurtbox.is_invulnerable(), "briefly invulnerable")
	assert_almost_eq(player.get_feet_position().distance_to(safe), 0.0, 1.0, "back on the last platform")
	assert_eq(player.side_motion.pit_falls, 1)


func test_pit_can_kill_like_an_abyss() -> void:
	var player := (await _setup())[0]
	player.health.take_damage(player.health.get_health() - 1.0)
	player.side_motion.start_pit()
	_run([player], ceili(SideRules.PIT_RETURN_TIME / STEP) + 1)
	assert_false(player.is_alive(), "the last heart goes in the pit (D-115)")


func test_coin_pays_run_gold_and_the_door_finishes() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()
	var player := (await _setup())[0]
	watch_signals(_segment)
	player.side_motion.place_at(_segment.to_global(SideLayout.feet_of(Vector2i(15, 7))))
	_press(Vector2.RIGHT)
	var frames := 0
	while not _segment.is_finished and frames < 200:
		_run([player], 1)
		frames += 1
	assert_eq(_segment.coins_taken, 1)
	assert_eq(RunManager.get_run_gold(), SideRules.coin_gold(1, MetaProgression.get_gold_multiplier()))
	assert_true(_segment.is_finished, "walked through the door")
	assert_signal_emitted(_segment, "finished")
	RunManager.end_run(RunManager.EndReason.ABORT)


func test_coop_straggler_is_brought_to_the_foremost_player() -> void:
	var players := await _setup(2)
	var leader := players[0]
	var straggler := players[1]
	leader.side_motion.place_at(_segment.to_global(SideLayout.feet_of(Vector2i(16, 7))))
	straggler.side_motion.place_at(_segment.to_global(SideLayout.feet_of(Vector2i(1, 7))))
	_run(players, 5)
	# The view is the camera's; here a narrow one around the leader.
	var view := Rect2(leader.global_position - Vector2(200, 200), Vector2(400, 400))
	for i in ceili(SideRules.CATCH_UP_TIME / STEP) + 2:
		_segment._update_catch_up(straggler, view, STEP)
	assert_lt(straggler.global_position.distance_to(leader.global_position), 80.0, "brought forward")
	assert_eq(straggler.side_motion.outside_time, 0.0)
	assert_eq(_segment.get_foremost_player(), leader)


func test_body_animations() -> void:
	var player := (await _setup())[0]
	var sprite := player.get_node("Sprite") as AnimatedSprite2D
	for animation in [PlayerSideArt.JUMP, PlayerSideArt.LAND, PlayerSideArt.FALL, PlayerSideArt.CLIMB]:
		assert_true(sprite.sprite_frames.has_animation(animation), "%s added" % animation)
	var data := sprite.get_meta(CharacterData.META_DATA, null) as CharacterData
	if data != null:
		assert_not_null(data.get_mask(PlayerSideArt.JUMP), "jump keeps the clothing colour")
	_run([player], 5)
	assert_eq(player.side_motion.get_animation(Vector2.ZERO), &"idle")
	_press(Vector2.ZERO, true, true)
	_run([player], 3)
	assert_eq(player.side_motion.get_animation(Vector2.ZERO), PlayerSideArt.JUMP)
	_press()
	var saw_fall := false
	var saw_land := false
	for i in 90:
		_run([player], 1)
		var animation := player.side_motion.get_animation(Vector2.ZERO)
		saw_fall = saw_fall or animation == PlayerSideArt.FALL
		saw_land = saw_land or animation == PlayerSideArt.LAND
	assert_true(saw_fall, "fall frame on the way down")
	assert_true(saw_land, "landing frame")


func test_top_down_player_has_no_side_motion() -> void:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	assert_null(player.side_motion)
	assert_false(player.is_side_view())
	assert_true(player.try_dash(Vector2.LEFT))
	assert_false(player.try_dash(Vector2.LEFT), "cooldown")


func test_bot_crosses_the_segment() -> void:
	var player := (await _setup())[0]
	player.hurtbox.set_invulnerable(&"test", true)
	var bot := SideBot.drive(_segment, player)
	var frames := 0
	while not _segment.is_finished and frames < 60 * 30:
		_run([player], 1)
		frames += 1
	assert_true(_segment.is_finished, "the autopilot reached the door (%d frames, %d jumps)" % [frames, bot.jumps])
	assert_eq(player.side_motion.pit_falls, 0)


func test_double_jump_once_per_air_time() -> void:
	var player := (await _setup())[0]
	var motion := player.side_motion
	_run([player], 10)
	var ground := _feet_local(player).y
	_press(Vector2.ZERO, true, true)
	_run([player], 1)
	_press(Vector2.ZERO, false, true)
	while player.velocity.y < -100.0:
		_run([player], 1)
	assert_false(motion.has_double_jumped)
	assert_eq(motion.air_jumps_left, 1)
	watch_signals(motion)
	_press()
	_run([player], 1)
	_press(Vector2.ZERO, true, true)
	_run([player], 1)
	assert_signal_emitted(motion, "double_jumped")
	assert_true(motion.has_double_jumped, "public, for the multiplayer mirror")
	assert_eq(motion.air_jumps_left, 0)
	assert_almost_eq(player.velocity.y, -SideRules.DOUBLE_JUMP_VELOCITY, 60.0)
	var top := _feet_local(player).y
	_press(Vector2.ZERO, false, true)
	for i in 60:
		_run([player], 1)
		top = minf(top, _feet_local(player).y)
	assert_gt(ground - top, 3.8 * SideRules.TILE, "both jumps reach about 4.5 tiles")
	_press()
	_run([player], 1)
	_press(Vector2.ZERO, true, true)
	_run([player], 1)
	assert_eq(motion.double_jumps, 1, "no third jump")
	for i in 120:
		_run([player], 1)
	assert_true(motion.is_on_floor())
	assert_false(motion.has_double_jumped, "landing gives it back")
	assert_eq(motion.air_jumps_left, SideRules.AIR_JUMPS)


func test_walking_off_an_edge_keeps_the_double_jump() -> void:
	var player := (await _setup())[0]
	player.side_motion.place_at(_segment.to_global(SideLayout.feet_of(Vector2i(11, 4))))
	_run([player], 5)
	_press(Vector2.RIGHT)
	while player.side_motion.is_on_floor():
		_run([player], 1)
	_run([player], 12)
	_press(Vector2.RIGHT, true, true)
	_run([player], 1)
	assert_lt(player.velocity.y, -600.0, "after the coyote time the air jump still works")
	assert_true(player.side_motion.has_double_jumped)


func test_apex_hang_slows_the_turn() -> void:
	var player := (await _setup())[0]
	_run([player], 10)
	_press(Vector2.ZERO, true, true)
	_run([player], 1)
	_press(Vector2.ZERO, false, true)
	var slow_frames := 0
	for i in 60:
		_run([player], 1)
		if absf(player.velocity.y) < SideRules.APEX_SPEED:
			slow_frames += 1
	# Without the hang the speed passes the band in about 2*90/2400 s (5 frames at 60 fps).
	assert_gt(slow_frames, 6, "the body hangs a moment at the top")


func test_wall_slide_and_wall_jump() -> void:
	var player := (await _setup())[0]
	var motion := player.side_motion
	# Next to the left border wall, jump and hold left: slide down the wall.
	player.side_motion.place_at(_segment.to_global(SideLayout.feet_of(Vector2i(1, 7))))
	_run([player], 5)
	_press(Vector2.LEFT, true, true)
	_run([player], 1)
	_press(Vector2.LEFT, false, true)
	var slid := false
	for i in 50:
		_run([player], 1)
		if motion.is_wall_sliding:
			slid = true
			assert_lte(player.velocity.y, SideRules.WALL_SLIDE_SPEED + 1.0, "the slide is slow")
			break
	assert_true(slid, "slides down the rock wall")
	assert_eq(motion.wall_side, -1, "the wall is on the left")
	watch_signals(motion)
	_press(Vector2.LEFT, true, true)
	_run([player], 1)
	assert_signal_emitted(motion, "wall_jumped")
	assert_gt(player.velocity.x, 100.0, "pushed away from the wall")
	assert_lt(player.velocity.y, -500.0, "and up")
	assert_false(motion.is_wall_sliding)
	assert_eq(motion.air_jumps_left, SideRules.AIR_JUMPS, "the wall gives the double jump back")


func test_crumbling_ledge_falls_and_comes_back() -> void:
	var plan := [
		"####################",
		"#..................#",
		"#..................#",
		"#..................#",
		"#..................#",
		"#.....~~~..........#",
		"#..................#",
		"#S...............D.#",
		"####################",
	]
	var player := (await _setup(1, plan))[0]
	var crumble := _segment.get_crumbles()[0]
	assert_eq(crumble.cells, 3)
	player.side_motion.place_at(_segment.to_global(SideLayout.feet_of(Vector2i(7, 4))))
	_run([player], 3)
	assert_eq(crumble.state, SideCrumble.State.SHAKING, "standing on it starts the shaking")
	_run([player], ceili(SideRules.CRUMBLE_DELAY / STEP) + 4)
	assert_eq(crumble.state, SideCrumble.State.FALLEN)
	_run([player], 40)
	assert_almost_eq(_feet_local(player).y, 8 * 64.0, 2.0, "the player dropped to the ground")
	_run([player], ceili(SideRules.CRUMBLE_RESPAWN / STEP) + 2)
	assert_true(crumble.is_solid(), "back after the respawn time")
	assert_eq(crumble.crumble_count, 1)


func test_squash_stretch_salto_and_camera_kick() -> void:
	var player := (await _setup())[0]
	var fx := _segment.get_fx(player)
	assert_not_null(fx)
	_run([player], 10)
	_press(Vector2.ZERO, true, true)
	_run([player], 1)
	assert_lt(fx.get_stretch().x, 1.0, "stretched at the take-off")
	assert_gt(fx.get_stretch().y, 1.0)
	_press()
	while player.velocity.y < -100.0:
		_run([player], 1)
	_press(Vector2.ZERO, true, true)
	_run([player], 1)
	assert_true(fx.is_spinning(), "salto at the double jump")
	# A hard landing from high up: squash and a camera kick.
	_press()
	player.side_motion.place_at(_segment.to_global(SideLayout.feet_of(Vector2i(3, 1))))
	for i in 90:
		_run([player], 1)
		if player.side_motion.is_on_floor():
			break
	assert_gt(fx.get_stretch().x, 1.0, "squashed wide at the landing")
	assert_lt(fx.get_stretch().y, 1.0)
	assert_gt(_segment.camera.get_kick().y, 0.0, "the camera is kicked down")
	var sprite := player.get_node("Sprite") as AnimatedSprite2D
	_segment.remove_players()
	assert_eq(sprite.scale, Vector2.ONE * SpriteStrip.PIXEL_SCALE, "the body sprite is put back")
	assert_eq(sprite.rotation, 0.0)


func test_new_animations_exist() -> void:
	var player := (await _setup())[0]
	var sprite := player.get_node("Sprite") as AnimatedSprite2D
	for animation in [PlayerSideArt.DOUBLE_JUMP, PlayerSideArt.WALL_SLIDE]:
		assert_true(sprite.sprite_frames.has_animation(animation), "%s added" % animation)

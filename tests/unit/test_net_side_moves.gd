extends GutTest
## Side-view moves and crumbling ledges in a group game (M5 round 2 over the network): the host
## decides every player's jumps, double jumps, wall jumps, wall slides and landings and every
## ledge; a copy of another machine's player (PlayerSideMotion.moves_from_remote) and a client's
## ledge (SideCrumble.remote_controlled) only show what the host decided - with the same signals,
## so salto, dust and squash play on every machine. Stepped by hand like test_side_motion.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const STEP := 1.0 / 60.0
const PLAN := [
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

var _old_save_path: String
var _segment: SideSegment = null
var _input := PlayerSideMotion.SideInput.new()


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_net_side_moves_save.cfg"


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	_input = PlayerSideMotion.SideInput.new()


func after_each() -> void:
	HitStop.reset()
	await wait_process_frames(1)


## A segment with one player whose input is _input, stepped by hand.
func _setup() -> Player:
	_segment = SideSegment.new()
	var layout := SideLayout.parse(PackedStringArray(PLAN), &"test")
	layout.biome_id = &"crypt"
	_segment.setup(layout, 1, null, 42)
	add_child_autofree(_segment)
	_segment.global_position = Vector2(0, 5000)
	_segment.set_physics_process(false)
	var player := PLAYER_SCENE.instantiate() as Player
	player.is_local = false
	add_child_autofree(player)
	player.set_physics_process(false)
	_segment.add_player(player)
	player.side_motion.input_source = func() -> PlayerSideMotion.SideInput: return _take_input()
	await wait_physics_frames(3)
	return player


func _take_input() -> PlayerSideMotion.SideInput:
	var input := _input
	var next := PlayerSideMotion.SideInput.new()
	next.axis = input.axis
	next.jump_pressed = input.jump_pressed
	_input = next
	return input


func _run(player: Player, frames: int) -> void:
	for i in frames:
		player._physics_process(STEP)


func _press_jump() -> void:
	_input.jump_just_pressed = true
	_input.jump_pressed = true


# --- Moves of a copy come from the host ---

func test_copy_does_not_jump_on_replayed_input() -> void:
	var player := await _setup()
	var motion := player.side_motion
	motion.moves_from_remote = true
	_run(player, 10)
	watch_signals(motion)
	_press_jump()
	_run(player, 2)
	assert_signal_not_emitted(motion, "jumped", "the host decides the jump")
	assert_gt(player.velocity.y, -10.0, "no jump of its own")
	motion.apply_remote_move(PlayerSideMotion.Move.JUMP, Vector2(0, -SideRules.JUMP_VELOCITY), 1.0)
	assert_signal_emitted(motion, "jumped")
	assert_lt(player.velocity.y, -SideRules.JUMP_VELOCITY + 1.0, "takes the host's velocity")
	assert_lt(_segment.get_fx(player).get_stretch().x, 1.0, "the take-off stretch plays here too")


func test_remote_double_jump_plays_the_salto() -> void:
	var player := await _setup()
	var motion := player.side_motion
	motion.moves_from_remote = true
	_run(player, 10)
	motion.apply_remote_move(PlayerSideMotion.Move.JUMP, Vector2(0, -SideRules.JUMP_VELOCITY), 1.0)
	_run(player, 12)
	watch_signals(motion)
	motion.apply_remote_move(PlayerSideMotion.Move.DOUBLE_JUMP, Vector2(120, -SideRules.DOUBLE_JUMP_VELOCITY), 1.0)
	assert_signal_emitted(motion, "double_jumped")
	assert_true(motion.has_double_jumped)
	assert_eq(motion.air_jumps_left, 0)
	assert_eq(motion.double_jumps, 1)
	assert_true(_segment.get_fx(player).is_spinning(), "salto on this machine")
	assert_eq(motion.get_animation(Vector2.ZERO), PlayerSideArt.DOUBLE_JUMP)


func test_landing_of_a_copy_is_the_hosts() -> void:
	var player := await _setup()
	var motion := player.side_motion
	motion.moves_from_remote = true
	motion.place_at(_segment.to_global(SideLayout.feet_of(Vector2i(3, 2))))
	watch_signals(motion)
	for i in 120:
		_run(player, 1)
		if motion.is_on_floor():
			break
	assert_true(motion.is_on_floor())
	assert_signal_not_emitted(motion, "landed", "no landing of its own")
	motion.apply_remote_move(PlayerSideMotion.Move.LAND, Vector2.ZERO, 1.0, SideRules.MAX_FALL_SPEED)
	assert_signal_emitted(motion, "landed")
	assert_gt(_segment.get_fx(player).get_stretch().x, 1.0, "squashed at the host's landing")


func test_wall_slide_and_double_jump_state_from_the_host() -> void:
	var player := await _setup()
	var motion := player.side_motion
	motion.moves_from_remote = true
	watch_signals(motion)
	motion.apply_remote_air_state(true, -1, true)
	assert_true(motion.is_wall_sliding)
	assert_eq(motion.wall_side, -1)
	assert_true(motion.has_double_jumped)
	assert_eq(motion.air_jumps_left, 0)
	assert_signal_emitted(motion, "wall_slide_changed")
	assert_eq(motion.get_animation(Vector2.ZERO), PlayerSideArt.WALL_SLIDE)
	motion.apply_remote_air_state(false, 1, false)
	assert_false(motion.is_wall_sliding)
	assert_eq(motion.air_jumps_left, SideRules.AIR_JUMPS)


func test_side_bits_carry_the_air_state() -> void:
	var player := await _setup()
	var motion := player.side_motion
	motion.is_wall_sliding = true
	motion.wall_side = 1
	motion.has_double_jumped = true
	var bits := NetPlayerState.side_bits_of(player)
	assert_true(bits & NetPlayerState.SIDE_WALL_SLIDING != 0)
	assert_true(bits & NetPlayerState.SIDE_WALL_RIGHT != 0)
	assert_true(bits & NetPlayerState.SIDE_DOUBLE_JUMPED != 0)
	motion.wall_side = -1
	assert_true(NetPlayerState.side_bits_of(player) & NetPlayerState.SIDE_WALL_RIGHT == 0, "left wall")


func test_own_moves_still_decide_without_the_flag() -> void:
	var player := await _setup()
	var motion := player.side_motion
	_run(player, 10)
	watch_signals(motion)
	_press_jump()
	_run(player, 1)
	assert_signal_emitted(motion, "jumped", "single player and the host decide as before")


# --- Crumbling ledges: the host decides ---

func test_host_ledge_reports_every_change() -> void:
	var player := await _setup()
	var crumble := _segment.get_crumbles()[0]
	var states: Array[int] = []
	crumble.state_changed.connect(func(_c: SideCrumble, state: SideCrumble.State) -> void: states.append(state))
	player.side_motion.place_at(_segment.to_global(SideLayout.feet_of(Vector2i(7, 4))))
	_run(player, 3)
	var players: Array[Player] = [player]
	crumble.update(players, STEP)
	for i in ceili(SideRules.CRUMBLE_DELAY / STEP) + 2:
		crumble.update(players, STEP)
	_run(player, 40)
	for i in ceili(SideRules.CRUMBLE_RESPAWN / STEP) + 2:
		crumble.update(players, STEP)
	assert_eq(states, [SideCrumble.State.SHAKING, SideCrumble.State.FALLEN, SideCrumble.State.SOLID] as Array[int])


func test_client_ledge_follows_the_host_only() -> void:
	await _setup()
	var crumble := _segment.get_crumbles()[0]
	crumble.remote_controlled = true
	crumble.apply_remote_state(SideCrumble.State.SHAKING)
	assert_eq(crumble.state, SideCrumble.State.SHAKING, "shakes when the host's shakes")
	crumble.step(SideRules.CRUMBLE_DELAY * 3.0, true)
	assert_eq(crumble.state, SideCrumble.State.SHAKING, "never falls on its own")
	crumble.apply_remote_state(SideCrumble.State.FALLEN)
	assert_false(crumble.is_solid())
	var shape := crumble.get_node("Body").get_child(0) as CollisionShape2D
	assert_true(shape.disabled, "nobody stands on it any more")
	crumble.step(SideRules.CRUMBLE_RESPAWN * 3.0, false)
	assert_eq(crumble.state, SideCrumble.State.FALLEN, "never comes back on its own")
	crumble.apply_remote_state(SideCrumble.State.SOLID)
	assert_true(crumble.is_solid())
	assert_false(shape.disabled)
	assert_eq(crumble.crumble_count, 1)


func test_client_ledge_can_skip_the_shaking() -> void:
	await _setup()
	var crumble := _segment.get_crumbles()[0]
	crumble.remote_controlled = true
	crumble.apply_remote_state(SideCrumble.State.FALLEN)
	assert_eq(crumble.state, SideCrumble.State.FALLEN, "a late client goes straight to the host's state")

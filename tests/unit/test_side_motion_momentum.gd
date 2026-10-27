extends GutTest
## Momentum and stomping in a real side segment (D-195, SV1, D-216), stepped by hand with the real
## player like test_side_motion: running speeds up to 2.0×, the jump keeps it, stopping, a wall and
## a hit lose it; landing on a slime stomps it and bounces 1.5 tiles; running into a skeleton at top
## speed hurts and beats nothing (no running over, D-216); an enemy that refuses is asked once; only
## the deciding machine decides (not a copy, not a client, not a host's puppet); the host's stomp
## plays on a copy.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const STEP := 1.0 / 60.0
## Long flat floor, start on the left, the door on the right.
const PLAN := [
	"##############################",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#S..........................D#",
	"##############################",
]
const FLOOR_ROW := 7


## A side enemy that refuses every stomp and counts the questions.
class RefusingEnemy:
	extends SideEnemy
	var asked := 0

	func on_stomped(_player: Player) -> bool:
		asked += 1
		return false


var _old_save_path: String
var _input := PlayerSideMotion.SideInput.new()
var _segment: SideSegment = null


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_side_motion_momentum_save.cfg"


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	_input = PlayerSideMotion.SideInput.new()


func after_each() -> void:
	HitStop.reset()
	await wait_process_frames(1)


## A segment with one player driven by _input; enemies as [kind, column] pairs on the floor.
func _setup(enemies: Array = []) -> Player:
	var plan := PackedStringArray(PLAN)
	for entry: Array in enemies:
		var row := plan[FLOOR_ROW]
		var column: int = entry[1]
		plan[FLOOR_ROW] = row.substr(0, column) + String(entry[0]) + row.substr(column + 1)
	_segment = SideSegment.new()
	var layout := SideLayout.parse(plan, &"test")
	layout.biome_id = &"crypt"
	_segment.setup(layout, 1, null, 42)
	add_child_autofree(_segment)
	_segment.global_position = Vector2(0, 5000)
	_segment.set_physics_process(false)
	var player := PLAYER_SCENE.instantiate() as Player
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


func _press(axis := Vector2.ZERO, jump_just := false, jump_held := false) -> void:
	_input.axis = axis
	_input.jump_just_pressed = jump_just
	_input.jump_pressed = jump_held or jump_just


func _run(player: Player, frames: int) -> void:
	for i in frames:
		player._physics_process(STEP)
		_segment._physics_process(STEP)


func _seconds(seconds: float) -> int:
	return roundi(seconds / STEP)


func _feet_local(player: Player) -> Vector2:
	return _segment.to_local(player.get_feet_position())


func _place(player: Player, cell: Vector2i, above_tiles := 0.0) -> void:
	player.side_motion.place_at(_segment.to_global(SideLayout.feet_of(cell) - Vector2(0, above_tiles * SideRules.TILE)))


func _gone(enemy: SideEnemy) -> bool:
	return not is_instance_valid(enemy) or enemy.is_dead()


# --- Momentum ---

func test_running_on_speeds_up_to_twice_the_move_speed() -> void:
	var player := await _setup()
	_press(Vector2.RIGHT)
	_run(player, _seconds(0.5))
	assert_almost_eq(player.velocity.x, player.move_speed * 1.3, 2.0, "1.3× at first")
	_run(player, _seconds(1.3))
	assert_almost_eq(player.side_motion.get_speed_factor(), 2.0, 0.001)
	assert_almost_eq(player.velocity.x, player.move_speed * 2.0, 2.0, "2.0× after 0.6 s + 1.0 s")


func test_the_jump_keeps_the_momentum() -> void:
	var player := await _setup()
	_press(Vector2.RIGHT)
	_run(player, _seconds(1.8))
	_press(Vector2.RIGHT, true, true)
	_run(player, 1)
	_press(Vector2.RIGHT, false, true)
	var fastest_in_air := 0.0
	for i in 40:
		_run(player, 1)
		if not player.side_motion.is_on_floor():
			fastest_in_air = maxf(fastest_in_air, player.velocity.x)
	assert_almost_eq(fastest_in_air, player.move_speed * 2.0, 2.0, "a jump with a run-up")
	assert_almost_eq(player.side_motion.get_speed_factor(), 2.0, 0.001, "still there after the landing")


func test_stopping_loses_the_momentum() -> void:
	var player := await _setup()
	var motion := player.side_motion
	_press(Vector2.RIGHT)
	_run(player, _seconds(1.8))
	watch_signals(motion)
	_press()
	_run(player, _seconds(0.2))
	assert_signal_emitted(motion, "momentum_lost")
	assert_almost_eq(motion.get_speed_factor(), SideRules.RUN_SPEED_FACTOR, 0.001)


func test_a_wall_loses_the_momentum() -> void:
	var player := await _setup()
	var motion := player.side_motion
	_place(player, Vector2i(18, FLOOR_ROW))
	_run(player, 3)
	_press(Vector2.RIGHT)
	var had := false
	watch_signals(motion)
	for i in _seconds(3.0):
		_run(player, 1)
		had = had or motion.get_speed_factor() > 1.6
	assert_true(had, "fast before the wall")
	assert_signal_emitted(motion, "momentum_lost")
	assert_lt(motion.get_speed_factor(), 1.6, "pressing into the wall builds no momentum")
	assert_almost_eq(player.velocity.x, 0.0, 1.0, "stands at the wall")


func test_a_hit_loses_the_momentum() -> void:
	var player := await _setup()
	_press(Vector2.RIGHT)
	_run(player, _seconds(1.8))
	assert_true(player.side_motion.momentum.has_momentum())
	var damage := DamageData.new()
	damage.amount = 1.0
	damage.hit_id = DamageData.next_hit_id()
	player.hurtbox.receive_hit(damage)
	assert_false(player.side_motion.momentum.has_momentum(), "lost with the hit")


func test_the_cap_stays_two_and_enter_resets_the_momentum() -> void:
	var player := await _setup()
	var motion := player.side_motion
	_press(Vector2.RIGHT)
	_run(player, _seconds(2.6))
	assert_almost_eq(motion.get_speed_factor(), SideMomentum.MAX_FACTOR, 0.001, "2.0× at most (D-216)")
	_segment.remove_players()
	_segment.add_player(player)
	assert_almost_eq(motion.get_speed_factor(), SideRules.RUN_SPEED_FACTOR, 0.001, "a new section starts without momentum")


func test_sprint_and_stomp_animations() -> void:
	var player := await _setup([["s", 8]])
	var motion := player.side_motion
	var sprite := player.get_node("Sprite") as AnimatedSprite2D
	assert_true(sprite.sprite_frames.has_animation(SideSpeedArt.SPRINT), "sprint added (placeholder or delivered)")
	assert_true(sprite.sprite_frames.has_animation(SideSpeedArt.STOMP), "stomp added")
	var data := sprite.get_meta(CharacterData.META_DATA, null) as CharacterData
	if data != null:
		assert_not_null(data.get_mask(SideSpeedArt.SPRINT), "the sprint keeps the clothing colour")
	_place(player, Vector2i(8, FLOOR_ROW), 2.5)
	var saw_stomp := false
	for i in 40:
		_run(player, 1)
		saw_stomp = saw_stomp or motion.get_animation(Vector2.ZERO) == SideSpeedArt.STOMP
	assert_true(saw_stomp, "stomp frames after the stomp")
	_place(player, Vector2i(1, FLOOR_ROW))
	_run(player, 30)
	_press(Vector2.RIGHT)
	_run(player, 10)
	assert_eq(motion.get_animation(Vector2.RIGHT), &"walk", "walking at first")
	_run(player, _seconds(1.5))
	assert_eq(motion.get_animation(Vector2.RIGHT), SideSpeedArt.SPRINT, "sprinting near the top speed")


# --- Stomp ---

func test_landing_on_a_slime_stomps_it_and_bounces() -> void:
	var player := await _setup([["s", 8]])
	var slime := _segment.get_enemies()[0]
	var hp := player.health.get_health()
	var motion := player.side_motion
	watch_signals(motion)
	_place(player, Vector2i(8, FLOOR_ROW), 2.5)
	var stomp_feet := INF
	var top := INF
	for i in 90:
		_run(player, 1)
		if stomp_feet == INF and motion.stomps > 0:
			stomp_feet = _feet_local(player).y
			assert_lt(player.velocity.y, 0.0, "bounces up")
		elif stomp_feet != INF:
			top = minf(top, _feet_local(player).y)
	assert_eq(motion.stomps, 1, "one stomp")
	assert_signal_emitted(motion, "stomped")
	assert_true(_gone(slime), "the slime is beaten")
	assert_almost_eq(stomp_feet - top, 1.5 * SideRules.TILE, 12.0, "1.5 tiles back up")
	assert_eq(player.health.get_health(), hp, "no damage")
	assert_eq(motion.air_jumps_left, SideRules.AIR_JUMPS, "the double jump is back")


func test_refusing_enemy_is_asked_once_and_the_player_falls_on() -> void:
	var player := await _setup()
	var enemy := RefusingEnemy.new()
	enemy.setup(SideEnemy.Kind.SLIME, 1, _segment, 7)
	enemy.position = SideLayout.feet_of(Vector2i(8, FLOOR_ROW))
	_segment.add_child(enemy)
	_segment._enemies.append(enemy)
	await wait_physics_frames(1)
	_place(player, Vector2i(8, FLOOR_ROW), 2.5)
	_run(player, 60)
	assert_eq(enemy.asked, 1, "asked once, not every frame")
	assert_eq(player.side_motion.stomps, 0)
	assert_false(enemy.is_dead())
	assert_true(player.side_motion.is_on_floor(), "no bounce: down on the floor")


# --- No running over (D-216) ---

func test_running_into_a_skeleton_at_top_speed_hurts_and_beats_nothing() -> void:
	# Near the far wall: wherever the skeleton walks, it stays in the way.
	var player := await _setup([["k", 26]])
	var skeleton := _segment.get_enemies()[0]
	var hp := player.health.get_health() + player.shield.get_shield()
	var motion := player.side_motion
	_press(Vector2.RIGHT)
	var top_speed := false
	var hurt := false
	for i in _seconds(6.0):
		_run(player, 1)
		await wait_physics_frames(1)
		top_speed = top_speed or motion.get_speed_factor() > 1.9
		if player.health.get_health() + player.shield.get_shield() < hp:
			hurt = true
			break
	assert_true(top_speed, "at top speed before the skeleton")
	assert_true(hurt, "the skeleton's contact hurts at any speed")
	assert_false(_gone(skeleton), "nobody is run over")
	assert_false(motion.momentum.has_momentum(), "the hit takes the momentum")


func test_walking_into_a_skeleton_beats_nothing() -> void:
	var player := await _setup([["k", 4]])
	var skeleton := _segment.get_enemies()[0]
	_press(Vector2.RIGHT)
	_run(player, _seconds(0.8))
	assert_eq(player.side_motion.stomps, 0)
	assert_false(_gone(skeleton), "walking into it does not beat it")


# --- Who decides (co-op) ---

func test_a_copy_and_a_client_do_not_decide() -> void:
	var player := await _setup([["s", 8]])
	var slime := _segment.get_enemies()[0]
	var motion := player.side_motion
	motion.moves_from_remote = true
	_place(player, Vector2i(8, FLOOR_ROW), 2.5)
	_run(player, 60)
	assert_eq(motion.stomps, 0, "a copy shows the host's stomps only")
	motion.moves_from_remote = false
	motion.decides_enemy_contacts = false
	_place(player, Vector2i(8, FLOOR_ROW), 2.5)
	_run(player, 60)
	assert_eq(motion.stomps, 0, "a client's own player waits for the host")
	motion.decides_enemy_contacts = true
	slime.set_physics_process(false)
	_place(player, Vector2i(8, FLOOR_ROW), 2.5)
	_run(player, 60)
	assert_eq(motion.stomps, 0, "a host's puppet is not decided here")
	assert_false(_gone(slime))
	slime.set_physics_process(true)
	_place(player, Vector2i(8, FLOOR_ROW), 2.5)
	_run(player, 60)
	assert_eq(motion.stomps, 1, "the deciding machine stomps")


func test_hosts_stomp_plays_on_a_copy() -> void:
	var player := await _setup()
	var motion := player.side_motion
	motion.moves_from_remote = true
	_place(player, Vector2i(8, FLOOR_ROW), 2.0)
	player.velocity = Vector2(123.0, 400.0)
	motion.air_jumps_left = 0
	watch_signals(motion)
	motion.apply_remote_move(PlayerSideMotion.Move.STOMP, Vector2(50.0, -600.0), 1.0)
	assert_almost_eq(player.velocity.y, -600.0, 0.01, "the host's bounce")
	assert_almost_eq(player.velocity.x, 123.0, 0.01, "the run stays its own")
	assert_signal_emitted_with_parameters(motion, "stomped", [player, null])
	assert_eq(motion.air_jumps_left, SideRules.AIR_JUMPS)
	assert_eq(PlayerSideMotion.Move.keys(), ["JUMP", "DOUBLE_JUMP", "WALL_JUMP", "LAND", "STOMP"], "no ram move any more (D-216)")

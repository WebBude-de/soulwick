extends GutTest
## Momentum and stomp rules of the side view (D-195, SV1, D-216) without nodes: the speed ramp
## (1.3× -> 2.0× after 0.6 s in 1.0 s, the same cap everywhere), what keeps and what loses the
## momentum, and the stomp geometry. Nobody is run over (D-216).

const STEP := 1.0 / 60.0


func _run(momentum: SideMomentum, seconds: float, on_floor := true, axis_x := 1.0) -> void:
	for i in roundi(seconds / STEP):
		momentum.update(STEP, on_floor, axis_x)


# --- Ramp ---

func test_ramp_starts_after_the_delay_and_reaches_two_in_one_second() -> void:
	assert_almost_eq(SideMomentum.factor_for(0.0), SideRules.RUN_SPEED_FACTOR, 0.0001, "1.3× at the start")
	assert_almost_eq(SideMomentum.factor_for(0.6), 1.3, 0.0001, "no climb before 0.6 s")
	assert_almost_eq(SideMomentum.factor_for(1.1), 1.65, 0.0001, "half way after half the ramp")
	assert_almost_eq(SideMomentum.factor_for(1.6), 2.0, 0.0001, "2.0× after 0.6 s + 1.0 s")
	assert_almost_eq(SideMomentum.factor_for(10.0), 2.0, 0.0001, "capped at 2.0×")


func test_the_cap_is_two_everywhere() -> void:
	assert_eq(SideMomentum.MAX_FACTOR, 2.0, "D-216: 2.0× in every obstacle run")
	assert_almost_eq(SideMomentum.factor_for(SideMomentum.time_for(1.8)), 1.8, 0.0001, "time_for inverts the ramp")
	assert_almost_eq(SideMomentum.time_for(SideMomentum.MAX_FACTOR), 1.6, 0.0001)


func test_running_on_the_ground_builds_momentum() -> void:
	var momentum := SideMomentum.new()
	_run(momentum, 0.5)
	assert_false(momentum.has_momentum(), "not yet after 0.5 s")
	_run(momentum, 1.2)
	assert_almost_eq(momentum.factor(), SideMomentum.MAX_FACTOR, 0.0001)
	assert_eq(momentum.direction, 1)


func test_the_jump_keeps_the_momentum_and_freezes_the_timer() -> void:
	var momentum := SideMomentum.new()
	_run(momentum, 1.1)
	var factor := momentum.factor()
	_run(momentum, 0.8, false, 1.0)
	assert_almost_eq(momentum.factor(), factor, 0.0001, "the air neither adds nor takes")
	_run(momentum, 0.8, false, 0.0)
	assert_almost_eq(momentum.factor(), factor, 0.0001, "letting go of the stick in the air keeps it")


func test_stopping_on_the_ground_loses_it_after_the_grace() -> void:
	var momentum := SideMomentum.new()
	_run(momentum, 2.0)
	assert_false(momentum.update(STEP, true, 0.0), "one frame without the stick is forgiven")
	assert_true(momentum.has_momentum())
	var lost := false
	for i in 10:
		lost = momentum.update(STEP, true, 0.0) or lost
	assert_true(lost, "the update reports the loss")
	assert_false(momentum.has_momentum())
	assert_eq(momentum.direction, 0)


func test_turning_round_loses_it_in_the_air_too() -> void:
	var momentum := SideMomentum.new()
	_run(momentum, 2.0)
	assert_true(momentum.update(STEP, false, -1.0), "turned in the air")
	assert_false(momentum.has_momentum())
	assert_eq(momentum.direction, -1, "runs the other way from now on")


func test_reset_reports_whether_there_was_momentum() -> void:
	var momentum := SideMomentum.new()
	assert_false(momentum.reset(), "nothing to lose")
	_run(momentum, 2.0)
	assert_true(momentum.reset())
	assert_almost_eq(momentum.factor(), SideRules.RUN_SPEED_FACTOR, 0.0001)


func test_deadzone() -> void:
	assert_eq(SideMomentum.axis_direction(0.1), 0)
	assert_eq(SideMomentum.axis_direction(-0.8), -1)


# --- Stomp ---

func test_stomp_bounce_is_one_and_a_half_tiles() -> void:
	var velocity := SideContactRules.stomp_bounce_velocity()
	assert_almost_eq(velocity * velocity / (2.0 * SideRules.GRAVITY), 1.5 * SideRules.TILE, 0.01)


func test_stomp_needs_a_fall_from_above_onto_the_body() -> void:
	var enemy := Rect2(Vector2(100, 200), Vector2(26, 22))
	var top := enemy.position.y
	var center_x := enemy.get_center().x
	assert_true(SideContactRules.is_stomp(Vector2(center_x, top - 12), Vector2(center_x, top - 4), 600.0, 10.0, enemy, STEP),
			"falling onto the top, reaches it next frame")
	assert_false(SideContactRules.is_stomp(Vector2(center_x, top - 12), Vector2(center_x, top - 4), -300.0, 10.0, enemy, STEP),
			"rising does not stomp")
	assert_false(SideContactRules.is_stomp(Vector2(center_x, top - 80), Vector2(center_x, top - 70), 600.0, 10.0, enemy, STEP),
			"still far above")
	assert_false(SideContactRules.is_stomp(Vector2(center_x, top + 18), Vector2(center_x, top + 20), 200.0, 10.0, enemy, STEP),
			"came from the side, not from above")
	assert_false(SideContactRules.is_stomp(Vector2(center_x + 30, top - 12), Vector2(center_x + 30, top - 4), 600.0, 10.0, enemy, STEP),
			"beside the body")
	assert_true(SideContactRules.is_stomp(Vector2(center_x + 18, top - 12), Vector2(center_x + 18, top - 4), 600.0, 10.0, enemy, STEP),
			"an edge of the feet on the body is enough")


func test_enemy_body_rect_stands_on_the_feet() -> void:
	var enemy := Node2D.new()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(26, 22)
	shape.shape = box
	shape.position = Vector2(0, -11)
	enemy.add_child(shape)
	add_child_autofree(enemy)
	enemy.global_position = Vector2(100, 300)
	var rect := SideContactRules.enemy_body_rect(enemy)
	assert_almost_eq(rect.position.x, 87.0, 0.01)
	assert_almost_eq(rect.position.y, 278.0, 0.01)
	assert_almost_eq(rect.end.y, 300.0, 0.01, "the bottom is the feet")

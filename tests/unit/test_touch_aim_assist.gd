extends GutTest
## Touch aim assist (TouchAimAssist, D-155 follow-up): with a ranged weapon the deflected aim stick
## snaps onto a living, visible enemy in a narrow cone and in range; smallest angle first, nearer on
## a tie. Melee weapons, a released stick and enemies in the dark get no assist.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://enemies/enemy_base.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
const BOW: WeaponData = preload("res://weapons/data/bow.tres")
const STAFF: WeaponData = preload("res://weapons/data/staff.tres")
const SWORD: WeaponData = preload("res://weapons/data/sword.tres")
const TEST_SAVE_PATH := "user://test_touch_aim_assist.cfg"

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.load_game()


func after_all() -> void:
	await wait_seconds(0.3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


# --- Pure decision ---

func _points(values: Array) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for value: Vector2 in values:
		points.append(value)
	return points


func test_pick_in_cone_takes_only_points_in_cone_and_range() -> void:
	var inside := Vector2.RIGHT.rotated(deg_to_rad(TouchAimAssist.CONE_DEGREES - 2.0)) * 200.0
	var outside := Vector2.RIGHT.rotated(deg_to_rad(TouchAimAssist.CONE_DEGREES + 2.0)) * 200.0
	assert_eq(TouchAimAssist.pick_in_cone(Vector2.ZERO, Vector2.RIGHT, _points([outside, inside]), 400.0), 1, "inside the cone")
	assert_eq(TouchAimAssist.pick_in_cone(Vector2.ZERO, Vector2.RIGHT, _points([outside]), 400.0), -1, "just outside the cone")
	assert_eq(TouchAimAssist.pick_in_cone(Vector2.ZERO, Vector2.RIGHT, _points([Vector2(500, 0)]), 400.0), -1, "out of range")
	assert_eq(TouchAimAssist.pick_in_cone(Vector2.ZERO, Vector2.RIGHT, _points([Vector2(-200, 0)]), 400.0), -1, "behind")
	assert_eq(TouchAimAssist.pick_in_cone(Vector2.ZERO, Vector2.RIGHT, _points([Vector2.ZERO]), 400.0), -1, "on the origin")
	assert_eq(TouchAimAssist.pick_in_cone(Vector2.ZERO, Vector2.RIGHT, _points([]), 400.0), -1, "nobody there")
	assert_eq(TouchAimAssist.pick_in_cone(Vector2(100, 100), Vector2.DOWN, _points([Vector2(110, 300)]), 400.0), 0, "measured from the origin")


func test_pick_in_cone_prefers_smallest_angle_then_nearer() -> void:
	var near_wide := Vector2.RIGHT.rotated(deg_to_rad(8.0)) * 100.0
	var far_narrow := Vector2.RIGHT.rotated(deg_to_rad(-3.0)) * 350.0
	assert_eq(TouchAimAssist.pick_in_cone(Vector2.ZERO, Vector2.RIGHT, _points([near_wide, far_narrow]), 400.0), 1, "smallest angle wins over distance")
	var far := Vector2(300, 0)
	var near := Vector2(120, 0)
	assert_eq(TouchAimAssist.pick_in_cone(Vector2.ZERO, Vector2.RIGHT, _points([far, near]), 400.0), 1, "tie: the nearer one")
	assert_eq(TouchAimAssist.pick_in_cone(Vector2.ZERO, Vector2.RIGHT, _points([near, far]), 400.0), 0, "tie: order does not matter")


func test_ranged_reach_only_for_bow_and_staff() -> void:
	assert_false(BOW.is_melee())
	assert_false(STAFF.is_melee())
	for weapon: WeaponData in [SWORD, preload("res://weapons/data/dagger.tres"), preload("res://weapons/data/hammer.tres")]:
		assert_true(weapon.is_melee(), "%s is melee" % weapon.id)


# --- Player with touch input ---

func _player(weapon: WeaponData) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)
	# Polled by hand below, so the player's own input and attacks stay out of the way.
	player.set_physics_process(false)
	var controller := player.weapon_controller
	if controller.get_active_weapon() != weapon:
		var slot := controller.get_active_slot()
		if not controller.equip_weapon(weapon, slot):
			var other := (slot + 1) % WeaponController.MAX_WEAPON_SLOTS
			controller.equip_weapon(weapon, other)
			controller.set_active_slot(other)
	assert_eq(controller.get_active_weapon(), weapon, "holds %s" % weapon.id)
	return player


func _enemy(pos: Vector2) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.data = SKELETON
	enemy.global_position = pos
	add_child_autofree(enemy)
	enemy.set_physics_process(false)
	return enemy


func _aim(player: Player, stick: Vector2) -> Vector2:
	var state := TouchState.new()
	state.forced = true
	state.mark_polled(false, true)
	state.aim = stick
	var input := TouchInput.new(state)
	input.poll(player)
	return input.get_aim_direction(Vector2.ZERO, Vector2.UP)


func test_bow_snaps_onto_the_enemy_in_the_cone() -> void:
	var player: Player = await _player(BOW)
	var origin := TouchAimAssist.aim_origin(player)
	var target := _enemy(origin + Vector2.RIGHT.rotated(deg_to_rad(8.0)) * 250.0)
	await wait_physics_frames(1)
	var aim := _aim(player, Vector2.RIGHT)
	assert_almost_eq(aim, (target.global_position - origin).normalized(), Vector2(0.001, 0.001), "snapped onto the enemy")
	var off := _aim(player, Vector2.UP)
	assert_almost_eq(off, Vector2.UP, Vector2(0.001, 0.001), "stick far from it: plain stick direction")


func test_staff_snaps_too_but_not_beyond_its_range() -> void:
	var player: Player = await _player(STAFF)
	var origin := TouchAimAssist.aim_origin(player)
	var far := _enemy(origin + Vector2.RIGHT.rotated(deg_to_rad(5.0)) * (STAFF.attack_range + 40.0))
	await wait_physics_frames(1)
	assert_almost_eq(_aim(player, Vector2.RIGHT), Vector2.RIGHT, Vector2(0.001, 0.001), "out of reach: no snap")
	far.global_position = origin + Vector2.RIGHT.rotated(deg_to_rad(5.0)) * (STAFF.attack_range - 40.0)
	assert_almost_eq(_aim(player, Vector2.RIGHT), Vector2.RIGHT.rotated(deg_to_rad(5.0)), Vector2(0.001, 0.001), "in reach: snap")


func test_melee_weapon_gets_no_assist() -> void:
	var player: Player = await _player(SWORD)
	var origin := TouchAimAssist.aim_origin(player)
	_enemy(origin + Vector2.RIGHT.rotated(deg_to_rad(8.0)) * 60.0)
	await wait_physics_frames(1)
	assert_almost_eq(_aim(player, Vector2.RIGHT), Vector2.RIGHT, Vector2(0.001, 0.001), "sword: plain stick direction")


func test_dead_or_dark_enemies_are_no_targets() -> void:
	var player: Player = await _player(BOW)
	var origin := TouchAimAssist.aim_origin(player)
	var enemy := _enemy(origin + Vector2.RIGHT.rotated(deg_to_rad(6.0)) * 300.0)
	await wait_physics_frames(1)
	var darkness := DarknessVisibility.new()
	var circles: Array[Vector3] = [LightQuery.circle(origin, 120.0)]
	darkness.set_viewer(circles, 1.0)
	add_child_autofree(darkness)
	darkness.refresh(true)
	assert_lt(darkness.get_enemy_alpha(enemy), TouchAimAssist.MIN_VISIBLE_ALPHA, "the enemy hides in the dark")
	assert_almost_eq(_aim(player, Vector2.RIGHT), Vector2.RIGHT, Vector2(0.001, 0.001), "unseen: no snap")
	circles = [LightQuery.circle(origin, 600.0)]
	darkness.set_viewer(circles, 1.0)
	darkness.refresh(true)
	assert_almost_eq(_aim(player, Vector2.RIGHT), Vector2.RIGHT.rotated(deg_to_rad(6.0)), Vector2(0.001, 0.001), "in the light: snap")
	enemy.visible = false
	assert_almost_eq(_aim(player, Vector2.RIGHT), Vector2.RIGHT, Vector2(0.001, 0.001), "hidden (coming out of a source): no snap")


func test_released_stick_gets_no_assist() -> void:
	var player: Player = await _player(BOW)
	var origin := TouchAimAssist.aim_origin(player)
	_enemy(origin + Vector2.RIGHT.rotated(deg_to_rad(6.0)) * 200.0)
	await wait_physics_frames(1)
	assert_eq(TouchAimAssist.apply(player, Vector2.ZERO, Vector2.RIGHT), Vector2.RIGHT, "no stick, no assist (walking direction stays)")
	assert_almost_eq(TouchAimAssist.apply(player, Vector2.RIGHT * 0.1, Vector2.RIGHT), Vector2.RIGHT.rotated(deg_to_rad(6.0)), Vector2(0.001, 0.001), "light deflection already snaps")

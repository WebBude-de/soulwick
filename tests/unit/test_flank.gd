extends GutTest
## Flanking (RAEUME §6): close-combat enemies spread over ring places around their
## target instead of queueing, a part cuts off a fleeing target, ranged enemies change sides now
## and then; all gentle in the first rooms (EnemyTactics.intensity).

const ENEMY_SCENE_PATH := "res://enemies/enemy_base.tscn"
const SKELETON := "res://enemies/data/skeleton.tres"
const ARCHER := "res://enemies/data/archer.tres"
const TEST_SAVE_PATH := "user://test_flank.cfg"

var _old_save_path: String


class FakePlayer:
	extends Node2D
	var alive := true

	func is_alive() -> bool:
		return alive


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.load_game()


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func after_each() -> void:
	HitStop.reset()


func _fake(position: Vector2) -> FakePlayer:
	var fake := FakePlayer.new()
	add_child_autofree(fake)
	fake.add_to_group(&"player")
	fake.global_position = position
	return fake


func _container() -> Node2D:
	var container := Node2D.new()
	add_child_autofree(container)
	return container


func _enemy(path: String, position: Vector2, container: Node, room: int) -> Enemy:
	var enemy: Enemy = (load(ENEMY_SCENE_PATH) as PackedScene).instantiate()
	enemy.data = load(path)
	enemy.apply_scaling(room, false)
	enemy.position = position
	container.add_child(enemy)
	return enemy


## Four skeletons coming from the east, all on one side of the target.
func _skeleton_group(container: Node, room: int) -> Array[Enemy]:
	var group: Array[Enemy] = []
	for i in 4:
		group.append(_enemy(SKELETON, Vector2(420 + (i % 2) * 40, -70 + i * 45), container, room))
	return group


func _angles(enemies: Array[Enemy], center: Vector2, pack: EnemyPack) -> PackedFloat32Array:
	var angles := PackedFloat32Array()
	for enemy in enemies:
		var order := pack.get_order(enemy)
		if order != null and order.role == EnemyPack.Role.RING:
			angles.append(angle_difference(0.0, order.angle))
	angles.sort()
	return angles


func test_melee_enemies_spread_around_the_target() -> void:
	var container := _container()
	var player := _fake(Vector2.ZERO)
	var skeletons := _skeleton_group(container, 10)
	await wait_physics_frames(10)
	var pack := EnemyPack.of(container)
	var angles := _angles(skeletons, player.global_position, pack)
	assert_eq(angles.size(), 4, "every skeleton has a ring place")
	assert_gt(angles[angles.size() - 1] - angles[0], PI, "places on several sides, not one queue")
	# They really get there: some walk around the player to the far (west) side.
	var far_side := false
	for i in 60 * 4:
		await wait_physics_frames(1)
		for skeleton in skeletons:
			var offset := skeleton.global_position - player.global_position
			if offset.x < 0.0 and absf(offset.angle()) > PI * 0.6:
				far_side = true
		if far_side:
			break
	assert_true(far_side, "a skeleton came round to the back")


func test_first_room_stays_a_narrow_fan() -> void:
	var container := _container()
	var player := _fake(Vector2.ZERO)
	var skeletons := _skeleton_group(container, 1)
	await wait_physics_frames(10)
	var angles := _angles(skeletons, player.global_position, EnemyPack.of(container))
	assert_eq(angles.size(), 4)
	assert_lt(angles[angles.size() - 1] - angles[0], TAU * EnemyTactics.MIN_SPREAD + 0.01, "room 1: they keep coming from one side")


func test_a_lone_enemy_keeps_its_straight_chase() -> void:
	var container := _container()
	_fake(Vector2.ZERO)
	var skeleton := _enemy(SKELETON, Vector2(300, 0), container, 20)
	await wait_physics_frames(10)
	assert_eq(skeleton.get_tactics().get_role(skeleton), EnemyPack.Role.DIRECT)


func test_a_part_cuts_off_a_fleeing_target() -> void:
	var container := _container()
	var player := _fake(Vector2.ZERO)
	var ahead := _enemy(SKELETON, Vector2(380, 160), container, 12)
	var behind_a := _enemy(SKELETON, Vector2(-320, 40), container, 12)
	var behind_b := _enemy(SKELETON, Vector2(-320, -60), container, 12)
	var cutter_seen := false
	var goal_ahead := false
	for i in 60 * 2:
		player.global_position += Vector2(160.0 / 60.0, 0.0)
		await wait_physics_frames(1)
		var pack := ahead.get_tactics()
		if pack == null:
			continue
		for skeleton in [ahead, behind_a, behind_b]:
			if pack.get_role(skeleton) == EnemyPack.Role.CUT_OFF:
				cutter_seen = true
				assert_eq(skeleton, ahead, "the one ahead of the target cuts off")
				goal_ahead = goal_ahead or pack.walk_goal(skeleton).x > player.global_position.x + 40.0
		if goal_ahead:
			break
	assert_true(cutter_seen, "someone cuts off the fleeing player")
	assert_true(goal_ahead, "its goal lies ahead in the running direction")


func test_nobody_cuts_off_in_the_first_rooms() -> void:
	var container := _container()
	var player := _fake(Vector2.ZERO)
	var group := _skeleton_group(container, 5)
	for i in 60:
		player.global_position += Vector2(0.0, 160.0 / 60.0)
		await wait_physics_frames(1)
	var pack := EnemyPack.of(container)
	for skeleton in group:
		assert_ne(pack.get_role(skeleton), EnemyPack.Role.CUT_OFF)


func test_ranged_enemies_change_sides_now_and_then() -> void:
	var container := _container()
	var player := _fake(Vector2.ZERO)
	var archer := _enemy(ARCHER, Vector2(240, 0), container, 10)
	await wait_physics_frames(5)
	var pack := archer.get_tactics()
	pack.set_seed(7)
	var relocating := false
	for i in 60:
		pack.advance(EnemyTactics.REPLAN_INTERVAL)
		if pack.is_relocating(archer):
			relocating = true
			break
	assert_true(relocating, "a side change comes within the interval")
	var order := pack.get_order(archer)
	assert_gt(absf(angle_difference(0.0, order.angle)), EnemyTactics.SIDE_SWITCH_ANGLE.x - 0.01, "a real change of sides")
	var start_angle := (archer.global_position - player.global_position).angle()
	var moved := false
	# A shot under way is finished first, then it walks (one loop step takes about two frames).
	for i in 60 * 3:
		await wait_physics_frames(1)
		if absf(angle_difference(start_angle, (archer.global_position - player.global_position).angle())) > 0.5:
			moved = true
			break
	assert_true(moved, "the archer walks around the player to its new side")
	assert_gt(archer.global_position.distance_to(player.global_position), 120.0, "and keeps its distance")


func test_ranged_enemies_hold_their_side_in_the_first_rooms() -> void:
	var container := _container()
	_fake(Vector2.ZERO)
	var archer := _enemy(ARCHER, Vector2(240, 0), container, 2)
	await wait_physics_frames(5)
	var pack := archer.get_tactics()
	for i in 80:
		pack.advance(EnemyTactics.REPLAN_INTERVAL)
		assert_false(pack.is_relocating(archer))
		if pack.is_relocating(archer):
			break

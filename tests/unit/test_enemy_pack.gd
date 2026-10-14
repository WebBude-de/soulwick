extends GutTest
## Group tactics (KONZEPT_RAEUME_V2 §6): rules of EnemyTactics and the slime packs of EnemyPack
## (packs of 3-5, hops in turn, landing marker, no damage in the air, never on a player, coop
## packs per target, bosses and champions stay out).

const ENEMY_SCENE_PATH := "res://enemies/enemy_base.tscn"
const SLIME := "res://enemies/data/slime.tres"
const SPLITTER := "res://enemies/data/splitter_slime.tres"
const SKELETON := "res://enemies/data/skeleton.tres"
const BOSS := "res://enemies/data/boss_slime_queen.tres"
const TEST_SAVE_PATH := "user://test_enemy_pack.cfg"

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


func _enemy(path: String, position: Vector2, container: Node, room := 10, champion := false) -> Enemy:
	var enemy: Enemy = (load(ENEMY_SCENE_PATH) as PackedScene).instantiate()
	enemy.data = load(path)
	enemy.apply_scaling(room, champion)
	enemy.position = position
	container.add_child(enemy)
	return enemy


## Largest angular gap between the enemies around center (TAU when there are none).
func _largest_gap(enemies: Array, center: Vector2) -> float:
	var angles: Array[float] = []
	for enemy: Variant in enemies:
		if is_instance_valid(enemy):
			angles.append(((enemy as Node2D).global_position - center).angle())
	if angles.size() < 2:
		return TAU
	angles.sort()
	var gap := angles[0] + TAU - angles[angles.size() - 1]
	for i in range(1, angles.size()):
		gap = maxf(gap, angles[i] - angles[i - 1])
	return gap


# --- Rules ---

func test_intensity_is_gentle_first_and_full_from_room_ten() -> void:
	assert_eq(EnemyTactics.intensity(1), EnemyTactics.START_INTENSITY, "room 1: weakest")
	assert_eq(EnemyTactics.intensity(EnemyTactics.FULL_ROOM), 1.0)
	assert_eq(EnemyTactics.intensity(80), 1.0, "stays full endlessly")
	var previous := -1.0
	for room in range(1, 12):
		var value := EnemyTactics.intensity(room)
		assert_true(value >= previous, "never falls (room %d)" % room)
		previous = value
	assert_lt(EnemyTactics.intensity(5), 0.5, "rooms 1-5 stay well below full strength")


func test_no_cut_off_in_the_first_rooms_or_without_flight() -> void:
	for room in range(1, EnemyTactics.CUT_OFF_FROM_ROOM):
		assert_eq(EnemyTactics.cut_off_count(5, room, 300.0), 0, "room %d" % room)
	assert_eq(EnemyTactics.cut_off_count(5, 20, 10.0), 0, "standing target: nobody cuts off")
	assert_eq(EnemyTactics.cut_off_count(1, 20, 300.0), 0, "a lone enemy chases")
	assert_between(EnemyTactics.cut_off_count(3, 20, 300.0), 1, 2, "a part, never all")
	assert_eq(EnemyTactics.cut_off_count(6, 20, 300.0), 2)


func test_ring_angles_spread_and_assignment_does_not_cross() -> void:
	var full := EnemyTactics.ring_angles(4, 0.0, 1.0)
	assert_eq(full.size(), 4)
	for i in range(1, 4):
		assert_almost_eq(full[i] - full[i - 1], TAU / 4.0, 0.001, "evenly around the target")
	var narrow := EnemyTactics.ring_angles(3, 1.0, EnemyTactics.MIN_SPREAD)
	assert_almost_eq(narrow[1], 1.0, 0.001, "one place on the reference angle")
	assert_lt(narrow[2] - narrow[0], TAU * EnemyTactics.MIN_SPREAD, "gentle: a narrow fan")
	# Members at -0.4, 0.1, 0.3 rad get the slots in the same order.
	var members := PackedFloat32Array([0.3, -0.4, 0.1])
	var slots := EnemyTactics.ring_angles(3, 0.0, 0.5)
	var assignment := EnemyTactics.assign_by_angle(members, slots, 0.0)
	assert_eq(Array(assignment), [2, 0, 1])


func test_approach_point_engages_inside_the_ring_and_circles_outside() -> void:
	var center := Vector2.ZERO
	assert_eq(EnemyTactics.approach_point(Vector2(50, 0), center, PI, 70.0), center, "inside the ring: straight at the target")
	var on_side := EnemyTactics.approach_point(Vector2(300, 0), center, 0.2, 70.0)
	assert_almost_eq(on_side.angle(), 0.2, 0.001, "close to its angle: walks to its place")
	# Its place is behind the target: it walks around, never through the target.
	var around := EnemyTactics.approach_point(Vector2(300, 0), center, PI, 70.0)
	assert_almost_eq(absf(around.angle()), EnemyTactics.ARC_STEP, 0.001, "one arc step around")
	assert_gt(around.length(), 70.0 - 0.01, "stays outside the ring on the way")


func test_cut_off_point_lies_ahead_of_the_fleeing_target() -> void:
	var flee := Vector2.RIGHT
	var ahead := EnemyTactics.cut_off_point(Vector2(250, 120), Vector2.ZERO, flee, 70.0, 160.0)
	assert_almost_eq(ahead.y, 0.0, 0.001, "steps onto the flight line")
	assert_between(ahead.x, 70.0, 160.0, "ahead of the target, at most the lead")
	var behind := EnemyTactics.cut_off_point(Vector2(-300, 0), Vector2.ZERO, flee, 70.0, 160.0)
	assert_ne(behind.y, 0.0, "a cutter behind the target walks around it")


func test_pack_sizes_are_three_to_five() -> void:
	assert_eq(EnemyTactics.pack_sizes(2), [] as Array[int], "too few for a pack")
	assert_eq(EnemyTactics.pack_sizes(3), [3] as Array[int])
	assert_eq(EnemyTactics.pack_sizes(5), [5] as Array[int])
	assert_eq(EnemyTactics.pack_sizes(6), [3, 3] as Array[int])
	assert_eq(EnemyTactics.pack_sizes(7), [4, 3] as Array[int])
	assert_eq(EnemyTactics.pack_sizes(11), [4, 4, 3] as Array[int])


func test_hop_landing_never_ends_on_the_target() -> void:
	var ring := 70.0
	for i in 16:
		var from := Vector2.from_angle(TAU * i / 16.0) * 130.0
		for slot in [0.0, PI * 0.5, PI, -PI * 0.5]:
			for velocity in [Vector2.ZERO, Vector2(180, 0), Vector2(0, -180)]:
				var landing := EnemyTactics.hop_landing(from, Vector2.ZERO, velocity, slot, ring, 1.0)
				assert_true(landing.length() >= ring * EnemyTactics.LAND_RING_SHARE - 0.01, "landing %s keeps away from the target" % landing)
				assert_true(from.distance_to(landing) <= EnemyTactics.HOP_DISTANCE.y + ring + 0.01, "a hop, not a teleport")


# --- Slime packs ---

func test_slimes_form_a_pack_and_hop_in_turn_next_to_the_player() -> void:
	var container := _container()
	var player := _fake(Vector2.ZERO)
	var slimes: Array[Enemy] = []
	for i in 4:
		slimes.append(_enemy(SLIME, Vector2(420 + i * 30, -60 + i * 40), container))
	var takeoffs: Array[int] = []
	var landings: Array[float] = []
	for slime in slimes:
		slime.ability_used.connect(func(enemy: Enemy, ability: StringName) -> void:
			if ability == &"hop":
				takeoffs.append(Engine.get_physics_frames())
			elif ability == &"hop_land":
				landings.append(enemy.global_position.distance_to(player.global_position)))
	var damage_in_air := false
	var marker_missing := false
	for i in 60 * 3:
		await wait_physics_frames(1)
		for slime in slimes:
			if slime.is_airborne():
				damage_in_air = damage_in_air or slime._attack_hitbox.is_active()
				var marker := slime.get_node_or_null(^"HopMarker") as Node2D
				marker_missing = marker_missing or marker == null or not marker.visible
	var pack := EnemyPack.of(container)
	assert_not_null(pack, "the room has a coordinator")
	assert_eq(pack.get_pack_count(), 1, "four slimes, one pack")
	assert_eq(pack.get_pack_mates(slimes[0]).size(), 4)
	assert_gte(takeoffs.size(), 4, "the pack hops")
	var min_gap := 1000
	for i in range(1, takeoffs.size()):
		min_gap = mini(min_gap, takeoffs[i] - takeoffs[i - 1])
	assert_gte(min_gap, floori(EnemyTactics.HOP_STAGGER * 60.0) - 1, "one after another, never all at once")
	assert_false(damage_in_air, "no damage in the air")
	assert_false(marker_missing, "the landing is marked while the slime flies")
	for distance in landings:
		assert_true(distance >= EnemyTactics.LAND_CLEARANCE - 0.5, "never lands on the player (%.0f px)" % distance)
	assert_lt(_largest_gap(slimes, player.global_position), PI * 1.25, "the pack spreads around the player")


func test_too_few_slimes_chase_alone() -> void:
	var container := _container()
	_fake(Vector2.ZERO)
	var a := _enemy(SLIME, Vector2(300, 0), container)
	var b := _enemy(SLIME, Vector2(300, 60), container)
	await wait_physics_frames(30)
	var pack := EnemyPack.of(container)
	assert_eq(pack.get_pack_count(), 0, "two slimes are no pack")
	assert_false(pack.is_pack_member(a))
	assert_false(pack.is_pack_member(b))


func test_coop_packs_are_formed_per_player() -> void:
	var container := _container()
	var left := _fake(Vector2(-500, 0))
	var right := _fake(Vector2(500, 0))
	var left_slimes: Array[Enemy] = []
	var right_slimes: Array[Enemy] = []
	for i in 3:
		left_slimes.append(_enemy(SLIME, Vector2(-250, -60 + i * 60), container))
		right_slimes.append(_enemy(SLIME, Vector2(250, -60 + i * 60), container))
	await wait_physics_frames(30)
	var pack := EnemyPack.of(container)
	assert_eq(pack.get_pack_count(), 2, "one pack per player")
	for slime in left_slimes:
		assert_eq(slime.get_target_node(), left)
		for mate in pack.get_pack_mates(slime):
			assert_has(left_slimes, mate, "no pack mixes the targets")
	for slime in right_slimes:
		assert_eq(slime.get_target_node(), right)


func test_dead_and_freed_members_leave_the_pack_and_split_slimes_join() -> void:
	var container := _container()
	_fake(Vector2.ZERO)
	var slimes: Array[Enemy] = []
	for i in 3:
		slimes.append(_enemy(SLIME, Vector2(380, -60 + i * 60), container, 16))
	var splitter := _enemy(SPLITTER, Vector2(420, 0), container, 16)
	await wait_physics_frames(20)
	var pack := EnemyPack.of(container)
	assert_eq(pack.get_pack_mates(splitter).size(), 4)
	splitter.health.take_damage(INF)
	slimes[0].queue_free()
	slimes[1].health.take_damage(INF)
	await wait_physics_frames(30)
	var minis: Array[Enemy] = []
	for child in container.get_children():
		if child is Enemy and (child as Enemy).data.id == &"mini_slime":
			minis.append(child)
	assert_eq(minis.size(), 2, "the splitter split")
	var mates := pack.get_pack_mates(slimes[2])
	assert_eq(mates.size(), 3, "the survivor and both mini slimes hop together")
	for mini in minis:
		assert_true(pack.is_pack_member(mini), "split slimes join the pack")


func test_bosses_and_champions_keep_their_behaviour() -> void:
	var container := _container()
	_fake(Vector2.ZERO)
	var boss := _enemy(BOSS, Vector2(300, 0), container, 30)
	var champion := _enemy(SKELETON, Vector2(-300, 0), container, 10, true)
	var minion := _enemy(SLIME, Vector2(0, 300), container, 10)
	await wait_physics_frames(5)
	assert_null(boss.get_tactics(), "bosses take no part")
	assert_null(champion.get_tactics(), "champions take no part")
	assert_not_null(minion.get_tactics(), "their minions do")
	boss.health.take_damage(INF)
	champion.health.take_damage(INF)
	await wait_physics_frames(2)

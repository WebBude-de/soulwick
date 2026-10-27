extends GutTest
## Flame mode (bug report 23.10.2026 #56d68b40, "Die Flamme bekommt basically nie Damage"): archers
## sent after the soul flame shot straight into a player standing beside it, so two defenders kept
## the flame almost untouched. A shooter whose line to its decoy is covered walks round it and shoots
## once the line is free (ShotLine); a player really in the line still blocks. Melee enemies on the
## one tile wide stairs walk straight at full speed (no creeping, no hops, EnemyPack.is_changing_level),
## so a group comes up together instead of one by one.

const ENEMY_SCENE: PackedScene = preload("res://enemies/enemy_base.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const ARCHER: EnemyData = preload("res://enemies/data/archer.tres")
const SLIME: EnemyData = preload("res://enemies/data/slime.tres")
const FLAME_ROOM := "res://dungeon/rooms/combat/flamme_schrein_crypt.tscn"
## Seconds the archer gets for a hit on the flame past the defender. TESTWERT
const SHOT_LIMIT := 8.0
## Seconds a slime group at the foot of the stairs gets to stand on the flame's plateau. TESTWERT
const CLIMB_LIMIT := 4.0

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_enemy_decoy_shots_save.cfg"


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()


func after_each() -> void:
	HitStop.reset()
	for node in get_children():
		if node is Projectile:
			node.queue_free()
	await wait_process_frames(1)


func _player(at: Vector2) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.global_position = at
	player.health.reset(99999.0)
	return player


func _flame(at: Vector2) -> SoulFlame:
	var flame := SoulFlame.new()
	flame.build(9999.0)
	add_child_autofree(flame)
	flame.global_position = at
	return flame


func test_a_player_on_the_line_covers_the_shot() -> void:
	var player := _player(Vector2(200, 200))
	var centre: Vector2 = ShotLine.hurt_circle(player)["centre"]
	var from := centre + Vector2(-300, 0)
	var to := centre + Vector2(80, 0)
	assert_eq(ShotLine.blocking_player(get_tree(), from, to, 4.0), player, "in the line")
	assert_null(ShotLine.blocking_player(get_tree(), from, to + Vector2(0, 160), 4.0), "beside the line")
	assert_null(ShotLine.blocking_player(get_tree(), from, centre + Vector2(-40, 0), 4.0), "behind the target")


func test_the_side_step_turns_the_line_off_the_blocker() -> void:
	var target := Vector2(0, 0)
	var from := Vector2(-300, 0)
	for blocker: Vector2 in [Vector2(-60, 10), Vector2(-60, -10)]:
		var goal := ShotLine.side_step_goal(from, target, blocker)
		var before := blocker.distance_to(Geometry2D.get_closest_point_to_segment(blocker, from, target))
		var after := blocker.distance_to(Geometry2D.get_closest_point_to_segment(blocker, goal, target))
		assert_gt(after, before + 10.0, "the new line runs farther from the blocker at %s (%s)" % [blocker, goal])
		assert_almost_eq(goal.distance_to(target), from.distance_to(target), 0.5, "same distance to the target")


## The measured case: a defender stands between the archer and the flame; before the fix every
## arrow hit him and the flame never.
func test_an_archer_shoots_the_flame_past_a_defender_beside_it() -> void:
	var flame := _flame(Vector2(500, 300))
	var archer: Enemy = ENEMY_SCENE.instantiate()
	archer.data = ARCHER
	archer.apply_scaling(6, false)
	add_child_autofree(archer)
	archer.global_position = flame.global_position + Vector2(-300, 120)
	EnemyDecoy.assign(archer, flame)
	# On the line archer -> flame, 60 px before the flame.
	var line := (flame.global_position - archer.global_position).normalized()
	var player := _player(flame.global_position - line * 60.0)
	var flame_hits := [0]
	var player_hits := [0]
	flame.hurtbox.hit_received.connect(func(_r: DamageResult, _d: DamageData) -> void: flame_hits[0] += 1)
	player.hurtbox.hit_received.connect(func(_r: DamageResult, _d: DamageData) -> void: player_hits[0] += 1)
	for frame in int(SHOT_LIMIT * 60.0):
		await wait_physics_frames(1)
		player.health.reset(99999.0)
		if flame_hits[0] > 0:
			break
	assert_gt(flame_hits[0], 0, "the archer hit the flame past the defender (defender hit %d times)" % player_hits[0])


func test_slimes_at_the_foot_of_the_stairs_come_up_together() -> void:
	var room := (load(FLAME_ROOM) as PackedScene).instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 56
	room.setup(6, RoomSequence.RoomType.COMBAT, -1, false, context)
	add_child_autofree(room)
	await wait_physics_frames(20)
	var layout := room.tiles.get_height_layout()
	var stairs: Vector2i = layout.stairs.keys()[0]
	var flame := _flame(room.tiles.to_global(room.tiles.map_to_local(stairs + Vector2i(0, -2))))
	# The player far off on the ground: the slimes are sent after the flame.
	_player(room.tiles.to_global(room.tiles.map_to_local(Vector2i(2, 6))))
	var slimes: Array[Enemy] = []
	for offset: Vector2i in [Vector2i(0, 2), Vector2i(-1, 2), Vector2i(1, 2), Vector2i(-1, 3), Vector2i(1, 3)]:
		var slime: Enemy = ENEMY_SCENE.instantiate()
		slime.data = SLIME
		slime.arena = room.get_arena()
		slime.apply_scaling(6, false)
		room.enemy_container.add_child(slime)
		slime.global_position = room.tiles.to_global(room.tiles.map_to_local(stairs + offset))
		EnemyDecoy.assign(slime, flame)
		slime.set_meta(&"flame_rolled", true)
		slimes.append(slime)
	flame.health.reset(99999.0)
	var up := {}
	for frame in int(CLIMB_LIMIT * 60.0):
		await wait_physics_frames(1)
		for slime in slimes:
			if is_instance_valid(slime) and HeightRules.level_of(slime) == HeightRules.PLATEAU:
				up[slime.get_instance_id()] = true
		if up.size() == slimes.size():
			break
	assert_eq(up.size(), slimes.size(), "all five slimes on the plateau within %.0f s" % CLIMB_LIMIT)
	room.queue_free()
	await wait_physics_frames(2)

extends GutTest
## Rooms from plans on a network client (MP3 with R2/R3, D-126, D-132, D-133): a remote room never
## spawns or completes by itself, it follows the host's wave state (RoomController.
## apply_remote_progress: the arena task bar counts, "Welle n/N" comes) and the host's completion;
## room goals other than the arena are mirrored (NetDungeon.objective_state_of /
## apply_objective_state). Uses a test save, never the real one.

const TEST_SAVE_PATH := "user://test_net_rooms.cfg"
const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.load_game()


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


## Arena room with skeletons only (like test_objective), marked as fought by the host.
func _remote_arena(room_index := 12) -> RoomController:
	var room := HALL.instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.ARENA
	room.forced_ambush = 0
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 31
	room.setup(room_index, RoomSequence.RoomType.COMBAT, -1, false, context)
	var spawner := room.get_node("EnemySpawner") as EnemySpawner
	spawner.biomes = [] as Array[BiomeData]
	spawner.extra_types = [] as Array[EnemyData]
	spawner.enemy_types = [SKELETON] as Array[EnemyData]
	spawner.spawn_weights = [1.0] as Array[float]
	room.remote_encounter = true
	add_child_autofree(room)
	return room


func test_a_remote_room_never_spawns_and_follows_the_host() -> void:
	var room := _remote_arena()
	var goal := ArenaObjective.attach_to(room)
	room.activate()
	room.start_encounter()
	await wait_process_frames(3)
	assert_false(room.is_encounter_started(), "the client's room waits for the host's fight")
	assert_eq(room.enemy_container.get_child_count(), 0, "no enemies of its own")

	watch_signals(room)
	watch_signals(goal)
	room.apply_remote_progress(1, 2, 3, 3)
	await wait_process_frames(2)
	assert_true(room.is_encounter_started(), "the host's first wave state starts the fight here")
	assert_eq(room.get_wave_progress(), Vector2i(1, 2))
	assert_eq(room.get_alive_enemy_count(), 3)
	assert_signal_not_emitted(room, "wave_started", "wave 1 comes with the encounter, not as a new wave")
	assert_eq(goal.label_text, DungeonTexts.t(&"OBJECTIVE_ARENA_WAVE", [1, 2, 3]), "task bar from the host's state")

	room.apply_remote_progress(1, 2, 0, 0)
	await wait_process_frames(2)
	assert_signal_emitted(goal, "wave_cleared", "between two waves: banner and gong")
	assert_true(goal.is_between_waves())
	room.check_completion()
	assert_eq(room.state, RoomController.State.ACTIVE, "a remote room never completes by itself")

	room.apply_remote_progress(2, 2, 4, 4)
	assert_signal_emitted_with_parameters(room, "wave_started", [room, 2, 2])
	room.apply_remote_progress(2, 2, 0, 0)
	room.check_completion()
	assert_eq(room.state, RoomController.State.ACTIVE, "still the host's call")
	room.complete_remotely()
	assert_eq(room.state, RoomController.State.CLEARED)
	assert_true(goal.is_finished() and goal.success, "the arena goal ends with the room")


func test_a_room_goal_is_mirrored_from_the_host() -> void:
	var host_goal: RoomObjective = autofree(RoomObjective.create(RoomObjective.SOULS))
	host_goal.set_count(4, 12)
	host_goal.set_time(27.0, true)
	host_goal.set_danger(true)
	host_goal.set_label("Seelen 4/12")
	host_goal.set_status("Eine Seele verblasst")
	var room: Node2D = add_child_autofree(Node2D.new())
	var goal := NetDungeon.apply_objective_state(room, NetDungeon.objective_state_of(host_goal))
	assert_not_null(goal, "the client gets a goal of its own")
	assert_eq(RoomObjective.of_room(room), goal, "attached to the room (DungeonUI binds the task bar)")
	assert_eq(goal.mode_id, RoomObjective.SOULS)
	assert_eq(goal.get_progress_text(), "4/12")
	assert_eq(RoomObjective.format_time(goal.time_left), "0:27")
	assert_true(goal.count_down and goal.danger)
	assert_eq(goal.label_text, "Seelen 4/12")
	assert_eq(goal.status_text, "Eine Seele verblasst")

	host_goal.set_ratio(0.5)
	host_goal.clear_time()
	host_goal.finish(true)
	assert_eq(NetDungeon.apply_objective_state(room, NetDungeon.objective_state_of(host_goal)), goal, "the same goal is updated")
	assert_eq(goal.get_progress_text(), "50 %")
	assert_false(goal.has_time())
	assert_true(goal.is_finished() and goal.success)


func test_the_arena_goal_follows_the_room_not_the_mirror() -> void:
	var room: Node2D = add_child_autofree(Node2D.new())
	var arena := RoomObjective.attach(room, ArenaObjective.new())
	var host_goal: RoomObjective = autofree(RoomObjective.create(RoomObjective.FLAME))
	host_goal.set_label("Flamme 70 %")
	assert_null(NetDungeon.apply_objective_state(room, NetDungeon.objective_state_of(host_goal)))
	assert_eq(RoomObjective.of_room(room), arena)
	assert_ne(arena.label_text, "Flamme 70 %")
	assert_null(NetDungeon.apply_objective_state(room, []), "bad data is ignored")

extends GutTest
## Gold pickups must always reach the player (regression: coins orbiting the player forever).

const PLAYER_SCENE := preload("res://player/player.tscn")
const PICKUP_SCENE := preload("res://economy/gold_pickup.tscn")

const TEST_SAVE_PATH := "user://test_gold_pickup_save.cfg"

var _player: Player
var _old_save_path: String


func before_all() -> void:
	# Ending a run writes the save file; keep the real one untouched.
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()
	_player = add_child_autofree(PLAYER_SCENE.instantiate())
	_player.set_physics_process(false)


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func _spawn_pickup(offset: Vector2) -> GoldPickup:
	var pickup: GoldPickup = PICKUP_SCENE.instantiate()
	pickup.amount = 3
	add_child_autofree(pickup)
	pickup.global_position = _player.global_position + offset
	return pickup


func test_pickups_from_all_directions_are_collected() -> void:
	for i in 8:
		_spawn_pickup(Vector2.from_angle(TAU * i / 8.0) * 300.0)
	await wait_physics_frames(150)
	assert_eq(RunManager.get_run_gold(), 24, "all eight coins arrived within 2.5 s")


func test_pickup_reaches_a_moving_player() -> void:
	_spawn_pickup(Vector2(400, 0))
	for i in 150:
		_player.global_position += Vector2(0, 2)
		await wait_physics_frames(1)
	assert_eq(RunManager.get_run_gold(), 3)

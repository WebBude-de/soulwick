extends GutTest
## Stone guardians (Lichtfeuer, RAEUME §3.9; before A9): frozen and vulnerable in a light
## circle, stone and advancing in the dark, a wind-up is cut off by the light, a started leap goes on;
## in Lichtfeuer only the fires hold them, not the players' own circles. The mode itself is tested in
## test_mode_rooms.gd.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const GUARDIAN_SCENE: PackedScene = preload("res://enemies/variants/stone_guardian.tscn")
const GUARDIAN_DATA: EnemyData = preload("res://enemies/data/stone_guardian.tres")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_stone_guardian_save.cfg"


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()


func after_each() -> void:
	HitStop.reset()
	await wait_process_frames(1)


func _guardian(at: Vector2) -> StoneGuardian:
	var guardian := GUARDIAN_SCENE.instantiate() as StoneGuardian
	guardian.data = GUARDIAN_DATA
	guardian.apply_scaling(8, false)
	add_child_autofree(guardian)
	guardian.global_position = at
	guardian.set_physics_process(false)
	return guardian


func _player(at: Vector2, drawn_radius := 300.0) -> Player:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.global_position = at
	player.set_physics_process(false)
	LightQuery.set_player_radius(player, drawn_radius)
	return player


func _hit(source: Node, amount := 5.0) -> DamageData:
	var hit := DamageData.new()
	hit.amount = amount
	hit.source = source
	hit.hit_id = DamageData.next_hit_id()
	return hit


# --- Rules ---

func test_guardian_numbers() -> void:
	assert_eq(LightfireRules.guardian_count(0.0, 1), 2)
	assert_eq(LightfireRules.guardian_count(0.99, 1), 4)
	assert_eq(LightfireRules.guardian_count(0.0, 3), 4, "+1 per extra player (MP5 parameter)")
	assert_true(LightfireRules.guardian_frozen(true, false, 0.0), "light freezes at once")
	assert_true(LightfireRules.guardian_frozen(false, true, LightfireRules.GUARDIAN_THAW_DELAY * 0.5), "short dark: still frozen")
	assert_false(LightfireRules.guardian_frozen(false, true, LightfireRules.GUARDIAN_THAW_DELAY), "then it moves")
	assert_false(LightfireRules.guardian_frozen(false, false, 0.0))
	assert_true(LightfireRules.guardian_vulnerable(true))
	assert_false(LightfireRules.guardian_vulnerable(false))


# --- The guardian ---

func test_dark_means_stone_light_means_frozen_and_vulnerable() -> void:
	var guardian := _guardian(Vector2(1000, 0))
	var player := _player(Vector2(0, 0))
	assert_true(guardian.hurtbox.is_invulnerable(), "a dormant statue takes nothing")
	guardian.activate()
	assert_true(guardian.is_frozen(), "wakes as a frozen statue")
	assert_false(guardian.is_in_light(), "far from the player: dark")
	guardian.step_light(LightfireRules.GUARDIAN_THAW_DELAY + 0.01, false)
	assert_false(guardian.is_frozen(), "the dark wakes it")
	assert_true(guardian.hurtbox.is_invulnerable(), "in the dark it is stone")
	var health := guardian.health.get_health()
	watch_signals(guardian.hurtbox)
	var result := guardian.hurtbox.receive_hit(_hit(player))
	assert_true(result.blocked)
	assert_eq(guardian.health.get_health(), health, "no damage in the dark")
	assert_signal_emitted(guardian.hurtbox, "deflected", "the player sees the hit bounce off")
	# The player walks up: its own light circle holds the guardian.
	player.global_position = guardian.global_position + Vector2(150, 0)
	assert_true(guardian.is_in_light())
	guardian.step_light(0.016, guardian.is_in_light())
	assert_true(guardian.is_frozen())
	assert_false(guardian.hurtbox.is_invulnerable(), "frozen = vulnerable")
	guardian.hurtbox.receive_hit(_hit(player, 5.0))
	assert_almost_eq(guardian.health.get_health(), health - 5.0, 0.01)


func test_frozen_guardian_does_not_move() -> void:
	var guardian := _guardian(Vector2(0, 0))
	_player(Vector2(100, 0))
	guardian.activate()
	var start := guardian.global_position
	guardian.set_physics_process(true)
	await wait_physics_frames(10)
	assert_true(guardian.is_frozen())
	assert_eq(guardian.global_position, start, "in the light it stands still")


func test_light_cuts_off_a_wind_up_but_not_a_leap() -> void:
	var guardian := _guardian(Vector2(0, 0))
	var player := _player(Vector2(330, 0))
	guardian.activate()
	guardian.step_light(1.0, false)
	assert_false(guardian.is_frozen())
	# In the dark and in reach: the leap's wind-up (yellow circle on the player).
	guardian.set_physics_process(true)
	await wait_physics_frames(3)
	assert_eq(guardian._state, Enemy.State.TELEGRAPH, "winds up the leap")
	assert_true(guardian._telegraph_circle.visible, "the landing spot is marked")
	guardian.set_physics_process(false)
	guardian.step_light(0.016, true)
	assert_true(guardian.is_frozen())
	assert_ne(guardian._state, Enemy.State.TELEGRAPH, "the light cuts the wind-up off")
	assert_false(guardian._telegraph_circle.visible)
	# A started leap goes on, even into the light.
	guardian.step_light(1.0, false)
	guardian._state = Enemy.State.LEAP
	guardian.step_light(0.016, true)
	assert_false(guardian.is_frozen(), "committed to the leap")
	assert_true(is_instance_valid(player))


func test_guardians_never_fall_and_ignore_knockback() -> void:
	assert_false(ChasmRules.can_enemy_fall(GUARDIAN_DATA, false), "heavy stone")
	assert_eq(GUARDIAN_DATA.knockback_resistance, 1.0)
	assert_eq(GUARDIAN_DATA.special, EnemyData.Special.LEAP_SLAM)


func test_lightfire_guardians_ignore_the_players_own_light() -> void:
	var guardian := _guardian(Vector2(0, 0))
	guardian.player_light_counts = false
	var player := _player(Vector2(100, 0))
	guardian.activate()
	assert_false(guardian.is_in_light(), "the player's circle does not hold it")
	guardian.step_light(LightfireRules.GUARDIAN_THAW_DELAY + 0.01, guardian.is_in_light())
	assert_false(guardian.is_frozen(), "it walks on in the player's light")
	var torch := RoomTorch.new()
	torch.build(Color.WHITE, LightfireRules.FIRE_LIGHT_RADIUS)
	add_child_autofree(torch)
	torch.global_position = guardian.global_position + Vector2(0, 40)
	torch.ignite(player)
	assert_true(guardian.is_in_light(), "a fire holds it")
	guardian.step_light(0.016, guardian.is_in_light())
	assert_true(guardian.is_frozen())
	assert_false(guardian.hurtbox.is_invulnerable(), "in the fire's light it can be broken")

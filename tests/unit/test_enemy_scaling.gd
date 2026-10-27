extends GutTest
## Enemy scaling per five-room block (D-011, retuned D-074, D-154, D-210, D-213).


func test_block_index() -> void:
	assert_eq(EnemyScaling.get_block(1), 0)
	assert_eq(EnemyScaling.get_block(5), 0)
	assert_eq(EnemyScaling.get_block(6), 1)
	assert_eq(EnemyScaling.get_block(26), 5)


func test_first_block_is_unscaled() -> void:
	assert_almost_eq(EnemyScaling.health_multiplier(3, false), 1.0, 0.0001)
	assert_almost_eq(EnemyScaling.damage_multiplier(3, false), 1.0, 0.0001)
	assert_almost_eq(EnemyScaling.cooldown_multiplier(3), 1.0, 0.0001)
	assert_almost_eq(EnemyScaling.speed_multiplier(3), 1.0, 0.0001)


func test_scaling_compounds_per_block() -> void:
	assert_almost_eq(EnemyScaling.health_multiplier(11, false), 1.17 * 1.17, 0.0001)
	assert_almost_eq(EnemyScaling.damage_multiplier(11, false), 1.11 * 1.11, 0.0001)


func test_tempo_limits() -> void:
	assert_almost_eq(EnemyScaling.cooldown_multiplier(500), 0.55, 0.0001)
	assert_almost_eq(EnemyScaling.telegraph_multiplier(500), 0.7, 0.0001)
	assert_almost_eq(EnemyScaling.speed_multiplier(500), 1.5, 0.0001)


func test_champion_factor() -> void:
	assert_almost_eq(EnemyScaling.health_multiplier(5, true), 6.0, 0.0001)
	assert_almost_eq(EnemyScaling.damage_multiplier(5, true), 1.7, 0.0001)

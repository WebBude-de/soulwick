extends GutTest
## Effective stat formulas (D-019, D-025, D-033, DECISIONS §6).


func test_raw_damage_adds_flat_then_percent() -> void:
	# Sword 12 + Krafttraining 2, two times +10 % global damage.
	assert_almost_eq(StatCalculator.compute_raw_damage(12.0, 2.0, 0.2), 16.8, 0.0001)


func test_raw_damage_applies_context_multiplier() -> void:
	assert_almost_eq(StatCalculator.compute_raw_damage(8.0, 0.0, 0.0, 0.5), 4.0, 0.0001)


func test_attack_rate_percent_bonus_is_additive() -> void:
	# Two stacks of +15 % on 1.5/s -> 1.5 * 1.3
	assert_almost_eq(StatCalculator.compute_attack_rate(1.5, 0.0, 0.3), 1.95, 0.0001)


func test_attack_cooldown_is_inverse_rate() -> void:
	assert_almost_eq(StatCalculator.attack_cooldown(0.8), 1.25, 0.0001)
	assert_eq(StatCalculator.attack_cooldown(0.0), INF)


func test_radius_bonus_matches_gdd_example() -> void:
	# Staff 45 px with three stacks of +20 % -> 72 px.
	assert_almost_eq(StatCalculator.compute_radius(45.0, 0.6), 72.0, 0.0001)

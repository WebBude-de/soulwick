class_name StatCalculator
extends RefCounted
## Shared formulas for effective attack values. Attacks and UI (weapon comparison) must both use these (D-034).
## Upgrade lookups are added in M3; callers pass the summed bonuses.


## D_raw = (D_base + sum(flat)) * (1 + sum(percent)) * product(context)
static func compute_raw_damage(base_damage: float, flat_bonus_sum := 0.0, percent_bonus_sum := 0.0, context_multiplier := 1.0) -> float:
	return (base_damage + flat_bonus_sum) * (1.0 + percent_bonus_sum) * context_multiplier


## R_eff in attacks per second (D-025); percent bonuses are additive.
static func compute_attack_rate(base_rate: float, flat_rate_bonus_sum := 0.0, percent_rate_bonus_sum := 0.0) -> float:
	return (base_rate + flat_rate_bonus_sum) * (1.0 + percent_rate_bonus_sum)


static func attack_cooldown(attack_rate: float) -> float:
	if attack_rate <= 0.0:
		return INF
	return 1.0 / attack_rate


## AOE radius bonuses are additive percentages (D-033).
static func compute_radius(base_radius: float, percent_bonus_sum := 0.0) -> float:
	return base_radius * (1.0 + percent_bonus_sum)

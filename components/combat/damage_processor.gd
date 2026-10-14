class_name DamageProcessor
extends RefCounted
## Single authority that turns a raw hit into shield and HP loss for players and enemies alike (D-018).
## Order: blocked check -> round once to 0.5 -> shield first -> HP.

const DAMAGE_STEP := 0.5
const MIN_DAMAGE := 0.5


static func round_to_step(value: float) -> float:
	return DAMAGE_STEP * roundf(value / DAMAGE_STEP)


## D_hit = 0.5 * round(2 * max(0, D_raw)); any positive raw damage deals at least 0.5.
static func round_damage(raw_amount: float) -> float:
	if raw_amount <= 0.0:
		return 0.0
	return maxf(MIN_DAMAGE, round_to_step(raw_amount))


## Portion of an already rounded hit that the shield absorbs.
static func shield_portion(amount: float, shield_value: float) -> float:
	return clampf(shield_value, 0.0, maxf(0.0, amount))


static func process_hit(damage: DamageData, health: HealthComponent, shield: ShieldComponent, is_blocked: bool) -> DamageResult:
	var result := DamageResult.new()
	if is_blocked or health == null or health.is_dead():
		result.blocked = true
		return result

	result.amount = round_damage(damage.amount)
	if result.amount <= 0.0:
		return result

	var shield_value := shield.get_shield() if shield != null else 0.0
	var to_shield := shield_portion(result.amount, shield_value)
	if to_shield > 0.0:
		result.shield_damage = shield.absorb(to_shield)
	var to_health := result.amount - result.shield_damage
	if to_health > 0.0:
		result.health_damage = health.take_damage(to_health)
	result.killed = health.is_dead()
	return result

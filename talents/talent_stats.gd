class_name TalentStats
extends RefCounted
## What one player's talents add up to (TalentEffects.resolve): plain numbers and switches the
## player, its weapons, spells (KE7) and the revive rules read. A fresh TalentStats is neutral (no
## talents), so code may always ask. Formulas follow D-019: percent bonuses add up within the
## "Talente" source and add to the other percent bonuses; situational bonuses multiply.

var move_speed_percent := 0.0
## Seconds taken off the dash cooldown (TalentEffects.dash_cooldown clamps the result).
var dash_cooldown_reduction := 0.0
var dash_charges := 1
var max_health_bonus := 0.0
## Fraction taken off knockback and stun duration (Standfest), at most TalentEffects.MAX_STAGGER_REDUCTION.
var stagger_reduction := 0.0
## Damage bonus for TalentEffects.EVASION_TIME after a dash (Ausweichkunst).
var evasion_damage_percent := 0.0
## Damage bonus against champions and shield bearers (Schildbrecher).
var breaker_damage_percent := 0.0
var spell_damage_percent := 0.0
var spell_cooldown_percent := 0.0
var spell_slots := 0
var unlocked_spells: Array[StringName] = []
var equipped_spells: Array[StringName] = []
var second_heart := false
var ember_heart := false
var wind_runner := false

## Weapon effects: {"effect": TalentDef.Effect, "value": float (level × value), "talent": TalentDef}.
var _weapon_entries: Array[Dictionary] = []


func add_weapon_entry(talent: TalentDef, total_value: float) -> void:
	_weapon_entries.append({"effect": talent.effect, "value": total_value, "talent": talent})


## Additive damage percent for an attack with these weapon tags (Wucht, Stab-Meister).
func damage_percent(weapon_tags: Array[StringName]) -> float:
	return _weapon_sum(TalentDef.Effect.DAMAGE_PERCENT, weapon_tags)


## Additive attack-rate percent for a weapon with these tags (Flinke Klinge).
func attack_rate_percent(weapon_tags: Array[StringName]) -> float:
	return _weapon_sum(TalentDef.Effect.ATTACK_RATE_PERCENT, weapon_tags)


## Factor for knockback and stun duration (1 = unchanged).
func stagger_multiplier() -> float:
	return 1.0 - clampf(stagger_reduction, 0.0, TalentEffects.MAX_STAGGER_REDUCTION)


## Factor for spell cooldowns (1 = unchanged), never below TalentEffects.MIN_SPELL_COOLDOWN_FACTOR.
func spell_cooldown_multiplier() -> float:
	return maxf(TalentEffects.MIN_SPELL_COOLDOWN_FACTOR, 1.0 - spell_cooldown_percent)


## No talent changes anything.
func is_neutral() -> bool:
	return is_zero_approx(move_speed_percent) and is_zero_approx(dash_cooldown_reduction) and dash_charges == 1 \
		and is_zero_approx(max_health_bonus) and is_zero_approx(stagger_reduction) and is_zero_approx(evasion_damage_percent) \
		and is_zero_approx(breaker_damage_percent) and is_zero_approx(spell_damage_percent) \
		and is_zero_approx(spell_cooldown_percent) and spell_slots == 0 and unlocked_spells.is_empty() \
		and not second_heart and not ember_heart and not wind_runner and _weapon_entries.is_empty()


func _weapon_sum(effect: TalentDef.Effect, weapon_tags: Array[StringName]) -> float:
	var total := 0.0
	for entry in _weapon_entries:
		var talent: TalentDef = entry["talent"]
		if entry["effect"] == effect and talent.applies_to(weapon_tags):
			total += float(entry["value"])
	return total

class_name StoneGuardianHurtbox
extends Hurtbox
## Hurtbox of a stone guardian (A9): like every hurtbox, but a hit that bounces off the stone (the
## guardian stands in the dark and is invulnerable) is reported, so the guardian can show it
## (spark, "clank"). One report per attack instance (hit id); the damage rules stay DamageProcessor's.

signal deflected(damage: DamageData)

var _last_deflected_id := -1


func receive_hit(damage: DamageData) -> DamageResult:
	var result := super.receive_hit(damage)
	if result.blocked and is_invulnerable() and damage != null and health != null and not health.is_dead():
		if damage.hit_id == 0 or damage.hit_id != _last_deflected_id:
			_last_deflected_id = damage.hit_id
			deflected.emit(damage)
	return result

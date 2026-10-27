class_name DamageResult
extends RefCounted
## Outcome of DamageProcessor.process_hit().

## True if the hit had no effect at all (invulnerable or already dead target).
var blocked := false
## Rounded damage of the hit (D_hit).
var amount := 0.0
var shield_damage := 0.0
var health_damage := 0.0
var killed := false
## False when this kill must not pay ON_KILL rewards (heal, shield): minions of a boss
## (BossRules.BOSS_MINIONS_GRANT_KILL_REWARDS). Set by the dying enemy; kill counts stay untouched.
var grants_kill_rewards := true


## A hit is effective if it removed shield or HP. Only effective hits start player hit I-frames (D-017).
func is_effective() -> bool:
	return not blocked and shield_damage + health_damage > 0.0

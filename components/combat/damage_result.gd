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


## A hit is effective if it removed shield or HP. Only effective hits start player hit I-frames (D-017).
func is_effective() -> bool:
	return not blocked and shield_damage + health_damage > 0.0

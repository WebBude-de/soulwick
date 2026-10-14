class_name RoomTorchHurtbox
extends Hurtbox
## Hurtbox of a torch in the torch room (A9): lies on ENEMY_HURTBOX, so every player attack (swing,
## projectile, blast) reaches it. A hit lights the torch and does no damage: the result is always
## "blocked", so the hit counts for nothing else (no damage number, no on-hit effects) and a
## projectile flies on. Enemies never light torches.

var torch: RoomTorch = null


func _ready() -> void:
	super._ready()
	collision_layer = PhysicsLayers.ENEMY_HURTBOX
	collision_mask = 0


func receive_hit(damage: DamageData) -> DamageResult:
	var result := DamageResult.new()
	result.blocked = true
	if damage != null and accepts(damage) and torch != null and is_instance_valid(torch):
		torch.ignite(damage.source)
	return result


## Any hit that does not come from an enemy (players, their projectiles and blasts, barrels).
static func accepts(damage: DamageData) -> bool:
	return not (damage.source != null and is_instance_valid(damage.source) and damage.source is Enemy)

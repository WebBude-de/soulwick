class_name EscortHurtbox
extends Hurtbox
## Hurtbox of the lost villager (escort mode, R4a): lies on PLAYER_HURTBOX, so the telegraphed
## attacks of enemies (melee hitbox, projectiles, blasts) hit him like a player. Only hits whose
## source is an enemy count (accepts: traps, barrels and players pass through); each one costs the
## villager one heart, whatever its damage, then he is briefly invulnerable.

var villager: LostVillager = null


func _ready() -> void:
	super._ready()
	collision_layer = PhysicsLayers.PLAYER_HURTBOX
	collision_mask = 0


func receive_hit(damage: DamageData) -> DamageResult:
	var result := DamageResult.new()
	if damage == null or villager == null or not accepts(damage) or is_invulnerable() or not villager.is_alive():
		result.blocked = true
		return result
	result.amount = 1.0
	result.health_damage = 1.0
	result.killed = villager.hearts <= 1
	villager.take_hit(damage)
	hit_received.emit(result, damage)
	return result


## Only damage from an enemy (directly or through its projectile or blast, source = the enemy).
static func accepts(damage: DamageData) -> bool:
	return damage != null and damage.source != null and is_instance_valid(damage.source) and damage.source is Enemy

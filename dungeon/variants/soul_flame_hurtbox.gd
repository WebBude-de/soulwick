class_name SoulFlameHurtbox
extends Hurtbox
## Hurtbox of the soul flame (A7): lies on PLAYER_HURTBOX, so the telegraphed attacks of enemies
## (melee hitbox, projectiles, blasts) hit it like a player. Only hits whose source is an enemy
## count; traps, barrels and other room hazards pass through without effect.


func _ready() -> void:
	super._ready()
	collision_layer = PhysicsLayers.PLAYER_HURTBOX
	collision_mask = 0


func receive_hit(damage: DamageData) -> DamageResult:
	if damage == null or not accepts(damage):
		var ignored := DamageResult.new()
		ignored.blocked = true
		return ignored
	return super.receive_hit(damage)


## Only damage from an enemy (directly or through its projectile or blast, source = the enemy).
static func accepts(damage: DamageData) -> bool:
	return damage.source != null and is_instance_valid(damage.source) and damage.source is Enemy

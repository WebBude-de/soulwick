class_name SecretWallHurtbox
extends Hurtbox
## Hurtbox of a cracked wall (A10): lies on both hurtbox layers, so the player's area hits and the
## barrels' blast (ENEMY_HURTBOX) and the blasts of bombers and other enemies (PLAYER_HURTBOX) reach
## it. It never takes damage; it only reports: an explosion (SecretRules.breaks_wall) -> struck, any
## other hit -> tapped (dust, hint). Every hit counts as blocked, so attacks pass on unchanged.

signal struck(damage: DamageData)
signal tapped(damage: DamageData)


func _ready() -> void:
	super._ready()
	collision_layer = PhysicsLayers.ENEMY_HURTBOX | PhysicsLayers.PLAYER_HURTBOX
	collision_mask = 0


func receive_hit(damage: DamageData) -> DamageResult:
	var result := DamageResult.new()
	result.blocked = true
	if damage == null:
		return result
	if SecretRules.breaks_wall(damage):
		struck.emit(damage)
	elif damage.source is Player or (damage.source == null and damage.tags.has(&"melee")):
		tapped.emit(damage)
	return result

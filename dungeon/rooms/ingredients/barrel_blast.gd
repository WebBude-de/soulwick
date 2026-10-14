class_name BarrelBlast
extends Blast
## Blast of an explosive barrel: the usual Blast (warning circle, player damage, explosion art,
## light, sound) plus a second hit with its own damage on the enemy hurtbox layer, which also holds
## enemies, crates and barrels (chain reaction). Hits players and enemies alike, so it works the
## same for any number of players.

var enemy_damage := 30.0


static func create(blast_radius: float, player_damage: float, damage_to_enemies: float, warning_delay: float) -> BarrelBlast:
	var blast := BarrelBlast.new()
	blast.radius = blast_radius
	blast.damage = player_damage
	blast.enemy_damage = damage_to_enemies
	blast.delay = warning_delay
	blast.target_mask = PhysicsLayers.PLAYER_HURTBOX
	blast.color = Color(1.0, 0.5, 0.15)
	blast.shake = 7.0
	return blast


func _detonate() -> void:
	super()
	var hit := DamageData.new()
	hit.amount = enemy_damage
	hit.tags.assign([&"explosion"])
	hit.hit_id = DamageData.next_hit_id()
	AreaDamage.apply(self, global_position, radius, PhysicsLayers.ENEMY_HURTBOX, hit, knockback)

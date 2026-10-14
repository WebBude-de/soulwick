class_name EnemyDecoy
extends RefCounted
## Decoy targets for enemies (A7 soul flame): an enemy with a living decoy attacks the decoy instead
## of the nearest player. Stored as metadata on the enemy, so enemy_base.gd needs no new field; the
## integrator only routes the target choice through choose_target() (hook in the A7 report).
## A decoy is any Node2D with is_alive() whose hurtbox lies on PhysicsLayers.PLAYER_HURTBOX, so the
## enemy's normal telegraphed attacks (melee hitbox, projectiles, specials) hit it unchanged.
## Without a living decoy the choice is the usual nearest living player (EnemyTargeting, D-088).

const META := &"decoy_target"


static func assign(enemy: Node, decoy: Node2D) -> void:
	if enemy != null and is_instance_valid(enemy) and decoy != null:
		enemy.set_meta(META, decoy)


static func clear(enemy: Node) -> void:
	if enemy != null and is_instance_valid(enemy) and enemy.has_meta(META):
		enemy.remove_meta(META)


## The enemy's decoy while it lives, else null.
static func get_decoy(enemy: Node) -> Node2D:
	if enemy == null or not is_instance_valid(enemy) or not enemy.has_meta(META):
		return null
	var decoy: Variant = enemy.get_meta(META)
	if not EnemyTargeting.is_alive(decoy):
		return null
	return decoy as Node2D


static func has_decoy(enemy: Node) -> bool:
	return get_decoy(enemy) != null


## Target of an enemy: its living decoy, otherwise the nearest living player (keeping current
## unless another player is clearly closer, EnemyTargeting.choose).
static func choose_target(enemy: Node2D, players: Array, current: Node2D) -> Node2D:
	var decoy := get_decoy(enemy)
	if decoy != null:
		return decoy
	var current_player: Node2D = current if current != null and is_instance_valid(current) and not _is_decoy_of(enemy, current) else null
	return EnemyTargeting.choose(players, enemy.global_position, current_player)


static func _is_decoy_of(enemy: Node, node: Node) -> bool:
	return enemy != null and enemy.has_meta(META) and is_same(enemy.get_meta(META), node)

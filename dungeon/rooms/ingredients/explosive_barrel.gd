class_name ExplosiveBarrel
extends Breakable
## Explosive barrel (ingredient "Explosionsfässer", KONZEPT_RAEUME §3.3): a hit that breaks it lights
## the fuse; after FUSE_TIME it explodes through BarrelBlast with the usual warning circle. The blast
## hurts players and enemies and breaks crates and other barrels in reach, so barrels set each
## other off (chain reaction). Later it also opens cracked walls (A10). No loot.

## Warning time between the breaking hit and the explosion (D-021 telegraph). TESTWERT
const FUSE_TIME := 0.7
## Blast radius in world px. TESTWERT
const BLAST_RADIUS := 96.0
## Damage to players (half a heart, like a bomber). TESTWERT
const PLAYER_DAMAGE := 1.0
## Damage to enemies, crates and other barrels (about a skeleton's health). TESTWERT
const ENEMY_DAMAGE := 30.0
const FUSE_FPS := 8.0

var _lit := false


func _ready() -> void:
	_sprite = $Sprite
	_sprite.texture = IngredientArt.get_texture("explosive_barrel")
	super()


func is_lit() -> bool:
	return _lit


## Breaking hit: no loot, the fuse burns and the barrel explodes.
func _on_broken() -> void:
	if _lit:
		return
	_lit = true
	_hurtbox.set_deferred("monitorable", false)
	_sprite.texture = IngredientArt.get_texture("explosive_barrel_fuse_4f")
	_sprite.hframes = IngredientArt.FRAMES
	Sfx.play_at(self, &"fuse", global_position)
	var blast := BarrelBlast.create(BLAST_RADIUS, PLAYER_DAMAGE, ENEMY_DAMAGE, FUSE_TIME)
	get_parent().add_child(blast)
	blast.global_position = global_position + Vector2(0, -14)
	var tween := create_tween()
	tween.tween_method(_show_fuse_frame, 0.0, 1.0, FUSE_TIME)
	tween.tween_callback(_explode)


func _show_fuse_frame(progress: float) -> void:
	_sprite.frame = int(progress * FUSE_FPS * FUSE_TIME) % IngredientArt.FRAMES


func _explode() -> void:
	set_deferred("collision_layer", 0)
	queue_free()


func _drop() -> void:
	pass

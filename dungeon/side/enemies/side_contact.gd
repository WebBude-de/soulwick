class_name SideContact
extends Hitbox
## Contact hitbox of a side enemy (SV4, D-195): hurts like any Hitbox, but holds back for a player
## the enemy spares right now (falling onto a stompable enemy), because the player side then defeats
## the enemy (SideEnemy.on_stomped) and must not be hurt first. A spared player is not marked as
## hit, so the same attack instance still hurts if the stomp does not happen after all.

## func(player: Player) -> bool; true = do not hurt this player now.
var spares: Callable


func _handle_contact(hurtbox: Hurtbox) -> void:
	var player := hurtbox.get_parent() as Player
	if player != null and spares.is_valid() and bool(spares.call(player)):
		return
	super._handle_contact(hurtbox)

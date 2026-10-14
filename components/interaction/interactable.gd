class_name Interactable
extends Area2D
## Something the player can use with E (dungeon entrance, fountain, shop, portal, ...).
## Sits on the "interaction" physics layer; the player's InteractionArea detects it.

signal interacted(player: Player)

@export var prompt := "Benutzen"
@export var enabled := true


func _ready() -> void:
	collision_layer = PhysicsLayers.INTERACTION
	collision_mask = 0
	monitoring = false
	monitorable = true


func is_available() -> bool:
	return enabled


func interact(player: Player) -> void:
	if enabled:
		interacted.emit(player)

class_name SideSpikeHedgehog
extends SideEnemy
## Spike hedgehog of a side segment (SV4, D-195): walks its platform slowly with its spikes up. It
## refuses a stomp: it lands in the spikes (contact damage at once, the spikes bristle), and touching
## it hurts like every side enemy. The player jumps over it or uses a weapon.

const DATA: EnemyData = preload("res://dungeon/side/enemies/data/side_spike_hedgehog.tres")
## TESTWERTE (SV4): patrol and chase speed (px/s), slower than a skeleton.
const SPEEDS := Vector2(38.0, 55.0)
const BODY := Vector2(28, 20)


func get_body_size() -> Vector2:
	return BODY


func _default_data() -> EnemyData:
	return DATA


func _uses_side_art() -> bool:
	return true


func _walk_speeds() -> Vector2:
	return SPEEDS


func _placeholder_look() -> int:
	return SideEnemyPlaceholder.Look.SPIKE_HEDGEHOG


func _on_rejected(player: Player) -> void:
	super._on_rejected(player)
	if _placeholder != null:
		_placeholder.bristle()

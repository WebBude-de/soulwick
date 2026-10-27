class_name SideShieldBearer
extends SideEnemy
## Shield bearer of a side segment (SV4, D-195): a skeleton with a shield in front. Only a stomp
## (from above) or a weapon beats it; running into it hurts like every side enemy, with a strong
## push back and a flash. Walks and chases like a skeleton, a bit slower.
## Until its art lies in art/ it is the skeleton's frames tinted steel blue plus a drawn shield.

const DATA: EnemyData = preload("res://dungeon/side/enemies/data/side_shield_bearer.tres")
## TESTWERTE (SV4): patrol and chase speed (px/s).
const SPEEDS := Vector2(45.0, 80.0)
const BODY := Vector2(24, 44)


func get_body_size() -> Vector2:
	return BODY


func _default_data() -> EnemyData:
	return DATA


func _uses_side_art() -> bool:
	return true


func _walk_speeds() -> Vector2:
	return SPEEDS


func _build_placeholder() -> void:
	_sprite.modulate = data.placeholder_color
	super._build_placeholder()


func _placeholder_look() -> int:
	return SideEnemyPlaceholder.Look.SHIELD


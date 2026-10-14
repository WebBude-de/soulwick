class_name UpgradeData
extends Resource
## Static upgrade definition (.tres). Stacks live in UpgradeManager (runtime state).
## Numeric values are TESTWERTE (DECISIONS §4), stack limits are VERBINDLICH (D-029).

enum Category { ATTRIBUTE, MECHANIC, EFFECT }
enum Effect {
	DAMAGE_PERCENT,
	DAMAGE_FLAT,
	ATTACK_RATE_PERCENT,
	PROJECTILE_SPEED_PERCENT,
	SHIELD_GAIN,
	PIERCE,
	WALL_BOUNCE,
	EXTRA_PROJECTILE,
	SWING_ANGLE_PERCENT,
	AOE_RADIUS_PERCENT,
	EXPLOSIVE_HIT,
	HEAL_ON_KILL,
	SHIELD_ON_KILL,
}

@export var id: StringName
## German display texts (fallback). Shown translated via DataTexts.upgrade_name()/upgrade_description()
## (keys UPGRADE_<ID>_NAME and UPGRADE_<ID>_DESC in localization/translations.csv, D-111).
@export var display_name := ""
@export_multiline var description := ""
@export var category := Category.ATTRIBUTE
@export var effect := Effect.DAMAGE_PERCENT
## Effect amount per stack (percent values as fractions: 0.1 = +10 %).
@export var value := 0.0
## 0 = unlimited.
@export var max_stacks := 0
## Applies to attacks carrying at least one of these tags (OR, D-028). Empty = every attack.
@export var applicable_tags: Array[StringName] = []
## All of these must be present in addition (AND, D-028).
@export var required_tags: Array[StringName] = []
@export var icon: Texture2D


func applies_to(tags: Array[StringName]) -> bool:
	for tag in required_tags:
		if not tags.has(tag):
			return false
	if applicable_tags.is_empty():
		return true
	for tag in applicable_tags:
		if tags.has(tag):
			return true
	return false


func is_limited() -> bool:
	return max_stacks > 0

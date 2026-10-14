class_name ShopOffer
extends RefCounted
## One shop slot. Only valid offers are created (D-036).

enum Kind { UPGRADE, WEAPON, HEAL, SHIELD }

var kind := Kind.HEAL
var upgrade: UpgradeData = null
var weapon: WeaponData = null
var amount := 0.0
var price := 0
var sold := false


func get_title() -> String:
	match kind:
		Kind.UPGRADE:
			return upgrade.display_name
		Kind.WEAPON:
			return weapon.display_name
		Kind.HEAL:
			return "Heiltrank"
	return "Schildrune"


func get_description() -> String:
	match kind:
		Kind.UPGRADE:
			return upgrade.description
		Kind.WEAPON:
			return "Neue Waffe"
		Kind.HEAL:
			return "+%s HP" % DamageNumber.format_amount(amount)
	return "+%s Schild" % DamageNumber.format_amount(amount)


func get_icon() -> Texture2D:
	match kind:
		Kind.UPGRADE:
			return upgrade.icon
		Kind.WEAPON:
			return weapon.icon
		Kind.HEAL:
			return preload("res://art/ui/heart_full.png")
	return preload("res://art/ui/shield_icon.png")

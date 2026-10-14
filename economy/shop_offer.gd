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
			return DataTexts.upgrade_name(upgrade)
		Kind.WEAPON:
			return DataTexts.weapon_name(weapon)
		Kind.HEAL:
			return Loc.t(&"SHOP_HEAL_NAME")
	return Loc.t(&"SHOP_SHIELD_NAME")


func get_description() -> String:
	match kind:
		Kind.UPGRADE:
			return DataTexts.upgrade_description(upgrade)
		Kind.WEAPON:
			return Loc.t(&"SHOP_NEW_WEAPON")
		Kind.HEAL:
			return Loc.t(&"SHOP_HEAL_DESC", [DamageNumber.format_amount(amount)])
	return Loc.t(&"SHOP_SHIELD_DESC", [DamageNumber.format_amount(amount)])


func get_icon() -> Texture2D:
	match kind:
		Kind.UPGRADE:
			return upgrade.icon
		Kind.WEAPON:
			return weapon.icon
		Kind.HEAL:
			return preload("res://art/ui/heart_full.png")
	return preload("res://art/ui/shield_icon.png")

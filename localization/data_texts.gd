class_name DataTexts
extends RefCounted
## Display texts of data resources (.tres) in the current language (D-111, round two). The resources
## keep their German texts (fallback, logs, tools and tests that look for them); the translation
## comes from localization/translations.csv by naming convention, so no resource or logic changes:
##   UpgradeData  UPGRADE_<ID>_NAME, UPGRADE_<ID>_DESC
##   WeaponData   WEAPON_<ID>_NAME, WEAPON_<ID>_SPECIAL, WEAPON_<ID>_SPECIAL_DESC
## <ID> is the resource id in capitals (big_explosion -> UPGRADE_BIG_EXPLOSION_NAME). Without a CSV
## entry the German field is shown. tools/i18n_check.py --tres knows the same convention.
## Also the translated weapon value line of the HUD (the German twin is UiKit.weapon_stats_text).


static func upgrade_name(upgrade: UpgradeData) -> String:
	if upgrade == null:
		return ""
	return text_or(key_for("upgrade", upgrade.id, "name"), upgrade.display_name)


static func upgrade_description(upgrade: UpgradeData) -> String:
	if upgrade == null:
		return ""
	return text_or(key_for("upgrade", upgrade.id, "desc"), upgrade.description)


static func weapon_name(weapon: WeaponData) -> String:
	if weapon == null:
		return ""
	return text_or(key_for("weapon", weapon.id, "name"), weapon.display_name)


## Name of the weapon's special attack ("" if it has none).
static func weapon_special_name(weapon: WeaponData) -> String:
	if weapon == null or weapon.special_name.is_empty():
		return ""
	return text_or(key_for("weapon", weapon.id, "special"), weapon.special_name)


static func weapon_special_description(weapon: WeaponData) -> String:
	if weapon == null or weapon.special_description.is_empty():
		return ""
	return text_or(key_for("weapon", weapon.id, "special_desc"), weapon.special_description)


## Translation key of a data field: key_for("upgrade", &"pierce", "name") -> UPGRADE_PIERCE_NAME.
static func key_for(prefix: String, id: StringName, field: String) -> StringName:
	return StringName(("%s_%s_%s" % [prefix, id, field]).to_upper())


## Translated text of key, or fallback while the key has no entry (no CSV row yet).
static func text_or(key: StringName, fallback: String) -> String:
	Loc.install()
	var text := String(TranslationServer.translate(key))
	return fallback if text.is_empty() or text == String(key) else text


## Effective values of a weapon in one line ("14 damage · 1.50/s · 100° swing"), translated.
## Same numbers as UiKit.weapon_stats_text (dungeon dialogs), which is still German.
static func weapon_stats_text(controller: WeaponController, weapon: WeaponData) -> String:
	var text := Loc.t(&"WEAPON_STATS", [
		DamageNumber.format_amount(DamageProcessor.round_damage(controller.get_effective_damage(weapon))),
		"%.2f" % controller.get_effective_attack_rate(weapon)])
	match weapon.weapon_type:
		WeaponData.WeaponType.SWORD, WeaponData.WeaponType.DAGGER:
			text += " · " + Loc.t(&"WEAPON_STATS_SWING", [roundi(controller.get_effective_swing_angle(weapon))])
		WeaponData.WeaponType.STAFF, WeaponData.WeaponType.HAMMER:
			text += " · " + Loc.t(&"WEAPON_STATS_AREA", [roundi(controller.get_effective_aoe_radius(weapon))])
		WeaponData.WeaponType.BOW:
			text += " · %d px/s" % roundi(controller.get_effective_projectile_speed(weapon))
	return text

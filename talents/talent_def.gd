class_name TalentDef
extends Resource
## One node of the talent tree (KONZEPT §6.1, D-194): path, rank, how many levels it takes and what
## every level does. Pure definition (D-045); the levels a player put in live in TalentState, what
## they add up to is resolved by TalentEffects. All values are TESTWERTE.
## Texts: TALENT_<ID> (name) and TALENT_<ID>_DESC (description, %s = value of one level) in
## localization/translations.csv (D-111). Icon by naming convention: art/ui/talents/talent_<id>.png
## (SPRITES_V13 §B5).

## What one level of a talent changes. Percent values are fractions (0.05 = +5 %).
enum Effect {
	## +value move speed per level (additive percent).
	MOVE_SPEED_PERCENT,
	## −value seconds dash cooldown per level.
	DASH_COOLDOWN_REDUCTION,
	## +value attack rate per level for weapons carrying one of weapon_tags (OR, like D-028).
	ATTACK_RATE_PERCENT,
	## +value damage per level for weapons carrying one of weapon_tags (OR, like D-028).
	DAMAGE_PERCENT,
	## For EVASION_TIME seconds after a dash: +value damage per level (situational, D-019).
	EVASION_DAMAGE_PERCENT,
	## +value further dash charges.
	DASH_CHARGES,
	## The dash leaves a light trail that slows enemies (Windläufer).
	WIND_RUNNER,
	## +value max HP per level.
	MAX_HEALTH,
	## −value knockback and stun duration per level.
	STAGGER_REDUCTION,
	## +value damage per level against champions and shield bearers (situational, D-019).
	BREAKER_DAMAGE_PERCENT,
	## Once per run get up with 2 HP alone, revive twice as fast in a group (Zweites Herz).
	SECOND_HEART,
	## Below 2 HP a hit sets off an ember wave (Glutherz).
	EMBER_HEART,
	## Unlocks the spell `spell` (KE7 builds the spells); light_flash also opens the spell slot.
	UNLOCK_SPELL,
	## +value spell damage per level (additive percent).
	SPELL_DAMAGE_PERCENT,
	## −value spell cooldown per level (additive percent).
	SPELL_COOLDOWN_PERCENT,
	## +value spell slots.
	SPELL_SLOTS,
}

const PATH_WIND: StringName = &"wind"
const PATH_EMBER: StringName = &"ember"
const PATH_SOUL: StringName = &"soul"
const PATHS: Array[StringName] = [PATH_WIND, PATH_EMBER, PATH_SOUL]
const MIN_RANK := 1
const MAX_RANK := 4
const ICON_PATH := "res://art/ui/talents/talent_%s.png"

@export var id: StringName
## wind, ember or soul (PATHS).
@export var path: StringName = PATH_WIND
## 1..4; rank 4 is the capstone (Schlussstein).
@export_range(1, 4) var rank := 1
## Levels this talent takes; each level costs one talent point.
@export var max_level := 1
@export var effect := Effect.MOVE_SPEED_PERCENT
## Effect amount per level (TESTWERT).
@export var value := 0.0
## Weapons the effect applies to (OR); empty = every weapon. Only for weapon effects.
@export var weapon_tags: Array[StringName] = []
## Spell id this talent unlocks (UNLOCK_SPELL), empty otherwise.
@export var spell: StringName = &""


func is_capstone() -> bool:
	return rank == MAX_RANK


func unlocks_spell() -> bool:
	return effect == Effect.UNLOCK_SPELL and spell != &""


## Weapon tags of an attack match this talent (OR; no weapon_tags = every weapon).
func applies_to(tags: Array[StringName]) -> bool:
	if weapon_tags.is_empty():
		return true
	for tag in weapon_tags:
		if tags.has(tag):
			return true
	return false


func name_key() -> StringName:
	return StringName("TALENT_%s" % String(id).to_upper())


func description_key() -> StringName:
	return StringName("TALENT_%s_DESC" % String(id).to_upper())


## Translated name.
func get_display_name() -> String:
	return Loc.t(name_key())


## Translated description. Talents with a number per level fill it in for %s (value_text()); the
## others (switches, spells) have no placeholder.
func get_description() -> String:
	if has_value_in_text():
		return Loc.t(description_key(), [value_text()])
	return Loc.t(description_key())


## The description shows the value of one level (%s in TALENT_<ID>_DESC).
func has_value_in_text() -> bool:
	return is_percent() or effect in [Effect.DASH_COOLDOWN_REDUCTION, Effect.MAX_HEALTH]


func is_percent() -> bool:
	return effect in [Effect.MOVE_SPEED_PERCENT, Effect.ATTACK_RATE_PERCENT, Effect.DAMAGE_PERCENT,
		Effect.EVASION_DAMAGE_PERCENT, Effect.STAGGER_REDUCTION, Effect.BREAKER_DAMAGE_PERCENT,
		Effect.SPELL_DAMAGE_PERCENT, Effect.SPELL_COOLDOWN_PERCENT]


## Value of one level for the description: percents as whole numbers (5), seconds and HP as they
## are (0.15 / 0,15, 1).
func value_text() -> String:
	if is_percent():
		return str(roundi(value * 100.0))
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	var text := String.num(value, 2)
	return text.replace(".", ",") if Loc.current_language() == &"de" else text


## Icon from art/ui/talents/ (SPRITES_V13 §B5). Spell nodes have no talent_<id>.png: they show the
## spell's symbol (SpellArt.icon). Else null until it is delivered (the UI draws a placeholder).
func get_icon() -> Texture2D:
	var icon_path := ICON_PATH % id
	if ResourceLoader.exists(icon_path):
		return load(icon_path) as Texture2D
	if unlocks_spell():
		return SpellArt.icon(spell)
	return null


static func path_name_key(talent_path: StringName) -> StringName:
	return StringName("TALENT_PATH_%s" % String(talent_path).to_upper())


static func path_description_key(talent_path: StringName) -> StringName:
	return StringName("TALENT_PATH_%s_DESC" % String(talent_path).to_upper())

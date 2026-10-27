class_name SpellBook
extends RefCounted
## The five spells (KE7, KONZEPT §6.2) by id: data from spells/data/<id>.tres and their texts
## (SPELL_<ID>, SPELL_<ID>_DESC, D-111). The ids are the ones the talent tree unlocks; the order is
## the catalog order of the talent tree (Lichtblitz first, it opens the spell slot).

const LIGHT_FLASH: StringName = &"light_flash"
const SOUL_SHIELD: StringName = &"soul_shield"
const FLAME_RING: StringName = &"flame_ring"
const WILL_O_WISP: StringName = &"will_o_wisp"
const HEAL_SPARK: StringName = &"heal_spark"
const IDS: Array[StringName] = [LIGHT_FLASH, SOUL_SHIELD, FLAME_RING, WILL_O_WISP, HEAL_SPARK]
const DATA_DIR := "res://spells/data/"
const KEY_PREFIX := "SPELL_"

static var _cache: Dictionary[StringName, SpellData] = {}


## Data of a spell, null for an unknown id.
static func get_spell(id: StringName) -> SpellData:
	if _cache.has(id):
		return _cache[id]
	var path := DATA_DIR + String(id) + ".tres"
	var data: SpellData = load(path) as SpellData if IDS.has(id) and ResourceLoader.exists(path) else null
	if data != null:
		_cache[id] = data
	return data


static func has_spell(id: StringName) -> bool:
	return get_spell(id) != null


static func all() -> Array[SpellData]:
	var result: Array[SpellData] = []
	for id in IDS:
		var data := get_spell(id)
		if data != null:
			result.append(data)
	return result


## Translated name ("Lichtblitz" / "Light Flash").
static func display_name(id: StringName) -> String:
	return Loc.t(name_key(id))


## Translated description with the spell's numbers (base values, before talents and upgrades).
static func description(id: StringName) -> String:
	var data := get_spell(id)
	if data == null:
		return ""
	var args: Array = []
	match data.effect:
		SpellData.Effect.BLIND_AREA:
			args = [_number(data.get_radius_tiles()), _number(data.duration)]
		SpellData.Effect.SHIELD:
			args = [_number(data.amount)]
		SpellData.Effect.DAMAGE_AREA:
			args = [_number(data.amount), _number(data.get_radius_tiles())]
		SpellData.Effect.HOMING_LIGHTS:
			args = [data.count, _number(data.amount)]
		SpellData.Effect.HEAL_AREA:
			args = [_number(data.amount), _number(data.get_radius_tiles())]
	return Loc.t(description_key(id), args)


static func name_key(id: StringName) -> StringName:
	return StringName(KEY_PREFIX + String(id).to_upper())


static func description_key(id: StringName) -> StringName:
	return StringName(KEY_PREFIX + String(id).to_upper() + "_DESC")


## "3", "2.5" (German "2,5").
static func _number(value: float) -> String:
	var text := DamageNumber.format_amount(value)
	return text.replace(".", ",") if Loc.current_language() == &"de" else text

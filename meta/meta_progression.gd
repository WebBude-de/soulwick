class_name MetaProgression
extends RefCounted
## The forge (Schmiede, KONZEPT §5.1, KE4) and the trading post (Handelsposten, KONZEPT §5.2, KE5).
## The forge only makes weapons and equipment better, paid with gold: Arsenal (start weapons),
## second start slot, "Waffe schmieden" I–V per weapon, Schildplatte and Laterne. Vitalität and
## Dash-Training live in the talent tree now (TalentEffects), Goldgier became the Proviant Goldregen,
## Schärfe is gone (D-194). The trading post takes Seelenkristalle: Proviant for the next run only
## (seven kinds, 1-3 slots, consumed at the run start) and permanent trade levels (Proviant-Platz,
## Glück, Händlerfreund). Levels, currencies and pending boosts are stored by SaveManager
## ([meta_upgrades], [trade_levels], [boosts]); this class holds the rules (costs, limits, effects as
## pure functions, values per level for the dialogs) and puts them on a run. Which upgrades are open
## decides MetaUnlocks.
## Co-op (D-088, KONZEPT §9): the forge levels of a run are state at the player (set_player_forge, a
## plain snapshot). Solo it comes from the save (apply_to_run); in a quick game the host puts every
## player's own snapshot from the lobby on its copy (apply_forge_snapshot); guild runs later use the
## guild forge (MP8b). Weapons, light and hits ask the player_* getters, never the save. Proviant and
## trade levels work the same way (set_player_provisions, apply_provisions per player); guild runs
## have none (KONZEPT §9).
## KF9 merges cloud worlds with the pure merge_* functions at the end (KONZEPT §10).
## All numbers are TESTWERTE.

# --- Weapons (WeaponData.id) ---
const WEAPON_SWORD: StringName = &"sword"
const WEAPON_BOW: StringName = &"bow"
const WEAPON_STAFF: StringName = &"staff"
const WEAPON_DAGGER: StringName = &"dagger"
const WEAPON_HAMMER: StringName = &"hammer"
## Forge order; the sword is always a start weapon, the others need their Arsenal entry.
const WEAPON_ORDER: Array[StringName] = [WEAPON_SWORD, WEAPON_BOW, WEAPON_STAFF, WEAPON_DAGGER, WEAPON_HAMMER]
const DEFAULT_START_WEAPON: StringName = WEAPON_SWORD
const WEAPON_PATHS := {
	WEAPON_SWORD: "res://weapons/data/sword.tres",
	WEAPON_BOW: "res://weapons/data/bow.tres",
	WEAPON_STAFF: "res://weapons/data/staff.tres",
	WEAPON_DAGGER: "res://weapons/data/dagger.tres",
	WEAPON_HAMMER: "res://weapons/data/hammer.tres",
}
## Weapon id -> translation key of its short name (get_weapon_name()).
const WEAPON_NAMES := {
	WEAPON_SWORD: &"META_WEAPON_SWORD", WEAPON_BOW: &"META_WEAPON_BOW", WEAPON_STAFF: &"META_WEAPON_STAFF",
	WEAPON_DAGGER: &"META_WEAPON_DAGGER", WEAPON_HAMMER: &"META_WEAPON_HAMMER",
}

# --- Forge upgrades (KONZEPT §5.1) ---
## Upgrade kinds: "Waffe schmieden" (one per weapon), Arsenal (one per weapon but the sword) and
## equipment (second start slot, Schildplatte, Laterne).
const KIND_WEAPON: StringName = &"weapon"
const KIND_ARSENAL: StringName = &"arsenal"
const KIND_EQUIPMENT: StringName = &"equipment"
const WEAPON_PREFIX := "weapon_"
const ARSENAL_PREFIX := "arsenal_"
const SMITH_SWORD: StringName = &"weapon_sword"
const SMITH_BOW: StringName = &"weapon_bow"
const SMITH_STAFF: StringName = &"weapon_staff"
const SMITH_DAGGER: StringName = &"weapon_dagger"
const SMITH_HAMMER: StringName = &"weapon_hammer"
const ARSENAL_BOW: StringName = &"arsenal_bow"
const ARSENAL_STAFF: StringName = &"arsenal_staff"
const ARSENAL_DAGGER: StringName = &"arsenal_dagger"
const ARSENAL_HAMMER: StringName = &"arsenal_hammer"
const SECOND_SLOT: StringName = &"second_slot"
const SHIELD_PLATE: StringName = &"shield_plate"
const LANTERN: StringName = &"lantern"
const WEAPON_UPGRADES: Array[StringName] = [SMITH_SWORD, SMITH_BOW, SMITH_STAFF, SMITH_DAGGER, SMITH_HAMMER]
const ARSENAL_UPGRADES: Array[StringName] = [ARSENAL_BOW, ARSENAL_STAFF, ARSENAL_DAGGER, ARSENAL_HAMMER]
const EQUIPMENT_UPGRADES: Array[StringName] = [SECOND_SLOT, SHIELD_PLATE, LANTERN]
const UPGRADE_ORDER: Array[StringName] = [
	SMITH_SWORD, SMITH_BOW, SMITH_STAFF, SMITH_DAGGER, SMITH_HAMMER,
	ARSENAL_BOW, ARSENAL_STAFF, ARSENAL_DAGGER, ARSENAL_HAMMER,
	SECOND_SLOT, SHIELD_PLATE, LANTERN,
]
## TESTWERT (KONZEPT §5.1): gold per level.
const WEAPON_LEVEL_COSTS: Array[int] = [60, 120, 200, 320, 480]
## Every entry: kind, weapon (weapon and Arsenal kinds), translation keys for name, effect, summary,
## the label of the value it changes (stat) and the group the unlock message uses, gold cost of each
## level (index = level - 1). Names of the weapon kinds take the weapon's short name ("%s schmieden").
## Read them translated with get_upgrade_name() and friends. Changing ids or the number of levels
## needs a save migration (SaveManager.migrate, D-059).
const UPGRADES := {
	SMITH_SWORD: {"kind": KIND_WEAPON, "weapon": WEAPON_SWORD, "costs": WEAPON_LEVEL_COSTS},
	SMITH_BOW: {"kind": KIND_WEAPON, "weapon": WEAPON_BOW, "costs": WEAPON_LEVEL_COSTS},
	SMITH_STAFF: {"kind": KIND_WEAPON, "weapon": WEAPON_STAFF, "costs": WEAPON_LEVEL_COSTS},
	SMITH_DAGGER: {"kind": KIND_WEAPON, "weapon": WEAPON_DAGGER, "costs": WEAPON_LEVEL_COSTS},
	SMITH_HAMMER: {"kind": KIND_WEAPON, "weapon": WEAPON_HAMMER, "costs": WEAPON_LEVEL_COSTS},
	ARSENAL_BOW: {"kind": KIND_ARSENAL, "weapon": WEAPON_BOW, "costs": [80]},
	ARSENAL_STAFF: {"kind": KIND_ARSENAL, "weapon": WEAPON_STAFF, "costs": [120]},
	ARSENAL_DAGGER: {"kind": KIND_ARSENAL, "weapon": WEAPON_DAGGER, "costs": [160]},
	ARSENAL_HAMMER: {"kind": KIND_ARSENAL, "weapon": WEAPON_HAMMER, "costs": [200]},
	SECOND_SLOT: {"kind": KIND_EQUIPMENT, "costs": [300]},
	SHIELD_PLATE: {"kind": KIND_EQUIPMENT, "costs": [40, 90, 160]},
	LANTERN: {"kind": KIND_EQUIPMENT, "costs": [50, 110, 200]},
}
## Texts per kind (weapon, Arsenal) or per equipment id: name, effect, summary, stat, group.
const TEXTS := {
	KIND_WEAPON: {"name": &"FORGE_SMITH_NAME", "effect": &"FORGE_SMITH_EFFECT", "summary": &"FORGE_SMITH_SUMMARY",
		"stat": &"FORGE_SMITH_STAT", "group": &"FORGE_SMITH_GROUP"},
	KIND_ARSENAL: {"name": &"FORGE_ARSENAL_UNLOCK_NAME", "effect": &"FORGE_ARSENAL_UNLOCK_EFFECT",
		"summary": &"FORGE_ARSENAL_UNLOCK_SUMMARY", "stat": &"FORGE_ARSENAL_UNLOCK_STAT", "group": &"FORGE_ARSENAL_NAME"},
	SECOND_SLOT: {"name": &"FORGE_SECOND_SLOT_NAME", "effect": &"FORGE_SECOND_SLOT_EFFECT", "summary": &"FORGE_SECOND_SLOT_SUMMARY",
		"stat": &"FORGE_SECOND_SLOT_STAT", "group": &"FORGE_SECOND_SLOT_NAME"},
	SHIELD_PLATE: {"name": &"FORGE_SHIELD_PLATE_NAME", "effect": &"FORGE_SHIELD_PLATE_EFFECT", "summary": &"FORGE_SHIELD_PLATE_SUMMARY",
		"stat": &"FORGE_START_SHIELD_STAT", "group": &"FORGE_SHIELD_PLATE_NAME"},
	LANTERN: {"name": &"FORGE_LANTERN_NAME", "effect": &"FORGE_LANTERN_EFFECT", "summary": &"FORGE_LANTERN_SUMMARY",
		"stat": &"FORGE_LANTERN_STAT", "group": &"FORGE_LANTERN_NAME"},
}
## TESTWERT (KONZEPT §5.1): effect per level. Waffe schmieden: +8 % damage per level (added to the
## weapon's DAMAGE_PERCENT sum like the run upgrades), from level III the special (right click) hits
## harder, level V is the "Meisterstück" with its own glint.
const WEAPON_DAMAGE_PER_LEVEL := 0.08
const WEAPON_SPECIAL_LEVEL := 3
const WEAPON_SPECIAL_BONUS := 0.25
const MASTERWORK_LEVEL := 5
const SHIELD_PER_LEVEL := 3.0
const LANTERN_RADIUS_PER_LEVEL := 0.10
## Player defaults (mirror of HealthComponent.max_health and Player.dash_cooldown; test_meta_values
## checks they still match). The forge no longer changes them; talents do (TalentEffects).
const BASE_MAX_HEALTH := 6.0
const BASE_DASH_COOLDOWN := 1.5

# --- Run-start banner (D-087) ---
## Translation key; a Label translates it by itself, get_run_banner_title() gives the text.
const RUN_BANNER_TITLE: StringName = &"META_RUN_BANNER_TITLE"

# --- The forge at the player (co-op state, D-088) ---
## Player meta holding the forge snapshot of this run (forge_snapshot()).
const FORGE_META: StringName = &"forge_loadout"

# --- Trading post: Proviant (KONZEPT §5.2, KE5; no crystal exchange since D-087) ---
## Proviant ids; the icon is art/ui/trading/boost_<id>.png. soul_anchor and return_stone are the ids
## the extraction hooks use (SoulGateRules.SOUL_ANCHOR_BOOST, RETURN_STONE_BOOST). The ids of older
## builds (potion, upgrade, gold) are mapped on load (SaveManager.LEGACY_BOOST_IDS).
const BOOST_GOLD_RAIN: StringName = &"gold_rain"
const BOOST_LUCKY_AMULET: StringName = &"lucky_amulet"
const BOOST_CLEAR_SIGHT: StringName = &"clear_sight"
const BOOST_HEALING_POTION: StringName = &"healing_potion"
const BOOST_SOUL_ANCHOR: StringName = &"soul_anchor"
const BOOST_RETURN_STONE: StringName = &"return_stone"
const BOOST_KEEN_NOSE: StringName = &"keen_nose"
const BOOST_ORDER: Array[StringName] = [
	BOOST_GOLD_RAIN, BOOST_LUCKY_AMULET, BOOST_CLEAR_SIGHT, BOOST_HEALING_POTION,
	BOOST_SOUL_ANCHOR, BOOST_RETURN_STONE, BOOST_KEEN_NOSE,
]
## TESTWERT (KONZEPT §5.2): Proviant effects.
const GOLD_RAIN_FACTOR := 2.0
const HEALING_POTION_HEALTH := 2.0
const LUCKY_AMULET_UPGRADES := 1
## Must equal SoulGateRules.SOUL_ANCHOR_PAYOUT_RATIO (test_trading_post checks it).
const SOUL_ANCHOR_PAYOUT_RATIO := 0.5
const RETURN_STONE_GATES := 1
## Proviant for the next run only (consumed by RunManager.start_run). Every entry: translation keys
## of name, effect text and the banner line (applied), the price in Seelenkristalle (TESTWERT,
## KONZEPT §5.2) and the effect values boost_effect() returns.
const BOOSTS := {
	BOOST_GOLD_RAIN: {"name": &"BOOST_GOLD_RAIN_NAME", "effect": &"BOOST_GOLD_RAIN_EFFECT",
		"applied": &"META_APPLIED_GOLD_RAIN", "price": 4, "values": {"gold_factor": GOLD_RAIN_FACTOR}},
	BOOST_LUCKY_AMULET: {"name": &"BOOST_LUCKY_AMULET_NAME", "effect": &"BOOST_LUCKY_AMULET_EFFECT",
		"applied": &"META_APPLIED_LUCKY_AMULET", "price": 3, "values": {"rare_upgrades": LUCKY_AMULET_UPGRADES}},
	BOOST_CLEAR_SIGHT: {"name": &"BOOST_CLEAR_SIGHT_NAME", "effect": &"BOOST_CLEAR_SIGHT_EFFECT",
		"applied": &"META_APPLIED_CLEAR_SIGHT", "price": 2, "values": {"blind_immune": true}},
	BOOST_HEALING_POTION: {"name": &"BOOST_HEALING_POTION_NAME", "effect": &"BOOST_HEALING_POTION_EFFECT",
		"applied": &"META_APPLIED_HEALING_POTION", "price": 2, "values": {"max_health": HEALING_POTION_HEALTH}},
	BOOST_SOUL_ANCHOR: {"name": &"BOOST_SOUL_ANCHOR_NAME", "effect": &"BOOST_SOUL_ANCHOR_EFFECT",
		"applied": &"META_APPLIED_SOUL_ANCHOR", "price": 3, "values": {"loss_payout_ratio": SOUL_ANCHOR_PAYOUT_RATIO}},
	BOOST_RETURN_STONE: {"name": &"BOOST_RETURN_STONE_NAME", "effect": &"BOOST_RETURN_STONE_EFFECT",
		"applied": &"META_APPLIED_RETURN_STONE", "price": 5, "values": {"return_gates": RETURN_STONE_GATES}},
	BOOST_KEEN_NOSE: {"name": &"BOOST_KEEN_NOSE_NAME", "effect": &"BOOST_KEEN_NOSE_EFFECT",
		"applied": &"META_APPLIED_KEEN_NOSE", "price": 2, "values": {"keen_nose": true}},
}

# --- Trading post: permanent trade levels (KONZEPT §5.2, KE5; SaveManager [trade_levels]) ---
const TRADE_PROVISION_SLOT: StringName = &"provision_slot"
const TRADE_LUCK: StringName = &"luck"
const TRADE_MERCHANT_FRIEND: StringName = &"merchant_friend"
const TRADE_ORDER: Array[StringName] = [TRADE_PROVISION_SLOT, TRADE_LUCK, TRADE_MERCHANT_FRIEND]
## Every entry: translation keys of name, effect and the label of the value it changes (stat),
## crystal cost of each level (index = level - 1; TESTWERT, KONZEPT §5.2). Changing ids or the
## number of levels needs a save migration (SaveManager.migrate, D-059).
const TRADE_LEVELS := {
	TRADE_PROVISION_SLOT: {"name": &"TRADE_SLOT_NAME", "effect": &"TRADE_SLOT_EFFECT", "stat": &"TRADE_SLOT_STAT", "costs": [8, 15]},
	TRADE_LUCK: {"name": &"TRADE_LUCK_NAME", "effect": &"TRADE_LUCK_EFFECT", "stat": &"TRADE_LUCK_STAT", "costs": [6, 12, 20]},
	TRADE_MERCHANT_FRIEND: {"name": &"TRADE_MERCHANT_NAME", "effect": &"TRADE_MERCHANT_EFFECT", "stat": &"TRADE_MERCHANT_STAT", "costs": [5, 10]},
}
## TESTWERT (KONZEPT §5.2): one Proviant slot at the start, one more per level (up to 3); rare
## upgrades weigh +10 % per Glück level in an upgrade choice; dungeon merchants -10 % per
## Händlerfreund level.
const BASE_PROVISION_SLOTS := 1
const LUCK_RARE_BONUS_PER_LEVEL := 0.10
const MERCHANT_DISCOUNT_PER_LEVEL := 0.10

# --- Proviant and trade levels at the player (co-op state, D-088, KONZEPT §9) ---
## Player meta holding the run's Proviant and trade levels (provision_snapshot()).
const PROVISION_META: StringName = &"provisions"
## Player meta set once the return stone opened its gate in this run.
const RETURN_STONE_USED_META: StringName = &"return_stone_used"

# --- Merge rules of the v5 fields (KONZEPT §10, used by KF9) ---
const MERGE_MAX: StringName = &"max"
const MERGE_UNION: StringName = &"union"
const MERGE_LAST_PLAYED: StringName = &"last_played"
## "section" or "section/key" -> rule. [meta_upgrades] holds levels and the Arsenal unlocks as 0/1
## levels, so the maximum per key is also the union of the unlocks (unlocked_weapons_from_levels).
const MERGE_RULES := {
	"meta_upgrades": MERGE_MAX,
	"trade_levels": MERGE_MAX,
	"migration/v5_refund_gold": MERGE_MAX,
	"migration/v5_weapons": MERGE_UNION,
	"progress/start_weapon": MERGE_LAST_PLAYED,
	"progress/second_weapon": MERGE_LAST_PLAYED,
	"boosts/pending": MERGE_LAST_PLAYED,
}


# --- Ids ---

static func smith_id(weapon_id: StringName) -> StringName:
	return StringName(WEAPON_PREFIX + String(weapon_id))


static func arsenal_id(weapon_id: StringName) -> StringName:
	return StringName(ARSENAL_PREFIX + String(weapon_id))


static func get_kind(id: StringName) -> StringName:
	return UPGRADES[id]["kind"] if UPGRADES.has(id) else &""


## The weapon of a "Waffe schmieden" or Arsenal entry, &"" for equipment and unknown ids.
static func get_upgrade_weapon(id: StringName) -> StringName:
	return StringName(UPGRADES[id].get("weapon", &"")) if UPGRADES.has(id) else &""


# --- Texts in the current language (D-111) ---

static func get_upgrade_name(id: StringName) -> String:
	return _upgrade_text(id, "name")


static func get_upgrade_summary(id: StringName) -> String:
	return _upgrade_text(id, "summary")


static func get_upgrade_effect(id: StringName) -> String:
	return _upgrade_text(id, "effect")


## Label of the value an upgrade changes ("Schaden", "Schild", "Lichtradius").
static func get_upgrade_stat(id: StringName) -> String:
	return _upgrade_text(id, "stat")


## Name of the group in unlock messages: "Arsenal" for every Arsenal entry, else the upgrade's name.
static func get_upgrade_group(id: StringName) -> String:
	return _upgrade_text(id, "group")


## "Schwert schmieden III", "Schildplatte II"; upgrades with one level have no number ("Arsenal: Bogen").
static func get_step_name(id: StringName, level: int) -> String:
	if get_max_level(id) <= 1:
		return get_upgrade_name(id)
	return "%s %s" % [get_upgrade_name(id), RunRecap.roman(level)]


static func get_boost_name(id: StringName) -> String:
	return Loc.t(StringName(BOOSTS[id]["name"])) if BOOSTS.has(id) else ""


## The Proviant's effect text with its real numbers ("+2 Max-HP für den Run").
static func get_boost_effect(id: StringName) -> String:
	if not BOOSTS.has(id):
		return ""
	var key := StringName(BOOSTS[id]["effect"])
	match id:
		BOOST_HEALING_POTION:
			return Loc.t(key, [roundi(HEALING_POTION_HEALTH)])
		BOOST_SOUL_ANCHOR:
			return Loc.t(key, [roundi(SOUL_ANCHOR_PAYOUT_RATIO * 100.0), roundi(RunManager.LOSS_PAYOUT_RATIO * 100.0)])
	return Loc.t(key)


## Banner line of a Proviant at the run start ("Heiltrank: +2 Max-HP"); detail fills the lucky
## amulet's upgrade name.
static func get_boost_applied_line(id: StringName, detail := "") -> String:
	if not BOOSTS.has(id):
		return ""
	var key := StringName(BOOSTS[id]["applied"])
	match id:
		BOOST_HEALING_POTION:
			return Loc.t(key, [roundi(HEALING_POTION_HEALTH)])
		BOOST_LUCKY_AMULET:
			return Loc.t(key, [detail])
		BOOST_SOUL_ANCHOR:
			return Loc.t(key, [roundi(SOUL_ANCHOR_PAYOUT_RATIO * 100.0)])
	return Loc.t(key)


static func get_trade_name(id: StringName) -> String:
	return Loc.t(StringName(TRADE_LEVELS[id]["name"])) if TRADE_LEVELS.has(id) else ""


static func get_trade_effect(id: StringName) -> String:
	if not TRADE_LEVELS.has(id):
		return ""
	var key := StringName(TRADE_LEVELS[id]["effect"])
	match id:
		TRADE_LUCK:
			return Loc.t(key, [roundi(LUCK_RARE_BONUS_PER_LEVEL * 100.0)])
		TRADE_MERCHANT_FRIEND:
			return Loc.t(key, [roundi(MERCHANT_DISCOUNT_PER_LEVEL * 100.0)])
	return Loc.t(key)


## "Glück II"; levels below 1 give the plain name.
static func get_trade_step_name(id: StringName, level: int) -> String:
	return get_trade_name(id) if level <= 0 else "%s %s" % [get_trade_name(id), RunRecap.roman(level)]


## Short name of a weapon ("Bogen", "Dolche"); the id for unknown weapons.
static func get_weapon_name(id: StringName) -> String:
	return Loc.t(WEAPON_NAMES[id]) if WEAPON_NAMES.has(id) else String(id)


static func get_run_banner_title() -> String:
	return Loc.t(RUN_BANNER_TITLE)


static func _upgrade_text(id: StringName, field: String) -> String:
	if not UPGRADES.has(id):
		return ""
	var kind := get_kind(id)
	if kind == KIND_WEAPON or kind == KIND_ARSENAL:
		var key := StringName(TEXTS[kind][field])
		# Names ("%s schmieden") and the Arsenal effect ("%s als Startwaffe wählbar") take the weapon.
		var with_weapon := field == "name" or (field == "effect" and kind == KIND_ARSENAL)
		return Loc.t(key, [get_weapon_name(get_upgrade_weapon(id))]) if with_weapon else Loc.t(key)
	return Loc.t(StringName(TEXTS[id][field]))


# --- Forge rules ---

static func get_level(id: StringName) -> int:
	return clampi(SaveManager.get_meta_level(id), 0, get_max_level(id))


static func get_max_level(id: StringName) -> int:
	if not UPGRADES.has(id):
		return 0
	return (UPGRADES[id]["costs"] as Array).size()


static func is_maxed(id: StringName) -> bool:
	return get_level(id) >= get_max_level(id)


## Gold cost of the next level, or -1 if the upgrade is maxed or unknown.
static func get_next_cost(id: StringName) -> int:
	if not UPGRADES.has(id) or is_maxed(id):
		return -1
	return UPGRADES[id]["costs"][get_level(id)]


## False for locked upgrades (MetaUnlocks, D-087): they are not shown before they open.
static func can_buy(id: StringName) -> bool:
	var cost := get_next_cost(id)
	return cost >= 0 and MetaUnlocks.is_upgrade_open(id) and SaveManager.get_permanent_gold() >= cost


## Atomic purchase with permanent gold: level +1 and gold spent, or nothing changes. Saves on success.
## A new Arsenal weapon fills an empty second start slot right away.
static func try_buy(id: StringName) -> bool:
	if not can_buy(id):
		return false
	var cost := get_next_cost(id)
	if not SaveManager.try_spend_permanent_gold(cost):
		return false
	SaveManager.set_meta_level(id, get_level(id) + 1)
	_fill_second_weapon(get_upgrade_weapon(id) if get_kind(id) == KIND_ARSENAL else &"")
	SaveManager.save_game()
	return true


static func _fill_second_weapon(preferred: StringName) -> void:
	if not has_second_slot() or get_second_weapon() != &"":
		return
	var candidates: Array[StringName] = get_unlocked_weapons()
	if preferred != &"":
		candidates = [preferred]
	for weapon in candidates:
		if weapon != get_start_weapon() and is_weapon_unlocked(weapon):
			SaveManager.set_second_weapon(weapon)
			return


# --- Start weapons (Arsenal, second start slot) ---

## The sword always; every other weapon once its Arsenal entry is bought.
static func is_weapon_unlocked(weapon_id: StringName) -> bool:
	if weapon_id == DEFAULT_START_WEAPON:
		return true
	return WEAPON_PATHS.has(weapon_id) and get_level(arsenal_id(weapon_id)) >= 1


## Unlocked start weapons in forge order.
static func get_unlocked_weapons() -> Array[StringName]:
	var result: Array[StringName] = []
	for weapon in WEAPON_ORDER:
		if is_weapon_unlocked(weapon):
			result.append(weapon)
	return result


static func has_second_slot() -> bool:
	return get_level(SECOND_SLOT) >= 1


## The weapon in the first slot at the run start: the stored choice if it is unlocked, else the sword.
static func get_start_weapon() -> StringName:
	var chosen := SaveManager.get_start_weapon()
	return chosen if is_weapon_unlocked(chosen) else DEFAULT_START_WEAPON


## Picks the first start weapon (unlocked only). Picking the second one swaps both. Saves.
static func set_start_weapon(weapon_id: StringName) -> bool:
	if not is_weapon_unlocked(weapon_id):
		return false
	var previous := get_start_weapon()
	if weapon_id == get_second_weapon():
		SaveManager.set_second_weapon(previous)
	SaveManager.set_start_weapon(weapon_id)
	SaveManager.save_game()
	return true


## The weapon in the second slot at the run start, &"" without the second start slot or without a
## valid choice (it must be unlocked and differ from the first).
static func get_second_weapon() -> StringName:
	if not has_second_slot():
		return &""
	var chosen := SaveManager.get_second_weapon()
	return chosen if chosen != get_start_weapon() and is_weapon_unlocked(chosen) else &""


## Picks the second start weapon; &"" = none. Needs the second start slot. Saves.
static func set_second_weapon(weapon_id: StringName) -> bool:
	if not has_second_slot():
		return false
	if weapon_id != &"" and (not is_weapon_unlocked(weapon_id) or weapon_id == get_start_weapon()):
		return false
	SaveManager.set_second_weapon(weapon_id)
	SaveManager.save_game()
	return true


## Start loadout: [first] or [first, second].
static func get_start_weapons() -> Array[StringName]:
	var result: Array[StringName] = [get_start_weapon()]
	var second := get_second_weapon()
	if second != &"":
		result.append(second)
	return result


# --- Effects (values per level, pure) ---

static func weapon_damage_bonus_at(level: int) -> float:
	return clampi(level, 0, WEAPON_LEVEL_COSTS.size()) * WEAPON_DAMAGE_PER_LEVEL


## Damage factor of a weapon smithed to a level: 1.0, 1.08, … 1.4.
static func weapon_damage_factor_at(level: int) -> float:
	return 1.0 + weapon_damage_bonus_at(level)


## Factor on the special's damage: from WEAPON_SPECIAL_LEVEL on 1 + WEAPON_SPECIAL_BONUS, else 1.
static func weapon_special_factor_at(level: int) -> float:
	return 1.0 + WEAPON_SPECIAL_BONUS if level >= WEAPON_SPECIAL_LEVEL else 1.0


static func is_masterwork_at(level: int) -> bool:
	return level >= MASTERWORK_LEVEL


static func light_radius_factor_at(level: int) -> float:
	return 1.0 + clampi(level, 0, get_max_level(LANTERN)) * LANTERN_RADIUS_PER_LEVEL


# --- Effects from the save (forge dialog, solo run) ---

## "Waffe schmieden" level of a weapon in the loaded world (0 for unknown weapons).
static func weapon_level(weapon_id: StringName) -> int:
	return get_level(smith_id(weapon_id))


static func weapon_damage_factor(weapon_id: StringName) -> float:
	return weapon_damage_factor_at(weapon_level(weapon_id))


static func get_start_shield() -> float:
	return get_level(SHIELD_PLATE) * SHIELD_PER_LEVEL


static func get_light_radius_factor() -> float:
	return light_radius_factor_at(get_level(LANTERN))


## Global damage bonus of the forge: always 0 since KE4 (Schärfe is gone, D-194); the forge's damage is
## per weapon now (player_weapon_damage_bonus). Kept until WeaponController uses the per-weapon hook.
static func get_damage_bonus() -> float:
	return 0.0


## Factor for gold drops of this machine's run: Goldregen doubles them (Goldgier left the forge,
## KE4). Every gold drop already multiplies with it (enemy spawners, side view coins). In a group
## run the host set group_gold_factor() of the players on the run (RunManager.set_group_gold_factor,
## DungeonManager.refresh_group_gold), and that counts instead (KONZEPT §9).
static func get_gold_multiplier() -> float:
	var group := RunManager.get_group_gold_factor()
	if group >= 0.0:
		return group
	return GOLD_RAIN_FACTOR if RunManager.has_run_boost(BOOST_GOLD_RAIN) else 1.0


# --- The forge at the player (co-op state, D-088) ---

## The loaded world's forge as a plain dictionary (lobby message, run state):
## {"weapons": {id: level}, "shield_plate": int, "lantern": int, "start": [first, second?]}.
static func forge_snapshot() -> Dictionary:
	var weapons := {}
	for weapon in WEAPON_ORDER:
		weapons[String(weapon)] = weapon_level(weapon)
	var start: Array = []
	for weapon in get_start_weapons():
		start.append(String(weapon))
	return {"weapons": weapons, "shield_plate": get_level(SHIELD_PLATE), "lantern": get_level(LANTERN), "start": start}


## A snapshot from elsewhere (lobby message, older client) cleaned up: known weapons only, levels
## clamped to their maximum, at most two different start weapons, the sword when none is valid.
static func sanitize_snapshot(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var weapons := {}
	var raw_weapons: Variant = source.get("weapons", {})
	for weapon in WEAPON_ORDER:
		var level: Variant = raw_weapons.get(String(weapon), 0) if raw_weapons is Dictionary else 0
		weapons[String(weapon)] = clampi(int(level), 0, WEAPON_LEVEL_COSTS.size()) if _is_number(level) else 0
	var start: Array = []
	var raw_start: Variant = source.get("start", [])
	if raw_start is Array:
		for item: Variant in raw_start:
			var weapon := String(item) if typeof(item) == TYPE_STRING or typeof(item) == TYPE_STRING_NAME else ""
			if WEAPON_PATHS.has(StringName(weapon)) and not start.has(weapon) and start.size() < 2:
				start.append(weapon)
	if start.is_empty():
		start.append(String(DEFAULT_START_WEAPON))
	return {
		"weapons": weapons,
		"shield_plate": _clamped_level(source.get("shield_plate", 0), SHIELD_PLATE),
		"lantern": _clamped_level(source.get("lantern", 0), LANTERN),
		"start": start,
	}


static func set_player_forge(player: Node, snapshot: Dictionary) -> void:
	if player != null and is_instance_valid(player):
		player.set_meta(FORGE_META, sanitize_snapshot(snapshot))


## The forge snapshot of a player in this run; {} for a player without one (quick game client
## copies until the host set theirs, tests): every getter below then answers "no forge".
static func get_player_forge(player: Node) -> Dictionary:
	if player == null or not is_instance_valid(player) or not player.has_meta(FORGE_META):
		return {}
	var value: Variant = player.get_meta(FORGE_META)
	return value if value is Dictionary else {}


static func player_weapon_level(player: Node, weapon_id: StringName) -> int:
	var weapons: Variant = get_player_forge(player).get("weapons", {})
	return int(weapons.get(String(weapon_id), 0)) if weapons is Dictionary else 0


## Additive damage bonus of a player's weapon (add it to the DAMAGE_PERCENT sum of
## WeaponController.get_effective_damage, like the old Schärfe). 0 for weapons without an id.
static func player_weapon_damage_bonus(player: Node, weapon: WeaponData) -> float:
	if weapon == null:
		return 0.0
	return weapon_damage_bonus_at(player_weapon_level(player, weapon.id))


## Factor on the special's damage multiplier of a player's weapon (forge level III and up).
static func player_special_factor(player: Node, weapon: WeaponData) -> float:
	if weapon == null:
		return 1.0
	return weapon_special_factor_at(player_weapon_level(player, weapon.id))


## True when a player's weapon is a "Meisterstück" (forge level V): hook for its glint.
static func player_is_masterwork(player: Node, weapon: WeaponData) -> bool:
	return weapon != null and is_masterwork_at(player_weapon_level(player, weapon.id))


## Factor on a player's light radius from the Laterne (1.0 without forge).
static func player_light_factor(player: Node) -> float:
	return light_radius_factor_at(int(get_player_forge(player).get("lantern", 0)))


# --- Values per level (forge display, D-087) ---

## Base damage of a weapon from its data (0 for unknown ids).
static func get_weapon_base_damage(weapon_id: StringName) -> float:
	if not WEAPON_PATHS.has(weapon_id):
		return 0.0
	var data := load(WEAPON_PATHS[weapon_id]) as WeaponData
	return data.base_damage if data != null else 0.0


## Effect value of an upgrade at a level (clamped to 0..max): weapon damage with the forge factor,
## Arsenal 0/1, number of start weapons, start shield, light radius bonus as a fraction.
static func get_value_at_level(id: StringName, level: int) -> float:
	level = clampi(level, 0, get_max_level(id))
	match get_kind(id):
		KIND_WEAPON:
			return get_weapon_base_damage(get_upgrade_weapon(id)) * weapon_damage_factor_at(level)
		KIND_ARSENAL:
			return float(level)
	match id:
		SECOND_SLOT:
			return 1.0 + level
		SHIELD_PLATE:
			return level * SHIELD_PER_LEVEL
		LANTERN:
			return level * LANTERN_RADIUS_PER_LEVEL
	return 0.0


## The value at a level as shown in the forge: "16,2", "frei", "2", "9", "+20 %".
static func format_value_at_level(id: StringName, level: int) -> String:
	var value := get_value_at_level(id, level)
	match get_kind(id):
		KIND_WEAPON:
			return format_number(snappedf(value, 0.1))
		KIND_ARSENAL:
			return Loc.t(&"FORGE_VALUE_UNLOCKED" if value >= 1.0 else &"FORGE_VALUE_LOCKED")
	if id == LANTERN:
		return "+%d %%" % roundi(value * 100.0)
	return format_number(value)


## What buying the next level changes, with real values (D-087): "Schaden 15 → 16,2",
## "Schaden 17,4 → 18,6 · Spezial +25 %", "Schild 0 → 3", "Startwaffe: gesperrt → frei". At the
## maximum "Schaden 21 (max.)"; upgrades with one level show just the value ("Startwaffe: frei").
## Empty for unknown ids.
static func describe_level_step(id: StringName, level: int) -> String:
	if not UPGRADES.has(id):
		return ""
	var max_level := get_max_level(id)
	level = clampi(level, 0, max_level)
	var stat := get_upgrade_stat(id)
	var current := format_value_at_level(id, level)
	if level >= max_level:
		return "%s %s" % [stat, current] if max_level <= 1 else "%s %s (max.)" % [stat, current]
	var text := "%s %s → %s" % [stat, current, format_value_at_level(id, level + 1)]
	if get_kind(id) == KIND_WEAPON:
		if level + 1 == WEAPON_SPECIAL_LEVEL:
			text += " · " + Loc.t(&"FORGE_STEP_SPECIAL", [roundi(WEAPON_SPECIAL_BONUS * 100.0)])
		elif level + 1 == MASTERWORK_LEVEL:
			text += " · " + Loc.t(&"FORGE_STEP_MASTERWORK")
	return text


## describe_level_step() for the current level from the save.
static func describe_next_level(id: StringName) -> String:
	return describe_level_step(id, get_level(id))


## Number without trailing zeros in the current language: German 1.35 -> "1,35", 1.5 -> "1,5",
## 7.0 -> "7"; English keeps the point ("1.35").
static func format_number(value: float) -> String:
	var text := "%.2f" % value
	text = text.rstrip("0").rstrip(".")
	return text.replace(".", ",") if Loc.current_language() == &"de" else text


# --- Run-start banner (D-087) ---

## Short parts for the given forge levels (upgrade id -> level) and start weapons, e.g.
## ["Bogen II + Stab", "+6 Schild", "+20 % Licht"]. The plain sword alone and level 0 are left out.
static func describe_forge_bonuses(levels: Dictionary, start_weapons: Array) -> Array[String]:
	var parts: Array[String] = []
	var names: Array[String] = []
	var smithed := false
	for item: Variant in start_weapons:
		var weapon := StringName(str(item))
		var level := clampi(int(levels.get(smith_id(weapon), 0)), 0, WEAPON_LEVEL_COSTS.size())
		smithed = smithed or level > 0
		names.append(get_weapon_name(weapon) + (" " + RunRecap.roman(level) if level > 0 else ""))
	if smithed or names.size() > 1 or (start_weapons.size() == 1 and StringName(str(start_weapons[0])) != DEFAULT_START_WEAPON):
		parts.append(" + ".join(names))
	var shield := clampi(int(levels.get(SHIELD_PLATE, 0)), 0, get_max_level(SHIELD_PLATE))
	if shield > 0:
		parts.append(Loc.t(&"META_BONUS_SHIELD", [format_number(shield * SHIELD_PER_LEVEL)]))
	var lantern := clampi(int(levels.get(LANTERN, 0)), 0, get_max_level(LANTERN))
	if lantern > 0:
		parts.append(Loc.t(&"META_BONUS_LIGHT", [roundi(lantern * LANTERN_RADIUS_PER_LEVEL * 100.0)]))
	return parts


## describe_forge_bonuses() for the current save.
static func get_forge_bonus_parts() -> Array[String]:
	var levels := {}
	for id in UPGRADE_ORDER:
		levels[id] = get_level(id)
	return describe_forge_bonuses(levels, get_start_weapons())


## Banner text for the run start: all forge bonuses plus the Proviant lines apply_to_run()
## returned, e.g. "Bogen II · +3 Schild · Heiltrank: +2 Max-HP". Empty if nothing applies (then no
## banner). Show it with get_run_banner_title() as the title.
static func get_run_start_summary(applied_boosts: Array[String]) -> String:
	var parts := get_forge_bonus_parts()
	parts.append_array(applied_boosts)
	return " · ".join(parts)


## Single-line variant: "Aus dem Dorf: Bogen II, +3 Schild". Empty if nothing applies.
static func get_run_start_banner_line(applied_boosts: Array[String]) -> String:
	var parts := get_forge_bonus_parts()
	parts.append_array(applied_boosts)
	if parts.is_empty():
		return ""
	return "%s: %s" % [get_run_banner_title(), ", ".join(parts)]


# --- The v5 migration notice (KE4, KONZEPT §5.1) ---

## Lines for the village notice about what the v4 -> v5 migration did in the loaded world, e.g.
## ["520 Gold zurück für Vitalität II, Schärfe I.", "Startschild ist jetzt Schildplatte II.",
## "Bogen und Stab sind als Startwaffen frei.", "Vitalität und Dash-Training: jetzt im Talentbaum."].
## Empty when nothing changed or the world started in v5.
static func describe_migration(report: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var refund := int(report.get("refund_gold", 0))
	if refund > 0:
		var names: Array[String] = []
		for entry: String in report.get("refunded", PackedStringArray()):
			var parts := entry.split(":")
			var key := StringName("FORGE_%s_NAME" % parts[0].to_upper())
			names.append("%s %s" % [Loc.t(key), RunRecap.roman(int(parts[1]) if parts.size() > 1 else 1)])
		lines.append(Loc.t(&"FORGE_MIGRATION_REFUND", [refund, MetaUnlocks.join_names(names)]))
	var shield := int(report.get("shield_plate", 0))
	if shield > 0:
		lines.append(Loc.t(&"FORGE_MIGRATION_SHIELD", [RunRecap.roman(shield)]))
	var weapons: Array[String] = []
	for weapon: String in report.get("weapons", PackedStringArray()):
		weapons.append(get_weapon_name(StringName(weapon)))
	if not weapons.is_empty():
		lines.append(Loc.t(&"FORGE_MIGRATION_WEAPONS", [MetaUnlocks.join_names(weapons)]))
	if refund > 0:
		lines.append(Loc.t(&"FORGE_MIGRATION_TALENTS"))
	return lines


## The notice lines of the loaded world while it is still pending, without marking it shown (the
## village's short notice on arrival; the forge shows and takes it on its first visit).
static func peek_migration_notice() -> Array[String]:
	if not SaveManager.is_v5_notice_pending():
		return []
	return describe_migration(SaveManager.get_v5_report())


## The notice of the loaded world once: its lines (empty if there is nothing to say) and the
## notice marked as shown (memory only, the caller saves).
static func take_migration_notice() -> Array[String]:
	if not SaveManager.is_v5_notice_pending():
		return []
	SaveManager.clear_v5_notice()
	return describe_migration(SaveManager.get_v5_report())


# --- Trading post rules: Proviant ---

static func get_boost_price(id: StringName) -> int:
	return BOOSTS[id]["price"] if BOOSTS.has(id) else -1


## Effect values of a Proviant (TESTWERT, KONZEPT §5.2), {} for unknown ids: gold_factor,
## rare_upgrades, blind_immune, max_health, loss_payout_ratio, return_gates or keen_nose.
static func boost_effect(id: StringName) -> Dictionary:
	return (BOOSTS[id]["values"] as Dictionary).duplicate() if BOOSTS.has(id) else {}


## Known Proviant ids of a list (pending, run or lobby boosts) in BOOST_ORDER, each once.
static func known_boosts(boosts: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for id in BOOST_ORDER:
		for item: Variant in boosts:
			if (typeof(item) == TYPE_STRING or typeof(item) == TYPE_STRING_NAME) and StringName(item) == id:
				result.append(id)
				break
	return result


## Proviant packed for the next run in the loaded world.
static func get_packed_boosts() -> Array[StringName]:
	return known_boosts(SaveManager.get_pending_boosts())


## Proviant slots of the loaded world (1 + Proviant-Platz level).
static func get_provision_slots() -> int:
	return provision_slots_at(get_trade_level(TRADE_PROVISION_SLOT))


## True while another Proviant fits. Older saves may hold more than the slots (they keep them).
static func has_free_provision_slot() -> bool:
	return get_packed_boosts().size() < get_provision_slots()


## A Proviant can be bought when it is not packed yet, a slot is free and the crystals pay it.
static func can_buy_boost(id: StringName) -> bool:
	return BOOSTS.has(id) and not SaveManager.has_pending_boost(id) and has_free_provision_slot() \
		and SaveManager.get_permanent_crystals() >= get_boost_price(id)


## One Proviant of each kind can be packed, at most get_provision_slots() together; they are
## consumed by the next RunManager.start_run(). Saves on success.
static func try_buy_boost(id: StringName) -> bool:
	if not can_buy_boost(id):
		return false
	if not SaveManager.try_spend_permanent_crystals(get_boost_price(id)):
		return false
	SaveManager.add_pending_boost(id)
	SaveManager.save_game()
	return true


# --- Trading post rules: trade levels ---

static func get_trade_level(id: StringName) -> int:
	return clampi(SaveManager.get_trade_level(id), 0, get_trade_max_level(id))


static func get_trade_max_level(id: StringName) -> int:
	return (TRADE_LEVELS[id]["costs"] as Array).size() if TRADE_LEVELS.has(id) else 0


static func is_trade_maxed(id: StringName) -> bool:
	return get_trade_level(id) >= get_trade_max_level(id)


## Crystal cost of the next trade level, or -1 if it is maxed or unknown.
static func get_trade_next_cost(id: StringName) -> int:
	if not TRADE_LEVELS.has(id) or is_trade_maxed(id):
		return -1
	return TRADE_LEVELS[id]["costs"][get_trade_level(id)]


## Crystals still missing for the next trade level (0 = affordable, -1 = maxed or unknown).
static func trade_crystals_missing(id: StringName) -> int:
	var cost := get_trade_next_cost(id)
	return -1 if cost < 0 else maxi(0, cost - SaveManager.get_permanent_crystals())


static func can_buy_trade(id: StringName) -> bool:
	var cost := get_trade_next_cost(id)
	return cost >= 0 and SaveManager.get_permanent_crystals() >= cost


## Atomic purchase with crystals: level +1 and crystals spent, or nothing changes. Saves on success.
static func try_buy_trade(id: StringName) -> bool:
	if not can_buy_trade(id):
		return false
	if not SaveManager.try_spend_permanent_crystals(get_trade_next_cost(id)):
		return false
	SaveManager.set_trade_level(id, get_trade_level(id) + 1)
	SaveManager.save_game()
	return true


# --- Trading post: effects per level and per Proviant list (pure) ---

static func provision_slots_at(level: int) -> int:
	return BASE_PROVISION_SLOTS + clampi(level, 0, get_trade_max_level(TRADE_PROVISION_SLOT))


## Weight bonus of rare upgrades for a Glück level: 0, 0.1, 0.2, 0.3.
static func luck_bonus_at(level: int) -> float:
	return clampi(level, 0, get_trade_max_level(TRADE_LUCK)) * LUCK_RARE_BONUS_PER_LEVEL


## Discount of dungeon merchants for a Händlerfreund level: 0, 0.1, 0.2.
static func merchant_discount_at(level: int) -> float:
	return clampi(level, 0, get_trade_max_level(TRADE_MERCHANT_FRIEND)) * MERCHANT_DISCOUNT_PER_LEVEL


## Price at a dungeon merchant (shop, wandering merchant, D-109) for a Händlerfreund level: the
## base price minus the discount, rounded, at least 1. Free or invalid prices stay as they are.
static func merchant_price(base_price: int, merchant_level: int) -> int:
	if base_price <= 0:
		return base_price
	return maxi(1, roundi(base_price * (1.0 - merchant_discount_at(merchant_level))))


## Rare upgrades are the wandering merchant's goods: mechanic and effect upgrades (D-109).
static func is_rare_upgrade(upgrade: UpgradeData) -> bool:
	return upgrade != null and WanderingMerchant.RARE_CATEGORIES.has(upgrade.category)


## Weight of an upgrade in a choice for a Glück level: rare ones 1 + luck_bonus_at(level), else 1.
static func upgrade_weight(upgrade: UpgradeData, luck_level: int) -> float:
	return 1.0 + luck_bonus_at(luck_level) if is_rare_upgrade(upgrade) else 1.0


## Up to count different upgrades of candidates, drawn with rng. Glück 0 draws exactly like
## UpgradeManager.roll_offer (same rng calls, so seeds stay the same); from Glück I on rare upgrades
## weigh more (upgrade_weight). Hook for UpgradeManager.roll_offer (KE5).
static func roll_weighted_offer(candidates: Array[UpgradeData], rng: RandomNumberGenerator, count: int, luck_level: int) -> Array[UpgradeData]:
	var pool := candidates.duplicate()
	var offer: Array[UpgradeData] = []
	while not pool.is_empty() and offer.size() < count:
		var index := rng.randi_range(0, pool.size() - 1) if luck_bonus_at(luck_level) <= 0.0 \
				else _weighted_index(pool, rng, luck_level)
		offer.append(pool.pop_at(index))
	return offer


static func _weighted_index(pool: Array[UpgradeData], rng: RandomNumberGenerator, luck_level: int) -> int:
	var total := 0.0
	for upgrade in pool:
		total += upgrade_weight(upgrade, luck_level)
	var roll := rng.randf() * total
	for i in pool.size():
		roll -= upgrade_weight(pool[i], luck_level)
		if roll < 0.0:
			return i
	return pool.size() - 1


## The lucky amulet's upgrade: a random rare one of candidates, any one when none is rare, null
## for an empty list.
static func pick_rare_upgrade(candidates: Array[UpgradeData], rng: RandomNumberGenerator) -> UpgradeData:
	var rare: Array[UpgradeData] = []
	for upgrade in candidates:
		if is_rare_upgrade(upgrade):
			rare.append(upgrade)
	var pool := rare if not rare.is_empty() else candidates
	return null if pool.is_empty() else pool[rng.randi_range(0, pool.size() - 1)]


## Gold factor of a Proviant list: Goldregen doubles, else 1.
static func gold_factor_for(boosts: Array) -> float:
	return GOLD_RAIN_FACTOR if known_boosts(boosts).has(BOOST_GOLD_RAIN) else 1.0


## Extra max HP of a Proviant list (Heiltrank).
static func max_health_bonus_for(boosts: Array) -> float:
	return HEALING_POTION_HEALTH if known_boosts(boosts).has(BOOST_HEALING_POTION) else 0.0


## Klarsicht: immune to blindness and gloom (curses, dark traps, light-fire darkness).
static func is_blind_immune_for(boosts: Array) -> bool:
	return known_boosts(boosts).has(BOOST_CLEAR_SIGHT)


## Share of run gold and crystals paid on death or abort: Seelenanker 50 %, else 25 %.
static func loss_payout_ratio_for(boosts: Array) -> float:
	return SOUL_ANCHOR_PAYOUT_RATIO if known_boosts(boosts).has(BOOST_SOUL_ANCHOR) else RunManager.LOSS_PAYOUT_RATIO


## Number of return gates a Proviant list may open in a run (Rückkehrstein: 1).
static func return_gates_for(boosts: Array) -> int:
	return RETURN_STONE_GATES if known_boosts(boosts).has(BOOST_RETURN_STONE) else 0


## Spürnase: secret niches shimmer and branches show their reward (optics only).
static func has_keen_nose_for(boosts: Array) -> bool:
	return known_boosts(boosts).has(BOOST_KEEN_NOSE)


# --- Trading post: values per level (trading post page, D-087) ---

## Effect value of a trade level (clamped): slots 1-3, luck bonus and discount as fractions.
static func get_trade_value_at_level(id: StringName, level: int) -> float:
	match id:
		TRADE_PROVISION_SLOT:
			return float(provision_slots_at(level))
		TRADE_LUCK:
			return luck_bonus_at(level)
		TRADE_MERCHANT_FRIEND:
			return merchant_discount_at(level)
	return 0.0


## The value as shown: "2", "+10 %", "−20 %", "0 %" at level 0 of a percentage.
static func format_trade_value_at_level(id: StringName, level: int) -> String:
	var value := get_trade_value_at_level(id, level)
	if id == TRADE_PROVISION_SLOT:
		return format_number(value)
	var percent := roundi(value * 100.0)
	if percent == 0:
		return "0 %"
	return ("+%d %%" if id == TRADE_LUCK else "−%d %%") % percent


## What buying the next trade level changes, with real values (D-087): "Plätze 1 → 2", "Seltene
## Upgrades +10 % → +20 %"; at the maximum "Händlerpreise −20 % (max.)". Empty for unknown ids.
static func describe_trade_step(id: StringName, level: int) -> String:
	if not TRADE_LEVELS.has(id):
		return ""
	var max_level := get_trade_max_level(id)
	level = clampi(level, 0, max_level)
	var stat := Loc.t(StringName(TRADE_LEVELS[id]["stat"]))
	if level >= max_level:
		return "%s %s (max.)" % [stat, format_trade_value_at_level(id, level)]
	return "%s %s → %s" % [stat, format_trade_value_at_level(id, level), format_trade_value_at_level(id, level + 1)]


static func describe_next_trade_level(id: StringName) -> String:
	return describe_trade_step(id, get_trade_level(id))


# --- Proviant and trade levels at the player (co-op state, D-088, KONZEPT §9) ---

## Proviant and trade levels as a plain dictionary (lobby message, run state):
## {"boosts": ["gold_rain", …], "luck": int, "merchant_friend": int}. boosts are the run's
## (RunManager.get_run_boosts()) or, for the lobby before the start, the packed ones.
static func provision_snapshot(boosts: Array) -> Dictionary:
	var ids: Array = []
	for id in known_boosts(boosts):
		ids.append(String(id))
	return {"boosts": ids, "luck": get_trade_level(TRADE_LUCK), "merchant_friend": get_trade_level(TRADE_MERCHANT_FRIEND)}


## A Proviant snapshot from elsewhere (lobby message, older client) cleaned up: known ids only, each
## once, at most the largest slot count; levels clamped to their maximum.
static func sanitize_provisions(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var raw_boosts: Variant = source.get("boosts", [])
	var ids: Array = []
	if raw_boosts is Array or raw_boosts is PackedStringArray:
		for id in known_boosts(Array(raw_boosts)):
			if ids.size() < provision_slots_at(get_trade_max_level(TRADE_PROVISION_SLOT)):
				ids.append(String(id))
	var luck: Variant = source.get("luck", 0)
	var merchant: Variant = source.get("merchant_friend", 0)
	return {
		"boosts": ids,
		"luck": clampi(int(luck), 0, get_trade_max_level(TRADE_LUCK)) if _is_number(luck) else 0,
		"merchant_friend": clampi(int(merchant), 0, get_trade_max_level(TRADE_MERCHANT_FRIEND)) if _is_number(merchant) else 0,
	}


## Puts a Proviant snapshot on a player (cleaned) and resets the return stone for the new run.
static func set_player_provisions(player: Node, snapshot: Dictionary) -> void:
	if player == null or not is_instance_valid(player):
		return
	player.set_meta(PROVISION_META, sanitize_provisions(snapshot))
	if player.has_meta(RETURN_STONE_USED_META):
		player.remove_meta(RETURN_STONE_USED_META)


## The Proviant snapshot of a player in this run; {} without one (guild runs, tests): every getter
## below then answers "no Proviant, level 0".
static func get_player_provisions(player: Node) -> Dictionary:
	if player == null or not is_instance_valid(player) or not player.has_meta(PROVISION_META):
		return {}
	var value: Variant = player.get_meta(PROVISION_META)
	return value if value is Dictionary else {}


static func get_player_boosts(player: Node) -> Array[StringName]:
	return known_boosts(get_player_provisions(player).get("boosts", []))


static func player_has_boost(player: Node, id: StringName) -> bool:
	return get_player_boosts(player).has(id)


static func player_luck_level(player: Node) -> int:
	return int(get_player_provisions(player).get("luck", 0))


static func player_merchant_level(player: Node) -> int:
	return int(get_player_provisions(player).get("merchant_friend", 0))


## Klarsicht at a player (hook for PlayerCurses.vision_factor, Player.blind, dark zones).
static func player_blind_immune(player: Node) -> bool:
	return is_blind_immune_for(get_player_boosts(player))


## Spürnase at a player (hook for the secret niche shimmer and the branch reward preview).
static func player_has_keen_nose(player: Node) -> bool:
	return has_keen_nose_for(get_player_boosts(player))


## Death and abort payout share of a player's world (Seelenanker 50 %, else 25 %).
static func player_loss_payout_ratio(player: Node) -> float:
	return loss_payout_ratio_for(get_player_boosts(player))


## Gold factor of a group run (Vorschlag, KONZEPT §9 says nothing): the shared purse gets the mean
## of the players' factors, so one Goldregen among four players gives +25 %, four give double.
## 1.0 without players.
static func group_gold_factor(players: Array) -> float:
	var total := 0.0
	var count := 0
	for player: Variant in players:
		if player is Node and is_instance_valid(player):
			total += gold_factor_for(get_player_boosts(player))
			count += 1
	return total / count if count > 0 else 1.0


## A dungeon merchant's price for this buyer (own Händlerfreund level): the host prices every
## purchase for the player who buys (hook for EconomySystem.try_buy and the shop's price labels).
static func player_merchant_price(player: Node, base_price: int) -> int:
	return merchant_price(base_price, player_merchant_level(player))


## The return stone of a player is ready: packed for this run and not used yet. The host asks this
## and SoulGateRules.can_open_return_gate(room, false) before SoulGate.open_return_gate.
static func can_use_return_stone(player: Node) -> bool:
	return player_has_boost(player, BOOST_RETURN_STONE) and not is_return_stone_used(player)


static func is_return_stone_used(player: Node) -> bool:
	return player != null and is_instance_valid(player) and player.get_meta(RETURN_STONE_USED_META, false) == true


## Marks the player's return stone as used (the host, after the gate opened).
static func mark_return_stone_used(player: Node) -> void:
	if player != null and is_instance_valid(player):
		player.set_meta(RETURN_STONE_USED_META, true)


# --- Run start ---

## Applies the forge of the loaded world and this run's Proviant (RunManager.get_run_boosts(), taken
## from the save at start_run) with the world's trade levels to a freshly spawned dungeon player.
## Call once per run after the player is bound to the context (DungeonManager.on_player_spawned).
## Returns short lines in the current language describing the Proviant that was applied (for the
## banner; the forge part comes from get_forge_bonus_parts()).
static func apply_to_run(player: Player, context: DungeonContext) -> Array[String]:
	if player == null:
		return []
	apply_forge_snapshot(player, forge_snapshot(), context)
	return apply_provisions(player, provision_snapshot(RunManager.get_run_boosts()), context)


## Puts a Proviant snapshot on a player at the run start (stored at the player, D-088) and applies
## what acts once: Heiltrank raises max HP (full health), the Glücksamulett gives a rare upgrade.
## Everything else is asked later through the player_* getters (Klarsicht, Spürnase, Seelenanker,
## Rückkehrstein, Glück, Händlerfreund) or get_gold_multiplier (Goldregen). The host of a quick game
## calls it for every player with that player's snapshot from the lobby (KONZEPT §9); guild runs
## have no Proviant. Returns the banner lines of the applied Proviant.
static func apply_provisions(player: Player, snapshot: Dictionary, context: DungeonContext = null) -> Array[String]:
	var lines: Array[String] = []
	if player == null:
		return lines
	set_player_provisions(player, snapshot)
	for id in get_player_boosts(player):
		match id:
			BOOST_HEALING_POTION:
				if player.health != null:
					player.health.reset(player.health.get_max_health() + max_health_bonus_for([id]))
					lines.append(get_boost_applied_line(id))
			BOOST_LUCKY_AMULET:
				var upgrade := _grant_rare_upgrade(context, player)
				if upgrade != null:
					lines.append(get_boost_applied_line(id, DataTexts.upgrade_name(upgrade)))
			_:
				lines.append(get_boost_applied_line(id))
	return lines


## The lucky amulet's rare upgrade from the player's upgrade manager (dungeon RNG); null without one.
## In a relay room every player has their own manager at the host (NetDungeon.manager_for).
static func _grant_rare_upgrade(context: DungeonContext, player: Player = null) -> UpgradeData:
	if context == null or context.upgrade_manager == null:
		return null
	var manager := context.upgrade_manager
	var owned := context.get_owned_weapons()
	var dungeon := context.manager as DungeonManager
	if player != null and dungeon != null and dungeon.net != null and dungeon.net.has_method(&"manager_for"):
		manager = dungeon.net.manager_for(player)
		owned = player.weapon_controller.get_owned_weapons()
	var rng := context.rng if context.rng != null else RandomNumberGenerator.new()
	var upgrade := pick_rare_upgrade(manager.get_available_upgrades(owned), rng)
	if upgrade == null or not manager.acquire_upgrade(upgrade):
		return null
	return upgrade


## Puts a forge snapshot on a player at the run start: stored at the player (weapon levels, Laterne),
## the Schildplatte's shield and the start weapons. The host of a quick game calls it for every
## player with that player's snapshot from the lobby (KONZEPT §9); solo apply_to_run() does it.
static func apply_forge_snapshot(player: Player, snapshot: Dictionary, context: DungeonContext = null) -> void:
	if player == null:
		return
	var clean := sanitize_snapshot(snapshot)
	set_player_forge(player, clean)
	var shield := int(clean["shield_plate"]) * SHIELD_PER_LEVEL
	if shield > 0.0 and player.shield != null:
		player.shield.add_shield(shield)
	_equip_start_weapons(player, clean["start"], context)


static func _equip_start_weapons(player: Player, start: Array, context: DungeonContext) -> void:
	var controller := player.weapon_controller
	if controller == null or start.is_empty():
		return
	var first := _load_weapon(StringName(start[0]), context)
	var current := controller.get_weapon(0)
	if first != null and (current == null or current.id != first.id):
		controller.equip_weapon(first, 0)
	if start.size() < 2:
		return
	var second := _load_weapon(StringName(start[1]), context)
	var slot := controller.find_free_slot()
	if second != null and slot >= 0 and controller.can_equip(second, slot):
		controller.equip_weapon(second, slot)


## The run's copy of a weapon (the dungeon's pool, so upgrades match), else its data file.
static func _load_weapon(weapon_id: StringName, context: DungeonContext) -> WeaponData:
	if not WEAPON_PATHS.has(weapon_id):
		return null
	if context != null:
		for weapon in context.weapon_pool:
			if weapon != null and weapon.id == weapon_id:
				return weapon
	return load(WEAPON_PATHS[weapon_id]) as WeaponData


# --- Merge rules of the v5 fields (KONZEPT §10; pure, for KF9) ---

## Levels of two states of a world ([meta_upgrades], [trade_levels]): the maximum per key, keys of
## both. Non-numbers count as 0.
static func merge_levels(a: Dictionary, b: Dictionary) -> Dictionary:
	var result := {}
	for source: Dictionary in [a, b]:
		for key: Variant in source:
			var value: Variant = source[key]
			var level := maxi(0, int(value)) if _is_number(value) else 0
			result[key] = maxi(int(result.get(key, 0)), level)
	return result


## Unlocks of two states (lists of ids): the union, a's order first, then b's new ids.
static func merge_unlocked(a: Array, b: Array) -> PackedStringArray:
	var result := PackedStringArray()
	for source: Array in [a, b]:
		for item: Variant in source:
			var id := str(item)
			if not result.has(id):
				result.append(id)
	return result


## The refund marker of the v5 migration ([migration] v5_refund_gold): the larger one, so a world
## that was refunded on one device is never refunded again after a merge.
static func merge_refund_marker(a: Variant, b: Variant) -> int:
	return maxi(maxi(0, int(a)) if _is_number(a) else 0, maxi(0, int(b)) if _is_number(b) else 0)


## Start weapons a set of forge levels unlocks: the sword plus every Arsenal entry at level 1.
static func unlocked_weapons_from_levels(levels: Dictionary) -> PackedStringArray:
	var result := PackedStringArray([String(DEFAULT_START_WEAPON)])
	for weapon in WEAPON_ORDER:
		var level: Variant = levels.get(String(arsenal_id(weapon)), levels.get(arsenal_id(weapon), 0))
		if weapon != DEFAULT_START_WEAPON and _is_number(level) and int(level) >= 1:
			result.append(String(weapon))
	return result


## The merge rule of a save field ("section/key"), else of its section; MERGE_LAST_PLAYED by default
## (D-188 rule 7: new fields without a class come from the last played state).
static func merge_rule(section: String, key := "") -> StringName:
	var full := "%s/%s" % [section, key]
	if MERGE_RULES.has(full):
		return MERGE_RULES[full]
	return MERGE_RULES.get(section, MERGE_LAST_PLAYED)


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _clamped_level(value: Variant, id: StringName) -> int:
	return clampi(int(value), 0, get_max_level(id)) if _is_number(value) else 0

class_name MetaProgression
extends RefCounted
## Permanent village upgrades (forge, D-087 table: 20 levels) and one-run Proviant boosts bought
## with Seelenkristalle (D-078; the crystal exchange was removed by D-087). Levels, currencies and
## pending boosts are stored by SaveManager; this class holds the rules (costs, limits, effects) and
## applies them to a run. Which upgrades are open decides MetaUnlocks. All values are TESTWERTE.

# --- Forge upgrades ---
const VITALITY: StringName = &"vitality"
const START_SHIELD: StringName = &"start_shield"
const SHARPNESS: StringName = &"sharpness"
const GOLD_GREED: StringName = &"gold_greed"
const DASH_TRAINING: StringName = &"dash_training"
const ARSENAL: StringName = &"arsenal"

const UPGRADE_ORDER: Array[StringName] = [VITALITY, START_SHIELD, SHARPNESS, GOLD_GREED, DASH_TRAINING, ARSENAL]
## id -> display name, description per level, one-line summary and the label of the value it
## changes (forge cards, D-087), gold cost of each level (index = level - 1).
## The texts are translation keys (D-111); read them translated with get_upgrade_name(),
## get_upgrade_summary(), get_upgrade_effect() and get_upgrade_stat().
## TESTWERT: levels and costs from the D-087 table (28 -> 20 levels); first level of Vitality 20 and
## Start shield 30 so an early first death buys something (D-167). Changing the number of levels
## needs a save migration (SaveManager.migrate, D-059).
const UPGRADES := {
	VITALITY: {"name": &"FORGE_VITALITY_NAME", "effect": &"FORGE_VITALITY_EFFECT", "summary": &"FORGE_VITALITY_SUMMARY",
		"stat": &"FORGE_VITALITY_STAT", "costs": [20, 80, 140, 220, 320]},
	START_SHIELD: {"name": &"FORGE_START_SHIELD_NAME", "effect": &"FORGE_START_SHIELD_EFFECT", "summary": &"FORGE_START_SHIELD_SUMMARY",
		"stat": &"FORGE_START_SHIELD_STAT", "costs": [30, 90, 160]},
	SHARPNESS: {"name": &"FORGE_SHARPNESS_NAME", "effect": &"FORGE_SHARPNESS_EFFECT", "summary": &"FORGE_SHARPNESS_SUMMARY",
		"stat": &"FORGE_SHARPNESS_STAT", "costs": [70, 150, 260, 400]},
	GOLD_GREED: {"name": &"FORGE_GOLD_GREED_NAME", "effect": &"FORGE_GOLD_GREED_EFFECT", "summary": &"FORGE_GOLD_GREED_SUMMARY",
		"stat": &"FORGE_GOLD_GREED_STAT", "costs": [60, 140, 250]},
	DASH_TRAINING: {"name": &"FORGE_DASH_TRAINING_NAME", "effect": &"FORGE_DASH_TRAINING_EFFECT", "summary": &"FORGE_DASH_TRAINING_SUMMARY",
		"stat": &"FORGE_DASH_TRAINING_STAT", "costs": [60, 140, 260]},
	ARSENAL: {"name": &"FORGE_ARSENAL_NAME", "effect": &"FORGE_ARSENAL_EFFECT", "summary": &"FORGE_ARSENAL_SUMMARY",
		"stat": &"FORGE_ARSENAL_STAT", "costs": [80, 160]},
}
## TESTWERT (D-087): effect per level.
const HEALTH_PER_LEVEL := 1.0
const SHIELD_PER_LEVEL := 3.0
const DAMAGE_PER_LEVEL := 0.10
const GOLD_PER_LEVEL := 0.15
const DASH_COOLDOWN_PER_LEVEL := 0.15
const MIN_DASH_COOLDOWN := 0.3
## Player defaults the forge values are shown against ("Max-HP 6 → 7"). Mirror of
## HealthComponent.max_health and Player.dash_cooldown; test_meta_values checks they still match.
const BASE_MAX_HEALTH := 6.0
const BASE_DASH_COOLDOWN := 1.5
## Arsenal value text per level (0..2), translation keys.
const ARSENAL_LEVEL_TEXTS: Array[StringName] = [&"FORGE_ARSENAL_NONE", &"FORGE_ARSENAL_BOW", &"FORGE_ARSENAL_BOW_OR_STAFF"]

# --- Arsenal start weapons ---
const WEAPON_BOW: StringName = &"bow"
const WEAPON_STAFF: StringName = &"staff"
const WEAPON_PATHS := {
	WEAPON_BOW: "res://weapons/data/bow.tres",
	WEAPON_STAFF: "res://weapons/data/staff.tres",
}
## Start weapon id -> translation key of its short name (get_weapon_name()).
const WEAPON_NAMES := {WEAPON_BOW: &"META_WEAPON_BOW", WEAPON_STAFF: &"META_WEAPON_STAFF"}

# --- Run-start banner (D-087) ---
## Translation key; a Label translates it by itself, get_run_banner_title() gives the text.
const RUN_BANNER_TITLE: StringName = &"META_RUN_BANNER_TITLE"

# --- Trader (Proviant only; no crystal exchange since D-087) ---
const BOOST_POTION: StringName = &"potion"
const BOOST_UPGRADE: StringName = &"upgrade"
const BOOST_GOLD: StringName = &"gold"
const BOOST_ORDER: Array[StringName] = [BOOST_POTION, BOOST_UPGRADE, BOOST_GOLD]
## Proviant for the next run only; price in Seelenkristalle. Texts are translation keys
## (get_boost_name(), get_boost_effect()).
const BOOSTS := {
	BOOST_POTION: {"name": &"BOOST_POTION_NAME", "effect": &"BOOST_POTION_EFFECT", "price": 1},
	BOOST_UPGRADE: {"name": &"BOOST_UPGRADE_NAME", "effect": &"BOOST_UPGRADE_EFFECT", "price": 2},
	BOOST_GOLD: {"name": &"BOOST_GOLD_NAME", "effect": &"BOOST_GOLD_EFFECT", "price": 2},
}
const BOOST_POTION_HEALTH := 2.0
const BOOST_GOLD_BONUS := 0.25


# --- Texts in the current language (D-111) ---

static func get_upgrade_name(id: StringName) -> String:
	return _info_text(UPGRADES, id, "name")


static func get_upgrade_summary(id: StringName) -> String:
	return _info_text(UPGRADES, id, "summary")


static func get_upgrade_effect(id: StringName) -> String:
	return _info_text(UPGRADES, id, "effect")


## Label of the value an upgrade changes ("Max-HP", "Schaden", "Zweite Startwaffe:").
static func get_upgrade_stat(id: StringName) -> String:
	return _info_text(UPGRADES, id, "stat")


static func get_boost_name(id: StringName) -> String:
	return _info_text(BOOSTS, id, "name")


static func get_boost_effect(id: StringName) -> String:
	return _info_text(BOOSTS, id, "effect")


## Short name of an Arsenal start weapon ("Bogen", "Stab"); the id for unknown weapons.
static func get_weapon_name(id: StringName) -> String:
	return Loc.t(WEAPON_NAMES[id]) if WEAPON_NAMES.has(id) else String(id)


static func get_run_banner_title() -> String:
	return Loc.t(RUN_BANNER_TITLE)


static func _info_text(table: Dictionary, id: StringName, field: String) -> String:
	if not table.has(id):
		return ""
	return Loc.t(StringName(table[id][field]))


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
static func try_buy(id: StringName) -> bool:
	if not can_buy(id):
		return false
	var cost := get_next_cost(id)
	if not SaveManager.try_spend_permanent_gold(cost):
		return false
	SaveManager.set_meta_level(id, get_level(id) + 1)
	if id == ARSENAL and SaveManager.get_second_weapon() == &"":
		SaveManager.set_second_weapon(WEAPON_BOW)
	SaveManager.save_game()
	return true


## Start weapons the Arsenal level allows (level 1: bow, level 2: bow or staff).
static func get_available_second_weapons() -> Array[StringName]:
	var result: Array[StringName] = []
	var level := get_level(ARSENAL)
	if level >= 1:
		result.append(WEAPON_BOW)
	if level >= 2:
		result.append(WEAPON_STAFF)
	return result


## Chosen second start weapon, or &"" without Arsenal.
static func get_second_weapon() -> StringName:
	var available := get_available_second_weapons()
	if available.is_empty():
		return &""
	var chosen := SaveManager.get_second_weapon()
	return chosen if available.has(chosen) else available[0]


static func set_second_weapon(id: StringName) -> bool:
	if not get_available_second_weapons().has(id):
		return false
	SaveManager.set_second_weapon(id)
	SaveManager.save_game()
	return true


# --- Effect getters (used by the run) ---

static func get_bonus_max_health() -> float:
	return get_level(VITALITY) * HEALTH_PER_LEVEL


static func get_start_shield() -> float:
	return get_level(START_SHIELD) * SHIELD_PER_LEVEL


## Additive percent damage bonus as a fraction (0.05 per Schärfe level). Add it to the
## DAMAGE_PERCENT sum of WeaponController.get_effective_damage().
static func get_damage_bonus() -> float:
	return get_level(SHARPNESS) * DAMAGE_PER_LEVEL


static func get_dash_cooldown_reduction() -> float:
	return get_level(DASH_TRAINING) * DASH_COOLDOWN_PER_LEVEL


## Factor for enemy gold drops: Goldgier levels plus an active Goldbeutel boost.
static func get_gold_multiplier() -> float:
	var multiplier := 1.0 + get_level(GOLD_GREED) * GOLD_PER_LEVEL
	if RunManager.has_run_boost(BOOST_GOLD):
		multiplier += BOOST_GOLD_BONUS
	return multiplier


# --- Values per level (forge display, D-087) ---

## Effect value of an upgrade at a level (clamped to 0..max): max HP incl. the player's base,
## start shield, damage or gold bonus as a fraction, dash cooldown in seconds, Arsenal = level.
static func get_value_at_level(id: StringName, level: int) -> float:
	level = clampi(level, 0, get_max_level(id))
	match id:
		VITALITY:
			return BASE_MAX_HEALTH + level * HEALTH_PER_LEVEL
		START_SHIELD:
			return level * SHIELD_PER_LEVEL
		SHARPNESS:
			return level * DAMAGE_PER_LEVEL
		GOLD_GREED:
			return level * GOLD_PER_LEVEL
		DASH_TRAINING:
			return maxf(MIN_DASH_COOLDOWN, BASE_DASH_COOLDOWN - level * DASH_COOLDOWN_PER_LEVEL)
		ARSENAL:
			return float(level)
	return 0.0


## The value at a level as shown in the forge: "7", "+10 %", "1,35 s", "Bogen".
static func format_value_at_level(id: StringName, level: int) -> String:
	var value := get_value_at_level(id, level)
	match id:
		SHARPNESS, GOLD_GREED:
			return "+%d %%" % roundi(value * 100.0)
		DASH_TRAINING:
			return "%s s" % format_number(value)
		ARSENAL:
			return Loc.t(ARSENAL_LEVEL_TEXTS[clampi(int(value), 0, ARSENAL_LEVEL_TEXTS.size() - 1)])
	return format_number(value)


## What buying the next level changes, with real values: "Max-HP 6 → 7", "Schaden +5 % → +10 %";
## at the maximum "Max-HP 11 (max.)". Empty for unknown ids.
static func describe_level_step(id: StringName, level: int) -> String:
	if not UPGRADES.has(id):
		return ""
	level = clampi(level, 0, get_max_level(id))
	var stat := get_upgrade_stat(id)
	var current := format_value_at_level(id, level)
	if level >= get_max_level(id):
		return "%s %s (max.)" % [stat, current]
	return "%s %s → %s" % [stat, current, format_value_at_level(id, level + 1)]


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

## Short parts for the given forge levels (id -> level) and second start weapon, e.g.
## ["+2 Max-HP", "+20 % Schaden", "Bogen"]. Upgrades at level 0 are left out.
static func describe_forge_bonuses(levels: Dictionary, second_weapon: StringName) -> Array[String]:
	var parts: Array[String] = []
	for id in UPGRADE_ORDER:
		var level := clampi(int(levels.get(id, 0)), 0, get_max_level(id))
		if level <= 0:
			continue
		match id:
			VITALITY:
				parts.append(Loc.t(&"META_BONUS_MAX_HP", [format_number(level * HEALTH_PER_LEVEL)]))
			START_SHIELD:
				parts.append(Loc.t(&"META_BONUS_SHIELD", [format_number(level * SHIELD_PER_LEVEL)]))
			SHARPNESS:
				parts.append(Loc.t(&"META_BONUS_DAMAGE", [roundi(level * DAMAGE_PER_LEVEL * 100.0)]))
			GOLD_GREED:
				parts.append(Loc.t(&"META_BONUS_GOLD", [roundi(level * GOLD_PER_LEVEL * 100.0)]))
			DASH_TRAINING:
				var reduction := BASE_DASH_COOLDOWN - get_value_at_level(DASH_TRAINING, level)
				parts.append(Loc.t(&"META_BONUS_DASH", [format_number(reduction)]))
			ARSENAL:
				if WEAPON_NAMES.has(second_weapon):
					parts.append(get_weapon_name(second_weapon))
	return parts


## describe_forge_bonuses() for the current save.
static func get_forge_bonus_parts() -> Array[String]:
	var levels := {}
	for id in UPGRADE_ORDER:
		levels[id] = get_level(id)
	return describe_forge_bonuses(levels, get_second_weapon())


## Banner text for the run start: all forge bonuses plus the Proviant lines apply_to_run()
## returned, e.g. "+2 Max-HP · +20 % Schaden · Bogen · Heiltrank: +2 Max-HP". Empty if nothing
## applies (then no banner). Show it with get_run_banner_title() as the title.
static func get_run_start_summary(applied_boosts: Array[String]) -> String:
	var parts := get_forge_bonus_parts()
	parts.append_array(applied_boosts)
	return " · ".join(parts)


## Single-line variant: "Aus dem Dorf: +2 Max-HP, +20 % Schaden, Bogen". Empty if nothing applies.
static func get_run_start_banner_line(applied_boosts: Array[String]) -> String:
	var parts := get_forge_bonus_parts()
	parts.append_array(applied_boosts)
	if parts.is_empty():
		return ""
	return "%s: %s" % [get_run_banner_title(), ", ".join(parts)]


# --- Trader rules (Proviant) ---

static func get_boost_price(id: StringName) -> int:
	return BOOSTS[id]["price"] if BOOSTS.has(id) else -1


static func can_buy_boost(id: StringName) -> bool:
	return BOOSTS.has(id) and not SaveManager.has_pending_boost(id) \
		and SaveManager.get_permanent_crystals() >= get_boost_price(id)


## One boost of each kind can be pending; it is consumed by the next RunManager.start_run().
static func try_buy_boost(id: StringName) -> bool:
	if not can_buy_boost(id):
		return false
	if not SaveManager.try_spend_permanent_crystals(get_boost_price(id)):
		return false
	SaveManager.add_pending_boost(id)
	SaveManager.save_game()
	return true


# --- Run start ---

## Applies all permanent upgrades and this run's Proviant boosts to a freshly spawned dungeon
## player. Call once per run after the player is bound to the context (DungeonManager.
## on_player_spawned). Returns short lines in the current language describing what was applied
## (for a banner).
static func apply_to_run(player: Player, context: DungeonContext) -> Array[String]:
	var applied: Array[String] = []
	if player == null:
		return applied
	var bonus_health := get_bonus_max_health()
	if RunManager.has_run_boost(BOOST_POTION):
		bonus_health += BOOST_POTION_HEALTH
		applied.append(Loc.t(&"META_APPLIED_POTION", [int(BOOST_POTION_HEALTH)]))
	if bonus_health > 0.0:
		player.health.reset(player.health.get_max_health() + bonus_health)
	var shield := get_start_shield()
	if shield > 0.0:
		player.shield.add_shield(shield)
	var dash_reduction := get_dash_cooldown_reduction()
	if dash_reduction > 0.0:
		player.dash_cooldown = maxf(MIN_DASH_COOLDOWN, player.dash_cooldown - dash_reduction)
	var weapon := _load_second_weapon(context)
	if weapon != null:
		var slot := player.weapon_controller.find_free_slot()
		if slot >= 0 and player.weapon_controller.can_equip(weapon, slot):
			player.weapon_controller.equip_weapon(weapon, slot)
	if RunManager.has_run_boost(BOOST_UPGRADE) and context != null and context.upgrade_manager != null:
		var rng := context.rng if context.rng != null else RandomNumberGenerator.new()
		var offer := context.upgrade_manager.roll_offer(context.get_owned_weapons(), rng, 1)
		if not offer.is_empty() and context.upgrade_manager.acquire_upgrade(offer[0]):
			applied.append(Loc.t(&"META_APPLIED_UPGRADE", [DataTexts.upgrade_name(offer[0])]))
	if RunManager.has_run_boost(BOOST_GOLD):
		applied.append(Loc.t(&"META_APPLIED_GOLD", [roundi(BOOST_GOLD_BONUS * 100.0)]))
	return applied


static func _load_second_weapon(context: DungeonContext) -> WeaponData:
	var id := get_second_weapon()
	if id == &"":
		return null
	var wanted := WeaponData.WeaponType.BOW if id == WEAPON_BOW else WeaponData.WeaponType.STAFF
	if context != null:
		for weapon in context.weapon_pool:
			if weapon != null and weapon.weapon_type == wanted:
				return weapon
	return load(WEAPON_PATHS[id]) as WeaponData

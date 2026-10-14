class_name WagerRules
extends RefCounted
## Pure rules of the wager altar (KONZEPT_RAEUME §5, D-104, D-109): which condition, what breaks
## it, what it pays. A trial condition (no hit, under 30 s, secondary weapon only) is a goal; a curse
## (light circle -40 %, enemies +15 % speed, no healing) makes the room harder and is met by clearing
## the room. Success pays soul crystals (D-109: 1-2, TESTWERTE); failure costs nothing more.
## Co-op: the condition holds for the group ("no hit" = no player is hit), D-104.

enum Condition { NO_HIT, UNDER_TIME, SECONDARY_ONLY, CURSE_GLOOM, CURSE_HASTE, CURSE_NO_HEAL }

## Time limit of UNDER_TIME, from the start of the fight (door closes) to the cleared room.
const TIME_LIMIT := 30.0  # TESTWERT
## Light circle of CURSE_GLOOM, enemy speed of CURSE_HASTE (KONZEPT §5).
const GLOOM_VISION_FACTOR := 0.6  # TESTWERT
const HASTE_SPEED_FACTOR := 1.15  # TESTWERT
## Soul crystals on success per condition (D-109: 1-2). TESTWERTE
const REWARD_CRYSTALS := {
	Condition.NO_HIT: 2,
	Condition.UNDER_TIME: 1,
	Condition.SECONDARY_ONLY: 1,
	Condition.CURSE_GLOOM: 1,
	Condition.CURSE_HASTE: 1,
	Condition.CURSE_NO_HEAL: 1,
}
## Co-op (D-109, MP5): crystals for every player instead of once for the group.
const CRYSTALS_PER_PLAYER := true  # TESTWERT
## Text keys (DungeonTexts) per condition: name and short rule.
const NAME_KEYS := {
	Condition.NO_HIT: &"WAGER_NO_HIT",
	Condition.UNDER_TIME: &"WAGER_UNDER_TIME",
	Condition.SECONDARY_ONLY: &"WAGER_SECONDARY_ONLY",
	Condition.CURSE_GLOOM: &"WAGER_CURSE_GLOOM",
	Condition.CURSE_HASTE: &"WAGER_CURSE_HASTE",
	Condition.CURSE_NO_HEAL: &"WAGER_CURSE_NO_HEAL",
}


static func is_curse(condition: int) -> bool:
	return condition in [Condition.CURSE_GLOOM, Condition.CURSE_HASTE, Condition.CURSE_NO_HEAL]


## Conditions the altar may offer: "secondary weapon only" needs a second weapon.
static func get_available(has_second_weapon: bool) -> Array[Condition]:
	var available: Array[Condition] = []
	for condition: Condition in Condition.values():
		if condition == Condition.SECONDARY_ONLY and not has_second_weapon:
			continue
		available.append(condition)
	return available


## One condition from one roll in [0, 1), all available ones equally likely.
static func pick(roll: float, has_second_weapon: bool) -> Condition:
	var available := get_available(has_second_weapon)
	return available[mini(floori(roll * available.size()), available.size() - 1)]


## Symbol in wager_icons.png (SPRITES_V5 §3): same order as Condition.
static func icon_index(condition: int) -> int:
	return clampi(condition, 0, 5)


static func get_reward(condition: int) -> int:
	return REWARD_CRYSTALS.get(condition, 1)


## Crystals the run gets for a won wager with this many players.
static func get_payout(condition: int, players: int) -> int:
	return get_reward(condition) * (maxi(1, players) if CRYSTALS_PER_PLAYER else 1)


# --- What breaks a condition ---

## A player was hit (any hit that went through, shield included).
static func breaks_on_hit(condition: int) -> bool:
	return condition == Condition.NO_HIT


## An attack or special with weapon slot (0 = first weapon, 1 = second weapon).
static func breaks_on_attack(condition: int, slot: int) -> bool:
	return condition == Condition.SECONDARY_ONLY and slot != 1


static func breaks_on_time(condition: int, elapsed: float) -> bool:
	return condition == Condition.UNDER_TIME and elapsed > TIME_LIMIT


## Seconds left for UNDER_TIME (-1 for every other condition).
static func time_left(condition: int, elapsed: float) -> float:
	return maxf(0.0, TIME_LIMIT - elapsed) if condition == Condition.UNDER_TIME else -1.0


# --- Texts ---

static func get_condition_name(condition: int) -> String:
	var key: StringName = NAME_KEYS.get(condition, &"")
	if condition == Condition.UNDER_TIME:
		return DungeonTexts.t(key, [roundi(TIME_LIMIT)])
	return DungeonTexts.t(key)


static func get_condition_rule(condition: int) -> String:
	var key := StringName(String(NAME_KEYS.get(condition, &"")) + "_RULE")
	match condition:
		Condition.UNDER_TIME:
			return DungeonTexts.t(key, [roundi(TIME_LIMIT)])
		Condition.CURSE_GLOOM:
			return DungeonTexts.t(key, [roundi((1.0 - GLOOM_VISION_FACTOR) * 100.0)])
		Condition.CURSE_HASTE:
			return DungeonTexts.t(key, [roundi((HASTE_SPEED_FACTOR - 1.0) * 100.0)])
	return DungeonTexts.t(key)

class_name DangerRank
extends RefCounted
## Danger level G and rank (D-194, D-196, KONZEPT §3, §3.1): how hard a run starts and the name of
## that level. G comes from two things: experience (the account level, a cap that only rises) and
## skill (the deepest room of the last runs, can fall like matchmaking); G = min(G_level, G_skill).
## The player never picks it (D-196): solo runs use the own level, groups the level the host
## computes from all players (KE2, online/coop_rules.gd). The rank is only the name of G: tier
## Funke, Kerze, Flamme, Laterne, Leuchtfeuer with step I–III (G 0–14), then Seelenmeister with
## step G − 14. Loot (gold, crystals, XP) grows by 5 % per level.
## Pure static functions, integer math only: a 1:1 mirror of the platform contract
## (soulwick-platform packages/contracts/src/rank.ts: dangerFromLevel, medianRoom, dangerFromSkill,
## dangerLevel, rankForDanger, DANGER_MAX; runXp's dangerBonus in xp.ts). Change both together.

## TESTWERT: account levels per danger step (G_level = floor((L − 1) / 2)); DANGER_LEVELS_PER_STEP.
const LEVELS_PER_STEP := 2
## TESTWERT: rooms of the median deepest room per danger step (G_skill = floor(median / 5) + 1).
const ROOMS_PER_STEP := 5
## TESTWERT: how many of the newest runs count for the skill part (DANGER_RECENT_RUNS).
const RECENT_RUNS := 5
## TESTWERT: below this many runs the skill part is unknown and the level part decides alone.
const MIN_RUNS := 3
## TESTWERT: highest danger level that still raises the XP of a run; higher ones count as this.
## Not a limit of the rank itself (contract DANGER_MAX).
const DANGER_MAX := 30
## danger_from_skill() with fewer than MIN_RUNS runs (the contract's null).
const SKILL_UNKNOWN := -1
## TESTWERT: loot (gold, crystals, XP) per danger level in percent: factor 1 + 0.05 · G
## (contract XP_DANGER_BONUS_PERCENT).
const LOOT_PERCENT_PER_LEVEL := 5
## Danger levels per tier below Seelenmeister (steps I, II, III).
const STEPS_PER_TIER := 3
## Rank tiers, lowest first (contract RankTier; ids match art/ui/ranks/rank_<id>.png, SPRITES_V13 §B3).
const SPARK: StringName = &"spark"
const CANDLE: StringName = &"candle"
const FLAME: StringName = &"flame"
const LANTERN: StringName = &"lantern"
const BEACON: StringName = &"beacon"
const SOUL_MASTER: StringName = &"soul_master"
const TIERS: Array[StringName] = [SPARK, CANDLE, FLAME, LANTERN, BEACON, SOUL_MASTER]
## First danger level of Seelenmeister (5 tiers × 3 steps).
const SOUL_MASTER_DANGER := 15
## Tier -> translation key of its name (D-111).
const TIER_KEYS := {
	SPARK: &"RANK_SPARK",
	CANDLE: &"RANK_CANDLE",
	FLAME: &"RANK_FLAME",
	LANTERN: &"RANK_LANTERN",
	BEACON: &"RANK_BEACON",
	SOUL_MASTER: &"RANK_SOUL_MASTER",
}


## Experience part: floor((level − 1) / 2); level 1–2 = 0, 3–4 = 1, 5–6 = 2, 50 = 24.
static func danger_from_level(level: int) -> int:
	@warning_ignore("integer_division")
	return (maxi(level, 1) - 1) / LEVELS_PER_STEP


## Median of whole room numbers (negative ones count as 0); for an even count the mean of the two
## middle values, rounded down. 0 for an empty list.
static func median_room(rooms: Array) -> int:
	if rooms.is_empty():
		return 0
	var sorted: Array[int] = []
	for room: Variant in rooms:
		sorted.append(maxi(0, int(room)))
	sorted.sort()
	@warning_ignore("integer_division")
	var middle := sorted.size() / 2
	if sorted.size() % 2 == 1:
		return sorted[middle]
	@warning_ignore("integer_division")
	return (sorted[middle - 1] + sorted[middle]) / 2


## Skill part: floor(median of the deepest rooms / 5) + 1. recent_deepest_rooms is newest first;
## only the first RECENT_RUNS values count. SKILL_UNKNOWN with fewer than MIN_RUNS runs.
static func danger_from_skill(recent_deepest_rooms: Array) -> int:
	var recent := recent_deepest_rooms.slice(0, RECENT_RUNS)
	if recent.size() < MIN_RUNS:
		return SKILL_UNKNOWN
	@warning_ignore("integer_division")
	return median_room(recent) / ROOMS_PER_STEP + 1


## The danger level G = min(G_level, G_skill); with fewer than MIN_RUNS runs G_level alone.
## recent_deepest_rooms newest first.
static func danger_level(level: int, recent_deepest_rooms: Array) -> int:
	var by_level := danger_from_level(level)
	var by_skill := danger_from_skill(recent_deepest_rooms)
	return by_level if by_skill == SKILL_UNKNOWN else mini(by_level, by_skill)


## Rank of a danger level: {"tier": tier id, "step": 1..3 (Seelenmeister: G − 14, no upper bound)}.
static func rank_for_danger(danger: int) -> Dictionary:
	var g := maxi(danger, 0)
	if g >= SOUL_MASTER_DANGER:
		return {"tier": SOUL_MASTER, "step": g - SOUL_MASTER_DANGER + 1}
	@warning_ignore("integer_division")
	return {"tier": TIERS[g / STEPS_PER_TIER], "step": g % STEPS_PER_TIER + 1}


## Name of a tier in the current language ("Kerze").
static func tier_name(tier: StringName) -> String:
	return Loc.t(TIER_KEYS[tier]) if TIER_KEYS.has(tier) else String(tier)


## "I", "II", "III" for the steps below Seelenmeister, the number for Seelenmeister ("2").
static func step_text(rank: Dictionary) -> String:
	var step := int(rank.get("step", 1))
	if StringName(rank.get("tier", SPARK)) == SOUL_MASTER:
		return str(step)
	return ["I", "II", "III"][clampi(step, 1, STEPS_PER_TIER) - 1]


## "Kerze II", "Seelenmeister 3" (current language).
static func rank_text(danger: int) -> String:
	var rank := rank_for_danger(danger)
	return "%s %s" % [tier_name(rank["tier"]), step_text(rank)]


## Loot factor of a danger level: 1 + 0.05 · G (gold, crystals, XP).
static func loot_factor(danger: int) -> float:
	return 1.0 + loot_percent(danger) / 100.0


## The loot bonus in whole percent (G 4 -> 20), for "Beute +20 %".
static func loot_percent(danger: int) -> int:
	return LOOT_PERCENT_PER_LEVEL * maxi(danger, 0)


## Bonus XP of a run like the contract's runXp: floor(xp · 5 · G / 100) with G limited to
## 0..DANGER_MAX; xp is the run's sum plus the co-op bonus, the run cap comes after.
static func xp_bonus(xp: int, danger: int) -> int:
	@warning_ignore("integer_division")
	return maxi(0, xp) * LOOT_PERCENT_PER_LEVEL * clampi(danger, 0, DANGER_MAX) / 100

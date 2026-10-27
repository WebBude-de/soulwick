class_name BossRules
extends RefCounted
## Pure rules of boss and champion fights (TESTWERTE): two phases and patterns that grow with the
## boss tier (RoomSequence.get_boss_tier). Phase two starts below half health with a short,
## invulnerable roar; afterwards the enemy is faster and uses its phase-two pattern
## (EnemyData "Phase two" group). Champions use the same rules with tier 0 and milder factors.

const PHASE_TWO_THRESHOLD := 0.5
const ROAR_TIME := 1.3
const CHAMPION_ROAR_TIME := 0.7
const ENRAGE_SPEED_FACTOR := 1.25
const ENRAGE_COOLDOWN_FACTOR := 0.7
const ENRAGE_TELEGRAPH_FACTOR := 0.9
const CHAMPION_ENRAGE_SPEED_FACTOR := 1.15
const CHAMPION_ENRAGE_COOLDOWN_FACTOR := 0.8
## Chained specials get a shorter (but still visible) telegraph.
const CHAIN_TELEGRAPH_FACTOR := 0.6
const MAX_SPECIAL_REPEATS := 3
const MAX_VOLLEY_WAVES := 5
const SPIRAL_WAVE_INTERVAL := 0.18
## Living minions one summoner may have at once (keeps long fights readable).
const MAX_MINIONS := 6
const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]

## Contact damage of bosses (TESTWERTE, playtest #ddb41969 "stood inside the slime queen and took
## nothing"): a player whose hurtbox touches the boss body is hurt every CONTACT_INTERVAL seconds by
## CONTACT_DAMAGE_FACTOR of the boss hit (at least the 0.5 step) and pushed out a little. Each tick
## is its own attack instance (D-020); hit I-frames (D-017) still block in between.
const CONTACT_INTERVAL := 1.0
const CONTACT_DAMAGE_FACTOR := 0.5
const CONTACT_KNOCKBACK := 140.0
## Share of the visual body radius (the enemy hurtbox) that counts as contact. 1.0: whoever presses
## against the body from any side touches it (the body collision sits at the feet, so a player north
## of the boss stands visually inside its sprite, one south of it only at its rim).
const CONTACT_RADIUS_SHARE := 1.0
## Kills of boss minions (summons and their split children) pay no ON_KILL rewards (heal, shield):
## an endless stream of minions refilled the shield faster than the boss could hit (TESTWERT).
const BOSS_MINIONS_GRANT_KILL_REWARDS := false


## Bosses hurt on contact; normal enemies, elites and champions do not (yet).
static func has_contact_damage(enemy_data: EnemyData) -> bool:
	return enemy_data != null and enemy_data.is_boss and enemy_data.damage > 0.0


## Damage of one contact tick from the scaled boss hit; never below the smallest step (0.5).
static func contact_damage(boss_hit: float) -> float:
	if boss_hit <= 0.0:
		return 0.0
	return maxf(DamageProcessor.MIN_DAMAGE, boss_hit * CONTACT_DAMAGE_FACTOR)


## Whether kills of a minion summoned by summoner_data pay ON_KILL rewards; parent_grants passes the
## rule on from a summoner that is itself a minion (split children of a boss minion).
static func minion_grants_kill_rewards(summoner_data: EnemyData, parent_grants: bool) -> bool:
	if not parent_grants:
		return false
	if summoner_data != null and summoner_data.is_boss:
		return BOSS_MINIONS_GRANT_KILL_REWARDS
	return true


## True when the fight should switch to phase two.
static func should_enrage(current: float, maximum: float, phase: int) -> bool:
	return phase == 1 and maximum > 0.0 and current > 0.0 and current <= maximum * PHASE_TWO_THRESHOLD


## Rings per volley. Phase two adds a second ring (a spiral of three with enrage_spiral),
## every tier adds one more; from tier 2 already phase one fires two rings.
static func volley_waves(tier: int, phase: int, spiral: bool) -> int:
	var waves := 1
	if phase >= 2:
		waves = (3 if spiral else 2) + mini(tier, 2)
	elif tier >= 2:
		waves = 2
	return mini(waves, MAX_VOLLEY_WAVES)


## Additional specials chained after the first one.
static func special_repeats(tier: int, phase: int, enrage_repeats: int) -> int:
	var repeats := 0
	if phase >= 2:
		repeats = enrage_repeats + (1 if tier >= 1 else 0)
	elif tier >= 2:
		repeats = 1
	return clampi(repeats, 0, MAX_SPECIAL_REPEATS)


## Projectiles in the ring fired on landing. From tier 1 phase one has a half ring.
static func landing_ring_count(tier: int, phase: int, base: int) -> int:
	if base <= 0:
		return 0
	if phase >= 2:
		return base + 4 * tier
	return floori(base / 2.0) if tier >= 1 else 0


## Eruptions after every special. From tier 2 phase one erupts too.
static func eruption_count(tier: int, phase: int, base: int) -> int:
	if base <= 0:
		return 0
	if phase >= 2:
		return base + tier
	return base if tier >= 2 else 0


## Extra minions per summon in phase two.
static func summon_bonus(phase: int) -> int:
	return 1 if phase >= 2 else 0


## "I", "II", ... for tier 0, 1, ...
static func tier_numeral(tier: int) -> String:
	if tier < 0:
		return ""
	if tier < ROMAN.size():
		return ROMAN[tier]
	return str(tier + 1)


## "Knochenkönig" for the first cycle, "Knochenkönig II" for the second, ...
## display_name may be the key from EnemyData (ENEMY_<ID>_NAME, D-111) or an already translated name.
static func boss_title(display_name: String, tier: int) -> String:
	var title := Loc.t(StringName(display_name)) if not display_name.is_empty() else display_name
	if tier <= 0:
		return title
	return "%s %s" % [title, tier_numeral(tier)]

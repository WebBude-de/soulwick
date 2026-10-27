class_name EconomyConfig
extends Resource
## All economy numbers in one place. Gold drops, prices and growth are OPEN in the GDD (DECISIONS §7);
## the values in economy_config.tres are PLATZHALTER (proposal D-057) until the team balances them.
## Heal +2 HP and shield +4 are VERBINDLICH (D-036).

## TESTWERT (KE2, KONZEPT §3): gold and soul crystals the run pays out +5 % per danger level.
## Applied once to the payout (EconomySystem.apply_danger_loot), not to every drop: most drops
## are 1-3 gold or one crystal, where +5 % would round away.
const LOOT_GAIN_PER_DANGER := 0.05
## TESTWERT (KE3, KONZEPT §2): depth bonus - gold per enemy (gold_growth_per_block) and the boss
## crystals grow by 10 % per five-room block, so going on past a soul gate pays more.
const DEPTH_BONUS_PER_BLOCK := 0.10

@export_group("Gold drops (PLATZHALTER)")
## Drop = base (EnemyData.gold_drop) * (1 + growth * k), k = five-room block.
## TESTWERT (D-091): 0.10 -> 0.0, enemy count and waves already raise the income per room.
## KE3 (KONZEPT §2): the depth bonus again, DEPTH_BONUS_PER_BLOCK (0.10).
@export var gold_growth_per_block := DEPTH_BONUS_PER_BLOCK


## Depth bonus of room_index in whole percent (block 3 = rooms 16-20: 30).
static func depth_bonus_percent(room_index: int) -> int:
	return roundi(100.0 * DEPTH_BONUS_PER_BLOCK * EnemyScaling.get_block(room_index))


## Crystals of a boss in room_index with the depth bonus, rounded half up (3 in room 15: 4).
## Hook (integrator): DungeonManager pays CRYSTALS_PER_BOSS through this.
static func depth_crystals(base: int, room_index: int) -> int:
	if base <= 0:
		return 0
	return floori(base * (1.0 + DEPTH_BONUS_PER_BLOCK * EnemyScaling.get_block(room_index)) + 0.5 + 1e-6)
## TESTWERT (D-118: 5 -> 9, keeps the champion's gold with gold_drop_factor 0.4; P1-5: 9 -> 12, the
## champion in room 5 comes right before a typical first death and makes the first forge buy reachable).
@export var miniboss_gold_multiplier := 12.0
## TESTWERT (D-091): flat factor on every enemy drop (playtest: 944 gold at room 43 was too much).
## D-118: 0.7 -> 0.4, about 1.75x as many enemies per room since then.
@export var gold_drop_factor := 0.4

@export_group("Shop prices (PLATZHALTER)")
@export var upgrade_price := 25
@export var weapon_price := 30
@export var heal_price := 15
@export var shield_price := 15
## Price = base * (1 + growth * k).
## TESTWERT (D-091): 0.15 -> 0.30.
@export var price_growth_per_block := 0.30

@export_group("Shop goods (VERBINDLICH)")
@export var heal_amount := 2.0
@export var shield_amount := 3.0
@export var upgrade_offers := 2
@export var weapon_offers := 2

class_name EconomyConfig
extends Resource
## All economy numbers in one place. Gold drops, prices and growth are OPEN in the GDD (DECISIONS §7);
## the values in economy_config.tres are PLATZHALTER (proposal D-057) until the team balances them.
## Heal +2 HP and shield +4 are VERBINDLICH (D-036).

@export_group("Gold drops (PLATZHALTER)")
## Drop = base (EnemyData.gold_drop) * (1 + growth * k), k = five-room block.
## TESTWERT (D-091): 0.10 -> 0.0, enemy count and waves already raise the income per room.
@export var gold_growth_per_block := 0.0
## TESTWERT (D-118: 5 -> 9, keeps the champion's gold with gold_drop_factor 0.4).
@export var miniboss_gold_multiplier := 9.0
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

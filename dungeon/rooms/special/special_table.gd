class_name SpecialTable
extends Resource
## Weighted draw of the special room on cycle place 4 (D-102, replaces the equal weights of D-005):
## Shop 35, weapons 20, fountain 15, extra upgrade 15, trial 15 (TESTWERTE, balanced in
## special_table.tres without code). The type of the special room directly before never repeats;
## its weight is then split proportionally between the others. The 30 % portal chance stays in
## RoomSequence.roll_portal.
## Also the sub-draws of the new special rooms: pact altar in a third of the extra-upgrade rooms
## (KONZEPT_RAEUME §6.2) and the kind of trial (§6.1). All draws use the dungeon RNG.

const DEFAULT_PATH := "res://dungeon/rooms/special/special_table.tres"
## Type ids in RoomSequence.SpecialType order. TRIAL is new (A8): the integrator appends it to the
## enum, so RoomSequence.SpecialType.TRIAL == TRIAL (checked by test_special_table).
const SHOP := 0
const WEAPON := 1
const FOUNTAIN := 2
const UPGRADE := 3
const TRIAL := 4
const TYPE_COUNT := 5
## Trial rooms bring their own template (parcours walls) and content (A8 hooks for the integrator).
const TRIAL_TEMPLATE_PATH := "res://dungeon/rooms/trials/trial_room.tscn"
const TRIAL_CONTENT_PATH := "res://dungeon/rooms/trials/trial_content.tscn"

## Kinds of trial rooms (KONZEPT_RAEUME §6.1). CRUMBLE needs the abyss of A4 and stays at weight 0.
enum TrialKind { GAUNTLET, LIGHT_RUN, CRUMBLE }

@export_group("Special room weights (D-102, TESTWERTE)")
@export var shop_weight := 35.0
@export var weapon_weight := 20.0
@export var fountain_weight := 15.0
@export var upgrade_weight := 15.0
@export var trial_weight := 15.0
@export_group("Variants (TESTWERTE)")
## Share of the extra-upgrade rooms that show a pact altar instead (KONZEPT_RAEUME §6.2).
@export_range(0.0, 1.0) var pact_chance := 1.0 / 3.0
@export var gauntlet_weight := 1.0
@export var light_run_weight := 1.0
## Bröckelboden: prepared interface only, needs pits (A4). Ignored while no course can build it.
@export var crumble_weight := 0.0


static func load_default() -> SpecialTable:
	if ResourceLoader.exists(DEFAULT_PATH):
		var table := load(DEFAULT_PATH) as SpecialTable
		if table != null:
			return table
	return SpecialTable.new()


## Weights in type order (SHOP .. TRIAL).
func get_base_weights() -> Array[float]:
	var weights: Array[float] = [shop_weight, weapon_weight, fountain_weight, upgrade_weight, trial_weight]
	return weights


## Effective weights for one draw: the previous type (-1 = none) gets 0.
func get_weights(previous: int) -> Array[float]:
	var weights := get_base_weights()
	if previous >= 0 and previous < weights.size():
		weights[previous] = 0.0
	return weights


## Weighted special type, never previous again. Always draws exactly one random number.
func roll(previous: int, rng: RandomNumberGenerator) -> int:
	return pick_weighted(get_weights(previous), rng.randf(), _fallback_type(previous))


## Probability of each type for one draw after previous (tests, balancing).
func get_chances(previous: int) -> Array[float]:
	var weights := get_weights(previous)
	var total := 0.0
	for weight in weights:
		total += maxf(weight, 0.0)
	var chances: Array[float] = []
	for weight in weights:
		chances.append(maxf(weight, 0.0) / total if total > 0.0 else 0.0)
	return chances


## Pact altar instead of the normal extra-upgrade altar? One random number.
func roll_pact(rng: RandomNumberGenerator) -> bool:
	return rng.randf() < pact_chance


## Kind of trial; kinds whose course cannot be built yet (crumble before A4) are skipped.
## Always draws exactly one random number.
func roll_trial_kind(rng: RandomNumberGenerator, crumble_available := false) -> TrialKind:
	var weights: Array[float] = [gauntlet_weight, light_run_weight, crumble_weight if crumble_available else 0.0]
	return pick_weighted(weights, rng.randf(), TrialKind.GAUNTLET) as TrialKind


## Index of the weight that roll (0..1) falls into; fallback if every weight is 0.
static func pick_weighted(weights: Array[float], roll_value: float, fallback: int) -> int:
	var total := 0.0
	for weight in weights:
		total += maxf(weight, 0.0)
	if total <= 0.0:
		return fallback
	var rest := roll_value * total
	var last := fallback
	for index in weights.size():
		var weight := maxf(weights[index], 0.0)
		if weight <= 0.0:
			continue
		last = index
		rest -= weight
		if rest < 0.0:
			return index
	# Rounding at the upper end: the last type with a weight.
	return last


## Room template of a special type: the trial room for TRIAL, null = the normal special template.
static func get_template_for(special_type: int) -> PackedScene:
	if special_type == TRIAL:
		return load(TRIAL_TEMPLATE_PATH) as PackedScene
	return null


static func get_type_name(special_type: int) -> String:
	match special_type:
		SHOP:
			return "Shop"
		WEAPON:
			return "Waffenauswahl"
		FOUNTAIN:
			return "Brunnen"
		UPGRADE:
			return "Upgrade-Altar"
		TRIAL:
			return "Prüfung"
	return ""


static func get_trial_name(kind: int) -> String:
	match kind:
		TrialKind.LIGHT_RUN:
			return "Lichtlauf"
		TrialKind.CRUMBLE:
			return "Bröckelboden"
	return "Spießrutenlauf"


func _fallback_type(previous: int) -> int:
	return SHOP if previous != SHOP else WEAPON

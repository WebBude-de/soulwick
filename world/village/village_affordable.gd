extends RefCounted
## P1-3 "Was kann ich mir leisten?": decides what the village marks as affordable right now.
## - Schmiede: an open forge upgrade whose next level the permanent gold pays (MetaProgression.can_buy).
## - Handelsposten: a Proviant that is not packed yet and the crystals pay (can_buy_boost) or the
##   next trade level (can_buy_trade, KE5), only
##   while the building is open (MetaUnlocks, D-087).
## The "!" over a building (Village) shows while something there is affordable; after a visit it
## stays away until the building's currency changes (gold for the forge, crystals for the trader).
## The visits are remembered for this session only (per save file): after a restart the marker shows
## once more if something is still affordable. Nothing is written to the save.
## The goal line (forge goals after the first run) is VillageGoal's (FS6, D-220).
## Koop: reads the local save only (the player's own wallet at this machine); nothing is sent.
## Reads MetaProgression, MetaUnlocks and SaveManager, never writes. No class_name: used through
## preload (Village.AffordableScript).

## Buildings with something to buy, in the order of the village.
const BUILDINGS: Array[StringName] = [VillageBuildings.FORGE, VillageBuildings.TRADER]

## "<save path>|<building id>" -> the building's currency when its dialog was closed last.
static var _visits: Dictionary = {}


## The things in a building that are affordable right now (forge: upgrade ids in forge order,
## trader: boost ids, then trade level ids); empty for other or locked buildings.
static func affordable_items(building_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	if not BUILDINGS.has(building_id) or not MetaUnlocks.is_building_open(building_id):
		return result
	if building_id == VillageBuildings.FORGE:
		for id in MetaUnlocks.get_open_upgrades():
			if MetaProgression.can_buy(id):
				result.append(id)
	else:
		for id in MetaProgression.BOOST_ORDER:
			if MetaProgression.can_buy_boost(id):
				result.append(id)
		# KE5: the trade levels (Proviant-Platz, Glück, Händlerfreund) count too.
		for id in MetaProgression.TRADE_ORDER:
			if MetaProgression.can_buy_trade(id):
				result.append(id)
	return result


static func has_affordable(building_id: StringName) -> bool:
	return not affordable_items(building_id).is_empty()


## The currency the building takes: permanent gold (forge) or crystals (trader); -1 otherwise.
static func wallet(building_id: StringName) -> int:
	if building_id == VillageBuildings.FORGE:
		return SaveManager.get_permanent_gold()
	if building_id == VillageBuildings.TRADER:
		return SaveManager.get_permanent_crystals()
	return -1


## Remembers that the building's dialog was seen with the current wallet (hides its "!").
static func mark_visited(building_id: StringName) -> void:
	if BUILDINGS.has(building_id):
		_visits[_visit_key(building_id)] = wallet(building_id)


## True while the building shows its "!": something is affordable and the currency changed since
## the last visit (or there was none in this session).
static func needs_marker(building_id: StringName) -> bool:
	if not has_affordable(building_id):
		return false
	var key := _visit_key(building_id)
	return not _visits.has(key) or int(_visits[key]) != wallet(building_id)


## Forgets every visit (tests).
static func clear_visits() -> void:
	_visits.clear()


## Gold still missing for the next forge level (0 = affordable, -1 = maxed or unknown).
static func gold_missing(upgrade_id: StringName) -> int:
	var cost := MetaProgression.get_next_cost(upgrade_id)
	if cost < 0:
		return -1
	return maxi(0, cost - SaveManager.get_permanent_gold())


## Crystals still missing for a Proviant (0 = affordable or packed, -1 = unknown).
static func crystals_missing(boost_id: StringName) -> int:
	var price := MetaProgression.get_boost_price(boost_id)
	if price < 0:
		return -1
	if SaveManager.has_pending_boost(boost_id):
		return 0
	return maxi(0, price - SaveManager.get_permanent_crystals())


static func _visit_key(building_id: StringName) -> String:
	return "%s|%s" % [SaveManager.save_path, building_id]

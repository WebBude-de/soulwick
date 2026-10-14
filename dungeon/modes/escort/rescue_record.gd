class_name RescueRecord
extends RefCounted
## Save marker of the escort mode (KONZEPT_RAEUME_V2 §3.3: "Gerettete tauchen später im Dorf auf"):
## every lost villager brought to the exit - or, rarely, a chicken - is counted in the save's
## statistics (SaveManager.add_stat). Written when the rescue happens, stored with the next save
## like every statistic (run end). Hook for R7: the village reads get_rescued() and lets that many
## rescued walk around (cloak colours from LostVillager.CLOAK_COLORS, in rescue order).

const VILLAGERS: StringName = &"rescued_villagers"
const CHICKENS: StringName = &"rescued_chickens"


## One more rescued (chicken = the rare chicken with a lantern).
static func record(chicken: bool) -> void:
	SaveManager.add_stat(CHICKENS if chicken else VILLAGERS, 1)


## Rescued villagers (chicken = false) or chickens (true) of this save.
static func get_rescued(chicken := false) -> int:
	return int(SaveManager.get_stat(CHICKENS if chicken else VILLAGERS))


static func get_total() -> int:
	return get_rescued(false) + get_rescued(true)

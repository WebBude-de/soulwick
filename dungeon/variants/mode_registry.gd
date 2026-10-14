class_name ModeRegistry
extends RefCounted
## Every minigame mode of the combat rooms in one table (KONZEPT_RAEUME_V2 §2, §4, D-120): one line
## per mode. VariantTable draws from it, CombatVariant.create() builds the mode node from its script,
## the DungeonManager draws the plan of the plan mode (RoomCatalog.pick(..., mode)).
##
## A line: id (RoomObjective mode id = RoomVariants.get_variant_id), script (a CombatVariant
## subclass, usually RoomMode; loaded by path, so modes never load each other), plan (RoomTemplate.mode
## of the generated plans, &"" = any combat plan), from_room (first room the mode may appear in,
## KONZEPT §2: "Zyklus 2" = room 6, "Zyklus 3" = 11, "Zyklus 4" / "2. Biom" = 16), weight (share
## among the available modes, TESTWERT) and biomes (bit mask of 1 << RoomSequence.Biome, 0 = all).
## Optional "secret": false - no secret niche in such a room (Einsturz breaks the floor in front of it).
##
## A new mode is one more line (the script extends CombatVariant, usually RoomMode; its id is a
## RoomObjective mode and a RoomGenre entry).

const ENTRIES: Array[Dictionary] = [
	{"id": &"flame", "script": "res://dungeon/modes/flame/flame_mode.gd", "plan": &"flame", "from_room": 6, "weight": 1.0, "biomes": 0},  # TESTWERT
	{"id": &"relic", "script": "res://dungeon/modes/relic/relic_mode.gd", "plan": &"relic", "from_room": 11, "weight": 1.0, "biomes": 0},  # TESTWERT
	{"id": &"rifts", "script": "res://dungeon/modes/rifts/rifts_mode.gd", "plan": &"rifts", "from_room": 16, "weight": 1.0, "biomes": 0},  # TESTWERT
	{"id": &"hunt", "script": "res://dungeon/modes/hunt/hunt_mode.gd", "plan": &"hunt", "from_room": 16, "weight": 1.0, "biomes": 0},  # TESTWERT
	{"id": &"lightfire", "script": "res://dungeon/modes/lightfire/lightfire_mode.gd", "plan": &"beacon", "from_room": 16, "weight": 1.0, "biomes": 0},  # TESTWERT
	# R4a (Geleit, Seelen sammeln, Einsturz)
	{"id": &"escort", "script": "res://dungeon/modes/escort/escort_mode.gd", "plan": &"escort", "from_room": 6, "weight": 1.0, "biomes": 0},  # TESTWERT
	{"id": &"souls", "script": "res://dungeon/modes/souls/souls_mode.gd", "plan": &"souls", "from_room": 11, "weight": 1.0, "biomes": 0},  # TESTWERT
	{"id": &"collapse", "script": "res://dungeon/modes/collapse/collapse_mode.gd", "plan": &"collapse", "from_room": 16, "weight": 1.0, "biomes": 0, "secret": false},  # TESTWERT
]

const NONE := &""


## Ids of every registered mode, in table order.
static func get_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry in ENTRIES:
		ids.append(StringName(entry.get("id", NONE)))
	return ids


static func has_mode(id: StringName) -> bool:
	return not get_entry(id).is_empty()


## The table line of a mode ({} for unknown ids).
static func get_entry(id: StringName) -> Dictionary:
	if id == NONE:
		return {}
	for entry in ENTRIES:
		if StringName(entry.get("id", NONE)) == id:
			return entry
	return {}


## Plan mode of the generated room plans for a mode (&"" = any combat plan, also for unknown ids).
static func get_plan_mode(id: StringName) -> StringName:
	return StringName(get_entry(id).get("plan", NONE))


static func get_from_room(id: StringName) -> int:
	return int(get_entry(id).get("from_room", 1))


static func get_weight(id: StringName) -> float:
	return maxf(0.0, float(get_entry(id).get("weight", 0.0)))


static func get_biome_mask(id: StringName) -> int:
	return int(get_entry(id).get("biomes", 0))


## May a room of this mode hide a secret niche (true for &"" and unknown ids)?
static func allows_secret(id: StringName) -> bool:
	return bool(get_entry(id).get("secret", true))


static func get_script_path(id: StringName) -> String:
	return String(get_entry(id).get("script", ""))


## A new, not yet attached node of the mode (null for unknown ids or a broken script).
static func create(id: StringName) -> CombatVariant:
	var path := get_script_path(id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		return null
	var instance: Object = script.new()
	if instance is CombatVariant:
		return instance as CombatVariant
	if instance is Node:
		(instance as Node).free()
	return null

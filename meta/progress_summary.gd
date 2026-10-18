class_name ProgressSummary
extends RefCounted
## "Dein Fortschritt" at a glance (D-188, KF1): what a world has reached (forge levels x/20,
## record, bosses per biome, unlocks) and the next goals (the cheapest forge step, the next unlock or
## boss, the next level reward of the account). Read only: a world comes from the loaded save
## (world_from_save) or from a slot file without loading it (world_from_file, migrated in memory);
## build() is a pure function over that snapshot, so the main menu, the chronicle and tests share
## one rule. Texts are translation keys (D-111) resolved by the *_text helpers.
## The account part (KF2) comes from AccountProgress (account_snapshot): level, XP, the account record
## and all defeated bosses, plus the next level reward as a goal.
## Bosses per biome are derived from the world's record and boss count (the save keeps no list):
## a boss counts as beaten once a room behind it was reached, or when the record ends in its room
## and the world has beaten at least that many bosses (the campfire after it keeps its number).

const GOAL_FORGE_BUY: StringName = &"forge_buy"
const GOAL_FORGE_SAVE: StringName = &"forge_save"
const GOAL_UNLOCK: StringName = &"unlock"
const GOAL_BOSS: StringName = &"boss"
const GOAL_REWARD: StringName = &"reward"
## At most this many goals in the list ("Nächste Ziele").
const MAX_GOALS := 3
## Statistics a snapshot carries (StatsTracker ids).
const STAT_IDS: Array[StringName] = [
	StatsTracker.RUNS, StatsTracker.DEATHS, StatsTracker.EXITS, StatsTracker.DEEPEST_ROOM,
	StatsTracker.ROOMS_CLEARED, StatsTracker.KILLS, StatsTracker.BOSSES, StatsTracker.CHAMPIONS,
	StatsTracker.PLAY_TIME,
]
## Boss of each biome (RoomSequence.Biome order; the bosses take turns like the biomes, D-076):
## translation key of its name.
const BOSS_NAME_KEYS: Array[StringName] = [
	&"ENEMY_BOSS_BONE_KING_NAME", &"ENEMY_BOSS_SLIME_QUEEN_NAME",
	&"ENEMY_BOSS_SHADOW_LORD_NAME", &"ENEMY_BOSS_EMBER_GOLEM_NAME",
]
## Unlock event -> translation key of its goal line.
const UNLOCK_GOAL_KEYS := {
	MetaUnlocks.EVENT_FIRST_RUN: &"PROGRESS_GOAL_FIRST_RUN",
	MetaUnlocks.EVENT_FIRST_CRYSTAL: &"PROGRESS_GOAL_FIRST_CRYSTAL",
	MetaUnlocks.EVENT_FIRST_BOSS: &"PROGRESS_GOAL_FIRST_BOSS",
}


# --- World snapshots ---

## An empty world (no save): nothing reached yet.
static func empty_world() -> Dictionary:
	return {"exists": false, "name": "", "gold": 0, "crystals": 0, "levels": {}, "events": [], "stats": {}}


## The loaded save (SaveManager) as a snapshot.
static func world_from_save() -> Dictionary:
	var world := empty_world()
	world["exists"] = true
	world["name"] = SaveManager.get_world_display_name()
	world["gold"] = SaveManager.get_permanent_gold()
	world["crystals"] = SaveManager.get_permanent_crystals()
	var levels := {}
	for id in MetaProgression.UPGRADE_ORDER:
		levels[id] = SaveManager.get_meta_level(id)
	world["levels"] = levels
	var events: Array[StringName] = []
	for event in MetaUnlocks.EVENTS:
		if SaveManager.is_unlocked(event):
			events.append(event)
	world["events"] = events
	var stats := {}
	for id in STAT_IDS:
		stats[id] = SaveManager.get_stat(id)
	world["stats"] = stats
	return world


## A slot file as a snapshot, without loading it (older versions are migrated in memory, D-059).
## Missing or unreadable files give empty_world(); a broken file uses its last good copy (P1-8).
static func world_from_file(path: String) -> Dictionary:
	var config := ConfigFile.new()
	if SafeSave.load_config(config, path) != OK:
		return empty_world()
	var version: Variant = config.get_value("meta", "version", -1)
	if typeof(version) != TYPE_INT or version < 1 or version > SaveManager.SAVE_VERSION:
		return empty_world()
	SaveManager.migrate(config)
	var world := empty_world()
	world["exists"] = true
	var stored_name: Variant = config.get_value("world", "name", "")
	world["name"] = String(stored_name) if typeof(stored_name) == TYPE_STRING else ""
	world["gold"] = _int(config.get_value("progress", "permanent_gold", 0))
	world["crystals"] = _int(config.get_value("progress", "permanent_crystals", 0))
	var levels := {}
	for id in MetaProgression.UPGRADE_ORDER:
		levels[id] = _int(config.get_value("meta_upgrades", String(id), 0))
	world["levels"] = levels
	var events: Array[StringName] = []
	var unlocked: Variant = config.get_value("progress", "unlocked", PackedStringArray())
	if typeof(unlocked) == TYPE_PACKED_STRING_ARRAY:
		for event in MetaUnlocks.EVENTS:
			if (unlocked as PackedStringArray).has(String(event)):
				events.append(event)
	world["events"] = events
	var stats := {}
	for id in STAT_IDS:
		var value: Variant = config.get_value("stats", String(id), 0)
		stats[id] = maxf(0.0, float(value)) if id == StatsTracker.PLAY_TIME and (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) else _int(value)
	world["stats"] = stats
	return world


## The account part for build(): {"xp", "best_room", "bosses"} of this machine's AccountProgress.
static func account_snapshot() -> Dictionary:
	var progress := AccountProgress.current()
	return {"xp": progress.get_total_xp(), "best_room": progress.best_room, "bosses": progress.bosses}


# --- The summary (pure) ---

## Everything the overview shows. world: a snapshot (world_from_save/world_from_file); account:
## account_snapshot() ({"xp", "best_room", "bosses"}), {} = no account part. Keys: forge_level, forge_max,
## deepest_room, bosses, runs, biomes [{biome, reached, beaten}], unlocks [{event, done}],
## forge_step ({} or {id, level, cost, missing}), next_boss {number, room, biome}, account ({} or
## {level, xp, into, needed, ratio, next_reward, reward_missing}), goals [{kind, ...}] (at most
## MAX_GOALS, the first is "Nächstes Ziel").
static func build(world: Dictionary, account := {}) -> Dictionary:
	var stats: Dictionary = world.get("stats", {})
	var levels: Dictionary = world.get("levels", {})
	var events: Array = world.get("events", [])
	var deepest := _int(stats.get(StatsTracker.DEEPEST_ROOM, 0))
	var bosses := _int(stats.get(StatsTracker.BOSSES, 0))
	var passed := bosses_passed(deepest, bosses)
	var summary := {
		"forge_level": forge_level(levels),
		"forge_max": SaveSlots.forge_max_level(),
		"deepest_room": deepest,
		"bosses": bosses,
		"runs": _int(stats.get(StatsTracker.RUNS, 0)),
		"biomes": [],
		"unlocks": [],
		"forge_step": forge_step(levels, events, _int(world.get("gold", 0))),
		"next_boss": boss_info(passed + 1),
		"account": {},
		"goals": [],
	}
	var biomes: Array[Dictionary] = []
	for biome in RoomSequence.BIOME_COUNT:
		biomes.append({"biome": biome, "reached": deepest >= biome * RoomSequence.BOSS_INTERVAL + 1, "beaten": passed >= biome + 1})
	summary["biomes"] = biomes
	var unlocks: Array[Dictionary] = []
	for event in MetaUnlocks.EVENTS:
		unlocks.append({"event": event, "done": events.has(event)})
	summary["unlocks"] = unlocks
	if not account.is_empty():
		var info := AccountProgress.level_info(int(account.get("xp", 0)))
		var reward := AccountProgress.next_reward_level(int(info["level"]))
		info["next_reward"] = reward
		info["reward_missing"] = maxi(0, AccountProgress.xp_for_level(reward) - int(info["xp"])) if reward > 0 else 0
		info["best_room"] = _int(account.get("best_room", 0))
		info["bosses"] = _int(account.get("bosses", 0))
		summary["account"] = info
	summary["goals"] = goals(summary, events)
	return summary


## The next goals, most useful first: buy a forge step the gold pays for, the next unlock or else
## the next boss, save gold for the cheapest step, the next level reward. One forge goal, one dungeon
## goal and the reward: at most MAX_GOALS.
static func goals(summary: Dictionary, events: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var step: Dictionary = summary.get("forge_step", {})
	if not step.is_empty() and int(step["missing"]) <= 0:
		result.append({"kind": GOAL_FORGE_BUY, "id": step["id"], "level": step["level"], "cost": step["cost"]})
	var unlock := &""
	for event in MetaUnlocks.EVENTS:
		if not events.has(event):
			unlock = event
			break
	if unlock != &"":
		result.append({"kind": GOAL_UNLOCK, "event": unlock, "room": RoomSequence.BOSS_INTERVAL})
	else:
		var boss: Dictionary = summary.get("next_boss", {})
		result.append({"kind": GOAL_BOSS, "room": boss["room"], "biome": boss["biome"], "number": boss["number"]})
	if not step.is_empty() and int(step["missing"]) > 0:
		result.append({"kind": GOAL_FORGE_SAVE, "id": step["id"], "level": step["level"], "cost": step["cost"], "missing": step["missing"]})
	var account: Dictionary = summary.get("account", {})
	if not account.is_empty() and int(account.get("next_reward", 0)) > 0:
		result.append({"kind": GOAL_REWARD, "level": account["next_reward"], "missing": account["reward_missing"]})
	return result.slice(0, MAX_GOALS)


## Forge levels bought (each at most its maximum), like SaveSlots.forge_progress.
static func forge_level(levels: Dictionary) -> int:
	var total := 0
	for id in MetaProgression.UPGRADE_ORDER:
		total += clampi(_int(levels.get(id, 0)), 0, MetaProgression.get_max_level(id))
	return total


## The cheapest open forge step of a world (same rule as RunRecap.next_forge_step and the village's
## "!", but from the snapshot): {"id", "level" (the one it buys), "cost", "missing"}; {} when every
## open upgrade is at its limit. Ties keep the forge order.
static func forge_step(levels: Dictionary, events: Array, gold: int) -> Dictionary:
	var best := {}
	for id in MetaProgression.UPGRADE_ORDER:
		var event := MetaUnlocks.get_upgrade_event(id)
		if event != &"" and not events.has(event):
			continue
		var level := clampi(_int(levels.get(id, 0)), 0, MetaProgression.get_max_level(id))
		var costs: Array = MetaProgression.UPGRADES[id]["costs"]
		if level >= costs.size():
			continue
		var cost := int(costs[level])
		if best.is_empty() or cost < int(best["cost"]):
			best = {"id": id, "level": level + 1, "cost": cost, "missing": maxi(0, cost - gold)}
	return best


## Boss rooms a world has passed: every boss room below its record, plus the record's own room
## when the world beat at least that many bosses (it ended at the campfire behind it).
static func bosses_passed(deepest_room: int, bosses: int) -> int:
	if deepest_room <= 0:
		return 0
	var passed := floori(float(deepest_room - 1) / RoomSequence.BOSS_INTERVAL)
	if deepest_room % RoomSequence.BOSS_INTERVAL == 0 and bosses >= passed + 1:
		passed += 1
	return passed


## Boss number n (1 = room 15): {"number", "room", "biome"}.
static func boss_info(number: int) -> Dictionary:
	var room := maxi(1, number) * RoomSequence.BOSS_INTERVAL
	return {"number": maxi(1, number), "room": room, "biome": int(RoomSequence.get_biome(room))}


# --- Texts (current language, D-111) ---

static func boss_name(biome: int) -> String:
	return Loc.t(BOSS_NAME_KEYS[clampi(biome, 0, BOSS_NAME_KEYS.size() - 1)])


## "Vitalität II".
static func forge_step_name(goal: Dictionary) -> String:
	return "%s %s" % [MetaProgression.get_upgrade_name(goal["id"]), RunRecap.roman(int(goal["level"]))]


## One line of a goal ("Kaufe Vitalität II in der Schmiede (80 Gold)").
static func goal_text(goal: Dictionary) -> String:
	match StringName(goal.get("kind", &"")):
		GOAL_FORGE_BUY:
			return Loc.t(&"PROGRESS_GOAL_FORGE_BUY", [forge_step_name(goal), int(goal["cost"])])
		GOAL_FORGE_SAVE:
			return Loc.t(&"PROGRESS_GOAL_FORGE_SAVE", [int(goal["missing"]), forge_step_name(goal)])
		GOAL_UNLOCK:
			var event := StringName(goal["event"])
			var opens := MetaUnlocks.describe_event(event)
			if event == MetaUnlocks.EVENT_FIRST_BOSS:
				return Loc.t(UNLOCK_GOAL_KEYS[event], [int(goal["room"]), opens])
			return Loc.t(UNLOCK_GOAL_KEYS[event], [opens])
		GOAL_BOSS:
			return Loc.t(&"PROGRESS_GOAL_BOSS", [boss_name(int(goal["biome"])), int(goal["room"])])
		GOAL_REWARD:
			return Loc.t(&"PROGRESS_GOAL_REWARD", [int(goal["level"]), int(goal["missing"])])
	return ""


## "Nächstes Ziel: …" of a summary ("" when there is none).
static func next_goal_text(summary: Dictionary) -> String:
	var list: Array = summary.get("goals", [])
	return Loc.t(&"PROGRESS_NEXT_GOAL", [goal_text(list[0])]) if not list.is_empty() else ""


## "Schmiede 7/20".
static func forge_text(summary: Dictionary) -> String:
	return Loc.t(&"PROGRESS_FORGE_SHORT", [int(summary["forge_level"]), int(summary["forge_max"])])


static func _int(value: Variant) -> int:
	return maxi(0, int(value)) if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT else 0

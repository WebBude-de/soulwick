class_name MetaUnlocks
extends RefCounted
## Village unlocks (D-087): which buildings and forge upgrades are open, the progress events that
## open them and the short "Neu freigeschaltet" message shown once in the village afterwards.
## A fresh save starts with the forge (Vitalität, Startschild, Schärfe), the guild, home and the
## dungeon. Chronik opens after the first run, Handelsposten with the first Seelenkristall, Goldgier,
## Dash-Training and Arsenal after the first defeated boss.
## Events are stored in the save as ids in [progress] unlocked (SaveManager.unlock_content) and are
## never taken back. Saves from before v3 get every event in SaveManager.migrate() ("alles
## freigeschaltet", D-087) and their announcements count as already shown.
## The decision lives here only: reached_events() maps progress to events, is_*_open() maps events to
## buildings and upgrades. StatsTracker records the events while playing, the village syncs on load.

const EVENT_FIRST_RUN: StringName = &"event_first_run"
const EVENT_FIRST_CRYSTAL: StringName = &"event_first_crystal"
const EVENT_FIRST_BOSS: StringName = &"event_first_boss"
const EVENTS: Array[StringName] = [EVENT_FIRST_RUN, EVENT_FIRST_CRYSTAL, EVENT_FIRST_BOSS]

## Seen-flag prefix ([seen] ids) for "this unlock was announced", e.g. unlock_first_boss.
const ANNOUNCED_PREFIX := "unlock_"
const EVENT_PREFIX := "event_"

## Building id (VillageBuildings) -> event that opens it. Buildings not listed are open from the start.
const BUILDING_EVENTS := {
	&"chronicle": EVENT_FIRST_RUN,
	&"trader": EVENT_FIRST_CRYSTAL,
}
## Forge upgrade id (MetaProgression) -> event that opens it. Upgrades not listed are open from the start.
const UPGRADE_EVENTS := {
	&"gold_greed": EVENT_FIRST_BOSS,
	&"dash_training": EVENT_FIRST_BOSS,
	&"arsenal": EVENT_FIRST_BOSS,
}
## When an event happens, as the end of "Öffnet …" (lock label at the door, door prompt) and of
## "Weitere Verbesserungen öffnen …" (forge). Translation keys (D-111).
const LOCK_CONDITIONS := {
	EVENT_FIRST_RUN: &"UNLOCK_AFTER_FIRST_RUN",
	EVENT_FIRST_CRYSTAL: &"UNLOCK_WITH_FIRST_CRYSTAL",
	EVENT_FIRST_BOSS: &"UNLOCK_AFTER_FIRST_BOSS",
}
## Title of the village message when something opened: translation key (a Label translates it by
## itself), get_announce_title() gives the text.
const ANNOUNCE_TITLE: StringName = &"UNLOCK_ANNOUNCE_TITLE"


# --- Events ---

static func has_event(event: StringName) -> bool:
	return SaveManager.is_unlocked(event)


## Stores an event (memory only, the caller saves). Returns true if it is new.
static func record_event(event: StringName) -> bool:
	if not EVENTS.has(event) or has_event(event):
		return false
	SaveManager.unlock_content(event)
	return true


## The decision in one place (pure): which events a progress has reached. Keys (all optional, ints):
## runs_finished (runs that ended: deaths + exits), crystals (permanent crystals now),
## crystals_earned, bosses (bosses defeated).
static func reached_events(progress: Dictionary) -> Array[StringName]:
	var events: Array[StringName] = []
	if int(progress.get("runs_finished", 0)) > 0:
		events.append(EVENT_FIRST_RUN)
	if int(progress.get("crystals", 0)) > 0 or int(progress.get("crystals_earned", 0)) > 0:
		events.append(EVENT_FIRST_CRYSTAL)
	if int(progress.get("bosses", 0)) > 0:
		events.append(EVENT_FIRST_BOSS)
	return events


## Progress of the loaded save in the form reached_events() expects. Finished runs: every started
## run except the one running now (aborted runs are not in the statistics on their own).
static func get_save_progress() -> Dictionary:
	var started := int(SaveManager.get_stat(StatsTracker.RUNS))
	if RunManager.is_run_active():
		started -= 1
	var ended := int(SaveManager.get_stat(StatsTracker.DEATHS)) + int(SaveManager.get_stat(StatsTracker.EXITS))
	return {
		"runs_finished": maxi(started, ended),
		"crystals": SaveManager.get_permanent_crystals(),
		"crystals_earned": int(SaveManager.get_stat(StatsTracker.CRYSTALS_EARNED)),
		"bosses": int(SaveManager.get_stat(StatsTracker.BOSSES)),
	}


## Records every event the loaded save's progress has reached (safety net next to StatsTracker).
## Memory only; returns the new events.
static func sync_from_save() -> Array[StringName]:
	var added: Array[StringName] = []
	for event in reached_events(get_save_progress()):
		if record_event(event):
			added.append(event)
	return added


# --- Buildings and upgrades ---

static func get_building_event(building_id: StringName) -> StringName:
	return BUILDING_EVENTS.get(building_id, &"")


static func get_upgrade_event(upgrade_id: StringName) -> StringName:
	return UPGRADE_EVENTS.get(upgrade_id, &"")


static func is_building_open(building_id: StringName) -> bool:
	var event := get_building_event(building_id)
	return event == &"" or has_event(event)


static func is_upgrade_open(upgrade_id: StringName) -> bool:
	var event := get_upgrade_event(upgrade_id)
	return event == &"" or has_event(event)


## Forge upgrades the player can see, in forge order.
static func get_open_upgrades() -> Array[StringName]:
	var result: Array[StringName] = []
	for id in MetaProgression.UPGRADE_ORDER:
		if is_upgrade_open(id):
			result.append(id)
	return result


## Events that still hide at least one forge upgrade, in EVENTS order.
static func get_locked_upgrade_events() -> Array[StringName]:
	var result: Array[StringName] = []
	for event in EVENTS:
		if has_event(event):
			continue
		for id in UPGRADE_EVENTS:
			if UPGRADE_EVENTS[id] == event:
				result.append(event)
				break
	return result


## "Öffnet nach deinem ersten Run" for a locked building, empty if it is open.
static func get_building_lock_text(building_id: StringName) -> String:
	if is_building_open(building_id):
		return ""
	return get_lock_text(get_building_event(building_id))


## "Öffnet nach deinem ersten Boss"; empty for unknown events.
static func get_lock_text(event: StringName) -> String:
	return Loc.t(&"UNLOCK_OPENS", [Loc.t(LOCK_CONDITIONS[event])]) if LOCK_CONDITIONS.has(event) else ""


## Forge line while upgrades are hidden: "Weitere Verbesserungen öffnen nach deinem ersten Boss."
static func get_forge_lock_text(event: StringName) -> String:
	return Loc.t(&"UNLOCK_FORGE_MORE", [Loc.t(LOCK_CONDITIONS[event])]) if LOCK_CONDITIONS.has(event) else ""


## "Neu freigeschaltet" in the current language.
static func get_announce_title() -> String:
	return Loc.t(ANNOUNCE_TITLE)


# --- Announcement (once per event and save) ---

static func get_announce_key(event: StringName) -> StringName:
	return StringName(ANNOUNCED_PREFIX + String(event).trim_prefix(EVENT_PREFIX))


## What opened with an event, e.g. "Chronik" or "Schmiede: Goldgier, Dash-Training und Arsenal".
static func describe_event(event: StringName) -> String:
	var buildings: Array[String] = []
	for id in BUILDING_EVENTS:
		if BUILDING_EVENTS[id] == event:
			buildings.append(VillageBuildings.get_display_name(id))
	var upgrades: Array[String] = []
	for id in MetaProgression.UPGRADE_ORDER:
		if UPGRADE_EVENTS.get(id, &"") == event:
			upgrades.append(MetaProgression.get_upgrade_name(id))
	var parts: Array[String] = []
	if not buildings.is_empty():
		parts.append(join_names(buildings))
	if not upgrades.is_empty():
		parts.append("%s: %s" % [VillageBuildings.get_display_name(VillageBuildings.FORGE), join_names(upgrades)])
	return " · ".join(parts)


## Lines for events that were reached but not announced yet; marks them announced (memory only, the
## caller saves). Old saves ("alles gesehen") never get a message.
static func take_announcements() -> Array[String]:
	var lines: Array[String] = []
	for event in EVENTS:
		if has_event(event) and SaveManager.mark_seen(get_announce_key(event)):
			lines.append(describe_event(event))
	return lines


## "A", "A und B", "A, B und C".
static func join_names(names: Array[String]) -> String:
	if names.size() <= 1:
		return "" if names.is_empty() else names[0]
	return Loc.t(&"UNLOCK_JOIN_AND", [", ".join(names.slice(0, names.size() - 1)), names[-1]])

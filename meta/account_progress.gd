class_name AccountProgress
extends RefCounted
## The account level (D-188, KF2): XP from every finished run, the same for all worlds, solo and
## co-op. Each level from 2 on gives one talent point for the talent tree at home (KONZEPT §4, D-194
## replaces "only for show"); every 5 levels a cosmetic reward (D-176: never bought). Rules and the
## level curve live here once as static functions (the platform computes the same curve, KF3).
## Danger level and rank (KE1, DangerRank): G from the level and the deepest room of the last 5 runs
## (get_danger_level); every run stores the danger level it was played on, its XP grow by 5 % per
## level (part "danger", after the co-op bonus, before the cap).
## Account state (KE1): get_state/set_state keep small dictionaries per key in [state] (seen flags
## AccountSeen, talents later), saved at once; they belong to the account, not to a world (§10).
##
## XP are increments: every run adds one entry exactly once (a second record_run() with the same run
## id changes nothing). An entry keeps the run's own counts in the form of the contract's XpEntry
## (KF3, packages/contracts/src/xp.ts: run id, end time, duration, game version, rooms, champions,
## bosses, deepest room, end reason, players) next to the XP counted here, so the server sync (KF4,
## POST /me/xp, get_pending_xp_entries) only has to send them; the server computes the same XP
## (runXp) and counts each run id once. The local XP are the estimate until the server answered. Besides the entries the file
## keeps the account record (deepest room over all worlds, for the record XP), defeated bosses and
## the day of the last daily bonus.
##
## Stored on this machine in progress.cfg next to settings.cfg (user://progress.cfg; game instance N:
## progress_<n>.cfg); runs started with a script (-s: tests, tools) on the real user folder use
## script_progress*.cfg and never touch the real file (AGENTS.md rule 4); SaveManager.set_storage_root()
## moves it along with the settings, tests may set path_override. The first load without a file
## takes the record and the bosses of the worlds on this machine once (older builds had no account
## record; without it the first run would pay the whole old record as "new record").
## Not an autoload (D-044): AccountProgress.current() loads it on first use. Co-op: every client
## counts only its own player (compute_run_xp is pure); the host never computes XP for others.

## Preloaded: works before the global class cache knows SafeSave.
const SafeSaveScript := preload("res://meta/safe_save.gd")
const FILE_NAME := "progress.cfg"
const INSTANCE_FILE_NAME := "progress_%d.cfg"
const SCRIPT_PREFIX := "script_"
const VERSION := 1

# --- XP sources (D-188, KONZEPT.md §4) ---
## TESTWERT: XP per cleared room (also mini game and arena rooms).
const XP_ROOM := 5
## TESTWERT: XP per defeated champion (miniboss).
const XP_CHAMPION := 10
## TESTWERT: XP per defeated boss.
const XP_BOSS := 50
## TESTWERT: XP per room above the old account record (deepest room over all worlds).
const XP_RECORD_ROOM := 5
## TESTWERT: XP for a run ended through the portal.
const XP_PORTAL := 20
## TESTWERT: XP for the first run of a UTC day (the server's day, contract xpDayOf).
const XP_FIRST_RUN_OF_DAY := 25
## TESTWERT: co-op bonus (2–4 players) on the whole run in percent, rounded down (contract runXp).
const COOP_BONUS_PERCENT := 20
## TESTWERT: caps of the server (§5.6), applied here too so the local level matches it.
const MAX_XP_PER_RUN := 2000
const MAX_XP_PER_DAY := 20000
## TESTWERT: level curve, XP for level L in total = XP_CURVE_STEP · L · (L − 1).
const XP_CURVE_STEP := 50
## TESTWERT (Vorschlag §5.5): a reward every 5 levels up to level 50; what it is comes with WK0/WK2.
const REWARD_EVERY := 5
const REWARD_MAX_LEVEL := 50
## Synced entries kept in the file (open entries are never dropped).
const MAX_SYNCED_ENTRIES := 200
## End reasons of the contract (RunEndReason): portal, wiped (died), abandoned (given up).
const END_PORTAL := "portal"
const END_WIPED := "wiped"
const END_ABANDONED := "abandoned"

## Parts of a run's XP, in the order the run end lists them.
const PART_ROOMS: StringName = &"rooms"
const PART_CHAMPIONS: StringName = &"champions"
const PART_BOSSES: StringName = &"bosses"
const PART_RECORD: StringName = &"record"
const PART_PORTAL: StringName = &"portal"
const PART_DAILY: StringName = &"daily"
const PART_COOP: StringName = &"coop"
const PART_DANGER: StringName = &"danger"
## Part id -> translation key of its caption (run end, D-111).
const PART_KEYS := {
	PART_ROOMS: &"XP_PART_ROOMS",
	PART_CHAMPIONS: &"XP_PART_CHAMPIONS",
	PART_BOSSES: &"XP_PART_BOSSES",
	PART_RECORD: &"XP_PART_RECORD",
	PART_PORTAL: &"XP_PART_PORTAL",
	PART_DAILY: &"XP_PART_DAILY",
	PART_COOP: &"XP_PART_COOP",
	PART_DANGER: &"XP_PART_DANGER",
}

## Tests may point the file somewhere else ("" = default_path()).
static var path_override := ""
static var _current: AccountProgress = null
static var _instance := 0
## Hook for the talents (KE6): returns the talent points already spent (int); by default the stored
## distribution of this account (AccountTalents). Empty = none spent, so every point is free.
static var spent_points_source: Callable = func() -> int: return AccountTalents.spent_points()

## File of this progress.
var path := ""
## Every XP entry counted here, oldest first: {"run_id", "xp", "at" (unix s of the run end), "day"
## (UTC day number), "synced", and the counts of the run: "rooms", "champions", "bosses",
## "deepest_room", "end_reason" (END_*), "players", "duration" (s), "game_version"}.
var entries: Array[Dictionary] = []
## Sum of all counted XP (also of synced entries that were dropped from the file).
var xp := 0
## Last total the server reported (KF4), 0 = never synced; the level uses the larger of both.
var server_xp := 0
## Deepest room over all worlds of this account (on this machine).
var best_room := 0
## Bosses and champions defeated in all counted runs (plus the worlds' bosses when the file was made).
var bosses := 0
var champions := 0
## Runs counted.
var runs := 0
## UTC day ("2026-10-18") of the last daily bonus, "" = never.
var last_bonus_day := ""
## Account state per key ("seen", "talents" …): small dictionaries, see get_state().
var _state: Dictionary = {}
## One-time bonus XP outside runs (WK10: the practice run), by id: {"xp", "at" (unix s), "synced"}.
## Part of xp and of the pending XP; stored in [bonus] (add_bonus_xp).
var bonus: Dictionary = {}


# --- Level curve (one place; the platform computes the same, KF3) ---

## XP needed for level in total: 50 · L · (L − 1). Level 1 = 0, 2 = 100, 3 = 300, 5 = 1000, 10 = 4500.
static func xp_for_level(level: int) -> int:
	var at := maxi(1, level)
	return XP_CURVE_STEP * at * (at - 1)


## Level of a total XP (1 for 0 XP, no upper limit).
static func level_for_xp(total_xp: int) -> int:
	var amount := maxi(0, total_xp)
	var level := maxi(1, floori((1.0 + sqrt(1.0 + 4.0 * amount / XP_CURVE_STEP)) * 0.5))
	while level > 1 and xp_for_level(level) > amount:
		level -= 1
	while xp_for_level(level + 1) <= amount:
		level += 1
	return level


## Everything a bar needs: level, xp, start and end of the level, into (XP in this level), needed
## (XP of this level), ratio 0..1.
static func level_info(total_xp: int) -> Dictionary:
	var amount := maxi(0, total_xp)
	var level := level_for_xp(amount)
	var start := xp_for_level(level)
	var end := xp_for_level(level + 1)
	return {
		"level": level, "xp": amount, "level_start": start, "level_end": end,
		"into": amount - start, "needed": end - start, "ratio": float(amount - start) / float(end - start),
	}


## The next level with a reward above level (0 when there is none left, REWARD_MAX_LEVEL).
static func next_reward_level(level: int) -> int:
	var next := (floori(float(maxi(0, level)) / REWARD_EVERY) + 1) * REWARD_EVERY
	return next if next <= REWARD_MAX_LEVEL else 0


# --- XP of a run (pure) ---

## XP of one finished run from its own numbers. Keys (all optional): rooms_cleared, champions,
## bosses, room (deepest room reached in the run), record_before (account record before the run),
## exit (bool: ended through the portal), first_of_day (bool), players (1..4), danger (G of the run).
## Returns {"xp": total (at most MAX_XP_PER_RUN), "parts": [{"id", "count", "xp"}, ...]} with only
## the parts that brought something; the co-op part is the bonus on the rest, the danger part
## (count = G) 5 % per level on everything before it, rounded down (DangerRank.xp_bonus).
static func compute_run_xp(run: Dictionary) -> Dictionary:
	var parts: Array[Dictionary] = []
	var rooms := maxi(0, int(run.get("rooms_cleared", 0)))
	_add_part(parts, PART_ROOMS, rooms, rooms * XP_ROOM)
	var champion_count := maxi(0, int(run.get("champions", 0)))
	_add_part(parts, PART_CHAMPIONS, champion_count, champion_count * XP_CHAMPION)
	var boss_count := maxi(0, int(run.get("bosses", 0)))
	_add_part(parts, PART_BOSSES, boss_count, boss_count * XP_BOSS)
	var above := maxi(0, int(run.get("room", 0)) - maxi(0, int(run.get("record_before", 0))))
	_add_part(parts, PART_RECORD, above, above * XP_RECORD_ROOM)
	if run.get("exit", false) == true:
		_add_part(parts, PART_PORTAL, 1, XP_PORTAL)
	if run.get("first_of_day", false) == true:
		_add_part(parts, PART_DAILY, 1, XP_FIRST_RUN_OF_DAY)
	var base := 0
	for part in parts:
		base += int(part["xp"])
	var players := clampi(int(run.get("players", 1)), 1, GameMode.MAX_PLAYERS)
	if players >= 2:
		@warning_ignore("integer_division")
		_add_part(parts, PART_COOP, players, base * COOP_BONUS_PERCENT / 100)
	var total := 0
	for part in parts:
		total += int(part["xp"])
	var danger := maxi(0, int(run.get("danger", 0)))
	var bonus := DangerRank.xp_bonus(total, danger)
	_add_part(parts, PART_DANGER, danger, bonus)
	total += bonus
	return {"xp": mini(total, MAX_XP_PER_RUN), "parts": parts}


static func _add_part(parts: Array[Dictionary], id: StringName, count: int, amount: int) -> void:
	if amount > 0:
		parts.append({"id": id, "count": count, "xp": amount})


## Caption of a part in the current language ("Raum ×12", "Boss", "Koop-Bonus").
static func part_text(part: Dictionary) -> String:
	var id := StringName(part.get("id", &""))
	var caption := Loc.t(PART_KEYS[id]) if PART_KEYS.has(id) else String(id)
	var count := int(part.get("count", 0))
	if id in [PART_ROOMS, PART_CHAMPIONS, PART_BOSSES] and count > 1:
		return "%s ×%d" % [caption, count]
	if id == PART_DANGER:
		return "%s %d" % [caption, count]
	return caption


# --- The progress of this machine ---

## The progress of this player, loaded on first use (and again when the storage folder changed).
static func current() -> AccountProgress:
	var wanted := default_path()
	if _current == null or _current.path != wanted:
		_current = load_from(wanted)
	return _current


## Forgets the loaded progress (tests): the next current() reads the file again.
static func reset() -> void:
	_current = null


## progress.cfg next to SaveManager.settings_path (progress_<n>.cfg for game instance n > 1;
## script_progress.cfg for script runs on the real user folder).
static func default_path() -> String:
	if not path_override.is_empty():
		return path_override
	var folder := SaveManager.settings_path.get_base_dir()
	var file := FILE_NAME if PlayerProfile.get_instance() <= 1 else INSTANCE_FILE_NAME % PlayerProfile.get_instance()
	if folder == SaveManager.DEFAULT_SETTINGS_PATH.get_base_dir() and PlayerProfile.is_script_run():
		file = SCRIPT_PREFIX + file
	return folder.path_join(file)


## Reads file_path; without a file the record and bosses of this machine's worlds are taken once
## (seed_from_worlds) and the file is written.
static func load_from(file_path: String) -> AccountProgress:
	var progress := AccountProgress.new()
	progress.path = file_path
	if FileAccess.file_exists(file_path) or FileAccess.file_exists(SafeSaveScript.backup_path(file_path)):
		progress._read()
	else:
		progress.seed_from_worlds()
		progress.save()
	return progress


func _read() -> void:
	var config := ConfigFile.new()
	if SafeSaveScript.load_config(config, path) != OK:
		return
	best_room = _int(config.get_value("account", "best_room", 0))
	bosses = _int(config.get_value("account", "bosses", 0))
	champions = _int(config.get_value("account", "champions", 0))
	runs = _int(config.get_value("account", "runs", 0))
	server_xp = _int(config.get_value("account", "server_xp", 0))
	var day: Variant = config.get_value("account", "last_bonus_day", "")
	last_bonus_day = day if typeof(day) == TYPE_STRING else ""
	entries.clear()
	var stored: Variant = config.get_value("xp", "entries", [])
	var sum := 0
	if stored is Array:
		for item: Variant in stored:
			var entry := _clean_entry(item)
			if not entry.is_empty() and not has_run(entry["run_id"]):
				entries.append(entry)
				sum += int(entry["xp"])
	bonus.clear()
	if config.has_section("bonus"):
		for id in config.get_section_keys("bonus"):
			var item := _clean_bonus(config.get_value("bonus", id, {}))
			if not item.is_empty():
				bonus[id] = item
				sum += int(item["xp"])
	# Synced entries may have been dropped from the file: the stored total keeps them.
	xp = maxi(sum, _int(config.get_value("account", "xp", 0)))
	_state.clear()
	if config.has_section("state"):
		for key in config.get_section_keys("state"):
			var data: Variant = config.get_value("state", key, {})
			if data is Dictionary:
				_state[key] = data


func save() -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "version", VERSION)
	config.set_value("account", "xp", xp)
	config.set_value("account", "server_xp", server_xp)
	config.set_value("account", "best_room", best_room)
	config.set_value("account", "bosses", bosses)
	config.set_value("account", "champions", champions)
	config.set_value("account", "runs", runs)
	config.set_value("account", "last_bonus_day", last_bonus_day)
	config.set_value("xp", "entries", entries)
	for key: String in _state:
		config.set_value("state", key, _state[key])
	for id: String in bonus:
		config.set_value("bonus", id, bonus[id])
	var err := SafeSaveScript.write_config(config, path)
	if err != OK:
		push_error("AccountProgress: could not write %s (%s)." % [path, error_string(err)])
	return err


## Takes the deepest room and the bosses of the worlds on this machine (all slots and the loaded
## save), so the account record starts where the player already is. Memory only.
func seed_from_worlds() -> void:
	var paths: Array[String] = []
	for slot in range(1, SaveSlots.SLOT_COUNT + 1):
		if SaveManager.has_slot(slot):
			paths.append(SaveManager.slot_path(slot))
	for slot_file in paths:
		var world := ProgressSummary.world_from_file(slot_file)
		best_room = maxi(best_room, int(world["stats"].get(StatsTracker.DEEPEST_ROOM, 0)))
		bosses += int(world["stats"].get(StatsTracker.BOSSES, 0))
		champions += int(world["stats"].get(StatsTracker.CHAMPIONS, 0))
	# The loaded save may be no slot (pre-slot save, a tool's file).
	if not paths.has(SaveManager.save_path):
		best_room = maxi(best_room, int(SaveManager.get_stat(StatsTracker.DEEPEST_ROOM)))
		bosses += int(SaveManager.get_stat(StatsTracker.BOSSES))
		champions += int(SaveManager.get_stat(StatsTracker.CHAMPIONS))


# --- State ---

## Total XP the level is computed from: the local sum, or the server's total plus what it does not
## know yet when that is larger (other devices, KF4).
func get_total_xp() -> int:
	return maxi(xp, server_xp + get_pending_xp())


func get_level() -> int:
	return level_for_xp(get_total_xp())


func get_level_info() -> Dictionary:
	return level_info(get_total_xp())


# --- Talent points (KONZEPT §4) ---

## Talent points of a level in total: one per level from level 2 (level 50 = 49).
static func talent_points_for_level(level: int) -> int:
	return maxi(0, level - 1)


func get_talent_points() -> int:
	return talent_points_for_level(get_level())


## Points already spent, from spent_points_source (the talents, KE6); 0 without it.
func get_spent_points() -> int:
	if not spent_points_source.is_valid():
		return 0
	return maxi(0, int(spent_points_source.call()))


## Points still free to spend (never below 0).
func get_free_points() -> int:
	return maxi(0, get_talent_points() - get_spent_points())


# --- Danger level and rank (KE1, DangerRank) ---

## Deepest room of the last runs counted here, newest first like the contract's dangerFromSkill
## (at most DangerRank.RECENT_RUNS).
func recent_deepest_rooms() -> Array[int]:
	var rooms: Array[int] = []
	for i in range(entries.size() - 1, maxi(-1, entries.size() - 1 - DangerRank.RECENT_RUNS), -1):
		rooms.append(int(entries[i]["deepest_room"]))
	return rooms


## This player's own danger level G (solo runs; a group uses the host's group level).
func get_danger_level() -> int:
	return DangerRank.danger_level(get_level(), recent_deepest_rooms())


## {"tier", "step"} of the own danger level (contract Rank).
func get_rank() -> Dictionary:
	return DangerRank.rank_for_danger(get_danger_level())


# --- Account state (KE1: seen flags, talents) ---

## A copy of the state stored under key ({} when there is none).
func get_state(key: String) -> Dictionary:
	var data: Variant = _state.get(key, {})
	return (data as Dictionary).duplicate(true) if data is Dictionary else {}


## Stores data under key (a copy; plain values only: numbers, strings, arrays, dictionaries) and
## writes the file at once.
func set_state(key: String, data: Dictionary) -> Error:
	if key.is_empty():
		push_error("AccountProgress.set_state: the key must not be empty.")
		return ERR_INVALID_PARAMETER
	_state[key] = data.duplicate(true)
	return save()


func has_state(key: String) -> bool:
	return _state.has(key)


func has_run(run_id: String) -> bool:
	for entry in entries:
		if entry["run_id"] == run_id:
			return true
	return false


## True when a run ending at unix time now would get the daily bonus (UTC day like the server).
func is_first_run_of_day(now := -1) -> bool:
	return last_bonus_day != utc_date(now)


## Counts a finished run once: input like compute_run_xp (record_before and first_of_day are filled
## in from this progress when missing; players defaults to 1; optional "end_reason" (END_*, else from
## "exit"), "duration" (s), "danger" (G the run was played on, 0 when missing)). Updates record, bosses and the daily bonus, applies the daily cap (the
## server defers such runs to the next day; here they count 0 until the sync) and saves. Returns {"added" (false for a known run id), "xp", "parts",
## "xp_before", "xp_after", "level_before", "level_after", "danger_before", "danger_after" (own G
## before and after this run counted, for "Rang gestiegen")}.
func record_run(run_id: String, run: Dictionary, now := -1) -> Dictionary:
	if now < 0:
		now = int(Time.get_unix_time_from_system())
	var before := get_total_xp()
	var danger_before := get_danger_level()
	var result := {"added": false, "xp": 0, "parts": [], "xp_before": before, "xp_after": before,
		"level_before": level_for_xp(before), "level_after": level_for_xp(before),
		"danger_before": danger_before, "danger_after": danger_before}
	if run_id.is_empty() or has_run(run_id):
		return result
	var input := run.duplicate()
	if not input.has("record_before"):
		input["record_before"] = best_room
	if not input.has("first_of_day"):
		input["first_of_day"] = is_first_run_of_day(now)
	var gained := compute_run_xp(input)
	var day := utc_day(now)
	var amount := mini(int(gained["xp"]), maxi(0, MAX_XP_PER_DAY - get_day_xp(day)))
	var reason := str(run.get("end_reason", END_PORTAL if run.get("exit", false) == true else END_WIPED))
	entries.append({
		"run_id": run_id, "xp": amount, "at": now, "day": day, "synced": false,
		"rooms": maxi(0, int(run.get("rooms_cleared", 0))), "champions": maxi(0, int(run.get("champions", 0))),
		"bosses": maxi(0, int(run.get("bosses", 0))), "deepest_room": maxi(0, int(run.get("room", 0))),
		"end_reason": reason, "players": clampi(int(run.get("players", 1)), 1, GameMode.MAX_PLAYERS),
		"duration": maxi(0, int(run.get("duration", 0))), "game_version": game_version(),
		"danger": maxi(0, int(run.get("danger", 0))),
	})
	xp += amount
	runs += 1
	best_room = maxi(best_room, int(run.get("room", 0)))
	bosses += maxi(0, int(run.get("bosses", 0)))
	champions += maxi(0, int(run.get("champions", 0)))
	if input.get("first_of_day", false) == true:
		last_bonus_day = utc_date(now)
	save()
	var after := get_total_xp()
	result["added"] = true
	result["xp"] = amount
	result["parts"] = gained["parts"]
	result["xp_after"] = after
	result["level_after"] = level_for_xp(after)
	result["danger_after"] = get_danger_level()
	return result


## One-time bonus XP outside a run (WK10: TutorialRules.credit_xp with id "tutorial", +25), counted
## once per id and account: part of the total (level, talent points, to_profile) and saved at once.
## Returns true when it counted. Server sync (KF4, platform contract later): an open bonus goes up as
## an XpEntry with endReason "tutorial" (runId = the id per account, no rooms); until the contract
## knows it, get_pending_xp_entries leaves it out and the local total keeps it.
func add_bonus_xp(id: String, amount: int, now := -1) -> bool:
	if id.is_empty() or amount <= 0 or bonus.has(id):
		return false
	if now < 0:
		now = int(Time.get_unix_time_from_system())
	bonus[id] = {"xp": amount, "at": now, "synced": false}
	xp += amount
	save()
	return true


func has_bonus_xp(id: String) -> bool:
	return bonus.has(id)


## XP already counted on a UTC day (the server's daily cap).
func get_day_xp(day: int) -> int:
	var total := 0
	for entry in entries:
		if int(entry["day"]) == day:
			total += int(entry["xp"])
	return total


# --- Server sync (KF4 hooks) ---

## Entries the server does not know yet, oldest first (copies of the stored entries).
func get_pending_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in entries:
		if not entry["synced"]:
			result.append(entry.duplicate())
	return result


## The open entries as the contract's XpEntry (POST /me/xp body "entries", oldest first, at most
## limit): runId, endedAt (ISO, UTC), durationSeconds, gameVersion, rooms, champions, bosses,
## deepestRoom, endReason, players, danger (KE1/KF3b). KF4 sends them as they are.
func get_pending_xp_entries(limit := 50) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in get_pending_entries():
		if result.size() >= limit:
			break
		result.append(xp_entry(entry))
	return result


## One stored entry in the contract's form (XpEntry, KF3).
static func xp_entry(entry: Dictionary) -> Dictionary:
	return {
		"runId": entry["run_id"],
		"endedAt": Time.get_datetime_string_from_unix_time(int(entry["at"])) + "Z",
		"durationSeconds": int(entry["duration"]),
		"gameVersion": String(entry["game_version"]),
		"rooms": int(entry["rooms"]),
		"champions": int(entry["champions"]),
		"bosses": int(entry["bosses"]),
		"deepestRoom": int(entry["deepest_room"]),
		"endReason": String(entry["end_reason"]),
		"players": int(entry["players"]),
		"danger": int(entry["danger"]),
	}


func get_pending_xp() -> int:
	var total := 0
	for entry in entries:
		if not entry["synced"]:
			total += int(entry["xp"])
	for id: String in bonus:
		if not bonus[id]["synced"]:
			total += int(bonus[id]["xp"])
	return total


## After POST /me/xp: these run ids are on the server (credited, duplicate or flagged; deferred ones
## stay open); total_xp (>= 0) is the server's total now (AddXpResponse.account.xp).
## Old synced entries beyond MAX_SYNCED_ENTRIES are dropped (the total keeps them). Saves.
func mark_synced(run_ids: Array, total_xp := -1) -> void:
	for entry in entries:
		if run_ids.has(entry["run_id"]):
			entry["synced"] = true
	if total_xp >= 0:
		server_xp = total_xp
	var synced := 0
	for i in range(entries.size() - 1, -1, -1):
		if entries[i]["synced"]:
			synced += 1
			if synced > MAX_SYNCED_ENTRIES:
				entries.remove_at(i)
	save()


## What goes into the profile for lobby, guild and leaderboard (KF4 sends it, D-188; danger and
## rank {"tier", "step"} like the contract's AccountDanger, KF3b).
func to_profile() -> Dictionary:
	var danger := get_danger_level()
	return {"xp": get_total_xp(), "level": get_level(), "danger": danger,
		"rank": {"tier": String(DangerRank.rank_for_danger(danger)["tier"]), "step": int(DangerRank.rank_for_danger(danger)["step"])}}


# --- Helpers ---

## A fresh run id (UUID v4 text), one per run and player.
static func new_run_id() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


## Days since 1970 in UTC (the server's day for the daily cap).
static func utc_day(unix_time: int) -> int:
	return floori(float(unix_time) / 86400.0)


## UTC calendar day "YYYY-MM-DD" of a unix time (-1 = now), like the contract's xpDayOf.
static func utc_date(unix_time := -1) -> String:
	if unix_time < 0:
		unix_time = int(Time.get_unix_time_from_system())
	return Time.get_date_string_from_unix_time(unix_time)


## "0.9.0" from project.godot (the contract's GameVersion), "0.0.0" when unset.
static func game_version() -> String:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	return version if not version.is_empty() else "0.0.0"


static func _clean_entry(item: Variant) -> Dictionary:
	if not item is Dictionary:
		return {}
	var raw := item as Dictionary
	var run_id: Variant = raw.get("run_id", "")
	if typeof(run_id) != TYPE_STRING or String(run_id).is_empty():
		return {}
	var at := _int(raw.get("at", 0))
	var reason: Variant = raw.get("end_reason", END_WIPED)
	var version: Variant = raw.get("game_version", "")
	return {
		"run_id": String(run_id), "xp": _int(raw.get("xp", 0)), "at": at,
		"day": _int(raw.get("day", utc_day(at))), "synced": raw.get("synced", false) == true,
		"rooms": _int(raw.get("rooms", 0)), "champions": _int(raw.get("champions", 0)),
		"bosses": _int(raw.get("bosses", 0)), "deepest_room": _int(raw.get("deepest_room", 0)),
		"end_reason": reason if reason in [END_PORTAL, END_WIPED, END_ABANDONED] else END_WIPED,
		"players": clampi(_int(raw.get("players", 1)), 1, GameMode.MAX_PLAYERS),
		"duration": _int(raw.get("duration", 0)), "danger": _int(raw.get("danger", 0)),
		"game_version": version if typeof(version) == TYPE_STRING and not String(version).is_empty() else game_version(),
	}


static func _clean_bonus(item: Variant) -> Dictionary:
	if not item is Dictionary:
		return {}
	var raw := item as Dictionary
	var amount := _int(raw.get("xp", 0))
	if amount <= 0:
		return {}
	return {"xp": amount, "at": _int(raw.get("at", 0)), "synced": raw.get("synced", false) == true}


static func _int(value: Variant) -> int:
	return maxi(0, int(value)) if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT else 0

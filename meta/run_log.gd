class_name RunLog
extends Node
## Local run protocol for play tests with people (P1-7): one JSON-lines file per run under
## user://runs/ (run_<date>_<time>.jsonl), at most MAX_RUNS files (the oldest go first). Only game
## data: no player or world name, no account or guild id (the project is open source and the files
## may be shared). Evaluated with `python tools/collect_feedback.py --runs`.
##
## Lines (every line one JSON object, written as it happens, so a crash keeps what came before):
##   {"type":"run", v, run, time, unix, game, debug, platform, mode, players, seed, weapons, boosts, meta}
##   {"type":"room", room, slot, room_type, special, kind, variant, branch, dark, biome, template,
##    start, duration, clear_time, damage, hits, gold, kills}       (when the room is left or the run ends)
##   {"type":"end", reason, room, biome, duration, cause, cause_kind, gold_earned, payout, crystals,
##    kills, rooms_cleared, damage, upgrades, weapons}
## reason: death, abort, exit (RunManager.EndReason) or quit (game closed / left mid-run, no payout).
## A file without an "end" line is a run that crashed. Times are unpaused game seconds (real seconds:
## HitStop's time scale is taken out), damage is shield + health of effective hits on the local
## player(s), gold is run gold collected (before spending).
##
## Not an autoload (D-044): StatsTracker (game.tscn) adds it as a child. It listens to EventBus and
## finds the dungeon and the players through the session owner (WorldController, GameMode.OWNER_GROUP):
## DungeonManager.room_activated and WorldController.player_spawned. No hotspot hooks needed.
## Script runs (GUT, tools) on the real user folder write nothing (AGENTS.md §6.4); tests set
## dir_override, tools may set the environment variable SOULWICK_RUN_LOG_DIR.

const FORMAT_VERSION := 1
## Number of run files kept (P1-7: "höchstens die letzten 50 Runs").
const MAX_RUNS := 50
const DIR_NAME := "runs"
const FILE_PREFIX := "run_"
const FILE_SUFFIX := ".jsonl"
## Tools: write the run log of a script run into this folder (absolute path or user://...).
const ENV_DIR := "SOULWICK_RUN_LOG_DIR"
## Global option (settings.cfg [options]) to switch the protocol off; on by default.
const OPTION_ENABLED: StringName = &"run_log"
const END_REASONS: Array[String] = ["death", "abort", "exit"]
const REASON_QUIT := "quit"
const CAUSE_UNKNOWN := "unknown"

## Tests: write here ("" = default_dir()).
static var dir_override := ""

var _active := false
var _path := ""
var _header: Dictionary = {}
var _header_written := false
var _run_time := 0.0
## The room the group is in: its record, open until the next room or the run end.
var _room: Dictionary = {}
var _room_start := 0.0
var _room_gold_start := 0
var _total_damage := 0.0
var _total_kills := 0
var _rooms_cleared := 0
## Upgrade id -> stacks (EventBus.upgrade_acquired).
var _upgrades: Dictionary = {}
## Weapon ids the local player held during the run, in order of appearance.
var _weapons: Array[String] = []
## What took the last HP of a local player (downed or dead): {cause, cause_kind}. Only killing hits
## count: a player killed outside the hurtbox (a tool, a script) has cause "unknown", not a stale hit.
var _killing_hit: Dictionary = {}
var _players: Array[Player] = []
var _owner_node: Node = null
var _dungeon: Node = null


func _ready() -> void:
	# Counts game time only (dialogs and the pause menu pause the tree in single player).
	process_mode = Node.PROCESS_MODE_PAUSABLE
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_ended.connect(_on_run_ended)
	EventBus.room_completed.connect(_on_room_completed)
	EventBus.enemy_damaged.connect(_on_enemy_damaged)
	EventBus.upgrade_acquired.connect(_on_upgrade_acquired)
	EventBus.weapon_changed.connect(_on_weapon_changed)


func _process(delta: float) -> void:
	if _active:
		_run_time += delta / maxf(Engine.time_scale, 0.01)


func _exit_tree() -> void:
	if _active:
		finish_run(REASON_QUIT, {})


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _active:
		finish_run(REASON_QUIT, {})


# --- Where the files go ---

## Folder of the run files; "" = no protocol (script run on the real user folder, or switched off).
static func default_dir() -> String:
	if not dir_override.is_empty():
		return dir_override
	var from_env := OS.get_environment(ENV_DIR)
	if not from_env.is_empty():
		return from_env
	if SaveManager.get_option(OPTION_ENABLED, true) != true:
		return ""
	var folder := SaveManager.settings_path.get_base_dir()
	if folder == SaveManager.DEFAULT_SETTINGS_PATH.get_base_dir() and PlayerProfile.is_script_run():
		return ""
	return folder.path_join(DIR_NAME)


## Run files in dir, oldest first (the names sort by time).
static func list_runs(dir: String) -> PackedStringArray:
	var result := PackedStringArray()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return result
	for file in DirAccess.get_files_at(dir):
		if file.begins_with(FILE_PREFIX) and file.ends_with(FILE_SUFFIX):
			result.append(file)
	result.sort()
	return result


## Removes the oldest run files until at most keep remain.
static func prune(dir: String, keep: int) -> void:
	var files := list_runs(dir)
	for index in maxi(0, files.size() - keep):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(files[index])))


## Reads a run file back: one Dictionary per complete line (a cut last line is skipped).
static func read_run(path: String) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return lines
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		# JSON.parse() instead of parse_string(): a cut line is skipped without an engine error.
		var json := JSON.new()
		if json.parse(line) == OK and json.data is Dictionary:
			lines.append(json.data)
	return lines


func is_active() -> bool:
	return _active


## File of the current (or last) run, "" when nothing is written.
func get_file_path() -> String:
	return _path


# --- Run lifecycle (public for tests; the signal handlers call these) ---

## Opens a new run file (the previous run, if still open, ends as "quit"). header: the fields of the
## "run" line besides type, v, run, time and unix (mode, players, seed, weapons, boosts, meta, ...).
## The line itself is written with the first room (the weapons are known then) or at the end.
func begin_run(header: Dictionary) -> void:
	if _active:
		finish_run(REASON_QUIT, {})
	_reset()
	var dir := default_dir()
	if dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	prune(dir, MAX_RUNS - 1)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var base_name := FILE_PREFIX + stamp
	var path := dir.path_join(base_name + FILE_SUFFIX)
	var counter := 2
	while FileAccess.file_exists(path):
		path = dir.path_join("%s_%d%s" % [base_name, counter, FILE_SUFFIX])
		counter += 1
	_path = path
	_active = true
	_header = {
		"type": "run",
		"v": FORMAT_VERSION,
		"run": path.get_file().get_basename(),
		"time": Time.get_datetime_string_from_system(false, true),
		"unix": int(Time.get_unix_time_from_system()),
		"game": str(ProjectSettings.get_setting("application/config/version", "")),
		"debug": OS.is_debug_build(),
		"platform": OS.get_name(),
	}
	_header.merge(header, true)


## The group entered a room (info: room_info()). Closes the record of the room before.
func enter_room(info: Dictionary) -> void:
	if not _active:
		return
	_write_header()
	_close_room()
	_room = info.duplicate()
	_room["type"] = "room"
	_room["start"] = _round(_run_time)
	_room["clear_time"] = null
	_room["damage"] = 0.0
	_room["hits"] = 0
	_room["kills"] = 0
	_room_start = _run_time
	_room_gold_start = RunManager.get_run_gold_earned()


## An effective hit on a local player (shield and health damage); cause from describe_cause(),
## killed: the hit took the last HP (the cause of death if the run ends by death).
func record_hit(shield_damage: float, health_damage: float, cause: Dictionary = {}, killed := false) -> void:
	if not _active:
		return
	var amount := maxf(0.0, shield_damage) + maxf(0.0, health_damage)
	if amount <= 0.0:
		return
	_total_damage += amount
	if not _room.is_empty():
		_room["damage"] = float(_room["damage"]) + amount
		_room["hits"] = int(_room["hits"]) + 1
	if killed and not cause.is_empty():
		_killing_hit = cause


## Ends the run: writes the open room and the "end" line. summary: RunManager.get_last_summary()
## ({} for "quit").
func finish_run(reason: String, summary: Dictionary) -> void:
	if not _active:
		return
	_write_header()
	_close_room()
	var room := int(summary.get("room", RunManager.get_current_room()))
	var upgrades := {}
	for id in _upgrades:
		upgrades[String(id)] = _upgrades[id]
	_append({
		"type": "end",
		"reason": reason,
		"room": room,
		"biome": biome_id(room),
		"duration": _round(_run_time),
		"cause": _killing_hit.get("cause", CAUSE_UNKNOWN) if reason == "death" else "",
		"cause_kind": _killing_hit.get("cause_kind", CAUSE_UNKNOWN) if reason == "death" else "",
		"gold_earned": int(summary.get("gold_earned", RunManager.get_run_gold_earned())),
		"payout": int(summary.get("payout", 0)),
		"crystals": int(summary.get("crystal_payout", 0)),
		"kills": _total_kills,
		"rooms_cleared": _rooms_cleared,
		"damage": _round(_total_damage),
		"upgrades": upgrades,
		"weapons": _weapons.duplicate(),
	})
	_active = false
	_unbind()


# --- Descriptions (language independent ids, never display names) ---

## Room record fields of a RoomController.
static func room_info(room: RoomController) -> Dictionary:
	var info := {
		"room": room.room_index,
		"slot": room.slot_index,
		"room_type": enum_id(RoomSequence.RoomType.keys(), room.room_type),
		"special": enum_id(RoomSequence.SpecialType.keys(), room.special_type) if room.room_type == RoomSequence.RoomType.SPECIAL else "",
		"kind": enum_id(RoomSequence.RoomKind.keys(), room.room_kind) if room.has_room_kind() else "",
		"variant": String(room.get_variant_id()),
		"branch": room.is_branch_room(),
		"dark": room.is_extra_dark,
		"biome": biome_id(room.room_index),
		"template": room.scene_file_path.get_file().get_basename(),
	}
	return info


## "crypt", "slime_grotto", ... for a room number.
static func biome_id(room_index: int) -> String:
	return enum_id(RoomSequence.Biome.keys(), RoomSequence.get_biome(maxi(1, room_index)))


static func enum_id(keys: Array, value: int) -> String:
	return String(keys[value]).to_lower() if value >= 0 and value < keys.size() else ""


## What dealt a hit: {cause: enemy id or trap tag, cause_kind: boss, champion, elite, enemy, trap,
## unknown}.
static func describe_cause(damage: DamageData) -> Dictionary:
	if damage == null:
		return {"cause": CAUSE_UNKNOWN, "cause_kind": CAUSE_UNKNOWN}
	var source: Node = damage.source if is_instance_valid(damage.source) else null
	var enemy := source as Enemy
	if enemy != null and enemy.data != null:
		var kind := "enemy"
		if enemy.data.is_boss:
			kind = "boss"
		elif enemy.is_miniboss:
			kind = "champion"
		elif enemy.elite != Enemy.Elite.NONE:
			kind = "elite"
		return {"cause": String(enemy.data.id), "cause_kind": kind}
	for entry in RunRecap.TRAP_CAUSES:
		if damage.tags.has(entry[0]):
			return {"cause": String(entry[0]), "cause_kind": "trap"}
	return {"cause": CAUSE_UNKNOWN, "cause_kind": CAUSE_UNKNOWN}


# --- Signals ---

func _on_run_started() -> void:
	_bind_session()
	var mode := GameMode.of_tree(get_tree())
	var header := {
		"mode": enum_id(GameMode.Kind.keys(), mode.kind),
		"players": mode.get_player_count(),
		# A string: a 64-bit seed does not survive JSON readers that use doubles.
		"seed": str(_dungeon_seed()),
		"boosts": _strings(RunManager.get_run_boosts()),
		"meta": {},
	}
	if mode.get_meta_source() == GameMode.MetaSource.LOCAL:
		var meta := {}
		for id in MetaProgression.UPGRADE_ORDER:
			meta[String(id)] = SaveManager.get_meta_level(id)
		header["meta"] = meta
	begin_run(header)


func _on_run_ended(reason: int, _remaining: int, _payout: int) -> void:
	var reason_id := END_REASONS[reason] if reason >= 0 and reason < END_REASONS.size() else str(reason)
	finish_run(reason_id, RunManager.get_last_summary())


func _on_room_activated(room: RoomController) -> void:
	if is_instance_valid(room):
		enter_room(room_info(room))


func _on_room_completed(room_index: int) -> void:
	if not _active:
		return
	_rooms_cleared += 1
	if not _room.is_empty() and int(_room.get("room", -1)) == room_index and _room["clear_time"] == null:
		_room["clear_time"] = _round(_run_time - _room_start)


func _on_enemy_damaged(_enemy: Node2D, result: DamageResult, _damage: DamageData) -> void:
	if not _active or result == null or not result.killed:
		return
	_total_kills += 1
	if not _room.is_empty():
		_room["kills"] = int(_room["kills"]) + 1


func _on_upgrade_acquired(upgrade_id: StringName, stacks: int) -> void:
	if _active:
		_upgrades[upgrade_id] = stacks


func _on_weapon_changed(_slot: int, weapon: WeaponData) -> void:
	if _active and weapon != null and not _weapons.has(String(weapon.id)):
		_weapons.append(String(weapon.id))


func _on_player_spawned(player: Player) -> void:
	if not _active or player == null or not player.is_local or _players.has(player):
		return
	_players.append(player)
	player.hurtbox.hit_received.connect(_on_player_hit)
	for weapon in player.weapon_controller.get_owned_weapons():
		if weapon != null and not _weapons.has(String(weapon.id)):
			_weapons.append(String(weapon.id))


func _on_player_hit(result: DamageResult, damage: DamageData) -> void:
	if result == null or result.blocked:
		return
	record_hit(result.shield_damage, result.health_damage, describe_cause(damage) if result.killed else {}, result.killed)


# --- Internals ---

## The dungeon (room_activated) and the session owner (player_spawned) of this run. The dungeon is
## the owner's world already: RunManager.start_run() runs inside DungeonManager._ready.
func _bind_session() -> void:
	_unbind()
	if not is_inside_tree():
		return
	_owner_node = get_tree().get_first_node_in_group(GameMode.OWNER_GROUP)
	if _owner_node == null:
		return
	if _owner_node.has_signal(&"player_spawned"):
		_owner_node.connect(&"player_spawned", _on_player_spawned)
	var world: Variant = _owner_node.call(&"get_world") if _owner_node.has_method(&"get_world") else null
	if world is Node and (world as Node).has_signal(&"room_activated"):
		_dungeon = world
		_dungeon.connect(&"room_activated", _on_room_activated)


func _unbind() -> void:
	if is_instance_valid(_owner_node) and _owner_node.is_connected(&"player_spawned", _on_player_spawned):
		_owner_node.disconnect(&"player_spawned", _on_player_spawned)
	if is_instance_valid(_dungeon) and _dungeon.is_connected(&"room_activated", _on_room_activated):
		_dungeon.disconnect(&"room_activated", _on_room_activated)
	for player in _players:
		if is_instance_valid(player) and player.hurtbox.hit_received.is_connected(_on_player_hit):
			player.hurtbox.hit_received.disconnect(_on_player_hit)
	_players.clear()
	_owner_node = null
	_dungeon = null


func _dungeon_seed() -> int:
	if not is_instance_valid(_dungeon):
		return 0
	var context: Variant = _dungeon.get(&"context")
	if context is DungeonContext and (context as DungeonContext).rng != null:
		return int((context as DungeonContext).rng.seed)
	return 0


func _reset() -> void:
	_active = false
	_path = ""
	_header = {}
	_header_written = false
	_run_time = 0.0
	_room = {}
	_room_start = 0.0
	_room_gold_start = 0
	_total_damage = 0.0
	_total_kills = 0
	_rooms_cleared = 0
	_upgrades = {}
	_weapons.clear()
	_killing_hit = {}


func _write_header() -> void:
	if _header_written or not _active:
		return
	_header["weapons"] = _weapons.duplicate()
	_append(_header)
	_header_written = true


func _close_room() -> void:
	if _room.is_empty():
		return
	_room["duration"] = _round(_run_time - _room_start)
	_room["gold"] = maxi(0, RunManager.get_run_gold_earned() - _room_gold_start)
	_room["damage"] = _round(float(_room["damage"]))
	_append(_room)
	_room = {}


func _append(record: Dictionary) -> void:
	if _path.is_empty():
		return
	var exists := FileAccess.file_exists(_path)
	var file := FileAccess.open(_path, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if file == null:
		push_warning("RunLog: could not write %s (%s)." % [_path, error_string(FileAccess.get_open_error())])
		return
	file.seek_end()
	file.store_line(JSON.stringify(record))
	file.close()


static func _round(value: float) -> float:
	return snappedf(value, 0.1)


static func _strings(ids: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for id in ids:
		result.append(String(id))
	return result

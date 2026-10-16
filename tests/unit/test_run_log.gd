extends GutTest
## P1-7: the local run protocol (RunLog) writes one JSON-lines file per run (run, room..., end), keeps
## at most MAX_RUNS files, holds only game data and writes nothing for script runs on the real user
## folder. Files go to a test folder only (dir_override); the save is a test file.

const RunLogScript := preload("res://meta/run_log.gd")
const DIR := "user://test_run_log"
const SAVE_PATH := "user://test_run_log_save.cfg"
## Keys a line may carry: game data only (P1-7, open source: no names, no account or guild ids).
const RUN_KEYS := ["type", "v", "run", "time", "unix", "game", "debug", "platform", "mode", "players", "seed", "weapons", "boosts", "meta"]
const ROOM_KEYS := ["type", "room", "slot", "room_type", "special", "kind", "variant", "branch", "dark", "biome", "template", "start", "duration", "clear_time", "damage", "hits", "gold", "kills"]
const END_KEYS := ["type", "reason", "room", "biome", "duration", "cause", "cause_kind", "gold_earned", "payout", "crystals", "kills", "rooms_cleared", "damage", "upgrades", "weapons"]

var _old_save_path: String
var _log: Node


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = SAVE_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	SaveManager.load_game()


func before_each() -> void:
	_wipe()
	RunLogScript.dir_override = DIR
	_log = RunLogScript.new()
	add_child_autofree(_log)


func after_each() -> void:
	if RunManager.is_run_active():
		RunManager.end_run(RunManager.EndReason.ABORT)
	RunLogScript.dir_override = ""


func after_all() -> void:
	_wipe()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	for suffix in ["", ".prev.bak", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH + suffix))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func _wipe() -> void:
	var dir := ProjectSettings.globalize_path(DIR)
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))


func _room(index: int, room_type := "combat") -> Dictionary:
	return {"room": index, "slot": index, "room_type": room_type, "special": "", "kind": "normal", "variant": "",
		"branch": false, "dark": false, "biome": RunLogScript.biome_id(index), "template": "test_room"}


func _lines() -> Array[Dictionary]:
	return RunLogScript.read_run(_log.get_file_path())


func test_script_runs_on_the_real_folder_write_nothing() -> void:
	RunLogScript.dir_override = ""
	if OS.get_environment(RunLogScript.ENV_DIR).is_empty() and SaveManager.settings_path.get_base_dir() == SaveManager.DEFAULT_SETTINGS_PATH.get_base_dir():
		assert_eq(RunLogScript.default_dir(), "", "GUT never writes into user://runs")
	else:
		pass_test("settings point elsewhere in this run")


func test_a_run_writes_header_rooms_and_end() -> void:
	_log.begin_run({"mode": "solo", "players": 1, "seed": "42", "boosts": [], "meta": {}})
	_log.enter_room(_room(1))
	_log.record_hit(0.0, 1.0, {"cause": "skeleton", "cause_kind": "enemy"}, true)
	_log.record_hit(3.0, 0.0, {})
	_log.record_hit(0.0, 1.0, {"cause": "pit", "cause_kind": "trap"})
	_log.enter_room(_room(2, "special"))
	_log.finish_run("death", {"room": 2, "gold_earned": 17, "payout": 9, "crystal_payout": 1})
	var lines := _lines()
	assert_eq(lines.size(), 4, "run, room 1, room 2, end")
	assert_eq(lines[0]["type"], "run")
	assert_eq(str(lines[0]["seed"]), "42")
	assert_eq(int(lines[0]["v"]), RunLogScript.FORMAT_VERSION)
	assert_eq(lines[1]["type"], "room")
	assert_eq(int(lines[1]["room"]), 1)
	assert_eq(lines[1]["biome"], "crypt")
	assert_almost_eq(float(lines[1]["damage"]), 5.0, 0.01, "shield and health")
	assert_eq(int(lines[1]["hits"]), 3)
	assert_eq(lines[2]["room_type"], "special")
	var end := lines[3]
	assert_eq(end["type"], "end")
	assert_eq(end["reason"], "death")
	assert_eq(int(end["room"]), 2)
	assert_eq(end["cause"], "skeleton", "the hit that took the last HP, not a later one")
	assert_eq(end["cause_kind"], "enemy")
	assert_eq(int(end["gold_earned"]), 17)
	assert_eq(int(end["crystals"]), 1)
	assert_false(_log.is_active())


func test_death_without_a_killing_hit_has_an_unknown_cause() -> void:
	_log.begin_run({})
	_log.enter_room(_room(4))
	_log.record_hit(0.0, 1.0, {"cause": "slime", "cause_kind": "enemy"})
	_log.finish_run("death", {"room": 4})
	var end: Dictionary = _lines().back()
	assert_eq(end["cause"], RunLogScript.CAUSE_UNKNOWN, "no stale hit as the cause")


func test_lines_hold_only_game_data() -> void:
	_log.begin_run({"mode": "solo", "players": 1, "seed": 1, "boosts": [], "meta": {"vitality": 2}})
	_log.enter_room(_room(1))
	_log.finish_run("exit", {})
	var lines := _lines()
	for key in lines[0]:
		assert_has(RUN_KEYS, key, "run line key %s" % key)
	for key in lines[1]:
		assert_has(ROOM_KEYS, key, "room line key %s" % key)
	for key in lines[2]:
		assert_has(END_KEYS, key, "end line key %s" % key)
	var text := FileAccess.get_file_as_string(_log.get_file_path())
	var player_name := PlayerProfile.current().player_name
	if not player_name.is_empty():
		assert_false(text.contains(player_name), "no player name")


func test_signals_drive_a_whole_run() -> void:
	RunManager.start_run()
	assert_true(_log.is_active(), "run_started opens a file")
	_log.enter_room(_room(1))
	RunManager.add_run_gold(25)
	EventBus.room_completed.emit(1)
	EventBus.upgrade_acquired.emit(&"sharp_edge", 2)
	RunManager.end_run(RunManager.EndReason.EXIT)
	var lines := _lines()
	assert_eq(lines.size(), 3)
	assert_eq(lines[0]["mode"], "solo")
	assert_eq(int(lines[1]["gold"]), 25, "run gold collected in the room")
	assert_not_null(lines[1]["clear_time"], "the room was cleared")
	assert_eq(lines[2]["reason"], "exit")
	assert_eq(int(lines[2]["rooms_cleared"]), 1)
	assert_eq(int(lines[2]["upgrades"]["sharp_edge"]), 2)
	assert_eq(lines[2]["cause"], "", "no cause unless the run ended by death")


func test_leaving_mid_run_ends_as_quit() -> void:
	_log.begin_run({})
	_log.enter_room(_room(3))
	var path: String = _log.get_file_path()
	remove_child(_log)
	var lines := RunLogScript.read_run(path)
	assert_eq(lines.back()["type"], "end")
	assert_eq(lines.back()["reason"], RunLogScript.REASON_QUIT)


func test_at_most_max_runs_are_kept() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	for index in RunLogScript.MAX_RUNS + 5:
		var file := FileAccess.open(DIR.path_join("run_2000-01-01_00-00-%02d.jsonl" % index), FileAccess.WRITE)
		file.store_line("{}")
		file.close()
	_log.begin_run({})
	_log.finish_run("abort", {})
	var files := RunLogScript.list_runs(DIR)
	assert_eq(files.size(), RunLogScript.MAX_RUNS)
	assert_false(files.has("run_2000-01-01_00-00-00.jsonl"), "the oldest went first")
	assert_true(files.has(_log.get_file_path().get_file()), "the new run is kept")


func test_a_cut_last_line_is_skipped_when_reading() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var path := DIR.path_join("run_cut.jsonl")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{\"type\":\"run\"}\n{\"type\":\"room\",\"ro")
	file.close()
	var lines := RunLogScript.read_run(path)
	assert_eq(lines.size(), 1)
	assert_engine_error_count(0)


func test_nothing_is_written_without_a_folder() -> void:
	RunLogScript.dir_override = ""
	if not RunLogScript.default_dir().is_empty():
		pass_test("a folder is configured in this run")
		return
	_log.begin_run({})
	assert_false(_log.is_active())
	assert_eq(_log.get_file_path(), "")


func test_ids_are_language_independent() -> void:
	assert_eq(RunLogScript.biome_id(1), "crypt")
	assert_eq(RunLogScript.biome_id(16), "slime_grotto")
	assert_eq(RunLogScript.enum_id(RoomSequence.RoomType.keys(), RoomSequence.RoomType.BOSS), "boss")
	var trap := DamageData.new()
	trap.tags.assign([&"pit"])
	assert_eq(RunLogScript.describe_cause(trap), {"cause": "pit", "cause_kind": "trap"})
	assert_eq(RunLogScript.describe_cause(null)["cause"], RunLogScript.CAUSE_UNKNOWN)

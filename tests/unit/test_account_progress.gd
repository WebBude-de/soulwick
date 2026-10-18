extends GutTest
## Account level (D-188, KF2): the curve 50·L·(L−1) and the XP of a run as pure functions, entries
## per run id exactly once in progress.cfg (daily bonus, caps, record), the first file takes the
## worlds' record, pending entries and the profile values for the later server sync (KF4).
## progress.cfg lives in a test folder (SaveManager.set_storage_root / path_override), never the
## real one (AGENTS.md rule 4).

const ROOT := "user://test_account_progress"
## 2026-10-18 12:00 UTC.
const NOON := 1792324800

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String
var _old_locale: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	_old_locale = TranslationServer.get_locale()


func before_each() -> void:
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()
	AccountProgress.path_override = ""
	AccountProgress.reset()
	Loc.apply(&"de")


func after_all() -> void:
	_wipe()
	AccountProgress.path_override = ""
	AccountProgress.reset()
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()
	PlayerProfile.reset()
	TranslationServer.set_locale(_old_locale)


func _wipe() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	for dir_path in [root.path_join("saves"), root]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			DirAccess.remove_absolute(dir_path.path_join(file))
	DirAccess.make_dir_recursive_absolute(root.path_join("saves"))


func _part(result: Dictionary, id: StringName) -> int:
	for part: Dictionary in result["parts"]:
		if part["id"] == id:
			return int(part["xp"])
	return 0


# --- Curve (the platform computes the same, KF3) ---

func test_level_curve() -> void:
	assert_eq(AccountProgress.xp_for_level(1), 0)
	assert_eq(AccountProgress.xp_for_level(2), 100)
	assert_eq(AccountProgress.xp_for_level(3), 300)
	assert_eq(AccountProgress.xp_for_level(5), 1000)
	assert_eq(AccountProgress.xp_for_level(10), 4500)
	assert_eq(AccountProgress.xp_for_level(20), 19000)
	assert_eq(AccountProgress.xp_for_level(50), 122500)
	for level in range(1, 120):
		var at := AccountProgress.xp_for_level(level)
		assert_eq(AccountProgress.level_for_xp(at), level, "exactly at level %d" % level)
		assert_eq(AccountProgress.level_for_xp(at - 1), maxi(1, level - 1), "just below level %d" % level)
	assert_eq(AccountProgress.level_for_xp(-5), 1)
	var info := AccountProgress.level_info(340)
	assert_eq(info["level"], 3)
	assert_eq(info["into"], 40)
	assert_eq(info["needed"], 300)
	assert_almost_eq(float(info["ratio"]), 40.0 / 300.0, 0.0001)


func test_next_reward_every_five_levels_up_to_fifty() -> void:
	assert_eq(AccountProgress.next_reward_level(1), 5)
	assert_eq(AccountProgress.next_reward_level(5), 10)
	assert_eq(AccountProgress.next_reward_level(49), 50)
	assert_eq(AccountProgress.next_reward_level(50), 0, "no reward after 50 (§5.5)")


# --- XP of a run (pure) ---

func test_run_xp_from_the_concept_table() -> void:
	var result := AccountProgress.compute_run_xp({
		"rooms_cleared": 12, "champions": 2, "bosses": 1, "room": 16, "record_before": 13,
		"exit": true, "first_of_day": true, "players": 1,
	})
	assert_eq(_part(result, AccountProgress.PART_ROOMS), 60)
	assert_eq(_part(result, AccountProgress.PART_CHAMPIONS), 20)
	assert_eq(_part(result, AccountProgress.PART_BOSSES), 50)
	assert_eq(_part(result, AccountProgress.PART_RECORD), 15, "5 per room above the old record")
	assert_eq(_part(result, AccountProgress.PART_PORTAL), 20)
	assert_eq(_part(result, AccountProgress.PART_DAILY), 25)
	assert_eq(result["xp"], 190)
	assert_eq(_part(result, AccountProgress.PART_COOP), 0, "solo: no bonus")


func test_coop_adds_twenty_percent_and_the_cap_holds() -> void:
	var solo := AccountProgress.compute_run_xp({"rooms_cleared": 10, "players": 1})
	var coop := AccountProgress.compute_run_xp({"rooms_cleared": 10, "players": 3})
	assert_eq(solo["xp"], 50)
	assert_eq(coop["xp"], 60, "+20 % (TESTWERT)")
	assert_eq(_part(coop, AccountProgress.PART_COOP), 10)
	var odd := AccountProgress.compute_run_xp({"rooms_cleared": 7, "players": 2})
	assert_eq(_part(odd, AccountProgress.PART_COOP), 7, "35 · 20 % = 7")
	var down := AccountProgress.compute_run_xp({"rooms_cleared": 1, "champions": 1, "players": 2})
	assert_eq(_part(down, AccountProgress.PART_COOP), 3, "15 · 20 % = 3, rounded down like the contract's runXp")
	var huge := AccountProgress.compute_run_xp({"rooms_cleared": 900, "bosses": 40})
	assert_eq(huge["xp"], AccountProgress.MAX_XP_PER_RUN)
	var nothing := AccountProgress.compute_run_xp({})
	assert_eq(nothing["xp"], 0)
	assert_eq((nothing["parts"] as Array).size(), 0, "only parts that brought something")


func test_part_texts() -> void:
	assert_eq(AccountProgress.part_text({"id": AccountProgress.PART_ROOMS, "count": 12, "xp": 60}), "Raum ×12")
	assert_eq(AccountProgress.part_text({"id": AccountProgress.PART_BOSSES, "count": 1, "xp": 50}), "Boss")
	assert_eq(AccountProgress.part_text({"id": AccountProgress.PART_COOP, "count": 2, "xp": 9}), "Koop-Bonus")
	assert_eq(XpGainView.parts_text([{"id": AccountProgress.PART_ROOMS, "count": 2, "xp": 10}, {"id": AccountProgress.PART_DAILY, "count": 1, "xp": 25}]),
			"Raum ×2 +10 · Erster Run heute +25")


# --- The file ---

func test_progress_lives_next_to_the_settings() -> void:
	assert_eq(AccountProgress.default_path(), ROOT.path_join("progress.cfg"))
	assert_true(AccountProgress.current().path.begins_with(ROOT))
	# Only the path is computed: the real folder is not opened.
	var test_settings := SaveManager.settings_path
	SaveManager.settings_path = SaveManager.DEFAULT_SETTINGS_PATH
	assert_eq(AccountProgress.default_path(), "user://script_progress.cfg", "script runs never touch the real file")
	SaveManager.settings_path = test_settings
	AccountProgress.path_override = ROOT.path_join("other.cfg")
	assert_eq(AccountProgress.default_path(), ROOT.path_join("other.cfg"))
	AccountProgress.path_override = ""


func test_a_run_counts_exactly_once() -> void:
	var progress := AccountProgress.current()
	var run := {"rooms_cleared": 5, "room": 6}
	var first := progress.record_run("run-a", run, NOON)
	assert_true(first["added"])
	assert_eq(first["xp"], 25 + 30 + 25, "rooms, record above 0, first run of the day")
	assert_eq(first["xp_before"], 0)
	assert_eq(first["xp_after"], 80)
	var again := progress.record_run("run-a", run, NOON + 60)
	assert_false(again["added"], "the same run id is counted once")
	assert_eq(progress.get_total_xp(), 80)
	var second := progress.record_run("run-b", {"rooms_cleared": 4, "room": 5}, NOON + 120)
	assert_eq(second["xp"], 20, "no daily bonus and no record the second time")
	assert_eq(progress.best_room, 6)
	assert_eq(progress.runs, 2)
	# From the file again.
	AccountProgress.reset()
	var loaded := AccountProgress.current()
	assert_eq(loaded.get_total_xp(), 100)
	assert_true(loaded.has_run("run-a") and loaded.has_run("run-b"))
	assert_eq(loaded.best_room, 6)
	assert_false(loaded.is_first_run_of_day(NOON + 300))
	assert_false(loaded.is_first_run_of_day(NOON + 11 * 3600 + 59 * 60), "still the same UTC day")
	assert_true(loaded.is_first_run_of_day(NOON + 12 * 3600), "the next UTC day pays the bonus again")


func test_level_up_in_the_result() -> void:
	var progress := AccountProgress.current()
	progress.record_run("warmup", {"rooms_cleared": 18}, NOON)
	var result := progress.record_run("boss", {"rooms_cleared": 30, "bosses": 1, "room": 15, "record_before": 15}, NOON + 10)
	assert_eq(result["xp"], 200, "30 rooms and a boss, no daily bonus the second time")
	assert_eq(result["xp_before"], 115)
	assert_eq(result["level_before"], 2)
	assert_eq(result["level_after"], 3, "315 XP")


func test_daily_cap_and_pending_entries() -> void:
	var progress := AccountProgress.current()
	for i in 10:
		progress.record_run("big-%d" % i, {"rooms_cleared": 900}, NOON + i)
	assert_eq(progress.get_day_xp(AccountProgress.utc_day(NOON)), AccountProgress.MAX_XP_PER_DAY)
	var capped := progress.record_run("big-10", {"rooms_cleared": 900}, NOON + 20)
	assert_eq(capped["xp"], 0, "the day is full (server cap, TESTWERT)")
	assert_true(capped["added"], "the run is still known (counted once)")
	var pending := progress.get_pending_entries()
	assert_eq(pending.size(), 11)
	assert_eq(pending[0]["run_id"], "big-0")
	progress.mark_synced(["big-0", "big-1"], 4000)
	assert_eq(progress.get_pending_entries().size(), 9)
	assert_eq(progress.get_total_xp(), maxi(progress.xp, 4000 + progress.get_pending_xp()))
	assert_eq(progress.to_profile(), {"xp": progress.get_total_xp(), "level": progress.get_level()})


func test_entries_carry_the_contract_fields_for_the_sync() -> void:
	var progress := AccountProgress.current()
	progress.record_run("0b6c6a8e-3a7d-4c1e-9d43-1f2a3b4c5d6e", {"rooms_cleared": 14, "champions": 2, "bosses": 1,
			"room": 16, "exit": true, "players": 2, "duration": 754}, NOON)
	var sent := progress.get_pending_xp_entries()
	assert_eq(sent.size(), 1)
	assert_eq(sent[0], {
		"runId": "0b6c6a8e-3a7d-4c1e-9d43-1f2a3b4c5d6e", "endedAt": "2026-10-18T12:00:00Z", "durationSeconds": 754,
		"gameVersion": AccountProgress.game_version(), "rooms": 14, "champions": 2, "bosses": 1, "deepestRoom": 16,
		"endReason": "portal", "players": 2,
	}, "POST /me/xp entry (KF3 XpEntry)")
	assert_eq(RunRecap.xp_end_reason(RunManager.EndReason.DEATH), "wiped")
	assert_eq(RunRecap.xp_end_reason(RunManager.EndReason.ABORT), "abandoned")
	AccountProgress.reset()
	assert_eq(AccountProgress.current().get_pending_xp_entries(), sent, "the same after a reload")


func test_server_total_from_other_devices_counts() -> void:
	var progress := AccountProgress.current()
	progress.record_run("local", {"rooms_cleared": 4}, NOON)
	progress.mark_synced(["local"], 5000)
	assert_eq(progress.get_total_xp(), 5000, "XP from another device (KF4)")
	assert_eq(progress.get_level(), 10)


func test_first_file_takes_the_record_of_the_worlds() -> void:
	SaveManager.create_slot(1, "Alt")
	SaveManager.record_stat_max(StatsTracker.DEEPEST_ROOM, 31)
	SaveManager.add_stat(StatsTracker.BOSSES, 2)
	SaveManager.save_game()
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tests/fixtures/save_v2_legacy.cfg"),
			ProjectSettings.globalize_path(SaveManager.slot_path(2)))
	AccountProgress.reset()
	var progress := AccountProgress.current()
	assert_eq(progress.best_room, 45, "the deepest room of all worlds (old v2 save: 45)")
	assert_eq(progress.bosses, 12)
	assert_eq(progress.get_total_xp(), 0, "no XP from old statistics (D-188: XP only from runs)")
	assert_true(FileAccess.file_exists(ROOT.path_join("progress.cfg")))
	var result := progress.record_run("after-update", {"rooms_cleared": 3, "room": 4}, NOON)
	assert_eq(_part(result, AccountProgress.PART_RECORD), 0, "an old player gets no record XP for room 4")


func test_broken_file_starts_empty_without_crashing() -> void:
	var path := ROOT.path_join("progress.cfg")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("[xp]\nentries=[{\"run_id\": 5}, \"junk\", {\"run_id\": \"ok\", \"xp\": 12, \"at\": 1}]\n[account]\nbest_room=\"x\"\n")
	file.close()
	AccountProgress.reset()
	var progress := AccountProgress.current()
	assert_eq(progress.entries.size(), 1, "invalid entries are dropped")
	assert_eq(progress.get_total_xp(), 12)
	assert_eq(progress.best_room, 0)


func test_run_ids_are_unique_uuids() -> void:
	var ids := {}
	var pattern := RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
	for i in 50:
		var id := AccountProgress.new_run_id()
		assert_not_null(pattern.search(id), id)
		ids[id] = true
	assert_eq(ids.size(), 50)

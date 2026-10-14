extends GutTest
## UX1 run end: RunRecap counts kills, cleared rooms, upgrades and time and names what hit the
## player; the run end dialog shows them and offers "Zurück ins Dorf" (Enter) or "Neuer Run" (N).
## Uses a test save (SaveManager.save_path), never the real one.

const TEST_SAVE_PATH := "user://test_ux_run_end.cfg"

var _old_locale: String
var _old_save_path: String


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	# The expected texts are German; English is the default language (D-111).
	Loc.apply(&"de")
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.load_game()


func after_each() -> void:
	GameManager.clear_pause_reasons()


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func _kill_result() -> DamageResult:
	var result := DamageResult.new()
	result.killed = true
	return result


func _trap_hit(tags: Array[StringName]) -> DamageData:
	var damage := DamageData.new()
	damage.amount = 1.0
	damage.tags.assign(tags)
	return damage


func test_duration_format() -> void:
	assert_eq(RunRecap.format_duration(0.0), "0:00")
	assert_eq(RunRecap.format_duration(247.9), "4:07")
	assert_eq(RunRecap.format_duration(3729.0), "1:02:09")


func test_trap_causes_have_german_names() -> void:
	assert_eq(RunRecap.describe_hit(_trap_hit([&"trap", &"fire"])), "Lavaspalt")
	assert_eq(RunRecap.describe_hit(_trap_hit([&"trap", &"poison"])), "Giftlache")
	assert_eq(RunRecap.describe_hit(_trap_hit([&"trap"])), "Stachelfalle")
	assert_eq(RunRecap.describe_hit(_trap_hit([])), "", "unknown stays empty")
	assert_eq(RunRecap.describe_hit(null), "")


func test_recap_counts_only_during_a_run() -> void:
	var recap := RunRecap.new()
	add_child_autofree(recap)
	EventBus.enemy_damaged.emit(null, _kill_result(), DamageData.new())
	assert_eq(recap.kills, 0, "no run, no count")
	recap.reset()
	EventBus.enemy_damaged.emit(null, _kill_result(), DamageData.new())
	EventBus.enemy_damaged.emit(null, DamageResult.new(), DamageData.new())
	EventBus.room_completed.emit(1)
	EventBus.upgrade_acquired.emit(&"strong_attack", 1)
	EventBus.upgrade_acquired.emit(&"strong_attack", 2)
	await wait_physics_frames(3)
	var stats := recap.get_stats()
	assert_eq(stats["kills"], 1, "only kills count")
	assert_eq(stats["rooms_cleared"], 1)
	assert_eq(stats["upgrades"], 2, "every upgrade pick counts")
	assert_gt(stats["play_time"], 0.0)
	EventBus.run_ended.emit(RunManager.EndReason.DEATH, 0, 0)
	EventBus.enemy_damaged.emit(null, _kill_result(), DamageData.new())
	assert_eq(recap.kills, 1, "stops at the run end")


func test_run_end_dialog_shows_stats_and_starts_a_new_run_with_n() -> void:
	var ui := GameUI.new()
	add_child_autofree(ui)
	var summary := {
		"reason": RunManager.EndReason.DEATH, "room": 12, "remaining_gold": 40, "payout": 20,
		"gold_earned": 95, "remaining_crystals": 2, "crystal_payout": 1,
	}
	var stats := {"kills": 31, "rooms_cleared": 11, "upgrades": 4, "play_time": 754.0, "cause": "Skelett", "record_before": 9}
	var result: Array = []
	var run_end := func() -> void: result.append(await ui.show_run_end(summary, stats))
	run_end.call()
	await wait_physics_frames(1)
	var modal := ui.find_children("*", "Modal", true, false)[0] as Modal
	var texts: PackedStringArray = []
	for label in modal.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	var all := "\n".join(texts)
	for expected in ["Du bist gefallen", "Todesursache: Skelett", "Neuer Rekord!", "31", "11", "4", "12:34",
			"Run-Gold gesammelt", "95", "+20", "+1", "Gold im Dorf"]:
		assert_string_contains(all, expected)
	var buttons := modal.find_children("*", "Button", true, false)
	var captions: PackedStringArray = []
	for button in buttons:
		captions.append((button as Button).text)
	assert_has(captions, "Zurück ins Dorf")
	assert_has(captions, "Neuer Run")
	assert_true(GameManager.has_pause_reason(GameManager.PAUSE_RUN_END))
	(modal.hotkeys[KEY_N] as Callable).call()
	await wait_physics_frames(1)
	assert_eq(result, [GameUI.RUN_END_NEW_RUN])


func test_run_end_default_is_the_village() -> void:
	var ui := GameUI.new()
	add_child_autofree(ui)
	var result: Array = []
	var run_end := func() -> void: result.append(await ui.show_run_end({"reason": RunManager.EndReason.EXIT, "room": 3}, {"kills": 0}))
	run_end.call()
	await wait_physics_frames(1)
	var modal := ui.find_children("*", "Modal", true, false)[0] as Modal
	assert_true(modal.accept_allowed, "Enter has a default")
	modal.finish(modal.accept_result)
	await wait_physics_frames(1)
	assert_eq(result, [GameUI.RUN_END_VILLAGE])
	assert_false(GameManager.is_game_paused())

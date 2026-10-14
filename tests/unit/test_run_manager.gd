extends GutTest
## RunManager gold, payout and run-end guarantees (D-038, D-039).

const TEST_SAVE_PATH := "user://test_run_manager_save.cfg"

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func test_start_run_resets_state() -> void:
	assert_true(RunManager.is_run_active())
	assert_eq(RunManager.get_current_room(), 1)
	assert_eq(RunManager.get_run_gold(), 0)


func test_spend_is_all_or_nothing() -> void:
	RunManager.add_run_gold(10)
	assert_false(RunManager.try_spend_run_gold(11))
	assert_eq(RunManager.get_run_gold(), 10, "Failed purchase must not change gold")
	assert_true(RunManager.try_spend_run_gold(10))
	assert_eq(RunManager.get_run_gold(), 0)


func test_negative_amounts_are_rejected() -> void:
	RunManager.add_run_gold(-5)
	assert_eq(RunManager.get_run_gold(), 0)
	assert_false(RunManager.try_spend_run_gold(-1))


func test_run_ends_only_once() -> void:
	watch_signals(EventBus)
	assert_true(RunManager.end_run(RunManager.EndReason.DEATH))
	assert_false(RunManager.end_run(RunManager.EndReason.EXIT), "Second end must be rejected (no double payout)")
	assert_signal_emit_count(EventBus, "run_ended", 1)


func test_advance_room() -> void:
	assert_eq(RunManager.advance_room(), 2)
	assert_eq(RunManager.get_current_room(), 2)


func test_payout_ratios() -> void:
	assert_eq(RunManager.calculate_payout(40, RunManager.EndReason.EXIT), 40, "regular exit: 100 %")
	assert_eq(RunManager.calculate_payout(40, RunManager.EndReason.DEATH), 20, "death: 50 %")
	assert_eq(RunManager.calculate_payout(40, RunManager.EndReason.ABORT), 20, "abort: 50 %")
	assert_eq(RunManager.calculate_payout(7, RunManager.EndReason.DEATH), 4, "odd amounts round up (D-062)")
	assert_eq(RunManager.calculate_payout(0, RunManager.EndReason.EXIT), 0)


func test_payout_is_credited_exactly_once() -> void:
	var before := SaveManager.get_permanent_gold()
	RunManager.add_run_gold(30)
	RunManager.end_run(RunManager.EndReason.EXIT)
	RunManager.end_run(RunManager.EndReason.EXIT)
	assert_eq(SaveManager.get_permanent_gold(), before + 30)
	assert_eq(RunManager.get_last_summary().get("payout"), 30)

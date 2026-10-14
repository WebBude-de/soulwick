extends GutTest
## UX1 first-run controls card: shown once per save (SaveManager "hint_controls"), rows turn done
## when the key is used, two steps, never pauses the game. Uses a test save, never the real one.

const TEST_SAVE_PATH := "user://test_ux_controls_hint.cfg"

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH


func before_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.load_game()


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func _action(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _hint() -> ControlsHint:
	var hint := ControlsHint.new()
	add_child_autofree(hint)
	return hint


func test_fresh_save_shows_it_and_used_keys_tick_off() -> void:
	assert_true(ControlsHint.should_show(), "a fresh save has not seen the controls")
	var hint := _hint()
	assert_eq(hint.get_stage(), 0)
	hint._input(_action(&"move_left"))
	assert_true(hint.is_done(ControlsInfo.MOVE), "any move key counts")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(ControlsHint.AIM_DISTANCE + 1.0, 0.0)
	hint._input(motion)
	assert_true(hint.is_done(ControlsInfo.AIM))
	hint._input(_action(&"attack"))
	hint._input(_action(&"dash"))
	assert_true(hint.is_done(ControlsInfo.DASH))
	assert_false(GameManager.is_game_paused(), "the card never pauses")
	await wait_seconds(ControlsHint.DONE_LINGER + 0.2)
	assert_eq(hint.get_stage(), 1, "all four keys used: the second step follows quickly")
	hint._input(_action(&"special_attack"))
	assert_true(hint.is_done(ControlsInfo.SPECIAL))


func test_finishing_marks_the_save() -> void:
	var hint := _hint()
	watch_signals(hint)
	hint.finish()
	assert_signal_emitted(hint, "finished")
	assert_true(SaveManager.has_seen(ControlsHint.SEEN_ID))
	assert_false(ControlsHint.should_show(), "once per save")


func test_leaving_the_first_room_ends_it() -> void:
	var hint := _hint()
	EventBus.room_entered.emit(1)
	assert_false(SaveManager.has_seen(ControlsHint.SEEN_ID), "room 1 keeps it")
	EventBus.room_entered.emit(2)
	assert_true(SaveManager.has_seen(ControlsHint.SEEN_ID))


func test_dungeon_ui_shows_it_only_once() -> void:
	var ui := DungeonUI.new()
	ui.auto_enemy_hints = false
	add_child_autofree(ui)
	await wait_physics_frames(1)
	var hint := ui.get_controls_hint()
	assert_not_null(hint, "first run: the card appears")
	hint.finish()
	await wait_physics_frames(1)
	assert_null(ui.start_controls_hint(), "seen: no second card")
	var other := DungeonUI.new()
	other.show_controls_hint = false
	add_child_autofree(other)
	await wait_physics_frames(1)
	assert_null(other.get_controls_hint(), "tools can switch it off")

extends GutTest
## UX1 first-run controls card: shown once per save (SaveManager "hint_controls"), rows turn done
## when the key is used, two steps, never pauses the game. P1-4: step 2 lasts until its keys were
## used (at most until room 4), the special row says "ready", the overview row points at the first
## upgrade, the HUD's key line hides meanwhile, gamepad symbols. Uses a test save, never the real one.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const InputDeviceScript := preload("res://player/input/input_device.gd")
const GamepadInputScript := preload("res://player/input/gamepad_input.gd")

const TEST_SAVE_PATH := "user://test_ux_controls_hint.cfg"

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH


func before_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.load_game()


func after_each() -> void:
	InputDeviceScript.shared().set_kind(InputDeviceScript.Kind.KEYBOARD_MOUSE)


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


func test_step_two_lasts_into_room_three_and_ends_with_room_four() -> void:
	# P1-4: room 1 is cleared in ~15 s; the second step must not get lost with it.
	var hint := _hint()
	EventBus.room_entered.emit(1)
	assert_eq(hint.get_stage(), 0, "room 1 keeps step 1")
	EventBus.room_entered.emit(2)
	assert_eq(hint.get_stage(), 1, "room 2 moves on to step 2")
	assert_false(SaveManager.has_seen(ControlsHint.SEEN_ID), "and keeps the card")
	assert_true(is_inf(hint._time_left), "step 2 has no timer")
	EventBus.room_entered.emit(3)
	assert_false(hint.is_finishing(), "room 3 still shows step 2")
	EventBus.room_entered.emit(ControlsHint.LAST_ROOM)
	assert_true(hint.is_finishing(), "room 4 ends it at the latest")
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


func test_step_two_ends_once_its_four_keys_were_used() -> void:
	var hint := _hint()
	hint._show_stage(1)
	for action: StringName in [&"special_attack", &"switch_weapon", &"interact"]:
		hint._input(_action(action))
	assert_false(hint.is_finishing(), "three of four keys: it stays")
	hint._input(_action(&"upgrade_overview"))
	assert_true(hint.is_done(ControlsInfo.OVERVIEW))
	await wait_seconds(ControlsHint.DONE_LINGER + 0.2)
	assert_true(hint.is_finishing(), "all four keys used: the card ends")
	assert_true(SaveManager.has_seen(ControlsHint.SEEN_ID))


func test_keys_count_while_another_card_holds_it() -> void:
	var hint := _hint()
	# DungeonUI disables the card behind an enemy card; the tracker child still sees the keys.
	hint.process_mode = Node.PROCESS_MODE_DISABLED
	var tracker := hint.get_node("HeldInputTracker")
	tracker._input(_action(&"dash"))
	assert_true(hint.is_done(ControlsInfo.DASH))
	hint.process_mode = Node.PROCESS_MODE_PAUSABLE
	tracker._input(_action(&"attack"))
	assert_false(hint.is_done(ControlsInfo.ATTACK), "running card: its own _input counts, not twice")


func test_first_upgrade_shows_step_two_and_points_at_the_overview() -> void:
	var hint := _hint()
	EventBus.upgrade_acquired.emit(&"test_upgrade", 1)
	assert_eq(hint.get_stage(), 1, "the first upgrade brings step 2")
	assert_eq(hint.get_tag(ControlsInfo.OVERVIEW), ControlsHint.TAG_UPGRADE)
	var tag := hint._rows[ControlsInfo.OVERVIEW].get_meta(&"tag") as Label
	assert_true(tag.visible)
	hint._input(_action(&"upgrade_overview"))
	assert_eq(hint.get_tag(ControlsInfo.OVERVIEW), &"", "opened: the tag goes")
	assert_false(tag.visible)


func test_special_row_says_ready_and_hud_hides_its_key_line() -> void:
	var hud: Hud = add_child_autofree(Hud.new())
	var player: Player = add_child_autofree(PLAYER_SCENE.instantiate())
	hud.set_dungeon_mode(true)
	hud.bind_player(player)
	assert_eq(Hud.local_player(get_tree()), player, "the HUD names its player")
	var hint := _hint()
	await wait_process_frames(2)
	assert_false(hud._hint_row.visible, "the card shows the keys: no second key line")
	hint._show_stage(1)
	await wait_process_frames(2)
	assert_eq(hint.get_tag(ControlsInfo.SPECIAL), ControlsHint.TAG_READY, "the special is ready")
	var controller := player.weapon_controller
	controller._special_cooldowns[controller.get_active_slot()] = 3.0
	await wait_process_frames(2)
	assert_eq(hint.get_tag(ControlsInfo.SPECIAL), &"", "recharging: no tag")
	hint.finish()
	await wait_process_frames(2)
	assert_true(hud._hint_row.visible, "the key line comes back with the card gone")
	assert_eq(hud._hint_row.get_child_count(), Hud.HINT_ENTRIES_SHORT.size(), "in its short form")


func test_gamepad_symbols_and_right_stick_aim() -> void:
	GamepadInputScript.ensure_actions()
	var hint := _hint()
	InputDeviceScript.shared().set_kind(InputDeviceScript.Kind.GAMEPAD)
	var caps := (hint._rows[ControlsInfo.ATTACK] as Control).find_children("Key", "KeyCap", true, false)
	assert_eq(caps.size(), 1)
	assert_eq((caps[0] as KeyCap).glyph_id, InputGlyphs.pad_id_for_action(&"attack"), "attack shows the pad button")
	var aim_caps := (hint._rows[ControlsInfo.AIM] as Control).find_children("Key", "KeyCap", true, false)
	assert_eq((aim_caps[0] as KeyCap).glyph_id, InputGlyphs.aim_id(), "aiming shows the right stick")
	hint._input(_action(GamepadInputScript.AIM_RIGHT))
	assert_true(hint.is_done(ControlsInfo.AIM), "the right stick counts as aiming")
	InputDeviceScript.shared().set_kind(InputDeviceScript.Kind.KEYBOARD_MOUSE)
	caps = (hint._rows[ControlsInfo.ATTACK] as Control).find_children("Key", "KeyCap", true, false)
	assert_eq((caps[0] as KeyCap).glyph_id, InputGlyphs.MOUSE_LEFT, "back to the mouse")
	assert_true(hint.is_done(ControlsInfo.AIM), "rebuilt rows keep their state")


func test_overview_key_shows_once_in_the_upgrade_dialog() -> void:
	var entry := ControlsHint.take_overview_key_hint()
	assert_eq(entry.size(), 2, "[key, caption]")
	assert_eq(String(entry[0]), ControlsInfo.key_text(ControlsInfo.OVERVIEW))
	assert_false(String(entry[1]).is_empty())
	assert_eq(ControlsHint.take_overview_key_hint(), [], "once per save")

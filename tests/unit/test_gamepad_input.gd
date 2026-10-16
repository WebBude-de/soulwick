extends GutTest
## Gamepad (P0-2): runtime bindings in the InputMap, two sticks like touch (left walks, right aims,
## RT attack, LT special, A dash, B side dash, X interact, Y switch, Start pause, Back overview),
## aim in walking direction without the right stick, light aim assist for ranged weapons (option),
## device detection (InputDevice: symbols and mouse cursor follow the device in use) and the
## gamepad symbols of InputGlyphs. Events are simulated InputEventJoypadMotion/Button.
## Runs in a test folder (SaveManager.set_storage_root), never on the real settings or save.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://enemies/enemy_base.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
const BOW: WeaponData = preload("res://weapons/data/bow.tres")
const SWORD: WeaponData = preload("res://weapons/data/sword.tres")
const ROOT := "user://test_gamepad_input"
const AXES: Array[JoyAxis] = [
	JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT,
]
const BUTTONS: Array[JoyButton] = [
	JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_START, JOY_BUTTON_BACK,
	JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT,
	JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER,
]

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()
	GamepadInput.ensure_actions()


func before_each() -> void:
	InputDevice.shared().set_kind(InputDevice.Kind.KEYBOARD_MOUSE)


func after_each() -> void:
	_neutral()
	InputDevice.shared().set_kind(InputDevice.Kind.KEYBOARD_MOUSE)
	GameOptions.set_gamepad_aim_assist(true)


func after_all() -> void:
	await wait_seconds(0.3)
	_wipe()
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()
	PlayerProfile.reset()


func _wipe() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	for dir_path in [root.path_join("saves"), root]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			DirAccess.remove_absolute(dir_path.path_join(file))
	DirAccess.make_dir_recursive_absolute(root)


# --- Simulated gamepad (a new event every time: Godot warns about re-parsed events) ---

func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	return event


func _button(index: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = index
	event.pressed = pressed
	event.pressure = 1.0 if pressed else 0.0
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	return event


func _neutral() -> void:
	for axis in AXES:
		_axis(axis, 0.0)
	for index in BUTTONS:
		_button(index, false)


func _has_event(action: StringName, expected: InputEvent) -> bool:
	return InputMap.has_action(action) and InputMap.action_has_event(action, expected)


# --- Bindings ---

func test_bindings_are_registered_at_runtime_once() -> void:
	assert_true(_has_event(&"attack", GamepadInput.axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)), "RT attacks")
	assert_true(_has_event(&"special_attack", GamepadInput.axis(JOY_AXIS_TRIGGER_LEFT, 1.0)), "LT special")
	assert_true(_has_event(&"dash", GamepadInput.button(JOY_BUTTON_A)), "A dash")
	assert_true(_has_event(&"side_dash", GamepadInput.button(JOY_BUTTON_B)), "B side dash")
	assert_true(_has_event(&"interact", GamepadInput.button(JOY_BUTTON_X)), "X interact")
	assert_true(_has_event(&"switch_weapon", GamepadInput.button(JOY_BUTTON_Y)), "Y switch weapon")
	assert_true(_has_event(&"pause_menu", GamepadInput.button(JOY_BUTTON_START)), "Start pause")
	assert_true(_has_event(&"upgrade_overview", GamepadInput.button(JOY_BUTTON_BACK)), "Back overview")
	assert_true(_has_event(&"move_left", GamepadInput.axis(JOY_AXIS_LEFT_X, -1.0)), "left stick walks")
	assert_true(_has_event(&"move_up", GamepadInput.button(JOY_BUTTON_DPAD_UP)), "D-pad walks")
	assert_true(_has_event(&"ui_accept", GamepadInput.button(JOY_BUTTON_A)), "A confirms in menus")
	assert_true(_has_event(&"ui_cancel", GamepadInput.button(JOY_BUTTON_B)), "B goes back in menus")
	for action in GamepadInput.AIM_ACTIONS:
		assert_true(InputMap.has_action(action), "%s exists at runtime" % action)
		assert_almost_eq(InputMap.action_get_deadzone(action), GamepadInput.AIM_DEADZONE, 0.0001)
	var before := InputMap.action_get_events(&"dash").size()
	GamepadInput.ensure_actions()
	assert_eq(InputMap.action_get_events(&"dash").size(), before, "idempotent")
	var first := InputMap.action_get_events(&"dash")[0]
	assert_true(first is InputEventKey, "project keys stay first (keyboard shown by default)")


func test_ensure_actions_comes_back_after_an_input_map_reload() -> void:
	InputMap.erase_action(GamepadInput.AIM_RIGHT)
	GamepadInput.ensure_actions()
	assert_true(_has_event(GamepadInput.AIM_RIGHT, GamepadInput.axis(JOY_AXIS_RIGHT_X, 1.0)))


# --- Polling the local input ---

func test_left_stick_walks_with_a_dead_zone() -> void:
	var input := LocalKeyboardMouseInput.new()
	_axis(JOY_AXIS_LEFT_X, 1.0)
	input.poll(null)
	assert_gt(input.move.x, 0.95, "full right")
	_axis(JOY_AXIS_LEFT_X, 0.1)
	input.poll(null)
	assert_eq(input.move, Vector2.ZERO, "inside the dead zone")
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_button(JOY_BUTTON_DPAD_DOWN, true)
	input.poll(null)
	assert_gt(input.move.y, 0.95, "D-pad down")


func test_buttons_and_triggers_drive_the_actions() -> void:
	var input := LocalKeyboardMouseInput.new()
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.9)
	_button(JOY_BUTTON_A, true)
	input.poll(null)
	assert_true(input.is_pressed(PlayerInput.ATTACK), "RT")
	assert_true(input.is_just_pressed(PlayerInput.DASH), "A")
	assert_false(input.is_pressed(PlayerInput.SPECIAL))
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	_button(JOY_BUTTON_X, true)
	_button(JOY_BUTTON_Y, true)
	_button(JOY_BUTTON_B, true)
	input.poll(null)
	assert_false(input.is_pressed(PlayerInput.ATTACK), "RT released")
	assert_true(input.is_pressed(PlayerInput.SPECIAL), "LT")
	assert_true(input.is_pressed(PlayerInput.INTERACT), "X")
	assert_true(input.is_pressed(PlayerInput.SWITCH_WEAPON), "Y")
	assert_true(input.is_pressed(PlayerInput.SIDE_DASH), "B")
	_axis(JOY_AXIS_TRIGGER_LEFT, 0.1)
	input.poll(null)
	assert_false(input.is_pressed(PlayerInput.SPECIAL), "a resting finger on LT does not count")


func test_right_stick_aims_and_without_it_the_walking_direction_counts() -> void:
	var input := LocalKeyboardMouseInput.new()
	InputDevice.shared().set_kind(InputDevice.Kind.GAMEPAD)
	_axis(JOY_AXIS_RIGHT_Y, -1.0)
	_axis(JOY_AXIS_LEFT_X, 1.0)
	input.poll(null)
	assert_almost_eq(input.get_aim_direction(Vector2.ZERO, Vector2.DOWN), Vector2.UP, Vector2(0.001, 0.001), "right stick wins")
	_axis(JOY_AXIS_RIGHT_Y, 0.1)
	input.poll(null)
	assert_almost_eq(input.get_aim_direction(Vector2.ZERO, Vector2.DOWN), Vector2.RIGHT, Vector2(0.001, 0.001), "stick in its dead zone: walking direction")
	_axis(JOY_AXIS_LEFT_X, 0.0)
	input.poll(null)
	assert_almost_eq(input.get_aim_direction(Vector2.ZERO, Vector2.DOWN), Vector2.RIGHT, Vector2(0.001, 0.001), "standing still keeps the last aim")


func test_the_aim_stick_takes_over_even_before_the_device_switched() -> void:
	# A watcher left by an earlier test (GameOptions.apply_controls) would switch the device on the
	# stick; this test is about the moment before that switch.
	var watcher := InputDeviceWatcher.get_instance()
	var watcher_mode := Node.PROCESS_MODE_INHERIT
	if is_instance_valid(watcher):
		watcher_mode = watcher.process_mode
		watcher.process_mode = Node.PROCESS_MODE_DISABLED
	var input := LocalKeyboardMouseInput.new()
	_axis(JOY_AXIS_RIGHT_X, -0.8)
	input.poll(null)
	assert_almost_eq(input.get_aim_direction(Vector2.ZERO, Vector2.DOWN), Vector2.LEFT, Vector2(0.001, 0.001))
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	input.poll(null)
	assert_eq(input.aim_direction, Vector2.ZERO, "keyboard and mouse in use: the mouse aims again")
	if is_instance_valid(watcher):
		watcher.process_mode = watcher_mode


func test_mouse_aim_is_unchanged_on_keyboard_and_mouse() -> void:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	await wait_physics_frames(1)
	player.set_physics_process(false)
	var input := LocalKeyboardMouseInput.new()
	input.poll(player)
	assert_eq(input.aim_direction, Vector2.ZERO, "aims at aim_point (the mouse)")
	assert_eq(input.aim_point, player.get_global_mouse_position())


# --- Aim assist (ranged weapons, option) ---

func _player(weapon: WeaponData) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(1)
	player.set_physics_process(false)
	var controller := player.weapon_controller
	if controller.get_active_weapon() != weapon:
		var slot := controller.get_active_slot()
		if not controller.equip_weapon(weapon, slot):
			var other := (slot + 1) % WeaponController.MAX_WEAPON_SLOTS
			controller.equip_weapon(weapon, other)
			controller.set_active_slot(other)
	assert_eq(controller.get_active_weapon(), weapon, "holds %s" % weapon.id)
	return player


func _enemy(pos: Vector2) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.data = SKELETON
	enemy.global_position = pos
	add_child_autofree(enemy)
	enemy.set_physics_process(false)
	return enemy


func test_bow_aim_snaps_onto_an_enemy_in_the_cone_unless_switched_off() -> void:
	var player: Player = await _player(BOW)
	var origin := TouchAimAssist.aim_origin(player)
	var target := _enemy(origin + Vector2.RIGHT.rotated(deg_to_rad(8.0)) * 250.0)
	await wait_physics_frames(1)
	var pad := GamepadInput.new()
	var snapped := pad.update_aim(player, Vector2.RIGHT, Vector2.ZERO, true)
	assert_almost_eq(snapped, (target.global_position - origin).normalized(), Vector2(0.001, 0.001), "snapped onto the enemy")
	assert_almost_eq(pad.update_aim(player, Vector2.RIGHT, Vector2.ZERO, false), Vector2.RIGHT, Vector2(0.001, 0.001), "option off: plain stick")
	assert_almost_eq(pad.update_aim(player, Vector2.ZERO, Vector2.RIGHT, true), Vector2.RIGHT, Vector2(0.001, 0.001), "only while the aim stick is deflected")
	InputDevice.shared().set_kind(InputDevice.Kind.GAMEPAD)
	var input := LocalKeyboardMouseInput.new()
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	input.poll(player)
	assert_almost_eq(input.aim_direction, snapped, Vector2(0.001, 0.001), "the local input uses it (option on by default)")
	GameOptions.set_gamepad_aim_assist(false)
	input.poll(player)
	assert_almost_eq(input.aim_direction, Vector2.RIGHT, Vector2(0.001, 0.001), "option off")


func test_sword_gets_no_assist() -> void:
	var player: Player = await _player(SWORD)
	var origin := TouchAimAssist.aim_origin(player)
	_enemy(origin + Vector2.RIGHT.rotated(deg_to_rad(8.0)) * 60.0)
	await wait_physics_frames(1)
	assert_almost_eq(GamepadInput.new().update_aim(player, Vector2.RIGHT, Vector2.ZERO, true), Vector2.RIGHT, Vector2(0.001, 0.001))


func test_player_walks_aims_and_attacks_with_the_pad() -> void:
	var player: Player = await _player(SWORD)
	player.set_physics_process(true)
	InputDevice.shared().set_kind(InputDevice.Kind.GAMEPAD)
	watch_signals(player.weapon_controller)
	var start := player.global_position
	_axis(JOY_AXIS_LEFT_X, 1.0)
	_axis(JOY_AXIS_RIGHT_Y, 1.0)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await wait_physics_frames(8)
	assert_gt(player.global_position.x, start.x + 5.0, "walked right")
	assert_almost_eq(player.get_aim_direction(), Vector2.DOWN, Vector2(0.001, 0.001), "aims down with the right stick")
	assert_signal_emitted(player.weapon_controller, "attack_performed", "RT swings")


# --- Device detection ---

func test_device_follows_the_last_real_input() -> void:
	var device := InputDevice.new()
	watch_signals(device)
	var drift := InputEventJoypadMotion.new()
	drift.axis = JOY_AXIS_LEFT_X
	drift.axis_value = 0.2
	assert_false(device.note(drift), "stick drift is no gamepad use")
	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	press.device = 2
	assert_true(device.note(press))
	assert_eq(device.kind, InputDevice.Kind.GAMEPAD)
	assert_eq(device.joypad, 2)
	assert_signal_emitted_with_parameters(device, "changed", [InputDevice.Kind.GAMEPAD])
	var jitter := InputEventMouseMotion.new()
	jitter.relative = Vector2(1, 0)
	assert_false(device.note(jitter), "a bumped mouse does not switch back")
	var trigger := InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger.axis_value = 0.5
	assert_false(device.note(trigger), "already the gamepad")
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(12, 4)
	assert_true(device.note(mouse), "a real mouse move switches back")
	assert_eq(device.kind, InputDevice.Kind.KEYBOARD_MOUSE)
	device.note(press.duplicate())
	assert_true(device.note(MenuInput.key_event(KEY_W)), "a key press switches back too")
	var emulated := InputEventMouseButton.new()
	emulated.pressed = true
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	device.note(press.duplicate())
	assert_false(device.note(emulated), "mouse events made from touches do not count")


func test_cursor_hides_only_for_the_gamepad() -> void:
	assert_true(InputDevice.wants_hidden_cursor(InputDevice.Kind.GAMEPAD))
	assert_false(InputDevice.wants_hidden_cursor(InputDevice.Kind.KEYBOARD_MOUSE))
	assert_false(InputDevice.wants_hidden_cursor(InputDevice.Kind.TOUCH))


func test_gamepad_use_leaves_the_touch_controls() -> void:
	var touch := TouchState.shared()
	var was_touched := touch.touched
	touch.touched = true
	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_START
	press.pressed = true
	InputDevice.new().note(press)
	assert_eq(touch.touched, touch.forced, "back from the on-screen controls (unless forced)")
	touch.touched = was_touched


func test_watcher_feeds_the_shared_device() -> void:
	InputDeviceWatcher.ensure(get_tree())
	InputDeviceWatcher.ensure(get_tree())
	await wait_process_frames(1)
	var watcher := InputDeviceWatcher.get_instance()
	assert_not_null(watcher)
	assert_eq(get_tree().root.get_children().filter(func(node: Node) -> bool: return node is InputDeviceWatcher).size(), 1, "one watcher")
	assert_eq(watcher.process_mode, Node.PROCESS_MODE_ALWAYS, "also in paused menus")
	_button(JOY_BUTTON_Y, true)
	assert_true(InputDevice.is_gamepad(), "the watcher saw the button")


# --- Symbols ---

func test_glyphs_follow_the_device_in_use() -> void:
	assert_eq(InputGlyphs.id_for_action(&"attack"), InputGlyphs.MOUSE_LEFT, "keyboard and mouse by default")
	assert_eq(InputGlyphs.aim_id(), InputGlyphs.MOUSE)
	assert_eq(InputGlyphs.id_for_name("Enter"), InputGlyphs.ENTER)
	InputDevice.shared().set_kind(InputDevice.Kind.GAMEPAD)
	if InputGlyphs.is_touch():
		pass_test("touch forced on this machine: touch symbols win")
		return
	assert_eq(InputGlyphs.id_for_action(&"attack"), InputGlyphs.PAD_RT)
	assert_eq(InputGlyphs.id_for_action(&"special_attack"), InputGlyphs.PAD_LT)
	assert_eq(InputGlyphs.id_for_action(&"dash"), InputGlyphs.PAD_SOUTH)
	assert_eq(InputGlyphs.id_for_action(&"interact"), InputGlyphs.PAD_WEST)
	assert_eq(InputGlyphs.id_for_action(&"switch_weapon"), InputGlyphs.PAD_NORTH)
	assert_eq(InputGlyphs.id_for_action(&"pause_menu"), InputGlyphs.PAD_START)
	assert_eq(InputGlyphs.id_for_action(&"upgrade_overview"), InputGlyphs.PAD_SELECT)
	assert_eq(InputGlyphs.id_for_action(&"move_up"), InputGlyphs.PAD_STICK_LEFT, "the stick before the D-pad")
	assert_eq(InputGlyphs.aim_id(), InputGlyphs.PAD_STICK_RIGHT)
	assert_eq(InputGlyphs.glyph_for_action(&"dash"), InputGlyphs.PAD_SOUTH)
	assert_eq(InputGlyphs.id_for_name("Enter"), InputGlyphs.PAD_SOUTH, "menu Enter is A")
	assert_eq(InputGlyphs.id_for_name("Esc"), InputGlyphs.PAD_EAST, "menu Esc is B")
	assert_eq(InputGlyphs.id_for_name(ControlsInfo.action_key(&"dash")), InputGlyphs.PAD_SOUTH, "the space key's name is A")
	assert_eq(InputGlyphs.id_for_name("1 – 3"), &"", "no binding: stays text")
	var cap := KeyCap.for_action(&"attack")
	assert_eq(cap.glyph_id, InputGlyphs.PAD_RT, "KeyCap shows the trigger")
	cap.free()
	InputDevice.shared().set_kind(InputDevice.Kind.KEYBOARD_MOUSE)
	assert_eq(InputGlyphs.id_for_action(&"attack"), InputGlyphs.MOUSE_LEFT, "back to the mouse")
	assert_eq(InputGlyphs.glyph_for_action(&"dash"), InputGlyphs.SPACE)


# --- Options ---

func test_aim_assist_option_defaults_on_and_is_stored() -> void:
	assert_true(GameOptions.is_gamepad_aim_assist_enabled(), "on by default")
	GameOptions.set_gamepad_aim_assist(false)
	SaveManager.load_settings()
	assert_false(GameOptions.is_gamepad_aim_assist_enabled(), "stored in settings.cfg")
	GameOptions.reset_to_defaults()
	assert_true(GameOptions.is_gamepad_aim_assist_enabled(), "reset turns it on again")


func test_options_view_has_the_aim_assist_row_and_pad_tab_switching() -> void:
	var view := OptionsView.new()
	add_child_autofree(view)
	view.select_row(OptionsView.Row.AIM_ASSIST)
	assert_eq(view.get_tab(), OptionsView.Tab.GENERAL, "on the Allgemein tab (Steuerung)")
	assert_eq(view.get_choice_buttons(OptionsView.Row.AIM_ASSIST).size(), 2)
	view.change(1)
	assert_false(GameOptions.is_gamepad_aim_assist_enabled(), "→ wraps from on to off")
	var rb := InputEventJoypadButton.new()
	rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	rb.pressed = true
	assert_true(view.handle_input(rb), "RB = next tab")
	assert_eq(view.get_tab(), OptionsView.Tab.DISPLAY)
	var lb := InputEventJoypadButton.new()
	lb.button_index = JOY_BUTTON_LEFT_SHOULDER
	lb.pressed = true
	assert_true(view.handle_input(lb), "LB = previous tab")
	assert_eq(view.get_tab(), OptionsView.Tab.GENERAL)
	view.show_controls()
	assert_false(_cap_ids(view).has(InputGlyphs.PAD_STICK_RIGHT), "keyboard: the mouse aims")
	InputDevice.shared().set_kind(InputDevice.Kind.GAMEPAD)
	await wait_process_frames(1)
	if not InputGlyphs.is_touch():
		var ids := _cap_ids(view)
		assert_true(ids.has(InputGlyphs.PAD_STICK_RIGHT), "gamepad: the right stick aims")
		assert_true(ids.has(InputGlyphs.PAD_RT), "gamepad: RT attacks")
		assert_false(ids.has(InputGlyphs.MOUSE_LEFT), "no mouse buttons left")
	InputDevice.shared().set_kind(InputDevice.Kind.KEYBOARD_MOUSE)
	await wait_process_frames(1)


## Glyph ids of every KeyCap below node.
func _cap_ids(node: Node) -> Array[StringName]:
	var ids: Array[StringName] = []
	for child in node.find_children("*", "KeyCap", true, false):
		ids.append((child as KeyCap).glyph_id)
	return ids

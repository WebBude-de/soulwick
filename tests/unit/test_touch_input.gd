extends GutTest
## Touch controls (CP2, two sticks): TouchState collects both sticks and the buttons, TouchOverlay
## turns simulated InputEventScreenTouch/Drag into that state, TouchInput hands it to the player
## (aim stick = aim + auto-attack) and falls back to keyboard and mouse while no finger is in use.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const TEST_SAVE_PATH := "user://test_touch_input.cfg"
const SCREEN := Rect2(0, 0, 1280, 720)

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.load_game()


func after_each() -> void:
	for action in PlayerInput.ACTIONS:
		Input.action_release(action)


func after_all() -> void:
	await wait_seconds(0.3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func _forced_state() -> TouchState:
	var state := TouchState.new()
	state.forced = true
	state.mark_polled(false, true)
	return state


func _overlay(state: TouchState) -> TouchOverlay:
	var overlay: TouchOverlay = add_child_autofree(TouchOverlay.new(state))
	overlay.layout(SCREEN)
	overlay.set_shown(true)
	return overlay


func _touch(overlay: TouchOverlay, index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	overlay._input(event)


func _drag(overlay: TouchOverlay, index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	overlay._input(event)


func _button_center(overlay: TouchOverlay, action: StringName) -> Vector2:
	for button in overlay.buttons:
		if button.action == action:
			return button.center
	fail_test("no button for %s" % action)
	return Vector2(-1000, -1000)


# --- TouchState ---

func test_state_press_counts_once_as_went_down_and_holds_until_release() -> void:
	var state := TouchState.new()
	state.press(PlayerInput.ATTACK)
	state.press(PlayerInput.ATTACK)
	assert_true(state.went_down(PlayerInput.ATTACK))
	state.consume_presses()
	assert_false(state.went_down(PlayerInput.ATTACK), "only once")
	assert_true(state.is_held(PlayerInput.ATTACK))
	state.release(PlayerInput.ATTACK)
	assert_false(state.is_held(PlayerInput.ATTACK))


func test_state_wants_overlay_only_when_active_and_polled_with_a_player_that_can_act() -> void:
	var state := TouchState.new()
	state.mark_polled(false, true)
	assert_false(state.wants_overlay(), "no finger yet, not forced")
	state.touched = true
	assert_true(state.wants_overlay())
	state.mark_polled(false, false)
	assert_false(state.wants_overlay(), "player locked (menu) or down")


# --- TouchInput ---

func test_touch_input_reads_stick_and_buttons_with_one_frame_just_pressed() -> void:
	var state := _forced_state()
	var input := TouchInput.new(state)
	state.move = Vector2(0.0, -1.0)
	state.press(PlayerInput.DASH)
	state.release(PlayerInput.DASH)
	input.poll(null)
	assert_eq(input.move, Vector2(0.0, -1.0))
	assert_true(input.is_just_pressed(PlayerInput.DASH), "a tap shorter than a frame is not lost")
	assert_true(input.is_pressed(PlayerInput.DASH))
	input.poll(null)
	assert_false(input.is_pressed(PlayerInput.DASH))
	assert_eq(input.get_aim_direction(Vector2.ZERO, Vector2.RIGHT), Vector2.UP, "aim follows the stick")


func test_touch_input_falls_back_to_keyboard_while_no_finger_is_used() -> void:
	var state := TouchState.new()
	var input := TouchInput.new(state)
	assert_true(input.is_local())
	Input.action_press(PlayerInput.ATTACK)
	input.poll(null)
	assert_true(input.is_pressed(PlayerInput.ATTACK), "keyboard/mouse path like LocalKeyboardMouseInput")
	assert_eq(input.aim_direction, Vector2.ZERO, "mouse aim, no touch aim")


func test_adapt_keeps_remote_and_desktop_inputs() -> void:
	assert_true(TouchInput.adapt(RemoteInput.new()) is RemoteInput)
	var shared := TouchState.shared()
	var old_forced := shared.forced
	shared.forced = false
	if not DisplayServer.is_touchscreen_available():
		var local := TouchInput.adapt(LocalKeyboardMouseInput.new())
		assert_false(local is TouchInput, "desktop without a touch screen stays unchanged")
	shared.forced = true
	assert_true(TouchInput.adapt(LocalKeyboardMouseInput.new()) is TouchInput)
	assert_true(TouchInput.adapt(RemoteInput.new()) is RemoteInput, "remote players never get touch")
	shared.forced = old_forced


func test_aim_prefers_aim_stick_then_move_stick_then_last_direction() -> void:
	assert_eq(TouchInput.choose_aim(Vector2(0, 0.5), Vector2.LEFT, Vector2.RIGHT), Vector2.DOWN, "aim stick wins")
	assert_eq(TouchInput.choose_aim(Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT), Vector2.LEFT, "no aim stick: walking direction")
	assert_eq(TouchInput.choose_aim(Vector2.ZERO, Vector2(0.1, 0), Vector2.UP), Vector2.UP, "resting thumb keeps aim")


func test_auto_attack_needs_deflection_and_pauses_for_the_special() -> void:
	assert_false(TouchInput.wants_auto_attack(Vector2.ZERO, false))
	assert_false(TouchInput.wants_auto_attack(Vector2(TouchInput.AUTO_ATTACK_THRESHOLD * 0.5, 0), false), "light touch only aims")
	assert_true(TouchInput.wants_auto_attack(Vector2(TouchInput.AUTO_ATTACK_THRESHOLD, 0), false))
	assert_false(TouchInput.wants_auto_attack(Vector2.RIGHT, true), "special held: no new swing")


func test_aim_stick_aims_and_attacks_until_released() -> void:
	var state := _forced_state()
	var input := TouchInput.new(state)
	state.move = Vector2.RIGHT
	state.aim = Vector2(0.0, 0.8)
	input.poll(null)
	assert_eq(input.get_aim_direction(Vector2.ZERO, Vector2.RIGHT), Vector2.DOWN, "looks where the aim stick points")
	assert_true(input.is_pressed(PlayerInput.ATTACK), "attacks on its own")
	assert_true(input.is_just_pressed(PlayerInput.ATTACK))
	input.poll(null)
	assert_true(input.is_pressed(PlayerInput.ATTACK), "keeps attacking while deflected")
	assert_false(input.is_just_pressed(PlayerInput.ATTACK))
	state.aim = Vector2.ZERO
	input.poll(null)
	assert_false(input.is_pressed(PlayerInput.ATTACK), "released: no auto-attack")
	assert_eq(input.get_aim_direction(Vector2.ZERO, Vector2.UP), Vector2.RIGHT, "released: walking direction again")
	state.move = Vector2.ZERO
	input.poll(null)
	assert_eq(input.get_aim_direction(Vector2.ZERO, Vector2.UP), Vector2.RIGHT, "standing: keeps the last direction")


func test_special_goes_in_the_aim_direction_and_pauses_the_auto_attack() -> void:
	var state := _forced_state()
	var input := TouchInput.new(state)
	state.aim = Vector2.LEFT
	input.poll(null)
	assert_true(input.is_pressed(PlayerInput.ATTACK))
	state.press(PlayerInput.SPECIAL)
	input.poll(null)
	assert_true(input.is_pressed(PlayerInput.SPECIAL))
	assert_false(input.is_pressed(PlayerInput.ATTACK), "no new swing while the special waits")
	assert_eq(input.get_aim_direction(Vector2.ZERO, Vector2.RIGHT), Vector2.LEFT, "special aims with the aim stick")
	for i in TouchInput.SPECIAL_BUFFER_FRAMES + 5:
		input.poll(null)
	assert_true(input.is_pressed(PlayerInput.SPECIAL), "held: stays requested (charging, cooldown)")
	state.release(PlayerInput.SPECIAL)
	input.poll(null)
	assert_false(input.is_pressed(PlayerInput.SPECIAL))
	assert_true(input.is_pressed(PlayerInput.ATTACK), "auto-attack resumes")


func test_quick_special_tap_is_buffered() -> void:
	var state := _forced_state()
	var input := TouchInput.new(state)
	state.press(PlayerInput.SPECIAL)
	state.release(PlayerInput.SPECIAL)
	input.poll(null)
	assert_true(input.is_just_pressed(PlayerInput.SPECIAL))
	for i in TouchInput.SPECIAL_BUFFER_FRAMES - 1:
		input.poll(null)
	assert_true(input.is_pressed(PlayerInput.SPECIAL), "a tap during a swing is not lost")
	input.poll(null)
	assert_false(input.is_pressed(PlayerInput.SPECIAL), "buffer runs out")


# --- TouchOverlay (simulated screen touches) ---

func test_stick_drag_moves_and_release_stops() -> void:
	var state := _forced_state()
	var overlay := _overlay(state)
	_touch(overlay, 0, Vector2(220, 520), true)
	assert_true(overlay.is_stick_held())
	_drag(overlay, 0, Vector2(220 + TouchOverlay.STICK_RADIUS, 520))
	assert_almost_eq(state.move, Vector2.RIGHT, Vector2(0.01, 0.01))
	_drag(overlay, 0, Vector2(225, 520))
	assert_eq(state.move, Vector2.ZERO, "inside the dead zone")
	_drag(overlay, 0, Vector2(225, 520 - 3.0 * TouchOverlay.STICK_RADIUS))
	assert_almost_eq(state.move.length(), 1.0, 0.01, "the floating stick follows the thumb")
	_touch(overlay, 0, Vector2(225, 300), false)
	assert_false(overlay.is_stick_held())
	assert_eq(state.move, Vector2.ZERO)


func test_buttons_press_their_actions_with_multi_touch() -> void:
	var state := _forced_state()
	var overlay := _overlay(state)
	_touch(overlay, 0, Vector2(200, 500), true)
	_drag(overlay, 0, Vector2(200, 500 - TouchOverlay.STICK_RADIUS))
	_touch(overlay, 1, _button_center(overlay, PlayerInput.DASH), true)
	_touch(overlay, 2, _button_center(overlay, PlayerInput.INTERACT), true)
	assert_true(state.is_held(PlayerInput.DASH))
	assert_true(state.is_held(PlayerInput.INTERACT))
	assert_almost_eq(state.move, Vector2.UP, Vector2(0.01, 0.01), "stick keeps working while buttons are held")
	_touch(overlay, 1, _button_center(overlay, PlayerInput.DASH), false)
	assert_false(state.is_held(PlayerInput.DASH))
	assert_true(state.is_held(PlayerInput.INTERACT))
	for action in [PlayerInput.SPECIAL, PlayerInput.SWITCH_WEAPON]:
		_touch(overlay, 3, _button_center(overlay, action), true)
		assert_true(state.went_down(action), str(action))
		_touch(overlay, 3, _button_center(overlay, action), false)


func test_aim_stick_on_its_ring_aims_at_once_and_floats_elsewhere() -> void:
	var state := _forced_state()
	var overlay := _overlay(state)
	var rest := overlay.get_aim_rest()
	_touch(overlay, 3, rest + Vector2(0, -TouchOverlay.STICK_RADIUS), true)
	assert_true(overlay.is_aim_held())
	assert_almost_eq(state.aim, Vector2.UP, Vector2(0.01, 0.01), "a touch on the ring's edge aims at once")
	_drag(overlay, 3, rest + Vector2(5, 0))
	assert_eq(state.aim, Vector2.ZERO, "back in the dead zone")
	_drag(overlay, 3, rest + Vector2(-TouchOverlay.STICK_RADIUS, 0))
	assert_almost_eq(state.aim, Vector2.LEFT, Vector2(0.01, 0.01))
	_touch(overlay, 3, rest, false)
	assert_false(overlay.is_aim_held())
	assert_eq(state.aim, Vector2.ZERO, "released: no aim")
	# Elsewhere in the right half (not on a button): the stick starts under the thumb.
	var free := Vector2(SCREEN.size.x * 0.62, SCREEN.size.y * 0.75)
	assert_eq(overlay.button_at(free), {}, "test point is free")
	_touch(overlay, 4, free, true)
	assert_true(overlay.is_aim_held())
	assert_eq(state.aim, Vector2.ZERO, "floating: no deflection on touch-down")
	_drag(overlay, 4, free + Vector2(0, TouchOverlay.STICK_RADIUS))
	assert_almost_eq(state.aim, Vector2.DOWN, Vector2(0.01, 0.01))
	_touch(overlay, 4, free, false)


func test_both_sticks_work_at_the_same_time() -> void:
	var state := _forced_state()
	var overlay := _overlay(state)
	_touch(overlay, 0, Vector2(200, 500), true)
	_drag(overlay, 0, Vector2(200 + TouchOverlay.STICK_RADIUS, 500))
	var rest := overlay.get_aim_rest()
	_touch(overlay, 1, rest, true)
	_drag(overlay, 1, rest + Vector2(0, -TouchOverlay.STICK_RADIUS))
	assert_almost_eq(state.move, Vector2.RIGHT, Vector2(0.01, 0.01))
	assert_almost_eq(state.aim, Vector2.UP, Vector2(0.01, 0.01))
	_touch(overlay, 2, _button_center(overlay, PlayerInput.SPECIAL), true)
	assert_true(state.is_held(PlayerInput.SPECIAL), "special with a third finger")
	_touch(overlay, 0, Vector2(200, 500), false)
	assert_eq(state.move, Vector2.ZERO)
	assert_almost_eq(state.aim, Vector2.UP, Vector2(0.01, 0.01), "aim stays while the left thumb lets go")
	overlay.set_shown(false)
	assert_eq(state.aim, Vector2.ZERO, "hidden overlay releases the aim stick")
	assert_false(state.is_held(PlayerInput.SPECIAL))


func test_layout_special_left_other_buttons_right_nothing_overlaps() -> void:
	var state := _forced_state()
	var overlay := _overlay(state)
	for side in [false, true]:
		state.side_view = side
		overlay.layout(SCREEN)
		var circles: Array[Dictionary] = [
			{"name": "move stick", "center": overlay.get_stick_rest(), "radius": TouchOverlay.STICK_RADIUS},
			{"name": "aim stick", "center": overlay.get_aim_rest(), "radius": TouchOverlay.STICK_RADIUS},
		]
		var inner := SCREEN.grow(-2.0)
		for button in overlay.buttons:
			var center: Vector2 = button.center
			var radius: float = button.radius
			var corner := Vector2(radius, radius)
			assert_true(inner.has_point(center + corner) and inner.has_point(center - corner), "%s on screen" % button.action)
			if button.event:
				continue
			if button.action == PlayerInput.SPECIAL:
				assert_lt(center.x, SCREEN.size.x * TouchOverlay.STICK_ZONE_WIDTH, "special on the left, next to the move stick")
			else:
				assert_gt(center.x, SCREEN.size.x * 0.5, "%s on the right" % button.action)
			circles.append({"name": str(button.action), "center": center, "radius": radius})
		assert_false(overlay.buttons.any(func(b: Dictionary) -> bool: return b.action == PlayerInput.ATTACK), "the aim stick attacks, no attack button")
		for i in circles.size():
			for j in range(i + 1, circles.size()):
				var first: Dictionary = circles[i]
				var second: Dictionary = circles[j]
				var gap := (first.center as Vector2).distance_to(second.center) - float(first.radius) - float(second.radius)
				assert_gt(gap, 4.0, "%s and %s do not overlap (side view %s)" % [first.name, second.name, side])


func test_side_view_shows_jump_and_side_dash() -> void:
	var state := _forced_state()
	var overlay := _overlay(state)
	assert_eq(overlay.button_at(Vector2(-500, -500)), {})
	var actions: Array = overlay.buttons.map(func(button: Dictionary) -> StringName: return button.action)
	assert_false(actions.has(PlayerInput.SIDE_DASH))
	assert_true(actions.has(TouchOverlay.PAUSE), "pause button on top")
	state.side_view = true
	overlay.layout(SCREEN)
	actions = overlay.buttons.map(func(button: Dictionary) -> StringName: return button.action)
	assert_true(actions.has(PlayerInput.SIDE_DASH))
	assert_true(actions.has(PlayerInput.DASH), "dash is the jump in a side view")


func test_hidden_overlay_ignores_touches_and_releases_held_buttons() -> void:
	var state := _forced_state()
	var overlay := _overlay(state)
	_touch(overlay, 1, _button_center(overlay, PlayerInput.INTERACT), true)
	assert_true(state.is_held(PlayerInput.INTERACT))
	overlay.set_shown(false)
	assert_false(state.is_held(PlayerInput.INTERACT), "nothing stays stuck behind a menu")
	_touch(overlay, 1, _button_center(overlay, PlayerInput.INTERACT), true)
	assert_false(state.is_held(PlayerInput.INTERACT), "taps go to the menu")
	_touch(overlay, 2, overlay.get_aim_rest(), true)
	assert_false(overlay.is_aim_held(), "the aim stick ignores taps behind a menu too")


func test_keyboard_switches_back_unless_forced() -> void:
	var state := TouchState.new()
	var overlay: TouchOverlay = add_child_autofree(TouchOverlay.new(state))
	_touch(overlay, 0, Vector2(10, 10), true)
	assert_true(state.touched, "the first touch turns the controls on")
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_W
	overlay._input(key)
	assert_false(state.touched, "keyboard turns them off again")


func test_screen_touch_through_the_engine_reaches_the_overlay() -> void:
	var state := _forced_state()
	var overlay := _overlay(state)
	var event := InputEventScreenTouch.new()
	event.index = 4
	# The engine gets window pixels and hands viewport coordinates to the overlay.
	event.position = overlay.get_viewport().get_final_transform() * _button_center(overlay, PlayerInput.SPECIAL)
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await wait_physics_frames(2)
	assert_true(state.is_held(PlayerInput.SPECIAL))
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await wait_physics_frames(2)
	assert_false(state.is_held(PlayerInput.SPECIAL))


# --- Player on touch ---

func test_player_walks_with_the_stick_and_attacks_with_the_aim_stick() -> void:
	var state := _forced_state()
	var player: Player = PLAYER_SCENE.instantiate()
	player.input = TouchInput.new(state)
	add_child_autofree(player)
	assert_true(player.input is TouchInput, "the setter keeps a TouchInput")
	await wait_physics_frames(2)
	var start := player.global_position
	state.move = Vector2.RIGHT
	await wait_physics_frames(10)
	assert_gt(player.global_position.x, start.x + 5.0, "moved right")
	assert_almost_eq(player.get_aim_direction(), Vector2.RIGHT, Vector2(0.01, 0.01), "aims where it walks")
	assert_false(player.input.is_pressed(PlayerInput.ATTACK), "walking alone does not attack")
	var attacks := [0]
	player.weapon_controller.attack_performed.connect(func(_weapon: WeaponData) -> void: attacks[0] += 1)
	state.aim = Vector2.LEFT
	await wait_physics_frames(6)
	assert_almost_eq(player.get_aim_direction(), Vector2.LEFT, Vector2(0.01, 0.01), "looks along the aim stick while walking right")
	assert_almost_eq(player.weapon_controller.aim_direction, Vector2.LEFT, Vector2(0.01, 0.01), "the weapon aims there too")
	assert_gt(attacks[0], 0, "the aim stick attacks on its own")
	state.release_all()
	await wait_physics_frames(2)
	assert_false(player.input.is_pressed(PlayerInput.ATTACK))


# --- Touch art (SPRITES_V10 §1) ---

func test_aim_stick_base_falls_back_to_the_move_stick_base() -> void:
	TouchArt.clear_cache()
	var own := TouchArt.texture(TouchArt.STICK_AIM_BASE)
	assert_eq(TouchArt.aim_base(), own if own != null else TouchArt.texture(TouchArt.STICK_BASE))


func test_touch_art_returns_null_for_missing_files_and_falls_back_for_attack() -> void:
	TouchArt.clear_cache()
	assert_null(TouchArt.texture("does_not_exist_v10"), "missing file: the overlay draws")
	var expected := TouchArt.texture("icon_attack_sword")
	if expected == null:
		expected = load("res://art/ui/icon_sword.png") if ResourceLoader.exists("res://art/ui/icon_sword.png") else TouchArt.icon(TouchArt.ICON_ATTACK)
	assert_eq(TouchArt.attack_icon(WeaponData.WeaponType.SWORD), expected, "own icon, then the HUD item icon")
	assert_eq(TouchArt.attack_icon(-1), TouchArt.icon(TouchArt.ICON_ATTACK), "no weapon: neutral attack icon")


func test_touch_art_sizes_fit_the_touch_areas() -> void:
	assert_almost_eq(TouchArt.frame_screen_size(TouchArt.Size.NORMAL) * 0.5, TouchOverlay.BUTTON_RADIUS, 4.0)
	assert_almost_eq(TouchArt.frame_screen_size(TouchArt.Size.SMALL) * 0.5, TouchOverlay.SMALL_RADIUS, 4.0)
	assert_almost_eq(float(TouchArt.STICK_BASE_ART_SIZE * TouchArt.PIXEL) * 0.5, TouchOverlay.STICK_RADIUS, 4.0)
	assert_eq(TouchArt.cooldown_frame(1.0), 0, "just used")
	assert_eq(TouchArt.cooldown_frame(0.01), TouchArt.COOLDOWN_FRAMES - 1, "almost ready")


func test_every_button_has_an_icon_and_a_size() -> void:
	var state := _forced_state()
	var overlay := _overlay(state)
	for side in [false, true]:
		state.side_view = side
		overlay.layout(SCREEN)
		for button in overlay.buttons:
			assert_true(TouchArt.ICONS.has(button.icon), "%s has a known icon" % button.action)
			assert_true(TouchArt.FRAME_NAMES.has(button.size))
	var dash: Dictionary = overlay.buttons.filter(func(b: Dictionary) -> bool: return b.action == PlayerInput.DASH)[0]
	assert_eq(dash.icon, TouchArt.ICON_JUMP, "the dash button jumps in a side view")


func test_overlay_draws_with_cooldowns_and_pressed_buttons() -> void:
	var state := _forced_state()
	var overlay := _overlay(state)
	state.cooldowns[PlayerInput.DASH] = 0.6
	state.cooldowns[PlayerInput.SPECIAL] = 1.0
	state.weapon_type = WeaponData.WeaponType.BOW
	_touch(overlay, 1, _button_center(overlay, PlayerInput.INTERACT), true)
	_touch(overlay, 2, overlay.get_aim_rest() + Vector2(TouchOverlay.STICK_RADIUS, 0), true)
	overlay._view.queue_redraw()
	await wait_process_frames(2)
	assert_true(state.is_held(PlayerInput.INTERACT), "drawing every state does not break input")
	assert_true(overlay.is_aim_held())
	_touch(overlay, 1, _button_center(overlay, PlayerInput.INTERACT), false)
	_touch(overlay, 2, overlay.get_aim_rest(), false)


func test_player_reports_weapon_and_cooldowns_to_the_touch_state() -> void:
	var state := _forced_state()
	var player: Player = PLAYER_SCENE.instantiate()
	player.input = TouchInput.new(state)
	add_child_autofree(player)
	await wait_physics_frames(2)
	assert_eq(state.cooldown_share(PlayerInput.DASH), 0.0, "ready")
	var weapon := player.weapon_controller.get_active_weapon()
	assert_eq(state.weapon_type, weapon.weapon_type if weapon != null else -1)
	assert_true(player.try_dash(Vector2.RIGHT))
	TouchInput.read_button_state(player, state)
	assert_gt(state.cooldown_share(PlayerInput.DASH), 0.0, "cooling down after a dash")

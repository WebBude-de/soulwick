extends GutTest
## Touch options and pixel-art look (Projektmitglied 17.10.2026): fixed sticks (default) or floating
## ones, swapped sides, three sizes, opacity, touch aim assist (GameOptions, settings.cfg), the
## "Touch" tab of the OptionsView, the drawn pixel-art placeholders (TouchPixelArt via TouchArt) and
## the safe area. Runs in a test folder (SaveManager.set_storage_root), never on the real settings.

const ROOT := "user://test_touch_options"
const SCREEN := Rect2(0, 0, 1280, 720)
## Phone formats with aspect "expand": 19.5:9 and 20:9 widen the viewport, 4:3 makes it taller.
const SCREENS: Array[Rect2] = [
	Rect2(0, 0, 1280, 720), Rect2(0, 0, 1560, 720), Rect2(0, 0, 1600, 720), Rect2(0, 0, 1280, 960),
]

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
	GameOptions.set_language(&"de")


func after_all() -> void:
	_wipe()
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()
	TranslationServer.set_locale(_old_locale)


func _wipe() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	for dir_path in [root.path_join("saves"), root]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			DirAccess.remove_absolute(dir_path.path_join(file))
	DirAccess.make_dir_recursive_absolute(root)


func _state() -> TouchState:
	var state := TouchState.new()
	state.forced = true
	state.mark_polled(false, true)
	return state


func _overlay(state: TouchState, floating := false, swap := false, step := 1) -> TouchOverlay:
	var overlay := TouchOverlay.new(state)
	overlay.follow_options = false
	overlay.set_options(swap, floating, step, 1.0)
	add_child_autofree(overlay)
	overlay.layout(SCREEN)
	overlay.set_shown(true)
	return overlay


func _button(overlay: TouchOverlay, action: StringName) -> Dictionary:
	for button in overlay.buttons:
		if button.action == action:
			return button
	fail_test("no button for %s" % action)
	return {}


# --- Options ---

func test_defaults_are_fixed_sticks_medium_full_opacity_and_aim_assist_on() -> void:
	SaveManager.load_settings()
	assert_false(GameOptions.is_touch_swap_sides())
	assert_eq(GameOptions.get_touch_stick_mode(), GameOptions.TOUCH_FIXED, "fixed sticks by default")
	assert_false(GameOptions.are_touch_sticks_floating())
	assert_eq(GameOptions.get_touch_size(), 1)
	assert_eq(GameOptions.get_touch_opacity(), 1.0)
	assert_true(GameOptions.is_touch_aim_assist_enabled())
	assert_true(TouchInput.aim_assist_enabled())


func test_options_are_stored_clamped_and_reset() -> void:
	GameOptions.set_touch_swap_sides(true)
	GameOptions.set_touch_stick_mode(GameOptions.TOUCH_FLOATING)
	GameOptions.set_touch_size(7)
	GameOptions.set_touch_opacity(0.1)
	GameOptions.set_touch_aim_assist(false)
	SaveManager.load_settings()
	assert_true(GameOptions.is_touch_swap_sides())
	assert_true(GameOptions.are_touch_sticks_floating())
	assert_eq(GameOptions.get_touch_size(), 2, "clamped to large")
	assert_eq(GameOptions.get_touch_opacity(), 0.5, "never invisible")
	assert_false(TouchInput.aim_assist_enabled())
	GameOptions.set_touch_stick_mode(&"wobbly")
	assert_eq(GameOptions.get_touch_stick_mode(), GameOptions.TOUCH_FIXED, "unknown mode = fixed")
	GameOptions.reset_to_defaults()
	assert_false(GameOptions.is_touch_swap_sides())
	assert_false(GameOptions.are_touch_sticks_floating())
	assert_eq(GameOptions.get_touch_size(), 1)
	assert_true(GameOptions.is_touch_aim_assist_enabled())


func test_overlay_follows_the_stored_options_at_once() -> void:
	var state := _state()
	var overlay := TouchOverlay.new(state)
	add_child_autofree(overlay)
	await wait_process_frames(1)
	var left_rest := overlay.get_stick_rest()
	GameOptions.set_touch_swap_sides(true)
	GameOptions.set_touch_opacity(0.75)
	GameOptions.set_touch_size(2)
	await wait_process_frames(2)
	assert_true(overlay.swap_sides)
	assert_gt(overlay.get_stick_rest().x, left_rest.x, "the move stick went to the right")
	assert_almost_eq(overlay._view.modulate.a, 0.75, 0.001, "opacity of the whole overlay")
	assert_eq(overlay.get_pixel(), TouchArt.PIXEL + 1, "large: one screen pixel more per art pixel")


# --- Fixed and floating sticks ---

func test_fixed_move_stick_stays_put_and_only_takes_touches_near_its_ring() -> void:
	var state := _state()
	var overlay := _overlay(state)
	var rest := overlay.get_stick_rest()
	var radius := overlay.get_stick_radius()
	var far := rest + Vector2(0, -radius * 2.2)
	assert_eq(overlay.button_at(far), {}, "test point is free")
	assert_false(overlay.handle_touch(0, far, true), "far from the ring: not taken")
	assert_false(overlay.is_stick_held())
	assert_true(overlay.handle_touch(0, rest + Vector2(radius, 0), true), "on the ring: taken")
	assert_almost_eq(state.move, Vector2.RIGHT, Vector2(0.01, 0.01), "the edge counts at once")
	overlay.handle_drag(0, rest + Vector2(-3.0 * radius, 0))
	assert_almost_eq(state.move, Vector2.LEFT, Vector2(0.01, 0.01), "full deflection outside the ring")
	assert_eq(overlay.get_stick_origin(), rest, "the stick does not wander")
	overlay.handle_drag(0, rest + Vector2(2, 1))
	assert_eq(state.move, Vector2.ZERO, "back in the dead zone")
	overlay.handle_touch(0, rest, false)
	assert_false(overlay.is_stick_held())


func test_fixed_aim_stick_measures_from_its_rest() -> void:
	var state := _state()
	var overlay := _overlay(state)
	var rest := overlay.get_aim_rest()
	var radius := overlay.get_stick_radius()
	overlay.handle_touch(1, rest + Vector2(0, radius * 0.5), true)
	assert_true(overlay.is_aim_held())
	assert_gt(state.aim.y, 0.0, "a touch inside the ring already aims")
	overlay.handle_drag(1, rest + Vector2(0, -4.0 * radius))
	assert_almost_eq(state.aim, Vector2.UP, Vector2(0.01, 0.01))
	assert_eq(overlay.get_aim_origin(), rest)
	overlay.handle_touch(1, rest, false)


func test_floating_option_keeps_the_wandering_sticks() -> void:
	var state := _state()
	var overlay := _overlay(state, true)
	var rest := overlay.get_stick_rest()
	var start := rest + Vector2(40, -200)
	assert_eq(overlay.button_at(start), {}, "test point is free")
	assert_true(overlay.handle_touch(0, start, true), "anywhere in the zone")
	assert_eq(state.move, Vector2.ZERO, "starts under the thumb")
	overlay.handle_drag(0, start + Vector2(3.0 * overlay.get_stick_radius(), 0))
	assert_almost_eq(state.move, Vector2.RIGHT, Vector2(0.01, 0.01))
	assert_ne(overlay.get_stick_origin(), rest, "it follows the thumb")
	overlay.handle_touch(0, start, false)
	assert_eq(overlay.get_stick_origin(), rest, "back home on release")


# --- Layout: sides, sizes, formats ---

func test_swapped_sides_mirror_the_layout() -> void:
	var state := _state()
	var overlay := _overlay(state, false, true)
	var middle := SCREEN.get_center().x
	assert_gt(overlay.get_stick_rest().x, middle, "move stick on the right")
	assert_lt(overlay.get_aim_rest().x, middle, "aim stick on the left")
	assert_gt(_button(overlay, PlayerInput.SPECIAL).center.x, middle, "special next to the move stick")
	for action in [PlayerInput.DASH, PlayerInput.INTERACT, PlayerInput.SWITCH_WEAPON]:
		assert_lt(_button(overlay, action).center.x, middle, "%s next to the aim stick" % action)
	var rest := overlay.get_stick_rest()
	overlay.handle_touch(0, rest + Vector2(0, -overlay.get_stick_radius()), true)
	assert_almost_eq(state.move, Vector2.UP, Vector2(0.01, 0.01), "the right stick moves")
	overlay.handle_touch(0, rest, false)
	var free := Vector2(SCREEN.size.x * 0.2, SCREEN.size.y * 0.75)
	var floating := _overlay(_state(), true, true)
	assert_eq(floating.button_at(free), {}, "test point is free")
	assert_true(floating.handle_touch(3, free, true))
	assert_true(floating.is_aim_held(), "floating: the left zone starts the aim stick")


func test_every_size_side_and_format_fits_without_overlaps() -> void:
	var state := _state()
	var overlay := _overlay(state)
	for screen in SCREENS:
		for step in 3:
			for swap in [false, true]:
				overlay.set_options(swap, false, step, 1.0)
				for side in [false, true]:
					state.side_view = side
					overlay.layout(screen)
					_assert_layout(overlay, screen, "%s size %d swap %s side %s" % [screen.size, step, swap, side])
	state.side_view = false


func _assert_layout(overlay: TouchOverlay, screen: Rect2, label: String) -> void:
	var radius := overlay.get_stick_radius()
	var circles: Array[Dictionary] = [
		{"name": "move stick", "center": overlay.get_stick_rest(), "radius": radius},
		{"name": "aim stick", "center": overlay.get_aim_rest(), "radius": radius},
	]
	for button in overlay.buttons:
		circles.append({"name": str(button.action), "center": button.center, "radius": button.radius})
	var inner := screen.grow(-2.0)
	for circle in circles:
		var corner := Vector2(circle.radius, circle.radius)
		assert_true(inner.has_point(circle.center + corner) and inner.has_point(circle.center - corner),
				"%s on screen (%s)" % [circle.name, label])
	for i in circles.size():
		for j in range(i + 1, circles.size()):
			var gap := (circles[i].center as Vector2).distance_to(circles[j].center) - float(circles[i].radius) - float(circles[j].radius)
			assert_gt(gap, 4.0, "%s and %s apart (%s)" % [circles[i].name, circles[j].name, label])


func test_sizes_scale_touch_areas_and_art_together() -> void:
	var state := _state()
	var overlay := _overlay(state)
	for step in 3:
		overlay.set_options(false, false, step, 1.0)
		var pixel := overlay.get_pixel()
		assert_eq(pixel, TouchArt.PIXEL - 1 + step)
		assert_almost_eq(float(TouchArt.STICK_BASE_ART_SIZE * pixel) * 0.5, overlay.get_stick_radius() + float(pixel), float(pixel) * 2.0,
				"the drawn stick matches its reach")
		var dash := _button(overlay, PlayerInput.DASH)
		assert_almost_eq(TouchArt.frame_screen_size(TouchArt.Size.NORMAL, pixel) * 0.5, float(dash.radius), 4.0)
		assert_gt(TouchArt.icon_pixel(TouchArt.Size.SMALL, pixel), 0)


func test_safe_area_keeps_the_controls_off_a_notch() -> void:
	var visible := Rect2(0, 0, 1560, 720)
	# Window twice the viewport, camera hole on the left (100 window px = 50 viewport px).
	var to_window := Transform2D.IDENTITY.scaled(Vector2(2, 2))
	var safe := Rect2(100, 0, 3020, 1440)
	var rect := TouchOverlay.safe_rect(visible, to_window, safe)
	assert_almost_eq(rect.position.x, 50.0, 0.01)
	assert_almost_eq(rect.end.x, 1560.0, 0.01)
	assert_eq(TouchOverlay.safe_rect(visible, to_window, Rect2()), visible, "no safe area: whole view")
	assert_eq(TouchOverlay.safe_rect(visible, to_window, Rect2(0, 0, 300, 200)), visible, "nonsense ignored")


# --- Pixel art ---

func test_every_part_has_a_pixel_art_sprite_with_hard_edges() -> void:
	TouchArt.clear_cache()
	var names: Array[String] = [TouchArt.STICK_BASE, TouchArt.STICK_AIM_BASE, TouchArt.STICK_KNOB,
			TouchArt.STICK_KNOB + TouchArt.PRESSED, TouchArt.STICK_ARROWS]
	for size: TouchArt.Size in TouchArt.FRAME_NAMES:
		for state_name in ["", TouchArt.PRESSED, TouchArt.DISABLED]:
			names.append(TouchArt.FRAME_NAMES[size] + state_name)
	for id in TouchArt.ICONS:
		names.append("icon_" + String(id))
	for art_name in names:
		var sprite := TouchArt.placeholder(art_name)
		assert_not_null(sprite, art_name)
		if sprite == null:
			continue
		var image := sprite.get_image()
		var colors := {}
		for y in image.get_height():
			for x in image.get_width():
				colors[image.get_pixel(x, y).to_rgba32()] = true
		assert_lt(colors.size(), 24, "%s: a few palette colours, no smooth gradients" % art_name)
	assert_eq(TouchArt.placeholder(TouchArt.STICK_BASE).get_width(), TouchArt.STICK_BASE_ART_SIZE)
	assert_eq(TouchArt.placeholder(TouchArt.STICK_KNOB).get_width(), TouchArt.STICK_KNOB_ART_SIZE)
	assert_eq(TouchArt.placeholder("icon_dash").get_width(), TouchArt.ICON_ART_SIZE)
	for size: TouchArt.Size in TouchArt.FRAME_NAMES:
		assert_eq(TouchArt.placeholder(TouchArt.FRAME_NAMES[size]).get_width(), TouchArt.FRAME_ART_SIZES[size])
	assert_null(TouchArt.placeholder("does_not_exist_v10"))


func test_sprites_prefer_files_and_fall_back_to_the_drawing() -> void:
	TouchArt.clear_cache()
	var base := TouchArt.stick_base_sprite(false)
	var own := TouchArt.texture(TouchArt.STICK_BASE)
	assert_eq(base, own if own != null else TouchArt.placeholder(TouchArt.STICK_BASE))
	var frame := TouchArt.frame_sprite(TouchArt.Size.NORMAL, TouchArt.PRESSED)
	assert_not_null(frame.texture, "a pressed frame always exists")
	assert_not_null(TouchArt.attack_sprite(-1), "no weapon: drawn neutral attack icon")
	for share in [1.0, 0.5, 0.01]:
		for size: TouchArt.Size in TouchArt.FRAME_NAMES:
			var cooldown := TouchArt.cooldown_sprite(size, share)
			assert_not_null(cooldown.texture)
			assert_true((cooldown.region as Rect2).has_area())


func test_cooldown_frames_release_clockwise() -> void:
	var just_used := TouchArt.placeholder("touch_cooldown_32_0").get_image()
	var almost := TouchArt.placeholder("touch_cooldown_32_7").get_image()
	var dark_pixels := func(image: Image) -> int:
		var count := 0
		for y in image.get_height():
			for x in image.get_width():
				var pixel := image.get_pixel(x, y)
				if pixel.a > 0.5 and pixel.r < 0.2:
					count += 1
		return count
	assert_gt(dark_pixels.call(just_used), dark_pixels.call(almost) * 4, "just used: almost all dark")


# --- Options view ---

func test_touch_tab_only_on_touch_devices_and_rows_store_at_once() -> void:
	var view := OptionsView.new()
	add_child_autofree(view)
	var touch := TouchState.is_touch_possible()
	assert_eq(OptionsView.is_tab_available(OptionsView.Tab.TOUCH), touch)
	assert_eq(view.get_tab_buttons().size(), OptionsView.Tab.size() if touch else OptionsView.Tab.size() - 1,
			"tab button only with a touch screen")
	if not touch:
		view.show_tab(OptionsView.Tab.CONTROLS)
		view.handle_input(MenuInput.key_event(KEY_E))
		assert_eq(view.get_tab(), OptionsView.Tab.GENERAL, "E skips the hidden touch tab")
	view.select_row(OptionsView.Row.TOUCH_STICKS)
	assert_eq(view.get_tab(), OptionsView.Tab.TOUCH)
	assert_true(view.get_caption_text(OptionsView.Row.TOUCH_STICKS).begins_with("> "), "row selected")
	view.change(1)
	assert_true(GameOptions.are_touch_sticks_floating(), "→ picks Mitwandernd")
	view.select_row(OptionsView.Row.TOUCH_SWAP)
	view.change(1)
	assert_true(GameOptions.is_touch_swap_sides())
	view.select_row(OptionsView.Row.TOUCH_SIZE)
	view.change(1)
	assert_eq(GameOptions.get_touch_size(), 2)
	view.select_row(OptionsView.Row.TOUCH_OPACITY)
	view.change(-1)
	assert_eq(GameOptions.get_touch_opacity(), 0.75)
	view.select_row(OptionsView.Row.TOUCH_AIM_ASSIST)
	view.change(1)
	assert_false(GameOptions.is_touch_aim_assist_enabled())
	var buttons := view.get_choice_buttons(OptionsView.Row.TOUCH_STICKS)
	assert_eq(buttons.size(), 2)
	assert_eq(buttons[0].text, &"OPTIONS_TOUCH_FIXED")

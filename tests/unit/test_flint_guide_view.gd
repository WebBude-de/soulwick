extends GutTest
## The corner of "Flint erklärt" (WK8, SPRITES_V13 §A2/§B2) and its input: Flint's portrait at the
## bottom right with the speech bubble, "Weiter ▸" and "Überspringen"; the placeholder portrait until
## the art arrives; simulated keyboard, mouse, gamepad and touch input; portrait on a phone (Flint
## above the controller). Seen flags are swapped for a dictionary (never the real save).

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const DT := 1.0 / 60.0
const PortraitLayout := preload("res://ui/touch/portrait_layout.gd")

var _seen: Dictionary = {}
var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_flint_guide_view_save.cfg"
	GamepadInput.ensure_actions()


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	_seen.clear()


func after_each() -> void:
	PortraitLayout.set_frame(null)


func _guide(with_view := true) -> FlintGuide:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.global_position = Vector2(400, 300)
	var guide := FlintGuide.for_player(player)
	guide.set_process(false)
	guide.shows_view = with_view
	guide.has_seen = func(id: StringName) -> bool: return _seen.has(id)
	guide.mark_seen = func(id: StringName) -> void: _seen[id] = true
	return guide


func _tour(steps := 2) -> FlintExplanation:
	var list: Array[FlintGuideStep] = []
	for i in steps:
		list.append(FlintGuideStep.say(&"FLINT_ENTRANCE_2", FlintGuideStep.Mood.POINT if i == 0 else FlintGuideStep.Mood.HAPPY))
	return FlintExplanation.tour(&"flint_view_tour", list)


func _run(guide: FlintGuide, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		guide.advance(DT)
		left -= DT


func _to_talk(guide: FlintGuide) -> void:
	_run(guide, FlintGuideRules.GROW_TIME + FlintGuideRules.FLY_OUT_TIME + DT)


func _past_grace(guide: FlintGuide) -> void:
	_run(guide, FlintGuideRules.PRESS_GRACE + DT)


func _view(guide: FlintGuide) -> FlintGuideView:
	return guide.get_view() as FlintGuideView


func _key(code: Key, pressed := true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	return event


func _pad(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	return event


func _touch(at := Vector2(100, 100)) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.position = at
	event.pressed = true
	return event


func _click() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


# --- The corner ---

func test_the_corner_shows_flint_and_his_sentence_bottom_right() -> void:
	var guide := _guide()
	guide.queue(_tour())
	var view := _view(guide)
	assert_not_null(view, "the local player gets the corner")
	assert_false(view.is_shown(), "hidden while Flint is still flying")
	_to_talk(guide)
	assert_true(view.is_shown())
	assert_eq(view.get_speech().text, Loc.t(&"FLINT_ENTRANCE_2"))
	assert_eq(view.get_speech().visible_characters, guide.get_revealed(), "letter by letter")
	assert_eq(view.get_speech().max_lines_visible, FlintGuideRules.MAX_LINES)
	assert_eq(view.get_portrait().animation, &"point", "the step's mood")
	await wait_frames(3)
	var corner := view.get_corner_screen_point()
	var screen := view.get_viewport().get_visible_rect()
	assert_gt(corner.x, screen.get_center().x, "right half")
	assert_gt(corner.y, screen.get_center().y, "bottom half")
	var bubble := view.get_bubble().get_global_rect()
	assert_lt(bubble.get_center().x, corner.x, "the bubble is left of Flint")
	assert_ne(view.get_corner_world_point(), Vector2.INF, "Flint knows where to fly")


func test_next_and_skip_buttons_drive_the_guide() -> void:
	var guide := _guide()
	guide.queue(_tour())
	_to_talk(guide)
	_past_grace(guide)
	var view := _view(guide)
	view.get_next_button().pressed.emit()
	assert_eq(guide.get_revealed(), guide.get_text().length(), "Weiter shows the whole sentence")
	_past_grace(guide)
	view.get_next_button().pressed.emit()
	assert_eq(guide.step_index, 1)
	assert_eq(view.get_portrait().animation, &"happy")
	view.get_skip_button().pressed.emit()
	assert_eq(guide.phase, FlintGuide.Phase.FLY_BACK, "Überspringen ends the tour")
	assert_true(guide.was_skipped)


func test_a_tap_on_the_bubble_goes_on() -> void:
	var guide := _guide()
	guide.queue(_tour())
	_to_talk(guide)
	_past_grace(guide)
	assert_true(_view(guide).handle_bubble_input(_touch()))
	assert_eq(guide.get_revealed(), guide.get_text().length())


func test_a_one_sentence_hint_has_no_skip_button() -> void:
	var guide := _guide()
	guide.queue(FlintExplanations.named(FlintExplanations.FIRST_TALENT_POINT))
	_to_talk(guide)
	assert_false(_view(guide).get_skip_button().visible, "Weiter closes it")
	var tour_guide := _guide()
	tour_guide.queue(_tour())
	_to_talk(tour_guide)
	assert_true(_view(tour_guide).get_skip_button().visible)


func test_the_view_goes_with_the_explanation() -> void:
	var guide := _guide()
	guide.queue(_tour(1))
	var view := _view(guide)
	_to_talk(guide)
	guide.skip()
	_run(guide, FlintGuideRules.FLY_BACK_TIME + DT)
	assert_null(guide.get_view())
	assert_true(view.is_queued_for_deletion())


# --- Input of every device ---

func test_keyboard_e_space_and_enter_go_on() -> void:
	for code: Key in [KEY_E, KEY_SPACE, KEY_ENTER]:
		var guide := _guide(false)
		guide.queue(_tour())
		_to_talk(guide)
		_past_grace(guide)
		assert_true(guide.handle_input(_key(code)), "key %s is used" % code)
		assert_eq(guide.get_revealed(), guide.get_text().length(), "key %s goes on" % code)
		guide.handle_input(_key(code, false))


func test_holding_a_key_skips_everything() -> void:
	var guide := _guide(false)
	var progress: Array = []
	guide.hold_progress.connect(func(ratio: float) -> void: progress.append(ratio))
	guide.queue(_tour())
	_to_talk(guide)
	guide.handle_input(_key(KEY_E))
	_run(guide, FlintGuideRules.HOLD_TO_SKIP_TIME + 2.0 * DT)
	assert_true(guide.was_skipped)
	assert_eq(guide.phase, FlintGuide.Phase.FLY_BACK)
	assert_gt(progress.max(), 0.5, "the hold bar filled")


func test_letting_go_early_does_not_skip() -> void:
	var guide := _guide(false)
	guide.queue(_tour())
	_to_talk(guide)
	guide.handle_input(_key(KEY_E))
	_run(guide, FlintGuideRules.HOLD_TO_SKIP_TIME * 0.5)
	assert_true(guide.handle_input(_key(KEY_E, false)))
	_run(guide, FlintGuideRules.HOLD_TO_SKIP_TIME)
	assert_eq(guide.phase, FlintGuide.Phase.TALK)


func test_a_mouse_click_goes_on() -> void:
	var guide := _guide(false)
	guide.queue(_tour())
	_to_talk(guide)
	_past_grace(guide)
	assert_true(guide.handle_input(_click()))
	assert_eq(guide.get_revealed(), guide.get_text().length())


func test_gamepad_a_and_x_go_on_and_b_skips() -> void:
	for button: JoyButton in [JOY_BUTTON_A, JOY_BUTTON_X]:
		var guide := _guide(false)
		guide.queue(_tour())
		_to_talk(guide)
		_past_grace(guide)
		assert_true(guide.handle_input(_pad(button)), "pad button %d is used" % button)
		assert_eq(guide.get_revealed(), guide.get_text().length(), "pad button %d goes on" % button)
	var skipping := _guide(false)
	skipping.queue(_tour())
	_to_talk(skipping)
	assert_true(skipping.handle_input(_pad(JOY_BUTTON_B)))
	assert_true(skipping.was_skipped, "B skips")


func test_a_tap_anywhere_goes_on() -> void:
	var guide := _guide(false)
	guide.queue(_tour())
	_to_talk(guide)
	_past_grace(guide)
	assert_true(guide.handle_input(_touch()))
	assert_eq(guide.get_revealed(), guide.get_text().length())


func test_escape_stays_the_pause_menu() -> void:
	var guide := _guide(false)
	guide.queue(_tour())
	_to_talk(guide)
	assert_false(guide.handle_input(_key(KEY_ESCAPE)), "Esc is not taken from the pause menu")
	assert_eq(guide.phase, FlintGuide.Phase.TALK)


# --- Portrait on a phone ---

func test_on_an_upright_phone_flint_sits_above_the_controller() -> void:
	PortraitLayout.set_frame(PortraitLayout.compute(Vector2(1080, 2400)))
	var guide := _guide()
	guide.queue(_tour())
	_to_talk(guide)
	await wait_frames(3)
	var view := _view(guide)
	var root := view.get_child(0) as Control
	assert_eq(root.scale, Vector2.ONE * PortraitLayout.UI_ZOOM, "drawn larger like the HUD")
	var screen := view.get_viewport().get_visible_rect()
	var corner := view.get_corner_screen_point()
	assert_true(screen.has_point(corner), "on the game screen, i.e. above the controller field")
	assert_gt(corner.x, screen.get_center().x)
	assert_gt(corner.y, screen.get_center().y)


# --- Art ---

func test_placeholder_portraits_exist_for_every_mood() -> void:
	var frames := FlintPortraitArt.get_frames("res://tests/missing_flint_guide_art/")
	for animation: StringName in FlintPortraitArt.ANIMATIONS:
		var spec: Array = FlintPortraitArt.ANIMATIONS[animation]
		assert_eq(frames.get_frame_count(animation), spec[0], "%s frames" % animation)
		var texture := frames.get_frame_texture(animation, 0)
		assert_eq(Vector2i(texture.get_size()), FlintPortraitArt.FRAME_SIZE, "%s is 48x48" % animation)
	assert_ne(FlintPortraitArt.placeholder_images(&"talk", 6)[0].get_data(), FlintPortraitArt.placeholder_images(&"talk", 6)[1].get_data(),
			"the mouth moves while he talks")


func test_the_bubble_tail_is_small_mirrored_and_outside_the_text() -> void:
	if FlintPortraitArt.texture(FlintPortraitArt.BUBBLE_TAIL_FILE) == null or FlintPortraitArt.texture(FlintPortraitArt.BUBBLE_FILE) == null:
		pass_test("no delivered bubble art")
		return
	var guide := _guide()
	guide.queue(_tour())
	_to_talk(guide)
	await wait_seconds(FlintGuideView.POP_TIME + 0.1)
	var view := _view(guide)
	var tail := view.get_bubble_tail()
	assert_not_null(tail, "the delivered tail is used")
	assert_ne(tail.get_parent(), view.get_bubble(), "not stretched by the bubble's panel")
	assert_true(tail.flip_h, "mirrored: points down right to Flint")
	var expected := UiKit.art_px(FlintGuideView.TAIL_SIZE, 8.0)
	assert_almost_eq(tail.size, Vector2(expected, expected), Vector2.ONE, "8x8 times the art scale, not stretched")
	var text := view.get_speech().get_global_rect()
	assert_false(text.intersects(tail.get_global_rect()), "outside the text area")
	var bubble := view.get_bubble().get_global_rect()
	var tail_rect := tail.get_global_rect()
	assert_gt(tail_rect.end.y, bubble.end.y, "hangs below the bubble")
	assert_gt(tail_rect.get_center().x, bubble.get_center().x, "at the right corner, towards Flint")
	assert_lt(tail_rect.end.x, view.get_corner_screen_point().x, "left of Flint")


## WCAG contrast ratio of two colours.
func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _luminance(c: Color) -> float:
	var lin := func(v: float) -> float: return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * lin.call(c.r) + 0.7152 * lin.call(c.g) + 0.0722 * lin.call(c.b)


func test_text_on_the_light_bubble_is_dark_and_readable() -> void:
	# Feedback #8e2a665c: the light text on the light parchment bubble showed only its shadow.
	var bubble_texture := FlintPortraitArt.texture(FlintPortraitArt.BUBBLE_FILE)
	if bubble_texture == null:
		pass_test("no delivered bubble art: the dark placeholder panel keeps light text")
		return
	var image := bubble_texture.get_image()
	var paper := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	var guide := _guide()
	guide.queue(_tour())
	_to_talk(guide)
	var view := _view(guide)
	var speech := view.get_speech()
	var ink := speech.get_theme_color("font_color")
	assert_gte(_contrast(ink, paper), 7.0, "sentence ink on the bubble (%s on %s)" % [ink, paper])
	assert_eq(speech.get_theme_color("font_shadow_color").a, 0.0, "no dark shadow smearing the letters")
	var next := view.get_next_button().get_theme_color("font_color")
	assert_gte(_contrast(next, paper), 4.5, "\"Weiter\" readable on the bubble")


func test_portrait_flames_end_in_a_tip() -> void:
	# Feedback #587a95a9 (V13c flames ran flat out of the picture) and D-217 (website figure): every
	# frame's topmost row is the narrow tip of the flame, never a cut-off flame.
	var frames := FlintPortraitArt.get_frames()
	for animation: StringName in FlintPortraitArt.ANIMATIONS:
		for f in frames.get_frame_count(animation):
			var picture := frames.get_frame_texture(animation, f).get_image()
			var top := -1
			var opaque := 0
			for y in picture.get_height():
				for x in picture.get_width():
					if picture.get_pixel(x, y).a > 0.5:
						opaque += 1
				if opaque > 0:
					top = y
					break
			assert_gte(top, 0, "%s frame %d is not empty" % [animation, f])
			assert_lte(opaque, 4, "%s frame %d: the flame ends in a tip (%d px)" % [animation, f, opaque])

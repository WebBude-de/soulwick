extends GutTest
## Portrait mode (D-180 proposal, Projektmitglied 17.10.2026: "oben zocken und unten wie ein Gamepad"):
## the screen frame per window (PortraitLayout), the root transform that keeps the screen uniform at
## the top, MobileUi and the HUD zoom in portrait, the landscape overlay hiding, the camera zoom, and
## the controller field (PortraitPad): layout inside the field, mapping top-down / side view / menus,
## D-pad snapping, attack in the walking direction through the aim stick. Never applied to the real
## root window; uses a test storage folder, never the real save.

const PortraitLayout := preload("res://ui/touch/portrait_layout.gd")
const PortraitPad := preload("res://ui/touch/portrait_pad.gd")
const PixelArt := preload("res://ui/touch/portrait_pixel_art.gd")
const MobileUi := preload("res://ui/menus/mobile_ui.gd")
const ROOT := "user://test_portrait_layout"
## Phones held upright: iPhone 13 (19.5:9), a 20:9 Android, a 16:9 phone, a 4:3 tablet.
const PHONES: Array[Vector2] = [Vector2(1170, 2532), Vector2(1080, 2400), Vector2(1080, 1920), Vector2(1536, 2048)]

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	SaveManager.set_storage_root(ROOT)


func after_each() -> void:
	PortraitLayout.set_frame(null)
	PortraitLayout.handheld_override = -1
	MobileUi.safe_inset_override = -1.0


func after_all() -> void:
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()


# --- Frame ---

func test_only_upright_windows_turn_portrait() -> void:
	assert_true(PortraitLayout.is_upright(Vector2(1080, 2400)))
	assert_false(PortraitLayout.is_upright(Vector2(2400, 1080)), "landscape stays as it is")
	assert_false(PortraitLayout.is_upright(Vector2(1000, 1000)), "square is not upright")
	PortraitLayout.handheld_override = 0
	assert_false(PortraitLayout.is_handheld(), "a desktop never turns portrait")
	PortraitLayout.handheld_override = 1
	assert_true(PortraitLayout.is_handheld())


func test_screen_keeps_the_layout_width_and_a_sensible_height() -> void:
	for window in PHONES:
		var frame := PortraitLayout.compute(window)
		assert_eq(frame.screen_size.x, PortraitLayout.VIEW_WIDTH, "layouts keep their width (%s)" % window)
		assert_between(frame.screen_size.y, PortraitLayout.MIN_SCREEN_HEIGHT, PortraitLayout.MAX_SCREEN_HEIGHT, "16:9 to square (%s)" % window)
		assert_almost_eq(frame.scale, window.x / 1280.0, 0.0001)
		var field := frame.pad_bottom() - frame.pad_top()
		assert_true(field >= window.y * 0.45, "the controller field gets at least about half the phone (%s: %d px)" % [window, field])
	assert_eq(PortraitLayout.compute(Vector2(1080, 2400)).screen_size.y, 1280, "20:9: a square screen")
	assert_eq(PortraitLayout.compute(Vector2(1080, 1920)).screen_size.y, 1024, "16:9 phone: 4:5 screen")


func test_root_transform_makes_the_stretch_uniform_below_the_notch() -> void:
	var window := Vector2(1170, 2532)
	var frame := PortraitLayout.compute(window, Vector4(0, 132, 0, 60))
	# What Window does with aspect "ignore": the content size stretched over the whole window.
	var stretch := Transform2D.IDENTITY.scaled(Vector2(window.x / 1280.0, window.y / frame.screen_size.y))
	var final := stretch * frame.global_transform()
	assert_almost_eq(final.get_scale().x, frame.scale, 0.0001)
	assert_almost_eq(final.get_scale().y, frame.scale, 0.0001, "no vertical distortion")
	assert_almost_eq(final.origin.y, 132.0, 0.001, "the screen starts below the notch")
	assert_almost_eq((final * Vector2(0, frame.screen_size.y)).y, frame.pad_top(), 0.01, "the field starts under the screen")
	assert_almost_eq(frame.to_window(frame.to_view(Vector2(300, 2000))).y, 2000.0, 0.001)
	assert_almost_eq(frame.pad_bottom(), window.y - 60.0, 0.001, "controls stay above the gesture bar")
	assert_true(frame.field_rect().position.y >= frame.screen_size.y, "the field lies below the visible rect")


func test_zoom_factors_only_in_portrait() -> void:
	assert_eq(PortraitLayout.world_zoom(), 1.0, "landscape and desktop unchanged")
	assert_eq(PortraitLayout.ui_zoom(), 1.0)
	PortraitLayout.set_frame(PortraitLayout.compute(Vector2(1080, 2400)))
	assert_true(PortraitLayout.is_active())
	assert_eq(PortraitLayout.world_zoom(), PortraitLayout.WORLD_ZOOM)
	assert_eq(PortraitLayout.ui_zoom(), PortraitLayout.UI_ZOOM)


# --- Hooks in MobileUi, HUD root, overlay, camera ---

func test_safe_rect_is_the_screen_in_portrait() -> void:
	MobileUi.safe_inset_override = 90.0
	var viewport := get_tree().root
	var visible := viewport.get_visible_rect()
	assert_ne(MobileUi.safe_rect(viewport), visible, "landscape: the notch insets apply")
	PortraitLayout.set_frame(PortraitLayout.compute(Vector2(1080, 2400)))
	assert_eq(MobileUi.safe_rect(viewport), visible, "portrait: the screen already sits below the notch")


func test_zoomed_overlay_covers_the_screen_at_ui_zoom() -> void:
	var layer: CanvasLayer = add_child_autofree(CanvasLayer.new())
	var control := Control.new()
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(control)
	var visible := control.get_viewport().get_visible_rect()
	MobileUi.apply_safe_offsets(control, true)
	assert_eq(control.scale, Vector2.ONE, "landscape: no zoom")
	assert_almost_eq(control.size.x, visible.size.x, 0.5)
	PortraitLayout.set_frame(PortraitLayout.compute(Vector2(1080, 2400)))
	MobileUi.apply_safe_offsets(control, true)
	assert_eq(control.scale, Vector2.ONE * PortraitLayout.UI_ZOOM)
	assert_almost_eq(control.size.x * control.scale.x, visible.size.x, 0.5, "drawn over the whole screen width")
	assert_almost_eq(control.size.y * control.scale.y, visible.size.y, 0.5)
	var plain := Control.new()
	plain.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(plain)
	MobileUi.apply_safe_offsets(plain)
	assert_eq(plain.scale, Vector2.ONE, "overlays that do not opt in keep their size")


func test_landscape_overlay_hides_in_portrait() -> void:
	var state := _state()
	var overlay: TouchOverlay = add_child_autofree(TouchOverlay.new(state))
	overlay.follow_options = false
	state.mark_polled(false, true)
	overlay._process(0.016)
	assert_true(overlay.is_shown(), "landscape: sticks and buttons")
	PortraitLayout.set_frame(PortraitLayout.compute(Vector2(1080, 2400)))
	state.mark_polled(false, true)
	overlay._process(0.016)
	assert_false(overlay.is_shown(), "portrait: the controller field takes over")


func test_camera_zooms_in_portrait() -> void:
	var holder: Node2D = add_child_autofree(Node2D.new())
	var rig := CameraRig.new()
	holder.add_child(rig)
	rig._process(0.016)
	var landscape := rig.zoom.x
	PortraitLayout.set_frame(PortraitLayout.compute(Vector2(1080, 2400)))
	rig._process(0.016)
	assert_almost_eq(rig.zoom.x, landscape * PortraitLayout.WORLD_ZOOM, 0.01, "the world is drawn larger on the narrow screen")


# --- Controller field ---

func test_controls_fit_into_the_field_without_overlapping() -> void:
	for window in PHONES:
		for step in 3:
			for swap in [false, true]:
				for side in [false, true]:
					var frame := PortraitLayout.compute(window, Vector4(0, 80, 0, 40))
					var pixel := PortraitPad.art_pixel(window.x, step)
					var layout := PortraitPad.layout_controls(frame, pixel, swap, side)
					# Shapes: the D-pad cross as two bars, round buttons as circles, flat ones as rects.
					var shapes: Array[Array] = []
					var dpad: Vector2 = layout.dpad
					var long := PixelArt.DPAD_SIZE * float(pixel)
					var arm := PixelArt.DPAD_ARM * float(pixel)
					shapes.append([Rect2(dpad - Vector2(long, arm) * 0.5, Vector2(long, arm)), Rect2(dpad - Vector2(arm, long) * 0.5, Vector2(arm, long))])
					for button: Dictionary in layout.buttons:
						var size: Vector2 = button.size * float(pixel)
						if button.kind == PortraitPad.Kind.FLAT:
							shapes.append([Rect2(button.center - size * 0.5, size)])
						else:
							shapes.append([Vector3(button.center.x, button.center.y, size.x * 0.5)])
					var context := "%s step %d swap %s side %s" % [window, step, swap, side]
					var field := Rect2(0.0, frame.pad_top(), window.x, frame.pad_bottom() - frame.pad_top())
					for i in shapes.size():
						for part: Variant in shapes[i]:
							assert_true(field.encloses(_bounds(part)), "inside the field (%s, #%d)" % [context, i])
						for j in range(i + 1, shapes.size()):
							assert_false(_overlap(shapes[i], shapes[j]), "no overlap (%s, #%d/#%d)" % [context, i, j])


func test_mapping_top_down_side_view_and_menus() -> void:
	assert_eq(PortraitPad.action_of(PortraitPad.A, false), PlayerInput.ATTACK, "A attacks")
	assert_eq(PortraitPad.action_of(PortraitPad.B, false), PlayerInput.DASH, "B dashes")
	assert_eq(PortraitPad.action_of(PortraitPad.X, false), PlayerInput.SPECIAL)
	assert_eq(PortraitPad.action_of(PortraitPad.Y, false), PlayerInput.SWITCH_WEAPON)
	assert_eq(PortraitPad.action_of(PortraitPad.USE, false), PlayerInput.INTERACT)
	assert_eq(PortraitPad.action_of(PortraitPad.START, false), &"pause_menu")
	assert_eq(PortraitPad.action_of(PortraitPad.SELECT, false), &"upgrade_overview")
	assert_eq(PortraitPad.action_of(PortraitPad.A, true), PlayerInput.DASH, "side view: A jumps")
	assert_eq(PortraitPad.action_of(PortraitPad.B, true), PlayerInput.SIDE_DASH, "side view: B side dash")
	assert_eq(PortraitPad.action_of(PortraitPad.Y, true), PlayerInput.ATTACK, "side view: Y attacks")
	assert_eq(PortraitPad.action_of(PortraitPad.WEAPON, true), PlayerInput.SWITCH_WEAPON)
	assert_eq(PortraitPad.nav_action_of(PortraitPad.A), &"ui_accept", "menus: A confirms")
	assert_eq(PortraitPad.nav_action_of(PortraitPad.B), &"ui_cancel", "menus: B goes back")
	assert_eq(PortraitPad.nav_action_of_direction(PortraitPad.nav_direction(Vector2(0.3, 0.95))), &"ui_down")
	assert_eq(PortraitPad.nav_direction(Vector2.ZERO), Vector2i.ZERO)


func test_dpad_snaps_to_eight_directions_with_a_dead_zone() -> void:
	assert_eq(PortraitPad.dpad_vector(Vector2(3, 1), 100.0), Vector2.ZERO, "resting thumb")
	assert_almost_eq(PortraitPad.dpad_vector(Vector2(80, 10), 100.0), Vector2.RIGHT, Vector2.ONE * 0.001, "7° snaps to right")
	var diagonal := PortraitPad.dpad_vector(Vector2(60, 66), 100.0)
	assert_almost_eq(diagonal, Vector2(1, 1).normalized(), Vector2.ONE * 0.001, "near 45° snaps to the diagonal")
	var between := PortraitPad.dpad_vector(Vector2(80, 30), 100.0)
	assert_almost_eq(between.angle(), Vector2(80, 30).angle(), 0.001, "22° stays analog (aiming)")
	assert_almost_eq(between.length(), 1.0, 0.001, "a D-pad walks at full speed")


func test_attack_aims_where_the_player_walks() -> void:
	var state := _state()
	var pad := _pad(state)
	state.mark_polled(false, true)
	pad.refresh_mode()
	assert_true(pad.playing)
	var frame: PortraitLayout.Frame = PortraitLayout.get_frame()
	var dpad := pad.get_dpad_center()
	assert_true(pad.handle_touch(0, frame.to_view(dpad + Vector2(0, -60)), true), "the D-pad takes the thumb")
	assert_almost_eq(state.move, Vector2.UP, Vector2.ONE * 0.001, "walks up")
	assert_eq(state.aim, Vector2.ZERO, "no attack without A")
	assert_true(pad.handle_touch(1, frame.to_view(pad.button_center(PortraitPad.A)), true))
	assert_almost_eq(state.aim, Vector2.UP, Vector2.ONE * 0.001, "A: the walking direction is the aim stick (auto-attack, aim assist)")
	pad.handle_touch(0, frame.to_view(dpad), false)
	assert_eq(state.move, Vector2.ZERO)
	assert_almost_eq(state.aim, Vector2.UP, Vector2.ONE * 0.001, "standing still: keeps the last direction")
	pad.handle_touch(1, Vector2.ZERO, false)
	assert_eq(state.aim, Vector2.ZERO, "A released: no more attacks")
	pad.handle_touch(2, frame.to_view(pad.button_center(PortraitPad.B)), true)
	assert_true(state.is_held(PlayerInput.DASH), "B dashes")
	pad.handle_touch(2, Vector2.ZERO, false)
	assert_false(state.is_held(PlayerInput.DASH))


func test_thumb_slides_from_b_to_a() -> void:
	var state := _state()
	var pad := _pad(state)
	state.mark_polled(false, true)
	pad.refresh_mode()
	var frame: PortraitLayout.Frame = PortraitLayout.get_frame()
	pad.handle_touch(0, frame.to_view(pad.button_center(PortraitPad.B)), true)
	pad.handle_drag(0, frame.to_view(pad.button_center(PortraitPad.A)))
	assert_false(state.is_held(PlayerInput.DASH), "B let go")
	assert_true(pad.is_attack_held(), "A pressed by the same thumb")


func test_side_view_buttons() -> void:
	var state := _state()
	state.side_view = true
	var pad := _pad(state)
	state.mark_polled(true, true)
	pad.refresh_mode()
	var frame: PortraitLayout.Frame = PortraitLayout.get_frame()
	assert_ne(pad.button_center(PortraitPad.WEAPON), Vector2.INF, "side view: weapon switch next to Benutzen")
	pad.handle_touch(0, frame.to_view(pad.button_center(PortraitPad.A)), true)
	assert_true(state.is_held(PlayerInput.DASH), "A jumps")
	pad.handle_touch(1, frame.to_view(pad.button_center(PortraitPad.Y)), true)
	assert_true(pad.is_attack_held(), "Y attacks")
	assert_ne(state.aim, Vector2.ZERO)


func test_screen_touches_pass_and_menus_do_not_play() -> void:
	var state := _state()
	var pad := _pad(state)
	var frame: PortraitLayout.Frame = PortraitLayout.get_frame()
	assert_false(pad.handle_touch(0, Vector2(640, 300), true), "a tap on the game screen goes to the menus")
	assert_false(pad.playing, "no player polled: menu navigation")
	# No menu events into the test run.
	pad._nav_quiet_until = Time.get_ticks_msec() + 100000
	pad.handle_touch(1, frame.to_view(pad.button_center(PortraitPad.A)), true)
	assert_eq(state.aim, Vector2.ZERO, "A in a menu never attacks")
	assert_false(state.is_held(PlayerInput.ATTACK))
	assert_true(pad.handle_touch(2, frame.to_view(Vector2(5, frame.pad_bottom() - 5)), true), "the casing swallows stray touches")


func test_placeholders_exist_in_briefing_sizes() -> void:
	var sizes := {
		PixelArt.PANEL: Vector2i(24, 24), PixelArt.DPAD: Vector2i(52, 52), PixelArt.DPAD + "_pressed": Vector2i(52, 52),
		PixelArt.BUTTON_A: Vector2i(28, 28), PixelArt.BUTTON_A + "_pressed": Vector2i(28, 28),
		PixelArt.BUTTON_B: Vector2i(28, 28), PixelArt.BUTTON_B + "_pressed": Vector2i(28, 28),
		PixelArt.BUTTON_SMALL: Vector2i(20, 20), PixelArt.BUTTON_SMALL + "_pressed": Vector2i(20, 20),
		PixelArt.BUTTON_FLAT: Vector2i(20, 8), PixelArt.BUTTON_FLAT + "_pressed": Vector2i(20, 8),
	}
	for art_name: String in sizes:
		var image := PixelArt.image(art_name)
		assert_not_null(image, art_name)
		if image != null:
			assert_eq(image.get_size(), sizes[art_name], art_name)
	assert_eq(PixelArt.image("letters_AB").get_size(), Vector2i(7, 5), "3×5 letters, 1 px apart")
	assert_true(PixelArt.image("button_a").get_pixel(14, 13).a > 0.99, "the casing buttons are opaque")


func _state() -> TouchState:
	var state := TouchState.new()
	state.forced = true
	return state


func _pad(state: TouchState) -> PortraitPad:
	PortraitLayout.set_frame(PortraitLayout.compute(Vector2(1080, 2400)))
	var pad: PortraitPad = autofree(PortraitPad.new(state))
	pad.follow_options = false
	pad.set_frame(PortraitLayout.get_frame())
	return pad


## Bounding rect of a shape part (Rect2, or Vector3 = circle centre x, y and radius).
func _bounds(part: Variant) -> Rect2:
	if part is Rect2:
		return part
	var circle: Vector3 = part
	return Rect2(circle.x - circle.z, circle.y - circle.z, circle.z * 2.0, circle.z * 2.0)


func _overlap(a: Array, b: Array) -> bool:
	for first: Variant in a:
		for second: Variant in b:
			if _parts_overlap(first, second):
				return true
	return false


func _parts_overlap(a: Variant, b: Variant) -> bool:
	if a is Rect2 and b is Rect2:
		return (a as Rect2).intersects(b)
	if a is Vector3 and b is Vector3:
		var ca: Vector3 = a
		var cb: Vector3 = b
		return Vector2(ca.x, ca.y).distance_to(Vector2(cb.x, cb.y)) < ca.z + cb.z
	var circle: Vector3 = a if a is Vector3 else b
	var rect: Rect2 = b if a is Vector3 else a
	var center := Vector2(circle.x, circle.y)
	var nearest := center.clamp(rect.position, rect.end)
	return nearest.distance_to(center) < circle.z

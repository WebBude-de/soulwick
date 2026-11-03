extends GutTest
## FS2c, D-218 "Nur Pixel-Effekte": the last soft spots found in FS2b. The village way-pointer is
## PixelArrow's upright picture at a whole scale and its soul lights twinkle in hard steps; the dialog
## accent line is a few hard texels; Flint's portrait frame, the side turret's telegraph and the
## village particles are whole art pixels; swing and explosion art get whole scales while the hits
## keep their exact size.

const GuideScript := preload("res://world/village/village_guide.gd")
const PIXEL := PixelDraw.WORLD_PIXEL

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_fx_pixel_leftovers_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path
	LightingQuality.set_high(true)


func _on_grid(value: float, pixel: float) -> bool:
	return is_equal_approx(fposmod(value, pixel), 0.0) or is_equal_approx(fposmod(value, pixel), pixel)


func _assert_rects_on_grid(rects: Array[Rect2], what: String, pixel := PIXEL, origin := Vector2.ZERO) -> void:
	assert_gt(rects.size(), 0, "%s draws something" % what)
	for area in rects:
		var start := area.position - origin
		if not (_on_grid(start.x, pixel) and _on_grid(start.y, pixel) and _on_grid(area.size.x, pixel) and _on_grid(area.size.y, pixel)):
			fail_test("%s: %s is off the grid of %s px" % [what, area, pixel])
			return
	pass_test("%s: %d rects on the grid" % [what, rects.size()])


## Distinct alpha values of the painted pixels.
func _alphas(image: Image) -> Dictionary:
	var found := {}
	for y in image.get_height():
		for x in image.get_width():
			found[snappedf(image.get_pixel(x, y).a, 0.01)] = true
	return found


# --- Village way: arrow and soul lights ---

func test_guide_arrow_is_the_upright_pixel_arrow_at_a_whole_scale() -> void:
	var art := roundf(GuideScript.ARROW_SCALE)
	assert_eq(GuideScript.ARROW_SCALE, art, "the arrow scale is a whole number")
	for i in 32:
		var angle := TAU * i / 32.0
		for bob in [-GuideScript.ARROW_BOB, -2.5, 0.0, 1.7, GuideScript.ARROW_BOB]:
			for grow in [0, 1]:
				var picture: Rect2 = GuideScript.pointer_rect(Vector2(401.3, 233.8), angle, bob, grow)
				var scale: float = art + float(grow)
				assert_eq(picture.size, Vector2.ONE * PixelArrow.CANVAS * scale, "whole scale of PixelArrow's canvas")
				assert_eq(picture.position, picture.position.round(), "corner on a whole screen pixel")
	var still: Rect2 = GuideScript.pointer_rect(Vector2(400, 240), 0.0, 0.0)
	for bob in [-GuideScript.ARROW_BOB, -3.1, 2.2, GuideScript.ARROW_BOB]:
		var moved: Rect2 = GuideScript.pointer_rect(Vector2(400, 240), 0.0, bob)
		assert_true(_on_grid(moved.position.x - still.position.x, art), "the bob moves in whole art pixels: %s" % bob)
	var source := FileAccess.get_file_as_string("res://world/village/village_guide.gd")
	assert_true(source.contains("PixelArrow.texture_for"), "drawn from PixelArrow's turned pictures")
	assert_false(source.contains("draw_set_transform(_pointer_position"), "no freely rotated texture any more")


func test_guide_soul_lights_twinkle_in_hard_steps() -> void:
	var seen := {}
	for i in 200:
		seen[snappedf(GuideScript.mote_alpha(i / 199.0), 0.001)] = true
	assert_lte(seen.size(), GuideScript.MOTE_ALPHA_STEPS + 1, "a few hard alpha steps: %s" % [seen.keys()])
	assert_eq(GuideScript.mote_alpha(0.0), 0.0, "faded out is gone")
	assert_eq(GuideScript.mote_alpha(1.0), 1.0)


# --- UI: accent line, Flint's portrait frame ---

func test_accent_line_is_a_few_hard_texels() -> void:
	var line := UiKit.accent_line(Color(0.9, 0.7, 0.2))
	add_child_autofree(line)
	assert_false(line.texture is GradientTexture1D, "no smooth gradient texture")
	assert_eq(line.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "stretched without smoothing")
	var image := line.texture.get_image()
	assert_eq(image.get_width(), UiKit.ACCENT_LINE_STEPS, "one texel per step")
	assert_lt(image.get_pixel(0, 0).a, image.get_pixel(1, 0).a, "fades out to the left")
	assert_lt(image.get_pixel(image.get_width() - 1, 0).a, 1.0, "and to the right")
	assert_eq(fposmod(line.custom_minimum_size.y, float(UiKit.ART_SCALE)), 0.0, "whole art pixels high")


func test_flint_portrait_frame_is_pixel_discs_on_the_ui_grid() -> void:
	var pixel := float(UiKit.ART_SCALE)
	var side := UiKit.art_px(FlintPortrait.RING_SPEC, FlintPortrait.RING_SPEC)
	var box := Rect2(Vector2.ZERO, Vector2(side, side))
	for delivered in [true, false]:
		var raster := PixelDraw.Raster.new(Vector2i(box.size))
		FlintPortrait.paint_frame(raster, box, delivered)
		_assert_rects_on_grid(raster.rects, "portrait frame (delivered %s)" % delivered, pixel)
		assert_eq(_alphas(raster.image).size(), 2, "opaque pixels and empty corners only, no smooth edge")
		assert_eq(raster.image.get_pixel(0, 0).a, 0.0, "corners stay free")
		assert_true(raster.image.get_pixelv(Vector2i(box.get_center())).is_equal_approx(FlintPortrait.RING_FILL), "dark disc in the middle")
	var raster := PixelDraw.Raster.new(Vector2i(box.size))
	FlintPortrait.paint_frame(raster, box, false)
	var edge := raster.image.get_pixel(int(side * 0.5), int(pixel * 1.5))
	assert_true(edge.is_equal_approx(FlintPortrait.RING_EDGE), "code ring: the gold ring one art pixel inside the rim, got %s" % edge)
	var source := FileAccess.get_file_as_string("res://ui/flint_guide/flint_portrait.gd")
	assert_false(source.contains("draw_circle("), "no soft circles left")


# --- Side turret telegraph ---

func test_side_turret_telegraph_is_pixels_on_the_world_grid() -> void:
	for progress in [0.05, 0.4, 0.8, 1.0]:
		for aim in [Vector2.RIGHT, Vector2(0.8, -0.6), Vector2.LEFT]:
			var raster := PixelDraw.Raster.new(Vector2i(400, 200), Vector2(200, 100))
			SideTurret.paint_telegraph(raster, Vector2(0, -40), aim * 180.0, progress, progress > 0.75, Color(1.0, 0.4, 0.3))
			_assert_rects_on_grid(raster.rects, "turret telegraph %s %s" % [progress, aim])
	var radii := {}
	for i in 40:
		var recorder := PixelDraw.Recorder.new()
		SideTurret.paint_telegraph(recorder, Vector2.ZERO, Vector2.ZERO, i / 39.0, false, Color.WHITE)
		var widest := 0.0
		for area in recorder.rects:
			widest = maxf(widest, area.size.x)
		radii[widest] = true
	assert_lte(radii.size(), SideTurret.TELEGRAPH_STEPS + 1, "the eye glow grows in a few hard steps (and the start): %s" % [radii.keys()])
	var source := FileAccess.get_file_as_string("res://enemies/turret/side_turret.gd")
	for call in ["draw_line(", "draw_circle(", "draw_arc("]:
		assert_false(source.contains(call), "no soft %s" % call)


# --- Village particles ---

func test_village_motes_are_one_art_pixel_and_step() -> void:
	var ambience: VillageAmbience = autofree(VillageAmbience.new())
	for mode in [VillageAmbience.Mode.POLLEN, VillageAmbience.Mode.FIREFLIES]:
		ambience.apply_mode(mode)
		assert_eq(ambience.scale_amount_min, PIXEL, "one art pixel")
		assert_eq(ambience.scale_amount_max, PIXEL, "no random fractional size")
		assert_eq(ambience.texture.get_size(), Vector2(1, 1), "a single texel")
		assert_eq(ambience.color_ramp.interpolation_mode, Gradient.GRADIENT_INTERPOLATE_CONSTANT, "blinks in hard steps")
		assert_null(ambience.scale_amount_curve, "no smooth growth")


func test_village_motes_are_off_on_low_light_effects() -> void:
	var ambience: VillageAmbience = add_child_autofree(VillageAmbience.new())
	LightingQuality.set_high(false)
	ambience.apply_mode(VillageAmbience.Mode.FIREFLIES)
	assert_false(ambience.emitting, "Lichteffekte: Niedrig switches the ambient motes off")
	LightingQuality.set_high(true)
	await wait_process_frames(2)
	assert_true(ambience.emitting, "and on again at once")


func test_chimney_smoke_grows_in_whole_pixel_frames() -> void:
	var smoke: ChimneySmoke = autofree(ChimneySmoke.new())
	assert_eq(smoke.scale_amount_min, ChimneySmoke.ART_SCALE)
	assert_eq(smoke.scale_amount_max, ChimneySmoke.ART_SCALE)
	assert_eq(ChimneySmoke.ART_SCALE, roundf(ChimneySmoke.ART_SCALE), "whole scale")
	assert_null(smoke.scale_amount_curve, "no smooth growth")
	var frames := smoke.material as CanvasItemMaterial
	assert_not_null(frames, "puff frames through the particle animation")
	assert_true(frames.particles_animation)
	assert_eq(frames.particles_anim_h_frames, ChimneySmoke.PUFF_RADII.size())
	assert_eq(smoke.color_ramp.interpolation_mode, Gradient.GRADIENT_INTERPOLATE_CONSTANT, "fades in hard steps")
	var image := ChimneySmoke.paint_puff_sheet()
	var side := ChimneySmoke.PUFF_RADII[ChimneySmoke.PUFF_RADII.size() - 1] * 2
	assert_eq(image.get_size(), Vector2i(side * ChimneySmoke.PUFF_RADII.size(), side))
	assert_eq(_alphas(image).size(), 2, "white pixels and empty ones only")
	var previous := 0
	for i in ChimneySmoke.PUFF_RADII.size():
		var count := 0
		for y in side:
			for x in side:
				if image.get_pixel(side * i + x, y).a > 0.0:
					count += 1
		assert_gt(count, previous, "frame %d is larger than the one before" % i)
		previous = count


# --- Swing and explosion: whole art scales, exact hits ---

func test_swing_art_gets_whole_scales() -> void:
	assert_eq(WeaponController.swing_art_scale(75.0, 100.0), Vector2(3, 3), "sword")
	assert_eq(WeaponController.swing_art_scale(52.0, 70.0), Vector2(2, 1), "dagger")
	for radius in [20.0, 37.0, 52.0, 63.0, 75.0, 90.0, 118.0]:
		for angle in [60.0, 100.0, 140.0, 200.0]:
			var scale := WeaponController.swing_art_scale(radius, angle)
			assert_eq(scale, scale.round(), "whole scale for %s px over %s deg" % [radius, angle])
			assert_gte(minf(scale.x, scale.y), 1.0)


func test_swing_hit_area_keeps_its_exact_reach() -> void:
	var source := FileAccess.get_file_as_string("res://player/weapon_controller.gd")
	assert_true(source.contains("_swing_shape.polygon = _build_swing_polygon(radius, deg_to_rad(angle_degrees))"), "the hit polygon still uses the exact radius and angle")
	assert_true(source.contains("_swing_effect.scale = swing_art_scale(radius, angle_degrees)"), "only the picture is rounded")


func test_explosive_hit_art_has_a_whole_scale_and_the_hit_keeps_its_radius() -> void:
	var scale := WeaponFx.art_scale(UpgradeEffects.EXPLOSION_RADIUS, UpgradeEffects.EXPLOSION_ART_RADIUS)
	assert_eq(scale, roundf(scale), "whole scale")
	assert_eq(scale, 1.0, "48 px hit on 45 px art: shown at 1x")
	var source := FileAccess.get_file_as_string("res://upgrades/effects/upgrade_effects.gd")
	assert_true(source.contains("AreaDamage.apply(self, center, EXPLOSION_RADIUS"), "the hit keeps EXPLOSION_RADIUS")
	assert_true(source.contains("WeaponFx.art_scale(EXPLOSION_RADIUS, EXPLOSION_ART_RADIUS)"))

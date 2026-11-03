extends GutTest
## Looks of the side view (FS7b): every side animation of the player - also the sprint at full
## momentum and the stomp - wears the colours of the player's look (feedback #31d6e702: the figure
## lost its colours while running, because the sprint was added later to the baked frames); a tilting
## platform keeps the art-pixel grid while it tips and falls, never turned, its whole slab in the
## picture (feedback #e0486234: the texture looked broken when the platform fell).

const SIDE_ANIMATIONS: Array[StringName] = [
	PlayerSideArt.JUMP, PlayerSideArt.LAND, PlayerSideArt.FALL, PlayerSideArt.CLIMB,
	PlayerSideArt.DOUBLE_JUMP, PlayerSideArt.WALL_SLIDE, SideSpeedArt.SPRINT, SideSpeedArt.STOMP,
]

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_side_look_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _look() -> Dictionary:
	var look := PlayerLook.with_color(PlayerLook.default_look(&"wick"), PlayerLook.HAIR, 3)
	return PlayerLook.with_color(look, PlayerLook.OUTFIT, 5)


func _image(texture: Texture2D) -> Image:
	var atlas := texture as AtlasTexture
	var image := (atlas.atlas if atlas != null else texture).get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	if atlas != null:
		image = image.get_region(Rect2i(atlas.region))
	return image


func _differing_pixels(a: Image, b: Image) -> int:
	var count := 0
	for y in mini(a.get_height(), b.get_height()):
		for x in mini(a.get_width(), b.get_width()):
			if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				count += 1
	return count


func test_baked_look_has_every_side_animation_in_its_colours() -> void:
	var data := CharacterCatalog.get_character(&"wick")
	var frames := PlayerLook.frames_for(data, _look())
	var base := data.get_frames()
	for animation in SIDE_ANIMATIONS:
		assert_true(frames.has_animation(animation), "%s is in the baked look" % animation)
		assert_true(base.has_animation(animation), "%s is in the base frames it was baked from" % animation)
		if not frames.has_animation(animation) or not base.has_animation(animation):
			continue
		var baked := _image(frames.get_frame_texture(animation, 0))
		var plain := _image(base.get_frame_texture(animation, 0))
		assert_gt(_differing_pixels(baked, plain), 0, "%s is recoloured" % animation)


func test_player_sprite_keeps_its_colours_after_the_side_view_was_prepared() -> void:
	var sprite := AnimatedSprite2D.new()
	add_child_autofree(sprite)
	SpriteFx.apply(sprite)
	PlayerLook.apply(sprite, _look())
	var baked_frames := sprite.sprite_frames
	PlayerSideArt.ensure(sprite)
	assert_eq(sprite.sprite_frames, baked_frames, "the side view adds nothing to the baked look")
	var sprint_art := SideSpeedArt.SPRINT_TEXTURE_PATH
	if not ResourceLoader.exists(sprint_art):
		pass_test("no delivered sprint strip: the sprint is the recoloured walk")
		return
	var raw := (load(sprint_art) as Texture2D)
	var shown := sprite.sprite_frames.get_frame_texture(SideSpeedArt.SPRINT, 0) as AtlasTexture
	assert_not_null(shown)
	if shown != null:
		assert_ne(shown.atlas, raw, "the sprint shows the recoloured sheet, not the delivered one")


# --- Tilting platform ---

func _opaque(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				count += 1
	return count


func _edge_rows_empty(image: Image) -> bool:
	for x in image.get_width():
		if image.get_pixel(x, 0).a > 0.0 or image.get_pixel(x, image.get_height() - 1).a > 0.0:
			return false
	return true


func test_tilting_platform_tips_and_falls_on_the_pixel_grid() -> void:
	var tilt := SideTilt.new()
	tilt.cells = 2
	add_child_autofree(tilt)
	var art := tilt.get_node_or_null("Pieces/Art") as Sprite2D
	if art == null:
		pass_test("no delivered tilt art: the placeholder ledge pieces only shake and drop")
		return
	tilt.step(0.0)
	var still := tilt.get_frame_picture()
	tilt.touch()
	tilt.step(SideElementRules.TILT_DELAY * 0.8)
	assert_eq(tilt.state, SideCrumble.State.SHAKING)
	assert_eq(art.rotation, 0.0, "tipping: not turned")
	var tipping := tilt.get_frame_picture()
	assert_true(_edge_rows_empty(tipping), "tipping: the whole slab is in the picture")
	tilt.step(SideElementRules.TILT_DELAY)
	assert_eq(tilt.state, SideCrumble.State.FALLEN)
	tilt.step(0.05)
	assert_eq(art.rotation, 0.0, "falling: not turned")
	var falling := tilt.get_frame_picture()
	assert_true(_edge_rows_empty(falling), "falling: the whole slab is in the picture")
	assert_gt(falling.get_height(), tipping.get_height() - 1, "falling tilts at least as far")
	tilt.step(SideElementRules.TILT_RESPAWN + 0.1)
	assert_eq(tilt.state, SideCrumble.State.SOLID)
	assert_eq(_opaque(tilt.get_frame_picture()), _opaque(still), "back: the still frame again")


func test_cut_off_frames_get_a_sheared_stand_in() -> void:
	var sheet := load(SideTilt.ART_PATH % SideTiles.FALLBACK_BIOME) as Texture2D
	if sheet == null:
		pass_test("no delivered tilt art")
		return
	assert_false(SideTilt.is_cut_off(sheet, SideTilt.FRAME_STILL), "the still slab fits its frame")
	assert_null(SideTilt.stand_in_for(sheet, SideTilt.FRAME_STILL), "the still frame is shown as delivered")
	var still := sheet.get_image().get_region(Rect2i(Vector2i.ZERO, SideTilt.ART_FRAME))
	for frame in [SideTilt.FRAME_TIPPING, SideTilt.FRAME_FALLING]:
		var stand_in := SideTilt.stand_in_for(sheet, frame)
		assert_eq(stand_in != null, SideTilt.is_cut_off(sheet, frame), "frame %d: a stand-in exactly when cut off" % frame)
		if stand_in != null:
			var image := stand_in.get_image()
			assert_eq(image.get_width(), SideTilt.ART_FRAME.x, "same width")
			assert_eq(_opaque(image), _opaque(still), "frame %d: the still slab, pixel for pixel, only sheared" % frame)


func test_shear_moves_whole_columns() -> void:
	var image := Image.create_empty(4, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var result := SideTilt.sheared(image, 0.5)
	assert_eq(result.get_size(), Vector2i(4, 4), "taller by twice the largest shift")
	assert_eq(result.get_pixel(0, 0).a, 1.0, "the left column goes up")
	assert_eq(result.get_pixel(3, 3).a, 1.0, "the right column goes down")
	assert_eq(result.get_pixel(0, 3).a, 0.0)

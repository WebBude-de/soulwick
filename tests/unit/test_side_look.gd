extends GutTest
## Looks of the side view (FS7b): every side animation of the player - also the sprint at full
## momentum and the stomp - wears the colours of the player's look (feedback #31d6e702: the figure
## lost its colours while running, because the sprint was added later to the baked frames); a tilting
## platform keeps the art-pixel grid while it tips and falls, never turned, its whole slab in the
## picture (feedback #e0486234: the texture looked broken when the platform fell). The V13e frames
## (64×48) are shown as delivered; only a frame cut off by its edge gets the sheared stand-in.

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


func _row_count(image: Image, row: int) -> int:
	var count := 0
	for x in image.get_width():
		if image.get_pixel(x, row).a > 0.0:
			count += 1
	return count


## The slab does not run into the top or bottom edge (a few falling crumbs may touch it).
func _slab_in_picture(image: Image) -> bool:
	return _row_count(image, 0) < SideTilt.CUT_OFF_PIXELS and _row_count(image, image.get_height() - 1) < SideTilt.CUT_OFF_PIXELS


## Rows from the first to the last one with opaque pixels (how far the slab leans).
func _row_span(image: Image) -> int:
	var first := -1
	var last := -1
	for y in image.get_height():
		if _row_count(image, y) > 0:
			if first < 0:
				first = y
			last = y
	return last - first + 1 if first >= 0 else 0


## A sheet of ART_FRAMES 64×16 frames whose tipping and falling slabs fill the frame (the first
## delivery's fault): a still slab of rows 4-11, the other frames full.
func _cut_off_sheet() -> ImageTexture:
	var image := Image.create_empty(64 * SideTilt.ART_FRAMES, 16, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(0, 4, 64, 8), Color.WHITE)
	image.fill_rect(Rect2i(64, 4, 64, 8), Color.WHITE)
	image.fill_rect(Rect2i(128, 0, 128, 16), Color.WHITE)
	return ImageTexture.create_from_image(image)


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
	assert_true(_slab_in_picture(tipping), "tipping: the whole slab is in the picture")
	assert_gt(_row_span(tipping), _row_span(still), "tipping: the slab leans")
	tilt.step(SideElementRules.TILT_DELAY)
	assert_eq(tilt.state, SideCrumble.State.FALLEN)
	tilt.step(0.05)
	assert_eq(art.rotation, 0.0, "falling: not turned")
	var falling := tilt.get_frame_picture()
	assert_true(_slab_in_picture(falling), "falling: the whole slab is in the picture")
	assert_gt(_row_span(falling), _row_span(tipping) - 1, "falling tilts at least as far")
	tilt.step(SideElementRules.TILT_RESPAWN + 0.1)
	assert_eq(tilt.state, SideCrumble.State.SOLID)
	assert_eq(_opaque(tilt.get_frame_picture()), _opaque(still), "back: the still frame again")


func test_delivered_frames_are_shown_as_they_are() -> void:
	for biome in [&"crypt", &"slime_grotto", &"ember_forge", &"shadow_realm"]:
		var path: String = SideTilt.ART_PATH % biome
		if not ResourceLoader.exists(path):
			continue
		var sheet := load(path) as Texture2D
		assert_eq(SideTilt.frame_size(sheet), SideTilt.ART_FRAME, "%s: 4 frames of 64×48 (V13e)" % biome)
		assert_eq(SideTilt.art_pivot(path, SideTilt.frame_size(sheet)), Vector2(32, 24), "%s: pivot from the JSON" % biome)
		for frame in SideTilt.ART_FRAMES:
			assert_false(SideTilt.is_cut_off(sheet, frame), "%s frame %d: the slab fits its frame" % [biome, frame])
			assert_null(SideTilt.stand_in_for(sheet, frame), "%s frame %d: shown as delivered" % [biome, frame])


func test_cut_off_frames_get_a_sheared_stand_in() -> void:
	var sheet := _cut_off_sheet()
	assert_false(SideTilt.is_cut_off(sheet, SideTilt.FRAME_STILL), "the still slab fits its frame")
	assert_null(SideTilt.stand_in_for(sheet, SideTilt.FRAME_STILL), "the still frame is shown as delivered")
	var still := sheet.get_image().get_region(Rect2i(Vector2i.ZERO, SideTilt.frame_size(sheet)))
	for frame in [SideTilt.FRAME_TIPPING, SideTilt.FRAME_FALLING]:
		assert_true(SideTilt.is_cut_off(sheet, frame), "frame %d runs into the edges" % frame)
		var stand_in := SideTilt.stand_in_for(sheet, frame)
		assert_not_null(stand_in, "frame %d: a stand-in" % frame)
		if stand_in != null:
			var image := stand_in.get_image()
			assert_eq(image.get_width(), 64, "same width")
			assert_eq(_opaque(image), _opaque(still), "frame %d: the still slab, pixel for pixel, only sheared" % frame)
			assert_true(_slab_in_picture(image), "frame %d: the stand-in holds the whole slab" % frame)


func test_crumbs_on_the_edge_are_no_cut_off() -> void:
	var image := Image.create_empty(64 * SideTilt.ART_FRAMES, 16, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(0, 4, 64 * SideTilt.ART_FRAMES, 8), Color.WHITE)
	image.set_pixel(64 * SideTilt.FRAME_FALLING + 60, 15, Color.WHITE)
	var sheet := ImageTexture.create_from_image(image)
	assert_false(SideTilt.is_cut_off(sheet, SideTilt.FRAME_FALLING), "one crumb on the bottom row")
	image.fill_rect(Rect2i(64 * SideTilt.FRAME_FALLING, 15, SideTilt.CUT_OFF_PIXELS, 1), Color.WHITE)
	assert_true(SideTilt.is_cut_off(ImageTexture.create_from_image(image), SideTilt.FRAME_FALLING), "a slab edge on the bottom row")


func test_shear_moves_whole_columns() -> void:
	var image := Image.create_empty(4, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var result := SideTilt.sheared(image, 0.5)
	assert_eq(result.get_size(), Vector2i(4, 4), "taller by twice the largest shift")
	assert_eq(result.get_pixel(0, 0).a, 1.0, "the left column goes up")
	assert_eq(result.get_pixel(3, 3).a, 1.0, "the right column goes down")
	assert_eq(result.get_pixel(0, 3).a, 0.0)

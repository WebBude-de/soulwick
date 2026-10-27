extends GutTest
## Flint's pictures follow the website figure (D-217): the strips of tools/generate_flint.py with
## every animation of flint.json, flame masks and anchors, the website colours and small eyes, the
## code placeholder pixel for pixel the same figure, and the portraits facing left.

const OUTLINE := Color("#1c1a2b")
const WAX := Color("#efe6cf")
const HIGHLIGHT := Color("#ffffff")
const SHADE := Color("#b9b3c9")
const CHEEK := Color("#f0648c")
const FLAME_COLORS: Array[Color] = [Color("#ff8a3c"), Color("#ffb54a"), Color("#fff3c4")]
## Eyes of the companion's idle frame 0 (raster columns 6 and 9, body rows 4-5) in frame pixels.
const EYES: Array[Vector2i] = [Vector2i(14, 21), Vector2i(14, 22), Vector2i(17, 21), Vector2i(17, 22)]

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_flint_art_save.cfg"


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func _frame(art: FlintArt, animation: StringName, index := 0) -> Image:
	var image := art.frames.get_frame_texture(animation, index).get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image


func _is_flame(color: Color) -> bool:
	for flame in FLAME_COLORS:
		if color.is_equal_approx(flame):
			return true
	return false


func test_generated_art_has_every_animation_of_the_json() -> void:
	var art := FlintArt.get_art()
	assert_false(art.is_placeholder, "tools/generate_flint.py wrote the strips")
	assert_eq(art.frame_size, Vector2i(32, 32))
	assert_eq(art.pivot, Vector2(16, 30))
	assert_true(art.faces_left)
	var settings := FlintArt.read_settings(FlintArt.DIR + FlintArt.JSON_FILE)
	for entry: Dictionary in settings["animations"]:
		var name := String(entry["name"])
		if name.begins_with(FlintArt.FLAME_MASK_PREFIX):
			assert_true(art.has_flame_mask(StringName(name.trim_prefix(FlintArt.FLAME_MASK_PREFIX))), name)
			continue
		assert_true(art.has_animation(StringName(name)), name)
		assert_eq(art.frames.get_frame_count(StringName(name)), int(entry["frames"]), "%s frames" % name)
		assert_true(art.has_flame_mask(StringName(name)), "%s has a flame mask" % name)
	for mood: FlintMood.Mood in FlintMood.ANIMATIONS:
		assert_true(art.has_animation(FlintMood.animation_for(mood)), "mood %s has its strip" % FlintMood.animation_for(mood))


func test_the_figure_has_the_website_look() -> void:
	var image := _frame(FlintArt.get_art(), &"idle")
	var found := {}
	for color: Color in [OUTLINE, WAX, HIGHLIGHT, SHADE, CHEEK] + FLAME_COLORS:
		found[color.to_html()] = false
	for y in image.get_height():
		for x in image.get_width():
			var key := image.get_pixel(x, y).to_html()
			if found.has(key):
				found[key] = true
	for key: String in found:
		assert_true(found[key], "colour #%s of the website figure is used" % key)
	for eye in EYES:
		assert_eq(image.get_pixelv(eye), OUTLINE, "small eye pixel at %s" % eye)
	# Small narrow eyes: wax between and around them, no big dark eyes.
	assert_eq(image.get_pixel(15, 21), WAX, "wax between the eyes")
	assert_eq(image.get_pixel(14, 20), WAX, "the eye is two pixels tall")
	assert_eq(image.get_pixel(14, 23), WAX)


func test_flame_masks_cover_exactly_the_flame() -> void:
	var art := FlintArt.get_art()
	for animation: StringName in [&"idle", &"move", &"pulse", &"sleep"]:
		var picture := _frame(art, animation)
		var mask := art.flame_masks.get_frame_texture(animation, 0).get_image()
		mask.convert(Image.FORMAT_RGBA8)
		for y in picture.get_height():
			for x in picture.get_width():
				var flame := picture.get_pixel(x, y).a > 0.5 and _is_flame(picture.get_pixel(x, y))
				assert_eq(mask.get_pixel(x, y).a > 0.5, flame, "%s mask at (%d, %d)" % [animation, x, y])


func test_flame_anchor_is_on_the_flame_and_closed_above() -> void:
	var art := FlintArt.get_art()
	for animation: StringName in [&"idle", &"move", &"joy", &"pulse", &"scared", &"sleep"]:
		for i in art.frames.get_frame_count(animation):
			var image := _frame(art, animation, i)
			var flame := art.get_anchor(FlintArt.ANCHOR_FLAME, animation, i)
			var head := art.get_anchor(FlintArt.ANCHOR_HEAD, animation, i)
			assert_lt(flame.y, head.y, "%s %d: flame above the head" % [animation, i])
			var near := false
			for offset: Vector2i in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
				var cell := Vector2i(flame.floor()) + offset
				near = near or _is_flame(image.get_pixelv(cell))
			assert_true(near, "%s %d: the flame anchor sits on the flame" % [animation, i])
			for x in image.get_width():
				assert_eq(image.get_pixel(x, 0).a, 0.0, "%s %d: room above the flame" % [animation, i])


func test_placeholder_is_pixel_for_pixel_the_generated_figure() -> void:
	var generated := _frame(FlintArt.get_art(), &"idle")
	var placeholder := FlintPlaceholder.paint(FlintPlaceholder.Pose.new())
	assert_eq(placeholder.get_size(), generated.get_size())
	var differing := 0
	for y in generated.get_height():
		for x in generated.get_width():
			var a := generated.get_pixel(x, y)
			var b := placeholder.get_pixel(x, y)
			if a.a > 0.0 or b.a > 0.0:
				if not a.is_equal_approx(b):
					differing += 1
	assert_eq(differing, 0, "one Flint look: FlintPlaceholder copies the rasters of tools/generate_flint.py")


func test_portraits_show_the_figure_facing_left() -> void:
	var frames := FlintPortraitArt.get_frames()
	assert_true(FlintPortraitArt.has_delivered_portraits())
	for animation: StringName in FlintPortraitArt.ANIMATIONS:
		var texture := frames.get_frame_texture(animation, 0)
		assert_eq(Vector2i(texture.get_size()), FlintPortraitArt.FRAME_SIZE, "%s is 48x48" % animation)
	var neutral := frames.get_frame_texture(&"neutral", 0).get_image()
	var point := frames.get_frame_texture(&"point", 0).get_image()
	assert_lt(point.get_used_rect().position.x, neutral.get_used_rect().position.x, "points to the left, to the bubble")
	var flame := Vector2i(FlintPortraitArt.flame_point())
	assert_gt(neutral.get_pixelv(flame).a, 0.5, "the portrait's flame anchor is on the flame")
	assert_ne(frames.get_frame_texture(&"talk", 0).get_image().get_data(), frames.get_frame_texture(&"talk", 1).get_image().get_data(),
			"the mouth moves while he talks")

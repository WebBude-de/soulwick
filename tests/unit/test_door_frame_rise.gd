extends GutTest
## Bug report 17.10.2026 #67215ac5 ("Cutted der Eingang"): no north frame reaches higher over its door
## tile than DoorStyle.MAX_FRAME_RISE (one corridor tile, M2: the crown is 32 art px, then the next
## room's floor). Tall art (boss gate, V9 soft arch) is lowered without scaling, a delivered
## <name>_low.png wins.

const TEST_SAVE_PATH := "user://test_door_frame_rise_save.cfg"
const TEST_ART_DIR := "user://test_door_rise_art/"

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH


func after_all() -> void:
	SaveManager.save_path = _old_save_path
	_wipe_art_dir()
	DoorArt.art_dir = DoorStyle.ART_DIR
	DoorArt.clear_cache()


func after_each() -> void:
	DoorArt.art_dir = DoorStyle.ART_DIR
	DoorArt.clear_cache()


func _wipe_art_dir() -> void:
	var path := ProjectSettings.globalize_path(TEST_ART_DIR)
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func _use_empty_art_dir() -> void:
	_wipe_art_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_ART_DIR))
	DoorArt.art_dir = TEST_ART_DIR
	DoorArt.clear_cache()


func _north_styles() -> Array[DoorStyle]:
	var styles: Array[DoorStyle] = []
	for biome in DoorStyle.BIOMES:
		styles.append_array(DoorArt.styles_of(biome))
	return styles


func _assert_fits(styles: Array[DoorStyle], label: String) -> void:
	for style in styles:
		var key := "%s %s" % [label, style.get_key()]
		assert_lte(style.leaf_offset.y, DoorStyle.MAX_FRAME_RISE, "%s: frame rises at most MAX_FRAME_RISE" % key)
		assert_eq(style.frame_size.y - style.leaf_offset.y, 32, "%s: the door tile stays at the bottom" % key)
		var frame := DoorArt.frame_image(style)
		assert_eq(Vector2i(frame.get_size()), style.frame_size, "%s: picture as large as the frame" % key)
		assert_false(DoorArt.passage_mask(style).is_empty(), "%s: still an opening" % key)


func test_delivered_frames_fit_under_the_next_room() -> void:
	DoorArt.clear_cache()
	_assert_fits(_north_styles(), "art")
	var boss := DoorStyle.for_door(&"crypt", DoorStyle.KIND_BOSS)
	if DoorArt.has_art(boss.get_frame_path()) and not boss.low_frame:
		assert_eq(boss.rise_cut, 56 - 32 - DoorStyle.MAX_FRAME_RISE, "the 64x56 boss gate loses its extra rows")
		# The head of the arch is kept: its top row is still the art's top row.
		var tall := DoorArt._load_file(DoorStyle.ART_DIR + "door_frame_boss.png").get_image()
		tall.convert(Image.FORMAT_RGBA8)
		var frame := DoorArt.frame_image(boss)
		var cut := DoorArt.frame_cut_rows(boss)
		assert_false(cut.has(0), "the top of the boss arch stays")
		for x in frame.get_width():
			assert_eq(frame.get_pixel(x, 0).a > 0.05, tall.get_pixel(x, 0).a > 0.05, "top row unchanged at x %d" % x)


func test_placeholder_frames_fit_too() -> void:
	_use_empty_art_dir()
	_assert_fits(_north_styles(), "placeholder")
	var boss := DoorStyle.for_door(&"crypt", DoorStyle.KIND_BOSS)
	assert_gt(boss.rise_cut, 0, "the painted boss gate is lowered")
	assert_not_null(DoorArt.get_glow(boss))
	assert_eq(Vector2i(DoorArt.get_glow(boss).get_size()), boss.frame_size, "glow lowered with the frame")
	var strip := DoorArt.get_leaf_strip(boss)
	assert_eq(Vector2i(strip.get_size()), Vector2i(boss.leaf_size.x * DoorArt.LEAF_FRAMES, boss.leaf_size.y))
	var holder := DoorArt.lowered_row(boss, 22)
	assert_between(holder, 22 - boss.rise_cut, 22, "torch holders move down with the rows above them")


func test_frames_that_fit_are_untouched() -> void:
	for biome in DoorStyle.BIOMES:
		for cave: bool in [false, true]:
			var style := DoorStyle.for_door(biome)
			style.apply_room_look(cave, false)
			assert_false(style.is_lowered(), "%s cave %s: 48 px tall frames stay as drawn" % [biome, cave])
			assert_eq(style.rise_cut, 0)


func test_delivered_low_frame_wins() -> void:
	_use_empty_art_dir()
	var low := Image.create_empty(64, 48, false, Image.FORMAT_RGBA8)
	# A plain frame: posts and a lintel, the passage open (transparent).
	for y in 48:
		for x in 64:
			if x < 16 or x >= 48 or y < 8:
				low.set_pixel(x, y, Color("8f88ad"))
	low.save_png(ProjectSettings.globalize_path(TEST_ART_DIR + "door_frame_boss_low.png"))
	DoorArt.clear_cache()
	var boss := DoorStyle.for_door(&"crypt", DoorStyle.KIND_BOSS)
	assert_true(boss.low_frame, "the low file is used")
	assert_eq(boss.rise_cut, 0, "nothing taken out of a low file that fits")
	assert_eq(boss.frame_size, Vector2i(64, 48))
	assert_eq(boss.leaf_offset, Vector2i(16, 16))
	assert_eq(boss.get_shown_frame_path(), DoorStyle.ART_DIR + "door_frame_boss_low.png")
	assert_true(DoorArt.has_frame_file(boss))
	var frame := DoorArt.frame_image(boss)
	assert_eq(Vector2i(frame.get_size()), Vector2i(64, 48))
	assert_almost_eq(frame.get_pixel(0, 0).a, 1.0, 0.01, "the delivered low picture")


func test_lower_rows_takes_empty_and_repeated_rows() -> void:
	# 8 wide, 12 tall: two empty rows on top, an outlined cap, a post of identical rows, a base.
	var image := Image.create_empty(8, 12, false, Image.FORMAT_RGBA8)
	for y in range(2, 12):
		for x in 8:
			var c := Color("6b6584")
			if y == 2 or y >= 10:
				c = Color("1c1a2b")
			image.set_pixel(x, y, c)
	var rows := DoorArt.lower_rows(image, 4)
	assert_eq(rows.size(), 4)
	assert_true(rows.has(0) and rows.has(1), "empty top rows first: %s" % [rows])
	assert_false(rows.has(2), "the outline of the top stays")
	for row in rows:
		assert_lt(row, 12 - DoorArt.LOWER_KEEP_BOTTOM, "the base stays")
	var lowered := DoorArt.without_rows(image, rows)
	assert_eq(lowered.get_height(), 8)
	assert_eq(lowered.get_pixel(0, lowered.get_height() - 1), Color("1c1a2b"), "bottom row unchanged")


func test_lowered_soft_arch_keeps_its_inner_shadow() -> void:
	for biome in DoorStyle.BIOMES:
		var style := DoorStyle.for_door(biome)
		style.apply_room_look(false, true)
		if not style.soft or not DoorArt.has_frame_file(style) or style.frame_size.x != DoorStyle.SOFT_ARCH_FRAME_SIZE.x:
			pending("V9 soft arch of %s not delivered" % biome)
			continue
		var shade := DoorArt.get_delivered_shade(style)
		assert_not_null(shade, "%s: inner shadow lowered with the arch" % biome)
		if shade != null:
			assert_eq(Vector2i(shade.get_size()), style.frame_size)

extends GutTest
## D1 doors: style choice per biome and room type, file names of SPRITES_V4 §4, fallback to
## placeholders without files and automatic use of delivered files.

const TEST_SAVE_PATH := "user://test_door_style_save.cfg"
const TEST_ART_DIR := "user://test_door_art/"

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH


func after_all() -> void:
	SaveManager.save_path = _old_save_path
	_wipe_art_dir()
	DoorArt.art_dir = DoorStyle.ART_DIR
	DoorArt.clear_cache()


func before_each() -> void:
	# An empty folder: no delivered door art, so every texture is a placeholder.
	_wipe_art_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_ART_DIR))
	DoorArt.art_dir = TEST_ART_DIR
	DoorArt.clear_cache()


func _wipe_art_dir() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_ART_DIR)
	var dir := DirAccess.open(absolute)
	if dir == null:
		return
	for file in dir.get_files():
		DirAccess.remove_absolute(absolute.path_join(file))
	DirAccess.remove_absolute(absolute)


func _save_png(file_name: String, size: Vector2i, color: Color) -> void:
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	image.save_png(ProjectSettings.globalize_path(TEST_ART_DIR + file_name))


# --- Style choice ---

func test_each_biome_has_its_own_leaf_and_sound() -> void:
	var leaves := {}
	var sounds := {}
	for biome in DoorStyle.BIOMES:
		var style := DoorStyle.for_door(biome)
		assert_eq(style.biome_id, biome)
		assert_eq(style.kind, DoorStyle.KIND_NORMAL)
		assert_eq(style.frame_size, Vector2i(48, 48), "frame size %s" % biome)
		leaves[style.leaf_kind] = true
		sounds[style.side_open_sound] = true
	assert_eq(leaves.size(), 4, "four different side leaves")
	assert_eq(sounds.size(), 4, "four different side door sounds")


## M2 (gates.json): slab in crypt and shadow realm, portcullis in grotto and forge and every arena;
## stone grinds, chains rattle; cave rooms frame their gate with the cave mouth.
func test_gates_per_biome_and_room() -> void:
	assert_eq(DoorStyle.for_door(&"crypt").gate, DoorStyle.GATE_SLAB)
	assert_eq(DoorStyle.for_door(&"shadow_realm").gate, DoorStyle.GATE_SLAB)
	assert_eq(DoorStyle.for_door(&"slime_grotto").gate, DoorStyle.GATE_BARS)
	assert_eq(DoorStyle.for_door(&"ember_forge").gate, DoorStyle.GATE_BARS)
	assert_eq(DoorStyle.for_door(&"crypt").open_sound, &"stone_grind")
	assert_eq(DoorStyle.for_door(&"ember_forge").open_sound, &"door_open_gate")
	var arena := DoorStyle.for_door(&"crypt")
	arena.apply_room_look(false, false, true)
	assert_eq(arena.gate, DoorStyle.GATE_BARS, "arenas close their ways with a portcullis")
	var cave := DoorStyle.for_door(&"slime_grotto")
	cave.apply_room_look(true)
	assert_true(cave.is_cave())
	assert_eq(cave.frame_size, DoorStyle.CAVE_FRAME_SIZE)
	assert_eq(cave.leaf_offset, DoorStyle.CAVE_LEAF_OFFSET)
	assert_eq(cave.get_frame_path(), "res://art/environment/doors/cave_mouth_slime_grotto.png")
	var soft := DoorStyle.for_door(&"crypt")
	soft.apply_room_look(true, true)
	assert_eq(soft.get_frame_path(), "res://art/environment/doors/cave_mouth_crypt_soft.png")
	var boss := DoorStyle.for_door(&"slime_grotto", DoorStyle.KIND_BOSS)
	boss.apply_room_look(true, false, true)
	assert_false(boss.is_gate(), "the boss gate keeps its chained double door")
	assert_false(boss.is_cave())
	assert_ne(DoorStyle.for_door(&"crypt").get_key(), cave.get_key())


func test_cave_rooms_by_template_or_fallback() -> void:
	assert_false(DoorStyle.is_cave_room(null, &"slime_grotto"))
	var hall := (load("res://dungeon/rooms/combat/combat_hall.tscn") as PackedScene).instantiate() as RoomController
	autofree(hall)
	var template := RoomTemplate.of(hall)
	if template != null and &"cave" in template:
		assert_eq(DoorStyle.is_cave_room(hall, &"slime_grotto"), bool(template.get(&"cave")), "the plan header decides")
	else:
		assert_true(DoorStyle.is_cave_room(hall, &"slime_grotto"), "fallback: grotto combat rooms are caves")
		assert_false(DoorStyle.is_cave_room(hall, &"crypt"), "fallback: crypt halls are built")


func test_biome_leaf_kinds() -> void:
	assert_eq(DoorStyle.for_door(&"crypt").leaf_kind, DoorStyle.LEAF_WOOD)
	assert_eq(DoorStyle.for_door(&"slime_grotto").leaf_kind, DoorStyle.LEAF_VINES)
	assert_eq(DoorStyle.for_door(&"shadow_realm").leaf_kind, DoorStyle.LEAF_VEIL)
	assert_eq(DoorStyle.for_door(&"ember_forge").leaf_kind, DoorStyle.LEAF_PORTCULLIS)
	assert_eq(DoorStyle.for_door(&"ember_forge").torch_mode, DoorStyle.TORCH_BRAZIER)
	assert_eq(DoorStyle.for_door(&"shadow_realm").glow_mode, DoorStyle.GLOW_PULSE, "runes glimmer")


func test_unknown_biome_falls_back_to_crypt() -> void:
	assert_eq(DoorStyle.for_door(&"").biome_id, &"crypt")
	assert_eq(DoorStyle.for_door(&"moon_garden").biome_id, &"crypt")
	assert_eq(DoorStyle.for_door(&"crypt", &"portal").kind, DoorStyle.KIND_NORMAL, "unknown kind = normal")


func test_boss_gate() -> void:
	for biome in DoorStyle.BIOMES:
		var style := DoorStyle.for_door(biome, DoorStyle.KIND_BOSS, &"shop")
		assert_true(style.is_boss())
		assert_eq(style.biome_id, biome, "boss gate keeps the biome for its tint")
		# 64x56 art, shown lowered to the crown (DoorStyle.MAX_FRAME_RISE, bug report #67215ac5).
		assert_eq(style.frame_size, Vector2i(64, 32 + DoorStyle.MAX_FRAME_RISE))
		assert_eq(style.leaf_kind, DoorStyle.LEAF_DOUBLE)
		assert_eq(style.glow_mode, DoorStyle.GLOW_THREAT, "closed boss gate looks threatening")
		assert_eq(style.open_sound, &"door_boss_unlock")
		assert_eq(style.symbol, &"", "no sign on the boss gate")


func test_file_names_follow_sprites_v4() -> void:
	assert_eq(DoorStyle.for_door(&"crypt").get_frame_path(), "res://art/environment/doors/door_frame_crypt.png")
	assert_eq(DoorStyle.for_door(&"slime_grotto").get_leaf_path(), "res://art/environment/doors/gate_bars_open_4f.png")
	assert_eq(DoorStyle.for_door(&"shadow_realm").get_frame_path(), "res://art/environment/doors/door_frame_shadow_realm.png")
	assert_eq(DoorStyle.for_door(&"shadow_realm").get_leaf_path(), "res://art/environment/doors/gate_slab_open_4f.png")
	assert_eq(DoorStyle.for_door(&"ember_forge").get_side_leaf_path(), "res://art/environment/doors/door_side_ember_forge_open_4f.png")
	var boss := DoorStyle.for_door(&"ember_forge", DoorStyle.KIND_BOSS)
	assert_eq(boss.get_frame_path(), "res://art/environment/doors/door_frame_boss.png")
	assert_eq(boss.get_leaf_path(), "res://art/environment/doors/door_boss_open_4f.png")
	assert_eq(DoorStyle.get_symbols_path(), "res://art/environment/doors/door_special_symbols.png")


func test_kind_per_room_type() -> void:
	assert_eq(DoorStyle.kind_for_room(RoomSequence.RoomType.BOSS), DoorStyle.KIND_BOSS)
	for type in [RoomSequence.RoomType.COMBAT, RoomSequence.RoomType.COMBAT_UPGRADE, RoomSequence.RoomType.SPECIAL, RoomSequence.RoomType.MINIBOSS]:
		assert_eq(DoorStyle.kind_for_room(type), DoorStyle.KIND_NORMAL)


func test_symbol_per_room_type() -> void:
	var special := RoomSequence.RoomType.SPECIAL
	assert_eq(DoorStyle.symbol_for_room(special, RoomSequence.SpecialType.SHOP), &"shop")
	assert_eq(DoorStyle.symbol_for_room(special, RoomSequence.SpecialType.WEAPON), &"weapon")
	assert_eq(DoorStyle.symbol_for_room(special, RoomSequence.SpecialType.FOUNTAIN), &"fountain")
	assert_eq(DoorStyle.symbol_for_room(special, RoomSequence.SpecialType.UPGRADE), &"upgrade")
	assert_eq(DoorStyle.symbol_for_room(special, -1), &"", "special type not known yet")
	assert_eq(DoorStyle.symbol_for_room(RoomSequence.RoomType.MINIBOSS), &"miniboss")
	assert_eq(DoorStyle.symbol_for_room(RoomSequence.RoomType.COMBAT), &"")
	assert_eq(DoorStyle.symbol_for_room(RoomSequence.RoomType.BOSS), &"", "the boss gate is sign enough")
	# Later room types (A6 campfire, A8 trial) get their sign by enum name.
	if RoomSequence.RoomType.has("CAMPFIRE"):
		assert_eq(DoorStyle.symbol_for_room(RoomSequence.RoomType["CAMPFIRE"]), &"campfire")


func test_symbol_columns_match_the_sheet() -> void:
	var expected: Array[StringName] = [&"shop", &"weapon", &"fountain", &"upgrade", &"trial", &"campfire"]
	for i in expected.size():
		assert_eq(DoorStyle.symbol_index(expected[i]), i)
	assert_eq(DoorStyle.symbol_index(&""), -1)


func test_every_door_sound_exists() -> void:
	var sounds := {}
	for kind in [DoorStyle.KIND_NORMAL, DoorStyle.KIND_BOSS]:
		for biome in DoorStyle.BIOMES:
			var style := DoorStyle.for_door(biome, kind)
			sounds[style.open_sound] = true
			sounds[style.side_open_sound] = true
			if style.close_sound != &"":
				sounds[style.close_sound] = true
	for sound: StringName in sounds:
		assert_true(ResourceLoader.exists("res://audio/sfx/%s.wav" % sound), "sound %s" % sound)


# --- Art: placeholders and delivered files ---

func test_placeholders_without_files() -> void:
	for kind in [DoorStyle.KIND_NORMAL, DoorStyle.KIND_BOSS]:
		for biome in DoorStyle.BIOMES:
			var style := DoorStyle.for_door(biome, kind)
			assert_false(DoorArt.has_frame_file(style))
			assert_false(DoorArt.has_leaf_file(style))
			var frame := DoorArt.get_frame(style)
			assert_not_null(frame, "placeholder frame %s %s" % [biome, kind])
			assert_eq(Vector2i(frame.get_size()), style.frame_size)
			var leaf := DoorArt.get_leaf_strip(style)
			assert_eq(Vector2i(leaf.get_size()), Vector2i(style.leaf_size.x * DoorArt.LEAF_FRAMES, style.leaf_size.y))
	for symbol in DoorStyle.SYMBOLS:
		assert_false(DoorArt.has_symbol_file(symbol))
		assert_not_null(DoorArt.get_symbol(symbol), "placeholder sign %s" % symbol)
	assert_null(DoorArt.get_symbol(&""))


func test_placeholder_leaf_ends_open() -> void:
	# Frame 4 of every leaf is a free, dark passage in the middle.
	for kind in [DoorStyle.KIND_NORMAL, DoorStyle.KIND_BOSS]:
		for biome in DoorStyle.BIOMES:
			var style := DoorStyle.for_door(biome, kind)
			var strip := DoorArt.paint_leaf_strip(style)
			var middle := strip.get_pixel(style.leaf_size.x * 3 + style.leaf_size.x / 2, style.leaf_size.y / 2)
			assert_lt(middle.get_luminance(), 0.12, "open passage %s %s" % [biome, kind])
			var closed := strip.get_region(Rect2i(Vector2i.ZERO, style.leaf_size)).get_data()
			var open := strip.get_region(Rect2i(Vector2i(style.leaf_size.x * 3, 0), style.leaf_size)).get_data()
			assert_ne(closed, open, "closed frame differs %s %s" % [biome, kind])


func test_delivered_frame_and_leaf_replace_placeholders() -> void:
	_save_png("door_frame_shadow_realm.png", Vector2i(48, 48), Color.MAGENTA)
	_save_png("gate_slab_open_4f.png", Vector2i(128, 48), Color.CYAN)
	var style := DoorStyle.for_door(&"shadow_realm")
	assert_true(DoorArt.has_frame_file(style))
	assert_true(DoorArt.has_leaf_file(style))
	var frame := DoorArt.get_frame(style).get_image()
	assert_eq(frame.get_pixel(5, 5), Color.MAGENTA)
	var leaf := DoorArt.get_leaf_strip(style).get_image()
	assert_eq(leaf.get_pixel(100, 10), Color.CYAN)
	# Other biomes still use placeholders.
	assert_false(DoorArt.has_frame_file(DoorStyle.for_door(&"crypt")))


func test_delivered_symbol_sheet() -> void:
	_save_png("door_special_symbols.png", Vector2i(96, 16), Color.WHITE)
	assert_true(DoorArt.has_symbol_file(&"weapon"))
	var weapon := DoorArt.get_symbol(&"weapon") as AtlasTexture
	assert_not_null(weapon)
	assert_eq(weapon.region, Rect2(16, 0, 16, 16))
	# The optional miniboss column is missing in a 6-column sheet: placeholder sign.
	assert_false(DoorArt.has_symbol_file(&"miniboss"))
	assert_false(DoorArt.get_symbol(&"miniboss") is AtlasTexture)


func test_glow_from_delivered_frame_finds_bright_colours() -> void:
	var image := Image.create_empty(48, 48, false, Image.FORMAT_RGBA8)
	image.fill(Color("3b3150"))
	image.set_pixel(10, 10, Color("a66ef0"))
	var glow := DoorArt.glow_from_frame(image, DoorStyle.for_door(&"shadow_realm"))
	assert_gt(glow.get_pixel(10, 10).a, 0.5, "rune glows")
	assert_eq(glow.get_pixel(20, 20).a, 0.0, "dark stone does not")


func test_glow_ignores_colours_far_from_the_glow_hue() -> void:
	var image := Image.create_empty(48, 48, false, Image.FORMAT_RGBA8)
	image.set_pixel(3, 3, Color("6fbf5a"))
	image.set_pixel(4, 4, Color("7ff0c8"))
	var glow := DoorArt.glow_from_frame(image, DoorStyle.for_door(&"slime_grotto"))
	assert_eq(glow.get_pixel(3, 3).a, 0.0, "moss stays dark")
	assert_gt(glow.get_pixel(4, 4).a, 0.5, "crystal glows")


func test_delivered_art_in_the_repository_is_used() -> void:
	DoorArt.art_dir = DoorStyle.ART_DIR
	DoorArt.clear_cache()
	for kind in [DoorStyle.KIND_NORMAL, DoorStyle.KIND_BOSS]:
		for biome in DoorStyle.BIOMES:
			var style := DoorStyle.for_door(biome, kind)
			if not DoorArt.has_frame_file(style):
				pending("door art for %s %s not delivered" % [biome, kind])
				continue
			assert_true(DoorArt.has_leaf_file(style), "leaf %s %s" % [biome, kind])
			assert_eq(Vector2i(DoorArt.get_frame(style).get_size()), style.frame_size, "frame size %s %s" % [biome, kind])
			assert_eq(Vector2i(DoorArt.get_leaf_strip(style).get_size()), Vector2i(style.leaf_size.x * DoorArt.LEAF_FRAMES, style.leaf_size.y))
	for symbol in [&"shop", &"weapon", &"fountain", &"upgrade", &"trial", &"campfire"]:
		if DoorArt.has_symbol_file(symbol):
			assert_true(DoorArt.get_symbol(symbol) is AtlasTexture, "sign %s from the sheet" % symbol)


func test_glow_only_for_glowing_styles() -> void:
	assert_null(DoorArt.get_glow(DoorStyle.for_door(&"crypt")))
	assert_not_null(DoorArt.get_glow(DoorStyle.for_door(&"shadow_realm")))
	assert_not_null(DoorArt.get_glow(DoorStyle.for_door(&"ember_forge")))
	assert_not_null(DoorArt.get_glow(DoorStyle.for_door(&"crypt", DoorStyle.KIND_BOSS)))

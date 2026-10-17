extends GutTest
## D-152: the look of a player (PlayerLook): API format of contracts PlayerAppearance, repair of bad
## values, the MM1 pair character + colour, recoloured frames per look (all four slots, every
## animation including the side view), placeholder marks of the three new figures, and the editor
## (ProfileEditor: rows, keys, figure switch). No save or profile file is written.

const PROFILE_PATH := "user://test_player_look_profile.cfg"


var _old_locale := ""


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	# Registers the translations (D-111) also when this file runs alone.
	Loc.apply(&"de")
	PlayerProfile.path_override = PROFILE_PATH
	PlayerProfile.reset()


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
	PlayerProfile.path_override = ""
	PlayerProfile.reset()


func test_ids_and_palettes_match_the_contract() -> void:
	assert_eq(PlayerLook.CHARACTERS, [&"wick", &"ember", &"moss", &"frost"] as Array[StringName])
	assert_eq(PlayerLook.COLOR_COUNT, 8, "contracts PLAYER_APPEARANCE_COLOR_MAX = 7")
	for slot in PlayerLook.SLOTS:
		assert_eq((PlayerLook.PALETTES[slot] as Array).size(), PlayerLook.COLOR_COUNT, "%s has 8 colours" % slot)
		assert_eq(PlayerLook.color_of(slot, 0), PlayerLook.SOURCE_RAMPS[slot][0], "%s: index 0 is the art's colour" % slot)
		for i in PlayerLook.COLOR_COUNT:
			assert_ne(tr(PlayerLook.color_name_key(slot, i)), String(PlayerLook.color_name_key(slot, i)), "name of %s %d" % [slot, i])
	for id in PlayerLook.CHARACTERS:
		assert_eq(PlayerLook.normalize(PlayerLook.default_look(id)), PlayerLook.default_look(id), "%s start look is valid" % id)


func test_normalize_repairs_everything() -> void:
	var look := PlayerLook.normalize({"character": "dragon", "colors": {"hair": 99.0, "outfit": -3, "skin": "x"}})
	assert_eq(look.character, "wick", "unknown figure")
	assert_eq(look.colors.hair, 7, "clamped, JSON floats become ints")
	assert_eq(look.colors.outfit, 0)
	assert_eq(look.colors.skin, 0, "broken value -> start colour")
	assert_eq(look.colors.accent, 0, "accent is optional")
	assert_eq(PlayerLook.normalize(null), PlayerLook.default_look())
	assert_true(PlayerLook.is_valid(PlayerLook.default_look(&"moss")))
	assert_false(PlayerLook.is_valid({"character": "moss"}))
	assert_eq(PlayerLook.key_of(PlayerLook.default_look(&"ember")), "ember|5|1|2|1")


func test_old_pair_of_mm1_becomes_a_look() -> void:
	var look := PlayerLook.from_legacy(&"hero", Color("#e0463a"))
	assert_eq(look.character, "wick")
	assert_eq(look.colors.outfit, 1, "red")
	assert_eq(PlayerLook.from_legacy(&"hero", Color(0, 0, 0, 0)).colors.outfit, 0, "no colour = start colour")
	assert_eq(PlayerLook.from_appearance({"character": &"hero", "color": Color("#f2cf4a")}).colors.outfit, 3)
	assert_eq(PlayerLook.from_appearance(PlayerLook.default_look(&"frost")), PlayerLook.default_look(&"frost"))
	assert_eq(PlayerLook.outfit_color(look), Color("#e0463a"))


func test_recolor_changes_only_its_slots_and_keeps_shading() -> void:
	var image := Image.create(6, 1, false, Image.FORMAT_RGBA8)
	var sources: Array[Color] = [Color("#c7542e"), Color("#86351c"), Color("#3690da"), Color("#f3c9a3"), Color("#1c1a2b"), Color("#c8552f")]
	for i in sources.size():
		image.set_pixel(i, 0, sources[i])
	var look := PlayerLook.normalize({"character": "wick", "colors": {"hair": 6, "outfit": 0, "skin": 0, "accent": 0}})
	PlayerLook.recolor(image, look)
	assert_true(image.get_pixel(0, 0).is_equal_approx(PlayerLook.color_of(PlayerLook.HAIR, 6)), "hair main tone -> blue")
	assert_lt(image.get_pixel(1, 0).get_luminance(), image.get_pixel(0, 0).get_luminance(), "the shadow stays darker")
	assert_eq(image.get_pixel(2, 0).to_html(false), "3690da", "outfit index 0 is untouched")
	assert_eq(image.get_pixel(3, 0).to_html(false), "f3c9a3", "skin untouched")
	assert_eq(image.get_pixel(4, 0).to_html(false), "1c1a2b", "outline untouched")
	assert_true(image.get_pixel(5, 0).is_equal_approx(image.get_pixel(0, 0)), "near colours of the art count too")


func test_baked_frames_have_every_animation_and_are_cached() -> void:
	var wick := CharacterCatalog.get_character(&"wick")
	var look := PlayerLook.normalize({"character": "wick", "colors": {"hair": 1, "outfit": 2, "skin": 3, "accent": 4}})
	var frames := PlayerLook.frames_for(wick, look)
	assert_not_null(frames)
	for animation: StringName in [&"idle", &"walk", &"dash", &"death", PlayerSideArt.JUMP, PlayerSideArt.CLIMB]:
		assert_true(frames.has_animation(animation), "has %s" % animation)
	assert_eq(frames.get_frame_count(&"walk"), wick.sprite_frames.get_frame_count(&"walk"))
	assert_eq(frames.get_animation_speed(&"walk"), wick.sprite_frames.get_animation_speed(&"walk"))
	assert_same(PlayerLook.frames_for(wick, look), frames, "cached per look")
	assert_same(PlayerLook.frames_for(wick, PlayerLook.default_look()).get_frame_texture(&"idle", 0).atlas, wick.sprite_frames.get_frame_texture(&"idle", 0).atlas, "wick in its art colours needs no new sheet")


func test_new_figures_are_visibly_different_placeholders() -> void:
	var counts := {}
	for id in PlayerLook.CHARACTERS:
		var data := CharacterCatalog.get_character(id)
		var frames := PlayerLook.frames_for(data, PlayerLook.normalize({"character": String(id), "colors": {"hair": 0, "outfit": 0, "skin": 0, "accent": 0}}))
		var texture := frames.get_frame_texture(&"idle", 0) as AtlasTexture
		var image := texture.atlas.get_image().get_region(Rect2i(texture.region))
		var opaque := 0
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a > 0.5:
					opaque += 1
		counts[id] = opaque
		assert_eq(data.get_placeholder_mark(), &"" if id == &"wick" or data.has_own_art() else id, "%s mark until its art exists" % id)
	for id in [&"ember", &"moss", &"frost"]:
		assert_gt(counts[id], counts[&"wick"], "%s has more on its head than wick" % id)
	assert_ne(counts[&"ember"], counts[&"moss"])
	assert_ne(counts[&"moss"], counts[&"frost"])


func test_apply_look_on_a_player_sprite_turns_the_mask_off() -> void:
	var sprite := AnimatedSprite2D.new()
	add_child_autofree(sprite)
	SpriteFx.apply(sprite)
	PlayerLook.apply(sprite, PlayerLook.default_look(&"frost"))
	sprite.play(&"walk")
	var material := sprite.material as ShaderMaterial
	assert_eq(material.shader, SpriteFx.SHADER, "the in-game material stays")
	assert_false(material.get_shader_parameter(&"use_mask"), "no double tint")
	assert_eq(sprite.get_meta(CharacterData.META_DATA), CharacterCatalog.get_character(&"frost"))
	PlayerSideArt.ensure(sprite)
	assert_false(material.get_shader_parameter(&"use_mask"), "also after the side view was prepared")


# --- Editor ---

func _editor(first := false) -> ProfileEditor:
	var editor := ProfileEditor.create("Kerze", PlayerLook.default_look(), first)
	add_child_autofree(editor)
	return editor


func test_editor_rows_and_keys() -> void:
	var editor := _editor()
	await wait_physics_frames(1)
	assert_eq(editor.get_row(), ProfileEditor.Row.NAME)
	editor._set_row(ProfileEditor.Row.FIGURE)
	assert_true(editor.handle_input(MenuInput.key_event(KEY_RIGHT)))
	assert_eq(PlayerLook.get_character(editor.get_look()), &"ember", "→ next figure")
	assert_eq(editor.get_look(), PlayerLook.default_look(&"ember"), "in its start colours")
	editor.handle_input(MenuInput.key_event(KEY_LEFT))
	editor.handle_input(MenuInput.key_event(KEY_LEFT))
	assert_eq(PlayerLook.get_character(editor.get_look()), &"frost", "← wraps around")
	editor.handle_input(MenuInput.key_event(KEY_DOWN))
	assert_eq(editor.get_row(), ProfileEditor.Row.HAIR)
	editor.handle_input(MenuInput.key_event(KEY_8))
	assert_eq(PlayerLook.get_index(editor.get_look(), PlayerLook.HAIR), 7, "8 picks the last colour")
	editor.handle_input(MenuInput.key_event(KEY_RIGHT))
	assert_eq(PlayerLook.get_index(editor.get_look(), PlayerLook.HAIR), 0, "→ wraps")
	editor.handle_input(MenuInput.key_event(KEY_S))
	assert_eq(editor.get_row(), ProfileEditor.Row.OUTFIT, "S works like ↓")
	(editor.find_child("Swatch_skin_5", true, false) as Button).pressed.emit()
	assert_eq(editor.get_row(), ProfileEditor.Row.SKIN, "a click selects the row")
	assert_eq(PlayerLook.get_index(editor.get_look(), PlayerLook.SKIN), 5)
	(editor.find_child("NextFigure", true, false) as Button).pressed.emit()
	assert_eq(PlayerLook.get_character(editor.get_look()), &"wick", "tap on the arrow")


func test_editor_escape_and_first_start() -> void:
	var editor := _editor()
	await wait_physics_frames(1)
	watch_signals(editor)
	editor._set_row(ProfileEditor.Row.FIGURE)
	assert_true(editor.handle_input(MenuInput.key_event(KEY_ESCAPE)))
	assert_signal_emitted(editor, "cancelled")
	var first := _editor(true)
	await wait_physics_frames(1)
	watch_signals(first)
	first._set_row(ProfileEditor.Row.FIGURE)
	first.handle_input(MenuInput.key_event(KEY_ESCAPE))
	assert_signal_not_emitted(first, "cancelled", "the first start has no way back")
	assert_null(first.find_child("CancelProfile", true, false))


func test_editor_saves_the_profile_offline() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
	PlayerProfile.reset()
	var editor := _editor(true)
	await wait_physics_frames(1)
	watch_signals(editor)
	editor.set_player_name("Lumen")
	editor.change_character(2)
	editor.confirm()
	await wait_physics_frames(2)
	assert_signal_emitted(editor, "saved", "no server needed")
	PlayerProfile.reset()
	assert_eq(PlayerProfile.current().player_name, "Lumen")
	assert_eq(PlayerLook.get_character(PlayerProfile.current().look), &"moss")


func test_first_start_without_a_keyboard_takes_the_default_name() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
	PlayerProfile.reset()
	var editor := ProfileEditor.create("", PlayerLook.default_look(), true)
	add_child_autofree(editor)
	await wait_physics_frames(1)
	watch_signals(editor)
	editor._set_row(ProfileEditor.Row.CONFIRM)
	editor.handle_input(MenuInput.key_event(KEY_ENTER))
	await wait_physics_frames(2)
	assert_signal_emitted(editor, "saved", "controller only: Enter on an empty name still goes on")
	assert_eq(PlayerProfile.current().player_name, tr(&"PROFILE_DEFAULT_NAME"))

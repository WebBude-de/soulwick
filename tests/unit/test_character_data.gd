extends GutTest
## Character data (MM1): catalog, tint masks that match the animation sheets, the clothing colour
## shader and the hook for the player sprite (CharacterCatalog.apply_active). Uses a test save file.

const TEST_PATH := "user://test_character_data.cfg"
const HANDOUT_COLORS: Array[String] = ["3690da", "e0463a", "5fcd62", "f2cf4a"]

var _old_path: String


func before_all() -> void:
	_old_path = SaveManager.save_path
	SaveManager.save_path = TEST_PATH
	SaveManager.load_game()


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	SaveManager.save_path = _old_path
	SaveManager.load_game()


func _sprite(data: CharacterData) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = data.sprite_frames
	add_child_autofree(sprite)
	return sprite


func test_catalog_has_the_hero_as_default() -> void:
	assert_false(CharacterCatalog.all().is_empty())
	var hero := CharacterCatalog.get_character(CharacterCatalog.DEFAULT_ID)
	assert_not_null(hero)
	assert_eq(hero.id, &"hero")
	assert_false(hero.display_name.is_empty())
	assert_false(hero.description.is_empty())
	assert_eq(CharacterCatalog.get_character(&"does_not_exist"), hero, "unknown ids fall back")
	assert_true(CharacterCatalog.has_character(&"hero"))


func test_every_character_is_complete() -> void:
	var ids := {}
	for data in CharacterCatalog.all():
		assert_false(ids.has(data.id), "unique id %s" % data.id)
		ids[data.id] = true
		assert_not_null(data.sprite_frames, String(data.id))
		assert_true(data.sprite_frames.has_animation(&"idle"), "%s has idle" % data.id)
		assert_false(data.color_choices.is_empty(), "%s offers colours" % data.id)
		assert_not_null(data.menu_weapon, "%s holds something in the menu" % data.id)


func test_masks_match_their_animation_sheets() -> void:
	var hero := CharacterCatalog.get_character(&"hero")
	for animation: StringName in [&"idle", &"walk", &"dash", &"death"]:
		var mask := hero.get_mask(animation)
		assert_not_null(mask, "mask for %s" % animation)
		var frame := hero.sprite_frames.get_frame_texture(animation, 0) as AtlasTexture
		assert_not_null(frame, "%s uses an atlas strip" % animation)
		if mask != null and frame != null:
			assert_eq(mask.get_size(), frame.atlas.get_size(), "mask size of %s" % animation)


func test_hero_offers_the_handout_player_colours() -> void:
	var hero := CharacterCatalog.get_character(&"hero")
	var offered: Array[String] = []
	for color in hero.color_choices:
		offered.append(color.to_html(false))
	for html in HANDOUT_COLORS:
		assert_has(offered, html)
	assert_eq(hero.default_color.to_html(false), "3690da")
	assert_eq(hero.get_color_index(Color("#e0463a")), 1)
	assert_eq(hero.color_names.size(), hero.color_choices.size(), "every colour has a name")
	assert_eq(hero.get_color_name(0), "Blau")
	assert_eq(hero.get_color_name(99), "")


func test_apply_to_sets_the_tint_and_follows_the_animation() -> void:
	var hero := CharacterCatalog.get_character(&"hero")
	var sprite := _sprite(hero)
	sprite.play(&"idle")
	hero.apply_to(sprite, Color("#e0463a"))
	var material := sprite.material as ShaderMaterial
	assert_not_null(material)
	assert_eq(material.shader, CharacterData.TINT_SHADER)
	assert_eq(material.get_shader_parameter(&"tint_color"), Color("#e0463a"))
	assert_eq(material.get_shader_parameter(&"tint_mask"), hero.get_mask(&"idle"))
	assert_true(material.get_shader_parameter(&"use_mask"))
	sprite.play(&"walk")
	assert_eq(material.get_shader_parameter(&"tint_mask"), hero.get_mask(&"walk"), "mask follows the animation")
	CharacterData.set_tint_color(sprite, Color("#f2cf4a"))
	assert_eq(material.get_shader_parameter(&"tint_color"), Color("#f2cf4a"))


func test_animation_without_mask_keeps_its_colours() -> void:
	var hero := CharacterCatalog.get_character(&"hero")
	var partial := CharacterData.new()
	partial.id = &"partial"
	partial.sprite_frames = hero.sprite_frames
	partial.tint_masks = {&"idle": hero.get_mask(&"idle")}
	var sprite := _sprite(hero)
	sprite.play(&"idle")
	partial.apply_to(sprite, Color.RED)
	sprite.play(&"dash")
	var material := sprite.material as ShaderMaterial
	assert_false(material.get_shader_parameter(&"use_mask"))


func test_apply_twice_reuses_material_and_connection() -> void:
	var hero := CharacterCatalog.get_character(&"hero")
	var sprite := _sprite(hero)
	hero.apply_to(sprite, Color.RED)
	var first := sprite.material
	hero.apply_to(sprite, Color.BLUE)
	assert_eq(sprite.material, first)
	assert_eq(sprite.animation_changed.get_connections().size(), 1)


func test_apply_active_uses_the_loaded_profile() -> void:
	SaveManager.set_profile("Test", &"hero", Color("#5fcd62"))
	var sprite := _sprite(CharacterCatalog.get_character(&"hero"))
	CharacterCatalog.apply_active(sprite)
	var material := sprite.material as ShaderMaterial
	assert_eq((material.get_shader_parameter(&"tint_color") as Color).to_html(false), "5fcd62")
	SaveManager.load_game()

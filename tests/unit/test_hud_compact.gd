extends GutTest
## G3 (playtest note #12): compact HUD with input symbols. InputGlyphs maps bindings to pictures
## (mouse buttons, space, tab …), KeyCap shows them or the key name on a cap of one height, the
## weapon block is small and keeps all values, the hint line uses the same caps. Uses a test save
## and a test settings folder, never the real ones.

const ROOT := "user://test_hud_compact"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const BOW: WeaponData = preload("res://weapons/data/bow.tres")

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String
var _old_locale: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	_old_locale = TranslationServer.get_locale()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()
	TranslationServer.set_locale("de")


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	_wipe()
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()
	TranslationServer.set_locale(_old_locale)


func after_each() -> void:
	TranslationServer.set_locale("de")


# --- InputGlyphs ---

func test_mouse_buttons_and_special_keys_have_pictures() -> void:
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	assert_eq(InputGlyphs.id_for_event(right), InputGlyphs.MOUSE_RIGHT)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	assert_eq(InputGlyphs.id_for_event(wheel), InputGlyphs.MOUSE_WHEEL)
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	assert_eq(InputGlyphs.id_for_event(space), InputGlyphs.SPACE)
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	assert_eq(InputGlyphs.id_for_event(tab), InputGlyphs.TAB)
	var letter := InputEventKey.new()
	letter.physical_keycode = KEY_Q
	assert_eq(InputGlyphs.id_for_event(letter), &"", "letters stay text caps")


func test_bindings_come_from_the_input_map() -> void:
	assert_eq(InputGlyphs.id_for_action(&"attack"), InputGlyphs.MOUSE_LEFT)
	assert_eq(InputGlyphs.id_for_action(&"special_attack"), InputGlyphs.MOUSE_RIGHT)
	assert_eq(InputGlyphs.id_for_action(&"dash"), InputGlyphs.SPACE)
	assert_eq(InputGlyphs.id_for_action(&"upgrade_overview"), InputGlyphs.TAB)
	assert_eq(InputGlyphs.id_for_action(&"no_such_action"), &"")


func test_shown_key_names_map_back_to_pictures_in_both_languages() -> void:
	assert_eq(InputGlyphs.id_for_name("Rechtsklick"), InputGlyphs.MOUSE_RIGHT)
	assert_eq(InputGlyphs.id_for_name("Leertaste"), InputGlyphs.SPACE)
	TranslationServer.set_locale("en")
	assert_eq(InputGlyphs.id_for_name("Right click"), InputGlyphs.MOUSE_RIGHT)
	assert_eq(InputGlyphs.id_for_name("Space"), InputGlyphs.SPACE)
	assert_eq(InputGlyphs.id_for_name("Q"), &"")


func test_every_glyph_has_a_placeholder_of_cap_height() -> void:
	for id in InputGlyphs.IDS:
		var texture := InputGlyphs.texture(id)
		assert_not_null(texture, String(id))
		if texture != null:
			assert_eq(texture.get_height(), InputGlyphs.CAP_HEIGHT, "%s is one cap high" % id)
	assert_null(InputGlyphs.texture(&"unknown"))


func test_mouse_placeholder_marks_the_pressed_button() -> void:
	var left := InputGlyphs.placeholder_image(InputGlyphs.MOUSE_LEFT)
	var right := InputGlyphs.placeholder_image(InputGlyphs.MOUSE_RIGHT)
	assert_eq(left.get_pixel(2, 2), InputGlyphs.COLOR_PRESSED)
	assert_ne(right.get_pixel(2, 2), InputGlyphs.COLOR_PRESSED)
	assert_eq(right.get_pixel(6, 2), InputGlyphs.COLOR_PRESSED)


func test_round_two_ids_escape_and_gamepad() -> void:
	for id: StringName in [&"escape", &"touch_attack", &"touch_interact", &"touch_jump", &"touch_side_dash",
			&"touch_pause", &"touch_menu", &"touch_stick", &"gesture_tap", &"gesture_hold", &"gesture_swipe",
			&"pad_south", &"pad_east", &"pad_west", &"pad_north", &"pad_a", &"pad_b", &"pad_x", &"pad_y",
			&"pad_lb", &"pad_rb", &"pad_lt", &"pad_rt", &"pad_stick_left", &"pad_stick_right", &"pad_dpad",
			&"pad_start", &"pad_select"]:
		assert_true(InputGlyphs.IDS.has(id), "%s is a glyph (SPRITES_V10 §2b)" % id)
	assert_eq(InputGlyphs.id_for_action(&"pause_menu"), InputGlyphs.ESCAPE)
	var south := InputEventJoypadButton.new()
	south.button_index = JOY_BUTTON_A
	assert_eq(InputGlyphs.id_for_event(south), InputGlyphs.PAD_SOUTH)
	var trigger := InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_LEFT
	assert_eq(InputGlyphs.id_for_event(trigger), InputGlyphs.PAD_LT)
	assert_eq(InputGlyphs.touch_id(ControlsInfo.MOVE), InputGlyphs.TOUCH_STICK)
	assert_eq(InputGlyphs.touch_id_for_action(&"dash", true), InputGlyphs.TOUCH_JUMP, "dash is the jump in a side view")
	if not ResourceLoader.exists(InputGlyphs.art_path(InputGlyphs.KEY_CAP_ID)):
		assert_null(InputGlyphs.key_cap_style(2), "drawn caps until input_key_cap.png exists")


# --- GlyphText ---

func test_key_names_in_hint_texts_become_symbols() -> void:
	var text := DungeonTexts.t(&"HINT_CHASM_TEXT", [ControlsInfo.key_text(ControlsInfo.DASH)])
	var parts := GlyphText.split(text)
	assert_true(GlyphText.has_glyphs(parts), text)
	assert_true(parts.has(InputGlyphs.texture(InputGlyphs.SPACE)), "Leertaste as the space symbol")
	assert_false(String(parts[0]).is_empty())
	var label: Control = autofree(GlyphText.wrapped(text, 150.0))
	assert_true(label is RichTextLabel)
	var plain: Control = autofree(GlyphText.wrapped("Ohne Tasten.", 150.0))
	assert_true(plain is Label, "texts without keys stay plain labels")
	assert_false(GlyphText.has_glyphs(GlyphText.split("Mit Q wechseln")), "single letters stay text on a keyboard")
	assert_false(GlyphText.has_glyphs(GlyphText.split("Leertastenwechsel")), "only whole words")


func test_touch_turns_key_names_into_touch_buttons() -> void:
	var state := TouchState.shared()
	var was_forced := state.forced
	state.forced = true
	var parts := GlyphText.split(DungeonTexts.t(&"HINT_CHASM_TEXT", [ControlsInfo.key_text(ControlsInfo.DASH)]))
	state.forced = was_forced
	assert_true(parts.has(InputGlyphs.texture(InputGlyphs.TOUCH_DASH)), "the dash button, never \"Leertaste\"")
	assert_false(parts.has(InputGlyphs.texture(InputGlyphs.SPACE)))


# --- KeyCap ---

func test_key_caps_show_pictures_or_names_at_one_height() -> void:
	var special: KeyCap = autofree(KeyCap.for_action(&"special_attack"))
	var switch: KeyCap = autofree(KeyCap.for_action(&"switch_weapon"))
	assert_true(special.is_glyph(), "right mouse button as a picture")
	assert_eq(special.get_text(), "Rechtsklick", "the name stays reachable")
	assert_false(switch.is_glyph())
	assert_eq(switch.get_text(), "Q")
	assert_eq(special.name, &"Key")
	var height := InputGlyphs.CAP_HEIGHT * KeyCap.HUD_PIXEL
	assert_eq(special.get_combined_minimum_size().y, float(height))
	assert_eq(switch.get_combined_minimum_size().y, float(height))
	var pause: KeyCap = autofree(KeyCap.for_action(&"pause_menu"))
	assert_eq(pause.get_text(), "Esc")


func test_key_cap_texts_follow_the_language() -> void:
	var dash: KeyCap = add_child_autofree(KeyCap.for_action(&"dash"))
	assert_eq(dash.get_text(), "Leertaste")
	TranslationServer.set_locale("en")
	await wait_physics_frames(1)
	assert_eq(dash.get_text(), "Space")


func test_control_rows_hold_every_key() -> void:
	var move: HBoxContainer = autofree(KeyCap.row_for_control(ControlsInfo.MOVE))
	assert_eq(move.get_child_count(), 4, "W A S D")
	var aim: HBoxContainer = autofree(KeyCap.row_for_control(ControlsInfo.AIM))
	assert_eq(aim.get_child_count(), 1)
	assert_eq((aim.get_child(0) as KeyCap).glyph_id, InputGlyphs.MOUSE)


# --- HUD ---

func test_weapon_block_is_compact_and_keeps_all_values() -> void:
	var hud: Hud = add_child_autofree(Hud.new())
	var player: Player = add_child_autofree(PLAYER_SCENE.instantiate())
	player.weapon_controller.equip_weapon(BOW, 1)
	hud.set_dungeon_mode(true)
	hud.bind_player(player)
	await wait_physics_frames(2)
	var block := hud._weapon_root
	# Before G3 the block was about 845 × 90 px at 1280 × 720; at most half the area now.
	assert_lte(block.size.y, 64.0, "two short lines")
	assert_lte(block.size.x * block.size.y, 845.0 * 90.0 * 0.5, "at most half the area")
	assert_false(hud._weapon_stats.text.is_empty(), "values stay")
	var caps := hud._weapon_keys.find_children("Key", "KeyCap", true, false)
	assert_eq(caps.size(), 3, "switch, special and dash")
	var glyphs := 0
	for cap: KeyCap in caps:
		if cap.is_glyph():
			glyphs += 1
	assert_eq(glyphs, 2, "right mouse button and space as pictures")
	assert_string_contains(hud._weapon_hint.text, DataTexts.weapon_name(BOW))


func test_touch_mode_shows_touch_buttons_and_hides_keyboard_hints() -> void:
	var hud: Hud = add_child_autofree(Hud.new())
	var player: Player = add_child_autofree(PLAYER_SCENE.instantiate())
	player.weapon_controller.equip_weapon(BOW, 1)
	hud.set_dungeon_mode(true)
	hud.bind_player(player)
	await wait_physics_frames(1)
	# Checked in the same frame: the HUD follows TouchState again in its next _process.
	hud.set_touch_mode(true)
	assert_false(hud._hint_row.visible, "no keyboard hints on a phone")
	var ids: Array[StringName] = []
	for cap: KeyCap in hud._weapon_keys.find_children("Key", "KeyCap", true, false):
		ids.append(cap.glyph_id)
	assert_eq(ids, [InputGlyphs.TOUCH_SWITCH, InputGlyphs.TOUCH_SPECIAL, InputGlyphs.TOUCH_DASH] as Array[StringName])
	assert_not_null(hud._dash_bar.get_parent(), "the dash cooldown stays")
	hud.set_touch_mode(false)
	assert_true(hud._hint_row.visible)


func test_hint_line_uses_key_caps() -> void:
	var hud: Hud = add_child_autofree(Hud.new())
	hud.set_dungeon_mode(true)
	await wait_physics_frames(1)
	var entries := hud.HINT_ENTRIES_SHORT.size() if SaveManager.has_seen(ControlsHint.SEEN_ID) else hud.HINT_ENTRIES_FULL.size()
	assert_eq(hud._hint_row.get_child_count(), entries)
	assert_gt(hud._hint_row.find_children("Key", "KeyCap", true, false).size(), 0)
	var rect := hud._hint_row.get_global_rect()
	assert_false(rect.intersects(hud._weapon_root.get_global_rect()), "hint line and weapon block never overlap")


## D-185 (#80c94d8c): nobody holds a weapon in the village, so its key line names no weapon keys;
## back in the dungeon the full line has them again.
func test_village_hint_line_has_no_weapon_keys() -> void:
	var village_full := Hud.hint_entries(true, false)
	assert_eq(village_full.size(), Hud.HINT_ENTRIES_FULL.size() - Hud.UNARMED_HIDDEN_HINTS.size())
	for entry: Array in village_full:
		assert_false(Hud.UNARMED_HIDDEN_HINTS.has(entry[0]), "no %s key in the village" % entry[0])
	assert_eq(Hud.hint_entries(true, true).size(), Hud.HINT_ENTRIES_FULL.size())
	assert_eq(Hud.hint_entries(false, false).size(), Hud.HINT_ENTRIES_SHORT.size(), "the short line has no weapon keys anyway")
	var hud: Hud = add_child_autofree(Hud.new())
	await wait_physics_frames(1)
	var full := not SaveManager.has_seen(ControlsHint.SEEN_ID)
	assert_eq(hud._hint_row.get_child_count(), Hud.hint_entries(full, false).size(), "village line")
	hud.set_dungeon_mode(true)
	assert_eq(hud._hint_row.get_child_count(), Hud.hint_entries(full, true).size(), "dungeon line rebuilt")
	hud.set_dungeon_mode(false)
	assert_eq(hud._hint_row.get_child_count(), Hud.hint_entries(full, false).size(), "village line rebuilt")
	# The replaced lines are queue_free'd: let them go before the HUD is freed (no orphans).
	await wait_physics_frames(1)


func test_new_texts_fall_back_per_language() -> void:
	assert_eq(Hud.hud_text(&"HUD_TEST_MISSING_KEY", "pause", "Pause"), "Pause")
	TranslationServer.set_locale("en")
	assert_eq(Hud.hud_text(&"HUD_TEST_MISSING_KEY", "pause", "Pause"), "pause")


func _wipe() -> void:
	var folder := ProjectSettings.globalize_path(ROOT)
	for dir_path in [folder.path_join("saves"), folder]:
		var dir := DirAccess.open(dir_path)
		if dir != null:
			for file in dir.get_files():
				DirAccess.remove_absolute(dir_path.path_join(file))

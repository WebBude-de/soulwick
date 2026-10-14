extends GutTest
## UI1 (UI nach Mockups): central scale, theme built from art/ui/theme.tres, legacy UiKit API,
## Modal keys, dialog defaults, cards, HUD modes and the tool contract of the upgrade cards.

const TEST_SAVE_PATH := "user://test_ui_kit.cfg"

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.load_game()


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


# --- Scale ---

func test_scale_goes_through_one_constant() -> void:
	assert_almost_eq(UiKit.UI_SCALE, 1280.0 / 480.0, 0.0001, "viewport width / mockup width")
	assert_eq(UiKit.ART_SCALE, maxi(1, roundi(UiKit.UI_SCALE)))
	assert_eq(UiKit.px(6.0), roundf(6.0 * UiKit.UI_SCALE))
	assert_eq(UiKit.pxv(480.0, 270.0), Vector2(roundf(480.0 * UiKit.UI_SCALE), roundf(270.0 * UiKit.UI_SCALE)))
	assert_eq(UiKit.font_px(7), roundi(7.0 * UiKit.UI_SCALE))


func test_pixel_art_snaps_to_whole_multiples() -> void:
	for spec_size in [12.0, 16.0, 24.0, 32.0, 48.0]:
		var on_screen := UiKit.art_px(spec_size, 16.0)
		assert_eq(fmod(on_screen, 16.0), 0.0, "%s px icon keeps whole pixels" % spec_size)
		assert_gt(on_screen, 0.0)
	assert_eq(UiKit.art_px(16.0, 16.0), 16.0 * UiKit.ART_SCALE)


# --- Theme ---

func test_theme_uses_pixel_font_and_scaled_nine_patches() -> void:
	var theme := UiKit.get_theme()
	assert_eq(theme.default_font, UiKit.FONT)
	assert_eq(theme.get_font_size("font_size", "Label"), UiKit.font_px(8), "theme.tres 8 px label, scaled")
	var panel := theme.get_stylebox("panel", "PanelContainer") as StyleBoxTexture
	assert_not_null(panel)
	assert_eq(panel.texture_margin_left, float(UiKit.PANEL_BORDER * UiKit.ART_SCALE), "6 px border × ART_SCALE")
	assert_eq(panel.texture.get_width(), 48 * UiKit.ART_SCALE, "nearest-upscaled panel.png")
	assert_eq(theme.get_type_variation_base(&"PanelGold"), &"PanelContainer")
	assert_eq(theme.get_color("font_shadow_color", "Label"), UiKit.COLOR_SHADOW)
	assert_eq(theme.get_constant("shadow_offset_x", "Label"), UiKit.SHADOW_OFFSET)


func test_legacy_api_still_works() -> void:
	var label := UiKit.label("Gold", 18, UiKit.ACCENT_COLOR)
	assert_eq(label.text, "Gold")
	assert_eq(label.get_theme_font_size("font_size"), 18, "legacy sizes stay viewport pixels")
	var wrapped := UiKit.wrapped_label("Text", 200.0)
	assert_eq(wrapped.custom_minimum_size.x, 200.0)
	var pressed := [false]
	var button := UiKit.button("Schließen", func() -> void: pressed[0] = true)
	assert_eq(button.text, "Schließen")
	button.pressed.emit()
	assert_true(pressed[0])
	assert_true(autofree(UiKit.panel(&"dark")) is PanelContainer)
	assert_eq((autofree(UiKit.icon(null, 24.0)) as TextureRect).custom_minimum_size, Vector2(24, 24))
	assert_true(UiKit.panel_style(&"gold") is StyleBoxTexture)
	for node: Node in [label, wrapped, button]:
		node.free()


# --- Modal and dialogs ---

func test_modal_number_keys_and_enter() -> void:
	var modal: Modal = add_child_autofree(Modal.create(&"test_ui_modal"))
	var picked := [0]
	modal.hotkeys[KEY_2] = func() -> void: picked[0] = 2
	modal._unhandled_input(_key(KEY_2))
	assert_eq(picked[0], 2)
	watch_signals(modal)
	modal.accept_allowed = true
	modal.accept_result = &"yes"
	modal._unhandled_input(_key(KEY_ENTER))
	assert_signal_emitted_with_parameters(modal, "finished", [&"yes"])


func test_dialog_default_button_is_enter_and_keeps_texts() -> void:
	var modal: Modal = autofree(UiDialog.create(&"test_ui_dialog", 220.0, "Run beenden?", "Text"))
	var buttons := UiDialog.add_buttons(modal, [
		{"text": "Abbrechen", "sub": "", "result": true},
		{"text": "Weiterspielen", "sub": "Esc", "result": false, "default": true},
	])
	assert_eq(buttons.size(), 2)
	assert_eq(buttons[1].text, "Weiterspielen", "tools press dialog buttons by text")
	assert_true(modal.accept_allowed)
	assert_eq(modal.accept_result, false)
	assert_eq(modal.frame.custom_minimum_size.x, UiKit.px(220.0))


func test_card_ignores_clicks_while_disabled() -> void:
	var card: UiCard = add_child_autofree(UiCard.new())
	watch_signals(card)
	card.disabled = true
	card.activate()
	assert_signal_not_emitted(card, "pressed")
	assert_almost_eq(card.modulate.a, card.disabled_alpha, 0.001)
	card.disabled = false
	card.activate()
	assert_signal_emitted(card, "pressed")


# --- Dungeon UI ---

func test_upgrade_card_keeps_bound_choose_button() -> void:
	var ui: DungeonUI = add_child_autofree(DungeonUI.new())
	ui.auto_enemy_hints = false
	var upgrade: UpgradeData = load("res://upgrades/data/wide_swing.tres")
	var chosen := [null]
	var pick := func(choice: UpgradeData) -> void: chosen[0] = choice
	var card: UiCard = autofree(ui._upgrade_card(upgrade, 0, pick.bind(upgrade)))
	var choose: Button = null
	for button in _buttons(card):
		if button.text == "Wählen":
			choose = button
	assert_not_null(choose, "smoke_test / screenshots press 'Wählen'")
	var bound := false
	for connection in choose.pressed.get_connections():
		if (connection.callable as Callable).get_bound_arguments().has(upgrade):
			bound = true
	assert_true(bound, "balance_sim reads the upgrade from the bound arguments")
	choose.pressed.emit()
	assert_eq(chosen[0], upgrade)


func test_long_banner_subtitle_wraps() -> void:
	var ui: DungeonUI = add_child_autofree(DungeonUI.new())
	ui.auto_enemy_hints = false
	ui.show_banner("Aus dem Dorf", "+2 Max-HP · +20 % Schaden · Bogen · Heiltrank: +2 Max-HP · Schildrune: +3 Schild · noch mehr Text")
	var box := ui._banner_root.get_child(ui._banner_root.get_child_count() - 1)
	var subtitle := box.get_child(1) as Label
	assert_eq(subtitle.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
	assert_eq(subtitle.custom_minimum_size.x, UiKit.px(DungeonUI.BANNER_SUBTITLE_WIDTH))


# --- HUD ---

func test_hud_switches_between_dungeon_and_village() -> void:
	var hud: Hud = add_child_autofree(Hud.new())
	hud.set_dungeon_mode(false)
	assert_true(hud._currency_frame.visible, "village: gold + crystals top right")
	assert_true(hud._chronicle_frame.visible, "village: chronicle bottom left")
	assert_false(hud._status_frame.visible)
	hud.set_dungeon_mode(true)
	assert_true(hud._status_frame.visible)
	assert_true(hud._room_box.visible)
	assert_false(hud._currency_frame.visible)
	hud.set_heal_countdown(3)
	assert_string_contains(hud._room_detail.text, "nächste Heilung in 3")
	hud.set_heal_countdown(-1)
	assert_false(hud._room_detail.text.contains("Heilung"))


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _buttons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	for child in node.get_children():
		if child is Button:
			result.append(child)
		result.append_array(_buttons(child))
	return result

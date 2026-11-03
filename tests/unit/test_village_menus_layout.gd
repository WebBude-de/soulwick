extends GutTest
## FS7a (reports #e0d2989d "Das sieht weird aus. Vom Layout-Format", #f6fe6427 "Man kann das alles
## schlecht lesen", #6bdaa672 / #d1a7f411 "Schließen soll immer sichtbar sein"): the building dialogs
## have a fixed head and foot around a scrolling body, the forge and trade rows line up like a table,
## texts use the mockup sizes, the value step draws its arrow (the pixel font has none), and all of
## it fits 1280×720, the browser's wider view, the square portrait screen and a zoomed touch screen.
## Test save only.

const TEST_PATH := "user://test_village_menus_layout.cfg"
const AffordableScript := preload("res://world/village/village_affordable.gd")
const PixelArrows := preload("res://ui/menus/village/pixel_arrows.gd")
const LevelPips := preload("res://ui/menus/village/level_pips.gd")
const MobileUi := preload("res://ui/menus/mobile_ui.gd")
## Screens of D-182 and the reports: PC, browser (#e0d2989d: 1423×720), portrait (square game
## screen above the pad), and a low window.
const SCREENS := [Vector2i(1280, 720), Vector2i(1423, 720), Vector2i(1280, 1280), Vector2i(1280, 480)]

var _old_path: String


func before_all() -> void:
	OnlineMenu.login_on_open = false
	_old_path = SaveManager.save_path
	GamepadInput.ensure_actions()


func before_each() -> void:
	SaveManager.save_path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	SaveManager.load_game()
	AffordableScript.clear_visits()
	# Everything open and affordable: the fullest dialogs (gold frames, "Leistbar", Arsenal).
	SaveManager.add_stat(StatsTracker.RUNS, 1)
	for event in [MetaUnlocks.EVENT_FIRST_RUN, MetaUnlocks.EVENT_FIRST_CRYSTAL, MetaUnlocks.EVENT_FIRST_BOSS]:
		MetaUnlocks.record_event(event)
	for building in [VillageBuildings.FORGE, VillageBuildings.TRADER, VillageBuildings.CHRONICLE]:
		SaveManager.mark_seen(VillageBuildings.get_intro_key(building))
	SaveManager.add_permanent_gold(100000)
	SaveManager.add_permanent_crystals(40)
	InputDevice.shared().set_kind(InputDevice.Kind.KEYBOARD_MOUSE)


func after_each() -> void:
	MobileUi.touch_override = -1
	MobileUi.zoom_override = 0.0
	GameManager.clear_pause_reasons()
	InputDevice.shared().set_kind(InputDevice.Kind.KEYBOARD_MOUSE)


func after_all() -> void:
	OnlineMenu.login_on_open = true
	AffordableScript.clear_visits()
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + suffix))
	SaveManager.save_path = _old_path
	SaveManager.load_game()


func _ui_in(size: Vector2i) -> VillageUI:
	var viewport := SubViewport.new()
	viewport.size = size
	add_child_autofree(viewport)
	var ui := VillageUI.new()
	viewport.add_child(ui)
	return ui


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _open(ui: VillageUI, building: StringName) -> Modal:
	match building:
		VillageBuildings.FORGE:
			ui.open_forge()
		VillageBuildings.TRADER:
			ui.open_trader()
		VillageBuildings.CHRONICLE:
			ui.open_chronicle()
	await _frames(4)
	return ui.get_building_modal()


func _close(ui: VillageUI) -> void:
	if ui.get_building_modal() != null:
		ui.get_building_modal().finish()
	await _frames(1)


func _rows(modal: Modal, table: String) -> Array[Node]:
	return modal.find_child(table, true, false).get_children()


func _cell(row: Node, prefixes: Array) -> Control:
	for child in row.get_child(0).get_children():
		for prefix: String in prefixes:
			if String(child.name).begins_with(prefix):
				return child as Control
	return null


# --- The arrow of "15 → 16,2" ---

func test_value_steps_draw_their_arrow() -> void:
	var font := PixelArrows.with_arrows(UiKit.get_font())
	assert_true(font.has_char(0x2192), "→ comes from the pixel arrows")
	for code in [0x2190, 0x2191, 0x2193]:
		assert_true(font.has_char(code), "%x too (for the integrator's global fallback)" % code)
	var line := TextLine.new()
	line.add_string("Schaden 15 → 16,2", font, UiKit.font_px(UiKit.SIZE_BODY))
	var glyphs := TextServerManager.get_primary_interface().shaped_text_get_glyphs(line.get_rid())
	var arrow: Dictionary = {}
	for glyph: Dictionary in glyphs:
		if int(glyph.index) == 0x2192:
			arrow = glyph
	assert_false(arrow.is_empty(), "the arrow is a real glyph, not a box")
	assert_true(PixelArrows.fallback().get_rids().has(arrow.get("font_rid")), "drawn with the pixel arrows")


func test_forge_and_trade_steps_use_the_arrow_font() -> void:
	var ui := _ui_in(Vector2i(1280, 720))
	for building: StringName in [VillageBuildings.FORGE, VillageBuildings.TRADER]:
		var modal := await _open(ui, building)
		var steps := modal.find_children("StepLabel", "Label", true, false)
		assert_gt(steps.size(), 2, String(building))
		for node in steps:
			var step := node as Label
			assert_true(step.get_theme_font("font").has_char(0x2192), "%s: %s" % [building, step.text])
		await _close(ui)


func test_level_pips_show_the_level_with_its_text_as_tooltip() -> void:
	var pips := LevelPips.create(2, 5)
	assert_eq(pips.tooltip_text, "Stufe 2/5")
	var image := pips.texture.get_image()
	var step := (LevelPips.PIP + LevelPips.GAP) * UiKit.ART_SCALE
	assert_eq(image.get_width(), step * 5 - LevelPips.GAP * UiKit.ART_SCALE, "five pips")
	var middle := LevelPips.PIP * UiKit.ART_SCALE / 2
	assert_eq(image.get_pixel(middle, middle), LevelPips.FILLED, "first pip gold")
	assert_eq(image.get_pixel(step + middle, middle), LevelPips.FILLED, "second pip gold")
	assert_eq(image.get_pixel(2 * step + middle, middle), LevelPips.EMPTY, "third pip empty")
	pips.free()


# --- Forge: one line per row, a table ---

func test_forge_rows_line_up_like_a_table() -> void:
	var ui := _ui_in(Vector2i(1280, 720))
	var modal := await _open(ui, VillageBuildings.FORGE)
	var rows := _rows(modal, "ForgeRows")
	assert_eq(rows.size(), MetaProgression.WEAPON_ORDER.size() + MetaProgression.EQUIPMENT_UPGRADES.size())
	var columns := {
		"name": ["NameLabel"], "pips": ["LevelPips"], "buy": ["Buy_weapon_", "Buy_second", "Buy_shield", "Buy_lantern"],
		"start": ["Start_", "Buy_arsenal_", "ArsenalLocked_", "NoStartCell"],
	}
	for column: String in columns:
		var first: Control = null
		for row in rows:
			var cell := _cell(row, columns[column])
			assert_not_null(cell, "%s: %s" % [row.name, column])
			if cell == null:
				continue
			if first == null:
				first = cell
				continue
			assert_almost_eq(cell.get_global_rect().position.x, first.get_global_rect().position.x, 0.5, "%s: %s in line" % [row.name, column])
			assert_almost_eq(cell.size.x, first.size.x, 0.5, "%s: %s as wide" % [row.name, column])
	await _close(ui)


func test_row_buttons_keep_off_the_row_frame() -> void:
	var ui := _ui_in(Vector2i(1280, 720))
	var modal := await _open(ui, VillageBuildings.FORGE)
	var keep := UiKit.px(VillageUI.ROW_PADDING.x) - 0.5
	for row in _rows(modal, "ForgeRows"):
		var card := (row as Control).get_global_rect()
		for node in (row as Node).find_children("*", "Button", true, false):
			var button := (node as Control).get_global_rect()
			assert_gte(button.position.y - card.position.y, keep, "%s: room above %s" % [row.name, node.name])
			assert_gte(card.end.y - button.end.y, keep, "%s: room below %s" % [row.name, node.name])
	await _close(ui)


func test_forge_fits_720_without_scrolling() -> void:
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1423, 720)]:
		var ui := _ui_in(size)
		var modal := await _open(ui, VillageBuildings.FORGE)
		gut.p("forge at %s: panel %s" % [size, modal.frame.size])
		assert_false(ui.is_body_scrolling(), "%s: every forge row shows (#0efb405c)" % size)
		assert_false(modal.is_scrolling(), "%s" % size)
		assert_true(Rect2(Vector2.ZERO, Vector2(size)).encloses(modal.get_panel_rect()), "%s: the panel fits" % size)
		await _close(ui)


# --- Readable sizes ---

func test_no_text_in_the_building_dialogs_is_smaller_than_the_small_mockup_size() -> void:
	var smallest := UiKit.font_px(UiKit.SIZE_EYEBROW)
	var ui := _ui_in(Vector2i(1280, 720))
	for building: StringName in [VillageBuildings.FORGE, VillageBuildings.TRADER, VillageBuildings.CHRONICLE]:
		var modal := await _open(ui, building)
		for node in modal.content.find_children("*", "Label", true, false):
			var label := node as Label
			assert_gte(label.get_theme_font_size("font_size"), smallest, "%s: '%s' (#f6fe6427)" % [building, label.text])
		await _close(ui)


func test_forge_names_steps_and_currencies_use_the_mockup_sizes() -> void:
	var ui := _ui_in(Vector2i(1280, 720))
	var modal := await _open(ui, VillageBuildings.FORGE)
	for node in modal.find_children("NameLabel", "Label", true, false):
		assert_eq((node as Label).get_theme_font_size("font_size"), UiKit.font_px(UiKit.SIZE_KEY_HINT))
	for node in modal.find_children("StepLabel", "Label", true, false):
		assert_eq((node as Label).get_theme_font_size("font_size"), UiKit.font_px(UiKit.SIZE_BODY))
	var gold := modal.find_child("GoldLabel", true, false) as Label
	assert_eq(gold.get_theme_font_size("font_size"), UiKit.font_px(UiKit.SIZE_KEY_HINT))
	await _close(ui)


# --- Head and foot fixed, only the body scrolls ---

func test_head_holds_title_and_currencies_with_the_title_centred() -> void:
	var ui := _ui_in(Vector2i(1280, 720))
	var modal := await _open(ui, VillageBuildings.FORGE)
	var header := modal.content.get_node(^"Header") as Control
	assert_not_null(header.find_child("Currencies", false, false), "currencies in the head line")
	var title := header.get_child(1) as Control
	assert_almost_eq(title.get_global_rect().get_center().x, header.get_global_rect().get_center().x, 1.5, "title centred")
	await _close(ui)


func test_close_is_always_on_screen_and_outside_the_scroll_area() -> void:
	for size: Vector2i in SCREENS:
		for building: StringName in [VillageBuildings.FORGE, VillageBuildings.TRADER, VillageBuildings.CHRONICLE]:
			var ui := _ui_in(size)
			var modal := await _open(ui, building)
			var close := modal.find_child("CloseButton", true, false) as Button
			var what := "%s at %s" % [building, size]
			assert_not_null(close, what)
			assert_true(Rect2(Vector2.ZERO, Vector2(size)).grow(0.5).encloses(close.get_global_rect()), "%s: Schließen on screen" % what)
			assert_false(ui.get_body_scroll().is_ancestor_of(close), "%s: outside the body" % what)
			assert_false(modal.is_scrolling(), "%s: the dialog itself never scrolls" % what)
			await _close(ui)


func test_footer_line_shows_only_while_the_body_scrolls() -> void:
	var low := _ui_in(Vector2i(1280, 480))
	var modal := await _open(low, VillageBuildings.TRADER)
	assert_true(low.is_body_scrolling())
	assert_eq((modal.find_child("FooterLine", true, false) as Control).modulate.a, 1.0, "a line marks the scrolling end")
	await _close(low)
	var tall := _ui_in(Vector2i(1280, 1280))
	modal = await _open(tall, VillageBuildings.TRADER)
	assert_false(tall.is_body_scrolling())
	assert_eq((modal.find_child("FooterLine", true, false) as Control).modulate.a, 0.0, "no line when everything shows")
	await _close(tall)


func test_touch_screen_with_zoom_keeps_close_outside_the_scroll() -> void:
	# A phone in landscape: bigger menus and the X; the body gives way, never the whole panel.
	MobileUi.touch_override = 1
	MobileUi.zoom_override = 4.0 / 3.0
	for building: StringName in [VillageBuildings.FORGE, VillageBuildings.TRADER]:
		var ui := _ui_in(Vector2i(1280, 720))
		var modal := await _open(ui, building)
		var close := modal.find_child("CloseButton", true, false) as Button
		assert_false(modal.is_scrolling(), "%s: the column does not scroll" % building)
		assert_true(modal.fits_safe_area(), "%s: panel and X inside the screen" % building)
		assert_true(Rect2(Vector2.ZERO, Vector2(1280, 720)).grow(0.5).encloses(close.get_global_rect()), "%s: Schließen on screen" % building)
		await _close(ui)

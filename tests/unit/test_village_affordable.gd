extends GutTest
## P1-3 "Was kann ich mir leisten?": a "!" over the forge and the trading post while something there
## is affordable (gone after a visit until the currency changes), "Leistbar" / "Noch N Gold" in the
## dialogs, the forge goal after a run until the first purchase, and the dialogs work with a gamepad
## (D-pad/stick move a visible focus, A presses, B closes). Reports 17.10.2026: buying keeps the
## dialog's size (#bf9c698d), the forge fits a 720 px high screen (#0efb405c), every button is a bold
## dialog button (#181dfb78). Uses a test save file only.

const TEST_PATH := "user://test_village_affordable.cfg"
const VILLAGE_SCENE := "res://world/village/village.tscn"
const AffordableScript := preload("res://world/village/village_affordable.gd")
## The new texts until the integrator has them in translations.csv (keys_p1_3_village.json).
const KEYS := {
	"VILLAGE_GOAL_FORGE": ["Grow stronger at the forge", "Stärke dich in der Schmiede"],
	"VILLAGE_UI_AFFORDABLE": ["Affordable", "Leistbar"],
	"VILLAGE_UI_MISSING_GOLD": ["%d more gold", "Noch %d Gold"],
	"VILLAGE_UI_MISSING_CRYSTAL": ["%d more crystal", "Noch %d Kristall"],
	"VILLAGE_UI_MISSING_CRYSTALS": ["%d more crystals", "Noch %d Kristalle"],
}

var _old_locale: String
var _old_path: String
var _translations: Array[Translation] = []


func before_all() -> void:
	OnlineMenu.login_on_open = false
	_old_locale = TranslationServer.get_locale()
	Loc.apply(&"de")
	for column in [0, 1]:
		var translation := Translation.new()
		translation.locale = "en" if column == 0 else "de"
		for key: String in KEYS:
			if not Loc.has_key(StringName(key), StringName(translation.locale)):
				translation.add_message(key, KEYS[key][column])
		TranslationServer.add_translation(translation)
		_translations.append(translation)
	_old_path = SaveManager.save_path
	# A = ui_accept, B = ui_cancel like in the game (the player's input adds them at runtime).
	GamepadInput.ensure_actions()


func before_each() -> void:
	SaveManager.save_path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	SaveManager.load_game()
	AffordableScript.clear_visits()
	InputDevice.shared().set_kind(InputDevice.Kind.KEYBOARD_MOUSE)


func after_each() -> void:
	GameManager.clear_pause_reasons()
	InputDevice.shared().set_kind(InputDevice.Kind.KEYBOARD_MOUSE)


func after_all() -> void:
	OnlineMenu.login_on_open = true
	for translation in _translations:
		TranslationServer.remove_translation(translation)
	TranslationServer.set_locale(_old_locale)
	AffordableScript.clear_visits()
	for suffix in ["", ".bak", ".tmp", ".v2.bak", ".v3.bak", ".v4.bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + suffix))
	SaveManager.save_path = _old_path
	SaveManager.load_game()


func _village() -> Village:
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	add_child_autofree(village)
	return village


## After the first run: the chronicle is open, the forge has explained itself.
func _after_first_run(gold: int) -> void:
	SaveManager.add_stat(StatsTracker.RUNS, 1)
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_RUN)
	SaveManager.mark_seen(VillageBuildings.get_intro_key(VillageBuildings.FORGE))
	SaveManager.mark_seen(VillageBuildings.get_intro_key(VillageBuildings.TRADER))
	SaveManager.add_permanent_gold(gold)


## Every Arsenal entry and the second start slot bought (the fullest weapon rows).
func _unlock_all_weapons() -> void:
	for id in MetaProgression.ARSENAL_UPGRADES:
		SaveManager.set_meta_level(id, 1)
	SaveManager.set_meta_level(MetaProgression.SECOND_SLOT, 1)


func _cheapest_forge_cost() -> int:
	var cheapest := 1 << 30
	for id in MetaUnlocks.get_open_upgrades():
		cheapest = mini(cheapest, MetaProgression.get_next_cost(id))
	return cheapest


func _labels(node: Node) -> Array[String]:
	var texts: Array[String] = []
	for label in node.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	return texts


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	get_viewport().push_input(event)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	get_viewport().push_input(release)


# --- Rules (VillageAffordable) ---

func test_nothing_affordable_without_gold() -> void:
	_after_first_run(5)
	assert_true(AffordableScript.affordable_items(VillageBuildings.FORGE).is_empty())
	assert_false(AffordableScript.needs_marker(VillageBuildings.FORGE))
	assert_false(AffordableScript.needs_forge_goal())
	var cost := MetaProgression.get_next_cost(MetaProgression.SHIELD_PLATE)
	assert_eq(AffordableScript.gold_missing(MetaProgression.SHIELD_PLATE), cost - 5, "Noch N Gold")


func test_locked_buildings_and_upgrades_never_count() -> void:
	_after_first_run(10000)
	SaveManager.add_permanent_crystals(5)
	var items := AffordableScript.affordable_items(VillageBuildings.FORGE)
	assert_has(items, MetaProgression.SHIELD_PLATE)
	assert_does_not_have(items, MetaProgression.ARSENAL_BOW, "locked until the first boss (D-087)")
	assert_true(AffordableScript.affordable_items(VillageBuildings.TRADER).is_empty(), "trading post still locked")
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_CRYSTAL)
	# KE5: every Proviant and the trade levels the crystals pay.
	var trades := MetaProgression.TRADE_ORDER.filter(func(id: StringName) -> bool: return MetaProgression.can_buy_trade(id)).size()
	assert_eq(AffordableScript.affordable_items(VillageBuildings.TRADER).size(), MetaProgression.BOOST_ORDER.size() + trades)
	assert_true(AffordableScript.affordable_items(VillageBuildings.CHRONICLE).is_empty(), "nothing to buy there")


func test_a_visit_hides_the_marker_until_the_currency_changes() -> void:
	_after_first_run(_cheapest_forge_cost())
	assert_true(AffordableScript.needs_marker(VillageBuildings.FORGE))
	AffordableScript.mark_visited(VillageBuildings.FORGE)
	assert_false(AffordableScript.needs_marker(VillageBuildings.FORGE), "seen")
	SaveManager.add_permanent_crystals(3)
	assert_false(AffordableScript.needs_marker(VillageBuildings.FORGE), "crystals are not the forge's currency")
	SaveManager.add_permanent_gold(7)
	assert_true(AffordableScript.needs_marker(VillageBuildings.FORGE), "more gold: back again")


func test_visits_belong_to_one_world() -> void:
	_after_first_run(_cheapest_forge_cost())
	AffordableScript.mark_visited(VillageBuildings.FORGE)
	SaveManager.save_path = TEST_PATH + ".other.cfg"
	assert_true(AffordableScript.needs_marker(VillageBuildings.FORGE), "another save file has its own visits")
	SaveManager.save_path = TEST_PATH


func test_forge_goal_only_after_a_run_and_until_the_first_purchase() -> void:
	SaveManager.add_permanent_gold(10000)
	assert_false(AffordableScript.needs_forge_goal(), "before the first run the dungeon is the goal")
	SaveManager.add_stat(StatsTracker.RUNS, 1)
	assert_true(AffordableScript.needs_forge_goal())
	assert_true(MetaProgression.try_buy(MetaProgression.SHIELD_PLATE))
	assert_false(AffordableScript.needs_forge_goal(), "first purchase done")


# --- Village: "!" and goal line ---

func test_village_marks_the_forge_and_shows_the_goal() -> void:
	_after_first_run(_cheapest_forge_cost())
	var village := _village()
	assert_true(village.has_afford_marker(VillageBuildings.FORGE), "! over the forge")
	assert_false(village.has_afford_marker(VillageBuildings.TRADER), "trading post locked")
	var marker := village.get_afford_marker(VillageBuildings.FORGE)
	var layer := marker.get_parent() as CanvasLayer
	assert_not_null(layer, "on a layer of its own")
	assert_gt(layer.layer, 2, "above the darkness (VisionOverlay)")
	assert_true(layer.follow_viewport_enabled, "moves with the world")
	assert_eq(village.get_goal_kind(), Village.GOAL_FORGE)
	var goal_text := village.ui.get_goal().find_child("GoalText", true, false) as Label
	assert_eq(goal_text.text, "VILLAGE_GOAL_FORGE", "the key: the label translates itself")
	assert_eq(Loc.t(Village.GOAL_FORGE), "Stärke dich in der Schmiede")


func test_marker_pulses() -> void:
	_after_first_run(_cheapest_forge_cost())
	var village := _village()
	var marker := village.get_afford_marker(VillageBuildings.FORGE)
	var seen: Array[float] = []
	for i in 12:
		await wait_physics_frames(3)
		seen.append(marker.call(&"get_pulse"))
	assert_gt(seen.max() - seen.min(), 0.02, "the ! pulses softly")
	assert_not_null(marker.call(&"get_texture"), "badge art (drawn in code until the file exists)")


func test_no_marker_and_no_forge_goal_when_poor_or_before_the_first_run() -> void:
	_after_first_run(3)
	var village := _village()
	assert_false(village.has_afford_marker(VillageBuildings.FORGE))
	assert_eq(village.get_goal_kind(), &"")
	assert_null(village.ui.get_goal())


func test_first_run_keeps_the_descend_goal() -> void:
	SaveManager.add_permanent_gold(10000)
	var village := _village()
	assert_true(village.has_afford_marker(VillageBuildings.FORGE), "the forge is marked anyway")
	assert_eq(village.get_goal_kind(), Village.GOAL_DESCEND, "the way down first")


func test_visit_hides_the_marker_and_buying_ends_the_goal() -> void:
	_after_first_run(_cheapest_forge_cost())
	var village := _village()
	village.enter_building(VillageBuildings.FORGE)
	var modal := village.ui.get_building_modal()
	assert_not_null(modal)
	var cheapest: StringName = AffordableScript.affordable_items(VillageBuildings.FORGE)[0]
	assert_true(MetaProgression.try_buy(cheapest))
	assert_eq(village.get_goal_kind(), &"", "goal gone after the first purchase")
	assert_null(village.ui.get_goal())
	modal.finish()
	await wait_physics_frames(2)
	assert_false(village.has_afford_marker(VillageBuildings.FORGE), "visited (and nothing affordable)")
	SaveManager.add_permanent_gold(10000)
	assert_true(village.has_afford_marker(VillageBuildings.FORGE), "new gold: the ! is back")
	assert_eq(village.get_goal_kind(), &"", "the goal stays gone")


func test_visit_without_buying_hides_the_marker_but_keeps_the_goal() -> void:
	_after_first_run(_cheapest_forge_cost())
	var village := _village()
	village.enter_building(VillageBuildings.FORGE)
	village.ui.get_building_modal().finish()
	await wait_physics_frames(2)
	assert_false(village.has_afford_marker(VillageBuildings.FORGE))
	assert_eq(village.get_goal_kind(), Village.GOAL_FORGE, "until the first purchase")
	var again := _village()
	assert_false(again.has_afford_marker(VillageBuildings.FORGE), "same gold after a reload: still seen")


func test_trader_marker_with_crystals() -> void:
	_after_first_run(0)
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_CRYSTAL)
	SaveManager.add_permanent_crystals(MetaProgression.get_boost_price(MetaProgression.BOOST_CLEAR_SIGHT))
	var village := _village()
	assert_true(village.has_afford_marker(VillageBuildings.TRADER), "the cheapest Proviant (2 crystals, KE5)")
	assert_false(village.has_afford_marker(VillageBuildings.FORGE))


func test_marker_moves_beside_the_info_marker() -> void:
	SaveManager.add_stat(StatsTracker.RUNS, 1)
	SaveManager.add_permanent_gold(10000)
	var village := _village()
	assert_true(village.has_intro_marker(VillageBuildings.FORGE), "forge not explained yet")
	var beside := village.get_afford_marker(VillageBuildings.FORGE).global_position
	SaveManager.mark_seen(VillageBuildings.get_intro_key(VillageBuildings.FORGE))
	var over := village.get_afford_marker(VillageBuildings.FORGE).global_position
	assert_almost_eq(beside.x - over.x, Village.AFFORD_BESIDE_INFO.x, 0.1, "back over the sign")


# --- Dialogs: Leistbar / Noch N Gold ---

func test_forge_cards_say_affordable_or_missing() -> void:
	var cost := MetaProgression.get_next_cost(MetaProgression.SHIELD_PLATE)
	_after_first_run(cost)
	var ui := VillageUI.new()
	add_child_autofree(ui)
	ui.open_forge()
	var modal := ui.get_building_modal()
	var vitality := modal.find_child("Buy_%s" % MetaProgression.SHIELD_PLATE, true, false) as Button
	assert_not_null(vitality)
	assert_false(vitality.disabled)
	var card := vitality.get_parent()
	assert_not_null(card.find_child("AffordableTag", true, false), "Leistbar")
	assert_eq((card.find_child("AffordableTag", true, false) as Label).text, "Leistbar")
	var frame := (card.get_parent() as PanelContainer).get_theme_stylebox("panel") as StyleBoxTexture
	assert_eq(frame.texture, UiKit.panel_style(&"gold").texture, "gold frame")
	var sharpness := modal.find_child("Buy_%s" % MetaProgression.SMITH_SWORD, true, false) as Button
	var missing := sharpness.get_parent().find_child("MissingLabel", true, false) as Label
	assert_not_null(missing, "not affordable: what is missing")
	var expected := MetaProgression.get_next_cost(MetaProgression.SMITH_SWORD) - cost
	assert_eq(missing.text, "Noch %d Gold" % expected)
	assert_null(sharpness.get_parent().find_child("AffordableTag", true, false))
	modal.finish()


func test_maxed_upgrade_has_no_line() -> void:
	_after_first_run(0)
	SaveManager.set_meta_level(MetaProgression.SHIELD_PLATE, MetaProgression.get_max_level(MetaProgression.SHIELD_PLATE))
	var ui := VillageUI.new()
	add_child_autofree(ui)
	ui.open_forge()
	var shield := ui.get_building_modal().find_child("Buy_%s" % MetaProgression.SHIELD_PLATE, true, false) as Button
	assert_null(shield.get_parent().find_child("MissingLabel", true, false))
	assert_null(shield.get_parent().find_child("AffordableTag", true, false))
	ui.get_building_modal().finish()


func test_trader_cards_say_affordable_or_missing() -> void:
	_after_first_run(0)
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_CRYSTAL)
	SaveManager.add_permanent_crystals(MetaProgression.get_boost_price(MetaProgression.BOOST_HEALING_POTION))
	var ui := VillageUI.new()
	add_child_autofree(ui)
	ui.open_trader()
	var modal := ui.get_building_modal()
	var potion := modal.find_child("Boost_%s" % MetaProgression.BOOST_HEALING_POTION, true, false) as Button
	assert_not_null(potion.get_parent().find_child("AffordableTag", true, false))
	var upgrade := modal.find_child("Boost_%s" % MetaProgression.BOOST_LUCKY_AMULET, true, false) as Button
	var missing := upgrade.get_parent().find_child("MissingLabel", true, false) as Label
	assert_not_null(missing)
	assert_eq(missing.text, "Noch 1 Kristall")
	modal.finish()


# --- Size of the dialogs (reports 17.10.2026) ---

## Every building open, every upgrade seen (like the reports).
func _all_open(gold: int, crystals := 0) -> void:
	_after_first_run(gold)
	SaveManager.add_permanent_crystals(crystals)
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_CRYSTAL)
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_BOSS)


func _frame_size(modal: Modal) -> Vector2:
	return modal.frame.get_combined_minimum_size()


func test_trader_keeps_its_size_after_buying() -> void:
	_all_open(0, 40)
	var ui := VillageUI.new()
	add_child_autofree(ui)
	ui.open_trader()
	await _frames(2)
	var modal := ui.get_building_modal()
	var before := _frame_size(modal)
	# KE5: three Proviant slots at most; the trade level itself is bought in the dialog too.
	for i in MetaProgression.get_trade_max_level(MetaProgression.TRADE_PROVISION_SLOT):
		assert_true(MetaProgression.try_buy_trade(MetaProgression.TRADE_PROVISION_SLOT))
		ui._request_refresh()
		await _frames(2)
		assert_eq(_frame_size(modal), before, "same size after a Proviant slot (#bf9c698d)")
	for id in MetaProgression.BOOST_ORDER.slice(0, MetaProgression.get_provision_slots()):
		assert_true(MetaProgression.try_buy_boost(id))
		ui._request_refresh()
		await _frames(2)
		assert_eq(_frame_size(modal), before, "same size after buying %s (#bf9c698d)" % id)
	var full := modal.find_child("Boost_%s" % MetaProgression.BOOST_ORDER[-1], true, false) as Button
	assert_true(full.disabled, "every slot is packed")
	assert_not_null(full.get_parent().find_child("SlotsFullLabel", true, false), "says why")
	var packed := modal.find_child("Boost_%s" % MetaProgression.BOOST_ORDER[0], true, false) as Button
	assert_eq(packed.text, Loc.t(&"VILLAGE_UI_PACKED"))
	assert_not_null(packed.get_parent().find_child("AffordSpacer", true, false), "an invisible line keeps the height")
	modal.finish()


func test_affordable_and_poor_cards_are_equally_large() -> void:
	_all_open(MetaProgression.get_next_cost(MetaProgression.SHIELD_PLATE))
	var ui := VillageUI.new()
	add_child_autofree(ui)
	ui.open_forge()
	await _frames(2)
	var modal := ui.get_building_modal()
	var gold_card := modal.find_child("Buy_%s" % MetaProgression.SHIELD_PLATE, true, false).get_parent().get_parent() as Control
	var dark_card := modal.find_child("Buy_%s" % MetaProgression.SMITH_SWORD, true, false).get_parent().get_parent() as Control
	var gold_style := gold_card.get_theme_stylebox("panel")
	var dark_style := dark_card.get_theme_stylebox("panel")
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		assert_eq(gold_style.get_margin(side), dark_style.get_margin(side), "same padding, only the colour differs")
	var before := _frame_size(modal)
	assert_true(MetaProgression.try_buy(MetaProgression.SHIELD_PLATE))
	ui._request_refresh()
	await _frames(2)
	assert_eq(_frame_size(modal), before, "no longer affordable: same size")
	modal.finish()


func test_forge_keeps_its_size_up_to_max() -> void:
	_all_open(100000)
	var ui := VillageUI.new()
	add_child_autofree(ui)
	ui.open_forge()
	await _frames(2)
	var modal := ui.get_building_modal()
	var before := _frame_size(modal)
	var id := MetaProgression.SHIELD_PLATE
	while MetaProgression.can_buy(id):
		assert_true(MetaProgression.try_buy(id))
		ui._request_refresh()
		await _frames(2)
		assert_gte(_frame_size(modal).y, before.y, "never lower after a purchase")
		assert_gte(_frame_size(modal).x, before.x, "never narrower after a purchase")
	assert_eq((modal.find_child("Buy_%s" % id, true, false) as Button).text, "Max.")
	modal.finish()


func test_forge_fits_a_720_px_screen_without_scrolling() -> void:
	# The fullest forge: every upgrade affordable (gold frames, "Leistbar") and the weapon choice.
	_all_open(100000)
	_unlock_all_weapons()
	var ui := VillageUI.new()
	add_child_autofree(ui)
	ui.open_forge()
	await _frames(3)
	var modal := ui.get_building_modal()
	assert_not_null(modal.find_child("Start_%s" % MetaProgression.WEAPON_STAFF, true, false), "with the weapon choice")
	gut.p("forge: %s" % _frame_size(modal))
	assert_lte(_frame_size(modal).y, 700.0, "fits 720 px with room to spare (#0efb405c)")
	assert_false(modal.is_scrolling())
	modal.finish()


func test_every_dialog_button_is_a_bold_dialog_button() -> void:
	_all_open(100000, 30)
	_unlock_all_weapons()
	var ui := VillageUI.new()
	add_child_autofree(ui)
	for open: Callable in [ui.open_forge, ui.open_trader]:
		open.call()
		await _frames(2)
		var modal := ui.get_building_modal()
		var buttons := modal.content.find_children("*", "Button", true, false)
		assert_gt(buttons.size(), 3)
		for node in buttons:
			var button := node as Button
			if button.name == &"InfoButton":
				continue
			assert_eq(button.get_theme_font("font"), UiKit.bold_font(), "%s bold (#181dfb78)" % button.name)
			assert_eq(button.get_theme_font_size("font_size"), UiKit.font_px(UiKit.SIZE_KEY_HINT), "%s in the dialog size" % button.name)
		modal.finish()
		await _frames(2)


# --- Gamepad ---

## The dialogs pause the tree: wait on SceneTree frames (they tick while paused).
func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## No input guard in the tests (it only swallows keys right after opening).
func _unguard(ui: VillageUI) -> void:
	var modal := ui.get_building_modal()
	if modal != null:
		modal.input_guard = 0.0


func test_gamepad_focus_starts_on_an_affordable_entry_and_a_buys() -> void:
	_after_first_run(MetaProgression.get_next_cost(MetaProgression.SHIELD_PLATE))
	InputDevice.shared().set_kind(InputDevice.Kind.GAMEPAD)
	var ui := VillageUI.new()
	add_child_autofree(ui)
	ui.open_forge()
	await _frames(2)
	var focused := ui.get_focused_button()
	assert_not_null(focused, "the gamepad has a focus right away")
	assert_eq(String(focused.name), "Buy_%s" % MetaProgression.SHIELD_PLATE, "the affordable entry")
	assert_eq(focused.focus_mode, Control.FOCUS_ALL)
	assert_true(focused.get_theme_stylebox("focus") is StyleBoxFlat, "a visible focus frame")
	# Wait for the input guard of the dialog, then A (ui_accept) presses the focused button.
	_unguard(ui)
	_press(&"ui_accept")
	await _frames(3)
	assert_eq(MetaProgression.get_level(MetaProgression.SHIELD_PLATE), 1, "bought with A")
	var after := ui.get_focused_button()
	assert_not_null(after, "the focus survives the rebuild")
	if after != null:
		assert_eq(String(after.name), "Buy_%s" % MetaProgression.SHIELD_PLATE, "on the same entry")
	ui.get_building_modal().finish()


func test_dpad_moves_the_focus_and_b_closes() -> void:
	_after_first_run(10000)
	InputDevice.shared().set_kind(InputDevice.Kind.GAMEPAD)
	var ui := VillageUI.new()
	add_child_autofree(ui)
	ui.open_forge()
	_unguard(ui)
	var first := ui.get_focused_button()
	assert_not_null(first)
	_press(&"ui_right")
	await _frames(2)
	var second := ui.get_focused_button()
	assert_not_null(second)
	assert_ne(second, first, "the D-pad moves to the next card")
	# KE4: one row per weapon and equipment; down walks the rows and ends on Schließen.
	for i in 12:
		if ui.get_focused_button() != null and ui.get_focused_button().name == &"CloseButton":
			break
		_press(&"ui_down")
		await _frames(2)
	assert_eq(String(ui.get_focused_button().name), "CloseButton", "down reaches Schließen")
	_press(&"ui_cancel")
	await _frames(2)
	assert_null(ui.get_building_modal(), "B closes")
	assert_false(ui.is_dialog_open())


func test_keyboard_gets_the_focus_with_the_first_arrow() -> void:
	_after_first_run(10000)
	var ui := VillageUI.new()
	add_child_autofree(ui)
	ui.open_forge()
	await _frames(2)
	assert_null(ui.get_focused_button(), "mouse players see no focus frame at first")
	_unguard(ui)
	var key := MenuInput.key_event(KEY_DOWN)
	get_viewport().push_input(key)
	await _frames(2)
	assert_not_null(ui.get_focused_button(), "the first arrow puts the focus on an entry")
	ui.get_building_modal().finish()


func test_chronicle_with_gamepad_focuses_close() -> void:
	_after_first_run(0)
	SaveManager.mark_seen(VillageBuildings.get_intro_key(VillageBuildings.CHRONICLE))
	InputDevice.shared().set_kind(InputDevice.Kind.GAMEPAD)
	var ui := VillageUI.new()
	add_child_autofree(ui)
	ui.open_chronicle()
	await _frames(2)
	assert_eq(String(ui.get_focused_button().name), "CloseButton")
	_unguard(ui)
	_press(&"ui_accept")
	await _frames(2)
	assert_null(ui.get_building_modal(), "A on Schließen closes")


# --- Old saves ---

func test_old_v2_save_loads_and_marks_what_is_affordable() -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("[meta]\nversion=2\n[progress]\npermanent_gold=500\n[stats]\nruns=6\n[meta_upgrades]\nvitality=0\n")
	file.close()
	assert_eq(SaveManager.load_game(), OK)
	var village := _village()
	assert_true(village.has_afford_marker(VillageBuildings.FORGE))
	assert_eq(village.get_goal_kind(), Village.GOAL_FORGE, "nothing bought yet")
	file = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("[meta]\nversion=2\n[progress]\npermanent_gold=500\n[stats]\nruns=6\n[meta_upgrades]\nstart_shield=3\n")
	file.close()
	assert_eq(SaveManager.load_game(), OK)
	var again := _village()
	assert_eq(again.get_goal_kind(), &"", "bought before (Startschild -> Schildplatte, KE4): no forge goal")

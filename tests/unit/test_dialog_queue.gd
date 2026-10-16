extends GutTest
## Modal dialogs of the dungeon run one after another (bug from the play test: the bonus chest and
## the upgrade choice after the room opened inside each other). A dialog requested while another
## is open waits in DungeonUI's queue, appears DIALOG_GAP after the first one closed and ignores
## keys and clicks for Modal.INPUT_GUARD, so a quick second press never picks in it. A time limit
## (group games) starts when the dialog appears, not while it waits.
## Uses a test save, never the real one.

const TEST_SAVE_PATH := "user://test_dialog_queue.cfg"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

var _old_save_path: String
var _upgrades: UpgradeManager


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.load_game()


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	GameManager.clear_pause_reasons()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()
	GameManager.clear_pause_reasons()
	_upgrades = autofree(UpgradeManager.new())
	for path in DirAccess.get_files_at("res://upgrades/data/"):
		if path.ends_with(".tres"):
			_upgrades.upgrade_pool.append(load("res://upgrades/data/" + path))


func after_each() -> void:
	GameManager.clear_pause_reasons()


func _upgrade(id: StringName) -> UpgradeData:
	for upgrade in _upgrades.upgrade_pool:
		if upgrade.id == id:
			return upgrade
	return null


func _offer(ids: Array) -> Array[UpgradeData]:
	var offer: Array[UpgradeData] = []
	for id: StringName in ids:
		var upgrade := _upgrade(id)
		assert_not_null(upgrade, "upgrade %s exists" % id)
		offer.append(upgrade)
	return offer


func _ui() -> DungeonUI:
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 7
	context.upgrade_manager = _upgrades
	context.player = add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	var ui: DungeonUI = add_child_autofree(DungeonUI.new())
	ui.auto_enemy_hints = false
	ui.show_controls_hint = false
	ui.context = context
	context.ui = ui
	return ui


func _modals(root: Node) -> Array[Modal]:
	var found: Array[Modal] = []
	for node in root.find_children("*", "Modal", true, false):
		if not node.is_queued_for_deletion():
			found.append(node as Modal)
	return found


func _title(modal: Modal) -> String:
	var label := modal.find_child("Title", true, false) as Label
	return label.text if label != null else ""


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _click(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	return event


## Real seconds in physics frames: the dialogs pause the tree, GUT's wait_seconds would stand still.
func _wait_real(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await wait_physics_frames(1)


## Waits (real time, at most max_seconds) until condition holds.
func _wait_for(condition: Callable, max_seconds := 2.0) -> void:
	var until := Time.get_ticks_msec() + int(max_seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < until:
		await wait_physics_frames(1)


## Waits until the queue has shown its next dialog.
func _wait_for_dialog(ui: DungeonUI) -> Modal:
	await _wait_for(func() -> bool: return _modals(ui).size() == 1)
	var modals := _modals(ui)
	return modals[0] if modals.size() == 1 else null


func test_chest_and_upgrade_choice_requested_together_open_one_after_another() -> void:
	var ui := _ui()
	var chest_offer := _offer([&"strong_attack", &"wide_swing"])
	var room_offer := _offer([&"pierce", &"explosive_hit", &"shield_on_kill"])
	var results: Array = [null, null]
	var chest := func() -> void: results[0] = await ui.choose_upgrade(chest_offer, "Truhe")
	var room := func() -> void: results[1] = await ui.choose_upgrade(room_offer, "Kampf gewonnen!")
	chest.call()
	room.call()
	await wait_physics_frames(2)
	var open := _modals(ui)
	assert_eq(open.size(), 1, "only one dialog on screen")
	assert_eq(_title(open[0]), "Truhe", "the first requested comes first")
	assert_eq(ui.get_dialog_queue_size(), 1, "the upgrade choice waits")
	assert_true(GameManager.is_game_paused())
	# Pick in the chest by key once its guard is over.
	await _wait_real(Modal.INPUT_GUARD + 0.05)
	open[0]._unhandled_input(_key(KEY_2))
	assert_eq(results[0], chest_offer[1], "the chest pick counts")
	await wait_physics_frames(2)
	assert_eq(_modals(ui).size(), 0, "a short pause before the next dialog")
	assert_true(GameManager.is_game_paused(), "the world stays held between the two dialogs")
	assert_null(results[1])
	var second := await _wait_for_dialog(ui)
	assert_not_null(second, "the upgrade choice follows")
	if second == null:
		return
	assert_eq(_title(second), "Kampf gewonnen!")
	assert_eq(ui.get_dialog_queue_size(), 0)
	# The same key pressed again right away does not slip through into the second dialog.
	assert_true(second.is_input_guarded(), "input guard after opening")
	second._unhandled_input(_key(KEY_1))
	await wait_physics_frames(1)
	assert_null(results[1], "no pick while the guard runs")
	assert_eq(_modals(ui).size(), 1)
	await _wait_real(Modal.INPUT_GUARD + 0.05)
	second._unhandled_input(_key(KEY_3))
	assert_eq(results[1], room_offer[2], "after the guard the key picks")
	await wait_physics_frames(2)
	assert_eq(_modals(ui).size(), 0)
	assert_false(GameManager.is_game_paused(), "all pauses released")


func test_a_click_on_a_just_opened_dialog_does_not_pick() -> void:
	var ui := _ui()
	var offer := _offer([&"strong_attack", &"wide_swing"])
	var result: Array = [null]
	var ask := func() -> void: result[0] = await ui.choose_upgrade(offer, "Truhe")
	ask.call()
	await wait_physics_frames(2)
	var modal := _modals(ui)[0]
	var blocker := modal.get_node_or_null(^"InputGuard") as Control
	assert_not_null(blocker, "a catcher lies over the dialog while the guard runs")
	if blocker != null:
		assert_eq(modal.get_child(modal.get_child_count() - 1), blocker, "on top of the cards")
		assert_eq(blocker.mouse_filter, Control.MOUSE_FILTER_STOP)
	var card := modal.find_child("Upgrade1", true, false) as UiCard
	# Window coordinates: push_input applies the stretch transform of the root viewport.
	var at := get_viewport().get_final_transform() * card.get_global_rect().get_center()
	get_viewport().push_input(_click(at, true))
	get_viewport().push_input(_click(at, false))
	await wait_physics_frames(2)
	assert_null(result[0], "a click during the guard does not pick")
	await _wait_real(Modal.INPUT_GUARD + 0.05)
	await wait_physics_frames(1)
	assert_null(modal.get_node_or_null(^"InputGuard"), "the catcher is gone after the guard")
	get_viewport().push_input(_click(at, true))
	get_viewport().push_input(_click(at, false))
	await wait_physics_frames(2)
	assert_eq(result[0], offer[0], "a click that begins after the guard picks")


func test_a_dialog_requested_alone_opens_at_once() -> void:
	var ui := _ui()
	ui.confirm("Dungeon verlassen?", "Text")
	assert_eq(_modals(ui).size(), 1, "nothing open: no waiting")
	assert_eq(ui.get_dialog_queue_size(), 0)
	_modals(ui)[0].finish(false)
	await wait_physics_frames(1)
	assert_false(ui.is_dialog_busy())


func test_weapon_slot_from_the_shop_goes_on_top() -> void:
	var ui := _ui()
	var staff: WeaponData = load("res://weapons/data/staff.tres")
	ui.confirm("Dungeon verlassen?", "Text")
	var result: Array = [-2]
	var ask := func() -> void: result[0] = await ui.choose_weapon_slot(staff, ui.context.player, true)
	ask.call()
	assert_eq(_modals(ui).size(), 2, "a dialog opened from inside the open one is not queued")
	assert_eq(ui.get_dialog_queue_size(), 0)
	_modals(ui)[1].finish(1)
	assert_eq(result[0], 1)
	# Without the flag it waits for the open dialog.
	ui.choose_weapon_slot(staff, ui.context.player)
	assert_eq(_modals(ui).size(), 1)
	assert_eq(ui.get_dialog_queue_size(), 1)
	_modals(ui)[0].finish(false)
	var next := await _wait_for_dialog(ui)
	assert_not_null(next, "the weapon slot dialog follows")
	if next != null:
		next.finish(-1)
	await wait_physics_frames(2)
	assert_false(GameManager.is_game_paused())


func test_time_limit_starts_when_the_dialog_appears() -> void:
	var ui := _ui()
	ui.dialog_gap = 0.05
	var chest_offer := _offer([&"strong_attack", &"wide_swing"])
	var room_offer := _offer([&"pierce", &"explosive_hit"])
	var results: Array = [null, null]
	var chest := func() -> void: results[0] = await ui.choose_upgrade(chest_offer, "Truhe")
	var room := func() -> void: results[1] = await ui.choose_upgrade(room_offer, "Kampf gewonnen!", 1, 0.5)
	chest.call()
	room.call()
	# The chest stays open longer than the time limit of the waiting choice.
	await _wait_real(0.8)
	assert_null(results[1], "the waiting choice is not taken while it waits")
	assert_eq(ui.get_dialog_queue_size(), 1)
	_modals(ui)[0].finish(chest_offer[0])
	var second := await _wait_for_dialog(ui)
	assert_not_null(second)
	await _wait_real(0.25)
	assert_null(results[1], "the clock started when the dialog appeared")
	await _wait_for(func() -> bool: return results[1] != null, 1.0)
	assert_eq(results[1], room_offer[0], "time up: the first card is taken")
	assert_eq(results[0], chest_offer[0])


func test_a_pick_meant_for_another_dialog_is_ignored() -> void:
	var ui := _ui()
	var chest_offer := _offer([&"strong_attack", &"wide_swing"])
	var room_offer := _offer([&"pierce", &"explosive_hit"])
	var result: Array = [null]
	var chest := func() -> void: result[0] = await ui.choose_upgrade(chest_offer, "Truhe")
	chest.call()
	ui.choose_upgrade(room_offer, "Kampf gewonnen!")
	# NetDungeon's old timer finishes every open upgrade choice with its own first card.
	for modal in _modals(ui):
		if modal.pause_reason == GameManager.PAUSE_UPGRADE_CHOICE:
			modal.finish(room_offer[0])
	await wait_physics_frames(1)
	assert_null(result[0], "the chest does not take an upgrade of the other offer")
	assert_eq(_modals(ui).size(), 1)
	assert_eq(_title(_modals(ui)[0]), "Truhe")


func test_upgrade_choice_waits_for_the_pause_menu() -> void:
	var ui := _ui()
	var game_ui: GameUI = add_child_autofree(GameUI.new())
	game_ui.open_pause_menu()
	var offer := _offer([&"strong_attack", &"wide_swing"])
	ui.choose_upgrade(offer, "Kampf gewonnen!")
	assert_eq(_modals(ui).size(), 0, "not over the pause menu")
	assert_eq(ui.get_dialog_queue_size(), 1)
	game_ui.get_pause_modal().finish(&"resume")
	var next := await _wait_for_dialog(ui)
	assert_not_null(next, "the choice appears after the pause menu")
	if next != null:
		next.finish(offer[0])
	await wait_physics_frames(2)
	assert_false(GameManager.is_game_paused())


func test_a_queued_overview_closed_while_waiting_leaves_no_pause() -> void:
	var ui := _ui()
	ui.confirm("Dungeon verlassen?", "Text")
	ui.show_upgrade_overview()
	assert_eq(ui.get_dialog_queue_size(), 1, "the overview waits")
	# Tab again while it waits: it is dropped.
	var tab := InputEventAction.new()
	tab.action = &"upgrade_overview"
	tab.pressed = true
	ui._unhandled_input(tab)
	assert_eq(ui.get_dialog_queue_size(), 0)
	_modals(ui)[0].finish(false)
	await _wait_real(DungeonUI.DIALOG_GAP + 0.1)
	assert_eq(_modals(ui).size(), 0, "nothing comes after")
	assert_false(GameManager.is_game_paused(), "no pause left behind")

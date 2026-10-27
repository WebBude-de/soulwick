extends GutTest
## Extraction (KE3, KONZEPT §2): what the soul gate pays and shows, the depth bonus, the loss payout
## with and without the soul anchor, the return stone rule, the gate dialog and the notice for the
## others (D-126). Uses a test save, never the real one.

const CAMPFIRE_SCENE: PackedScene = preload("res://dungeon/rooms/campfire/campfire_room.tscn")

var _old_save_path: String
var _old_locale: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_extraction_save.cfg"
	_old_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("de")


func after_all() -> void:
	GameManager.clear_pause_reasons()
	TranslationServer.set_locale(_old_locale)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func _context() -> DungeonContext:
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 7
	context.upgrade_manager = autofree(UpgradeManager.new())
	return context


func _ui(context: DungeonContext) -> DungeonUI:
	var ui: DungeonUI = add_child_autofree(DungeonUI.new())
	ui.auto_enemy_hints = false
	ui.show_controls_hint = false
	ui.context = context
	context.ui = ui
	return ui


func _modal(root: Node) -> Modal:
	var found := root.find_children("*", "Modal", true, false)
	return found[0] as Modal if not found.is_empty() else null


func _texts(root: Node) -> String:
	var texts: Array[String] = []
	for node in root.find_children("*", "", true, false):
		if node is Label or node is Button:
			texts.append(node.text)
	return " | ".join(texts)


## A bare room (no scene) for the return stone rule.
func _room(type: RoomSequence.RoomType, state: RoomController.State, arena := false) -> RoomController:
	var room: RoomController = autofree(RoomController.new())
	room.room_type = type
	room.state = state
	room.is_arena = arena
	return room


# --- Payouts ---

func test_loss_pays_a_quarter_and_the_soul_anchor_half() -> void:
	assert_eq(RunManager.LOSS_PAYOUT_RATIO, 0.25, "TESTWERT KE3 (D-196)")
	assert_eq(SoulGateRules.loss_payout_ratio(false), 0.25)
	assert_eq(SoulGateRules.loss_payout_ratio(true), 0.5, "soul anchor (KE5 hook)")
	assert_eq(SoulGateRules.payout(240, RunManager.EndReason.EXIT), 240, "the gate pays everything")
	assert_eq(SoulGateRules.payout(240, RunManager.EndReason.DEATH), 60)
	assert_eq(SoulGateRules.payout(241, RunManager.EndReason.ABORT), 61, "rounded up (D-062)")
	assert_eq(SoulGateRules.payout(241, RunManager.EndReason.DEATH, true), 121, "anchor: 50 %, rounded up")
	assert_eq(SoulGateRules.payout(0, RunManager.EndReason.DEATH, true), 0)
	for amount in [1, 7, 40, 241]:
		assert_eq(SoulGateRules.payout(amount, RunManager.EndReason.DEATH), RunManager.calculate_payout(amount, RunManager.EndReason.DEATH),
				"without the anchor the same as RunManager (%d)" % amount)


func test_secure_amounts_include_the_danger_bonus() -> void:
	assert_eq(SoulGateRules.secure_amounts(240, 3, 0), Vector2i(240, 3))
	# G 4: +20 % once on the payout (D-197): 240 -> 288, 3 -> 3.6 -> 4.
	assert_eq(SoulGateRules.secure_amounts(240, 3, 4), Vector2i(288, 4))
	assert_eq(SoulGateRules.secure_amounts(-5, 0, 4), Vector2i(0, 0))


# --- Depth bonus ---

func test_depth_bonus_is_ten_percent_per_block() -> void:
	assert_eq(EconomyConfig.DEPTH_BONUS_PER_BLOCK, 0.10, "TESTWERT KE3")
	assert_eq(EconomyConfig.new().gold_growth_per_block, 0.10, "gold per enemy grows again")
	assert_eq(EconomyConfig.depth_bonus_percent(5), 0)
	assert_eq(EconomyConfig.depth_bonus_percent(16), 30)
	assert_eq(EconomyConfig.depth_crystals(3, 5), 3, "first block: no bonus")
	assert_eq(EconomyConfig.depth_crystals(3, 15), 4, "boss 1: 3 x 1.2 = 3.6 -> 4")
	assert_eq(EconomyConfig.depth_crystals(3, 30), 5, "boss 2: 3 x 1.5 = 4.5 -> 5")
	assert_eq(EconomyConfig.depth_crystals(3, 60), 6, "boss 4: 3 x 2.1 = 6.3 -> 6")
	assert_eq(EconomyConfig.depth_crystals(0, 60), 0)


func test_gold_per_enemy_grows_with_the_depth() -> void:
	var config := EconomyConfig.new()
	assert_eq(EconomySystem.scale_by_block(10.0, 1, config.gold_growth_per_block), 10)
	assert_eq(EconomySystem.scale_by_block(10.0, 26, config.gold_growth_per_block), 15, "block 5: +50 %")


func test_onward_shows_the_bonus_of_the_next_block() -> void:
	assert_eq(SoulGateRules.onward_bonus_percent(4), 10, "gate in room 4: rooms 6-10 give +10 %")
	assert_eq(SoulGateRules.onward_bonus_percent(15), 30, "campfire after 15: rooms 16-20")
	assert_eq(SoulGateRules.onward_bonus_percent(19), 40)
	assert_eq(SoulGateRules.onward_bonus_percent(7), 20, "return stone in room 7: from room 11 on")


func test_rooms_to_the_next_gate() -> void:
	assert_eq(SoulGateRules.rooms_to_next_gate(4), 5, "room 4 -> room 9")
	assert_eq(SoulGateRules.rooms_to_next_gate(14), 1, "room 14 -> campfire after 15")
	assert_eq(SoulGateRules.rooms_to_next_gate(15), 4, "campfire after 15 -> room 19")
	assert_eq(SoulGateRules.rooms_to_next_gate(7), 2, "return stone in room 7 -> room 9")
	assert_eq(SoulGateRules.rooms_to_next_gate(14, false), 5, "without the campfire gate: room 19")
	assert_eq(SoulGateRules.rooms_to_next_gate(0), 4)


# --- Return stone (KE5 hook) ---

func test_return_stone_waits_for_big_fights() -> void:
	var types := RoomSequence.RoomType
	var states := RoomController.State
	assert_true(SoulGateRules.can_open_return_gate(_room(types.COMBAT, states.ACTIVE), false), "a normal fight: yes")
	assert_false(SoulGateRules.can_open_return_gate(_room(types.COMBAT, states.ACTIVE), true), "once per run")
	assert_false(SoulGateRules.can_open_return_gate(_room(types.BOSS, states.ACTIVE), false), "not in a boss fight")
	assert_false(SoulGateRules.can_open_return_gate(_room(types.MINIBOSS, states.ACTIVE), false), "not against a champion")
	assert_false(SoulGateRules.can_open_return_gate(_room(types.COMBAT, states.ACTIVE, true), false), "not in an arena fight")
	assert_true(SoulGateRules.can_open_return_gate(_room(types.BOSS, states.CLEARED), false), "after the boss: yes")
	assert_true(SoulGateRules.can_open_return_gate(_room(types.SPECIAL, states.ACTIVE), false))
	assert_false(SoulGateRules.can_open_return_gate(_room(types.COMBAT, states.PREPARED), false), "not in a room nobody entered")
	assert_false(SoulGateRules.can_open_return_gate(null, false))
	var with_gate := _room(types.SPECIAL, states.ACTIVE)
	with_gate.has_portal = true
	assert_false(SoulGateRules.can_open_return_gate(with_gate, false), "a gate stands there already")


func test_return_stone_opens_a_gate_in_the_room() -> void:
	var context := _context()
	_ui(context)
	var room := CAMPFIRE_SCENE.instantiate() as RoomController
	room.setup(15, RoomSequence.RoomType.CAMPFIRE, -1, false, context)
	room.slot_index = RoomSequence.get_campfire_slot_after(15)
	add_child_autofree(room)
	assert_null(SoulGate.open_return_gate(room, false), "not before the room is entered")
	room.activate()
	var gate := SoulGate.open_return_gate(room, false)
	assert_not_null(gate)
	assert_eq(SoulGate.find_in(room), gate)
	assert_true(room.has_portal)
	assert_null(SoulGate.open_return_gate(room, false), "one gate per room")


# --- The gate and its dialog ---

func test_campfire_gate_is_a_soul_gate_with_its_caption() -> void:
	var context := _context()
	var room := CAMPFIRE_SCENE.instantiate() as RoomController
	room.setup(15, RoomSequence.RoomType.CAMPFIRE, -1, true, context)
	room.slot_index = RoomSequence.get_campfire_slot_after(15)
	add_child_autofree(room)
	var gate := SoulGate.find_in(room)
	assert_not_null(gate, "the campfire has its soul gate (D-103)")
	if gate != null:
		assert_string_contains(_texts(gate), "Seelentor")


func test_gate_dialog_shows_both_sides_and_secures_on_the_first() -> void:
	var ui := _ui(_context())
	watch_signals(ui)
	var result := [null]
	var ask := func() -> void: result[0] = await ui.choose_soul_gate(null, 240, 3, 40, 5)
	ask.call()
	await wait_physics_frames(2)
	var modal := _modal(ui)
	assert_not_null(modal)
	if modal == null:
		return
	var text := _texts(modal)
	assert_string_contains(text, "Jetzt sichern")
	assert_string_contains(text, "240 Gold · 3 Kristalle")
	assert_string_contains(text, "Weiter")
	assert_string_contains(text, "Tiefenbonus +40 %, nächstes Tor frühestens in 5 Räumen")
	assert_string_contains(text, "25 %", "the footnote names the loss payout")
	assert_signal_emitted_with_parameters(ui, "soul_gate_used", [null, DungeonUI.SOUL_GATE_OPEN])
	modal.finish(0)
	await wait_physics_frames(2)
	assert_eq(result[0], true, "first card: secure")
	assert_signal_emitted_with_parameters(ui, "soul_gate_used", [null, DungeonUI.SOUL_GATE_SECURED])


func test_gate_dialog_goes_on_with_esc_and_says_one_room() -> void:
	var ui := _ui(_context())
	watch_signals(ui)
	var result := [null]
	var ask := func() -> void: result[0] = await ui.choose_soul_gate(null, 12, 0, 30, 1)
	ask.call()
	await wait_physics_frames(2)
	var modal := _modal(ui)
	assert_not_null(modal)
	if modal == null:
		return
	assert_string_contains(_texts(modal), "frühestens in 1 Raum")
	modal.finish(modal.cancel_result)
	await wait_physics_frames(2)
	assert_eq(result[0], false, "Esc: go on")
	assert_signal_emitted_with_parameters(ui, "soul_gate_used", [null, DungeonUI.SOUL_GATE_ONWARD])


func test_the_others_see_a_notice() -> void:
	var ui := _ui(_context())
	await wait_physics_frames(1)
	ui.show_soul_gate_notice("Anna", DungeonUI.SOUL_GATE_OPEN)
	assert_eq(ui.get_status_line_text(), "Anna steht am Seelentor …")
	ui.show_soul_gate_notice("Anna", DungeonUI.SOUL_GATE_SECURED)
	assert_eq(ui.get_status_line_text(), "Anna sichert die Beute")
	ui.show_soul_gate_notice("Anna", DungeonUI.SOUL_GATE_ONWARD)
	assert_eq(ui.get_status_line_text(), "Anna geht weiter")

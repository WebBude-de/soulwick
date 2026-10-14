extends GutTest
## UX2 menu kit: every dungeon dialog uses the same frame (header, key bar with "Spiel pausiert"),
## shop cards show clear states instead of half transparency (affordable, too little gold with a
## red price and a lock, at the limit, sold), blocked cards answer with an error, disabled option
## buttons use button_disabled, and the text table covers every key the menus use.
## Uses a test save, never the real one.

const TEST_SAVE_PATH := "user://test_ux2_menus.cfg"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const ALTAR_SCRIPT: GDScript = preload("res://dungeon/rooms/special/altar_content.gd")
## Files whose DungeonTexts keys must all have a German text.
const KEY_FILES := [
	"res://ui/menus/dungeon_ui.gd", "res://ui/menus/ui_dialog.gd", "res://ui/menus/modal.gd",
	"res://ui/menus/game_ui.gd", "res://ui/hints/room_genre.gd", "res://ui/hints/room_intro_card.gd",
	"res://ui/ui_kit.gd",
]

var _old_save_path: String
var _upgrades: UpgradeManager
var _economy: EconomySystem


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.load_game()


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()
	_upgrades = autofree(UpgradeManager.new())
	for path in DirAccess.get_files_at("res://upgrades/data/"):
		if path.ends_with(".tres"):
			_upgrades.upgrade_pool.append(load("res://upgrades/data/" + path))
	_economy = autofree(EconomySystem.new())
	_economy.config = EconomyConfig.new()


func _upgrade(id: StringName) -> UpgradeData:
	for upgrade in _upgrades.upgrade_pool:
		if upgrade.id == id:
			return upgrade
	return null


func _player() -> Player:
	return add_child_autofree(PLAYER_SCENE.instantiate()) as Player


func _ui(player: Player) -> DungeonUI:
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 7
	context.upgrade_manager = _upgrades
	context.economy = _economy
	context.player = player
	var ui: DungeonUI = add_child_autofree(DungeonUI.new())
	ui.auto_enemy_hints = false
	ui.show_controls_hint = false
	ui.context = context
	context.ui = ui
	return ui


func _offer(kind: ShopOffer.Kind, price: int, upgrade: UpgradeData = null) -> ShopOffer:
	var offer := ShopOffer.new()
	offer.kind = kind
	offer.price = price
	offer.upgrade = upgrade
	offer.amount = 2.0
	return offer


func _modal(ui: Node) -> Modal:
	var found := ui.find_children("*", "Modal", true, false)
	return found[0] as Modal if not found.is_empty() else null


func _texts(root: Node) -> Array[String]:
	var texts: Array[String] = []
	for label: Label in root.find_children("*", "Label", true, false):
		texts.append(label.text)
	return texts


func _badge_texts(card: Node) -> Array[String]:
	var texts: Array[String] = []
	for chip in card.find_children("Badge", "", true, false):
		texts.append((chip as UiChip).get_text())
	return texts


func _assert_kit_frame(modal: Modal, what: String) -> void:
	assert_not_null(modal, "%s: dialog open" % what)
	if modal == null:
		return
	assert_not_null(modal.content.get_node_or_null(^"Header"), "%s: shared header" % what)
	assert_true(modal.key_bar.visible, "%s: key bar inside the panel" % what)
	assert_true(_texts(modal.key_bar).has(DungeonTexts.t(&"MENU_PAUSED")), "%s: names the pause" % what)
	# Key caps of the hints, or of the buttons placed in the bar (run end, R8).
	var caps := modal.key_bar.find_children("Key", "", true, false).size() + modal.key_bar.find_children("KeyCap", "", true, false).size()
	assert_gt(caps, 0, "%s: key caps" % what)


# --- Shop states ---

func test_offer_states_follow_gold_limit_and_sale() -> void:
	var player := _player()
	var ui := _ui(player)
	RunManager.add_run_gold(20)
	var swing := _upgrade(&"wide_swing")
	assert_eq(ui.get_offer_state(_offer(ShopOffer.Kind.UPGRADE, 15, swing), player), &"buy")
	assert_eq(ui.get_offer_state(_offer(ShopOffer.Kind.UPGRADE, 25, swing), player), &"too_expensive")
	var sold := _offer(ShopOffer.Kind.UPGRADE, 5, swing)
	sold.sold = true
	assert_eq(ui.get_offer_state(sold, player), &"sold")
	for i in swing.max_stacks:
		_upgrades.acquire_upgrade(swing)
	assert_eq(ui.get_offer_state(_offer(ShopOffer.Kind.UPGRADE, 25, swing), player), &"unavailable",
		"at the limit wins over too little gold: gold would not help")
	assert_eq(ui.get_offer_state(_offer(ShopOffer.Kind.HEAL, 5), player), &"unavailable", "full HP")


func test_shop_cards_keep_their_look_and_show_badges() -> void:
	var player := _player()
	var ui := _ui(player)
	RunManager.add_run_gold(20)
	var swing := _upgrade(&"wide_swing")
	var cheap := _offer(ShopOffer.Kind.UPGRADE, 15, swing)
	var expensive := _offer(ShopOffer.Kind.UPGRADE, 40, _upgrade(&"strong_attack"))
	var sold := _offer(ShopOffer.Kind.SHIELD, 10)
	sold.sold = true
	var offers: Array[ShopOffer] = [cheap, expensive, sold]
	ui.open_shop(offers, player)
	await wait_physics_frames(2)
	var modal := _modal(ui)
	_assert_kit_frame(modal, "shop")
	var cheap_card := modal.find_child("Offer1", true, false) as UiCard
	var expensive_card := modal.find_child("Offer2", true, false) as UiCard
	var sold_card := modal.find_child("Offer3", true, false) as UiCard
	# The cards are dealt in (R8); once they are there, none is half transparent. Physics frames
	# run while the dialog pauses the tree (wait_seconds would not).
	await wait_physics_frames(50)
	for card in [cheap_card, expensive_card, sold_card]:
		assert_eq((card as UiCard).modulate.a, 1.0, "no half transparency")
	assert_false(cheap_card.disabled)
	assert_eq(_badge_texts(cheap_card).size(), 0, "a buyable offer needs no badge")
	assert_true(expensive_card.disabled)
	# R8: too little gold is a red price with a lock (and the reason as tooltip), no badge wall.
	assert_eq(_badge_texts(expensive_card).size(), 0)
	assert_not_null(expensive_card.find_child("Lock", true, false))
	assert_eq((expensive_card.find_child("PriceRow", true, false) as Control).tooltip_text, DungeonTexts.t(&"STATE_TOO_LITTLE_GOLD"))
	var price := expensive_card.find_child("Price", true, false)
	var price_label := price.get_child(1) as Label
	assert_eq(price_label.get_theme_color("font_color"), UiKit.COLOR_DANGER, "price in red")
	assert_true(sold_card.disabled)
	assert_true(_badge_texts(sold_card).has(DungeonTexts.t(&"STATE_SOLD").to_upper()))
	# A key on a blocked offer: error, nothing bought.
	watch_signals(expensive_card)
	(modal.hotkeys[KEY_2] as Callable).call()
	assert_signal_emitted(expensive_card, "rejected")
	assert_eq(RunManager.get_run_gold(), 20)
	# A key on the affordable offer buys it and the card turns into "sold".
	(modal.hotkeys[KEY_1] as Callable).call()
	await wait_physics_frames(2)
	assert_eq(RunManager.get_run_gold(), 5)
	assert_true(cheap.sold)
	var bought := modal.find_child("Offer1", true, false) as UiCard
	assert_true(_badge_texts(bought).has(DungeonTexts.t(&"STATE_SOLD").to_upper()))
	var close: Button = null
	for button: Button in modal.find_children("*", "Button", true, false):
		if button.text == DungeonTexts.t(&"MENU_CLOSE"):
			close = button
	assert_not_null(close, "tools close the shop with 'Schließen'")
	modal.finish()
	await wait_physics_frames(1)
	assert_false(GameManager.is_game_paused())


# --- Same frame for every dialog ---

func test_every_dungeon_dialog_uses_the_kit() -> void:
	var player := _player()
	var ui := _ui(player)
	var offer: Array[UpgradeData] = [_upgrade(&"wide_swing"), _upgrade(&"strong_attack")]
	var dialogs := {
		"upgrade": func() -> void: await ui.choose_upgrade(offer, "Kampf gewonnen!"),
		"portal": func() -> void: await ui.confirm("Dungeon verlassen?", "Text", "Verlassen", "Weiterspielen"),
		"pact": func() -> void: await ui.choose_option("Pakt-Altar", "Text", [], [{"text": "A"}, {"text": "B"}], true),
		"campfire": func() -> void: await ui.choose_campfire_rest(4.0, false, offer, player),
		"weapon": func() -> void: await ui.choose_weapon_slot(load("res://weapons/data/staff.tres"), player),
		"overview": func() -> void: await ui.show_upgrade_overview(),
	}
	player.weapon_controller.equip_weapon(load("res://weapons/data/bow.tres"), 1)
	for what: String in dialogs:
		(dialogs[what] as Callable).call()
		await wait_physics_frames(2)
		var modal := _modal(ui)
		_assert_kit_frame(modal, what)
		if modal != null:
			modal.finish(modal.cancel_result)
		await wait_physics_frames(2)
	assert_false(GameManager.is_game_paused())


func test_run_end_uses_the_kit() -> void:
	var game_ui := GameUI.new()
	add_child_autofree(game_ui)
	game_ui.show_run_end({"reason": RunManager.EndReason.DEATH, "room": 4}, {"kills": 2})
	await wait_physics_frames(1)
	var modal := _modal(game_ui)
	_assert_kit_frame(modal, "run end")
	modal.finish(modal.accept_result)
	await wait_physics_frames(1)


func test_upgrade_cards_carry_key_caps_and_arrows_move_the_focus() -> void:
	var ui := _ui(_player())
	var offer: Array[UpgradeData] = [_upgrade(&"wide_swing"), _upgrade(&"strong_attack"), _upgrade(&"fast_attack")]
	var result: Array = [null]
	var ask := func() -> void: result[0] = await ui.choose_upgrade(offer, "Truhe")
	ask.call()
	await wait_physics_frames(2)
	var modal := _modal(ui)
	var cards := modal.find_children("*", "UiCard", true, false)
	assert_eq(cards.size(), 3)
	for i in cards.size():
		var keys := (cards[i] as Node).find_children("Key", "", true, false)
		assert_eq((keys[0] as UiChip).get_text(), str(i + 1), "card %d shows its number key" % (i + 1))
	var right := InputEventAction.new()
	right.action = &"ui_right"
	right.pressed = true
	assert_true(modal.input_handler.call(right))
	assert_true((cards[0] as UiCard).focused, "first arrow focuses the first card")
	modal.input_handler.call(right)
	assert_true((cards[1] as UiCard).focused)
	modal.accept_action.call()
	await wait_physics_frames(2)
	assert_eq(result[0], offer[1], "Enter picks the focused card")


func test_campfire_heal_is_disabled_with_its_own_frame() -> void:
	var ui := _ui(_player())
	var upgrades: Array[UpgradeData] = [_upgrade(&"wide_swing")]
	ui.choose_campfire_rest(4.0, false, upgrades)
	await wait_physics_frames(2)
	var modal := _modal(ui)
	var heal := modal.find_child("Heal", true, false) as Button
	assert_true(heal.disabled)
	var style := heal.get_theme_stylebox("disabled") as StyleBoxTexture
	assert_eq(style.texture, UiKit.upscale(UiKit.BUTTON_DISABLED_TEXTURE), "button_disabled.png frame")
	assert_eq(heal.get_theme_color("font_disabled_color"), UiKit.COLOR_DISABLED)
	assert_false(modal.accept_allowed, "Enter does not heal at full health")
	modal.finish(-1)
	await wait_physics_frames(1)


func test_theme_uses_button_disabled() -> void:
	var style := UiKit.get_theme().get_stylebox("disabled", "Button") as StyleBoxTexture
	assert_not_null(style)
	assert_eq(style.texture, UiKit.upscale(UiKit.BUTTON_DISABLED_TEXTURE))
	var button: Button = autofree(UiKit.dialog_button("Kaufen", "", func() -> void: pass))
	assert_eq((button.get_theme_stylebox("disabled") as StyleBoxTexture).texture, UiKit.upscale(UiKit.BUTTON_DISABLED_TEXTURE))


func test_legacy_key_subs_become_key_caps() -> void:
	var modal: Modal = autofree(UiDialog.create(&"test_ux2_keys", 220.0, "Titel"))
	var buttons := UiDialog.add_buttons(modal, [
		{"text": "Weiterspielen", "sub": "Esc", "result": false, "default": true},
		{"text": "Heilen", "sub": "+4 HP", "result": true},
	])
	assert_not_null(buttons[0].get_node_or_null(^"KeyCap"), "'Esc' becomes a key cap")
	assert_null(buttons[0].get_node_or_null(^"Sub"))
	assert_not_null(buttons[1].get_node_or_null(^"Sub"), "a real sub line stays")
	assert_eq(buttons[0].text, "Weiterspielen", "tools press dialog buttons by text")


# --- Texts ---

func test_every_used_key_has_a_german_text() -> void:
	var pattern := RegEx.create_from_string("(?:_t|DungeonTexts\\.t)\\(&\"([A-Z0-9_]+)\"")
	var missing: Array[String] = []
	for path: String in KEY_FILES:
		var source := FileAccess.get_file_as_string(path)
		for found in pattern.search_all(source):
			var key := found.get_string(1)
			if not DungeonTexts.has_text(StringName(key)):
				missing.append("%s: %s" % [path.get_file(), key])
	assert_eq(missing, [] as Array[String])
	for key in UiKit.CATEGORY_KEYS.values():
		assert_true(DungeonTexts.has_text(key))


func test_copied_texts_match_their_sources() -> void:
	assert_eq(DungeonTexts.DE[&"ROOM_TRIAL_GAUNTLET_INTRO"], TrialContent.get_intro_text(SpecialTable.TrialKind.GAUNTLET))
	assert_eq(DungeonTexts.DE[&"ROOM_TRIAL_LIGHT_RUN_INTRO"], TrialContent.get_intro_text(SpecialTable.TrialKind.LIGHT_RUN))
	assert_eq(DungeonTexts.DE[&"ROOM_PACT_INTRO"], ALTAR_SCRIPT.PACT_INTRO_TEXT)
	for key: StringName in [WaveRules.ARENA_TITLE, WaveRules.ARENA_INTRO_TEXT]:
		assert_true(DungeonTexts.has_text(key), "A5 key %s has a German text" % key)


func test_unknown_key_comes_back_and_formats() -> void:
	assert_eq(DungeonTexts.t(&"NO_SUCH_KEY_UX2"), "NO_SUCH_KEY_UX2")
	assert_eq(DungeonTexts.t(&"ROOM_EYEBROW_COMBAT", [7]), "Raum 7 · Kampfraum")
	var lines := DungeonTexts.to_csv_lines()
	assert_eq(lines[0], "keys,en,de")
	assert_eq(lines.size(), DungeonTexts.DE.size() + 1)

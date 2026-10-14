extends GutTest
## R8 UI rework (07_ui.md): every dungeon dialog stays under 60 % of the screen height with the scene
## visible behind a lighter overlay, cards carry their category colour, the task bar keeps a goal that
## was bound during the result moment of the one before (R4a bug), the boss bar is compact and never
## covers the room line, banners use the stripe of 4 px and 14 px titles, and the brightness option
## reaches LightingProfile. Uses a test save and a test settings folder, never the real ones.

const ROOT := "user://test_r8_ui"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String
var _old_locale: String
var _upgrades: UpgradeManager
var _economy: EconomySystem


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
	GameManager.clear_pause_reasons()
	LightingProfile.set_brightness(0.0)
	_wipe()
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()
	TranslationServer.set_locale(_old_locale)


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()
	_upgrades = autofree(UpgradeManager.new())
	for path in DirAccess.get_files_at("res://upgrades/data/"):
		if path.ends_with(".tres"):
			_upgrades.upgrade_pool.append(load("res://upgrades/data/" + path))
	_economy = autofree(EconomySystem.new())
	_economy.config = EconomyConfig.new()


func after_each() -> void:
	GameManager.clear_pause_reasons()


func _wipe() -> void:
	var folder := ProjectSettings.globalize_path(ROOT)
	for dir_path in [folder.path_join("saves"), folder]:
		var dir := DirAccess.open(dir_path)
		if dir != null:
			for file in dir.get_files():
				DirAccess.remove_absolute(dir_path.path_join(file))


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


func _modal(root: Node) -> Modal:
	var found := root.find_children("*", "Modal", true, false)
	return found[0] as Modal if not found.is_empty() else null


func _offer(kind: ShopOffer.Kind, price: int, upgrade: UpgradeData = null, weapon: WeaponData = null) -> ShopOffer:
	var offer := ShopOffer.new()
	offer.kind = kind
	offer.price = price
	offer.upgrade = upgrade
	offer.weapon = weapon
	offer.amount = 2.0
	return offer


func _height_ratio(modal: Modal) -> float:
	return modal.frame.get_combined_minimum_size().y / modal.get_viewport_rect().size.y


# --- Dialogs: at most 60 % of the screen, scene visible ---

func test_every_dungeon_dialog_fits_sixty_percent() -> void:
	var player := _player()
	var ui := _ui(player)
	player.weapon_controller.equip_weapon(load("res://weapons/data/bow.tres"), 1)
	RunManager.add_run_gold(20)
	var three: Array[UpgradeData] = [_upgrade(&"strong_attack"), _upgrade(&"pierce"), _upgrade(&"shield_on_kill")]
	var owned: Array[UpgradeData] = [_upgrade(&"strong_attack"), _upgrade(&"heal_on_kill"), _upgrade(&"wide_swing"), _upgrade(&"fast_attack")]
	var offers: Array[ShopOffer] = [
		_offer(ShopOffer.Kind.UPGRADE, 28, _upgrade(&"wide_swing")),
		_offer(ShopOffer.Kind.UPGRADE, 120, _upgrade(&"shield_on_kill")),
		_offer(ShopOffer.Kind.WEAPON, 30, null, load("res://weapons/data/hammer.tres")),
		_offer(ShopOffer.Kind.WEAPON, 34, null, load("res://weapons/data/staff.tres")),
		_offer(ShopOffer.Kind.HEAL, 18),
		_offer(ShopOffer.Kind.SHIELD, 18),
	]
	var game_ui: GameUI = add_child_autofree(GameUI.new())
	var dialogs := {
		"upgrade": func() -> void: await ui.choose_upgrade(three, "Kampf gewonnen!"),
		"pact upgrade": func() -> void: await ui.choose_upgrade(three, "Pakt", 2),
		"shop": func() -> void: await ui.open_shop(offers, player),
		"weapon": func() -> void: await ui.choose_weapon_slot(load("res://weapons/data/staff.tres"), player),
		"campfire": func() -> void: await ui.choose_campfire_rest(4.0, true, owned, player),
		"pact": func() -> void: await ui.choose_option("Pakt-Altar", "Nimm ein gewöhnliches Upgrade – oder schließe einen Pakt.",
				[["Pakt", "Upgrade +2 Stufen", UiKit.COLOR_GOLD], ["Fluch (ganzer Run)", "Lichtkreis −20 %", UiKit.COLOR_DANGER_SOFT]],
				[{"text": "Extra-Upgrade", "sub": "1 Stufe, kein Preis"}, {"text": "Pakt schließen", "sub": "Fluch: Düsternis"}], true, "Flüche zeigt die Übersicht (Tab)."),
		"portal": func() -> void: await ui.confirm("Dungeon verlassen?", "Der Run endet. Du nimmst 100 % deines Run-Goldes mit (55 Gold).", "Verlassen", "Weiterspielen",
				[["Run-Gold", "55", UiKit.COLOR_GOLD], ["Gutschrift (100 %)", "55", UiKit.COLOR_SUCCESS]]),
		"overview": func() -> void: await ui.show_upgrade_overview(),
		"run end": func() -> void: await game_ui.show_run_end({"reason": RunManager.EndReason.DEATH, "room": 16, "remaining_gold": 55,
				"gold_earned": 140, "payout": 28, "remaining_crystals": 2, "crystal_payout": 1},
				{"kills": 47, "rooms_cleared": 15, "upgrades": 6, "play_time": 754.0, "cause": "Knochenkönig", "record_before": 12}),
		"pause": func() -> void: await game_ui.open_pause_menu(),
	}
	for upgrade in owned:
		_upgrades.acquire_upgrade(upgrade)
	for what: String in dialogs:
		(dialogs[what] as Callable).call()
		await wait_physics_frames(3)
		var modal := _modal(ui) if _modal(ui) != null else _modal(game_ui)
		assert_not_null(modal, "%s: open" % what)
		if modal == null:
			continue
		var ratio := _height_ratio(modal)
		gut.p("%s: %.0f %% of the screen height" % [what, ratio * 100.0])
		assert_true(modal.fits_screen(), "%s: %.0f %% > 60 %% of the screen height" % [what, ratio * 100.0])
		modal.finish(modal.cancel_result if modal.cancel_allowed else modal.accept_result)
		await wait_physics_frames(2)
	assert_false(GameManager.is_game_paused())
	assert_lt(UiKit.COLOR_OVERLAY.a, 0.7, "the scene stays visible behind the dialogs")


func test_upgrade_cards_carry_their_category_colour_and_a_symbol_tile() -> void:
	var ui := _ui(_player())
	var offer: Array[UpgradeData] = [_upgrade(&"strong_attack"), _upgrade(&"pierce"), _upgrade(&"explosive_hit")]
	ui.choose_upgrade(offer, "Truhe")
	await wait_physics_frames(2)
	var modal := _modal(ui)
	var cards := modal.find_children("*", "UiCard", true, false)
	assert_eq(cards.size(), 3)
	for i in cards.size():
		var card := cards[i] as UiCard
		assert_eq(card.accent, UiKit.category_color(offer[i].category), "card %d: category colour" % (i + 1))
		assert_not_null(card.find_child("SymbolTile", true, false), "card %d: 32 px symbol on a tile" % (i + 1))
		assert_not_null(card.symbol, "card %d: the symbol hops on focus" % (i + 1))
	assert_eq(modal.accent, UiKit.COLOR_GOLD, "accent stripe of the dialog")
	assert_not_null(modal.find_child("Eyebrow", true, false), "eyebrow tag on the frame")
	var pips := (cards[1] as Node).find_child("Stacks", true, false)
	assert_gt(pips.get_child_count(), offer[1].max_stacks, "limited upgrade: one pip per stack plus the numbers")
	modal.finish(offer[0])
	await wait_physics_frames(1)


func test_a_pick_leaves_a_burst_that_outlasts_the_dialog() -> void:
	var ui := _ui(_player())
	var offer: Array[UpgradeData] = [_upgrade(&"strong_attack"), _upgrade(&"wide_swing")]
	var result: Array = [null]
	var ask := func() -> void: result[0] = await ui.choose_upgrade(offer, "Truhe")
	ask.call()
	await wait_physics_frames(2)
	var modal := _modal(ui)
	(modal.hotkeys[KEY_2] as Callable).call()
	await wait_physics_frames(2)
	assert_eq(result[0], offer[1], "the pick is instant")
	assert_null(_modal(ui), "the dialog is gone")
	assert_not_null(get_tree().root.get_node_or_null("PickBurst"), "the burst plays on its own layer")
	await wait_seconds(0.6)
	assert_null(get_tree().root.get_node_or_null("PickBurst"), "and frees itself")


func test_shop_too_little_gold_is_a_red_price_with_a_lock() -> void:
	var player := _player()
	var ui := _ui(player)
	RunManager.add_run_gold(10)
	var offers: Array[ShopOffer] = [_offer(ShopOffer.Kind.UPGRADE, 40, _upgrade(&"strong_attack"))]
	ui.open_shop(offers, player)
	await wait_physics_frames(2)
	var modal := _modal(ui)
	var card := modal.find_child("Offer1", true, false) as UiCard
	assert_true(card.disabled)
	assert_not_null(card.find_child("Lock", true, false), "lock in front of the price")
	assert_not_null(card.find_child("Effect", true, false), "the effect stays readable")
	modal.finish()
	await wait_physics_frames(1)


# --- Task bar (R4a bug) ---

func test_a_new_goal_survives_the_result_moment_of_the_old_one() -> void:
	var bar: ObjectiveBar = add_child_autofree(ObjectiveBar.new())
	var first: RoomObjective = add_child_autofree(RoomObjective.create(RoomObjective.FLAME))
	bar.bind(first)
	first.finish(true)
	await wait_physics_frames(1)
	assert_true(bar.is_showing_result(), "result moment of the first goal")
	var second: RoomObjective = add_child_autofree(RoomObjective.create(RoomObjective.SOULS))
	bar.bind(second)
	assert_false(bar.is_showing_result(), "binding cancels the old result moment")
	await wait_seconds(ObjectiveBar.RESULT_TIME + ObjectiveBar.FADE_TIME + 0.5)
	assert_eq(bar.objective, second, "the old close does not take the new goal away")
	assert_true(bar.visible)
	assert_eq(bar.modulate.a, 1.0)


func test_the_result_moment_still_closes_its_own_goal() -> void:
	var bar: ObjectiveBar = add_child_autofree(ObjectiveBar.new())
	var goal: RoomObjective = add_child_autofree(RoomObjective.create(RoomObjective.ARENA))
	bar.bind(goal)
	watch_signals(bar)
	goal.finish(false)
	await wait_seconds(ObjectiveBar.RESULT_TIME + ObjectiveBar.FADE_TIME + 0.5)
	assert_signal_emitted(bar, "done")
	assert_null(bar.objective)
	assert_false(bar.visible)


# --- Boss bar and HUD ---

func test_boss_bar_is_compact_and_leaves_the_room_line_alone() -> void:
	var hud: Hud = add_child_autofree(Hud.new())
	hud.set_dungeon_mode(true)
	hud.set_heal_countdown(4)
	hud.set_room_mode("Flamme hüten")
	var ui := _ui(_player())
	var boss: Enemy = load("res://enemies/enemy_base.tscn").instantiate()
	boss.data = load("res://enemies/data/boss_bone_king.tres")
	add_child_autofree(boss)
	await wait_physics_frames(2)
	ui.show_boss_bar(boss)
	await wait_physics_frames(3)
	var bar := ui._boss_bar_root
	var height := bar.get_combined_minimum_size().y
	assert_lte(height, UiKit.px(30), "about as high as the task bar (was ~92 mockup px)")
	assert_false(bar.get_global_rect().intersects(hud._room_box.get_global_rect()), "never over the room line")
	assert_almost_eq(hud._room_box.position.y, UiKit.px(Hud.ROOM_LINE_TOP), 0.5, "the room line stays at the height of the bars")
	assert_false(ui.get_objective_bar().visible, "the boss bar replaces the task bar")


func test_weapon_block_shows_keys_as_key_caps() -> void:
	var hud: Hud = add_child_autofree(Hud.new())
	var player := _player()
	player.weapon_controller.equip_weapon(load("res://weapons/data/bow.tres"), 1)
	hud.set_dungeon_mode(true)
	hud.bind_player(player)
	await wait_physics_frames(1)
	var keys := hud._weapon_keys.find_children("Key", "", true, false)
	assert_gte(keys.size(), 2, "switch and dash (and the special) as key caps")
	assert_not_null(hud._dash_bar.get_parent(), "the dash bar sits next to its key")
	assert_string_contains(hud._weapon_hint.text, DataTexts.weapon_name(load("res://weapons/data/bow.tres")))


# --- Banners ---

func test_banner_has_a_wide_stripe_and_a_big_title() -> void:
	var ui := _ui(_player())
	ui.show_banner("Raum geschafft!", "Der Weg ist frei")
	var box := ui.get_banner()
	assert_not_null(box)
	var stripe := box.find_child("Stripe", true, false) as Control
	assert_eq(stripe.custom_minimum_size.x, UiKit.px(4.0), "07_ui.md: 4-6 px stripe")
	var title := box.find_child("Title", true, false) as Label
	assert_eq(title.get_theme_font_size("font_size"), UiKit.font_px(UiKit.SIZE_TITLE_LARGE), "07_ui.md: 14 px title")


# --- Brightness (R6 hook) ---

func test_brightness_option_reaches_the_lighting() -> void:
	assert_eq(GameOptions.get_brightness(), 0.0, "default: as designed")
	GameOptions.set_brightness(0.5)
	assert_almost_eq(LightingProfile.brightness, 0.5, 0.001)
	GameOptions.set_brightness(3.0)
	assert_eq(GameOptions.get_brightness(), 1.0, "clamped to +1")
	GameOptions.set_brightness(-0.4)
	LightingProfile.set_brightness(0.0)
	GameOptions.apply_all()
	assert_almost_eq(LightingProfile.brightness, -0.4, 0.001, "apply_all() brings it back at start")
	GameOptions.reset_to_defaults()
	assert_eq(GameOptions.get_brightness(), 0.0)
	assert_eq(LightingProfile.brightness, 0.0)


func test_brightness_row_sits_in_the_display_tab() -> void:
	var view: OptionsView = add_child_autofree(OptionsView.new())
	await wait_physics_frames(1)
	view.select_row(OptionsView.Row.BRIGHTNESS)
	assert_eq(view.get_tab(), OptionsView.Tab.DISPLAY)
	view.change(1)
	assert_almost_eq(GameOptions.get_brightness(), OptionsView.BRIGHTNESS_STEP, 0.001, "→ makes it brighter")
	assert_eq(OptionsView.brightness_text(0.2), "+20 %")
	assert_eq(OptionsView.brightness_text(0.0), "0 %")
	GameOptions.reset_to_defaults()

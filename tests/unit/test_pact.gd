extends GutTest
## Pact altar and curses (D-112, ROADMAP_AUSBAU A8): a pact gives a better upgrade
## (one stack more) against a curse for the rest of the run; curses lie on the player who sealed
## the pact, act through PlayerCurses' queries and show up in the Tab overview.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const ALTAR: PackedScene = preload("res://dungeon/rooms/special/altar_content.tscn")
const FOUNTAIN_SCRIPT: GDScript = preload("res://dungeon/rooms/special/fountain_content.gd")

var _old_save_path: String
var _upgrades: UpgradeManager


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_pact_save.cfg"


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func before_each() -> void:
	_upgrades = autofree(UpgradeManager.new())
	for path in DirAccess.get_files_at("res://upgrades/data/"):
		if path.ends_with(".tres"):
			_upgrades.upgrade_pool.append(load("res://upgrades/data/" + path))


func _upgrade(id: StringName) -> UpgradeData:
	for upgrade in _upgrades.upgrade_pool:
		if upgrade.id == id:
			return upgrade
	return null


func _player() -> Player:
	return add_child_autofree(PLAYER_SCENE.instantiate()) as Player


func _context(player: Player = null) -> DungeonContext:
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 3
	context.upgrade_manager = _upgrades
	context.player = player
	return context


func _altar(context: DungeonContext, pact: bool, curse := -1) -> SpecialContent:
	var altar := ALTAR.instantiate() as SpecialContent
	altar.set(&"forced_pact", 1 if pact else 0)
	add_child_autofree(altar)
	altar.setup(context, null)
	if curse >= 0:
		altar.set(&"pact_curse", curse)
	return altar


# --- Curses on the player ---

func test_curses_attach_to_the_player_at_runtime() -> void:
	var player := _player()
	assert_null(PlayerCurses.of(player), "no node before the first pact")
	assert_eq(PlayerCurses.get_curses_of(player).size(), 0)
	var curses := PlayerCurses.ensure(player)
	assert_eq(curses.get_parent(), player)
	assert_eq(PlayerCurses.ensure(player), curses, "one node per player")
	assert_true(curses.add_curse(PlayerCurses.Curse.HASTE))
	assert_false(curses.add_curse(PlayerCurses.Curse.HASTE), "each curse once")
	assert_true(PlayerCurses.has_curse(player, PlayerCurses.Curse.HASTE))


func test_curse_values() -> void:
	var player := _player()
	assert_eq(PlayerCurses.enemy_speed_factor(player), 1.0)
	assert_eq(PlayerCurses.vision_factor(player), 1.0)
	assert_eq(PlayerCurses.fountain_heal_factor(player), 1.0)
	var curses := PlayerCurses.ensure(player)
	curses.add_curse(PlayerCurses.Curse.HASTE)
	curses.add_curse(PlayerCurses.Curse.GLOOM)
	curses.add_curse(PlayerCurses.Curse.DRY_FOUNTAINS)
	assert_almost_eq(PlayerCurses.enemy_speed_factor(player), 1.1, 0.0001, "enemies +10 %")
	assert_almost_eq(PlayerCurses.vision_factor(player), 0.8, 0.0001, "light circle -20 %")
	assert_almost_eq(PlayerCurses.fountain_heal_factor(player), 0.5, 0.0001, "fountains heal half")
	assert_eq(PlayerCurses.get_curse_effect(PlayerCurses.Curse.FRAILTY), "−1 Max-Herz")
	assert_eq(PlayerCurses.get_curse_effect(PlayerCurses.Curse.HASTE), "Gegner +10 % Tempo")


func test_frailty_takes_one_heart_of_maximum_health() -> void:
	var player := _player()
	var max_before := player.health.get_max_health()
	watch_signals(player.health)
	PlayerCurses.ensure(player).add_curse(PlayerCurses.Curse.FRAILTY)
	assert_eq(player.health.get_max_health(), max_before - 2.0)
	assert_eq(player.health.get_health(), max_before - 2.0, "current health follows the lower maximum")
	assert_signal_emitted(player.health, "health_changed", "the HUD hearts update")
	assert_true(player.is_alive())


func test_frailty_never_goes_below_one_heart() -> void:
	var player := _player()
	player.health.reset(2.0)
	assert_false(PlayerCurses.can_take(player, PlayerCurses.Curse.FRAILTY))
	assert_false(PlayerCurses.get_available(player).has(PlayerCurses.Curse.FRAILTY))
	assert_false(PlayerCurses.ensure(player).add_curse(PlayerCurses.Curse.FRAILTY))
	assert_eq(player.health.get_max_health(), 2.0)


func test_curses_are_per_player() -> void:
	var cursed := _player()
	var other := _player()
	PlayerCurses.ensure(cursed).add_curse(PlayerCurses.Curse.HASTE)
	PlayerCurses.ensure(cursed).add_curse(PlayerCurses.Curse.DRY_FOUNTAINS)
	assert_almost_eq(PlayerCurses.enemy_speed_factor(cursed), 1.1, 0.0001)
	assert_eq(PlayerCurses.enemy_speed_factor(other), 1.0, "the pact only curses who sealed it")
	assert_almost_eq(PlayerCurses.group_enemy_speed_factor([other, cursed]), 1.1, 0.0001)
	assert_eq(PlayerCurses.group_enemy_speed_factor([other]), 1.0)
	assert_eq(FOUNTAIN_SCRIPT.get_heal_amount(cursed), 1.5, "fountain heals half")
	assert_eq(FOUNTAIN_SCRIPT.get_heal_amount(other), 3.0)


# --- Pact altar ---

func test_pact_altar_in_a_third_of_the_upgrade_rooms() -> void:
	var pacts := 0
	var context := _context()
	for i in 600:
		var altar := ALTAR.instantiate() as SpecialContent
		add_child(altar)
		altar.setup(context, null)
		if altar.get(&"is_pact"):
			pacts += 1
		altar.free()
	assert_almost_eq(pacts / 600.0, 1.0 / 3.0, 0.06)


func test_normal_choice_on_a_pact_altar_costs_nothing() -> void:
	var player := _player()
	var altar := _altar(_context(player), true, PlayerCurses.Curse.GLOOM)
	var swing := _upgrade(&"wide_swing")
	assert_true(altar.call(&"take_choice", player, swing, -1))
	assert_eq(_upgrades.get_stacks(swing.id), 1)
	assert_eq(PlayerCurses.get_curses_of(player).size(), 0)
	assert_false(altar.call(&"take_choice", player, swing, -1), "one choice per player")


func test_pact_gives_one_stack_more_and_the_curse() -> void:
	var player := _player()
	var altar := _altar(_context(player), true, PlayerCurses.Curse.GLOOM)
	watch_signals(altar)
	var strength := _upgrade(&"strong_attack")
	assert_false(altar.call(&"take_choice", player, strength, PlayerCurses.Curse.HASTE), "only the curse the altar shows")
	assert_true(altar.call(&"take_choice", player, strength, PlayerCurses.Curse.GLOOM))
	assert_eq(_upgrades.get_stacks(strength.id), 2, "a stack more than the normal altar")
	assert_true(PlayerCurses.has_curse(player, PlayerCurses.Curse.GLOOM))
	assert_signal_emitted_with_parameters(altar, "choice_taken", [player, strength, PlayerCurses.Curse.GLOOM])


func test_pact_offer_prefers_upgrades_that_take_the_extra_stack() -> void:
	var player := _player()
	var altar := _altar(_context(player), true, PlayerCurses.Curse.HASTE)
	var owned := player.weapon_controller.get_owned_weapons()
	for i in 30:
		var offer: Array[UpgradeData] = altar.call(&"roll_pact_offer", owned)
		assert_eq(offer.size(), 3)
		for upgrade in offer:
			var room_left := upgrade.max_stacks - _upgrades.get_stacks(upgrade.id)
			assert_true(not upgrade.is_limited() or room_left >= 2, "%s can take two stacks" % upgrade.id)


func test_pact_curse_falls_back_to_one_the_player_can_take() -> void:
	var player := _player()
	PlayerCurses.ensure(player).add_curse(PlayerCurses.Curse.GLOOM)
	var altar := _altar(_context(player), true, PlayerCurses.Curse.GLOOM)
	assert_eq(altar.call(&"get_curse_for", player), PlayerCurses.Curse.FRAILTY, "next curse in order")
	for curse: PlayerCurses.Curse in PlayerCurses.Curse.values():
		PlayerCurses.ensure(player).add_curse(curse)
	assert_eq(altar.call(&"get_curse_for", player), -1, "nothing left: only the normal upgrade")


func test_a_normal_altar_never_takes_a_pact() -> void:
	var player := _player()
	var altar := _altar(_context(player), false)
	assert_false(altar.get(&"is_pact"))
	assert_false(altar.call(&"take_choice", player, _upgrade(&"strong_attack"), PlayerCurses.Curse.HASTE))
	assert_true(altar.call(&"take_choice", player, _upgrade(&"strong_attack"), -1))


func test_every_player_seals_their_own_pact() -> void:
	var first := _player()
	var second := _player()
	var altar := _altar(_context(first), true, PlayerCurses.Curse.HASTE)
	assert_true(altar.call(&"take_choice", first, _upgrade(&"strong_attack"), PlayerCurses.Curse.HASTE))
	assert_true(altar.call(&"take_choice", second, _upgrade(&"strong_attack"), -1))
	assert_true(PlayerCurses.has_curse(first, PlayerCurses.Curse.HASTE))
	assert_false(PlayerCurses.has_curse(second, PlayerCurses.Curse.HASTE))


# --- Dialogs and Tab overview ---

func _ui(context: DungeonContext) -> DungeonUI:
	var ui: DungeonUI = add_child_autofree(DungeonUI.new())
	ui.auto_enemy_hints = false
	ui.show_controls_hint = false
	ui.context = context
	context.ui = ui
	return ui


func _labels(root: Node) -> Array[String]:
	var labels: Array[String] = []
	for label: Label in root.find_children("*", "Label", true, false):
		labels.append(label.text)
	return labels


func test_pact_offer_cards_show_the_extra_stack() -> void:
	var context := _context(_player())
	var ui := _ui(context)
	var offer: Array[UpgradeData] = [_upgrade(&"strong_attack"), _upgrade(&"wide_swing")]
	var result: Array = [null]
	var ask := func() -> void: result[0] = await ui.choose_upgrade(offer, "Pakt", 2)
	ask.call()
	await wait_physics_frames(2)
	var modal := ui.find_children("*", "Modal", true, false)
	assert_eq(modal.size(), 1)
	var labels := _labels(modal[0])
	assert_true(labels.has("Stufe 0 → 2 · unbegrenzt"), "unlimited upgrade +2")
	assert_true(labels.has("0 / 3 → 2 / 3"), "limited upgrade +2")
	(modal[0] as Modal).finish(offer[0])
	await wait_physics_frames(2)
	assert_eq(result[0], offer[0])


func test_tab_overview_shows_the_curses() -> void:
	var player := _player()
	var context := _context(player)
	var ui := _ui(context)
	ui.show_upgrade_overview()
	await wait_physics_frames(2)
	var modal := ui.find_children("*", "Modal", true, false)
	assert_eq(modal.size(), 1)
	assert_eq(modal[0].find_children("Curses", "", true, false).size(), 0, "no curse, no curse row")
	(modal[0] as Modal).finish(null)
	await wait_physics_frames(2)
	PlayerCurses.ensure(player).add_curse(PlayerCurses.Curse.GLOOM)
	PlayerCurses.ensure(player).add_curse(PlayerCurses.Curse.FRAILTY)
	ui.show_upgrade_overview()
	await wait_physics_frames(2)
	modal = ui.find_children("*", "Modal", true, false)
	assert_eq(modal.size(), 1)
	assert_eq(modal[0].find_children("Curses", "", true, false).size(), 1)
	var labels := _labels(modal[0])
	assert_true(labels.has(PlayerCurses.get_curse_name(PlayerCurses.Curse.GLOOM)))
	assert_true(labels.has("Lichtkreis −20 %"))
	assert_true(labels.has(PlayerCurses.get_curse_name(PlayerCurses.Curse.FRAILTY)))
	(modal[0] as Modal).finish(null)
	await wait_physics_frames(2)
	assert_false(GameManager.is_game_paused())


func test_curse_icons_fall_back_to_placeholders() -> void:
	var icon := CurseArt.get_icon(PlayerCurses.Curse.HASTE)
	assert_not_null(icon)
	assert_eq(Vector2i(icon.get_size()), Vector2i(16, 16))
	assert_eq(Vector2i(CurseArt.get_strip().get_size()), Vector2i(64, 16), "4 symbols of 16x16 (SPRITES_V5 §4)")
	for art_name in [TrialArt.PENDULUM, TrialArt.FLAME_JET, TrialArt.PACT_ALTAR, TrialArt.CHEST_OPEN, TrialArt.TORCH_STAND, TrialArt.TORCH_UNLIT, TrialArt.PLATE, TrialArt.CHEST_CLOSED]:
		var texture := TrialArt.get_texture(art_name)
		var size := TrialArt.get_frame_size(art_name)
		assert_eq(Vector2i(texture.get_size()), Vector2i(size.x * TrialArt.get_frame_count(art_name), size.y), art_name)

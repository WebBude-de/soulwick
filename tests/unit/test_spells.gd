extends GutTest
## Spells (KE7, KONZEPT §6.2): the five spells' data and texts, the loadout from the talents, damage
## with the run multipliers and cooldowns with Konzentration, casting from the player's input object
## (MP1) only where the game is decided, the effects at the player, the wisps, the client's replay
## from the host's cast event and Flint's cast reaction. Never touches a save.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const ENEMY_SCENE_PATH := "res://enemies/enemy_base.tscn"
const STEP := 1.0 / 60.0

var _tree: TalentTree
var _old_save_path: String


## An input object with presses set by hand (like a network packet would).
class HandInput:
	extends PlayerInput

	func tap(action: StringName) -> void:
		_just_pressed[action] = true
		_pressed[action] = true

	func poll(_body: Node2D) -> void:
		pass


## PlayerSpells of a machine that does not decide the game (a client).
class ClientSpells:
	extends PlayerSpells

	func is_authority() -> bool:
		return false


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_spells_save.cfg"
	_tree = TalentTree.get_default()


func after_all() -> void:
	SaveManager.save_path = _old_save_path
	_free_effects()


func after_each() -> void:
	_free_effects()


## Effects of casts (sparks, flashes, rings, wisps, damage numbers) land next to the player, i.e.
## under this test.
func _free_effects() -> void:
	for child in get_children():
		if child is WillOWisp or child is SpellRing or child is SpellSpark or child is CPUParticles2D \
				or child is LightSource or child is AnimatedSprite2D or child is Label:
			child.free()


func _player() -> Player:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.set_physics_process(false)
	return player


func _spells(player: Player, loadout: Array[StringName]) -> PlayerSpells:
	var spells := PlayerSpells.attach_to(player)
	spells.set_physics_process(false)
	spells.set_loadout(loadout)
	return spells


func _state(ids: Array) -> TalentState:
	var state := TalentState.new()
	for id: StringName in ids:
		var talent := _tree.get_talent(id)
		for i in talent.max_level:
			assert_true(state.raise(id, 99, _tree), "raise %s" % id)
	return state


func _enemy_at(position: Vector2) -> Enemy:
	var enemy: Enemy = load(ENEMY_SCENE_PATH).instantiate()
	enemy.data = load("res://enemies/data/slime.tres")
	add_child_autofree(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = position
	enemy.health.reset(1000.0)
	return enemy


# --- Data and texts ---

func test_five_spells_with_the_concept_numbers() -> void:
	assert_eq(SpellBook.IDS.size(), 5)
	assert_eq(SpellBook.IDS, _tree.get_spells(), "the ids the talent tree unlocks, in its order")
	var flash := SpellBook.get_spell(SpellBook.LIGHT_FLASH)
	assert_eq(flash.effect, SpellData.Effect.BLIND_AREA)
	assert_eq(flash.get_radius_tiles(), 3.0)
	assert_eq(flash.duration, 1.0)
	assert_eq(flash.cooldown, 12.0)
	var shield := SpellBook.get_spell(SpellBook.SOUL_SHIELD)
	assert_eq([shield.effect, shield.amount, shield.cooldown], [SpellData.Effect.SHIELD, 4.0, 15.0])
	var ring := SpellBook.get_spell(SpellBook.FLAME_RING)
	assert_eq([ring.effect, ring.amount, ring.get_radius_tiles(), ring.cooldown], [SpellData.Effect.DAMAGE_AREA, 3.0, 2.5, 10.0])
	assert_gt(ring.knockback, 0.0, "Rückstoß")
	var wisps := SpellBook.get_spell(SpellBook.WILL_O_WISP)
	assert_eq([wisps.effect, wisps.count, wisps.amount, wisps.cooldown], [SpellData.Effect.HOMING_LIGHTS, 3, 2.0, 9.0])
	var heal := SpellBook.get_spell(SpellBook.HEAL_SPARK)
	assert_eq([heal.effect, heal.amount, heal.get_radius_tiles(), heal.cooldown], [SpellData.Effect.HEAL_AREA, 2.0, 4.0, 25.0])
	assert_null(SpellBook.get_spell(&"fireball"), "unknown ids have no data")


func test_every_spell_has_texts_in_both_languages() -> void:
	for id in SpellBook.IDS:
		for language in [&"en", &"de"]:
			assert_true(Loc.has_key(SpellBook.name_key(id), language), "%s name (%s)" % [id, language])
			assert_true(Loc.has_key(SpellBook.description_key(id), language), "%s description (%s)" % [id, language])
		var text := SpellBook.description(id)
		assert_false(text.contains("%"), "%s description is filled in: %s" % [id, text])
		assert_ne(SpellBook.display_name(id), String(SpellBook.name_key(id)))


# --- Loadout, damage, cooldown ---

func test_loadout_from_the_talents() -> void:
	assert_eq(SpellEffects.loadout_of(TalentStats.new()), [] as Array[StringName], "no talents, no spells")
	var state := _state([&"light_flash", &"spell_power", &"focus", &"soul_shield", &"flame_ring"])
	var stats := TalentEffects.resolve(state, _tree)
	assert_eq(SpellEffects.loadout_of(stats), [&"light_flash"] as Array[StringName], "nothing equipped yet: the first unlocked, one slot")
	state.equip_spell(&"flame_ring", 0, _tree)
	assert_eq(SpellEffects.loadout_of(TalentEffects.resolve(state, _tree)), [&"flame_ring"] as Array[StringName], "the equipped one")
	var player := _player()
	TalentEffects.apply_to(player, state, _tree).set_physics_process(false)
	var spells := PlayerSpells.attach_to(player)
	assert_eq(spells.get_loadout(), [&"flame_ring"] as Array[StringName], "PlayerSpells reads the talents")
	spells.set_loadout([&"heal_spark", &"nonsense", &"heal_spark", &"soul_shield", &"flame_ring"] as Array[StringName])
	assert_eq(spells.get_loadout(), [&"heal_spark", &"soul_shield"] as Array[StringName], "override: known, unique, two slots")
	spells.clear_loadout()
	assert_eq(spells.get_spell(0), &"flame_ring")


func test_damage_grows_like_weapon_damage() -> void:
	var player := _player()
	assert_almost_eq(SpellEffects.damage(player, 3.0), 3.0, 0.0001, "no bonuses")
	var upgrades: UpgradeManager = autofree(UpgradeManager.new())
	for path in ["res://upgrades/data/strong_attack.tres", "res://upgrades/data/magic_power.tres", "res://upgrades/data/strength_training.tres"]:
		var upgrade: UpgradeData = load(path)
		upgrades.upgrade_pool.append(upgrade)
		upgrades.acquire_upgrade(upgrade)
	player.weapon_controller.upgrades = upgrades
	assert_almost_eq(SpellEffects.damage(player, 3.0), 3.3, 0.0001, "Starker Angriff (+10 %, every attack) counts; Magiekraft and Krafttraining are weapon upgrades")
	TalentEffects.apply_to(player, _state([&"light_flash", &"spell_power"]), _tree).set_physics_process(false)
	assert_almost_eq(SpellEffects.damage(player, 3.0), 3.0 * (1.0 + 0.1 + 0.3), 0.0001, "Zauberkraft adds to the percent sum (D-019)")
	var hit := SpellEffects.make_hit(player, SpellBook.get_spell(SpellBook.FLAME_RING), 3.0)
	assert_eq(hit.origin, DamageData.Origin.SECONDARY, "no Explosiver Treffer chains")
	assert_true(hit.tags.has(SpellEffects.SPELL_TAG) and hit.tags.has(SpellBook.FLAME_RING))
	assert_eq(hit.source, player)


func test_cooldown_with_konzentration() -> void:
	var player := _player()
	var ring := SpellBook.get_spell(SpellBook.FLAME_RING)
	assert_almost_eq(SpellEffects.cooldown(player, ring), 10.0, 0.0001)
	TalentEffects.apply_to(player, _state([&"light_flash", &"spell_power", &"focus"]), _tree).set_physics_process(false)
	assert_almost_eq(SpellEffects.cooldown(player, ring), 7.6, 0.0001, "3 × 8 % less")


# --- Casting ---

func test_attach_is_idempotent_and_found_from_children() -> void:
	var player := _player()
	var spells := PlayerSpells.attach_to(player)
	assert_eq(PlayerSpells.attach_to(player), spells)
	assert_eq(PlayerSpells.of(player.weapon_controller), spells, "from a child of the player")
	assert_eq(spells.name, String(PlayerSpells.NODE_NAME))
	assert_null(PlayerSpells.of(_player()), "another player has none until attached")


func test_cast_from_the_input_object_then_cooldown() -> void:
	var player := _player()
	var spells := _spells(player, [&"soul_shield"] as Array[StringName])
	var input := HandInput.new()
	player.input = input
	watch_signals(spells)
	input.tap(PlayerSpells.ACTION)
	spells._physics_process(STEP)
	assert_signal_emit_count(spells, "spell_cast", 1, "the press casts")
	assert_eq(player.shield.get_shield(), 4.0, "Seelenschild +4")
	assert_almost_eq(spells.get_cooldown_left(0), 15.0, 0.001)
	assert_almost_eq(spells.get_cooldown_share(0), 1.0, 0.001)
	assert_false(spells.is_ready(0))
	input.tap(PlayerSpells.ACTION)
	spells._physics_process(STEP)
	assert_signal_emit_count(spells, "spell_cast", 1, "cooling down")
	spells.tick(15.0)
	assert_true(spells.is_ready(0), "ready after 15 s")
	assert_true(spells.press(0))
	assert_eq(player.shield.get_shield(), 8.0)


func test_no_cast_while_stunned_or_down() -> void:
	var player := _player()
	var spells := _spells(player, [&"soul_shield"] as Array[StringName])
	player.stun(1.0)
	assert_false(spells.can_cast(), "stunned")
	assert_false(spells.try_cast_slot(0))
	var other := _player()
	var other_spells := _spells(other, [&"soul_shield"] as Array[StringName])
	other.set_input_locked(&"intro", true)
	assert_false(other_spells.can_cast(), "locked (intro, menu)")
	other.set_input_locked(&"intro", false)
	other.health.take_damage(INF)
	assert_false(other_spells.can_cast(), "down")
	assert_false(_spells(_player(), [] as Array[StringName]).try_cast_slot(0), "no spell in the slot")


func test_one_button_or_two_buttons_pick_the_slot() -> void:
	assert_eq(PlayerSpells.slot_for_button(0, [true, true] as Array[bool], true), 0)
	assert_eq(PlayerSpells.slot_for_button(1, [true, true] as Array[bool], true), 1)
	assert_eq(PlayerSpells.slot_for_button(0, [false, true] as Array[bool], true), -1, "two buttons: slot 1 waits")
	assert_eq(PlayerSpells.slot_for_button(0, [false, true] as Array[bool], false), 1, "one button: the next ready spell")
	assert_eq(PlayerSpells.slot_for_button(0, [false, false] as Array[bool], false), -1)
	assert_eq(PlayerSpells.slot_for_button(1, [true] as Array[bool], true), -1, "no second slot")
	assert_eq(PlayerSpells.slot_for_button(0, [] as Array[bool], false), -1)


func test_a_client_never_casts_but_replays_the_hosts_event() -> void:
	var player := _player()
	var spells := ClientSpells.new()
	spells.name = PlayerSpells.NODE_NAME
	player.add_child(spells)
	spells.set_physics_process(false)
	var input := HandInput.new()
	player.input = input
	watch_signals(spells)
	input.tap(PlayerSpells.ACTION)
	spells._physics_process(STEP)
	assert_signal_emit_count(spells, "spell_cast", 0, "the press only travels to the host")
	player.health.take_damage(2.0)
	var before := player.health.get_health()
	spells.play_remote_cast(SpellBook.HEAL_SPARK, 0, Vector2.RIGHT, 19.0)
	assert_eq(player.health.get_health(), before, "the heal comes with the host's vitals, not from the look")
	assert_eq(spells.get_loadout(), [&"heal_spark"] as Array[StringName], "the HUD learns the spell from the event")
	assert_almost_eq(spells.get_cooldown_left(0), 19.0, 0.001, "the host's cooldown")
	assert_signal_emitted_with_parameters(spells, "spell_shown", [SpellBook.HEAL_SPARK, Vector2.RIGHT, true])
	assert_signal_emit_count(spells, "spell_cast", 0)


func test_flint_reacts_and_the_effect_starts_at_his_flame() -> void:
	var player := _player()
	var flint := FlintCompanion.attach_to(player)
	var spells := _spells(player, [&"soul_shield"] as Array[StringName])
	assert_eq(SpellEffects.cast_origin(player), flint.get_light_center(), "spells start at Flint's flame")
	assert_true(spells.try_cast_slot(0))
	flint._process(STEP)
	assert_eq(flint.get_mood(), FlintMood.Mood.CAST, "Flint casts visibly")
	var without := _player()
	assert_eq(SpellEffects.cast_origin(without), without.global_position, "without Flint: the body centre")


# --- Effects ---

func test_heal_spark_heals_players_in_reach() -> void:
	var caster := _player()
	var near := _player()
	var far := _player()
	caster.global_position = Vector2(1000, 1000)
	near.global_position = caster.global_position + Vector2(200, 0)
	far.global_position = caster.global_position + Vector2(400, 0)
	for player in [caster, near, far]:
		player.health.take_damage(3.0)
	var max_hp := caster.health.get_max_health()
	var healed := SpellEffects.apply(caster, SpellBook.get_spell(SpellBook.HEAL_SPARK), Vector2.RIGHT)
	assert_true(healed.has(caster) and healed.has(near), "caster and the teammate within 4 tiles")
	assert_false(healed.has(far), "not 6 tiles away")
	assert_eq(caster.health.get_health(), max_hp - 1.0)
	assert_eq(near.health.get_health(), max_hp - 1.0)
	assert_eq(far.health.get_health(), max_hp - 3.0)


func test_light_flash_blinds_enemies_in_reach() -> void:
	var caster := _player()
	caster.global_position = Vector2(2000, 2000)
	var near := _enemy_at(caster.global_position + Vector2(120, 0))
	var far := _enemy_at(caster.global_position + Vector2(400, 0))
	var blinded := SpellEffects.apply(caster, SpellBook.get_spell(SpellBook.LIGHT_FLASH), Vector2.RIGHT)
	assert_eq(blinded, [near], "only the enemy within 3 tiles")
	if not near.has_method(&"apply_blind"):
		assert_true(near.is_slowed(), "until Enemy.apply_blind exists: held in place")
	assert_false(far.is_slowed())


func test_flame_ring_hits_enemies_in_reach() -> void:
	var caster := _player()
	caster.global_position = Vector2(3000, 3000)
	var near := _enemy_at(caster.global_position + Vector2(100, 0))
	var far := _enemy_at(caster.global_position + Vector2(300, 0))
	await wait_physics_frames(2)
	var results := SpellEffects.apply(caster, SpellBook.get_spell(SpellBook.FLAME_RING), Vector2.RIGHT)
	assert_eq(results.size(), 1, "one hurtbox within 2.5 tiles")
	assert_almost_eq(near.health.get_health(), 997.0, 0.001, "3 damage")
	assert_eq(far.health.get_health(), 1000.0)


func test_wisps_fan_out_home_in_and_hit_once() -> void:
	var caster := _player()
	caster.global_position = Vector2(4000, 4000)
	var data := SpellBook.get_spell(SpellBook.WILL_O_WISP)
	assert_almost_eq(WillOWisp.fan_angle(0, 3), -WillOWisp.fan_angle(2, 3), 0.0001, "symmetric fan")
	assert_eq(WillOWisp.fan_angle(1, 3), 0.0, "the middle one flies along the aim")
	var enemies := [_enemy_at(caster.global_position + Vector2(160, -40)), _enemy_at(caster.global_position + Vector2(160, 40))]
	var wisps := WillOWisp.launch_all(caster, data, caster.global_position, Vector2.RIGHT, 2.0, true)
	assert_eq(wisps.size(), 3)
	var hits: Array = []
	for wisp: WillOWisp in wisps:
		wisp.set_physics_process(false)
		wisp.hit_enemy.connect(func(enemy: Enemy) -> void: hits.append(enemy))
	for i in 180:
		for wisp: WillOWisp in wisps:
			if is_instance_valid(wisp):
				wisp.step(STEP)
	assert_eq(hits.size(), 3, "every wisp hit")
	assert_true(hits.has(enemies[0]) and hits.has(enemies[1]), "the wisps spread over both enemies")
	var lost := 0.0
	for enemy: Enemy in enemies:
		lost += 1000.0 - enemy.health.get_health()
	assert_almost_eq(lost, 6.0, 0.001, "3 × 2 damage")


func test_look_only_wisps_deal_no_damage() -> void:
	var caster := _player()
	caster.global_position = Vector2(5000, 5000)
	var enemy := _enemy_at(caster.global_position + Vector2(100, 0))
	var wisps := WillOWisp.launch_all(caster, SpellBook.get_spell(SpellBook.WILL_O_WISP), caster.global_position, Vector2.RIGHT, 2.0, false)
	for i in 180:
		for wisp: WillOWisp in wisps:
			if is_instance_valid(wisp):
				wisp.set_physics_process(false)
				wisp.step(STEP)
	assert_eq(enemy.health.get_health(), 1000.0, "a client's wisps only show")


func test_every_spell_casts_and_shows_without_errors() -> void:
	var caster := _player()
	caster.global_position = Vector2(6000, 6000)
	FlintCompanion.attach_to(caster)
	_enemy_at(caster.global_position + Vector2(90, 0))
	await wait_physics_frames(2)
	var spells := _spells(caster, [] as Array[StringName])
	for id in SpellBook.IDS:
		spells.set_loadout([id] as Array[StringName])
		assert_true(spells.try_cast_slot(0), "%s casts" % id)
		spells.play_remote_cast(id, 0, Vector2.LEFT, 1.0)
	await wait_process_frames(3)
	assert_true(true, "looks of all five spells played on host and client side")

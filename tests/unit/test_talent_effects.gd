extends GutTest
## What talents do (KE6, KONZEPT §6.1, D-019): the pure resolution of a distribution, the run-start
## values on a real player (taken back on a new distribution), the hooks for weapons, hits, stun,
## revive and spells, and the reacting talents: Ausweichkunst after a dash, Windläufer trail,
## Glutherz wave, Zweites Herz (alone once per run, in a group faster revive). Never touches a save.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const STEP := 1.0 / 60.0
const SWORD: Array[StringName] = [&"melee", &"sword", &"swing"]
const DAGGER: Array[StringName] = [&"melee", &"dagger", &"swing"]
const BOW: Array[StringName] = [&"ranged", &"projectile", &"bow"]
const STAFF: Array[StringName] = [&"ranged", &"projectile", &"magic", &"aoe", &"staff"]

var _tree: TalentTree
var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_talent_effects_save.cfg"
	_tree = TalentTree.get_default()


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func after_each() -> void:
	HitStop.reset()
	# Dash dust, trails, sparks and light flashes land next to the player, i.e. under this test.
	for child in get_children():
		if child is WindRunnerTrail or child is AnimatedSprite2D or child is CPUParticles2D or child is LightSource:
			child.queue_free()
	await wait_process_frames(1)


## A distribution of whole talents (each at max level), checked against the rules.
func _state(ids: Array) -> TalentState:
	var state := TalentState.new()
	for id: StringName in ids:
		var talent := _tree.get_talent(id)
		for i in talent.max_level:
			assert_true(state.raise(id, 99, _tree), "raise %s" % id)
	return state


func _wind() -> TalentState:
	return _state([&"light_foot", &"dash_training", &"swift_blade", &"evasion", &"double_dash", &"wind_runner"])


func _ember() -> TalentState:
	return _state([&"vitality", &"might", &"steadfast", &"shield_breaker", &"second_heart", &"ember_heart"])


func _soul() -> TalentState:
	var state := _state([&"light_flash", &"spell_power", &"focus", &"soul_shield", &"flame_ring", &"staff_master", &"second_spell_slot"])
	state.equip_spell(&"light_flash", 0, _tree)
	state.equip_spell(&"flame_ring", 1, _tree)
	return state


## A player driven by hand (no own physics step) with talents on it.
func _player_with(state: TalentState) -> Player:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.set_physics_process(false)
	var talents := TalentEffects.apply_to(player, state, _tree)
	talents.set_physics_process(false)
	return player


func _step(player: Player, seconds: float) -> void:
	var talents := PlayerTalents.of(player)
	var time := 0.0
	while time < seconds:
		player._tick_timers(STEP)
		talents._physics_process(STEP)
		time += STEP


# --- Pure resolution ---

func test_no_talents_are_neutral() -> void:
	var stats := TalentEffects.resolve(TalentState.new(), _tree)
	assert_true(stats.is_neutral())
	assert_eq(stats.damage_percent(SWORD), 0.0)
	assert_eq(stats.stagger_multiplier(), 1.0)
	assert_eq(stats.spell_cooldown_multiplier(), 1.0)
	assert_true(TalentEffects.stats_of(null).is_neutral(), "no owner, neutral numbers")
	assert_eq(TalentEffects.attack_multiplier(null), 1.0)
	assert_eq(TalentEffects.target_multiplier(null, null), 1.0)


func test_wind_path() -> void:
	var stats := TalentEffects.resolve(_wind(), _tree)
	assert_almost_eq(stats.move_speed_percent, 0.15, 0.0001, "Leichtfuß 3 × 5 %")
	assert_almost_eq(stats.dash_cooldown_reduction, 0.45, 0.0001, "Dash-Training 3 × 0,15 s")
	assert_almost_eq(stats.attack_rate_percent(DAGGER), 0.24, 0.0001, "Flinke Klinge on daggers")
	assert_almost_eq(stats.attack_rate_percent(BOW), 0.24, 0.0001, "and bows")
	assert_eq(stats.attack_rate_percent(SWORD), 0.0, "not on swords")
	assert_almost_eq(stats.evasion_damage_percent, 0.3, 0.0001, "Ausweichkunst 2 × 15 %")
	assert_eq(stats.dash_charges, 2, "Doppel-Dash")
	assert_true(stats.wind_runner)
	assert_almost_eq(TalentEffects.move_speed(180.0, stats), 207.0, 0.001)
	assert_almost_eq(TalentEffects.dash_cooldown(1.5, stats), 1.05, 0.0001)
	stats.dash_cooldown_reduction = 5.0
	assert_eq(TalentEffects.dash_cooldown(1.5, stats), TalentEffects.MIN_DASH_COOLDOWN, "never below the floor")


func test_ember_path() -> void:
	var stats := TalentEffects.resolve(_ember(), _tree)
	assert_eq(stats.max_health_bonus, 5.0, "Vitalität 5 × 1 HP")
	assert_almost_eq(stats.damage_percent(SWORD), 0.24, 0.0001, "Wucht on swords")
	assert_almost_eq(stats.damage_percent([&"melee", &"hammer"] as Array[StringName]), 0.24, 0.0001, "and hammers")
	assert_eq(stats.damage_percent(BOW), 0.0, "not on bows")
	assert_almost_eq(stats.stagger_multiplier(), 0.5, 0.0001, "Standfest 2 × 25 %")
	assert_almost_eq(stats.breaker_damage_percent, 0.4, 0.0001)
	assert_true(stats.second_heart)
	assert_true(stats.ember_heart)


func test_soul_path() -> void:
	var stats := TalentEffects.resolve(_soul(), _tree)
	assert_almost_eq(stats.spell_damage_percent, 0.3, 0.0001)
	assert_almost_eq(stats.spell_cooldown_multiplier(), 0.76, 0.0001, "Konzentration 3 × 8 %")
	assert_almost_eq(stats.damage_percent(STAFF), 0.16, 0.0001, "Stab-Meister on the staff")
	assert_eq(stats.damage_percent(SWORD), 0.0)
	assert_eq(stats.spell_slots, 2)
	assert_eq(stats.unlocked_spells, [&"light_flash", &"soul_shield", &"flame_ring"] as Array[StringName])
	assert_eq(stats.equipped_spells, [&"light_flash", &"flame_ring"] as Array[StringName])


func test_resolve_ignores_levels_beyond_the_catalog() -> void:
	var state := TalentState.new()
	state.levels[&"vitality"] = 50
	state.levels[&"made_up"] = 3
	var stats := TalentEffects.resolve(state, _tree)
	assert_eq(stats.max_health_bonus, 5.0, "clamped to max level")


func test_breaker_targets() -> void:
	assert_false(TalentEffects.is_breaker_target(null))
	var enemy: Enemy = load("res://enemies/enemy_base.tscn").instantiate()
	enemy.data = load("res://enemies/data/slime.tres")
	assert_false(TalentEffects.is_breaker_target(enemy), "a plain slime")
	enemy.elite = Enemy.Elite.ARMORED
	assert_true(TalentEffects.is_breaker_target(enemy), "armored elite")
	enemy.elite = Enemy.Elite.NONE
	enemy.is_miniboss = true
	assert_true(TalentEffects.is_breaker_target(enemy), "champion")
	enemy.is_miniboss = false
	enemy.data = load("res://enemies/data/skeleton.tres")
	assert_true(TalentEffects.is_breaker_target(enemy), "shield charger")
	enemy.data = load("res://enemies/data/boss_bone_king.tres")
	assert_false(TalentEffects.is_breaker_target(enemy), "bosses are not")
	enemy.free()


# --- On a player ---

func test_run_start_values_on_the_player_and_taken_back() -> void:
	var plain := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	var base_health := plain.health.get_max_health()
	var player := _player_with(_wind())
	assert_almost_eq(player.move_speed, plain.move_speed * 1.15, 0.001, "faster")
	assert_almost_eq(player.dash_cooldown, plain.dash_cooldown - 0.45, 0.0001, "shorter dash cooldown")
	assert_eq(player.health.get_max_health(), base_health, "wind adds no HP")
	TalentEffects.apply_to(player, _ember(), _tree)
	assert_eq(player.get_node(NodePath(PlayerTalents.NODE_NAME)).get_parent(), player)
	assert_eq(player.get_children().filter(func(n: Node) -> bool: return n is PlayerTalents).size(), 1, "one talents node")
	assert_almost_eq(player.move_speed, plain.move_speed, 0.001, "wind taken back")
	assert_almost_eq(player.dash_cooldown, plain.dash_cooldown, 0.0001)
	assert_eq(player.health.get_max_health(), base_health + 5.0, "Vitalität")
	assert_eq(player.health.get_health(), base_health + 5.0, "full at the start")
	TalentEffects.apply_to(player, TalentState.new(), _tree)
	assert_eq(player.health.get_max_health(), base_health, "ember taken back")


func test_weapon_and_spell_hooks_ask_the_owner() -> void:
	var player := _player_with(_ember())
	assert_almost_eq(TalentEffects.damage_bonus(player, SWORD), 0.24, 0.0001)
	assert_almost_eq(TalentEffects.damage_bonus(player.weapon_controller, SWORD), 0.24, 0.0001, "from a child of the player")
	assert_eq(TalentEffects.attack_rate_bonus(player, DAGGER), 0.0)
	assert_almost_eq(TalentEffects.stagger_multiplier(player), 0.5, 0.0001)
	var soul := _player_with(_soul())
	assert_almost_eq(TalentEffects.spell_damage_bonus(soul), 0.3, 0.0001)
	assert_almost_eq(TalentEffects.spell_cooldown_multiplier(soul), 0.76, 0.0001)
	var none := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	assert_eq(TalentEffects.damage_bonus(none, SWORD), 0.0, "a player without talents")


func test_shield_breaker_multiplies_hits_on_champions() -> void:
	var player := _player_with(_ember())
	var enemy: Enemy = load("res://enemies/enemy_base.tscn").instantiate()
	enemy.data = load("res://enemies/data/slime.tres")
	assert_eq(TalentEffects.target_multiplier(player, enemy), 1.0, "plain enemy")
	enemy.is_miniboss = true
	assert_almost_eq(TalentEffects.target_multiplier(player, enemy), 1.4, 0.0001, "champion +40 %")
	var none := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	assert_eq(TalentEffects.target_multiplier(none, enemy), 1.0, "attacker without the talent")
	enemy.free()


func test_evasion_after_a_dash_and_wind_trail() -> void:
	var player := _player_with(_wind())
	var talents := PlayerTalents.of(player)
	watch_signals(talents)
	assert_eq(TalentEffects.attack_multiplier(player), 1.0, "no dash yet")
	player.global_position = Vector2(100, 100)
	assert_true(player.try_dash(Vector2.RIGHT))
	_step(player, STEP)
	player.global_position += Vector2(80, 0)
	_step(player, player.dash_duration + STEP)
	assert_false(player.is_dashing())
	assert_signal_emitted(talents, "evasion_started")
	assert_almost_eq(TalentEffects.attack_multiplier(player), 1.3, 0.0001, "+30 % right after the dash")
	assert_signal_emitted(talents, "wind_trail_spawned")
	var trail := get_signal_parameters(talents, "wind_trail_spawned")[0] as WindRunnerTrail
	assert_not_null(trail)
	assert_gt(trail.from.distance_to(trail.to), 50.0, "the trail spans the dash")
	_step(player, TalentEffects.EVASION_TIME)
	assert_eq(TalentEffects.attack_multiplier(player), 1.0, "over after 1 s")


func test_wind_trail_finds_enemies_on_it_and_fades() -> void:
	var enemy: Enemy = load("res://enemies/enemy_base.tscn").instantiate()
	enemy.data = load("res://enemies/data/slime.tres")
	add_child_autofree(enemy)
	enemy.global_position = Vector2(400, 300)
	enemy.set_physics_process(false)
	var trail := WindRunnerTrail.create(Vector2(300, 300), Vector2(500, 300), null)
	add_child_autofree(trail)
	await wait_physics_frames(3)
	assert_true(trail.find_enemies().has(enemy), "enemy on the trail")
	var away := WindRunnerTrail.create(Vector2(300, 600), Vector2(500, 600), null)
	add_child_autofree(away)
	await wait_physics_frames(2)
	assert_false(away.find_enemies().has(enemy), "enemy beside the trail")
	trail._physics_process(TalentEffects.WIND_TRAIL_LIFETIME + 0.1)
	assert_true(trail.is_queued_for_deletion(), "gone after its lifetime")


func test_ember_heart_below_two_hp_with_cooldown() -> void:
	var player := _player_with(_ember())
	var talents := PlayerTalents.of(player)
	assert_true(talents.should_trigger_ember_wave(1.5, true))
	assert_false(talents.should_trigger_ember_wave(2.0, true), "not at 2 HP")
	assert_false(talents.should_trigger_ember_wave(1.5, false), "only effective hits")
	assert_false(talents.should_trigger_ember_wave(0.0, true), "not when down")
	watch_signals(talents)
	player.health.take_damage(player.health.get_health() - 2.0)
	var hit := DamageData.new()
	hit.amount = 0.5
	hit.hit_id = DamageData.next_hit_id()
	player.hurtbox.receive_hit(hit)
	assert_signal_emit_count(talents, "ember_wave_triggered", 1, "wave at 1.5 HP")
	assert_almost_eq(talents.get_ember_cooldown_left(), TalentEffects.EMBER_HEART_COOLDOWN, 0.001)
	assert_false(talents.should_trigger_ember_wave(1.0, true), "cooling down")
	_step(player, TalentEffects.EMBER_HEART_COOLDOWN + STEP)
	assert_true(talents.should_trigger_ember_wave(1.0, true), "ready again after 10 s")
	var plain := _player_with(_wind())
	assert_false(PlayerTalents.of(plain).should_trigger_ember_wave(1.0, true), "without the talent")


func test_second_heart_alone_once_per_run() -> void:
	var player := _player_with(_ember())
	var talents := PlayerTalents.of(player)
	watch_signals(talents)
	assert_true(talents.can_use_second_heart())
	assert_eq(talents.claim_second_heart(), TalentEffects.SECOND_HEART_HEALTH, "stands up with 2 HP")
	assert_signal_emitted(talents, "second_heart_used")
	assert_true(talents.is_second_heart_used())
	assert_eq(talents.claim_second_heart(), 0.0, "only once per run")
	var plain := _player_with(_wind())
	assert_eq(PlayerTalents.of(plain).claim_second_heart(), 0.0, "without the talent")
	assert_eq(TalentEffects.revive_speed(player), TalentEffects.SECOND_HEART_REVIVE_SPEED, "group revive twice as fast")
	assert_eq(TalentEffects.revive_speed(plain), 1.0)

extends GutTest
## Wave 1 wiring (KE1, KE2, KE6): the own danger level for "Neuer Run" from the run end, the group
## level the host sends with the run start, the solo character's talents stored on the account and
## put on the player at the spawn (solo: DungeonManager; quick game: the host from the lobby profile),
## and the talent hooks in player, weapons, hits, health and enemies (Doppel-Dash, Zweites Herz,
## Standfest, Schildbrecher rounding, Windläufer slow). progress.cfg and the save live in a test
## folder, never the real ones (AGENTS.md rule 4).

const ROOT := "user://test_wave1_integration"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://enemies/enemy_base.tscn")
const STEP := 1.0 / 60.0

var _tree: TalentTree
var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String
var _old_danger: int


## Run end screen that always answers "Neuer Run".
class NewRunUI extends GameUI:
	func show_run_end(_summary: Dictionary, _stats: Dictionary = {}) -> StringName:
		return GameUI.RUN_END_NEW_RUN


## World controller that only records which world it would load.
class RecordingController extends WorldController:
	var loaded: PackedScene = null

	func load_world(scene: PackedScene) -> void:
		loaded = scene


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	_old_danger = RunManager.get_danger_level()
	_tree = TalentTree.get_default()


func before_each() -> void:
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()
	AccountProgress.path_override = ""
	AccountProgress.reset()
	AccountProgress.spent_points_source = func() -> int: return AccountTalents.spent_points()


func after_each() -> void:
	HitStop.reset()
	# Players, enemies and the dash dust they leave next to them.
	for child in get_children():
		if child is CanvasItem:
			child.queue_free()
	await wait_process_frames(1)


func after_all() -> void:
	_wipe()
	AccountProgress.path_override = ""
	AccountProgress.reset()
	RunManager.set_danger_level(_old_danger)
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()
	PlayerProfile.reset()


func _wipe() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	for dir_path in [root.path_join("saves"), root]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			DirAccess.remove_absolute(dir_path.path_join(file))
	DirAccess.make_dir_recursive_absolute(root.path_join("saves"))


## This machine's account at level (no runs: the danger level follows the level).
func _account_at_level(level: int) -> AccountProgress:
	var progress := AccountProgress.current()
	progress.xp = AccountProgress.xp_for_level(level)
	progress.entries.clear()
	return progress


## Whole talents (each at max level), checked against the rules.
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


func _player_with(state: TalentState) -> Player:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.set_physics_process(false)
	if state != null:
		TalentEffects.apply_to(player, state, _tree).set_physics_process(false)
	return player


func _step(player: Player, seconds: float) -> void:
	var time := 0.0
	while time < seconds:
		player._tick_timers(STEP)
		time += STEP


# --- Danger level ---

func test_new_run_from_the_run_end_uses_the_own_danger_level() -> void:
	_account_at_level(11)
	var own := AccountProgress.current().get_danger_level()
	assert_gt(own, 0, "level 11 has a danger level")
	RunManager.set_danger_level(0)
	var controller := RecordingController.new()
	var ui := NewRunUI.new()
	controller.game_ui = ui
	controller.dungeon_scene = PackedScene.new()
	controller.village_scene = PackedScene.new()
	await controller._on_run_ended(RunManager.EndReason.DEATH, 0, 0)
	assert_eq(controller.loaded, controller.dungeon_scene, "straight into the dungeon")
	assert_eq(RunManager.get_danger_level(), own, "the new run starts on the own level")
	ui.free()
	controller.free()


func test_host_group_level_and_client_run_start() -> void:
	_account_at_level(11)
	var own := AccountProgress.current().get_danger_level()
	var run := NetRun.new()
	add_child_autofree(run)
	run._profiles[7] = {"danger": own + 6}
	run._profiles[9] = {"name": "old build without a level"}
	var levels := run.get_danger_levels(PackedInt32Array([7, 9, 12]))
	assert_eq(levels, [own, own + 6] as Array[int], "own level first, clients with a level")
	assert_eq(CoopRules.group_danger(levels), own + 3, "rounded mean")
	assert_eq(run.get_danger_levels(PackedInt32Array()), [own] as Array[int], "alone")
	RunManager.set_danger_level(0)
	run.accept_run_start(1234, 2, 1, false, 7)
	assert_eq(RunManager.get_danger_level(), 7, "the client takes the host's group level before the dungeon")
	await wait_process_frames(1)


func test_lobby_profile_carries_danger_level_and_talents() -> void:
	_account_at_level(6)
	AccountTalents.save_state(_state([&"vitality", &"might"]))
	var lobby := LobbyClient.new()
	var profile := lobby._local_profile()
	assert_eq(profile.get("danger"), AccountProgress.current().get_danger_level())
	assert_eq(profile.get("level"), 6)
	assert_eq(TalentState.from_dict(profile.get("talents")).get_level(&"vitality"), 5)
	lobby.free()


# --- Talents on the account and at the spawn ---

func test_talents_saved_on_the_account_and_sanitized_on_load() -> void:
	var progress := _account_at_level(9)
	assert_eq(progress.get_free_points(), 8, "nothing spent yet")
	assert_eq(AccountTalents.save_state(_state([&"vitality", &"might"])), OK)
	AccountProgress.reset()
	var loaded := AccountTalents.load_state()
	assert_eq(loaded.get_level(&"vitality"), 5)
	assert_eq(loaded.get_level(&"might"), 3)
	progress = _account_at_level(9)
	assert_eq(progress.get_spent_points(), 8, "spent points come from the stored talents")
	assert_eq(progress.get_free_points(), 0)
	_account_at_level(4)
	assert_eq(AccountTalents.load_state().get_spent_points(), 3, "never more than the level gives")


func test_solo_spawn_puts_the_account_talents_on_the_player() -> void:
	_account_at_level(20)
	AccountTalents.save_state(_ember())
	var dungeon := DungeonManager.new()
	var player := _player_with(null)
	var base_health := player.health.get_max_health()
	dungeon._apply_account_talents(player)
	assert_not_null(PlayerTalents.of(player), "talents on the player")
	assert_eq(player.health.get_max_health(), base_health + 5.0, "Vitalität")
	var plain := _player_with(null)
	AccountTalents.save_state(TalentState.new())
	dungeon._apply_account_talents(plain)
	assert_null(PlayerTalents.of(plain), "no talents node without talents")
	dungeon.free()


func test_host_puts_profile_talents_on_players_in_the_dungeon() -> void:
	var profile := {"level": 20, "talents": _ember().to_dict()}
	assert_eq(NetPlayers.profile_talents(profile).get_level(&"vitality"), 5)
	assert_eq(NetPlayers.profile_talents({"level": 3, "talents": _ember().to_dict()}).get_spent_points(), 2,
		"checked against the profile's level")
	assert_eq(NetPlayers.profile_talents({"name": "old"}).get_spent_points(), 0, "old profiles: none")
	var net := NetPlayers.new()
	var dungeon := DungeonManager.new()
	var village := Node2D.new()
	var player := _player_with(null)
	net.world = village
	net._apply_profile_talents(player, profile)
	assert_null(PlayerTalents.of(player), "not in the village")
	net.world = dungeon
	net._apply_profile_talents(player, profile)
	assert_not_null(PlayerTalents.of(player), "in the dungeon")
	assert_true(PlayerTalents.of(player).stats.second_heart)
	net.free()
	dungeon.free()
	village.free()


# --- Hooks ---

func test_double_dash_two_charges_then_one_after_the_cooldown() -> void:
	var plain := _player_with(null)
	assert_true(plain.try_dash(Vector2.RIGHT))
	_step(plain, plain.dash_duration + STEP)
	assert_false(plain.can_dash(), "one charge only")
	var player := _player_with(_wind())
	assert_eq(player.dash_charges, 2, "Doppel-Dash")
	assert_true(player.try_dash(Vector2.RIGHT))
	_step(player, player.dash_duration + STEP)
	assert_eq(player.get_dash_cooldown_left(), 0.0, "a charge is left")
	assert_true(player.try_dash(Vector2.RIGHT), "second dash right away")
	_step(player, player.dash_duration + STEP)
	assert_false(player.can_dash(), "both charges spent")
	assert_gt(player.get_dash_cooldown_left(), 0.0)
	_step(player, player.dash_cooldown)
	assert_eq(player.get_dash_charges_left(), 1, "one charge back after one cooldown")
	_step(player, player.dash_cooldown)
	assert_eq(player.get_dash_charges_left(), 2, "the second after another")
	TalentEffects.apply_to(player, TalentState.new(), _tree)
	assert_eq(player.dash_charges, 1, "taken back")


func test_second_heart_catches_one_lethal_hit_alone() -> void:
	var player := _player_with(_ember())
	assert_true(player.health.death_guard.is_valid(), "guard installed")
	player.health.take_damage(player.health.get_health() + 3.0)
	assert_false(player.health.is_dead(), "stands up")
	assert_eq(player.health.get_health(), TalentEffects.SECOND_HEART_HEALTH)
	player.health.take_damage(10.0)
	assert_true(player.health.is_dead(), "only once per run")
	var plain := _player_with(null)
	plain.health.take_damage(100.0)
	assert_true(plain.health.is_dead(), "without the talent")


func test_steadfast_shortens_stuns() -> void:
	var player := _player_with(_ember())
	player.stun(1.0)
	assert_almost_eq(player._stun_left, 0.5, 0.0001, "Standfest 2×: −50 %")
	var plain := _player_with(null)
	plain.stun(1.0)
	assert_almost_eq(plain._stun_left, 1.0, 0.0001)


func test_weapon_damage_and_rate_with_talents() -> void:
	var sword: WeaponData = load("res://weapons/data/sword.tres")
	var dagger: WeaponData = load("res://weapons/data/dagger.tres")
	var plain := _player_with(null)
	var ember := _player_with(_ember())
	var wind := _player_with(_wind())
	var base := plain.weapon_controller.get_effective_damage(sword)
	assert_almost_eq(ember.weapon_controller.get_effective_damage(sword), base * 1.24, 0.0001, "Wucht +24 %")
	assert_gt(wind.weapon_controller.get_effective_attack_rate(dagger), plain.weapon_controller.get_effective_attack_rate(dagger),
		"Flinke Klinge")
	PlayerTalents.of(wind)._evasion_left = 1.0
	assert_almost_eq(wind.weapon_controller.get_effective_damage(sword), base * 1.3, 0.0001, "Ausweichkunst ×1.3")


func test_shield_breaker_rounds_once_and_keeps_the_hit() -> void:
	var player := _player_with(_ember())
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	enemy.data = load("res://enemies/data/slime.tres")
	add_child_autofree(enemy)
	enemy.set_physics_process(false)
	enemy.is_miniboss = true
	enemy.health.reset(100.0)
	var hit := DamageData.new()
	hit.amount = 1.0
	hit.source = player
	var result := DamageProcessor.process_hit(hit, enemy.health, null, false)
	assert_eq(result.amount, 1.5, "1.0 × 1.4 = 1.4, rounded once to 1.5")
	assert_eq(hit.amount, 1.0, "the hit itself is unchanged")
	var plain_hit := DamageData.new()
	plain_hit.amount = 1.0
	plain_hit.source = _player_with(null)
	assert_eq(DamageProcessor.process_hit(plain_hit, enemy.health, null, false).amount, 1.0)


func test_enemy_slow_strongest_wins_and_runs_out() -> void:
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	enemy.data = load("res://enemies/data/slime.tres")
	add_child_autofree(enemy)
	enemy.set_physics_process(false)
	var speed := enemy.get_move_speed()
	enemy.apply_slow(TalentEffects.WIND_TRAIL_SLOW_FACTOR, 1.0)
	assert_almost_eq(enemy.get_move_speed(), speed * 0.6, 0.001)
	enemy.apply_slow(0.9, 5.0)
	assert_almost_eq(enemy.get_move_speed(), speed * 0.6, 0.001, "a weaker slow does not replace it")
	enemy.apply_slow(0.3, 0.5)
	assert_almost_eq(enemy.get_move_speed(), speed * 0.3, 0.001, "the stronger wins")
	enemy._tick_slow(0.6)
	assert_false(enemy.is_slowed())
	assert_almost_eq(enemy.get_move_speed(), speed, 0.001, "back to full speed")


func test_flint_explanations_are_not_covered_by_seen_all() -> void:
	assert_true(SaveManager.is_excluded_from_seen_all(&"flint_dungeon_entrance"))
	assert_true(SaveManager.is_excluded_from_seen_all(&"boss_intro_golem"))
	assert_false(SaveManager.is_excluded_from_seen_all(&"village_intro"))

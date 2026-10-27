extends GutTest
## The village is peaceful (#80c94d8c): players there hold no weapon (no attack, special or weapon
## switch, nothing in the hand) and their dash is almost always ready (Village.DASH_COOLDOWN). The
## village sets this on every player copy it gets (on_player_spawned, also remote copies of a group
## game); the dungeon spawns new, armed players and the forge's "Dash-Training" works as before.
## Uses a test save file only.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const VILLAGE_SCENE := "res://world/village/village.tscn"
const BOW: WeaponData = preload("res://weapons/data/bow.tres")
const TEST_SAVE_PATH := "user://test_player_village.cfg"

var _old_save_path: String
var _old_phase: GameManager.Phase
var _plain_world: PackedScene = null


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.load_game()
	_old_phase = GameManager.get_phase()
	_plain_world = _make_plain_world()


func after_each() -> void:
	GameManager.clear_pause_reasons()
	HitStop.reset()


func after_all() -> void:
	GameManager.set_phase(_old_phase)
	await wait_seconds(0.3)
	for suffix in ["", ".bak", ".v2.bak", ".prev.bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH + suffix))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


## A minimal world (stands in for the dungeon): a Node2D with a PlayerSpawn marker.
static func _make_plain_world() -> PackedScene:
	var root := Node2D.new()
	root.name = "PlainWorld"
	var spawn := Marker2D.new()
	spawn.name = WorldController.PLAYER_SPAWN_NODE
	spawn.position = Vector2(320, 240)
	root.add_child(spawn)
	spawn.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	return scene


## A player driven by RemoteInput (like a remote copy), optionally disarmed before _ready.
func _remote_player(armed := true) -> Array:
	var player := PLAYER_SCENE.instantiate() as Player
	var input := RemoteInput.new()
	player.input = input
	player.is_local = false
	if not armed:
		player.set_armed(false)
	add_child_autofree(player)
	return [player, input]


func _pivot(player: Player) -> Node2D:
	return player.get_node(^"WeaponPivot") as Node2D


# --- Player: armed or not ---

func test_players_are_armed_by_default() -> void:
	var player: Player = _remote_player()[0]
	assert_true(player.is_armed())
	assert_true(_pivot(player).visible, "weapon in the hand")
	assert_almost_eq(player.dash_cooldown, MetaProgression.BASE_DASH_COOLDOWN, 0.001, "dungeon dash cooldown")


func test_unarmed_player_neither_attacks_nor_uses_the_special_nor_switches() -> void:
	var pair := _remote_player()
	var player: Player = pair[0]
	var input: RemoteInput = pair[1]
	assert_true(player.weapon_controller.equip_weapon(BOW, 1), "a second weapon to switch to")
	player.set_armed(false)
	watch_signals(player.weapon_controller)
	input.press(PlayerInput.ATTACK)
	input.press(PlayerInput.SPECIAL)
	input.tap(PlayerInput.SWITCH_WEAPON)
	await wait_physics_frames(6)
	input.release(PlayerInput.ATTACK)
	input.release(PlayerInput.SPECIAL)
	assert_signal_not_emitted(player.weapon_controller, "attack_performed")
	assert_signal_not_emitted(player.weapon_controller, "special_performed")
	assert_eq(player.weapon_controller.get_active_slot(), 0, "no weapon switch")
	assert_false(_pivot(player).visible, "nothing in the hand")
	assert_not_null(player.weapon_controller.get_active_weapon(), "the weapons stay in their slots")


func test_unarmed_weapon_controller_refuses_direct_requests() -> void:
	var player: Player = _remote_player(false)[0]
	assert_false(player.weapon_controller.request_attack())
	assert_false(player.weapon_controller.request_special())
	assert_false(player.weapon_controller.is_attacking())


func test_disarming_ends_a_running_attack() -> void:
	var player: Player = _remote_player()[0]
	assert_true(player.weapon_controller.request_attack())
	assert_true(player.weapon_controller.is_attacking())
	watch_signals(player.weapon_controller)
	player.set_armed(false)
	assert_false(player.weapon_controller.is_attacking())
	assert_signal_emitted(player.weapon_controller, "attack_cancelled")


func test_disarmed_before_ready_keeps_the_weapon_hidden() -> void:
	var player: Player = _remote_player(false)[0]
	assert_false(player.is_armed())
	assert_false(_pivot(player).visible, "set before _ready")
	player.set_body_visible(false)
	player.set_body_visible(true)
	assert_false(_pivot(player).visible, "showing the body again (fall, side view) does not show the weapon")


func test_rearming_brings_the_weapon_back() -> void:
	var pair := _remote_player(false)
	var player: Player = pair[0]
	var input: RemoteInput = pair[1]
	player.set_armed(true)
	assert_true(_pivot(player).visible)
	watch_signals(player.weapon_controller)
	input.press(PlayerInput.ATTACK)
	await wait_physics_frames(3)
	input.release(PlayerInput.ATTACK)
	assert_signal_emitted(player.weapon_controller, "attack_performed")


func test_dash_still_works_unarmed() -> void:
	var pair := _remote_player(false)
	var player: Player = pair[0]
	var input: RemoteInput = pair[1]
	input.set_move(Vector2.RIGHT)
	input.tap(PlayerInput.DASH)
	await wait_physics_frames(2)
	assert_true(player.is_dashing() or player.get_dash_cooldown_left() > 0.0, "dash started")


# --- The village hook ---

func test_village_hook_disarms_and_shortens_the_dash() -> void:
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	add_child_autofree(village)
	var player: Player = _remote_player()[0]
	village.on_player_spawned(player)
	assert_false(player.is_armed())
	assert_false(_pivot(player).visible)
	assert_almost_eq(player.dash_cooldown, Village.DASH_COOLDOWN, 0.001)
	assert_lt(Village.DASH_COOLDOWN, MetaProgression.BASE_DASH_COOLDOWN, "much shorter than in the dungeon")


## A WorldController without HUD, menus and vision, village first, the plain world as the dungeon.
func _controller(mode: GameMode) -> WorldController:
	var world_root := Node2D.new()
	add_child_autofree(world_root)
	var controller := WorldController.new()
	controller.world_root = world_root
	controller.village_scene = load(VILLAGE_SCENE) as PackedScene
	controller.dungeon_scene = _plain_world
	controller.game_mode = mode
	add_child_autofree(controller)
	await wait_process_frames(2)
	return controller


func test_every_copy_in_the_village_is_unarmed_and_dashes_often() -> void:
	var controller := await _controller(GameMode.quick(2))
	assert_true(controller.get_world() is Village)
	var players := controller.get_players()
	assert_eq(players.size(), 2)
	for player in players:
		assert_false(player.is_armed(), "%s unarmed (local and remote copy alike)" % player.name)
		assert_almost_eq(player.dash_cooldown, Village.DASH_COOLDOWN, 0.001)
	# The remote copy dashes again right after its dash (RemoteInput, like a copy in a group game).
	var remote: Player = players[1]
	assert_false(remote.is_local)
	var input := remote.input as RemoteInput
	input.set_move(Vector2.RIGHT)
	input.tap(PlayerInput.DASH)
	await wait_physics_frames(2)
	assert_true(remote.is_dashing(), "first dash")
	await wait_seconds(Village.DASH_COOLDOWN + 0.05)
	assert_true(remote.can_dash(), "ready again after %.2f s" % Village.DASH_COOLDOWN)
	input.tap(PlayerInput.DASH)
	await wait_physics_frames(2)
	assert_true(remote.is_dashing(), "second dash")


func test_dungeon_players_are_armed_and_keep_the_forge_dash() -> void:
	var controller := await _controller(GameMode.solo())
	var village_player := controller.get_player()
	assert_false(village_player.is_armed())
	controller.load_world(_plain_world)
	await wait_process_frames(2)
	var player := controller.get_player()
	assert_ne(player, village_player, "a new player instance for the next world (D-041)")
	assert_true(player.is_armed())
	assert_true(_pivot(player).visible)
	assert_almost_eq(player.dash_cooldown, MetaProgression.BASE_DASH_COOLDOWN, 0.001, "no village dash in the dungeon")
	# The forge on the fresh player (DungeonManager.on_player_spawned -> apply_to_run) keeps the
	# dungeon dash: Dash-Training is a talent since KE4 (TalentEffects), not the village's dash.
	MetaProgression.apply_to_run(player, null)
	assert_almost_eq(player.dash_cooldown, MetaProgression.BASE_DASH_COOLDOWN, 0.001,
		"not the village's %.2f s" % Village.DASH_COOLDOWN)

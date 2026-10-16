extends GutTest
## Weapons per player in a group game (first online test, 15.10.2026: everybody saw the other one's
## weapon, the host ran a client's bow shot as a sword swing). The active weapon slot travels as
## state with the held actions (NetPlayerState.ACTIVE_SLOT_*), the switch button is never replayed,
## so every copy holds the weapon its owner holds - also when only one copy was locked (room intro)
## while the button went down. Two "machines" are played in one tree: the owner's player and the
## copy another machine runs from the bits the owner sends.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const TEST_SAVE_PATH := "user://test_net_weapons.cfg"
const SWORD: WeaponData = preload("res://weapons/data/sword.tres")
const BOW: WeaponData = preload("res://weapons/data/bow.tres")
const STAFF: WeaponData = preload("res://weapons/data/staff.tres")
const CLIENT_PEER := 2

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.load_game()


func after_each() -> void:
	HitStop.reset()


func after_all() -> void:
	await wait_seconds(0.3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


## A player driven by RemoteInput (the keyboard of its machine or the network), with a NetState.
func _player(local: bool, peer := CLIENT_PEER) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.input = RemoteInput.new()
	player.is_local = local
	player.add_child(NetPlayerState.create(peer, Vector2.ZERO))
	add_child_autofree(player)
	return player


func _state(player: Player) -> NetPlayerState:
	return player.get_node(NodePath(NetPlayerState.NODE_NAME)) as NetPlayerState


func _keys(player: Player) -> RemoteInput:
	return player.input as RemoteInput


## Host side: what a client's packet does to the host's copy (NetRun.submit_input -> apply_input).
func _send_to_host(owner_player: Player, copy: Player) -> void:
	_state(copy).apply_input(CLIENT_PEER, owner_player.input.move, owner_player.get_aim_direction(), NetPlayerState.held_bits_of(owner_player))


## Client side: what the synchronizer brings for another player's copy (NetPlayerState._follow).
func _sync_to_client(owner_player: Player, copy: Player, extra_bits := 0) -> void:
	var state := _state(copy)
	state.pos = copy.position
	state.held = NetPlayerState.held_bits_of(owner_player) | extra_bits
	state.call(&"_follow", 1.0 / 60.0)


func _sprite_texture(player: Player) -> Texture2D:
	return (player.get_node(^"WeaponPivot/WeaponSprite") as Sprite2D).texture


# --- Bits ---

func test_slot_bits_round_trip_and_replay_mask() -> void:
	assert_eq(NetPlayerState.SWITCH_BIT, 1 << PlayerInput.ACTIONS.find(PlayerInput.SWITCH_WEAPON), "switch bit = action order")
	assert_eq(NetPlayerState.INTERACT_BIT, 1 << PlayerInput.ACTIONS.find(PlayerInput.INTERACT))
	assert_eq(NetPlayerState.slot_of(0), -1, "no slot in the bits: keep the copy's")
	for slot in WeaponController.MAX_WEAPON_SLOTS:
		var bits := ((slot + 1) << NetPlayerState.ACTIVE_SLOT_SHIFT) | NetPlayerState.SWITCH_BIT | 1
		assert_eq(NetPlayerState.slot_of(bits), slot)
		var replayed := NetPlayerState.actions_of(bits & NetPlayerState.REPLAY_MASK)
		assert_eq(replayed, [PlayerInput.ATTACK] as Array[StringName], "the switch button is never replayed")
	assert_lt(NetPlayerState.ACTIVE_SLOT_SHIFT, 31)
	assert_eq(NetPlayerState.ACTIVE_SLOT_MASK & ((1 << PlayerInput.ACTIONS.size()) - 1), 0, "slot bits do not overlap actions")


func test_set_active_slot_is_state_not_a_toggle() -> void:
	var player := _player(true)
	var controller := player.weapon_controller
	controller.equip_weapon(BOW, 1)
	assert_true(controller.set_active_slot(1))
	assert_false(controller.set_active_slot(1), "already active: nothing happens")
	assert_eq(controller.get_active_weapon(), BOW)
	assert_false(controller.set_active_slot(5), "out of range")
	controller.equip_weapon(STAFF, 1)
	controller.set_active_slot(0)
	assert_eq(controller.get_active_weapon(), SWORD)
	assert_true(controller.switch_weapon(), "the switch button still toggles at the owner's machine")
	assert_eq(controller.get_active_weapon(), STAFF)


# --- Host runs a client's attack with the client's weapon ---

func test_host_copy_attacks_with_the_clients_bow() -> void:
	var client := _player(true)
	var copy := _player(false)
	# The client takes a bow (weapon room) - the host's copy gets it through submit_weapon.
	client.weapon_controller.equip_weapon(BOW, 1)
	copy.weapon_controller.equip_weapon(BOW, 1)
	_keys(client).tap(PlayerInput.SWITCH_WEAPON)
	await wait_physics_frames(2)
	assert_eq(client.weapon_controller.get_active_weapon(), BOW, "the client holds the bow")
	_keys(client).press(PlayerInput.ATTACK)
	await wait_physics_frames(1)
	watch_signals(copy.weapon_controller)
	var used: Array[WeaponData] = []
	copy.weapon_controller.attack_performed.connect(func(weapon: WeaponData) -> void: used.append(weapon))
	_send_to_host(client, copy)
	await wait_physics_frames(3)
	assert_signal_emitted(copy.weapon_controller, "attack_performed")
	assert_eq(used, [BOW] as Array[WeaponData], "the host shoots the client's bow, no sword swing")
	assert_eq(copy.weapon_controller.get_active_weapon(), BOW)
	assert_eq(_sprite_texture(copy), BOW.sprite, "the copy shows the bow")


func test_switch_during_a_lock_on_one_machine_keeps_both_copies_in_step() -> void:
	var client := _player(true)
	var copy := _player(false)
	for player in [client, copy]:
		(player as Player).weapon_controller.equip_weapon(BOW, 1)
	# A room intro locks only the player of its own machine (D-133): the client's player is locked,
	# the host's copy is not. The client presses the switch button meanwhile.
	client.set_input_locked(&"intro", true)
	_keys(client).press(PlayerInput.SWITCH_WEAPON)
	await wait_physics_frames(2)
	assert_eq(client.weapon_controller.get_active_weapon(), SWORD, "locked: no switch at the client")
	_send_to_host(client, copy)
	await wait_physics_frames(3)
	assert_eq(copy.weapon_controller.get_active_weapon(), SWORD, "the host's copy did not switch on its own")
	_keys(client).release(PlayerInput.SWITCH_WEAPON)
	client.set_input_locked(&"intro", false)
	await wait_physics_frames(1)
	_keys(client).tap(PlayerInput.SWITCH_WEAPON)
	await wait_physics_frames(2)
	_send_to_host(client, copy)
	await wait_physics_frames(2)
	assert_eq(client.weapon_controller.get_active_weapon(), BOW)
	assert_eq(copy.weapon_controller.get_active_weapon(), BOW, "the next switch arrives as the slot")


func test_slot_waits_for_its_weapon() -> void:
	var client := _player(true)
	var copy := _player(false)
	client.weapon_controller.equip_weapon(STAFF, 1)
	client.weapon_controller.switch_weapon()
	_send_to_host(client, copy)
	assert_eq(copy.weapon_controller.get_active_weapon(), SWORD, "slot 1 still empty at the host")
	copy.weapon_controller.equip_weapon(STAFF, 1)
	# NetPlayerState applies the wanted slot again in its physics step (only with a session); the
	# next packet does the same.
	_send_to_host(client, copy)
	assert_eq(copy.weapon_controller.get_active_weapon(), STAFF)


# --- Every machine shows every player's own weapon ---

func test_client_copy_of_the_host_follows_the_host_and_never_double_switches() -> void:
	var host := _player(true, 1)
	var copy := _player(false, 1)
	for player in [host, copy]:
		(player as Player).weapon_controller.equip_weapon(STAFF, 1)
	_keys(host).tap(PlayerInput.SWITCH_WEAPON)
	await wait_physics_frames(2)
	# The old path: a loadout switched the copy, then the synced bits with the button still held
	# switched it back.
	copy.weapon_controller.set_active_slot(host.weapon_controller.get_active_slot())
	_sync_to_client(host, copy, NetPlayerState.SWITCH_BIT)
	await wait_physics_frames(3)
	assert_eq(host.weapon_controller.get_active_weapon(), STAFF)
	assert_eq(copy.weapon_controller.get_active_weapon(), STAFF, "the copy holds the host's staff")
	assert_eq(_sprite_texture(copy), STAFF.sprite)


func test_three_players_three_weapons() -> void:
	var weapons: Array[WeaponData] = [SWORD, BOW, STAFF]
	var owners: Array[Player] = []
	var copies: Array[Player] = []
	for i in weapons.size():
		var owner_player := _player(true, i + 1)
		var copy := _player(false, i + 1)
		if weapons[i] != SWORD:
			owner_player.weapon_controller.equip_weapon(weapons[i], 1)
			copy.weapon_controller.equip_weapon(weapons[i], 1)
			owner_player.weapon_controller.switch_weapon()
		owners.append(owner_player)
		copies.append(copy)
	for i in weapons.size():
		_sync_to_client(owners[i], copies[i])
	await wait_physics_frames(2)
	for i in weapons.size():
		assert_eq(copies[i].weapon_controller.get_active_weapon(), weapons[i], "player %d holds its own weapon" % (i + 1))
		assert_eq(_sprite_texture(copies[i]), weapons[i].sprite)


# --- Global events and village bonuses belong to this machine ---

func test_remote_copies_do_not_emit_global_weapon_events() -> void:
	var copy := _player(false)
	watch_signals(EventBus)
	copy.weapon_controller.equip_weapon(BOW, 1)
	copy.weapon_controller.set_active_slot(1)
	assert_signal_not_emitted(EventBus, "weapon_changed", "the HUD and statistics of this machine stay untouched")
	var own := _player(true)
	own.weapon_controller.equip_weapon(BOW, 1)
	assert_signal_emitted(EventBus, "weapon_changed")


func test_village_damage_bonus_only_from_the_local_save_in_single_player() -> void:
	SaveManager.set_meta_level(MetaProgression.SHARPNESS, 2)
	var player := _player(true)
	var solo_damage := player.weapon_controller.get_effective_damage(SWORD)
	assert_almost_eq(player.weapon_controller.get_meta_damage_bonus(), MetaProgression.get_damage_bonus(), 0.0001, "solo: own forge")
	var owner_node := SessionOwner.new()
	owner_node.game_mode = GameMode.quick(2)
	add_child_autofree(owner_node)
	owner_node.add_to_group(GameMode.OWNER_GROUP)
	assert_eq(player.weapon_controller.get_meta_damage_bonus(), 0.0, "D-081: quick games without village bonuses")
	assert_lt(player.weapon_controller.get_effective_damage(SWORD), solo_damage)
	owner_node.remove_from_group(GameMode.OWNER_GROUP)
	SaveManager.set_meta_level(MetaProgression.SHARPNESS, 0)


## Stand-in for the WorldController: any node of the owner group with a game_mode property.
class SessionOwner:
	extends Node
	var game_mode: GameMode = null

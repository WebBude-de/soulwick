extends GutTest
## Wave 2 wiring (KE3, KE4, KE7, SV1, SV4, WK8): the soul gate guarantee tracked by the dungeon over
## two cycles, boss crystals with the depth bonus, the forge's weapon level and special III in the
## damage, the Laterne in the light circle, the spell keys and a cast from them, the forge in the
## lobby profile and on the network player, the stomp and the defeat style as network events, Flint
## at the dungeon entrance once and his protection over the network. Save and account live in a test
## folder, never the real ones (AGENTS.md rule 4).

const ROOT := "user://test_wave2_integration"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://enemies/enemy_base.tscn")
const DUNGEON: PackedScene = preload("res://dungeon/dungeon.tscn")
const SEEDS: Array[int] = [11, 4242]
const STEP := 1.0 / 60.0

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String


## NetDungeon stand-in: records what goes to the clients, answers the sender of an RPC.
class RecordingNet extends NetDungeon:
	var sent: Array = []
	var sender: Player = null

	func send_to_clients(_node: Node, method: StringName, args: Array = []) -> void:
		sent.append([method, args])

	func _sender_player() -> Player:
		return sender


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path


func before_each() -> void:
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()
	AccountProgress.path_override = ""
	AccountProgress.reset()


func after_each() -> void:
	HitStop.reset()
	for child in get_children():
		if child is CanvasItem:
			child.queue_free()
	await wait_process_frames(1)


func after_all() -> void:
	if RunManager.is_run_active():
		RunManager.end_run(RunManager.EndReason.ABORT)
	_wipe()
	AccountProgress.path_override = ""
	AccountProgress.reset()
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()


func _wipe() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	for dir_path in [root.path_join("saves"), root]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			DirAccess.remove_absolute(dir_path.path_join(file))
	DirAccess.make_dir_recursive_absolute(root.path_join("saves"))


func _player() -> Player:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.set_physics_process(false)
	return player


func _forge(weapon_levels: Dictionary, lantern := 0) -> Dictionary:
	var snapshot := MetaProgression.sanitize_snapshot({"lantern": lantern})
	for weapon: StringName in weapon_levels:
		snapshot["weapons"][String(weapon)] = weapon_levels[weapon]
	return snapshot


func _dungeon(seed_value: int) -> DungeonManager:
	var dungeon := DUNGEON.instantiate() as DungeonManager
	dungeon.seed_value = seed_value
	add_child(dungeon)
	return dungeon


## Freed at once (like test_passage_chain): deferred UI calls of its rooms die with it.
func _free_dungeon(dungeon: DungeonManager) -> void:
	remove_child(dungeon)
	dungeon.free()


# --- KE3: soul gates and boss crystals ---

func test_a_gate_at_least_every_second_cycle_and_the_dungeon_tracks_it() -> void:
	for seed_value in SEEDS:
		var dungeon := _dungeon(seed_value)
		await wait_physics_frames(2)
		var gate_cycles: Dictionary = {}
		var last_gate := 0
		for slot in range(1, 23):
			var room := dungeon.get_room_at_slot(slot)
			var before := dungeon.get_room_at_slot(slot - 1)
			if room == null and before != null and before.is_branch_room():
				before.choose_branch(0)
				room = dungeon.get_room_at_slot(slot)
			assert_not_null(room, "seed %d: slot %d prepared" % [seed_value, slot])
			if room == null:
				break
			if room.has_portal:
				gate_cycles[RoomSequence.get_cycle(room.room_index)] = true
				last_gate = room.room_index
			if slot > 1:
				dungeon._on_player_entered_room(room)
		assert_eq(dungeon._last_gate_room, maxi(last_gate, dungeon._last_gate_room), "seed %d: tracks the last gate" % seed_value)
		for cycle in range(2, 5):
			assert_true(gate_cycles.has(cycle) or gate_cycles.has(cycle - 1),
					"seed %d: a gate in cycle %d or %d" % [seed_value, cycle - 1, cycle])
		var state := dungeon._capture_chain()
		assert_eq(state.last_gate_room, dungeon._last_gate_room, "the branch chain keeps it")
		_free_dungeon(dungeon)
		await wait_physics_frames(1)


func test_boss_crystals_grow_with_the_depth() -> void:
	var dungeon := _dungeon(7)
	await wait_physics_frames(2)
	if not RunManager.is_run_active():
		RunManager.start_run()
	var before := RunManager.get_run_crystals()
	var room := dungeon.get_room_at_slot(1)
	room.room_index = 15
	var boss := ENEMY_SCENE.instantiate() as Enemy
	var data := (load("res://enemies/data/slime.tres") as EnemyData).duplicate() as EnemyData
	data.is_boss = true
	boss.data = data
	add_child_autofree(boss)
	boss.set_physics_process(false)
	dungeon._on_encounter_started(room, [boss] as Array[Enemy])
	boss.died.emit(boss)
	var expected := EconomyConfig.depth_crystals(DungeonManager.CRYSTALS_PER_BOSS, 15)
	assert_gt(expected, DungeonManager.CRYSTALS_PER_BOSS, "room 15 pays more than the base")
	assert_eq(RunManager.get_run_crystals() - before, expected, "boss in room 15 with the depth bonus")
	_free_dungeon(dungeon)


func test_net_signature_names_the_gate() -> void:
	var dungeon := _dungeon(11)
	await wait_physics_frames(2)
	var room := dungeon.get_room_at_slot(1)
	var signature := NetDungeon.signature_of(room)
	assert_true(signature.ends_with("|%s" % room.has_portal), "has_portal is part of the room signature")
	_free_dungeon(dungeon)


# --- KE4: forge in the fight, the light and the lobby ---

func test_weapon_level_counts_in_the_damage_and_special_from_level_three() -> void:
	var player := _player()
	var controller := player.weapon_controller
	var weapon := controller.get_active_weapon()
	assert_not_null(weapon)
	var plain := controller.get_effective_damage(weapon)
	var plain_special := controller.get_effective_special_damage(weapon)
	MetaProgression.set_player_forge(player, _forge({weapon.id: 2}))
	assert_almost_eq(controller.get_effective_damage(weapon), plain * (1.0 + MetaProgression.weapon_damage_bonus_at(2)), 0.001,
			"level II: +%d %%" % roundi(MetaProgression.weapon_damage_bonus_at(2) * 100.0))
	var level_two_special := controller.get_effective_special_damage(weapon)
	MetaProgression.set_player_forge(player, _forge({weapon.id: 3}))
	var level_three := controller.get_effective_damage(weapon)
	assert_almost_eq(controller.get_effective_special_damage(weapon) / level_three, level_two_special / (plain * (1.0 + MetaProgression.weapon_damage_bonus_at(2))) * MetaProgression.weapon_special_factor_at(3), 0.001,
			"level III: the special gets its factor on top")
	var damage := controller._create_damage(weapon, weapon.special_damage_multiplier, &"special")
	assert_almost_eq(damage.amount, controller.get_effective_special_damage(weapon), 0.001, "the special attack itself")
	assert_gt(plain_special, 0.0)


func test_lantern_widens_the_light_and_blindness_still_wins() -> void:
	GameManager.set_phase(GameManager.Phase.DUNGEON)
	var overlay := VisionOverlay.new()
	add_child_autofree(overlay)
	var player := _player()
	overlay.bind_player(player)
	overlay.set_vision(DungeonManager.DUNGEON_DARKNESS, DungeonManager.VISION_RADIUS, true)
	await wait_process_frames(2)
	var plain := overlay.get_current_radius()
	MetaProgression.set_player_forge(player, _forge({}, 2))
	for i in 120:
		overlay._process(STEP)
	assert_almost_eq(overlay.get_current_radius(), plain * MetaProgression.light_radius_factor_at(2), 1.0, "Laterne II: +20 %")


func test_forge_travels_in_the_lobby_profile_and_lands_on_the_network_player() -> void:
	var lobby := LobbyClient.new()
	add_child_autofree(lobby)
	var profile := lobby._local_profile()
	assert_true(profile.has("forge"), "the own forge goes with the profile")
	assert_eq(profile["forge"], MetaProgression.forge_snapshot())
	assert_eq(NetPlayers.profile_forge({}), {}, "an old profile brings none")
	var forge := NetPlayers.profile_forge({"forge": {"weapons": {"bow": 99}, "start": ["bow"]}})
	assert_eq(int(forge["weapons"]["bow"]), MetaProgression.WEAPON_LEVEL_COSTS.size(), "levels clamped")
	var players := NetPlayers.new()
	add_child_autofree(players)
	var player := players._build_player({"peer": 5, "index": 1, "forge": forge}) as Player
	autofree(player)
	assert_eq(MetaProgression.player_weapon_level(player, &"bow"), MetaProgression.WEAPON_LEVEL_COSTS.size(),
			"every machine stores the player's forge")


# --- KE7: spells ---

func test_spell_keys_are_mapped_and_a_press_casts() -> void:
	assert_true(InputMap.has_action(PlayerInput.CAST_SPELL), "F")
	assert_true(InputMap.has_action(PlayerInput.CAST_SPELL_2), "R")
	var keys: Array[int] = []
	for action in [PlayerInput.CAST_SPELL, PlayerInput.CAST_SPELL_2]:
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				keys.append((event as InputEventKey).physical_keycode)
	assert_eq(keys, [KEY_F, KEY_R] as Array[int])
	assert_eq(PlayerInput.ACTIONS.find(PlayerInput.CAST_SPELL), 6, "net bit 6")
	assert_eq(PlayerInput.ACTIONS.find(PlayerInput.CAST_SPELL_2), 7, "net bit 7")
	assert_eq(NetPlayerState.ACTIVE_SLOT_MASK & ((1 << PlayerInput.ACTIONS.size()) - 1), 0, "slot bits stay apart")
	assert_true(PlayerSpells.has_second_button())
	var pad: Array = []
	for binding in GamepadInput.bindings():
		if binding[0] in [PlayerInput.CAST_SPELL, PlayerInput.CAST_SPELL_2]:
			pad.append((binding[1] as InputEventJoypadButton).button_index)
	assert_eq(pad, [JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_LEFT_SHOULDER], "RB and LB")
	assert_true(ControlsInfo.get_ids().has(ControlsInfo.SPELL), "on the controls page")
	var player := _player()
	var spells := PlayerSpells.attach_to(player)
	spells.set_physics_process(false)
	spells.set_loadout([&"soul_shield", &"heal_spark"] as Array[StringName])
	var input := RemoteInput.new()
	player.input = input
	watch_signals(spells)
	input.tap(PlayerInput.CAST_SPELL_2)
	input.poll(player)
	spells.read_input(input)
	assert_signal_emitted_with_parameters(spells, "spell_cast", [&"heal_spark", 1, player.get_aim_direction(), spells.get_cooldown_left(1)])


func test_blinded_enemies_do_not_attack_and_bosses_shorter() -> void:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.data = load("res://enemies/data/skeleton.tres")
	add_child_autofree(enemy)
	enemy.set_physics_process(false)
	SpellEffects.blind_enemy(enemy, 2.0)
	assert_true(enemy.is_blinded())
	assert_false(enemy.is_slowed(), "a real blind, not the stand-in slow")
	enemy._tick_slow(1.9)
	assert_true(enemy.is_blinded())
	enemy._tick_slow(0.2)
	assert_false(enemy.is_blinded(), "over after 2 s")
	var boss := ENEMY_SCENE.instantiate() as Enemy
	var data := (load("res://enemies/data/slime.tres") as EnemyData).duplicate() as EnemyData
	data.is_boss = true
	boss.data = data
	add_child_autofree(boss)
	boss.set_physics_process(false)
	boss.apply_blind(2.0)
	boss._tick_slow(1.1)
	assert_false(boss.is_blinded(), "bosses: half the time (TESTWERT)")


# --- SV1, SV4: side view over the network ---

func test_stomp_goes_to_the_clients_with_the_defeat_style() -> void:
	var net := RecordingNet.new()
	autofree(net)
	var side := NetSide.create(net, null)
	add_child_autofree(side)
	side.set_physics_process(false)
	var player := _player()
	var motion := PlayerSideMotion.new()
	autofree(motion)
	player.side_motion = motion
	var segment := SideSegment.new()
	autofree(segment)
	segment._players.assign([player])
	side._watch_moves(segment)
	motion.stomped.emit(player, null)
	var moves: Array = []
	for entry: Array in net.sent:
		if entry[0] == &"side_move_net":
			moves.append(entry[1][1])
	assert_eq(moves, [int(PlayerSideMotion.Move.STOMP)], "STOMP as a move event (no ram since D-216)")
	var enemy := SideEnemy.new()
	autofree(enemy)
	enemy.defeat_style = SideEnemy.Defeat.POP
	enemy.set(&"_defeat_direction", -1.0)
	side._enemies.assign([enemy])
	net.sent.clear()
	side._on_enemy_died_host(0)
	assert_eq(net.sent[0][0], &"side_enemy_died_net")
	assert_eq(net.sent[0][1].slice(1), [0, int(SideEnemy.Defeat.POP), -1.0], "index, style and direction")


# --- KE3, WK8: notices and Flint ---

func test_guide_protection_reaches_the_host() -> void:
	var net := RecordingNet.new()
	autofree(net)
	net.is_host = true
	var player := _player()
	net.sender = player
	net.submit_guide_protected(true)
	assert_true(player.is_input_locked(), "the host protects the client's player during a tour")
	net.submit_guide_protected(false)
	assert_false(player.is_input_locked())


func test_flint_explains_the_entrance_once() -> void:
	var village := Node2D.new()
	var entrance := Node2D.new()
	entrance.position = Vector2(300, 200)
	add_child_autofree(village)
	village.add_child(entrance)
	var player := _player()
	player.is_local = true
	var guide := FlintGuide.for_player(player)
	guide.set_process(false)
	guide.shows_view = false
	var ui := VillageUI.new()
	ui.entrance_anchor = entrance
	village.add_child(ui)
	ui.set_process(false)
	ui.show_entrance_info()
	assert_true(guide.is_known(&"flint_entrance_danger"), "Flint introduces the danger at the first card")
	guide.skip()
	assert_true(AccountSeen.has_seen(&"flint_entrance_danger"), "seen per account")
	ui.hide_entrance_info()
	await wait_process_frames(2)
	ui.show_entrance_info()
	assert_eq(guide.get_queue_size(), 0, "only once: nothing queued again")
	assert_false(FlintExplanations.entrance_danger(player, entrance), "seen")

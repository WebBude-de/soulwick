extends GutTest
## Wave 3 wiring (KE5 Proviant, KE8 home door, WK10 practice run, SV2 jump trial, player knockback,
## Flint's portrait): the Seelenanker pays half, the Rückkehrstein opens a gate once (key, host,
## network event), Klarsicht blocks blindness and gloom, Glück 0 draws like before, Händlerfreund
## prices, Proviant in the lobby profile and on the host's player, a quick game consumes it, the
## group's Goldregen, the home door loads the interior, the practice run starts before room 1 alone
## and not in a group, bonus XP once, the element clock over the network, the spring throws a jump,
## knockback stops at an abyss. Save and account live in a test folder, never the real ones
## (AGENTS.md rule 4).

const ROOT := "user://test_wave3_integration"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const DUNGEON: PackedScene = preload("res://dungeon/dungeon.tscn")
const VILLAGE_SCENE := "res://world/village/village.tscn"
const STEP := 1.0 / 60.0

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String


## NetDungeon stand-in: records what goes to the clients.
class RecordingNet extends NetDungeon:
	var sent: Array = []

	func send_to_clients(_node: Node, method: StringName, args: Array = []) -> void:
		sent.append([method, args])

	func _send(method: StringName, args: Array = []) -> void:
		sent.append([method, args])


## The session owner GameMode.of() asks (a WorldController in the game).
class ModeOwner extends Node:
	var game_mode: GameMode = GameMode.solo()


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
	TutorialRun.force_next = false


func after_each() -> void:
	HitStop.reset()
	TutorialRun.force_next = false
	HomeTravel.reset()
	GameManager.clear_pause_reasons()
	if RunManager.is_run_active():
		RunManager.end_run(RunManager.EndReason.ABORT)
	for child in get_children():
		if child is CanvasItem or child is ModeOwner:
			child.queue_free()
	await wait_process_frames(1)


func after_all() -> void:
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


func _provisions(boosts: Array, luck := 0, merchant := 0) -> Dictionary:
	return {"boosts": boosts, "luck": luck, "merchant_friend": merchant}


func _dungeon(seed_value := 11) -> DungeonManager:
	var dungeon := DUNGEON.instantiate() as DungeonManager
	dungeon.seed_value = seed_value
	add_child(dungeon)
	return dungeon


func _free_dungeon(dungeon: DungeonManager) -> void:
	dungeon.net = null
	if RunManager.is_run_active():
		RunManager.end_run(RunManager.EndReason.ABORT)
	remove_child(dungeon)
	dungeon.free()


func _owner(mode: GameMode) -> ModeOwner:
	var owner_node := ModeOwner.new()
	owner_node.game_mode = mode
	add_child(owner_node)
	owner_node.add_to_group(GameMode.OWNER_GROUP)
	return owner_node


func _remove_owner(owner_node: ModeOwner) -> void:
	owner_node.remove_from_group(GameMode.OWNER_GROUP)
	remove_child(owner_node)
	owner_node.free()


# --- A1 Seelenanker ---

func test_soul_anchor_pays_half_on_death() -> void:
	SaveManager.add_pending_boost(MetaProgression.BOOST_SOUL_ANCHOR)
	RunManager.set_danger_level(0)
	RunManager.start_run()
	RunManager.add_run_gold(10)
	RunManager.add_run_crystals(3)
	assert_eq(RunManager.calculate_payout(10, RunManager.EndReason.DEATH), 5, "50 % with the anchor")
	assert_eq(RunManager.calculate_payout(10, RunManager.EndReason.EXIT), 10, "the gate pays everything")
	assert_almost_eq(RunManager.get_loss_payout_ratio(), 0.5, 0.0001)
	var gold_before := SaveManager.get_permanent_gold()
	RunManager.end_run(RunManager.EndReason.DEATH)
	assert_eq(SaveManager.get_permanent_gold() - gold_before, 5)
	assert_almost_eq(float(RunManager.get_last_summary()["loss_ratio"]), 0.5, 0.0001, "the run end shows 50 %")
	RunManager.start_run()
	assert_eq(RunManager.calculate_payout(10, RunManager.EndReason.DEATH), 3, "without it 25 % rounded up")


# --- A2 Rückkehrstein ---

func test_return_stone_action_has_its_own_bit_and_key() -> void:
	assert_eq(PlayerInput.ACTIONS.find(PlayerInput.USE_RETURN_STONE), 8, "net bit 8, appended")
	assert_eq(NetPlayerState.ACTIVE_SLOT_MASK & ((1 << PlayerInput.ACTIONS.size()) - 1), 0, "slot bits stay apart")
	assert_true(InputMap.has_action(PlayerInput.USE_RETURN_STONE))
	var keys := InputMap.action_get_events(PlayerInput.USE_RETURN_STONE).filter(func(event: InputEvent) -> bool: return event is InputEventKey)
	assert_eq((keys[0] as InputEventKey).physical_keycode, KEY_G, "G")


func test_return_stone_opens_a_gate_once_and_tells_the_clients() -> void:
	SaveManager.add_pending_boost(MetaProgression.BOOST_RETURN_STONE)
	var dungeon := _dungeon()
	await wait_physics_frames(2)
	var player := PLAYER_SCENE.instantiate() as Player
	dungeon.add_child(player)
	player.set_physics_process(false)
	dungeon.on_player_spawned(player)
	assert_true(MetaProgression.can_use_return_stone(player), "packed and applied at the run start")
	var room := dungeon.get_room_at_slot(1)
	dungeon.enter_room(room)
	await wait_physics_frames(1)
	var net := RecordingNet.new()
	net.is_host = true
	net.dm = dungeon
	dungeon.net = net
	# The key at this machine (G): the dungeon breaks the stone.
	var input := RemoteInput.new()
	player.input = input
	input.tap(PlayerInput.USE_RETURN_STONE)
	input.poll(player)
	dungeon._physics_process(STEP)
	assert_true(room.has_portal, "a gate stands in the active room")
	assert_not_null(SoulGate.find_in(room))
	assert_true(MetaProgression.is_return_stone_used(player))
	assert_false(MetaProgression.can_use_return_stone(player), "once per run")
	assert_false(dungeon.request_return_stone(player), "a second time does nothing")
	var events := net.sent.filter(func(entry: Array) -> bool: return entry[0] == &"return_gate_net")
	assert_eq(events.size(), 1, "the clients get the gate once")
	assert_eq(int(events[0][1][0]), room.slot_index)
	net.free()
	_free_dungeon(dungeon)


func test_client_opens_the_hosts_return_gate() -> void:
	var dungeon := _dungeon(4242)
	await wait_physics_frames(2)
	var room := dungeon.get_room_at_slot(1)
	dungeon.enter_room(room)
	var net := RecordingNet.new()
	net.is_host = false
	net.dm = dungeon
	net.return_gate_net(room.slot_index, 2, room.global_position)
	assert_true(room.has_portal, "the client's copy of the room gets the gate")
	net.free()
	_free_dungeon(dungeon)


# --- A3 Klarsicht ---

func test_clear_sight_blocks_blindness_and_gloom() -> void:
	var player := _player()
	watch_signals(player)
	player.blind(1.0)
	assert_signal_emit_count(player, "blinded", 1, "without Klarsicht")
	PlayerCurses.ensure(player).add_curse(PlayerCurses.Curse.GLOOM)
	assert_lt(PlayerCurses.vision_factor(player), 1.0, "gloom narrows the circle")
	MetaProgression.set_player_provisions(player, _provisions([String(MetaProgression.BOOST_CLEAR_SIGHT)]))
	player.blind(1.0)
	assert_signal_emit_count(player, "blinded", 1, "immune with Klarsicht")
	assert_eq(PlayerCurses.vision_factor(player), 1.0, "no gloom with Klarsicht")


# --- A4 Glück ---

func test_luck_zero_draws_like_before_and_luck_counts_at_the_manager() -> void:
	var manager := UpgradeManager.new()
	var pool_data: Array[UpgradeData] = []
	for i in 6:
		var upgrade := UpgradeData.new()
		upgrade.id = StringName("wave3_%d" % i)
		upgrade.category = UpgradeData.Category.MECHANIC if i % 2 == 0 else UpgradeData.Category.ATTRIBUTE
		pool_data.append(upgrade)
	manager.upgrade_pool = pool_data
	add_child_autofree(manager)
	var player := _player()
	manager.player = player
	for seed_value in [1, 7, 99]:
		var a := RandomNumberGenerator.new()
		a.seed = seed_value
		var b := RandomNumberGenerator.new()
		b.seed = seed_value
		var old: Array[UpgradeData] = []
		var pool := manager.get_available_upgrades([])
		while not pool.is_empty() and old.size() < UpgradeManager.OFFER_SIZE:
			old.append(pool.pop_at(b.randi_range(0, pool.size() - 1)))
		assert_eq(manager.roll_offer([], a), old, "seed %d: the old offer at Glück 0" % seed_value)
	MetaProgression.set_player_provisions(player, _provisions([], 3))
	assert_eq(MetaProgression.player_luck_level(manager.player), 3, "the manager's player brings Glück")


# --- A7 Händlerfreund ---

func test_merchant_friend_lowers_the_price_of_the_buyer() -> void:
	var economy := EconomySystem.new()
	add_child_autofree(economy)
	var player := _player()
	var offer := ShopOffer.new()
	offer.kind = ShopOffer.Kind.SHIELD
	offer.price = 100
	offer.amount = 1.0
	assert_eq(EconomySystem.price_for(offer, player), 100)
	MetaProgression.set_player_provisions(player, _provisions([], 0, 2))
	assert_eq(EconomySystem.price_for(offer, player), 80, "-10 % per level")
	RunManager.start_run()
	RunManager.add_run_gold(85)
	assert_true(economy.can_purchase(offer, player, null), "85 gold buy what costs 80 for this buyer")
	assert_true(economy.purchase(offer, player, null))
	assert_eq(RunManager.get_run_gold(), 5, "the buyer's price was paid")


# --- A8 Proviant in a quick game, A6 Goldregen of the group ---

func test_provisions_travel_in_the_profile_and_land_on_the_hosts_player() -> void:
	SaveManager.add_pending_boost(MetaProgression.BOOST_HEALING_POTION)
	SaveManager.add_pending_boost(MetaProgression.BOOST_GOLD_RAIN)
	var own := LobbyClient.own_provisions()
	assert_true(own.has(MetaProgression.BOOST_GOLD_RAIN), "in the village: the packed Proviant")
	var profile := {"provisions": MetaProgression.provision_snapshot(own)}
	var clean := NetPlayers.profile_provisions(profile)
	assert_eq(clean["boosts"].size(), 2)
	assert_eq(NetPlayers.profile_provisions({}), {}, "old profiles bring none")
	var dungeon := _dungeon()
	await wait_physics_frames(2)
	assert_true(LobbyClient.own_provisions().has(MetaProgression.BOOST_GOLD_RAIN), "in the run: the run's Proviant")
	var player := PLAYER_SCENE.instantiate() as Player
	dungeon.add_child(player)
	player.set_physics_process(false)
	var max_before := player.health.get_max_health()
	var net_players := NetPlayers.new()
	net_players.world = dungeon
	net_players._apply_profile_provisions(player, clean)
	assert_almost_eq(player.health.get_max_health(), max_before + MetaProgression.HEALING_POTION_HEALTH, 0.001, "Heiltrank on the host's copy")
	assert_true(MetaProgression.player_has_boost(player, MetaProgression.BOOST_GOLD_RAIN))
	net_players.free()
	_free_dungeon(dungeon)


func test_quick_game_consumes_own_provisions_guild_does_not() -> void:
	var quick := _owner(GameMode.quick(2))
	SaveManager.add_pending_boost(MetaProgression.BOOST_KEEN_NOSE)
	RunManager.start_run()
	assert_true(RunManager.has_run_boost(MetaProgression.BOOST_KEEN_NOSE), "a quick game takes the own Proviant")
	assert_false(SaveManager.has_pending_boost(MetaProgression.BOOST_KEEN_NOSE))
	RunManager.end_run(RunManager.EndReason.ABORT)
	_remove_owner(quick)
	var guild := _owner(GameMode.guild(2))
	SaveManager.add_pending_boost(MetaProgression.BOOST_KEEN_NOSE)
	RunManager.start_run()
	assert_false(RunManager.has_run_boost(MetaProgression.BOOST_KEEN_NOSE), "guild runs have none")
	assert_true(SaveManager.has_pending_boost(MetaProgression.BOOST_KEEN_NOSE), "it waits")
	RunManager.end_run(RunManager.EndReason.ABORT)
	_remove_owner(guild)


func test_group_gold_rain_is_the_mean_of_the_players() -> void:
	var with_rain := _player()
	var without := _player()
	MetaProgression.set_player_provisions(with_rain, _provisions([String(MetaProgression.BOOST_GOLD_RAIN)]))
	MetaProgression.set_player_provisions(without, _provisions([]))
	RunManager.start_run()
	assert_almost_eq(MetaProgression.get_gold_multiplier(), 1.0, 0.0001)
	RunManager.set_group_gold_factor(MetaProgression.group_gold_factor([with_rain, without]))
	assert_almost_eq(MetaProgression.get_gold_multiplier(), 1.5, 0.0001, "the host's group factor counts")
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()
	assert_almost_eq(MetaProgression.get_gold_multiplier(), 1.0, 0.0001, "a new run forgets it")


# --- A5 Spürnase, A9 Dorf-"!" ---

func test_keen_nose_names_the_rewards_of_a_branch() -> void:
	var player := _player()
	var options: Array[String] = [BranchOption.create(BranchOption.Kind.SAFE).reward_text(),
			BranchOption.create(BranchOption.Kind.SPECIAL, SpecialTable.SHOP).reward_text()]
	assert_eq(BranchOption.reward_preview(options, player), "", "without Spürnase nothing")
	MetaProgression.set_player_provisions(player, _provisions([String(MetaProgression.BOOST_KEEN_NOSE)]))
	var preview := BranchOption.reward_preview(options, player)
	assert_string_contains(preview, Loc.t(&"ROOM_SHOP_TITLE"))
	assert_string_contains(preview, Loc.t(&"BRANCH_REWARD_SAFE"))


func test_trade_levels_light_the_trader_marker() -> void:
	SaveManager.add_permanent_crystals(MetaProgression.get_trade_next_cost(MetaProgression.TRADE_MERCHANT_FRIEND))
	var items := preload("res://world/village/village_affordable.gd").affordable_items(VillageBuildings.TRADER)
	if MetaUnlocks.is_building_open(VillageBuildings.TRADER):
		assert_true(items.has(MetaProgression.TRADE_MERCHANT_FRIEND), "a trade level counts for the '!'")
	else:
		assert_true(items.is_empty(), "closed building: nothing")


# --- B Zuhause ---

func test_home_door_loads_the_interior() -> void:
	AccountSeen.mark_seen(HomeInterior.EXPLANATION_ID)
	HomeTravel.reset()
	var world_root := Node2D.new()
	add_child_autofree(world_root)
	var controller := WorldController.new()
	controller.world_root = world_root
	controller.village_scene = load(VILLAGE_SCENE) as PackedScene
	controller.dungeon_scene = load(VILLAGE_SCENE) as PackedScene
	add_child_autofree(controller)
	await wait_process_frames(2)
	var village := controller.get_world() as Village
	assert_not_null(village)
	assert_eq(VillageBuildings.get_prompt(VillageBuildings.HOME), Loc.t(&"VILLAGE_HOME_INSIDE_ENTER"))
	village.enter_building(VillageBuildings.HOME)
	await wait_seconds(HomeTravel.DOOR_OPEN_TIME + 0.2)
	assert_true(controller.get_world() is HomeInterior, "the door leads inside, no wardrobe")
	assert_false(VillageBuildings.needs_intro(VillageBuildings.HOME), "entering counts as explained")


# --- C Übungsgang and bonus XP ---

func test_practice_run_starts_before_room_one_alone_and_not_in_a_group() -> void:
	TutorialRun.force_next = true
	var dungeon := _dungeon()
	await wait_physics_frames(1)
	var run := TutorialRun.of(dungeon)
	assert_not_null(run, "alone: the hall before room 1")
	var spawn := dungeon.get_node("PlayerSpawn") as Node2D
	assert_gt(spawn.global_position.y, TutorialRules.ORIGIN.y - 5000.0, "the spawn moved into the hall")
	_free_dungeon(dungeon)
	var group := _owner(GameMode.quick(2))
	TutorialRun.force_next = true
	var group_dungeon := _dungeon()
	await wait_physics_frames(1)
	assert_null(TutorialRun.of(group_dungeon), "a group game: no practice run")
	assert_lt((group_dungeon.get_node("PlayerSpawn") as Node2D).global_position.y, TutorialRules.ORIGIN.y - 5000.0)
	_free_dungeon(group_dungeon)
	_remove_owner(group)


func test_bonus_xp_counts_once_and_stays() -> void:
	AccountProgress.path_override = ROOT + "/progress.cfg"
	AccountProgress.reset()
	var progress := AccountProgress.current()
	var before := progress.get_total_xp()
	assert_true(TutorialRules.credit_xp(progress, TutorialRules.XP_FIRST_COMPLETION), "the practice run's hook")
	assert_false(progress.add_bonus_xp(TutorialRules.XP_CREDIT_ID, 25), "once per id")
	assert_eq(progress.get_total_xp(), before + TutorialRules.XP_FIRST_COMPLETION)
	assert_eq(int(progress.to_profile()["xp"]), before + TutorialRules.XP_FIRST_COMPLETION, "in the profile")
	assert_true(progress.get_pending_xp_entries().is_empty(), "no run entry for the server yet")
	AccountProgress.reset()
	var again := AccountProgress.current()
	assert_true(again.has_bonus_xp(TutorialRules.XP_CREDIT_ID), "saved")
	assert_eq(again.get_total_xp(), before + TutorialRules.XP_FIRST_COMPLETION)
	assert_false(again.add_bonus_xp(TutorialRules.XP_CREDIT_ID, 25))
	AccountProgress.path_override = ""
	AccountProgress.reset()


# --- D Sprungprobe ---

func _segment(plan: StringName, rng_seed := 99) -> SideSegment:
	var segment := SideSegment.new()
	segment.setup(SidePlans.build(plan), 1, null, rng_seed)
	add_child_autofree(segment)
	segment.global_position = SideSegment.WORLD_ORIGIN
	return segment


func test_element_clock_goes_from_the_host_to_the_client() -> void:
	var host_segment := _segment(&"crypt_gauntlet")
	var client_segment := _segment(&"crypt_gauntlet")
	var net := RecordingNet.new()
	var host_side := NetSide.create(net, null)
	host_side.is_host = true
	host_side._segment = host_segment
	host_side._segment_slot = 5
	host_segment.apply_element_clock(3.25)
	host_side._tick_clock(host_segment, STEP)
	var clocks := net.sent.filter(func(entry: Array) -> bool: return entry[0] == &"side_clock_net")
	assert_eq(clocks.size(), 1, "at the start")
	host_side._tick_clock(host_segment, 0.5)
	assert_eq(host_side.clocks_sent, 1, "not again before a second")
	host_side._tick_clock(host_segment, 0.6)
	assert_eq(host_side.clocks_sent, 2, "about once a second")
	var client_side := NetSide.create(net, null)
	client_side.is_host = false
	client_side._segment = client_segment
	client_side._segment_slot = 5
	client_side.side_clock_net(5, float(clocks[0][1][1]))
	assert_almost_eq(client_segment.get_element_clock(), 3.25, 0.001, "the client's elements at the host's clock")
	assert_eq(client_segment.get_movers()[0].position, host_segment.get_movers()[0].position)
	client_side.side_clock_net(6, 9.0)
	assert_almost_eq(client_segment.get_element_clock(), 3.25, 0.001, "another segment's clock is ignored")
	host_side.free()
	client_side.free()
	net.free()


func test_spring_throws_a_jump_off_it_too() -> void:
	var segment := _segment(&"crypt_springs", 7)
	var player := _player()
	segment.add_player(player)
	var spring := segment.get_springs()[0]
	player.global_position = spring.global_position - Player.FEET_OFFSET + Vector2(0, -10)
	player.velocity = Vector2(0, -SideRules.JUMP_VELOCITY)
	player.side_motion._jumping = true
	watch_signals(spring)
	spring._physics_process(STEP)
	assert_signal_emitted(spring, "launched", "the spring throws while jumping off it")
	assert_almost_eq(player.velocity.y, -SideElementRules.spring_velocity(), 0.01)
	assert_false(player.side_motion.is_jumping(), "launch ends the jump: letting go cannot cut the rise")
	segment.remove_players()


func test_plans_come_from_the_current_and_the_previous_tier() -> void:
	for run_seed in 60:
		var layout := SidePlans.pick(&"ember_forge", SideRules.make_rng(run_seed, 3), false, 3)
		assert_gte(layout.tier, 2, "%s: no tier 1 plan at tier 3" % layout.plan_id)
	assert_eq(SidePlans.pick_min_tier(1), 1)
	assert_eq(SidePlans.pick_min_tier(2), 1)
	assert_eq(SidePlans.pick_min_tier(3), 2)


# --- E Rückstoß ---

func test_knockback_pushes_and_stops_at_an_abyss_edge() -> void:
	var player := _player()
	player.global_position = Vector2(100, 100)
	player.fall.pit_probe = func(point: Vector2) -> bool: return point.x > 140.0
	player.apply_knockback(Vector2(400, 0))
	player.apply_knockback(Vector2(200, 0))
	assert_almost_eq(player.get_knockback_velocity().x, 400.0, 0.01, "the strongest push wins, nothing adds up")
	for i in 30:
		player._tick_knockback(STEP)
	var feet_x := player.get_feet_position().x
	assert_gt(player.global_position.x, 105.0, "pushed")
	assert_lte(feet_x, 140.0, "never over the abyss")
	assert_eq(player.get_knockback_velocity(), Vector2.ZERO, "the push ended at the edge")


func test_effective_hits_push_the_player() -> void:
	var player := _player()
	player.fall.pit_probe = func(_point: Vector2) -> bool: return false
	var damage := DamageData.new()
	damage.amount = 0.5
	damage.hit_id = DamageData.next_hit_id()
	damage.knockback = Vector2(0, 240)
	var result := player.hurtbox.receive_hit(damage)
	assert_true(result.is_effective())
	assert_gt(player.get_knockback_velocity().y, 0.0, "DamageData.knockback on the player")


# --- F Flint ---

func test_flint_has_a_neutral_mood_and_a_dark_disc() -> void:
	assert_eq(FlintGuideRules.portrait_animation(FlintGuideStep.Mood.NEUTRAL), &"neutral")
	assert_eq(FlintPortrait.RING_FILL, Color("#2a2638"))
	var portrait := FlintPortrait.new()
	add_child_autofree(portrait)
	portrait.set_mood(FlintGuideStep.Mood.NEUTRAL)
	assert_eq(portrait.animation, &"neutral", "the delivered neutral strip")

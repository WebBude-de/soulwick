extends GutTest
## Room modes on a network client (R4 with MP3, D-126, D-135..D-137, NetModes): every machine builds the
## same mode from the slot's RNG state (layout in the room signature), a client's mode never starts
## (RoomController.remote_encounter) and shows what the host sends: flame health, souls, collapsing
## fields, the villager, the bonus; its own banners stay quiet. Uses a test save, never the real one.

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const COLLAPSE_ROOM: PackedScene = preload("res://dungeon/rooms/combat/einsturz_halle_ember_forge.tscn")
const RIFTS_ROOM: PackedScene = preload("res://dungeon/rooms/combat/risse_schlucht_ember_forge.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_net_modes.cfg"
	SaveManager.load_game()


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()


func after_each() -> void:
	HitStop.reset()
	await wait_process_frames(1)


func _room(scene: PackedScene = HALL, room_index := 17, remote := false) -> RoomController:
	var room := scene.instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 77
	room.setup(room_index, RoomSequence.RoomType.COMBAT, -1, false, context)
	var spawner := room.get_node("EnemySpawner") as EnemySpawner
	spawner.biomes = [] as Array[BiomeData]
	spawner.extra_types = [] as Array[EnemyData]
	spawner.enemy_types = [SKELETON] as Array[EnemyData]
	spawner.spawn_weights = [1.0] as Array[float]
	room.remote_encounter = remote
	add_child_autofree(room)
	return room


## A client's NetModes (no session: only the apply side is used).
func _client_modes() -> NetModes:
	var modes: NetModes = add_child_autofree(NetModes.new())
	modes.is_host = false
	return modes


func test_the_same_seed_builds_the_same_mode_layout() -> void:
	for id: StringName in [&"flame", &"relic", &"lightfire", &"hunt"]:
		var host := _room()
		var client := _room(HALL, 17, true)
		var host_mode := CombatVariant.attach_to(host, id, 4242)
		var client_mode := CombatVariant.attach_to(client, id, 4242)
		assert_not_null(host_mode, "%s fits the hall" % id)
		assert_not_null(client_mode)
		assert_ne(NetModes.layout_of(host), "", "%s has a layout" % id)
		assert_eq(NetModes.layout_of(client), NetModes.layout_of(host), "%s: same layout on both machines" % id)
		assert_string_contains(NetDungeon.signature_of(client), NetModes.layout_of(client), "the layout is part of the room signature")
	var plain := _room()
	assert_eq(NetModes.layout_of(plain), "", "no mode, no layout")


func test_a_client_mode_never_starts_and_keeps_its_banners_quiet() -> void:
	var room := _room(HALL, 17, true)
	var mode := CombatVariant.attach_to(room, &"flame", 7)
	var modes := _client_modes()
	modes.on_room_prepared(room)
	assert_true(mode.banners_muted, "the host's banners come instead")
	mode.start()
	assert_false(mode.is_started(), "the host runs the mode (remote_encounter)")
	watch_signals(mode)
	mode.show_banner("Titel", "Untertitel")
	assert_signal_emitted(mode, "banner_shown", "the hook still fires")


func test_flame_health_and_bonus_follow_the_host() -> void:
	var host := _room()
	var client := _room(HALL, 17, true)
	var host_mode := CombatVariant.attach_to(host, &"flame", 7) as FlameMode
	var client_mode := CombatVariant.attach_to(client, &"flame", 7) as FlameMode
	var modes := _client_modes()
	modes.on_room_prepared(client)
	host_mode.flame.health.reset(120.0)
	host_mode.flame.health.set_current(54.0)
	assert_true(modes.apply_state(client, NetModes.capture_state(host_mode)))
	assert_almost_eq(client_mode.flame.get_health_ratio(), 0.45, 0.001, "the client's flame shows the host's health")
	host_mode.flame.health.take_damage(999.0)
	modes.apply_state(client, NetModes.capture_state(host_mode))
	assert_false(client_mode.flame.is_alive(), "out at the host, out here")
	assert_eq(client_mode.bonus, CombatVariant.Bonus.LOST, "no bonus without the flame")
	assert_true(modes.apply_bonus(client, false))
	assert_eq(modes.bonus_by_slot[client.slot_index], 0)


func test_souls_appear_go_and_end_as_at_the_host() -> void:
	var room := _room(HALL, 17, true)
	var mode := SoulsMode.attach(room, 31)
	assert_not_null(mode, "souls fit the hall")
	var modes := _client_modes()
	modes.on_room_prepared(room)
	assert_true(modes.apply_event(room, NetModes.Event.SOUL_SPAWNED, [0]))
	modes.apply_event(room, NetModes.Event.SOUL_SPAWNED, [1])
	modes.apply_event(room, NetModes.Event.SOUL_SPAWNED, [1])
	assert_eq(mode.get_visible_wisps().size(), 2, "two souls, the second only once")
	assert_eq(mode.get_node("Soul1").tile, mode.spots[1], "at the host's place")
	modes.apply_event(room, NetModes.Event.SOUL_TAKEN, [0])
	modes.apply_event(room, NetModes.Event.SOUL_LOST, [1])
	assert_eq(mode.collected, 1)
	assert_eq(mode.get_visible_wisps().size(), 0)
	modes.apply_event(room, NetModes.Event.SOULS_OVER, [1, 1])
	assert_true(mode.is_round_over)
	var crystal := mode.get_crystal_pickup()
	assert_not_null(crystal, "the crystals lie by the exit here too")
	assert_eq(crystal.amount, 0, "booked at the host only (shared pot)")


func test_collapse_fields_break_here_when_the_host_says_so() -> void:
	var room := _room(COLLAPSE_ROOM, 17, true)
	var mode := CollapseMode.attach(room, 13)
	assert_not_null(mode, "the collapse fits the plan room")
	var modes := _client_modes()
	modes.on_room_prepared(room)
	mode.step(40.0)
	assert_eq(mode.broken_count, 0, "nothing breaks by itself on a client")
	modes.apply_event(room, NetModes.Event.FIELD_WARNED, [0])
	assert_eq(mode.field_states[0], CollapseMode.FieldState.WARNED)
	modes.apply_event(room, NetModes.Event.FIELD_BROKEN, [0])
	assert_eq(mode.field_states[0], CollapseMode.FieldState.BROKEN)
	for tile: Vector2i in mode.fields[0]:
		assert_true(room.tiles.is_pit(tile), "the field is abyss here too")
	modes.apply_event(room, NetModes.Event.SURVIVED)
	assert_true(mode.is_survived)
	assert_eq(mode.chests.size(), 1, "the bonus chest waits at the end of the way")


func test_a_sinkhole_opens_and_closes_here_when_the_host_says_so() -> void:
	var room := _room(COLLAPSE_ROOM, 17, true)
	var mode := CollapseMode.attach(room, 13)
	var modes := _client_modes()
	modes.on_room_prepared(room)
	var tiles: Array[Vector2i] = []
	tiles.assign(mode.fields[0])
	for tile in tiles:
		assert_false(room.tiles.is_pit(tile), "standing floor before")
	var args := NetModes._sinkhole_args(tiles, CollapseMode.SinkPhase.OPENED)
	assert_eq(NetModes._sinkhole_tiles(args), tiles, "the tiles survive the wire")
	assert_true(modes.apply_event(room, NetModes.Event.SINKHOLE, args))
	for tile in tiles:
		assert_true(room.tiles.is_pit(tile), "the sinkhole is abyss here too")
	modes.apply_event(room, NetModes.Event.SINKHOLE, NetModes._sinkhole_args(tiles, CollapseMode.SinkPhase.CLOSED))
	for tile in tiles:
		assert_false(room.tiles.is_pit(tile), "and floor again when the host closes it")
	assert_not_null(mode)


func test_the_villager_walks_and_loses_hearts_as_at_the_host() -> void:
	var host := _room()
	var client := _room(HALL, 17, true)
	var host_mode := EscortMode.attach(host, 5)
	var client_mode := EscortMode.attach(client, 5)
	assert_not_null(host_mode, "the escort fits the hall")
	var modes := _client_modes()
	modes.on_room_prepared(client)
	host_mode.walk_state = EscortMode.Walk.WALKING
	host_mode.travelled = 64.0
	host_mode.villager.set_max_hearts(3)
	host_mode.villager.hearts = 2
	modes.apply_state(client, NetModes.capture_state(host_mode))
	assert_eq(client_mode.villager.max_hearts, 3)
	assert_eq(client_mode.villager.hearts, 2, "one heart lost at the host")
	assert_eq(client_mode.walk_state, EscortMode.Walk.WALKING)
	# Follows at VILLAGER_FOLLOW_SPEED per second of real frames (headless frame rates vary).
	await wait_seconds(0.6)
	assert_almost_eq(client_mode.travelled, 64.0, 0.5, "he follows the host's way share")
	modes.apply_event(client, NetModes.Event.VILLAGER_LOST)
	assert_false(client_mode.villager.is_alive(), "his last heart went at the host")
	assert_eq(client_mode.walk_state, EscortMode.Walk.DOWN)


func test_the_goal_texts_of_a_mode_variant_are_mirrored() -> void:
	var host_goal: RoomObjective = autofree(RoomObjective.create(RoomObjective.ESCORT))
	host_goal.goal_key = &"MODE_ESCORT_CHICKEN_GOAL"
	host_goal.auto_danger = true
	var room: Node2D = add_child_autofree(Node2D.new())
	var goal := NetDungeon.apply_objective_state(room, NetDungeon.objective_state_of(host_goal))
	assert_eq(goal.goal_key, &"MODE_ESCORT_CHICKEN_GOAL", "the chicken's goal on the client too")
	assert_false(goal.auto_danger, "danger comes from the host")


func test_relic_and_torches_ask_the_host_and_follow_it() -> void:
	var room := _room(HALL, 17, true)
	var mode := CombatVariant.attach_to(room, &"relic", 21) as RelicMode
	assert_not_null(mode, "the relic fits the hall")
	var modes := _client_modes()
	modes.on_room_prepared(room)
	var relic := mode.relics[0]
	relic.get_interactable().interacted.emit(null)
	assert_eq(relic.state, Relic.State.LYING, "E only asks the host")
	assert_eq(modes.actions, 1)
	var at := relic.global_position
	var host_state: Array = [int(Relic.State.CARRIED), 0, at.x, at.y]
	modes.apply_state(room, host_state)
	assert_true(relic.is_carried(), "carried at the host, carried here")
	modes.apply_state(room, [int(Relic.State.LYING), 0, at.x + 64.0, at.y])
	assert_eq(relic.state, Relic.State.LYING)
	assert_almost_eq(relic.global_position.x, at.x + 64.0, 0.5, "where the host's carrier put it down")
	assert_eq(mode.get_placed_count(), 0)
	modes.apply_state(room, [int(Relic.State.PLACED), 0, at.x, at.y])
	assert_true(relic.is_placed(), "on the altar")
	assert_false(relic.get_interactable().enabled)
	assert_eq(mode.get_placed_count(), 0, "the client's mode decides nothing (signals cut off)")

	var dark := _room(HALL, 17, true)
	var lightfire := CombatVariant.attach_to(dark, &"lightfire", 21) as LightfireMode
	modes.on_room_prepared(dark)
	var cold: RoomTorch = null
	for torch in lightfire.torches:
		if not torch.lit:
			cold = torch
			break
	assert_not_null(cold, "a cold stand")
	cold.get_interactable().interacted.emit(null)
	assert_false(cold.lit, "E only asks the host")
	assert_true(modes.apply_event(dark, NetModes.Event.TORCH_LIT, [String(cold.name)]))
	assert_true(cold.lit, "lit at the host, lit here")


# --- Makeover wave B (15.10.2026): bonus chests and rifts ---

func test_bonus_chests_stand_where_the_hosts_stand() -> void:
	var room := _room(HALL, 17, true)
	var mode := CombatVariant.attach_to(room, &"flame", 7)
	var modes := _client_modes()
	modes.on_room_prepared(room)
	var host_spot := Vector2(200, 300)
	assert_true(modes.apply_chest(room, "BonusChest0", host_spot), "kept until the chest is placed here")
	var placed := mode.spawn_bonus_chests(Vector2(600, 400))
	assert_false(placed.is_empty())
	# The chest lifts its sort origin in _ready (SortLift), on the host the same way.
	var lift := Vector2(0, Player.FEET_OFFSET.y)
	assert_eq(placed[0].position, host_spot - lift, "placed at the host's spot, not by this machine's players")
	modes.apply_chest(room, "BonusChest0", host_spot + Vector2(64, 0))
	assert_eq(placed[0].position, host_spot + Vector2(64, 0) - lift, "a chest already here moves")


func test_a_client_wall_rift_shows_no_second_hole() -> void:
	var room := _room(RIFTS_ROOM, 20, true)
	var mode := CombatVariant.attach_to(room, &"rifts", 4242) as RiftsMode
	assert_not_null(mode, "rifts fit their plan room")
	var tiles := mode.get_wall_rift_tiles()
	assert_false(tiles.is_empty(), "the plan has wall rifts")
	var modes := _client_modes()
	modes.on_room_prepared(room)
	assert_true(NetModes.hide_rift_opening(mode, tiles[0]), "the wall source of the rift is found")
	var source: SpawnSource = null
	for candidate in mode.get_sources().get_sources():
		if candidate.kind == SpawnSourceRules.Kind.RIFT_WALL and candidate.floor_tile == tiles[0]:
			source = candidate
	assert_not_null(source)
	assert_true(source.is_opening_hidden(), "like at the host: the rift is the opening")
	source.warn()
	source.open(true)
	source.settle()
	assert_true(source.is_opening_hidden(), "the host's phases keep the wall whole")
	assert_false(NetModes.hide_rift_opening(mode, Vector2i(-50, -50)), "no source there")

extends GutTest
## Co-op feel (MP5, D-191) without a network: the host's "Seitenwege auslassen" for the whole group,
## stragglers landing on a plateau (M3), the trap clock a client follows, pact curses laid once on a
## copy, the light circle of a mate (optics only) and the arrows to mates off screen.

const TEST_SAVE_PATH := "user://test_net_coop_feel.cfg"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const SPIKE_SCENE: PackedScene = preload("res://dungeon/environment/traps/spike_trap.tscn")
const LAVA_SCENE: PackedScene = preload("res://dungeon/environment/traps/lava_crack.tscn")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.load_game()


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func _player(at := Vector2.ZERO) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.global_position = at
	player.health.reset(10.0)
	return player


# --- Side ways: the host's option ---

func test_the_group_skips_side_ways_by_the_hosts_option_from_the_run_start() -> void:
	var net := NetDungeon.new()
	autofree(net)
	var run := NetRun.new()
	autofree(run)
	net.run = run
	assert_false(net.side_ways_skipped(), "default: side ways on")
	run.side_ways_skipped = true
	assert_true(net.side_ways_skipped(), "the host skips: every machine skips")
	var lone := NetDungeon.new()
	autofree(lone)
	assert_false(lone.side_ways_skipped(), "a client without a run never guesses the own option")


# --- Stragglers on a plateau (M3) ---

func test_a_straggler_may_land_on_a_plateau_but_never_on_its_cliff_or_ladder() -> void:
	var room: RoomController = null
	var entries := RoomCatalog.create().get_entries()
	entries.append_array(RoomCatalog.load_plans().get_entries())
	for entry in entries:
		var candidate := entry.scene.instantiate() as RoomController
		if (candidate.get_node("Tiles") as RoomTiles).has_height():
			room = candidate
			break
		candidate.free()
	if room == null:
		pass_test("no template with height in the catalog")
		return
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 11
	room.setup(3, RoomSequence.RoomType.COMBAT, -1, false, context)
	add_child_autofree(room)
	var tiles := room.get_node("Tiles") as RoomTiles
	var layout := tiles.get_height_layout()
	var reachable := tiles.get_height_reachable_tiles()
	var inside := room.get_arena().grow(-GateCloser.INSIDE_MARGIN)
	var start := room.get_player_start()
	var surface_checked := 0
	for tile: Vector2i in layout.surface:
		var point := room.to_global(RoomTiles.tile_center(tile))
		if not inside.has_point(point) or not reachable.has(tile):
			continue
		assert_eq(NetDungeon.gather_point(room, point, start), point, "reachable plateau %s is floor" % tile)
		surface_checked += 1
	assert_gt(surface_checked, 0, "%s: a reachable plateau tile inside the room" % room.scene_file_path.get_file())
	for tile: Vector2i in layout.cliffs.keys() + layout.ladders.keys() + layout.stairs.keys():
		var point := room.to_global(RoomTiles.tile_center(tile))
		if inside.has_point(point):
			assert_eq(NetDungeon.gather_point(room, point, start), start, "cliff, ladder or stair %s: the start" % tile)


# --- Trap clock ---

func test_a_client_trap_steps_into_the_hosts_phase_and_waits_for_the_next() -> void:
	var trap: SpikeTrap = SPIKE_SCENE.instantiate()
	add_child_autofree(trap)
	await wait_physics_frames(1)
	NetDetails.apply_phase(trap, SpikeTrap.Phase.WARN)
	assert_eq(NetDetails.phase_of(trap), SpikeTrap.Phase.WARN)
	assert_almost_eq(float(trap.get(&"_time_left")), SpikeTrap.WARN_TIME + NetDetails.TRAP_SLACK, 0.001, "own clock runs longer")
	NetDetails.apply_phase(trap, SpikeTrap.Phase.ACTIVE)
	assert_true(trap.is_active(), "spikes out with the host")
	assert_true((trap.get(&"_hitbox") as Hitbox).is_active(), "it stepped there itself (hitbox, sound)")
	NetDetails.apply_phase(trap, SpikeTrap.Phase.ACTIVE)
	assert_true(trap.is_active(), "the same phase again only resets the clock")
	NetDetails.apply_phase(trap, SpikeTrap.Phase.IDLE)
	assert_eq(NetDetails.phase_of(trap), SpikeTrap.Phase.IDLE)
	assert_false((trap.get(&"_hitbox") as Hitbox).is_active())
	await wait_seconds(SpikeTrap.IDLE_TIME * 0.5)
	assert_eq(NetDetails.phase_of(trap), SpikeTrap.Phase.IDLE, "no step of its own while the host's is due")


func test_a_sleeping_lava_crack_takes_the_hosts_phase_directly() -> void:
	var crack: LavaCrack = LAVA_SCENE.instantiate()
	add_child_autofree(crack)
	crack.global_position = Vector2(50000, 50000)
	await wait_physics_frames(1)
	NetDetails.apply_phase(crack, LavaCrack.Phase.WARN)
	assert_true(crack.is_warning(), "nobody near here, the host's player is: warning anyway")
	assert_almost_eq(NetDetails.phase_time(crack, LavaCrack.Phase.ACTIVE), LavaCrack.ACTIVE_TIME, 0.001)


func test_traps_of_a_room_in_build_order() -> void:
	var room := Node2D.new()
	add_child_autofree(room)
	var props := Node2D.new()
	room.add_child(props)
	var first: SpikeTrap = SPIKE_SCENE.instantiate()
	props.add_child(first)
	room.add_child(Node2D.new())
	var second: LavaCrack = LAVA_SCENE.instantiate()
	room.add_child(second)
	var traps := NetDetails.traps_of(room)
	assert_eq(traps.size(), 2)
	assert_eq(traps[0], first)
	assert_eq(traps[1], second)


# --- Pact curses ---

func test_a_curse_is_laid_on_a_copy_once_and_frailty_acts_there() -> void:
	var copy := _player()
	assert_true(NetDetails.lay_curse(copy, PlayerCurses.Curse.FRAILTY), "laid")
	assert_true(PlayerCurses.has_curse(copy, PlayerCurses.Curse.FRAILTY))
	assert_almost_eq(copy.health.get_max_health(), 10.0 - PlayerCurses.MAX_HEALTH_LOSS, 0.001, "one heart less on the copy")
	assert_false(NetDetails.lay_curse(copy, PlayerCurses.Curse.FRAILTY), "never twice (own player, echo)")
	assert_almost_eq(copy.health.get_max_health(), 10.0 - PlayerCurses.MAX_HEALTH_LOSS, 0.001)
	assert_false(NetDetails.lay_curse(copy, 99), "unknown curse")
	assert_false(NetDetails.lay_curse(null, PlayerCurses.Curse.HASTE))
	assert_true(NetDetails.lay_curse(copy, PlayerCurses.Curse.HASTE))
	assert_almost_eq(PlayerCurses.enemy_speed_factor(copy), PlayerCurses.ENEMY_SPEED_FACTOR, 0.001, "enemies of the host hunt it faster")


# --- Merchant ---

func test_merchant_offers_have_their_own_key_apart_from_shop_rooms() -> void:
	assert_eq(NetDungeon.merchant_key(7), NetDungeon.MERCHANT_KEY + 7)
	assert_gt(NetDungeon.merchant_key(1), 500, "never a room's slot")


# --- Mate light ---

func test_a_mate_carries_a_light_that_only_draws() -> void:
	var mate := _player(Vector2(100, 100))
	var light := MateLight.attach(mate)
	assert_not_null(light)
	assert_eq(MateLight.attach(mate), light, "one per mate")
	await wait_process_frames(2)
	assert_true(light.is_in_group(LightSource.GROUP), "the overlay draws it")
	assert_false(light.is_in_group(LightSource.GAMEPLAY_GROUP), "optics only: no LightQuery circle")
	assert_false(light.counts_as_light)
	assert_true(light.is_lit())
	light.set_hidden(true)
	assert_false(light.is_lit(), "in a tunnel under the rock: gone")
	light.set_hidden(false)
	assert_true(light.is_lit())
	assert_almost_eq(MateLight.radius_for(300.0, 1.2, 1.5, false), 240.0, 0.01, "same size as an own circle")
	assert_almost_eq(MateLight.radius_for(300.0, 1.0, 1.0, true), 300.0 * MateLight.DOWNED_SHARE, 0.01, "a downed mate glows small")


# --- Arrows to mates off screen ---

func test_arrows_point_from_the_screen_edge_to_mates_off_screen() -> void:
	var view := Rect2(0, 0, 1280, 720)
	var right := MatePointers.edge_point(view, Vector2(5000, 360), 20.0)
	assert_almost_eq(right.x, 1260.0, 0.01, "right edge inside the margin")
	assert_almost_eq(right.y, 360.0, 0.01)
	var corner := MatePointers.edge_point(view, Vector2(-1000, -1000), 20.0)
	assert_true(view.grow(-19.0).has_point(corner), "corner inside the margin: %s" % corner)
	assert_eq(MatePointers.short_name("Anna"), "Anna")
	assert_eq(MatePointers.short_name("Maximilian").length(), MatePointers.NAME_CHARS, "long names cut")
	var pointers := MatePointers.new()
	add_child_autofree(pointers)
	var size := pointers.get_view().size
	var targets: Array[Dictionary] = [
		{"point": size * 0.5, "color": Color.RED, "name": "on screen"},
		{"point": size * 3.0, "color": Color.BLUE, "name": "far"},
	]
	pointers.set_targets(targets)
	assert_eq(pointers.get_target_count(), 2)
	assert_eq(pointers.get_arrow_count(), 1, "only the mate off screen gets an arrow")
	await wait_process_frames(1)
	pointers.set_targets([] as Array[Dictionary])
	assert_eq(pointers.get_arrow_count(), 0)

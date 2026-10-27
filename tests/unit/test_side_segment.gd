extends GutTest
## A side segment as a world (M5): tiles from the biome's rock set (rock with the corner rule,
## ledges one-way), coins, golden coin, ladders with top steps, spike trap, enemies, chest, door,
## camera inside the segment; the side enemies take hits like enemies (EventBus, gold); the transit
## fades in, hands the players over, gives them back and puts them into the next room.
## Round 3: pools slow the running (and let go), spike runs fire as a wave, a client's trap waits for
## the host, turrets only when the layout sets them up, the biome dressing is the same on every
## machine, and the doorway behind the start.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const STEP := 1.0 / 60.0

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_side_segment_save.cfg"


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	SaveManager.save_path = _old_save_path


func after_each() -> void:
	HitStop.reset()
	await wait_process_frames(1)


func _segment(plan: StringName, mirrored := false) -> SideSegment:
	var segment := SideSegment.new()
	segment.setup(SidePlans.build(plan, mirrored), 1, null, 7)
	add_child_autofree(segment)
	segment.global_position = SideSegment.WORLD_ORIGIN
	return segment


func test_segment_builds_everything_of_its_plan() -> void:
	for plan in [&"crypt_gallery", &"grotto_pools", &"shadow_rift", &"ember_anvils", &"crypt_gauntlet", &"shadow_tower"]:
		var segment := _segment(plan)
		var layout := segment.layout
		var tiles := segment.get_node("Tiles") as TileMapLayer
		var solid := 0
		for row in layout.size.y:
			for column in layout.size.x:
				var cell := Vector2i(column, row)
				if layout.is_blocking(cell) and not layout.is_element_ground(cell):
					solid += 1
		var in_plan := 0
		for cell in tiles.get_used_cells():
			if cell.y < layout.size.y:
				in_plan += 1
		assert_eq(in_plan, solid, "%s: a tile for every rock and ledge cell" % plan)
		assert_eq(segment.coins_total, layout.coins.size(), "%s: coins" % plan)
		assert_true(segment.has_golden_coin(), "%s: golden coin" % plan)
		assert_eq(segment.get_ladder_bodies().size(), layout.ladders.size(), "%s: ladder steps" % plan)
		assert_eq(segment.get_enemies().size(), layout.enemy_cells().size(), "%s: enemies" % plan)
		assert_eq(segment.get_chest() != null, layout.chest.x >= 0, "%s: chest as planned" % plan)
		var bridge_pieces := 0
		for run in layout.bridges:
			bridge_pieces += run.y - run.x + 1
		assert_eq(segment.get_crumbles().size(), layout.crumbles.size() + layout.tilts.size() + bridge_pieces,
				"%s: crumbling ledges, tilting platforms and bridge pieces" % plan)
		assert_not_null(segment.get_node_or_null("Exit"), "%s: door" % plan)
		assert_not_null(segment.camera, "%s: own camera" % plan)
		assert_eq(segment.get_door_feet(), segment.to_global(SideLayout.feet_of(layout.door)))


func test_rock_mask_keeps_corners_only_with_both_sides() -> void:
	var layout := SideLayout.parse(PackedStringArray([
		"#####",
		"#...#",
		"#.#.#",
		"#...#",
		"#####",
	]), &"mask")
	assert_eq(SideTiles.rock_mask(layout, Vector2i(2, 2)), 0, "a lone block")
	# Top row: rock north (outside), east and west, air south; both upper corners count.
	assert_eq(SideTiles.rock_mask(layout, Vector2i(1, 0)), 1 | 2 | 4 | 64 | 128)
	# The left wall: rock north, south and west, air east; corners need both of their sides.
	assert_eq(SideTiles.rock_mask(layout, Vector2i(0, 2)), 1 | 16 | 64 | 32 | 128, "the wall beside the room: only the west corners")
	var full := SideLayout.parse(PackedStringArray(["###", "###", "###"]), &"full")
	assert_eq(SideTiles.rock_mask(full, Vector2i(1, 1)), 255)


func test_ledges_are_one_way_and_pieces_follow_neighbours() -> void:
	var layout := SideLayout.parse(PackedStringArray(["#.===.=.#"]), &"ledges")
	assert_eq(SideTiles.ledge_piece(layout, Vector2i(2, 0)), "front_left")
	assert_eq(SideTiles.ledge_piece(layout, Vector2i(3, 0)), "front_mid")
	assert_eq(SideTiles.ledge_piece(layout, Vector2i(4, 0)), "front_right")
	assert_eq(SideTiles.ledge_piece(layout, Vector2i(6, 0)), "front_single")
	var tileset := SideTiles.tileset_for(&"crypt")
	var source := tileset.get_source(SideTiles.SOURCE_ID) as TileSetAtlasSource
	assert_not_null(source)
	var one_way := 0
	var solid := 0
	for i in source.get_tiles_count():
		var data := source.get_tile_data(source.get_tile_id(i), 0)
		if data.get_collision_polygons_count(0) > 0:
			if data.is_collision_polygon_one_way(0, 0):
				one_way += 1
			else:
				solid += 1
	assert_eq(one_way, 4, "the four fronts are one-way ledges")
	assert_eq(solid, 47, "the 47 rock pieces are solid")
	assert_eq(tileset.get_physics_layer_collision_layer(0), PhysicsLayers.WORLD)


func test_every_biome_has_tiles() -> void:
	for biome in [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]:
		assert_false(SideTiles.sheet_path(biome).is_empty(), "%s rock sheet" % biome)


func test_side_enemy_reports_hits_and_dies_without_gold() -> void:
	var segment := _segment(&"crypt_steps")
	var enemy := segment.get_enemies()[0]
	watch_signals(EventBus)
	watch_signals(enemy)
	var damage := DamageData.new()
	damage.amount = 1.0
	damage.hit_id = DamageData.next_hit_id()
	enemy.hurtbox.receive_hit(damage)
	assert_signal_emitted(EventBus, "enemy_damaged", "upgrade effects and stats see the hit")
	assert_lt(enemy.health.get_health(), enemy.health.get_max_health())
	var kill := DamageData.new()
	kill.amount = 999.0
	kill.hit_id = DamageData.next_hit_id()
	enemy.hurtbox.receive_hit(kill)
	assert_true(enemy.is_dead())
	assert_signal_emitted(enemy, "died")
	await wait_process_frames(2)
	var gold := 0
	for child in segment.get_children():
		if child is GoldPickup:
			gold += 1
	assert_eq(gold, 0, "side enemies are obstacles, the coins are the reward")


func test_side_enemy_is_weaker_than_in_a_room() -> void:
	var segment := _segment(&"crypt_steps")
	for enemy in segment.get_enemies():
		assert_lte(enemy.health.get_max_health(), enemy.data.max_health, "not tougher than in a room at the start")
		assert_eq(enemy.collision_layer, 0, "players walk through it")


func test_spikes_cycle_and_hit_only_when_out() -> void:
	var spikes := SideSpikes.new()
	add_child_autofree(spikes)
	spikes.setup(0.1)
	var hitbox := spikes.get_node("Hitbox") as Hitbox
	assert_false(hitbox.is_active())
	var seen_active := false
	var seen_warn := false
	for i in ceili((SideSpikes.IDLE_TIME + SideSpikes.WARN_TIME + 0.2) / STEP):
		spikes._physics_process(STEP)
		seen_warn = seen_warn or spikes.phase == SideSpikes.Phase.WARN
		if spikes.is_active():
			seen_active = true
			assert_true(hitbox.is_active(), "out = hurts")
	assert_true(seen_warn, "warns first")
	assert_true(seen_active, "then comes out")
	assert_eq(hitbox.collision_mask, PhysicsLayers.PLAYER_HURTBOX, "only players")


func test_camera_stays_inside_the_segment() -> void:
	var segment := _segment(&"crypt_steps")
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.set_physics_process(false)
	segment.add_player(player)
	segment.make_camera_current()
	var view := segment.camera.get_view_rect()
	var bounds := Rect2(segment.global_position, segment.layout.world_size())
	assert_true(segment.camera.is_current())
	assert_gte(view.position.x, bounds.position.x - 1.0, "not left of the segment")
	assert_eq(segment.camera_targets(), [player] as Array[Player], "the camera follows the player")
	segment.remove_players()


func test_transit_hands_the_player_over_and_back() -> void:
	var world := Node2D.new()
	add_child_autofree(world)
	var player := PLAYER_SCENE.instantiate() as Player
	world.add_child(player)
	player.global_position = Vector2(100, 100)
	var placed := []
	var place := func(group: Array) -> void:
		placed.append(group.size())
		for member: Player in group:
			member.global_position = Vector2(300, 100)
	var group: Array[Player] = [player]
	var transit := SideTransit.start(world, group, SidePlans.build(&"crypt_steps"), 1, null, 5, place)
	watch_signals(transit)
	await wait_seconds(SideRules.FADE_TIME + 0.2)
	assert_true(player.is_side_view(), "in side view behind the black")
	assert_true(player.is_input_locked(), "locked while black")
	assert_not_null(transit.segment)
	await wait_seconds(SideRules.BANNER_TIME + SideRules.FADE_TIME + 0.2)
	assert_false(player.is_input_locked(), "free to play")
	transit.segment.finish()
	await wait_seconds(SideRules.FADE_TIME * 2.0 + 0.4)
	assert_false(player.is_side_view(), "top-down again")
	assert_eq(placed, [1], "the next room got the player")
	assert_eq(player.global_position, Vector2(300, 100))
	assert_false(player.is_input_locked())
	assert_true((player.get_node("Camera2D") as Camera2D).is_current(), "the room camera is back")
	assert_false(is_instance_valid(transit), "the transit is gone")
	assert_gte(int(SaveManager.get_stat(SideRules.STAT_SEGMENTS)), 1, "counted for the jump hint")


func test_side_view_keys_come_from_flint() -> void:
	var explanation := FlintControls.explanation_for(FlintControls.SIDE_VIEW)
	assert_not_null(explanation, "Flint explains jump and dash (D-211)")
	assert_true(InputMap.has_action(PlayerSideMotion.DASH_ACTION), "the side dash action exists at runtime")


func test_chest_only_when_the_way_brings_one() -> void:
	var layout := SidePlans.build(&"crypt_gallery")
	assert_true(layout.chest.x >= 0, "the plan has a niche")
	layout.chest_enabled = false
	var segment := SideSegment.new()
	segment.setup(layout, 1, null, 7)
	add_child_autofree(segment)
	assert_null(segment.get_chest(), "no chest outside the ladder way")


func test_golden_coin_pays_gold_not_crystals() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()
	var segment := _segment(&"crypt_steps")
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.set_physics_process(false)
	segment.add_player(player)
	var crystals := RunManager.get_run_crystals()
	player.global_position = segment.to_global(SideLayout.cell_center(segment.layout.golden_coin))
	segment._physics_process(STEP)
	assert_true(segment.golden_coin_taken)
	assert_eq(RunManager.get_run_gold(), SideRules.golden_coin_gold(1, MetaProgression.get_gold_multiplier()))
	assert_eq(RunManager.get_run_crystals(), crystals, "no crystals (round 2 balance)")
	segment.remove_players()
	RunManager.end_run(RunManager.EndReason.ABORT)


func test_dust_spawns_and_frees_itself() -> void:
	var holder := Node2D.new()
	add_child_autofree(holder)
	for kind in [SideDust.Kind.PUFF, SideDust.Kind.CLOUD, SideDust.Kind.RING, SideDust.Kind.SLIDE]:
		var dust := SideDust.spawn(holder, Vector2(10, 10), kind, 0.8)
		assert_not_null(dust, "dust %d" % kind)
	await wait_seconds(0.5)
	var left := 0
	for child in holder.get_children():
		if child is SideDust:
			left += 1
	assert_eq(left, 0, "placeholder dust is gone after its lifetime")



# --- Round 3 ---

const POOL_PLAN := [
	"##############",
	"#............#",
	"#............#",
	"#S..........D#",
	"####www#######",
	"##############",
]


func test_pool_slows_running_and_lets_go() -> void:
	var layout := SideLayout.parse(PackedStringArray(POOL_PLAN), &"pool")
	layout.biome_id = &"slime_grotto"
	var segment := SideSegment.new()
	segment.setup(layout, 1, null, 3)
	add_child_autofree(segment)
	segment.global_position = Vector2(0, 7000)
	var player := PLAYER_SCENE.instantiate() as Player
	player.is_local = false
	add_child_autofree(player)
	segment.add_player(player)
	var pool := segment.get_pools()[0]
	var base_speed := player.move_speed
	player.side_motion.place_at(segment.to_global(SideLayout.feet_of(Vector2i(5, 4))))
	await wait_physics_frames(3)
	assert_true(pool.is_slowing(player), "feet in the water")
	assert_almost_eq(player.move_speed, base_speed * SideRules.POOL_SLOW_FACTOR, 0.5, "running slowed")
	player.side_motion.place_at(segment.get_start_feet())
	await wait_physics_frames(3)
	assert_false(pool.is_slowing(player))
	assert_almost_eq(player.move_speed, base_speed, 0.01, "full speed on dry ground")
	player.side_motion.place_at(segment.to_global(SideLayout.feet_of(Vector2i(5, 4))))
	await wait_physics_frames(3)
	segment.remove_players()
	assert_almost_eq(player.move_speed, base_speed, 0.01, "leaving the segment takes the slow away")


func test_spike_run_fires_as_a_wave() -> void:
	var layout := SideLayout.parse(PackedStringArray([
		"##############",
		"#............#",
		"#S...^^^....D#",
		"##############",
	]), &"wave")
	layout.biome_id = &"crypt"
	var segment := SideSegment.new()
	segment.setup(layout, 1, null, 5)
	add_child_autofree(segment)
	var spikes := segment.get_spikes()
	assert_eq(spikes.size(), 3)
	for trap in spikes:
		trap.set_physics_process(false)
	var fired_at := [-1, -1, -1]
	for frame in 300:
		for i in spikes.size():
			spikes[i]._physics_process(STEP)
			if fired_at[i] < 0 and spikes[i].is_active():
				fired_at[i] = frame
	assert_true(fired_at[0] >= 0 and fired_at[1] > fired_at[0] and fired_at[2] > fired_at[1], "left to right: %s" % [fired_at])
	assert_almost_eq((fired_at[1] - fired_at[0]) * STEP, SideRules.SPIKE_WAVE_STEP, 0.05)


func test_remote_spikes_wait_for_the_host() -> void:
	var spikes := SideSpikes.new()
	add_child_autofree(spikes)
	spikes.setup(0.1)
	spikes.remote_controlled = true
	spikes.set_physics_process(false)
	watch_signals(spikes)
	for i in 30:
		spikes._physics_process(STEP)
	assert_eq(spikes.phase, SideSpikes.Phase.IDLE, "no own phase change while the host is in time")
	spikes.apply_remote_phase(SideSpikes.Phase.WARN)
	assert_eq(spikes.phase, SideSpikes.Phase.WARN)
	spikes.apply_remote_phase(SideSpikes.Phase.ACTIVE)
	assert_true(spikes.is_active())
	assert_signal_emit_count(spikes, "phase_changed", 2)
	for i in ceili((SideSpikes.ACTIVE_TIME + SideSpikes.REMOTE_GRACE + 0.1) / STEP):
		spikes._physics_process(STEP)
	assert_eq(spikes.phase, SideSpikes.Phase.IDLE, "a lost message does not keep the spikes out forever")


func test_turrets_only_when_the_layout_sets_them_up() -> void:
	var layout := SidePlans.build(&"crypt_cistern")
	assert_eq(layout.turrets.size(), 2)
	var with := SideSegment.new()
	with.setup(layout, 1, null, 7)
	add_child_autofree(with)
	assert_eq(with.get_turrets().size(), 2, "both mounts set up")
	var plain := SidePlans.build(&"crypt_cistern")
	plain.turrets_enabled = false
	var without := SideSegment.new()
	without.setup(plain, 1, null, 7)
	add_child_autofree(without)
	assert_eq(without.get_turrets().size(), 0, "no turrets in this segment")


func test_dressing_is_the_same_on_every_machine() -> void:
	for plan in [&"crypt_steps", &"grotto_spores", &"shadow_rift", &"ember_quench"]:
		var a := _segment(plan)
		var b := _segment(plan)
		var decor_a := a.get_node("Decor") as SideDecor
		var decor_b := b.get_node("Decor") as SideDecor
		assert_gt(decor_a.prop_count, 0, "%s: props on the floor" % plan)
		assert_eq(decor_a.prop_count, decor_b.prop_count, "%s: the same props" % plan)
		assert_eq(decor_a.hang_count, decor_b.hang_count, "%s: the same hangings" % plan)
		assert_not_null(a.get_node_or_null("Ambience"), "%s: air particles" % plan)
		assert_not_null(a.get_node_or_null("Entrance"), "%s: the doorway behind the start" % plan)
		assert_not_null(a.get_node_or_null("Backdrop/Middle"), "%s: the middle parallax layer" % plan)
		for cell in decor_a.free_floor_cells():
			assert_false(a.layout.spikes.has(cell) or cell == a.layout.start or cell == a.layout.door, "%s: props keep the way readable" % plan)

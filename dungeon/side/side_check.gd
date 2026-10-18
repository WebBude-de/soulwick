extends SceneTree
## Plays every side-segment layout (M5) with the autopilot (SideBot) and checks the rules at runtime:
## the plan rules (SideLayout.check), the door is reached by jumping and climbing within
## SideRules.MAX_SEGMENT_SECONDS, the golden coin is fetched with the double jump on the way, the
## player never falls into a pit, the autopilot walks up to every niche chest (it stands in the
## chest's interaction range, D-144), enemies, spikes and crumbling ledges are only counted. The
## player is invulnerable for the check (it measures the way, not the fight).
## Round 3: every turret mount is set up (the game sets them up in SideRules.TURRET_CHANCE of the
## segments) and its shots are counted, pools count the players they slowed. hits=1 lets the player
## take hits (health stays high): turret slows and spikes act on the run, and the bot must still
## make it without falling into a pit.
## Usage (repo root):
##   godot --headless --fixed-fps 60 --path . -s dungeon/side/side_check.gd -- [plan=<id>] [mirror=0|1] [hits=1]
##   godot --headless --fixed-fps 60 --path . -s dungeon/side/side_check.gd -- dungeon
##     (the hook path in the real dungeon: SideWays.plan puts a gate between room 1 and 2, the
##     player walks in, SideTransit runs the segment with the autopilot, room 2 starts afterwards)
##   godot --path . -s dungeon/side/side_check.gd -- shots=<dir>   (window: screenshots in the real
##   dungeon - room, black fade with the banner, the segment in every biome)
## Classes are loaded dynamically: this script is compiled before the autoloads exist.

const SAVE_PATH := "user://side_check_save.cfg"
const SETTINGS_PATH := "user://side_check_settings.cfg"
const PLAYER_SCENE_PATH := "res://player/player.tscn"
const SHOT_BIOMES := [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]
const SHOT_PLANS := [&"crypt_cistern", &"grotto_spores", &"shadow_rift", &"ember_quench"]

var _failures: Array[String] = []
var _shots_dir := ""
var _dungeon_mode := false
var _take_hits := false
var _chests_reached := 0


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var only_plan := ""
	var only_mirror := -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("plan="):
			only_plan = arg.trim_prefix("plan=")
		elif arg.begins_with("mirror="):
			only_mirror = int(arg.trim_prefix("mirror="))
		elif arg.begins_with("shots="):
			_shots_dir = arg.trim_prefix("shots=")
		elif arg == "dungeon":
			_dungeon_mode = true
		elif arg == "hits=1":
			_take_hits = true
	var save_manager := root.get_node("SaveManager")
	save_manager.save_path = SAVE_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	save_manager.load_game()
	save_manager.settings_path = SETTINGS_PATH
	save_manager.load_settings()
	if not _shots_dir.is_empty():
		await _screenshots()
		quit(0)
		return
	if _dungeon_mode:
		_failures.append("dungeon check did not finish")
		await _dungeon_check()
		_finish()
		return
	var plans_script: GDScript = load("res://dungeon/side/side_plans.gd")
	var total := 0
	var seconds_sum := 0.0
	for plan_id: StringName in plans_script.all_ids():
		if not only_plan.is_empty() and String(plan_id) != only_plan:
			continue
		for mirrored in [false, true]:
			if only_mirror >= 0 and int(mirrored) != only_mirror:
				continue
			var result: Dictionary = await _play(plan_id, mirrored)
			total += 1
			seconds_sum += float(result.get("seconds", 0.0))
	print("side_check: %d layouts, mean %.1f s, %d chests reached" % [total, seconds_sum / maxf(1.0, total), _chests_reached])
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("side_check: PASS")
		quit(0)
	else:
		for failure in _failures:
			print("FAIL ", failure)
		print("side_check: FAIL (%d)" % _failures.size())
		quit(1)


func _play(plan_id: StringName, mirrored: bool) -> Dictionary:
	var plans_script: GDScript = load("res://dungeon/side/side_plans.gd")
	var layout: Variant = plans_script.build(plan_id, mirrored)
	var name := "%s%s" % [plan_id, " (gespiegelt)" if mirrored else ""]
	for error: String in layout.check():
		_failures.append(error + (" (gespiegelt)" if mirrored else ""))
	var world := Node2D.new()
	world.name = "SideCheckWorld"
	root.add_child(world)
	var player: Node = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate()
	world.add_child(player)
	player.health.reset(99999.0)
	if not _take_hits:
		player.hurtbox.set_invulnerable(&"side_check", true)
	var segment: Node2D = (load("res://dungeon/side/side_segment.gd") as GDScript).new()
	segment.setup(layout, 1, null, hash(plan_id))
	world.add_child(segment)
	segment.global_position = segment.WORLD_ORIGIN
	segment.add_player(player)
	segment.make_camera_current()
	var bot: Variant = (load("res://dungeon/side/side_bot.gd") as GDScript).drive(segment, player)
	var chest: Node = segment.get_chest()
	bot.fetch_chest = chest != null
	var interaction_area: Area2D = player.get_node("InteractionArea")
	var chest_reached := false
	var max_frames := int(70.0 * Engine.physics_ticks_per_second)
	var frames := 0
	var slowed_frames := 0
	while not segment.is_finished and frames < max_frames:
		await physics_frame
		frames += 1
		if chest != null and not chest_reached:
			chest_reached = interaction_area.get_overlapping_areas().has(chest.get_interactable())
		for pool: Node in segment.get_pools():
			if pool.is_slowing(player):
				slowed_frames += 1
	var turret_shots := 0
	for turret: Node in segment.get_turrets():
		if is_instance_valid(turret):
			turret_shots += turret.shots
	var seconds := frames / float(Engine.physics_ticks_per_second)
	var falls: int = player.side_motion.pit_falls
	var crumbled := 0
	for crumble: Node in segment.get_crumbles():
		crumbled += crumble.crumble_count
	var line := "%s: %s in %.1f s, %d/%d Münzen, goldene Münze %s, Truhe %s, Gold %d, %d Sprünge, %d Doppelsprünge%s, %d Wandsprünge, %d Bröckel, %d Stürze, %d Türme (%d Schüsse), %d Becken (%.1f s gebremst), %d Stacheln" % [
		name, "Tür erreicht" if segment.is_finished else "Tür NICHT erreicht", seconds,
		segment.coins_taken, segment.coins_total, "ja" if segment.golden_coin_taken else "nein",
		"erreicht" if chest_reached else ("NICHT erreicht" if chest != null else "keine"), segment.gold_earned,
		bot.jumps, player.side_motion.double_jumps, " (Pflicht)" if layout.way_needs_double_jump() else "",
		player.side_motion.wall_jumps, crumbled, falls, segment.get_turrets().size(), turret_shots,
		segment.get_pools().size(), slowed_frames / float(Engine.physics_ticks_per_second), segment.get_spikes().size()]
	print(line)
	if chest_reached:
		_chests_reached += 1
	if not segment.is_finished:
		_failures.append("%s: door not reached (bot at %s)" % [name, segment.to_local(player.get_feet_position())])
	elif seconds > 45.0:
		_failures.append("%s: %.1f s > 45 s" % [name, seconds])
	if falls > 0:
		_failures.append("%s: %d falls into a pit" % [name, falls])
	if segment.get_turrets().size() != layout.turrets.size():
		_failures.append("%s: %d of %d turrets built" % [name, segment.get_turrets().size(), layout.turrets.size()])
	if not segment.golden_coin_taken:
		_failures.append("%s: golden coin not reached with the double jump" % name)
	if layout.chest.x < 0:
		_failures.append("%s: no chest niche" % name)
	elif not chest_reached:
		_failures.append("%s: chest at %s not reached (bot at %s)" % [name, layout.chest, segment.to_local(player.get_feet_position())])
	segment.remove_players()
	world.queue_free()
	await process_frame
	return {"seconds": seconds}


# --- The hook path in the real dungeon ---

func _dungeon_check() -> void:
	TranslationServer.set_locale("de")
	change_scene_to_file("res://scenes/game.tscn")
	await _seconds(1.0)
	var controller: Node = current_scene.get_node("WorldController")
	controller.enter_dungeon()
	await _seconds(1.0)
	var dungeon: Node2D = controller.get_world()
	var player: Node2D = controller.get_player()
	player.health.reset(99999.0)
	player.hurtbox.set_invulnerable(&"side_check", true)
	var ways: GDScript = load("res://dungeon/side/side_ways.gd")
	var room1: Node2D = dungeon.get_room(1)
	var room2: Node2D = dungeon.get_room(2)
	_expect(room1 != null and room2 != null, "rooms 1 and 2 are built")
	_expect(ways.plan(room1, room2, 777, false) == null, "a plain combat room leads into a plain corridor")
	_expect(ways.plan(room1, room2, 777, true, true) == null, "never twice in a row")
	var gate: Node2D = ways.plan(room1, room2, 777, false, true)
	_expect(gate != null, "the ladder way gets a gate")
	if gate == null:
		return
	var run_manager := root.get_node("RunManager")
	var gold_before: int = run_manager.get_run_gold()
	var transits := []
	var transit_script: GDScript = load("res://dungeon/side/side_transit.gd")
	var player_script: GDScript = load(PLAYER_SCENE_PATH.replace(".tscn", ".gd"))
	gate.passed.connect(func(passed_gate: Node, _who: Node) -> void:
		var group := Array([player], TYPE_OBJECT, &"CharacterBody2D", player_script)
		transits.append(transit_script.start(dungeon, group, passed_gate.layout, passed_gate.next_room.room_index,
				dungeon.context, passed_gate.rng_seed, passed_gate.place_players)))
	player.global_position = gate.global_position
	var waited := 0.0
	while (transits.is_empty() or transits[0].segment == null) and waited < 5.0:
		await _seconds(0.1)
		waited += 0.1
	_expect(not transits.is_empty(), "walking into the gate starts the transit")
	if transits.is_empty() or transits[0].segment == null:
		return
	var transit: Node = transits[0]
	_expect(player.is_side_view(), "the player is in side view")
	var _bot: Variant = (load("res://dungeon/side/side_bot.gd") as GDScript).drive(transit.segment, player)
	waited = 0.0
	while is_instance_valid(transit) and waited < 70.0:
		await _seconds(0.25)
		waited += 0.25
	_bot = null
	await _seconds(0.5)
	_expect(not is_instance_valid(transit), "the transit ended (%.1f s)" % waited)
	_expect(not player.is_side_view(), "top-down again")
	_expect(dungeon.get_active_room_index() == 2, "room 2 started after the segment (active %d)" % dungeon.get_active_room_index())
	_expect(run_manager.get_run_gold() >= gold_before, "coins went to the run gold (%d -> %d)" % [gold_before, run_manager.get_run_gold()])
	_expect(current_scene.get_viewport().get_camera_2d() == player.get_node("Camera2D"), "the room camera is current")
	_failures.erase("dungeon check did not finish")


func _expect(condition: bool, text: String) -> void:
	print("%s %s" % ["PASS" if condition else "FAIL", text])
	if not condition:
		_failures.append(text)


# --- Screenshots in the real dungeon (window needed) ---

func _screenshots() -> void:
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	TranslationServer.set_locale("de")
	root.get_node("SaveManager").set_option(&"language", "de")
	change_scene_to_file("res://scenes/game.tscn")
	await _seconds(1.0)
	TranslationServer.set_locale("de")
	var controller: Node = current_scene.get_node("WorldController")
	controller.enter_dungeon()
	await _seconds(1.5)
	var dungeon: Node2D = controller.get_world()
	var player: Node2D = controller.get_player()
	player.health.reset(99999.0)
	player.hurtbox.set_invulnerable(&"side_check", true)
	var plans_script: GDScript = load("res://dungeon/side/side_plans.gd")
	var transit_script: GDScript = load("res://dungeon/side/side_transit.gd")
	var start: Vector2 = player.global_position
	for i in SHOT_BIOMES.size():
		var biome: StringName = SHOT_BIOMES[i]
		var layout: Variant = plans_script.build(SHOT_PLANS[i], i % 2 == 1, biome)
		if i == 0:
			_shot("00_raum_vorher")
		var back := func(members: Array) -> void:
			for member: Node2D in members:
				member.global_position = start
		var group := Array([player], TYPE_OBJECT, &"CharacterBody2D", load(PLAYER_SCENE_PATH.replace(".tscn", ".gd")))
		var transit: Node = transit_script.start(dungeon, group, layout, 1 + i * 15, dungeon.context, 1234 + i, back)
		await _seconds(0.25)
		if i == 0:
			_shot("01_blende")
		await _seconds(0.6)
		_shot("%02d_banner_%s" % [i * 10 + 2, biome])
		await _seconds(2.4)
		_shot("%02d_segment_start_%s" % [i * 10 + 3, biome])
		var segment: Node2D = transit.segment
		if i == 0:
			await _moves_sequence(segment, player)
		var _bot: Variant = (load("res://dungeon/side/side_bot.gd") as GDScript).drive(segment, player)
		var shots_taken := 0
		var elapsed := 0.0
		var crumble_shot := false
		while is_instance_valid(transit) and transit.segment != null and not transit.segment.is_finished and elapsed < 60.0:
			await _seconds(0.1)
			elapsed += 0.1
			if shots_taken < 2 and elapsed >= 5.0 + shots_taken * 6.0:
				_shot("%02d_segment_%s_%d" % [i * 10 + 4 + shots_taken, biome, shots_taken + 1])
				shots_taken += 1
			if not crumble_shot:
				for crumble: Node in segment.get_crumbles():
					if crumble.state == 1:
						_shot("%02d_broeckelt_%s" % [i * 10 + 6, biome])
						crumble_shot = true
						break
		_bot = null
		await _seconds(0.25)
		if i == 0:
			_shot("06_blende_zurueck")
		while is_instance_valid(transit):
			await _seconds(0.2)
		await _seconds(0.5)
		if i == 0:
			_shot("07_raum_danach")


## Short picture series of the moves (window): take-off, double jump with salto and ring, landing
## with squash and dust, a hard landing with the camera kick, a wall slide. Scripted input through
## input_source, like the autopilot.
func _moves_sequence(segment: Node2D, player: Node2D) -> void:
	var motion_script: GDScript = load("res://player/player_side_motion.gd")
	var state := {"axis": Vector2.ZERO, "just": false, "held": false}
	player.side_motion.input_source = func() -> Variant:
		var input: Variant = motion_script.SideInput.new()
		input.axis = state["axis"]
		input.jump_just_pressed = state["just"]
		input.jump_pressed = state["held"] or state["just"]
		state["just"] = false
		return input
	await _seconds(0.3)
	state["just"] = true
	state["held"] = true
	for k in 3:
		await _frames(3)
		_shot("seq_a_sprung_%d" % k)
	while player.velocity.y < -120.0:
		await _frames(1)
	state["held"] = false
	await _frames(1)
	state["just"] = true
	state["held"] = true
	for k in 6:
		await _frames(3)
		_shot("seq_b_doppelsprung_%d" % k)
	state["held"] = false
	while not player.side_motion.is_on_floor():
		await _frames(1)
	for k in 4:
		_shot("seq_c_landung_%d" % k)
		await _frames(3)
	# A hard landing from high above the start ledge.
	var layout: Variant = segment.layout
	player.side_motion.place_at(segment.to_global(layout.feet_of(layout.start + Vector2i(2 * int(layout.run_direction()), -5))))
	await _frames(4)
	while player.velocity.y < 900.0:
		await _frames(1)
	while not player.side_motion.is_on_floor():
		await _frames(1)
	for k in 4:
		_shot("seq_d_harte_landung_%d" % k)
		await _frames(2)
	# Wall slide: next to the outer wall, jump and press into it.
	player.side_motion.place_at(segment.to_global(layout.feet_of(layout.start)))
	await _frames(20)
	state["axis"] = Vector2(-layout.run_direction(), 0)
	state["just"] = true
	state["held"] = true
	var slid := false
	for k in 180:
		await _frames(1)
		if player.side_motion.is_wall_sliding:
			slid = true
			await _frames(6)
			_shot("seq_e_wandrutschen")
			break
	print("wall slide seen: ", slid, " wall_side ", player.side_motion.wall_side)
	state["axis"] = Vector2.ZERO
	state["held"] = false
	await _seconds(0.6)
	player.side_motion.place_at(segment.to_global(layout.feet_of(layout.start)))
	await _frames(5)


func _frames(count: int) -> void:
	for k in count:
		await process_frame


func _shot(shot_name: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(_shots_dir.path_join(shot_name + ".png"))
	print("saved ", shot_name)


func _seconds(duration: float) -> void:
	await create_timer(duration, true, false, true).timeout

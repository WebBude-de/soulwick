extends SceneTree
## Plays every side-segment layout (M5) with the autopilot (SideBot) and checks the rules at runtime:
## the plan rules (SideLayout.check), the door is reached by jumping and climbing within
## SideRules.MAX_SEGMENT_SECONDS, the player never falls into a pit, enemies and spikes are only
## counted. The player is invulnerable for the check (it measures the way, not the fight).
## Usage (repo root):
##   godot --headless --fixed-fps 60 --path . -s dungeon/side/side_check.gd -- [plan=<id>] [mirror=0|1]
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
const SHOT_PLANS := [&"crypt_steps", &"grotto_pools", &"shadow_rift", &"ember_anvils"]

var _failures: Array[String] = []
var _shots_dir := ""
var _dungeon_mode := false


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
	print("side_check: %d layouts, mean %.1f s" % [total, seconds_sum / maxf(1.0, total)])
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
	player.hurtbox.set_invulnerable(&"side_check", true)
	var segment: Node2D = (load("res://dungeon/side/side_segment.gd") as GDScript).new()
	segment.setup(layout, 1, null, hash(plan_id))
	world.add_child(segment)
	segment.global_position = segment.WORLD_ORIGIN
	segment.add_player(player)
	segment.make_camera_current()
	var bot: Variant = (load("res://dungeon/side/side_bot.gd") as GDScript).drive(segment, player)
	var max_frames := int(70.0 * Engine.physics_ticks_per_second)
	var frames := 0
	while not segment.is_finished and frames < max_frames:
		await physics_frame
		frames += 1
	var seconds := frames / float(Engine.physics_ticks_per_second)
	var falls: int = player.side_motion.pit_falls
	var line := "%s: %s in %.1f s, %d/%d Münzen, goldene Münze %s, %d Sprünge, %d Stürze" % [
		name, "Tür erreicht" if segment.is_finished else "Tür NICHT erreicht", seconds,
		segment.coins_taken, segment.coins_total, "ja" if not segment.has_golden_coin() else "nein",
		bot.jumps, falls]
	print(line)
	if not segment.is_finished:
		_failures.append("%s: door not reached (bot at %s)" % [name, segment.to_local(player.get_feet_position())])
	elif seconds > 45.0:
		_failures.append("%s: %.1f s > 45 s" % [name, seconds])
	if falls > 0:
		_failures.append("%s: %d falls into a pit" % [name, falls])
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
		var _bot: Variant = (load("res://dungeon/side/side_bot.gd") as GDScript).drive(segment, player)
		var shots_taken := 0
		var elapsed := 0.0
		while is_instance_valid(transit) and transit.segment != null and not transit.segment.is_finished and elapsed < 60.0:
			await _seconds(0.5)
			elapsed += 0.5
			if shots_taken < 2 and elapsed >= 5.0 + shots_taken * 6.0:
				_shot("%02d_segment_%s_%d" % [i * 10 + 4 + shots_taken, biome, shots_taken + 1])
				shots_taken += 1
		_bot = null
		await _seconds(0.25)
		if i == 0:
			_shot("06_blende_zurueck")
		while is_instance_valid(transit):
			await _seconds(0.2)
		await _seconds(0.5)
		if i == 0:
			_shot("07_raum_danach")


func _shot(shot_name: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(_shots_dir.path_join(shot_name + ".png"))
	print("saved ", shot_name)


func _seconds(duration: float) -> void:
	await create_timer(duration, true, false, true).timeout

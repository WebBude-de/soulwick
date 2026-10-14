extends SceneTree
## Automated play-through (headless): village -> dungeon -> N rooms -> death -> village.
## Checks M2/M4/M5 acceptance rules at runtime and prints PASS/FAIL lines.
## Usage: godot --headless --path . -s tools/smoke_test.gd -- [rooms]
## Classes are accessed dynamically: this script is compiled before autoloads exist.

const SAVE_PATH := "user://smoke_test_save.cfg"
const MAX_LIVE_ROOMS := 3

var _failures: Array[String] = []
var _max_live_rooms := 0
var _dungeon: Node = null
var _modal_log: Array[String] = []
## Room kinds (D-086): rolled per range and actually used, plus the previous combat room's kind.
var _rolled_early := {}
var _rolled_deep := {}
var _used_kinds := {}
var _previous_kind := -1


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var rooms_to_play := 12
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		rooms_to_play = int(args[0])
	var save_manager := root.get_node("SaveManager")
	save_manager.save_path = SAVE_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	save_manager.load_game()
	process_frame.connect(_watch)

	change_scene_to_file("res://scenes/game.tscn")
	await _frames(20)
	var controller := current_scene.get_node("WorldController")
	_check(controller.get_world().get_script().get_global_name() == &"Village", "starts in the village")
	var village_player: Node = controller.get_player()
	_check(village_player != null, "player spawned in village")

	controller.enter_dungeon()
	await _frames(20)
	_dungeon = controller.get_world()
	var run_manager := root.get_node("RunManager")
	_check(_dungeon.get_script().get_global_name() == &"DungeonManager", "dungeon loaded")
	_check(run_manager.is_run_active(), "run started")
	var player: Node = controller.get_player()
	_check(player != village_player, "new player instance for the dungeon (D-041)")
	# Traps and explosions are real now; the test player must survive the walk-through.
	player.health.reset(99999.0)

	for index in range(1, rooms_to_play + 1):
		var ok: bool = await _play_room(index, player, run_manager)
		if not ok:
			break
		_check(controller.get_player() == player, "room %d keeps the same player instance" % index)

	_check(_max_live_rooms <= MAX_LIVE_ROOMS, "never more than 3 live rooms (max seen: %d)" % _max_live_rooms)
	var gold_before: int = run_manager.get_run_gold()
	var permanent_before: int = save_manager.get_permanent_gold()
	print("run gold before death: ", gold_before)

	# Death -> run end -> village.
	player.health.take_damage(999999.0)
	await _frames(150)
	_check(not run_manager.is_run_active(), "run ended after death")
	var summary: Dictionary = run_manager.get_last_summary()
	var expected := permanent_before + ceili(summary.get("remaining_gold", -1) * 0.5)
	_check(summary.get("payout", -1) == ceili(summary.get("remaining_gold", -1) * 0.5), "summary payout is 50 %")
	_check(save_manager.get_permanent_gold() == expected, "50 %% payout credited once (%d == %d)" % [save_manager.get_permanent_gold(), expected])
	await _press_modal_button("Zurück ins Dorf")
	await _frames(20)
	_check(controller.get_world().get_script().get_global_name() == &"Village", "back in the village after the run")
	_check(not root.get_node("GameManager").is_game_paused(), "no stale pause reason after the run")

	var reloaded := ConfigFile.new()
	_check(reloaded.load(SAVE_PATH) == OK and reloaded.get_value("progress", "permanent_gold", -1) == expected, "permanent gold persisted to disk")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	print("modals seen: ", ", ".join(_modal_log))
	_print_kind_distribution()
	if _failures.is_empty():
		print("SMOKE TEST PASSED")
		quit(0)
	else:
		print("SMOKE TEST FAILED (%d):" % _failures.size())
		for failure in _failures:
			print("  - ", failure)
		quit(1)


func _play_room(index: int, player: Node, run_manager: Node) -> bool:
	var room: Node = _dungeon.get_room(index)
	if room == null:
		_fail("room %d was not prepared" % index)
		return false
	var type_name: String = ["COMBAT", "COMBAT_UPGRADE", "SPECIAL", "MINIBOSS", "BOSS"][room.room_type]
	var expected_type := _expected_type(index)
	_check(type_name == expected_type, "room %d type %s (expected %s)" % [index, type_name, expected_type])
	if index > 1:
		# Room 1 is entered by spawning inside it.
		_check(not room.is_encounter_started(), "room %d: preparing does not start the encounter" % index)

	# Walk in: teleport into the middle of the floor.
	player.global_position = room.to_global(room.get_node("Tiles").get_floor_rect().get_center())
	await _frames(6)
	_check(run_manager.get_current_room() == index, "RunManager room %d" % index)
	_check(_dungeon.get_room(index - 2) == null, "room %d unloaded when entering %d" % [index - 2, index])
	_check(_dungeon.get_room(index + 1) != null, "room %d prepared when entering %d" % [index + 1, index])

	if type_name == "SPECIAL":
		print("room %d: special %s, portal=%s" % [index, room.special_type, room.has_portal])
		await _use_special(room, player)
	else:
		_check(room.is_encounter_started(), "room %d encounter started on entry" % index)
		var enemies: Array = room.enemy_container.get_children().filter(func(n): return n.get_script() != null and n.get_script().get_global_name() == &"Enemy")
		if type_name.begins_with("COMBAT"):
			_check_room_kind(index, room)
			var limits: Vector2i = load("res://dungeon/room_sequence.gd").get_enemy_count_range(index)
			_check(enemies.size() >= limits.x and enemies.size() <= limits.y, "room %d spawned %d enemies (%d-%d)" % [index, enemies.size(), limits.x, limits.y])
		elif type_name == "BOSS":
			_check(enemies.size() == 1, "room %d boss spawned alone" % index)
			# The boss intro (D-098) keeps the boss invulnerable: skip it like a player would.
			await _frames(30)
			_check(_skip_boss_intros() > 0, "room %d boss intro started and was skipped" % index)
		else:
			_check(enemies.size() >= 2, "room %d champion comes with an escort (%d)" % [index, enemies.size()])
		var kind_label: String = _dungeon.get_room_kind_label(room)
		print("room %d: %s%s, %d enemies" % [index, type_name, (" [%s]" % kind_label) if not kind_label.is_empty() else "", enemies.size()])
		for enemy in enemies:
			_kill(enemy, player)
		# Splitting slimes, summons and later waves add enemies: keep clearing until empty.
		for sweep in 12:
			await _frames(25)
			var remaining: Array = room.enemy_container.get_children().filter(func(n): return n.get_script() != null and n.get_script().get_global_name() == &"Enemy" and not n.is_dead())
			if remaining.is_empty():
				break
			for enemy in remaining:
				_kill(enemy, player)
		# Banner first, dialogs only after the reward delay (D-070).
		await _frames(20)
		_check(_find_modal(root) == null, "room %d: no dialog right after the last kill" % index)
		await _frames(100)
		# Exactly one encounter: entering again must not respawn.
		room.start_encounter()
		await _frames(2)
		var alive: Array = room.enemy_container.get_children().filter(func(n): return n.get_script() != null and n.get_script().get_global_name() == &"Enemy" and not n.is_dead())
		_check(alive.is_empty(), "room %d: no respawn after clear" % index)

	if not type_name.begins_with("COMBAT"):
		_previous_kind = -1
	# Room 3 of each cycle: upgrade choice after the fight.
	await _resolve_modals()
	await _frames(10)
	var exit_door: Node = room._exit_door
	_check(exit_door.is_open, "room %d exit opened after completion" % index)
	return exit_door.is_open


## Room kind rules (D-086): rooms 1-5 without abyss, no abyss twice in a row, fallback to arena
## only without a template, single-player sizes, spawn marker count per size.
func _check_room_kind(index: int, room: Node) -> void:
	var sequence: GDScript = load("res://dungeon/room_sequence.gd")
	var kinds: Dictionary = sequence.get_script_constant_map()["RoomKind"]
	var abyss: int = kinds["ABYSS"]
	var solo_sizes: Array = sequence.get_script_constant_map()["SOLO_ROOM_SIZES"]
	var rolled: int = room.rolled_kind
	var used: int = room.room_kind
	_check(rolled >= 0, "room %d has a rolled room kind" % index)
	if index < sequence.get_script_constant_map()["ABYSS_FROM_ROOM"]:
		_check(rolled != abyss, "room %d: no abyss before room 6" % index)
	_check(not (used == abyss and _previous_kind == abyss), "room %d: no abyss room right after an abyss room" % index)
	var catalog: Object = _dungeon.get_combat_catalog()
	var expected: int = rolled if catalog.has_kind(rolled, sequence.SOLO_ROOM_SIZES) else kinds["ARENA"]
	_check(used == expected, "room %d: kind %d used for rolled %d (expected %d)" % [index, used, rolled, expected])
	_check(solo_sizes.has(room.room_size_class), "room %d: single-player size class" % index)
	var markers: int = room.get_spawn_markers().size()
	var min_markers: int = sequence.get_min_spawn_points(room.room_size_class)
	_check(markers >= min_markers and markers <= sequence.get_script_constant_map()["MAX_SPAWN_POINTS"], "room %d: %d spawn markers (min %d)" % [index, markers, min_markers])
	var bucket: Dictionary = _rolled_early if index < sequence.get_script_constant_map()["ABYSS_FROM_ROOM"] else _rolled_deep
	var rolled_name: String = sequence.get_kind_name(rolled)
	var used_name: String = sequence.get_kind_name(used)
	bucket[rolled_name] = bucket.get(rolled_name, 0) + 1
	_used_kinds[used_name] = _used_kinds.get(used_name, 0) + 1
	_previous_kind = used


func _print_kind_distribution() -> void:
	var sequence: GDScript = load("res://dungeon/room_sequence.gd")
	var constants := sequence.get_script_constant_map()
	print("room kinds rolled, rooms 1-5: %s (weights %s)" % [_format_counts(_rolled_early), constants["ROOM_KIND_WEIGHTS_EARLY"]])
	print("room kinds rolled, rooms 6+: %s (weights %s)" % [_format_counts(_rolled_deep), constants["ROOM_KIND_WEIGHTS"]])
	print("room kinds used (after template fallback): %s" % _format_counts(_used_kinds))
	# One run is a small sample: the same draw over many simulated 47-room runs for comparison.
	var rng := RandomNumberGenerator.new()
	rng.seed = 47
	var early := {}
	var deep := {}
	for run in 1000:
		var previous := -1
		for index in range(1, 48):
			if not sequence.is_normal_combat(sequence.get_room_type(index)):
				previous = -1
				continue
			var kind: int = sequence.roll_room_kind(index, previous, rng)
			var bucket: Dictionary = early if index < constants["ABYSS_FROM_ROOM"] else deep
			var kind_name: String = sequence.get_kind_name(kind)
			bucket[kind_name] = bucket.get(kind_name, 0) + 1
			previous = kind
	print("room kinds drawn over 1000 simulated runs, rooms 1-5: %s" % _format_counts(early))
	print("room kinds drawn over 1000 simulated runs, rooms 6+: %s" % _format_counts(deep))


func _format_counts(counts: Dictionary) -> String:
	var total := 0
	for key in counts:
		total += counts[key]
	var parts: Array[String] = []
	for key in counts:
		parts.append("%s %d (%.0f %%)" % [key, counts[key], 100.0 * counts[key] / maxi(total, 1)])
	return ", ".join(parts) if not parts.is_empty() else "none"


func _use_special(room: Node, player: Node) -> void:
	await _frames(4)
	for content in room.get_children():
		for child in content.get_children():
			if child.get_script() != null and child.get_script().get_global_name() == &"Interactable" and child.enabled:
				if child.prompt.begins_with("Dungeon verlassen"):
					continue
				child.interact(player)
				await _frames(4)
				await _resolve_modals()
				return


func _kill(enemy: Node, player: Node) -> void:
	var damage: RefCounted = load("res://components/combat/damage_data.gd").new()
	damage.amount = 9999.0
	damage.source = player
	damage.hit_id = load("res://components/combat/damage_data.gd").next_hit_id()
	damage.tags.assign([&"melee"])
	enemy.hurtbox.receive_hit(damage)


## Skips every running boss intro (after its grace time). Returns how many were skipped.
func _skip_boss_intros() -> int:
	var skipped := 0
	for node in root.find_children("*", "Node", true, false):
		if node.get_script() != null and node.get_script().get_global_name() == &"BossIntro" and node.skip():
			skipped += 1
	return skipped


## Answers every open dialog: picks the first upgrade, closes shops, declines confirmations.
func _resolve_modals() -> void:
	for attempt in 40:
		await _frames(3)
		var modal := _find_modal(root)
		if modal == null:
			return
		var buttons := _buttons(modal)
		var labels: Array[String] = []
		for button in buttons:
			labels.append(button.text)
		_modal_log.append("[" + "|".join(labels) + "]")
		var preferred := ["Wählen", "Schließen", "Weiterspielen", "Abbrechen", "Zurück ins Dorf"]
		var pressed := false
		for wanted in preferred:
			for button in buttons:
				if button.text == wanted and not button.disabled:
					button.pressed.emit()
					pressed = true
					break
			if pressed:
				break
		if not pressed and not buttons.is_empty():
			buttons[0].pressed.emit()


func _press_modal_button(text: String) -> void:
	for attempt in 40:
		await _frames(3)
		var modal := _find_modal(root)
		if modal == null:
			continue
		for button in _buttons(modal):
			if button.text == text:
				button.pressed.emit()
				return
	_fail("dialog with button '%s' not found" % text)


func _find_modal(node: Node) -> Node:
	for child in node.get_children():
		if child.get_script() != null and child.get_script().get_global_name() == &"Modal" and not child.is_queued_for_deletion():
			return child
		var found := _find_modal(child)
		if found != null:
			return found
	return null


func _buttons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	for child in node.get_children():
		if child is Button:
			result.append(child)
		result.append_array(_buttons(child))
	return result


func _expected_type(index: int) -> String:
	match (index - 1) % 5 + 1:
		3:
			return "COMBAT_UPGRADE"
		4:
			return "SPECIAL"
		5:
			return "BOSS" if index % 15 == 0 else "MINIBOSS"
	return "COMBAT"


func _watch() -> void:
	if _dungeon != null and is_instance_valid(_dungeon):
		_max_live_rooms = maxi(_max_live_rooms, _dungeon.get_live_room_count())


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS ", message)
	else:
		_fail(message)


func _fail(message: String) -> void:
	print("FAIL ", message)
	_failures.append(message)

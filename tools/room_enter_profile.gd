extends SceneTree
## Frame times around room entries (feedback 16.10.2026: "the screen hangs briefly when entering a
## room"). Plays a run like the smoke test, but walks the player through every gate and corridor
## into the next room (veil, trigger, entry, preparation of the room after) and measures the wall
## time of every frame with Time.get_ticks_usec(). Prints per transition the longest frame and where
## it lies relative to the entry (frame 0 = DungeonManager.room_activated), and a summary at the end.
## Headless the renderer does nothing, so this measures the CPU side (scripts, scene building,
## physics, navigation); run it in a window (SOULWICK_QUIET=1) to include drawing and shader work.
## Also measures the frame that loads the dungeon (village -> dungeon) and the worst frame of the
## first AFTER_LOAD_FRAMES frames after it (room 1 starts; the idle warm-up waits for a calm room).
## Usage: godot --headless --audio-driver Dummy --fixed-fps 60 --path . -s tools/room_enter_profile.gd -- [rooms] [seed=<n>] [frames=1] [preload=1]
## frames=1 prints every frame over the budget of each transition. preload=1 calls the village hook
## DungeonManager.preload_in_background() first and waits (up to PRELOAD_WAIT_MSEC) until it is done,
## like a player who spends a few seconds in the village.
## Classes are accessed dynamically: this script is compiled before autoloads exist.

const SAVE_PATH := "user://room_enter_profile_save.cfg"
const SETTINGS_PATH := "user://room_enter_profile_settings.cfg"
## One frame at 60 fps.
const BUDGET_USEC := 16667
## Walking speed through the corridor (world px per physics frame, about the player's speed).
const WALK_STEP := 5.0
## Frames measured after the entry (the next room is prepared over the next few frames).
const AFTER_ENTRY_FRAMES := 45
## Frames watched after the dungeon loaded.
const AFTER_LOAD_FRAMES := 120
const PRELOAD_WAIT_MSEC := 10000
const CATALOG_PATH := "res://dungeon/rooms/combat/combat_catalog.tres"
const TILE := 64.0

var _dungeon: Node = null
var _seed := 0
var _print_frames := false
## Wall time of every process frame since the walk began (usec), and the frame of the entry.
var _frame_times: Array[int] = []
var _last_tick := 0
var _recording := false
var _entry_frame := -1
## Per transition: [label, worst usec, offset of the worst frame, frames over budget, sum usec, frame count].
var _results: Array = []


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var rooms_to_play := 16
	var preload_first := false
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args[0].is_valid_int():
		rooms_to_play = int(args[0])
	for arg in args:
		if arg.begins_with("seed="):
			_seed = int(arg.trim_prefix("seed="))
		elif arg == "frames=1":
			_print_frames = true
		elif arg == "preload=1":
			preload_first = true
	if _seed != 0:
		node_added.connect(_on_node_added)
	TranslationServer.set_locale("de")
	var save_manager := root.get_node("SaveManager")
	save_manager.save_path = SAVE_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	save_manager.load_game()
	save_manager.settings_path = SETTINGS_PATH
	save_manager.load_settings()
	save_manager.set_option(&"language", "de")
	process_frame.connect(_tick)

	change_scene_to_file("res://scenes/game.tscn")
	await _frames(20)
	var controller := current_scene.get_node("WorldController")
	if preload_first:
		var wait_start := Time.get_ticks_msec()
		load("res://dungeon/dungeon_manager.gd").call(&"preload_in_background")
		while ResourceLoader.load_threaded_get_status(CATALOG_PATH) == ResourceLoader.THREAD_LOAD_IN_PROGRESS \
				and Time.get_ticks_msec() - wait_start < PRELOAD_WAIT_MSEC:
			await process_frame
		print("village: room catalogs loaded in the background in %d ms" % (Time.get_ticks_msec() - wait_start))
	var load_start := Time.get_ticks_usec()
	controller.enter_dungeon()
	await process_frame
	print("dungeon load frame: %.1f ms" % ((Time.get_ticks_usec() - load_start) / 1000.0))
	_frame_times.clear()
	_last_tick = Time.get_ticks_usec()
	_recording = true
	await _frames(AFTER_LOAD_FRAMES)
	_recording = false
	var after_load := 0
	for usec in _frame_times:
		after_load = maxi(after_load, usec)
	print("after the load: worst of the next %d frames %.1f ms" % [_frame_times.size(), after_load / 1000.0])
	_dungeon = controller.get_world()
	_dungeon.room_activated.connect(_on_room_activated)
	var player: Node = controller.get_player()
	player.health.reset(99999.0)

	# Room 1 is entered by spawning inside it.
	var first: Node = _dungeon.get_room(1)
	await _clear_room(first, player)
	var room: Node = first
	for _index in range(2, rooms_to_play + 1):
		var next: Node = await _walk_to_next(room, player)
		if next == null:
			print("FAIL no room after %s" % room.name)
			break
		room = next
		if room.is_campfire():
			# The campfire is a slot of its own (D-103); walk on through it.
			var after: Node = await _walk_to_next(room, player)
			if after == null:
				break
			room = after
		await _clear_room(room, player)

	_print_summary()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	quit(0)


## Walks the player from the exit of room through the gate and the corridor into the next slot
## and records every frame from the first step until AFTER_ENTRY_FRAMES after the entry.
func _walk_to_next(room: Node, player: Node) -> Node:
	var next: Node = _dungeon.get_room_at_slot(room.slot_index + 1)
	if next == null:
		return null
	var tiles: Node = room.get_node("Tiles")
	var exit: Vector2i = room.get_chosen_exit()
	var start: Vector2 = _at(room, _center(tiles.inside_tile_of(exit.x, exit.y, tiles.room_size)))
	var gate: Vector2 = _at(room, _center(room.get_exit_tile()))
	var next_tiles: Node = next.get_node("Tiles")
	var inside_tile: Vector2i = next_tiles.get_entrance_inside_tile()
	var inside: Vector2 = _at(next, _center(inside_tile))
	var inward: Vector2 = (inside - _at(next, _center(next.get_entrance_tile()))).normalized()
	var target: Vector2 = inside + inward * TILE * 2.0
	player.global_position = start
	await _frames(10)
	_frame_times.clear()
	_entry_frame = -1
	_recording = true
	_last_tick = Time.get_ticks_usec()
	# Steps from a fixed point, not from where the body ended up: a shut door must not hold the walk.
	var from: Vector2 = start
	for point: Vector2 in [gate, inside, target]:
		while from.distance_to(point) > WALK_STEP:
			from = from.move_toward(point, WALK_STEP)
			player.global_position = from
			await physics_frame
		from = point
		player.global_position = point
	var waited := 0
	while (_entry_frame < 0 or _frame_times.size() - _entry_frame < AFTER_ENTRY_FRAMES) and waited < 240:
		await process_frame
		waited += 1
	_recording = false
	if _entry_frame < 0:
		print("  no entry: player at %s, start %s gate %s inside %s (tile %s side %d) target %s, %s at %s floor %s" % [player.global_position, start, gate, inside, inside_tile, next_tiles.entrance_side, target, next.name, next.global_position, Rect2(next.to_global(next.tiles.get_floor_rect().position), next.tiles.get_floor_rect().size)])
	_report("%s -> %s" % [room.name, next.name], next)
	return next


## Starts and clears the fight of room like the smoke test (intro skipped, enemies killed, dialogs
## answered, a branch decided for its first way) until its exit is open.
func _clear_room(room: Node, player: Node) -> void:
	await _frames(4)
	if room.is_campfire():
		return
	if _print_frames:
		print("  clearing %s" % room.name)
	var intro: Object = load("res://dungeon/modes/room_intro.gd").get_intro(room)
	if intro != null:
		intro.skip()
	await _frames(30)
	_skip_boss_intros()
	var variant: Node = room.get_node_or_null("CombatVariant")
	if variant != null:
		variant.step(61.0)
	for sweep in 30:
		var remaining: Array = room.enemy_container.get_children().filter(func(n): return _is_enemy(n) and not n.is_dead())
		if remaining.is_empty() and room._waves_spawned >= room._waves_total and room.state != 1:
			break
		for enemy in remaining:
			_kill(enemy, player)
		await _frames(25)
		_skip_boss_intros()
		await _resolve_modals()
	await _frames(100)
	await _resolve_modals()
	if not room._exit_door.is_open and not room.is_branch_room():
		print("  %s: exit still shut after the fight (state %d)" % [room.name, room.state])
	if room.is_branch_room() and room.get_chosen_branch() < 0:
		var tiles: Node = room.get_node("Tiles")
		var exit: Vector2i = tiles.get_exit_doors()[0]
		player.global_position = _at(room, _center(tiles.inside_tile_of(exit.x, exit.y, tiles.room_size)))
		await _frames(10)
		await _frames(int(float(_dungeon.get_script().get_script_constant_map()["BRANCH_FADE_TIME"]) * 60.0) + 10)
	await _frames(10)


func _on_room_activated(_room: Node) -> void:
	if _recording and _entry_frame < 0:
		# room_activated comes inside the frame being measured: that frame gets index size().
		_entry_frame = _frame_times.size()


func _tick() -> void:
	var now := Time.get_ticks_usec()
	if _recording:
		_frame_times.append(now - _last_tick)
	_last_tick = now


func _report(label: String, next: Node) -> void:
	var worst := 0
	var worst_at := 0
	var over := 0
	var total := 0
	var lines: Array[String] = []
	for i in _frame_times.size():
		var usec := _frame_times[i]
		total += usec
		var offset := i - _entry_frame
		if usec > worst:
			worst = usec
			worst_at = offset
		if usec > BUDGET_USEC:
			over += 1
			lines.append("    frame %+d: %.1f ms" % [offset, usec / 1000.0])
	var kind: String = ["COMBAT", "COMBAT_UPGRADE", "SPECIAL", "MINIBOSS", "BOSS", "CAMPFIRE"][next.room_type]
	_results.append([label, worst, worst_at, over, total, _frame_times.size()])
	print("%-22s %-14s worst %6.1f ms at frame %+d, %d frames > 16.7 ms, mean %.2f ms" % [label, kind, worst / 1000.0, worst_at, over, total / 1000.0 / maxi(1, _frame_times.size())])
	if _print_frames:
		for line in lines:
			print(line)


func _print_summary() -> void:
	if _results.is_empty():
		return
	var worst := 0
	var worst_label := ""
	var over := 0
	var sum_worst := 0
	var by_offset := {}
	for result: Array in _results:
		sum_worst += result[1]
		over += result[3]
		by_offset[result[2]] = by_offset.get(result[2], 0) + 1
		if result[1] > worst:
			worst = result[1]
			worst_label = result[0]
	print("SUMMARY transitions %d, worst frame %.1f ms (%s), mean of the worst frames %.1f ms, frames > 16.7 ms: %d" % [_results.size(), worst / 1000.0, worst_label, sum_worst / 1000.0 / _results.size(), over])
	print("SUMMARY worst frame offset (frame: transitions): %s" % by_offset)


## Global point of a room-local tile position (Tiles may be offset inside its room).
func _at(room: Node, local: Vector2) -> Vector2:
	return room.to_global(room.get_node("Tiles").position + local)


func _center(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * TILE


func _on_node_added(node: Node) -> void:
	if node.get_script() != null and node.get_script().resource_path.ends_with("dungeon_manager.gd"):
		node.set(&"seed_value", _seed)


func _is_enemy(node: Object) -> bool:
	var script: Script = node.get_script()
	while script != null:
		if script.get_global_name() == &"Enemy":
			return true
		script = script.get_base_script()
	return false


func _kill(enemy: Node, player: Node) -> void:
	var damage: RefCounted = load("res://components/combat/damage_data.gd").new()
	damage.amount = 9999.0
	damage.source = player
	damage.hit_id = load("res://components/combat/damage_data.gd").next_hit_id()
	damage.tags.assign([&"melee"])
	enemy.hurtbox.receive_hit(damage)


func _skip_boss_intros() -> void:
	for node in root.find_children("*", "Node", true, false):
		if node.get_script() != null and node.get_script().get_global_name() == &"BossIntro":
			node.skip()


## Answers every open dialog: picks the first upgrade, closes shops, declines confirmations.
func _resolve_modals() -> void:
	for attempt in 40:
		await _frames(3)
		var modal := _find_modal(root)
		if modal == null:
			return
		var buttons := _buttons(modal)
		var pressed := false
		for wanted in ["Wählen", "Schließen", "Weiterspielen", "Abbrechen"]:
			for button in buttons:
				if button.text == wanted and not button.disabled:
					button.pressed.emit()
					pressed = true
					break
			if pressed:
				break
		if not pressed and not buttons.is_empty():
			buttons[0].pressed.emit()


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


func _frames(count: int) -> void:
	for i in count:
		await physics_frame

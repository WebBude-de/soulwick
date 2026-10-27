extends SceneTree
## Local multi-player run without network (MP1, ROADMAP): a quick game (GameMode QUICK)
## with N players at one machine. Player 0 is the local player (keyboard/mouse input, camera, HUD);
## the others are dummies driven by RemoteInput bots that walk to the nearest enemy, aim at it,
## attack and now and then use their special. The group walks through rooms 1..R (teleport like
## smoke_test.gd), the rooms are cleared and the dialogs answered, and the multiplayer rules are
## checked on the way (PASS/FAIL lines):
## - every player spawns once per world, only the local one has camera, keyboard and HUD;
## - the dummies act through RemoteInput (attacks, specials) and enemies also target them;
## - menus never pause the tree, the local player is protected while one is open (D-085, D-123);
## - Engine.time_scale never changes (no HitStop in a group game);
## - the run goes on while one player stands and ends when the last one falls; back in the village
##   the same session spawns N players again.
## Usage: godot --headless --fixed-fps 60 --path . -s tools/mp_local_sim.gd -- players=2 rooms=5
## Classes are accessed dynamically: this script is compiled before autoloads exist.

const SAVE_PATH := "user://mp_local_sim_save.cfg"
const SETTINGS_PATH := "user://mp_local_sim_settings.cfg"
## Rooms beyond the first boss would need the campfire walk of smoke_test.gd.
const MAX_ROOMS := 14
## How long the bots fight on their own in every combat room before the rest is cleared.
const BOT_FIGHT_FRAMES := 240
## Bots stop this close to their enemy and attack within ATTACK_RANGE (px).
const STOP_DISTANCE := 56.0
const ATTACK_RANGE := 150.0
## A bot taps its special every SPECIAL_EVERY physics frames while it has a target.
const SPECIAL_EVERY := 90

var _failures: Array[String] = []
var _player_count := 2
var _controller: Node = null
var _dungeon: Node = null
## RoomController.State.CLEARED
const ROOM_CLEARED := 2
var _modal_log: Array[String] = []
var _frame := 0
## Watched every physics frame.
var _min_time_scale := 1.0
var _paused_frames := 0
var _dummy_targets := 0
## Per player id: attacks and specials performed.
var _attacks := {}
var _specials := {}


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var rooms_to_play := 5
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("players="):
			_player_count = clampi(int(arg.get_slice("=", 1)), 1, 4)
		elif arg.begins_with("rooms="):
			rooms_to_play = clampi(int(arg.get_slice("=", 1)), 1, MAX_ROOMS)
	print("mp_local_sim: %d players, rooms 1-%d" % [_player_count, rooms_to_play])
	# Buttons are found by their German texts (as in smoke_test.gd).
	TranslationServer.set_locale("de")
	var save_manager := root.get_node("SaveManager")
	save_manager.save_path = SAVE_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	save_manager.load_game()
	save_manager.settings_path = SETTINGS_PATH
	save_manager.load_settings()
	save_manager.set_option(&"language", "de")
	physics_frame.connect(_drive_bots)

	change_scene_to_file("res://scenes/game.tscn")
	await _frames(20)
	TranslationServer.set_locale("de")
	_controller = current_scene.get_node("WorldController")
	var game_mode_script: GDScript = load("res://scenes/game_mode.gd")
	_controller.game_mode = game_mode_script.quick(_player_count)
	print("session: ", _controller.game_mode.describe())
	# Respawn the village with the group, then go down.
	_controller.load_world(_controller.village_scene)
	await _frames(10)
	_check_group("village")

	_controller.enter_dungeon()
	await _frames(20)
	_dungeon = _controller.get_world()
	var run_manager := root.get_node("RunManager")
	_check(_dungeon.get_script().get_global_name() == &"DungeonManager", "dungeon loaded")
	_check(run_manager.is_run_active(), "run started")
	_check_group("dungeon")
	var players: Array = _controller.get_players()
	for player in players:
		# Traps and explosions are real; the test group must survive the walk-through.
		player.health.reset(99999.0)
		var id: int = player.player_id
		_attacks[id] = 0
		_specials[id] = 0
		player.weapon_controller.attack_performed.connect(func(_w: Resource) -> void: _attacks[id] += 1)
		player.weapon_controller.special_performed.connect(func(_w: Resource) -> void: _specials[id] += 1)

	for index in range(1, rooms_to_play + 1):
		var ok: bool = await _play_room(index, run_manager)
		if not ok:
			break
		_check(_controller.get_players().size() == _player_count, "room %d keeps all %d players" % [index, _player_count])

	_check(_min_time_scale == 1.0, "Engine.time_scale never changed (min %.2f)" % _min_time_scale)
	_check(_paused_frames == 0, "the tree was never paused (%d frames)" % _paused_frames)
	if _player_count > 1:
		_check(_dummy_targets > 0, "enemies also targeted the dummy players (%d frames)" % _dummy_targets)
		for player in players:
			if player.is_local:
				continue
			_check(_attacks[player.player_id] > 0, "dummy %d attacked through RemoteInput (%d)" % [player.player_id, _attacks[player.player_id]])
			_check(_specials[player.player_id] > 0, "dummy %d used its special through RemoteInput (%d)" % [player.player_id, _specials[player.player_id]])
	print("run gold (shared pot, D-081): ", run_manager.get_run_gold())
	print("attacks per player: %s, specials: %s" % [_attacks, _specials])

	await _end_run(run_manager)

	print("modals seen: ", ", ".join(_modal_log))
	if _failures.is_empty():
		print("MP LOCAL SIM PASSED")
		quit(0)
	else:
		print("MP LOCAL SIM FAILED (%d):" % _failures.size())
		for failure in _failures:
			print("  - ", failure)
		quit(1)


## Every player of the session exists once; only the local one has camera, keyboard and HUD.
func _check_group(where: String) -> void:
	var players: Array = _controller.get_players()
	_check(players.size() == _player_count, "%s: %d players spawned" % [where, players.size()])
	var local: Node = _controller.get_player()
	_check(local != null and local.is_local and local.player_id == 0, "%s: player 0 is the local player" % where)
	if local == null:
		return
	_check(local.input.get_script().get_global_name() == &"LocalKeyboardMouseInput", "%s: the local player reads keyboard and mouse" % where)
	var camera: Camera2D = local.get_node("Camera2D")
	_check(root.get_camera_2d() == camera or local.get_viewport().get_camera_2d() == camera, "%s: the view follows the local player" % where)
	var hud: Node = current_scene.get_node("Hud")
	_check(hud.get(&"_player") == local, "%s: the HUD shows the local player" % where)
	var ids := {}
	for player in players:
		ids[player.player_id] = true
		_check(player.is_in_group(&"player"), "%s: player %d in the player group" % [where, player.player_id])
		if player == local:
			continue
		_check(not player.is_local, "%s: player %d is not local" % [where, player.player_id])
		_check(player.input.get_script().get_global_name() == &"RemoteInput", "%s: player %d reads RemoteInput" % [where, player.player_id])
		_check(not (player.get_node("Camera2D") as Camera2D).enabled, "%s: player %d has no camera" % [where, player.player_id])
	_check(ids.size() == _player_count, "%s: distinct player ids %s" % [where, ids.keys()])


func _play_room(index: int, run_manager: Node) -> bool:
	var room: Node = _dungeon.get_room(index)
	if room == null:
		_fail("room %d was not prepared" % index)
		return false
	var type_name: String = ["COMBAT", "COMBAT_UPGRADE", "SPECIAL", "MINIBOSS", "BOSS", "CAMPFIRE"][room.room_type]
	_place_group(room)
	await _frames(6)
	_check(run_manager.get_current_room() == index, "RunManager room %d" % index)
	# D-084 (L from 3 players) as far as the catalog has the size: the plan rooms (R1) have no L yet.
	var sizes: Array = _dungeon.get_room_sizes()
	if room.has_room_kind():
		_check(sizes.has(room.room_size_class), "room %d: size class %d for %d players (D-084)" % [index, room.room_size_class, _player_count])

	if type_name == "SPECIAL":
		print("room %d: special %s" % [index, room.special_type])
		await _use_special(room)
	else:
		# Intro pattern (R3, arena): a player would skip it with E; the fight starts on release.
		var intro: Object = load("res://dungeon/modes/room_intro.gd").get_intro(room)
		if intro != null:
			intro.skip()
			await _frames(5)
		_check(room.is_encounter_started(), "room %d encounter started on entry" % index)
		var enemies: Array = _living_enemies(room)
		print("room %d: %s, %d enemies, size %d" % [index, type_name, enemies.size(), room.room_size_class])
		if type_name == "BOSS":
			await _frames(30)
			_skip_boss_intros()
		var variant: Node = room.get_node_or_null("CombatVariant")
		if variant != null:
			variant.step(41.0)
		# The bots fight on their own for a while.
		await _frames(BOT_FIGHT_FRAMES)
		# Until the room is done: arenas pause 2 s between waves (R3), an enemy needs 1.5 s to come
		# out of its source (R2, unhittable meanwhile).
		for sweep in 40:
			if room.state == ROOM_CLEARED:
				break
			var remaining := _living_enemies(room)
			var players: Array = _controller.get_players()
			for i in remaining.size():
				# Kills are credited round robin, so kill rewards meet every player.
				_kill(remaining[i], players[i % players.size()])
			await _frames(25)
		_check(_living_enemies(room).is_empty(), "room %d cleared" % index)
		await _frames(120)
		await _resolve_modals()

	await _resolve_modals()
	await _frames(10)
	if room.is_branch_room():
		await _take_branch(index, room)
	var exit_door: Node = room._exit_door
	_check(exit_door.is_open, "room %d exit opened after completion" % index)
	return exit_door.is_open


## The whole group onto the free floor tiles nearest to the middle of the room, one tile each.
func _place_group(room: Node) -> void:
	var points := _walk_in_points(room, _player_count)
	var players: Array = _controller.get_players()
	for i in players.size():
		players[i].global_position = room.to_global(points[mini(i, points.size() - 1)])


func _walk_in_points(room: Node, count: int) -> Array[Vector2]:
	var tiles: Node = room.get_node("Tiles")
	var reachable: Dictionary = tiles.get_reachable_tiles(0)
	var scatter: Node = room.get_node_or_null("Ingredients")
	var occupied: Array = scatter.get_blocked_tiles() if scatter != null else []
	var middle: Vector2 = tiles.get_floor_rect().get_center()
	var candidates: Array[Vector2i] = []
	for tile: Vector2i in reachable:
		if tile.x < 0 or tile.y < 0 or tile.x >= tiles.room_size.x or tile.y >= tiles.room_size.y - 1 or occupied.has(tile):
			continue
		if tiles.has_pits() and tiles.is_pit(tile):
			continue
		candidates.append(tile)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _tile_center(a).distance_to(middle) < _tile_center(b).distance_to(middle))
	var points: Array[Vector2] = []
	for tile in candidates:
		points.append(tiles.position + (Vector2(tile) + Vector2(0.5, 0.5)) * 64.0)
		if points.size() >= count:
			break
	if points.is_empty():
		points.append(tiles.position + (Vector2(tiles.entrance_x, tiles.room_size.y - 2) + Vector2(0.5, 0.5)) * 64.0)
	return points


## Room-local centre of a tile relative to the floor (as in smoke_test.gd).
static func _tile_center(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * 64.0


## Branch room (D-105): the group walks up to the first door; the doors decide for everybody.
func _take_branch(index: int, room: Node) -> void:
	var tiles: Node = room.get_node("Tiles")
	var exit: Vector2i = tiles.get_exit_doors()[0]
	var inside: Vector2i = tiles.inside_tile_of(exit.x, exit.y, tiles.room_size)
	for player in _controller.get_players():
		player.global_position = room.to_global((Vector2(inside) + Vector2(0.5, 0.5)) * 64.0)
	await _frames(8)
	_check(room.get_chosen_branch() == 0, "branch room %d: the group chose door 0" % index)
	_place_group(room)
	await _frames(4)


func _use_special(room: Node) -> void:
	await _frames(4)
	var local: Node = _controller.get_player()
	for content in room.get_children():
		for child in content.get_children():
			if child.get_script() != null and child.get_script().get_global_name() == &"Interactable" and child.enabled:
				if child.prompt.begins_with("Dungeon verlassen"):
					continue
				child.interact(local)
				await _frames(4)
				await _resolve_modals()
				return


## The local player falls first: the run goes on while the dummies stand (D-084), then the last
## one falls and the run ends; the group respawns in the village.
func _end_run(run_manager: Node) -> void:
	var players: Array = _controller.get_players()
	var local: Node = _controller.get_player()
	local.health.take_damage(999999.0)
	await _frames(150)
	if _player_count > 1:
		_check(run_manager.is_run_active(), "the run goes on while another player stands")
		for player in players:
			if player != local:
				player.health.take_damage(999999.0)
		await _frames(150)
	_check(not run_manager.is_run_active(), "the run ended when the last player fell")
	_check(Engine.time_scale == 1.0, "no slow motion at the death of a group player")
	await _press_modal_button("Zurück ins Dorf")
	await _frames(20)
	_check(_controller.get_world().get_script().get_global_name() == &"Village", "back in the village after the run")
	_check(not root.get_node("GameManager").is_game_paused(), "no stale menu reason after the run")
	_check_group("village after the run")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


## RemoteInput bots for every non-local player: walk to the nearest enemy, aim, attack, special.
func _drive_bots() -> void:
	_frame += 1
	_min_time_scale = minf(_min_time_scale, Engine.time_scale)
	if paused:
		_paused_frames += 1
	if _controller == null or not is_instance_valid(_controller) or _dungeon == null or not is_instance_valid(_dungeon):
		return
	var room: Node = _dungeon.get_room(_dungeon.get_active_room_index())
	if room == null:
		return
	var enemies := _living_enemies(room)
	for enemy in enemies:
		var target: Node = enemy.get_target()
		if target != null and not target.is_local:
			_dummy_targets += 1
			break
	for player in _controller.get_players():
		if not is_instance_valid(player) or player.is_local or not player.is_alive():
			continue
		var input: Object = player.input
		var nearest: Node2D = null
		var best := INF
		for enemy in enemies:
			var distance: float = player.global_position.distance_to(enemy.global_position)
			if distance < best:
				best = distance
				nearest = enemy
		if nearest == null:
			input.set_move(Vector2.ZERO)
			input.release(&"attack")
			continue
		var to_enemy: Vector2 = nearest.global_position - player.global_position
		input.set_aim_point(nearest.global_position)
		input.set_move(to_enemy.normalized() if best > STOP_DISTANCE else Vector2.ZERO)
		if best < ATTACK_RANGE:
			input.press(&"attack")
		else:
			input.release(&"attack")
		if (_frame + player.player_id * 17) % SPECIAL_EVERY == 0:
			input.tap(&"special_attack")


func _living_enemies(room: Node) -> Array:
	return room.enemy_container.get_children().filter(func(n: Node) -> bool: return _is_enemy(n) and not n.is_dead())


func _is_enemy(node: Object) -> bool:
	var script: Script = node.get_script()
	while script != null:
		if script.get_global_name() == &"Enemy":
			return true
		script = script.get_base_script()
	return false


func _kill(enemy: Node, player: Node) -> void:
	var damage_script: GDScript = load("res://components/combat/damage_data.gd")
	var damage: RefCounted = damage_script.new()
	damage.amount = 9999.0
	damage.source = player
	damage.hit_id = damage_script.next_hit_id()
	damage.tags.assign([&"melee"])
	enemy.hurtbox.receive_hit(damage)


func _skip_boss_intros() -> void:
	for node in root.find_children("*", "Node", true, false):
		if node.get_script() != null and node.get_script().get_global_name() == &"BossIntro":
			node.skip()


## Answers every open dialog (first upgrade, close shops). While one is open the tree keeps
## running and the local player is protected (D-085, D-123).
func _resolve_modals() -> void:
	for attempt in 40:
		await _frames(3)
		var modal := _find_modal(root)
		if modal == null:
			return
		var local: Node = _controller.get_player()
		_check(not paused, "dialog open, the world keeps running")
		_check(local.is_protected() and local.hurtbox.is_invulnerable(), "dialog open, the local player is protected")
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
		await _frames(2)
		if _find_modal(root) == null:
			_check(not local.is_protected(), "dialog closed, the local player is free again")


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

extends SceneTree
## Enemy pathfinding check (A2) in a real dungeon room.
## Usage: godot --headless --fixed-fps 60 --path . -s tests/manual/enemy_nav_check.gd [-- nav=off bench=0 uwall=0 body=1 isolate=1 enemies=N trace=N]
##
## 1. U-wall: wall tiles form a cup that opens away from the player; enemies start inside the cup
##    and must walk out and around it. PASS when every enemy reaches the player (melee) or gets a free
##    shot (ranged) within ENGAGE_LIMIT and never stands in CHASE for more than STUCK_LIMIT seconds
##    without moving (the "hängt nicht länger als 2 s" rule).
##    Then a wall body that is not part of the navigation (like boss_sim): the old steering must
##    still walk around it.
## 2. Benchmark: 18 enemies (enemies=N) around two inner walls, wall time per frame (--fixed-fps
##    runs frames back to back) without enemies, with navigation and with the room navigation off.
## The player stands still and is invulnerable the whole time.
## nav=off turns the room navigation off (old behaviour, for comparison; never fails).
## body=1 skips the U-wall cases, uwall=0 skips part 1, bench=0 skips part 2.
## isolate=1 gives the room its own navigation map first (EnemyNavigation.isolate_room_navigation).
## trace=N prints position, state and waypoints of the N-th enemy of every case.

const STUCK_LIMIT := 2.0
const STUCK_MOVE := 24.0
const ENGAGE_LIMIT := 25.0
const MELEE_REACH := 80.0
const WALL_TILE := Vector2i(6, 2)  # pillar tile of the ground atlas, blocks like a wall
const FLOOR_TILE := Vector2i(0, 0)
## Enemy.State / Enemy.Action / EnemyData.AttackKind values. Scripts started with -s must not name
## classes that use autoloads (they compile before the autoloads exist), so plain ints here.
const STATE_CHASE := 1
const STATE_TELEGRAPH := 2
const ACTION_NORMAL := 0
const ATTACK_RANGED := 1
const SOURCE_ID := 0
const TILE_WORLD := 64.0
const CASES := [
	{"name": "slime", "data": "res://enemies/data/slime.tres", "count": 1},
	{"name": "skeleton", "data": "res://enemies/data/skeleton.tres", "count": 1},
	{"name": "shadow", "data": "res://enemies/data/shadow.tres", "count": 1},
	{"name": "golem", "data": "res://enemies/data/golem.tres", "count": 1},
	{"name": "archer", "data": "res://enemies/data/archer.tres", "count": 1},
	{"name": "necromancer", "data": "res://enemies/data/necromancer.tres", "count": 1},
	{"name": "slime crowd", "data": "res://enemies/data/slime.tres", "count": 5},
]
const BENCH_ENEMIES := [
	"res://enemies/data/slime.tres", "res://enemies/data/skeleton.tres", "res://enemies/data/archer.tres",
	"res://enemies/data/shadow.tres", "res://enemies/data/golem.tres", "res://enemies/data/necromancer.tres",
]
const BENCH_COUNT := 18
const BENCH_FRAMES := 600

var _failures: Array[String] = []
var _navigation := true
var _bench := true
var _trace := false
var _trace_index := 0
var _u_wall := true
var _isolate := false
var _body_only := false
var _bench_count := BENCH_COUNT


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "nav=off":
			_navigation = false
		elif arg == "bench=0":
			_bench = false
		elif arg == "uwall=0":
			_u_wall = false
		elif arg.begins_with("enemies="):
			_bench_count = maxi(1, int(arg.trim_prefix("enemies=")))
		elif arg == "body=1":
			_body_only = true
		elif arg == "isolate=1":
			_isolate = true
		elif arg.begins_with("trace="):
			_trace = true
			_trace_index = int(arg.trim_prefix("trace=")) - 1
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	root.get_node("SaveManager").save_path = "user://enemy_nav_check_save.cfg"
	change_scene_to_file("res://scenes/game.tscn")
	await _frames(20)
	var controller := current_scene.get_node("WorldController")
	controller.enter_dungeon()
	await _frames(30)
	var dungeon: Node = controller.get_world()
	var player: Node = controller.get_player()
	var room: Node2D = dungeon.get_room(1)
	var tiles: Node = room.get_node("Tiles")
	for enemy in room.enemy_container.get_children():
		if enemy.has_method("is_dead"):
			enemy.health.take_damage(INF)
	await _frames(120)
	player.set_physics_process(false)
	# Invulnerable instead of huge health: no hit stops (Engine.time_scale) and no HUD with
	# thousands of hearts distorting the frame times.
	player.hurtbox.set_invulnerable(&"nav_check", true)
	tiles.navigation_enabled = _navigation
	if _isolate:
		var map: RID = load("res://enemies/enemy_navigation.gd").isolate_room_navigation(tiles)
		_check(map.is_valid() and tiles.get_navigation_map() == map, "room tiles use their own navigation map")
	print("room size %s, navigation %s%s" % [tiles.room_size, "on" if _navigation else "off", ", own map" if _isolate else ""])

	if _u_wall:
		var cup := _build_cup(tiles)
		await _frames(3)
		for case in CASES:
			if not _body_only:
				await _run_u_wall(case, room, tiles, player, cup)

	if _u_wall:
		_clear_area(tiles, Rect2i(Vector2i.ZERO, tiles.room_size))
		await _frames(3)
		await _run_body_wall(room, tiles, player)

	if _bench:
		_clear_area(tiles, Rect2i(Vector2i.ZERO, tiles.room_size))
		_build_inner_walls(tiles)
		await _frames(3)
		var empty := await _benchmark(room, tiles, player, true, 0)
		var with_nav := await _benchmark(room, tiles, player, true, _bench_count)
		var without_nav := await _benchmark(room, tiles, player, false, _bench_count)
		for row in [["no enemies", empty], ["navigation on", with_nav], ["navigation off", without_nav]]:
			var result: Dictionary = row[1]
			print("BENCH %d enemies, %s: frame avg %.2f ms, p95 %.2f ms, max %.2f ms, %d alive at the end, path requests/s %.1f, sight checks/s %.1f" % [
				_bench_count if row[0] != "no enemies" else 0, row[0], result["avg"], result["p95"], result["max"], result["alive"], result["paths"], result["sights"]])
		_check(with_nav["p95"] < 1000.0 / 60.0, "%d enemies with navigation: 95 %% of frames below 16.7 ms (%.2f ms)" % [_bench_count, with_nav["p95"]])

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://enemy_nav_check_save.cfg"))
	if _failures.is_empty():
		print("ENEMY NAV CHECK PASSED")
		quit(0)
	else:
		print("ENEMY NAV CHECK FAILED: ", _failures)
		quit(0 if not _navigation else 1)


## A cup of wall tiles opening north, away from the player below it. Returns tile anchors.
func _build_cup(tiles) -> Dictionary:
	var size: Vector2i = tiles.room_size
	var center: int = size.x / 2
	var bar: int = size.y - 3
	_clear_area(tiles, Rect2i(Vector2i.ZERO, size))
	for x in range(center - 3, center + 4):
		tiles.set_cell(Vector2i(x, bar), SOURCE_ID, WALL_TILE)
	for y in range(bar - 3, bar):
		tiles.set_cell(Vector2i(center - 3, y), SOURCE_ID, WALL_TILE)
		tiles.set_cell(Vector2i(center + 3, y), SOURCE_ID, WALL_TILE)
	return {"inside": Vector2i(center, bar - 1), "player": Vector2i(center, size.y - 1)}


## Two inner walls with gaps and a few pillars for the benchmark.
func _build_inner_walls(tiles) -> void:
	var size: Vector2i = tiles.room_size
	for x in range(2, size.x - 4):
		tiles.set_cell(Vector2i(x, 2), SOURCE_ID, WALL_TILE)
	for x in range(4, size.x - 2):
		tiles.set_cell(Vector2i(x, size.y - 3), SOURCE_ID, WALL_TILE)
	tiles.set_cell(Vector2i(size.x / 2, size.y / 2), SOURCE_ID, WALL_TILE)


func _clear_area(tiles, area: Rect2i) -> void:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			tiles.set_cell(Vector2i(x, y), SOURCE_ID, FLOOR_TILE)


func _run_u_wall(case: Dictionary, room: Node2D, tiles, player, cup: Dictionary) -> void:
	player.global_position = room.to_global(_tile_center(cup["player"]))
	var enemies: Array = []
	var count: int = case["count"]
	for i in count:
		var enemy: Node = load("res://enemies/enemy_base.tscn").instantiate()
		enemy.data = load(case["data"])
		enemy.apply_scaling(1, false)
		enemy.arena = room.get_arena()
		var offset := Vector2((i - (count - 1) * 0.5) * 34.0, 0.0)
		enemy.position = _tile_center(cup["inside"]) + offset
		room.enemy_container.add_child(enemy)
		enemies.append(enemy)
	var engaged_at: Array[float] = []
	var longest_stuck: Array[float] = []
	var anchors: Array[Vector2] = []
	var anchor_times: Array[float] = []
	for enemy in enemies:
		engaged_at.append(-1.0)
		longest_stuck.append(0.0)
		anchors.append(enemy.global_position)
		anchor_times.append(0.0)
	var frames := int(ENGAGE_LIMIT * 60.0)
	for frame in frames:
		await physics_frame
		var time := frame / 60.0
		var all_engaged := true
		for i in enemies.size():
			var enemy = enemies[i]
			if not is_instance_valid(enemy) or enemy.is_dead():
				continue
			if engaged_at[i] < 0.0 and _is_engaged(enemy, player):
				engaged_at[i] = time
			if engaged_at[i] >= 0.0:
				continue
			if _trace and i == _trace_index and frame % 10 == 0:
				var nav = enemy.get_navigation()
				print("  t=%.2f pos=%s state=%d following=%s vel=%s detour=%.2f walk=%s tiles=%s" % [time, room.to_local(enemy.global_position).round(), enemy._state, nav.is_following_path(), enemy.velocity.round(), enemy._detour_left, nav._walk_clear, nav._tiles_in_the_way])
				var local_points := []
				for point in nav.get_waypoints():
					local_points.append(room.to_local(point).round())
				print("    waypoints ", local_points, " raw ", Array(enemy._navigation_agent.get_current_navigation_path()).map(func(p): return room.to_local(p).round()))
			all_engaged = false
			if enemy._state != STATE_CHASE or enemy.global_position.distance_to(anchors[i]) > STUCK_MOVE:
				anchors[i] = enemy.global_position
				anchor_times[i] = time
			longest_stuck[i] = maxf(longest_stuck[i], time - anchor_times[i])
		if all_engaged:
			break
	for i in enemies.size():
		var label := "%s #%d" % [case["name"], i + 1]
		var engaged := engaged_at[i] >= 0.0
		print("%s: engaged %s, longest stand %.2f s, path requests %d" % [
			label, ("after %.2f s" % engaged_at[i]) if engaged else "never", longest_stuck[i],
			enemies[i].get_navigation().path_requests if is_instance_valid(enemies[i]) else -1])
		_check(engaged, "%s gets out of the U-wall and engages" % label)
		_check(longest_stuck[i] <= STUCK_LIMIT, "%s never hangs longer than %.0f s (%.2f s)" % [label, STUCK_LIMIT, longest_stuck[i]])
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.is_dead():
			enemy.health.take_damage(INF)
	await _frames(90)


## Same as boss_sim "melee enemy walks around a wall": a wall body that is not part of the tile
## navigation (crates, doors, test walls). The old steering must still handle it.
func _run_body_wall(room: Node2D, tiles, player) -> void:
	var size: Vector2i = tiles.room_size
	var center: Vector2 = room.to_global(Vector2(size) * TILE_WORLD * 0.5)
	player.global_position = center + Vector2(0, 140)
	var wall := StaticBody2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(180, 40)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	wall.add_child(collision)
	room.add_child(wall)
	wall.global_position = center
	var enemy: Node = load("res://enemies/enemy_base.tscn").instantiate()
	enemy.data = load("res://enemies/data/slime.tres")
	enemy.apply_scaling(1, false)
	enemy.arena = room.get_arena()
	enemy.position = room.to_local(center + Vector2(0, -110))
	room.enemy_container.add_child(enemy)
	var reached_after := -1.0
	for i in 60 * 12:
		await physics_frame
		if _trace and i % 10 == 0:
			print("  t=%.2f pos=%s state=%d vel=%s following=%s" % [i / 60.0, room.to_local(enemy.global_position).round(), enemy._state, enemy.velocity.round(), enemy.get_navigation().is_following_path()])
		if enemy.global_position.distance_to(player.global_position) < 60.0:
			reached_after = i / 60.0
			break
	print("wall body: reached %s" % (("after %.2f s" % reached_after) if reached_after >= 0.0 else "never"))
	_check(reached_after >= 0.0, "melee enemy walks around a wall body that is not in the navigation")
	enemy.health.take_damage(INF)
	wall.queue_free()
	await _frames(60)


func _is_engaged(enemy, player) -> bool:
	if enemy.data.attack_kind == ATTACK_RANGED:
		# Shooting with a free line (normal shot telegraph) counts; volleys ignore walls anyway.
		return enemy._state == STATE_TELEGRAPH and enemy._action == ACTION_NORMAL
	return enemy.global_position.distance_to(player.global_position) < MELEE_REACH


func _benchmark(room: Node2D, tiles, player, navigation: bool, count: int) -> Dictionary:
	tiles.navigation_enabled = navigation
	await _frames(3)
	var size: Vector2i = tiles.room_size
	player.global_position = room.to_global(_tile_center(Vector2i(size.x / 2, size.y - 2)))
	var enemies: Array = []
	for i in count:
		var enemy: Node = load("res://enemies/enemy_base.tscn").instantiate()
		enemy.data = load(BENCH_ENEMIES[i % BENCH_ENEMIES.size()])
		enemy.apply_scaling(1, false)
		enemy.arena = room.get_arena()
		# Above the upper inner wall, so they all have to path around.
		enemy.position = _tile_center(Vector2i(1 + (i * 3) % maxi(1, size.x - 2), i % 2))
		room.enemy_container.add_child(enemy)
		enemies.append(enemy)
	await _frames(10)
	# --fixed-fps disables real-time sync: frames run back to back, so wall time per frame is
	# the full cost of a frame (physics, navigation, scripts, headless rendering).
	var frame_times: Array[float] = []
	var alive := 0
	var last := Time.get_ticks_usec()
	for frame in BENCH_FRAMES:
		await physics_frame
		var now := Time.get_ticks_usec()
		frame_times.append((now - last) / 1000.0)
		if frame_times[-1] > 50.0:
			print("  slow frame %d: %.1f ms" % [frame, frame_times[-1]])
		last = now
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.is_dead():
			alive += 1
	frame_times.sort()
	var total := 0.0
	for value in frame_times:
		total += value
	var paths := 0
	var sights := 0
	for enemy in enemies:
		if is_instance_valid(enemy):
			paths += enemy.get_navigation().path_requests
			sights += enemy.get_navigation().sight_checks
			if not enemy.is_dead():
				enemy.health.take_damage(INF)
	await _frames(120)
	var seconds := BENCH_FRAMES / 60.0
	return {"avg": total / frame_times.size(), "p95": frame_times[int(frame_times.size() * 0.95)],
		"max": frame_times[-1], "alive": alive, "paths": paths / seconds, "sights": sights / seconds}


static func _tile_center(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * TILE_WORLD


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		_failures.append(message)

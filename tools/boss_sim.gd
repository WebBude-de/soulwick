extends SceneTree
## Headless check of bosses, new enemy types, champions, boss phase two and elites with real AI
## against a sturdy player.
## Usage: godot --headless --fixed-fps 60 --path . -s tools/boss_sim.gd
## Case keys: data, room, expect (abilities that must be seen), optional forbid, champion (bool),
## tier (boss tier), phase2 (push below half health after a moment), kill_after (frames).
## Abilities come from Enemy.ability_used plus player effects (stun, blind) and summons.

const CASES := [
	# Bosses, phase one.
	{"data": "res://enemies/data/boss_bone_king.tres", "room": 15, "expect": ["stun", "volley"]},
	{"data": "res://enemies/data/boss_slime_queen.tres", "room": 30, "expect": ["summon", "slam"]},
	{"data": "res://enemies/data/boss_shadow_lord.tres", "room": 45, "expect": ["blind", "teleport"]},
	{"data": "res://enemies/data/boss_ember_golem.tres", "room": 60, "expect": ["slam", "summon", "volley"]},
	# Bosses, phase two: roar (invulnerable), then the new pattern.
	{"data": "res://enemies/data/boss_bone_king.tres", "room": 15, "phase2": true, "expect": ["roar", "roar_invulnerable", "chain", "spiral", "summon"]},
	{"data": "res://enemies/data/boss_slime_queen.tres", "room": 30, "phase2": true, "expect": ["roar", "roar_invulnerable", "chain", "landing_ring"]},
	{"data": "res://enemies/data/boss_shadow_lord.tres", "room": 45, "phase2": true, "expect": ["roar", "roar_invulnerable", "spiral", "eruption"]},
	{"data": "res://enemies/data/boss_ember_golem.tres", "room": 60, "phase2": true, "expect": ["roar", "roar_invulnerable", "landing_ring", "eruption", "spiral"]},
	# Higher tier: patterns already in phase one.
	{"data": "res://enemies/data/boss_ember_golem.tres", "room": 120, "tier": 1, "expect": ["landing_ring", "slam"]},
	{"data": "res://enemies/data/boss_bone_king.tres", "room": 135, "tier": 2, "expect": ["chain", "spiral"]},
	# Normal enemies.
	{"data": "res://enemies/data/skeleton.tres", "room": 6, "expect": ["stun"]},
	{"data": "res://enemies/data/shadow.tres", "room": 6, "expect": ["blind"]},
	{"data": "res://enemies/data/bomber.tres", "room": 6, "expect": ["self_destruct"]},
	{"data": "res://enemies/data/golem.tres", "room": 31, "expect": ["slam"]},
	{"data": "res://enemies/data/necromancer.tres", "room": 31, "expect": ["summon"]},
	{"data": "res://enemies/data/splitter_slime.tres", "room": 16, "kill_after": 90, "expect": ["split", "summon"]},
	# Champions: type-specific specials, phase two.
	{"data": "res://enemies/data/skeleton.tres", "room": 10, "champion": true, "phase2": true, "expect": ["charge", "roar", "chain", "summon"]},
	{"data": "res://enemies/data/slime.tres", "room": 5, "champion": true, "expect": ["slam"]},
	{"data": "res://enemies/data/archer.tres", "room": 10, "champion": true, "expect": ["volley"]},
	{"data": "res://enemies/data/bomber.tres", "room": 10, "champion": true, "expect": ["eruption"], "forbid": ["self_destruct"]},
	{"data": "res://enemies/data/shadow.tres", "room": 10, "champion": true, "expect": ["teleport", "blind"]},
	{"data": "res://enemies/data/necromancer.tres", "room": 35, "champion": true, "phase2": true, "expect": ["summon", "roar", "spiral"]},
]
const CASE_FRAMES := 60 * 20
const PHASE_TWO_AFTER := 90

var _failures: Array[String] = []


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	root.get_node("SaveManager").save_path = "user://boss_sim_save.cfg"
	change_scene_to_file("res://scenes/game.tscn")
	await _frames(20)
	var controller := current_scene.get_node("WorldController")
	controller.enter_dungeon()
	await _frames(30)
	var dungeon: Node = controller.get_world()
	var player: Node = controller.get_player()
	var room: Node = dungeon.get_room(1)
	# Clear the regular encounter first.
	for enemy in room.enemy_container.get_children():
		if enemy.has_method("is_dead"):
			enemy.health.take_damage(INF)
	await _frames(200)

	for case in CASES:
		await _run_case(case, room, player)

	await _check_obstacle_avoidance(room, player)

	# Elites: every kind spawns, glows, shows its badge and the volatile one explodes on death.
	for kind in [1, 2, 3]:
		var elite := _spawn(load("res://enemies/data/slime.tres"), room, player, 10)
		elite.make_elite(kind)
		room.enemy_container.add_child(elite)
		await _frames(5)
		_check(elite.has_node("Glow"), "elite kind %d glows in the dark" % kind)
		_check(elite.get_badges().size() == 1, "elite kind %d shows its badge" % kind)
		var hp_before: float = player.health.get_health()
		elite.global_position = player.global_position + Vector2(30, 0)
		elite.health.take_damage(INF)
		await _frames(80)
		if kind == 3:
			_check(player.health.get_health() < hp_before or player.hurtbox.is_invulnerable(), "volatile elite exploded next to the player")

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://boss_sim_save.cfg"))
	if _failures.is_empty():
		print("BOSS SIM PASSED")
		quit(0)
	else:
		print("BOSS SIM FAILED: ", _failures)
		quit(1)


func _run_case(case: Dictionary, room: Node, player: Node) -> void:
	var data: Resource = load(case["data"])
	var champion: bool = case.get("champion", false)
	var label := "%s%s%s%s" % [
		"Champion " if champion else "",
		data.display_name,
		" T%d" % case["tier"] if case.has("tier") else "",
		" (phase 2)" if case.get("phase2", false) else "",
	]
	player.health.reset(99999.0)
	player.global_position = room.to_global(room.get_node("Tiles").get_floor_rect().get_center() + Vector2(0, 150))
	var enemy := _spawn(data, room, player, case["room"], champion)
	if champion:
		# Like EnemySpawner: an elite trait and escort summons for types without own summons.
		enemy.make_elite(1 + randi() % 3)
		if data.summon_data == null:
			enemy.extra_summon_data = load("res://enemies/data/slime.tres")
	if case.has("tier"):
		enemy.set_boss_tier(case["tier"])
	var seen := {}
	enemy.ability_used.connect(func(_e, ability: StringName) -> void: seen[String(ability)] = true)
	enemy.summoned.connect(func(_m) -> void: seen["summon"] = true)
	var on_blind := func(_d) -> void: seen["blind"] = true
	player.blinded.connect(on_blind)
	room.enemy_container.add_child(enemy)
	var expected: Array = case["expect"]
	for i in CASE_FRAMES:
		await physics_frame
		if not is_instance_valid(enemy):
			break
		if case.get("phase2", false) and i == PHASE_TWO_AFTER:
			enemy.health.take_damage(enemy.health.get_max_health() * 0.55)
		if case.has("kill_after") and i == case["kill_after"]:
			enemy.health.take_damage(INF)
		if enemy.is_dead():
			if not case.has("kill_after"):
				break
		elif enemy.is_roaring() and enemy.hurtbox.is_invulnerable():
			seen["roar_invulnerable"] = true
		if player.is_stunned():
			seen["stun"] = true
		if enemy._state == 5:
			seen["slam"] = true
		# Keep the player from being hit constantly, but alive and in reach.
		if player.health.get_health() < 1000.0:
			player.health.reset(99999.0)
		if expected.all(func(key: String) -> bool: return seen.has(key)) and not case.has("forbid"):
			break
	player.blinded.disconnect(on_blind)
	print("%s: seen %s" % [label, seen.keys()])
	for key in expected:
		_check(seen.has(key), "%s uses %s" % [label, key])
	for key in case.get("forbid", []):
		_check(not seen.has(key), "%s never uses %s" % [label, key])
	if is_instance_valid(enemy) and not enemy.is_dead():
		enemy.health.take_damage(INF)
	await _frames(30)
	for child in room.enemy_container.get_children():
		if child.has_method("is_dead") and not child.is_dead():
			child.health.take_damage(INF)
	await _frames(120)


## A wall between enemy and player: the enemy must walk around it (steering).
func _check_obstacle_avoidance(room: Node, player: Node) -> void:
	player.health.reset(99999.0)
	var center: Vector2 = room.to_global(room.get_node("Tiles").get_floor_rect().get_center())
	player.global_position = center + Vector2(0, 140)
	var wall := StaticBody2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(180, 40)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	wall.add_child(collision)
	room.add_child(wall)
	wall.global_position = center
	var enemy := _spawn(load("res://enemies/data/slime.tres"), room, player, 1)
	enemy.position = room.to_local(center + Vector2(0, -110))
	room.enemy_container.add_child(enemy)
	var reached := false
	for i in 60 * 12:
		await physics_frame
		if enemy.global_position.distance_to(player.global_position) < 60.0:
			reached = true
			break
	_check(reached, "melee enemy walks around a wall to reach the player")
	enemy.health.take_damage(INF)
	wall.queue_free()
	await _frames(60)


func _spawn(data: Resource, room: Node, player: Node, room_index: int, champion := false) -> Node:
	var enemy: Node = load("res://enemies/enemy_base.tscn").instantiate()
	enemy.data = data
	enemy.position = room.to_local(player.global_position) + Vector2(0, -220)
	enemy.arena = room.get_arena()
	enemy.apply_scaling(room_index, champion)
	return enemy


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		_failures.append(message)

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
	# Own settings: never read or write the real settings.cfg.
	root.get_node("SaveManager").settings_path = "user://boss_sim_settings.cfg"
	root.get_node("SaveManager").load_settings()
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

	# Bare floor: room 1 is a random template (A3); its inner walls, pillars and cover must not
	# decide whether a boss finds room for a pattern or a test setup is reachable at all.
	await _clear_floor(room)
	for case in CASES:
		await _run_case(case, room, player)

	await _check_obstacle_avoidance(room, player)
	await _check_u_wall(room, player)
	await _check_slime_pack(room, player)
	await _check_flanking(room, player)
	await _check_spawn_sources(room, player)

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
func _clear_floor(room: Node) -> void:
	var tiles: Node = room.get_node("Tiles")
	tiles.wall_rects.clear()
	tiles.pillar_tiles.clear()
	tiles.paint()
	var props: Array[Node] = room.get_node("Props").get_children()
	for child in room.get_children():
		if child.has_method(&"get_built_nodes"):
			props.append_array(child.call(&"get_built_nodes"))
	for prop in props:
		if is_instance_valid(prop) and room.is_solid_prop(prop):
			prop.queue_free()
	await _frames(5)


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


## A2: a cup of wall tiles that opens away from the player; a melee and a ranged enemy start inside
## and must find the way out over the tile navigation. None may stand still in CHASE for more than
## 2 s, and both must engage (melee: reach the player, ranged: shoot with a free line).
func _check_u_wall(room: Node, player: Node) -> void:
	var tiles: Node = room.get_node("Tiles")
	var size: Vector2i = tiles.room_size
	var center: int = size.x / 2
	var bar: int = size.y - 3
	var saved := {}
	var cup: Array[Vector2i] = []
	for x in range(center - 3, center + 4):
		cup.append(Vector2i(x, bar))
	# Small makeover caves have only 6-7 rows: keep at least two free rows above the cup.
	var depth := clampi(size.y - 5, 1, 3)
	for y in range(bar - depth, bar):
		cup.append(Vector2i(center - 3, y))
		cup.append(Vector2i(center + 3, y))
	for y in size.y:
		for x in size.x:
			var cell := Vector2i(x, y)
			saved[cell] = tiles.get_cell_atlas_coords(cell)
			tiles.set_cell(cell, 0, Vector2i(6, 2) if cup.has(cell) else Vector2i(0, 0))
	await _frames(3)
	# Invulnerable instead of refilled: no hit stops while the enemies find their way.
	player.hurtbox.set_invulnerable(&"u_wall", true)
	player.global_position = room.to_global((Vector2(center, size.y - 1) + Vector2(0.5, 0.5)) * 64.0)
	var inside: Vector2 = (Vector2(center, bar - 1) + Vector2(0.5, 0.5)) * 64.0
	for path in ["res://enemies/data/slime.tres", "res://enemies/data/archer.tres"]:
		var data: Resource = load(path)
		var enemy := _spawn(data, room, player, 1)
		enemy.position = inside
		room.enemy_container.add_child(enemy)
		var anchor: Vector2 = enemy.global_position
		var anchor_time := 0.0
		var longest := 0.0
		var engaged := false
		for i in 60 * 20:
			await physics_frame
			var time := i / 60.0
			if data.attack_kind == 1:
				engaged = enemy._state == 2 and enemy._action == 0
			else:
				engaged = enemy.global_position.distance_to(player.global_position) < 80.0
			if engaged:
				break
			if enemy._state != 1 or enemy.global_position.distance_to(anchor) > 24.0:
				anchor = enemy.global_position
				anchor_time = time
			longest = maxf(longest, time - anchor_time)
		print("U-wall %s: engaged %s, longest stand %.2f s" % [data.display_name, engaged, longest])
		_check(engaged, "%s finds the way out of a U-wall" % data.display_name)
		_check(longest <= 2.0, "%s never hangs longer than 2 s at the U-wall" % data.display_name)
		enemy.health.take_damage(INF)
		await _frames(60)
	player.hurtbox.set_invulnerable(&"u_wall", false)
	for cell in saved:
		tiles.set_cell(cell, 0, saved[cell])
	await _frames(3)


## Slime pack (KONZEPT_RAEUME_V2 §6): four slimes in room 10 form one pack, hop one after another
## with a landing marker, never land on the player, deal no damage in the air and end up on
## several sides of the player.
func _check_slime_pack(room: Node, player: Node) -> void:
	player.hurtbox.set_invulnerable(&"pack_check", true)
	var center: Vector2 = room.to_global(room.get_node("Tiles").get_floor_rect().get_center())
	player.global_position = center + Vector2(-120, 0)
	var slimes: Array = []
	for i in 4:
		var slime := _spawn(load("res://enemies/data/slime.tres"), room, player, 10)
		slime.position = room.to_local(player.global_position + Vector2(330, -90 + i * 60))
		room.enemy_container.add_child(slime)
		slimes.append(slime)
	var stats := {"hops": 0, "closest": INF}
	for slime in slimes:
		slime.ability_used.connect(func(enemy: Node, ability: StringName) -> void:
			if ability == &"hop":
				stats.hops += 1
			elif ability == &"hop_land":
				stats.closest = minf(stats.closest, enemy.global_position.distance_to(player.global_position)))
	var damage_in_air := false
	var unmarked := false
	var behind := false
	var packs := 0
	for i in 60 * 6:
		await physics_frame
		for slime in slimes:
			if not is_instance_valid(slime):
				continue
			if slime.is_airborne():
				damage_in_air = damage_in_air or slime._attack_hitbox.is_active()
				var marker: Node2D = slime.get_node_or_null("HopMarker")
				unmarked = unmarked or marker == null or not marker.visible
			if slime.global_position.x < player.global_position.x - 20.0:
				behind = true
			if slime.get_tactics() != null:
				packs = maxi(packs, slime.get_tactics().get_pack_count())
	print("Slime pack: %d hops, closest landing %.0f px, packs %d, behind %s" % [stats.hops, stats.closest, packs, behind])
	_check(packs == 1, "four slimes form one pack")
	_check(stats.hops >= 4, "the pack hops")
	_check(stats.closest >= 40.0 - 0.5, "slimes never land on the player")
	_check(not damage_in_air, "no damage in the air")
	_check(not unmarked, "every landing is marked")
	_check(behind, "the pack gets behind the player")
	for slime in slimes:
		if is_instance_valid(slime) and not slime.is_dead():
			slime.health.take_damage(INF)
	player.hurtbox.set_invulnerable(&"pack_check", false)
	await _frames(60)


## Flanking: four skeletons coming from one side of the player in room 10 spread over the ring;
## at least one reaches the far side instead of queueing behind the others.
func _check_flanking(room: Node, player: Node) -> void:
	player.hurtbox.set_invulnerable(&"flank_check", true)
	var center: Vector2 = room.to_global(room.get_node("Tiles").get_floor_rect().get_center())
	player.global_position = center + Vector2(-120, 0)
	var skeletons: Array = []
	for i in 4:
		var skeleton := _spawn(load("res://enemies/data/skeleton.tres"), room, player, 10)
		skeleton.position = room.to_local(player.global_position + Vector2(340 + (i % 2) * 40, -90 + i * 60))
		room.enemy_container.add_child(skeleton)
		skeletons.append(skeleton)
	var far_side := false
	var seconds := 0.0
	for i in 60 * 8:
		await physics_frame
		for skeleton in skeletons:
			var offset: Vector2 = skeleton.global_position - player.global_position
			if offset.x < 0.0 and absf(offset.angle()) > PI * 0.6:
				far_side = true
		if far_side:
			seconds = i / 60.0
			break
	print("Flanking: far side reached %s after %.1f s" % [far_side, seconds])
	_check(far_side, "skeletons flank the player instead of queueing")
	for skeleton in skeletons:
		if is_instance_valid(skeleton) and not skeleton.is_dead():
			skeleton.health.take_damage(INF)
	player.hurtbox.set_invulnerable(&"flank_check", false)
	await _frames(60)


## Enemy sources (R2): a push comes out of several (never all) sources away from the player, after
## the warning; hidden enemies cannot be hit, once out they fight. A champion rises from its source.
func _check_spawn_sources(room: Node, player: Node) -> void:
	var rules: GDScript = load("res://dungeon/spawning/spawn_source_rules.gd")
	var sources: Node = load("res://dungeon/spawning/spawn_sources.gd").setup(room)
	_check(sources != null, "room 1 has enemy sources")
	if sources == null:
		return
	player.hurtbox.set_invulnerable(&"source_check", true)
	player.health.reset(99999.0)
	var center: Vector2 = room.to_global(room.get_node("Tiles").get_floor_rect().get_center())
	player.global_position = center
	await _frames(5)
	var pool: Array = sources.get_pool()
	var enemies: Array = sources.spawn_wave(room.spawner, 4, room.enemy_container, room.context, room.get_arena())
	var used: Array = sources.get_last_sources()
	print("Spawn sources: %d sources, push of %d out of %d" % [pool.size(), enemies.size(), used.size()])
	_check(enemies.size() == 4, "a push of four enemies spawns")
	_check(used.size() >= mini(2, pool.size()) and (pool.size() <= 2 or used.size() < pool.size()), "several sources, never all of three or more")
	var hidden := true
	var far := true
	for enemy in enemies:
		hidden = hidden and enemy.is_hidden_in_source() and enemy.hurtbox.is_invulnerable()
		far = far and enemy.global_position.distance_to(player.global_position) >= rules.MIN_PLAYER_DISTANCE - 2.0 * rules.QUEUE_SPREAD
	_check(hidden, "enemies wait hidden and invulnerable in their sources")
	_check(far, "no enemy comes out next to the player")
	await _frames(3)
	_check(used[0].is_active(), "the first source warns")
	var out_after := -1.0
	var fighting := false
	for i in 60 * 8:
		await physics_frame
		var all_out := true
		for enemy in enemies:
			if is_instance_valid(enemy) and not enemy.is_dead() and enemy.is_in_intro():
				all_out = false
		if all_out and out_after < 0.0:
			out_after = i / 60.0
		if out_after >= 0.0:
			for enemy in enemies:
				if is_instance_valid(enemy) and not enemy.is_dead() and enemy._state in [2, 3, 4, 5, 9]:
					fighting = true
		if fighting:
			break
	print("Spawn sources: all out after %.2f s, fighting %s" % [out_after, fighting])
	_check(out_after >= rules.WARN_TIME, "nobody comes out before the warning is over")
	_check(out_after >= 0.0 and out_after <= rules.release_time(used.size(), ceili(4.0 / used.size())) + 0.2, "everyone is out in time")
	_check(fighting, "enemies attack once they are out")
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.is_dead():
			enemy.health.take_damage(INF)
	await _frames(60)
	# Champion: rises from a big source where it stands, passive until it is out.
	var champion := _spawn(load("res://enemies/data/skeleton.tres"), room, player, 10, true)
	champion.position = room.to_local(center + Vector2(0, -260))
	room.enemy_container.add_child(champion)
	# Typed like the room passes it (Array[Enemy]); built dynamically, this script knows no classes.
	sources.release_encounter(Array([champion], TYPE_OBJECT, &"CharacterBody2D", load("res://enemies/enemy_base.gd")))
	_check(champion.is_hidden_in_source(), "the champion waits in its source")
	await _frames(roundi((rules.WARN_TIME + rules.EMERGE_TIME) * 60.0) + 20)
	_check(not champion.is_in_intro() and champion.visible, "the champion is out and fights")
	champion.health.take_damage(INF)
	player.hurtbox.set_invulnerable(&"source_check", false)
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

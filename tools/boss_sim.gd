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
## Longest wait for the navigation map after a tile change (frames, see _navigation_synced).
const NAVIGATION_WAIT_FRAMES := 180

var _failures: Array[String] = []
## Dungeon seed of this run: room 1 is a random template, so a failure is only reproducible with the
## same seed (`-- seed=N`; 0 or missing = a random one, printed at the start).
var _dungeon_seed := 0
var _seed_pending := true


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seed="):
			_dungeon_seed = int(arg.substr(5))
	if _dungeon_seed == 0:
		randomize()
		_dungeon_seed = 1 + randi() % 1000000
	# The global RNG too (elite traits of champions): one seed repeats the whole run.
	seed(_dungeon_seed)
	print("Boss sim dungeon seed %d (repeat with -- seed=%d)" % [_dungeon_seed, _dungeon_seed])
	node_added.connect(_on_node_added)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


## Sets the seed on the DungeonManager before its _ready builds the dungeon (like balance_sim).
func _on_node_added(node: Node) -> void:
	if not _seed_pending or node.get_script() == null:
		return
	if node.get_script().get_global_name() == &"DungeonManager":
		node.seed_value = _dungeon_seed
		_seed_pending = false


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
	print("Room 1: %s" % room.scene_file_path)
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
	await _check_pillar_circle(dungeon, room, player)

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


## Bare floor for the checks: no inner walls, pillars, abysses or bridges, no solid props. Left-over
## abysses turned the wall check into another test (brueckenkreuz: the test wall, a body outside the
## navigation, stands on the bridge the path leads over), and torch stands and crystals hide their
## blocker one level deeper (DecoProp -> LightIsland -> Blocker), where RoomController.is_solid_prop
## does not look (wachposten: a torch stand inside the U-wall).
func _clear_floor(room: Node) -> void:
	var tiles: Node = room.get_node("Tiles")
	tiles.wall_rects.clear()
	tiles.pillar_tiles.clear()
	var no_rects: Array[Rect2i] = []
	tiles.pit_rects = no_rects
	tiles.bridge_rects = no_rects.duplicate()
	var runtime_pits: Array[Vector2i] = tiles.get_runtime_pit_tiles()
	if not runtime_pits.is_empty():
		tiles.remove_pit_tiles(runtime_pits)
	var iteration := _navigation_iteration(tiles)
	tiles.paint()
	var props: Array[Node] = room.get_node("Props").get_children()
	for child in room.get_children():
		if child.has_method(&"get_built_nodes"):
			props.append_array(child.call(&"get_built_nodes"))
	for prop in props:
		if is_instance_valid(prop) and (room.is_solid_prop(prop) or _has_solid_body(prop)):
			prop.queue_free()
	await _frames(5)
	# The room's own navigation map follows the repaint only after its next sync.
	await _navigation_synced(tiles, iteration)


func _has_solid_body(node: Node) -> bool:
	for child in node.get_children():
		if child is StaticBody2D or _has_solid_body(child):
			return true
	return false


## Iteration id of the navigation map of the tiles (grows with every sync that changed the map).
func _navigation_iteration(tiles: Node) -> int:
	var map: RID = tiles.get_navigation_map()
	return NavigationServer2D.map_get_iteration_id(map) if map.is_valid() else 0


## Waits until the navigation map of the tiles was rebuilt after a tile change made at iteration
## before, at most NAVIGATION_WAIT_FRAMES: changed tiles reach the map only on a later sync of the
## NavigationServer, which runs asynchronously and can take longer than a fixed few frames under
## load. Then a few frames more, so path queries see the new map.
func _navigation_synced(tiles: Node, before: int) -> void:
	var map: RID = tiles.get_navigation_map()
	for i in NAVIGATION_WAIT_FRAMES:
		if not map.is_valid() or NavigationServer2D.map_get_iteration_id(map) > before:
			break
		await physics_frame
	await _frames(3)


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
	var iteration := _navigation_iteration(tiles)
	for y in size.y:
		for x in size.x:
			var cell := Vector2i(x, y)
			# Whole cell: cave rooms paint their floor from another source (RockTerrain).
			saved[cell] = [tiles.get_cell_source_id(cell), tiles.get_cell_atlas_coords(cell), tiles.get_cell_alternative_tile(cell)]
			tiles.set_cell(cell, 0, Vector2i(6, 2) if cup.has(cell) else Vector2i(0, 0))
	# The enemies path over the navigation of the cup, not over the old floor.
	await _navigation_synced(tiles, iteration)
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
	iteration = _navigation_iteration(tiles)
	for cell in saved:
		tiles.set_cell(cell, saved[cell][0], saved[cell][1], saved[cell][2])
	await _navigation_synced(tiles, iteration)


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


## The shadow lord's own room (saeulenkreis, 16.10.2026): with the player above, below or inside the
## pocket between the east pillar and the decoration group, the boss hung at the pillar without a
## shot (the tile navigation led through a corner gap, the group counted as no obstacle) and the
## balance bot's fights ran into the time limit. Now it must keep attacking and never stand still.
const PILLAR_ROOM := "res://dungeon/rooms/boss/saeulenkreis.tscn"
const PILLAR_SPOTS: Array[Vector2i] = [Vector2i(18, 1), Vector2i(18, 8), Vector2i(19, 4)]
const PILLAR_FRAMES := 60 * 15


func _check_pillar_circle(dungeon: Node, room1: Node, player: Node) -> void:
	var boss_type: int = load("res://dungeon/room_sequence.gd").RoomType.BOSS
	var room: Node = load(PILLAR_ROOM).instantiate()
	room.setup(45, boss_type, -1, false, room1.context)
	room.position = Vector2(0, -30000)
	dungeon.room_container.add_child(room)
	var tiles: Node = room.get_node("Tiles")
	await _navigation_synced(tiles, 0)
	# The tile layer hands its cells to the navigation map a little after the first sync.
	await _frames(30)
	player.hurtbox.set_invulnerable(&"pillar_check", true)
	for spot in PILLAR_SPOTS:
		player.health.reset(99999.0)
		player.global_position = room.to_global((Vector2(spot) + Vector2(0.5, 0.5)) * 64.0)
		var boss := _spawn(load("res://enemies/data/boss_shadow_lord.tres"), room, player, 45)
		boss.position = Vector2(672, 96)
		boss.arena = room.get_arena()
		room.enemy_container.add_child(boss)
		var attacks := 0
		var last_count := 0
		var last_attack := 0.0
		var gap := 0.0
		var anchor: Vector2 = boss.global_position
		var anchor_time := 0.0
		var stand := 0.0
		for i in PILLAR_FRAMES:
			await physics_frame
			if not is_instance_valid(boss) or boss.is_dead():
				break
			var time := i / 60.0
			if boss._attack_count != last_count:
				last_count = boss._attack_count
				attacks += 1
				gap = maxf(gap, time - last_attack)
				last_attack = time
			if boss._state != 1 or boss.global_position.distance_to(anchor) > 20.0:
				anchor = boss.global_position
				anchor_time = time
			stand = maxf(stand, time - anchor_time)
			# Only the boss: its shadows would block shots and stand in its way.
			for child in room.enemy_container.get_children():
				if child != boss and child.has_method("is_dead") and not child.is_dead():
					child.health.take_damage(INF)
			if player.health.get_health() < 1000.0:
				player.health.reset(99999.0)
		gap = maxf(gap, PILLAR_FRAMES / 60.0 - last_attack)
		print("Saeulenkreis, player at %s: %d attacks, longest gap %.1f s, longest stand %.1f s" % [spot, attacks, gap, stand])
		_check(attacks >= 5, "shadow lord keeps attacking in saeulenkreis (player at %s)" % spot)
		_check(gap <= 6.0, "shadow lord never goes 6 s without an attack (player at %s)" % spot)
		_check(stand <= 2.0, "shadow lord never hangs at a pillar for 2 s (player at %s)" % spot)
		if is_instance_valid(boss) and not boss.is_dead():
			boss.health.take_damage(INF)
		await _frames(60)
	player.hurtbox.set_invulnerable(&"pillar_check", false)
	player.global_position = room1.to_global(room1.get_node("Tiles").get_floor_rect().get_center())
	room.queue_free()
	await _frames(10)


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

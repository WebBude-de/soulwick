extends SceneTree
## Headless combat simulation: real enemy AI, real attacks of all five weapons with upgrades,
## weapon specials (RMB) and the sword combo finisher.
## Prints PASS/FAIL; any engine error in the output also counts as a failure for the reviewer.
## Usage: godot --headless --path . -s tools/combat_sim.gd

const WEAPON_IDS: Array[StringName] = [&"sword", &"bow", &"staff", &"dagger", &"hammer"]
const ARENA_FRAMES := 60 * 4

var _failures: Array[String] = []
## Hits per weapon id: {id: {"normal": n, "special": n, "finisher": n}}.
var _hits: Dictionary = {}
var _specials_used: Dictionary = {}


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	root.get_node("SaveManager").save_path = "user://combat_sim_save.cfg"
	change_scene_to_file("res://scenes/game.tscn")
	await _frames(20)
	root.get_node("EventBus").enemy_damaged.connect(_on_enemy_damaged)
	var controller := current_scene.get_node("WorldController")
	controller.enter_dungeon()
	await _frames(30)
	var dungeon: Node = controller.get_world()
	var player: Node = controller.get_player()
	var room: Node = dungeon.get_room(1)
	# Bare floor: room 1 is a random template (A3); inner walls and cover must not decide whether
	# enemies reach the player or a shot lands.
	await _clear_floor(room)

	# 1) Enemies attack an idle player.
	player.health.reset(1000.0)
	await _frames(60 * 15)
	_check(player.health.get_health() < 1000.0, "enemies dealt damage to the idle player (%.1f HP left)" % player.health.get_health())

	# 2) Fight with real weapons and upgrades. Drive the weapon directly (no mouse in headless).
	player.set_physics_process(false)
	var upgrades: Node = dungeon.get_node("UpgradeManager")
	for id in ["double_shot", "explosive_hit", "pierce", "wall_bounce", "big_explosion", "heal_on_kill"]:
		for upgrade in upgrades.upgrade_pool:
			if upgrade.id == id:
				upgrades.acquire_upgrade(upgrade)
	var weapons: Node = player.weapon_controller
	weapons.special_performed.connect(func(weapon: Resource) -> void: _specials_used[weapon.id] = int(_specials_used.get(weapon.id, 0)) + 1)
	var bow: Resource = load("res://weapons/data/bow.tres")
	var staff: Resource = load("res://weapons/data/staff.tres")
	var sword: Resource = load("res://weapons/data/sword.tres")
	var dagger: Resource = load("res://weapons/data/dagger.tres")
	var hammer: Resource = load("res://weapons/data/hammer.tres")
	_check(weapons.get_projectile_count(bow) == 2, "Doppelschuss: two projectiles")
	_check(weapons.get_effective_aoe_radius(staff) > 45.0, "Größere Explosion enlarges the staff AOE")
	_check(weapons.get_effective_aoe_radius(hammer) > hammer.aoe_radius, "Größere Explosion enlarges the hammer slam")

	var plan := [null, bow, staff]
	for step in plan.size():
		if plan[step] != null:
			_equip_active(weapons, plan[step], 1)
		await _fight(room, player, 60 * 6)
	var alive := _alive(room)
	_check(alive.is_empty() or room.state != 0, "room 1 enemies defeated by real attacks (%d left)" % alive.size())

	# 3) Next rooms: bow first, then the staff, with specials.
	await _frames(30)
	var room2: Node = dungeon.get_room(2)
	# The weapon arena below stands in the middle of room 2: no inner walls or cover there either.
	await _clear_floor(room2)
	player.global_position = room2.to_global(room2.get_node("Tiles").get_floor_rect().get_center())
	await _frames(10)
	_check(room2.is_encounter_started(), "room 2 encounter started")
	_equip_active(weapons, bow, 1)
	await _fight(room2, player, 60 * 4)
	_equip_active(weapons, staff, 1)
	await _fight(room2, player, 60 * 10)
	_check(_alive(room2).is_empty(), "room 2 cleared with projectiles (%d left)" % _alive(room2).size())
	# Coins pop out first and only home in after half a second.
	await _frames(90)
	_check(root.get_node("RunManager").get_run_gold() > 0, "gold was picked up (%d)" % root.get_node("RunManager").get_run_gold())

	# 4) Weapon arena in the cleared room: every weapon's attack and special against tough dummies.
	await _frames(60)
	player.health.reset(5000.0)
	var dummies := _spawn_dummies(room2, player.global_position)
	await _frames(5)
	_equip_active(weapons, dagger, 0)
	var arena_plan := [[dagger, 0], [hammer, 1], [bow, 1], [staff, 1], [sword, 1]]
	for entry in arena_plan:
		_equip_active(weapons, entry[0], entry[1])
		await _arena_round(player, dummies, ARENA_FRAMES)
	for id in WEAPON_IDS:
		var hits: Dictionary = _hits.get(id, {})
		_check(int(hits.get("normal", 0)) > 0, "%s: regular attacks hit (%d)" % [id, int(hits.get("normal", 0))])
		_check(int(_specials_used.get(id, 0)) > 0, "%s: special used (%d)" % [id, int(_specials_used.get(id, 0))])
		_check(int(hits.get("special", 0)) > 0, "%s: special hit (%d)" % [id, int(hits.get("special", 0))])
	_check(int(_hits.get(&"sword", {}).get("finisher", 0)) > 0, "sword combo finisher landed")
	for dummy in dummies:
		if is_instance_valid(dummy):
			dummy.queue_free()

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://combat_sim_save.cfg"))
	if _failures.is_empty():
		print("COMBAT SIM PASSED")
		quit(0)
	else:
		print("COMBAT SIM FAILED: ", _failures)
		quit(1)


func _equip_active(weapons: Node, weapon: Resource, slot: int) -> void:
	if weapons.get_weapon(slot) != weapon:
		var equipped: bool = weapons.equip_weapon(weapon, slot)
		_check(equipped, "equip %s in slot %d" % [weapon.id, slot])
	if weapons.get_active_slot() != slot:
		weapons.switch_weapon()


func _fight(room: Node, player: Node, max_frames: int) -> void:
	for i in max_frames:
		var targets := _alive(room)
		if targets.is_empty():
			return
		_engage(player, targets[0])
		await physics_frame


## Moves to a fitting distance for the active weapon, attacks and uses the special when useful.
func _engage(player: Node, target: Node2D) -> void:
	var weapons: Node = player.weapon_controller
	var weapon: Resource = weapons.get_active_weapon()
	var to_target: Vector2 = target.global_position - player.global_position
	var special_ready: bool = weapons.is_special_ready(weapons.get_active_slot())
	var wanted := 50.0 if weapon.is_melee() else 220.0
	# The staff nova hits around the player: walk in when it is ready.
	if weapon.id == &"staff" and special_ready:
		wanted = weapons.get_nova_radius(weapon) * 0.6
	if to_target.length() > wanted:
		player.velocity = to_target.normalized() * 180.0
	else:
		player.velocity = Vector2.ZERO
	player.move_and_slide()
	weapons.aim_direction = to_target.normalized()
	if special_ready and (weapon.id != &"staff" or to_target.length() < weapons.get_nova_radius(weapon) * 0.8):
		weapons.request_special()
	weapons.request_attack()


func _arena_round(player: Node, dummies: Array, frames: int) -> void:
	for i in frames:
		var targets := dummies.filter(func(n): return is_instance_valid(n) and not n.is_dead())
		if targets.is_empty():
			return
		targets.sort_custom(func(a, b): return a.global_position.distance_squared_to(player.global_position) < b.global_position.distance_squared_to(player.global_position))
		_engage(player, targets[0])
		await physics_frame


func _spawn_dummies(room: Node, center: Vector2) -> Array:
	var dummies := []
	var scene: PackedScene = load("res://enemies/enemy_base.tscn")
	for offset in [Vector2(70, 0), Vector2(-60, 30), Vector2(10, -70)]:
		var enemy: Node = scene.instantiate()
		enemy.data = load("res://enemies/data/slime.tres")
		room.add_child(enemy)
		enemy.global_position = center + offset
		enemy.health.reset(100000.0)
		dummies.append(enemy)
	return dummies


func _on_enemy_damaged(_enemy, _result, damage) -> void:
	for id in WEAPON_IDS:
		if not damage.tags.has(id):
			continue
		var hits: Dictionary = _hits.get_or_add(id, {})
		var kind := "special" if damage.tags.has(&"special") else "normal"
		hits[kind] = int(hits.get(kind, 0)) + 1
		if damage.tags.has(&"finisher"):
			hits["finisher"] = int(hits.get("finisher", 0)) + 1


func _alive(room: Node) -> Array:
	return room.enemy_container.get_children().filter(func(n): return n.has_method("is_dead") and not n.is_dead())


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


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		_failures.append(message)

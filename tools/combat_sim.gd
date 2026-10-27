extends SceneTree
## Headless combat simulation: real enemy AI, real attacks of all five weapons with upgrades,
## weapon specials (RMB) and the sword combo finisher.
## Prints PASS/FAIL; any engine error in the output also counts as a failure for the reviewer.
## Usage: godot --headless --path . -s tools/combat_sim.gd
## Talents (KE6): -- talents=wind (or ember, soul, or a list wind,ember) fills these paths of the
## talent tree, puts them on the player before the fights and checks what they do.
## Spells (KE7): -- spell=flame_ring (or several: spell=light_flash,heal_spark, or spell=all) casts
## each spell at the end next to dummies, through the input object when the cast action is wired
## (PlayerInput.ACTIONS), else straight through PlayerSpells, and checks its effect and cooldown.

const WEAPON_IDS: Array[StringName] = [&"sword", &"bow", &"staff", &"dagger", &"hammer"]
const ARENA_FRAMES := 60 * 4

var _failures: Array[String] = []
## Hits per weapon id: {id: {"normal": n, "special": n, "finisher": n}}.
var _hits: Dictionary = {}
var _specials_used: Dictionary = {}
## Damage events per enemy instance id (source check, R2).
var _damaged: Dictionary = {}
## Talent paths of this run (talents=...), and hits of the Glutherz wave. The talent scripts are
## loaded at run time: a -s script must not name classes that use autoloads (AGENTS.md §9).
var _talent_paths: Array[StringName] = []
var _ember_wave_hits := 0
var _talent_def: GDScript = null
var _talent_effects: GDScript = null
## Spells of this run (spell=...) and hits per spell id.
var _spell_ids: Array[StringName] = []
var _spell_hits: Dictionary = {}
var _spell_damage: Dictionary = {}


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	root.get_node("SaveManager").save_path = "user://combat_sim_save.cfg"
	# Own settings: never read or write the real settings.cfg.
	root.get_node("SaveManager").settings_path = "user://combat_sim_settings.cfg"
	root.get_node("SaveManager").load_settings()
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
	_talent_def = load("res://talents/talent_def.gd")
	_talent_effects = load("res://talents/talent_effects.gd")
	_talent_paths = _read_talent_paths()
	if not _talent_paths.is_empty():
		await _apply_talents(player)

	# 1) Enemies attack an idle player.
	player.health.reset(1000.0)
	await _frames(60 * 15)
	_check(player.health.get_health() < 1000.0, "enemies dealt damage to the idle player (%.1f HP left)" % player.health.get_health())
	# Group tactics (RAEUME §6): the room's enemies share one coordinator.
	_check(room.enemy_container.has_meta(&"enemy_pack"), "room 1 enemies are coordinated (EnemyPack)")

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

	# 5) Enemy sources (R2): an enemy still in its source cannot be hit, once out it can.
	await _check_source_emergence(room2, player, sword)

	# 6) Talents that react during play (KE6), only with talents=...
	if _talent_paths.has(&"wind"):
		await _check_wind_talents(room2, player)
	if _talent_paths.has(&"ember"):
		await _check_ember_heart(room2, player)

	# 7) Spells (KE7), only with spell=...
	_spell_ids = _read_spell_ids()
	for spell_id in _spell_ids:
		await _check_spell(room2, player, spell_id)

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


func _on_enemy_damaged(enemy, _result, damage) -> void:
	if is_instance_valid(enemy) and damage.amount > 0.0:
		_damaged[enemy.get_instance_id()] = int(_damaged.get(enemy.get_instance_id(), 0)) + 1
	if _talent_effects != null and damage.tags.has(_talent_effects.EMBER_WAVE_TAG):
		_ember_wave_hits += 1
	if damage.tags.has(&"spell"):
		for tag in damage.tags:
			if tag != &"spell":
				_spell_hits[tag] = int(_spell_hits.get(tag, 0)) + 1
				_spell_damage[tag] = damage.amount
	for id in WEAPON_IDS:
		if not damage.tags.has(id):
			continue
		var hits: Dictionary = _hits.get_or_add(id, {})
		var kind := "special" if damage.tags.has(&"special") else "normal"
		hits[kind] = int(hits.get(kind, 0)) + 1
		if damage.tags.has(&"finisher"):
			hits["finisher"] = int(hits.get("finisher", 0)) + 1


## A grave at the player's feet brings a sturdy slime: sword swings during the warning and the
## emergence do nothing (hidden, invulnerable), after it the same swings hurt.
func _check_source_emergence(room: Node, player: Node, sword: Resource) -> void:
	var rules: GDScript = load("res://dungeon/spawning/spawn_source_rules.gd")
	var source: Node2D = load("res://dungeon/environment/spawn/spawn_source.gd").create_floor(0, room.to_local(player.global_position + Vector2(60, 0)))
	room.add_child(source)
	var enemy: Node = load("res://enemies/enemy_base.tscn").instantiate()
	enemy.data = load("res://enemies/data/slime.tres")
	room.enemy_container.add_child(enemy)
	enemy.health.reset(100000.0)
	await _frames(2)
	source.bring(enemy, room, rules.WARN_TIME, 0)
	source.play(0.0, 1)
	_equip_active(player.weapon_controller, sword, 1)
	var id: int = enemy.get_instance_id()
	_damaged.erase(id)
	var hidden_frames := roundi((rules.WARN_TIME + rules.EMERGE_TIME) * 60.0) - 6
	for i in hidden_frames:
		_engage(player, enemy)
		await physics_frame
	_check(int(_damaged.get(id, 0)) == 0, "no hits on an enemy still in its source")
	await _frames(20)
	for i in 60 * 2:
		_engage(player, enemy)
		await physics_frame
	_check(int(_damaged.get(id, 0)) > 0, "hits once it is out (%d)" % int(_damaged.get(id, 0)))
	if is_instance_valid(enemy):
		enemy.queue_free()
	source.queue_free()


## talents=wind,ember,soul from the user arguments (unknown paths are reported and skipped).
func _read_talent_paths() -> Array[StringName]:
	var paths: Array[StringName] = []
	for arg in OS.get_cmdline_user_args():
		if not arg.trim_prefix("--").begins_with("talents="):
			continue
		for name in arg.split("=", true, 1)[1].split(",", false):
			var talent_path := StringName(name.strip_edges())
			_check(_talent_def.PATHS.has(talent_path), "talent path %s exists (wind, ember, soul)" % talent_path)
			if _talent_def.PATHS.has(talent_path) and not paths.has(talent_path):
				paths.append(talent_path)
	return paths


## Fills the chosen paths (rank by rank, every talent to its max) and puts them on the player.
func _apply_talents(player: Node) -> void:
	var tree: Resource = load("res://talents/talent_tree.gd").get_default()
	var state: RefCounted = load("res://talents/talent_state.gd").new()
	for talent_path in _talent_paths:
		for talent in tree.get_path_talents(talent_path):
			for i in talent.max_level:
				state.raise(talent.id, 99, tree)
	for spell in state.get_unlocked_spells(tree):
		state.equip_spell(spell, state.equipped_spells.size(), tree)
	_check(state.is_valid(state.get_spent_points(), tree), "talent distribution is valid (%d points)" % state.get_spent_points())
	var base_speed: float = player.move_speed
	var base_dash: float = player.dash_cooldown
	var base_health: float = player.health.get_max_health()
	_talent_effects.apply_to(player, state, tree)
	await _frames(1)
	var sword: Array[StringName] = [&"sword"]
	var dagger: Array[StringName] = [&"dagger"]
	var staff: Array[StringName] = [&"staff"]
	var stats: RefCounted = _talent_effects.stats_of(player)
	print("TALENTS %s: %d points, speed %.0f -> %.0f, dash cooldown %.2f -> %.2f s, max HP %.0f -> %.0f, sword +%d %%, dagger rate +%d %%, staff +%d %%, spells %s" % [
		",".join(_talent_paths), state.get_spent_points(), base_speed, player.move_speed, base_dash, player.dash_cooldown,
		base_health, player.health.get_max_health(), roundi(_talent_effects.damage_bonus(player, sword) * 100.0),
		roundi(_talent_effects.attack_rate_bonus(player, dagger) * 100.0), roundi(_talent_effects.damage_bonus(player, staff) * 100.0),
		stats.equipped_spells])
	if _talent_paths.has(&"wind"):
		_check(player.move_speed > base_speed, "wind: Leichtfuß makes the player faster")
		_check(player.dash_cooldown < base_dash, "wind: Dash-Training shortens the dash cooldown")
		_check(_talent_effects.attack_rate_bonus(player, dagger) > 0.0, "wind: Flinke Klinge speeds up daggers")
	if _talent_paths.has(&"ember"):
		_check(player.health.get_max_health() > base_health, "ember: Vitalität raises max HP")
		_check(_talent_effects.damage_bonus(player, sword) > 0.0, "ember: Wucht raises sword damage")
		_check(_talent_effects.stagger_multiplier(player) < 1.0, "ember: Standfest shortens stuns")
	if _talent_paths.has(&"soul"):
		_check(_talent_effects.damage_bonus(player, staff) > 0.0, "soul: Stab-Meister raises staff damage")
		_check(stats.spell_slots == 2, "soul: two spell slots")
		_check(stats.equipped_spells.size() == 2, "soul: two spells equipped")
		_check(_talent_effects.spell_cooldown_multiplier(player) < 1.0, "soul: Konzentration shortens spell cooldowns")


## Ausweichkunst and Windläufer with a real dash: bonus right after it, a trail over an enemy.
func _check_wind_talents(room: Node, player: Node) -> void:
	var talents: Node = player.get_node("Talents")
	var trails: Array = []
	talents.wind_trail_spawned.connect(func(trail: Node) -> void: trails.append(trail))
	var enemy: Node = load("res://enemies/enemy_base.tscn").instantiate()
	enemy.data = load("res://enemies/data/slime.tres")
	room.enemy_container.add_child(enemy)
	enemy.global_position = player.get_feet_position() + Vector2(50, 0)
	enemy.health.reset(100000.0)
	enemy.set_physics_process(false)
	player.set_physics_process(true)
	await _frames(2)
	_check(player.try_dash(Vector2.RIGHT), "wind: dash started")
	for i in 30:
		if not trails.is_empty():
			break
		await physics_frame
	var bonus: float = _talent_effects.attack_multiplier(player)
	_check(bonus > 1.0, "wind: Ausweichkunst bonus after the dash (x%.2f)" % bonus)
	_check(trails.size() == 1, "wind: Windläufer left a trail")
	if trails.size() == 1:
		var on_trail: Array = []
		trails[0].enemy_on_trail.connect(func(e: Node) -> void: on_trail.append(e))
		await _frames(12)
		_check(on_trail.has(enemy), "wind: the trail reaches the enemy it crossed")
	player.set_physics_process(false)
	enemy.queue_free()


## Glutherz with a real hit at 2 HP: the wave hits a dummy next to the player.
func _check_ember_heart(room: Node, player: Node) -> void:
	var dummies := _spawn_dummies(room, player.global_position)
	await _frames(3)
	player.health.reset(2.0)
	player.shield.absorb(player.shield.get_shield())
	# Player.INVULNERABLE_HIT and INVULNERABLE_DASH: the hand-driven player keeps old I-frames.
	player.hurtbox.set_invulnerable(&"hit", false)
	player.hurtbox.set_invulnerable(&"dash", false)
	_ember_wave_hits = 0
	var hit: RefCounted = load("res://components/combat/damage_data.gd").new()
	hit.amount = 0.5
	hit.hit_id = hit.next_hit_id()
	player.hurtbox.receive_hit(hit)
	await _frames(3)
	_check(player.health.get_health() < 2.0, "ember: the hit left the player below 2 HP (%.1f)" % player.health.get_health())
	_check(_ember_wave_hits > 0, "ember: Glutherz wave hit %d enemies" % _ember_wave_hits)
	player.health.reset(5000.0)
	for dummy in dummies:
		if is_instance_valid(dummy):
			dummy.queue_free()


## spell=<id>[,<id>] or spell=all from the user arguments (unknown ids are reported and skipped).
func _read_spell_ids() -> Array[StringName]:
	var book: GDScript = load("res://spells/spell_book.gd")
	var ids: Array[StringName] = []
	for arg in OS.get_cmdline_user_args():
		if not arg.trim_prefix("--").begins_with("spell="):
			continue
		for name in arg.split("=", true, 1)[1].split(",", false):
			var wanted := name.strip_edges()
			var picked: Array[StringName] = []
			if wanted == "all":
				picked.assign(book.IDS)
			else:
				_check(book.IDS.has(StringName(wanted)), "spell %s exists (%s)" % [wanted, ", ".join(book.IDS)])
				if book.IDS.has(StringName(wanted)):
					picked.append(StringName(wanted))
			for id in picked:
				if not ids.has(id):
					ids.append(id)
	return ids


## Casts spell_id next to three dummies and checks its effect, the cooldown and Flint's reaction.
func _check_spell(room: Node, player: Node, spell_id: StringName) -> void:
	var spells: Node = load("res://spells/player_spells.gd").attach_to(player)
	var data: Resource = load("res://spells/spell_book.gd").get_spell(spell_id)
	spells.set_loadout([spell_id] as Array[StringName])
	spells.reset_cooldowns()
	player.health.reset(5000.0)
	player.health.take_damage(10.0)
	player.shield.absorb(player.shield.get_shield())
	var dummies := _spawn_dummies(room, player.global_position)
	await _frames(3)
	# A dummy's hit may have stunned the player a moment ago: wait until it may cast (at most 2 s).
	# Step 2 turns the player's physics off; a stun only runs out while it is on.
	var was_processing := player.is_physics_processing()
	player.set_physics_process(true)
	for i in 120:
		if spells.can_cast():
			break
		await physics_frame
	player.set_physics_process(was_processing)
	_spell_hits.erase(spell_id)
	var health_before: float = player.health.get_health()
	var shield_before: float = player.shield.get_shield()
	var casts := [0]
	spells.spell_cast.connect(func(_id: StringName, _slot: int, _aim: Vector2, _cooldown: float) -> void: casts[0] += 1)
	var through_input := _press_cast(player, spells)
	_check(casts[0] == 1, "%s: cast %s (alive %s, stunned %s, locked %s, falling %s)" % [spell_id,
		"through the input object" if through_input else "through PlayerSpells (cast action not wired yet)",
		player.is_alive(), player.is_stunned(), player.is_input_locked(), player.is_falling()])
	var flint: Node = player.get_node_or_null("Flint")
	if flint != null:
		flint._process(1.0 / 60.0)
		var cast_mood: int = load("res://companions/flint/flint_mood.gd").Mood.CAST
		_check(flint.get_mood() == cast_mood, "%s: Flint casts it visibly (mood CAST)" % spell_id)
	match int(data.effect):
		0:
			var blinded := 0
			for dummy in dummies:
				if dummy.has_method(&"is_blinded") and dummy.call(&"is_blinded") or dummy.is_slowed():
					blinded += 1
			_check(blinded == dummies.size(), "%s: %d of %d enemies in reach blinded" % [spell_id, blinded, dummies.size()])
		1:
			_check(player.shield.get_shield() - shield_before >= data.amount, "%s: +%.1f shield" % [spell_id, player.shield.get_shield() - shield_before])
		2:
			_check(int(_spell_hits.get(spell_id, 0)) == dummies.size(), "%s: hit %d enemies for %.2f each" % [spell_id, int(_spell_hits.get(spell_id, 0)), float(_spell_damage.get(spell_id, 0.0))])
		3:
			for i in 60 * 3:
				if int(_spell_hits.get(spell_id, 0)) >= data.count:
					break
				await physics_frame
			_check(int(_spell_hits.get(spell_id, 0)) == data.count, "%s: %d of %d wisps hit for %.2f each" % [spell_id, int(_spell_hits.get(spell_id, 0)), data.count, float(_spell_damage.get(spell_id, 0.0))])
		4:
			_check(player.health.get_health() - health_before >= data.amount, "%s: healed %.1f HP" % [spell_id, player.health.get_health() - health_before])
	var cooldown: float = spells.get_cooldown_left(0)
	_check(cooldown > 0.0 and not spells.press(0), "%s: cooling down (%.1f s)" % [spell_id, cooldown])
	for dummy in dummies:
		if is_instance_valid(dummy):
			dummy.queue_free()
	await _frames(2)


## A press of the cast button: through the player's input object when the action is wired (MP1),
## else PlayerSpells.press. Returns whether the input object was used.
func _press_cast(player: Node, spells: Node) -> bool:
	var action: StringName = spells.ACTION
	if not load("res://player/input/player_input.gd").ACTIONS.has(action):
		spells.press(0)
		return false
	var old_input: Variant = player.input
	var remote: RefCounted = load("res://player/input/remote_input.gd").new()
	player.input = remote
	remote.tap(action)
	remote.poll(player)
	spells.read_input(remote)
	player.input = old_input
	return true


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

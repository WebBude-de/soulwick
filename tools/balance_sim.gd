extends SceneTree
## Balance simulation: a bot plays real runs headless (real rooms, enemies, upgrades, shops) and
## records per room: clear time, damage taken (HP + shield), HP/shield afterwards, upgrades, deaths.
## The bot is NOT invincible. It sees every telegraph (no darkness), but reacts only with a
## probability (skill) and after a human-like reaction delay.
##
## Usage (from the project root):
##   godot --headless --fixed-fps 60 --path . -s tools/balance_sim.gd -- runs=3 policy=sword
## Arguments (key=value):
##   runs=3            number of runs in this process
##   policy=sword      sword | bow | staff  (bow/staff replace the starting sword)
##   pick=greedy       greedy | random | tank  (upgrade choice; tank = shield/heal first)
##   max_rooms=150     abort the run after this room
##   skill=0.8         chance to react to a telegraph / projectile (0..1)
##   reaction=0.22     reaction delay in seconds
##   seed=0            0 = random
##   out=<path>        CSV with one row per room (default user://balance_sim_<policy>.csv)
##   quiet=1           only print run summaries
##   branch=first      first | safe | nest  (way of a branch room, D-105: the first door, the safe
##                     way or the elite nest / unknown variant when offered)
##   dseed=1           with seed=N != 0 also fix the dungeon seed (run r gets N * 1000 + r + 1), so the
##                     same rooms come again; dseed=0 keeps the dungeon random
##   hazards=0         1 = avoid static hazards as danger zones: toxic puddles always, lava cracks
##                     while warning or active (spike traps are always avoided)
##   falls=0           1 = abysses are real for the bot: it runs the player's fall logic (falling, pit
##                     damage) and keeps its feet off pit tiles while walking and dashing
##   nav=0             1 = walk around walls (and with falls=1 over bridges around abysses) along the
##                     room's navigation path when the target is out of sight
##   smart=0           1 = go for summoning rifts first when no enemy is close
##   god_until=0       N > 0 = invulnerable up to room N, normal from room N + 1 (boss tests)
##   bosshits=0        1 = print damage taken in boss rooms by boss state/action (BOSSHITS line)
##   debug=0           1 = every hit, 2 = position trace, 3 = zone trace, 5 = rift rooms
##   audio=0           0 = no sound effects and no music (default). The bot runs far faster than
##                     real time; Godot frees replaced audio bus data two frames later while its
##                     mixer thread may still read it, so many positional sounds at a high frame
##                     rate crashed about every second to tenth process (segfault in
##                     AudioServer::_mix_step). 1 = keep the sound (crash diagnosis only)
##   max_fps=0         cap the frame rate (0 = unlimited)
## Recommended realistic bot: hazards=1 falls=1 nav=1 (off by default to stay comparable with
## older measurements).
## Death cause: the cause column / SUMMARY keep the short source (enemy id, trap, pit, explosion);
## cause_detail adds trap kind (trap:spike|lava|poison|trial), *elite / *champ, and desc the room
## (kind, variant, wager/ambush/branch, encounter group, special type, dark, template).
## Runtime experiments (shared files stay untouched, values are changed in memory only):
##   set.hp_growth=1.22      enemy HP factor per 5-room block (replaces EnemyScaling value)
##   set.dmg_growth=1.16     enemy damage factor per block
##   set.hp_mult=1.0         flat factor on all non-boss enemy HP
##   set.dmg_mult=1.0        flat factor on all enemy damage
##   set.champ_hp=3.0        miniboss HP factor (replaces EnemyScaling.MINIBOSS_HEALTH_FACTOR)
##   set.boss_hp=1.0         flat factor on boss HP
##   set.waves=20:2,45:3     waves per normal combat room from room X (replaces RoomSequence)
##   set.extra=10:1,40:2     extra enemies per wave from room X
##   set.speed_growth=0.02   enemy move speed gain per block
##   set.speed_max=1.4       cap of that speed factor
##   set.player_hp=6         player max HP
##   set.hp_per_boss=0       extra player max HP after every boss (+ heal by that amount)
##   set.softcap=15          shield softcap threshold (emulated on top of ShieldComponent)
##   set.softcap_factor=0.5  share of a gain above the softcap that counts
##   set.fix_hitbox=1        move melee hitboxes during the telegraph (phantom-hit bug workaround)
##   upg.<id>=<value>        upgrade value per stack, e.g. upg.shield_boost=3
##   wpn.<id>.<field>=<v>    weapon field, e.g. wpn.sword.base_damage=11
##   enemy.<id>.<field>=<v>  enemy data field, e.g. enemy.skeleton.damage=1.5
##   econ.<field>=<v>        economy config field, e.g. econ.shield_amount=2
##   vt.chance=0.9           room variant chance (variant_table.tres)
##   vt.wager=0              wager altar chance
##   vt.only=<variant id>    only this variant, in every biome
## Classes are accessed dynamically: this script is compiled before autoloads exist.

const ROOM_TIMEOUT := 240.0
const POST_CLEAR_TIME := 2.2
const LOOKAHEAD := 0.22
const PLAYER_HURT_RADIUS := 13.0
const DANGER_MARGIN := 8.0
const DIRECTIONS := 16

var opt := {
	"runs": 3, "policy": "sword", "pick": "greedy", "max_rooms": 150, "skill": 0.8,
	"reaction": 0.22, "seed": 0, "out": "", "quiet": 0, "debug": 0, "branch": "first",
	"dseed": 1, "hazards": 0, "falls": 0, "nav": 0, "smart": 0, "god_until": 0, "bosshits": 0,
	"audio": 0, "max_fps": 0,
}
var ovr := {}
var res_overrides: Array = []

var rng := RandomNumberGenerator.new()
var controller: Node = null
var dungeon: Node = null
var player: Node = null
var upgrades: Node = null

# Enum values, resolved at runtime from the scripts.
var ST_TELEGRAPH := 2
var ST_ATTACK := 3
var ST_CHARGE := 4
var ST_LEAP := 5
var ST_RECOVER := 6
var AC_NORMAL := 0
var AC_VOLLEY := 1
var AC_SPECIAL := 2
var SP_CHARGE := 1
var SP_LEAP := 2
var SP_SELF_DESTRUCT := 4
var KIND_MELEE := 0
var RT_SPECIAL := 2
var ROOM_CLEARED := 2
var scaling: Script = null

var _time := 0.0
var _seen := {}
var _last_dir := Vector2.ZERO
var _rec := {}
var _last_hit_source := ""
var _stall_time := 0.0
var _last_enemy_hp := 0.0
var _aggressive_left := 0.0
var _traps: Array = []
var _hazards: Array = []
var _shield_prev := 0.0
var _stuck_pause := 0
var _rows: Array[String] = []
var _summaries: Array = []
var _last_hit_detail := ""
var _pending_seed := 0
var _nav_cache := {"t": -1.0, "wp": Vector2.INF, "path": PackedVector2Array()}
var _vt_keep: Resource = null
var _boss_hits := {}


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)
	node_added.connect(_on_node_added)


## Fixed dungeon seed (dseed=1): set on the DungeonManager before its _ready builds the dungeon.
func _on_node_added(node: Node) -> void:
	if _pending_seed == 0 or node.get_script() == null:
		return
	if node.get_script().get_global_name() == &"DungeonManager":
		node.seed_value = _pending_seed
		_pending_seed = 0


func _run() -> void:
	_parse_args()
	if int(opt.seed) != 0:
		rng.seed = int(opt.seed)
		seed(int(opt.seed))
	else:
		rng.randomize()
	_apply_resource_overrides()
	_apply_variant_overrides()
	# Buttons are found by their German texts; English is the default language (D-111).
	TranslationServer.set_locale("de")
	var save_manager := root.get_node("SaveManager")
	var save_path := "user://balance_sim_%d.cfg" % OS.get_process_id()
	save_manager.save_path = save_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	save_manager.load_game()
	# Own settings in German: the real settings.cfg may say English and would win at world start.
	save_manager.settings_path = "user://balance_sim_settings.cfg"
	save_manager.load_settings()
	save_manager.set_option(&"language", "de")
	if int(opt.max_fps) > 0:
		Engine.max_fps = int(opt.max_fps)
	if int(opt.audio) == 0:
		_silence_sfx()

	change_scene_to_file("res://scenes/game.tscn")
	await _frames(20)
	if int(opt.audio) == 0:
		_silence_music()
	controller = current_scene.get_node("WorldController")
	_load_enums()
	_rows.append("run,policy,pick,room,type,enemies,time,hp_dmg,shield_dmg,hits,dashes,hp,max_hp,shield,upgrades,gold,dead,timeout,cause,cause_detail,desc,trap_dmg,pit_dmg,expl_dmg,enemy_dmg")
	for run in int(opt.runs):
		var summary: Dictionary = await _play_run(run)
		_summaries.append(summary)
		print("RUN %d %s/%s: reached room %d, %s%s, upgrades %d, gold %d, wall time %.0fs%s" % [
			run, opt.policy, opt.pick, summary.room, "died" if summary.dead else "survived",
			(" (" + summary.cause + ")") if summary.dead else "", summary.upgrades, summary.gold, summary.wall,
			(" | death: %s in %s" % [summary.detail, summary.where]) if summary.dead else ""])
	_write_csv()
	_print_overview()
	if int(opt.bosshits) == 1:
		print("BOSSHITS ", JSON.stringify(_boss_hits))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	quit(0)


# --- Setup ---

## No sound effects (audio=0): every known sound is cached as "missing", so Sfx creates no players.
func _silence_sfx() -> void:
	var sfx: Script = load("res://components/audio/sfx.gd")
	var cache: Dictionary = sfx.get(&"_cache")
	var dir := DirAccess.open(sfx.SFX_DIR)
	if cache == null or dir == null:
		push_warning("balance_sim: could not silence the sound effects")
		return
	for file in dir.get_files():
		var name := file.trim_suffix(".import").trim_suffix(".remap")
		if name.get_extension() == "wav":
			cache[StringName(name.get_basename())] = null


## No music (audio=0): the MusicPlayer of game.tscn goes; its group calls then reach nobody.
func _silence_music() -> void:
	var music := current_scene.get_node_or_null(^"MusicPlayer")
	if music != null:
		music.queue_free()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		if parts.size() != 2:
			continue
		var key: String = parts[0]
		var value: String = parts[1]
		if key.begins_with("set."):
			ovr[key.substr(4)] = value
		elif key.begins_with("upg.") or key.begins_with("wpn.") or key.begins_with("enemy.") or key.begins_with("econ."):
			res_overrides.append([key, value])
		elif opt.has(key):
			opt[key] = value
	opt.runs = int(opt.runs)
	opt.max_rooms = int(opt.max_rooms)
	opt.skill = float(opt.skill)
	opt.reaction = float(opt.reaction)
	opt.quiet = int(opt.quiet)


func _load_enums() -> void:
	var enemy_script: Script = load("res://enemies/enemy_base.gd")
	var consts := enemy_script.get_script_constant_map()
	var state: Dictionary = consts["State"]
	ST_TELEGRAPH = state["TELEGRAPH"]
	ST_ATTACK = state["ATTACK"]
	ST_CHARGE = state["CHARGE"]
	ST_LEAP = state["LEAP"]
	ST_RECOVER = state["RECOVER"]
	var action: Dictionary = consts["Action"]
	AC_NORMAL = action["NORMAL"]
	AC_VOLLEY = action["VOLLEY"]
	AC_SPECIAL = action["SPECIAL"]
	var data_consts := (load("res://enemies/enemy_data.gd") as Script).get_script_constant_map()
	var special: Dictionary = data_consts["Special"]
	SP_CHARGE = special["SHIELD_CHARGE"]
	SP_LEAP = special["LEAP_SLAM"]
	SP_SELF_DESTRUCT = special["SELF_DESTRUCT"]
	KIND_MELEE = (data_consts["AttackKind"] as Dictionary)["MELEE"]
	var seq_consts := (load("res://dungeon/room_sequence.gd") as Script).get_script_constant_map()
	RT_SPECIAL = (seq_consts["RoomType"] as Dictionary)["SPECIAL"]
	var room_consts := (load("res://dungeon/rooms/room_controller.gd") as Script).get_script_constant_map()
	ROOM_CLEARED = (room_consts["State"] as Dictionary)["CLEARED"]
	scaling = load("res://enemies/enemy_scaling.gd")


## Changes cached resources in memory; every later load() returns the same instance.
func _apply_resource_overrides() -> void:
	for entry in res_overrides:
		var key: String = entry[0]
		var value := float(entry[1])
		var parts := key.split(".")
		var resource: Resource = null
		var field := ""
		match parts[0]:
			"upg":
				resource = load("res://upgrades/data/%s.tres" % parts[1])
				field = "value" if parts.size() == 2 else parts[2]
			"wpn":
				resource = load("res://weapons/data/%s.tres" % parts[1])
				field = parts[2]
			"enemy":
				resource = load("res://enemies/data/%s.tres" % parts[1])
				field = parts[2]
			"econ":
				resource = load("res://economy/data/economy_config.tres")
				field = parts[1]
		if resource == null or not field in resource:
			push_error("balance_sim: unknown override " + key)
			continue
		var old = resource.get(field)
		resource.set(field, int(value) if typeof(old) == TYPE_INT else value)
		print("override %s: %s -> %s" % [key, old, resource.get(field)])
		# Keep the resource alive so the cache keeps the changed instance.
		entry.append(resource)


# --- One run ---

func _play_run(run: int) -> Dictionary:
	var wall_start := Time.get_ticks_msec()
	if int(opt.dseed) == 1 and int(opt.seed) != 0:
		_pending_seed = int(opt.seed) * 1000 + run + 1
	controller.enter_dungeon()
	await _frames(20)
	dungeon = controller.get_world()
	player = controller.get_player()
	upgrades = dungeon.get_node("UpgradeManager")
	player.set_physics_process(false)
	if ovr.has("player_hp"):
		player.health.reset(float(ovr.player_hp))
	_equip_policy_weapon()
	player.hurtbox.hit_received.connect(_on_player_hit)
	_shield_prev = 0.0
	if ovr.has("softcap") or ovr.has("softcap_factor"):
		player.shield.shield_changed.connect(_on_shield_changed)
	_seen.clear()

	var summary := {"room": 1, "dead": false, "cause": "", "upgrades": 0, "gold": 0, "wall": 0.0, "detail": "", "where": ""}
	var index := 1
	while true:
		var room: Node = dungeon.get_room(index)
		if room == null:
			push_error("balance_sim: room %d missing" % index)
			break
		if index > 1:
			player.global_position = room.get_player_start()
		for i in 120:
			await physics_frame
			if dungeon.get_active_room_index() >= index:
				break
		if int(opt.get("god_until", 0)) > 0:
			player.hurtbox.set_invulnerable(&"bal_god", index <= int(opt.god_until))
		_begin_record(room)
		if room.room_type == RT_SPECIAL:
			await _use_special(room)
		else:
			await _fight_room(room)
		if player.is_alive():
			await _after_clear(room)
		_end_record(run, room)
		summary.room = index
		if room.room_type == 4 and player.is_alive() and float(ovr.get("hp_per_boss", 0.0)) > 0.0:
			var bonus := float(ovr.hp_per_boss)
			player.health.max_health += bonus
			player.health.heal(bonus)
		if not player.is_alive():
			summary.dead = true
			summary.cause = _last_hit_source
			summary.detail = _last_hit_detail
			summary.where = _room_desc(room)
			break
		if index >= int(opt.max_rooms):
			break
		# After a boss the campfire (A6, not a room) has to be entered before room n+1 exists.
		var campfire: Node = dungeon.get_campfire(index)
		if campfire != null:
			player.global_position = campfire.get_player_start()
			for i in 120:
				await physics_frame
				if dungeon.get_active_slot() == campfire.slot_index:
					break
		index += 1
	summary.upgrades = _upgrade_count()
	summary.gold = root.get_node("RunManager").get_run_gold()
	if not summary.dead:
		dungeon.end_run(1)  # RunManager.EndReason.ABORT
	await _return_to_village()
	summary.wall = (Time.get_ticks_msec() - wall_start) / 1000.0
	return summary


func _equip_policy_weapon() -> void:
	var path := ""
	match String(opt.policy):
		"bow":
			path = "res://weapons/data/bow.tres"
		"staff":
			path = "res://weapons/data/staff.tres"
	if path.is_empty():
		return
	var weapon: Resource = load(path)
	player.weapon_controller.equip_weapon(weapon, 0)


func _fight_room(room: Node) -> void:
	_stall_time = 0.0
	_last_enemy_hp = -1.0
	_aggressive_left = 0.0
	_traps = _find_by_class(room, &"SpikeTrap")
	_hazards = _find_by_class(room, &"ToxicPuddle") + _find_by_class(room, &"LavaCrack")
	var started := _time
	while room.state != ROOM_CLEARED:
		await physics_frame
		if _handle_pause():
			continue
		_bot_step(room)
		if not player.is_alive():
			return
		if _time - started > ROOM_TIMEOUT:
			_rec.timeout = 1
			for enemy in _alive(room):
				enemy.health.take_damage(INF)


func _after_clear(room: Node) -> void:
	var until := _time + POST_CLEAR_TIME
	while _time < until or paused or not room._exit_door.is_open:
		await physics_frame
		if _handle_pause():
			continue
		# Branch room (A10, D-105): the doors wait until the group walks up to one; the bot decides
		# through the room's decision hook instead of walking there.
		if room.has_method(&"is_branch_room") and room.is_branch_room() and room.get_chosen_branch() < 0 \
				and room.get_branch_choice() != null and room.get_branch_choice().is_offered:
			room.choose_branch(_pick_branch(room))
		_bot_step(room)
		if not player.is_alive():
			return
		if _time > until + 30.0:
			push_error("balance_sim: room %d exit never opened" % room.room_index)
			return


## Way of a branch room by option branch: the first door, the safe way or the risky one.
func _pick_branch(room: Node) -> int:
	var options: Array = room.branch_options
	var wanted := String(opt.branch)
	for i in options.size():
		var safe: bool = int(options[i].kind) == 0
		if (wanted == "safe" and safe) or (wanted == "nest" and not safe):
			return i
	return 0


func _use_special(room: Node) -> void:
	await _frames(6)
	var context: Object = dungeon.context
	for content in room.get_children():
		if content.get(&"_offers") != null:
			_shop(content.get(&"_offers"), context)
		for child in content.get_children():
			if not _is_class(child, &"Interactable") or not child.enabled:
				continue
			var prompt: String = child.prompt
			if prompt.begins_with("Aus dem Brunnen") and player.health.get_health() < player.health.get_max_health():
				child.interact(player)
				_rec.fountain = 1
			elif prompt.begins_with("Upgrade wählen"):
				child.interact(player)
	await _frames(4)
	for i in 200:
		await physics_frame
		if not _handle_pause() and not paused:
			break


## Buys what a sensible player would: missing HP first, then the best upgrade, then shield.
func _shop(offers: Array, context: Object) -> void:
	var economy: Object = context.economy
	var bought := true
	while bought:
		bought = false
		var best: Object = null
		var best_score := 0.0
		for offer in offers:
			if offer.sold or not economy.can_purchase(offer, player, upgrades):
				continue
			var score := 0.0
			match int(offer.kind):
				0:  # upgrade
					score = 5.0 + _upgrade_score(offer.upgrade)
				2:  # heal
					var missing: float = player.health.get_max_health() - player.health.get_health()
					score = 40.0 if missing >= 2.0 else (8.0 if missing > 0.0 else 0.0)
				3:  # shield
					score = 6.0 if String(opt.pick) != "tank" else 30.0
			if score > best_score:
				best_score = score
				best = offer
		if best != null and economy.try_purchase(best, player, upgrades):
			bought = true
			_rec.bought += 1


# --- Bot ---

func _bot_step(room: Node) -> void:
	var dt := 1.0 / Engine.physics_ticks_per_second
	_time += dt
	if player.has_method(&"_tick_timers"):
		player._tick_timers(dt)
	if int(opt.falls) == 1:
		player.fall.update(dt)
		if player.fall.is_falling():
			return
	if not player.is_alive():
		return
	if player.is_stunned():
		player.velocity = Vector2.ZERO
		player.move_and_slide()
		return
	var enemies := _alive(room)
	_apply_enemy_overrides(room, enemies)
	_check_stall(enemies, dt)
	var zones := _collect_zones(room, enemies)
	var target: Node2D = _pick_target(enemies)
	var pos: Vector2 = player.global_position
	var arena: Rect2 = room.get_arena()

	var best_dir := Vector2.ZERO
	var best_cost := INF
	var step: float = player.move_speed * LOOKAHEAD
	var waypoint := _nav_waypoint(room, pos, target) if int(opt.nav) == 1 else Vector2.INF
	for i in DIRECTIONS + 1:
		var dir := Vector2.ZERO if i == DIRECTIONS else Vector2.from_angle(TAU * i / DIRECTIONS)
		if dir != Vector2.ZERO and player.test_move(player.global_transform, dir * step):
			continue
		var candidate := pos + dir * step
		# Sample the path too, so the bot does not plan to step "over" a danger zone.
		var danger := maxf(_zone_cost(candidate, zones), maxf(_zone_cost(pos + dir * step * 0.5, zones), _zone_cost(pos + dir * 6.0, zones)))
		var goal_cost := _objective(candidate, target, enemies, arena) if waypoint == Vector2.INF else candidate.distance_to(waypoint) * 2.0
		var cost := danger + goal_cost + _pit_cost(candidate) + _pit_cost(pos + dir * 10.0)
		if dir != Vector2.ZERO and dir.dot(_last_dir) > 0.9:
			cost -= 4.0
		if dir != Vector2.ZERO and target == null:
			cost += 5.0
		if cost < best_cost:
			best_cost = cost
			best_dir = dir
	_last_dir = best_dir
	if int(opt.debug) == 3 and not zones.is_empty():
		var parts: Array[String] = []
		for zone in zones:
			parts.append("t=%.2f d=%.0f" % [zone.t, _depth(pos, zone)])
		print("    trace %.2f pos=%s dir=%s cost=%.0f dashcd=%.2f %s" % [_time, pos.round(), best_dir.round(), best_cost, player.get_dash_cooldown_left(), " | ".join(parts)])
	if int(opt.debug) == 5 and Engine.get_physics_frames() % 60 == 0 and String(room.get_variant_id()) == "rifts":
		var rifts_hp: Array[String] = []
		for enemy in enemies:
			if String(enemy.data.id) == "summoning_rift":
				rifts_hp.append("%.0f@%s" % [enemy.health.get_health(), enemy.global_position.round()])
		print("    rift r%d t=%.0f pos=%s target=%s alive=%d rifts=%s" % [room.room_index, _time, pos.round(), (String(target.data.id) + "@" + str(target.global_position.round())) if target != null else "-", enemies.size(), rifts_hp])
	if int(opt.debug) == 2 and Engine.get_physics_frames() % 30 == 0:
		var blocked := 0
		for i in DIRECTIONS:
			if player.test_move(player.global_transform, Vector2.from_angle(TAU * i / DIRECTIONS) * step):
				blocked += 1
		print("    dbg pos=%s dir=%s cost=%.1f blocked=%d zones=%d target=%s" % [pos, best_dir, best_cost, blocked, zones.size(), target.global_position if target != null else Vector2.INF])

	# Dash with I-frames when a hit is imminent and walking does not get us out in time.
	if player.can_dash() and not player.is_dashing():
		var imminent := _imminent_cost(pos, zones)
		if imminent > 0.0 and _imminent_cost(pos + best_dir * step, zones) > 0.0:
			var dash_dir := best_dir
			var dash_best := INF
			for i in DIRECTIONS:
				var dir := Vector2.from_angle(TAU * i / DIRECTIONS)
				var reach: float = player.dash_speed * player.dash_duration
				if player.test_move(player.global_transform, dir * reach * 0.5):
					continue
				var c := _zone_cost(pos + dir * reach, zones) + _objective(pos + dir * reach, target, enemies, arena) * 0.1 + _pit_cost(pos + dir * reach)
				if c < dash_best:
					dash_best = c
					dash_dir = dir
			if dash_dir == Vector2.ZERO:
				dash_dir = Vector2.from_angle(rng.randf() * TAU)
			player._start_dash(dash_dir, dash_dir)
			_rec.dashes += 1

	if player.is_dashing():
		player.velocity = player._dash_direction * player.dash_speed
	else:
		player.velocity = best_dir * player.move_speed
	player.move_and_slide()

	if target == null or player.is_dashing():
		return
	var weapon: Resource = player.weapon_controller.get_active_weapon()
	var to_target: Vector2 = target.global_position - player.weapon_controller.global_position
	var distance := to_target.length()
	var aim := to_target.normalized()
	var melee: bool = weapon.is_melee()
	var can_attack := false
	if melee:
		can_attack = distance <= weapon.attack_range + _enemy_radius(target) * 0.6
	else:
		var speed: float = player.weapon_controller.get_effective_projectile_speed(weapon)
		var lead: Vector2 = target.velocity * (distance / maxf(speed, 1.0)) * 0.5
		aim = (to_target + lead).normalized()
		can_attack = distance <= weapon.attack_range * 0.92 and _has_line_of_sight(pos, target.global_position)
	player.set(&"_aim", aim)
	player.weapon_controller.aim_direction = aim
	if can_attack:
		player.weapon_controller.request_attack()


func _objective(candidate: Vector2, target: Node2D, enemies: Array, arena: Rect2) -> float:
	if target == null:
		return 0.0
	var weapon: Resource = player.weapon_controller.get_active_weapon()
	var d_target := candidate.distance_to(target.global_position)
	var cost := 0.0
	if weapon.is_melee() or _aggressive_left > 0.0:
		# Poke from just outside the enemy's own trigger range when the sword reaches that far.
		var wanted := 42.0
		if weapon.is_melee() and _aggressive_left <= 0.0:
			var reach: float = weapon.attack_range + _enemy_radius(target) * 0.6
			wanted = clampf(target.data.attack_range + 16.0, 42.0, reach - 8.0)
		cost += absf(d_target - wanted) * 1.0
		for enemy in enemies:
			if enemy != target and candidate.distance_to(enemy.global_position) < 70.0:
				cost += 12.0
		return cost
	var keep_min := 230.0 if weapon.weapon_type == 1 else 200.0
	var keep_max := 360.0 if weapon.weapon_type == 1 else 300.0
	var nearest := INF
	for enemy in enemies:
		nearest = minf(nearest, candidate.distance_to(enemy.global_position))
	cost += maxf(0.0, keep_min - nearest) * 3.0
	cost += maxf(0.0, d_target - keep_max) * 1.2
	var edge := minf(minf(candidate.x - arena.position.x, arena.end.x - candidate.x), minf(candidate.y - arena.position.y, arena.end.y - candidate.y))
	cost += maxf(0.0, 110.0 - edge) * 2.5
	if not _has_line_of_sight(candidate, target.global_position):
		cost += 60.0
	return cost


func _pick_target(enemies: Array) -> Node2D:
	var best: Node2D = null
	var best_distance := INF
	if int(opt.get("smart", 0)) == 1:
		var close_enemy := false
		var rift: Node2D = null
		var rift_d := INF
		for enemy in enemies:
			var dd: float = player.global_position.distance_to(enemy.global_position)
			if String(enemy.data.id) == "summoning_rift":
				if dd < rift_d:
					rift_d = dd
					rift = enemy
			elif dd < 90.0:
				close_enemy = true
		if rift != null and not close_enemy:
			return rift
	for enemy in enemies:
		var d: float = player.global_position.distance_to(enemy.global_position)
		if d < best_distance:
			best_distance = d
			best = enemy
	return best


## Danger zones the bot noticed: circles {c, r, t} and segments {a, b, w, t}; t = time until it hits.
func _collect_zones(room: Node, enemies: Array) -> Array:
	var zones: Array = []
	var margin := PLAYER_HURT_RADIUS + DANGER_MARGIN
	for enemy in enemies:
		var state: int = enemy._state
		var data: Resource = enemy.data
		if state == ST_TELEGRAPH:
			if not _noticed("%d:%d" % [enemy.get_instance_id(), enemy._attack_count]):
				continue
			var left: float = enemy._state_time_left
			var dir: Vector2 = enemy._attack_direction
			var action: int = enemy._action
			if action == AC_NORMAL:
				if data.attack_kind == KIND_MELEE:
					zones.append({"c": enemy.global_position + dir * data.attack_reach, "r": data.attack_radius + margin, "t": left})
				else:
					var width: float = data.projectile_radius + margin + (data.projectile_count - 1) * 18.0
					zones.append({"a": enemy.global_position, "b": enemy.global_position + dir * data.attack_range * 1.5, "w": width, "t": left + 0.2})
			elif action == AC_VOLLEY:
				# A ring is dense close to the shooter: get out of that radius (or dash through it).
				var count: int = data.volley_count + 6 * int(enemy._boss_tier)
				var ring: float = count * (PLAYER_HURT_RADIUS * 2.0 + data.projectile_radius * 2.0) / TAU + 10.0
				zones.append({"c": enemy.global_position, "r": maxf(ring, _enemy_radius(enemy) + 40.0) + margin, "t": left + 0.1})
			elif action == AC_SPECIAL:
				var special := int(data.special)
				if special == SP_CHARGE:
					zones.append({"a": enemy.global_position, "b": enemy.global_position + dir * (data.charge_speed * data.charge_time + data.attack_reach), "w": data.attack_radius + margin, "t": left})
				elif special == SP_LEAP:
					zones.append({"c": enemy._leap_target, "r": data.blast_radius + margin, "t": left + 0.5})
				elif special == SP_SELF_DESTRUCT:
					zones.append({"c": enemy.global_position, "r": data.blast_radius + margin + 20.0, "t": left})
		elif state == ST_CHARGE:
			var dir2: Vector2 = enemy._attack_direction
			zones.append({"a": enemy.global_position, "b": enemy.global_position + dir2 * data.charge_speed * maxf(0.05, enemy._state_time_left), "w": data.attack_radius + margin, "t": 0.0})
		elif state == ST_LEAP:
			zones.append({"c": enemy._leap_target, "r": data.blast_radius + margin, "t": enemy._state_time_left})
		elif state == ST_ATTACK and data.attack_kind == KIND_MELEE:
			zones.append({"c": enemy._attack_hitbox.global_position, "r": data.attack_radius + margin, "t": 0.0})
	var pos: Vector2 = player.global_position
	for child in room.enemy_container.get_children():
		if _is_class(child, &"Projectile"):
			if child._finished or (int(child.collision_mask) & 8) == 0:
				continue
			var rel: Vector2 = pos - child.global_position
			var along: float = rel.dot(child.direction)
			if along < -20.0 or along > child.speed * 0.9:
				continue
			if not _noticed("p%d" % child.get_instance_id()):
				continue
			var width2: float = child.collision_radius + margin
			zones.append({"a": child.global_position, "b": child.global_position + child.direction * child.speed * 0.9, "w": width2, "t": maxf(0.0, along) / maxf(child.speed, 1.0)})
		elif _is_class(child, &"Blast"):
			if child._time < child.delay and _noticed("b%d" % child.get_instance_id()):
				zones.append({"c": child.global_position, "r": child.radius + margin, "t": child.delay - child._time})
	if int(opt.hazards) == 1:
		for hazard in _hazards:
			if not is_instance_valid(hazard):
				continue
			if _is_class(hazard, &"ToxicPuddle"):
				zones.append({"c": hazard.global_position, "r": 44.0 * 0.85 + PLAYER_HURT_RADIUS, "t": 0.5})
			elif int(hazard._phase) != 0:
				zones.append({"c": hazard.global_position, "r": 34.0 + PLAYER_HURT_RADIUS, "t": hazard._time_left if int(hazard._phase) == 1 else 0.0})
	for trap in _traps:
		if is_instance_valid(trap) and int(trap._phase) != 0:
			zones.append({"c": trap.global_position, "r": 26.0 * 1.3 + PLAYER_HURT_RADIUS, "t": trap._time_left if int(trap._phase) == 1 else 0.0})
	return zones


## A threat is noticed with probability `skill` and only after the reaction delay.
func _noticed(key: String) -> bool:
	if not _seen.has(key):
		_seen[key] = [_time, rng.randf() < float(opt.skill)]
		if _seen.size() > 4000:
			_seen.clear()
			_seen[key] = [_time, rng.randf() < float(opt.skill)]
	var entry: Array = _seen[key]
	return entry[1] and _time - entry[0] >= float(opt.reaction)


func _zone_cost(point: Vector2, zones: Array) -> float:
	var cost := 0.0
	for zone in zones:
		var depth := _depth(point, zone)
		if depth > 0.0:
			var urgency := 1.0 if zone.t < 0.8 else 0.4
			cost += (1000.0 + depth * 10.0) * urgency
	return cost


func _imminent_cost(point: Vector2, zones: Array) -> float:
	var cost := 0.0
	for zone in zones:
		if zone.t <= 0.16 and _depth(point, zone) > 0.0:
			cost += 1.0
	return cost


func _depth(point: Vector2, zone: Dictionary) -> float:
	if zone.has("c"):
		return zone.r - point.distance_to(zone.c)
	var closest := Geometry2D.get_closest_point_to_segment(point, zone.a, zone.b)
	return zone.w - point.distance_to(closest)


func _has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	return player.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _enemy_radius(enemy: Node) -> float:
	return enemy.data.body_radius * enemy._visual_scale


## If no enemy loses HP for a while (stuck behind a pillar), charge in for a few seconds.
func _check_stall(enemies: Array, dt: float) -> void:
	var total := 0.0
	for enemy in enemies:
		total += enemy.health.get_health()
	if _last_enemy_hp < 0.0 or total < _last_enemy_hp - 0.01 or enemies.size() == 0:
		_stall_time = 0.0
	else:
		_stall_time += dt
	_last_enemy_hp = total
	_aggressive_left = maxf(0.0, _aggressive_left - dt)
	if _stall_time > 12.0:
		_stall_time = 0.0
		_aggressive_left = 4.0


# --- Overrides on spawned enemies ---

func _apply_enemy_overrides(room: Node, enemies: Array) -> void:
	if ovr.has("waves") and room.is_encounter_started() and not room.has_meta(&"bal_waves"):
		room.set_meta(&"bal_waves", true)
		if room.room_type <= 1:
			room._waves_total = _threshold_value(String(ovr.waves), room.room_index, room._waves_total)
	if ovr.has("extra") and room.is_encounter_started() and room.room_type <= 1:
		var wave: int = room.get_wave_progress().x
		if int(room.get_meta(&"bal_extra_wave", 0)) < wave:
			room.set_meta(&"bal_extra_wave", wave)
			var extra := _threshold_value(String(ovr.extra), room.room_index, 0)
			var markers: Array = room._get_markers()
			for i in extra:
				var data: Resource = room.spawner._pick_type(room.room_index, dungeon.context.rng)
				var marker: Node2D = markers[rng.randi_range(0, markers.size() - 1)]
				var enemy: Node = room.spawner._create(data, marker.position + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30)), room.room_index, false, dungeon.context, room.get_arena())
				room.enemy_container.add_child(enemy)
				room._track_enemy(enemy)
	if ovr.has("fix_hitbox"):
		# Experiment: move the melee hitbox already during the telegraph, so its overlap list is
		# current when the attack begins (see BALANCE_REPORT: stale-overlap phantom hits).
		for enemy in enemies:
			if enemy._state == ST_TELEGRAPH and enemy._action == AC_NORMAL and enemy.data.attack_kind == KIND_MELEE:
				enemy._attack_hitbox.position = enemy._attack_direction * enemy.data.attack_reach
	for enemy in enemies:
		if enemy.has_meta(&"bal") or not enemy.is_node_ready():
			continue
		enemy.set_meta(&"bal", true)
		var block: int = scaling.get_block(enemy._room_index)
		var hp_ratio := 1.0
		var dmg_ratio := 1.0
		if ovr.has("hp_growth"):
			hp_ratio *= pow(float(ovr.hp_growth) / scaling.HEALTH_FACTOR_PER_BLOCK, block)
		if ovr.has("dmg_growth"):
			dmg_ratio *= pow(float(ovr.dmg_growth) / scaling.DAMAGE_FACTOR_PER_BLOCK, block)
		if enemy.data.is_boss:
			hp_ratio *= float(ovr.get("boss_hp", 1.0))
		else:
			hp_ratio *= float(ovr.get("hp_mult", 1.0))
		if enemy.is_miniboss and ovr.has("champ_hp"):
			hp_ratio *= float(ovr.champ_hp) / scaling.MINIBOSS_HEALTH_FACTOR
		dmg_ratio *= float(ovr.get("dmg_mult", 1.0))
		if not is_equal_approx(hp_ratio, 1.0):
			enemy.health.reset(enemy.health.get_max_health() * hp_ratio)
		if not is_equal_approx(dmg_ratio, 1.0):
			enemy._damage_multiplier *= dmg_ratio
		if ovr.has("speed_growth") or ovr.has("speed_max"):
			var old_speed: float = scaling.speed_multiplier(enemy._room_index)
			var new_speed := minf(float(ovr.get("speed_max", scaling.MAX_SPEED_FACTOR)), 1.0 + float(ovr.get("speed_growth", scaling.SPEED_GAIN_PER_BLOCK)) * block)
			enemy._speed_multiplier *= new_speed / old_speed


## "20:2,45:3" -> value of the highest threshold <= room, else fallback.
func _threshold_value(spec: String, room_index: int, fallback: int) -> int:
	var result := fallback
	var best := -1
	for part in spec.split(",", false):
		var pair := part.split(":")
		if pair.size() == 2 and int(pair[0]) <= room_index and int(pair[0]) > best:
			best = int(pair[0])
			result = int(pair[1])
	return result


# --- Dialogs ---

## Answers an open dialog. Returns true while the game is paused.
func _handle_pause() -> bool:
	if not paused:
		_stuck_pause = 0
		return false
	var modal := _find_modal(root)
	if modal == null:
		# A pause reason without a dialog (should not happen): clear it instead of hanging forever.
		_stuck_pause += 1
		if _stuck_pause > 600:
			push_warning("balance_sim: stale pause without dialog, clearing pause reasons")
			root.get_node("GameManager").clear_pause_reasons()
			_stuck_pause = 0
		return true
	var buttons := _buttons(modal)
	var choices: Array = []
	for button in buttons:
		var upgrade = _bound_upgrade(button)
		if upgrade != null:
			choices.append([button, upgrade])
	if not choices.is_empty():
		var pick: Array = choices[rng.randi_range(0, choices.size() - 1)]
		if String(opt.pick) != "random":
			var best := -INF
			for choice in choices:
				var score := _upgrade_score(choice[1]) + rng.randf() * 1.5
				if score > best:
					best = score
					pick = choice
		pick[0].pressed.emit()
		_rec.picked.append(String(pick[1].id))
		return true
	for wanted in ["Zurück ins Dorf", "Schließen", "Weiterspielen", "Abbrechen", "Nein"]:
		for button in buttons:
			if button.text == wanted and not button.disabled:
				button.pressed.emit()
				return true
	if not buttons.is_empty():
		buttons[0].pressed.emit()
	return true


func _bound_upgrade(button: Button) -> Variant:
	for connection in button.pressed.get_connections():
		var callable: Callable = connection.callable
		for argument in callable.get_bound_arguments():
			if argument is Resource and &"effect" in argument and &"max_stacks" in argument:
				return argument
	return null


const SCORES := {
	"sword": {"strength_training": 10, "strong_attack": 8, "fast_attack": 9, "wide_swing": 6, "explosive_hit": 7, "heal_on_kill": 5, "shield_on_kill": 4, "shield_boost": 4},
	"bow": {"double_shot": 11, "precise_arrows": 9, "fast_attack": 9, "strong_attack": 8, "explosive_hit": 7, "pierce": 6, "fast_projectiles": 4, "wall_bounce": 3, "heal_on_kill": 5, "shield_on_kill": 4, "shield_boost": 4},
	"staff": {"double_shot": 11, "magic_power": 9, "fast_attack": 9, "strong_attack": 8, "explosive_hit": 7, "big_explosion": 6, "fast_projectiles": 5, "wall_bounce": 3, "heal_on_kill": 5, "shield_on_kill": 4, "shield_boost": 4},
}
const TANK_SCORES := {"shield_boost": 14, "shield_on_kill": 13, "heal_on_kill": 12}


func _upgrade_score(upgrade: Resource) -> float:
	var id := String(upgrade.id)
	if String(opt.pick) == "tank" and TANK_SCORES.has(id):
		return TANK_SCORES[id]
	return float((SCORES.get(String(opt.policy), SCORES.sword) as Dictionary).get(id, 1))


func _return_to_village() -> void:
	for i in 1200:
		await physics_frame
		_handle_pause()
		var world: Node = controller.get_world()
		if world != null and world != dungeon and world.get_script() != null and world.get_script().get_global_name() == &"Village":
			await _frames(10)
			return
	push_error("balance_sim: did not return to the village")


# --- Recording ---

func _begin_record(room: Node) -> void:
	_rec = {
		"room": room.room_index, "type": int(room.room_type), "start": _time, "hp_dmg": 0.0, "shield_dmg": 0.0,
		"hits": 0, "dashes": 0, "enemies": 0, "timeout": 0, "fountain": 0, "bought": 0, "picked": [],
		"trap_dmg": 0.0, "pit_dmg": 0.0, "explosion_dmg": 0.0, "enemy_dmg": 0.0, "desc": _room_desc(room),
	}
	room.set_meta(&"bal_record", true)


func _end_record(run: int, room: Node) -> void:
	var type_name: String = ["COMBAT", "COMBAT_UPGRADE", "SPECIAL", "MINIBOSS", "BOSS"][_rec.type] if _rec.type < 5 else str(_rec.type)
	if _rec.type == RT_SPECIAL:
		type_name = "SPECIAL_" + ["SHOP", "WEAPON", "FOUNTAIN", "ALTAR"][clampi(int(room.special_type), 0, 3)]
	var dead: bool = not player.is_alive()
	var row := "%d,%s,%s,%d,%s,%d,%.1f,%.1f,%.1f,%d,%d,%.1f,%.1f,%.1f,%d,%d,%d,%d,%s" % [
		run, opt.policy, opt.pick, _rec.room, type_name, room.enemy_container.get_child_count(), _time - _rec.start,
		_rec.hp_dmg, _rec.shield_dmg, _rec.hits, _rec.dashes, player.health.get_health(), player.health.get_max_health(),
		player.shield.get_shield(), _upgrade_count(), root.get_node("RunManager").get_run_gold(), 1 if dead else 0, _rec.timeout,
		_last_hit_source if dead else ""]
	row += ",%s,%s,%.1f,%.1f,%.1f,%.1f" % [_last_hit_detail if dead else "", _rec.desc, _rec.trap_dmg, _rec.pit_dmg, _rec.explosion_dmg, _rec.enemy_dmg]
	_rows.append(row)
	if int(opt.quiet) == 0:
		print("  r%-3d %-15s t=%5.1fs dmg=%4.1f+%4.1fsh hits=%2d dash=%2d hp=%4.1f/%-4.1f sh=%5.1f upg=%2d%s%s" % [
			_rec.room, type_name, _time - _rec.start, _rec.hp_dmg, _rec.shield_dmg, _rec.hits, _rec.dashes,
			player.health.get_health(), player.health.get_max_health(), player.shield.get_shield(), _upgrade_count(),
			(" picked " + ",".join(PackedStringArray(_rec.picked))) if not _rec.picked.is_empty() else "",
			(" DIED (" + _last_hit_detail + ")") if dead else ""])
		print("       %s trap=%.1f pit=%.1f expl=%.1f enemy=%.1f%s" % [_rec.desc, _rec.trap_dmg, _rec.pit_dmg, _rec.explosion_dmg, _rec.enemy_dmg, " TIMEOUT" if _rec.timeout else ""])


func _on_player_hit(result: Object, damage: Object) -> void:
	if _rec.is_empty():
		return
	_rec.hp_dmg += result.health_damage
	_rec.shield_dmg += result.shield_damage
	_rec.hits += 1
	if int(opt.debug) > 0:
		var zones_now := _collect_zones(dungeon.get_room(dungeon.get_active_room_index()), _alive(dungeon.get_room(dungeon.get_active_room_index())))
		var src_state = damage.source._state if damage.source != null and is_instance_valid(damage.source) and &"_state" in damage.source else -1
		var src_action = damage.source._action if damage.source != null and is_instance_valid(damage.source) and &"_action" in damage.source else -1
		print("    hit state=%s action=%s stun=%.1f" % [src_state, src_action, damage.stun_duration])
		print("    hit %.1f t=%.2f src=%s tags=%s zones=%s dash_cd=%.2f" % [result.amount, _time, damage.source.data.id if damage.source != null and is_instance_valid(damage.source) and &"data" in damage.source else "-", damage.tags, zones_now, player.get_dash_cooldown_left()])
	var source: Object = damage.source
	if source != null and is_instance_valid(source) and &"data" in source and source.data != null:
		_last_hit_source = String(source.data.id)
	elif damage.tags.has(&"trap"):
		_last_hit_source = "trap"
	else:
		_last_hit_source = "explosion" if damage.tags.has(&"explosion") else ("pit" if damage.tags.has(&"pit") else "unknown")
	_last_hit_detail = _hit_detail(damage)
	if int(opt.bosshits) == 1 and _rec.has("type") and int(_rec.type) == 4 and source != null and is_instance_valid(source) and &"_state" in source:
		var st := ["IDLE", "CHASE", "TELEGRAPH", "ATTACK", "CHARGE", "LEAP", "RECOVER", "DEAD", "ROAR"]
		var ac := ["NORMAL", "VOLLEY", "SPECIAL", "SUMMON"]
		var key := "r%d %s@%s/%s" % [int(_rec.room), String(source.data.id), st[clampi(int(source._state), 0, 8)], ac[clampi(int(source._action), 0, 3)]]
		_boss_hits[key] = float(_boss_hits.get(key, 0.0)) + result.health_damage + result.shield_damage
	var cat := _last_hit_detail.get_slice(":", 0)
	if cat == "trap" or cat == "pit" or cat == "explosion":
		_rec[cat + "_dmg"] = float(_rec.get(cat + "_dmg", 0.0)) + result.health_damage + result.shield_damage
	else:
		_rec.enemy_dmg = float(_rec.get("enemy_dmg", 0.0)) + result.health_damage + result.shield_damage


## Re-computes every shield gain with another softcap: undo the built-in cap, apply the new one.
func _on_shield_changed(current: float) -> void:
	var previous := _shield_prev
	_shield_prev = current
	if current <= previous + 0.001:
		return
	var shield_script: Script = player.shield.get_script()
	var threshold: float = shield_script.SOFTCAP_THRESHOLD
	var factor: float = shield_script.SOFTCAP_FACTOR
	var gain := current - previous
	var normal := maxf(0.0, threshold - previous)
	var requested := gain if gain <= normal else normal + (gain - normal) / factor
	var new_threshold := float(ovr.get("softcap", threshold))
	var new_factor := float(ovr.get("softcap_factor", factor))
	var new_normal := minf(requested, maxf(0.0, new_threshold - previous))
	var new_gain := new_normal + new_factor * (requested - new_normal)
	_shield_prev = previous + new_gain
	player.shield.set(&"_current", _shield_prev)


func _upgrade_count() -> int:
	var total := 0
	for upgrade in upgrades.get_active_upgrades():
		total += upgrades.get_stacks(upgrade.id)
	return total


func _write_csv() -> void:
	var path := String(opt.out)
	if path.is_empty():
		path = ProjectSettings.globalize_path("user://balance_sim_%s_%s.csv" % [opt.policy, opt.pick])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("balance_sim: cannot write " + path)
		return
	file.store_string("\n".join(_rows) + "\n")
	print("CSV written: ", path)


func _print_overview() -> void:
	var rooms: Array = []
	var deaths := {}
	var details := {}
	var places := {}
	for summary in _summaries:
		rooms.append(summary.room)
		if summary.dead:
			deaths[summary.cause] = deaths.get(summary.cause, 0) + 1
			details[summary.detail] = details.get(summary.detail, 0) + 1
			var place := String(summary.where).get_slice("|", 0)
			places[place] = places.get(place, 0) + 1
	rooms.sort()
	print("SUMMARY policy=%s pick=%s skill=%.2f runs=%d rooms reached=%s median=%s death causes=%s overrides=%s %s" % [
		opt.policy, opt.pick, float(opt.skill), _summaries.size(), rooms, rooms[rooms.size() / 2] if not rooms.is_empty() else "-",
		deaths, ovr, res_overrides.map(func(e): return "%s=%s" % [e[0], e[1]])])
	if not details.is_empty():
		print("DEATHS detail=%s room kind=%s" % [details, places])


# --- Helpers ---

func _alive(room: Node) -> Array:
	return room.enemy_container.get_children().filter(func(n): return _is_class(n, &"Enemy") and not n.is_dead())


func _is_class(node: Object, class_id: StringName) -> bool:
	var script: Script = node.get_script()
	while script != null:
		if script.get_global_name() == class_id:
			return true
		script = script.get_base_script()
	return false


func _find_by_class(node: Node, class_id: StringName) -> Array:
	var found: Array = []
	for child in node.get_children():
		if _is_class(child, class_id):
			found.append(child)
		found.append_array(_find_by_class(child, class_id))
	return found


func _find_modal(node: Node) -> Node:
	for child in node.get_children():
		if _is_class(child, &"Modal") and not child.is_queued_for_deletion():
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


# --- Abysses, room description, hit details, variant overrides, navigation ---

func _pit_cost(point: Vector2) -> float:
	if int(opt.falls) != 1:
		return 0.0
	var probe: Callable = player.fall.pit_probe
	if not probe.is_valid():
		return 0.0
	var feet := point + Vector2(0, 16)
	return 1500.0 if bool(probe.call(feet)) else 0.0


func _room_desc(room: Node) -> String:
	var parts: Array[String] = []
	var kinds := ["normal", "arena", "chasm"]
	if room.room_type <= 1:
		parts.append(kinds[clampi(int(room.room_kind), 0, 2)])
		if room.has_method(&"get_variant_id") and String(room.get_variant_id()) != "":
			parts.append("var=" + String(room.get_variant_id()))
		if room.has_method(&"has_wager_altar") and room.has_wager_altar():
			parts.append("wager")
		if room.has_method(&"is_ambush_room") and room.is_ambush_room():
			parts.append("ambush")
		if room.has_method(&"is_branch_room") and room.is_branch_room():
			parts.append("branch")
		if room.spawner != null and room.spawner.encounter_group != null:
			parts.append("grp=" + String(room.spawner.encounter_group.id))
	elif room.room_type == 2:
		parts.append("special=" + ["shop", "weapon", "fountain", "upgrade", "trial"][clampi(int(room.special_type), 0, 4)])
	else:
		parts.append(["", "", "", "miniboss", "boss"][int(room.room_type)])
	if room.is_extra_dark:
		parts.append("dark")
	parts.append(String(room.scene_file_path).get_file().get_basename())
	return "|".join(parts)


func _hit_detail(damage: Object) -> String:
	var source: Object = damage.source
	if damage.tags.has(&"trap"):
		if damage.tags.has(&"trial"):
			return "trap:trial"
		if damage.tags.has(&"fire"):
			return "trap:lava"
		if damage.tags.has(&"poison"):
			return "trap:poison"
		return "trap:spike"
	if damage.tags.has(&"pit"):
		return "pit"
	if source != null and is_instance_valid(source) and &"data" in source and source.data != null:
		var id := String(source.data.id)
		if &"is_miniboss" in source and source.is_miniboss and not source.data.is_boss:
			id += "*champ"
		elif &"elite" in source and int(source.elite) != 0:
			id += "*elite"
		return id
	if damage.tags.has(&"explosion"):
		return "explosion"
	return "unknown:" + "+".join(PackedStringArray(damage.tags))


## vt.chance / vt.wager / vt.only: changes the cached variant table in memory (file untouched).
func _apply_variant_overrides() -> void:
	var table: Resource = load("res://dungeon/variants/variant_table.tres")
	var used := false
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() != 2 or not parts[0].begins_with("vt."):
			continue
		used = true
		match parts[0]:
			"vt.chance":
				table.variant_chance = float(parts[1])
			"vt.wager":
				table.wager_chance = float(parts[1])
			"vt.only":
				var weights: Array[float] = []
				for id in table.variant_ids:
					weights.append(1.0 if String(id) == parts[1] else 0.0)
				table.variant_weights = weights
				var biomes: Array[int] = []
				var masks: Array[int] = []
				for id in table.variant_ids:
					biomes.append(-1)
					masks.append(0)
				table.variant_biomes = biomes
				table.variant_biome_masks = masks
	if used:
		# Keep the resource alive so the cache keeps the changed instance.
		_vt_keep = table
		print("variant table: chance %.2f weights %s" % [table.variant_chance, table.variant_weights])


func _room_nav_map(room: Node) -> RID:
	if room.has_meta(&"bal_nav"):
		return room.get_meta(&"bal_nav")
	var map := RID()
	for layer in room.find_children("*", "TileMapLayer", true, false):
		var candidate: RID = (layer as TileMapLayer).get_navigation_map()
		if candidate.is_valid() and not NavigationServer2D.map_get_regions(candidate).is_empty():
			map = candidate
			break
	room.set_meta(&"bal_nav", map)
	return map


## Next waypoint towards the target when walls hide it, else INF (the normal objective).
func _nav_waypoint(room: Node, pos: Vector2, target: Node2D) -> Vector2:
	if target == null or (_has_line_of_sight(pos, target.global_position) and not _pit_between(pos, target.global_position)):
		return Vector2.INF
	if _time - float(_nav_cache.t) < 0.25 and _nav_cache.wp != Vector2.INF and pos.distance_to(_nav_cache.wp) > 14.0:
		return _nav_cache.wp
	var map := _room_nav_map(room)
	if not map.is_valid():
		return Vector2.INF
	var path := NavigationServer2D.map_get_path(map, pos, target.global_position, true)
	path = load("res://enemies/enemy_navigation.gd").clear_corners(path, 18.0)
	var wp := Vector2.INF
	for point in path:
		if point.distance_to(pos) > 24.0:
			wp = point
			break
	_nav_cache = {"t": _time, "wp": wp, "path": path}
	return wp


func _pit_between(a: Vector2, b: Vector2) -> bool:
	if int(opt.falls) != 1:
		return false
	var steps := int(a.distance_to(b) / 24.0)
	for i in range(1, steps):
		if _pit_cost(a.lerp(b, float(i) / steps)) > 0.0:
			return true
	return false

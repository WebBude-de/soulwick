extends SceneTree
## Two-instance test of the shared dungeon run (MP3, ROADMAP_MULTIPLAYER, D-126): a headless host and
## a headless client (second Godot process, started by the host) over a running soulwick-api and
## soulwick-relay play a scripted run. The client's player is a bot (RemoteInput: walks to the
## nearest enemy, aims, attacks), the host places the group and finishes fights that take too long.
## Checked on the way (PASS/FAIL lines, exit code 1 on any failure):
## - every process enters the room with a relay JWT from GET /auth/token (P-027), not the session
##   token;
## - "Starten" takes both into the dungeon with the same seed; both build the same rooms
##   (room signatures, no mismatch) and the same room numbers;
## - rooms 1-5: enemies exist only as the host's real ones and the client's puppets (same count,
##   same deaths), the client's bot deals damage through the host, gold goes into the shared pot
##   (same value on both machines); the exit rule (online test 15.10.2026): one player alone in the
##   next room does not start it - no countdown, no teleport; he sees "Warte auf ...", the other one
##   "... wartet im naechsten Raum" with the arrow; the room starts once the other one walked in;
## - after room 3 both pick their own upgrade, the exit waits for both; the special room (shop:
##   purchase validated by the host; weapons: the client's pick reaches the host);
## - the client's player goes down and is revived by the host's player (2 s, 2 HP);
## - the client uses the portal: the run ends for both with 100 % of the pot as village gold;
## - both are back in the shared village; the host closes the room.
## end=two_runs (several runs per room): run 1 as with end=portal; back in the village the host
## sends end_run (relay: run_ended "portal", room back in the lobby); a third process (role late)
## joins the room in the village and appears there with its own look on every machine; run 2 starts
## for three players (scaling, same seed, run number 2 everywhere), rooms 1-2, ends through the
## portal for everybody, end_run again; then the host closes the room.
## Usage (API and relay running, see docs/MULTIPLAYER.md §3c):
##   godot --headless --path . -s tools/net_run_smoke.gd -- api=http://localhost:8787 relay=ws://localhost:8790/v1 dev_key=<DEV_AUTH_KEY>
## Options: side=1 (see above), rooms=1..16 (default 5; 16 = first boss, campfire and the first room of the next biome), seed=<n> (default random), end=portal|host_leaves|client_leaves|two_runs,
## modes=all|flame,escort,... (room modes R4 from room mode_from, default 2, in every combat room the
## mode table allows; both machines), branch=1 (every eligible room branches, D-105/R5). With modes
## both machines compare the mode of every room they entered, its bonus, the events and states of
## NetModes; with branch the client compares both built ways and the chosen way (signatures).
## side=1 (makeover M5, D-144): every way that may be a side-view segment is one (rooms 1->2 and 3->4
## with rooms=5); the group walks into the gate, both players run through the segment (the host's
## player and the client's bot with the autopilot SideBot, the client's through RemoteInput and the
## network), both come out in the next room. Checked: the same side way signature on both machines,
## both players in the segment and in its camera, the host's end reaches the client. Round 2: the
## host's ledges are made to crumble (as if stood on) - the client's shake, fall and come back with
## them (same changes, same collapses); every move of the host's player (jumps, the double jump to
## the golden coin, landings) reaches the client and plays on its copy there. Round 3 (traps): every
## segment gets its turret mounts (SidePlans.force_turrets_for_tests); the host's turret shots and
## spike phases play on the client (counters of NetSide compared). In every
## scenario: the gate behind a started room shuts only once both are inside (host), the client
## mirrors it, and the group camera holds both players.
## weapons=<host>,<client> (e.g. sword,bow or staff,bow; online test 15.10.2026): weapons per player.
## Each machine gives its own player its weapon (second slot, like a weapon pedestal) and switches to
## it with the switch button; the host's player attacks with it, the client's bot fights with it.
## In the first fight room from room 2 on each one switches to the other slot, attacks, switches back and attacks again
## (the client's bot pauses meanwhile; its shop buys a weapon when one is offered). Checked: every
## machine sees the other player holding and showing (sprite) the owner's weapon; the host's hits
## of the client's player carry the client's weapon tags; the active weapons of every player and
## the weapons of its attacks (in order) are the same on the owner's machine and on the other one.
## (portal: the client uses the portal after the revive; host_leaves: the host leaves in room 3,
## both get 50 %; client_leaves: the client gives up in room 3, the host plays on alone),
## spawn_client=0. Real time.
## Classes are accessed dynamically: this script is compiled before autoloads exist.

const DEFAULT_API := "http://localhost:8787"
const DEFAULT_RELAY := "ws://localhost:8790/v1"
const HOST_INSTANCE := 21
const CLIENT_INSTANCE := 22
const LATE_INSTANCE := 23
## Clothing colour of the late joiner (end=two_runs): every machine must draw it.
const LATE_COLOR := Color("#8e44ad")
## Rooms of the second run (end=two_runs).
const SECOND_RUN_ROOMS := 2
const STEP_TIMEOUT := 30.0
const STARTUP_TIMEOUT := 120.0
## Seconds the client's bot fights before the host finishes the rest of a room.
const BOT_FIGHT_SECONDS := 5.0
## Room 1: the client's bot must have hit something through the host by then.
const BOT_HIT_TIMEOUT := 20.0
## Extra pot gold the host adds before a shop so the client can buy something (test only).
const SHOP_TEST_GOLD := 500
const STOP_DISTANCE := 70.0
const ATTACK_RANGE := 140.0
const ROOM_TYPES := ["COMBAT", "COMBAT_UPGRADE", "SPECIAL", "MINIBOSS", "BOSS", "CAMPFIRE"]
const SPECIAL_TYPES := ["SHOP", "WEAPON", "FOUNTAIN", "UPGRADE", "TRIAL"]
## Longest run of the test: the first boss (15), its campfire and room 16.
const MAX_ROOMS := 16
## RoomController.State.CLEARED
const ROOM_CLEARED := 2
## weapons=: weapon ids (weapons/data/<id>.tres; the id is one of its damage tags).
const WEAPON_IDS: Array[String] = ["sword", "bow", "staff", "dagger", "hammer"]
## Seconds the attack button is held per weapon in the weapons scenario.
const WEAPON_ATTACK_SECONDS := 1.0
## Seconds the host waits alone in room 3 (longer than the old 10 s countdown).
const STRAGGLER_WAIT := 11.0

var _role := "host"
var _run_id := ""
var _args: Dictionary = {}
var _failures: Array[String] = []
var _log: Array[String] = []
var _controller: Node = null
var _lobby: Node = null
var _rooms := 5
var _bot_enabled := false
var _bot_attacks := 0
var _stats: Dictionary = {}
## How the run ends: portal (client uses it), host_leaves (in room 3), client_leaves (in room 3),
## two_runs (portal, then a second run with a late joiner).
var _scenario := "portal"
## Processes the host started (client, late joiner).
var _pids: Array[int] = []
var _session: Node = null
## Client: autopilot of the running side segment (drives RemoteInput, so the input goes to the host).
var _side_bot: RefCounted = null
var _side_was_on := false
var _side_check_at := -1
## Client, M2 tunnels: the last active slot counted, frames in a passage per player.
var _tunnel_slot := -1
var _tunnel_streak: Dictionary[int, int] = {}
## weapons=: weapon log per tracked player ("host_own", "host_client", "client_own", "client_host"):
## {active: [weapon ids, changes only], attacks: [weapon ids, changes only]}.
var _weapon_logs: Dictionary = {}
## Client: the bot is paused while the switch round runs (weapons=).
var _bot_paused := false
## weapons=: the switch round runs in the first fight room from room 2 on (not in a special room,
## whose dialogs it would wait for).
var _switch_started := false


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	# Godot 4.7.2 audio race (AudioServer::_mix_step) at very high headless FPS: cap and mute.
	Engine.max_fps = 60
	AudioServer.set_bus_mute(0, true)
	var config_script: GDScript = load("res://online/online_config.gd")
	_args = config_script.parse_args(OS.get_cmdline_user_args())
	_role = str(_args.get("role", "host"))
	_run_id = str(_args.get("run", str(Time.get_ticks_usec() % 1000000)))
	_rooms = clampi(int(_args.get("rooms", "5")), 1, MAX_ROOMS)
	_scenario = str(_args.get("end", "portal"))
	if not _is_portal():
		_rooms = maxi(_rooms, 3)
	_apply_test_tables()
	_say("net_run_smoke %s, run %s, api %s, relay %s" % [_role, _run_id, _args.get("api", DEFAULT_API), _args.get("relay", DEFAULT_RELAY)])
	var save_manager := root.get_node("SaveManager")
	var save_path := "user://net_run_smoke_%s_save.cfg" % _role
	save_manager.save_path = save_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	save_manager.load_game()
	save_manager.settings_path = "user://net_run_smoke_%s_settings.cfg" % _role
	save_manager.load_settings()
	save_manager.set_option(&"language", "en")
	change_scene_to_file("res://scenes/game.tscn")
	await _seconds(0.5)
	TranslationServer.set_locale("en")
	_controller = current_scene.get_node("WorldController")
	var config: RefCounted = config_script.new()
	config.instance = int(_args.get("instance", {"client": CLIENT_INSTANCE, "late": LATE_INSTANCE}.get(_role, HOST_INSTANCE)))
	config.path = config_script.INSTANCE_FILE_PATH % config.instance
	config.settings_path = config.path
	var with_defaults := {"api": DEFAULT_API, "relay": DEFAULT_RELAY, "name": {"client": "Run Client", "late": "Run Late"}.get(_role, "Run Host")}
	with_defaults.merge(_args, true)
	if not with_defaults.has("dev_key") and not OS.get_environment("SOULWICK_DEV_KEY").is_empty():
		with_defaults["dev_key"] = OS.get_environment("SOULWICK_DEV_KEY")
	_args = with_defaults
	config.load_from(_args)
	var session: Node = load("res://online/session.gd").new(config)
	session.name = "OnlineSession"
	current_scene.add_child(session)
	_session = session
	_lobby = load("res://online/lobby_client.gd").of(_controller)
	var api := get_multiplayer()
	api.peer_connected.connect(func(id: int) -> void: _say("  peer_connected %d" % id))
	api.peer_disconnected.connect(func(id: int) -> void: _say("  peer_disconnected %d" % id))
	_lobby.session_ended.connect(func(reason: String) -> void: _say("  session ended: %s" % reason))
	physics_frame.connect(_drive_bot)
	if _role == "client":
		await _client()
		_write_result()
	elif _role == "late":
		await _late()
		_write_result()
	else:
		await _host()
	var ok := _failures.is_empty()
	_say("net_run_smoke %s: %s" % [_role, "PASSED" if ok else "FAILED (%d)" % _failures.size()])
	for failure in _failures:
		_say("  - " + failure)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	quit(0 if ok else 1)


## modes= / branch=: the same mode table and branch chance on every machine, before the dungeon.
func _apply_test_tables() -> void:
	var mode_ids := str(_args.get("modes", ""))
	if not mode_ids.is_empty():
		var table := {"chance": 1.0, "from_room": int(_args.get("mode_from", "2"))}
		if mode_ids != "all":
			table["ids"] = Array(mode_ids.split(",", false))
		load("res://online/net_dungeon.gd").test_mode_table = table
	if str(_args.get("branch", "0")) == "1":
		load("res://dungeon/rooms/branches/branch_rules.gd").chance_override = 1.0
	if str(_args.get("side", "0")) == "1":
		load("res://dungeon/side/side_ways.gd").force_for_tests = true
		load("res://dungeon/side/side_plans.gd").force_turrets_for_tests = true


## Mode of a room (&"" for none) and what the run saw: "room:mode" per room entered.
func _note_mode(room: Node) -> void:
	if room == null:
		return
	var variant: Node = room.get_node_or_null("CombatVariant")
	var id := String(variant.variant_id) if variant != null else ""
	var modes: Array = _stats.get("_modes", [])
	modes.append("%d:%s" % [room.room_index, id])
	_stats["_modes"] = modes


## Mode stats for the result: count of distinct modes, a hash of "room:mode" and of the bonus per mode room.
func _mode_stats(net: Node) -> void:
	var modes: Array = _stats.get("_modes", [])
	_stats.erase("_modes")
	var distinct := {}
	for entry: String in modes:
		var id := entry.get_slice(":", 1)
		if not id.is_empty():
			distinct[id] = true
	_stats["mode_count"] = distinct.size()
	_stats["mode_hash"] = hash(",".join(modes)) & 0x7fffffff
	# Bonus of every mode room at its end (CombatVariant.finished), on each machine its own.
	var bonus: Array = []
	var by_slot: Dictionary = net.modes.finished_by_slot
	var slots := by_slot.keys()
	slots.sort()
	for slot in slots:
		bonus.append("%d:%d" % [slot, by_slot[slot]])
	_stats["mode_bonus"] = hash(",".join(bonus)) & 0x7fffffff
	_stats["mode_finished"] = bonus.size()
	_stats["mode_events"] = net.modes.events
	_stats["mode_states"] = net.modes.states
	_stats["mode_banners"] = net.modes.banners
	# Bonus chests (makeover wave B: never on a player, whose places differ per machine): the client's
	# stand where the host's stand.
	var places: Array = []
	var keys: Array = net.modes.chest_places.keys()
	keys.sort()
	for key: String in keys:
		places.append("%s@%s" % [key, net.modes.chest_places[key].round()])
	_stats["mode_chests"] = places.size()
	_stats["mode_chest_hash"] = hash(",".join(places)) & 0x7fffffff
	_say("modes: %s, events %d, states %d, banners %d, bonus %s, chests %s" % [modes, net.modes.events, net.modes.states, net.modes.banners, bonus, places])


# --- Host ---

func _host() -> void:
	_lobby.create_room()
	if not await _until(func() -> bool: return _lobby.is_in_room(), "host created a room"):
		_say("lobby error: %s" % _lobby.last_error)
		return
	_check_relay_token()
	_write_file(_code_path(), _lobby.get_room_code())
	for role in ["client", "late"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_result_path(role)))
	if str(_args.get("spawn_client", "1")) != "0":
		_spawn_client()
	if not await _until(func() -> bool: return _players().size() == 2, "host sees the client in the village", STARTUP_TIMEOUT):
		return
	await _seconds(1.0)
	var run_manager := root.get_node("RunManager")
	var start_gold: int = root.get_node("SaveManager").get_permanent_gold()
	_lobby.net_run.start(int(_args.get("seed", "0")))
	if not await _until(func() -> bool: return _dungeon() != null and _net() != null, "host entered the dungeon"):
		return
	_say("seed %d, scenario %s" % [_lobby.net_run.seed_value, _scenario])
	root.get_node("EventBus").enemy_damaged.connect(func(_enemy: Node, _result: RefCounted, damage: RefCounted) -> void:
		var source: Object = damage.source
		if source != null and is_instance_valid(source) and source.get_script() != null and source.get_script().get_global_name() == &"Player" and not source.is_local:
			_stats["client_hits"] = int(_stats.get("client_hits", 0)) + 1
			for weapon_id: String in WEAPON_IDS:
				if damage.tags.has(StringName(weapon_id)):
					_stats["client_hits_" + weapon_id] = int(_stats.get("client_hits_" + weapon_id, 0)) + 1)
	if not await _until(func() -> bool: return _players().size() == 2 and _net().get_ready_peers().size() == 1, "client loaded the dungeon (ready, 2 players)", STARTUP_TIMEOUT):
		return
	for player in _players():
		# Traps and enemies are real: the test pair must survive the walk-through.
		player.health.reset(99999.0)
	if not await _until(func() -> bool: return _dungeon().get_active_room_index() == 1 and _room(1).is_encounter_started(), "room 1 starts once the client is there"):
		return
	if _has_weapon_test():
		await _host_weapons()
	var host_rooms_ok := true
	for index in range(1, _rooms + 1):
		if index == 3 and _scenario == "host_leaves":
			await _until(func() -> bool: return _dungeon().get_active_room_index() == 3, "room 3 active, the host leaves now")
			# Let the room start reach the client first (relay latency).
			await _seconds(1.5)
			_stats["host_pot"] = run_manager.get_run_gold()
			_lobby.leave()
			host_rooms_ok = false
			break
		if index == 3 and _scenario == "client_leaves":
			await _until(func() -> bool: return _players().size() == 1, "the client left in room 3")
			_check(run_manager.is_run_active(), "the run goes on without the client (D-123)")
		if not await _host_room(index):
			host_rooms_ok = false
			break
	if _scenario == "client_leaves" and host_rooms_ok:
		_check(_controller.game_mode.get_player_count() == 1, "the next rooms are prepared for one player (count %d)" % _controller.game_mode.get_player_count())
		_dungeon().end_run(2)
	elif host_rooms_ok:
		await _host_revive()
	# portal: the client uses it (request to the host, D-126); host_leaves: the host gave up.
	if not await _until(func() -> bool: return not run_manager.is_run_active(), "run ended for the host", STEP_TIMEOUT * 2):
		return
	var summary: Dictionary = run_manager.get_last_summary()
	var expected_reason := 1 if _scenario == "host_leaves" else 2
	_check(int(summary.get("reason", -1)) == expected_reason, "host: run ended with reason %d" % expected_reason)
	if _scenario != "host_leaves":
		_stats["host_pot"] = int(summary.get("remaining_gold", -1))
	_stats["host_payout"] = int(summary.get("payout", -1))
	_stats["host_room"] = int(summary.get("room", -1))
	var expected_payout: int = _stats["host_pot"] if expected_reason == 2 else ceili(_stats["host_pot"] * 0.5)
	_check(_stats["host_payout"] == expected_payout, "host: %s of the pot as village gold (%d)" % ["100 %" if expected_reason == 2 else "50 %", _stats["host_payout"]])
	_check(root.get_node("SaveManager").get_permanent_gold() - start_gold == _stats["host_payout"], "host: village gold booked")
	_stats["host_enemies"] = _net().enemies.spawned_count if _net() != null else -1
	_stats["host_deaths"] = _net().enemies.died_count if _net() != null else -1
	_stats["host_emerges"] = _net().enemies.emerge_count if _net() != null else -1
	if _net() != null:
		_host_makeover_checks(_net())
	if _net() != null:
		_mode_stats(_net())
	var client_copy := _remote_player()
	if _has_weapon_test():
		_weapon_stats("host_own", "w_host_own")
		_weapon_stats("host_client", "w_host_client")
	_stats["host_client_upgrades"] = _stack_total(_net().manager_for(client_copy)) if client_copy != null and _net() != null else -1
	_stats["host_client_weapons"] = client_copy.weapon_controller.get_owned_weapons().size() if client_copy != null else -1
	await _close_run_end()
	if _is_portal():
		await _until(func() -> bool: return _world_name() == &"Village" and _players().size() == 2, "host back in the shared village with the client")
		await _until(func() -> bool: return _lobby.net_run.last_report_status != "", "run report finished")
		_say("run report: %s" % _lobby.net_run.last_report_status)
		_check(_lobby.net_run.last_report_status == "sent", "host reported the run (POST /runs)")
		if _scenario == "two_runs":
			await _host_second_run()
		await _seconds(1.0)
		_lobby.leave()
		await _until(func() -> bool: return int(_lobby.state) == 0, "host closed the room")
	elif _scenario == "client_leaves":
		await _until(func() -> bool: return _world_name() == &"Village" and _players().size() == 1, "host back in the room's village, alone")
		await _until(func() -> bool: return _lobby.net_run.last_report_status != "", "run report finished")
		_check(_lobby.net_run.last_report_status == "sent", "host reported the run (POST /runs)")
		_lobby.leave()
		await _until(func() -> bool: return int(_lobby.state) == 0, "host closed the room")
	else:
		await _until(func() -> bool: return _world_name() == &"Village" and not _controller.game_mode.is_networked(), "host back in a solo village")
	var client_stats := await _read_result("client")
	if _scenario == "two_runs":
		var late_stats := await _read_result("late")
		for stats: Dictionary in [client_stats, late_stats]:
			_check(stats.get("r2_pot", -2) == _stats.get("r2_host_pot", -1), "run 2: same pot on every machine (%s / %s)" % [stats.get("r2_pot"), _stats.get("r2_host_pot")])
			_check(stats.get("r2_payout", -2) == _stats.get("r2_host_payout", -1), "run 2: same payout on every machine (%s)" % stats.get("r2_payout"))
			_check(stats.get("r2_room", -2) == _stats.get("r2_host_room", -1), "run 2: same room at the end (%s)" % stats.get("r2_room"))
	if _scenario != "client_leaves":
		_check(client_stats.get("pot", -2) == _stats.get("host_pot", -1), "same pot on both machines (%s / %s)" % [client_stats.get("pot"), _stats.get("host_pot")])
		_check(client_stats.get("payout", -2) == _stats.get("host_payout", -1), "same payout on both machines (%s)" % client_stats.get("payout"))
	if _is_portal():
		_check(client_stats.get("room", -2) == _stats.get("host_room", -1), "same room at the end (%s)" % client_stats.get("room"))
		_check(client_stats.get("enemies", -2) == _stats.get("host_enemies", -1), "every host enemy became a client puppet (%s / %s)" % [client_stats.get("enemies"), _stats.get("host_enemies")])
		_check(client_stats.get("deaths", -2) == _stats.get("host_deaths", -1), "every enemy death reached the client (%s / %s)" % [client_stats.get("deaths"), _stats.get("host_deaths")])
		_check(client_stats.get("emerges", -2) == _stats.get("host_emerges", -1), "every emergence out of a spawn source reached the client (%s / %s)" % [client_stats.get("emerges"), _stats.get("host_emerges")])
		if _rooms >= 3:
			_check(client_stats.get("upgrades", -2) == _stats.get("host_client_upgrades", -1) and int(client_stats.get("upgrades", 0)) >= 1,
					"the client's own upgrades are the same on the host (%s / %s stacks)" % [client_stats.get("upgrades"), _stats.get("host_client_upgrades")])
		_check(client_stats.get("weapons", -2) == _stats.get("host_client_weapons", -1), "the client's weapons are the same on the host (%s / %s)" % [client_stats.get("weapons"), _stats.get("host_client_weapons")])
		if _has_weapon_test():
			_check_weapon_logs(client_stats)
		_check(client_stats.get("mode_hash", -2) == _stats.get("mode_hash", -1), "same room modes in the same rooms on both machines (%s modes)" % _stats.get("mode_count"))
		_check(int(client_stats.get("gates", 0)) >= 1 and int(client_stats.get("gates", 0)) <= int(_stats.get("host_gates", 0)), "the client shut the gates the host shut (%s / %s)" % [client_stats.get("gates"), _stats.get("host_gates")])
		_check(int(client_stats.get("camera", 0)) >= 2, "client: the group camera held both players (%s)" % client_stats.get("camera"))
		if _rooms >= 3 and _stats.get("straggler_room", false):
			_check(int(client_stats.get("wait_hints", 0)) >= 1 and int(client_stats.get("wait_arrow", 0)) >= 1,
					"client: \"... wartet im naechsten Raum\" with the arrow while the host waited (%s hints, %s arrow frames)" % [client_stats.get("wait_hints"), client_stats.get("wait_arrow")])
		_check(client_stats.get("side_ways", -2) == _stats.get("host_side_ways", -1) and client_stats.get("side_sig", -2) == _stats.get("host_side_sig", -1),
				"same side ways on both machines (%s ways, signatures equal)" % _stats.get("host_side_ways"))
		if int(_stats.get("host_side_transits", 0)) > 0:
			_check(client_stats.get("side_transits", -2) == _stats.get("host_side_transits", -1), "the client followed every side transit (%s / %s)" % [client_stats.get("side_transits"), _stats.get("host_side_transits")])
			_check(client_stats.get("side_finished", -2) == _stats.get("host_side_finished", -1), "the host's end of every segment reached the client (%s)" % client_stats.get("side_finished"))
			_check(int(client_stats.get("side_players", 0)) == 2 and int(client_stats.get("side_camera", 0)) == 2, "client: both players in the segment and its camera (%s / %s)" % [client_stats.get("side_players"), client_stats.get("side_camera")])
			_check(int(client_stats.get("side_passed", 0)) >= int(_stats.get("host_side_transits", 0)), "client: its player came out of every segment in the next room (%s)" % client_stats.get("side_passed"))
			if int(_stats.get("side_crumbles", 0)) > 0:
				_check(int(_stats.get("host_side_collapses", 0)) >= 1, "host: its ledges crumbled (%s of %s)" % [_stats.get("host_side_collapses"), _stats.get("side_crumbles")])
				_check(client_stats.get("side_collapses", -2) == _stats.get("host_side_collapses", -1) and client_stats.get("side_crumble_events", -2) == _stats.get("host_side_crumble_events", -1),
						"the client's ledges shook, fell and came back with the host's (%s / %s changes, %s falls)" % [client_stats.get("side_crumble_events"), _stats.get("host_side_crumble_events"), client_stats.get("side_collapses")])
			_check(int(_stats.get("host_side_moves", 0)) >= 1 and client_stats.get("side_moves", -2) == _stats.get("host_side_moves", -1),
					"every move of the host's player in a segment reached the client (%s / %s; %s played)" % [client_stats.get("side_moves"), _stats.get("host_side_moves"), client_stats.get("side_moves_applied")])
			_check(int(client_stats.get("side_moves_applied", 0)) >= 1, "client: the host's moves played on its copy (%s)" % client_stats.get("side_moves_applied"))
			_check(client_stats.get("side_double_jumps", -2) == _stats.get("host_side_double_jumps", -1),
					"every double jump of the host's player played (salto) on the client (%s / %s)" % [client_stats.get("side_double_jumps"), _stats.get("host_side_double_jumps")])
			var host_shots := int(_stats.get("host_side_turret_shots", 0))
			var client_shots := int(client_stats.get("side_turret_shots", -1))
			_check(host_shots >= 1 and absi(client_shots - host_shots) <= 1,
					"TRAPS: the host's turret shots played on the client (%d / %d; events %s / %s)" % [client_shots, host_shots, client_stats.get("side_turret_events"), _stats.get("host_side_turret_events")])
			var host_spikes := int(_stats.get("host_side_spike_events", 0))
			var client_spikes := int(client_stats.get("side_spike_events", -1))
			_check(host_spikes >= 3 and client_spikes >= host_spikes * 0.8 and client_spikes <= host_spikes,
					"TRAPS: the host's spike phases played on the client (%d / %d)" % [client_spikes, host_spikes])
		elif str(_args.get("side", "0")) == "1":
			_check(false, "side=1: at least one side segment in the tested rooms")
		if not str(_args.get("modes", "")).is_empty():
			_check(int(_stats.get("mode_count", 0)) >= 2, "at least two different room modes were played (%s)" % _stats.get("mode_count"))
			_check(int(client_stats.get("mode_events", 0)) > 0 or int(_stats.get("mode_events", 0)) == 0, "mode events reached the client (%s / %s)" % [client_stats.get("mode_events"), _stats.get("mode_events")])
			_check(client_stats.get("mode_bonus", -2) == _stats.get("mode_bonus", -1) and int(_stats.get("mode_finished", 0)) > 0,
					"every mode room ended with the host's bonus on the client too (%s rooms)" % _stats.get("mode_finished"))
			_check(client_stats.get("mode_chest_hash", -2) == _stats.get("mode_chest_hash", -1),
					"the client's bonus chests stand where the host's stand (%s / %s chests)" % [client_stats.get("mode_chests"), _stats.get("mode_chests")])
		if int(_stats.get("branches", 0)) > 0:
			_check(int(client_stats.get("way_signatures", 0)) >= 2 * int(_stats.get("branches", 0)), "the client compared both built ways of every branch (%s)" % client_stats.get("way_signatures"))
			_check(int(client_stats.get("branch_choices", 0)) == int(_stats.get("branches", 0)), "the client took the host's way (%s / %s)" % [client_stats.get("branch_choices"), _stats.get("branches")])
		elif str(_args.get("branch", "0")) == "1":
			_check(false, "branch=1: at least one branch in the tested rooms")
	await _seconds(0.5)
	for role in ["client", "late"]:
		for line in _read_file(_client_log_path(role)).split("\n", false):
			if line.begins_with("ERROR") or line.begins_with("SCRIPT ERROR") or line.begins_with("WARNING"):
				_say("  %s log| %s" % [role, line])
	for pid in _pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)


## end=two_runs, host: the relay opened the room again (end_run after run 1); a late joiner comes
## into the village; run 2 for three players, rooms 1-2, portal; end_run again.
func _host_second_run() -> void:
	var run_manager := root.get_node("RunManager")
	if not await _until(func() -> bool: return _lobby.runs_ended == 1, "relay confirmed the end of run 1 (run_ended)"):
		return
	_check(_lobby.last_run_end_reason == "portal", "run 1 ended with reason portal at the relay (%s)" % _lobby.last_run_end_reason)
	_check(not _lobby.is_run_started(), "room back in the lobby (started false)")
	_spawn_client("late", LATE_INSTANCE)
	if not await _until(func() -> bool: return _players().size() == 3 and _lobby.get_room_peers().size() == 3, "late joiner is in the host's village (3 players)", STARTUP_TIMEOUT):
		return
	var late_peer := int(_lobby.get_room_peers()[2].get("peerId", 0))
	var late_name := str(_lobby.get_room_peers()[2].get("name", ""))
	_check_look(_player_for_peer(late_peer), late_name, "host")
	await _seconds(1.0)
	var start_gold: int = root.get_node("SaveManager").get_permanent_gold()
	_lobby.last_error = ""
	_lobby.net_run.start()
	if not await _until(func() -> bool: return _dungeon() != null and _net() != null, "host entered run 2"):
		return
	_say("run 2: seed %d" % _lobby.net_run.seed_value)
	await _until(func() -> bool: return _lobby.is_run_started(), "relay started run 2 (no room_started)")
	_check(_lobby.last_error == "", "no relay error at the second start (%s)" % _lobby.last_error)
	_check(_lobby.net_run.runs_begun == 2, "run number 2 on the host")
	_check(_lobby.net_run.player_count == 3 and _controller.game_mode.get_player_count() == 3, "run 2 is scaled for 3 players (%d)" % _controller.game_mode.get_player_count())
	_check(_lobby.net_run.participants.size() == 3, "run 2 has 3 participants for the report")
	if not await _until(func() -> bool: return _players().size() == 3 and _net().get_ready_peers().size() == 2, "both clients loaded run 2 (3 players)", STARTUP_TIMEOUT):
		return
	for player in _players():
		player.health.reset(99999.0)
	if not await _until(func() -> bool: return _dungeon().get_active_room_index() == 1 and _room(1).is_encounter_started(), "run 2: room 1 starts once everybody is there"):
		return
	_lobby.net_run.last_report_status = ""
	for index in range(1, SECOND_RUN_ROOMS + 1):
		if not await _host_room(index, SECOND_RUN_ROOMS):
			return
	_dungeon().end_run(2)
	if not await _until(func() -> bool: return not run_manager.is_run_active(), "run 2 ended for the host"):
		return
	var summary: Dictionary = run_manager.get_last_summary()
	_check(int(summary.get("reason", -1)) == 2, "run 2: portal for everybody")
	_stats["r2_host_pot"] = int(summary.get("remaining_gold", -1))
	_stats["r2_host_payout"] = int(summary.get("payout", -1))
	_stats["r2_host_room"] = int(summary.get("room", -1))
	_check(_stats["r2_host_payout"] == _stats["r2_host_pot"], "run 2: 100 %% of the pot (%d)" % _stats["r2_host_payout"])
	_check(root.get_node("SaveManager").get_permanent_gold() - start_gold == _stats["r2_host_payout"], "run 2: village gold booked")
	await _close_run_end()
	await _until(func() -> bool: return _world_name() == &"Village" and _players().size() == 3, "host back in the village with both clients after run 2")
	await _until(func() -> bool: return _lobby.runs_ended == 2, "relay confirmed the end of run 2 (run_ended)")
	_check(_lobby.last_run_end_reason == "portal" and not _lobby.is_run_started(), "room in the lobby again after run 2")
	await _until(func() -> bool: return _lobby.net_run.last_report_status != "", "run 2 report finished")
	_check(_lobby.net_run.last_report_status == "sent", "host reported run 2 (POST /runs, 3 participants)")


## One room on the host: the group is in, the fight is won (the client's bot first), dialogs are
## answered, the exit opens; then the group moves on (room 2 -> 3 tests the wait for a straggler).
func _host_room(index: int, last_room := -1) -> bool:
	var dungeon := _dungeon()
	var room: Node = _room(index)
	if room == null:
		_check(false, "room %d prepared on the host" % index)
		return false
	if not await _until(func() -> bool: return dungeon.get_active_room_index() == index and room.state != 0, "room %d active on the host" % index):
		return false
	var type_name: String = ROOM_TYPES[room.room_type]
	var variant: Node = room.get_node_or_null("CombatVariant")
	_note_mode(room)
	if index >= 2 and type_name != "SPECIAL" and _has_weapon_test() and last_room < 0 and not _switch_started:
		# Not awaited: the room goes on meanwhile.
		_switch_started = true
		_switch_round(_local_player(), _weapon_pair()[0])
	_say("room %d: %s%s%s" % [index, type_name, (" " + SPECIAL_TYPES[room.special_type]) if type_name == "SPECIAL" else "",
			(" mode " + String(variant.variant_id)) if variant != null else ""])
	if type_name == "SPECIAL":
		if room.special_type == 0 and root.get_node("RunManager").get_run_gold() < 100:
			# Only when the pot is short (the client buys as soon as it holds 100): a later top-up
			# would change the pot under its purchase check (second shop of rooms=16).
			root.get_node("RunManager").add_run_gold(SHOP_TEST_GOLD)
		# The client acts in the special room (shop, weapon); give it time.
		await _seconds(6.0)
	else:
		await _until(func() -> bool: return _living_enemies(room).size() > 0, "room %d has enemies" % index)
		_stats["enemies_room_%d" % index] = _living_enemies(room).size()
		var start_damage := _client_player_damage_dealt()
		await _seconds(BOT_FIGHT_SECONDS)
		_skip_boss_intros()
		if variant != null and variant.get(&"torches") is Array:
			# Lichtfeuer: every fire burns, so the stone guardians can be broken.
			for torch: Node in variant.get(&"torches"):
				torch.ignite(_local_player())
		if variant != null and variant.has_method(&"step"):
			# Raid timers and the like: forward, as in mp_local_sim.
			variant.step(41.0)
		if index == 1:
			# Enemies come out of their sources one after another (R2: 1 s warning, 0.5 s unhittable):
			# the bot may need longer than BOT_FIGHT_SECONDS to reach the first one.
			await _until(func() -> bool: return _client_player_damage_dealt() > start_damage, "the client's bot hits enemies through the host", BOT_HIT_TIMEOUT)
		# Until the room is done: arenas pause 2 s between waves (R3), sources need 1.5 s to let an
		# enemy out (R2, unhittable meanwhile).
		for sweep in 60:
			if room.state == ROOM_CLEARED:
				break
			if variant != null and variant.has_method(&"step"):
				# Mode clocks (souls round, escort way, collapse) run on faster.
				variant.step(2.0)
			var remaining := _living_enemies(room)
			var players := _players()
			for i in remaining.size():
				_kill(remaining[i], players[i % players.size()])
			await _seconds(0.4)
		_check(room.state == ROOM_CLEARED and _living_enemies(room).is_empty(), "room %d cleared on the host" % index)
	if type_name == "COMBAT_UPGRADE":
		await _seconds(1.0)
		await _answer_upgrade()
	if room.is_branch_room():
		# Branch (D-105): the host's group walks up to the first door, the client builds that way too.
		await _until(func() -> bool: return room.get_branch_choice().is_offered, "room %d offers two ways" % index, STEP_TIMEOUT * 2)
		var tiles: Node = room.get_node("Tiles")
		var door: Vector2i = tiles.get_exit_doors()[0]
		var inside: Vector2i = tiles.inside_tile_of(door.x, door.y, tiles.room_size)
		for player in _players():
			player.global_position = room.to_global(tiles.position + _tile_center(inside))
		await _until(func() -> bool: return room.get_chosen_branch() == 0, "room %d: the group chose way 1" % index)
		_stats["branches"] = int(_stats.get("branches", 0)) + 1
	if not await _until(func() -> bool: return room._exit_door.is_open, "room %d exit open on the host" % index, STEP_TIMEOUT * 2):
		return false
	if type_name == "COMBAT_UPGRADE":
		_check(_net().upgrade_rounds >= 1, "upgrade round ran on the host")
	if index >= (last_room if last_room > 0 else _rooms):
		return true
	var from_room: Node = room
	var campfire: Node = dungeon.get_campfire(index)
	if campfire != null:
		# After a boss: the campfire is a room without a number (D-103); the group rests there first.
		_place_group(campfire)
		if not await _until(func() -> bool: return dungeon.get_active_slot() == campfire.slot_index, "campfire after room %d active" % index):
			return false
		await _seconds(2.0)
		from_room = campfire
	var next: Node = _room(index + 1)
	if next == null:
		_check(false, "room %d prepared" % (index + 1))
		return false
	var side_gate: Node = from_room.get_node_or_null("SideGate")
	if side_gate != null and not side_gate.is_used:
		return await _host_side(side_gate, next)
	if index == 2:
		# Exit rule (online test 15.10.2026): only the host walks in - room 3 waits for the client, no
		# countdown, no teleport; then the client walks in and it starts.
		var host_player := _local_player()
		var net := _net()
		host_player.global_position = _walk_in_points(next, 1)[0]
		await _until(func() -> bool: return net.get(&"_waiting_room") == next, "host alone in room 3: the room waits")
		await _until(func() -> bool: return net.get_wait_hint() == 1, "host: \"Warte auf ...\" while it waits")
		_say("  host hint: %s" % net.get(&"_countdown_label").text)
		await _seconds(STRAGGLER_WAIT)
		var client_player := _remote_player()
		_check(dungeon.get_active_room_index() == index, "room 3 did not start without the client (%.0f s, no countdown)" % STRAGGLER_WAIT)
		_check(client_player != null and not next.get_arena().has_point(client_player.global_position), "the straggler was not teleported into room 3")
		var walked := Time.get_ticks_msec()
		_place_group(next)
		await _until(func() -> bool: return dungeon.get_active_room_index() == index + 1, "room 3 starts once the client is in")
		_check(Time.get_ticks_msec() - walked < 3000, "room 3 started right after the client came in")
		_check(net.living_teleports == 0, "host: no living player was teleported (%d)" % net.living_teleports)
		_check(net.get_wait_hint() == 0, "host: the hint is gone once the room started")
		_stats["straggler_room"] = true
	else:
		_place_group(next)
	return true


## M5: the way into next runs through a side segment. The group walks into the gate, the host's player
## runs with the autopilot, the client's bot runs at the client; the first at the door ends it, the
## transit puts everybody into next and the room starts by the exit rule.
func _host_side(gate: Node, next: Node) -> bool:
	var side: Node = _net().side
	var finished_before: int = side.segments_finished
	var players := _players()
	for player in players:
		player.global_position = gate.global_position
	if not await _until(func() -> bool:
		var running: Node = side.get_segment()
		return running != null and running.is_inside_tree() and running.get_players().size() == players.size(), "host: the whole group is in the side segment into room %d" % next.room_index, 15.0):
		return false
	_stats["side_segments"] = int(_stats.get("side_segments", 0)) + 1
	var segment: Node = side.get_segment()
	var all_side := true
	for player in players:
		all_side = all_side and player.is_side_view()
	_check(all_side, "host: every player moves in side view")
	_check(segment.camera_targets().size() == players.size(), "host: the segment camera keeps the group (%d)" % segment.camera_targets().size())
	var local := _local_player()
	# The fade ends before anybody may move (SideTransit locks input meanwhile).
	await _seconds(1.0)
	# Round 2: every ledge crumbles as if somebody stood on it (the host decides, the clients follow).
	for crumble: Node in segment.get_crumbles():
		crumble.touch()
	_stats["side_crumbles"] = int(_stats.get("side_crumbles", 0)) + segment.get_crumbles().size()
	var bot: RefCounted = load("res://dungeon/side/side_bot.gd").drive(segment, local)
	if not await _until(func() -> bool: return side.segments_finished > finished_before, "host: the group reached the door of the segment", 60.0):
		_say("  segment %s, feet %s, door %s, locked %s, protected %s, on floor %s, climbing %s, pit falls %d" % [segment.layout.plan_id,
				segment.to_local(local.get_feet_position()), segment.to_local(segment.get_door_feet()), local.is_input_locked(),
				local.is_protected(), local.side_motion.is_on_floor(), local.side_motion.is_climbing(), local.side_motion.pit_falls])
		_say("  physics %s, velocity %s, last axis %s, stunned %s, alive %s, paused %s, time scale %.2f, bot path %s" % [local.is_physics_processing(),
				local.velocity, local.side_motion.get_last_input().axis, local.is_stunned(), local.is_alive(), paused, Engine.time_scale, bot.get(&"_path")])
		return false
	local.side_motion.input_source = Callable()
	if not await _until(func() -> bool: return _dungeon().get_active_room_index() == next.room_index, "room %d starts after the segment" % next.room_index, 15.0):
		return false
	var inside := 0
	for player in _players():
		if next.get_arena().has_point(player.global_position) and not player.is_side_view():
			inside += 1
	_check(inside == players.size(), "both players came out of the segment in room %d (%d)" % [next.room_index, inside])
	return true


## Makeover checks of the host (every scenario): gate, group camera, side ways.
func _host_makeover_checks(net: Node) -> void:
	_stats["host_gates"] = net.gates_closed
	_stats["host_camera"] = net.max_camera_targets
	_stats["host_side_ways"] = net.side.ways_announced
	_stats["host_side_transits"] = net.side.transits
	_stats["host_side_finished"] = net.side.segments_finished
	_stats["host_side_sig"] = hash(",".join(net.side.signatures)) & 0x7fffffff
	_stats["host_side_crumble_events"] = net.side.crumble_events
	_stats["host_side_collapses"] = net.side.crumble_collapses
	_stats["host_side_moves"] = net.side.moves_sent_own
	_stats["host_side_double_jumps"] = net.side.double_jumps_sent_own
	_stats["host_side_turret_events"] = net.side.turret_events
	_stats["host_side_turret_shots"] = net.side.turret_shots
	_stats["host_side_spike_events"] = net.side.spike_events
	_check(net.gates_closed_early == 0, "host: no gate shut while a living player was outside the new room (%d gates)" % net.gates_closed)
	if _rooms >= 2 and _is_portal():
		_check(net.gates_closed >= 1, "host: gates shut behind the group (%d)" % net.gates_closed)
	_check(net.max_camera_targets >= 2, "host: the group camera held both players (%d)" % net.max_camera_targets)
	if str(_args.get("side", "0")) == "1":
		_check(int(_stats.get("side_segments", 0)) >= 1 and net.side.transits == int(_stats.get("side_segments", 0)), "host: side segments played (%d)" % net.side.transits)
		_check(net.side.max_players_in_segment == 2 and net.side.max_camera_targets == 2, "host: both players in the segment and its camera (%d / %d)" % [net.side.max_players_in_segment, net.side.max_camera_targets])


## The client's player goes down; the host's player stands next to it and gets it up (D-084).
func _host_revive() -> void:
	var client_player := _remote_player()
	var host_player := _local_player()
	if client_player == null or host_player == null:
		_check(false, "both players for the revive test")
		return
	host_player.global_position = client_player.global_position + Vector2(200, 0)
	await _seconds(0.5)
	client_player.health.take_damage(999999.0)
	_check(client_player.is_downed() and root.get_node("RunManager").is_run_active(), "client player down, the run goes on")
	await _seconds(1.5)
	_check(client_player.is_downed(), "still down while nobody helps")
	host_player.global_position = client_player.global_position + Vector2(24, 0)
	var started := Time.get_ticks_msec()
	await _until(func() -> bool: return client_player.is_alive(), "host's player revives the client's player", 8.0)
	var took := float(Time.get_ticks_msec() - started) / 1000.0
	_check(took >= 1.8, "revive took about 2 s (%.1f s)" % took)
	_check(is_equal_approx(client_player.health.get_health(), 2.0), "revived with 2 HP (%.1f)" % client_player.health.get_health())


## P-027: the relay got a JWT for this player (aud soulwick-relay), not the session token.
func _check_relay_token() -> void:
	var jwt: String = _session.relay_token
	var claims := {}
	var parts := jwt.split(".")
	if parts.size() == 3:
		var text := parts[1].replace("-", "+").replace("_", "/")
		while text.length() % 4 != 0:
			text += "="
		var parsed: Variant = JSON.parse_string(Marshalls.base64_to_raw(text).get_string_from_utf8())
		claims = parsed if parsed is Dictionary else {}
	_check(jwt != _session.token and claims.get("aud") == "soulwick-relay" and claims.get("sub") == _session.get_player_id(), "entered with a relay JWT (aud soulwick-relay, own player id), not the session token")


# --- Client ---

func _client() -> void:
	var box := {"code": ""}
	if not await _until(func() -> bool:
		box.code = _read_file(_code_path())
		return not box.code.is_empty(), "client got the room code"):
		return
	_lobby.join_room(box.code)
	if not await _until(func() -> bool: return _lobby.is_in_room() and _players().size() == 2, "client joined the room (2 players)"):
		_say("lobby error: %s" % _lobby.last_error)
		return
	_check_relay_token()
	var start_gold: int = root.get_node("SaveManager").get_permanent_gold()
	if not await _until(func() -> bool: return _dungeon() != null and _net() != null, "client entered the dungeon with the host", STEP_TIMEOUT * 2):
		return
	_check(_dungeon().seed_value == _lobby.net_run.seed_value and _dungeon().seed_value != 0, "same seed as the host (%d)" % _dungeon().seed_value)
	if not await _until(func() -> bool: return _players().size() == 2 and _local_player() != null, "client sees both players in the dungeon"):
		return
	var local := _local_player()
	local.input = load("res://player/input/remote_input.gd").new()
	if _has_weapon_test():
		await _client_weapons(local)
	_bot_enabled = true
	local.weapon_controller.attack_performed.connect(func(_w: Resource) -> void: _bot_attacks += 1)
	var run_manager := root.get_node("RunManager")
	var net := _net()
	var seen_puppets := 0
	var room_index := 0
	var downed_seen := false
	var revived_hp := -1.0
	var weapons_before: int = local.weapon_controller.get_owned_weapons().size()
	var weapons_now := weapons_before
	var deadline := Time.get_ticks_msec() + 600 * 1000
	while Time.get_ticks_msec() < deadline and run_manager.is_run_active():
		await process_frame
		var dungeon := _dungeon()
		if dungeon == null or not is_instance_valid(local):
			break
		weapons_now = local.weapon_controller.get_owned_weapons().size()
		var active: int = dungeon.get_active_room_index()
		if active != room_index and active > 0:
			room_index = active
			var room: Node = _room(active)
			_note_mode(room)
			_say("room %d active on the client (%s), pot %d" % [active, ROOM_TYPES[room.room_type] if room != null else "?", run_manager.get_run_gold()])
			if room != null and room.room_type == 2:
				_client_special(room)
			if active >= 2 and room != null and room.room_type != 2 and _has_weapon_test() and not _switch_started:
				_switch_started = true
				# Not awaited: rooms, dialogs and the revive go on meanwhile.
				_client_switch_round(local)
			if active == 3 and _scenario == "client_leaves":
				await _seconds(1.0)
				_say("client gives up and leaves the room")
				dungeon.end_run(1)
				break
		seen_puppets = maxi(seen_puppets, net.enemies.get_live_count())
		_watch_tunnels(net)
		_watch_side(local, dungeon)
		_skip_boss_intros()
		await _answer_upgrade_if_open()
		if not local.is_alive() and not downed_seen:
			downed_seen = true
			_say("own player is down")
			_check(run_manager.is_run_active(), "client: the run goes on while the host stands")
		if downed_seen and revived_hp < 0.0 and local.is_alive():
			revived_hp = local.health.get_health()
			_check(is_equal_approx(revived_hp, 2.0), "client: up again with 2 HP (%.1f)" % revived_hp)
			await _seconds(1.0)
			# Through the portal: the client asks, the host ends the run for everybody.
			_say("client uses the portal")
			dungeon.end_run(2)
	var expected_room := _rooms if _is_portal() else 3
	_check(room_index == expected_room, "client followed the host to room %d" % room_index)
	_check(seen_puppets > 0, "client saw puppets of the host's enemies (max %d alive)" % seen_puppets)
	_check(_bot_attacks > 0, "client's bot attacked (%d)" % _bot_attacks)
	_check(net.signature_mismatches == 0, "client built the same rooms as the host (0 mismatches, %d compared, %d ways)" % [net.signatures_checked, net.way_signatures_checked])
	_check(net.rng_mismatches == 0, "client drew every slot from the host's RNG state (0 mismatches)")
	_check(net.side.signature_mismatches == 0, "client planned the same side ways as the host (0 mismatches, %d compared)" % net.side.signatures_checked)
	_stats["gates"] = net.gates_closed
	_stats["camera"] = net.max_camera_targets
	_stats["wait_hints"] = net.wait_hints
	_stats["wait_arrow"] = net.wait_arrow_frames
	_stats["side_ways"] = net.side.ways_announced
	_stats["side_sig"] = hash(",".join(net.side.signatures)) & 0x7fffffff
	_stats["side_transits"] = net.side.transits
	_stats["side_finished"] = net.side.segments_finished
	_stats["side_players"] = net.side.max_players_in_segment
	_stats["side_camera"] = net.side.max_camera_targets
	_stats["side_crumble_events"] = net.side.crumble_events
	_stats["side_collapses"] = net.side.crumble_collapses
	_stats["side_moves"] = net.side.moves_received
	_stats["side_moves_applied"] = net.side.moves_applied
	_stats["side_double_jumps"] = net.side.double_jumps_applied
	_stats["side_turret_events"] = net.side.turret_events
	_stats["side_turret_shots"] = net.side.turret_shots
	_stats["side_spike_events"] = net.side.spike_events
	_stats["side_passed"] = int(_stats.get("side_passed", 0))
	_stats["tunnels"] = int(_stats.get("tunnels", 0))
	_stats["tunnel_frames"] = int(_stats.get("tunnel_frames", 0))
	_check(int(_stats.get("tunnel_tags_shown", 0)) == 0, "client: a player in a tunnel shows no name tag (%d frames in a tunnel)" % _stats["tunnel_frames"])
	if _is_portal() and _rooms >= 3:
		_check(_stats["tunnels"] >= 1, "client: rock over the passages behind the group (%d rooms)" % _stats["tunnels"])
	_stats["way_signatures"] = net.way_signatures_checked
	_stats["branch_choices"] = net.branch_choices
	_mode_stats(net)
	if _is_portal():
		_check(downed_seen and revived_hp > 0.0, "client: downed and revived")
		_check(weapons_now >= weapons_before, "client weapons kept")
	if not await _until(func() -> bool: return not run_manager.is_run_active(), "run ended for the client"):
		return
	var summary: Dictionary = run_manager.get_last_summary()
	var expected_reason := 2 if _is_portal() else 1
	_check(int(summary.get("reason", -1)) == expected_reason, "client: run ended with reason %d" % expected_reason)
	_stats["pot"] = int(summary.get("remaining_gold", -1))
	_stats["payout"] = int(summary.get("payout", -1))
	_stats["room"] = int(summary.get("room", -1))
	_stats["enemies"] = net.enemies.spawned_count
	_stats["upgrades"] = _stack_total(_dungeon().upgrade_manager) if _dungeon() != null else -1
	_stats["weapons"] = weapons_now
	if _has_weapon_test():
		_weapon_stats("client_own", "w_client_own")
		_weapon_stats("client_host", "w_client_host")
	_stats["deaths"] = net.enemies.died_count
	_stats["emerges"] = net.enemies.emerge_count
	# Rooms from plans (R2/R3): sources warn and open, puppets emerge, the wave state comes from the host.
	_check(net.progress_events > 0, "client: the host's wave state arrived (%d updates)" % net.progress_events)
	_check(net.enemies.emerge_count > 0, "client: puppets came out of spawn sources (%d)" % net.enemies.emerge_count)
	_check(net.enemies.source_events > 0, "client: spawn sources warned and opened (%d phases)" % net.enemies.source_events)
	var expected_payout: int = _stats["pot"] if expected_reason == 2 else ceili(_stats["pot"] * 0.5)
	_check(_stats["payout"] == expected_payout and _stats["pot"] > 0, "client: %s of the pot (%d of %d)" % ["100 %" if expected_reason == 2 else "50 %", _stats["payout"], _stats["pot"]])
	_check(root.get_node("SaveManager").get_permanent_gold() - start_gold == _stats["payout"], "client: village gold booked")
	_bot_enabled = false
	await _close_run_end()
	match _scenario:
		"portal":
			await _until(func() -> bool: return _world_name() == &"Village" and _players().size() == 2, "client back in the shared village with the host")
			await _until(func() -> bool: return int(_lobby.state) == 0 and _lobby.last_end_reason == "host_left", "host closed the room", STEP_TIMEOUT * 2)
		"two_runs":
			await _until(func() -> bool: return _world_name() == &"Village" and _players().size() >= 2, "client back in the shared village with the host")
			await _until(func() -> bool: return _lobby.runs_ended == 1, "client: relay reported the end of run 1 (run_ended)")
			_check(_lobby.last_run_end_reason == "portal" and not _lobby.is_run_started(), "client: room back in the lobby (%s)" % _lobby.last_run_end_reason)
			if not await _until(func() -> bool: return _players().size() == 3 and _lobby.get_room_peers().size() == 3, "client sees the late joiner in the village", STARTUP_TIMEOUT):
				return
			var late: Dictionary = _lobby.get_room_peers()[2]
			_check_look(_player_for_peer(int(late.get("peerId", 0))), str(late.get("name", "")), "client")
			await _client_second_run()
			await _until(func() -> bool: return int(_lobby.state) == 0 and _lobby.last_end_reason == "host_left", "host closed the room", STEP_TIMEOUT * 2)
		"host_leaves":
			_check(_lobby.last_end_reason == "host_left", "client: the host left (%s)" % _lobby.last_end_reason)
			await _until(func() -> bool: return _world_name() == &"Village" and not _controller.game_mode.is_networked() and _players().size() == 1, "client back in a solo village")
		"client_leaves":
			await _until(func() -> bool: return int(_lobby.state) == 0 and _world_name() == &"Village" and not _controller.game_mode.is_networked(), "client left the room: solo village")


## end=two_runs, late joiner: joins the room in the village after run 1, appears there with its own
## look, plays run 2 with the other two.
func _late() -> void:
	root.get_node("SaveManager").set_character_color(LATE_COLOR)
	var code := _read_file(_code_path())
	_lobby.join_room(code)
	if not await _until(func() -> bool: return _lobby.is_in_room() and _players().size() == 3, "late client joined the room between runs (3 players in the village)", STARTUP_TIMEOUT):
		_say("lobby error: %s" % _lobby.last_error)
		return
	_check_relay_token()
	_check(_world_name() == &"Village", "late client is in the shared village")
	await _until(func() -> bool: return _lobby.net_run.runs_begun == 1, "late client learned the room's run number (1)")
	var peers: Array = _lobby.get_room_peers()
	for i in 2:
		var peer: Dictionary = peers[i]
		var player := _player_for_peer(int(peer.get("peerId", 0)))
		var tag: Node = player.get_node_or_null("NameTag") if player != null else null
		_check(tag != null and tag.text == str(peer.get("name", "")), "late client sees P%d (%s)" % [i + 1, peer.get("name", "")])
	var local := _local_player()
	_check(local != null and local.get_node("NameTag").text == str(peers[2].get("name", "")), "late client's own player has its name")
	await _client_second_run()
	await _until(func() -> bool: return int(_lobby.state) == 0 and _lobby.last_end_reason == "host_left", "host closed the room", STEP_TIMEOUT * 2)


## end=two_runs, both clients: run 2 for three players, bot fights, the host ends it via the portal.
func _client_second_run() -> void:
	var run_manager := root.get_node("RunManager")
	var start_gold: int = root.get_node("SaveManager").get_permanent_gold()
	# The late joiner never heard run 1's run_ended: count from here.
	var ended_before: int = _lobby.runs_ended
	if not await _until(func() -> bool: return _dungeon() != null and _net() != null, "%s entered run 2 with the host" % _role, STARTUP_TIMEOUT):
		return
	_check(_dungeon().seed_value == _lobby.net_run.seed_value and _dungeon().seed_value != 0, "%s: same seed as the host in run 2" % _role)
	_check(_lobby.net_run.runs_begun == 2, "%s: run number 2 (%d)" % [_role, _lobby.net_run.runs_begun])
	_check(_lobby.net_run.player_count == 3 and _controller.game_mode.get_player_count() == 3, "%s: run 2 is scaled for 3 players" % _role)
	if not await _until(func() -> bool: return _players().size() == 3 and _local_player() != null, "%s sees all three players in run 2" % _role, STARTUP_TIMEOUT):
		return
	var local := _local_player()
	local.input = load("res://player/input/remote_input.gd").new()
	_bot_enabled = true
	var net := _net()
	var deadline := Time.get_ticks_msec() + 300 * 1000
	while Time.get_ticks_msec() < deadline and run_manager.is_run_active():
		await process_frame
		if _dungeon() == null:
			break
		_skip_boss_intros()
		await _answer_upgrade_if_open()
	_check(net.signature_mismatches == 0, "%s built the same rooms as the host in run 2" % _role)
	if not await _until(func() -> bool: return not run_manager.is_run_active(), "run 2 ended for %s" % _role):
		return
	var summary: Dictionary = run_manager.get_last_summary()
	_check(int(summary.get("reason", -1)) == 2, "%s: run 2 ended through the portal" % _role)
	_stats["r2_pot"] = int(summary.get("remaining_gold", -1))
	_stats["r2_payout"] = int(summary.get("payout", -1))
	_stats["r2_room"] = int(summary.get("room", -1))
	_check(_stats["r2_payout"] == _stats["r2_pot"], "%s: 100 %% of the pot in run 2 (%d)" % [_role, _stats["r2_payout"]])
	_check(root.get_node("SaveManager").get_permanent_gold() - start_gold == _stats["r2_payout"], "%s: run 2 village gold booked" % _role)
	_bot_enabled = false
	await _close_run_end()
	await _until(func() -> bool: return _world_name() == &"Village" and _players().size() == 3, "%s back in the village with everybody after run 2" % _role)
	await _until(func() -> bool: return _lobby.runs_ended == ended_before + 1 and _lobby.last_run_end_reason == "portal", "%s: relay reported the end of run 2 (portal)" % _role)


## The late joiner's player as another machine draws it: its name and its clothing colour.
func _check_look(player: Node, expected_name: String, who: String) -> void:
	if player == null:
		_check(false, "%s: the late joiner's player exists" % who)
		return
	var tag: Node = player.get_node_or_null("NameTag")
	_check(tag != null and tag.text == expected_name and not expected_name.is_empty(), "%s: late joiner's name tag (%s)" % [who, tag.text if tag != null else "?"])
	var color: Variant = player.appearance.get("color")
	_check(color is Color and (color as Color).is_equal_approx(LATE_COLOR), "%s: late joiner's clothing colour (%s)" % [who, color])
	_check(not player.is_local, "%s: the late joiner's player is remote" % who)


## Special room on the client: buy in the shop (the host validates), take a weapon.
func _client_special(room: Node) -> void:
	_say("special room: %s" % SPECIAL_TYPES[room.special_type])
	match room.special_type:
		0:
			_client_shop(room)
		1:
			_client_weapon(room)


func _client_shop(room: Node) -> void:
	var net := _net()
	var local := _local_player()
	var run_manager := root.get_node("RunManager")
	if not await _until(func() -> bool: return net.get(&"_shop_offers").has(room.slot_index) and run_manager.get_run_gold() >= 100, "client got the host's shop offers and the test gold"):
		return
	var offers: Array = net.get(&"_shop_offers")[room.slot_index]
	var chosen: RefCounted = null
	var weapon_slot := -1
	if _has_weapon_test():
		# weapons=: a weapon from the shop goes into the inactive slot (the host equips it, the
		# client gets it back with the loadout).
		var controller: Node = local.weapon_controller
		var free: int = controller.find_free_slot()
		var slot: int = free if free >= 0 else 1 - controller.get_active_slot()
		for offer in offers:
			if offer.weapon != null and _dungeon().economy.can_purchase(offer, local, _dungeon().upgrade_manager, slot):
				chosen = offer
				weapon_slot = slot
				break
	if chosen == null:
		for offer in offers:
			if _dungeon().economy.can_purchase(offer, local, _dungeon().upgrade_manager, -1):
				chosen = offer
				break
	if chosen == null:
		_say("no offer the client can buy")
		return
	var pot_before: int = run_manager.get_run_gold()
	_dungeon().economy.try_purchase(chosen, local, _dungeon().upgrade_manager, weapon_slot)
	_check(not chosen.sold and run_manager.get_run_gold() == pot_before, "client purchase waits for the host")
	await _until(func() -> bool: return chosen.sold and run_manager.get_run_gold() == pot_before - chosen.price, "host sold the offer to the client (pot -%d)" % chosen.price)
	if chosen.weapon != null:
		var bought: Resource = chosen.weapon
		await _until(func() -> bool: return local.weapon_controller.get_weapon(weapon_slot) == bought,
				"client: the bought %s arrived from the host in slot %d" % [bought.id, weapon_slot])
		_stats["shop_weapons"] = int(_stats.get("shop_weapons", 0)) + 1


func _client_weapon(room: Node) -> void:
	await _seconds(0.5)
	var local := _local_player()
	for content in room.get_children():
		for child in content.get_children():
			if child.get_script() != null and child.get_script().get_global_name() == &"Interactable" and child.enabled and String(child.prompt).ends_with("nehmen"):
				child.interact(local)
				await _seconds(0.3)
				await _answer_upgrade_if_open()
				var owned: int = local.weapon_controller.get_owned_weapons().size()
				_say("client took a weapon (%d owned)" % owned)
				return


# --- Bot (client) ---

## Client: after every side segment its own player must stand in the room the segment led into.
func _watch_side(local: Node, dungeon: Node) -> void:
	var on: bool = local.is_side_view()
	if _side_was_on and not on:
		_side_check_at = Time.get_ticks_msec() + 2500
	_side_was_on = on
	if _side_check_at > 0 and Time.get_ticks_msec() >= _side_check_at:
		_side_check_at = -1
		var room: Node = dungeon.get_room(dungeon.get_active_room_index())
		var inside: bool = room != null and room.get_arena().has_point(local.global_position)
		_say("client: out of the side segment, in room %d: %s" % [dungeon.get_active_room_index(), inside])
		if inside:
			_stats["side_passed"] = int(_stats.get("side_passed", 0)) + 1


## Client, M2 tunnels: the passage behind the active room has its rock here too (DoorView lintel),
## and a player who stays in a passage (local or the host's) shows no name tag (NetDungeon).
func _watch_tunnels(net: Node) -> void:
	var views: Array = net.call(&"_passage_views")
	var slot: int = _dungeon().get_active_slot()
	if slot >= 2 and slot != _tunnel_slot:
		_tunnel_slot = slot
		if not views.is_empty():
			_stats["tunnels"] = int(_stats.get("tunnels", 0)) + 1
	for player: Node in _players():
		var key := player.get_instance_id()
		if views.is_empty() or not net.call(&"in_tunnel", player):
			_tunnel_streak.erase(key)
			continue
		_stats["tunnel_frames"] = int(_stats.get("tunnel_frames", 0)) + 1
		_tunnel_streak[key] = _tunnel_streak.get(key, 0) + 1
		var tag: CanvasItem = player.get_node_or_null("NameTag")
		# A few frames of grace: NetDungeon hides the tag in its next physics step.
		if _tunnel_streak[key] > 3 and tag != null and tag.visible:
			_stats["tunnel_tags_shown"] = int(_stats.get("tunnel_tags_shown", 0)) + 1


## Client bot in a side segment: the autopilot's input goes through RemoteInput (and the network).
func _drive_side(local: Node, input: Object) -> void:
	var segment: Node = local.side_motion.get_world()
	if segment == null:
		return
	if _side_bot == null or _side_bot.segment != segment:
		_side_bot = load("res://dungeon/side/side_bot.gd").new()
		_side_bot.segment = segment
		_side_bot.player = local
	var step: RefCounted = _side_bot.next_input()
	input.set_move(step.axis)
	if step.jump_just_pressed:
		input.release(&"dash")
		input.press(&"dash")
	elif step.jump_pressed:
		input.press(&"dash")
	else:
		input.release(&"dash")
	if step.dash_just_pressed:
		input.tap(&"side_dash")


func _drive_bot() -> void:
	if not _bot_enabled or _bot_paused or _controller == null or not is_instance_valid(_controller):
		return
	var local := _local_player()
	var dungeon := _dungeon()
	if local == null or dungeon == null or not local.is_alive():
		return
	var input: Object = local.input
	if not input.has_method(&"set_move"):
		return
	if local.is_side_view():
		input.release(&"attack")
		_drive_side(local, input)
		return
	if _side_bot != null:
		_side_bot = null
		input.release(&"dash")
	var room: Node = dungeon.get_room(dungeon.get_active_room_index())
	var nearest: Node2D = null
	var best := INF
	if room != null:
		for enemy in _living_enemies(room):
			var distance: float = local.global_position.distance_to(enemy.global_position)
			if distance < best:
				best = distance
				nearest = enemy
	if nearest == null:
		input.set_move(Vector2.ZERO)
		input.release(&"attack")
		return
	input.set_aim_point(nearest.global_position)
	input.set_move((nearest.global_position - local.global_position).normalized() if best > STOP_DISTANCE else Vector2.ZERO)
	if best < ATTACK_RANGE:
		input.press(&"attack")
	else:
		input.release(&"attack")


# --- Weapons per player (weapons=) ---

func _has_weapon_test() -> bool:
	return _weapon_pair().size() == 2


## [host's weapon id, client's weapon id] from weapons=, empty without (or with an unknown id).
func _weapon_pair() -> Array[String]:
	var pair: Array[String] = []
	for id in str(_args.get("weapons", "")).split(",", false):
		if WEAPON_IDS.has(id.strip_edges()):
			pair.append(id.strip_edges())
	if pair.size() != 2:
		pair.clear()
	return pair


static func _weapon_data(id: String) -> Resource:
	return load("res://weapons/data/%s.tres" % id)


static func _weapon_id_of(weapon: Object) -> String:
	return String(weapon.id) if weapon != null else ""


static func _active_id(player: Node) -> String:
	if player == null or not is_instance_valid(player):
		return ""
	return _weapon_id_of(player.weapon_controller.get_active_weapon())


static func _append_change(list: Array, id: String) -> void:
	if list.is_empty() or list[-1] != id:
		list.append(id)


## Logs the active weapon (on every change) and the weapon of every attack of player under key.
func _track_weapons(player: Node, key: String) -> void:
	var log := {"active": [], "attacks": []}
	_weapon_logs[key] = log
	var controller: Node = player.weapon_controller
	var note := func() -> void: _append_change(log["active"], _weapon_id_of(controller.get_active_weapon()))
	controller.weapon_changed.connect(func(_slot: int, _weapon: Resource) -> void: note.call())
	controller.active_slot_changed.connect(func(_slot: int) -> void: note.call())
	controller.attack_performed.connect(func(weapon: Resource) -> void: _append_change(log["attacks"], _weapon_id_of(weapon)))
	note.call()


## STAT values of a weapon log: hashes of both lists (and their lengths). The start weapon every
## player has (sword) is dropped from the front of the active list: whether the other machine saw it
## before the owner switched depends only on who was faster.
func _weapon_stats(key: String, prefix: String) -> void:
	var log: Dictionary = _weapon_logs.get(key, {"active": [], "attacks": []})
	for part in ["active", "attacks"]:
		var list: Array = (log[part] as Array).duplicate()
		if part == "active" and not list.is_empty() and list[0] == "sword":
			list.remove_at(0)
		_stats["%s_%s" % [prefix, part]] = hash(",".join(PackedStringArray(list))) & 0x7fffffff
		_stats["%s_%s_n" % [prefix, part]] = list.size()
	_say("weapons %s: active %s, attacks %s" % [key, log["active"], log["attacks"]])


## The owner's machine: id goes into the second slot (like a weapon pedestal: equip_weapon at the
## owner, the network brings it to the others) and the switch button makes it the active weapon.
func _hold_weapon(player: Node, id: String) -> void:
	await _until(func() -> bool: return not player.is_input_locked() and not player.is_protected(), "%s: own player free to switch weapons" % _role)
	if id != "sword":
		var controller: Node = player.weapon_controller
		_check(controller.equip_weapon(_weapon_data(id), 1), "%s: own player got the %s" % [_role, id])
		await _seconds(0.5)
		player.input.tap(&"switch_weapon")
	await _until(func() -> bool: return _active_id(player) == id, "%s: own player holds the %s" % [_role, id])


func _attack_for(player: Node, seconds: float) -> void:
	player.input.press(&"attack")
	await _seconds(seconds)
	player.input.release(&"attack")


## First fight room from room 2 on: the other slot, attack, back, attack (no-op with a single weapon).
func _switch_round(player: Node, id: String) -> void:
	if id == "sword" or player == null:
		return
	await _until(func() -> bool: return not player.is_input_locked() and not player.is_protected(), "%s: free to switch (room %d)" % [_role, _dungeon().get_active_room_index()])
	player.input.set_move(Vector2.ZERO)
	var before := _active_id(player)
	player.input.tap(&"switch_weapon")
	await _until(func() -> bool: return _active_id(player) != before, "%s: switched away from the %s" % [_role, before])
	await _attack_for(player, WEAPON_ATTACK_SECONDS)
	await _seconds(0.3)
	var other := _active_id(player)
	player.input.tap(&"switch_weapon")
	await _until(func() -> bool: return _active_id(player) != other, "%s: switched back" % _role)
	await _attack_for(player, WEAPON_ATTACK_SECONDS)
	_stats["switch_rounds"] = int(_stats.get("switch_rounds", 0)) + 1


## Client: the bot rests while its player switches there and back.
func _client_switch_round(local: Node) -> void:
	_bot_paused = true
	await _switch_round(local, _weapon_pair()[1])
	_bot_paused = false


## Host, right after room 1 started: its weapon, an attack with it, then it sees the client's.
func _host_weapons() -> void:
	var pair := _weapon_pair()
	var local := _local_player()
	var copy := _remote_player()
	local.input = load("res://player/input/remote_input.gd").new()
	_track_weapons(local, "host_own")
	_track_weapons(copy, "host_client")
	await _hold_weapon(local, pair[0])
	await _attack_for(local, WEAPON_ATTACK_SECONDS)
	await _until(func() -> bool: return _active_id(copy) == pair[1], "host: the client's player holds the client's %s" % pair[1])
	var sprite: Texture2D = copy.get_node("WeaponPivot/WeaponSprite").texture
	_check(sprite == _weapon_data(pair[1]).sprite, "host: the client's player shows the %s sprite" % pair[1])


## Client, before its bot fights: its weapon, then it sees the host's.
func _client_weapons(local: Node) -> void:
	var pair := _weapon_pair()
	var copy := _remote_player()
	_track_weapons(local, "client_own")
	_track_weapons(copy, "client_host")
	await _hold_weapon(local, pair[1])
	await _until(func() -> bool: return _active_id(copy) == pair[0], "client: the host's player holds the host's %s" % pair[0])
	var sprite: Texture2D = copy.get_node("WeaponPivot/WeaponSprite").texture
	_check(sprite == _weapon_data(pair[0]).sprite, "client: the host's player shows the %s sprite" % pair[0])
	var own_sprite: Texture2D = local.get_node("WeaponPivot/WeaponSprite").texture
	_check(own_sprite == _weapon_data(pair[1]).sprite, "client: its own player shows the %s sprite" % pair[1])


## Host, at the end: both machines saw the same weapons per player, in the same order.
func _check_weapon_logs(client_stats: Dictionary) -> void:
	var pair := _weapon_pair()
	_check(int(_stats.get("client_hits_" + pair[1], 0)) > 0, "host: the client's hits carry its %s (by weapon: %s)" % [pair[1], _hit_summary()])
	for part in ["active", "attacks"]:
		_check(client_stats.get("w_client_own_" + part, -2) == _stats.get("w_host_client_" + part, -1),
				"the client's %s weapons are the same on the host (%s / %s entries)" % [part, client_stats.get("w_client_own_%s_n" % part), _stats.get("w_host_client_%s_n" % part)])
		_check(client_stats.get("w_client_host_" + part, -2) == _stats.get("w_host_own_" + part, -1),
				"the host's %s weapons are the same on the client (%s / %s entries)" % [part, client_stats.get("w_client_host_%s_n" % part), _stats.get("w_host_own_%s_n" % part)])
	if pair[0] != "sword":
		_check(int(_stats.get("switch_rounds", 0)) == 1, "host: switched there and back in a fight room")
	if pair[1] != "sword":
		_check(int(client_stats.get("switch_rounds", 0)) == 1, "client: switched there and back in a fight room")
		_check(int(client_stats.get("w_client_own_active_n", 0)) >= 3, "client: own weapon, switch, back (%s changes)" % client_stats.get("w_client_own_active_n"))


func _hit_summary() -> String:
	var parts: Array[String] = []
	for id in WEAPON_IDS:
		if _stats.has("client_hits_" + id):
			parts.append("%s %d" % [id, _stats["client_hits_" + id]])
	return ", ".join(parts)


# --- Helpers ---

func _dungeon() -> Node:
	var world: Node = _controller.get_world() if _controller != null else null
	return world if world != null and world.get_script() != null and world.get_script().get_global_name() == &"DungeonManager" else null


func _net() -> Node:
	var dungeon := _dungeon()
	return dungeon.get_node_or_null("NetDungeon") if dungeon != null else null


func _world_name() -> StringName:
	var world: Node = _controller.get_world() if _controller != null else null
	return world.get_script().get_global_name() if world != null and world.get_script() != null else &""


func _room(index: int) -> Node:
	var dungeon := _dungeon()
	return dungeon.get_room(index) if dungeon != null else null


func _players() -> Array:
	var result: Array = []
	if _controller == null:
		return result
	for player in _controller.players:
		if is_instance_valid(player):
			result.append(player)
	return result


func _player_for_peer(peer_id: int) -> Node:
	for player in _players():
		if player.name == "Net%d" % peer_id:
			return player
	return null


func _local_player() -> Node:
	for player in _players():
		if player.is_local:
			return player
	return null


func _remote_player() -> Node:
	for player in _players():
		if not player.is_local:
			return player
	return null


func _living_enemies(room: Node) -> Array:
	var result: Array = []
	for node in room.enemy_container.get_children():
		if _is_enemy(node) and not node.is_dead():
			result.append(node)
	return result


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


## Hits of the client's player on the host (EventBus.enemy_damaged with the client player as source).
func _skip_boss_intros() -> void:
	for node in root.find_children("*", "Node", true, false):
		if node.get_script() != null and node.get_script().get_global_name() == &"BossIntro":
			node.skip()


func _client_player_damage_dealt() -> int:
	return int(_stats.get("client_hits", 0))


func _place_group(room: Node) -> void:
	var players := _players()
	var points := _walk_in_points(room, maxi(2, players.size()))
	for i in players.size():
		players[i].global_position = points[mini(i, points.size() - 1)]


## Global centres of free floor tiles nearest to the middle of a room.
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
		points.append(room.to_global(tiles.position + (Vector2(tile) + Vector2(0.5, 0.5)) * 64.0))
		if points.size() >= count:
			break
	if points.is_empty():
		points.append(room.to_global(tiles.get_floor_rect().get_center()))
	return points


static func _stack_total(manager: Object) -> int:
	var total := 0
	if manager == null:
		return -1
	var stacks: Dictionary = manager.get_all_stacks()
	for id in stacks:
		total += int(stacks[id])
	return total


static func _tile_center(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * 64.0


func _find_modal(node: Node) -> Node:
	for child in node.get_children():
		if child.get_script() != null and child.get_script().get_global_name() == &"Modal" and not child.is_queued_for_deletion():
			return child
		var found := _find_modal(child)
		if found != null:
			return found
	return null


## Picks the first card of an open upgrade choice (each player for themselves, D-126).
func _answer_upgrade() -> void:
	for attempt in 60:
		var modal := _find_modal(root)
		if modal != null and modal.pause_reason == &"upgrade_choice":
			await _seconds(0.5)
			if is_instance_valid(modal) and not modal.is_queued_for_deletion():
				var hotkey: Callable = modal.hotkeys.get(KEY_1, Callable())
				if hotkey.is_valid():
					hotkey.call()
				_say("%s picked an upgrade" % _role)
			return
		await _seconds(0.1)


func _answer_upgrade_if_open() -> void:
	var modal := _find_modal(root)
	if modal != null and modal.pause_reason == &"upgrade_choice":
		await _answer_upgrade()
	elif modal != null and modal.pause_reason == &"weapon_choice":
		modal.finish(0)


func _close_run_end() -> void:
	# Read the run end like a player would (the host's last packets of the dungeon arrive meanwhile).
	await _seconds(1.0)
	for attempt in 100:
		var modal := _find_modal(root)
		if modal != null and modal.pause_reason == &"run_end":
			modal.finish(&"village")
			return
		await _seconds(0.1)
	_check(false, "%s: run end screen shown" % _role)


func _until(condition: Callable, label: String, timeout := STEP_TIMEOUT) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			_check(true, label)
			return true
		await process_frame
	_check(false, label + " (timeout %.0f s)" % timeout)
	return false


func _seconds(duration: float) -> void:
	await create_timer(duration, true).timeout


func _check(ok: bool, label: String) -> void:
	_say(("PASS " if ok else "FAIL ") + label)
	if not ok:
		_failures.append(label)


func _say(line: String) -> void:
	print("[%s %7.1f] %s" % [_role, Time.get_ticks_msec() / 1000.0, line])
	_log.append(line)


func _spawn_client(role := "client", instance := CLIENT_INSTANCE) -> int:
	var args := PackedStringArray(["--headless", "--log-file", ProjectSettings.globalize_path(_client_log_path(role)),
		"--path", ProjectSettings.globalize_path("res://"), "-s", "res://tools/net_run_smoke.gd", "--",
		"role=%s" % role, "run=%s" % _run_id, "instance=%d" % instance, "rooms=%d" % _rooms, "end=%s" % _scenario,
		"api=%s" % _args.get("api", DEFAULT_API), "relay=%s" % _args.get("relay", DEFAULT_RELAY)])
	if _args.has("dev_key"):
		args.append("dev_key=%s" % _args.dev_key)
	for key in ["modes", "mode_from", "branch", "side", "weapons"]:
		if _args.has(key):
			args.append("%s=%s" % [key, _args[key]])
	var pid := OS.create_process(OS.get_executable_path(), args)
	_check(pid > 0, "%s process started" % role)
	_pids.append(pid)
	return pid


func _code_path() -> String:
	return "user://net_run_smoke_%s.code" % _run_id


func _client_log_path(role := "client") -> String:
	return "user://net_run_smoke_%s_%s.log" % [_run_id, role]


func _result_path(role := _role) -> String:
	return "user://net_run_smoke_%s_%s.result" % [_run_id, role]


## Waits for a client's result file, prints it and returns its STAT values.
func _read_result(role: String) -> Dictionary:
	var box := {"text": ""}
	await _until(func() -> bool:
		box.text = _read_file(_result_path(role))
		return not box.text.is_empty(), "%s finished" % role, STEP_TIMEOUT * 3)
	var result: String = box.text
	var stats := {}
	for line in result.split("\n", false):
		_say("  %s| %s" % [role, line])
		if line.begins_with("STAT "):
			var pair := line.substr(5).split("=")
			if pair.size() == 2:
				stats[pair[0]] = int(pair[1])
	_check(result.contains("RESULT OK"), "%s checks passed" % role)
	return stats


## The run ends through the portal (end=portal, and run 1 of end=two_runs).
func _is_portal() -> bool:
	return _scenario == "portal" or _scenario == "two_runs"


func _write_result() -> void:
	for key in _stats:
		_log.append("STAT %s=%d" % [key, _stats[key]])
	_log.append("RESULT OK" if _failures.is_empty() else "RESULT FAIL")
	_write_file(_result_path(), "\n".join(_log))


func _write_file(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


func _read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path).strip_edges()

extends SceneTree
## Two-instance network test of MP2 (ROADMAP): a headless host and a headless client
## (second Godot process, started by the host) against a running soulwick-api and soulwick-relay.
## Both log in with the dev login, the host creates a quick room, the client joins by its code;
## checked on the way (PASS/FAIL lines, exit code 1 on any failure):
## - the relay gets a player JWT from GET /auth/token in hello, never the session token (P-027:
##   aud soulwick-relay, sub = own player id); the client's rejoin reuses the cached JWT;
## - both see two players in the village (MultiplayerSpawner, appearance from the profile);
## - the client's movement input reaches the host, the host moves the client's player and its
##   position comes back to the client (MultiplayerSynchronizer), the client settles on it;
## - the client leaves cleanly (host: back to one player) and joins again;
## - the host leaves: the room closes for the client (host_left, D-123), both are solo again.
## Usage (API and relay running, see docs/MULTIPLAYER.md §3b):
##   godot --headless --path . -s tools/net_smoke.gd -- api=http://localhost:3102 relay=ws://localhost:3103/v1 dev_key=<DEV_AUTH_KEY>
## The dev key can also come from the environment (SOULWICK_DEV_KEY). spawn_client=0 starts no
## client (start it yourself with role=client run=<id>). Real time, no --fixed-fps.
## load=<enemies> (network load, online test 16.10.2026): instead of the village checks the host
## starts a run, puts both players into room 1 and adds that many enemies (archers, skeletons,
## slimes, shadows) to its encounter; for load_seconds (default 20) the client's player walks and
## dashes in a square, both players stay alive. Both print their traffic (NetDiagnostics: frames,
## game packets and bytes per second in both directions, round trip, buffers, longest hitch) and
## the corrections of the own player (snaps). hitch=<seconds> hitch_role=client|host freezes that
## process once in the middle of the window (what a hang does to the other side and the relay).
## With hitch_role=host (a host whose browser tab went into the background, D-183) the client must
## notice the host's stall and must not pull its own player back; the host must notice its own gap.
## In every load run the client must not see a host stall while joining and at the run start (the
## host's beats and load announcement, D-183 follow-up).
## SOULWICK_NET_BUNDLE=0 compares without bundles; relay=ws://127.0.0.1:<port>/v1 of an own relay
## started with --sim-latency=<ms> adds latency.
## Classes are accessed dynamically: this script is compiled before autoloads exist.

const DEFAULT_API := "http://localhost:3102"
const DEFAULT_RELAY := "ws://localhost:3103/v1"
const HOST_INSTANCE := 11
const CLIENT_INSTANCE := 12
## Seconds for each step (TESTWERT; generous for RELAY_SIM_LATENCY_MS runs).
const STEP_TIMEOUT := 20.0
## Seconds the host waits for the client process to boot, log in and join (slow on a busy machine).
const STARTUP_TIMEOUT := 120.0
## px the client's player must move on the host and back on the client.
const MOVE_DISTANCE := 60.0
## px the client's own player may differ from the host's position once both stand still.
const SETTLE_TOLERANCE := 4.0

var _role := "host"
var _run_id := ""
var _args: Dictionary = {}
var _failures: Array[String] = []
var _log: Array[String] = []
var _controller: Node = null
var _lobby: Node = null
var _session: Node = null
## GET /auth/token calls of this process (P-027).
var _relay_token_requests := 0


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
	_say("net_smoke %s, run %s, api %s, relay %s" % [_role, _run_id, _args.get("api", DEFAULT_API), _args.get("relay", DEFAULT_RELAY)])
	var save_manager := root.get_node("SaveManager")
	var save_path := "user://net_smoke_%s_save.cfg" % _role
	save_manager.save_path = save_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	save_manager.load_game()
	save_manager.settings_path = "user://net_smoke_%s_settings.cfg" % _role
	save_manager.load_settings()
	change_scene_to_file("res://scenes/game.tscn")
	await _seconds(0.5)
	_controller = current_scene.get_node("WorldController")
	# Own online file per role (instance 11/12), dev key from the arguments or SOULWICK_DEV_KEY.
	var config: RefCounted = config_script.new()
	config.instance = int(_args.get("instance", CLIENT_INSTANCE if _role == "client" else HOST_INSTANCE))
	config.path = config_script.INSTANCE_FILE_PATH % config.instance
	config.settings_path = config.path
	var with_defaults := {"api": DEFAULT_API, "relay": DEFAULT_RELAY, "name": "Smoke Client" if _role == "client" else "Smoke Host"}
	with_defaults.merge(_args, true)
	if not with_defaults.has("dev_key") and not OS.get_environment("SOULWICK_DEV_KEY").is_empty():
		with_defaults["dev_key"] = OS.get_environment("SOULWICK_DEV_KEY")
	_args = with_defaults
	config.load_from(_args)
	var session: Node = load("res://online/session.gd").new(config)
	session.name = "OnlineSession"
	current_scene.add_child(session)
	_session = session
	session.api.request_finished.connect(func(path: String, result: RefCounted) -> void:
		if path == "/auth/token":
			_relay_token_requests += 1
			_say("  GET /auth/token: %s" % result.describe()))
	_lobby = load("res://online/lobby_client.gd").of(_controller)
	# Event trail for failed runs.
	var api := get_multiplayer()
	api.peer_connected.connect(func(id: int) -> void: _say("  peer_connected %d" % id))
	api.peer_disconnected.connect(func(id: int) -> void: _say("  peer_disconnected %d" % id))
	_controller.player_spawned.connect(func(player: Node) -> void:
		_say("  player %s registered (local %s), %d players" % [player.name, player.is_local, _player_count()])
		player.tree_exiting.connect(func() -> void: _say("  player %s leaves the world" % player.name)))
	_lobby.state_changed.connect(func(state: int) -> void: _say("  lobby state %d" % state))
	_lobby.session_ended.connect(func(reason: String) -> void: _say("  session ended: %s" % reason))
	var load_test := int(_args.get("load", "0")) > 0
	if _role == "client":
		if load_test:
			await _client_load()
		else:
			await _client()
		_write_result()
	elif load_test:
		await _host_load()
	else:
		await _host()
	var ok := _failures.is_empty()
	_say("net_smoke %s: %s" % [_role, "PASSED" if ok else "FAILED (%d)" % _failures.size()])
	for failure in _failures:
		_say("  - " + failure)
	quit(0 if ok else 1)


# --- Host ---

func _host() -> void:
	_lobby.create_room()
	if not await _until(func() -> bool: return _lobby.is_in_room(), "host created a room"):
		_say("lobby error: %s" % _lobby.last_error)
		return
	var code: String = _lobby.get_room_code()
	_say("room code %s" % code)
	_check_relay_token()
	_write_file(_code_path(), code)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_result_path()))
	var client_pid := -1
	if str(_args.get("spawn_client", "1")) != "0":
		client_pid = _spawn_client()
	await _until(func() -> bool: return _player_count() == 2, "host sees 2 players", STARTUP_TIMEOUT)
	var client_player: Node = _remote_player()
	_check(client_player != null, "host has the client's player (Net<peer>)")
	if client_player != null:
		var start_x: float = client_player.position.x
		await _until(func() -> bool: return is_instance_valid(client_player) and client_player.position.x - start_x >= MOVE_DISTANCE, "client input moves its player on the host (+%d px)" % MOVE_DISTANCE)
		_check(client_player.get(&"appearance") is Dictionary and not (client_player.get(&"appearance") as Dictionary).is_empty(), "client player wears the client's profile")
	await _until(func() -> bool: return _player_count() == 1 and _lobby.get_room_peers().size() == 1, "client left: host back to 1 player")
	await _until(func() -> bool: return _player_count() == 2, "client joined again: 2 players")
	await _seconds(1.0)
	_lobby.leave()
	await _until(func() -> bool: return int(_lobby.state) == 0 and not _controller.game_mode.is_networked() and _player_count() == 1, "host left: solo village again")
	var box := {"text": ""}
	await _until(func() -> bool:
		box.text = _read_file(_result_path())
		return not box.text.is_empty(), "client finished", STEP_TIMEOUT * 3)
	var result: String = box.text
	for line in result.split("\n", false):
		_say("  client| " + line)
	_check(result.contains("RESULT OK"), "client checks passed")
	# Engine errors and warnings of the client process (its full log: user://net_smoke_<run>_client.log).
	await _seconds(0.5)
	for line in _read_file(_client_log_path()).split("\n", false):
		if line.begins_with("ERROR") or line.begins_with("WARNING") or line.begins_with("SCRIPT ERROR"):
			_say("  client log| " + line)
	if client_pid > 0 and OS.is_process_running(client_pid):
		OS.kill(client_pid)


func _spawn_client() -> int:
	var args := PackedStringArray(["--headless", "--log-file", ProjectSettings.globalize_path(_client_log_path()),
		"--path", ProjectSettings.globalize_path("res://"), "-s", "res://tools/net_smoke.gd", "--",
		"role=client", "run=%s" % _run_id, "instance=%d" % CLIENT_INSTANCE,
		"api=%s" % _args.get("api", DEFAULT_API), "relay=%s" % _args.get("relay", DEFAULT_RELAY)])
	if _args.has("dev_key"):
		args.append("dev_key=%s" % _args.dev_key)
	for key in ["load", "load_seconds", "hitch", "hitch_role"]:
		if _args.has(key):
			args.append("%s=%s" % [key, _args[key]])
	var pid := OS.create_process(OS.get_executable_path(), args)
	_check(pid > 0, "client process started")
	return pid


# --- Client ---

func _client() -> void:
	var box := {"code": ""}
	if not await _until(func() -> bool:
		box.code = _read_file(_code_path())
		return not box.code.is_empty(), "client got the room code"):
		return
	var code: String = box.code
	_lobby.join_room(code)
	if not await _until(func() -> bool: return _lobby.is_in_room(), "client joined %s" % code):
		_say("lobby error: %s" % _lobby.last_error)
		return
	_check_relay_token()
	if not await _until(func() -> bool: return _player_count() == 2 and _controller.local_player != null, "client sees 2 players (own + host)"):
		return
	var own: Node = _controller.local_player
	var state: Node = own.get_node("NetState")
	_check(_remote_player() != null and not _remote_player().is_local, "host's player is remote on the client")
	var start_x: float = state.pos.x
	Input.action_press(&"move_right")
	await _seconds(1.0)
	Input.action_release(&"move_right")
	await _until(func() -> bool: return is_instance_valid(state) and state.pos.x - start_x >= MOVE_DISTANCE, "host position of the own player synced back (+%d px)" % MOVE_DISTANCE)
	await _seconds(1.5)
	if not is_instance_valid(state):
		_check(false, "own player still there after moving")
		return
	var gap: float = own.position.distance_to(state.pos)
	_check(gap <= SETTLE_TOLERANCE, "own player settled on the host position (gap %.1f px)" % gap)
	_lobby.leave()
	await _until(func() -> bool: return int(_lobby.state) == 0 and not _controller.game_mode.is_networked(), "client left cleanly")
	await _seconds(1.0)
	_lobby.join_room(code)
	await _until(func() -> bool: return _lobby.is_in_room() and _player_count() == 2, "client joined again")
	_check(_relay_token_requests == 1, "rejoin reused the cached relay JWT (%d x GET /auth/token)" % _relay_token_requests)
	await _until(func() -> bool: return int(_lobby.state) == 0 and _lobby.last_end_reason == "host_left", "host leaving closed the room (host_left)", STEP_TIMEOUT * 2)
	await _until(func() -> bool: return not _controller.game_mode.is_networked() and _player_count() == 1, "client back in a solo village")


# --- Load test (load=<enemies>) ---

func _host_load() -> void:
	_lobby.create_room()
	if not await _until(func() -> bool: return _lobby.is_in_room(), "host created a room"):
		return
	_write_file(_code_path(), _lobby.get_room_code())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_result_path()))
	var client_pid := -1
	if str(_args.get("spawn_client", "1")) != "0":
		client_pid = _spawn_client()
	if not await _until(func() -> bool: return _player_count() == 2, "host sees the client in the village", STARTUP_TIMEOUT):
		return
	await _seconds(1.0)
	_lobby.net_run.start(int(_args.get("seed", "0")))
	if not await _until(func() -> bool: return _dungeon() != null and _net() != null, "host entered the dungeon"):
		return
	if not await _until(func() -> bool: return _player_count() == 2 and _net().get_ready_peers().size() == 1, "client loaded the dungeon", STARTUP_TIMEOUT):
		return
	await _seconds(1.0)
	var dungeon := _dungeon()
	var room: Node = dungeon.get_room(maxi(1, dungeon.get_active_room_index()))
	_keep_alive_players()
	_place_players(room)
	if not await _until(func() -> bool: return room.is_encounter_started(), "room %d started with both players inside" % room.room_index):
		return
	await _until(func() -> bool: return _living_enemies(room).size() > 0, "room has enemies")
	var extra := int(_args.get("load", "30"))
	_spawn_load(room, extra)
	await _seconds(2.0)
	_say("load: %d living enemies in room %d" % [_living_enemies(room).size(), room.room_index])
	var diagnostics: Object = _diagnostics()
	var start: Dictionary = diagnostics.mark()
	var load_seconds := float(_args.get("load_seconds", "20"))
	var hitch_done := false
	var deadline := Time.get_ticks_msec() + int(load_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		_keep_alive_players()
		if not hitch_done and str(_args.get("hitch_role", "")) == "host" and Time.get_ticks_msec() > deadline - int(load_seconds * 500.0):
			hitch_done = true
			_hitch()
		await _seconds(0.25)
		if _living_enemies(room).size() < extra / 2:
			_spawn_load(room, extra / 2)
	_report_load(diagnostics, start)
	# 2000 ms = HostStall.HOST_AWAY_NOTICE_MSEC.
	if hitch_done and float(_args.get("hitch", "0")) * 1000.0 >= 2000.0 and _lobby.peer != null:
		_check(int(_lobby.peer.host_away_count) >= 1, "the host noticed its own stall (%d ms)" % int(_lobby.peer.last_host_away_msec))
	_check(_lobby.is_in_room(), "host still in the room after the load")
	_lobby.leave()
	var box := {"text": ""}
	await _until(func() -> bool:
		box.text = _read_file(_result_path())
		return not box.text.is_empty(), "client finished", STEP_TIMEOUT * 3)
	for line in str(box.text).split("\n", false):
		_say("  client| " + line)
	_check(str(box.text).contains("RESULT OK"), "client checks passed")
	await _seconds(0.5)
	for line in _read_file(_client_log_path()).split("\n", false):
		if line.begins_with("ERROR") or line.begins_with("WARNING") or line.begins_with("SCRIPT ERROR"):
			_say("  client log| " + line)
	if client_pid > 0 and OS.is_process_running(client_pid):
		OS.kill(client_pid)


func _client_load() -> void:
	var box := {"code": ""}
	if not await _until(func() -> bool:
		box.code = _read_file(_code_path())
		return not box.code.is_empty(), "client got the room code"):
		return
	_lobby.join_room(box.code)
	if not await _until(func() -> bool: return _lobby.is_in_room(), "client joined"):
		return
	if not await _until(func() -> bool: return _dungeon() != null and _net() != null and _player_count() == 2 and _controller.local_player != null, "client in the dungeon with both players", STEP_TIMEOUT * 2):
		return
	var extra := int(_args.get("load", "30"))
	if not await _until(func() -> bool: return _net().enemies.get_live_count() >= extra / 2, "client sees the load (%d+ puppets)" % (extra / 2), STEP_TIMEOUT * 2):
		return
	var diagnostics: Object = _diagnostics()
	# Joining, the host's world change and this client's own dungeon load (hide_from_peers: no world
	# data for a while, only the host's beats and its load announcement) are no host stall.
	_check(int(diagnostics.totals.get("host_stalls", 0)) == 0, "no host stall noticed while joining and at the run start (%d)" % int(diagnostics.totals.get("host_stalls", 0)))
	var start: Dictionary = diagnostics.mark()
	var state: Node = _controller.local_player.get_node("NetState")
	var snaps_before: int = state.snap_count
	var load_seconds := float(_args.get("load_seconds", "20"))
	var started := Time.get_ticks_msec()
	var hitch_done := false
	var directions := [&"move_right", &"move_down", &"move_left", &"move_up"]
	var step := 0
	var peak_puppets := 0
	var snaps := 0
	var host_stalls := 0
	var locked_frames := 0
	while _lobby.is_in_room() and Time.get_ticks_msec() - started < int((load_seconds + 30.0) * 1000.0):
		var held: StringName = directions[step % directions.size()]
		Input.action_press(held)
		if step % 3 == 0:
			Input.action_press(&"dash")
		await _seconds(0.15)
		Input.action_release(&"dash")
		await _seconds(0.55)
		Input.action_release(held)
		step += 1
		peak_puppets = maxi(peak_puppets, _net().enemies.get_live_count() if _net() != null else 0)
		if is_instance_valid(state):
			snaps = state.snap_count - snaps_before
			if state.is_host_stalled():
				locked_frames += 1
		host_stalls = int(diagnostics.totals.get("host_stalls", 0)) - int(start.get("host_stalls", 0))
		if not hitch_done and str(_args.get("hitch_role", "")) == "client" and Time.get_ticks_msec() - started > int(load_seconds * 500.0):
			hitch_done = true
			_hitch()
	_say("load: up to %d puppets, own player snapped back %d times, host stalls noticed %d (longest %d ms, %d steps waiting)" % [
		peak_puppets, snaps, host_stalls, diagnostics.longest_host_stall_msec, locked_frames])
	if str(_args.get("hitch_role", "")) == "host" and float(_args.get("hitch", "0")) >= 1.0:
		_check(host_stalls >= 1, "the client noticed the host's stall (%d)" % host_stalls)
		_check(snaps == 0, "the own player was not pulled back while the host stood still (%d)" % snaps)
	_report_load(diagnostics, start)
	_check(_lobby.last_end_reason == "host_left", "the session ended because the host left (%s)" % _lobby.last_end_reason)


func _report_load(diagnostics: Object, start: Dictionary) -> void:
	var averages: Dictionary = diagnostics.since(start)
	_say("load %s averages over %.1f s: out %.1f frames/s, %.1f packets/s, %.0f B/s; in %.1f frames/s, %.1f packets/s, %.0f B/s; dropped out %d in %d, send errors %d, relay errors %d, hitches %d" % [
		_role, averages.seconds, averages.frames_out_per_s, averages.packets_out_per_s, averages.bytes_out_per_s,
		averages.frames_in_per_s, averages.packets_in_per_s, averages.bytes_in_per_s,
		averages.dropped_out, averages.dropped_in, averages.send_errors, averages.relay_errors, averages.hitches])
	_say("load %s diagnostics: %s" % [_role, diagnostics.summary_line()])
	_check(int(averages.send_errors) == 0 and int(averages.relay_errors) == 0, "%s: no send or relay errors under load" % _role)


func _hitch() -> void:
	var seconds := float(_args.get("hitch", "0"))
	if seconds <= 0.0:
		return
	_say("freezing this process for %.1f s" % seconds)
	OS.delay_msec(int(seconds * 1000.0))
	_say("awake again")


func _diagnostics() -> Object:
	return _lobby.peer.diagnostics


func _keep_alive_players() -> void:
	for player in _controller.players:
		if is_instance_valid(player) and player.health.get_health() < 5000.0:
			player.health.reset(99999.0)


## Both players into the middle of the room (the client's own player follows the host: far off = snap).
func _place_players(room: Node) -> void:
	var middle: Vector2 = room.get_arena().get_center()
	var offsets := [Vector2(-40, 0), Vector2(40, 0)]
	var i := 0
	for player in _controller.players:
		if is_instance_valid(player):
			player.global_position = middle + offsets[mini(i, 1)]
			i += 1


func _spawn_load(room: Node, count: int) -> void:
	var scene: PackedScene = load("res://enemies/enemy_base.tscn")
	var net_enemies: GDScript = load("res://online/net_enemies.gd")
	var ids := [&"archer", &"skeleton", &"slime", &"shadow", &"archer", &"skeleton"]
	var arena: Rect2 = room.get_arena()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	for i in count:
		var data: Resource = net_enemies.data_for(ids[i % ids.size()])
		if data == null:
			continue
		var enemy: Node2D = scene.instantiate()
		enemy.set(&"data", data)
		enemy.set(&"arena", arena)
		var at := arena.get_center() + Vector2(rng.randf_range(-0.4, 0.4) * arena.size.x, rng.randf_range(-0.4, 0.4) * arena.size.y)
		enemy.position = room.enemy_container.to_local(at)
		enemy.apply_scaling(room.room_index, false)
		room.enemy_container.add_child(enemy)


func _living_enemies(room: Node) -> Array:
	var result: Array = []
	for node in room.enemy_container.get_children():
		if node.has_method(&"is_dead") and not node.is_dead():
			result.append(node)
	return result


func _dungeon() -> Node:
	var world: Node = _controller.get_world() if _controller != null else null
	return world if world != null and world.get_script() != null and world.get_script().get_global_name() == &"DungeonManager" else null


func _net() -> Node:
	var dungeon := _dungeon()
	return dungeon.get_node_or_null("NetDungeon") if dungeon != null else null

# --- Helpers ---

## P-027: the relay got a JWT for this player (aud soulwick-relay), not the session token.
func _check_relay_token() -> void:
	var jwt: String = _session.relay_token
	var claims := _jwt_claims(jwt)
	_check(jwt.split(".").size() == 3 and jwt != _session.token, "hello carried a relay JWT, not the session token")
	_check(claims.get("aud") == "soulwick-relay" and claims.get("sub") == _session.get_player_id(), "relay JWT: aud soulwick-relay, sub = own player id")


## Claims of a JWT without checking the signature (that is the relay's job).
static func _jwt_claims(jwt: String) -> Dictionary:
	var parts := jwt.split(".")
	if parts.size() != 3:
		return {}
	var text := parts[1].replace("-", "+").replace("_", "/")
	while text.length() % 4 != 0:
		text += "="
	var parsed: Variant = JSON.parse_string(Marshalls.base64_to_raw(text).get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


func _player_count() -> int:
	return _controller.players.size() if _controller != null else 0


## The first player in the world that is not this machine's.
func _remote_player() -> Node:
	for player in _controller.players:
		if is_instance_valid(player) and not player.is_local:
			return player
	return null


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
	print("[%s] %s" % [_role, line])
	_log.append(line)


func _code_path() -> String:
	return "user://net_smoke_%s.code" % _run_id


func _client_log_path() -> String:
	return "user://net_smoke_%s_client.log" % _run_id


func _result_path() -> String:
	return "user://net_smoke_%s.result" % _run_id


func _write_result() -> void:
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

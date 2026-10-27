class_name LobbyClient
extends Node
## Rooms on soulwick-relay for the UI (MP2, D-119, D-124): create_room(mode) and join_room(code),
## leave(); signals for the room list and errors. Logs in through OnlineSession first (dev login,
## D-121), fetches a short-lived player JWT for the relay's hello (GET /auth/token before every
## connection, P-027; the session token itself is only for the API), connects a RelayPeer and, once in the room, makes it the SceneTree's multiplayer peer
## (SceneMultiplayer, server_relay on), switches the session to a quick game (GameMode QUICK,
## D-081) whose players come from the network, and reloads the village so NetPlayers spawns
## everybody. Host gone, kicked, relay restart or a lost connection end the session (D-123): back to
## a solo village with a notice. Lives under the game scene like OnlineSession (of(), no autoload).
## The shared run (MP3, "Starten") lives in the child NetRun (online/net_run.gd) and, inside the
## dungeon, in NetDungeon. A room has any number of runs: the host's start closes it for joins, its
## end_run (back in the village) opens it again; run_ended reaches every member.
## Guild rooms (D-147): create_room(MODE_GUILD, guild_id); the relay lets only members of that guild
## join (not_guild_member). In a guild room the session is GameMode GUILD with the guild id, the run
## report goes out with mode guild (the API pays the treasury from it). Not here yet: the guild
## forge (MP8).
## The main menu has no game scene to hold a room: it stores the wish with request_launch() and the
## village of the started game runs it (take_launch(), VillageUI).
## A guild room belongs on its guild's page in the online menu: target_guild_id names the guild while
## the room is being created or joined from there (the room itself knows it once entered).
## Host stall (D-183): in a room the browser build keeps running in a hidden tab (WebKeepAlive, on
## from IN_ROOM to IDLE); the child HostStallNotice shows "Warte auf den Host …" on a client whose
## host stands still and tells a host afterwards that the others waited (RelayPeer.host_hitched).
## Invite by link (MP2b, D-190): a launch wish with via_link remembers the room as invite_code until
## the room is entered or the player gives up (give_up_invite, "Selbst spielen"). While that room's
## run is in progress (room_started) the client waits (invite_waiting) and tries again every
## INVITE_RETRY_SECONDS, only while the village is loaded: the player arrives once the run ends.

signal state_changed(state: State)
## The room snapshot changed (RoomInfo of the contract; {} when not in a room).
signal room_changed(room: Dictionary)
## A failure the player should see: relay error code (room_not_found, room_full …) or a local one
## (ERROR_*). error_text(code) gives the translated sentence.
signal error(code: String)
## The session is over (RoomClosedReason or "disconnected").
signal session_ended(reason: String)
## The relay confirmed the end of a run (run_ended): the room is in the lobby again, joins and
## start work. reason: RunEndReason ("portal", "wiped", "abandoned") or "".
signal run_ended(reason: String)

enum State { IDLE, LOGGING_IN, CONNECTING, IN_ROOM, LEAVING }

const GROUP: StringName = &"lobby_client"
## Preloaded: works before the global class cache knows NetDiagnostics (new file).
const NetDiagnosticsScript := preload("res://online/net_diagnostics.gd")
const HostStallNoticeScript := preload("res://online/host_stall_notice.gd")
const WebKeepAliveScript := preload("res://online/web_keep_alive.gd")
const MODE_QUICK := "quick"
const MODE_GUILD := "guild"
## Local error codes besides the relay's.
const ERROR_LOGIN := "login_failed"
const ERROR_NO_DEV_KEY := "no_dev_key"
const ERROR_API_UNREACHABLE := "api_unreachable"
const ERROR_RELAY_UNREACHABLE := "relay_unreachable"
const ERROR_TIMEOUT := "relay_timeout"
const ERROR_INVALID_CODE := "invalid_code"
const ERROR_BUSY := "busy"
## This build is older than minGameVersion of the API (MP4, OnlineVersionCheck).
const ERROR_UPDATE_REQUIRED := "update_required"
## The session expired or was revoked and no new login was possible (API 401 / relay 4001).
const ERROR_UNAUTHORIZED := "unauthorized"
## A guild room without a guild id.
const ERROR_NO_GUILD := "no_guild"
## Launch wishes of the main menu (request_launch): create a room, join one by code.
const LAUNCH_CREATE := "create"
const LAUNCH_JOIN := "join"
## TESTWERT (D-190): seconds between two join tries of an invite whose room is in a run.
const INVITE_RETRY_SECONDS := 5.0
## TESTWERT: seconds from connecting until the room must be entered.
const CONNECT_TIMEOUT := 10.0
## TESTWERT: seconds to wait for the relay's confirmation of a leave.
const LEAVE_TIMEOUT := 2.0

var state := State.IDLE
## Last room snapshot (RoomInfo), {} outside a room.
var room: Dictionary = {}
var peer: RelayPeer = null
## Last error code ("" if none) and the reason the last session ended.
var last_error := ""
var last_end_reason := ""
## Reason of the last run_ended of this room ("" if none or none given) and how many arrived.
var last_run_end_reason := ""
var runs_ended := 0
## For tests and tools: reload the village on entering/leaving (off when there is no village).
var reload_world := true
## Set by the UI that started create/join: reopen the room dialog in the reloaded village.
var resume_dialog := false
## Display name of the guild of a guild room this machine created or joined from the guild menu
## ("" if unknown, e.g. joined by room code).
var room_guild_name := ""
## Tag of that guild ("" if unknown), e.g. for "+21 Gold für [DOCHT]" after a guild run.
var room_guild_tag := ""
## Guild whose room is being created or joined from its page ("" for quick rooms or by code alone);
## the online menu shows the room there while it connects. Inside the room get_room_guild_id().
var target_guild_id := ""
## Name and tag of target_guild_id while joining from its page (room_guild_name/_tag once inside).
var _target_guild_name := ""
var _target_guild_tag := ""
## Room of an invite link this machine is on its way to ("" if none or once inside, MP2b).
var invite_code := ""
## The invite's room is in a run (room_started): join_room is tried again every INVITE_RETRY_SECONDS.
var invite_waiting := false
var _invite_retry_left := 0.0

## The main menu's wish for the next game scene ({} if none): {action, mode, guild_id, guild_name,
## guild_tag, code, via_link}. Static: it has to survive the scene change (no autoload, D-044).
static var _pending_launch: Dictionary = {}

var _session: OnlineSession = null
var _connect_left := 0.0
var _leave_left := 0.0
var _assigned := false
## Translation key of a notice for the next village (session end), "" if none.
var _pending_notice := ""
var _net_players: NetPlayers = null
## The shared run of this room (MP3), child "NetRun".
var net_run: NetRun = null
## "Warte auf den Host …" and the host's notes (D-183), child "HostStallNotice".
var stall_notice: HostStallNoticeScript = null


static func of(node: Node) -> LobbyClient:
	if node == null or not node.is_inside_tree():
		return null
	var tree := node.get_tree()
	var existing := tree.get_first_node_in_group(GROUP) as LobbyClient
	if existing != null:
		return existing
	var parent := tree.current_scene if tree.current_scene != null else tree.root
	var lobby := LobbyClient.new()
	lobby.name = "LobbyClient"
	parent.add_child(lobby)
	return lobby


## The lobby of the running game if one exists (does not create one).
static func find(node: Node) -> LobbyClient:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group(GROUP) as LobbyClient


## Lobby error code for a failed login or GET /auth/token (ApiResult).
static func login_error(result: ApiResult) -> String:
	if result == null:
		return ERROR_LOGIN
	match result.error:
		ApiResult.NO_DEV_KEY:
			return ERROR_NO_DEV_KEY
		ApiResult.UNREACHABLE, ApiResult.TIMEOUT:
			return ERROR_API_UNREACHABLE
		ApiResult.BANNED:
			return ApiResult.BANNED
		ApiResult.UNAUTHORIZED:
			return ERROR_UNAUTHORIZED
	return ERROR_LOGIN


## Translation key for an error or end reason, e.g. LOBBY_ERR_ROOM_FULL.
static func error_key(code: String) -> StringName:
	return StringName("LOBBY_ERR_%s" % code.to_upper())


## Translated sentence for an error or end reason (falls back to a generic one with the code).
static func error_text(code: String) -> String:
	var key := error_key(code)
	var text := Loc.t(key)
	return text if text != String(key) else Loc.t(&"LOBBY_ERR_GENERIC", [code])


## Main menu: remember to create a room (mode quick or guild with its id) or to join one by code
## once the game's village is loaded (VillageUI runs it, run_launch()).
## via_link: the code came from an invite link (MP2b): failures are explained with a way out.
static func request_launch(action: String, mode := MODE_QUICK, guild_id := "", guild_name := "", code := "", guild_tag := "", via_link := false) -> void:
	_pending_launch = {"action": action, "mode": mode, "guild_id": guild_id, "guild_name": guild_name, "guild_tag": guild_tag, "code": code, "via_link": via_link}


static func has_pending_launch() -> bool:
	return not _pending_launch.is_empty()


## Takes the main menu's wish ({} if none); it runs only once.
static func take_launch() -> Dictionary:
	var launch := _pending_launch
	_pending_launch = {}
	return launch


## Runs a launch wish of the main menu (take_launch()): create or join, the room dialog reopens
## in the village of the room (resume_dialog).
func run_launch(launch: Dictionary) -> void:
	resume_dialog = true
	match str(launch.get("action", "")):
		LAUNCH_CREATE:
			room_guild_name = str(launch.get("guild_name", ""))
			room_guild_tag = str(launch.get("guild_tag", ""))
			await create_room(str(launch.get("mode", MODE_QUICK)), str(launch.get("guild_id", "")))
		LAUNCH_JOIN:
			if bool(launch.get("via_link", false)):
				invite_code = RelayProtocol.normalize_code(str(launch.get("code", "")))
				invite_waiting = false
			# Joined from a guild's page: its name and tag are known (used only if it is that guild's
			# room, see _on_room_entered).
			await join_room(str(launch.get("code", "")), str(launch.get("guild_id", "")),
					str(launch.get("guild_name", "")), str(launch.get("guild_tag", "")))


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	net_run = NetRun.create(self)
	add_child(net_run)
	stall_notice = HostStallNoticeScript.new()
	add_child(stall_notice)


func _exit_tree() -> void:
	# The game scene goes (main menu): a browser tab may sleep again.
	WebKeepAliveScript.set_enabled(false)


func get_session() -> OnlineSession:
	if _session == null or not is_instance_valid(_session):
		_session = OnlineSession.of(self)
	return _session


func is_busy() -> bool:
	return state == State.LOGGING_IN or state == State.CONNECTING or state == State.LEAVING


func is_in_room() -> bool:
	return state == State.IN_ROOM


func is_host() -> bool:
	return peer != null and peer.is_host() and is_in_room()


func get_room_code() -> String:
	return str(room.get("code", ""))


## Mode of the current room ("quick" or "guild"; "" outside a room).
func get_room_mode() -> String:
	return str(room.get("mode", MODE_QUICK)) if is_in_room() else ""


## Guild id of a guild room ("" for quick rooms and outside).
func get_room_guild_id() -> String:
	var id: Variant = room.get("guildId", null)
	return str(id) if id != null and get_room_mode() == MODE_GUILD else ""


## The guild whose page shows this machine's room: the room's guild inside a guild room, the guild
## of a guild room being created or joined from its page while connecting, else "".
func get_guild_room_target() -> String:
	if is_in_room() or state == State.LEAVING:
		return get_room_guild_id()
	if state == State.LOGGING_IN or state == State.CONNECTING:
		return target_guild_id
	return ""


func is_guild_room() -> bool:
	return get_room_mode() == MODE_GUILD


## The relay has a run of this room in progress (started; no joins until the host's end_run).
func is_run_started() -> bool:
	return is_in_room() and bool(room.get("started", false))


## Own peer id in the room (1 = host), 0 outside.
func get_peer_id() -> int:
	return peer.get_unique_id() if peer != null and is_in_room() else 0


## Players of the room (RoomPeer: peerId, playerId, name, platform), host first.
func get_room_peers() -> Array:
	return room.get("peers", [])


## The players of the current world in the room (NetPlayers) or null.
func get_net_players() -> NetPlayers:
	return _net_players if _net_players != null and is_instance_valid(_net_players) else null


## Takes the notice for the village after a session ended ("" if none).
func take_notice() -> String:
	var key := _pending_notice
	_pending_notice = ""
	return key


## Host a room (mode quick, or guild with guild_id: only members of that guild may join, D-147).
func create_room(mode := MODE_QUICK, guild_id := "") -> void:
	if mode == MODE_GUILD and guild_id.is_empty():
		_fail(ERROR_NO_GUILD)
		return
	if mode != MODE_GUILD:
		room_guild_name = ""
		room_guild_tag = ""
	target_guild_id = guild_id if mode == MODE_GUILD else ""
	_target_guild_name = ""
	_target_guild_tag = ""
	await _enter(RelayProtocol.create(mode, guild_id))


## Join a room by its 6-character code (case and spaces do not matter). guild_id, guild_name,
## guild_tag: the guild whose page the player joins from ("" = by code alone, see target_guild_id);
## name and tag are taken over only if the room really is that guild's room.
func join_room(code: String, guild_id := "", guild_name := "", guild_tag := "") -> void:
	room_guild_name = ""
	room_guild_tag = ""
	target_guild_id = guild_id
	_target_guild_name = guild_name if not guild_id.is_empty() else ""
	_target_guild_tag = guild_tag if not guild_id.is_empty() else ""
	var normalized := RelayProtocol.normalize_code(code)
	if not RelayProtocol.is_valid_code(normalized):
		_fail(ERROR_INVALID_CODE)
		return
	await _enter(RelayProtocol.join(normalized))


## Leaves the room; as host this closes it for everybody (D-123).
func leave() -> void:
	if state == State.IN_ROOM and peer != null:
		_set_state(State.LEAVING)
		_leave_left = LEAVE_TIMEOUT
		peer.leave()
	elif state == State.CONNECTING or state == State.LOGGING_IN:
		_close_peer()
		_set_state(State.IDLE)


## Invite by link (MP2b): on the way to invite_code (also while it failed or waits for a run).
func has_invite() -> bool:
	return not invite_code.is_empty()


## The invite's join once more (after a failure, "Erneut versuchen").
func retry_invite() -> void:
	if invite_code.is_empty() or state != State.IDLE:
		return
	invite_waiting = false
	await join_room(invite_code)


## "Selbst spielen": the invite is dropped; a join on its way is cancelled, the village stays solo.
func give_up_invite() -> void:
	var was_invite := has_invite()
	invite_code = ""
	invite_waiting = false
	if was_invite and (state == State.LOGGING_IN or state == State.CONNECTING):
		leave()
	last_error = ""
	state_changed.emit(state)


## Host only: removes a player from the room.
func kick(peer_id: int) -> void:
	if is_host():
		peer.kick(peer_id)


## Host only (MP3): starts the shared dungeon run for everybody in the room (NetRun).
func start_run() -> void:
	if is_host() and net_run != null:
		net_run.start()


## Host only: the relay closes the room for new players while the run lasts (D-123).
func request_relay_start() -> void:
	if is_host():
		peer.start()


## Host only: the run is over and the group is back in the village; the relay opens the room for
## joins again (reason: RelayProtocol.RUN_END_*).
func request_relay_end_run(reason: String) -> void:
	if is_host():
		peer.end_run(reason)


## The WorldController of the game (null outside game.tscn).
func get_world_controller() -> WorldController:
	return _controller()


## Called by the WorldController for every new world before it enters the tree (MP3: the dungeon
## gets the run's seed and its NetDungeon).
func configure_world(world: Node) -> void:
	if peer != null:
		# Host: the world enters the tree in this frame (a long one on purpose); its clients are told
		# so they wait calmly instead of seeing "Warte auf den Host …" (D-183).
		peer.announce_loading()
	if net_run != null:
		net_run.configure_world(world)


## Called by the WorldController when the world loads in a networked session.
func attach_world(controller: Node, world: Node) -> void:
	if peer != null:
		# Loading the world was a long frame on purpose, not a hang the others waited through.
		peer.forgive_hitch()
	var profile := _local_profile()
	_net_players = NetPlayers.create(controller, world, profile)
	world.add_child(_net_players)


## The dungeon entrance in a room (MP3): the host starts the shared run, a client is told that
## the host starts it.
func on_dungeon_requested() -> void:
	if is_host():
		start_run()
		return
	var controller := _controller()
	var world: Node = controller.get_world() if controller != null else null
	var ui: Variant = world.get(&"ui") if world != null else null
	if ui is Object and (ui as Object).has_method(&"show_notice"):
		var lines: Array[String] = [Loc.t(&"LOBBY_DUNGEON_HOST_HINT")]
		ui.show_notice(Loc.t(&"LOBBY_DUNGEON_HOST"), lines)


func _process(delta: float) -> void:
	WebKeepAliveScript.update(delta)
	_wait_for_invite(delta)
	if peer == null:
		return
	# Until SceneMultiplayer owns the peer it is polled here.
	if not _assigned:
		peer.poll()
	if state == State.CONNECTING:
		_connect_left -= delta
		if _connect_left <= 0.0:
			_close_peer()
			_set_state(State.IDLE)
			_fail(ERROR_TIMEOUT)
	elif state == State.LEAVING:
		_leave_left -= delta
		if _leave_left <= 0.0:
			_end_session(RelayProtocol.CLOSED_LEFT)


## An invite whose room is in a run: try again every INVITE_RETRY_SECONDS while idle in the village
## (never in the dungeon of a solo run: entering the room reloads the village).
func _wait_for_invite(delta: float) -> void:
	if not invite_waiting or invite_code.is_empty() or state != State.IDLE:
		return
	_invite_retry_left -= delta
	if _invite_retry_left > 0.0:
		return
	_invite_retry_left = INVITE_RETRY_SECONDS
	var controller := _controller()
	if reload_world and (controller == null or not controller.get_world() is Village):
		return
	join_room(invite_code)


## "0.9.0" older than "1.0.0"? Numeric parts, pre-release suffixes ignored (OnlineConfig).
static func is_version_older(version: String, minimum: String) -> bool:
	return OnlineConfig.is_version_older(version, minimum)


func _enter(action: Dictionary) -> void:
	if state != State.IDLE:
		_fail(ERROR_BUSY)
		return
	# The main menu found this build too old for the API (MP4): no login, no relay.
	if OnlineVersionCheck.is_locked():
		_fail(ERROR_UPDATE_REQUIRED)
		return
	last_error = ""
	_set_state(State.LOGGING_IN)
	var session := get_session()
	if not session.is_node_ready():
		await session.ready
	var login := await session.ensure_login()
	if state != State.LOGGING_IN:
		return
	if not login.ok:
		_set_state(State.IDLE)
		_fail(login_error(login))
		return
	# GET /public/config names the oldest game version allowed online (P16).
	if OnlineVersionCheck.apply_config(session.public_config) == OnlineVersionCheck.Status.OUTDATED:
		_set_state(State.IDLE)
		_fail(ERROR_UPDATE_REQUIRED)
		return
	# The relay only takes the short-lived player JWT (P-027), fetched (or reused) per connection.
	var relay_token := await session.ensure_relay_token()
	if state != State.LOGGING_IN:
		return
	if not relay_token.ok:
		_set_state(State.IDLE)
		_fail(login_error(relay_token))
		return
	peer = RelayPeer.new()
	peer.room_entered.connect(_on_room_entered)
	peer.room_updated.connect(_on_room_updated)
	peer.room_left.connect(_on_room_left)
	peer.relay_error.connect(_on_relay_error)
	peer.connection_closed.connect(_on_connection_closed)
	peer.run_ended.connect(_on_run_ended)
	peer.host_hitched.connect(_on_host_hitched)
	var hello := RelayProtocol.hello(session.relay_token, OnlineConfig.PROTOCOL_VERSION, OnlineConfig.get_game_version(), OnlineConfig.get_platform())
	_assigned = false
	_connect_left = CONNECT_TIMEOUT
	_set_state(State.CONNECTING)
	if peer.open(RelayProtocol.prefer_ipv4_loopback(RelayProtocol.with_ws_path(session.get_relay_url())), hello, action) != OK:
		_close_peer()
		_set_state(State.IDLE)
		_fail(ERROR_RELAY_UNREACHABLE)


func _on_room_entered(new_room: Dictionary, entered_peer_id: int) -> void:
	room = new_room
	# Joined from a guild's page: that guild's name and tag, if this is its room.
	# (The state is not IN_ROOM yet: the snapshot is read directly.)
	if str(new_room.get("mode", "")) == MODE_GUILD and not target_guild_id.is_empty() \
			and str(new_room.get("guildId", "")) == target_guild_id and not _target_guild_name.is_empty():
		room_guild_name = _target_guild_name
		room_guild_tag = _target_guild_tag
	last_run_end_reason = ""
	runs_ended = 0
	invite_code = ""
	invite_waiting = false
	var tree := get_tree()
	var api := tree.get_multiplayer() as SceneMultiplayer
	if api != null:
		api.server_relay = true
	tree.get_multiplayer().multiplayer_peer = peer
	_assigned = true
	_set_state(State.IN_ROOM)
	var controller := _controller()
	if controller != null:
		var mode := create_session_mode()
		mode.network = self
		controller.set_game_mode(mode)
		if reload_world:
			controller.load_world(controller.village_scene)
	peer.set_delivering(true)
	room_changed.emit(room)
	# A host in the browser: its tab must stay alive for the others (D-183; a phone browser or an
	# energy saver may still stop it).
	if entered_peer_id == RelayProtocol.HOST_PEER_ID and WebKeepAliveScript.is_supported() and stall_notice != null:
		stall_notice.show_web_host_hint()


## Host: its own game stood still for gap_msec while teammates were in the room.
func _on_host_hitched(gap_msec: int) -> void:
	if stall_notice != null and is_host():
		stall_notice.show_host_away(gap_msec)


## The session of the current room: a guild run for guild rooms (GameMode GUILD with the guild
## id: run report mode guild, D-147), else a quick game (D-081: no village upgrades either way).
func create_session_mode() -> GameMode:
	if is_guild_room() and not get_room_guild_id().is_empty():
		return GameMode.guild(1, [0], get_room_guild_id())
	return GameMode.quick(1, [0])


func _on_room_updated(new_room: Dictionary) -> void:
	if state == State.IN_ROOM or state == State.LEAVING:
		room = new_room
		room_changed.emit(room)


## Every member, host included: the run is over, the room is in the lobby again (room_state with
## started false follows). The host's start button and joins work again.
func _on_run_ended(reason: String) -> void:
	if state != State.IN_ROOM:
		return
	last_run_end_reason = reason
	runs_ended += 1
	room["started"] = false
	if net_run != null:
		net_run.on_relay_run_ended(reason)
	run_ended.emit(reason)
	room_changed.emit(room)


func _on_room_left(reason: String) -> void:
	# Out of SceneMultiplayer's poll before the world changes.
	_end_session.call_deferred(reason)


func _on_relay_error(code: String, message: String, request: String) -> void:
	push_warning("Relay error %s (%s): %s" % [code, request, message])
	if state == State.CONNECTING:
		_close_peer()
		_set_state(State.IDLE)
		# The relay refused the JWT: the next try fetches a fresh one (the session may still be fine).
		if code == ERROR_UNAUTHORIZED:
			get_session().forget_relay_token()
		_fail(code)
	elif state == State.IN_ROOM and request in ["start", "kick", "end_run"]:
		# end_run while the room is already in the lobby: nothing to repair, nothing to show.
		if request == "end_run" and code == "room_not_started":
			return
		_fail(code)


func _on_connection_closed(code: int, reason: String) -> void:
	if state == State.CONNECTING:
		_close_peer()
		_set_state(State.IDLE)
		match code:
			RelayProtocol.CLOSE_UNAUTHORIZED:
				get_session().forget_relay_token()
				_fail(ERROR_UNAUTHORIZED)
			RelayProtocol.CLOSE_BANNED:
				_fail("banned")
			RelayProtocol.CLOSE_VERSION_MISMATCH:
				_fail("version_mismatch")
			_:
				_fail(ERROR_RELAY_UNREACHABLE)
	elif state == State.IN_ROOM or state == State.LEAVING:
		push_warning("Relay connection closed (%d %s)." % [code, reason])
		# The peer knows why (room_closed reason, own silence check), else the relay's close code
		# says it (shutdown, timeout, slow_consumer, rate_limited, banned or disconnected).
		var end_reason := peer.end_reason if peer != null and not peer.end_reason.is_empty() else RelayProtocol.end_reason_for_close(code)
		_end_session.call_deferred(end_reason)


## Back to a solo village; a notice explains why unless the player left on purpose.
func _end_session(reason: String) -> void:
	if state != State.IN_ROOM and state != State.LEAVING:
		return
	var left_on_purpose := state == State.LEAVING or reason == RelayProtocol.CLOSED_LEFT
	last_end_reason = reason
	if not left_on_purpose:
		print("LobbyClient: session lost: ", NetDiagnosticsScript.describe_last_disconnect())
	_pending_notice = "" if left_on_purpose else String(error_key(reason))
	_close_peer()
	room = {}
	room_guild_name = ""
	room_guild_tag = ""
	target_guild_id = ""
	_set_state(State.IDLE)
	var controller := _controller()
	if controller != null:
		controller.set_game_mode(GameMode.solo())
		if reload_world and controller.get_world() is Village:
			controller.load_world(controller.village_scene)
	# In the middle of a shared run (MP3): the run ends here with the loss payout (D-123), the run
	# end screen leads back to the solo village.
	if net_run != null:
		net_run.on_session_lost()
	room_changed.emit(room)
	session_ended.emit(reason)


func _close_peer() -> void:
	if peer == null:
		return
	var old := peer
	peer = null
	if old.room_entered.is_connected(_on_room_entered):
		old.room_entered.disconnect(_on_room_entered)
		old.room_updated.disconnect(_on_room_updated)
		old.room_left.disconnect(_on_room_left)
		old.relay_error.disconnect(_on_relay_error)
		old.connection_closed.disconnect(_on_connection_closed)
		old.run_ended.disconnect(_on_run_ended)
	if old.host_hitched.is_connected(_on_host_hitched):
		old.host_hitched.disconnect(_on_host_hitched)
	if _assigned:
		get_tree().get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
		_assigned = false
	old.close()
	_net_players = null


func _fail(code: String) -> void:
	last_error = code
	if has_invite():
		# The run of the invite's room is in progress: wait for its end and try again (D-190).
		invite_waiting = code == "room_started"
		if invite_waiting and _invite_retry_left <= 0.0:
			_invite_retry_left = INVITE_RETRY_SECONDS
	error.emit(code)


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	# Browser only: keep running in a hidden tab while in a room (D-183).
	WebKeepAliveScript.set_enabled(state == State.IN_ROOM or state == State.LEAVING)
	state_changed.emit(state)


func _controller() -> WorldController:
	return get_tree().get_first_node_in_group(GameMode.OWNER_GROUP) as WorldController


## What the other machines need to draw this player: name, character, clothing colour, platform;
## and what the host needs to run it (KONZEPT §3.2, §9): the own danger level for the group level,
## the solo character's talents and the account level (the host sanitizes them against it).
func _local_profile() -> Dictionary:
	var session := get_session()
	var player_name := session.get_player_name() if session != null else ""
	if player_name.is_empty():
		player_name = OnlineSession.sanitize_name(SaveManager.get_display_name())
	var account := AccountProgress.current()
	return {
		"name": player_name,
		"character": String(SaveManager.get_character_id()),
		"color": SaveManager.get_character_color().to_html(false),
		"platform": OnlineConfig.get_platform(),
		"danger": account.get_danger_level(),
		"level": account.get_level(),
		"talents": AccountTalents.load_state(account).to_dict(),
		# KE4: the own forge for the dungeon of a quick game (the host applies it, NetPlayers).
		"forge": MetaProgression.forge_snapshot(),
		# KE5: the own Proviant and trade levels for a quick game (the host applies them, NetPlayers).
		"provisions": MetaProgression.provision_snapshot(own_provisions()),
	}


## The Proviant this machine brings into a quick game: the run's (start_run took it from the save
## before the dungeon attaches its players) or, in the village, the packed one.
static func own_provisions() -> Array[StringName]:
	return RunManager.get_run_boosts() if RunManager.is_run_active() else SaveManager.get_pending_boosts()

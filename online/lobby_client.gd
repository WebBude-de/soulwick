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
## end_run (back in the village) opens it again; run_ended reaches every member. Not here yet: guild
## rooms beyond passing mode/guildId (MP8).

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

var _session: OnlineSession = null
var _connect_left := 0.0
var _leave_left := 0.0
var _assigned := false
## Translation key of a notice for the next village (session end), "" if none.
var _pending_notice := ""
var _net_players: NetPlayers = null
## The shared run of this room (MP3), child "NetRun".
var net_run: NetRun = null


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


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	net_run = NetRun.create(self)
	add_child(net_run)


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


## Host a room (mode quick, or guild with guild_id; guild rooms are only passed on, MP8).
func create_room(mode := MODE_QUICK, guild_id := "") -> void:
	await _enter(RelayProtocol.create(mode, guild_id))


## Join a room by its 6-character code (case and spaces do not matter).
func join_room(code: String) -> void:
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
	if net_run != null:
		net_run.configure_world(world)


## Called by the WorldController when the world loads in a networked session.
func attach_world(controller: Node, world: Node) -> void:
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
	var hello := RelayProtocol.hello(session.relay_token, OnlineConfig.PROTOCOL_VERSION, OnlineConfig.get_game_version(), OnlineConfig.get_platform())
	_assigned = false
	_connect_left = CONNECT_TIMEOUT
	_set_state(State.CONNECTING)
	if peer.open(RelayProtocol.prefer_ipv4_loopback(RelayProtocol.with_ws_path(session.get_relay_url())), hello, action) != OK:
		_close_peer()
		_set_state(State.IDLE)
		_fail(ERROR_RELAY_UNREACHABLE)


func _on_room_entered(new_room: Dictionary, _peer_id: int) -> void:
	room = new_room
	last_run_end_reason = ""
	runs_ended = 0
	var tree := get_tree()
	var api := tree.get_multiplayer() as SceneMultiplayer
	if api != null:
		api.server_relay = true
	tree.get_multiplayer().multiplayer_peer = peer
	_assigned = true
	_set_state(State.IN_ROOM)
	var controller := _controller()
	if controller != null:
		var mode := GameMode.quick(1, [0])
		mode.network = self
		controller.set_game_mode(mode)
		if reload_world:
			controller.load_world(controller.village_scene)
	peer.set_delivering(true)
	room_changed.emit(room)


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
		_end_session.call_deferred(RelayProtocol.CLOSED_SHUTDOWN if code == RelayProtocol.CLOSE_SHUTDOWN else "disconnected")


## Back to a solo village; a notice explains why unless the player left on purpose.
func _end_session(reason: String) -> void:
	if state != State.IN_ROOM and state != State.LEAVING:
		return
	var left_on_purpose := state == State.LEAVING or reason == RelayProtocol.CLOSED_LEFT
	last_end_reason = reason
	_pending_notice = "" if left_on_purpose else String(error_key(reason))
	_close_peer()
	room = {}
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
	if _assigned:
		get_tree().get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
		_assigned = false
	old.close()
	_net_players = null


func _fail(code: String) -> void:
	last_error = code
	error.emit(code)


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)


func _controller() -> WorldController:
	return get_tree().get_first_node_in_group(GameMode.OWNER_GROUP) as WorldController


## What the other machines need to draw this player: name, character, clothing colour, platform.
func _local_profile() -> Dictionary:
	var session := get_session()
	var player_name := session.get_player_name() if session != null else ""
	if player_name.is_empty():
		player_name = OnlineSession.sanitize_name(SaveManager.get_display_name())
	return {
		"name": player_name,
		"character": String(SaveManager.get_character_id()),
		"color": SaveManager.get_character_color().to_html(false),
		"platform": OnlineConfig.get_platform(),
	}

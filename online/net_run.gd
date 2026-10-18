class_name NetRun
extends Node
## The shared run of a relay room, session part (MP3, D-126): start, seed, end of the run and the
## run report. Child "NetRun" of the LobbyClient, so the node path is the same on every machine.
## - Host: start() (village "Starten" or the dungeon entrance) closes the room for new players at the
##   relay, picks the seed and tells every client begin_run(seed, players, run number); then it loads
##   the dungeon.
## - Client: begin_run loads the dungeon with the host's seed. configure_world gives the dungeon its
##   seed and a NetDungeon (rooms, enemies, players, online/net_dungeon.gd) before it enters the tree.
## - Run end: the host's NetDungeon sends run_over; every machine books its own payout (portal 100 %,
##   death/abort/host gone 50 %, D-081/D-123) and goes back to the shared village. The host reports
##   the run (POST /runs, mode quick, or guild with the guild id in a guild room, D-147) when it is
##   logged in; failures are only logged (D-082). A guild run's payout into the treasury goes to
##   every machine of the room (share_guild_payout); the village shows it once ("+21 Gold für
##   [DOCHT]", VillageUI via take_payout_notice / guild_payout_noticed).
## - Back in the village the host sends end_run (portal, wiped, abandoned) to the relay: the room
##   takes new players again until the next start. A newcomer learns the room's run number
##   (sync_runs), so its profiles count for the host's current village.

signal run_begun(seed_value: int, players: int)
## The run report finished: status "sent", "skipped" (not logged in) or "failed:<code>".
signal run_reported(status: String)
## A guild run paid into the treasury (host after its report, clients from the host): notice is
## {payout, treasury, tag, name}.
signal guild_payout_noticed(notice: Dictionary)

const NODE_NAME := &"NetRun"
const MODE_QUICK := "quick"
const MODE_GUILD := "guild"
## TESTWERT: seconds before the one retry of a failed run report.
const REPORT_RETRY_SECONDS := 2.0
## Contracts MAX_RUN_REMAINING_GOLD: the most run gold one report may carry.
const MAX_REPORTED_GOLD := 10_000_000

## The LobbyClient this run belongs to (parent).
var lobby: LobbyClient = null
## Seed and player count of the running (or last) run.
var seed_value := 0
var player_count := 1
## "Seitenwege auslassen" of the host for this run (M5, D-144/D-191): the host's option at the
## start, sent with begin_run; every machine rolls its room chain (ladder door) with it.
var side_ways_skipped := false
## Account ids (API player ids) of the room at the start: the participants of the run report.
var participants: Array[String] = []
## A run of this room is running (set at begin, cleared at the run end or session end).
var in_run := false
## Runs begun in this room (the same on every machine: begin_run and sync_runs carry it). It is the
## "epoch" of the profiles: a profile of the village before a run never counts for the one after.
var runs_begun := 0
## Status of the last run report ("" before the first).
var last_report_status := ""
## Idempotency key of the current run's report (contracts run.ts reportId): one UUID per run, the
## same when the report is sent again.
var report_id := ""
## Guild runs: gold the last report paid into the guild treasury and the treasury after it
## (CreateRunResponse guildPayout / guildProgress); -1 until a guild run was reported.
var last_guild_payout := -1
var last_guild_treasury := -1

## The last guild payout nobody has shown yet ({} if none, see take_payout_notice).
var _payout_notice: Dictionary = {}

var _started_msec := 0
## Host: RunEndReason of a run that ended; sent as end_run once the village is loaded ("" = none).
var _pending_end_reason := ""
## Host: the last profile of every client, with the world it was sent from (MP3). Kept until the
## host has that world too, so the order of world changes does not matter.
var _profiles: Dictionary[int, Dictionary] = {}


static func create(owner_lobby: LobbyClient) -> NetRun:
	var run := NetRun.new()
	run.name = NODE_NAME
	run.lobby = owner_lobby
	return run


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.run_ended.connect(_on_run_ended)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(func(peer: int) -> void: _profiles.erase(peer))


## The relay name of a run end (end_run reason): portal, everybody down, given up.
static func relay_end_reason(reason: int) -> String:
	match reason:
		RunManager.EndReason.EXIT:
			return RelayProtocol.RUN_END_PORTAL
		RunManager.EndReason.DEATH:
			return RelayProtocol.RUN_END_WIPED
	return RelayProtocol.RUN_END_ABANDONED


## Host: a new peer (joined in the village between runs) learns the room's run number first.
func _on_peer_connected(peer: int) -> void:
	if multiplayer.is_server() and lobby != null and lobby.is_in_room():
		sync_runs.rpc_id(peer, runs_begun)


## Host -> new client: runs begun in this room. The client's profile for the current village is
## sent again with it (the first one, epoch 0, was for a village the host left long ago).
@rpc("authority", "call_remote", "reliable")
func sync_runs(count: int) -> void:
	if multiplayer.get_remote_sender_id() != RelayProtocol.HOST_PEER_ID or in_run or count == runs_begun:
		return
	runs_begun = maxi(0, count)
	var net_players := lobby.get_net_players() if lobby != null else null
	if net_players != null:
		net_players.resend_profile()


## Client -> host: this client's player in its current world (NetPlayers._send_profile). Also the
## "world loaded" message: the dungeon's NetDungeon counts the client from now on.
@rpc("any_peer", "call_remote", "reliable")
func submit_profile(profile: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer <= 0:
		return
	_profiles[peer] = profile
	_deliver_profile(peer)


## Client -> host: input for the client's player (NetPlayerState, unreliable ordered, channel 1).
@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func submit_input(move: Vector2, aim: Vector2, held: int) -> void:
	if not multiplayer.is_server() or lobby == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	var net_players := lobby.get_net_players()
	var player := net_players.get_player_for_peer(sender) if net_players != null else null
	var state := player.get_node_or_null(NodePath(NetPlayerState.NODE_NAME)) as NetPlayerState if player != null else null
	if state != null:
		state.apply_input(sender, move, aim, held)


## Host: its NetPlayers of a new world is ready; profiles that came first are handed over.
func on_host_world_ready(_net_players: NetPlayers) -> void:
	for peer in _profiles.keys():
		_deliver_profile(peer)


func _deliver_profile(peer: int) -> void:
	var net_players := lobby.get_net_players() if lobby != null else null
	if net_players == null or not net_players.is_inside_tree() or not _profiles.has(peer):
		return
	var profile := _profiles[peer]
	# Only for the same world: a profile from the village before a run never counts for the village
	# after it (epoch = runs begun).
	if str(profile.get("world", "")) != net_players.get_world_kind() or int(profile.get("epoch", -1)) != runs_begun:
		return
	net_players.accept_profile(peer, profile)
	var dungeon := net_players.world as DungeonManager
	var net := dungeon.get_node_or_null(NodePath(NetDungeon.NODE_NAME)) as NetDungeon if dungeon != null else null
	if net != null:
		net.on_client_ready(peer)


## Host: starts the shared run for everybody in the room (forced_seed: tools and tests).
func start(forced_seed := 0) -> void:
	if lobby == null or not lobby.is_host() or in_run:
		return
	# No joins while the run lasts; end_run (back in the village) opens the room again.
	lobby.request_relay_start()
	_pending_end_reason = ""
	var new_seed := forced_seed if forced_seed > 0 else randi_range(1, 2_000_000_000)
	var peers := lobby.get_room_peers()
	var count := clampi(peers.size(), 1, GameMode.MAX_PLAYERS)
	participants.clear()
	for peer: Variant in peers:
		if peer is Dictionary and peer.get("playerId") != null:
			participants.append(str(peer.get("playerId")))
	# The village's players leave the clients first, so nothing of the old world arrives late.
	var net_players := lobby.get_net_players()
	if net_players != null:
		net_players.hide_from_peers()
	side_ways_skipped = SideWays.is_skipped()
	for peer_id in multiplayer.get_peers():
		begin_run.rpc_id(peer_id, new_seed, count, runs_begun + 1, side_ways_skipped)
	_begin.call_deferred(new_seed, count)


## Host -> clients: the run (number run_number of this room) starts with this seed for this many
## players and the host's "Seitenwege auslassen" (skip_side; older hosts send none = off).
@rpc("authority", "call_remote", "reliable")
func begin_run(new_seed: int, count: int, run_number: int, skip_side := false) -> void:
	if multiplayer.get_remote_sender_id() != RelayProtocol.HOST_PEER_ID or in_run:
		return
	side_ways_skipped = skip_side
	# _begin counts this run: afterwards runs_begun is the host's run number (late joiners too).
	runs_begun = maxi(0, run_number - 1)
	# Packets behind this one belong to the dungeon: held back until it is loaded (_begin).
	if lobby != null and lobby.peer != null:
		lobby.peer.set_delivering(false)
	# Out of SceneMultiplayer's poll before the world changes.
	_begin.call_deferred(new_seed, count)


func _begin(new_seed: int, count: int) -> void:
	var controller := lobby.get_world_controller() if lobby != null else null
	if controller == null or not lobby.is_in_room():
		if lobby != null and lobby.peer != null:
			lobby.peer.set_delivering(true)
		return
	seed_value = new_seed
	player_count = count
	in_run = true
	runs_begun += 1
	report_id = new_uuid()
	_started_msec = Time.get_ticks_msec()
	controller.game_mode.player_count = clampi(count, 1, GameMode.MAX_PLAYERS)
	run_begun.emit(seed_value, player_count)
	if lobby.peer != null:
		# Host: begin_run and a load announcement leave before the dungeon is built (D-183).
		lobby.peer.announce_loading()
	controller.load_world(controller.dungeon_scene)
	if lobby.peer != null:
		lobby.peer.set_delivering(true)


## Called by the WorldController (through the LobbyClient) for every new world before it enters
## the tree: a dungeon of this run gets the seed and its NetDungeon.
func configure_world(world: Node) -> void:
	var dungeon := world as DungeonManager
	if dungeon == null:
		in_run = false
		# Host back in the village after a run: the relay takes new players again.
		if not _pending_end_reason.is_empty() and lobby != null and lobby.is_host():
			lobby.request_relay_end_run(_pending_end_reason)
		_pending_end_reason = ""
		return
	if not in_run:
		# A dungeon without a started run (should not happen: the entrance starts the run).
		push_warning("NetRun: dungeon loaded without a started run; using a fresh seed.")
		seed_value = randi_range(1, 2_000_000_000)
		in_run = true
	dungeon.seed_value = seed_value
	dungeon.add_child(NetDungeon.create(self, dungeon))


## The relay session ended in the middle of a run (host gone, kicked, connection lost): the run ends
## for this machine with the loss payout (50 %, D-123), the run end screen leads to the solo village.
func on_session_lost() -> void:
	var controller := lobby.get_world_controller() if lobby != null else null
	var dungeon: DungeonManager = controller.get_world() as DungeonManager if controller != null else null
	in_run = false
	_pending_end_reason = ""
	if dungeon == null:
		return
	var net := dungeon.get_node_or_null(NodePath(NetDungeon.NODE_NAME)) as NetDungeon
	if net != null:
		net.detach()
	if RunManager.is_run_active():
		dungeon.end_run(RunManager.EndReason.ABORT)


## Seconds since the run began (run report).
func get_run_seconds() -> int:
	return maxi(0, roundi(float(Time.get_ticks_msec() - _started_msec) / 1000.0))


## The relay confirmed end_run (every member): the room is in the lobby again.
func on_relay_run_ended(_reason: String) -> void:
	_pending_end_reason = ""


func _on_run_ended(reason: int, _remaining: int, _payout: int) -> void:
	if not in_run:
		return
	in_run = false
	if lobby != null and lobby.is_host():
		_pending_end_reason = relay_end_reason(reason)
		_report_run(RunManager.get_last_summary())


## D-082: the host reports the run when it is logged in; failures are ignored (only logged).
func _report_run(summary: Dictionary) -> void:
	var session := lobby.get_session()
	if session == null or not session.is_logged_in() or participants.is_empty():
		_set_report("skipped")
		return
	var own_id := session.get_player_id()
	if not own_id.is_empty() and not participants.has(own_id):
		participants.push_front(own_id)
	var body := report_body(summary)
	var result: ApiResult = await session.api.post_run(body)
	# One more try on a network or server error; the same reportId keeps it from counting twice.
	if not result.ok and (result.status == 0 or result.status >= 500) and is_inside_tree():
		await get_tree().create_timer(REPORT_RETRY_SECONDS, true).timeout
		result = await session.api.post_run(body)
	if result.ok:
		if _accept_guild_payout(result):
			_share_payout()
		_set_report("sent")
	else:
		push_warning("NetRun: run report failed (%s)." % result.error)
		_set_report("failed:%s" % result.error)


## CreateRunRequest (contracts run.ts) for a finished run: mode quick, or guild with the guild id
## of the room (D-147; the API wants guildId exactly for guild runs).
func report_body(summary: Dictionary) -> Dictionary:
	var mode := report_mode()
	var body := {
		"mode": mode,
		"participants": participants.slice(0, GameMode.MAX_PLAYERS),
		"roomReached": int(summary.get("room", 1)),
		"durationSeconds": get_run_seconds(),
		"seed": str(seed_value),
		"gameVersion": OnlineConfig.get_game_version(),
	}
	if report_id.is_empty():
		report_id = new_uuid()
	body["reportId"] = report_id
	if mode == MODE_GUILD:
		body["guildId"] = report_guild_id()
		# The API pays the guild treasury from these (portal 100 %, else 50 %, D-081).
		var reason := _pending_end_reason
		if reason.is_empty():
			reason = relay_end_reason(int(summary.get("reason", RunManager.EndReason.ABORT)))
		body["endReason"] = reason
		body["remainingGold"] = clampi(int(summary.get("remaining_gold", 0)), 0, MAX_REPORTED_GOLD)
	return body


## A random UUID v4 (reportId).
static func new_uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


## CreateRunResponse of a guild run: what went into the treasury and what is in it now. false if the
## answer has no guild payout (quick runs, older API builds).
func _accept_guild_payout(result: ApiResult) -> bool:
	var payout: Variant = result.get_field("guildPayout", null)
	var progress: Variant = result.get_field("guildProgress", null)
	if payout == null and not (progress is Dictionary):
		return false
	last_guild_payout = int(payout) if payout != null else 0
	if progress is Dictionary:
		last_guild_treasury = int(progress.get("treasury", 0))
	return true


## Host: the payout of the reported guild run for itself and every client of the room.
func _share_payout() -> void:
	var tag := lobby.room_guild_tag if lobby != null else ""
	var guild_name := lobby.room_guild_name if lobby != null else ""
	if multiplayer.has_multiplayer_peer() and lobby != null and lobby.is_in_room():
		for peer_id in multiplayer.get_peers():
			share_guild_payout.rpc_id(peer_id, last_guild_payout, last_guild_treasury, tag, guild_name)
	_notice_payout(last_guild_payout, last_guild_treasury, tag, guild_name)


## Host -> clients: the guild run they played paid this into the treasury.
@rpc("authority", "call_remote", "reliable")
func share_guild_payout(payout: int, treasury: int, tag: String, guild_name: String) -> void:
	if multiplayer.get_remote_sender_id() != RelayProtocol.HOST_PEER_ID:
		return
	last_guild_payout = maxi(0, payout)
	last_guild_treasury = treasury
	# The host knows the guild of its room; a client that joined by code may not.
	if lobby != null:
		if lobby.room_guild_tag.is_empty():
			lobby.room_guild_tag = tag
		if lobby.room_guild_name.is_empty():
			lobby.room_guild_name = guild_name
	_notice_payout(last_guild_payout, treasury, tag, guild_name)


## A payout worth showing (more than 0 gold): kept until the village takes it, and announced.
func _notice_payout(payout: int, treasury: int, tag: String, guild_name: String) -> void:
	if payout <= 0:
		return
	_payout_notice = {"payout": payout, "treasury": treasury, "tag": tag, "name": guild_name}
	guild_payout_noticed.emit(_payout_notice)


## The guild payout not shown yet ({} if none); it is handed out once.
func take_payout_notice() -> Dictionary:
	var notice := _payout_notice
	_payout_notice = {}
	return notice


## "+21 Gold für [DOCHT]" (without a tag: "+21 Gold für die Gildenkasse").
static func payout_text(notice: Dictionary) -> String:
	var tag := str(notice.get("tag", ""))
	if tag.is_empty():
		return Loc.t(&"GUILD_RUN_PAYOUT_PLAIN", [int(notice.get("payout", 0))])
	return Loc.t(&"GUILD_RUN_PAYOUT_SHORT", [int(notice.get("payout", 0)), tag])


## "guild" for a guild room with a guild id, else "quick".
func report_mode() -> String:
	return MODE_GUILD if not report_guild_id().is_empty() else MODE_QUICK


## The guild of this run: the session's (GameMode GUILD), else the room's ("" for quick rooms).
func report_guild_id() -> String:
	var mode := GameMode.of(self)
	if mode.kind == GameMode.Kind.GUILD and not mode.guild_id.is_empty():
		return mode.guild_id
	return lobby.get_room_guild_id() if lobby != null else ""


func _set_report(status: String) -> void:
	last_report_status = status
	run_reported.emit(status)

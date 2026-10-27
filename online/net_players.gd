class_name NetPlayers
extends Node
## Players of a room in the current world (MP2, host authority): a MultiplayerSpawner whose custom
## spawn function builds one player per peer on every machine. Created by LobbyClient.attach_world
## (via the WorldController) as child "NetPlayers" of the world, so the node paths match everywhere.
## - Host: spawns its own player at once and one for every client as soon as that client sent its
##   profile (name, character, clothing colour from its save, D-081: nothing else); despawns it when
##   the client leaves. MultiplayerSpawner replicates spawns and despawns, also to late joiners.
## - Every machine: the player of its own peer is local (keyboard, camera, HUD via
##   WorldController.register_player), the others get RemoteInput and follow NetPlayerState.
## Name tags in the co-op colours P1–P4 (HANDOUT, TESTWERT) show who is who.
## World changes (MP3): a player is only spawned on peers that have this world loaded. A peer counts
## as ready once its NetPlayers sent the profile for this world (through the session's NetRun, which
## keeps it until the host has the same world); then the synchronizers of all players become
## visible to it (MultiplayerSpawner spawns by synchronizer visibility, the synchronizer is rooted
## at the player). So host and clients can change worlds in any order without spawns getting lost.
## Looks (D-152): every profile carries "look" (PlayerLook of the account profile, PlayerProfile)
## next to the old character/color pair. A change of the own profile (editor in the lobby or the
## village) goes to the host (request_look) and from there to every peer of this world (apply_look);
## a peer that loads the world later gets all current looks once it is ready. The relay round trip
## of every machine is shared the same way every PING_SHARE_SECONDS (lobby slots, D-152).
## Room types (WK11): every profile carries the room types the account had Flint explain
## (RoomFlint.PROFILE_KEY); the spawn data hands them to the player on every machine (player meta),
## so every machine knows who still needs Flint's tour and holds the room countdown alike.

signal players_changed
## A player's look or name changed (lobby slots; pings are read with get_ping()).
signal looks_changed

const NODE_NAME := &"NetPlayers"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
## Co-op colours P1–P4 (docs/HANDOUT.md "Koop-Einfärbung", Vorschlag).
const PLAYER_COLORS: Array[Color] = [Color("#3690da"), Color("#e0463a"), Color("#5fcd62"), Color("#f2cf4a")]
const NAME_TAG_OFFSET := Vector2(0, -62)
const NAME_MAX := 24
## TESTWERT: seconds between two ping reports (client -> host -> everybody).
const PING_SHARE_SECONDS := 2.0

## The WorldController (register_player/unregister_player); may be null in tests.
var controller: Node = null
var world: Node = null
## This machine's profile {name, character, color, platform}.
var local_profile: Dictionary = {}

var _spawner: MultiplayerSpawner = null
var _by_peer: Dictionary[int, Player] = {}
## Host: peers whose world has this NetPlayers (they sent their profile), MP3.
var _ready_peers: Dictionary[int, bool] = {}
var _origin := Vector2.ZERO
## Current look (PlayerLook) and name per peer, also for players not spawned here yet.
var _looks: Dictionary[int, Dictionary] = {}
var _names: Dictionary[int, String] = {}
## Relay round trip in ms per peer (-1 unknown).
var _pings: Dictionary[int, int] = {}
var _ping_left := 0.0


static func create(world_controller: Node, target_world: Node, profile: Dictionary) -> NetPlayers:
	var net := NetPlayers.new()
	net.name = NODE_NAME
	net.controller = world_controller
	net.world = target_world
	net.local_profile = with_seen_rooms(with_own_look(profile))
	return net


## profile plus this player's look and name from the account profile (D-152); character and color
## stay for older readers.
static func with_own_look(profile: Dictionary) -> Dictionary:
	var result := profile.duplicate()
	var own := PlayerProfile.current()
	result["look"] = own.look.duplicate(true)
	result["character"] = String(own.look.character)
	result["color"] = PlayerLook.outfit_color(own.look).to_html(false)
	if not own.player_name.is_empty():
		result["name"] = own.player_name
	return result


## profile plus the room types this account knows (Flint explained them, WK11).
static func with_seen_rooms(profile: Dictionary) -> Dictionary:
	var result := profile.duplicate()
	result[RoomFlint.PROFILE_KEY] = Array(RoomFlint.account_known())
	return result


## The room types of a profile or spawn data, cleaned; null when it has none (an older build: its
## player counts as knowing every room type, RoomFlint.knows).
static func profile_seen_rooms(profile: Dictionary) -> Variant:
	if not profile.has(RoomFlint.PROFILE_KEY):
		return null
	return Array(RoomFlint.sanitize_known(profile[RoomFlint.PROFILE_KEY]))


## Colour of the index-th player (P1..P4).
static func color_for(index: int) -> Color:
	return PLAYER_COLORS[clampi(index, 0, PLAYER_COLORS.size() - 1)]


func _ready() -> void:
	var spawn := world.find_child(WorldController.PLAYER_SPAWN_NODE, true, false) as Node2D if world != null else null
	_origin = spawn.global_position if spawn != null else Vector2.ZERO
	_spawner = MultiplayerSpawner.new()
	_spawner.name = "Spawner"
	# Spawner -> NetPlayers -> world: the players live directly in the (y-sorted) world.
	_spawner.spawn_path = NodePath("../..")
	_spawner.spawn_function = _build_player
	add_child(_spawner)
	SaveManager.profile_changed.connect(_on_own_profile_changed)
	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		_host_spawn(multiplayer.get_unique_id(), local_profile)
		# Profiles of clients that loaded this world before the host did.
		var run := _net_run()
		if run != null:
			run.on_host_world_ready.call_deferred(self)
	else:
		_spawner.spawned.connect(_on_spawned)
		if multiplayer.get_peers().has(RelayProtocol.HOST_PEER_ID):
			_send_profile()
		else:
			multiplayer.connected_to_server.connect(_send_profile, CONNECT_ONE_SHOT)


func get_player_for_peer(peer_id: int) -> Player:
	var player: Player = _by_peer.get(peer_id, null)
	return player if player != null and is_instance_valid(player) else null


func get_peer_ids() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_by_peer.keys())
	return ids


func get_player_count() -> int:
	return _by_peer.size()


## Peers that have this world loaded (host), MP3.
func get_ready_peers() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_ready_peers.keys())
	return ids


## Look (PlayerLook) of peer's player: the own profile for this machine, {} if unknown.
func get_look(peer_id: int) -> Dictionary:
	if peer_id == multiplayer.get_unique_id():
		return PlayerProfile.current().look.duplicate(true)
	return _looks.get(peer_id, {}).duplicate(true)


## Name of peer's player as this world knows it ("" if unknown).
func get_player_name_of(peer_id: int) -> String:
	if peer_id == multiplayer.get_unique_id() and not PlayerProfile.current().player_name.is_empty():
		return PlayerProfile.current().player_name
	return _names.get(peer_id, "")


## Relay round trip of peer in ms (-1 unknown).
func get_ping(peer_id: int) -> int:
	if peer_id == multiplayer.get_unique_id():
		return _own_rtt()
	return _pings.get(peer_id, -1)


## Name of this world for the profiles ("Village", "Dungeon"): the same on every machine.
func get_world_kind() -> String:
	return String(world.name) if world != null else ""


## Host: a client's profile for this world arrived (NetRun.submit_profile): what its player looks
## like, and "this world is loaded": from now on the peer sees every player of it (MP3).
func accept_profile(peer: int, profile: Dictionary) -> void:
	if not multiplayer.is_server() or peer <= 0:
		return
	var is_new := not _ready_peers.has(peer)
	if is_new:
		_ready_peers[peer] = true
		for player in _by_peer.values():
			_show_to(player, peer)
	if _by_peer.has(peer):
		if is_new:
			_send_looks_to.call_deferred(peer)
		return
	_host_spawn(peer, profile)
	if is_new:
		_send_looks_to.call_deferred(peer)


## Client: sends the profile of this world again (the room's run number changed, NetRun.sync_runs).
func resend_profile() -> void:
	if not multiplayer.is_server():
		_send_profile()


## Client -> host, once per world, through the NetRun (a node every machine always has).
func _send_profile() -> void:
	var run := _net_run()
	if is_inside_tree() and run != null:
		var profile := local_profile.duplicate()
		profile["world"] = get_world_kind()
		# Which village or dungeon: the number of runs begun in this room (the same everywhere).
		profile["epoch"] = run.runs_begun
		run.submit_profile.rpc_id(RelayProtocol.HOST_PEER_ID, profile)


func _net_run() -> NetRun:
	var lobby := LobbyClient.find(self)
	return lobby.net_run if lobby != null else null


func _host_spawn(peer: int, profile: Dictionary) -> void:
	var index := _free_index()
	if index < 0:
		push_warning("NetPlayers: no free player slot for peer %d." % peer)
		return
	var look := _profile_look(profile)
	var player_name := str(profile.get("name", "")).left(NAME_MAX)
	_looks[peer] = look
	if not player_name.is_empty():
		_names[peer] = player_name
	var data := {
		"peer": peer,
		"index": index,
		"name": player_name,
		"character": str(profile.get("character", "")),
		"color": str(profile.get("color", "")),
		"look": look,
		"pos": _origin + WorldController.get_spawn_offset(index),
		"forge": profile_forge(profile) if _takes_profile_forge() else {},
		"provisions": profile_provisions(profile) if _takes_profile_forge() else {},
	}
	var seen_rooms: Variant = profile_seen_rooms(profile)
	if seen_rooms != null:
		data[RoomFlint.PROFILE_KEY] = seen_rooms
	var player := _spawner.spawn(data) as Player
	if player != null:
		_apply_profile_talents(player, profile)
		_apply_profile_forge(player, data["forge"])
		_apply_profile_provisions(player, data["provisions"])
		_register(player, peer)
		for ready_peer in _ready_peers:
			_show_to(player, ready_peer)


## Host, dungeon of a quick game (KONZEPT §9): the solo character's talents from the profile, checked
## against the profile's account level (TalentState.sanitized); the host runs them for every player,
## the clients only see the result. Guild runs use the guild character later (MP8b), the village none.
func _apply_profile_talents(player: Player, profile: Dictionary) -> void:
	if not (world is DungeonManager) or GameMode.of(self).kind == GameMode.Kind.GUILD:
		return
	var state := profile_talents(profile)
	if not state.levels.is_empty():
		TalentEffects.apply_to(player, state)


## Dungeon of a quick game (KE4, KONZEPT §9): every player brings their own forge in the lobby
## profile. Solo takes the own save (DungeonManager, MetaProgression.apply_to_run), guild runs none.
func _takes_profile_forge() -> bool:
	return world is DungeonManager and GameMode.of(self).get_meta_source() == GameMode.MetaSource.NONE


## The cleaned forge snapshot of a lobby profile; {} for old profiles without one (no forge).
static func profile_forge(profile: Dictionary) -> Dictionary:
	var raw: Variant = profile.get("forge", null)
	return MetaProgression.sanitize_snapshot(raw) if raw is Dictionary else {}


## Host: the player's forge (weapon levels, Laterne, Schildplatte, start weapons) on its copy; the
## clients got the snapshot with the spawn data (_build_player), the loadout follows from the host.
func _apply_profile_forge(player: Player, forge: Dictionary) -> void:
	if forge.is_empty():
		return
	MetaProgression.apply_forge_snapshot(player, forge, (world as DungeonManager).context)


## The cleaned Proviant snapshot of a lobby profile (KE5); {} for old profiles without one.
static func profile_provisions(profile: Dictionary) -> Dictionary:
	var raw: Variant = profile.get("provisions", null)
	return MetaProgression.sanitize_provisions(raw) if raw is Dictionary else {}


## Host: the player's Proviant and trade levels on its copy (Heiltrank, Glücksamulett act now; the
## rest is asked through MetaProgression.player_*), then the group's Goldregen anew. The clients got
## the snapshot with the spawn data (_build_player) for their own optics (Klarsicht, Spürnase,
## Rückkehrstein button, prices).
func _apply_profile_provisions(player: Player, provisions: Dictionary) -> void:
	if provisions.is_empty():
		return
	var dungeon := world as DungeonManager
	MetaProgression.apply_provisions(player, provisions, dungeon.context)
	dungeon.refresh_group_gold()


## The talent distribution of a lobby profile, valid for its "level" (empty for old profiles).
static func profile_talents(profile: Dictionary) -> TalentState:
	var level: Variant = profile.get("level", 1)
	var points := TalentState.points_for_level(int(level) if (level is int or level is float) else 1)
	return TalentState.from_dict(profile.get("talents", {})).sanitized(points)


## Host (MP3): the players of this world leave every client at once (start or end of a run): they
## are despawned there now, and nothing of this world is sent any more while the machines change
## their worlds at their own pace.
func hide_from_peers() -> void:
	if not multiplayer.is_server():
		return
	for peer in _ready_peers.keys():
		for player in _by_peer.values():
			var state := player.get_node_or_null(NodePath(NetPlayerState.NODE_NAME)) as NetPlayerState if is_instance_valid(player) else null
			var sync := state.get_synchronizer() if state != null else null
			if sync != null:
				sync.set_visibility_for(peer, false)
				sync.update_visibility(peer)
	_ready_peers.clear()


## Host: player becomes visible (spawned, synchronized) on peer.
func _show_to(player: Player, peer: int) -> void:
	if not is_instance_valid(player):
		return
	var state := player.get_node_or_null(NodePath(NetPlayerState.NODE_NAME)) as NetPlayerState
	var sync := state.get_synchronizer() if state != null else null
	if sync == null:
		return
	sync.set_visibility_for(peer, true)
	sync.update_visibility(peer)


func _free_index() -> int:
	var used: Dictionary[int, bool] = {}
	for player in _by_peer.values():
		if is_instance_valid(player):
			used[player.player_id] = true
	for index in GameMode.MAX_PLAYERS:
		if not used.has(index):
			return index
	return -1


## Spawn function, the same on every machine: data comes from _host_spawn.
func _build_player(data: Variant) -> Node:
	var info: Dictionary = data if data is Dictionary else {}
	var peer := int(info.get("peer", 0))
	var index := int(info.get("index", 0))
	var player := PLAYER_SCENE.instantiate() as Player
	player.name = "Net%d" % peer
	# KE4: the forge of a quick game's player on every machine (weapon damage shown, own Laterne).
	var forge: Variant = info.get("forge", {})
	if forge is Dictionary and not (forge as Dictionary).is_empty():
		MetaProgression.set_player_forge(player, forge)
	# KE5: the Proviant of a quick game's player on every machine (own optics, prices, the stone).
	var provisions: Variant = info.get("provisions", {})
	if provisions is Dictionary and not (provisions as Dictionary).is_empty() and not multiplayer.is_server():
		MetaProgression.set_player_provisions(player, provisions)
	player.player_id = index
	player.is_local = peer == multiplayer.get_unique_id()
	# WK11: the room types this player knows, the same on every machine.
	var seen_rooms: Variant = profile_seen_rooms(info)
	if seen_rooms != null:
		RoomFlint.set_known(player, seen_rooms)
	player.input = LocalKeyboardMouseInput.new() if player.is_local else RemoteInput.new()
	# The newest look known here wins over the spawn data (it may have changed since the spawn).
	var appearance: Dictionary = _looks.get(peer, _profile_look(info))
	_looks[peer] = appearance
	var player_name: String = _names.get(peer, str(info.get("name", "")))
	if not player_name.is_empty():
		_names[peer] = player_name
	info["name"] = player_name
	# The own player follows the profile (and the editor) like in single player.
	player.appearance = {} if player.is_local else appearance
	var start: Vector2 = info.get("pos", Vector2.ZERO)
	player.position = start
	var state := NetPlayerState.create(peer, start)
	if multiplayer.is_server():
		# Spawned and synced only on peers that loaded this world (_show_to, MP3). Clients keep the
		# default: their RPCs to the host check this visibility too.
		state.get_synchronizer().public_visibility = false
	player.add_child(state)
	player.add_child(_name_tag(str(info.get("name", "")), index))
	return player


## The look of a profile or spawn data: "look" (D-152), else the MM1 pair character + color.
static func _profile_look(profile: Dictionary) -> Dictionary:
	var look: Variant = profile.get("look", null)
	if look is Dictionary:
		return PlayerLook.normalize(look)
	var color_text := str(profile.get("color", ""))
	return PlayerLook.from_legacy(profile.get("character", ""), Color.html(color_text) if Color.html_is_valid(color_text) else Color(0, 0, 0, 0))


# --- Looks and pings (D-152) ---

## The own profile changed (editor): tell the others through the host.
func _on_own_profile_changed() -> void:
	if not is_inside_tree() or multiplayer.multiplayer_peer == null:
		return
	var own := with_own_look(local_profile)
	if PlayerLook.equals(own.get("look", {}), local_profile.get("look", {})) and str(own.get("name", "")) == str(local_profile.get("name", "")):
		return
	local_profile = own
	var me := multiplayer.get_unique_id()
	var look: Dictionary = own.look
	var player_name := str(own.get("name", "")).left(NAME_MAX)
	if multiplayer.is_server():
		_set_look(me, look, player_name)
		for peer in _ready_peers:
			apply_look.rpc_id(peer, me, look, player_name)
	elif get_player_for_peer(RelayProtocol.HOST_PEER_ID) != null:
		# The host's player is here, so the host has this world loaded too.
		_set_look(me, look, player_name)
		request_look.rpc_id(RelayProtocol.HOST_PEER_ID, look, player_name)


## Client -> host: my new look and name. The host checks them and passes them on.
@rpc("any_peer", "call_remote", "reliable")
func request_look(look: Dictionary, player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0 or not _by_peer.has(sender):
		return
	var clean := PlayerLook.normalize(look)
	var clean_name := OnlineSession.sanitize_name(player_name) if not player_name.strip_edges().is_empty() else ""
	_set_look(sender, clean, clean_name)
	for peer in _ready_peers:
		if peer != sender:
			apply_look.rpc_id(peer, sender, clean, clean_name)


## Host -> everybody: the look and name of peer's player.
@rpc("authority", "call_remote", "reliable")
func apply_look(peer_id: int, look: Dictionary, player_name: String) -> void:
	_set_look(peer_id, PlayerLook.normalize(look), player_name.left(NAME_MAX))


## Host: a peer that just loaded this world gets every look and name known here.
func _send_looks_to(peer_id: int) -> void:
	if not is_inside_tree() or not multiplayer.is_server() or not _ready_peers.has(peer_id):
		return
	for look_peer in _looks:
		if look_peer != peer_id:
			apply_look.rpc_id(peer_id, look_peer, _looks[look_peer], _names.get(look_peer, ""))


func _set_look(peer_id: int, look: Dictionary, player_name: String) -> void:
	_looks[peer_id] = look
	if not player_name.is_empty():
		_names[peer_id] = player_name
	var player := get_player_for_peer(peer_id)
	if player != null:
		if not player.is_local:
			player.appearance = look
			player._apply_appearance()
		var tag := player.get_node_or_null(^"NameTag") as Label
		if tag != null and not player_name.is_empty():
			tag.text = player_name
	looks_changed.emit()


func _process(delta: float) -> void:
	_ping_left -= delta
	if _ping_left > 0.0:
		return
	_ping_left = PING_SHARE_SECONDS
	if not is_inside_tree() or multiplayer.multiplayer_peer == null:
		return
	var me := multiplayer.get_unique_id()
	var own := _own_rtt()
	if own >= 0:
		_pings[me] = own
	if multiplayer.is_server():
		if not _ready_peers.is_empty():
			var shared := {}
			for peer in _pings:
				shared[peer] = _pings[peer]
			for peer in _ready_peers:
				share_pings.rpc_id(peer, shared)
	elif own >= 0 and get_player_for_peer(RelayProtocol.HOST_PEER_ID) != null:
		report_ping.rpc_id(RelayProtocol.HOST_PEER_ID, own)


@rpc("any_peer", "call_remote", "unreliable")
func report_ping(rtt_msec: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and _by_peer.has(sender):
		_pings[sender] = clampi(rtt_msec, 0, 9999)


@rpc("authority", "call_remote", "unreliable")
func share_pings(pings: Dictionary) -> void:
	var me := multiplayer.get_unique_id()
	for peer: Variant in pings:
		if int(peer) != me:
			_pings[int(peer)] = clampi(int(pings[peer]), 0, 9999)


## This machine's round trip to the relay (LobbyClient's RelayPeer), -1 unknown.
func _own_rtt() -> int:
	var lobby := LobbyClient.find(self)
	if lobby == null or lobby.peer == null:
		return -1
	return lobby.peer.last_rtt_msec


## The name a player of the session shows over its head ("" without a name tag: single player).
static func display_name_of(player: Node) -> String:
	if player == null or not is_instance_valid(player):
		return ""
	var tag := player.get_node_or_null(^"NameTag") as Label
	return tag.text if tag != null else ""


## M2 tunnels: the name tag goes while its player is hidden under the rock (NetDungeon).
static func set_tag_hidden(player: Node, hidden: bool) -> void:
	if player == null or not is_instance_valid(player):
		return
	var tag := player.get_node_or_null(^"NameTag") as CanvasItem
	if tag != null:
		tag.visible = not hidden


func _name_tag(text: String, index: int) -> Label:
	var label := Label.new()
	label.name = "NameTag"
	label.text = text if not text.is_empty() else "P%d" % (index + 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 12)
	label.add_theme_color_override(&"font_color", color_for(index))
	label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override(&"outline_size", 4)
	label.z_index = 30
	label.size = Vector2(160, 18)
	label.position = NAME_TAG_OFFSET - Vector2(80, 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _on_spawned(node: Node) -> void:
	var player := node as Player
	if player == null:
		return
	var state := player.get_node_or_null(NodePath(NetPlayerState.NODE_NAME)) as NetPlayerState
	_register(player, state.peer_id if state != null else 0)


func _register(player: Player, peer: int) -> void:
	_by_peer[peer] = player
	player.tree_exiting.connect(_on_player_exiting.bind(peer, player), CONNECT_ONE_SHOT)
	if controller != null and controller.has_method(&"register_player"):
		controller.register_player(player)
	players_changed.emit()


func _on_player_exiting(peer: int, player: Player) -> void:
	if _by_peer.get(peer, null) == player:
		_by_peer.erase(peer)
	if controller != null and is_instance_valid(controller) and controller.has_method(&"unregister_player"):
		controller.unregister_player(player)
	players_changed.emit()


## Host: the client's player goes; the spawner despawns it everywhere.
func _on_peer_disconnected(peer: int) -> void:
	_ready_peers.erase(peer)
	var player := get_player_for_peer(peer)
	if player != null:
		player.queue_free()

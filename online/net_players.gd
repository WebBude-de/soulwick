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

signal players_changed

const NODE_NAME := &"NetPlayers"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
## Co-op colours P1–P4 (docs/HANDOUT.md "Koop-Einfärbung", Vorschlag).
const PLAYER_COLORS: Array[Color] = [Color("#3690da"), Color("#e0463a"), Color("#5fcd62"), Color("#f2cf4a")]
const NAME_TAG_OFFSET := Vector2(0, -62)
const NAME_MAX := 24

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


static func create(world_controller: Node, target_world: Node, profile: Dictionary) -> NetPlayers:
	var net := NetPlayers.new()
	net.name = NODE_NAME
	net.controller = world_controller
	net.world = target_world
	net.local_profile = profile
	return net


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


## Name of this world for the profiles ("Village", "Dungeon"): the same on every machine.
func get_world_kind() -> String:
	return String(world.name) if world != null else ""


## Host: a client's profile for this world arrived (NetRun.submit_profile): what its player looks
## like, and "this world is loaded": from now on the peer sees every player of it (MP3).
func accept_profile(peer: int, profile: Dictionary) -> void:
	if not multiplayer.is_server() or peer <= 0:
		return
	if not _ready_peers.has(peer):
		_ready_peers[peer] = true
		for player in _by_peer.values():
			_show_to(player, peer)
	if _by_peer.has(peer):
		return
	_host_spawn(peer, profile)


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
	var data := {
		"peer": peer,
		"index": index,
		"name": str(profile.get("name", "")).left(NAME_MAX),
		"character": str(profile.get("character", "")),
		"color": str(profile.get("color", "")),
		"pos": _origin + WorldController.get_spawn_offset(index),
	}
	var player := _spawner.spawn(data) as Player
	if player != null:
		_register(player, peer)
		for ready_peer in _ready_peers:
			_show_to(player, ready_peer)


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
	player.player_id = index
	player.is_local = peer == multiplayer.get_unique_id()
	player.input = LocalKeyboardMouseInput.new() if player.is_local else RemoteInput.new()
	var appearance := {}
	if CharacterCatalog.has_character(StringName(str(info.get("character", "")))):
		appearance["character"] = StringName(str(info.get("character", "")))
	var color_text := str(info.get("color", ""))
	if Color.html_is_valid(color_text):
		appearance["color"] = Color.html(color_text)
	# The own player follows the save (and the wardrobe) like in single player.
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

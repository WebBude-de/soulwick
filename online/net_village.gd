class_name NetVillage
extends Node
## The host's village decoration for the guests of a relay room (WK5 "Gäste sehen das Dorf des
## Hosts", KONZEPT §8): child "NetVillage" of the village world, added by the WorldController before
## the world enters the tree (prepare), so the node path is the same on every machine.
## - Host: once per village load sends DecorState.snapshot() plus the colour of its guild banner
##   (reliable, at most MAX_BYTES) to every peer that has this village loaded
##   (NetPlayers.get_ready_peers), and to every peer that becomes ready later. Decorating only works
##   alone (DecorStation.can_decorate), so the host's decoration does not change inside a room.
## - Client: checks the snapshot (sanitize: size, known catalog ids of the right space, cells inside
##   the grid, no free text) and shows it (Village.apply_host_decor, view only, the own save stays
##   untouched); a rejected snapshot changes nothing. When the room ends without a reload of the
##   village, the own decoration and the own banner colour come back.
## Every machine: prepare() sets DecorPiece.guild_color from the own guild before the village is
## built (white without a guild or without a colour in the guild data).

const NODE_NAME := &"NetVillage"
## The host's peer id in a relay room (RelayProtocol.HOST_PEER_ID).
const HOST_PEER := 1
## TESTWERT: largest snapshot a host sends and a client takes (var_to_bytes, bytes).
const MAX_BYTES := 16384
## TESTWERT: most placements per space in a snapshot (the village grid is 32×20, the home 15×9).
const MAX_PLACEMENTS := {"village": 256, "home": 160}
## Longest placement entry ("id:col:row:rot") a client takes.
const MAX_ENTRY_LENGTH := 64
const KEY_GUILD_COLOR := "guild_color"
## Guild data keys that may carry the banner colour (hex "#rrggbb"); the API has none yet.
const GUILD_COLOR_KEYS: Array[String] = ["color", "bannerColor"]
## Tools (net_run_smoke): with this environment variable "1" every machine prints what its NetVillage
## sent, took and rejected when the village goes (client processes inherit it).
const ENV_LOG := "SOULWICK_NET_VILLAGE_LOG"

var village: Village = null
## Banner colour of this machine's own guild (restored when the host's view goes).
var own_guild_color := Color.WHITE
## Tests and tools: snapshots sent (host), taken and rejected (client).
var sent_count := 0
var received_count := 0
var rejected_count := 0
## The ready peers of this world (tests swap it): () -> Array[int].
var ready_peers: Callable = _world_ready_peers
## Sends a snapshot to one peer (tests swap it): (peer: int, data: Dictionary) -> void.
var send_to: Callable = _rpc_send
## True on the machine that decides (tests swap it): () -> bool.
var host_check: Callable = _default_is_host
## True while a relay room is connected (tests swap it): () -> bool.
var connected_check: Callable = _connected

## Host: peers that got the snapshot of this village load.
var _sent: Dictionary[int, bool] = {}
## Client: the host's arrangement is shown.
var _showing_host := false
## The role seen while the room was live (the log at exit, when the peer may be closed already).
var _role := ""


## Sets the banner colour of the own guild for world (a village) and, in a relay room, adds the
## network part. Call before the world enters the tree. Returns the NetVillage or null.
static func prepare(world: Node, networked: bool, tree: SceneTree) -> NetVillage:
	var target := world as Village
	if target == null:
		return null
	var colour := own_guild_color_in(tree)
	DecorPiece.guild_color = colour
	if not networked:
		return null
	var net := attach(target)
	net.own_guild_color = colour
	return net


## Adds the network part to village (idempotent). Returns it, null without a village.
static func attach(target: Village) -> NetVillage:
	if target == null or not is_instance_valid(target):
		return null
	var existing := target.get_node_or_null(NodePath(NODE_NAME)) as NetVillage
	if existing != null:
		return existing
	var net := NetVillage.new()
	net.name = NODE_NAME
	net.village = target
	target.add_child(net)
	return net


## Banner colour of this machine's guild: the guild of the room in a guild room, else the oldest
## membership of the logged-in account; white without a session, a guild or a colour.
static func own_guild_color_in(tree: SceneTree) -> Color:
	if tree == null:
		return Color.WHITE
	var session := tree.get_first_node_in_group(OnlineSession.GROUP) as OnlineSession
	if session == null:
		return Color.WHITE
	var lobby := tree.get_first_node_in_group(LobbyClient.GROUP) as LobbyClient
	var room_guild := lobby.get_room_guild_id() if lobby != null else ""
	return guild_color_for(session.player, room_guild)


## Banner colour from a PlayerSelf (guilds, oldest first; the old single "guild" as fallback).
static func guild_color_for(self_data: Dictionary, room_guild_id := "") -> Color:
	var guilds: Array = []
	var list: Variant = self_data.get("guilds", null)
	if list is Array:
		guilds = list
	var single: Variant = self_data.get("guild", null)
	if guilds.is_empty() and single is Dictionary:
		guilds = [single]
	if guilds.is_empty():
		return Color.WHITE
	for guild: Variant in guilds:
		if guild is Dictionary and not room_guild_id.is_empty() and str((guild as Dictionary).get("id", "")) == room_guild_id:
			return guild_color_of(guild)
	return guild_color_of(guilds[0])


## The colour a guild's data carries ("#rrggbb"), opaque; white if it has none.
static func guild_color_of(guild: Variant) -> Color:
	if not guild is Dictionary:
		return Color.WHITE
	for key in GUILD_COLOR_KEYS:
		var colour: Variant = parse_color((guild as Dictionary).get(key, null))
		if colour != null:
			return colour
	return Color.WHITE


## An opaque colour from "#rrggbb"/"rrggbb", null for anything else (no names, no alpha tricks).
static func parse_color(raw: Variant) -> Variant:
	if typeof(raw) != TYPE_STRING:
		return null
	var text := String(raw).strip_edges().trim_prefix("#")
	if text.length() != 6 or not text.is_valid_hex_number(false):
		return null
	var colour := Color.html(text)
	colour.a = 1.0
	return colour


func _ready() -> void:
	if village == null:
		village = get_parent() as Village


func is_host() -> bool:
	return bool(host_check.call())


func _process(_delta: float) -> void:
	if village == null or not is_instance_valid(village):
		return
	var live := bool(connected_check.call())
	if live:
		_role = "host" if is_host() else "client"
	if is_host():
		if live:
			send_to_new_peers()
	elif _showing_host and not live:
		# The room ended and the village stays (no reload): the own decoration comes back.
		show_own()


## Host: the snapshot to every ready peer that has not got it in this village load. Returns how many.
func send_to_new_peers() -> int:
	var peers: Array[int] = []
	peers.assign(ready_peers.call())
	for peer: int in _sent.keys():
		if not peers.has(peer):
			_sent.erase(peer)
	var own := multiplayer.get_unique_id() if multiplayer != null and multiplayer.has_multiplayer_peer() else HOST_PEER
	var count := 0
	var data := {}
	for peer in peers:
		if peer == own or _sent.has(peer):
			continue
		if data.is_empty():
			data = build_snapshot(DecorState.snapshot(), DecorPiece.guild_color)
		send_to.call(peer, data)
		_sent[peer] = true
		count += 1
	sent_count += count
	return count


## The host's snapshot as sent: the decoration (capped per space, then trimmed to MAX_BYTES) and the
## banner colour as "#rrggbb".
static func build_snapshot(decor: Dictionary, colour: Color) -> Dictionary:
	var data := {}
	for space: String in MAX_PLACEMENTS:
		var list: Array = []
		var raw: Variant = decor.get(space, [])
		if raw is Array or raw is PackedStringArray:
			for entry: Variant in raw:
				if typeof(entry) == TYPE_STRING and list.size() < int(MAX_PLACEMENTS[space]):
					list.append(String(entry))
		data[space] = list
	for setting in DecorState.SETTINGS:
		data[setting] = str(decor.get(setting, ""))
	data[KEY_GUILD_COLOR] = "#" + colour.to_html(false)
	# Too big (very long ids): the home goes first, the guests look at the village.
	while var_to_bytes(data).size() > MAX_BYTES:
		var home: Array = data[DecorState.HOME]
		var trimmed: Array = home if not home.is_empty() else data[DecorState.VILLAGE]
		if trimmed.is_empty():
			break
		trimmed.pop_back()
	return data


func _rpc_send(peer: int, data: Dictionary) -> void:
	rpc_id(peer, &"host_decor", data)


## Host -> clients: the host's village decoration (build_snapshot), once per village load.
@rpc("authority", "call_remote", "reliable")
func host_decor(data: Variant) -> void:
	if is_host():
		return
	receive(data)


## Client: shows the host's snapshot if it passes sanitize. False (and nothing changes) if not.
func receive(data: Variant) -> bool:
	if village == null or not is_instance_valid(village) or village.decor_layer == null:
		return false
	var clean := sanitize(data, village.decor_layer.grid.size)
	if clean.is_empty():
		rejected_count += 1
		return false
	received_count += 1
	DecorPiece.guild_color = clean[KEY_GUILD_COLOR]
	village.apply_host_decor(clean)
	_showing_host = true
	return true


## Client: the own decoration and banner colour again.
func show_own() -> void:
	_showing_host = false
	DecorPiece.guild_color = own_guild_color
	if village != null and is_instance_valid(village):
		village.apply_host_decor({})


func is_showing_host() -> bool:
	return _showing_host


## A snapshot from the network made safe, or {} to reject it: a dictionary of at most MAX_BYTES with
## at most MAX_PLACEMENTS entries per space. Entries that do not parse, are too long, name an
## unknown item or one of another space, or reach outside the grid (village: village_size, home:
## HomeLayout) are left out; a home surface is "" or an existing style; the colour is "#rrggbb"
## (white otherwise). Unknown keys are dropped.
static func sanitize(raw: Variant, village_size: Vector2i) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var data := raw as Dictionary
	if var_to_bytes(data).size() > MAX_BYTES:
		return {}
	var sizes := {"village": village_size, "home": Vector2i(HomeLayout.COLS, HomeLayout.ROWS)}
	var clean := {}
	for space: String in MAX_PLACEMENTS:
		var list: Variant = data.get(space, [])
		if not (list is Array or list is PackedStringArray):
			return {}
		var count: int = (list as Array).size() if list is Array else (list as PackedStringArray).size()
		if count > int(MAX_PLACEMENTS[space]):
			return {}
		clean[space] = _clean_placements(list, StringName(space), sizes[space])
	for setting in DecorState.SETTINGS:
		clean[setting] = _clean_surface(data.get(setting, ""), setting)
	var colour: Variant = parse_color(data.get(KEY_GUILD_COLOR, null))
	clean[KEY_GUILD_COLOR] = colour if colour != null else Color.WHITE
	return clean


static func _clean_placements(list: Variant, space: StringName, grid_size: Vector2i) -> Array:
	var result: Array = []
	for entry: Variant in list:
		if typeof(entry) != TYPE_STRING or String(entry).length() > MAX_ENTRY_LENGTH:
			continue
		var parsed := DecorState.parse(entry)
		if parsed.is_empty():
			continue
		var item := DecorCatalog.get_item(String(parsed["id"]))
		if item == null or item.space != space or item.is_surface():
			continue
		if not _inside(item, parsed["cell"], int(parsed["rot"]), grid_size):
			continue
		result.append(String(entry))
	return result


## Every cell of the piece inside a grid of grid_size.
static func _inside(item: DecorItem, cell: Vector2i, rot: int, grid_size: Vector2i) -> bool:
	var bounds := Rect2i(Vector2i.ZERO, grid_size)
	for covered in DecorGrid.cells_of(item, cell, item.normalized_rotation(rot)):
		if not bounds.has_point(covered):
			return false
	return true


## A home surface style: "" (the original room) or a style with a catalog item.
static func _clean_surface(raw: Variant, setting: String) -> String:
	if typeof(raw) != TYPE_STRING or String(raw).is_empty() or String(raw).length() > MAX_ENTRY_LENGTH:
		return ""
	var style := String(raw)
	return style if DecorCatalog.has_item(DecorCatalog.surface_id(setting.trim_prefix("home_"), style)) else ""


func _exit_tree() -> void:
	if OS.get_environment(ENV_LOG) == "1":
		print("NetVillage %s: sent %d, received %d, rejected %d, showing host %s" % [_role if not _role.is_empty() else "solo",
				sent_count, received_count, rejected_count, str(_showing_host)])
	# The next world sets its own colour (prepare); a guest's view of the host's banner ends here.
	if _showing_host:
		DecorPiece.guild_color = own_guild_color


func _default_is_host() -> bool:
	return multiplayer == null or not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _connected() -> bool:
	var peer := multiplayer.multiplayer_peer if multiplayer != null else null
	return peer != null and not (peer is OfflineMultiplayerPeer) and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _net_players() -> NetPlayers:
	return village.get_node_or_null(NodePath(NetPlayers.NODE_NAME)) as NetPlayers if village != null else null


func _world_ready_peers() -> Array[int]:
	var net_players := _net_players()
	return net_players.get_ready_peers() if net_players != null else ([] as Array[int])

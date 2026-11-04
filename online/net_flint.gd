class_name NetFlint
extends Node
## The one Flint of a networked world (WK13, D-225 §3): child "NetFlint" of the world's Flint
## (FlintCompanion, child "Flint" of the world), so the node path is the same on every machine.
## WorldController adds it with the Flint, before NetPlayers spawns anybody, in the village of a
## relay room and in the shared run alike.
## - Host: decides Flint's spot (FlintGroup, FlintFollow) and sends it SEND_RATE times a second
##   (unreliable, the next one replaces a lost one) to every peer that has this world loaded
##   (NetPlayers.get_ready_peers).
## - Client: Flint is net_driven: he glides to the host's spot (FlintCompanion.apply_net_follow);
##   roaming, bob, mood and his flight into the corner stay local optics.
## Both: the host's player is Flint's look owner (D-225 §6, WK2 hat and flame colour).

const NODE_NAME := &"NetFlint"
## TESTWERT: how often the host sends Flint's spot (per second); enemies go 15/s (MULTIPLAYER.md §3).
const SEND_RATE := 15.0
## The host's peer id in a relay room (RelayProtocol.HOST_PEER_ID).
const HOST_PEER := 1
## Tools (net_run_smoke): with this environment variable "1" every machine prints what its NetFlint
## sent and received when the world goes (client processes inherit it).
const ENV_LOG := "SOULWICK_NET_FLINT_LOG"

var flint: FlintCompanion = null
## Tests and tools: spots sent (host) and taken (client).
var sent_count := 0
var received_count := 0
## The ready peers of this world (tests swap it): () -> Array[int].
var ready_peers: Callable = _world_ready_peers

var _send_left := 0.0


## Adds the network part to flint (idempotent). Returns it, null without a Flint.
static func attach(target: FlintCompanion) -> NetFlint:
	if target == null or not is_instance_valid(target):
		return null
	var existing := target.get_node_or_null(NodePath(NODE_NAME)) as NetFlint
	if existing != null:
		return existing
	var net := NetFlint.new()
	net.name = NODE_NAME
	net.flint = target
	target.add_child(net)
	return net


func _ready() -> void:
	if flint == null:
		flint = get_parent() as FlintCompanion
	_apply_role()


## True on the machine that decides: the host of a relay room (or a machine without a session).
func is_host() -> bool:
	return multiplayer == null or not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _process(delta: float) -> void:
	if flint == null or not is_instance_valid(flint):
		return
	_apply_role()
	if not is_host() or not _connected():
		return
	_send_left -= delta
	if _send_left > 0.0:
		return
	_send_left = 1.0 / SEND_RATE
	send_spot()


## Host: sends Flint's spot to every ready peer now. Returns how many got it.
func send_spot() -> int:
	var spot := flint.get_follow_position()
	var own := multiplayer.get_unique_id()
	var count := 0
	for peer: int in ready_peers.call():
		if peer == own:
			continue
		rpc_id(peer, &"flint_spot", spot.x, spot.y)
		count += 1
	sent_count += count
	return count


## Host -> clients: Flint's pivot in global px.
@rpc("authority", "call_remote", "unreliable")
func flint_spot(x: float, y: float) -> void:
	if is_host() or flint == null or not is_instance_valid(flint):
		return
	received_count += 1
	flint.apply_net_follow(Vector2(x, y))


## The client draws, the host decides; the host's player is the look owner.
func _apply_role() -> void:
	var host := is_host()
	if flint.net_driven == host:
		flint.set_net_driven(not host)
	var net_players := _net_players()
	if net_players != null:
		var owner_player := net_players.get_player_for_peer(HOST_PEER)
		if owner_player != null:
			flint.host_player = owner_player


func _exit_tree() -> void:
	if OS.get_environment(ENV_LOG) == "1":
		var members := flint.get_members().size() if flint != null and is_instance_valid(flint) else 0
		print("NetFlint %s in %s: sent %d, received %d, members %d, net_driven %s" % ["host" if is_host() else "client",
				String(flint.get_parent().name) if flint != null and is_instance_valid(flint) and flint.get_parent() != null else "?",
				sent_count, received_count, members, str(flint.net_driven) if flint != null and is_instance_valid(flint) else "?"])


func _connected() -> bool:
	var peer := multiplayer.multiplayer_peer if multiplayer != null else null
	return peer != null and not (peer is OfflineMultiplayerPeer) and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _net_players() -> NetPlayers:
	var world := flint.get_parent() if flint != null else null
	return world.get_node_or_null(NodePath(NetPlayers.NODE_NAME)) as NetPlayers if world != null else null


func _world_ready_peers() -> Array[int]:
	var net_players := _net_players()
	return net_players.get_ready_peers() if net_players != null else ([] as Array[int])

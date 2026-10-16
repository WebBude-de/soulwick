class_name GameMode
extends RefCounted
## The session being played (MP1, D-080, D-081, D-085): solo, quick game or guild run, how many
## players take part and which of them sit at this machine. Held by the WorldController of game.tscn
## (no autoload, D-044); code anywhere in the game asks GameMode.of(node). Without a WorldController
## (main menu, unit tests) the answer is a solo session, so everything behaves as in single player.
## The mode only decides; the places that pause, freeze or apply meta upgrades act on its answers.

enum Kind { SOLO, QUICK, GUILD }
## Where the village upgrades of a run come from (D-081): the local save, none, the guild server.
enum MetaSource { LOCAL, NONE, GUILD }

## Group of the node that owns the session (the WorldController); it has a game_mode property.
const OWNER_GROUP: StringName = &"game_mode_owner"
const MAX_PLAYERS := 4

var kind: Kind = Kind.SOLO
## Players taking part, local and remote (1..MAX_PLAYERS).
var player_count := 1
## Player ids (0..player_count-1) that sit at this machine. Empty on a host without a player of its
## own (the "server code must not assume an own player" rule, MULTIPLAYER.md 4a).
var local_player_ids: Array[int] = [0]
## Online session (MP2): the LobbyClient of a relay room, or null for a session at this machine.
## When set, the world's players come from the network (attach_world) instead of the spawn order.
var network: Object = null
## Guild run (D-080, D-147): the API id of the guild whose room this is ("" otherwise). Only
## members may join (the relay checks), the run report carries it (POST /runs mode guild).
var guild_id := ""


static func solo() -> GameMode:
	return create(Kind.SOLO, 1, [0])


## Quick game (D-080): count players, local_ids of them at this machine.
static func quick(count: int, local_ids: Array[int] = [0]) -> GameMode:
	return create(Kind.QUICK, count, local_ids)


static func guild(count: int, local_ids: Array[int] = [0], owner_guild_id := "") -> GameMode:
	var mode := create(Kind.GUILD, count, local_ids)
	mode.guild_id = owner_guild_id
	return mode


static func create(mode_kind: Kind, count: int, local_ids: Array[int]) -> GameMode:
	var mode := GameMode.new()
	mode.kind = mode_kind
	mode.player_count = clampi(count, 1, MAX_PLAYERS)
	mode.local_player_ids.clear()
	for id in local_ids:
		if id >= 0 and id < mode.player_count and not mode.local_player_ids.has(id):
			mode.local_player_ids.append(id)
	return mode


## Session of the game node is part of (solo without a session owner in the tree).
static func of(node: Node) -> GameMode:
	if node == null or not node.is_inside_tree():
		return solo()
	return of_tree(node.get_tree())


static func of_tree(tree: SceneTree) -> GameMode:
	if tree == null:
		return solo()
	var owner_node := tree.get_first_node_in_group(OWNER_GROUP)
	var mode: Variant = owner_node.get(&"game_mode") if owner_node != null else null
	return mode if mode is GameMode else solo()


func is_multiplayer() -> bool:
	return kind != Kind.SOLO


## Players are spawned by the network (a relay room) instead of the WorldController.
func is_networked() -> bool:
	return network != null and is_instance_valid(network)


func get_player_count() -> int:
	return clampi(player_count, 1, MAX_PLAYERS)


func is_local(player_id: int) -> bool:
	return local_player_ids.has(player_id)


func has_local_player() -> bool:
	return not local_player_ids.is_empty()


## The player the single-player systems of a world serve first (shop, upgrade dialogs, vision):
## the first local player, or player 0 on a host without a player of its own.
func get_primary_player_id() -> int:
	return local_player_ids[0] if has_local_player() else 0


## Spawn order: the primary player first, then the others by id.
func get_spawn_order() -> Array[int]:
	var primary := get_primary_player_id()
	var order: Array[int] = [primary]
	for id in get_player_count():
		if id != primary:
			order.append(id)
	return order


## Menus hold the whole game only in single player (D-043). In a group game the world keeps
## running and the player in a menu is protected instead (D-085).
func pauses_for_menus() -> bool:
	return kind == Kind.SOLO


## HitStop changes Engine.time_scale for everybody: single player only (D-085).
func allows_hit_stop() -> bool:
	return kind == Kind.SOLO


## D-081: solo runs use the local village upgrades, quick games none, guild runs the guild's.
func get_meta_source() -> MetaSource:
	match kind:
		Kind.QUICK:
			return MetaSource.NONE
		Kind.GUILD:
			return MetaSource.GUILD
	return MetaSource.LOCAL


## RunMode of the API for the run report (contracts common.ts): "solo", "quick" or "guild". A guild
## session without a guild id reports as "quick" (the API needs the id for guild runs).
func get_run_mode_name() -> String:
	match kind:
		Kind.QUICK:
			return "quick"
		Kind.GUILD:
			return "guild" if not guild_id.is_empty() else "quick"
	return "solo"


## Input object for a new player: keyboard and mouse for the primary local player, RemoteInput for
## everybody else (remote players, local test dummies).
func create_input(player_id: int) -> PlayerInput:
	if has_local_player() and player_id == get_primary_player_id():
		return LocalKeyboardMouseInput.new()
	return RemoteInput.new()


## Short description for logs and tools, e.g. "QUICK 3 players, local [0]".
func describe() -> String:
	return "%s %d player%s, local %s" % [Kind.keys()[kind], get_player_count(), "" if get_player_count() == 1 else "s", local_player_ids]

extends GutTest
## NetVillage (WK5 Koop): the host sends its village decoration and banner colour once per village
## load to every ready peer (late joiners too), a guest shows it after a defensive check and gets its
## own decoration back when the room ends; prepare() sets the own guild's banner colour. Uses a test
## save file only.

const TEST_PATH := "user://test_net_village.cfg"
const VILLAGE_SCENE := "res://world/village/village.tscn"

var _old_path: String


func before_all() -> void:
	_old_path = SaveManager.save_path


func before_each() -> void:
	SaveManager.save_path = TEST_PATH
	_remove_files()
	SaveManager.load_game()
	DecorPiece.guild_color = Color.WHITE


func after_each() -> void:
	DecorPiece.guild_color = Color.WHITE


func after_all() -> void:
	_remove_files()
	SaveManager.save_path = _old_path
	SaveManager.load_game()


func _remove_files() -> void:
	for suffix in ["", ".bak", ".prev.bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + suffix))


func _village() -> Village:
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	add_child_autofree(village)
	return village


## A guest's NetVillage on village: no host, a live room.
func _guest(village: Village) -> NetVillage:
	var net := NetVillage.attach(village)
	net.host_check = func() -> bool: return false
	net.connected_check = func() -> bool: return true
	return net


func _host_snapshot(entries: Array, colour := "#3366cc") -> Dictionary:
	return {"village": entries, "home": [], "home_wall": "", "home_floor": "", "guild_color": colour}


# --- Banner colour ---------------------------------------------------------------------------

func test_guild_color_from_the_account() -> void:
	assert_eq(NetVillage.guild_color_for({}), Color.WHITE, "no guild: white")
	assert_eq(NetVillage.guild_color_for({"guilds": [{"id": "a", "name": "Ash"}]}), Color.WHITE,
			"a guild without a colour stays white")
	var guilds := {"guilds": [{"id": "a", "color": "#ff0000"}, {"id": "b", "color": "00ff00"}]}
	assert_eq(NetVillage.guild_color_for(guilds), Color(1, 0, 0), "the oldest membership")
	assert_eq(NetVillage.guild_color_for(guilds, "b"), Color(0, 1, 0), "the guild of the guild room")
	assert_eq(NetVillage.guild_color_for({"guilds": [], "guild": {"id": "c", "bannerColor": "#0000ff"}}),
			Color(0, 0, 1), "the old single guild field")
	for bad: Variant in ["red", "#ff000080", "#gg0000", 12, null, "#fff"]:
		assert_eq(NetVillage.guild_color_of({"color": bad}), Color.WHITE, "rejected colour %s" % str(bad))


func test_prepare_sets_the_colour_and_attaches_only_in_a_room() -> void:
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	DecorPiece.guild_color = Color.RED
	assert_null(NetVillage.prepare(village, false, get_tree()), "solo: no network part")
	assert_eq(DecorPiece.guild_color, Color.WHITE, "no session: white")
	var net := NetVillage.prepare(village, true, get_tree())
	assert_not_null(net)
	assert_eq(NetVillage.attach(village), net, "idempotent")
	add_child_autofree(village)
	assert_eq(String(village.get_path_to(net)), "NetVillage", "the same path on every machine")
	var plain := Node2D.new()
	assert_null(NetVillage.prepare(plain, true, get_tree()), "not a village")
	plain.free()


# --- Host ------------------------------------------------------------------------------------

func test_host_sends_once_per_peer_and_to_late_joiners() -> void:
	SaveManager.set_decor_placements(DecorState.VILLAGE, PackedStringArray([DecorState.format("flint_statue", Vector2i(3, 4), 0)]))
	DecorPiece.guild_color = Color(0.2, 0.4, 0.8)
	var village := _village()
	var net := NetVillage.attach(village)
	var peers: Array[int] = [1, 5]
	var sent: Array = []
	net.ready_peers = func() -> Array[int]: return peers
	net.send_to = func(peer: int, data: Dictionary) -> void: sent.append([peer, data])
	net.connected_check = func() -> bool: return true
	assert_true(net.is_host(), "without a session this machine decides")
	net._process(0.016)
	assert_eq(sent.size(), 1, "the host itself gets nothing")
	assert_eq(int(sent[0][0]), 5)
	var data: Dictionary = sent[0][1]
	assert_eq(Array(data["village"]), ["flint_statue:3:4:0"])
	assert_eq(String(data["guild_color"]), "#3366cc")
	assert_lt(var_to_bytes(data).size(), NetVillage.MAX_BYTES)
	net._process(0.016)
	assert_eq(sent.size(), 1, "once per village load")
	peers.append(7)
	net._process(0.016)
	assert_eq(sent.size(), 2, "a peer that loads the village later")
	assert_eq(int(sent[1][0]), 7)
	peers.erase(5)
	net._process(0.016)
	peers.append(5)
	net._process(0.016)
	assert_eq(sent.size(), 3, "a peer that loaded the village again")
	assert_eq(net.sent_count, 3)


func test_host_sends_nothing_without_a_room() -> void:
	var village := _village()
	var net := NetVillage.attach(village)
	var sent: Array = []
	net.ready_peers = func() -> Array[int]: return [5] as Array[int]
	net.send_to = func(peer: int, data: Dictionary) -> void: sent.append([peer, data])
	net._process(0.016)
	assert_eq(sent.size(), 0, "no relay room connected")


func test_build_snapshot_stays_small() -> void:
	var many: Array = []
	for index in 400:
		many.append(DecorState.format("flint_statue", Vector2i(index % 30, index % 18), 0))
	var data := NetVillage.build_snapshot({"village": many, "home": many}, Color.WHITE)
	assert_eq((data["village"] as Array).size(), int(NetVillage.MAX_PLACEMENTS["village"]), "capped per space")
	assert_lte(var_to_bytes(data).size(), NetVillage.MAX_BYTES)
	assert_false(NetVillage.sanitize(data, Vector2i(32, 20)).is_empty(), "a host's own snapshot passes the guest's check")


# --- Client ----------------------------------------------------------------------------------

func test_guest_sees_the_hosts_village_and_banner() -> void:
	var village := _village()
	var net := _guest(village)
	var entries := [DecorState.format("flint_statue", Vector2i(3, 4), 0), DecorState.format("guild_banner", Vector2i(8, 4), 0)]
	assert_true(net.receive(_host_snapshot(entries)))
	assert_true(net.is_showing_host())
	assert_true(village.decor_layer.is_showing_snapshot())
	assert_eq(village.decor_layer.get_pieces().size(), 2, "the host's statue and banner")
	assert_eq(DecorPiece.guild_color, Color("#3366cc"), "the host's banner colour")
	for piece in village.decor_layer.get_pieces():
		if piece.item.id == "guild_banner":
			assert_eq((piece.get_node(NodePath(DecorPiece.VISUAL)) as Node2D).modulate, Color("#3366cc"))
	assert_true(SaveManager.get_decor_placements(DecorState.VILLAGE).is_empty(), "the guest's save stays untouched")
	assert_eq(net.received_count, 1)


func test_guest_rejects_bad_snapshots() -> void:
	var village := _village()
	var net := _guest(village)
	assert_false(net.receive("flint_statue:1:1:0"), "not a dictionary")
	assert_false(net.receive({"village": "flint_statue:1:1:0"}), "not a list")
	var many: Array = []
	for index in int(NetVillage.MAX_PLACEMENTS["village"]) + 1:
		many.append(DecorState.format("flint_statue", Vector2i(1, 1), 0))
	assert_false(net.receive(_host_snapshot(many)), "too many entries")
	var huge := _host_snapshot([])
	huge["padding"] = "x".repeat(NetVillage.MAX_BYTES)
	assert_false(net.receive(huge), "too big")
	assert_eq(net.rejected_count, 4)
	assert_false(net.is_showing_host(), "a rejected snapshot changes nothing")
	assert_false(village.decor_layer.is_showing_snapshot())


func test_guest_drops_bad_entries() -> void:
	var size := Vector2i(32, 20)
	var good := DecorState.format("flint_statue", Vector2i(3, 4), 0)
	var raw := _host_snapshot([
		good,
		"no_such_item:3:4:0",
		DecorState.format("flint_statue", Vector2i(-1, 4), 0),
		DecorState.format("flint_statue", Vector2i(31, 19), 0),
		DecorState.format("flint_statue", Vector2i(400, 4), 0),
		"flint_statue:3:4",
		"flint_statue:a:4:0",
		12,
		"x".repeat(NetVillage.MAX_ENTRY_LENGTH + 1) + ":1:1:0",
	], "not a colour")
	raw["home"] = [DecorState.format("flint_statue", Vector2i(2, 3), 0)]
	raw["home_wall"] = "../../evil"
	raw["home_floor"] = 5
	raw["player_name"] = "<b>free text</b>"
	var clean := NetVillage.sanitize(raw, size)
	var statue := DecorCatalog.get_item("flint_statue")
	var corner_ok := Rect2i(Vector2i.ZERO, size).encloses(Rect2i(Vector2i(31, 19), statue.footprint(0)))
	var expected: Array = [good] if not corner_ok else [good, DecorState.format("flint_statue", Vector2i(31, 19), 0)]
	assert_eq(clean["village"], expected, "only known pieces inside the grid")
	assert_eq(clean["home"], [], "a village piece is not a home piece")
	assert_eq(clean["home_wall"], "")
	assert_eq(clean["home_floor"], "")
	assert_eq(clean["guild_color"], Color.WHITE, "a bad colour is white")
	assert_false(clean.has("player_name"), "unknown keys go")


func test_guest_gets_the_own_village_back_when_the_room_ends() -> void:
	SaveManager.set_decor_placements(DecorState.VILLAGE, PackedStringArray([DecorState.format("flint_statue", Vector2i(3, 4), 0)]))
	var village := _village()
	var net := _guest(village)
	net.own_guild_color = Color(0.5, 0.5, 0.5)
	assert_true(net.receive(_host_snapshot([])))
	assert_eq(village.decor_layer.get_pieces().size(), 0, "the host has nothing set")
	var live := [true]
	net.connected_check = func() -> bool: return live[0]
	net._process(0.016)
	assert_true(net.is_showing_host(), "still in the room")
	live[0] = false
	net._process(0.016)
	assert_false(net.is_showing_host())
	assert_false(village.decor_layer.is_showing_snapshot())
	assert_eq(village.decor_layer.get_pieces().size(), 1, "the own statue again")
	assert_eq(DecorPiece.guild_color, Color(0.5, 0.5, 0.5), "the own banner colour again")


func test_host_takes_no_snapshot() -> void:
	var village := _village()
	var net := NetVillage.attach(village)
	net.host_decor(_host_snapshot([DecorState.format("flint_statue", Vector2i(3, 4), 0)]))
	assert_eq(net.received_count, 0, "the host shows its own village")
	assert_false(village.decor_layer.is_showing_snapshot())

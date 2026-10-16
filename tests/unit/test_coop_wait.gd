extends GutTest
## Co-op waits (online test 16.10.2026, like the truck of R.E.P.O.): the wait display sits at the top
## centre inside the screen (the old label sat half outside its left edge), below a bar of the top
## centre, one channel at a time; the group countdown is a big number over "Beeil dich!" for a
## straggler and a smaller one over "Warte auf <Name>" for the ones waiting, pops and ticks every
## second, red from 3 s on. Rooms and side ways share CoopRules.WAIT_COUNTDOWN. The side way waits
## for the group - at the gate into a segment and at its door: the first living player there starts
## the countdown, who stands there is held and protected, the way starts once everybody is there or
## the time is up (downed players do not count), a client follows the host's state and holds its own
## player; the segment's camera follows the stragglers and nobody is pulled meanwhile. Without a
## network: fakes for NetDungeon and DungeonManager, RPC handlers called directly.

const WaitLine := preload("res://online/coop_wait_line.gd")
const WaitBanner := preload("res://online/coop_wait_banner.gd")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const STEP := 1.0 / 60.0
const SLOT := 4
const PLAN := [
	"####################",
	"#..................#",
	"#..................#",
	"#..................#",
	"#S................D#",
	"####################",
]


class FakeNet extends NetDungeon:
	var players_by_peer: Dictionary = {}
	var local: Player = null
	var sent: Array = []
	var line: WaitLine = null

	func player_of(peer: int) -> Player:
		return players_by_peer.get(peer, null)

	func names_of(peers: Array[int]) -> String:
		var names: Array[String] = []
		for peer in peers:
			names.append("P%d" % peer)
		return ", ".join(names)

	func get_local_player() -> Player:
		return local

	func send_to_clients(_node: Node, method: StringName, args: Array = []) -> void:
		sent.append([method, args])

	func get_wait_line() -> WaitLine:
		return line

	func count(method: StringName) -> int:
		var result := 0
		for entry: Array in sent:
			if entry[0] == method:
				result += 1
		return result


class FakeDungeon extends DungeonManager:
	var living: Array[Player] = []
	var started := 0

	func get_living_players() -> Array[Player]:
		var result: Array[Player] = []
		for player in living:
			if is_instance_valid(player) and player.is_alive():
				result.append(player)
		return result

	func start_side_transit(_gate: SideGate) -> SideTransit:
		started += 1
		return null

	func get_room_at_slot(_slot: int) -> RoomController:
		return null


var _old_save_path: String
var _net: FakeNet = null
var _dm: FakeDungeon = null
var _line: WaitLine = null


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_coop_wait_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	_line = WaitLine.new()
	add_child_autofree(_line)
	_net = autofree(FakeNet.new())
	_net.line = _line
	_dm = autofree(FakeDungeon.new())


func _side(host: bool) -> NetSide:
	var side := NetSide.new()
	side.name = NetSide.NODE_NAME
	side.net = _net
	side.dm = _dm
	add_child_autofree(side)
	side.is_host = host
	side.set_physics_process(false)
	return side


## A player of peer (its NetPlayerState carries the peer), standing still where it is put.
func _player(peer: int, at: Vector2) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.set_physics_process(false)
	var state := NetPlayerState.new()
	state.name = NetPlayerState.NODE_NAME
	state.peer_id = peer
	player.add_child(state)
	player.global_position = at
	_net.players_by_peer[peer] = player
	_dm.living.append(player)
	return player


func _gate() -> SideGate:
	var room := autofree(RoomController.new()) as RoomController
	room.slot_index = SLOT
	var gate := SideGate.new()
	add_child_autofree(gate)
	gate.next_room = room
	gate.cover(Vector2(1000, 1000), Vector2(1100, 1000))
	return gate


func _run(side: NetSide, seconds: float) -> void:
	for i in ceili(seconds / STEP):
		side._physics_process(STEP)


# --- Rules ---

func test_side_way_rules() -> void:
	assert_true(CoopRules.should_start_side_way(2, 2, 5.0), "everybody there")
	assert_false(CoopRules.should_start_side_way(2, 1, 5.0), "one missing, time left")
	assert_true(CoopRules.should_start_side_way(2, 1, 0.0), "time up")
	assert_true(CoopRules.should_start_side_way(1, 1, CoopRules.WAIT_COUNTDOWN), "alone: at once")
	assert_eq(CoopRules.WAIT_COUNTDOWN, 10.0, "TESTWERT of the online test 16.10.2026")
	assert_eq(CoopRules.countdown_seconds(7.2), 8)
	assert_eq(CoopRules.countdown_seconds(7.0), 7)
	assert_eq(CoopRules.countdown_seconds(-1.0), 0)


func test_wait_texts() -> void:
	var waiting := NetSide.wait_text(CoopRules.WaitHint.WAIT_FOR_MATES, "Anna")
	assert_true(waiting.contains("Anna") and not waiting.contains("%"), waiting)
	var hurry := NetSide.wait_text(CoopRules.WaitHint.MATES_WAIT_FOR_YOU, "Anna")
	assert_eq(hurry, WaitLine.hurry_text())
	assert_false(hurry.is_empty() or hurry == String(WaitLine.HURRY_KEY), "never the bare key: %s" % hurry)
	assert_eq(NetSide.wait_text(CoopRules.WaitHint.NONE, "Anna"), "", "downed: nothing")
	assert_eq(WaitLine.format(&"NO_SUCH_KEY_COOP_WAIT", [3], "in %d s"), "in 3 s", "fallback while the key is missing")


func test_countdown_rules() -> void:
	assert_eq(CoopRules.WAIT_COUNTDOWN, 10.0, "TESTWERT of the online test 16.10.2026, rooms and side ways")
	assert_true(CoopRules.should_start_room(2, 1, 0.0), "rooms: at 0 the straggler is brought in")
	assert_false(CoopRules.should_start_room(2, 1, 4.0))
	assert_true(CoopRules.countdown_urgent(2.5), "3 s shown: red")
	assert_false(CoopRules.countdown_urgent(3.5), "4 s shown")


# --- The countdown ---

func test_banner_big_for_a_straggler_small_for_the_waiting() -> void:
	var banner := _line.get_banner()
	banner.show_countdown(7.2, "Beeil dich!", true)
	assert_eq(banner.get_seconds(), 8)
	assert_true(banner.is_hurry())
	assert_eq(banner.get_caption(), "Beeil dich!")
	var big := banner.get_number_font_size()
	assert_eq(banner.get_number_color(), WaitBanner.COLOR)
	banner.show_countdown(5.0, "Warte auf Anna …", false)
	assert_lt(banner.get_number_font_size(), big, "smaller for the ones waiting")
	assert_gte(big, UiKit.font_px(24), "big enough for a phone")
	banner.show_countdown(2.4, "Warte auf Anna …", false)
	assert_true(banner.is_urgent())
	assert_eq(banner.get_number_color(), WaitBanner.URGENT_COLOR, "red from 3 s on")
	banner.hide_countdown()
	assert_eq(banner.get_seconds(), -1)


func test_banner_ticks_every_second() -> void:
	var banner := _line.get_banner()
	var left := 4.0
	while left > 0.0:
		banner.show_countdown(left, "Beeil dich!", true)
		left -= 0.25
	assert_eq(banner.ticks, 4, "4, 3, 2, 1")
	assert_eq(banner.urgent_ticks, 3, "3, 2, 1 in red")


func test_countdown_sits_at_the_top_centre() -> void:
	_line.set_text(WaitLine.CHANNEL_ROOM, WaitLine.hurry_text())
	_line.set_countdown(WaitLine.CHANNEL_ROOM, 6.0, true)
	await wait_process_frames(1)
	assert_true(_line.is_countdown_visible())
	assert_eq(_line.get_banner().get_seconds(), 6)
	var view := _line.get_viewport().get_visible_rect().size
	var rect := _line.get_line_rect()
	assert_gte(rect.position.x, 0.0)
	assert_lte(rect.end.x, view.x)
	assert_almost_eq(rect.get_center().x, view.x * 0.5, 2.0, "centred")
	assert_lt(rect.end.y, view.y * 0.4, "above the middle of the playfield")
	assert_true(_line.is_on_screen_top())
	assert_gt(_line.hurry_frames, 0, "the straggler's countdown is counted (tools)")
	assert_eq(_line.hurry_frames_on_screen, _line.hurry_frames, "every frame of it inside the screen")
	_line.clear_countdown(WaitLine.CHANNEL_ROOM)
	assert_false(_line.is_countdown_visible(), "without a countdown the plain line")
	assert_true(_line.is_line_visible())


# --- The line ---

func test_line_sits_at_the_top_centre_inside_the_screen() -> void:
	_line.set_text(WaitLine.CHANNEL_ROOM, "Warte auf Anna, Ben …")
	await wait_process_frames(1)
	var view := _line.get_viewport().get_visible_rect().size
	var rect := _line.get_line_rect()
	assert_true(_line.is_line_visible())
	assert_gte(rect.position.x, 0.0, "not cut off on the left (old label: x = -width / 2)")
	assert_lte(rect.end.x, view.x, "not cut off on the right")
	assert_almost_eq(rect.get_center().x, view.x * 0.5, 1.0, "centred")
	assert_eq(rect.position.y, UiKit.px(WaitLine.TOP), "at the top edge, not in the playfield")
	assert_lt(rect.end.y, view.y * 0.2, "a small line")
	assert_eq(_line.layer, WaitLine.LAYER)
	assert_gt(_line.layer, 20, "above DungeonUI's banners")


func test_line_moves_below_a_bar_of_the_top_centre() -> void:
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var bar := Control.new()
	bar.add_to_group(Hud.TOP_CENTER_GROUP)
	layer.add_child(bar)
	var view := _line.get_viewport().get_visible_rect().size
	bar.position = Vector2(view.x * 0.5 - 150.0, 10.0)
	bar.size = Vector2(300.0, 50.0)
	_line.set_text(WaitLine.CHANNEL_ROOM, "Warte auf Anna …")
	await wait_process_frames(1)
	assert_gte(_line.get_line_rect().position.y, 60.0, "below the bar")
	bar.visible = false
	await wait_process_frames(1)
	assert_eq(_line.get_line_rect().position.y, UiKit.px(WaitLine.TOP), "back up once the bar is gone")


func test_line_shows_one_channel_at_a_time() -> void:
	_line.set_text(WaitLine.CHANNEL_PLAYERS, "players")
	_line.set_text(WaitLine.CHANNEL_ROOM, "room")
	assert_eq(_line.get_text(), "room", "the room wait beats the start wait")
	_line.set_text(WaitLine.CHANNEL_SIDE, "side")
	assert_eq(_line.get_text(), "side")
	assert_eq(_line.get_shown_channel(), WaitLine.CHANNEL_SIDE)
	_line.set_text(WaitLine.CHANNEL_SIDE, "")
	assert_eq(_line.get_text(), "room", "the next one comes back")
	_line.clear_all()
	assert_false(_line.is_line_visible())


# --- Gate into a segment (host) ---

func test_host_gate_waits_for_the_straggler() -> void:
	var side := _side(true)
	var gate := _gate()
	var host := _player(1, gate.global_position)
	var client := _player(2, Vector2(400, 400))
	_net.local = host
	assert_false(side.allow_side_transit(gate), "the way does not start with a straggler")
	assert_eq(side.get_wait_kind(), NetSide.WaitKind.ENTRY)
	assert_eq(_net.count(&"side_transit_net"), 0, "nobody pulled")
	_run(side, 3.0)
	assert_true(host.is_protected() and host.is_input_locked(), "who is at the gate waits (held, protected)")
	assert_false(client.is_protected(), "the straggler moves freely")
	assert_eq(side.get_wait_peers(), [1] as Array[int])
	assert_eq(side.get_missing_peers(), [2] as Array[int])
	assert_eq(side.get_wait_hint(), CoopRules.WaitHint.WAIT_FOR_MATES)
	assert_true(_line.get_text().contains("P2"), "\"Warte auf P2 …\": %s" % _line.get_text())
	assert_eq(_line.get_banner().get_seconds(), 7, "the countdown")
	assert_false(_line.get_banner().is_hurry(), "small for the one waiting")
	assert_gt(_net.count(&"side_wait_net"), 1, "the clients get the state (and every second)")
	assert_eq(_dm.started, 0)
	client.global_position = gate.global_position + Vector2(20, 0)
	_run(side, 0.1)
	assert_eq(_dm.started, 1, "everybody at the gate: the way starts")
	assert_eq(side.transits, 1)
	assert_eq(_net.count(&"side_transit_net"), 1)
	assert_eq(side.waits_full, 1)
	assert_eq(side.get_wait_kind(), NetSide.WaitKind.NONE)
	assert_false(host.is_protected(), "let go when the way starts")
	assert_eq(_line.get_text(), "")
	var last: Array = _net.sent[_net.sent.size() - 2]
	assert_eq(last[0], &"side_wait_net", "the clients hear the wait is over first")
	assert_eq(int(last[1][0]), int(NetSide.WaitKind.NONE))


func test_host_gate_starts_when_the_time_is_up() -> void:
	var side := _side(true)
	var gate := _gate()
	_net.local = _player(1, gate.global_position)
	_player(2, Vector2(400, 400))
	side.allow_side_transit(gate)
	_run(side, CoopRules.WAIT_COUNTDOWN - 0.5)
	assert_eq(_dm.started, 0, "still waiting")
	_run(side, 1.0)
	assert_eq(_dm.started, 1, "time up: the straggler is taken along")
	assert_eq(side.waits_timed_out, 1)
	assert_almost_eq(side.max_side_wait, CoopRules.WAIT_COUNTDOWN, 0.1)


func test_host_gate_starts_at_once_when_everybody_is_there_and_downed_do_not_count() -> void:
	var side := _side(true)
	var gate := _gate()
	_net.local = _player(1, gate.global_position)
	var downed := _player(2, Vector2(400, 400))
	downed.health.take_damage(downed.health.get_health() + 1.0)
	assert_false(downed.is_alive())
	assert_true(side.allow_side_transit(gate), "only living players count: the DungeonManager starts now")
	assert_eq(side.transits, 1)
	assert_eq(side.get_wait_kind(), NetSide.WaitKind.NONE)
	assert_false(side.allow_side_transit(gate), "never twice")


func test_host_straggler_sees_the_hurry_line() -> void:
	var side := _side(true)
	var gate := _gate()
	_player(2, gate.global_position)
	_net.local = _player(1, Vector2(400, 400))
	side.allow_side_transit(gate)
	_run(side, 2.5)
	assert_eq(side.get_wait_hint(), CoopRules.WaitHint.MATES_WAIT_FOR_YOU)
	assert_eq(_line.get_text(), WaitLine.hurry_text())
	assert_eq(_line.get_banner().get_seconds(), 8, "countdown")
	assert_true(_line.get_banner().is_hurry(), "big for the straggler")
	assert_false(_net.local.is_protected())


# --- Client ---

func test_client_follows_the_hosts_wait() -> void:
	var side := _side(false)
	# Offline the own peer id is 1: here the client's own player, the host's player is peer 7.
	var own := _player(1, Vector2(400, 400))
	_player(7, Vector2.ZERO)
	_net.local = own
	side.side_wait_net(NetSide.WaitKind.ENTRY, SLOT, PackedInt32Array([7]), PackedInt32Array([1]), 9.0)
	_run(side, 1.5)
	assert_eq(side.get_wait_hint(), CoopRules.WaitHint.MATES_WAIT_FOR_YOU)
	assert_eq(_line.get_banner().get_seconds(), 8, "local countdown between messages")
	assert_false(own.is_protected())
	side.side_wait_net(NetSide.WaitKind.ENTRY, SLOT, PackedInt32Array([1, 7]), PackedInt32Array(), 5.0)
	_run(side, STEP)
	assert_true(own.is_protected(), "the host counts it as waiting: held")
	side.side_wait_net(NetSide.WaitKind.NONE, SLOT, PackedInt32Array(), PackedInt32Array(), 0.0)
	_run(side, STEP)
	assert_false(own.is_protected(), "let go when the wait is over")
	assert_eq(_line.get_text(), "")
	assert_eq(side.side_waits, 1)


# --- Door of a segment ---

func _segment(side: NetSide) -> SideSegment:
	side._segment_slot = SLOT
	var layout := SideLayout.parse(PackedStringArray(PLAN), &"coop_wait")
	layout.biome_id = &"crypt"
	var segment := SideSegment.new()
	segment.setup(layout, 1, null, 9)
	side.on_node_added(segment)
	add_child_autofree(segment)
	segment.global_position = Vector2(0, 21000)
	segment.set_physics_process(false)
	return segment


func _side_player(segment: SideSegment, peer: int, cell: Vector2i) -> Player:
	var player := _player(peer, Vector2.ZERO)
	segment.add_player(player)
	player.side_motion.place_at(segment.to_global(SideLayout.feet_of(cell)))
	return player


func test_segment_door_waits_only_in_a_group_game() -> void:
	var segment := SideSegment.new()
	var layout := SideLayout.parse(PackedStringArray(PLAN), &"coop_wait")
	layout.biome_id = &"crypt"
	segment.setup(layout, 1, null, 9)
	add_child_autofree(segment)
	segment.global_position = Vector2(0, 23000)
	segment.set_physics_process(false)
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.set_physics_process(false)
	segment.add_player(player)
	player.side_motion.place_at(segment.get_door_feet())
	assert_true(segment.is_at_door(player))
	segment.door_waits = true
	segment._physics_process(STEP)
	assert_false(segment.is_finished, "co-op: the door only counts")
	segment.door_waits = false
	segment._physics_process(STEP)
	assert_true(segment.is_finished, "solo: the first at the door ends it as before")


func test_host_door_waits_for_the_straggler() -> void:
	var side := _side(true)
	var segment := _segment(side)
	assert_true(segment.door_waits, "the host's segment waits at its door")
	# Offline the own peer id is 1: here the straggler is this machine's player, peer 2 runs ahead.
	var host := _side_player(segment, 2, Vector2i(2, 4))
	var client := _side_player(segment, 1, Vector2i(3, 4))
	_net.local = client
	_run(side, 0.5)
	assert_eq(side.get_wait_kind(), NetSide.WaitKind.NONE, "nobody at the door yet")
	host.side_motion.place_at(segment.get_door_feet())
	_run(side, 1.0)
	assert_eq(side.get_wait_kind(), NetSide.WaitKind.EXIT)
	assert_true(host.is_protected(), "waits at the door, held")
	assert_eq(segment.get_door_waiting(), [host] as Array[Player])
	assert_eq(segment.camera_targets(), [client] as Array[Player], "the camera follows the straggler")
	assert_false(segment.is_finished, "nobody pulled")
	assert_eq(side.get_wait_hint(), CoopRules.WaitHint.MATES_WAIT_FOR_YOU)
	assert_eq(_line.get_banner().get_seconds(), 9, "hurry with the countdown")
	assert_eq(_line.get_text(), WaitLine.hurry_text())
	_line._update_arrow()
	assert_eq(_line.get_arrow_channel(), WaitLine.CHANNEL_SIDE, "the arrow points the straggler to the door")
	# No catch-up meanwhile: the straggler out of view stays where it is.
	var before := client.global_position
	var view := Rect2(host.global_position - Vector2(50, 50), Vector2(100, 100))
	for i in ceili(SideRules.CATCH_UP_TIME / STEP) + 5:
		segment._update_catch_up(client, view, STEP)
	assert_eq(client.global_position, before, "not pulled to the door while the others wait")
	client.side_motion.place_at(segment.get_door_feet())
	_run(side, 0.1)
	assert_true(segment.is_finished, "everybody at the door: the segment ends")
	assert_eq(side.waits_full, 1)
	assert_false(host.is_protected())
	assert_true(segment.get_door_waiting().is_empty())
	assert_eq(segment.camera_targets().size(), 2)


func test_host_door_ends_when_the_time_is_up() -> void:
	var side := _side(true)
	var segment := _segment(side)
	var host := _side_player(segment, 1, Vector2i(2, 4))
	_side_player(segment, 2, Vector2i(3, 4))
	_net.local = host
	host.side_motion.place_at(segment.get_door_feet())
	_run(side, CoopRules.WAIT_COUNTDOWN - 0.5)
	assert_false(segment.is_finished)
	assert_true(_line.get_text().contains("P2"), "\"Warte auf P2 …\": %s" % _line.get_text())
	_run(side, 1.0)
	assert_true(segment.is_finished, "time up: the straggler comes along")
	assert_eq(side.waits_timed_out, 1)


func test_client_holds_its_player_at_the_door_at_once() -> void:
	var side := _side(false)
	var segment := _segment(side)
	var own := _side_player(segment, 1, Vector2i(2, 4))
	_net.local = own
	own.side_motion.place_at(segment.get_door_feet())
	_run(side, STEP)
	assert_true(own.is_protected(), "held before the host's word")
	_run(side, NetSide.WAIT_PREDICT_GRACE + 0.2)
	assert_false(own.is_protected(), "no word from the host: let go")
	_run(side, 0.5)
	assert_false(own.is_protected(), "once per door")

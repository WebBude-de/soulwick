extends GutTest
## Flint in online games (feedback 23.10.2026): no explanations in the online lobby and the village of
## a relay room (#ce7cde79, FlintGuide.allowed_now), and in a shared run the "first time" hints go
## through the host to everybody at once, all players held until the learner is through or the time
## is up (#2b1a5a87, NetGuide; FlintControls routes to it). Seen flags are a dictionary, never the
## real save; no network (NetGuide's message paths are called directly).

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const DT := 1.0 / 60.0

var _seen: Dictionary = {}
var _old_save_path: String
var _old_phase: GameManager.Phase


## Stands in for the LobbyClient (group lobby_client): in a relay room or not.
class FakeLobby extends Node:
	var in_room := true

	func is_in_room() -> bool:
		return in_room

	func is_busy() -> bool:
		return false


## Stands in for NetGuide in FlintControls' routing test.
class FakeRouter extends Node:
	var asked: Array[StringName] = []

	func request_hint(_player: Player, id: StringName) -> bool:
		asked.append(id)
		return true


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_flint_guide_group_save.cfg"


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	_seen.clear()
	_old_phase = GameManager.get_phase()


func after_each() -> void:
	GameManager.set_phase(_old_phase)


func _player() -> Player:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.global_position = Vector2(400, 300)
	return player


func _guide(player: Player) -> FlintGuide:
	var guide := FlintGuide.for_player(player)
	guide.set_process(false)
	guide.shows_view = false
	guide.has_seen = func(id: StringName) -> bool: return _seen.has(id)
	guide.mark_seen = func(id: StringName) -> void: _seen[id] = true
	return guide


func _tour() -> FlintExplanation:
	return FlintExplanation.tour(&"flint_group_test_tour", [FlintGuideStep.say(&"FLINT_ENTRANCE_2")])


func _run(guide: FlintGuide, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		guide.advance(DT)
		left -= DT


func _lobby(in_room := true) -> FakeLobby:
	var lobby := FakeLobby.new()
	lobby.in_room = in_room
	lobby.add_to_group(FlintGuide.LOBBY_GROUP)
	add_child_autofree(lobby)
	return lobby


# --- No Flint in the online lobby and village (#ce7cde79) ---

func test_flint_explains_nothing_in_the_village_of_an_online_room() -> void:
	GameManager.set_phase(GameManager.Phase.VILLAGE)
	assert_true(FlintGuide.allowed_now(get_tree()), "solo: Flint explains")
	var lobby := _lobby()
	assert_true(FlintGuide.is_online(get_tree()))
	assert_false(FlintGuide.allowed_now(get_tree()), "in a relay room in the village: no Flint")
	var player := _player()
	var guide := _guide(player)
	assert_false(guide.queue(_tour()), "no tour starts")
	assert_false(_seen.has(&"flint_group_test_tour"), "and nothing is marked seen")
	GameManager.set_phase(GameManager.Phase.DUNGEON)
	assert_true(FlintGuide.allowed_now(get_tree()), "the dungeon of a shared run: the group hints run")
	lobby.in_room = false
	GameManager.set_phase(GameManager.Phase.VILLAGE)
	assert_true(FlintGuide.allowed_now(get_tree()), "left the room: Flint is back")


func test_joining_a_lobby_ends_a_running_tour_unseen() -> void:
	GameManager.set_phase(GameManager.Phase.VILLAGE)
	var player := _player()
	var guide := _guide(player)
	assert_true(guide.queue(_tour()))
	_run(guide, FlintGuideRules.GROW_TIME + FlintGuideRules.FLY_OUT_TIME + DT)
	assert_true(guide.is_running())
	_lobby()
	guide._process(DT)
	assert_false(guide.is_running(), "the tour stops at once")
	assert_false(player.is_protected(), "the player is free")
	assert_false(_seen.has(&"flint_group_test_tour"), "unseen: it comes on the next solo start")


# --- Hints for the whole group (#2b1a5a87) ---

func test_the_coach_hands_hints_to_the_group_router() -> void:
	var router := FakeRouter.new()
	router.add_to_group(FlintControls.GROUP_ROUTER)
	add_child_autofree(router)
	var player := _player()
	var coach := FlintControls.new()
	var direct: Array[StringName] = []
	coach.explain = func(_p: Player, explanation: FlintExplanation) -> bool:
		direct.append(explanation.id)
		return true
	coach.has_seen = func(_id: StringName) -> bool: return false
	coach.players_override = [player]
	add_child_autofree(coach)
	coach.tick(FlintControls.START_DELAY + 0.1)
	assert_eq(router.asked, [FlintControls.BASICS] as Array[StringName], "the router gets the hint")
	assert_true(direct.is_empty(), "not shown at this machine alone")
	assert_true(FlintControls.explain_first(player, FlintControls.CHASM))
	assert_true(router.asked.has(FlintControls.CHASM), "explain_first goes the same way")


func _net_guide(host: bool, local: Player, everybody: Array[Player]) -> NetGuide:
	var net_guide := NetGuide.create(null)
	net_guide.is_host = host
	net_guide.local_player = func() -> Player: return local
	net_guide.all_players = func() -> Array[Player]: return everybody
	add_child_autofree(net_guide)
	return net_guide


func test_host_shows_a_hint_to_everybody_and_holds_all_until_the_learner_is_through() -> void:
	GameManager.set_phase(GameManager.Phase.DUNGEON)
	var host_player := _player()
	var client_copy := _player()
	client_copy.is_local = false
	var guide := _guide(host_player)
	var net_guide := _net_guide(true, host_player, [host_player, client_copy] as Array[Player])
	assert_true(net_guide.request_hint(host_player, FlintControls.SPECIAL), "taken over")
	assert_eq(net_guide.get_active(), FlintControls.SPECIAL)
	assert_true(net_guide.is_learner(), "the host's own player asked: he pages")
	assert_true(host_player.is_protected(), "the host's player is held")
	assert_true(client_copy.is_protected(), "the client's player is held at the host too")
	assert_eq(guide.current.id, FlintControls.SPECIAL)
	assert_true(guide.current.locks_player(), "a tour with \"Weiter\" for the learner")
	assert_false(guide.current.advances_by_itself())
	_run(guide, FlintGuideRules.GROW_TIME + FlintGuideRules.FLY_OUT_TIME + 0.5)
	guide.press()
	_run(guide, 0.2)
	guide.press()
	_run(guide, FlintGuideRules.FLY_BACK_TIME + DT)
	assert_eq(net_guide.get_active(), &"", "the learner is through: over for everybody")
	assert_false(host_player.is_protected())
	assert_false(client_copy.is_protected())
	assert_true(_seen.has(FlintControls.SPECIAL), "seen")
	assert_true(net_guide.request_hint(host_player, FlintControls.SPECIAL), "seen: nothing more to do")
	assert_eq(net_guide.get_active(), &"")


func test_a_clients_hint_runs_on_the_host_and_ends_by_time() -> void:
	GameManager.set_phase(GameManager.Phase.DUNGEON)
	var host_player := _player()
	var guide := _guide(host_player)
	_seen[FlintControls.SWITCH] = true
	var net_guide := _net_guide(true, host_player, [host_player] as Array[Player])
	# Client 7 is new to weapon switching; the host's own player knows it already.
	net_guide.host_need(FlintControls.SWITCH, 7)
	assert_eq(net_guide.get_active(), FlintControls.SWITCH)
	assert_false(net_guide.is_learner(), "the host's player only watches")
	assert_true(host_player.is_protected(), "but waits with everybody")
	assert_eq(guide.current.id, FlintControls.SWITCH, "shown here too, even though seen")
	assert_true(guide.current.advances_by_itself(), "it goes on by itself for those who watch")
	net_guide.host_need(FlintControls.INTERACT, 7)
	assert_eq(net_guide.get_waiting_count(), 1, "one at a time")
	var limit := NetGuide.time_limit(FlintControls.explanation_for(FlintControls.SWITCH))
	assert_between(limit, NetGuide.LIMIT_MIN, NetGuide.LIMIT_MAX)
	net_guide._process(limit + 0.1)
	assert_eq(net_guide.get_active(), FlintControls.INTERACT, "time up: the next one starts")
	net_guide.host_done(FlintControls.INTERACT, 7)
	assert_eq(net_guide.get_active(), &"", "client 7 is through")
	_run(guide, FlintGuideRules.FLY_BACK_TIME + DT)
	assert_false(host_player.is_protected(), "free once Flint is back")
	assert_null(guide.current, "the dropped hint does not come afterwards")


func test_a_client_follows_the_host() -> void:
	GameManager.set_phase(GameManager.Phase.DUNGEON)
	var player := _player()
	var guide := _guide(player)
	var net_guide := _net_guide(false, player, [player] as Array[Player])
	net_guide.group_hint(String(FlintControls.OVERVIEW), PackedInt32Array([5]))
	assert_true(net_guide.is_showing())
	assert_true(player.is_protected(), "held while the host's hint runs")
	assert_eq(guide.current.id, FlintControls.OVERVIEW)
	net_guide.group_hint_end(String(FlintControls.OVERVIEW))
	assert_false(net_guide.is_showing())
	assert_ne(guide.phase, FlintGuide.Phase.TALK, "Flint flies back")
	_run(guide, FlintGuideRules.FLY_BACK_TIME + DT)
	assert_false(player.is_protected(), "free when the host ends it")

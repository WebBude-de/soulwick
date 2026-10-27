extends GutTest
## Flint explains new room types (WK11, KONZEPT §7.2, D-206, D-211): the texts of every room type
## (en + de, 2-4 sentences, two lines each), the tour between door and banner the first time per
## account (camera goals from the mode, fight held, the learner protected, no lock of its own), the
## short intro for known room types, co-op (the intro waits until every living player is in the
## room; the same learners and the same extra countdown on every machine; once anybody learns, every
## player sees the tour and is protected - playtest 23.10.2026 #88465571, #2b1a5a87; seen state
## through the lobby profile) and the old card that only hands the genre to Flint.
## Seen flags: player meta and a swapped FlintGuide store; the account file is a test file
## (AccountProgress.path_override), never the real save (AGENTS.md rule 4).

const TEST_SAVE_PATH := "user://test_room_intro_flint.cfg"
const TEST_PROGRESS_PATH := "user://test_room_intro_flint_progress.cfg"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
const MODES: Array[StringName] = [&"escort", &"flame", &"relic", &"souls", &"rifts", &"hunt", &"lightfire", &"collapse"]

var _old_save_path: String
var _seen: Dictionary = {}


## Stand-in for a RoomController whose fight may already run.
class FakeRoom:
	extends Node2D
	var started := false
	var room_index := 7

	func is_encounter_started() -> bool:
		return started


## A room with an arena rect (co-op: the intro waits until everybody stands in it).
class ArenaRoom:
	extends FakeRoom

	func get_arena() -> Rect2:
		return Rect2(0, 0, 800, 600)


## A mode node with camera goals of its own (like the room's CombatVariant).
class FakeMode:
	extends Node2D
	var points: Array = []

	func get_flint_steps() -> Array[FlintGuideStep]:
		return RoomFlint.steps(&"hunt", points)


## The session owner (WorldController stand-in): GameMode.of answers its game_mode.
class ModeOwner:
	extends Node
	var game_mode: GameMode = null


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	AccountProgress.path_override = TEST_PROGRESS_PATH
	AccountProgress.reset()


func before_each() -> void:
	_seen.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.load_game()
	RoomFlint.explain_in_scripts = true


func after_each() -> void:
	RoomFlint.explain_in_scripts = false
	Loc.apply(&"de")


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROGRESS_PATH))
	AccountProgress.path_override = ""
	AccountProgress.reset()
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


# --- Helpers ---

func _room() -> FakeRoom:
	var room := FakeRoom.new()
	add_child_autofree(room)
	return room


func _goal(room: Node2D, mode: StringName) -> RoomObjective:
	return RoomObjective.attach(room, RoomObjective.create(mode))


## A player whose seen flags are this test's: known room types (meta, like a co-op session) or the
## swapped guide store; remote = a mate of another machine (name tag name).
func _player(known: Array = [], remote := false, player_name := "", at := Vector2(400, 300)) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.is_local = not remote
	add_child_autofree(player)
	player.global_position = at
	RoomFlint.set_known(player, known)
	if not player_name.is_empty():
		var tag := Label.new()
		tag.name = "NameTag"
		tag.text = player_name
		player.add_child(tag)
	if not remote:
		var guide := FlintGuide.for_player(player)
		guide.shows_view = false
		guide.has_seen = func(id: StringName) -> bool: return _seen.has(id)
		guide.mark_seen = func(id: StringName) -> void: _seen[id] = true
	return player


func _coop(count := 2) -> void:
	var owner := ModeOwner.new()
	owner.game_mode = GameMode.quick(count)
	owner.add_to_group(GameMode.OWNER_GROUP)
	add_child_autofree(owner)


func _phases(intro: RoomIntro) -> Array:
	var phases: Array = []
	intro.phase_changed.connect(func(phase: RoomIntro.Phase) -> void: phases.append(phase))
	return phases


func _translations() -> Dictionary:
	return Loc.load_csv(Loc.CSV_PATH)


# --- Texts ---

func test_every_room_type_has_a_tour_in_both_languages_in_two_lines() -> void:
	var translations := _translations()
	var font := UiKit.get_font()
	var width := UiKit.px(FlintGuideView.BUBBLE_WIDTH)
	var size := UiKit.font_px(FlintGuideView.TEXT_SIZE)
	for genre: StringName in RoomGenre.TABLE:
		assert_true(RoomFlint.has_tour(genre), "%s: Flint explains it (the card is gone, D-211)" % genre)
	for genre: StringName in RoomFlint.TOURS:
		var count := RoomFlint.sentence_count(genre)
		assert_between(count, 2, 4, "%s: 2-4 sentences" % genre)
		var keys: Array[StringName] = []
		for i in count:
			keys.append(RoomFlint.text_key(genre, i))
		if RoomFlint.INTRO_GENRES.has(genre):
			keys.append(RoomFlint.short_key(genre))
			keys.append(RoomFlint.name_key(genre))
		for key in keys:
			for language: StringName in Loc.LANGUAGES:
				var text := String((translations[language] as Translation).get_message(key))
				assert_false(text.is_empty() or text == String(key), "%s has %s" % [key, language])
				var shown := text.replace("%d", "12").replace("%s", "Mia")
				assert_lte(FlintGuideRules.line_count(shown, font, size, width), FlintGuideRules.MAX_LINES,
						"%s (%s) fits two lines: %s" % [key, language, shown])
	for key: StringName in [&"FLINT_ROOM_EXPLAINING", &"FLINT_ROOM_AND"]:
		for language: StringName in Loc.LANGUAGES:
			assert_ne(String((translations[language] as Translation).get_message(key)), "", "%s %s" % [key, language])


func test_the_hunt_says_catch_the_crowned_one() -> void:
	Loc.apply(&"de")
	var steps := RoomFlint.steps(&"hunt")
	assert_eq(steps[0].get_text(), "Fang den Gekrönten! Er trägt jede Menge Beute.", "D-206")
	assert_eq(Loc.t(RoomFlint.short_key(&"hunt")), "Fang den Gekrönten! Er flieht – treib ihn in die Ecke.")
	assert_eq(RoomFlint.explaining_text("Mia", &"hunt"), "Flint erklärt Mia die Jagd …")


func test_steps_take_camera_goals_and_arguments_by_sentence() -> void:
	Loc.apply(&"de")
	var steps := RoomFlint.steps(&"escort", [Vector2(10, 20), Vector2.INF, Vector2(30, 40)], {1: [5]})
	assert_eq(steps.size(), 4)
	assert_eq(steps[0].resolve_focus(null), Vector2(10, 20))
	assert_false(steps[1].wants_camera(), "INF: Flint only talks")
	assert_eq(steps[2].resolve_focus(null), Vector2(30, 40))
	assert_false(steps[3].wants_camera(), "no goal given")
	assert_eq(steps[1].get_text(), "Er muss hier entlang zum Ausgang. Er hat 5 Leben.")
	var tour := RoomFlint.tour(&"escort", steps, true)
	assert_true(tour.is_valid(), str(tour.problems()))
	assert_eq(tour.id, &"flint_room_escort", "seen id per account")
	assert_true(tour.auto_advance, "co-op: goes on by itself")
	assert_eq(tour.max_pan_distance, RoomFlint.MAX_PAN_DISTANCE)
	assert_false(RoomFlint.tour(&"escort", steps).auto_advance, "single player: Weiter")
	var hint := RoomFlint.short_hint(&"escort")
	assert_eq(hint.style, FlintExplanation.Style.HINT)
	assert_false(hint.once, "the short version every time")
	assert_true(hint.is_valid())


func test_the_estimated_time_is_the_same_in_every_language() -> void:
	var steps := RoomFlint.steps(&"hunt")
	Loc.apply(&"de")
	var german := RoomFlint.estimated_duration(steps)
	Loc.apply(&"en")
	var english := RoomFlint.estimated_duration(steps)
	assert_eq(german, english, "host and clients hold the countdown alike")
	var texts := PackedStringArray()
	for step in steps:
		texts.append(step.get_text())
	assert_gte(english, FlintGuideRules.estimated_duration(texts) + RoomFlint.COOP_MARGIN, "never shorter than the shown language")


# --- Knowledge ---

func test_who_knows_which_room_type() -> void:
	var local := _player()
	local.remove_meta(RoomFlint.KNOWN_META)
	assert_false(RoomFlint.knows(local, &"hunt"), "own account: not seen")
	AccountSeen.mark_seen(RoomFlint.seen_id(&"hunt"))
	assert_true(RoomFlint.knows(local, &"hunt"), "own account: seen")
	assert_true(RoomFlint.account_known().has("hunt"), "for the lobby profile")
	var mate := _player([&"flame"], true)
	assert_true(RoomFlint.knows(mate, &"flame"))
	assert_false(RoomFlint.knows(mate, &"hunt"), "the session's state wins")
	var old_build := _player([], true)
	old_build.remove_meta(RoomFlint.KNOWN_META)
	assert_true(RoomFlint.knows(old_build, &"hunt"), "a mate without a state never holds the countdown")
	var players: Array[Player] = [local, mate, old_build]
	assert_eq(RoomFlint.learners(players, &"hunt"), [mate] as Array[Player])
	RoomFlint.mark_known(players, &"hunt")
	assert_true(RoomFlint.knows(mate, &"hunt"), "after an intro everybody knows it")
	assert_eq(RoomFlint.sanitize_known(["hunt", "hunt", 3, "nonsense", &"flame"]), PackedStringArray(["hunt", "flame"]))
	assert_eq(RoomFlint.sanitize_known("hunt"), PackedStringArray())


func test_the_lobby_profile_carries_the_known_room_types() -> void:
	AccountSeen.mark_seen(RoomFlint.seen_id(&"relic"))
	var profile := NetPlayers.with_seen_rooms({"name": "Mia"})
	assert_true((profile[RoomFlint.PROFILE_KEY] as Array).has("relic"))
	assert_eq(profile["name"], "Mia", "the rest stays")
	assert_eq(NetPlayers.profile_seen_rooms({RoomFlint.PROFILE_KEY: ["relic", "x"]}), ["relic"], "cleaned")
	assert_null(NetPlayers.profile_seen_rooms({}), "older build: no state")


func test_names_of_the_learners() -> void:
	Loc.apply(&"de")
	var mia := _player([], true, "Mia")
	var tom := _player([], true, "Tom")
	var ben := _player([], true, "Ben")
	assert_eq(RoomFlint.names_text([mia] as Array[Player]), "Mia")
	assert_eq(RoomFlint.names_text([mia, tom] as Array[Player]), "Mia und Tom")
	assert_eq(RoomFlint.names_text([mia, tom, ben] as Array[Player]), "Mia, Tom und Ben")


# --- Single player ---

func test_first_time_flint_explains_between_door_and_banner() -> void:
	var room := _room()
	var player := _player()
	var mode := FakeMode.new()
	mode.name = "CombatVariant"
	mode.points = [Vector2(700, 300), Vector2(400, 600)]
	room.add_child(mode)
	var calls: Array = []
	var intro := RoomIntro.start(room, _goal(room, &"hunt"), Vector2(900, 300))
	var phases := _phases(intro)
	RoomIntro.after_intro(room, func() -> void: calls.append(1))
	assert_true(intro.has_flint(), "first time: Flint")
	assert_true(intro.full)
	assert_eq(intro.learners, [player] as Array[Player])
	assert_eq(intro.flint_time, 0.0, "single player: as long as he talks")
	var guide := FlintGuide.of(player)
	assert_eq(guide.current, intro.flint_tour, "the tour starts with the door")
	assert_true(guide.current.uses_camera(), "camera goals from the mode")
	assert_eq(guide.current.steps[0].resolve_focus(null), Vector2(700, 300))
	assert_true(player.is_protected(), "the learner is protected (FlintGuide)")
	assert_true(intro.get_locked_players().is_empty(), "no lock of the intro's own")
	await wait_seconds(RoomIntro.DOOR_TIME + 0.1)
	assert_eq(intro.phase, RoomIntro.Phase.FLINT)
	await wait_seconds(2.0)
	assert_eq(intro.phase, RoomIntro.Phase.FLINT, "the countdown waits for Flint")
	assert_true(calls.is_empty(), "the fight is held")
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	intro._unhandled_input(event)
	assert_false(intro.is_released(), "E is Flint's Weiter, it does not skip the intro")
	guide.skip()
	await wait_seconds(FlintGuideRules.FLY_BACK_TIME + 0.2)
	assert_eq(intro.phase, RoomIntro.Phase.BANNER, "Flint is done: banner")
	assert_true(_seen.has(&"flint_room_hunt"), "seen for the account")
	assert_true(RoomFlint.knows(player, &"hunt"))
	await wait_seconds(RoomIntro.BANNER_LEAD + RoomIntro.COUNTDOWN_FROM * RoomIntro.COUNTDOWN_STEP + 0.3)
	assert_eq(calls, [1], "then 3-2-1 and the fight")
	assert_eq(phases, [RoomIntro.Phase.FLINT, RoomIntro.Phase.BANNER, RoomIntro.Phase.COUNTDOWN, RoomIntro.Phase.DONE])
	assert_false(player.is_protected())


func test_a_known_room_type_gets_the_short_intro_without_flint() -> void:
	var room := _room()
	var player := _player([&"flame"])
	var intro := RoomIntro.start(room, _goal(room, &"flame"), Vector2(900, 300))
	var phases := _phases(intro)
	assert_false(intro.has_flint())
	assert_false(intro.full, "short")
	assert_false(FlintGuide.of(player).is_running())
	await wait_seconds(RoomIntro.get_total_time(false) + 0.3)
	assert_true(not is_instance_valid(intro) or intro.is_queued_for_deletion(), "over in about 2 s")
	assert_false(phases.has(RoomIntro.Phase.FLINT))
	assert_false(phases.has(RoomIntro.Phase.PAN), "no camera swing either")


func test_skip_ends_the_tour_too() -> void:
	var room := _room()
	var player := _player()
	var intro := RoomIntro.start(room, _goal(room, &"relic"), Vector2(900, 300))
	var guide := FlintGuide.of(player)
	assert_true(guide.is_running())
	intro.skip()
	assert_true(intro.is_released(), "tools and the smoke test skip like before")
	assert_eq(guide.phase, FlintGuide.Phase.FLY_BACK, "Flint flies back")
	assert_true(_seen.has(&"flint_room_relic"))


func test_without_a_mode_flint_looks_at_the_focus() -> void:
	var room := _room()
	var player := _player()
	RoomIntro.start(room, _goal(room, &"souls"), Vector2(123, 456))
	var tour := FlintGuide.of(player).current
	assert_eq(tour.steps[0].resolve_focus(null), Vector2(123, 456))
	assert_false(tour.steps[1].wants_camera())


func test_scripts_keep_the_old_intro_unless_switched_on() -> void:
	RoomFlint.explain_in_scripts = false
	var room := _room()
	var player := _player()
	var intro := RoomIntro.start(room, _goal(room, &"hunt"), Vector2(900, 300))
	assert_false(intro.has_flint(), "bots never wait for a Weiter")
	assert_true(intro.full, "first time per save: the old swing")
	assert_false(FlintGuide.of(player).is_running())


# --- Co-op ---

func test_coop_everybody_gets_the_tour_while_a_mate_learns() -> void:
	_coop()
	var room := _room()
	var host := _player([&"hunt"], false, "Ben")
	var mate := _player([], true, "Mia")
	var intro := RoomIntro.start(room, _goal(room, &"hunt"), Vector2(900, 300))
	assert_eq(intro.learners, [mate] as Array[Player])
	assert_true(intro.full)
	var expected := RoomFlint.estimated_duration(RoomFlint.steps(&"hunt", [Vector2(900, 300)]))
	assert_almost_eq(intro.flint_time, expected, 0.001, "the countdown grows by Flint's time")
	var guide := FlintGuide.of(host)
	assert_eq(guide.current, intro.flint_tour, "the host who knows it sees the whole tour too")
	assert_true(guide.current.auto_advance, "co-op: goes on by itself")
	assert_true(host.is_protected(), "nobody plays on while a mate listens")
	assert_eq(intro.get_flint_guides(), [guide] as Array[FlintGuide])
	await wait_seconds(RoomIntro.DOOR_TIME + 0.1)
	assert_eq(intro.phase, RoomIntro.Phase.FLINT)
	await wait_seconds(intro.flint_time - 0.4)
	assert_eq(intro.phase, RoomIntro.Phase.FLINT, "still waiting for the mate")
	await wait_seconds(0.5)
	assert_eq(intro.phase, RoomIntro.Phase.BANNER)
	assert_true(RoomFlint.knows(mate, &"hunt"), "next time nobody waits")


func test_coop_client_learns_with_the_same_time() -> void:
	_coop()
	var room := _room()
	var me := _player([], false, "Mia")
	var host := _player([&"hunt"], true, "Ben")
	var intro := RoomIntro.start(room, _goal(room, &"hunt"), Vector2(900, 300))
	assert_eq(intro.learners, [me] as Array[Player])
	var expected := RoomFlint.estimated_duration(RoomFlint.steps(&"hunt", [Vector2(900, 300)]))
	assert_almost_eq(intro.flint_time, expected, 0.001, "the same number as on the host")
	var guide := FlintGuide.of(me)
	assert_eq(guide.current, intro.flint_tour)
	assert_true(guide.current.auto_advance, "goes on by itself: the host's countdown waits")
	assert_true(me.is_protected(), "protected (the host learns it through submit_guide_protected)")
	assert_false(RoomFlint.knows(host, &"flame"))


func test_online_the_tour_goes_to_the_whole_group_through_net_guide() -> void:
	_coop()
	var net_guide := NetGuide.create(null)
	net_guide.is_host = true
	add_child_autofree(net_guide)
	var room := _room()
	var host := _player([&"hunt"], false, "Ben")
	var mate := _player([], true, "Mia")
	net_guide.local_player = func() -> Player: return host
	net_guide.all_players = func() -> Array[Player]: return [host, mate] as Array[Player]
	_seen[&"flint_room_hunt"] = true
	var intro := RoomIntro.start(room, _goal(room, &"hunt"), Vector2(900, 300))
	assert_true(intro.has_flint(), "Mia learns the hunt")
	assert_eq(net_guide.get_active(), &"", "the host knows it: his machine does not ask")
	assert_eq(RoomIntro.build_group_tour(&"flint_room_hunt"), intro.flint_tour, "every machine builds the same tour")
	net_guide.host_need(&"flint_room_hunt", 2)
	assert_eq(net_guide.get_active(), &"flint_room_hunt", "Mia's request starts it for everybody")
	assert_true(host.is_protected(), "the host listens too, protected")
	assert_true(mate.is_protected(), "and so does Mia's copy")
	await wait_seconds(RoomIntro.DOOR_TIME + 0.1)
	assert_eq(intro.phase, RoomIntro.Phase.FLINT)
	await wait_seconds(RoomIntro.GROUP_START_WAIT + 0.2)
	assert_eq(intro.phase, RoomIntro.Phase.FLINT, "the countdown waits for the group hint")
	net_guide.host_done(&"flint_room_hunt", 2)
	await wait_physics_frames(3)
	assert_eq(intro.phase, RoomIntro.Phase.BANNER, "over for everybody: banner")
	await wait_seconds(FlintGuideRules.FLY_BACK_TIME + 0.3)
	assert_false(host.is_protected(), "free again once Flint flew back")


func test_coop_intro_waits_until_everybody_is_in_the_room() -> void:
	_coop()
	var room := ArenaRoom.new()
	add_child_autofree(room)
	var host := _player([&"hunt"], false, "Ben")
	var mate := _player([], true, "Mia", Vector2(1400, 300))
	var calls: Array = []
	var intro := RoomIntro.start(room, _goal(room, &"hunt"), Vector2(500, 300))
	RoomIntro.after_intro(room, func() -> void: calls.append(1))
	assert_true(intro.gathering, "Mia is still outside")
	assert_false(intro.has_flint(), "no tour yet")
	assert_false(FlintGuide.of(host).is_running(), "nothing is explained to the host alone")
	await wait_seconds(RoomIntro.DOOR_TIME + 0.5)
	assert_eq(intro.phase, RoomIntro.Phase.DOOR, "the intro waits behind the door")
	assert_true(calls.is_empty(), "the fight is held")
	mate.global_position = Vector2(300, 300)
	await wait_physics_frames(3)
	assert_false(intro.gathering, "everybody is in")
	assert_true(intro.has_flint(), "now Flint explains")
	assert_eq(FlintGuide.of(host).current, intro.flint_tour, "to both at the same time")
	await wait_seconds(RoomIntro.DOOR_TIME + 0.1)
	assert_eq(intro.phase, RoomIntro.Phase.FLINT)


func test_coop_intro_stops_waiting_at_the_limit() -> void:
	_coop()
	var room := ArenaRoom.new()
	add_child_autofree(room)
	_player([&"hunt"], false, "Ben")
	_player([&"hunt"], true, "Mia", Vector2(1400, 300))
	var intro := RoomIntro.start(room, _goal(room, &"hunt"), Vector2(500, 300))
	assert_true(intro.gathering)
	assert_gte(RoomIntro.GATHER_MAX_WAIT, CoopRules.WAIT_COUNTDOWN, "longer than the room's wait: the stragglers come")
	intro._phase_time = RoomIntro.GATHER_MAX_WAIT
	await wait_physics_frames(2)
	assert_false(intro.gathering, "the limit ends the wait")


func test_coop_when_everybody_knows_it_is_short() -> void:
	_coop()
	var room := _room()
	_player([&"rifts"], false)
	_player([&"rifts"], true)
	var intro := RoomIntro.start(room, _goal(room, &"rifts"), Vector2(900, 300))
	assert_false(intro.has_flint())
	assert_false(intro.full)


func test_coop_fight_started_by_the_host_leaves_the_tour_running() -> void:
	_coop()
	var room := _room()
	var me := _player([], false, "Mia")
	_player([], true, "Ben")
	var intro := RoomIntro.start(room, _goal(room, &"collapse"), Vector2(900, 300))
	var ends: Array = []
	intro.finished.connect(func(skipped: bool) -> void: ends.append([skipped, intro.fight_was_running]))
	await wait_seconds(RoomIntro.DOOR_TIME + 0.1)
	room.started = true
	await wait_physics_frames(3)
	assert_eq(ends, [[true, true]], "the client's intro ends with the host's fight")
	assert_true(FlintGuide.of(me).is_running(), "he goes on explaining, the learner stays protected")


# --- Modes give their camera goals ---

func _hall(room_index := 20) -> RoomController:
	var room := HALL.instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 41
	room.setup(room_index, RoomSequence.RoomType.COMBAT, -1, false, context)
	var spawner := room.get_node("EnemySpawner") as EnemySpawner
	spawner.biomes = [] as Array[BiomeData]
	spawner.extra_types = [] as Array[EnemyData]
	spawner.enemy_types = [SKELETON] as Array[EnemyData]
	spawner.spawn_weights = [1.0] as Array[float]
	add_child_autofree(room)
	return room


func test_every_mode_tour_shows_its_goal_first() -> void:
	RunManager.start_run()
	for id in MODES:
		var room := _hall()
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		if RoomVariants.attach(room, VariantTable.pick_for(id), rng) != id:
			pending("%s cannot host in the plain hall" % id)
			continue
		var mode := CombatVariant.of(room)
		assert_true(mode.has_method(&"get_flint_steps"), "%s gives camera goals" % id)
		if mode.has_method(&"begin_intro"):
			mode.call(&"begin_intro")
		elif mode is RoomMode:
			(mode as RoomMode).start_intro()
		var steps: Array[FlintGuideStep] = []
		steps.assign(mode.call(&"get_flint_steps"))
		assert_eq(steps.size(), RoomFlint.sentence_count(id), "%s: every sentence" % id)
		assert_true(steps[0].wants_camera(), "%s: the camera shows the goal first" % id)
		var goal := steps[0].resolve_focus(null)
		assert_true(goal.is_finite() and room.get_arena().grow(64.0).has_point(goal), "%s: goal %s in the room" % [id, goal])
		for step in steps:
			assert_false(step.get_text().contains("%"), "%s: %s formatted" % [id, step.text_key])
	RunManager.end_run(RunManager.EndReason.ABORT)


func test_the_arena_tour_names_its_waves() -> void:
	Loc.apply(&"de")
	RunManager.start_run()
	var room := _hall(8)
	var arena := ArenaObjective.attach_to(room)
	var steps := arena.get_flint_steps()
	assert_eq(steps.size(), RoomFlint.sentence_count(&"arena"))
	assert_eq(steps[0].get_text(), "Aus diesen Toren kommen Monster – in %d Wellen." % arena.get_total_waves())
	RunManager.end_run(RunManager.EndReason.ABORT)


# --- Rooms without an intro ---

func test_special_rooms_get_flint_from_the_genre_banner() -> void:
	var player := _player()
	var ui: DungeonUI = add_child_autofree(DungeonUI.new())
	ui.auto_enemy_hints = false
	ui.show_controls_hint = false
	ui.show_genre(&"fountain")
	var tour := FlintGuide.of(player).current
	assert_eq(tour.id, &"flint_room_fountain")
	assert_null(ui._hint_card, "no card (D-211)")
	assert_false(RoomFlint.explain_room(player, &"fountain"), "queued once")
	_seen[&"flint_room_shop"] = true
	RoomFlint.set_known(player, ["shop"])
	assert_false(RoomFlint.explain_room(player, &"shop"), "known: nothing")


func test_explain_room_leaves_rooms_with_an_intro_to_it() -> void:
	var room := _room()
	var player := _player([&"hunt"])
	RoomIntro.start(room, _goal(room, &"hunt"), Vector2(900, 300))
	RoomFlint.set_known(player, [])
	assert_false(RoomFlint.explain_room(player, &"hunt", room), "the RoomIntro explains its room")
	assert_false(RoomFlint.explain_room(_player([], true), &"shop"), "never for a remote player")

extends GutTest
## "Flint erklärt" (WK8, KONZEPT §7.2): the data form (FlintExplanation, FlintGuideStep, the .tres in
## companions/guide/explanations/), the pure rules (FlintGuideRules) and the runner per player
## (FlintGuide): flight out and back, steps letter by letter, "Weiter" and "Überspringen", the
## player's own camera on a tour, protection only for the explained player (co-op, D-085/D-123/D-184),
## hints without lock, queue and seen flags. Seen flags are swapped for a dictionary; the AccountSeen
## test uses a test folder only (never the real save, AGENTS.md rule 4).

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const DT := 1.0 / 60.0
const ROOT := "user://test_flint_guide"

var _seen: Dictionary = {}
var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	SaveManager.save_path = ROOT + "/save.cfg"


func before_each() -> void:
	_seen.clear()


func after_all() -> void:
	_wipe()
	AccountProgress.path_override = ""
	AccountProgress.reset()
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()


func _wipe() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	for dir_path in [root.path_join("saves"), root]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			DirAccess.remove_absolute(dir_path.path_join(file))
	DirAccess.make_dir_recursive_absolute(root.path_join("saves"))


func _player(at := Vector2(400, 300)) -> Player:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.global_position = at
	return player


## A guide driven by hand, without the corner view, with seen flags in _seen.
func _guide(player: Player) -> FlintGuide:
	var guide := FlintGuide.for_player(player)
	guide.set_process(false)
	guide.shows_view = false
	guide.has_seen = func(id: StringName) -> bool: return _seen.has(id)
	guide.mark_seen = func(id: StringName) -> void: _seen[id] = true
	return guide


func _tour(id := &"flint_test_tour", count := 2) -> FlintExplanation:
	var steps: Array[FlintGuideStep] = []
	for i in count:
		steps.append(FlintGuideStep.say(&"FLINT_FIRST_TALENT_POINT", FlintGuideStep.Mood.TALK))
	return FlintExplanation.tour(id, steps)


func _hint(id := &"flint_test_hint") -> FlintExplanation:
	return FlintExplanation.hint(id, [FlintGuideStep.say(&"FLINT_FIRST_SPELL", FlintGuideStep.Mood.HAPPY)] as Array[FlintGuideStep])


func _run(guide: FlintGuide, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		guide.advance(DT)
		left -= DT


## Flies out and stops at the first sentence.
func _to_talk(guide: FlintGuide) -> void:
	_run(guide, FlintGuideRules.GROW_TIME + FlintGuideRules.FLY_OUT_TIME + DT)
	assert_eq(guide.phase, FlintGuide.Phase.TALK, "Flint arrived in the corner")


## Types the current sentence fully and waits past the grace time.
func _finish_typing(guide: FlintGuide) -> void:
	_run(guide, FlintGuideRules.typing_time(guide.get_text()) + FlintGuideRules.PRESS_GRACE + DT)


# --- Data and rules ---

func test_an_explanation_needs_a_flint_id_and_steps_with_keys() -> void:
	assert_true(_tour().is_valid())
	var wrong_id := FlintExplanation.tour(&"village_forge", [FlintGuideStep.say(&"FLINT_FIRST_SPELL")] as Array[FlintGuideStep])
	assert_false(wrong_id.is_valid(), "ids start with flint_ (seen flags of old worlds)")
	assert_false(FlintExplanation.tour(&"flint_empty", [] as Array[FlintGuideStep]).is_valid(), "no steps")
	assert_false(FlintExplanation.hint(&"flint_no_key", [FlintGuideStep.new()] as Array[FlintGuideStep]).is_valid(), "a step without key")


func test_should_explain_respects_seen_once_and_force() -> void:
	var tour := _tour()
	assert_true(FlintGuideRules.should_explain(tour, false))
	assert_false(FlintGuideRules.should_explain(tour, true), "seen once: not again")
	assert_true(FlintGuideRules.should_explain(tour, true, true), "force shows it again")
	tour.once = false
	assert_true(FlintGuideRules.should_explain(tour, true), "repeating tips ignore the seen flag")
	assert_false(FlintGuideRules.should_explain(null, false))


func test_a_press_reveals_the_sentence_then_goes_on() -> void:
	assert_eq(FlintGuideRules.press(3, 20, 0.1), FlintGuideRules.Press.IGNORED, "grace time after a sentence appears")
	assert_eq(FlintGuideRules.press(3, 20, 0.5), FlintGuideRules.Press.REVEAL_ALL)
	assert_eq(FlintGuideRules.press(20, 20, 0.5), FlintGuideRules.Press.NEXT)


func test_reading_time_grows_with_the_text_but_has_a_ceiling() -> void:
	assert_gt(FlintGuideRules.read_time("Ein langer Satz mit vielen Wörtern."), FlintGuideRules.read_time("Hallo!"))
	assert_lte(FlintGuideRules.read_time("x".repeat(500)), FlintGuideRules.READ_MAX)
	var texts := PackedStringArray(["Hallo!", "Noch ein Satz."])
	assert_gt(FlintGuideRules.estimated_duration(texts), FlintGuideRules.typing_time(texts[0]) + FlintGuideRules.typing_time(texts[1]))


func test_flight_out_first_grows_then_flies() -> void:
	assert_eq(FlintGuideRules.fly_out_parts(0.0), Vector2.ZERO)
	var grow_share := FlintGuideRules.GROW_TIME / (FlintGuideRules.GROW_TIME + FlintGuideRules.FLY_OUT_TIME)
	assert_eq(FlintGuideRules.fly_out_parts(grow_share * 0.5), Vector2(0.5, 0.0))
	assert_eq(FlintGuideRules.fly_out_parts(1.0), Vector2.ONE)


func test_every_mood_has_a_portrait_strip() -> void:
	for mood: int in FlintGuideStep.Mood.values():
		assert_true(FlintPortraitArt.ANIMATIONS.has(FlintGuideRules.portrait_animation(mood)), "mood %d" % mood)


func test_shipped_explanations_are_valid_and_translated_in_two_lines() -> void:
	var names := FlintExplanations.all_names()
	assert_true(names.has(FlintExplanations.ENTRANCE_DANGER))
	for first in FlintExplanations.FIRST_TIMES:
		assert_true(names.has(first), "%s ships" % first)
	var translations := Loc.load_csv(Loc.CSV_PATH)
	var font := UiKit.get_font()
	var width := UiKit.px(FlintGuideView.BUBBLE_WIDTH)
	var size := UiKit.font_px(FlintGuideView.TEXT_SIZE)
	for explanation_name in names:
		var explanation := FlintExplanations.named(explanation_name)
		assert_not_null(explanation, String(explanation_name))
		assert_true(explanation.is_valid(), "%s: %s" % [explanation_name, explanation.problems()])
		assert_eq(String(explanation.id), "flint_" + String(explanation_name), "file name = id without prefix")
		for step in explanation.steps:
			for language: StringName in Loc.LANGUAGES:
				var translation: Translation = translations[language]
				var text := String(translation.get_message(step.text_key))
				assert_false(text.is_empty() or text == String(step.text_key), "%s has %s" % [step.text_key, language])
				assert_lte(FlintGuideRules.line_count(text, font, size, width), FlintGuideRules.MAX_LINES,
						"%s (%s) fits two lines: %s" % [step.text_key, language, text])


func test_first_times_are_hints_and_the_entrance_is_a_camera_tour() -> void:
	for first in FlintExplanations.FIRST_TIMES:
		var explanation := FlintExplanations.named(first)
		assert_eq(explanation.style, FlintExplanation.Style.HINT, String(first))
		assert_false(explanation.uses_camera(), "%s: no camera ride" % first)
		assert_false(explanation.locks_player(), "%s: no lock" % first)
	var entrance := FlintExplanations.named(FlintExplanations.ENTRANCE_DANGER)
	assert_eq(entrance.style, FlintExplanation.Style.TOUR)
	assert_true(entrance.uses_camera())
	assert_eq(entrance.steps[0].focus_path, FlintExplanations.ENTRANCE_NODE)


func test_a_copy_keeps_the_loaded_resource_clean() -> void:
	var loaded := FlintExplanations.named(FlintExplanations.ENTRANCE_DANGER)
	var node := add_child_autofree(Node2D.new()) as Node2D
	var copy := loaded.copy()
	copy.steps[0].focus_node = node
	assert_null(loaded.steps[0].focus_node, "the shared resource holds no node of a world")
	assert_eq(copy.steps.size(), loaded.steps.size())


func test_a_step_resolves_node_path_and_point_goals() -> void:
	var world := add_child_autofree(Node2D.new()) as Node2D
	var buildings := Node2D.new()
	buildings.name = "Buildings"
	world.add_child(buildings)
	var forge := Node2D.new()
	forge.name = "Forge"
	forge.position = Vector2(500, 120)
	buildings.add_child(forge)
	assert_eq(FlintGuideStep.say(&"K").at_path(^"Buildings/Forge", Vector2(0, 10)).resolve_focus(world), Vector2(500, 130))
	assert_eq(FlintGuideStep.say(&"K").at_node(forge).resolve_focus(world), Vector2(500, 120))
	assert_eq(FlintGuideStep.say(&"K").at_point(Vector2(7, 8)).resolve_focus(world), Vector2(7, 8))
	assert_eq(FlintGuideStep.say(&"K").resolve_focus(world), Vector2.INF, "no goal")
	assert_eq(FlintGuideStep.say(&"K").at_path(^"Buildings/Missing").resolve_focus(world), Vector2.INF, "a missing node is no goal")


# --- The runner ---

func test_a_tour_flies_out_talks_and_flies_back() -> void:
	var player := _player()
	var guide := _guide(player)
	var phases: Array = []
	guide.phase_changed.connect(func(phase: FlintGuide.Phase) -> void: phases.append(phase))
	assert_true(guide.queue(_tour(&"flint_test_tour", 1)))
	assert_eq(guide.phase, FlintGuide.Phase.FLY_OUT)
	_to_talk(guide)
	assert_eq(guide.get_text(), Loc.t(&"FLINT_FIRST_TALENT_POINT"))
	assert_lt(guide.get_revealed(), guide.get_text().length(), "letter by letter")
	_finish_typing(guide)
	assert_eq(guide.get_revealed(), guide.get_text().length())
	assert_true(guide.press(), "Weiter after the last sentence ends the tour")
	assert_eq(guide.phase, FlintGuide.Phase.FLY_BACK)
	assert_true(_seen.has(&"flint_test_tour"), "marked seen when the talking ends")
	_run(guide, FlintGuideRules.FLY_BACK_TIME + DT)
	assert_eq(guide.phase, FlintGuide.Phase.IDLE)
	assert_eq(phases, [FlintGuide.Phase.FLY_OUT, FlintGuide.Phase.TALK, FlintGuide.Phase.FLY_BACK, FlintGuide.Phase.IDLE])


func test_a_tour_protects_only_the_explained_player() -> void:
	var player := _player()
	var mate := _player(Vector2(700, 300))
	var guide := _guide(player)
	var protection: Array = []
	guide.protection_changed.connect(func(value: bool) -> void: protection.append(value))
	guide.queue(_tour())
	assert_true(player.is_protected(), "no damage, enemies ignore him (like a menu, D-123)")
	assert_true(player.is_input_locked(), "the explained player stands still")
	assert_false(mate.is_protected(), "the mate plays on")
	assert_false(mate.is_input_locked())
	assert_false(get_tree().paused, "nothing pauses (D-085)")
	guide.skip()
	_run(guide, FlintGuideRules.FLY_BACK_TIME + DT)
	assert_false(player.is_protected())
	assert_false(player.is_input_locked())
	assert_eq(protection, [true, false], "the network hook hears both changes")


func test_a_press_while_typing_shows_the_whole_sentence_first() -> void:
	var guide := _guide(_player())
	guide.queue(_tour())
	_to_talk(guide)
	assert_false(guide.press(), "grace time: a click meant for the game does not skip")
	_run(guide, FlintGuideRules.PRESS_GRACE + DT)
	assert_true(guide.press())
	assert_eq(guide.get_revealed(), guide.get_text().length(), "whole sentence at once")
	assert_eq(guide.step_index, 0, "still the first sentence")
	assert_false(guide.press(), "a double tap (touch + emulated click) counts once")
	_run(guide, FlintGuideRules.PRESS_GRACE + DT)
	assert_true(guide.press())
	assert_eq(guide.step_index, 1, "next sentence")


func test_skip_ends_at_any_time_and_counts_as_seen() -> void:
	var guide := _guide(_player())
	var ended: Array = []
	guide.finished.connect(func(explanation: FlintExplanation, skipped: bool) -> void: ended.append([explanation.id, skipped]))
	guide.queue(_tour())
	_run(guide, 0.1)
	assert_true(guide.skip(), "even while Flint is still flying out")
	assert_eq(guide.phase, FlintGuide.Phase.FLY_BACK)
	_run(guide, FlintGuideRules.FLY_BACK_TIME + DT)
	assert_eq(ended, [[&"flint_test_tour", true]])
	assert_true(_seen.has(&"flint_test_tour"))
	assert_false(guide.skip(), "nothing left to skip")


func test_explanations_queue_and_seen_ones_stay_away() -> void:
	var guide := _guide(_player())
	assert_true(guide.queue(_tour(&"flint_first")))
	assert_true(guide.queue(_hint(&"flint_second")))
	assert_false(guide.queue(_hint(&"flint_second")), "already waiting")
	assert_eq(guide.get_queue_size(), 1)
	guide.skip()
	_run(guide, FlintGuideRules.FLY_BACK_TIME + DT)
	assert_eq(guide.current.id, &"flint_second", "the next one starts after the flight back")
	assert_false(guide.queue(_tour(&"flint_first")), "seen")
	assert_true(guide.queue(_tour(&"flint_first"), true), "force shows it again")


func test_a_hint_neither_locks_nor_waits() -> void:
	var player := _player()
	var guide := _guide(player)
	guide.queue(_hint())
	assert_false(player.is_protected(), "a hint never stops the game")
	assert_false(player.is_input_locked())
	assert_null(guide.get_camera(), "no camera ride")
	_to_talk(guide)
	var key := InputEventAction.new()
	key.action = &"attack"
	key.pressed = true
	assert_false(guide.handle_input(key), "a hint takes no game input (fight on)")
	_run(guide, FlintGuideRules.typing_time(guide.get_text()) + FlintGuideRules.read_time(guide.get_text()) + 0.1)
	assert_eq(guide.phase, FlintGuide.Phase.FLY_BACK, "goes on by itself after the reading time")
	assert_false(guide.was_skipped)
	assert_true(_seen.has(&"flint_test_hint"))


func test_a_tour_flies_only_the_explained_players_camera_and_brings_it_home() -> void:
	var player := _player(Vector2(400, 300))
	var mate := _player(Vector2(900, 300))
	var camera := player.get_node(^"Camera2D") as Camera2D
	var mate_camera := mate.get_node(^"Camera2D") as Camera2D
	var goal := Vector2(1000, 300)
	var near := Vector2(450, 300)
	var guide := _guide(player)
	var explanation := FlintExplanation.tour(&"flint_camera", [
		FlintGuideStep.say(&"FLINT_ENTRANCE_1", FlintGuideStep.Mood.POINT).at_point(goal),
		FlintGuideStep.say(&"FLINT_ENTRANCE_2"),
		FlintGuideStep.say(&"FLINT_ENTRANCE_3").at_point(near),
	] as Array[FlintGuideStep])
	explanation.max_pan_distance = 260.0
	guide.queue(explanation)
	assert_not_null(guide.get_camera())
	_to_talk(guide)
	assert_eq(guide.get_camera().get_target(), Vector2(260, 0), "towards the goal, at most max_pan_distance")
	await wait_seconds(FlintGuideRules.CAMERA_PAN_TIME + 0.15)
	assert_almost_eq(camera.position.x, 260.0, 1.0, "the explained player's own camera flew")
	assert_eq(mate_camera.position, Vector2.ZERO, "nobody else's camera moves (D-184)")
	_finish_typing(guide)
	guide.press()
	assert_false(guide.get_camera().is_away(), "a step without goal brings the camera home")
	_finish_typing(guide)
	guide.press()
	assert_eq(guide.get_camera().get_target(), Vector2(50, 0))
	_finish_typing(guide)
	guide.press()
	_run(guide, FlintGuideRules.FLY_BACK_TIME + DT)
	assert_eq(guide.phase, FlintGuide.Phase.IDLE)
	await wait_seconds(FlintGuideRules.CAMERA_RETURN_TIME + 0.15)
	assert_almost_eq(camera.position.x, 0.0, 0.5, "home at the end")


func test_a_remote_player_is_not_explained_here() -> void:
	var player := _player()
	player.is_local = false
	assert_false(FlintGuide.explain(player, _tour()), "his own machine explains it")
	assert_null(FlintGuide.of(player))


func test_flint_flies_into_the_corner_but_the_light_stays_with_the_player() -> void:
	var player := _player()
	var flint := FlintCompanion.attach_to(player)
	flint.set_process(false)
	flint._process(DT)
	var light := flint.get_light_center()
	var guide := _guide(player)
	guide.queue(_tour())
	_run(guide, FlintGuideRules.GROW_TIME * 0.9)
	flint._process(DT)
	assert_true(flint.is_on_excursion())
	assert_gt(flint.get_sprite().scale.x, SpriteStrip.PIXEL_SCALE, "Flint grows beside the player")
	_to_talk(guide)
	flint._process(DT)
	assert_eq(flint.get_sprite().modulate.a, 0.0, "his picture is in the corner now")
	assert_almost_eq(flint.get_light_center(), light, Vector2.ONE, "his light stays with the player (LightQuery)")
	guide.skip()
	_run(guide, FlintGuideRules.FLY_BACK_TIME + DT)
	flint._process(DT)
	assert_false(flint.is_on_excursion(), "back at his spot")
	assert_eq(flint.get_sprite().scale.x, SpriteStrip.PIXEL_SCALE, "small again")


func test_freeing_the_player_mid_tour_leaves_nothing_behind() -> void:
	var player := _player()
	var guide := _guide(player)
	guide.queue(_tour())
	_to_talk(guide)
	guide.cancel_all()
	assert_eq(guide.phase, FlintGuide.Phase.IDLE)
	assert_false(player.is_protected())
	assert_false(_seen.has(&"flint_test_tour"), "an interrupted tour shows again")


func test_babble_speaks_syllables_while_typing() -> void:
	var guide := _guide(_player())
	var syllables: Array = []
	guide.syllable_spoken.connect(func(_index: int, syllable: String) -> void: syllables.append(syllable))
	guide.queue(_hint())
	_to_talk(guide)
	_finish_typing(guide)
	assert_gt(syllables.size(), 3)
	assert_eq(FlintBabble.sound_for("Zau"), FlintBabble.sound_for("Zau"), "the same syllable sounds the same")
	assert_true(ResourceLoader.exists(Sfx.SFX_DIR + String(FlintBabble.sound_for("Zau")) + ".wav"), "an existing sound")


# --- Hooks and the account ---

func test_the_entrance_demo_shows_the_entrance_once() -> void:
	var player := _player()
	var entrance := add_child_autofree(Node2D.new()) as Node2D
	entrance.global_position = Vector2(400, 100)
	var guide := _guide(player)
	assert_true(FlintExplanations.entrance_danger(player, entrance))
	assert_eq(guide.current.id, &"flint_entrance_danger")
	_to_talk(guide)
	assert_eq(guide.get_camera().get_target(), Vector2(0, -200), "the camera shows the entrance")
	guide.skip()
	_run(guide, FlintGuideRules.FLY_BACK_TIME + DT)
	# D-220: the intro comes once; danger and rank only once the danger level rose above 0.
	assert_eq(FlintExplanations.entrance_choice(true, 0), &"", "intro seen, danger 0: nothing")
	assert_eq(FlintExplanations.entrance_choice(true, 2), FlintExplanations.ENTRANCE_DANGER_FULL,
			"intro seen, danger rose: the full explanation")
	assert_eq(FlintExplanations.entrance_choice(false, 2), FlintExplanations.ENTRANCE_DANGER, "the intro first")


func test_village_arrival_names_the_due_first_times() -> void:
	assert_eq(FlintExplanations.village_firsts(0, 0), [] as Array[StringName], "a new player: nothing yet")
	assert_eq(FlintExplanations.village_firsts(1, 0), [FlintExplanations.FIRST_RANK_UP] as Array[StringName])
	assert_eq(FlintExplanations.village_firsts(0, 2), [FlintExplanations.FIRST_TALENT_POINT] as Array[StringName])
	assert_eq(FlintExplanations.village_firsts(3, 1).size(), 2, "both, one after the other")


func test_seen_flags_go_to_the_account() -> void:
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()
	AccountProgress.path_override = ""
	AccountProgress.reset()
	var player := _player()
	var guide := FlintGuide.for_player(player)
	guide.set_process(false)
	guide.shows_view = false
	assert_false(AccountSeen.has_seen(&"flint_first_rank_up"))
	assert_true(FlintExplanations.rank_up(player))
	guide.skip()
	assert_true(AccountSeen.has_seen(&"flint_first_rank_up"), "per account, not per world")
	_run(guide, FlintGuideRules.FLY_BACK_TIME + DT)
	assert_false(FlintExplanations.rank_up(player), "seen")


# --- Queue with priority (FS5, finding P1-1 of the newcomer run) ---

func _prioritized(id: StringName, priority: FlintExplanation.Priority, tour := false) -> FlintExplanation:
	var explanation := _tour(id, 1) if tour else _hint(id)
	explanation.priority = priority
	return explanation


func test_rules_order_the_queue_by_priority() -> void:
	var general := FlintExplanation.Priority.GENERAL
	var place := FlintExplanation.Priority.PLACE
	var urgent := FlintExplanation.Priority.URGENT
	assert_eq(FlintGuideRules.queue_index([] as Array[int], general), 0)
	assert_eq(FlintGuideRules.queue_index([urgent, place, general] as Array[int], place), 2, "behind its equals")
	assert_eq(FlintGuideRules.queue_index([urgent, place, general] as Array[int], place, true), 1, "a cut one in front of them")
	assert_eq(FlintGuideRules.queue_index([place, general] as Array[int], urgent), 0, "danger first")
	var hint := _prioritized(&"flint_test_general", general)
	assert_true(FlintGuideRules.gives_way(hint, true, _prioritized(&"flint_test_urgent", urgent)))
	assert_false(FlintGuideRules.gives_way(hint, false, _prioritized(&"flint_test_urgent", urgent)), "not while flying back")
	assert_false(FlintGuideRules.gives_way(hint, true, _prioritized(&"flint_test_other", general)), "equals wait")
	assert_false(FlintGuideRules.gives_way(_prioritized(&"flint_test_tour", general, true), true,
			_prioritized(&"flint_test_urgent", urgent)), "a tour is never cut")


func test_the_place_goes_before_general_hints_and_danger_cuts_a_running_hint() -> void:
	var player := _player()
	var guide := _guide(player)
	var ended: Array = []
	guide.finished.connect(func(explanation: FlintExplanation, skipped: bool) -> void: ended.append([explanation.id, skipped]))
	assert_true(guide.queue(_prioritized(&"flint_test_general", FlintExplanation.Priority.GENERAL)))
	assert_true(guide.queue(_prioritized(&"flint_test_general_2", FlintExplanation.Priority.GENERAL)))
	_to_talk(guide)
	assert_true(guide.queue(_prioritized(&"flint_test_room", FlintExplanation.Priority.PLACE, true)))
	assert_eq(guide.current.id, &"flint_test_room", "the room's tour cuts the general hint at once")
	assert_true(player.is_protected(), "the tour holds")
	assert_eq(ended, [[&"flint_test_general", true]])
	assert_false(_seen.has(&"flint_test_general"), "a cut hint is not seen")
	assert_true(guide.is_known(&"flint_test_general"), "it waits again")
	assert_true(guide.queue(_prioritized(&"flint_test_hole", FlintExplanation.Priority.URGENT)))
	assert_eq(guide.current.id, &"flint_test_room", "a tour is never cut")
	guide.skip()
	_run(guide, FlintGuideRules.FLY_BACK_TIME + DT)
	assert_eq(guide.current.id, &"flint_test_hole", "danger next")
	_to_talk(guide)
	guide.skip()
	_run(guide, FlintGuideRules.FLY_BACK_TIME + DT)
	assert_eq(guide.current.id, &"flint_test_general", "the cut hint comes back first of its kind")
	guide.skip()
	_run(guide, FlintGuideRules.FLY_BACK_TIME + DT)
	assert_eq(guide.current.id, &"flint_test_general_2")


func test_a_hint_no_longer_due_is_dropped_unseen() -> void:
	var player := _player()
	var guide := _guide(player)
	var dropped: Array[StringName] = []
	guide.dropped.connect(func(explanation: FlintExplanation) -> void: dropped.append(explanation.id))
	assert_true(guide.queue(_hint(&"flint_test_first")))
	var due := [true]
	var waiting := _hint(&"flint_test_key")
	waiting.still_due = func() -> bool: return due[0]
	assert_true(guide.queue(waiting))
	_to_talk(guide)
	due[0] = false
	guide.advance(DT)
	assert_eq(dropped, [&"flint_test_key"] as Array[StringName], "the key was pressed meanwhile")
	assert_false(guide.is_known(&"flint_test_key"))
	assert_false(_seen.has(&"flint_test_key"), "not seen: it comes on the next occasion")
	assert_true(guide.queue(_hint(&"flint_test_key")), "and may be asked again")


func test_the_same_channel_replaces_the_running_hint() -> void:
	var player := _player()
	var guide := _guide(player)
	var welcome := _hint(&"flint_test_welcome")
	welcome.channel = &"test"
	var station := _hint(&"flint_test_station")
	station.channel = &"test"
	var other := _hint(&"flint_test_other")
	other.channel = &"test"
	assert_true(guide.queue(welcome))
	_to_talk(guide)
	assert_true(guide.queue(station))
	assert_eq(guide.current.id, &"flint_test_station", "the new station's hint at once")
	assert_eq(guide.phase, FlintGuide.Phase.TALK, "Flint stays in his corner")
	assert_false(guide.is_known(&"flint_test_welcome"), "the welcome is gone, not waiting")
	assert_true(guide.queue(other))
	assert_eq(guide.current.id, &"flint_test_other")
	assert_eq(guide.get_queue_size(), 0)


func test_no_tour_starts_in_the_side_view() -> void:
	var player := _player()
	var guide := _guide(player)
	if player.side_motion == null:
		player.side_motion = PlayerSideMotion.new()
		player.add_child(player.side_motion)
	player.side_motion.set(&"_active", true)
	assert_true(player.is_side_view())
	assert_true(guide.queue(_prioritized(&"flint_test_room", FlintExplanation.Priority.PLACE, true)))
	assert_false(guide.is_running(), "the tour waits: it would hold him mid-jump")
	assert_true(guide.queue(_prioritized(&"flint_test_side", FlintExplanation.Priority.URGENT)))
	assert_eq(guide.current.id, &"flint_test_side", "the side view hint comes at once")
	guide.skip()
	_run(guide, FlintGuideRules.FLY_BACK_TIME + DT)
	assert_false(guide.is_running(), "still in the side view")
	player.side_motion.set(&"_active", false)
	guide.advance(DT)
	assert_eq(guide.current.id, &"flint_test_room", "back on the floor: the tour")
	guide.skip()
	_run(guide, FlintGuideRules.FLY_BACK_TIME + DT)

extends GutTest
## The first-run keys without cards (decision 22.10.2026 "Ganz durch Flint ersetzen", FlintControls):
## Flint says each one once in his corner as a short hint (walk/aim/attack/dash at the start, the
## special from room 2, switching with two weapons, the use key at the first prompt, the overview
## after the first upgrade), worlds that saw the old card skip them, the HUD's key line is marked
## short from room 4, nothing while switched off or on touch; the hooks for holes, side view and the
## cracked wall; key names in the bubble become the pictures of the device in use (GlyphText).
## Seen flags are swapped for dictionaries; a test save only (never the real one).

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const InputDeviceScript := preload("res://player/input/input_device.gd")
const DT := 1.0 / 60.0

var _seen: Dictionary = {}
var _told: Array[StringName] = []
var _card_marked := 0
var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_flint_guide_controls_save.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.load_game()


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func before_each() -> void:
	_seen.clear()
	_told.clear()
	_card_marked = 0


func after_each() -> void:
	InputDeviceScript.shared().set_kind(InputDeviceScript.Kind.KEYBOARD_MOUSE)


func _player() -> Player:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.global_position = Vector2(400, 300)
	return player


## A coach for player with swapped seen flags; explain records the ids instead of showing them.
func _coach(player: Player) -> FlintControls:
	var coach := FlintControls.new()
	coach.has_seen = func(id: StringName) -> bool: return _seen.has(id)
	coach.explain = func(_player_node: Player, explanation: FlintExplanation) -> bool:
		_told.append(explanation.id)
		return true
	coach.mark_card_seen = func() -> void: _card_marked += 1
	coach.players_override = [player] as Array[Player]
	coach.set_process(false)
	add_child_autofree(coach)
	return coach


func _guide(player: Player) -> FlintGuide:
	var guide := FlintGuide.for_player(player)
	guide.set_process(false)
	guide.has_seen = func(id: StringName) -> bool: return _seen.has(id)
	guide.mark_seen = func(id: StringName) -> void: _seen[id] = true
	return guide


# --- The hints ---

func test_every_hint_is_a_short_hint_with_texts_in_both_languages() -> void:
	for id: StringName in FlintControls.RUN_HINTS + ([FlintControls.CHASM, FlintControls.SIDE_VIEW, FlintControls.SECRET_WALL] as Array[StringName]):
		var explanation := FlintControls.explanation_for(id)
		assert_not_null(explanation, String(id))
		assert_true(explanation.is_valid(), "%s: %s" % [id, explanation.problems()])
		assert_eq(explanation.style, FlintExplanation.Style.HINT, "%s: no camera, no lock" % id)
		assert_true(String(id).begins_with(FlintExplanation.ID_PREFIX), "seen per account")
		for step in explanation.steps:
			var key := String(step.text_key)
			assert_true(key.begins_with("FLINT_"), key)
			for locale: String in ["en", "de"]:
				var text := TranslationServer.get_translation_object(locale).get_message(step.text_key)
				assert_ne(String(text), "", "%s in %s" % [key, locale])
				assert_eq(String(text).count("%s"), step.text_args.size(), "%s %s: one key per placeholder" % [key, locale])
	assert_null(FlintControls.explanation_for(&"flint_nothing"))


func test_the_keys_are_named_with_the_binding() -> void:
	var basics := FlintControls.explanation_for(FlintControls.BASICS)
	assert_eq(basics.steps[1].text_args, [ControlsInfo.key_text(ControlsInfo.ATTACK), ControlsInfo.key_text(ControlsInfo.DASH)])
	assert_true(basics.steps[1].get_text().contains(ControlsInfo.key_text(ControlsInfo.DASH)))
	var overview := FlintControls.explanation_for(FlintControls.OVERVIEW)
	assert_eq(overview.steps[0].text_args, [ControlsInfo.key_text(ControlsInfo.OVERVIEW)])


# --- When the coach brings them ---

func test_flint_says_the_keys_when_they_become_new() -> void:
	var player := _player()
	var coach := _coach(player)
	coach.tick(FlintControls.START_DELAY - 0.1)
	assert_eq(_told, [] as Array[StringName], "a moment for the run start first")
	coach.tick(0.2)
	assert_eq(_told, [FlintControls.BASICS] as Array[StringName], "walk, aim, attack, dash")
	EventBus.room_entered.emit(FlintControls.SPECIAL_ROOM)
	coach.tick(DT)
	assert_eq(_told.back(), FlintControls.SPECIAL, "room 2: the special")
	assert_false(_told.has(FlintControls.SWITCH), "one weapon: nothing to switch")
	assert_true(player.weapon_controller.equip_weapon(load("res://weapons/data/bow.tres") as WeaponData, 1))
	coach.tick(DT)
	assert_eq(_told.back(), FlintControls.SWITCH, "two weapons: switching")
	(player.get_node(FlintControls.PROMPT_NODE) as CanvasItem).visible = true
	coach.tick(DT)
	assert_eq(_told.back(), FlintControls.INTERACT, "something to use: the use key")
	EventBus.upgrade_acquired.emit(&"sharp_edge", 1)
	coach.tick(DT)
	assert_eq(_told.back(), FlintControls.OVERVIEW, "first upgrade: the overview key")
	var count := _told.size()
	for i in 30:
		coach.tick(DT)
	assert_eq(_told.size(), count, "each hint once")
	assert_eq(_card_marked, 0, "the HUD keeps the full key line before room 4")
	EventBus.room_entered.emit(FlintControls.LAST_ROOM)
	coach.tick(DT)
	coach.tick(DT)
	assert_eq(_card_marked, 1, "from room 4 the key line is short, marked once")


func test_worlds_that_saw_the_old_card_skip_its_keys() -> void:
	_seen[ControlsHint.SEEN_ID] = true
	var player := _player()
	var coach := _coach(player)
	coach.tick(FlintControls.START_DELAY + 0.1)
	EventBus.room_entered.emit(FlintControls.SPECIAL_ROOM)
	EventBus.upgrade_acquired.emit(&"sharp_edge", 1)
	coach.tick(DT)
	assert_eq(_told, [FlintControls.OVERVIEW] as Array[StringName], "the card taught the keys, not the overview tip")
	assert_true(coach.was_asked(player, FlintControls.BASICS))


func test_a_world_marked_by_flint_itself_still_gets_the_rest() -> void:
	# Room 4 marked "hint_controls" for the HUD after Flint said the basics: later hints still come.
	_seen[ControlsHint.SEEN_ID] = true
	_seen[FlintControls.BASICS] = true
	var player := _player()
	var coach := _coach(player)
	EventBus.room_entered.emit(FlintControls.SPECIAL_ROOM)
	coach.tick(DT)
	assert_true(_told.has(FlintControls.SPECIAL))


func test_nothing_while_switched_off_or_on_touch() -> void:
	var player := _player()
	var coach := _coach(player)
	coach.enabled = false
	coach.tick(FlintControls.START_DELAY + 1.0)
	assert_eq(_told, [] as Array[StringName], "the practice run holds it")
	coach.enabled = true
	var touch := TouchState.shared()
	var was_touched := touch.touched
	touch.touched = true
	coach.tick(FlintControls.START_DELAY + 1.0)
	touch.touched = was_touched
	assert_eq(_told, [] as Array[StringName], "touch controls show their own buttons")
	coach.tick(FlintControls.START_DELAY + DT)
	assert_eq(_told, [FlintControls.BASICS] as Array[StringName])


func test_flint_really_says_it_once_per_account() -> void:
	var player := _player()
	var guide := _guide(player)
	assert_true(FlintControls.explain_first(player, FlintControls.CHASM))
	assert_eq(guide.current.id, FlintControls.CHASM)
	assert_false(guide.current.locks_player(), "a hint: nothing stops")
	guide.skip()
	assert_true(_seen.has(FlintControls.CHASM))
	assert_false(FlintControls.explain_first(player, FlintControls.CHASM), "seen: not again")
	assert_false(FlintControls.explain_first(player, &"flint_nothing"))


func test_hooks_for_holes_side_view_and_cracked_walls() -> void:
	var player := _player()
	var guide := _guide(player)
	assert_true(FlintExplanations.chasm(player))
	assert_true(FlintExplanations.side_view(player))
	assert_true(FlintExplanations.secret_wall(player))
	assert_eq(guide.get_queue_size(), 2, "one after another")


# --- DungeonUI ---

func test_dungeon_ui_starts_flint_instead_of_the_card() -> void:
	var ui := DungeonUI.new()
	ui.auto_enemy_hints = false
	add_child_autofree(ui)
	await wait_physics_frames(1)
	var coach := ui.get_controls_hint()
	assert_not_null(coach, "the run starts Flint's key hints")
	assert_is(coach, FlintControls)
	assert_null(ui.start_controls_hint(), "only one")
	ui.show_controls_hint = false
	assert_false(coach.enabled, "the practice run holds it")
	ui.show_controls_hint = true
	assert_true(coach.enabled)
	assert_eq(ui.get_tree().get_nodes_in_group(&"controls_hint").size(), 0, "no card any more")
	var other := DungeonUI.new()
	other.show_controls_hint = false
	add_child_autofree(other)
	await wait_physics_frames(1)
	assert_null(other.get_controls_hint(), "tools can switch it off")


# --- Key pictures in the bubble ---

func test_glyph_starts_map_the_typing_onto_the_pictures() -> void:
	var icon := PlaceholderTexture2D.new()
	var text := "Mit Leertaste weg"
	var starts := FlintGuideView.glyph_starts(text, ["Mit ", icon, " weg"])
	assert_eq(starts, PackedInt32Array([0, 1, 2, 3, 4, 13, 14, 15, 16]), "the picture shows with the first letter of its name")
	assert_eq(FlintGuideView.glyph_starts("A B", [icon, " ", icon]), PackedInt32Array([0, 1, 2]))


func test_the_bubble_shows_key_pictures() -> void:
	var player := _player()
	var guide := _guide(player)
	guide.shows_view = true
	var explanation := FlintControls.explanation_for(FlintControls.BASICS)
	assert_true(guide.queue(explanation))
	for i in int((FlintGuideRules.GROW_TIME + FlintGuideRules.FLY_OUT_TIME) / DT) + 2:
		guide.advance(DT)
	var view := guide.get_view() as FlintGuideView
	assert_not_null(view)
	var text := guide.get_text()
	if not GlyphText.has_glyphs(GlyphText.split(text)):
		pending("no key pictures for this binding: %s" % text)
		return
	var rich := view.get_speech_glyphs()
	assert_not_null(rich, "the sentence names keys: pictures in the bubble")
	assert_false(view.get_speech().visible, "the plain line hides")
	assert_eq(rich.get_total_character_count(), FlintGuideView.glyph_starts(text, GlyphText.split(text)).size(),
			"a picture counts as one character")
	for i in 600:
		guide.advance(DT)
		if guide.get_revealed() >= text.length():
			break
	assert_eq(rich.visible_characters, -1, "all of it once typed")


# --- Queue (FS5) and the first crystal (D-220) ---

func test_danger_and_the_place_come_before_general_keys() -> void:
	assert_eq(FlintControls.explanation_for(FlintControls.CHASM).priority, FlintExplanation.Priority.URGENT, "holes")
	assert_eq(FlintControls.explanation_for(FlintControls.SIDE_VIEW).priority, FlintExplanation.Priority.URGENT, "side view")
	assert_eq(FlintControls.explanation_for(FlintControls.INTERACT).priority, FlintExplanation.Priority.PLACE, "the thing in front of him")
	assert_eq(FlintControls.explanation_for(FlintControls.SECRET_WALL).priority, FlintExplanation.Priority.PLACE)
	for id in [FlintControls.BASICS, FlintControls.SPECIAL, FlintControls.SWITCH, FlintControls.OVERVIEW, FlintControls.FIRST_CRYSTAL]:
		assert_eq(FlintControls.explanation_for(id).priority, FlintExplanation.Priority.GENERAL, String(id))


func test_a_waiting_key_hint_is_dropped_once_the_player_did_it() -> void:
	var player := _player()
	var guide := _guide(player)
	guide.shows_view = false
	var coach := _coach(player)
	coach.explain = func(target: Player, explanation: FlintExplanation) -> bool:
		_told.append(explanation.id)
		return FlintGuide.of(target).queue(explanation)
	_seen[FlintControls.BASICS] = true
	# A tour runs: the special hint has to wait.
	assert_true(guide.queue(FlintExplanation.tour(&"flint_test_tour", [FlintGuideStep.say(&"FLINT_ENTRANCE_1")] as Array[FlintGuideStep])))
	EventBus.room_entered.emit(FlintControls.SPECIAL_ROOM)
	coach.tick(DT)
	assert_true(guide.is_known(FlintControls.SPECIAL), "asked, waits behind the tour")
	player.weapon_controller.special_performed.emit(null)
	assert_true(coach.did_action(player, FlintControls.SPECIAL), "the coach saw the special")
	guide.advance(DT)
	assert_false(guide.is_known(FlintControls.SPECIAL), "dropped: he knows it already")
	assert_false(_seen.has(FlintControls.SPECIAL), "dropped is not seen")
	coach.tick(DT)
	assert_eq(_told.count(FlintControls.SPECIAL), 1, "not again in the same room")
	EventBus.room_entered.emit(FlintControls.SPECIAL_ROOM + 1)
	coach.tick(DT)
	assert_eq(_told.count(FlintControls.SPECIAL), 2, "the next room is the next occasion")
	assert_false(coach.did_action(player, FlintControls.SPECIAL), "counted anew from the new ask")


func test_the_first_crystal_brings_its_hint() -> void:
	var player := _player()
	var coach := _coach(player)
	coach.tick(FlintControls.START_DELAY + 0.1)
	assert_false(_told.has(FlintControls.FIRST_CRYSTAL))
	RunManager.run_crystals_changed.emit(0)
	coach.tick(DT)
	assert_false(_told.has(FlintControls.FIRST_CRYSTAL), "no crystal yet")
	RunManager.run_crystals_changed.emit(1)
	coach.tick(DT)
	assert_true(_told.has(FlintControls.FIRST_CRYSTAL), "the first crystal: what it is for")
	assert_eq(FlintControls.explanation_for(FlintControls.FIRST_CRYSTAL).steps[0].text_key, &"FLINT_FIRST_CRYSTAL")

extends GutTest
## The practice run in play (WK10, TutorialRun) on a stand-in dungeon: begin() builds the hall and
## moves the spawn there, the run takes the local player, Flint welcomes with a hint while the first
## door is already open, the stations finish in order (flags, doors, strip), a fall into the abyss
## costs nothing, the shield dummy only breaks with a special, the gate ends it with the XP of the
## first completion (hook), the seen flag and Flint's "geschafft", "Kenne ich schon" ends it without
## XP. WK10b: the strip is one slim line at the top edge and hides in the side view, a controls card
## that came first waits hidden. The dummies take real hits through their
## hurtbox. Co-op: tip bubbles in the first rooms instead. Seen flags and the XP target are swapped,
## the account progress lives in a test file (never the real save, AGENTS.md rule 4).

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const ROOT := "user://test_tutorial_run"
const DT := 1.0 / 60.0


## The parts of DungeonManager the practice run asks for.
class FakeDungeon:
	extends Node2D
	var players: Array[Player] = []
	var ui: Node = null

	func _init() -> void:
		var spawn := Marker2D.new()
		spawn.name = "PlayerSpawn"
		add_child(spawn)

	func get_session_players() -> Array[Player]:
		return players

	func get_room(_index: int) -> RoomController:
		return null


## The DungeonUI hooks of the first-run controls card.
class FakeUi:
	extends Node
	var show_controls_hint := true
	var card: Control = null
	var started := 0

	func get_controls_hint() -> Control:
		return card

	func start_controls_hint() -> Control:
		started += 1
		return null


class FakeProgress:
	extends RefCounted
	var credits: Array = []

	func add_bonus_xp(id: String, amount: int) -> bool:
		credits.append([id, amount])
		return true


var _seen: Dictionary = {}
var _tour_seen := false
var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = ROOT + "/save.cfg"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	AccountProgress.path_override = ROOT + "/progress.cfg"
	AccountProgress.reset()


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ROOT + "/progress.cfg"))
	AccountProgress.path_override = ""
	AccountProgress.reset()
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()
	TutorialRun.force_next = false


func before_each() -> void:
	_seen.clear()
	_tour_seen = false


## A dungeon with a running practice run and its player (welcome still running).
func _start() -> Array:
	var dungeon := FakeDungeon.new()
	add_child_autofree(dungeon)
	var run := TutorialRun.begin(dungeon, true)
	# A new account (another test marked the test account as seen).
	run.was_seen = false
	run.mark_seen = func(id: StringName) -> void: _seen[id] = true
	run.village_tour_seen = func() -> bool: return _tour_seen
	var player := PLAYER_SCENE.instantiate() as Player
	dungeon.add_child(player)
	player.global_position = (dungeon.get_node(^"PlayerSpawn") as Node2D).global_position
	dungeon.players.append(player)
	var guide := FlintGuide.for_player(player)
	guide.shows_view = false
	guide.set_process(false)
	guide.has_seen = func(id: StringName) -> bool: return _seen.has(id)
	guide.mark_seen = func(id: StringName) -> void: _seen[id] = true
	await wait_physics_frames(2)
	return [dungeon, run, player, guide]


func _skip_welcome(guide: FlintGuide) -> void:
	guide.advance(FlintGuideRules.GROW_TIME + FlintGuideRules.FLY_OUT_TIME + DT)
	guide.skip()
	var left := FlintGuideRules.FLY_BACK_TIME + DT * 2.0
	while left > 0.0:
		guide.advance(DT)
		left -= DT


func test_begin_builds_the_hall_and_moves_the_spawn() -> void:
	var parts: Array = await _start()
	var dungeon: FakeDungeon = parts[0]
	var run: TutorialRun = parts[1]
	assert_eq(TutorialRun.of(dungeon), run)
	assert_eq(TutorialRun.begin(dungeon, true), run, "idempotent: the hook and a tool may both call it")
	var spawn := dungeon.get_node(^"PlayerSpawn") as Node2D
	assert_almost_eq(spawn.global_position.distance_to(run.area.get_start_feet() - Player.FEET_OFFSET), 0.0, 0.1, "players spawn in the hall")
	assert_true(run.area.global_position.distance_to(TutorialRules.ORIGIN) < 1.0, "far from the rooms")


func test_not_offered_again_once_seen() -> void:
	var dungeon := FakeDungeon.new()
	add_child_autofree(dungeon)
	AccountSeen.mark_seen(TutorialRules.SEEN_ID)
	assert_null(TutorialRun.begin(dungeon), "seen for this account: no practice run")
	assert_null(dungeon.get_node_or_null(^"TutorialCoopTips"), "alone: no co-op tips either")
	TutorialRun.force_next = true
	var forced := TutorialRun.begin(dungeon)
	assert_not_null(forced, "force_next (tools) offers it anyway")
	assert_false(TutorialRun.force_next, "force_next is used up")


func test_welcome_then_stations_in_order() -> void:
	var parts: Array = await _start()
	var run: TutorialRun = parts[1]
	var player: Player = parts[2]
	var guide: FlintGuide = parts[3]
	assert_eq(run.player, player, "the run takes the local player")
	assert_eq(guide.current.id, TutorialRun.WELCOME_ID, "Flint welcomes")
	assert_eq(guide.current.style, FlintExplanation.Style.HINT, "a hint while playing, no tour")
	assert_false(guide.current.locks_player(), "nobody waits for Flint")
	assert_false(guide.current.uses_camera(), "no camera ride")
	assert_eq(guide.current.steps.size(), 1, "one sentence")
	assert_eq(guide.current.steps[0].text_key, TutorialRules.WELCOME_INTRO_KEY, "never met: Flint introduces himself")
	assert_eq(run.zone, 0, "station 1 at once")
	assert_true(run.area.doors[0].is_open, "the first door is open at once")
	_skip_welcome(guide)
	# Out of order: nothing happens.
	run.complete(TutorialRules.Station.SPECIAL)
	assert_false(run.done[TutorialRules.Station.SPECIAL], "stations finish in order")
	watch_signals(run)
	for dummy in run.area.dummies:
		for hit in TutorialRules.DUMMY_HITS:
			dummy.take_hit([] as Array[StringName])
		assert_true(dummy.is_broken)
	assert_true(run.done[TutorialRules.Station.ATTACK], "all straw dummies down: station 1 done")
	assert_signal_emitted_with_parameters(run, "station_completed", [TutorialRules.Station.ATTACK])
	assert_true(run.area.get_flag(0).is_raised, "its flag flies")
	assert_true(run.area.doors[1].is_open, "the next door opens")
	assert_eq(run.hud.done[0], true)
	assert_eq(run.zone, TutorialRules.Station.DASH)


func test_no_second_introduction_after_the_village_tour() -> void:
	_tour_seen = true
	var parts: Array = await _start()
	var guide: FlintGuide = parts[3]
	assert_eq(guide.current.steps[0].text_key, TutorialRules.WELCOME_KNOWN_KEY, "met in the village: just \"kurz üben\"")


func test_the_dash_station_and_a_free_fall() -> void:
	var parts: Array = await _start()
	var run: TutorialRun = parts[1]
	var player: Player = parts[2]
	_skip_welcome(parts[3])
	for dummy in run.area.dummies:
		for hit in TutorialRules.DUMMY_HITS:
			dummy.take_hit([] as Array[StringName])
	# A fall into the abyss: back to the last safe spot, no heart lost.
	var health := player.health.get_health()
	assert_true(player.fall.start_fall())
	player.fall.land()
	assert_eq(player.health.get_health(), health, "falling while practising costs nothing")
	# Over the abyss: on safe ground beyond its east edge.
	player.global_position = Vector2(run.area.get_pit_east_x() + 48.0, run.area.get_pit_run_up_feet().y) - Player.FEET_OFFSET
	await wait_physics_frames(2)
	assert_true(run.done[TutorialRules.Station.DASH], "station 2 done beyond the abyss")
	assert_true(run.area.jump_door.is_open, "the door to the side view opens")
	assert_eq(run.zone, TutorialRules.Station.JUMP)


func test_the_shield_dummy_needs_the_special_and_the_gate_ends_it() -> void:
	var parts: Array = await _start()
	var run: TutorialRun = parts[1]
	var progress := FakeProgress.new()
	run.progress_source = func() -> Object: return progress
	_skip_welcome(parts[3])
	run.zone = TutorialRules.Station.SPECIAL
	for station in 3:
		run.done[station] = true
	var shield := run.area.shield_dummy
	assert_eq(shield.take_hit([&"sword"] as Array[StringName]), TutorialRules.Hit.BLOCKED, "a normal hit bounces off")
	assert_eq(run.blocked_hits, 1, "Flint gets told (Klonk!)")
	assert_false(shield.is_broken)
	# A real special through the hurtbox (DamageData with the special tag).
	var damage := DamageData.new()
	damage.amount = 1.0
	damage.tags.assign([&"sword", TutorialRules.SPECIAL_TAG])
	shield.get_hurtbox().receive_hit(damage)
	assert_true(shield.is_broken, "the special breaks shield and dummy")
	assert_true(run.done[TutorialRules.Station.SPECIAL])
	assert_true(run.area.doors[run.area.doors.size() - 1].is_open, "the way to the gate opens")
	assert_eq(run.zone, TutorialRun.FINISH)
	var ended: Array = []
	run.finished.connect(func(completed: bool, xp: int) -> void: ended.append([completed, xp]))
	run.area.gate_passed.emit(run.player)
	assert_true(_seen.has(TutorialRules.SEEN_ID), "done: seen for the account")
	assert_eq(progress.credits, [[TutorialRules.XP_CREDIT_ID, TutorialRules.XP_FIRST_COMPLETION]], "+25 XP through the hook")
	await wait_for_signal(run.finished, 3.0)
	assert_eq(ended, [[true, TutorialRules.XP_FIRST_COMPLETION]], "finished, completed, with the XP")
	var guide: FlintGuide = parts[3]
	assert_true(guide.is_known(TutorialRun.DONE_ID), "Flint says it is done in room 1 (no banner)")
	assert_eq(guide.current.steps[0].text_key, &"FLINT_TUTORIAL_DONE_XP", "with the XP")
	assert_eq(guide.current.steps[1].text_key, &"FLINT_TUTORIAL_DEATH", "and what a fall costs (D-220)")
	assert_true(_seen.has(FlintControls.BASICS), "completed: Flint's first-run basics are not needed (FS5)")


func test_the_end_names_what_a_fall_costs() -> void:
	var steps := TutorialRun.done_steps(0)
	assert_eq(steps.size(), 2)
	assert_eq(steps[0].text_key, &"FLINT_TUTORIAL_DONE", "no XP: the plain sentence")
	assert_eq(steps[1].text_key, &"FLINT_TUTORIAL_DEATH")
	assert_eq(steps[1].text_args, [roundi(RunManager.LOSS_PAYOUT_RATIO * 100.0)], "the share from the code")
	assert_eq(TutorialRun.loss_percent(), 25)
	assert_true(steps[1].get_text().contains("25"), "the number is in the sentence")


func test_a_new_station_replaces_the_running_hint() -> void:
	var parts: Array = await _start()
	var run: TutorialRun = parts[1]
	var guide: FlintGuide = parts[3]
	guide.advance(FlintGuideRules.GROW_TIME + FlintGuideRules.FLY_OUT_TIME + DT)
	assert_eq(guide.current.id, TutorialRun.WELCOME_ID, "Flint welcomes")
	run._announce(0)
	assert_eq(guide.current.id, TutorialRules.explanation_id(TutorialRules.Station.ATTACK), "the welcome gives way to the straw dummies at once")
	assert_eq(guide.get_queue_size(), 0, "the welcome does not come again")
	assert_eq(guide.current.channel, TutorialRun.FLINT_CHANNEL)
	run.complete(TutorialRules.Station.ATTACK)
	assert_eq(guide.current.id, StringName(String(TutorialRules.explanation_id(TutorialRules.Station.ATTACK)) + "_done"))
	run._announce(1)
	assert_eq(guide.current.id, TutorialRules.explanation_id(TutorialRules.Station.DASH), "the newest station counts")
	assert_eq(guide.get_queue_size(), 0)


func test_skip_ends_it_without_xp() -> void:
	var parts: Array = await _start()
	var run: TutorialRun = parts[1]
	var progress := FakeProgress.new()
	run.progress_source = func() -> Object: return progress
	var player: Player = parts[2]
	var ended: Array = []
	run.finished.connect(func(completed: bool, xp: int) -> void: ended.append([completed, xp]))
	run.area.shortcut.interact(player)
	assert_true(run.is_finished)
	assert_true(_seen.has(TutorialRules.SEEN_ID), "skipped: not offered again")
	assert_eq(progress.credits, [], "no XP for skipping")
	await wait_for_signal(run.finished, 3.0)
	assert_eq(ended, [[false, 0]])
	await wait_physics_frames(2)
	assert_false(player.is_input_locked(), "the player is free again")
	assert_null(TutorialRun.of(parts[0]), "the hall is gone")


func test_hud_skip_button_skips_too() -> void:
	var parts: Array = await _start()
	var run: TutorialRun = parts[1]
	run.progress_source = func() -> Object: return FakeProgress.new()
	run.hud.get_skip_button().pressed.emit()
	assert_true(run.is_finished)
	assert_false(run.was_completed)


func test_hud_shows_station_and_progress() -> void:
	var hud := TutorialHud.new()
	add_child_autofree(hud)
	hud.show_zone(1)
	assert_eq(hud.get_station_text(), Loc.t(&"TUTORIAL_STATION_DASH"), "only the station's name")
	assert_string_contains(hud.get_progress_text(), "0/4")
	hud.set_done(0)
	assert_string_contains(hud.get_progress_text(), "1/4")
	hud.show_zone(TutorialHud.FINISH)
	assert_false(hud.get_skip_button().visible, "no skip on the last few steps")
	assert_eq(hud.get_station_text(), "", "the way to the gate: Flint says it")


## WK10b: one slim line at the top edge, no panel over the playfield, no key row.
func test_the_strip_is_one_slim_line_at_the_top() -> void:
	var hud := TutorialHud.new()
	add_child_autofree(hud)
	hud.show_zone(0)
	await wait_process_frames(2)
	var panel := hud.get_panel()
	var rect := panel.get_global_rect()
	assert_lte(rect.position.y, UiKit.px(TutorialHud.TOP_MARGIN) + 1.0, "at the top edge")
	assert_lte(rect.size.y, UiKit.px(14.0), "one slim line (%d px)" % rect.size.y)
	# At the portrait zoom (x1.5) it must still fit between the hearts and the room label.
	assert_lte(rect.size.x, UiKit.px(480.0) * 0.32, "narrow (%d px)" % rect.size.x)
	assert_eq(panel.find_children("*", "KeyCap", true, false).size(), 0, "the keys stand on the signs, not in the strip")


func test_the_strip_hides_in_the_side_view() -> void:
	var parts: Array = await _start()
	var run: TutorialRun = parts[1]
	var player: Player = parts[2]
	_skip_welcome(parts[3])
	run.zone = TutorialRules.Station.JUMP
	for station in 2:
		run.done[station] = true
	run.area.jump_door_entered.emit(player)
	var jump := run.get_jump()
	assert_not_null(jump, "the side-view stretch starts")
	assert_false(run.hud.visible, "nothing over the side view but Flint's corner")
	jump.left.emit(jump)
	assert_true(run.hud.visible, "back in the hall: the strip again")
	assert_true(run.done[TutorialRules.Station.JUMP])


func test_the_controls_card_waits_hidden() -> void:
	var dungeon := FakeDungeon.new()
	add_child_autofree(dungeon)
	var ui := FakeUi.new()
	ui.card = Control.new()
	ui.add_child(ui.card)
	dungeon.add_child(ui)
	dungeon.ui = ui
	var run := TutorialRun.begin(dungeon, true)
	assert_false(ui.show_controls_hint, "no card during the practice run")
	assert_false(ui.card.visible, "a card that came first waits hidden")
	run.hold_controls_card(false)
	assert_true(ui.card.visible, "afterwards it shows again")
	assert_eq(ui.started, 0, "no second card")
	ui.card = null
	run.hold_controls_card(false)
	assert_eq(ui.started, 1, "without one it starts now")


func test_side_stretch_hints_and_momentum() -> void:
	var jump := TutorialJump.new()
	var first: Array = TutorialPlans.JUMP_HINTS[0]
	var ground_row := TutorialPlans.jump_layout().start.y
	var feet_at := func(column: int, row: int) -> Vector2: return SideLayout.feet_of(Vector2i(column, row))
	assert_eq(jump.hint_for(feet_at.call(2, ground_row)), &"", "nothing at the start")
	assert_eq(jump.hint_for(feet_at.call(int(first[0]), ground_row)), first[1])
	assert_eq(jump.hint_for(feet_at.call(int(first[0]), ground_row)), &"", "each hint once")
	jump.hints_given.clear()
	for spot: Array in TutorialPlans.JUMP_HINTS:
		jump.hints_given.append(spot[1])
	var ditch := TutorialPlans.JUMP_DITCH
	assert_eq(jump.hint_for(feet_at.call(ditch.y + 1, ground_row)), TutorialJump.MOMENTUM_KEY, "over the ditch without touching it: momentum")
	var walker := TutorialJump.new()
	walker.hints_given.assign(jump.hints_given)
	assert_eq(walker.hint_for(feet_at.call(ditch.x, ground_row + 2)), &"")
	assert_eq(walker.hint_for(feet_at.call(ditch.y + 1, ground_row)), TutorialJump.DITCH_KEY, "fell into the ditch: a tip")
	jump.free()
	walker.free()


func test_coop_tips_in_the_first_rooms() -> void:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	var guide := FlintGuide.for_player(player)
	guide.shows_view = false
	guide.set_process(false)
	var tips := TutorialCoopTips.new()
	add_child_autofree(tips)
	tips.has_seen = func(_id: StringName) -> bool: return false
	var tip := TutorialCoopTips.tip_for(1)
	assert_true(tip.is_valid())
	assert_eq(tip.style, FlintExplanation.Style.HINT, "a bubble without stop")
	assert_false(tip.once, "again in every group game until done alone")
	assert_eq(tips.show_tip(1, [player]), 1)
	assert_eq(tips.show_tip(1, [player]), 0, "once per room")
	assert_eq(tips.show_tip(TutorialRules.COOP_TIP_ROOMS + 1, [player]), 0, "only the first rooms")
	tips.has_seen = func(_id: StringName) -> bool: return true
	assert_eq(tips.show_tip(2, [player]), 0, "done alone: no tips")

extends GutTest
## Room goals and the task bar (R3, KONZEPT_RAEUME_V2 §1.4, 07_ui.md): RoomObjective holds mode,
## texts, progress, time and danger; ArenaObjective follows an arena room ("Welle 1/2 · 3 Gegner",
## wave_cleared between waves); ObjectiveBar shows it at the top centre, pulses red in danger and
## gives way to the boss bar. Uses a test save, never the real one.

const TEST_SAVE_PATH := "user://test_objective.cfg"
const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH


func before_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.load_game()


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func _ui() -> DungeonUI:
	var ui: DungeonUI = add_child_autofree(DungeonUI.new())
	ui.auto_enemy_hints = false
	ui.show_controls_hint = false
	return ui


## Arena room with skeletons only and a fixed count per wave (like test_arena).
func _arena(count := 3, room_index := 12) -> RoomController:
	var room := HALL.instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.ARENA
	room.forced_ambush = 0
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 31
	room.setup(room_index, RoomSequence.RoomType.COMBAT, -1, false, context)
	var spawner := room.get_node("EnemySpawner") as EnemySpawner
	spawner.biomes = [] as Array[BiomeData]
	spawner.extra_types = [] as Array[EnemyData]
	spawner.enemy_types = [SKELETON] as Array[EnemyData]
	spawner.spawn_weights = [1.0] as Array[float]
	var group := EncounterGroup.new()
	group.count_range = Vector2i(count, count)
	group.allow_elites = false
	spawner.encounter_group = group
	add_child_autofree(room)
	return room


func _living(room: RoomController) -> Array[Enemy]:
	var living: Array[Enemy] = []
	for child in room.enemy_container.get_children():
		var enemy := child as Enemy
		if enemy != null and not enemy.is_dead():
			living.append(enemy)
	return living


# --- RoomObjective ---

func test_every_mode_has_symbol_colour_and_texts() -> void:
	for mode: StringName in RoomObjective.MODES:
		var goal := RoomObjective.create(mode)
		assert_not_null(goal.get_icon(), "%s: symbol from door_mode_symbols.png" % mode)
		for text in [goal.get_title(), goal.get_rule()]:
			assert_false(text.is_empty(), "%s has a title and a rule" % mode)
			assert_false(text.contains("_TITLE") or text.contains("_RULE"), "%s: '%s' is not a raw key" % [mode, text])
		var sentence := DungeonTexts.t(goal.goal_key)
		assert_false(sentence.is_empty() or sentence.contains("_GOAL"), "%s: goal sentence" % mode)
		assert_true(RoomGenre.has_genre(goal.genre), "%s: first-time card text" % mode)
		goal.free()
	assert_eq(RoomObjective.get_mode_color(RoomObjective.ARENA), Color("#e0463a"), "07_ui.md")
	assert_eq(RoomObjective.get_mode_color(RoomObjective.FLAME), Color("#6a4fc4"))
	assert_gt(RoomObjective.get_mode_ui_color(RoomObjective.LIGHTFIRE).get_luminance(), RoomObjective.get_mode_color(RoomObjective.LIGHTFIRE).get_luminance(),
		"the nearly black Lichtfeuer colour is lifted on dark panels")
	assert_true(RoomObjective.is_calm_mode(RoomObjective.ESCORT))
	assert_false(RoomObjective.is_calm_mode(RoomObjective.ARENA))


func test_arena_goal_sentence() -> void:
	var goal := RoomObjective.create(RoomObjective.ARENA)
	goal.goal_args = [3]
	assert_eq(goal.get_title(), "Arena")
	assert_eq(goal.get_goal(), "Überlebe 3 Wellen")
	goal.free()


func test_progress_texts_and_time() -> void:
	var goal: RoomObjective = autofree(RoomObjective.create(RoomObjective.SOULS))
	watch_signals(goal)
	assert_false(goal.has_progress())
	assert_eq(goal.get_progress_text(), "")
	goal.set_count(4, 12)
	assert_eq(goal.get_progress_text(), "4/12")
	assert_almost_eq(goal.get_ratio(), 4.0 / 12.0, 0.001)
	goal.set_ratio(0.62)
	assert_eq(goal.get_progress_text(), "62 %")
	assert_signal_emit_count(goal, "changed", 2)
	goal.set_ratio(0.62)
	assert_signal_emit_count(goal, "changed", 2, "no change, no signal")
	assert_eq(RoomObjective.format_time(27.2), "0:28")
	assert_eq(RoomObjective.format_time(65.0), "1:05")
	assert_eq(RoomObjective.format_time(-1.0), "")
	assert_false(goal.has_time())
	goal.set_time(40.0)
	assert_true(goal.has_time())
	goal.clear_time()
	assert_false(goal.has_time())


func test_running_time_counts_down_and_fires_once() -> void:
	var goal: RoomObjective = add_child_autofree(RoomObjective.create(RoomObjective.COLLAPSE))
	watch_signals(goal)
	goal.set_time(0.3, true)
	await wait_seconds(0.6)
	assert_eq(goal.time_left, 0.0)
	assert_signal_emit_count(goal, "time_up", 1)


func test_auto_danger_below_thirty_percent() -> void:
	var goal: RoomObjective = autofree(RoomObjective.create(RoomObjective.FLAME))
	goal.auto_danger = true
	goal.set_ratio(0.7)
	assert_false(goal.danger)
	goal.set_ratio(0.25)
	assert_true(goal.danger, "flame < 30 %")
	goal.set_ratio(0.5)
	assert_false(goal.danger)


func test_finish_once_and_one_goal_per_room() -> void:
	var room: Node2D = add_child_autofree(Node2D.new())
	var first := RoomObjective.attach(room, RoomObjective.create(RoomObjective.RELIC))
	assert_eq(RoomObjective.of_room(room), first)
	assert_eq(first.get_parent(), room)
	assert_true(first.is_in_group(RoomObjective.GROUP))
	watch_signals(first)
	first.finish(false)
	first.finish(true)
	assert_signal_emit_count(first, "finished", 1)
	assert_false(first.success)
	var second := RoomObjective.attach(room, RoomObjective.create(RoomObjective.HUNT))
	assert_eq(RoomObjective.of_room(room), second, "a newer goal replaces the old one")
	await wait_physics_frames(1)
	assert_false(is_instance_valid(first))
	assert_null(RoomObjective.of_room(null))


# --- ArenaObjective ---

func test_arena_objective_follows_the_waves() -> void:
	var room := _arena(3, 12)
	await wait_process_frames(2)
	var goal := ArenaObjective.attach_to(room)
	assert_eq(ArenaObjective.attach_to(room), goal, "one per room")
	assert_eq(goal.get_total_waves(), WaveRules.ARENA_WAVES)
	assert_eq(goal.get_goal(), "Überlebe 2 Wellen")
	assert_eq(goal.label_text, "2 Wellen", "before the fight")
	assert_eq(ArenaObjective.get_wave_pause(room), ArenaObjective.WAVE_PAUSE)
	watch_signals(goal)
	room.activate()
	await wait_process_frames(1)
	assert_eq(goal.label_text, "Welle 1/2 · 3 Gegner")
	# Enemies step out of their sources first (R2, warning + emerge) and only then take hits.
	await wait_seconds(2.5)
	for enemy in _living(room):
		enemy.health.take_damage(INF)
	await wait_process_frames(3)
	assert_signal_emitted_with_parameters(goal, "wave_cleared", [2, 2])
	assert_signal_emit_count(goal, "wave_cleared", 1)
	# The room waits WAVE_PAUSE before wave 2 (integrated hook), then the wave emerges.
	await wait_seconds(ArenaObjective.WAVE_PAUSE + 0.3)
	assert_eq(goal.label_text, "Welle 2/2 · 3 Gegner")
	await wait_seconds(2.5)
	for enemy in _living(room):
		enemy.health.take_damage(INF)
	await wait_process_frames(3)
	assert_signal_emit_count(goal, "wave_cleared", 1, "no banner after the last wave")
	assert_signal_emitted_with_parameters(goal, "finished", [true])
	assert_true(goal.is_finished())


func test_no_wave_pause_outside_an_arena() -> void:
	var room: Node2D = add_child_autofree(Node2D.new())
	assert_eq(ArenaObjective.get_wave_pause(room), 0.0)
	RoomObjective.attach(room, RoomObjective.create(RoomObjective.FLAME))
	assert_eq(ArenaObjective.get_wave_pause(room), 0.0, "only the arena pauses between waves")


# --- Task bar ---

func test_task_bar_shows_the_goal() -> void:
	var ui := _ui()
	var room: Node2D = add_child_autofree(Node2D.new())
	var goal := RoomObjective.attach(room, RoomObjective.create(RoomObjective.FLAME))
	goal.set_ratio(0.7)
	goal.set_label("Flamme")
	goal.set_time(27.0)
	await wait_process_frames(1)
	var bar := ui.get_objective_bar()
	assert_true(bar.visible, "found through node_added")
	assert_eq(bar.objective, goal)
	assert_eq(bar.get_title_text(), "Flamme hüten")
	assert_eq(bar.get_detail_text(), "Flamme")
	assert_eq(bar.get_value_text(), "0:27", "time wins over the share on the right")
	assert_true(bar.is_progress_shown())
	assert_lt(bar.get_global_rect().position.y, UiKit.px(10), "top centre")
	goal.clear_time()
	assert_eq(bar.get_value_text(), "70 %")
	goal.set_status("Der Dorfbewohner bleibt stehen")
	assert_eq(bar.get_status_text(), "Der Dorfbewohner bleibt stehen")


func test_danger_turns_the_bar_red_and_pulses() -> void:
	var ui := _ui()
	var room: Node2D = add_child_autofree(Node2D.new())
	var goal := RoomObjective.attach(room, RoomObjective.create(RoomObjective.FLAME))
	goal.auto_danger = true
	goal.set_ratio(0.2)
	await wait_process_frames(3)
	var bar := ui.get_objective_bar()
	assert_true(bar.is_danger_shown())
	var panel := bar.get_node("Bar") as Control
	assert_ne(panel.self_modulate, Color.WHITE, "red tint")
	await wait_seconds(0.15)
	assert_ne(panel.modulate, Color.WHITE, "pulsing")
	goal.set_ratio(0.8)
	assert_false(bar.is_danger_shown())
	assert_eq(panel.modulate, Color.WHITE)


func test_result_moment_then_the_bar_goes() -> void:
	var ui := _ui()
	var room: Node2D = add_child_autofree(Node2D.new())
	var goal := RoomObjective.attach(room, RoomObjective.create(RoomObjective.ESCORT))
	await wait_process_frames(1)
	var bar := ui.get_objective_bar()
	watch_signals(bar)
	goal.finish(true)
	assert_eq(bar.get_title_text(), "Geschafft!")
	await wait_seconds(ObjectiveBar.RESULT_TIME + ObjectiveBar.FADE_TIME + 0.4)
	assert_signal_emitted(bar, "done")
	assert_false(bar.visible)
	assert_false(bar.is_active())


func test_boss_bar_replaces_the_task_bar() -> void:
	var ui := _ui()
	var room: Node2D = add_child_autofree(Node2D.new())
	RoomObjective.attach(room, RoomObjective.create(RoomObjective.ARENA))
	await wait_process_frames(1)
	var bar := ui.get_objective_bar()
	assert_true(bar.visible)
	ui._boss_bar_root.visible = true
	ui._update_top_bars()
	assert_false(bar.visible, "the boss bar replaces it")
	ui.hide_boss_bar()
	assert_true(bar.visible, "and gives the place back")


func test_room_line_moves_below_a_bar_that_covers_it() -> void:
	var hud: Hud = add_child_autofree(Hud.new())
	hud.set_dungeon_mode(true)
	await wait_process_frames(1)
	var line := hud._room_box
	assert_eq(line.position.y, UiKit.px(Hud.ROOM_LINE_TOP), "same height as the task bar")
	var cover: Control = add_child_autofree(ColorRect.new())
	cover.add_to_group(Hud.TOP_CENTER_GROUP)
	cover.position = Vector2(line.global_position.x - 10.0, 0.0)
	cover.size = Vector2(line.size.x + 20.0, UiKit.px(30))
	await wait_process_frames(2)
	assert_gte(line.position.y, UiKit.px(30), "dodges the bar")
	cover.visible = false
	await wait_process_frames(2)
	assert_eq(line.position.y, UiKit.px(Hud.ROOM_LINE_TOP), "and comes back")


func test_room_line_names_the_mode() -> void:
	var hud: Hud = add_child_autofree(Hud.new())
	hud.set_dungeon_mode(true)
	hud.set_room_mode("Arena")
	assert_true(hud._room_detail.text.ends_with("Arena"), hud._room_detail.text)
	hud.set_room_mode("")
	assert_false(hud._room_detail.text.ends_with("Arena"))


func test_wave_banner_between_arena_waves() -> void:
	var ui := _ui()
	var room := _arena(2, 12)
	await wait_process_frames(2)
	var goal := ArenaObjective.attach_to(room)
	await wait_process_frames(1)
	goal.wave_cleared.emit(2, 2)
	var banner := ui.get_banner()
	assert_not_null(banner)
	assert_eq(banner.name, &"WaveBanner")
	assert_eq((banner.find_child("Title", true, false) as Label).text, "Welle 2/2")
	ui.show_banner("Welle 2/2", "Sie kommen …")
	assert_eq(ui.get_banner_queue_size(), 0, "the old wave banner of the dungeon is not shown twice")

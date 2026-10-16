extends GutTest
## P1-2 "Ziel und Weg zum Dungeon": until the first run of a world the village shows the goal line,
## a trail of soul lights from the spawn to the ruin and an arrow to the entrance; on the very first
## visit the chronicler says a few words (non-blocking card, once per world, old saves have seen it).
## Uses a test save file only.

const TEST_PATH := "user://test_village_guide.cfg"
const VILLAGE_SCENE := "res://world/village/village.tscn"
const GuideScript := preload("res://world/village/village_guide.gd")

var _old_locale: String
var _old_path: String


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	Loc.apply(&"de")
	_old_path = SaveManager.save_path


func before_each() -> void:
	SaveManager.save_path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	SaveManager.load_game()


func after_each() -> void:
	GameManager.clear_pause_reasons()


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)
	for suffix in ["", ".bak", ".v2.bak", ".v3.bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + suffix))
	SaveManager.save_path = _old_path
	SaveManager.load_game()


func _village() -> Village:
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	add_child_autofree(village)
	return village


func _opening_lines(ui: VillageUI) -> Array[String]:
	var lines: Array[String] = []
	var card := ui.get_opening()
	if card != null:
		for node in card.find_children("*", "Label", true, false):
			if node.is_in_group(&"village_opening_line"):
				lines.append((node as Label).text)
	return lines


# --- Fresh world: opening, goal, trail and arrow ---

func test_fresh_world_shows_opening_goal_and_way() -> void:
	var village := _village()
	var ui := village.ui
	assert_true(GuideScript.is_active(), "no run yet")
	assert_not_null(village.get_guide(), "trail and arrow to the dungeon")
	assert_not_null(ui.get_goal(), "goal line at the top")
	var goal_text := ui.get_goal().find_child("GoalText", true, false) as Label
	assert_not_null(goal_text)
	assert_eq(goal_text.text, "VILLAGE_GOAL_DESCEND", "the key: the label translates itself")
	assert_not_null(ui.get_opening(), "the chronicler speaks on the first visit")
	assert_eq(_opening_lines(ui).size(), Village.OPENING_LINES.size(), "2-3 sentences")
	assert_false(ui.is_dialog_open(), "the opening never blocks: no dialog, no pause")
	assert_false(get_tree().paused, "no global pause (Koop)")
	assert_false(SaveManager.has_seen(GuideScript.OPENING_SEEN_ID), "seen only once it closes")


func test_enter_closes_the_opening_once_per_world() -> void:
	var village := _village()
	var ui := village.ui
	ui._unhandled_input(MenuInput.key_event(KEY_ENTER))
	await wait_physics_frames(2)
	assert_null(ui.get_opening(), "Enter closes it")
	assert_true(SaveManager.has_seen(GuideScript.OPENING_SEEN_ID), "marked as seen")
	assert_not_null(ui.get_goal(), "the goal stays until the first run")
	# Stored in the save: the next visit has goal and way, but no opening.
	SaveManager.load_game()
	assert_true(SaveManager.has_seen(GuideScript.OPENING_SEEN_ID), "written to the file")
	var again := _village()
	assert_null(again.ui.get_opening(), "not again")
	assert_not_null(again.ui.get_goal())
	assert_not_null(again.get_guide())


func test_opening_closes_by_itself() -> void:
	var village := _village()
	var tween_time := VillageUI.OPENING_TIME + VillageUI.NOTICE_FADE * 2.0 + 0.3
	assert_lt(tween_time, 30.0)
	village.ui.close_opening()
	await wait_physics_frames(2)
	assert_null(village.ui.get_opening())
	assert_true(SaveManager.has_seen(GuideScript.OPENING_SEEN_ID))


func test_after_the_first_run_the_village_is_quiet() -> void:
	SaveManager.add_stat(StatsTracker.RUNS, 1)
	var village := _village()
	assert_false(GuideScript.is_active())
	assert_null(village.get_guide(), "no trail after the first run")
	assert_null(village.ui.get_goal(), "no goal line")
	assert_null(village.ui.get_opening(), "no opening")


func test_old_saves_have_seen_the_opening() -> void:
	# v2 without [seen] counts as "everything seen" (D-087); with runs the guide is gone as well.
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("[meta]\nversion=2\n[progress]\npermanent_gold=5\n[stats]\nruns=0\n")
	file.close()
	SaveManager.load_game()
	assert_true(SaveManager.has_seen(GuideScript.OPENING_SEEN_ID), "old save: seen")
	var village := _village()
	assert_null(village.ui.get_opening(), "old players are not greeted again")
	assert_not_null(village.ui.get_goal(), "without a run the goal still helps")
	file = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("[meta]\nversion=2\n[progress]\npermanent_gold=5\n[stats]\nruns=4\n")
	file.close()
	SaveManager.load_game()
	var veteran := _village()
	assert_null(veteran.get_guide())
	assert_null(veteran.ui.get_goal())


# --- Trail and arrow ---

func test_trail_runs_from_the_spawn_to_the_ruin() -> void:
	var village := _village()
	var guide := village.get_guide()
	var points := guide.get_points()
	var spawn := village.find_child("PlayerSpawn", true, false) as Node2D
	var entrance := village.get_node("Buildings/DungeonEntrance") as Node2D
	assert_eq(points[0], spawn.global_position, "starts at the spawn")
	assert_almost_eq(points[points.size() - 1].distance_to(entrance.global_position), GuideScript.TRAIL_END_OFFSET.length(), 0.1, "ends at the stairs")
	assert_gt(GuideScript.path_length(points), spawn.global_position.distance_to(entrance.global_position), "follows the paths, no straight line")
	assert_eq(GuideScript.point_at(points, 0.0), points[0])
	assert_eq(GuideScript.point_at(points, 1.0e6), points[points.size() - 1], "clamped at the end")
	var trail_layer := guide.get_node("TrailLayer") as CanvasLayer
	assert_true(trail_layer.follow_viewport_enabled, "drawn in the world, above the darkness")
	assert_gt(trail_layer.layer, 2, "above VisionOverlay")
	assert_lt(trail_layer.layer, 5, "below the HUD")


func test_arrow_points_to_the_entrance() -> void:
	var view := Vector2(1280, 720)
	var inner := GuideScript.inner_rect(view)
	assert_true(Rect2(Vector2.ZERO, view).encloses(inner))
	# In view: above the ruin, pointing down.
	var inside := GuideScript.place_pointer(Vector2(600, 400), inner, 150.0)
	assert_true(inside[2])
	assert_eq(inside[0], Vector2(600, 250), "over the doorway")
	assert_almost_eq(float(inside[1]), PI * 0.5, 0.001)
	# The ruin at the top of the view: the arrow stays below the goal line, still pointing down.
	var high := GuideScript.place_pointer(Vector2(600, inner.position.y + 20.0), inner, 150.0)
	assert_eq((high[0] as Vector2).y, inner.position.y, "kept inside")
	# Far above the screen (the start: spawn at the bottom, ruin at the top): top edge, pointing up.
	var above := GuideScript.place_pointer(Vector2(inner.get_center().x, -900), inner, 150.0)
	assert_false(above[2])
	assert_almost_eq((above[0] as Vector2).y, inner.position.y, 0.01, "at the top edge")
	assert_almost_eq(float(above[1]), -PI * 0.5, 0.001, "pointing up")
	# Up and to the right: stays inside.
	var corner := GuideScript.place_pointer(Vector2(5000, -5000), inner, 150.0)
	var spot := corner[0] as Vector2
	assert_true(inner.grow(0.01).has_point(spot), "always inside the free part of the screen")


func test_arrow_hides_while_a_dialog_is_open() -> void:
	var village := _village()
	var guide := village.get_guide()
	# Headless GUT steps physics frames; the guide's frame update is called directly.
	guide._process(0.016)
	assert_true(guide.is_pointer_shown())
	assert_eq(guide.process_mode, Node.PROCESS_MODE_ALWAYS, "updates while a dialog pauses the village")
	village.ui.close_opening()
	village.enter_building(&"forge")
	await wait_physics_frames(2)
	assert_true(village.ui.is_dialog_open())
	guide._process(0.016)
	assert_false(guide.is_pointer_shown(), "no arrow over a dialog")
	village.ui.get_intro_modal().finish()
	await wait_physics_frames(2)
	village.ui.get_building_modal().finish()
	await wait_physics_frames(2)
	guide._process(0.016)
	assert_true(guide.is_pointer_shown(), "back after the dialog")

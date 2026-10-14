extends SceneTree
## Preview of the boss intro in a real dungeon room: every boss tells its story (first encounter,
## with a shot of the hold-to-skip bar) and then says its short intro (later encounters), with
## screenshots while lines are typed and after the boss was released.
## Needs a window (not --headless); never touches the real save.
## Usage: godot --path . -s ui/boss_intro/boss_intro_preview.gd -- <output_dir>

const BOSSES := [
	"res://enemies/data/boss_bone_king.tres",
	"res://enemies/data/boss_slime_queen.tres",
	"res://enemies/data/boss_shadow_lord.tres",
	"res://enemies/data/boss_ember_golem.tres",
]
const SAVE_PATH := "user://boss_intro_preview_save.cfg"

var _out_dir := "user://boss_intro_preview"
var _failures: Array[String] = []


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	# A fresh save: no boss story heard yet (the real save is never loaded into this run's state).
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	root.get_node("SaveManager").save_path = SAVE_PATH
	root.get_node("SaveManager").load_game()
	change_scene_to_file("res://scenes/game.tscn")
	await _frames(30)
	var controller := current_scene.get_node("WorldController")
	controller.enter_dungeon()
	await _frames(60)
	var dungeon: Node = controller.get_world()
	var player: Node = controller.get_player()
	var room: Node = dungeon.get_room(1)
	for enemy in room.enemy_container.get_children():
		if enemy.has_method(&"is_dead"):
			enemy.health.take_damage(INF)
	await _settle()

	for path in BOSSES:
		await _preview(load(path), dungeon, room, player)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if _failures.is_empty():
		print("BOSS INTRO PREVIEW PASSED")
		quit(0)
	else:
		print("BOSS INTRO PREVIEW FAILED: ", _failures)
		quit(1)


func _preview(data: Resource, dungeon: Node, room: Node, player: Node) -> void:
	player.health.reset(99999.0)
	player.global_position = room.to_global(room.get_node("Tiles").get_floor_rect().get_center() + Vector2(0, 120))
	player.get_node("Camera2D").reset_smoothing()
	# Untyped: typed class checks are unreliable in -s scripts.
	var boss: Node = (load("res://enemies/enemy_base.tscn") as PackedScene).instantiate()
	boss.data = data
	boss.position = room.to_local(player.global_position) + Vector2(0, -200)
	boss.arena = room.get_arena()
	boss.apply_scaling(15, false)
	# Like the integrator hook: the first-encounter hint card waits until the intro is over.
	var ui: Node = dungeon.get_node("DungeonUI")
	ui.auto_enemy_hints = false
	room.enemy_container.add_child(boss)
	# Loaded at runtime: class names used directly here would compile before the autoloads exist.
	var rules: Script = load("res://enemies/boss_intro_rules.gd")
	var intro_script: Script = load("res://ui/boss_intro/boss_intro.gd")
	var name := String(data.id).trim_prefix("boss_")
	var save: Node = root.get_node("SaveManager")
	_check(not save.has_seen(rules.seen_key(data)), "%s story not heard yet" % name)

	# First encounter: the story, with a shot of the hold-to-skip bar on the second line.
	var story_done := [false]
	var story_finished: Signal = intro_script.play(boss, ui, intro_script.Kind.STORY)
	story_finished.connect(func() -> void: story_done[0] = true)
	var story: Node = ui.get_node_or_null("BossIntro")
	_check(story != null and story.is_story, "%s plays the story" % name)
	if story == null:
		return
	var last: int = story.lines.size() - 1
	await _until(func() -> bool: return _typed(story, 0, 0.7), 5.0)
	_shot("%s_story_1_first_line" % name)
	_check(boss.is_in_intro(), "%s is held during the story" % name)
	await _until(func() -> bool: return _typed(story, 1, 0.6), 8.0)
	story.press()
	story.begin_hold(&"interact")
	Input.action_press(&"interact")
	await _seconds(rules.HOLD_TO_SKIP_TIME * 0.55)
	_shot("%s_story_2_hold_to_skip" % name)
	Input.action_release(&"interact")
	story.end_hold()
	_check(is_instance_valid(story) and not story.was_skipped, "%s: a short hold does not skip" % name)
	await _until(func() -> bool: return _typed(story, last, 1.0), 25.0)
	_shot("%s_story_3_last_line" % name)
	await _until(func() -> bool: return story_done[0], 6.0)
	_check(story_done[0], "%s story finished" % name)
	_check(save.has_seen(rules.seen_key(data)), "%s story marked as heard" % name)
	_check(not boss.is_in_intro(), "%s fights after the story" % name)

	# Every later encounter: the short intro.
	await _seconds(0.4)
	var short_done := [false]
	var short_finished: Signal = intro_script.play(boss, ui)
	short_finished.connect(func() -> void:
		short_done[0] = true
		ui.auto_enemy_hints = true
		ui.notice_enemy(boss))
	var short: Node = ui.get_node_or_null("BossIntro")
	_check(short != null and not short.is_story, "%s: short intro once the story was heard" % name)
	if short != null:
		await _until(func() -> bool: return _typed(short, short.lines.size() - 1, 0.8), 6.0)
		_shot("%s_short_1_line" % name)
	await _until(func() -> bool: return short_done[0], 6.0)
	_check(short_done[0], "%s short intro finished" % name)
	_check(not boss.is_in_intro(), "%s fights after the short intro" % name)
	await _seconds(0.3)
	_shot("%s_fight" % name)
	boss.health.take_damage(INF)
	await _seconds(1.5)
	await _settle()


## True when the intro shows line index with at least share of its letters (false once freed).
func _typed(intro: Node, index: int, share: float) -> bool:
	if not is_instance_valid(intro) or intro.line_index != index:
		return false
	return intro.visible_characters >= ceili(intro.get_line().length() * share)


## Waits (game time) until condition is true or timeout seconds passed.
func _until(condition: Callable, timeout: float) -> void:
	var time := 0.0
	while not condition.call() and time < timeout:
		await _seconds(0.02)
		time += 0.02


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		print("FAIL: ", message)


func _shot(shot_name: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(_out_dir.path_join(shot_name + ".png"))
	print("saved ", shot_name)


## Closes dialogs that pop up with a delay (D-070) until none is left.
func _settle() -> void:
	for i in 6:
		_close_modals(root)
		await _seconds(0.4)


func _close_modals(node: Node) -> void:
	for child in node.get_children():
		if child.get_script() != null and child.get_script().get_global_name() == &"Modal":
			for button in _buttons(child):
				if button.text in ["Wählen", "Schließen"]:
					button.pressed.emit()
					break
			if child.cancel_allowed:
				child.finish(child.cancel_result)
		else:
			_close_modals(child)


func _buttons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	for child in node.get_children():
		if child is Button:
			result.append(child)
		result.append_array(_buttons(child))
	return result


## Game time, like the intro itself: on loading hitches Godot clamps the frame delta, so a
## real-time timer would run ahead of the game.
func _seconds(duration: float) -> void:
	await create_timer(duration, true, false, false).timeout


func _frames(count: int) -> void:
	for i in count:
		await process_frame

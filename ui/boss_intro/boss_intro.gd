class_name BossIntro
extends Node
## Logic of the boss intro (BI1, D-098): before the fight the boss speaks a few threatening lines,
## letter by letter, with a babbling voice (one meaningless syllable sound per syllable, the text
## itself is readable German). There is no global pause (multiplayer guard rails): the boss itself
## stays passive and invulnerable (Enemy.begin_intro) until the intro ends; the caller locks the
## player's movement meanwhile (DungeonManager._announce_boss, Player.set_input_locked), the skip
## keys below still reach this node. Presentation (dialog, babble sounds, roar, camera) lives in BossIntroView and only
## listens to the signals below. Timings and line choice: BossIntroRules.
##
## Two kinds (Kind.AUTO decides with the save):
## - STORY, the first encounter with this boss per save: all story lines with a longer hold.
##   Tap (E, Space, left click, Enter) = show the typed line at once, tap again = next line;
##   hold a key HOLD_TO_SKIP_TIME = skip the whole intro. Marked as seen (and saved) once it ran
##   to the end or was skipped.
## - SHORT, every later encounter: 1-2 lines; a tap skips the whole intro (as before).
## skip() always ends the whole intro (smoke test, tools).
##
## Usage:  await BossIntro.play(boss, ui_root)   # resumes when the boss is free to fight
## Without intro data (EnemyData.intro_lines / intro_story) "finished" comes right away (next frame).

signal line_started(index: int, text: String)
## The first count characters of line index are visible.
signal characters_revealed(index: int, count: int)
## A babbled syllable starts at char_index of line index; variant picks babble_<voice>_<variant>.
signal syllable_spoken(index: int, char_index: int, variant: int)
## Story intro: share 0..1 of HOLD_TO_SKIP_TIME a skip key is held (0 again on release).
signal hold_progress(ratio: float)
## The last line is over or the intro was skipped: roar moment, the overlay fades out.
signal ending(skipped: bool)
## The boss is released and fights. Emitted exactly once (unless the intro is freed early).
signal finished

enum Step { IDLE, FADE_IN, TYPING, HOLD, FADE_OUT, DONE }
## AUTO: STORY on the first encounter per save (and when the boss has a story), else SHORT.
enum Kind { AUTO, STORY, SHORT }

## E, Space, left click and Enter (ui_accept also covers Space and keypad Enter).
const SKIP_ACTIONS: Array[StringName] = [&"interact", &"dash", &"attack", &"ui_accept"]
## Guard against endless loops when a huge delta arrives.
const MAX_STEPS_PER_ADVANCE := 64

var boss: Enemy = null
var data: EnemyData = null
var lines := PackedStringArray()
## True for the long first-encounter intro.
var is_story := false
var step := Step.IDLE
var line_index := -1
var visible_characters := 0
## Seconds since start().
var elapsed := 0.0
var was_skipped := false

var _step_time := 0.0
var _reveal_times := PackedFloat32Array()
var _syllables := PackedInt32Array()
var _next_syllable := 0
var _duration := 0.0
var _speed := 1.0
var _hold := BossIntroRules.LINE_HOLD
var _finished := false
## Skip key currently held (story intro), empty = none.
var _hold_action: StringName = &""
var _held_time := 0.0


## Creates the intro for boss, adds it (and its view) below ui_root and starts it.
## Returns the "finished" signal, so callers can simply await it.
static func play(target: Enemy, ui_root: Node, kind := Kind.AUTO) -> Signal:
	var intro := create(target, kind)
	var parent: Node = ui_root
	if parent == null or not parent.is_inside_tree():
		if target != null and is_instance_valid(target) and target.is_inside_tree():
			parent = target
		else:
			parent = (Engine.get_main_loop() as SceneTree).root
	parent.add_child(intro)
	if intro.has_lines():
		intro.add_child(BossIntroView.new())
	intro.start()
	return intro.finished


## The intro node without view and without starting it (tests, custom presentation).
static func create(target: Enemy, kind := Kind.AUTO) -> BossIntro:
	var intro := BossIntro.new()
	intro.name = "BossIntro"
	if target != null and is_instance_valid(target) and target.data != null:
		intro.boss = target
		intro.data = target.data
		if kind == Kind.AUTO:
			kind = Kind.STORY if is_first_encounter(target.data) else Kind.SHORT
		intro.is_story = kind == Kind.STORY and BossIntroRules.has_story(target.data)
		intro.lines = BossIntroRules.pick_lines(target.data, target.get_boss_tier(), intro.is_story, _encounter())
	return intro


## True when the boss has intro data (the intro will show something).
static func has_intro_for(target: Enemy) -> bool:
	return target != null and is_instance_valid(target) and BossIntroRules.has_intro(target.data)


## True while this save has not heard the boss's story yet.
static func is_first_encounter(boss_data: EnemyData) -> bool:
	return BossIntroRules.has_story(boss_data) and not SaveManager.has_seen(BossIntroRules.seen_key(boss_data))


## Runs started so far (chronicle statistic): later encounters change their line with every run.
static func _encounter() -> int:
	return int(SaveManager.get_stat(StatsTracker.RUNS))


func _init() -> void:
	# The intro freezes with menus (Esc), but never pauses the game itself.
	process_mode = Node.PROCESS_MODE_PAUSABLE


func has_lines() -> bool:
	return not lines.is_empty()


func is_running() -> bool:
	return step in [Step.FADE_IN, Step.TYPING, Step.HOLD, Step.FADE_OUT]


func is_finished() -> bool:
	return _finished


## Planned duration from the first fade to the released boss (without paging or skipping).
func get_duration() -> float:
	return _duration


func get_line() -> String:
	return lines[line_index] if line_index >= 0 and line_index < lines.size() else ""


func start() -> void:
	if step != Step.IDLE:
		return
	if lines.is_empty() or boss == null or not is_instance_valid(boss) or boss.is_dead():
		step = Step.DONE
		_finish.call_deferred()
		return
	_speed = data.intro_type_speed
	_hold = BossIntroRules.line_hold(is_story)
	_duration = BossIntroRules.total_duration(lines, _speed, is_story)
	# The safety time grows with the intro: the story intro holds the boss longer.
	boss.begin_intro(_duration + BossIntroRules.SAFETY_MARGIN)
	boss.died.connect(_on_boss_died, CONNECT_ONE_SHOT)
	step = Step.FADE_IN
	_step_time = 0.0


## Ends the whole intro early (roar, fade out). Ignored during SKIP_GRACE and after the ending began.
func skip() -> bool:
	if not _accepts_input():
		return false
	was_skipped = true
	_begin_ending()
	return true


## A tap on a skip key. Short intro: skips it. Story intro: a line still being typed appears at once,
## a complete line goes on to the next one (the last one to the ending). False when ignored.
func press() -> bool:
	if not _accepts_input():
		return false
	if not is_story:
		return skip()
	match step:
		Step.FADE_IN:
			_step_time = 0.0
			_start_line(0)
			_show_whole_line()
		Step.TYPING:
			_show_whole_line()
		Step.HOLD:
			_next_line()
	return true


## Story intro: a skip key went down (after press()); held HOLD_TO_SKIP_TIME it skips everything.
func begin_hold(action: StringName) -> void:
	if not is_story or not _accepts_input():
		return
	_hold_action = action
	_held_time = 0.0
	hold_progress.emit(0.0)


func end_hold() -> void:
	if _hold_action == &"":
		return
	_hold_action = &""
	_held_time = 0.0
	hold_progress.emit(0.0)


func is_holding() -> bool:
	return _hold_action != &""


func _accepts_input() -> bool:
	return step in [Step.FADE_IN, Step.TYPING, Step.HOLD] and elapsed >= BossIntroRules.SKIP_GRACE


func _process(delta: float) -> void:
	# Releases can get lost (focus change, consumed by a menu): check the key itself.
	if _hold_action != &"" and InputMap.has_action(_hold_action) and not Input.is_action_pressed(_hold_action):
		end_hold()
	advance(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not is_running() or event.is_echo():
		return
	for action in SKIP_ACTIONS:
		if not InputMap.has_action(action):
			continue
		if event.is_action_released(action) and action == _hold_action:
			end_hold()
			return
		if event.is_action_pressed(action) and press():
			begin_hold(action)
			get_viewport().set_input_as_handled()
			return


## Steps the intro by delta seconds (called every frame; tests call it directly).
func advance(delta: float) -> void:
	if not is_running():
		return
	if boss == null or not is_instance_valid(boss):
		_finish()
		return
	elapsed += delta
	_step_time += delta
	if _hold_action != &"" and step != Step.FADE_OUT:
		_held_time += delta
		hold_progress.emit(minf(1.0, _held_time / BossIntroRules.HOLD_TO_SKIP_TIME))
		if _held_time >= BossIntroRules.HOLD_TO_SKIP_TIME:
			end_hold()
			skip()
			return
	for i in MAX_STEPS_PER_ADVANCE:
		if not _process_step():
			break


## One transition at most; true when the step changed and the rest of the time should carry on.
func _process_step() -> bool:
	match step:
		Step.FADE_IN:
			if _step_time >= BossIntroRules.FADE_IN_TIME:
				_step_time -= BossIntroRules.FADE_IN_TIME
				_start_line(0)
				return true
		Step.TYPING:
			_reveal()
			var line := get_line()
			var typing := BossIntroRules.typing_time(line, _speed)
			if visible_characters >= line.length() and _step_time >= typing:
				_step_time -= typing
				step = Step.HOLD
				return true
		Step.HOLD:
			if _step_time >= _hold:
				_step_time -= _hold
				_next_line()
				return true
		Step.FADE_OUT:
			if _step_time >= BossIntroRules.FADE_OUT_TIME:
				_finish()
	return false


func _start_line(index: int) -> void:
	line_index = index
	visible_characters = 0
	_reveal_times = BossIntroRules.reveal_times(get_line(), _speed)
	_syllables = BossIntroRules.syllable_starts(get_line())
	_next_syllable = 0
	step = Step.TYPING
	_keep_boss_music_held()
	line_started.emit(index, get_line())


func _next_line() -> void:
	if line_index + 1 < lines.size():
		_start_line(line_index + 1)
	else:
		_begin_ending()


## Paged by the player: the whole line at once (no babble for the rest), then the full hold.
func _show_whole_line() -> void:
	visible_characters = get_line().length()
	_next_syllable = _syllables.size()
	characters_revealed.emit(line_index, visible_characters)
	step = Step.HOLD
	_step_time = 0.0


func _reveal() -> void:
	var line := get_line()
	var before := visible_characters
	while visible_characters < line.length() and _reveal_times[visible_characters] <= _step_time:
		var char_index := visible_characters
		visible_characters += 1
		if _next_syllable < _syllables.size() and _syllables[_next_syllable] == char_index:
			_next_syllable += 1
			var syllable := BossIntroRules.syllable_at(line, char_index)
			syllable_spoken.emit(line_index, char_index, BossIntroRules.babble_variant(syllable, data.intro_voice_variants))
	if visible_characters != before:
		characters_revealed.emit(line_index, visible_characters)


## The MusicPlayer holds the boss track while a BossIntro is in the tree, but starts it on its own
## after MusicPlayer.BOSS_HOLD_MAX_TIME. The story intro can take longer, so every new line renews
## the hold (public hook, same group call the MusicPlayer documents). Short intros do not need it.
func _keep_boss_music_held() -> void:
	if is_story and line_index > 0 and is_inside_tree():
		get_tree().call_group(MusicPlayer.GROUP, &"hold_boss_music")


func _begin_ending() -> void:
	if step == Step.TYPING and line_index >= 0:
		visible_characters = get_line().length()
		characters_revealed.emit(line_index, visible_characters)
	end_hold()
	step = Step.FADE_OUT
	_step_time = 0.0
	if is_story:
		_mark_story_seen()
	ending.emit(was_skipped)


## Heard to the end or skipped: later encounters use the short intro (saved right away, like the
## village explanations). Only the public SaveManager API.
func _mark_story_seen() -> void:
	if SaveManager.mark_seen(BossIntroRules.seen_key(data)):
		SaveManager.save_game()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	step = Step.DONE
	_release_boss()
	finished.emit()
	if is_inside_tree():
		queue_free()


func _release_boss() -> void:
	if boss != null and is_instance_valid(boss):
		if boss.died.is_connected(_on_boss_died):
			boss.died.disconnect(_on_boss_died)
		boss.end_intro()


func _on_boss_died(_enemy: Enemy) -> void:
	_finish()


func _exit_tree() -> void:
	# Freed early (room unloaded, run over): never leave the boss frozen. No "finished" here, the
	# caller's world is going away.
	if not _finished:
		_release_boss()

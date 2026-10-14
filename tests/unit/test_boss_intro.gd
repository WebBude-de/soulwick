extends GutTest
## Boss intro (BI1, D-098): story lines (first encounter per save) and short variants (later
## encounters) plus babble voice per boss, timing rules, the passive and invulnerable boss while the
## intro runs, paging and skipping, the seen flag, safety timeout and the full intro with its view.

const ENEMY_SCENE_PATH := "res://enemies/enemy_base.tscn"
const PLAYER_SCENE_PATH := "res://player/player.tscn"
const TEST_SAVE_PATH := "user://test_boss_intro.cfg"
const BOSSES := [
	"res://enemies/data/boss_bone_king.tres",
	"res://enemies/data/boss_slime_queen.tres",
	"res://enemies/data/boss_shadow_lord.tres",
	"res://enemies/data/boss_ember_golem.tres",
]
const STEP := 1.0 / 60.0
## Short enough to read while it is typed (one or two rows in the mockup dialog).
const MAX_LINE_LENGTH := 42
const MIN_STORY_LINES := 4
const MAX_STORY_LINES := 7
const MIN_REPEAT_VARIANTS := 3

var _old_save_path: String


## Stub in the music group: counts the renewed boss music holds.
class MusicStub extends Node:
	var holds := 0

	func _init() -> void:
		add_to_group(MusicPlayer.GROUP)

	func hold_boss_music() -> void:
		holds += 1

	func release_boss_music() -> void:
		pass


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH


func before_each() -> void:
	# Every test starts with a fresh save: no boss story heard yet.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.load_game()


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func after_each() -> void:
	for node in get_children():
		if node is Enemy or node is Projectile or node is Blast or node is BossIntro or node is MusicStub:
			node.queue_free()


func _spawn(path: String, room := 15) -> Enemy:
	var enemy: Enemy = (load(ENEMY_SCENE_PATH) as PackedScene).instantiate()
	enemy.data = load(path)
	enemy.apply_scaling(room, false)
	add_child_autofree(enemy)
	return enemy


## Steps the intro until it is finished (or limit seconds). Returns the elapsed time.
func _run(intro: BossIntro, limit := 40.0) -> float:
	var time := 0.0
	while not intro.is_finished() and time < limit:
		intro.advance(STEP)
		time += STEP
	return time


func _story_intro(path: String) -> BossIntro:
	var boss := _spawn(path)
	await wait_physics_frames(1)
	var intro := BossIntro.create(boss, BossIntro.Kind.STORY)
	intro.start()
	return intro


# --- Data ---

func test_every_boss_has_story_variants_and_a_voice() -> void:
	for path in BOSSES:
		var data: EnemyData = load(path)
		assert_true(BossIntroRules.has_intro(data), "%s has an intro" % data.id)
		assert_true(BossIntroRules.has_story(data), "%s has a story" % data.id)
		assert_between(BossIntroRules.story_lines(data).size(), MIN_STORY_LINES, MAX_STORY_LINES, "%s: story length" % data.id)
		assert_gte(data.intro_lines.size(), MIN_REPEAT_VARIANTS, "%s: short variants" % data.id)
		for variant in data.intro_lines:
			var parts := variant.split(BossIntroRules.LINE_SEPARATOR, false)
			assert_between(parts.size(), 1, BossIntroRules.MAX_REPEAT_LINES, "'%s': 1-2 sentences" % variant)
		assert_ne(data.intro_voice, &"", "%s has a voice" % data.id)
		for variant in range(1, data.intro_voice_variants + 1):
			var sound := BossIntroRules.babble_sound(data, variant)
			assert_true(ResourceLoader.exists("res://audio/sfx/%s.wav" % sound), "%s exists" % sound)


func test_lines_are_short_readable_and_without_numbers() -> void:
	var digits := RegEx.new()
	digits.compile("[0-9]")
	var letters := RegEx.new()
	letters.compile("\\p{L}")
	for path in BOSSES:
		var data: EnemyData = load(path)
		var lines := BossIntroRules.story_lines(data)
		for variant in data.intro_lines:
			lines.append_array(variant.split(BossIntroRules.LINE_SEPARATOR, false))
		for line in lines:
			assert_lte(line.length(), MAX_LINE_LENGTH, "'%s' is short" % line)
			assert_null(digits.search(line), "'%s' has no numbers" % line)
			assert_not_null(letters.search(line), "'%s' has words" % line)
			assert_false(line.contains("["), "'%s' has no BBCode" % line)


func test_short_intro_stays_short_and_story_takes_longer() -> void:
	for path in BOSSES:
		var data: EnemyData = load(path)
		for tier in 4:
			for encounter in 5:
				var lines := BossIntroRules.pick_lines(data, tier, false, encounter)
				assert_between(lines.size(), 1, BossIntroRules.MAX_REPEAT_LINES)
				var duration := BossIntroRules.total_duration(lines, data.intro_type_speed)
				assert_between(duration, 2.5, 5.5, "%s tier %d run %d: %.2f s" % [data.id, tier, encounter, duration])
		var story := BossIntroRules.pick_lines(data, 0, true)
		var story_time := BossIntroRules.total_duration(story, data.intro_type_speed, true)
		assert_between(story_time, 8.0, 14.0, "%s story: %.2f s" % [data.id, story_time])


func test_normal_enemies_and_champions_have_no_intro() -> void:
	for path in ["res://enemies/data/skeleton.tres", "res://enemies/data/slime.tres", "res://enemies/data/necromancer.tres"]:
		var data: EnemyData = load(path)
		assert_false(BossIntroRules.has_intro(data), path)
		assert_false(BossIntroRules.has_story(data), path)
		assert_false(BossIntroRules.has_intro(ChampionRules.make_champion_data(data)), "champion of " + path)
	assert_false(BossIntroRules.has_intro(null))


# --- Rules ---

func test_short_variant_is_deterministic_and_moves_on() -> void:
	var data := EnemyData.new()
	data.intro_lines = PackedStringArray(["a|b", "c", " ", "d|e|f"])
	assert_eq(BossIntroRules.repeat_lines(data, 0, 0), PackedStringArray(["a", "b"]), "| splits into two lines")
	assert_eq(BossIntroRules.repeat_lines(data, 1, 0), PackedStringArray(["c"]), "next tier, next variant")
	assert_eq(BossIntroRules.repeat_lines(data, 0, 1), PackedStringArray(["c"]), "next run, next variant")
	assert_eq(BossIntroRules.repeat_lines(data, 2, 0), PackedStringArray(["d", "e"]), "blank variants ignored, at most two lines")
	assert_eq(BossIntroRules.repeat_lines(data, 1, 2), PackedStringArray(["a", "b"]), "wraps around")
	assert_eq(BossIntroRules.repeat_lines(data, 1, 1), BossIntroRules.repeat_lines(data, 1, 1), "same input, same lines")


func test_story_or_short_lines() -> void:
	var data := EnemyData.new()
	data.intro_story = PackedStringArray(["s1", "s2", "s3"])
	data.intro_lines = PackedStringArray(["r1|r2"])
	assert_eq(BossIntroRules.pick_lines(data, 0, true), PackedStringArray(["s1", "s2", "s3"]))
	assert_eq(BossIntroRules.pick_lines(data, 3, false, 7), PackedStringArray(["r1", "r2"]))
	data.intro_lines = PackedStringArray()
	assert_eq(BossIntroRules.pick_lines(data, 0, false), PackedStringArray(["s1", "s2"]), "no variants: the first story lines")
	data.intro_story = PackedStringArray()
	data.intro_lines = PackedStringArray(["r"])
	assert_false(BossIntroRules.has_story(data))
	assert_eq(BossIntroRules.pick_lines(data, 0, true), PackedStringArray(["r"]), "no story: the short intro")


func test_seen_key_per_boss() -> void:
	assert_eq(BossIntroRules.seen_key(load(BOSSES[0])), &"boss_intro_bone_king")
	assert_eq(BossIntroRules.seen_key(load(BOSSES[3])), &"boss_intro_ember_golem")
	assert_eq(BossIntroRules.seen_key(null), &"")


func test_story_hold_is_longer() -> void:
	assert_gt(BossIntroRules.line_hold(true), BossIntroRules.line_hold(false))
	var lines := PackedStringArray(["abc", "de"])
	var gap := BossIntroRules.total_duration(lines, 1.0, true) - BossIntroRules.total_duration(lines, 1.0, false)
	assert_almost_eq(gap, 2.0 * (BossIntroRules.STORY_LINE_HOLD - BossIntroRules.LINE_HOLD), 0.0001)


func test_letters_appear_one_by_one_with_pauses_after_punctuation() -> void:
	var c := BossIntroRules.CHAR_INTERVAL
	var p := BossIntroRules.PUNCTUATION_PAUSE
	var times := BossIntroRules.reveal_times("a. b")
	assert_eq(times.size(), 4)
	assert_almost_eq(times[0], 0.0, 0.0001)
	assert_almost_eq(times[1], c, 0.0001)
	assert_almost_eq(times[2], 2.0 * c + p, 0.0001, "pause after the full stop")
	assert_almost_eq(times[3], 3.0 * c + p, 0.0001)
	var dots := BossIntroRules.reveal_times("a...b")
	assert_almost_eq(dots[4], 4.0 * c + p, 0.0001, "a group of dots pauses once")
	assert_almost_eq(BossIntroRules.typing_time("ab"), 2.0 * c, 0.0001)
	var slow := BossIntroRules.reveal_times("a. b", 0.5)
	assert_almost_eq(slow[3], 2.0 * (3.0 * c + p), 0.0001, "half speed, twice the time")
	assert_almost_eq(BossIntroRules.typing_time("ab", 2.0), c, 0.0001)


func test_syllables_and_their_sounds() -> void:
	var line := "Krrak … xarrem!"  # Syllables only drive the babble sound.
	assert_eq(BossIntroRules.syllable_starts(line), PackedInt32Array([0, 3, 8, 11]))
	assert_eq(BossIntroRules.syllable_at(line, 0), "Krr")
	assert_eq(BossIntroRules.syllable_at(line, 3), "ak")
	assert_eq(BossIntroRules.syllable_starts("Tek'kuul"), PackedInt32Array([0, 4, 7]), "apostrophes split")
	for syllable in ["Krr", "ak", "xar", "Blo", "ss"]:
		var variant := BossIntroRules.babble_variant(syllable, 6)
		assert_between(variant, 1, 6)
		assert_eq(variant, BossIntroRules.babble_variant(syllable.to_upper(), 6), "same syllable, same sound")
	var data: EnemyData = load(BOSSES[0])
	assert_eq(BossIntroRules.babble_sound(data, 3), &"babble_bone_king_3")
	assert_eq(BossIntroRules.babble_sound(data, 99), &"babble_bone_king_6", "clamped")
	assert_eq(BossIntroRules.babble_sound(EnemyData.new(), 1), &"", "no voice, no sound")


# --- Boss hold ---

func test_boss_stays_passive_and_invulnerable_during_the_intro() -> void:
	var player: Player = add_child_autofree((load(PLAYER_SCENE_PATH) as PackedScene).instantiate())
	var boss := _spawn(BOSSES[0])
	boss.global_position = player.global_position + Vector2(50, 0)
	watch_signals(boss)
	boss.begin_intro(10.0)
	var start := boss.global_position
	var health := player.health.get_health()
	await wait_physics_frames(60)
	assert_true(boss.is_in_intro())
	assert_true(boss.hurtbox.is_invulnerable(), "invulnerable during the intro")
	assert_signal_not_emitted(boss, "ability_used")
	assert_almost_eq(boss.global_position.distance_to(start), 0.0, 0.5, "stands still")
	assert_eq(player.health.get_health(), health, "no attack during the intro")
	var hit := DamageData.new()
	hit.amount = 5.0
	assert_true(boss.hurtbox.receive_hit(hit).blocked, "hits are blocked")
	boss.end_intro()
	assert_false(boss.is_in_intro())
	assert_false(boss.hurtbox.is_invulnerable())
	assert_signal_emit_count(boss, "intro_ended", 1)
	boss.end_intro()
	assert_signal_emit_count(boss, "intro_ended", 1, "only once")


func test_boss_frees_itself_after_the_safety_timeout() -> void:
	var boss := _spawn(BOSSES[1], 30)
	watch_signals(boss)
	boss.begin_intro(0.2)
	await wait_physics_frames(30)
	assert_false(boss.is_in_intro())
	assert_false(boss.hurtbox.is_invulnerable())
	assert_signal_emitted(boss, "intro_ended")


func test_safety_time_grows_with_the_story() -> void:
	var intro: BossIntro = await _story_intro(BOSSES[2])
	assert_true(intro.is_story)
	assert_gt(intro.get_duration(), 10.0)
	assert_almost_eq(intro.boss._intro_time_left, intro.get_duration() + BossIntroRules.SAFETY_MARGIN, 0.001)
	intro.free()


# --- Sequencer ---

func test_first_encounter_tells_the_story_later_ones_are_short() -> void:
	var boss := _spawn(BOSSES[0])
	await wait_physics_frames(1)
	assert_true(BossIntro.is_first_encounter(boss.data))
	var first := BossIntro.create(boss)
	assert_true(first.is_story, "fresh save: story")
	assert_eq(first.lines, BossIntroRules.story_lines(boss.data))
	first.free()
	SaveManager.mark_seen(BossIntroRules.seen_key(boss.data))
	assert_false(BossIntro.is_first_encounter(boss.data))
	var later := BossIntro.create(boss)
	assert_false(later.is_story, "story heard: short intro")
	assert_between(later.lines.size(), 1, BossIntroRules.MAX_REPEAT_LINES)
	later.free()
	var other := _spawn(BOSSES[1])
	await wait_physics_frames(1)
	assert_true(BossIntro.is_first_encounter(other.data), "flags are per boss")


func test_short_intro_plays_all_lines_and_releases_the_boss() -> void:
	var boss := _spawn(BOSSES[2], 45)
	await wait_physics_frames(1)
	var intro := BossIntro.create(boss, BossIntro.Kind.SHORT)
	watch_signals(intro)
	intro.start()
	assert_true(intro.is_running())
	assert_false(intro.is_story)
	assert_true(boss.is_in_intro())
	var lines := intro.lines.duplicate()
	var duration := intro.get_duration()
	assert_almost_eq(duration, BossIntroRules.total_duration(lines, boss.data.intro_type_speed), 0.001)
	var time := _run(intro)
	assert_true(intro.is_finished())
	assert_almost_eq(time, duration, 0.05, "plays for its planned duration")
	assert_signal_emit_count(intro, "line_started", lines.size())
	assert_signal_emit_count(intro, "ending", 1)
	assert_signal_emit_count(intro, "finished", 1)
	assert_signal_emitted_with_parameters(intro, "ending", [false])
	var syllables := 0
	for line in lines:
		syllables += BossIntroRules.syllable_starts(line).size()
	assert_signal_emit_count(intro, "syllable_spoken", syllables, "one babble per syllable")
	assert_false(boss.is_in_intro(), "boss released")
	assert_false(boss.hurtbox.is_invulnerable())
	assert_false(SaveManager.has_seen(BossIntroRules.seen_key(boss.data)), "a short intro marks nothing")
	intro.free()


func test_story_runs_to_the_end_and_is_marked_seen() -> void:
	var intro: BossIntro = await _story_intro(BOSSES[3])
	watch_signals(intro)
	var key := BossIntroRules.seen_key(intro.data)
	var lines := intro.lines.duplicate()
	assert_between(lines.size(), MIN_STORY_LINES, MAX_STORY_LINES)
	var time := _run(intro)
	assert_true(intro.is_finished())
	assert_almost_eq(time, intro.get_duration(), 0.05, "plays for its planned duration")
	assert_signal_emit_count(intro, "line_started", lines.size())
	assert_signal_emitted_with_parameters(intro, "ending", [false])
	assert_true(SaveManager.has_seen(key), "heard to the end")
	assert_eq(SaveManager.load_game(), OK, "and saved")
	assert_true(SaveManager.has_seen(key), "survives a reload")
	intro.free()


func test_story_tap_shows_the_line_then_pages() -> void:
	var intro: BossIntro = await _story_intro(BOSSES[0])
	watch_signals(intro)
	intro.advance(0.1)
	assert_false(intro.press(), "ignored during the grace time")
	intro.advance(BossIntroRules.SKIP_GRACE)
	assert_eq(intro.line_index, 0)
	assert_eq(intro.step, BossIntro.Step.TYPING)
	assert_lt(intro.visible_characters, intro.get_line().length(), "still typing")
	assert_true(intro.press())
	assert_eq(intro.visible_characters, intro.get_line().length(), "first tap: whole line at once")
	assert_eq(intro.step, BossIntro.Step.HOLD)
	assert_eq(intro.line_index, 0, "still the same line")
	intro.advance(BossIntroRules.STORY_LINE_HOLD * 0.5)
	assert_eq(intro.line_index, 0, "the full hold after the tap")
	assert_true(intro.press())
	assert_eq(intro.line_index, 1, "second tap: next line")
	assert_eq(intro.step, BossIntro.Step.TYPING)
	assert_eq(intro.visible_characters, 0)
	assert_false(intro.is_finished())
	# Page through the rest: two taps per line, the last one starts the ending.
	for i in intro.lines.size() * 2:
		if intro.step == BossIntro.Step.FADE_OUT:
			break
		intro.press()
	assert_eq(intro.step, BossIntro.Step.FADE_OUT)
	assert_signal_emitted_with_parameters(intro, "ending", [false])
	assert_false(intro.was_skipped, "paged to the end, not skipped")
	assert_true(SaveManager.has_seen(BossIntroRules.seen_key(intro.data)))
	intro.advance(BossIntroRules.FADE_OUT_TIME + 0.01)
	assert_true(intro.is_finished())
	assert_false(intro.boss.is_in_intro())
	intro.free()


func test_story_hold_skips_everything() -> void:
	var intro: BossIntro = await _story_intro(BOSSES[1])
	watch_signals(intro)
	intro.advance(BossIntroRules.SKIP_GRACE + 0.05)
	assert_true(intro.press())
	intro.begin_hold(&"interact")
	assert_true(intro.is_holding())
	intro.advance(BossIntroRules.HOLD_TO_SKIP_TIME * 0.5)
	assert_signal_emitted(intro, "hold_progress")
	assert_false(intro.was_skipped, "not held long enough yet")
	intro.end_hold()
	assert_false(intro.is_holding())
	intro.advance(BossIntroRules.HOLD_TO_SKIP_TIME * 0.7)
	assert_false(intro.was_skipped, "releasing resets the hold")
	intro.begin_hold(&"interact")
	for i in ceili(BossIntroRules.HOLD_TO_SKIP_TIME / STEP) + 1:
		intro.advance(STEP)
	assert_true(intro.was_skipped, "held long enough: whole intro skipped")
	assert_signal_emitted_with_parameters(intro, "ending", [true])
	assert_true(SaveManager.has_seen(BossIntroRules.seen_key(intro.data)), "skipped counts as seen")
	intro.advance(BossIntroRules.FADE_OUT_TIME + 0.01)
	assert_true(intro.is_finished())
	intro.free()


func test_hold_is_ignored_in_the_short_intro() -> void:
	var boss := _spawn(BOSSES[1])
	await wait_physics_frames(1)
	var intro := BossIntro.create(boss, BossIntro.Kind.SHORT)
	intro.start()
	intro.advance(BossIntroRules.SKIP_GRACE + 0.05)
	intro.begin_hold(&"interact")
	assert_false(intro.is_holding())
	assert_true(intro.press(), "a tap skips the short intro")
	assert_true(intro.was_skipped)
	intro.free()


func test_skip_ends_the_whole_story_but_not_during_the_grace_time() -> void:
	var intro: BossIntro = await _story_intro(BOSSES[3])
	watch_signals(intro)
	intro.advance(0.1)
	assert_false(intro.skip(), "too early")
	intro.advance(BossIntroRules.SKIP_GRACE)
	assert_true(intro.skip(), "smoke test and tools skip everything")
	assert_true(intro.was_skipped)
	assert_signal_emitted_with_parameters(intro, "ending", [true])
	assert_false(intro.skip(), "ending already running")
	assert_true(SaveManager.has_seen(BossIntroRules.seen_key(intro.data)))
	assert_true(intro.boss.is_in_intro(), "released after the fade out")
	intro.advance(BossIntroRules.FADE_OUT_TIME + 0.01)
	assert_true(intro.is_finished())
	assert_false(intro.boss.is_in_intro())
	intro.free()


func test_story_interrupted_by_death_is_not_marked() -> void:
	var intro: BossIntro = await _story_intro(BOSSES[0])
	watch_signals(intro)
	intro.advance(0.5)
	intro.boss.health.take_damage(INF)
	assert_true(intro.is_finished())
	assert_signal_emit_count(intro, "finished", 1)
	assert_signal_not_emitted(intro, "ending")
	assert_false(SaveManager.has_seen(BossIntroRules.seen_key(intro.data)), "not heard, tell it again")
	intro.free()


func test_story_keeps_the_boss_music_held() -> void:
	var music := MusicStub.new()
	add_child(music)
	var boss := _spawn(BOSSES[2])
	await wait_physics_frames(1)
	var intro := BossIntro.create(boss, BossIntro.Kind.STORY)
	add_child(intro)
	intro.set_process(false)
	intro.start()
	_run(intro)
	assert_true(intro.is_finished())
	assert_eq(music.holds, intro.lines.size() - 1, "every further line renews the hold")
	var short := BossIntro.create(boss, BossIntro.Kind.SHORT)
	add_child(short)
	short.set_process(false)
	music.holds = 0
	short.start()
	_run(short)
	assert_eq(music.holds, 0, "short intros stay below the music's own limit")
	assert_lt(short.get_duration(), MusicPlayer.BOSS_HOLD_MAX_TIME)


func test_play_without_intro_data_finishes_right_away() -> void:
	var slime := _spawn("res://enemies/data/slime.tres", 3)
	await wait_physics_frames(1)
	assert_false(BossIntro.has_intro_for(slime))
	var done := [false]
	var signal_finished := BossIntro.play(slime, self)
	signal_finished.connect(func() -> void: done[0] = true)
	assert_false(slime.is_in_intro())
	await wait_physics_frames(3)
	assert_true(done[0], "finished without showing anything")


func test_play_with_view_runs_to_the_end() -> void:
	var boss := _spawn(BOSSES[1], 30)
	await wait_physics_frames(1)
	assert_true(BossIntro.has_intro_for(boss))
	var done := [false]
	var signal_finished := BossIntro.play(boss, self, BossIntro.Kind.SHORT)
	signal_finished.connect(func() -> void: done[0] = true)
	await wait_physics_frames(2)
	var intro := get_node_or_null("BossIntro") as BossIntro
	assert_not_null(intro, "intro node below the ui root")
	var duration := 0.0
	if intro != null:
		duration = intro.get_duration()
		var view := intro.get_child(0) as BossIntroView
		assert_not_null(view, "view attached")
		if view != null:
			assert_eq(view.layer, BossIntroView.LAYER)
			assert_not_null(view.find_child("Speech", true, false), "speech label built")
			assert_null(view.find_child("Counter", true, false), "no line counter in the short intro")
			var hint := view.find_child("Hint", true, false) as Label
			assert_eq(hint.text if hint != null else "", BossIntroView.SHORT_HINT)
	assert_true(boss.is_in_intro())
	await wait_seconds(duration + 0.5)
	assert_true(done[0], "finished")
	assert_false(boss.is_in_intro())


func test_story_view_shows_counter_hint_and_hold_bar() -> void:
	var boss := _spawn(BOSSES[0])
	await wait_physics_frames(1)
	BossIntro.play(boss, self)
	await wait_physics_frames(2)
	var intro := get_node_or_null("BossIntro") as BossIntro
	assert_not_null(intro)
	if intro == null:
		return
	assert_true(intro.is_story, "fresh save: the story")
	intro.set_process(false)
	var view := intro.get_child(0) as BossIntroView
	var counter := view.find_child("Counter", true, false) as Label
	var hint := view.find_child("Hint", true, false) as Label
	var bar := view.find_child("HoldBar", true, false) as ProgressBar
	assert_not_null(counter)
	assert_not_null(bar)
	assert_eq(hint.text if hint != null else "", BossIntroView.STORY_HINT)
	intro.advance(BossIntroRules.SKIP_GRACE + 0.05)
	intro.press()
	intro.press()
	assert_eq(counter.text if counter != null else "", BossIntroView.counter_text(2, intro.lines.size()))
	intro.begin_hold(&"interact")
	intro.advance(BossIntroRules.HOLD_TO_SKIP_TIME * 0.5)
	if bar != null:
		assert_almost_eq(bar.value, 0.5, 0.05, "the bar fills while held")
	intro.skip()
	intro.advance(BossIntroRules.FADE_OUT_TIME + 0.01)
	assert_true(intro.is_finished())


func test_speech_bbcode_trembles_and_escapes() -> void:
	var data: EnemyData = load(BOSSES[1])
	var text := BossIntroView.speech_bbcode(data, "Blo[b]")
	assert_string_contains(text, "[wave")
	assert_string_contains(text, "Blo[lb]b]")
	var calm := EnemyData.new()
	calm.intro_shake = 0.0
	calm.intro_wave = 0.0
	assert_eq(BossIntroView.speech_bbcode(calm, "ab"), "ab")

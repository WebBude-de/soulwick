class_name BossIntroRules
extends RefCounted
## Pure rules of the boss intro (BossIntro, BI1/D-098): which lines a boss says, when every letter
## appears, where a syllable starts and which babble sound it gets. The text is readable German,
## only the voice is babble (Animal Crossing / Undertale principle). Two kinds of intro:
## - story (first encounter per save, EnemyData.intro_story): all lines, longer hold per line, the
##   player can page through it (tap) or skip it as a whole (hold);
## - short (every later encounter, EnemyData.intro_lines): one variant of 1-2 lines.
## No randomness: the same boss on the same tier in the same run always says and sounds the same,
## and the same syllable always gets the same sound. All timings are TESTWERTE.

## Most dialog lines of one short intro (a variant "A|B" is two lines).
const MAX_REPEAT_LINES := 2
## Splits a short-intro variant into dialog lines.
const LINE_SEPARATOR := "|"
## Letter by letter: seconds per character (divided by EnemyData.intro_type_speed).
const CHAR_INTERVAL := 0.04
## Extra pause after punctuation, once per group ("..." pauses once).
const PUNCTUATION_PAUSE := 0.14
const PUNCTUATION := ".!?,;:…—–"
## A fully typed line stays this long before the next one starts (short intro) ...
const LINE_HOLD := 0.42
## ... and this long in the story intro (time to read; a tap goes on right away).
const STORY_LINE_HOLD := 0.7
## Overlay, letterbox and dialog fade in ...
const FADE_IN_TIME := 0.35
## ... and out again after the roar.
const FADE_OUT_TIME := 0.4
## Skip presses are ignored this long, so a click that was meant for the room does not skip unseen.
const SKIP_GRACE := 0.4
## Story intro: holding a skip key this long skips the whole intro (a tap only pages).
const HOLD_TO_SKIP_TIME := 0.7
## The boss frees itself after the planned duration plus this margin, even if nobody ends the intro.
const SAFETY_MARGIN := 2.0
## Letters per babbled syllable inside a long word ("Krrak" = "Krr" + "ak").
const SYLLABLE_LETTERS := 3
const BABBLE_PREFIX := "babble_"
## Seen flag of the story intro in the save ([seen] ids, SaveManager.has_seen/mark_seen).
const SEEN_PREFIX := "boss_intro_"


## True when the enemy has intro lines (bosses with data; champions and normal enemies have none).
static func has_intro(data: EnemyData) -> bool:
	return data != null and not (_clean(data.intro_lines).is_empty() and _clean(data.intro_story).is_empty())


## True when the boss has a story intro for the first encounter.
static func has_story(data: EnemyData) -> bool:
	return data != null and not _clean(data.intro_story).is_empty()


## Save flag of the story intro, e.g. &"boss_intro_bone_king" for id boss_bone_king.
static func seen_key(data: EnemyData) -> StringName:
	if data == null:
		return &""
	return StringName(SEEN_PREFIX + String(data.id).trim_prefix("boss_"))


## The lines of one intro. story = first encounter: all story lines (falls back to the short intro
## without story). Otherwise one short variant, see repeat_lines.
static func pick_lines(data: EnemyData, tier := 0, story := false, encounter := 0) -> PackedStringArray:
	if data == null:
		return PackedStringArray()
	if story and has_story(data):
		return story_lines(data)
	var lines := repeat_lines(data, tier, encounter)
	if lines.is_empty():
		# A boss with only a story says its first lines on later encounters.
		lines = story_lines(data).slice(0, MAX_REPEAT_LINES)
	return lines


static func story_lines(data: EnemyData) -> PackedStringArray:
	return _clean(data.intro_story) if data != null else PackedStringArray()


## One variant of intro_lines for a later encounter: it moves on with every boss tier (cycle) and
## every run (encounter = runs started so far), so a returning player hears something else; split
## at LINE_SEPARATOR into at most MAX_REPEAT_LINES dialog lines.
static func repeat_lines(data: EnemyData, tier := 0, encounter := 0) -> PackedStringArray:
	var result := PackedStringArray()
	if data == null:
		return result
	var variants := _clean(data.intro_lines)
	if variants.is_empty():
		return result
	var variant := variants[posmod(maxi(0, tier) + maxi(0, encounter), variants.size())]
	for part in variant.split(LINE_SEPARATOR, false):
		if not part.strip_edges().is_empty() and result.size() < MAX_REPEAT_LINES:
			result.append(part.strip_edges())
	return result


## Hold after a fully typed line.
static func line_hold(story := false) -> float:
	return STORY_LINE_HOLD if story else LINE_HOLD


## Seconds after the start of a line at which character i becomes visible (the first at 0).
## speed > 1 types faster, < 1 slower (pauses included).
static func reveal_times(line: String, speed := 1.0) -> PackedFloat32Array:
	var times := PackedFloat32Array()
	var step := CHAR_INTERVAL / maxf(0.1, speed)
	var pause := PUNCTUATION_PAUSE / maxf(0.1, speed)
	var time := 0.0
	for i in line.length():
		if i > 0:
			time += step
			if is_punctuation(line[i - 1]) and not is_punctuation(line[i]):
				time += pause
		times.append(time)
	return times


## Typing time of a line (until the last letter has settled), without the hold.
static func typing_time(line: String, speed := 1.0) -> float:
	var times := reveal_times(line, speed)
	return (times[times.size() - 1] + CHAR_INTERVAL / maxf(0.1, speed)) if not times.is_empty() else 0.0


static func line_duration(line: String, speed := 1.0, story := false) -> float:
	return typing_time(line, speed) + line_hold(story)


## Whole intro from the first fade to the released boss (nobody pages or skips).
static func total_duration(lines: PackedStringArray, speed := 1.0, story := false) -> float:
	if lines.is_empty():
		return 0.0
	var total := FADE_IN_TIME + FADE_OUT_TIME
	for line in lines:
		total += line_duration(line, speed, story)
	return total


## Character indices at which a babbled syllable starts: the first letter of every word part
## (hyphens and apostrophes split), and every SYLLABLE_LETTERS letters inside long parts.
static func syllable_starts(line: String) -> PackedInt32Array:
	var starts := PackedInt32Array()
	var letters := 0
	for i in line.length():
		if not is_letter(line[i]):
			letters = 0
			continue
		if letters == 0 or letters >= SYLLABLE_LETTERS:
			starts.append(i)
			letters = 0
		letters += 1
	return starts


## The letters of the syllable that starts at index start.
static func syllable_at(line: String, start: int) -> String:
	var result := ""
	var i := start
	while i < line.length() and is_letter(line[i]) and result.length() < SYLLABLE_LETTERS:
		result += line[i]
		i += 1
	return result


## Babble sound variant 1..variants of a syllable: a fixed hash of its letters.
static func babble_variant(syllable: String, variants: int) -> int:
	if variants <= 1:
		return 1
	var code := 7
	for c in syllable.to_lower():
		code = (code * 31 + c.unicode_at(0)) % 100003
	return posmod(code, variants) + 1


## Sound name for Sfx (audio/sfx/babble_<voice>_<variant>.wav), empty without a voice.
static func babble_sound(data: EnemyData, variant: int) -> StringName:
	if data == null or data.intro_voice == &"":
		return &""
	return StringName("%s%s_%d" % [BABBLE_PREFIX, data.intro_voice, clampi(variant, 1, maxi(1, data.intro_voice_variants))])


static func is_letter(character: String) -> bool:
	return character.to_upper() != character.to_lower()


static func is_punctuation(character: String) -> bool:
	return not character.is_empty() and PUNCTUATION.contains(character)


static func _clean(lines: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	for line in lines:
		if not line.strip_edges().is_empty():
			result.append(line.strip_edges())
	return result

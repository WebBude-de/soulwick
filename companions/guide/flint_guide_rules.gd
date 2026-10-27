class_name FlintGuideRules
extends RefCounted
## Pure rules of "Flint erklärt" (KONZEPT §7.2): timings, when an explanation shows, what a press
## does, how long a sentence stays, which portrait strip belongs to a mood. No nodes, no randomness
## (D-088). Letter-by-letter typing and babble syllables reuse BossIntroRules (D-098), only faster
## and brighter. All numbers are TESTWERTE.

## What a press of "Weiter" does right now.
enum Press { IGNORED, REVEAL_ALL, NEXT }

## Flint grows beside the player (s), then flies into the corner (s).
const GROW_TIME := 0.25
const FLY_OUT_TIME := 0.45
## ... and back to the player, shrinking (s).
const FLY_BACK_TIME := 0.45
## How big Flint gets beside the player before he takes off.
const GROW_SCALE := 2.0
## The player's camera flies to a goal in this time and comes home in CAMERA_RETURN_TIME (s).
const CAMERA_PAN_TIME := 0.6
const CAMERA_RETURN_TIME := 0.45
## Flint talks a little faster than a boss (BossIntroRules.CHAR_INTERVAL / speed).
const TYPE_SPEED := 1.25
## A press right after a sentence appeared is ignored, so a click meant for the game does not skip
## the first sentence unread (s).
const PRESS_GRACE := 0.3
## Two presses closer than this count once (a tap arrives as touch and as emulated click) (s).
const PRESS_DEBOUNCE := 0.12
## Holding a "Weiter" key this long skips the whole explanation (like the boss story, s).
const HOLD_TO_SKIP_TIME := 0.7
## Reading time after a sentence is fully typed when it goes on by itself: base plus per letter (s).
const READ_BASE := 1.6
const READ_PER_CHAR := 0.035
const READ_MAX := 5.0
## The bubble holds at most this many lines (§7.2, A2).
const MAX_LINES := 2
## Portrait strips of §B2 per mood (art/ui/flint_guide/flint_portrait_<name>_<n>f.png).
const PORTRAIT_ANIMATIONS := {
	FlintGuideStep.Mood.TALK: &"talk",
	FlintGuideStep.Mood.HAPPY: &"happy",
	FlintGuideStep.Mood.WORRIED: &"worried",
	FlintGuideStep.Mood.POINT: &"point",
	FlintGuideStep.Mood.PROUD: &"proud",
	FlintGuideStep.Mood.NEUTRAL: &"neutral",
}


## True if the explanation should be shown: valid, and not seen yet unless it may repeat or force.
static func should_explain(explanation: FlintExplanation, seen: bool, force := false) -> bool:
	if explanation == null or not explanation.is_valid():
		return false
	return force or not explanation.once or not seen


## Seconds after the start of a sentence at which character i appears (BossIntroRules timing).
static func reveal_times(text: String) -> PackedFloat32Array:
	return BossIntroRules.reveal_times(text, TYPE_SPEED)


## Characters visible time seconds into a sentence with these reveal times.
static func revealed_count(times: PackedFloat32Array, time: float) -> int:
	var count := 0
	while count < times.size() and times[count] <= time:
		count += 1
	return count


## Typing time of a whole sentence (s).
static func typing_time(text: String) -> float:
	return BossIntroRules.typing_time(text, TYPE_SPEED)


## How long a fully typed sentence stays before it goes on by itself (s).
static func read_time(text: String) -> float:
	return minf(READ_MAX, READ_BASE + READ_PER_CHAR * text.length())


## A press of "Weiter": ignored in the grace time, shows the whole sentence while it is still being
## typed, else goes on to the next sentence.
static func press(revealed: int, total: int, time_in_step: float) -> Press:
	if time_in_step < PRESS_GRACE:
		return Press.IGNORED
	return Press.REVEAL_ALL if revealed < total else Press.NEXT


## Where an explanation of priority goes into a queue with these priorities (highest first): behind
## its equals, or in front of them (before_equals: a cut hint coming back).
static func queue_index(waiting: Array[int], priority: int, before_equals := false) -> int:
	for i in waiting.size():
		if waiting[i] < priority or (before_equals and waiting[i] == priority):
			return i
	return waiting.size()


## A waiting explanation cuts the running one: only a hint (a tour holds its player, he reads it on
## purpose) of lower priority while Flint flies out or talks (FS5: the place before general hints,
## danger before everything).
static func gives_way(running: FlintExplanation, talking: bool, waiting: FlintExplanation) -> bool:
	if running == null or waiting == null or not talking or running.locks_player():
		return false
	return waiting.priority > running.priority


## About how long the explanation takes without anybody pressing (s): flights, typing and the
## reading time per sentence. Co-op (WK11): the host lengthens the room countdown by this.
static func estimated_duration(texts: PackedStringArray) -> float:
	var total := GROW_TIME + FLY_OUT_TIME + FLY_BACK_TIME
	for text in texts:
		total += typing_time(text) + read_time(text)
	return total


## Portrait strip name of a mood (talk for unknown moods).
static func portrait_animation(mood: int) -> StringName:
	return PORTRAIT_ANIMATIONS.get(mood, &"talk")


## Where Flint is on the way out: 0..1 of the whole flight -> [grow 0..1, fly 0..1].
static func fly_out_parts(progress: float) -> Vector2:
	var grow_share := GROW_TIME / (GROW_TIME + FLY_OUT_TIME)
	var p := clampf(progress, 0.0, 1.0)
	if p <= grow_share:
		return Vector2(p / grow_share, 0.0)
	return Vector2(1.0, (p - grow_share) / (1.0 - grow_share))


## Number of lines text needs in a bubble width px wide with font at size (word wrap).
static func line_count(text: String, font: Font, font_size: int, width: float) -> int:
	if text.is_empty() or font == null:
		return 0
	var size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size)
	return maxi(1, roundi(size.y / maxf(1.0, font.get_height(font_size))))

class_name FlintMood
extends RefCounted
## Flint's reactions (KONZEPT §7.1) as one pure decision: which mood shows right now. Only picks an
## animation (and a little lean), never changes the game. Flint fills a Facts object from signals and
## the player's state; FlintMood.decide() orders them:
##   sad (player down) > a one-shot reaction running (cast > pulse > joy) > scared (boss, darkness)
##   > asleep (village, player resting) > curious (secret close by) > move > idle.

enum Mood { IDLE, MOVE, JOY, PULSE, CAST, SCARED, SAD, SLEEP, CURIOUS }

## One-shot reactions that play once and then return to the held mood, by priority.
const ONE_SHOTS: Array[Mood] = [Mood.JOY, Mood.PULSE, Mood.CAST]

const ANIMATIONS := {
	Mood.IDLE: &"idle",
	Mood.MOVE: &"move",
	Mood.JOY: &"joy",
	Mood.PULSE: &"pulse",
	Mood.CAST: &"cast",
	Mood.SCARED: &"scared",
	Mood.SAD: &"sad",
	Mood.SLEEP: &"sleep",
	# Not in §B1 (requested in SPRITES_V13 part C): until delivered Flint plays idle and leans.
	Mood.CURIOUS: &"curious",
}


## What Flint knows this frame.
class Facts:
	extends RefCounted
	var downed := false
	var moving := false
	var afraid := false
	var sleepy := false
	var curious := false
	## The one-shot reaction playing right now, or -1.
	var one_shot := -1


static func decide(facts: Facts) -> Mood:
	if facts.downed:
		return Mood.SAD
	if is_one_shot(facts.one_shot):
		return facts.one_shot as Mood
	if facts.afraid:
		return Mood.SCARED
	if facts.sleepy:
		return Mood.SLEEP
	if facts.curious:
		return Mood.CURIOUS
	return Mood.MOVE if facts.moving else Mood.IDLE


static func is_one_shot(mood: int) -> bool:
	return ONE_SHOTS.has(mood)


## May a new one-shot replace the running one? Only a stronger (or the same) one does.
static func replaces(running: int, incoming: Mood) -> bool:
	if not is_one_shot(incoming):
		return false
	if not is_one_shot(running):
		return true
	return ONE_SHOTS.find(incoming) >= ONE_SHOTS.find(running)


static func animation_for(mood: Mood) -> StringName:
	return ANIMATIONS.get(mood, &"idle")

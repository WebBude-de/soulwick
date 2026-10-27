class_name FlintExplanation
extends Resource
## One Flint explanation (KONZEPT §7.2, the "Flint erklärt" kit): an id, the sentences (steps) and
## how it is shown. Data only; FlintGuide plays it for one player.
## - TOUR: Flint flies into the corner, the explained player stands still and is protected like in a
##   menu (D-085/D-123, nothing pauses), steps may fly the player's own camera to goals (D-184),
##   "Weiter" goes on, "Überspringen" ends. Village tour (WK9), practice run (WK10), new room types
##   (WK11), the entrance demo (WK8).
## - HINT: the "first time" short form: one or two sentences in the corner without camera or lock,
##   closes by itself after reading time (rank up, first talent point, first soul gate, first spell).
## Seen flags per account through AccountSeen with the id; ids start with ID_PREFIX ("flint_"), so a
## pre-D-087 world counting as "everything seen" does not swallow them
## (SaveManager.SEEN_ALL_EXCLUDED_PREFIXES).
## Build in .tres (companions/guide/explanations/<name>.tres, FlintExplanations.named()) or in code:
##   FlintExplanation.tour(&"flint_village_forge", [FlintGuideStep.say(&"FLINT_VILLAGE_FORGE")])
## Queue order (FS5, finding P1-1 of the newcomer run): priority first (the place before general
## hints, danger before everything), channel for explanations that replace each other (the practice
## run's stations), still_due to drop one that no longer fits (room left, gate used, key pressed).

enum Style { TOUR, HINT }
## GENERAL: keys and "first time" hints that fit any time. PLACE: about where the player is now (the
## room's tour, the soul gate, the use prompt, a practice station). URGENT: danger right now (holes,
## the side view); it interrupts a running hint of lower priority.
enum Priority { GENERAL, PLACE, URGENT }

const ID_PREFIX := "flint_"

## Seen id, also the name in the guide's queue (FLINT ids start with ID_PREFIX).
@export var id: StringName = &""
@export var style: Style = Style.TOUR
@export var steps: Array[FlintGuideStep] = []
## Shown once per account (AccountSeen); false: every time it is asked for (co-op tip bubbles).
@export var once := true
## TOUR: go on by itself after the reading time instead of waiting for "Weiter" (WK11 in co-op,
## where the host's countdown waits). HINT always goes on by itself.
@export var auto_advance := false
## TOUR: the camera flies at most this far from the player (world px, a room's walls); 0 = no limit
## (village tour).
@export var max_pan_distance := 0.0
## Place in the guide's queue (FlintGuide: higher first, the same in order of arrival).
@export var priority: Priority = Priority.GENERAL
## Explanations of the same non-empty channel replace each other: a new one ends a running hint of
## its channel and drops the waiting ones (practice run: the newest station's hint counts).
@export var channel: StringName = &""

## () -> bool: false once the explanation no longer fits; FlintGuide then drops it unseen (it comes
## on the next fitting occasion). Not saved; empty = always due.
var still_due := Callable()


## A tour (camera, lock, "Weiter") with steps.
static func tour(explanation_id: StringName, tour_steps: Array[FlintGuideStep]) -> FlintExplanation:
	return _create(explanation_id, Style.TOUR, tour_steps)


## A "first time" hint (no camera, no lock, closes by itself).
static func hint(explanation_id: StringName, hint_steps: Array[FlintGuideStep]) -> FlintExplanation:
	return _create(explanation_id, Style.HINT, hint_steps)


static func _create(explanation_id: StringName, kind: Style, list: Array[FlintGuideStep]) -> FlintExplanation:
	var explanation := FlintExplanation.new()
	explanation.id = explanation_id
	explanation.style = kind
	explanation.steps = list.duplicate()
	return explanation


## A copy with copies of every step (to set runtime goals like focus_node without touching the
## shared resource loaded from disk).
func copy() -> FlintExplanation:
	var result := duplicate() as FlintExplanation
	var copied: Array[FlintGuideStep] = []
	for step in steps:
		var step_copy: FlintGuideStep = step.duplicate() as FlintGuideStep if step != null else null
		if step_copy != null:
			step_copy.focus_node = step.focus_node
		copied.append(step_copy)
	result.steps = copied
	result.still_due = still_due
	return result


## Still fits (no still_due, or it says so).
func is_still_due() -> bool:
	return not still_due.is_valid() or bool(still_due.call())


## Playable: an id with ID_PREFIX and at least one step, every step with a text key.
func is_valid() -> bool:
	return problems().is_empty()


## What is wrong with this explanation (empty when it is fine); for tests and push_warning.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if not String(id).begins_with(ID_PREFIX):
		found.append("id '%s' must start with '%s' (seen flags, SaveManager.SEEN_ALL_EXCLUDED_PREFIXES)" % [id, ID_PREFIX])
	if steps.is_empty():
		found.append("'%s' has no steps" % id)
	for i in steps.size():
		if steps[i] == null or steps[i].text_key == &"":
			found.append("'%s' step %d has no text_key" % [id, i])
	return found


## The explained player stands still and is protected (TOUR only).
func locks_player() -> bool:
	return style == Style.TOUR


## Steps go on by themselves after the reading time.
func advances_by_itself() -> bool:
	return style == Style.HINT or auto_advance


## Some step flies the camera (TOUR only; a HINT never moves the camera).
func uses_camera() -> bool:
	if style != Style.TOUR:
		return false
	for step in steps:
		if step != null and step.wants_camera():
			return true
	return false

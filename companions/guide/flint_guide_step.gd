class_name FlintGuideStep
extends Resource
## One sentence of a Flint explanation (KONZEPT §7.2): the text key Flint says (FLINT_*, D-111, at
## most two lines in the bubble), his mood in the corner portrait (SPRITES_V13 §B2) and optionally a
## camera goal the player's own camera flies to while Flint says it (D-184: only the explained
## player's camera). Data only; FlintGuide shows it.
## Build in .tres (companions/guide/explanations/*.tres) or in code:
##   FlintGuideStep.say(&"FLINT_VILLAGE_FORGE", FlintGuideStep.Mood.POINT).at_node(forge)

## Portrait moods of §B2 (talk is the plain speaking face).
## NEUTRAL (V13c portrait): calm, without talking; appended, so saved steps keep their numbers.
enum Mood { TALK, HAPPY, WORRIED, POINT, PROUD, NEUTRAL }

## Translation key of the sentence (FLINT_*), may contain %s/%d for text_args.
@export var text_key: StringName = &""
## Arguments for the key's placeholders (Loc.t(text_key, text_args)).
@export var text_args: Array = []
@export var mood: Mood = Mood.TALK
## Camera goal: a node relative to the explained player's world (the player's parent), e.g.
## ^"Buildings/DungeonEntrance" in the village. Empty: see focus_point and focus_node.
@export var focus_path: NodePath = NodePath()
## Added to the goal node's position (world px), e.g. to show the door of a building.
@export var focus_offset := Vector2.ZERO
## Camera goal as a global point (used when has_focus_point is set and no node is given).
@export var focus_point := Vector2.ZERO
@export var has_focus_point := false

## Camera goal as a node, set from code (WK9 buildings, WK11 escort goal); wins over the others.
## Not saved: a node lives only as long as its world.
var focus_node: Node2D = null


## A step saying text_key with mood.
static func say(key: StringName, with_mood: Mood = Mood.TALK, args: Array = []) -> FlintGuideStep:
	var step := FlintGuideStep.new()
	step.text_key = key
	step.mood = with_mood
	step.text_args = args.duplicate()
	return step


## The camera shows node (plus offset) during this step. Returns self for chaining.
func at_node(node: Node2D, offset := Vector2.ZERO) -> FlintGuideStep:
	focus_node = node
	focus_offset = offset
	return self


## The camera shows a global point during this step. Returns self for chaining.
func at_point(point: Vector2) -> FlintGuideStep:
	focus_point = point
	has_focus_point = true
	return self


## The camera shows a node under the player's world during this step. Returns self for chaining.
func at_path(path: NodePath, offset := Vector2.ZERO) -> FlintGuideStep:
	focus_path = path
	focus_offset = offset
	return self


## True if this step names any camera goal (it may still be missing in the world).
func wants_camera() -> bool:
	return focus_node != null or not focus_path.is_empty() or has_focus_point


## The global camera goal in world, or Vector2.INF without one (or when the node is gone).
func resolve_focus(world: Node) -> Vector2:
	if focus_node != null and is_instance_valid(focus_node) and focus_node.is_inside_tree():
		return focus_node.global_position + focus_offset
	if not focus_path.is_empty() and world != null and is_instance_valid(world):
		var node := world.get_node_or_null(focus_path) as Node2D
		if node != null:
			return node.global_position + focus_offset
	if has_focus_point:
		return focus_point
	return Vector2.INF


## The sentence in the current language.
func get_text() -> String:
	if text_key == &"":
		return ""
	return Loc.t(text_key, text_args)

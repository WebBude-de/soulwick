class_name TutorialCoopTips
extends Node
## Co-op instead of the practice run (WK10, KONZEPT §7.2): in a group game nobody waits for a
## practice run; a local player who has not done it (AccountSeen TutorialRules.SEEN_ID) gets one
## short Flint tip bubble in each of the first rooms (FlintExplanation.hint: no stop, no lock, closes
## by itself), and the practice run is offered on his next solo start (the flag stays unset).
## Lives under the DungeonManager and follows its room_activated signal; only local players, each
## machine for its own player (D-088).

var manager: Node = null
## Tips shown (room index -> true), each room once.
var shown: Dictionary[int, bool] = {}
## Seen flag lookup (tests swap it).
var has_seen := func(id: StringName) -> bool: return AccountSeen.has_seen(id)


## Adds the tips to a group game's dungeon (idempotent). Returns the node.
static func attach(dungeon: Node) -> TutorialCoopTips:
	var existing := dungeon.get_node_or_null(^"TutorialCoopTips") as TutorialCoopTips
	if existing != null:
		return existing
	var tips := TutorialCoopTips.new()
	tips.name = "TutorialCoopTips"
	tips.manager = dungeon
	dungeon.add_child(tips)
	return tips


func _ready() -> void:
	if manager == null:
		manager = get_parent()
	if manager != null and manager.has_signal(&"room_activated"):
		manager.connect(&"room_activated", _on_room_activated)


## The tip explanation of a room (null after the first rooms).
static func tip_for(room_index: int) -> FlintExplanation:
	var key := TutorialRules.coop_tip_for_room(room_index)
	if key == &"":
		return null
	var tip := FlintExplanation.hint(StringName("flint_tutorial_tip_%d" % room_index),
			[FlintGuideStep.say(key, FlintGuideStep.Mood.POINT)] as Array[FlintGuideStep])
	# Shown again in every group game until the practice run is done alone.
	tip.once = false
	return tip


## Shows the tip of room_index to every local player who needs it. Returns how many got it.
func show_tip(room_index: int, players: Array) -> int:
	if shown.has(room_index):
		return 0
	var tip := tip_for(room_index)
	if tip == null:
		return 0
	shown[room_index] = true
	var count := 0
	for node: Variant in players:
		var player := node as Player
		if player == null or not is_instance_valid(player) or not player.is_local:
			continue
		if not TutorialRules.wants_coop_tips(bool(has_seen.call(TutorialRules.SEEN_ID)), true):
			continue
		if FlintGuide.explain(player, tip):
			count += 1
	return count


func _on_room_activated(room: Node) -> void:
	if room == null or not manager.has_method(&"get_session_players"):
		return
	show_tip(int(room.get(&"room_index")), manager.call(&"get_session_players"))

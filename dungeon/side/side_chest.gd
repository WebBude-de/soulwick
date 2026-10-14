class_name SideChest
extends TreasureChest
## The chest in a niche of a side segment (M5): the bonus chest of D-109 (an upgrade choice), open
## from the start because a segment has no fight to win. The segment hands over the run's context,
## since no RoomController is around it.

var segment_context: DungeonContext = null


func _init() -> void:
	locked_until_cleared = false


func find_context() -> DungeonContext:
	return segment_context

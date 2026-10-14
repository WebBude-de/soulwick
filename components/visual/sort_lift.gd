class_name SortLift
extends RefCounted
## Y-sorting compares node origins. Characters (player, enemies) have their origin at the body
## centre, Player.FEET_OFFSET above their feet, while props and buildings sit on their base line.
## Lifting a prop's origin by that offset (and moving its children down by the same amount, so
## nothing moves on screen) makes the sort compare feet with base lines: a player whose feet are in
## front of a house is drawn in front of it.


## Lifts every direct Node2D/Control child of container (each one a prop) by amount world px.
static func lift_props(container: Node, amount: float = Player.FEET_OFFSET.y) -> void:
	for prop in container.get_children():
		if prop is Node2D:
			lift(prop, amount)


## Moves the sort origin of prop up by amount without changing what is drawn or where it collides.
static func lift(prop: Node2D, amount: float = Player.FEET_OFFSET.y) -> void:
	prop.position.y -= amount
	for child in prop.get_children():
		if child is Node2D:
			child.position.y += amount
		elif child is Control:
			child.position.y += amount

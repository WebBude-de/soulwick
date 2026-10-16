class_name PropBodies
extends RefCounted
## Solid bodies of room props at any depth. A prop is a body itself (crate, barrel, rubble), carries
## one as a direct child (light pedestal, chest, altar) or deeper: a plan crystal or torch stand is a
## DecoProp holding a LightIsland holding the Blocker. RoomController.is_solid_prop used to look one
## level deep only and missed those.

## Levels below the prop that are searched (the deepest prop today: DecoProp -> LightIsland ->
## Blocker = 2).
const MAX_DEPTH := 4


## The first StaticBody2D of prop: the prop itself or a descendant up to max_depth levels below it
## (depth first, in child order); null if there is none.
static func find_solid_body(prop: Node, max_depth: int = MAX_DEPTH) -> StaticBody2D:
	if prop == null:
		return null
	if prop is StaticBody2D:
		return prop as StaticBody2D
	if max_depth <= 0:
		return null
	for child in prop.get_children():
		var body := find_solid_body(child, max_depth - 1)
		if body != null:
			return body
	return null


## Does prop block walking (a StaticBody2D in it, see find_solid_body)?
static func is_solid(prop: Node) -> bool:
	return find_solid_body(prop) != null

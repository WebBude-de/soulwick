class_name HeightBody
extends StaticBody2D
## Solid part of a room's height (M3, HeightField): cliffs and edges (PhysicsLayers.CLIFF) or ladders
## for enemies (PhysicsLayers.LADDER). Its own class so EnemyNavigation counts it like the walls of
## the tiles: something the navigation walks around, not a crate to steer past.

## Kinds of one-way rectangles (create): the north edge of a plateau has one for each side.
const ONE_WAY_FROM_NORTH := 1
const ONE_WAY_FROM_SOUTH := -1


## One body on layer with a rectangle per entry of rects (layer space of the room tiles). one_way
## (optional, one entry per rect): 0 = solid, ONE_WAY_FROM_NORTH = stops only who walks south into
## it, ONE_WAY_FROM_SOUTH = stops only who walks north into it.
static func create(body_name: String, layer: int, rects: Array[Rect2], one_way: Array[int] = []) -> HeightBody:
	var body := HeightBody.new()
	body.name = body_name
	body.collision_layer = layer
	body.collision_mask = 0
	for i in rects.size():
		var rect := rects[i]
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.position = rect.get_center()
		var way := one_way[i] if i < one_way.size() else 0
		if way != 0:
			# A one-way shape stops bodies coming from its local top; turned over, from the south.
			collision.one_way_collision = true
			collision.rotation = PI if way == ONE_WAY_FROM_SOUTH else 0.0
		body.add_child(collision)
	return body

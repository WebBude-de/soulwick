class_name HeightBody
extends StaticBody2D
## Solid part of a room's height (M3, HeightField): cliffs and edges (PhysicsLayers.CLIFF) or ladders
## for enemies (PhysicsLayers.LADDER). Its own class so EnemyNavigation counts it like the walls of
## the tiles: something the navigation walks around, not a crate to steer past.


## One body on layer with a rectangle per entry of rects (layer space of the room tiles).
static func create(body_name: String, layer: int, rects: Array[Rect2]) -> HeightBody:
	var body := HeightBody.new()
	body.name = body_name
	body.collision_layer = layer
	body.collision_mask = 0
	for rect in rects:
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.position = rect.get_center()
		body.add_child(collision)
	return body

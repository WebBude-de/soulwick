class_name HomeFrontWall
extends Node2D
## The low front wall of the home with the doorway, door posts and threshold (KE8b), as its own
## layer OVER the furniture and the players: pieces in the last floor row stand visibly behind it
## instead of on top of it. Players never reach behind it (the floor ends at the wall's top edge).
## Child of HomeRoom (art px, the room's scale); HomeRoom paints it (paint_front_wall) so the time
## of day of the glimpse outside stays in one place.

## Above the y-sorted furniture and players (z 0), below the decorating mode (DecorEditor z 40).
const Z := 5

var room: HomeRoom = null


func _ready() -> void:
	z_as_relative = false
	z_index = Z
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _draw() -> void:
	if room != null:
		room.paint_front_wall(self)

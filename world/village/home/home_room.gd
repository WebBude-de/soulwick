class_name HomeRoom
extends Node2D
## Floor and walls of the home interior (KE8): wooden planks, two rows of panelled back wall with the
## moon window (by day lighter), side and bottom walls with the door out. Drawn from the delivered
## tile sheet (home_interior_tiles.png, only row 1 and the door are delivered); side walls and the
## bottom wall are dark beams until the missing rows arrive (SPRITES_V13 Teil C). Also the static
## bodies of the walls. Lies under everything (z_index), drawn in art px at HomeLayout.SCALE.

const BEAM := Color("#3b2a22")
const BEAM_LIGHT := Color("#5c3a24")
const UPPER_WALL_TINT := Color(0.72, 0.68, 0.78)
const DAY_WINDOW_TINT := Color(1.35, 1.45, 1.6)
const Z := -10

## 0 = day (lighter window), 1 = night (VillageDaylight.night_amount).
var night := 1.0


func _ready() -> void:
	z_index = Z
	scale = Vector2.ONE * HomeLayout.SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_add_walls()


func set_night(amount: float) -> void:
	night = clampf(amount, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var sheet := HomeArt.tiles_texture()
	var tile := float(HomeLayout.TILE)
	for row in HomeLayout.ROWS:
		for col in HomeLayout.COLS:
			var at := Rect2(col * tile, row * tile, tile, tile)
			if row >= HomeLayout.WALL_ROWS:
				_tile(sheet, "floor_a" if (col * 7 + row * 3) % 5 != 0 else "floor_b", at, Color.WHITE)
			elif row == HomeLayout.WALL_ROWS - 1:
				_tile(sheet, _back_wall_tile(col), at, _window_tint(col))
			else:
				_tile(sheet, "wall_front", at, UPPER_WALL_TINT)
	# Side walls and the bottom wall with a gap for the door (beams until the tiles exist).
	var height := HomeLayout.ROWS * tile
	var width := HomeLayout.COLS * tile
	draw_rect(Rect2(0, 0, HomeLayout.SIDE_WALL, height), BEAM)
	draw_rect(Rect2(width - HomeLayout.SIDE_WALL, 0, HomeLayout.SIDE_WALL, height), BEAM)
	draw_rect(Rect2(HomeLayout.SIDE_WALL - 1, 0, 1, height), BEAM_LIGHT)
	draw_rect(Rect2(width - HomeLayout.SIDE_WALL, 0, 1, height), BEAM_LIGHT)
	var bottom := height - HomeLayout.BOTTOM_WALL
	draw_rect(Rect2(0, bottom, width, HomeLayout.BOTTOM_WALL), BEAM)
	draw_rect(Rect2(0, bottom, width, 1), BEAM_LIGHT)
	var door := Rect2(HomeLayout.DOOR_COL * tile, height - tile, tile, tile)
	if sheet != null and HomeArt.tile_region("door_out").has_area():
		draw_texture_rect_region(sheet, door, HomeArt.tile_region("door_out"))
	else:
		draw_rect(door.grow(-4), BEAM_LIGHT)


func _back_wall_tile(col: int) -> String:
	if col == 0:
		return "wall_corner_l"
	if col == HomeLayout.COLS - 1:
		return "wall_corner_r"
	if col == HomeLayout.WINDOW_COL:
		return "window_a"
	if col == HomeLayout.WINDOW_COL + 1:
		return "window_b"
	return "wall_front"


func _window_tint(col: int) -> Color:
	if col != HomeLayout.WINDOW_COL and col != HomeLayout.WINDOW_COL + 1:
		return Color.WHITE
	return DAY_WINDOW_TINT.lerp(Color.WHITE, night)


func _tile(sheet: Texture2D, tile_name: String, at: Rect2, tint: Color) -> void:
	var region := HomeArt.tile_region(tile_name)
	if sheet == null or not region.has_area():
		draw_rect(at, BEAM_LIGHT if tile_name.begins_with("wall") else Color("#a8703f"))
		return
	draw_texture_rect_region(sheet, at, region, tint)


## Static bodies around the floor (world layer): the back wall, both sides and the bottom wall.
func _add_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	add_child(body)
	var floor_area := HomeLayout.floor_rect()
	var room := Rect2(Vector2.ZERO, Vector2(HomeLayout.COLS, HomeLayout.ROWS) * HomeLayout.TILE)
	var thick := 32.0
	_add_box(body, Rect2(room.position.x - thick, room.position.y - thick, room.size.x + thick * 2, floor_area.position.y + thick))
	_add_box(body, Rect2(room.position.x - thick, floor_area.end.y, room.size.x + thick * 2, room.end.y - floor_area.end.y + thick))
	_add_box(body, Rect2(room.position.x - thick, 0, floor_area.position.x + thick, room.size.y))
	_add_box(body, Rect2(floor_area.end.x, 0, room.end.x - floor_area.end.x + thick, room.size.y))


static func _add_box(body: StaticBody2D, rect: Rect2) -> void:
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.get_center()
	body.add_child(shape)

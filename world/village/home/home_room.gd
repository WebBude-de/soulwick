class_name HomeRoom
extends Node2D
## Floor and walls of the home interior (KE8): wooden planks, two rows of panelled back wall with
## the windows (HomeWindow children: the view follows the village clock), side beams and the low
## front wall with the open doorway: a gap with two door posts, the threshold, a glimpse of the path
## outside (bright by day, dark at night) and a striped door mat on the floor in front of it (KE8b,
## playtest 04.11.2026 "die Tür unten sieht weird aus": the delivered door tile stood like a block in
## the wall). Drawn from the delivered tile sheet (home_interior_tiles.png row 1); beams, posts and
## mat are code pixels until home_doorway.png and door_mat.png arrive (SPRITES_V13 Teil C: the
## doorway with a see-through opening over the drawn path, the mat on the floor). Also the static bodies of the
## walls. Lies under everything (z_index), drawn in art px at HomeLayout.SCALE; only the front wall
## lies over the furniture (HomeFrontWall, KE8b: pieces in the last row stand behind it).
## WK7: a bought wallpaper or floor style (DecorState home_wall/home_floor, V13e wall_<style>.png and
## floor_<style>.png) replaces the plain wall tiles and the planks; corners, windows and door stay.

const BEAM := Color("#3b2a22")
const BEAM_LIGHT := Color("#5c3a24")
const WALL_TOP := Color("#7a4e30")
const SKIRTING := Color("#2e211b")
const POST := Color("#5c3a24")
const POST_LIGHT := Color("#8a5a34")
const THRESHOLD := Color("#a8703f")
const MAT := Color("#8a5a34")
const MAT_STRIPE := Color("#c0603a")
const MAT_EDGE := Color("#5c3a24")
const OUTSIDE_DAY := Color("#c8a46a")
const OUTSIDE_NIGHT := Color("#2a2640")
const GRASS_DAY := Color("#6fae52")
const UPPER_WALL_TINT := Color(0.72, 0.68, 0.78)
## Delivered doorway (front wall piece with a see-through opening, pivot bottom middle) and mat.
const DOORWAY_FILE := "home_doorway.png"
const MAT_FILE := "door_mat.png"
const Z := -10

## 0 = day, 1 = night (VillageDaylight.night_amount): windows and the glimpse outside follow it.
var night := 1.0
var windows: Array[HomeWindow] = []
## The front wall with the doorway, a layer over the furniture (HomeFrontWall).
var front_wall: HomeFrontWall = null


func _ready() -> void:
	z_index = Z
	scale = Vector2.ONE * HomeLayout.SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_add_walls()
	_add_windows()
	front_wall = HomeFrontWall.new()
	front_wall.name = "FrontWall"
	front_wall.room = self
	add_child(front_wall)
	SaveManager.decor_changed.connect(queue_redraw)


func _exit_tree() -> void:
	if SaveManager.decor_changed.is_connected(queue_redraw):
		SaveManager.decor_changed.disconnect(queue_redraw)


func set_night(amount: float) -> void:
	night = clampf(amount, 0.0, 1.0)
	for window in windows:
		window.set_night(night)
	if front_wall != null:
		front_wall.queue_redraw()
	queue_redraw()


func _add_windows() -> void:
	windows.clear()
	for col in HomeLayout.WINDOW_COLS:
		var window := HomeWindow.create(col, col == HomeWindow.middle_col())
		add_child(window)
		window.set_night(night)
		windows.append(window)


func _draw() -> void:
	var sheet := HomeArt.tiles_texture()
	var tile := float(HomeLayout.TILE)
	var floor_style := HomeArt.style_texture("floor", DecorState.surface_style(DecorState.SETTING_FLOOR))
	var wall_style := HomeArt.style_texture("wall", DecorState.surface_style(DecorState.SETTING_WALL))
	for row in HomeLayout.ROWS:
		for col in HomeLayout.COLS:
			var at := Rect2(col * tile, row * tile, tile, tile)
			if row >= HomeLayout.WALL_ROWS:
				if floor_style != null:
					draw_texture_rect(floor_style, at, false)
				else:
					_tile(sheet, "floor_a" if (col * 7 + row * 3) % 5 != 0 else "floor_b", at, Color.WHITE)
			elif row == HomeLayout.WALL_ROWS - 1:
				var wall_tile := _back_wall_tile(col)
				if wall_style != null and wall_tile == "wall_front":
					draw_texture_rect(wall_style, at, false)
				else:
					_tile(sheet, wall_tile, at, Color.WHITE)
			elif wall_style != null:
				draw_texture_rect(wall_style, at, false, UPPER_WALL_TINT)
			else:
				_tile(sheet, "wall_front", at, UPPER_WALL_TINT)
	var height := HomeLayout.ROWS * tile
	var width := HomeLayout.COLS * tile
	# Ceiling beam and the skirting board where the wall meets the planks.
	draw_rect(Rect2(0, 0, width, 3), BEAM)
	draw_rect(Rect2(0, HomeLayout.WALL_ROWS * tile - 1, width, 2), SKIRTING)
	# Side walls.
	draw_rect(Rect2(0, 0, HomeLayout.SIDE_WALL, height), BEAM)
	draw_rect(Rect2(width - HomeLayout.SIDE_WALL, 0, HomeLayout.SIDE_WALL, height), BEAM)
	draw_rect(Rect2(HomeLayout.SIDE_WALL - 1, 0, 1, height), BEAM_LIGHT)
	draw_rect(Rect2(width - HomeLayout.SIDE_WALL, 0, 1, height), BEAM_LIGHT)
	_draw_door_mat()


## The low front wall with the doorway into canvas (HomeFrontWall draws it over the furniture): the
## wall's top edge, the gap with the path outside, the threshold and two door posts. Art px.
func paint_front_wall(canvas: CanvasItem) -> void:
	var tile := float(HomeLayout.TILE)
	var height := HomeLayout.ROWS * tile
	var width := HomeLayout.COLS * tile
	var top := height - HomeLayout.BOTTOM_WALL
	var gap := door_gap()
	for part in [Rect2(0, top, gap.position.x, HomeLayout.BOTTOM_WALL),
			Rect2(gap.end.x, top, width - gap.end.x, HomeLayout.BOTTOM_WALL)]:
		canvas.draw_rect(part, BEAM)
		canvas.draw_rect(Rect2(part.position, Vector2(part.size.x, 2)), WALL_TOP)
		canvas.draw_rect(Rect2(part.position + Vector2(0, 2), Vector2(part.size.x, 1)), BEAM_LIGHT)
	canvas.draw_rect(Rect2(gap.position.x, top + 2, gap.size.x, HomeLayout.BOTTOM_WALL - 2), outside_color())
	canvas.draw_rect(Rect2(gap.position.x, top, gap.size.x, 2), THRESHOLD)
	# Grass at the sides of the path outside, the door jambs in the wall.
	canvas.draw_rect(Rect2(gap.position.x, top + 3, 3, HomeLayout.BOTTOM_WALL - 3), outside_grass())
	canvas.draw_rect(Rect2(gap.end.x - 3, top + 3, 3, HomeLayout.BOTTOM_WALL - 3), outside_grass())
	var doorway := _art(DOORWAY_FILE)
	if doorway != null:
		canvas.draw_texture(doorway, Vector2(gap.get_center().x - doorway.get_width() * 0.5, height - doorway.get_height()).round())
		return
	for x in [gap.position.x - 3.0, gap.end.x]:
		canvas.draw_rect(Rect2(x, top - 1, 3, HomeLayout.BOTTOM_WALL + 1), POST)
		canvas.draw_rect(Rect2(x + (2.0 if x < gap.position.x else 0.0), top - 1, 1, HomeLayout.BOTTOM_WALL + 1), POST_LIGHT)


## The striped door mat on the floor in front of the doorway.
func _draw_door_mat() -> void:
	var mat := door_mat_rect()
	var art := _art(MAT_FILE)
	if art != null:
		draw_texture(art, Vector2(mat.get_center().x - art.get_width() * 0.5, mat.end.y - art.get_height()).round())
		return
	draw_rect(mat, MAT_EDGE)
	draw_rect(mat.grow(-1), MAT)
	for x in range(int(mat.position.x) + 3, int(mat.end.x) - 2, 4):
		draw_rect(Rect2(x, mat.position.y + 2, 2, mat.size.y - 4), MAT_STRIPE)


## The opening in the front wall (art px, the wall's height).
static func door_gap() -> Rect2:
	var middle := HomeLayout.DOOR_COL * HomeLayout.TILE + HomeLayout.TILE * 0.5
	var height := HomeLayout.ROWS * HomeLayout.TILE
	return Rect2(middle - HomeLayout.DOOR_OPENING * 0.5, height - HomeLayout.BOTTOM_WALL,
		HomeLayout.DOOR_OPENING, HomeLayout.BOTTOM_WALL)


static func door_mat_rect() -> Rect2:
	var gap := door_gap()
	var mat := Vector2(HomeLayout.DOOR_MAT)
	return Rect2(Vector2(gap.get_center().x - mat.x * 0.5, gap.position.y - mat.y - 3), mat)


## What shows through the doorway: the path in daylight, the dark at night.
func outside_color() -> Color:
	return OUTSIDE_DAY.lerp(OUTSIDE_NIGHT, night)


func outside_grass() -> Color:
	return GRASS_DAY.lerp(OUTSIDE_NIGHT.darkened(0.2), night)


static func _art(file: String) -> Texture2D:
	var path := HomeArt.DIR + file
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _back_wall_tile(col: int) -> String:
	if col == 0:
		return "wall_corner_l"
	if col == HomeLayout.COLS - 1:
		return "wall_corner_r"
	return "wall_front"


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

class_name RoomVeil
extends Node2D
## "Nothing pops up" (R5, KONZEPT_RAEUME_V2 §1.2/§4, 05_tueren.md): a room that is prepared but not
## entered yet lies built and dark behind its door. The veil is a soft dark sheet over the room's
## floor and walls (its entrance corridor stays free, so the way to it is visible as soon as the door
## opens); it lifts when a player walks into the entrance corridor or when the room activates, and
## the room lights up. Pure optics: no collision, no gameplay state, no dungeon RNG.
## The DungeonManager attaches one to every prepared room except the first.

signal lifted(veil: RoomVeil)

const NODE_NAME := &"RoomVeil"
## Darkness of the sheet and its colour (TESTWERTE): dark enough to read as "not lit yet", light
## enough that the layout shows through the dungeon darkness.
const VEIL_ALPHA := 0.62
const VEIL_COLOR := Color(0.015, 0.01, 0.03)
## Time the veil takes to lift (TESTWERT).
const LIFT_TIME := 0.45
## Above the room's tiles, props, doors and enemies; the vision overlay draws above it anyway.
const VEIL_Z := 20
## Texture resolution: pixels per tile; the soft edge is this many pixels wide (one tile).
const PIXELS_PER_TILE := 4
const EDGE_PIXELS := 4

var room: RoomController = null
var _sheet: Sprite2D = null
var _trigger: Area2D = null
var _lifted := false


## Puts a veil over a prepared room (after it entered the tree); returns the existing one if any.
static func attach(target: RoomController) -> RoomVeil:
	var existing := of(target)
	if existing != null:
		return existing
	var veil := RoomVeil.new()
	veil.name = NODE_NAME
	veil.room = target
	target.add_child(veil)
	return veil


static func of(target: Node) -> RoomVeil:
	if target == null or not is_instance_valid(target):
		return null
	return target.get_node_or_null(NodePath(NODE_NAME)) as RoomVeil


## Lifts the veil of a room (no-op without one).
static func lift_room(target: Node, instant := false) -> void:
	var veil := of(target)
	if veil != null:
		veil.lift(instant)


## Room-local tile rectangle the veil covers: floor and wall ring, one tile of rock around it,
## except on the entrance side, where the corridor stays visible.
static func get_veil_rect(size: Vector2i, entrance_side: int) -> Rect2i:
	var body := ExitRules.body_rect_of(size)
	var grow := [1, 1, 1, 1]
	# Order of grow_individual: left, top, right, bottom.
	match entrance_side:
		RoomTiles.DoorSide.WEST:
			grow[0] = 0
		RoomTiles.DoorSide.NORTH:
			grow[1] = 0
		RoomTiles.DoorSide.EAST:
			grow[2] = 0
		_:
			grow[3] = 0
	return body.grow_individual(grow[0], grow[1], grow[2], grow[3])


func _ready() -> void:
	z_index = VEIL_Z
	z_as_relative = false
	if room == null:
		room = get_parent() as RoomController
	if room == null:
		return
	var tiles := room.get_node("Tiles") as RoomTiles
	var rect := get_veil_rect(tiles.room_size, tiles.entrance_side)
	_sheet = Sprite2D.new()
	_sheet.name = "Sheet"
	_sheet.centered = false
	_sheet.texture = make_texture(rect.size)
	_sheet.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sheet.scale = Vector2.ONE * RoomTiles.TILE_WORLD / PIXELS_PER_TILE
	_sheet.position = RoomTiles.tile_to_local(rect.position)
	_sheet.modulate = Color(VEIL_COLOR, VEIL_ALPHA)
	add_child(_sheet)
	_build_trigger(tiles)


func is_lifted() -> bool:
	return _lifted


func get_sheet() -> Sprite2D:
	return _sheet


## Lifts the veil once: the room lights up (fades, or at once with instant).
func lift(instant := false) -> void:
	if _lifted:
		return
	_lifted = true
	if _trigger != null:
		_trigger.set_deferred("monitoring", false)
	lifted.emit(self)
	if instant or _sheet == null or not is_inside_tree():
		visible = false
		return
	var tween := create_tween()
	tween.tween_property(_sheet, "modulate:a", 0.0, LIFT_TIME)
	tween.tween_callback(hide)


## White sheet of size tiles with a soft edge (alpha 0 at the border, 1 one tile inside); the colour
## comes from modulate.
static func make_texture(size_tiles: Vector2i) -> ImageTexture:
	var size := Vector2i(maxi(1, size_tiles.x), maxi(1, size_tiles.y)) * PIXELS_PER_TILE
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			var edge := mini(mini(x, size.x - 1 - x), mini(y, size.y - 1 - y))
			var alpha := clampf((float(edge) + 0.5) / EDGE_PIXELS, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, alpha * alpha * (3.0 - 2.0 * alpha)))
	return ImageTexture.create_from_image(image)


## A player stepping into the entrance corridor (the door tile and the tiles beyond it) lifts the veil,
## so the room is lit before anyone stands in it.
func _build_trigger(tiles: RoomTiles) -> void:
	var corridor := RoomTiles.corridor_tiles_of(tiles.entrance_side, tiles.entrance_x, tiles.room_size, tiles.entrance_corridor_extra)
	if corridor.is_empty():
		return
	var bounds := RoomTiles.tile_bounds(corridor)
	_trigger = Area2D.new()
	_trigger.name = "Trigger"
	_trigger.collision_layer = 0
	_trigger.collision_mask = PhysicsLayers.PLAYER
	_trigger.monitorable = false
	var shape := RectangleShape2D.new()
	shape.size = Vector2(bounds.size) * RoomTiles.TILE_WORLD
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = RoomTiles.tile_to_local(bounds.position) + shape.size * 0.5
	_trigger.add_child(collision)
	add_child(_trigger)
	_trigger.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		lift()

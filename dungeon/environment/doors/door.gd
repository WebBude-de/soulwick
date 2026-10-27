class_name Door
extends StaticBody2D
## One-tile door on the world layer. Node origin = top-left corner of its tile.
## Logic only: open/closed and the collision. Looks, particles, light and sound live in DoorView
## ($View), which follows state_changed (ROADMAP D1, decisions separate from effects).
## Biome and destination come from outside: configure() / configure_for_room() / set_destination().
## The way behind an exit door (R5): show_way() puts the mode symbol over it and a light cone in the
## mode colour in front of it (DoorSigns decides both from the prepared next room).
## One gate per transition (M2): an exit is the gate of the transition (closed, opening, open; sealed
## at a branch), flush in the wall of the room being left; its frame follows that room's wall (cave
## mouth or arch, DoorStyle.apply_room_look); it shuts again behind the group once everyone is inside
## the next room (GateCloser). An entrance is no door any more: an open gap in the wall without a leaf
## (close() does nothing, the gate behind it is the door). It only blocks while nothing lies behind it
## (room 1, or the room before was unloaded: block()).

## Emitted on every open()/close()/set_open_instant(); instant = no animation or effects.
signal state_changed(open: bool, instant: bool)

## World px of a tile.
const TILE := 64.0

var is_open := false
## Look of the door. Unconfigured doors use the crypt style.
var style: DoorStyle = DoorStyle.for_door(DoorStyle.DEFAULT_BIOME)
## Entrance of a room (M2): an open gap without leaf, frame, torches or sign; blocks only when nothing
## lies behind it.
var is_entrance := false
## Wall the door stands in (RoomTiles.DoorSide, A10): north and south doors face the camera, west and
## east doors are seen from above (DoorView draws them as narrow leaves with a torch above).
var side: int = RoomTiles.DoorSide.NORTH
## Becomes true with configure(). Only configured doors play their own sounds: before D1 is
## wired in, RoomController still plays "door_open" itself.
var is_configured := false
## Mode and light colour of the way behind the door (show_way); kept across configure().
var way_mode: StringName = &""
var way_color := Color(0, 0, 0, 0)

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var view: DoorView = $View


func _ready() -> void:
	_fit_shape()
	view.setup(_sprite)
	view.side = side
	view.apply_style(style, is_entrance)
	view.sounds_enabled = is_configured
	state_changed.connect(view.on_state_changed)
	_apply(is_open, true)


## Sets biome and kind (DoorStyle.KIND_NORMAL / KIND_BOSS) and an optional sign
## (DoorStyle.SYMBOLS). May be called before or after the door enters the tree.
func configure(biome_id: StringName, kind: StringName = DoorStyle.KIND_NORMAL, symbol: StringName = &"", entrance := false) -> void:
	style = DoorStyle.for_door(biome_id, kind, symbol)
	is_entrance = entrance
	# The wall around the gate is the wall of the room the door belongs to (M2).
	var room := get_parent()
	style.apply_room_look(DoorStyle.is_cave_room(room, style.biome_id), DoorStyle.is_soft_room(room, style.biome_id), DoorStyle.is_arena_room(room))
	is_configured = true
	_copy_way()
	if is_node_ready():
		_fit_shape()
		view.apply_style(style, is_entrance)
		view.sounds_enabled = true
		view.show_state(is_open)


## Door in a room of biome_id that leads into a room of target_room_type (RoomSequence.RoomType,
## target_special = its SpecialType or -1): boss gate in front of boss rooms, signs for special rooms.
func configure_for_room(biome_id: StringName, target_room_type: int, target_special: int = -1, entrance := false) -> void:
	configure(biome_id, DoorStyle.kind_for_room(target_room_type), DoorStyle.symbol_for_room(target_room_type, target_special), entrance)


## Updates kind and sign once the room behind the door is known; keeps the biome.
func set_destination(target_room_type: int, target_special: int = -1) -> void:
	configure_for_room(style.biome_id, target_room_type, target_special, is_entrance)


func get_style() -> DoorStyle:
	return style


## Wall of the door (RoomTiles.DoorSide). Call before the door enters the tree or call configure()
## again afterwards.
func set_side(value: int) -> void:
	side = value
	if is_node_ready():
		_fit_shape()
		view.side = value
		view.apply_style(style, is_entrance)
		view.show_state(is_open)


func is_side_door() -> bool:
	return side == RoomTiles.DoorSide.WEST or side == RoomTiles.DoorSide.EAST


## Shows a branch symbol over a door that is no entrance (D-105), &"" removes it.
func set_branch_symbol(symbol_id: StringName) -> void:
	style.symbol = symbol_id if DoorStyle.is_branch_symbol(symbol_id) else &""
	if is_node_ready():
		view.set_symbol(style.symbol)


## The way behind this door (R5): mode of the next room (RoomObjective mode id, &"" = none, its symbol
## replaces a special or branch sign) and the colour of the light cone (transparent = none).
## Entrance doors show neither.
func show_way(mode: StringName, color: Color) -> void:
	way_mode = mode
	way_color = color
	_copy_way()
	if is_node_ready():
		view.apply_style(style, is_entrance)
		view.show_state(is_open)


func get_way_mode() -> StringName:
	return way_mode


## A branch door that was not chosen: it stays shut for good and dims (decision of the room).
func seal() -> void:
	_apply(false, true)
	if is_node_ready():
		view.show_sealed()


func open() -> void:
	_apply(true, false)


## Shuts an exit gate. An entrance has nothing to shut (M2: the gate of the room before is the
## door); see block().
func close() -> void:
	if is_entrance:
		return
	_apply(false, false)


## Nothing lies behind this entrance any more (the room before it was unloaded): the gap blocks.
## Instant, without effects.
func block() -> void:
	_apply(false, true)


## Is an entrance passable? Exits: is_open.
func is_passable() -> bool:
	return is_open


## The entrance of a room (its Door child with is_entrance), null without one.
static func entrance_of(room: Node) -> Door:
	if room == null or not is_instance_valid(room):
		return null
	for child in room.get_children():
		if child is Door and (child as Door).is_entrance:
			return child
	return null


## A blocked entrance in the south wall is part of that wall's lip: it blocks from the lip's walkable
## band (RockTerrain.LIP_WALK) down like the rock beside it, so a player walking along the wall's top
## edge passes it without a step (bug report 17.10.2026 #5d991188). Every other door blocks its tile.
func _fit_shape() -> void:
	var lip := is_entrance and side == RoomTiles.DoorSide.SOUTH
	var rect := _shape.shape as RectangleShape2D
	# The walkable band at the top of a lip: RockTerrain.LIP_WALK art px.
	var height := TILE - RockTerrain.LIP_WALK * SpriteStrip.PIXEL_SCALE if lip else TILE
	if rect == null or not is_equal_approx(rect.size.y, height):
		# Own shape: the scene's shape is shared by every door.
		rect = RectangleShape2D.new()
		rect.size = Vector2(TILE, height)
		_shape.shape = rect
	_shape.position = Vector2(TILE * 0.5, TILE - height * 0.5)


func get_blocking_rect() -> Rect2:
	var size := (_shape.shape as RectangleShape2D).size
	return Rect2(_shape.position - size * 0.5, size)


func set_open_instant(value: bool) -> void:
	_apply(value, true)


func _copy_way() -> void:
	style.mode = way_mode
	style.way_color = way_color


func _apply(value: bool, instant: bool) -> void:
	is_open = value
	if not is_node_ready():
		return
	_shape.set_deferred("disabled", value)
	state_changed.emit(value, instant)

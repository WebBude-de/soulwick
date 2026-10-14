class_name Door
extends StaticBody2D
## One-tile door on the world layer. Node origin = top-left corner of its tile.
## Logic only: open/closed and the collision. Looks, particles, light and sound live in DoorView
## ($View), which follows state_changed (ROADMAP_AUSBAU D1, decisions separate from effects).
## Biome and destination come from outside: configure() / configure_for_room() / set_destination().
## The way behind an exit door (R5): show_way() puts the mode symbol over it and a light cone in the
## mode colour in front of it (DoorSigns decides both from the prepared next room).

## Emitted on every open()/close()/set_open_instant(); instant = no animation or effects.
signal state_changed(open: bool, instant: bool)

var is_open := false
## Look of the door. Unconfigured doors use the crypt style.
var style: DoorStyle = DoorStyle.for_door(DoorStyle.DEFAULT_BIOME)
## Entrance doors sit in the south wall: frame and leaf only, no torches and no sign.
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
	is_configured = true
	_copy_way()
	if is_node_ready():
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


func close() -> void:
	_apply(false, false)


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

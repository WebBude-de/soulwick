class_name Door
extends StaticBody2D
## One-tile door on the world layer. Node origin = top-left corner of its tile.
## Logic only: open/closed and the collision. Looks, particles, light and sound live in DoorView
## ($View), which follows state_changed (ROADMAP_AUSBAU D1, decisions separate from effects).
## Biome and destination come from outside: configure() / configure_for_room() / set_destination().

## Emitted on every open()/close()/set_open_instant(); instant = no animation or effects.
signal state_changed(open: bool, instant: bool)

var is_open := false
## Look of the door. Unconfigured doors use the crypt style.
var style: DoorStyle = DoorStyle.for_door(DoorStyle.DEFAULT_BIOME)
## Entrance doors sit in the south wall: frame and leaf only, no torches and no sign.
var is_entrance := false
## Becomes true with configure(). Only configured doors play their own sounds: before D1 is
## wired in, RoomController still plays "door_open" itself.
var is_configured := false

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var view: DoorView = $View


func _ready() -> void:
	view.setup(_sprite)
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


func open() -> void:
	_apply(true, false)


func close() -> void:
	_apply(false, false)


func set_open_instant(value: bool) -> void:
	_apply(value, true)


func _apply(value: bool, instant: bool) -> void:
	is_open = value
	if not is_node_ready():
		return
	_shape.set_deferred("disabled", value)
	state_changed.emit(value, instant)

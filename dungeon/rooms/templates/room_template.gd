class_name RoomTemplate
extends Resource
## Metadata of one combat room template (KONZEPT_RAEUME §9.2): room kind, shape, size class, door
## sides, spawn points and allowed biomes. Written by tools/generate_room_templates.py next to the
## scene (dungeon/rooms/templates/<id>.tres) and listed in combat_catalog.tres (RoomCatalog).
## The scene stays the source of the layout; this resource only describes it, so the catalog can
## choose without instantiating rooms. Kind and size are also set on the scene's RoomController.

## Floor plan of a template (KONZEPT_RAEUME §3.2). Never shown in the game (D-100).
enum Shape { RECTANGLE, L_SHAPE, CROSS, RING, TWO_CHAMBERS, PILLAR_HALL, CATACOMB }
## Wall of the room a door sits in. Today entrances are south and exits north (stacked rooms);
## A10 adds exits east/west.
enum DoorSide { NORTH, EAST, SOUTH, WEST }

@export var id: StringName
@export var scene: PackedScene
@export var room_kind: RoomSequence.RoomKind = RoomSequence.RoomKind.NORMAL
@export var shape: Shape = Shape.RECTANGLE
@export var size_class: RoomSequence.RoomSize = RoomSequence.RoomSize.S
## Floor size in tiles (RoomTiles.room_size).
@export var room_size := Vector2i(15, 9)
@export var entrance_side: DoorSide = DoorSide.SOUTH
@export var exit_sides: Array[DoorSide] = [DoorSide.NORTH]
## Spawn marker tiles of the scene (same order as SpawnPoints/Spawn1..n).
@export var spawn_tiles: Array[Vector2i] = []
## Markers in dead ends (catacomb ambush, KONZEPT_RAEUME §3.2); a subset of spawn_tiles.
@export var ambush_tiles: Array[Vector2i] = []
## Treasure chest in the deepest dead end (catacomb); (-1, -1) = none.
@export var chest_tile := Vector2i(-1, -1)
## BiomeData.id values this template may appear in; empty = every biome.
@export var allowed_biomes: Array[StringName] = []


func allows_biome(biome_id: StringName) -> bool:
	return allowed_biomes.is_empty() or biome_id == &"" or allowed_biomes.has(biome_id)


func has_chest() -> bool:
	return chest_tile.x >= 0


## Template of a live room (by its scene), null for rooms outside the generated catalog.
static func of(room: Node) -> RoomTemplate:
	return RoomCatalog.find_template_of(room)


## Name shown when a room with gameplay of its own is entered (D-110): "Arena", "Abgrund",
## "Katakombe"; empty for normal combat rooms of every other shape (D-100: shapes stay unnamed).
static func get_room_name(kind: int, template: RoomTemplate) -> String:
	match kind:
		RoomSequence.RoomKind.ARENA:
			return "Arena"
		RoomSequence.RoomKind.CHASM:
			return "Abgrund"
	if template != null and template.shape == Shape.CATACOMB:
		return "Katakombe"
	return ""


## Code/test name of a shape (never shown to the player, D-100).
static func get_shape_name(value: int) -> String:
	match value:
		Shape.L_SHAPE:
			return "L-Form"
		Shape.CROSS:
			return "Kreuz"
		Shape.RING:
			return "Ring"
		Shape.TWO_CHAMBERS:
			return "Zwei Kammern"
		Shape.PILLAR_HALL:
			return "Säulenhalle"
		Shape.CATACOMB:
			return "Katakombe"
	return "Rechteck"

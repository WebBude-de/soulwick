class_name RoomTemplate
extends Resource
## Metadata of one combat room template (KONZEPT_RAEUME §9.2): room kind, shape, size class, door
## sides, spawn points and allowed biomes. Written by tools/generate_room_templates.py next to the
## scene (dungeon/rooms/templates/<id>.tres) and listed in combat_catalog.tres (RoomCatalog).
## The scene stays the source of the layout; this resource only describes it, so the catalog can
## choose without instantiating rooms. Kind and size are also set on the scene's RoomController.
## Since R1 (D-120) every template comes from a hand-made floor plan (dungeon/rooms/plans/*.txt):
## plan_id names it, mode says which game mode the plan was built for (only "clear" and "arena"
## plans are drawn for plain fights, the mode plans wait for their mode, R4), role tells combat
## rooms from boss, miniboss, rest and campfire rooms (RoomCatalog.load_plans()), weight scales the
## draw among the candidates.

## Floor plan of a template (KONZEPT_RAEUME §3.2). Never shown in the game (D-100). BRIDGE_HALL ..
## RING_HOLE are the old chasm shapes (A4); PLAN = built from a hand-made plan (R1, every template snow).
enum Shape { RECTANGLE, L_SHAPE, CROSS, RING, TWO_CHAMBERS, PILLAR_HALL, CATACOMB, BRIDGE_HALL, ISLANDS, WALKWAY, RING_HOLE, PLAN }
## Wall of the room a door sits in (same order as RoomTiles.DoorSide). Entrances come from the
## south, west or east, exits lead north, east or west (A10, KONZEPT_RAEUME §7.1).
enum DoorSide { NORTH, EAST, SOUTH, WEST }

## Plan modes (KONZEPT_RAEUME_V2 §2). Plain fights draw MODE_CLEAR (normal kind) and MODE_ARENA.
const MODE_CLEAR := &"clear"
const MODE_ARENA := &"arena"
## Roles of a plan template (RoomCatalog.load_plans for everything except combat).
const ROLE_COMBAT := &"combat"
const ROLE_BOSS := &"boss"
const ROLE_MINIBOSS := &"miniboss"
const ROLE_REST := &"rest"
const ROLE_CAMPFIRE := &"campfire"

@export var id: StringName
@export var scene: PackedScene
@export var room_kind: RoomSequence.RoomKind = RoomSequence.RoomKind.NORMAL
@export var shape: Shape = Shape.RECTANGLE
@export var size_class: RoomSequence.RoomSize = RoomSequence.RoomSize.S
## Floor size in tiles (RoomTiles.room_size).
@export var room_size := Vector2i(15, 9)
## The template's own entrance wall (its scene's entrance_x lies there).
@export var entrance_side: DoorSide = DoorSide.SOUTH
## Walls with an exit place.
@export var exit_sides: Array[DoorSide] = [DoorSide.NORTH]
## Walls the room may be entered through (south always; west/east where the template has a place).
@export var entrance_sides: Array[DoorSide] = [DoorSide.SOUTH]
## Every door place of the scene: x = DoorSide, y = place along the wall (same as its
## RoomTiles.door_slots). North places beyond the first serve the second door of a branch (D-105).
@export var door_slots: Array[Vector2i] = []
## Spawn marker tiles of the scene (same order as SpawnPoints/Spawn1..n).
@export var spawn_tiles: Array[Vector2i] = []
## First treasure chest of the plan (cell 'c'); (-1, -1) = none.
@export var chest_tile := Vector2i(-1, -1)
## BiomeData.id values this template may appear in; empty = every biome.
@export var allowed_biomes: Array[StringName] = []
## First room number this template may appear in (catacomb from room 2, chasm from room 6; the
## first room of a run stays a plain one). RoomCatalog.pick filters by it when given a room.
@export var min_room := 1
## Plan file the template was built from (dungeon/rooms/plans/, R1); empty for old templates.
@export var plan_id: StringName = &""
## Game mode the plan was built for (MODE_CLEAR, MODE_ARENA, &"escort", &"flame", &"relic",
## &"souls", &"rifts", &"hunt", &"beacon", &"collapse", &"boss", &"rest", &"campfire").
@export var mode: StringName = MODE_CLEAR
## ROLE_COMBAT, ROLE_BOSS, ROLE_MINIBOSS, ROLE_REST or ROLE_CAMPFIRE.
@export var role: StringName = ROLE_COMBAT
## Relative weight among the candidates of one draw (plan header "weight"). TESTWERT per plan.
@export var weight := 1.0
## Rest rooms: RoomSequence.SpecialType values the plan is made for (shop, weapon, fountain, altar).
@export var special_types: Array[int] = []
## A mirrored copy of the plan (generator option "mirror").
@export var mirrored := false
## What the walls are made of (plan header "rock", M1): RoomTiles.RockStyle WALL (masonry) or BLOB
## (cave rock). Same value as the scene's RoomTiles.rock_style.
@export var rock_style := 0
## Plan header "cave": a cave mouth instead of an arch at the doors (door art: M2).
@export var cave := false


func allows_room(room_index: int) -> bool:
	return room_index <= 0 or room_index >= min_room


## Drawn for a plain fight (normal or arena kind, no special mode)?
func is_plain_fight() -> bool:
	return role == ROLE_COMBAT and (mode == MODE_CLEAR or mode == MODE_ARENA or mode == &"")


func allows_mode(wanted: StringName) -> bool:
	if wanted == &"":
		return is_plain_fight()
	return mode == wanted


func allows_biome(biome_id: StringName) -> bool:
	return allowed_biomes.is_empty() or biome_id == &"" or allowed_biomes.has(biome_id)


func has_chest() -> bool:
	return chest_tile.x >= 0


## May the room be entered through this wall? side < 0 = any (no filter).
func allows_entrance(side: int) -> bool:
	return side < 0 or entrance_sides.has(side)


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
		Shape.BRIDGE_HALL:
			return "Brückenhalle"
		Shape.ISLANDS:
			return "Inseln"
		Shape.WALKWAY:
			return "Steg"
		Shape.RING_HOLE:
			return "Ring um ein Loch"
		Shape.PLAN:
			return "Plan"
	return "Rechteck"

class_name CorridorDressing
extends Node2D
## Corridors with character (R5, 05_tueren.md, 04_wandsystem.md): the way between two doors is no
## longer a bare strip of floor. Each corridor gets a style, chosen per run and room, and dressed
## from the plan decoration (DecoProp) in the biome's colours:
##   - STRAIGHT: a plain way with a small touch (bones, mushrooms, rubble),
##   - DRIP: a drip from the ceiling over a puddle (embers: fallen rubble instead),
##   - NICHE: a lit niche in the wall front above a side corridor (north corridors have no front:
##     a drip instead),
##   - STAIRS: a few steps down in the middle of the corridor (Höhenversatz).
## M2: the corridor is one tile - the entrance gap in this room's wall (the entrance has no leaf any
## more) - plus any extra tiles of a longer corridor. Playtest 14.10.2026: no decoration in corridors
## and gates at all (DRESS_CORRIDORS off); the styles stay for the corridor art of SPRITES_V8 §1.
## Placeholders until the corridor art of SPRITES_V8 §1 arrives (corridor_<biome>_<style>.png); only
## floor decals and wall fixtures, nothing blocks the way. Optics only: the style comes from a hash of
## the run seed and the room number, never from the dungeon RNG (the room stream stays the same).

enum Style { STRAIGHT, DRIP, NICHE, STAIRS }

const NODE_NAME := &"CorridorDressing"
## Corridors get no decoration of their own (playtest 14.10.2026). Design switch.
const DRESS_CORRIDORS := false
## Weights of the styles (TESTWERTE).
const STYLE_WEIGHTS: Dictionary[Style, float] = {
	Style.STRAIGHT: 0.35,
	Style.DRIP: 0.25,
	Style.NICHE: 0.2,
	Style.STAIRS: 0.2,
}
const TILE := RoomTiles.TILE_WORLD
## Small touch of a straight corridor per biome (DecoProp items).
const STRAIGHT_ITEMS: Dictionary[StringName, StringName] = {
	&"crypt": &"bones_1",
	&"slime_grotto": &"mushrooms",
	&"shadow_realm": &"bone_pile",
	&"ember_forge": &"rubble_1",
}
## Water of a drip per biome (like the plan drips, generate_room_templates.py WATER_TINTS).
const WATER_TINTS: Dictionary[StringName, Color] = {
	&"crypt": Color(0.75, 0.82, 1.0),
	&"slime_grotto": Color(0.72, 1.0, 0.72),
	&"shadow_realm": Color(0.72, 0.6, 1.0),
	&"ember_forge": Color(1.0, 0.62, 0.42),
}
## Stone of steps and niches per biome (the art is crypt grey).
const STONE_TINTS: Dictionary[StringName, Color] = {
	&"crypt": Color(1, 1, 1),
	&"slime_grotto": Color(0.78, 0.95, 0.85),
	&"shadow_realm": Color(0.78, 0.68, 0.95),
	&"ember_forge": Color(1.0, 0.82, 0.72),
}

var style: Style = Style.STRAIGHT
var biome_id: StringName = &"crypt"
## Room-local floor tiles of the corridor, from this room's entrance gap outwards.
var tiles: Array[Vector2i] = []
## Direction from this room's door along the corridor (RoomTiles.SIDE_DIRECTIONS of its side).
var direction := Vector2i.DOWN


## Style of the corridor into room room_index through its entrance wall (the two ways of a branch
## differ) in a run with run_seed (hash, no dungeon RNG). NICHE needs a side corridor; a north corridor
## takes a drip instead.
static func pick_style(run_seed: int, room_index: int, entrance_side: int) -> Style:
	var horizontal := entrance_side == RoomTiles.DoorSide.WEST or entrance_side == RoomTiles.DoorSide.EAST
	var roll := float(absi(hash([run_seed, room_index, entrance_side, "corridor"])) % 10000) / 10000.0
	var total := 0.0
	for weight: float in STYLE_WEIGHTS.values():
		total += weight
	var rest := roll * total
	var picked := Style.STRAIGHT
	for key: Style in STYLE_WEIGHTS:
		rest -= STYLE_WEIGHTS[key]
		if rest < 0.0:
			picked = key
			break
	if picked == Style.NICHE and not horizontal:
		return Style.DRIP
	return picked


## Room-local corridor tiles from the entrance gap of room (side, place) up to the exit door of the
## room before it (room-local too, not included), walking out of the entrance; empty if they do not
## line up. M2: the gap itself is the corridor (the entrance has no leaf).
static func tiles_between(entrance: Vector2i, size: Vector2i, other_door: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var step: Vector2i = RoomTiles.SIDE_DIRECTIONS[entrance.x]
	var tile := RoomTiles.door_tile_of(entrance.x, entrance.y, size)
	for i in RoomTiles.MAX_CORRIDOR_EXTRA + 8:
		if tile == other_door:
			return result
		result.append(tile)
		tile += step
	return []


## Dresses the corridor in front of room's entrance. other_door: the exit door of the room before it
## in room-local tiles of room. Returns null when there is nothing to dress.
static func attach(room: Node2D, other_door: Vector2i, run_seed: int, room_index: int, biome: StringName) -> CorridorDressing:
	var room_tiles := room.get_node("Tiles") as RoomTiles
	var between := tiles_between(room_tiles.get_entrance_door(), room_tiles.room_size, other_door)
	# The entrance gap stays bare; a one-tile corridor gets no dressing at all.
	if not DRESS_CORRIDORS or between.size() <= 1:
		return null
	between = between.slice(1)
	var dressing := CorridorDressing.new()
	dressing.name = NODE_NAME
	dressing.tiles = between
	dressing.direction = RoomTiles.SIDE_DIRECTIONS[room_tiles.entrance_side]
	dressing.biome_id = biome if STRAIGHT_ITEMS.has(biome) else &"crypt"
	dressing.style = pick_style(run_seed, room_index, room_tiles.entrance_side)
	room.add_child(dressing)
	return dressing


func is_horizontal() -> bool:
	return direction.y == 0


func _ready() -> void:
	if tiles.is_empty():
		return
	var middle: Vector2i = tiles[tiles.size() / 2]
	match style:
		Style.DRIP:
			if biome_id == &"ember_forge":
				_add(&"rubble_2", _centre(middle) + Vector2(-10, 12))
				_add(&"rubble_1", _centre(middle) + Vector2(14, 18), Color.WHITE, true)
			else:
				_add(&"puddle", _centre(middle) + Vector2(0, 6), WATER_TINTS[biome_id])
				_add(&"drip", _centre(middle) + Vector2(4, 4))
		Style.NICHE:
			# The wall front above a side corridor tile; candles at its foot.
			var front := middle + Vector2i.UP
			_add(&"wall_niche", Vector2((front.x + 0.5) * TILE, (front.y + 1) * TILE), STONE_TINTS[biome_id])
			if biome_id != &"slime_grotto":
				_add(&"candles", _centre(middle) + Vector2(18, 20))
		Style.STAIRS:
			var stairs := _add(&"stairs", _centre(middle), STONE_TINTS[biome_id])
			# Steps across the way: turned for a side corridor, falling away from this room's door.
			stairs.rotation = Vector2.DOWN.angle_to(Vector2(direction))
		_:
			_add(STRAIGHT_ITEMS[biome_id], _centre(middle) + Vector2(-12, 14), Color.WHITE, absi(hash(middle)) % 2 == 0)


func get_props() -> Array[DecoProp]:
	var props: Array[DecoProp] = []
	for child in get_children():
		if child is DecoProp:
			props.append(child)
	return props


func _add(item: StringName, pos: Vector2, tint := Color.WHITE, flip := false) -> DecoProp:
	var prop := DecoProp.new()
	prop.name = String(item).to_pascal_case()
	prop.item = item
	prop.tint = tint
	prop.flip = flip
	prop.position = pos
	add_child(prop)
	return prop


static func _centre(tile: Vector2i) -> Vector2:
	return RoomTiles.tile_center(tile)

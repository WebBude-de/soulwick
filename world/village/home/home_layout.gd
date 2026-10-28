class_name HomeLayout
extends RefCounted
## Where everything stands in the home interior (KE8, D-205 "eingerichtet, aber basic cozy",
## Antwort 20 §1, Mockup 14b): a room of 15×9 tiles (32 art px, drawn at SCALE like the village),
## two rows of panelled back wall with the moon window, the starting furniture, the candle altar,
## the mirror and the door out at the bottom. Positions are the foot point (pivot bottom centre) in
## art px from the room's top left; the world multiplies by SCALE. All values TESTWERT; WK7 moves the
## furniture onto the decoration system later.

const SCALE := 2.0
const TILE := 32
const COLS := 15
const ROWS := 9
## Back wall rows (row 0 upper wall, row 1 panelling with the window).
const WALL_ROWS := 2
## Side and bottom walls are drawn beams (art px) until the tiles arrive (SPRITES_V13 Teil C).
const SIDE_WALL := 6
const BOTTOM_WALL := 8
const WINDOW_COL := 2
const DOOR_COL := 7

## Where a prop is drawn: ROOM props sort with the players (y-sort), FLOOR lies under everything
## (rug, basket), WALL hangs on the back wall.
const ROOM := &"room"
const FLOOR := &"floor"
const WALL := &"wall"

## Starting furniture (Antwort 20 §1). "solid": footprint in art px that blocks walking (none: walk
## over or behind it); "optional": only placed once the art exists (no placeholder).
const FURNITURE: Array[Dictionary] = [
	{"name": "bed", "at": Vector2(52, 150), "solid": Vector2(60, 22)},
	{"name": "nightstand", "at": Vector2(98, 126), "solid": Vector2(14, 8)},
	{"name": "fireplace", "at": Vector2(392, 74), "solid": Vector2(60, 10)},
	{"name": "armchair", "at": Vector2(440, 130), "solid": Vector2(22, 10)},
	{"name": "pet_bed", "at": Vector2(392, 104), "layer": FLOOR},
	{"name": "rug_round", "at": Vector2(300, 178), "layer": FLOOR},
	{"name": "shelf", "at": Vector2(268, 74), "solid": Vector2(30, 10)},
	{"name": "bookshelf_full", "at": Vector2(236, 74), "solid": Vector2(30, 10), "optional": true},
	{"name": "chest", "at": Vector2(168, 232), "solid": Vector2(28, 12)},
	{"name": "plant_pot", "at": Vector2(458, 264), "solid": Vector2(12, 8)},
	{"name": "broom", "at": Vector2(468, 94)},
	{"name": "window_sill_flower", "at": Vector2(96, 64), "layer": WALL},
	{"name": "wall_picture", "at": Vector2(200, 46), "layer": WALL},
]
## The candle altar with the talent tree, its footprint; the mirror (D-152).
const ALTAR_AT := Vector2(300, 134)
const ALTAR_SOLID := Vector2(26, 10)
const MIRROR_AT := Vector2(160, 76)
## The door out (bottom wall, DOOR_COL) and where a player arrives (out of the door's reach).
const DOOR_AT := Vector2(240, 288)
const DOOR_USE_AT := Vector2(240, 276)
const DOOR_USE_RADIUS := 14.0
const SPAWN_AT := Vector2(240, 236)

## Light (Antwort 20 §1): ambient 40 % with a soft blue (#2d2250) at night, brighter by day; the
## player's own circle comes from Flint. Radii in tiles of TILE art px.
const DARKNESS_NIGHT := 0.6
const DARKNESS_DAY := 0.35
const DARK_COLOR := Color("#2d2250")
const FLINT_RADIUS := 150.0
const FIRE_COLOR := Color("#ff8a3c")
const FIRE_RADIUS_TILES := 5.0
const FIRE_FLICKER := 0.03
const FIRE_AT := Vector2(392, 52)
const MOON_COLOR := Color("#c8beff")
const SUN_COLOR := Color("#fff1c8")
const MOON_RADIUS_TILES := 2.5
const MOON_INTENSITY := 0.45
const MOON_FLOOR_AT := Vector2(118, 176)
const NIGHT_LAMP_COLOR := Color("#ffd166")
const NIGHT_LAMP_RADIUS_TILES := 2.0
const NIGHT_LAMP_AT := Vector2(98, 106)
## Altar candles in the path colours (TalentTreeArt.PATH_COLORS), 1.5 tiles, brighter when ready.
const ALTAR_LIGHT_RADIUS_TILES := 1.5
const ALTAR_LIGHT_IDLE := 0.5
const ALTAR_LIGHT_READY := 0.95
const ALTAR_CANDLES: Array[Vector2] = [Vector2(-8, -34), Vector2(0, -38), Vector2(8, -34)]


## World px of an art px position in the room.
static func to_world(art: Vector2) -> Vector2:
	return art * SCALE


static func tiles_to_world(tiles: float) -> float:
	return tiles * TILE * SCALE


## The whole room in world px (camera limits).
static func room_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(COLS * TILE, ROWS * TILE) * SCALE)


## Walkable floor in art px (inside the walls).
static func floor_rect() -> Rect2:
	var top := WALL_ROWS * TILE + 6
	return Rect2(SIDE_WALL, top, COLS * TILE - SIDE_WALL * 2, ROWS * TILE - BOTTOM_WALL - top)


static func furniture_names() -> Array[String]:
	var names: Array[String] = []
	for item in FURNITURE:
		names.append(String(item["name"]))
	return names

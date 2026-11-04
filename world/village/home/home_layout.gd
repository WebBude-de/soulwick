class_name HomeLayout
extends RefCounted
## Where everything stands in the home interior (KE8, D-205 "eingerichtet, aber basic cozy",
## Antwort 20 §1, Mockup 14b): a small room of 11×7 tiles (32 art px, drawn at SCALE like the
## village), two rows of panelled back wall with three windows, the starting furniture, the candle
## altar under the middle window, the mirror and the open doorway with its mat in the front wall.
## Positions are the foot point (pivot bottom centre) in art px from the room's top left; the world
## multiplies by SCALE. All values TESTWERT.
## WK7: the furniture is decoration now (DecorState.STARTER_HOME, DecorLayer, DecorGrid on the same
## 32 px tiles); here stay the fixed things (altar, mirror, broom, the catalog stand, the door) and
## the cells the furniture keeps free for them.
## KE8b (playtest 04.11.2026 "viel zu groß, riesige leere Fläche", D-proposal in the report): the
## room shrank from 15×9 to 11×7 tiles; the camera keeps the village zoom (nothing looks bigger than
## outside), the room sits in the middle of the view with the dark around it like a doll's house.

const SCALE := 2.0
const TILE := 32
## TESTWERT (KE8b): 11×7 tiles (was 15×9), 5 floor rows.
const COLS := 11
const ROWS := 7
## Back wall rows (row 0 upper wall, row 1 panelling with the windows).
const WALL_ROWS := 2
## Side walls are drawn beams; the front wall is a low cut wall with the doorway (art px).
const SIDE_WALL := 6
const BOTTOM_WALL := 14
## TESTWERT (KE8b): three windows in the back wall (column of each window's middle); the wall cell
## under each one takes only window boxes (DecorGrid.WINDOW_KINDS).
const WINDOW_COLS: Array[int] = [2, 5, 7]
## Lower edge of the window sill (art px from the top): the windows sit across both wall rows.
const WINDOW_SILL_Y := 54
const DOOR_COL := 5

## Where a prop is drawn: ROOM props sort with the players (y-sort), FLOOR lies under everything
## (rug, basket), WALL hangs on the back wall.
const ROOM := &"room"
const FLOOR := &"floor"
const WALL := &"wall"

## Fixed props of the KE8 room that are no catalog furniture (Antwort 20 §1: the broom, KE8b: it
## leans beside the doorway).
## "solid": footprint in art px that blocks walking (none: walk over or behind it).
const FIXED_PROPS: Array[Dictionary] = [
	{"name": "broom", "at": Vector2(206, 208)},
]
## The candle altar with the talent tree under the middle window (the first thing seen from the
## door), its footprint; the mirror (D-152) under the right window. Both stand in the middle of a tile.
const ALTAR_AT := Vector2(176, 94)
const ALTAR_SOLID := Vector2(26, 10)
const MIRROR_AT := Vector2(240, 92)
## WK7: the catalog stand ("Zuhause einrichten", DecorStation) left of the doorway, in view on
## arrival (KE8b: it was easy to miss at the far end of the old front wall).
const DECOR_STATION_AT := Vector2(144, 208)
## WK7 grid (tiles of TILE art px, DecorGrid.for_home): the door's tile (nothing on it, the way check
## starts here), tiles that block walking without furniture (altar, catalog stand, broom), tiles only
## flat pieces may cover (mirror, spawn) and tiles that must keep a free side (altar, mirror, stand).
const DOOR_CELL := Vector2i(5, 6)
const FIXED_CELLS: Array[Vector2i] = [Vector2i(5, 2), Vector2i(4, 6), Vector2i(6, 6)]
const FLAT_ONLY_CELLS: Array[Vector2i] = [Vector2i(7, 2), Vector2i(5, 5)]
const ACCESS_CELLS: Array[Vector2i] = [Vector2i(5, 2), Vector2i(7, 2), Vector2i(4, 6)]
## The doorway (front wall, DOOR_COL): opening width, the mat in front of it (art px) and where a
## player arrives (out of the door's reach).
const DOOR_OPENING := 24
const DOOR_MAT := Vector2i(26, 10)
const DOOR_AT := Vector2(176, 224)
const DOOR_USE_AT := Vector2(176, 204)
const DOOR_USE_RADIUS := 12.0
const SPAWN_AT := Vector2(176, 168)

## Light (Antwort 20 §1, KE8b "aus dem Fenster ist es immer Nacht"): the room follows the same
## clock as the village (VillageDaylight.night_amount): bright and warm by day, violet at dusk, a
## soft blue (#2d2250) at night; the player's own circle comes from Flint. Radii in tiles of TILE
## art px. TESTWERT: by day only a light shade (a room is a bit darker than the open village).
const DARKNESS_NIGHT := 0.55
const DARKNESS_DAY := 0.12
const DARK_COLOR := Color("#2d2250")
const DARK_COLOR_DAY := Color("#2a1c16")
const DARK_COLOR_DUSK := Color("#2a1430")
const FLINT_RADIUS := 150.0
## The fireplace (catalog piece) is the main light (DecorCatalog.LIGHT_RADIUS_TILES: 5 tiles).
const FIRE_COLOR := Color("#ff8a3c")
const FIRE_RADIUS_TILES := 5.0
## Light through each window: sun by day, warm orange at dusk, moon at night; a patch on the floor.
const MOON_COLOR := Color("#c8beff")
const SUN_COLOR := Color("#fff1c8")
const DUSK_LIGHT_COLOR := Color("#ffb070")
const MOON_RADIUS_TILES := 1.5
const MOON_INTENSITY := 0.4
const SUN_INTENSITY := 0.55
## Where a window's light patch lies (art px below and right of the window's middle).
const WINDOW_LIGHT_DROP := Vector2(14, 84)
## TESTWERT: the room checks the clock this often (s) and follows dusk and dawn while one stays.
const CLOCK_INTERVAL := 20.0
## The night light beside the bed (the starter floor lamp, a catalog piece: 2 tiles, warm yellow).
const NIGHT_LAMP_COLOR := Color("#ffd166")
const NIGHT_LAMP_RADIUS_TILES := 2.0
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


## Foot point (art px) of the window with its middle in column col: on the sill.
static func window_foot(col: int) -> Vector2:
	return Vector2(col * TILE + TILE * 0.5, WINDOW_SILL_Y)


## The lit patch on the floor under a window (art px).
static func window_light_point(col: int) -> Vector2:
	return window_foot(col) + WINDOW_LIGHT_DROP


## Darkness of the room for a night amount (0 = day, 1 = night).
static func darkness_for(night: float) -> float:
	return lerpf(DARKNESS_DAY, DARKNESS_NIGHT, clampf(night, 0.0, 1.0))


## Colour of the room's shade: warm by day, violet at dusk, blue at night.
static func dark_color_for(night: float) -> Color:
	night = clampf(night, 0.0, 1.0)
	if night < 0.5:
		return DARK_COLOR_DAY.lerp(DARK_COLOR_DUSK, night * 2.0)
	return DARK_COLOR_DUSK.lerp(DARK_COLOR, (night - 0.5) * 2.0)


## Colour of the light through the windows: sun, dusk, moon.
static func window_light_color(night: float) -> Color:
	night = clampf(night, 0.0, 1.0)
	if night < 0.5:
		return SUN_COLOR.lerp(DUSK_LIGHT_COLOR, night * 2.0)
	return DUSK_LIGHT_COLOR.lerp(MOON_COLOR, (night - 0.5) * 2.0)


## Walkable floor in art px (inside the walls).
static func floor_rect() -> Rect2:
	var top := WALL_ROWS * TILE + 6
	return Rect2(SIDE_WALL, top, COLS * TILE - SIDE_WALL * 2, ROWS * TILE - BOTTOM_WALL - top)


class_name LightfireRules
extends RefCounted
## Rules and numbers of "Lichtfeuer" (RAEUME §3.9, R4b; replaces the torch room and the
## stone guardian variant of D-116). No nodes, unit-testable; LightfireMode, RoomTorch and
## StoneGuardian only apply them. Whether a point is lit is LightQuery's decision.

# --- Fires ---

## Torch stands of a room without stands in its plan (inclusive range, one roll of the mode RNG).
const FIRE_COUNT := Vector2i(4, 6)  # TESTWERT
const FIRE_MIN_TILE_DISTANCE := 4.0
const FIRE_DOOR_CLEARANCE := 3.0
## Light of a burning stand (design answer: "jedes entzündete Feuer schlägt eine warme Insel,
## Radius 4 Kacheln").
const FIRE_LIGHT_RADIUS := 240.0  # TESTWERT
## Default light of a torch stand outside this mode (RoomTorch.build without a radius).
const TORCH_LIGHT_RADIUS := 190.0
## The room is dark except for the light circle: the players' circle starts at this factor and grows
## to the room's normal circle when every fire burns.
const VISION_FACTOR := 0.5  # TESTWERT

# --- Stone guardians ---

## Guardians of a room without guardians in its plan (inclusive range, one roll).
const GUARDIAN_COUNT := Vector2i(2, 4)  # TESTWERT
## Co-op (D-109, set in MP5): extra guardians per additional player.
const GUARDIANS_PER_EXTRA_PLAYER := 1  # TESTWERT
## Guardians stand at least this many tiles from the entrance and from each other.
const GUARDIAN_ENTRANCE_TILES := 6.0
const GUARDIAN_MIN_TILE_DISTANCE := 3.0
## A frozen guardian stays frozen until it was this long in the dark (no flicker at the edge).
const GUARDIAN_THAW_DELAY := 0.3  # TESTWERT
## The players' own (small) light circles hold the guardians too (D-116: every light counts), so a
## room without a single fire lit can still be finished; the fires make the safe light big. Only the
## fires would be the stricter reading of "im Dunkeln unbesiegbar" (open question in the R4b report).
const PLAYER_LIGHT_HOLDS_GUARDIANS := true
## The normal enemies of the room are few (the guardians are the main threat).
const ROOM_COUNT_FACTOR := 0.5  # TESTWERT


# --- Fires ---

## Fires of a room without plan stands from one roll in [0, 1), at most available spots.
static func fire_count(roll: float, available: int) -> int:
	var span := FIRE_COUNT.y - FIRE_COUNT.x + 1
	return mini(available, FIRE_COUNT.x + mini(floori(roll * span), span - 1))


## Light circle factor of the players with lit of total fires burning.
static func vision_factor(lit: int, total: int) -> float:
	if total <= 0:
		return 1.0
	return lerpf(VISION_FACTOR, 1.0, clampf(float(lit) / float(total), 0.0, 1.0))


static func all_lit(lit: int, total: int) -> bool:
	return total > 0 and lit >= total


## Success: every fire burns and every guardian is broken.
static func is_complete(lit: int, total: int, guardians_left: int) -> bool:
	return all_lit(lit, total) and guardians_left <= 0


# --- Stone guardians ---

## Guardians of a room without plan guardians from one roll in [0, 1) and the number of players.
static func guardian_count(roll: float, players: int) -> int:
	var span := GUARDIAN_COUNT.y - GUARDIAN_COUNT.x + 1
	var base := GUARDIAN_COUNT.x + mini(floori(roll * span), span - 1)
	return base + extra_guardians(players)


static func extra_guardians(players: int) -> int:
	return GUARDIANS_PER_EXTRA_PLAYER * (maxi(1, players) - 1)


## Decision for one frame: frozen (in the light) or moving. dark_time = seconds in the dark so far.
static func guardian_frozen(lit: bool, was_frozen: bool, dark_time: float) -> bool:
	if lit:
		return true
	return was_frozen and dark_time < GUARDIAN_THAW_DELAY


## Only a frozen guardian takes damage (in the dark it is stone).
static func guardian_vulnerable(frozen: bool) -> bool:
	return frozen

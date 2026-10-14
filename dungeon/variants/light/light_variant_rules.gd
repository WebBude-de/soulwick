class_name LightVariantRules
extends RefCounted
## Pure rules and numbers of the light variants (A9, KONZEPT_RAEUME §4.3, §4.4, §4.7, D-101, D-109):
## stone guardians, lantern bearer and torch room. No nodes, unit-testable. Whether a point is lit
## is LightQuery's decision; these functions decide what follows from it. The variant nodes only
## add the effects. Co-op values are parameters prepared for MP5 (D-109); with one player every
## factor is neutral.

# --- Stone guardians (§4.3, crypt and shadow realm) ---

## Guardians per room (inclusive range, one roll of the variant RNG).
const GUARDIAN_COUNT := Vector2i(2, 4)  # TESTWERT
## Co-op (D-109, set in MP5): extra guardians per additional player.
const GUARDIANS_PER_EXTRA_PLAYER := 1  # TESTWERT
## The normal enemies of a guardian room are fewer (the guardians are the main threat).
const GUARDIAN_ROOM_COUNT_FACTOR := 0.7  # TESTWERT
## Guardians stand at least this many tiles from the entrance and from each other.
const GUARDIAN_ENTRANCE_TILES := 6.0
const GUARDIAN_MIN_TILE_DISTANCE := 3.0
## A frozen guardian stays frozen until it was this long in the dark (no flicker at the edge).
const GUARDIAN_THAW_DELAY := 0.3  # TESTWERT

# --- Lantern bearer (§4.4, every biome) ---

## A player brings the lantern to the socket within this time after the door shut -> bonus chest.
## Later the socket calls it home by itself (no bonus), so the room can always be finished.
const LANTERN_TIME := 40.0  # TESTWERT
## The carrier walks slower and cannot attack (dash stays).
const LANTERN_CARRY_SPEED_FACTOR := 0.75  # TESTWERT (KONZEPT: -25 %)
## Light of the lantern on the floor and in the hand (clearly bigger than the room's light circle).
const LANTERN_LIGHT_RADIUS := 190.0  # TESTWERT
const LANTERN_CARRIED_RADIUS := 330.0  # TESTWERT
## The lantern room is dark: the players' own light circle times this factor.
const LANTERN_ROOM_VISION_FACTOR := 0.55  # TESTWERT
## First wave smaller; a second one comes out of the dark when the lantern is first picked up.
const LANTERN_ROOM_COUNT_FACTOR := 0.7  # TESTWERT
const LANTERN_WAVE_FACTOR := 0.6  # TESTWERT
const LANTERN_WAVE_MIN := 2
## Enemies of that wave appear at least this far from every player (out of the dark).
const LANTERN_WAVE_MIN_DISTANCE := 220.0
## Share of the enemies that go for the carrier instead of the nearest player (co-op).
const LANTERN_CHASER_SHARE := 0.6  # TESTWERT
## Putting the lantern down this close to the socket sets it in.
const SOCKET_RADIUS := 80.0
## The lantern lies this many tiles inside the entrance; the socket stands in front of the exit.
const LANTERN_ENTRANCE_TILES := 2

# --- Torch room (§4.7, shadow realm only) ---

## Unlit torch stands per room (inclusive range, one roll of the variant RNG).
const TORCH_COUNT := Vector2i(4, 6)  # TESTWERT
const TORCH_MIN_TILE_DISTANCE := 4.0
const TORCH_DOOR_CLEARANCE := 3.0
## Light of a burning torch stand.
const TORCH_LIGHT_RADIUS := 190.0  # TESTWERT
## The room is dark except for the light circle: the players' circle starts at this factor and grows
## to the room's normal circle when every torch burns ("jede vergrößert die Sicht dauerhaft").
const TORCH_ROOM_VISION_FACTOR := 0.5  # TESTWERT
## Enemies inside the light of a burning torch deal this share of their damage.
const TORCH_DAMAGE_FACTOR := 0.8  # TESTWERT (KONZEPT: -20 %)


# --- Stone guardians ---

## Guardians of a room from one roll in [0, 1) and the number of players.
static func guardian_count(roll: float, players: int) -> int:
	var span := GUARDIAN_COUNT.y - GUARDIAN_COUNT.x + 1
	var base := GUARDIAN_COUNT.x + mini(floori(roll * span), span - 1)
	return base + GUARDIANS_PER_EXTRA_PLAYER * (maxi(1, players) - 1)


## Decision for one frame: frozen (in the light) or moving. dark_time = seconds in the dark so far.
static func guardian_frozen(lit: bool, was_frozen: bool, dark_time: float) -> bool:
	if lit:
		return true
	return was_frozen and dark_time < GUARDIAN_THAW_DELAY


## Only a frozen guardian takes damage (in the dark it is stone).
static func guardian_vulnerable(frozen: bool) -> bool:
	return frozen


# --- Lantern ---

static func lantern_bonus_open(elapsed: float) -> bool:
	return elapsed < LANTERN_TIME


## Time is up: the socket calls the lantern home (no bonus).
static func lantern_returns(elapsed: float, socketed: bool) -> bool:
	return not socketed and elapsed >= LANTERN_TIME


static func can_insert(distance_to_socket: float) -> bool:
	return distance_to_socket <= SOCKET_RADIUS


## One roll per enemy: does it go for the carrier?
static func is_chaser(roll: float) -> bool:
	return roll < LANTERN_CHASER_SHARE


static func lantern_wave_size(rolled: int) -> int:
	return maxi(LANTERN_WAVE_MIN, roundi(rolled * LANTERN_WAVE_FACTOR))


## The room stays shut until the lantern is in the socket (KONZEPT: "erst dann öffnet der Ausgang").
static func lantern_holds_room(started: bool, socketed: bool) -> bool:
	return started and not socketed


# --- Torch room ---

## Torches of a room from one roll in [0, 1), at most available spots.
static func torch_count(roll: float, available: int) -> int:
	var span := TORCH_COUNT.y - TORCH_COUNT.x + 1
	return mini(available, TORCH_COUNT.x + mini(floori(roll * span), span - 1))


## Light circle factor of the players with lit of total torches burning.
static func torch_vision_factor(lit: int, total: int) -> float:
	if total <= 0:
		return 1.0
	return lerpf(TORCH_ROOM_VISION_FACTOR, 1.0, clampf(float(lit) / float(total), 0.0, 1.0))


static func enemy_damage_factor(in_torchlight: bool) -> float:
	return TORCH_DAMAGE_FACTOR if in_torchlight else 1.0


## Bonus: every torch burns.
static func torches_complete(lit: int, total: int) -> bool:
	return total > 0 and lit >= total

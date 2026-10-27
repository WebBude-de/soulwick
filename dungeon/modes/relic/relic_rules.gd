class_name RelicRules
extends RefCounted
## Rules and numbers of "Reliquie holen" (RAEUME §3.5, R4b; the carrying of the lantern
## bearer, D-116, lives on in LanternCarry). No nodes, unit-testable; RelicMode, Relic and
## LanternCarry only apply them.

## The carrier walks slower and cannot attack (dash stays).
const CARRY_SPEED_FACTOR := 0.75  # TESTWERT (KONZEPT: langsamer)
## Bonus only if every relic lies on the altar within this time after the fight started; later the
## relics fly home by themselves (no bonus), so the room can always be finished. 40 s like the
## lantern of D-116 (the smoke test fast-forwards 41 s).
const BONUS_TIME := 40.0  # TESTWERT
## Two relics from this room on (KONZEPT: "ab Zyklus 6", rooms 26-30).
const DOUBLE_FROM_ROOM := 26
## Putting a relic down this close to the altar lays it on.
const ALTAR_RADIUS := 80.0
## Guards of the relic: the plan's guards; without them this many on free tiles near the relic.
const MIN_GUARDS := 2
## When the relic is first lifted, every grave breaks open: the room's roll times this factor.
const WAKE_FACTOR := 0.8  # TESTWERT
const WAKE_MIN := 3
## Share of the other enemies (guards, late arrivals) that chase the carrier instead of the nearest
## player (co-op); the enemies of the wake always chase him.
const CHASER_SHARE := 0.6  # TESTWERT
## Without the RoomController first-wave hook the room also spawns a small wave of its own.
const FALLBACK_WAVE_FACTOR := 0.4  # TESTWERT
## Light of a relic on the floor and in the hand (it shines gold through the dark).
const LIGHT_RADIUS := 120.0
const CARRIED_LIGHT_RADIUS := 170.0
## Wake pushes do not start within this distance of a player (world px).
const WAKE_MIN_PLAYER_DISTANCE := 160.0


static func relic_count(room_index: int) -> int:
	return 2 if room_index >= DOUBLE_FROM_ROOM else 1


static func bonus_open(elapsed: float) -> bool:
	return elapsed < BONUS_TIME


## Time is up: the relics still away fly home to the altar (no bonus).
static func relics_return(elapsed: float, placed: int, total: int) -> bool:
	return placed < total and elapsed >= BONUS_TIME


## The room stays shut until every relic lies on the altar.
static func holds_room(started: bool, placed: int, total: int) -> bool:
	return started and placed < total


static func can_place(distance_to_altar: float) -> bool:
	return distance_to_altar <= ALTAR_RADIUS


static func wake_size(rolled: int) -> int:
	return maxi(WAKE_MIN, roundi(rolled * WAKE_FACTOR))


## One roll per enemy: does it chase the carrier?
static func is_chaser(roll: float) -> bool:
	return roll < CHASER_SHARE


static func time_left(elapsed: float) -> float:
	return maxf(0.0, BONUS_TIME - elapsed)

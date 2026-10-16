class_name RiftRules
extends RefCounted
## Rules and numbers of "Risse schließen" (KONZEPT_RAEUME_V2 §3.7, R4b; before: Beschwörungsrisse,
## D-114). No nodes, unit-testable; RiftsMode and SummoningRift only apply them.

## Rifts of a room without wall rifts in its plan (inclusive range, one roll).
const COUNT := Vector2i(2, 3)  # TESTWERT
## Co-op (D-109, set in MP5): extra rifts per additional player.
const PER_EXTRA_PLAYER := 1  # TESTWERT
## Every open rift sends one enemy every this many seconds while fewer than MAX_ALIVE enemies live
## (design answer: "im Takt alle 6 s", fewer than six; D-154 follow-up 16.10.2026: 6 s -> 9 s and
## 6 -> 4, rift rooms were the deadliest fights in rooms 31-44).
const PUSH_INTERVAL := 9.0  # TESTWERT
const MAX_ALIVE := 4  # TESTWERT
## The first push waits a little, rifts take turns (s).
const FIRST_DELAY := 2.0
const STAGGER := 0.8
## Readable summon of a rift without a wall source: it glows and a circle marks the spot this long.
const WIND_UP := 0.7
## The room's own first wave is smaller; the rifts bring the rest (D-154 follow-up: 0.7 -> 0.6).
const FIRST_WAVE_FACTOR := 0.6  # TESTWERT
## Once the first rift is closed the floor sources (vents) join in: this many per push.
const VENT_PUSH := 1  # TESTWERT
## Rifts stand at least this many tiles apart and this far from the doors (rooms without plan rifts).
const MIN_TILE_DISTANCE := 4.0
const DOOR_CLEARANCE := 3.0
## Every rift closed within this time after the fight started: extra soul crystals ("schnell").
const FAST_TIME := 40.0  # TESTWERT
const FAST_CRYSTALS := 1  # TESTWERT


## Rifts of a room without plan rifts from one roll in [0, 1) and the number of players.
static func rift_count(roll: float, players: int) -> int:
	var span := COUNT.y - COUNT.x + 1
	var base := COUNT.x + mini(floori(roll * span), span - 1)
	return base + extra_rifts(players)


## Extra rifts for more players (co-op).
static func extra_rifts(players: int) -> int:
	return PER_EXTRA_PLAYER * (maxi(1, players) - 1)


## May a rift call another enemy? alive = living enemies of the room without the rifts.
static func can_summon(alive: int) -> bool:
	return alive < MAX_ALIVE


## Is the next push of a rift due?
static func should_push(since_push: float) -> bool:
	return since_push >= PUSH_INTERVAL


## Floor-source enemies that join a push: none until a rift is closed.
static func vent_count(closed: int) -> int:
	return VENT_PUSH if closed > 0 else 0


static func is_fast(elapsed: float) -> bool:
	return elapsed < FAST_TIME


static func fast_crystals(elapsed: float) -> int:
	return FAST_CRYSTALS if is_fast(elapsed) else 0

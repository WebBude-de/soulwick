class_name HuntRules
extends RefCounted
## Rules and numbers of "Jagd" (KONZEPT_RAEUME_V2 §3.8, R4b; before: Kopfgeld, D-114). No nodes,
## unit-testable; HuntMode and BountyFlight only apply them.

## The escape hole opens over this time after the crowned one saw a player; when it is open and he
## stands at it, he jumps in.
const CATCH_TIME := 15.0  # TESTWERT (D-114: 12 s; the hall has pillars and guards)
## He spots a player within this distance and with a free line of sight.
const SIGHT_RANGE := 320.0  # TESTWERT
## Running speed of the crowned one relative to his normal speed.
const FLEE_SPEED_FACTOR := 1.1  # TESTWERT
## Until the last RUN_TO_HOLE_TIME seconds he zigzags away from the players between the pillars
## (design answer: "flieht im Zickzack"), then he runs for the hole.
const RUN_TO_HOLE_TIME := 4.0  # TESTWERT
## He picks a new spot to run to this often.
const EVADE_REPICK := 1.2
## Spots he runs to lie at most this far from him (tiles), so he never runs through the player.
const EVADE_RANGE_TILES := 6.0
## At the hole he waits for it to open completely; the last seconds the crown blinks.
const ARRIVE_RADIUS := 20.0
const WARN_TIME := 3.0
## Duration of the jump into the hole (still catchable).
const JUMP_TIME := 0.35
## Stuck on the way (blocked by players): he jumps after this extra time anyway.
const STUCK_GRACE := 3.0
## The hole lies at least this many tiles from him and this far from every player (rooms without a
## plan hole).
const HOLE_MIN_TILES := 5.0
const HOLE_PLAYER_TILES := 3.0
## Guards of the plan; without plan guards at least this many between him and the entrance.
const MIN_GUARDS := 3
## Without the RoomController first-wave hook the room also spawns a small wave of its own.
const FALLBACK_WAVE_FACTOR := 0.4  # TESTWERT
## His loot (KONZEPT: "viel Gold, gelegentlich ein Upgrade"): his gold times this factor, and with
## UPGRADE_CHANCE a bonus chest with an upgrade choice.
const LOOT_GOLD_FACTOR := 6  # TESTWERT
const LOOT_GOLD_MIN := 20  # TESTWERT
const UPGRADE_CHANCE := 0.3  # TESTWERT
## The task bar turns red when the hole is this far open.
const DANGER_PROGRESS := 0.75


## Does an enemy at distance with or without a free line see the player?
static func sees(distance: float, free_line: bool) -> bool:
	return free_line and distance <= SIGHT_RANGE


## Opening of the escape hole (0..1) after time_fleeing seconds.
static func hole_progress(time_fleeing: float) -> float:
	return clampf(time_fleeing / CATCH_TIME, 0.0, 1.0)


## The hole is open: he jumps in as soon as he stands at it.
static func hole_open(time_fleeing: float) -> bool:
	return time_fleeing >= CATCH_TIME


## Kept from away from the hole too long (blocked): he jumps anyway.
static func forced_escape(time_fleeing: float) -> bool:
	return time_fleeing >= CATCH_TIME + STUCK_GRACE


static func warns(time_fleeing: float) -> bool:
	return time_fleeing >= CATCH_TIME - WARN_TIME


## From now on he runs straight for the hole instead of zigzagging.
static func runs_to_hole(time_fleeing: float) -> bool:
	return time_fleeing >= CATCH_TIME - RUN_TO_HOLE_TIME


## Score of a spot to run to: far from the nearest player, not too far from himself.
static func evade_score(distance_to_player: float, distance_to_self: float) -> float:
	return distance_to_player - 0.5 * distance_to_self


static func loot_gold(base_gold: int) -> int:
	return maxi(LOOT_GOLD_MIN, base_gold * LOOT_GOLD_FACTOR)


static func loot_has_upgrade(roll: float) -> bool:
	return roll < UPGRADE_CHANCE

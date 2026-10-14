class_name VariantRules
extends RefCounted
## Pure rules and numbers of the combat variants (KONZEPT_RAEUME §4, D-101, D-109): soul flame,
## summoning rifts, gravedigger (crypt) and bounty. No nodes, unit-testable. The variant nodes
## (CombatVariant and its subclasses) ask these functions and only add the effects.
## Co-op values (flame health, rift count, chests per player) are parameters prepared for MP5
## (D-109); with one player every factor is neutral.

const SOUL_FLAME := &"soul_flame"
const RIFTS := &"rifts"
const GRAVEDIGGER := &"gravedigger"
const BOUNTY := &"bounty"
## The variants of this round (A7). Later: stone_guardian, lantern, torch_room (A9), elite_nest (A10).
const ALL: Array[StringName] = [SOUL_FLAME, RIFTS, GRAVEDIGGER, BOUNTY]

# --- Soul flame (§4.1) ---

## Raid waves come for this long after the fight started; then the rest must be beaten.
const FLAME_DURATION := 40.0  # TESTWERT
## Share of the enemies that go for the flame instead of the players.
const FLAME_RAID_SHARE := 0.7  # TESTWERT
## A raid wave every this many seconds, or earlier once at most FLAME_WAVE_AT_ALIVE enemies are left.
const FLAME_WAVE_INTERVAL := 10.0  # TESTWERT
const FLAME_WAVE_AT_ALIVE := 1
## Never two raid waves closer than this (also the first one after the start).
const FLAME_WAVE_MIN_GAP := 3.0  # TESTWERT
## Size of a raid wave: the room's normal roll times this factor, at least FLAME_WAVE_MIN.
const FLAME_WAVE_FACTOR := 0.6  # TESTWERT
const FLAME_WAVE_MIN := 2
## Flame health in hits of a plain enemy: scaled with the enemy damage of the room, so the number
## of hits it takes stays the same with depth.
const FLAME_HITS := 16.0  # TESTWERT
## Co-op (D-109, set in MP5): extra flame health per additional player.
const FLAME_HEALTH_PER_EXTRA_PLAYER := 0.5  # TESTWERT
## After the flame went out the room gets darker: light circle times this factor.
const FLAME_OUT_VISION_FACTOR := 0.8  # TESTWERT
## Raid waves appear at least this far from every player and from the flame (world px).
const FLAME_SPAWN_MIN_DISTANCE := 160.0

# --- Summoning rifts (§4.2) ---

## Rifts per room (inclusive range, one roll).
const RIFT_COUNT := Vector2i(2, 3)  # TESTWERT
## Co-op (D-109, set in MP5): extra rifts per additional player.
const RIFTS_PER_EXTRA_PLAYER := 1  # TESTWERT
## Every rift calls one enemy every this many seconds while fewer than RIFT_MAX_ALIVE live.
const RIFT_SUMMON_INTERVAL := 4.0  # TESTWERT
const RIFT_MAX_ALIVE := 6  # TESTWERT
## Readable summon: the rift glows and the spot flickers this long before the enemy appears.
const RIFT_WIND_UP := 0.7
## The first wave of a rift room is smaller; the rifts bring the rest.
const RIFT_ROOM_COUNT_FACTOR := 0.7  # TESTWERT
## The first summon waits a little longer, so the room does not start with a burst.
const RIFT_FIRST_DELAY := 2.0
## Rifts stand at least this many tiles apart and this far from the entrance door.
const RIFT_MIN_TILE_DISTANCE := 4.0
const RIFT_DOOR_CLEARANCE := 3.0

# --- Gravedigger (§4.5, crypt only) ---

## A bone heap that is not destroyed within this time rises again ...
const RISE_TIME := 5.0  # TESTWERT
## ... the last part of it visibly (bone_heap_rise animation).
const RISE_ANIMATION_TIME := 1.0
## ... with this share of its health, at most once.
const RISE_HEALTH_SHARE := 0.5  # TESTWERT
## Enemy types that leave a bone heap.
const RISING_IDS: Array[StringName] = [&"skeleton"]
## A player whose feet come this close destroys the heap (walking over it or dashing through).
const STOMP_RADIUS := 30.0
## Skeletons are more frequent in a gravedigger room (weight factor in the biome table).
const RISING_WEIGHT_FACTOR := 3.0  # TESTWERT
## Bonus chest only if no skeleton rose again (false = clearing the room is enough, KONZEPT §4.5
## names no failure). Open question for the team member.
const GRAVEDIGGER_BONUS_NEEDS_NO_RISE := false  # TESTWERT

# --- Bounty (§4.6) ---

## The crowned enemy must be caught within this time after it spotted a player.
const BOUNTY_CATCH_TIME := 12.0  # TESTWERT
## It spots a player within this distance and with a free line of sight.
const BOUNTY_SIGHT_RANGE := 320.0  # TESTWERT
## Running speed of the fleeing enemy relative to its normal speed.
const BOUNTY_FLEE_SPEED_FACTOR := 1.1  # TESTWERT
## At the hole it waits for the hole to open completely; the last seconds the crown blinks.
const BOUNTY_ARRIVE_RADIUS := 20.0
const BOUNTY_WARN_TIME := 3.0
## Duration of the jump into the hole (still catchable).
const BOUNTY_JUMP_TIME := 0.35
## The hole lies at least this many tiles from the crowned enemy and this far from every player.
const BOUNTY_HOLE_MIN_TILES := 5.0
const BOUNTY_HOLE_PLAYER_TILES := 3.0

# --- Reward (D-109) ---

## Upgrade choices of the bonus chest (D-109: upgrade choice through the existing dialog).
const CHEST_UPGRADE_CHOICES := 1  # TESTWERT
## Co-op (D-109, set in MP5): one chest per player instead of one for the group.
const CHESTS_PER_PLAYER := false  # TESTWERT


static func is_known(variant_id: StringName) -> bool:
	return ALL.has(variant_id)


# --- Soul flame ---

## Maximum health of the soul flame in a room for a number of players (0.5 steps).
static func flame_health(room_index: int, players: int) -> float:
	var extra := FLAME_HEALTH_PER_EXTRA_PLAYER * (maxi(1, players) - 1)
	var health := FLAME_HITS * EnemyScaling.damage_multiplier(room_index, false) * (1.0 + extra)
	return maxf(DamageProcessor.DAMAGE_STEP, DamageProcessor.round_to_step(health))


## One roll per enemy: does it go for the flame?
static func is_raider(roll: float) -> bool:
	return roll < FLAME_RAID_SHARE


## Is a raid wave due? Only while the flame burns and the raid time runs.
static func should_send_wave(elapsed: float, since_last_wave: float, alive: int, flame_alive: bool) -> bool:
	if not flame_alive or elapsed >= FLAME_DURATION:
		return false
	if since_last_wave >= FLAME_WAVE_INTERVAL:
		return true
	return alive <= FLAME_WAVE_AT_ALIVE and since_last_wave >= FLAME_WAVE_MIN_GAP


static func flame_wave_size(rolled: int) -> int:
	return maxi(FLAME_WAVE_MIN, roundi(rolled * FLAME_WAVE_FACTOR))


## The soul flame room stays closed while the raid time runs (RoomController hook, A7).
static func flame_holds_room(elapsed: float, started: bool) -> bool:
	return started and elapsed < FLAME_DURATION


# --- Rifts ---

## Rifts of a room from one roll in [0, 1) and the number of players.
static func rift_count(roll: float, players: int) -> int:
	var span := RIFT_COUNT.y - RIFT_COUNT.x + 1
	var base := RIFT_COUNT.x + mini(floori(roll * span), span - 1)
	return base + RIFTS_PER_EXTRA_PLAYER * (maxi(1, players) - 1)


## May a rift call another enemy? alive = living enemies of the room without the rifts.
static func can_summon(alive: int) -> bool:
	return alive < RIFT_MAX_ALIVE


# --- Gravedigger ---

static func can_rise(enemy_id: StringName) -> bool:
	return RISING_IDS.has(enemy_id)


## Health of a risen skeleton (0.5 steps, at least 0.5).
static func risen_health(max_health: float) -> float:
	return maxf(DamageProcessor.DAMAGE_STEP, DamageProcessor.round_to_step(max_health * RISE_HEALTH_SHARE))


## Has the heap been lying long enough to start its rise animation / to stand up?
static func is_rising(age: float) -> bool:
	return age >= RISE_TIME - RISE_ANIMATION_TIME


static func should_rise(age: float) -> bool:
	return age >= RISE_TIME


static func is_stomped(feet_distance: float) -> bool:
	return feet_distance <= STOMP_RADIUS


# --- Bounty ---

## Does an enemy at distance with or without a free line see the player?
static func bounty_sees(distance: float, free_line: bool) -> bool:
	return free_line and distance <= BOUNTY_SIGHT_RANGE


## Opening of the escape hole (0..1) after time_fleeing seconds.
static func hole_progress(time_fleeing: float) -> float:
	return clampf(time_fleeing / BOUNTY_CATCH_TIME, 0.0, 1.0)


static func bounty_escapes(time_fleeing: float) -> bool:
	return time_fleeing >= BOUNTY_CATCH_TIME


static func bounty_warns(time_fleeing: float) -> bool:
	return time_fleeing >= BOUNTY_CATCH_TIME - BOUNTY_WARN_TIME


# --- Reward ---

static func chest_count(players: int) -> int:
	return maxi(1, players) if CHESTS_PER_PLAYER else 1

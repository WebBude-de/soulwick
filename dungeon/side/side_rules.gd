class_name SideRules
extends RefCounted
## Gang segments in side view (M5, Makeover 3 §3): every decision and every number in one place.
## A segment is a short jump'n'run between two rooms: black fade, banner "Abstieg", 20-40 s of
## running and jumping, a door, black fade, the next room from above again. The functions here only
## decide (no nodes, no sounds); SideTransit, SideSegment and PlayerSideMotion apply them.
## Randomness only through a RandomNumberGenerator the caller passes in (multiplayer rule).

## Why a way runs through a segment.
enum Reason {
	NONE,
	## After the campfire, into the next biome ("Abstieg", once per 15 rooms).
	BIOME_CHANGE,
	## The ladder door of a branch: a side way with coins and a chest instead of a fight.
	LADDER_WAY,
	## Now and then after a rest room, as a surprise.
	AFTER_REST,
}

const TILE := 64.0
## Height of every segment in tiles (one screen high at zoom 1, no vertical scrolling in V1).
const ROWS := 11

# --- Platform physics (TESTWERTE, world px; sprites are drawn ×2, one tile = 64 px) ---
## Gravity while rising; falling uses FALL_GRAVITY_FACTOR on top (snappier landings).
const GRAVITY := 1800.0
const FALL_GRAVITY_FACTOR := 1.4
## Jump height 2.5 tiles: v = sqrt(2 * GRAVITY * 2.5 * TILE) = 759 px/s.
const JUMP_HEIGHT_TILES := 2.5
const JUMP_VELOCITY := 759.0
## Releasing the jump button while rising cuts the upward speed (variable jump height).
const JUMP_CUT_FACTOR := 0.45
const COYOTE_TIME := 0.1
const JUMP_BUFFER_TIME := 0.12
const MAX_FALL_SPEED := 1100.0
## Running speed = the player's move_speed (with all its modifiers) times this factor.
const RUN_SPEED_FACTOR := 1.3
const GROUND_ACCELERATION := 2400.0
const AIR_ACCELERATION := 1600.0
const CLIMB_SPEED := 170.0
## How close (px) the body centre must be to a ladder's middle to grab it.
const LADDER_GRAB_DISTANCE := 24.0

# --- Pits (TESTWERTE) ---
## Falling out of the segment costs half a heart past the shield, never the last 0.5 HP (no death
## by falling in a side segment, Makeover 3 §3 "Risiken").
const PIT_DAMAGE := 1.0
const PIT_MIN_HEALTH_LEFT := 0.5
## How long the player is gone before landing on the last platform.
const PIT_RETURN_TIME := 0.45

# --- Rewards (TESTWERTE, Makeover 3 §3 "Vorschlag Gameplay") ---
## Gold per coin before the side-way factor (one coin = one enemy's gold drop at the start).
const COIN_GOLD := 1.0
## Coins count as run gold ×1.5 because there is (almost) no fight.
const COIN_GOLD_FACTOR := 1.5
## The golden coin at the hardest spot.
const GOLDEN_COIN_CRYSTALS := 1

# --- Where segments sit (TESTWERTE) ---
const AFTER_REST_CHANCE := 0.1
## The jump hint ("Springen: Leertaste") on the first few segments of a save.
const JUMP_HINT_TIMES := 3
## Save statistic counting the segments entered (SaveManager.add_stat).
const STAT_SEGMENTS := &"side_segments"
## Option key for "Seitenwege auslassen" (R8 owns the options menu; false = segments on).
const OPTION_SKIP := &"skip_side_paths"

# --- Transition (TESTWERTE) ---
const FADE_TIME := 0.3
const BANNER_TIME := 1.3
const BANNER_TIME_WITH_HINT := 2.2
## Co-op: a player outside the view this long is brought to the foremost player.
const CATCH_UP_TIME := 3.0
## Segments must never take longer than this (checked by the side check tool).
const MAX_SEGMENT_SECONDS := 45.0

# --- Sounds: delivered names first, existing fallbacks second (R9 may add the first ones) ---
const SOUND_DRONE := &"side_drone"
const SOUND_DRONE_FALLBACK := &"intro_door"
const SOUND_JUMP := &"side_jump"
const SOUND_JUMP_FALLBACK := &"dash"
const SOUND_LAND := &"side_land"
const SOUND_LAND_FALLBACK := &"slime_land"
const SOUND_COIN := &"coin"
const SOUND_GOLDEN_COIN := &"soul_collect"
const SOUND_DOOR := &"door_open"


## Decides whether the way into the next room runs through a segment. Draws at most one number
## (only after a rest room), so the caller's RNG stream stays predictable.
## after_campfire: the room the group leaves is the campfire between two biomes.
## ladder_way: the group took the ladder door of a branch.
## after_rest: the room the group leaves is a rest room (shop, weapons, fountain, altar).
## next_is_boss: the next room is a boss room. previous_was_side: the last way was a segment.
## skip: the player switched side ways off (OPTION_SKIP).
static func roll_reason(after_campfire: bool, ladder_way: bool, after_rest: bool, next_is_boss: bool,
		previous_was_side: bool, skip: bool, rng: RandomNumberGenerator) -> Reason:
	if skip or next_is_boss or previous_was_side:
		return Reason.NONE
	if after_campfire:
		return Reason.BIOME_CHANGE
	if ladder_way:
		return Reason.LADDER_WAY
	if after_rest and rng != null and rng.randf() < AFTER_REST_CHANCE:
		return Reason.AFTER_REST
	return Reason.NONE


## Whether a branch may show a ladder door at all (same limits as roll_reason, no draw).
static func allows_ladder_way(next_is_boss: bool, previous_was_side: bool, skip: bool) -> bool:
	return not skip and not next_is_boss and not previous_was_side


## A segment's own RNG, derived from the run seed and the slot it sits in front of: the dungeon
## stream stays untouched and every co-op peer builds the same segment.
static func make_rng(run_seed: int, slot: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, slot, "side_segment"])
	return rng


## Gold for coin number index (0-based) of a segment: the running total of index + 1 coins minus
## the total of index coins, so fractions carry over and n coins pay floor(n × 1.5 × multiplier).
static func coin_gold(index: int, gold_multiplier := 1.0) -> int:
	return _coin_total(index + 1, gold_multiplier) - _coin_total(index, gold_multiplier)


static func _coin_total(count: int, gold_multiplier: float) -> int:
	return floori(count * COIN_GOLD * COIN_GOLD_FACTOR * maxf(0.0, gold_multiplier) + 0.0001)


## Damage of a fall out of the segment: half a heart, never below PIT_MIN_HEALTH_LEFT.
static func pit_damage(health: float) -> float:
	var allowed := maxf(0.0, health - PIT_MIN_HEALTH_LEFT)
	return DamageProcessor.DAMAGE_STEP * floorf(minf(PIT_DAMAGE, allowed) / DamageProcessor.DAMAGE_STEP)


## Show "Springen: Leertaste" when the save has seen fewer than JUMP_HINT_TIMES segments.
static func shows_jump_hint(segments_seen: int) -> bool:
	return segments_seen < JUMP_HINT_TIMES


## Jump speed for a height in px under GRAVITY (tests and tools).
static func jump_velocity_for(height: float) -> float:
	return sqrt(2.0 * GRAVITY * height)


## Highest point of a full jump in px.
static func jump_height() -> float:
	return JUMP_VELOCITY * JUMP_VELOCITY / (2.0 * GRAVITY)


## The sound to play: the delivered one, else the fallback.
static func sound_or(sound: StringName, fallback: StringName) -> StringName:
	return sound if ResourceLoader.exists(Sfx.SFX_DIR + String(sound) + ".wav") else fallback

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
# Round 2 (15.10.2026): snappier jump (higher gravity, faster take-off), a short hang at the apex,
# faster falling, a double jump, wall slide and wall jump. The single jump still reaches 2.5 tiles,
# so every plan rule for a plain jump stays; the double jump adds 2 tiles on top.
## Gravity while rising; falling uses FALL_GRAVITY_FACTOR on top.
const GRAVITY := 2400.0
const FALL_GRAVITY_FACTOR := 1.6
## Apex hang: while the vertical speed is below APEX_SPEED, gravity is scaled by this factor.
const APEX_SPEED := 90.0
const APEX_GRAVITY_FACTOR := 0.45
## Jump height 2.5 tiles: v = sqrt(2 * GRAVITY * 2.5 * TILE) = 876 px/s.
const JUMP_HEIGHT_TILES := 2.5
const JUMP_VELOCITY := 876.0
## Double jump: one more jump in the air, 2 tiles high: sqrt(2 * GRAVITY * 2 * TILE) = 784 px/s.
const AIR_JUMPS := 1
const DOUBLE_JUMP_HEIGHT_TILES := 2.0
const DOUBLE_JUMP_VELOCITY := 784.0
## Releasing the jump button while rising cuts the upward speed (variable jump height).
const JUMP_CUT_FACTOR := 0.4
const COYOTE_TIME := 0.1
const JUMP_BUFFER_TIME := 0.12
const MAX_FALL_SPEED := 1250.0
## Running speed = the player's move_speed (with all its modifiers) times this factor.
const RUN_SPEED_FACTOR := 1.3
const GROUND_ACCELERATION := 3000.0
const AIR_ACCELERATION := 2000.0
## Wall slide: falling while pressing against a rock wall is capped at this speed; a jump from
## the wall pushes away (x) and up (y), the stick is ignored for WALL_JUMP_LOCK seconds. Touching a
## wall gives the double jump back.
const WALL_SLIDE_SPEED := 170.0
const WALL_JUMP_VELOCITY := Vector2(330.0, 800.0)
const WALL_JUMP_LOCK := 0.14
const CLIMB_SPEED := 170.0
## How close (px) the body centre must be to a ladder's middle to grab it.
const LADDER_GRAB_DISTANCE := 24.0
## Landings faster than this are hard: louder, more dust, a camera kick.
const HARD_LANDING_SPEED := 900.0

# --- Crumbling ledges (plan "~", TESTWERTE) ---
## A crumbling ledge shakes this long after a player stands on it, then falls; it is back after
## CRUMBLE_RESPAWN seconds (when nobody is in the way).
const CRUMBLE_DELAY := 0.6
const CRUMBLE_RESPAWN := 3.0

# --- Pits (decision of the team member, 15.10.2026) ---
## Falling out of the segment costs what an abyss in a room costs (D-115: a whole heart past the
## shield, may kill, ChasmRules.fall_damage), then back on the last platform.
## How long the player is gone before landing on the last platform.
const PIT_RETURN_TIME := 0.45

# --- Rewards (TESTWERTE, delegated 15.10.2026: "worth about a normal combat room, not more") ---
## A normal combat room pays about 1 gold per enemy (gold_drop × 0.4, at least 1) for 2-6 enemies,
## plus 1-2 from crates: 4-8 gold in rooms 1-29, ×2 waves from room 30, ×3 from room 60. A segment
## pays 6-7 coins + the golden coin (2 coins) = 8-9 coin values, scaled by the same wave count, and
## its enemies drop nothing (they are obstacles here). No crystals, no hearts; the chest (an upgrade
## choice) only on the ladder way of a branch, where it stands against the elite nest or a variant.
const COIN_GOLD := 1
const GOLDEN_COIN_COINS := 2
## Side enemies drop no gold (the coins are the reward).
const ENEMY_GOLD := 0

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
const SOUND_DOUBLE_JUMP := &"side_double_jump"
const SOUND_LAND := &"side_land"
const SOUND_LAND_FALLBACK := &"slime_land"
const SOUND_LAND_HARD := &"side_land_hard"
const SOUND_WALL_SLIDE := &"side_wall_slide"
const SOUND_CRUMBLE := &"side_crumble"
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


## Gold of one coin in room room_index: COIN_GOLD × the room's wave count (rooms pay more deeper
## down the same way), × the village gold multiplier, rounded, at least 1.
static func coin_gold(room_index: int, gold_multiplier := 1.0) -> int:
	return maxi(1, roundi(COIN_GOLD * RoomSequence.get_wave_count(room_index) * maxf(0.0, gold_multiplier)))


## Gold of the golden coin (the hardest spot, needs the double jump).
static func golden_coin_gold(room_index: int, gold_multiplier := 1.0) -> int:
	return coin_gold(room_index, gold_multiplier) * GOLDEN_COIN_COINS


## Everything a segment can pay in gold: all coins and the golden coin (tools, balance).
static func segment_gold(coins: int, room_index: int, gold_multiplier := 1.0) -> int:
	return coins * coin_gold(room_index, gold_multiplier) + golden_coin_gold(room_index, gold_multiplier)


## Damage of a fall out of the segment: the same as an abyss in a room (may kill).
static func pit_damage() -> float:
	return ChasmRules.fall_damage()


## Whether the chest in a plan's niche is set up: only on the ladder way of a branch.
static func has_chest(reason: Reason) -> bool:
	return reason == Reason.LADDER_WAY


## Show "Springen: Leertaste" when the save has seen fewer than JUMP_HINT_TIMES segments.
static func shows_jump_hint(segments_seen: int) -> bool:
	return segments_seen < JUMP_HINT_TIMES


## Highest point of a double jump taken at the apex of the first, in px.
static func double_jump_height() -> float:
	return jump_height() + DOUBLE_JUMP_VELOCITY * DOUBLE_JUMP_VELOCITY / (2.0 * GRAVITY)


## Jump speed for a height in px under GRAVITY (tests and tools).
static func jump_velocity_for(height: float) -> float:
	return sqrt(2.0 * GRAVITY * height)


## Highest point of a full jump in px.
static func jump_height() -> float:
	return JUMP_VELOCITY * JUMP_VELOCITY / (2.0 * GRAVITY)


## The sound to play: the delivered one, else the fallback.
static func sound_or(sound: StringName, fallback: StringName) -> StringName:
	return sound if ResourceLoader.exists(Sfx.SFX_DIR + String(sound) + ".wav") else fallback

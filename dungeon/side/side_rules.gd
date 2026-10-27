class_name SideRules
extends RefCounted
## Side view between two rooms (M5, D-144): every decision and every number in one place. Since
## D-216 every such section is an obstacle run (Hindernislauf): black fade, banner, a small
## jump'n'run level of about a minute (ObstacleRunPlans: opening, two ways, hard part, lantern,
## final jump), a door, black fade, the next room from above again. The functions here only decide
## (no nodes, no sounds); SideTransit, SideSegment and PlayerSideMotion apply them.
## Randomness only through a RandomNumberGenerator the caller passes in (multiplayer rule).
## The way rule (roll_reason) decides where a run sits: on the way into every champion room, behind
## the campfire and on the ladder way (D-216, Nachtrag 26.10.2026).

## Why a way runs through an obstacle run.
enum Reason {
	NONE,
	## After the campfire, into the next biome ("Abstieg", once per 15 rooms).
	BIOME_CHANGE,
	## The ladder door of a branch: a side way with coins and a chest instead of a fight.
	LADDER_WAY,
	## Now and then after a rest room, as a surprise (rounds 1-3; since SV3 the share rule, SHARE).
	AFTER_REST,
	## The way into a champion room (miniboss, place 5 of a cycle; D-216, Nachtrag 26.10.2026). The
	## name stays from the former share rule (about every fourth way at random): the number travels
	## (NetSide) and the smoke test reads it by name.
	SHARE,
}

const TILE := 64.0
## Height of a plan in tiles: ROWS for the plans of rounds 1-3, tall jump trials (SV2, D-195) up to
## MAX_ROWS; the camera scrolls vertically and looks ahead along the way (SideCamera).
const ROWS := 11
const MAX_ROWS := 22

# --- Tiers (SV2, D-195, kept by D-216, TESTWERTE) ---
## Tier 1 up to room TIER_2_FROM_ROOM - 1, tier 2 up to TIER_3_FROM_ROOM - 1, tier 3 from there on or
## from danger level TIER_3_FROM_DANGER (KE2). A tier-t run draws from the biome's runs of tier t
## and the one before (ObstacleRunPlans.pick), so the elements met before stay in the mix.
const TIER_2_FROM_ROOM := 16
const TIER_3_FROM_ROOM := 46
const TIER_3_FROM_DANGER := 6
const MAX_TIER := 3

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

# --- Round 3 (16.10.2026): towers, pools, spike rhythm (TESTWERTE) ---
## Share of runs whose plan mounts its turret(s) ("T"); one draw per run (ObstacleRunPlans.pick).
const TURRET_CHANCE := 0.5
## A turret mount keeps at least this many columns away from the start and the door.
const TURRET_MIN_DISTANCE := 6
## Side turret: sight in tiles, telegraph (the eye lights up) and pause between shots in seconds,
## shot speed (slow, px/s). Depth scales telegraph and cadence like every enemy (TurretRules).
## Damage and the slow come from the biome's turret data and TurretRules (as in the rooms); a hit
## never blocks the jump.
const TURRET_SIGHT_TILES := 8.0
const TURRET_CHARGE_TIME := 0.8
const TURRET_COOLDOWN := 2.4
const TURRET_FIRST_DELAY := 1.2
const TURRET_SHOT_SPEED := 160.0
const TURRET_HEALTH_FACTOR := 1.0
## Water / slime pools ("w"): running speed while the feet are in it (jumping stays the same).
const POOL_SLOW_FACTOR := 0.6
## Out of a pool a plain jump reaches only this far (columns), the double jump POOL_REACH_DOUBLE.
const POOL_REACH := 1
const POOL_REACH_DOUBLE := 3
## Spike runs ("^^^") fire as a wave: each trap of a run this much later than its neighbour.
const SPIKE_WAVE_STEP := 0.3

# --- Pits (decision of the team member, 15.10.2026) ---
## Falling out of the segment costs what an abyss in a room costs (D-115: a whole heart past the
## shield, may kill, ChasmRules.fall_damage), then back on the last platform.
## How long the player is gone before landing on the last platform.
const PIT_RETURN_TIME := 0.45

# --- Rewards (TESTWERTE, delegated 15.10.2026: "worth about a normal combat room, not more") ---
## A normal combat room pays about 1 gold per enemy (gold_drop × 0.4, at least 1) for 2-6 enemies,
## plus 1-2 from crates: 4-8 gold in rooms 1-29, ×2 waves from room 30, ×3 from room 60. An obstacle
## run (D-216) keeps every RUN_COIN_KEEP_EVERY-th coin of its pieces: about 7 on the lower ways + the
## golden coin (2 coins) = about 9 coin values, the upper way of its two-way piece 2-3 more, scaled
## by the same wave count; its enemies drop nothing (they are obstacles here). No crystals, no
## hearts; the chest (an upgrade choice) only on the ladder way of a branch, where it stands against
## the elite nest or a variant.
const COIN_GOLD := 1
const GOLDEN_COIN_COINS := 2
## Side enemies drop no gold (the coins are the reward).
const ENEMY_GOLD := 0
## An obstacle run keeps every this-many-th coin of its pieces (in way order, ObstacleRunPlans).
const RUN_COIN_KEEP_EVERY := 3

# --- Where obstacle runs sit (way rule, D-216, TESTWERTE) ---
## Project member 26.10.2026 ("Vor jedem Champion"): no random ways any more. The way into every
## champion room (miniboss, place 5 of a cycle: rooms 5, 10, 20, 25, ...) always runs through an
## obstacle run (Reason.SHARE), the way behind the campfire too ("Abstieg", BIOME_CHANGE) and the
## ladder way of a branch (its chest, LADDER_WAY); every other way is a plain corridor. Never into
## the boss room or out of it, never twice in a row (D-144), never with "Seitenwege auslassen". The
## champion way never meets a ladder way: the room before a champion is the special room (place 4),
## which never branches, and the way into it never runs through a run either.
## SHARE_TARGET is the expected share of all ways (2 champion ways + 1 campfire way of 16 ways per
## biome, plus the ladder ways taken); measured in tests/unit/test_side_ways.gd and the smoke log.
const SHARE_TARGET := 0.19
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
## How long the bot (side check) needs for an obstacle run: about a minute (D-216, TESTWERT).
const RUN_SECONDS_RANGE := Vector2(45.0, 75.0)
## A piece played alone (side check pieces=1) stays under this (TESTWERT).
const MAX_PIECE_SECONDS := 40.0

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


## Decides whether the way into the next room runs through an obstacle run (way rule). Draws
## nothing: every machine answers the same from the rooms alone.
## after_campfire: the room the group leaves is the campfire between two biomes.
## ladder_way: the group took the ladder door of a branch.
## from_boss: the room the group leaves is a boss room (its way leads to the campfire).
## next_is_boss: the next room is a boss room. previous_was_side: the last way was a run.
## skip: the player switched side ways off (OPTION_SKIP). next_is_champion: the next room is a
## champion room (RoomType.MINIBOSS).
static func roll_reason(after_campfire: bool, ladder_way: bool, from_boss: bool, next_is_boss: bool,
		previous_was_side: bool, skip: bool, next_is_champion := false) -> Reason:
	if skip or next_is_boss or previous_was_side:
		return Reason.NONE
	if after_campfire:
		return Reason.BIOME_CHANGE
	if ladder_way:
		return Reason.LADDER_WAY
	if next_is_champion and not from_boss:
		return Reason.SHARE
	return Reason.NONE


## Whether a room may branch with a ladder way (BranchRules: a normal combat room from FROM_ROOM on
## before another normal combat room). Static, no draw: asked before the branch is rolled.
static func may_offer_ladder(room_index: int, room_type: RoomSequence.RoomType, next_slot_type: RoomSequence.RoomType) -> bool:
	return room_index >= BranchRules.FROM_ROOM and RoomSequence.is_normal_combat(room_type) \
			and RoomSequence.is_normal_combat(next_slot_type)


## Whether a branch may show a ladder door at all (same limits as roll_reason).
static func allows_ladder_way(next_is_boss: bool, previous_was_side: bool, skip: bool) -> bool:
	return not skip and not next_is_boss and not previous_was_side


## A run's own RNG, derived from the run seed and the slot it sits in front of: the dungeon
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


## Tier of an obstacle run (D-195, D-216) in front of room room_index at a danger level: 1 for
## rooms 1-15, 2 for rooms 16-45, 3 from room 46 or from danger level TIER_3_FROM_DANGER.
static func tier_for(room_index: int, danger := 0) -> int:
	if room_index >= TIER_3_FROM_ROOM or danger >= TIER_3_FROM_DANGER:
		return 3
	if room_index >= TIER_2_FROM_ROOM:
		return 2
	return 1


## The longest a bot may need for a layout (side check, smoke test): a run RUN_SECONDS_RANGE.y,
## a piece played alone MAX_PIECE_SECONDS.
static func max_seconds_for(layout: SideLayout) -> float:
	return RUN_SECONDS_RANGE.y if layout.is_obstacle_run() else MAX_PIECE_SECONDS


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
